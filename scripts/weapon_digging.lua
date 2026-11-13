local world = require("scripts.world")
local M = {}
local dig_handler
local damage_marks = {} -- Lethal damage and death resolve in the same tick.
local STORAGE_KEY = "the_cave_weapon_digging"
local ATOMIC = { ["atomic-rocket"] = true, ["atomic-bomb-wave"] = true,
    ["atomic-bomb-ground-zero-projectile"] = true }
local WAVES = {"atomic-bomb-wave", "atomic-bomb-ground-zero-projectile"}
local BLAST_RADIUS = 45 -- Native targets: radius 35, damage radius 3; bounded halo.
local DIGS_PER_TICK = 8

local function state()
    storage[STORAGE_KEY] = storage[STORAGE_KEY] or {surfaces = {}}
    return storage[STORAGE_KEY]
end

local function team(force)
    return force and force.valid and force.name ~= "neutral" and force.name ~= "enemy"
end

local function context(event, atomic_hit)
    local cause, source = event.cause or event.cause_entity, event.source or event.source_entity
    local force = event.force
    if not team(force) and cause and cause.valid then force = cause.force end
    if not team(force) and source and source.valid then force = source.force end
    if not team(force) then return nil end
    local kind
    if atomic_hit then kind = "atomic"
    elseif source and source.valid and ATOMIC[source.name] then kind = "atomic"
    elseif cause and cause.valid and ATOMIC[cause.name] then kind = "atomic"
    elseif cause and cause.valid and cause.name == "tank" then kind = "tank"
    elseif source and source.valid and source.name == "tank" then kind = "tank" end
    if not kind then return nil end
    local player
    if cause and cause.valid and cause.type == "character" then player = cause.player end
    if kind == "tank" and cause and cause.valid and cause.name == "tank" then
        local driver = cause.get_driver()
        if driver and driver.valid then
            if driver.object_name == "LuaPlayer" then player = driver
            elseif driver.type == "character" then player = driver.player end
        end
    end
    return {kind = kind, force = force, player_index = player and player.index}
end

local function entity_key(entity)
    return entity.unit_number or (entity.surface.index .. ":" .. math.floor(entity.position.x)
        .. ":" .. math.floor(entity.position.y))
end

function M.configure(api) dig_handler = api.on_dig end
function M.on_init() storage[STORAGE_KEY] = {surfaces = {}} end

function M.on_entity_damaged(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.name == "diggy-rock") then return end
    local key = entity_key(entity)
    local previous = damage_marks[key]
    damage_marks[key] = nil
    if event.final_health and event.final_health <= 0 then
        local mark = context(event)
        if not mark and previous and previous.tick == event.tick and previous.pre_damage then
            mark = context(event, true)
            if not mark then mark = previous end
        end
        if mark then mark.tick = event.tick; damage_marks[key] = mark end
    end
end

function M.death_context(event)
    if event.name ~= defines.events.on_entity_died then return nil end
    local entity = event.entity
    if not (entity and entity.valid and entity.name == "diggy-rock") then return nil end
    local key = entity_key(entity)
    local mark = damage_marks[key]
    damage_marks[key] = nil
    if mark and mark.tick == event.tick then
        if not team(mark.force) and team(event.force) then mark.force = event.force end
        if team(mark.force) then return mark end
    end
    return context(event)
end

local function surface_state(index)
    local root = state()
    root.surfaces[index] = root.surfaces[index] or {blasts = {}, pending = {}, seen = {}, next = 1}
    return root.surfaces[index]
end

function M.on_script_trigger_effect(event)
    local surface = game.surfaces[event.surface_index]
    if not (surface and surface.valid) then return end
    local position = event.target_position or event.source_position
    if not position then return end
    if event.effect_id == "the-cave-atomic-rock-hit" then
        local entity = event.target_entity
        if entity and entity.valid and entity.name == "diggy-rock" then
            local mark = context(event, true) or {kind = "atomic"}
            mark.tick, mark.pre_damage = event.tick, true
            damage_marks[entity_key(entity)] = mark
        end
        return
    end
    if event.effect_id:match("^the%-cave%-atomic%-terrain%-%d+$") then
        if not world.is_cave_world_surface(surface) then
            surface.create_entity {name = event.effect_id, position = position}
        end
        return
    end
    if event.effect_id ~= "the-cave-atomic-blast-start" then return end
    local group = surface_state(surface.index)
    group.blasts[#group.blasts + 1] = {x = position.x, y = position.y, tick = event.tick}
    group.last_check = nil
    group.ready = false
end

function M.enqueue(dig)
    local group = surface_state(dig.surface.index)
    local key = math.floor(dig.position.x) .. ":" .. math.floor(dig.position.y)
    if group.seen[key] then return end
    group.seen[key] = true
    group.pending[#group.pending + 1] = {position = {x = dig.position.x, y = dig.position.y},
        force_index = dig.force.index, player_index = dig.player_index, name = dig.name}
    if #group.blasts == 0 then
        -- A verified atomic damage source still works if another mod replaced
        -- the impact action. Wait for actual local wave projectiles to leave.
        group.blasts[1] = {x = dig.position.x, y = dig.position.y, tick = game.tick}
        group.ready = false
        group.last_check = nil
    end
end

local function blast_finished(surface, blast, tick)
    if tick <= blast.tick then return false end
    return surface.count_entities_filtered {name = WAVES, type = "projectile", limit = 1,
        area = {{blast.x - BLAST_RADIUS, blast.y - BLAST_RADIUS},
            {blast.x + BLAST_RADIUS, blast.y + BLAST_RADIUS}}} == 0
end

function M.on_tick(event)
    damage_marks = {}
    local root = storage[STORAGE_KEY]
    if not root then return end
    local remaining = DIGS_PER_TICK
    for surface_index, group in pairs(root.surfaces) do
        local surface = game.surfaces[surface_index]
        if not (surface and surface.valid) then root.surfaces[surface_index] = nil
        else
            if not group.ready and (not group.last_check or event.tick - group.last_check >= 15) then
                group.last_check = event.tick
                local all_finished = true
                for _, blast in ipairs(group.blasts) do
                    if not blast_finished(surface, blast, event.tick) then all_finished = false; break end
                end
                group.ready = all_finished
            end
            while group.ready and remaining > 0 and group.next <= #group.pending do
                local pending = group.pending[group.next]
                group.next = group.next + 1
                remaining = remaining - 1
                local force = game.forces[pending.force_index]
                if team(force) then
                    assert(dig_handler, "The Cave: weapon Dig callback is not configured")
                    local player = pending.player_index and game.get_player(pending.player_index)
                    dig_handler {surface = surface, position = pending.position, name = pending.name,
                        force = force, player_index = player and player.valid and player.index or nil,
                        allow_dig_outcomes = true, allow_hostile_spawns = true,
                        allow_room_generation = true, is_atomic_dig = true}
                end
            end
            if group.ready and group.next > #group.pending then root.surfaces[surface_index] = nil end
        end
    end
end

function M.on_surface_deleted(event)
    local root = storage[STORAGE_KEY]
    if root then root.surfaces[event.surface_index] = nil end
end

return M
