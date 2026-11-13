-- Persistent chunk reservations for the timed Advancing Collapse garrison.
-- No surface scans: ten groups, three homes each, and a bounded 80-cell search.
local clearing = require("scripts.advancing_clearing")
local hash = require("scripts.lib.hash")
local groups = { COUNT = 10, SIZE = 3, INTERVAL = 4 * 60 * 60,
    REBUILD_DELAY = 2 * 60 * 60 }
local STREAM = 81440

local function valid(entity) return entity and entity.valid end

local function home_in_area(surface_state, home)
    if not home then return false end
    local left, right, top, bottom = clearing.bounds(surface_state)
    return home.x * 32 < right and (home.x + 1) * 32 > left
        and home.y * 32 >= top and (home.y + 1) * 32 <= bottom
end

function groups.home_bounds(home)
    return math.max(-clearing.WIDTH / 2, home.x * 32),
        math.min(clearing.WIDTH / 2, (home.x + 1) * 32), home.y * 32, (home.y + 1) * 32
end

local function home_key(home) return home.x .. ":" .. home.y end

local function create_cycle(state, surface_state, tick)
    local seed = tonumber(surface_state.assault_seed) or 0
    local _, _, top = clearing.bounds(surface_state)
    local plots = {}
    -- Two rows of five 2x2 plots. A spare chunk separates neighbouring groups.
    for row = 0, 3, 3 do
        for column = 0, 12, 3 do plots[#plots + 1] = {x=column-8, y=top/32+row} end
    end
    for i = #plots, 2, -1 do
        local j = hash.range(seed, state.wave_number, i, STREAM, 1, i)
        plots[i], plots[j] = plots[j], plots[i]
    end
    local cycle = {start_tick=tick, groups={}, unlocked=0, wave=state.wave_number}
    for id = 1, groups.COUNT do
        local plot = plots[id]
        local missing = hash.range(seed, state.wave_number, id, STREAM+1, 1, 4)
        local group = {id=id, slots={}}
        for corner = 1, 4 do
            if corner ~= missing then
                local index = #group.slots + 1
                group.slots[index] = {index=index, group=id, family=((id-1)*3+index-1)%4+1,
                    home={x=plot.x+(corner-1)%2, y=plot.y+math.floor((corner-1)/2)},
                    next_build_tick=tick}
            end
        end
        cycle.groups[id] = group
    end
    state.nest_cycle = cycle
    return cycle
end

function groups.start_cycle(state, surface_state, tick)
    return create_cycle(state, surface_state, tick)
end

function groups.ensure(state, surface_state, tick)
    if state.break_until_tick then state.nest_restart_pending=true;return nil end
    if state.nest_restart_pending then return nil end
    if state.nest_cycle then return state.nest_cycle end
    if state.wave_number <= 0 or state.break_until_tick then return nil end
    -- Migrate the current combat clock, never start the round again on update.
    local elapsed_waves = (state.wave_number - 1) % 20
    local start = (tonumber(state.last_wave_tick) or tick) - elapsed_waves * 2 * 60 * 60
    local cycle = create_cycle(state, surface_state, start)
    local ids = {}
    for id, record in pairs(state.nests) do
        if type(record)=="table" and valid(record.entity) then ids[#ids+1]=id end
    end
    table.sort(ids)
    for index, id in ipairs(ids) do
        if index > groups.COUNT * groups.SIZE then break end
        local slot = cycle.groups[math.floor((index-1)/3)+1].slots[(index-1)%3+1]
        local record = state.nests[id]
        slot.entity_id, slot.entity = id, record.entity
        slot.family = record.family or slot.family
        slot.legacy_move = true -- bounded relocation preserves health, quality and IDs
        record.group, record.slot = slot.group, slot.index
    end
    return cycle
end

function groups.clear(state)
    state.nest_cycle = nil
    state.nest_restart_pending = true
end

function groups.mark_missing(state, record, tick, entity_id)
    if type(record)~="table" then return end
    local cycle = state.nest_cycle
    local group = cycle and record and cycle.groups[record.group]
    local slot = group and group.slots[record.slot]
    if not slot or slot.entity_id ~= entity_id then return end
    slot.entity, slot.entity_id, slot.legacy_move = nil, nil, nil
    slot.next_build_tick = tick + groups.REBUILD_DELAY
end

local function reservations(cycle, surface_state)
    local result = {}
    for _, group in ipairs(cycle.groups) do
        for _, slot in ipairs(group.slots) do
            -- Keep a live nest's real chunk reserved through the short gap
            -- between the aligned boundary and the consuming physical front.
            if slot.home and not home_in_area(surface_state, slot.home)
                and (not valid(slot.entity) or slot.legacy_move) then slot.home = nil end
            if slot.home then result[home_key(slot.home)] = slot.group end
        end
    end
    return result
end

local function available(home, id, reserved)
    for dy = -1, 1 do
        for dx = -1, 1 do
            local owner = reserved[home_key{x=home.x+dx,y=home.y+dy}]
            if owner and (owner ~= id or (dx == 0 and dy == 0)) then return false end
        end
    end
    return true
end

local function reserve_home(surface_state, slot, reserved)
    if slot.home then return true end
    local _, _, top = clearing.bounds(surface_state)
    for offset = 0, clearing.CELL_COUNT-1 do
        local cell = ((slot.group*17+slot.index*7+offset-1)%clearing.CELL_COUNT)+1
        local home={x=(cell-1)%clearing.COLUMNS-8,
            y=top/32+math.floor((cell-1)/clearing.COLUMNS)}
        if available(home,slot.group,reserved) then
            slot.home=home; reserved[home_key(home)]=slot.group
            return true
        end
    end
    return false -- retain the slot and retry; never crowd another group's chunks
end

local function position_for(surface, surface_state, slot, name, callbacks)
    local left,right,top,bottom=groups.home_bounds(slot.home)
    local center={x=(left+right)/2,y=(top+bottom)/2}
    for attempt=1,6 do
        local anchor={x=center.x+(attempt%3-1)*3,y=center.y+(math.floor((attempt-1)/3)*2-1)*3}
        local p=surface.find_non_colliding_position(name,anchor,4,0.5,true)
        if p and p.x>=left+5 and p.x<right-5 and p.y>=top+5 and p.y<bottom-5
            and callbacks.valid_position(name,p) then return {x=p.x,y=p.y} end
    end
end

function groups.populate(surface, surface_state, state, tick, limit, callbacks, queen_id)
    local cycle=groups.ensure(state,surface_state,tick)
    if not cycle then return 0 end
    cycle.unlocked=math.max(cycle.unlocked,math.min(groups.COUNT,
        1+math.floor(math.max(0,tick-cycle.start_tick)/groups.INTERVAL)))
    local reserved=reservations(cycle,surface_state)
    local created,work=0,0
    for id,group in ipairs(cycle.groups) do
        for _,slot in ipairs(group.slots) do
            if work>=limit then return created end
            if slot.legacy_move and valid(slot.entity) and tick >= (slot.next_move_tick or 0) then
                work=work+1
                slot.next_move_tick=tick+5*60
                if reserve_home(surface_state,slot,reserved) then
                    local name=slot.entity.name
                    local p=position_for(surface,surface_state,slot,name,callbacks)
                    if p and slot.entity.teleport(p) then
                        slot.legacy_move=nil
                    end
                end
            elseif id<=cycle.unlocked and not valid(slot.entity)
                and tick>=(slot.next_build_tick or cycle.start_tick) then
                work=work+1
                if reserve_home(surface_state,slot,reserved) then
                    local name=callbacks.nest_name(slot.family)
                    if name then
                        local p=position_for(surface,surface_state,slot,name,callbacks)
                        local record=p and callbacks.create(name,p,slot,queen_id)
                        if record then
                            slot.entity,slot.entity_id=record.entity,record.entity.unit_number
                            slot.next_build_tick=nil
                            created=created+1
                        end
                    end
                end
                -- Bound failed placement too, with per-slot retry backoff.
                if not valid(slot.entity) then slot.next_build_tick=tick+5*60 end
            end
        end
    end
    return created
end

return groups
