local cave_teams = require("scripts.cave_teams")
local physical = require("scripts.player_physical")
-- One-direction enemy assault for Advancing Collapse.
--
-- A timed combat/recovery schedule prevents a player from freezing progression by
-- keeping one attacker alive.  Every wave is staged on valid Cave floor north
-- of the moving collapse, while surviving attackers and nests remain active.
-- Private Train Wave unit prototypes keep these units out of ordinary Cave
-- expansion and Queen ownership; private nest prototypes keep nest ecology
-- independent as well.
local hash = require("scripts.lib.hash")
local cave_evolution = require("scripts.cave_evolution")
local zones = require("scripts.advancing_zones")
local clearing = require("scripts.advancing_clearing")

local schedule = require("scripts.advancing_schedule")
local recovery = require("scripts.advancing_recovery")
local nest_groups = require("scripts.advancing_nest_groups")

local assault = {}

local VERSION = 5
local TICKS_PER_SECOND = 60
local WAVE_INTERVAL_TICKS = schedule.wave_duration(1)
local FIRST_WAVE_DELAY_TICKS = 5 * TICKS_PER_SECOND
local NEST_REINFORCEMENT_TICKS = schedule.NEST_INTERVAL
local COMMAND_REFRESH_TICKS = 30 * TICKS_PER_SECOND
local STALE_REPOSITION_TICKS = 5 * 60 * TICKS_PER_SECOND
local STARTING_UNITS = 30
local UNITS_PER_WAVE = 2
local UNITS_PER_EXTRA_PLAYER = 5
local ACTIVE_UNIT_CAP = 1000
local SPAWN_BATCH_SIZE = 25
local ACTIVE_NEST_CAP = schedule.NEST_CAP
local MIN_FRONT_DISTANCE = 30
local MAX_FRONT_DISTANCE = clearing.DEPTH - 20
local FRONT_SAFETY_ROWS = 20
local PLAYER_SPAWN_CLEARANCE_SQUARED = 24 * 24
local UNIT_PREFIX = "the-cave-train-wave-"
local QUEEN_NAME = UNIT_PREFIX .. "advancing-queen"
local QUEEN_WAVE_STEP = 60
local QUEEN_NEST_INTERVAL_TICKS = 30 * TICKS_PER_SECOND
local QUEEN_MOVE_INTERVAL_TICKS = 10 * TICKS_PER_SECOND
local QUEEN_RETRY_TICKS = 5 * TICKS_PER_SECOND
local QUEEN_NEST_BATCH = 3
local NEST_PREFIX = "the-cave-advancing-assault-"
local BITER_NEST = NEST_PREFIX .. "biter-spawner"
local SPITTER_NEST = NEST_PREFIX .. "spitter-spawner"
local FAMILIES = {
    { kind = "biter", weight = 40, nest = BITER_NEST },
    { kind = "spitter", weight = 30, nest = SPITTER_NEST },
    { kind = "armoured", weight = 15, nest = NEST_PREFIX .. "armoured-biter-spawner" },
    { kind = "arachnid", weight = 15, nest = NEST_PREFIX .. "arachnid-spawner-unitspawner" },
}
local POSITION_STREAM = 81401
local UNIT_STREAM = 81402

local objective_api

function assault.configure_objective_api(api)
    assert(type(api) == "table" and type(api.get_objective) == "function",
        "advancing assault objective API requires get_objective(force)")
    objective_api = api
end

local function root()
    return storage and storage.the_cave_advancing_collapse or nil
end

local function valid(entity)
    return entity and entity.valid
end

local function copy_position(position)
    if not position then return nil end
    local x = position.x
    local y = position.y
    if x == nil then x = position[1] end
    if y == nil then y = position[2] end
    if x == nil or y == nil then return nil end
    return { x = x, y = y }
end

local function count_records(records)
    local count = 0
    for _, record in pairs(records or {}) do
        local entity = type(record) == "table" and record.entity or record
        if valid(entity) then count = count + 1 end
    end
    return count
end

local function ensure_state(surface_state, tick)
    local state = surface_state.assault
    if type(state) ~= "table" then state = { recovery_15m_migrated = true } end
    local previous_version = tonumber(state.version) or 0
    state.version = VERSION
    state.wave_number = math.max(0, math.floor(tonumber(state.wave_number) or 0))
    state.units = state.units or {}
    state.nests = state.nests or {}
    state.queens = state.queens or {}
    state.queen_due_waves = state.queen_due_waves or {}
    state.next_wave_tick = tonumber(state.next_wave_tick) or (tick + FIRST_WAVE_DELAY_TICKS)
    state.next_nest_tick = tonumber(state.next_nest_tick) or (tick + NEST_REINFORCEMENT_TICKS)
    if previous_version < 4 then
        -- Upgrade once, preserving the current wave and its elapsed combat.
        -- Never replay an old Queen or reset progress when loading a save.
        if state.wave_number > 0 and not state.break_until_tick then
            state.next_wave_tick = math.max(tick,
                (tonumber(state.last_wave_tick) or tick) + schedule.wave_duration(state.wave_number))
        end
        state.next_nest_tick = tick + NEST_REINFORCEMENT_TICKS
    end
    if previous_version < VERSION then
        state.spawn_cells, state.spawn_cell_wave = nil, nil
        state.spawn_failed = nil
        for id, value in pairs(state.nests) do
            if type(value) ~= "table" and valid(value) then
                state.nests[id]={entity=value, wave=state.wave_number, born_tick=tick}
            end
            local record=state.nests[id]
            if type(record)=="table" and valid(record.entity) and not record.family then
                for family, definition in ipairs(FAMILIES) do
                    if definition.nest==record.entity.name then record.family=family;break end
                end
            end
        end
        for _, record in pairs(state.units) do
            if valid(record.entity) then
                record.observed_position = copy_position(record.entity.position)
                record.stationary_since = tick
                record.next_command_tick = tick + COMMAND_REFRESH_TICKS
            end
        end
    end
    surface_state.assault_seed = tonumber(surface_state.assault_seed) or 0
    state.guard_retired = state.guard_retired == true
    surface_state.assault = state
    return state
end

local function active_unit_count(state)
    return count_records(state.units) + count_records(state.queens)
end

local function available_attacker_slots(state)
    -- Reserve the next free slot for a due Queen, even when her bounded
    -- placement retry and the reinforcement clock are offset.
    local reserved = #state.queen_due_waves > 0 and 1 or 0
    return math.max(0, ACTIVE_UNIT_CAP - active_unit_count(state) - reserved)
end

local function safe_destroy(entity)
    if not valid(entity) then return end
    pcall(function() entity.destroy { raise_destroy = false } end)
end

local function destroy_objects(objects)
    for _, object in pairs(objects or {}) do
        if object and object.valid then pcall(function() object.destroy() end) end
    end
end

-- The original guard strip is south of the collapse start line and becomes
-- permanently disconnected as soon as the collapse begins.  Retire only its
-- enemy actors; player entities are never touched.  The first scripted assault
-- then recreates a progression-matched garrison on reachable northern floor.
local function retire_south_guard(surface, surface_state, state)
    if state.guard_retired then return end
    for _, value in pairs(surface_state.south_guard_units or {}) do
        local entity = type(value) == "table" and value.entity or value
        safe_destroy(entity)
    end
    surface_state.south_guard_units = {}

    local half = math.floor(zones.ZONE_WIDTH / 2)
    for _, entity in pairs(surface.find_entities_filtered {
        area = {
            { -half, zones.SOUTH_GUARD_LINE_Y },
            { half, zones.SOUTH_VOID_Y },
        },
        force = "enemy",
        type = { "unit", "unit-spawner", "turret" },
    }) do
        safe_destroy(entity)
    end

    destroy_objects(surface_state.south_guard_beams)
    destroy_objects(surface_state.south_guard_renders)
    surface_state.south_guard_beams = {}
    surface_state.south_guard_renders = {}
    state.guard_retired = true
end

local function owner_force(surface)
    if not (objective_api and type(objective_api.get_owner_force) == "function") then return nil end
    local ok, force = pcall(objective_api.get_owner_force, surface)
    if ok and force and force.valid and force.name ~= "enemy" and force.name ~= "neutral" then
        return force
    end
    return nil
end

local function objective_for(force)
    if not (objective_api and force and force.valid) then return nil end
    local ok, entity = pcall(objective_api.get_objective, force)
    if ok and valid(entity) and entity.force == force then return entity end
    return nil
end

local function add_target(targets, seen, entity)
    if not valid(entity) then return end
    local key = entity.unit_number and ("u:" .. tostring(entity.unit_number))
        or ("p:" .. tostring(entity.position.x) .. ":" .. tostring(entity.position.y))
    if seen[key] then return end
    seen[key] = true
    targets[#targets + 1] = { entity = entity, position = copy_position(entity.position) }
end

local function active_context(surface, surface_state)
    local force = owner_force(surface)
    local players = {}
    local targets = {}
    local seen = {}
    local forces = {}

    for _, resident in ipairs(cave_teams.residents()) do
        local player = resident.player
        local candidate = player.valid and player.connected and player.force
        -- A spectator may keep its team's identity in another mod while its
        -- actual force is the lobby. It must not count toward this assault.
        local relevant = candidate and resident.force == candidate
            and player.controller_type ~= defines.controllers.spectator
            and cave_teams.force_is_running(candidate)
            and resident.home == surface
        if relevant then
            players[#players + 1] = player
            forces[candidate.index] = candidate
        end
    end

    if force and cave_teams.force_is_running(force)
        and cave_teams.home_surface(force) == surface then forces[force.index] = force end
    local force_indexes = {}
    for index in pairs(forces) do force_indexes[#force_indexes + 1] = index end
    table.sort(force_indexes)
    for _, index in ipairs(force_indexes) do
        local objective = objective_for(forces[index])
        if objective and objective.surface == surface then add_target(targets, seen, objective) end
    end

    -- A team's train (or its configured Shelter objective) takes priority.
    -- Characters are a fallback only when no same-surface objective exists.
    if #targets == 0 then
        for _, player in ipairs(players) do
            if physical.surface(player) == surface and valid(player.character) then
                add_target(targets, seen, player.character)
            end
        end
    end

    if #targets == 0 then
        targets[1] = {
            position = {
                x = 0,
                y = tonumber(surface_state.progress_y) or (surface_state.line_y - 200),
            },
        }
    end
    return players, targets
end

local function valid_floor(surface, surface_state, position)
    if not position or not zones.inside_width(position.x) then return false end
    if math.floor(position.y) >= math.floor(surface_state.line_y or zones.SOUTH_GUARD_LINE_Y) - 3 then
        return false
    end
    if zones.is_collapsed(surface, position.x, position.y) then return false end
    local tile = surface.get_tile(position)
    if not (tile and tile.valid) then return false end
    local name = tile.name or ""
    return name ~= "out-of-map"
        and not name:find("water", 1, true)
        and not name:find("ocean", 1, true)
        and not name:find("lava", 1, true)
end

local function clear_of_players(surface, position, players)
    for _, player in ipairs(players or {}) do
        if valid(player.character) and player.character.surface == surface then
            local dx = position.x - physical.position(player).x
            local dy = position.y - physical.position(player).y
            if dx * dx + dy * dy < PLAYER_SPAWN_CLEARANCE_SQUARED then return false end
        end
    end
    return true
end

local function inside_spawn_area(surface_state, name, position)
    local left, right, top, bottom = clearing.bounds(surface_state)
    if position.x < left + 4 or position.x >= right - 4
        or position.y < top + 6 or position.y >= bottom - 8 then return false end
    local prototype = prototypes.entity[name]
    local box = prototype and prototype.collision_box
    if not box then return false end
    local lt, rb = box.left_top or box[1], box.right_bottom or box[2]
    return position.x + (lt.x or lt[1]) >= left
        and position.x + (rb.x or rb[1]) <= right
        and position.y + (lt.y or lt[2]) >= top + 2
        and position.y + (rb.y or rb[2]) < bottom - 4
end

local function choose_wave_cells(surface, state)
    if state.spawn_cells and #state.spawn_cells == clearing.CELL_COUNT
        and state.spawn_cell_wave == state.wave_number then return end
    local seed = tonumber(surface.map_gen_settings and surface.map_gen_settings.seed) or 0
    local order = {}
    for i = 1, clearing.CELL_COUNT do order[i] = i end
    -- Fisher-Yates: every cell has the same initial chance. Consecutive waves
    -- may select the same cell; the saved permutation survives reloads.
    for i = #order, 2, -1 do
        local j = hash.range(seed, state.wave_number, i, POSITION_STREAM + 20, 1, i)
        order[i], order[j] = order[j], order[i]
    end
    state.spawn_cells = order
    state.spawn_cell_cursor = 1
    state.spawn_cell = order[1]
    state.spawn_cell_wave = state.wave_number
    state.spawn_failed = nil
end

local function find_spawn_position(surface, surface_state, name, spawn_y, sequence, players, targets)
    local state = surface_state.assault
    choose_wave_cells(surface, state)
    state.spawn_failed = state.spawn_failed or {}
    if state.spawn_failed[name] == game.tick then return nil end
    local seed = tonumber(surface.map_gen_settings and surface.map_gen_settings.seed) or 0
    local start = state.spawn_cell_cursor or 1
    for offset = 0, clearing.CELL_COUNT - 1 do
        local cursor = ((start + offset - 1) % clearing.CELL_COUNT) + 1
        local cell = state.spawn_cells[cursor]
        local left, right, top, bottom = clearing.cell_bounds(surface_state, cell)
        for attempt = 1, 12 do
            local key = sequence * 97 + attempt
            local anchor = {
                x = hash.range(seed, key, state.wave_number, POSITION_STREAM + cell * 2,
                    left + 2, right - 3),
                y = hash.range(seed, key, state.wave_number, POSITION_STREAM + cell * 2 + 1,
                    top + 2, bottom - 3),
            }
            local position = surface.find_non_colliding_position(name, anchor, 8, 1, true)
            if position and position.x >= left and position.x < right
                and position.y >= top and position.y < bottom
                and valid_floor(surface, surface_state, position)
                and inside_spawn_area(surface_state, name, position)
                and clear_of_players(surface, position, players) then
                local prototype = prototypes.entity[name]
                if prototype.type ~= "unit-spawner" or #surface.find_entities_filtered {
                    type = "unit-spawner", position = position, radius = 10, limit = 1,
                } == 0 then
                    state.spawn_cell_cursor = cursor % clearing.CELL_COUNT + 1
                    state.spawn_cell = cell
                    return copy_position(position)
                end
            end
        end
    end
    -- No destructive clearing or spawn beside a player if all eighty cells
    -- are blocked. Retry later; avoid repeating a full search in this batch.
    state.spawn_failed[name] = game.tick
    return nil
end

local function issue_command(entity, command)
    if not valid(entity) then return false end
    local commanded = false
    pcall(function()
        if entity.commandable and entity.commandable.valid then
            entity.commandable.set_command(command)
            commanded = entity.commandable.has_command
        end
    end)
    if not commanded then
        pcall(function()
            if entity.set_command then
                entity.set_command(command)
                commanded = true
            end
        end)
    end
    return commanded
end

local function target_position(record, targets)
    if #targets == 0 then return nil end
    local key = tonumber(record.entity and record.entity.unit_number) or tonumber(record.wave) or 1
    local target = targets[((key - 1) % #targets) + 1]
    if target.entity and valid(target.entity) then return copy_position(target.entity.position) end
    return copy_position(target.position)
end

local function command_toward_target(record, targets)
    local destination = target_position(record, targets)
    if not destination then return false end
    record.last_target = destination
    record.command_sent = issue_command(record.entity, {
        type = defines.command.attack_area,
        destination = destination,
        radius = 32,
        distraction = defines.distraction.by_enemy,
    })
    if record.command_sent then record.last_command_tick = game.tick end
    return record.command_sent
end

local function nearest_player_blocker(entity)
    if not valid(entity) then return nil end
    local nearest, nearest_distance
    for _, candidate in pairs(entity.surface.find_entities_filtered {
        position = entity.position,
        radius = 12,
    }) do
        if valid(candidate) and candidate ~= entity and candidate.health
            and candidate.force and candidate.force.valid
            and candidate.force.name ~= "enemy" and candidate.force.name ~= "neutral"
            and candidate.prototype and candidate.prototype.is_building then
            local dx = candidate.position.x - entity.position.x
            local dy = candidate.position.y - entity.position.y
            local distance = dx * dx + dy * dy
            if not nearest_distance or distance < nearest_distance then
                nearest = candidate
                nearest_distance = distance
            end
        end
    end
    return nearest
end

local function command_blocker(entity, blocker)
    if not (valid(entity) and valid(blocker)) then return false end
    return issue_command(entity, {
        type = defines.command.attack,
        target = blocker,
        distraction = defines.distraction.by_enemy,
    })
end

local function choose_unit_name(surface, wave_number, sequence, family_index)
    local seed = tonumber(surface.map_gen_settings and surface.map_gen_settings.seed) or 0
    if not family_index then
        local roll = hash.range(seed, wave_number, sequence, UNIT_STREAM, 1, 100)
        for index, family in ipairs(FAMILIES) do
            roll = roll - family.weight
            if roll <= 0 then family_index = index; break end
        end
    end
    local biter = cave_evolution.tier_names(surface)
    local tier = biter:match("^([a-z]+)%-biter$") or "small"
    return UNIT_PREFIX .. tier .. "-" .. FAMILIES[family_index].kind
end

-- Largest-remainder quotas keep the total unchanged and each ordinary wave
-- mixed. Rotate tied remainders between waves; retries never consume a quota.
local function family_quotas(total, wave_number)
    local counts, remainder, allocated = {}, {}, 0
    for index, family in ipairs(FAMILIES) do
        local exact = total * family.weight / 100
        counts[index] = math.floor(exact)
        remainder[index] = exact - counts[index]
        allocated = allocated + counts[index]
    end
    for _ = allocated + 1, total do
        local best
        for offset = 0, #FAMILIES - 1 do
            local index = ((wave_number - 1 + offset) % #FAMILIES) + 1
            if not best or remainder[index] > remainder[best] then best = index end
        end
        counts[best] = counts[best] + 1
        remainder[best] = -1
    end
    if total >= #FAMILIES then
        for index = 1, #FAMILIES do
            if counts[index] == 0 then
                local donor = 1
                for candidate = 2, #FAMILIES do
                    if counts[candidate] > counts[donor] then donor = candidate end
                end
                counts[donor] = counts[donor] - 1
                counts[index] = 1
            end
        end
    end
    return counts
end

local function register_unit(state, entity, wave_number, tick)
    if not (valid(entity) and entity.unit_number) then return nil end
    local record = {
        entity = entity,
        wave = wave_number,
        born_tick = tick,
        last_position = copy_position(entity.position),
        stationary_since = tick,
        next_command_tick = tick + COMMAND_REFRESH_TICKS,
        observed_position = copy_position(entity.position),
    }
    state.units[entity.unit_number] = record
    pcall(function()
        if entity.ai_settings then
            entity.ai_settings.allow_destroy_when_commands_fail = false
            entity.ai_settings.allow_try_return_to_spawner = false
            entity.ai_settings.join_attacks = false
        end
    end)
    return record
end

local function create_unit(surface, surface_state, state, name, spawn_y, sequence,
        players, targets, wave_number, tick, anchor)
    if not (prototypes and prototypes.entity and prototypes.entity[name]) then return nil end
    local position
    if anchor then
        position = surface.find_non_colliding_position(name, anchor, 10, 0.5, true)
        if position and (not valid_floor(surface, surface_state, position)
            or not inside_spawn_area(surface_state, name, position)
            or not clear_of_players(surface, position, players)) then
            position = nil
        end
    end
    position = position or find_spawn_position(
        surface, surface_state, name, spawn_y, sequence, players, targets)
    if not position then return nil end

    local entity
    local ok = pcall(function()
        entity = surface.create_entity {
            name = name,
            position = position,
            force = game.forces.enemy,
            create_build_effect_smoke = false,
        }
    end)
    if not ok or not valid(entity) then return nil end
    local record = register_unit(state, entity, wave_number, tick)
    if record and not command_toward_target(record, targets) then
        record.next_command_tick = tick + TICKS_PER_SECOND
    end
    return record
end

local function prune_units(surface, surface_state, state)
    for unit_number, record in pairs(state.units) do
        local entity = record and record.entity
        if not (valid(entity) and entity.unit_number == unit_number and entity.type == "unit") then
            state.units[unit_number] = nil
        elseif zones.is_collapsed(surface, entity.position.x, entity.position.y) then
            safe_destroy(entity)
            state.units[unit_number] = nil
        end
    end
end

local function prune_nests(surface, surface_state, state)
    for unit_number, record in pairs(state.nests) do
        local entity = type(record) == "table" and record.entity or record
        if not (valid(entity) and entity.unit_number == unit_number
            and entity.type == "unit-spawner") then
            nest_groups.mark_missing(state, record, game.tick, unit_number)
            state.nests[unit_number] = nil
        elseif zones.is_collapsed(surface, entity.position.x, entity.position.y) then
            nest_groups.mark_missing(state, record, game.tick, unit_number)
            safe_destroy(entity)
            state.nests[unit_number] = nil
        end
    end
end

local function clear_round_nests(state)
    -- A chunk-aligned boundary can leave a surviving nest in the narrow gap
    -- before the physical front. Retire every owned nest when its round ends.
    for _, record in pairs(state.nests) do
        safe_destroy(type(record) == "table" and record.entity or record)
    end
    state.nests = {}
end

local function prune(surface, surface_state, state)
    prune_units(surface, surface_state, state)
    prune_nests(surface, surface_state, state)
    for unit_number, record in pairs(state.queens) do
        local entity = record.entity
        if not (valid(entity) and entity.unit_number == unit_number and entity.name == QUEEN_NAME) then
            state.queens[unit_number] = nil
        elseif zones.is_collapsed(surface, entity.position.x, entity.position.y) then
            safe_destroy(entity)
            state.queens[unit_number] = nil
        end
    end
end

local function front_distance(amount, speed)
    amount = math.max(1, tonumber(amount) or 4)
    speed = math.max(1, tonumber(speed) or 8)
    local rows_before_next_wave = math.ceil(
        WAVE_INTERVAL_TICKS * amount / (speed * zones.ZONE_WIDTH))
    return math.max(
        MIN_FRONT_DISTANCE,
        math.min(MAX_FRONT_DISTANCE, rows_before_next_wave + FRONT_SAFETY_ROWS)
    )
end

local function current_spawn_y(surface_state, state, amount, speed)
    local distance = front_distance(amount, speed)
    state.last_front_distance = distance
    return math.floor(surface_state.line_y or zones.SOUTH_GUARD_LINE_Y) - distance
end

local function spawn_pending_batch(surface, surface_state, state, tick, players, targets, amount, speed)
    local pending = state.pending_units
    if type(pending) ~= "table" or (tonumber(pending.remaining) or 0) <= 0 then
        state.pending_units = nil
        return 0
    end

    local available = available_attacker_slots(state)
    if available <= 0 then
        state.pending_units = nil
        return 0
    end
    local wanted = math.min(SPAWN_BATCH_SIZE, pending.remaining, available)
    pending.family_remaining = pending.family_remaining
        or family_quotas(pending.remaining, pending.wave)
    local spawn_y = current_spawn_y(surface_state, state, amount, speed)
    local created = 0
    local attempts = 0
    while created < wanted and attempts < SPAWN_BATCH_SIZE + 8 do
        attempts = attempts + 1
        pending.sequence = (tonumber(pending.sequence) or 0) + 1
        local family_index
        for _ = 1, #FAMILIES do
            pending.family_cursor = ((pending.family_cursor or 0) % #FAMILIES) + 1
            if pending.family_remaining[pending.family_cursor] > 0 then
                family_index = pending.family_cursor
                break
            end
        end
        if not family_index then break end
        local name = choose_unit_name(surface, pending.wave, pending.sequence, family_index)
        local record = create_unit(
            surface, surface_state, state, name, spawn_y, pending.sequence,
            players, targets, pending.wave, tick)
        if record then
            created = created + 1
            pending.remaining = pending.remaining - 1
            pending.family_remaining[family_index] = pending.family_remaining[family_index] - 1
        end
    end

    if created == 0 then
        pending.failed_batches = (tonumber(pending.failed_batches) or 0) + 1
    else
        pending.failed_batches = 0
    end
    if pending.remaining <= 0 or pending.failed_batches >= 5 then
        state.pending_units = nil
    else
        pending.next_tick = tick + TICKS_PER_SECOND
    end
    return created
end

local function create_wave_nests(surface, surface_state, state, wave_number, wanted,
        spawn_y, players, targets, family_start, sequence_offset, queen_id)
    local available = ACTIVE_NEST_CAP - count_records(state.nests)
    wanted = math.min(math.max(0, wanted), math.max(0, available))
    -- Both timed groups and Queen placement use these reserved homes. Neither
    -- can bypass a destroyed nest's two-minute deadline or unlock future groups.
    return nest_groups.populate(surface, surface_state, state, game.tick, wanted, {
        nest_name = function(family)
            local name = FAMILIES[family].nest
            return prototypes.entity[name] and name or nil
        end,
        valid_position = function(name, position)
            return valid_floor(surface, surface_state, position)
                and inside_spawn_area(surface_state, name, position)
                and clear_of_players(surface, position, players)
        end,
        create = function(name, position, slot, parent_queen)
            if count_records(state.nests) >= ACTIVE_NEST_CAP then return nil end
            local entity = surface.create_entity {name=name, position=position,
                force=game.forces.enemy, create_build_effect_smoke=false}
            if not (valid(entity) and entity.unit_number) then return nil end
            entity.disabled_by_script=true
            entity.minable_flag=false
            local record={entity=entity, wave=wave_number, born_tick=game.tick,
                family=slot.family, group=slot.group, slot=slot.index, queen_id=parent_queen}
            state.nests[entity.unit_number]=record
            return record
        end,
    }, queen_id)
end

local function queen_location(entity)
    return "[gps=" .. math.floor(entity.position.x) .. "," .. math.floor(entity.position.y)
        .. "," .. entity.surface.name .. "]"
end

local function command_queen(surface, surface_state, record, tick)
    local entity = record.entity
    local left, right, top, bottom = clearing.bounds(surface_state)
    local seed = tonumber(surface.map_gen_settings and surface.map_gen_settings.seed) or 0
    local sequence = (entity.unit_number or 0) + math.floor(tick / TICKS_PER_SECOND)
    local destination
    -- Destinations follow the moving rectangle, with a larger margin from the
    -- consuming front. No attack, excavation or destructive escape fallback.
    for attempt = 1, 8 do
        local anchor = {
            x = hash.range(seed, sequence, attempt, POSITION_STREAM + 10, left + 10, right - 10),
            y = hash.range(seed, sequence, attempt, POSITION_STREAM + 11, top + 24, bottom - 56),
        }
        local position = surface.find_non_colliding_position(QUEEN_NAME, anchor, 8, 1, true)
        if position and valid_floor(surface, surface_state, position)
            and inside_spawn_area(surface_state, QUEEN_NAME, position)
            and position.y < bottom - 40 then
            destination = copy_position(position)
            break
        end
    end
    if destination then
        issue_command(entity, {
            type = defines.command.go_to_location,
            destination = destination,
            radius = 2,
            distraction = defines.distraction.none,
            pathfind_flags = { allow_destroy_friendly_entities = false,
                allow_paths_through_own_entities = false, cache = false },
        })
    else
        issue_command(entity, { type = defines.command.stop, distraction = defines.distraction.none })
    end
    record.destination = destination
    record.next_move_tick = tick + (destination and QUEEN_MOVE_INTERVAL_TICKS or QUEEN_RETRY_TICKS)
end

local function lay_queen_nests(surface, surface_state, state, record, tick, players, targets)
    local entity = record.entity
    if not valid(entity) then return 0 end
    local created = create_wave_nests(surface, surface_state, state,
        record.wave, QUEEN_NEST_BATCH, entity.position.y, players, targets,
        record.family_cursor or 0, entity.unit_number + math.floor(tick / TICKS_PER_SECOND),
        entity.unit_number)
    record.family_cursor = ((record.family_cursor or 0) + created) % #FAMILIES
    record.next_nest_tick = tick + QUEEN_NEST_INTERVAL_TICKS
    return created
end

local function spawn_queen(surface, surface_state, state, tick, players, targets, wave_number)
    if active_unit_count(state) >= ACTIVE_UNIT_CAP then return nil, "queen-test-cap" end
    if not prototypes.entity[QUEEN_NAME] then return nil, "queen-test-unavailable" end
    local position = find_spawn_position(surface, surface_state, QUEEN_NAME,
        surface_state.line_y - 100, tick + wave_number, players, targets)
    if not position then return nil, "queen-test-blocked" end
    local entity
    local ok = pcall(function()
        entity = surface.create_entity {
            name = QUEEN_NAME, position = position, force = game.forces.enemy,
            create_build_effect_smoke = false,
        }
    end)
    if not (ok and valid(entity) and entity.unit_number) then return nil, "queen-test-blocked" end
    -- Keep her outside native attacks and ordinary Cave Queen ownership.
    local ai = entity.ai_settings
    ai.join_attacks = false
    ai.allow_try_return_to_spawner = false
    ai.allow_destroy_when_commands_fail = false
    local record = { entity = entity, wave = wave_number, born_tick = tick, family_cursor = 0 }
    state.queens[entity.unit_number] = record
    command_queen(surface, surface_state, record, tick)
    local nests = lay_queen_nests(surface, surface_state, state, record, tick, players, targets)
    for _, player in ipairs(players) do
        player.print({ "the-cave-advancing-collapse.queen-arrived", queen_location(entity), nests })
    end
    return record
end

local function spawn_due_queen(surface, surface_state, state, tick, players, targets)
    if #state.queen_due_waves == 0 or tick < (state.next_queen_retry_tick or 0) then return end
    local record = spawn_queen(surface, surface_state, state, tick, players, targets,
        state.queen_due_waves[1])
    if record then table.remove(state.queen_due_waves, 1) end
    -- A crowded/blocked milestone is retained across saves and gets priority
    -- over reinforcements when a slot opens; never delete enemies to fit it.
    state.next_queen_retry_tick = tick + QUEEN_RETRY_TICKS
end

local function process_queens(surface, surface_state, state, tick, players, targets, ready)
    local _, _, top, bottom = clearing.bounds(surface_state)
    for _, record in pairs(state.queens) do
        if valid(record.entity) then
            local destination = record.destination
            if tick >= (record.next_move_tick or 0)
                or (destination and (destination.y < top + 6 or destination.y >= bottom - 40)) then
                command_queen(surface, surface_state, record, tick)
            end
            if ready and tick >= (record.next_nest_tick or tick) then
                lay_queen_nests(surface, surface_state, state, record, tick, players, targets)
            end
        end
    end
end

local function announce_wave(players, wave_number, units, nests)
    for _, player in ipairs(players) do
        if player and player.valid and player.connected then
            player.print(
                { "the-cave-advancing-collapse.wave-started", wave_number, units, nests },
                { r = 1, g = 0.22, b = 0.06 }
            )
            pcall(function()
                player.play_sound { path = "utility/new_objective", volume_modifier = 1 }
            end)
        end
    end
end

local function start_wave(surface, surface_state, state, tick, players, targets, amount, speed)
    state.wave_number = state.wave_number + 1
    if not state.nest_cycle or state.nest_restart_pending then
        nest_groups.start_cycle(state, surface_state, tick)
        state.nest_restart_pending=nil
    end
    choose_wave_cells(surface, state)
    if state.wave_number % QUEEN_WAVE_STEP == 0 then
        state.queen_due_waves[#state.queen_due_waves + 1] = state.wave_number
        state.next_queen_retry_tick = tick
        spawn_due_queen(surface, surface_state, state, tick, players, targets)
    end
    local player_count = math.max(1, #players)
    local requested = STARTING_UNITS
        + (state.wave_number - 1) * UNITS_PER_WAVE
        + (player_count - 1) * UNITS_PER_EXTRA_PLAYER
    requested = math.min(requested, available_attacker_slots(state))

    local spawn_y = current_spawn_y(surface_state, state, amount, speed)
    local nests = create_wave_nests(
        surface, surface_state, state, state.wave_number, nest_groups.SIZE,
        spawn_y, players, targets)

    if requested > 0 then
        state.pending_units = {
            wave = state.wave_number,
            remaining = requested,
            sequence = 0,
            failed_batches = 0,
            next_tick = tick,
            family_remaining = family_quotas(requested, state.wave_number),
        }
        spawn_pending_batch(surface, surface_state, state, tick, players, targets, amount, speed)
    else
        state.pending_units = nil
    end

    state.last_wave_tick = tick
    state.last_wave_units = requested
    state.last_wave_nests = nests
    -- Start the first reinforcement clock from the first nests' creation.
    if state.wave_number == 1 then
        state.next_nest_tick = tick + NEST_REINFORCEMENT_TICKS
    end
    state.next_wave_tick = tick + schedule.wave_duration(state.wave_number)
    announce_wave(players, state.wave_number, requested, nests)
end

local function spawn_nest_reinforcements(surface, surface_state, state, tick,
        players, targets, amount, speed)
    local available = available_attacker_slots(state)
    if available <= 0 then return 0 end
    local spawn_y = current_spawn_y(surface_state, state, amount, speed)
    local created = 0
    local sequence = state.wave_number * 10000 + math.floor(tick / NEST_REINFORCEMENT_TICKS)
    for _, nest_record in pairs(state.nests) do
        if created >= available then break end
        local nest = type(nest_record) == "table" and nest_record.entity or nest_record
        if valid(nest) then
            sequence = sequence + 1
            local family_index = type(nest_record) == "table" and nest_record.family or nil
            if not family_index then
                for index, family in ipairs(FAMILIES) do
                    if nest.name == family.nest then family_index = index; break end
                end
            end
            local name = choose_unit_name(surface, state.wave_number, sequence, family_index)
            local record = create_unit(
                surface, surface_state, state, name, spawn_y, sequence,
                players, targets, state.wave_number, tick, nest.position)
            if record then created = created + 1 end
        end
    end
    return created
end

local function reposition_stale_unit(surface, surface_state, state, record, tick,
        players, targets, amount, speed)
    local entity = record.entity
    if not valid(entity) then return false end
    local spawn_y = current_spawn_y(surface_state, state, amount, speed)
    local position = find_spawn_position(
        surface, surface_state, entity.name, spawn_y,
        (entity.unit_number or 0) + math.floor(tick / TICKS_PER_SECOND), players, targets)
    if not position then return false end
    local ok, teleported = pcall(function() return entity.teleport(position) end)
    if not ok or teleported == false then return false end
    record.last_position = copy_position(entity.position)
    record.stationary_since = tick
    return true
end

local function engaged_in_combat(entity)
    local engaged=false
    pcall(function()
        local commandable=entity.commandable
        local command=commandable and (commandable.distraction_command or commandable.command)
        if not (command and command.type==defines.command.attack and valid(command.target)) then return end
        local attack=entity.prototype.attack_parameters
        local range=attack and attack.range or 0
        local box=command.target.bounding_box
        local position=entity.position
        local dx=math.max(box.left_top.x-position.x,0,position.x-box.right_bottom.x)
        local dy=math.max(box.left_top.y-position.y,0,position.y-box.right_bottom.y)
        engaged=dx*dx+dy*dy<=(range+1)^2
    end)
    return engaged
end

local function process_units(surface, surface_state, state, tick, players, targets, amount, speed)
    for unit_number, record in pairs(state.units) do
        local entity = record and record.entity
        if not valid(entity) then
            state.units[unit_number] = nil
        else
            local previous = record.observed_position or record.last_position or entity.position
            local dx = entity.position.x - previous.x
            local dy = entity.position.y - previous.y
            if dx * dx + dy * dy >= 0.0625 then
                record.observed_position = copy_position(entity.position)
                record.last_position = copy_position(entity.position)
                record.stationary_since = tick
            else
                record.stationary_since = tonumber(record.stationary_since) or tick
            end

            if tick >= (tonumber(record.next_command_tick) or 0) then
                local commanded=false
                pcall(function() commanded=entity.commandable.has_command end)
                local idle=tick-record.stationary_since>=COMMAND_REFRESH_TICKS
                -- Leave moving units and active attack/distraction commands alone.
                if not engaged_in_combat(entity) and (idle or not commanded) then
                    local blocker = nearest_player_blocker(entity)
                    if blocker then
                        record.command_sent=command_blocker(entity, blocker)
                    else
                        if tick - record.stationary_since >= STALE_REPOSITION_TICKS then
                            reposition_stale_unit(surface, surface_state, state, record, tick,
                                players, targets, amount, speed)
                        end
                        command_toward_target(record, targets)
                    end
                end
                record.next_command_tick = tick + (record.command_sent == false
                    and TICKS_PER_SECOND or COMMAND_REFRESH_TICKS)
            end
        end
    end
end

function assault.begin_surface(surface, surface_state, tick)
    if not (surface and surface.valid and surface_state) then return nil end
    local state = ensure_state(surface_state, tick or (game and game.tick or 0))
    surface_state.assault_seed = tonumber(surface.map_gen_settings.seed) or 0
    nest_groups.ensure(state, surface_state, tick or game.tick)
    retire_south_guard(surface, surface_state, state)
    return state
end

function assault.drop_surface(surface_state)
    local state = surface_state and surface_state.assault
    if not state then return end
    for _, records in ipairs({state.units or {}, state.nests or {}, state.queens or {}}) do
        for _, record in pairs(records) do safe_destroy(record.entity) end
    end
    surface_state.assault = nil
end

function assault.on_configuration_changed()
    local value = root()
    if not (zones.is_active() and value) then return end
    local tick = game and game.tick or 0
    for surface_index, surface_state in pairs(value.surfaces or {}) do
        local surface = game.get_surface(surface_index)
        if surface and surface.valid and surface_state.phase == "active" and cave_teams.is_world_running(surface) then
            local state = assault.begin_surface(surface, surface_state, tick)
            if state.break_until_tick then
                local left, right, top, bottom = clearing.bounds(surface_state)
                state.break_area = { {left, top}, {right, bottom} }
                if not state.recovery_15m_migrated and state.wave_number % 20 == 0
                    and state.wave_number % 60 ~= 0 then
                    state.break_until_tick = state.break_until_tick + 5 * 60 * TICKS_PER_SECOND
                    state.next_wave_tick = state.break_until_tick
                end
                recovery.clear(surface, state, false)
            end
            state.recovery_15m_migrated = true
        end
    end
end

function assault.on_tick(surface, surface_state, tick, amount, speed)
    if not (surface and surface.valid and surface_state and surface_state.phase == "active" and cave_teams.is_world_running(surface) and tick % TICKS_PER_SECOND == 0) then return end
    local state = assault.begin_surface(surface, surface_state, tick)
    prune(surface, surface_state, state)

    local players, targets = active_context(surface, surface_state)
    if #players == 0 then return end

    local was_resting = state.break_until_tick ~= nil
    local transition = schedule.transition(state, tick)
    if transition == "break" then
        local min_x, max_x, top, bottom = clearing.bounds(surface_state)
        state.break_area = { { min_x, top }, { max_x, bottom } }
        state.pending_units = nil
        state.queen_due_waves = {}
        nest_groups.clear(state)
        recovery.clear(surface, state, true)
        clear_round_nests(state)
        prune(surface, surface_state, state)
        for _, player in ipairs(players) do
            player.print({ "the-cave-advancing-collapse.recovery-started",
                state.wave_number, schedule.break_duration(state.wave_number) / 3600 })
        end
        return
    elseif transition == "rest" then
        nest_groups.clear(state)
        clear_round_nests(state)
        return
    end

    local ready = clearing.is_ready(surface_state)
    if transition == "wave" and ready then
        -- Process this boundary before old nests/Queens can spawn again.
        if was_resting then
            state.next_nest_tick = tick + NEST_REINFORCEMENT_TICKS
            for _, record in pairs(state.queens) do
                record.next_nest_tick = tick + QUEEN_NEST_INTERVAL_TICKS
            end
        end
        start_wave(surface, surface_state, state, tick, players, targets, amount, speed)
    end
    process_queens(surface, surface_state, state, tick, players, targets, ready)
    if not ready then
        process_units(surface, surface_state, state, tick, players, targets, amount, speed)
        return
    end

    -- At most three placement/legacy-migration attempts per second. Existing
    -- homes are never rerolled just because a player or building blocks them.
    create_wave_nests(surface, surface_state, state, state.wave_number,
        nest_groups.SIZE, current_spawn_y(surface_state,state,amount,speed), players,targets)

    spawn_due_queen(surface, surface_state, state, tick, players, targets)

    if state.pending_units and tick >= (tonumber(state.pending_units.next_tick) or tick) then
        spawn_pending_batch(surface, surface_state, state, tick, players, targets, amount, speed)
    end

    if tick >= state.next_nest_tick then
        spawn_nest_reinforcements(
            surface, surface_state, state, tick, players, targets, amount, speed)
        state.next_nest_tick = tick + NEST_REINFORCEMENT_TICKS
    end

    process_units(surface, surface_state, state, tick, players, targets, amount, speed)
end

function assault.on_entity_died(event)
    local entity=event and event.entity
    if not (valid(entity) and entity.unit_number) then return end
    local value=root()
    if not (zones.is_active() and value) then return end
    local ss=value and value.surfaces and value.surfaces[entity.surface.index]
    local state=ss and ss.phase=="active" and ss.assault
    local record=state and state.nests and state.nests[entity.unit_number]
    if record then
        nest_groups.mark_missing(state,record,game.tick,entity.unit_number)
        state.nests[entity.unit_number]=nil
    end
end

function assault.on_entity_spawned(event)
    local entity,spawner=event and event.entity,event and event.spawner
    if not (valid(entity) and valid(spawner) and entity.type=="unit"
        and entity.force.name=="enemy" and entity.surface==spawner.surface) then return end
    local value=root()
    if not (zones.is_active() and value) then return end
    local ss=value.surfaces and value.surfaces[spawner.surface.index]
    local state=ss and ss.phase=="active" and ss.assault
    if not (state and state.nests and state.nests[spawner.unit_number]) then return end
    if state.units[entity.unit_number] then return end -- duplicate events do not reset AI
    if state.break_until_tick or available_attacker_slots(state)<=0 then safe_destroy(entity);return end
    local record=register_unit(state,entity,state.wave_number,game.tick)
    pcall(function() entity.release_from_spawner() end)
    local _,targets=active_context(entity.surface,ss)
    if record and not command_toward_target(record,targets) then
        record.next_command_tick=game.tick+TICKS_PER_SECOND
    end
end

local function status_surface_for_player(player, value)
    local force = cave_teams.player_force(player)
    local surface = physical.surface(player)
    if surface and zones.is_main_surface(surface) and owner_force(surface) == force then return surface end
    surface = force and cave_teams.home_surface(force)
    return surface and zones.is_main_surface(surface) and surface or nil
end

function assault.status_for_player(player)
    local value = root()
    if not (player and player.valid and value) then return nil end
    local surface = status_surface_for_player(player, value)
    local surface_state = surface and value.surfaces and value.surfaces[surface.index]
    local state = surface_state and surface_state.phase == "active" and surface_state.assault
    if type(state) ~= "table" then return nil end
    return {
        wave = math.max(0, math.floor(tonumber(state.wave_number) or 0)),
        units = active_unit_count(state),
        nests = count_records(state.nests),
        resting = state.break_until_tick ~= nil,
        recovery_due = schedule.break_duration(state.wave_number) > 0,
        next_seconds = math.max(0, math.ceil(
            ((tonumber(state.next_wave_tick) or game.tick) - game.tick) / TICKS_PER_SECOND)),
    }
end

function assault.is_owned_entity(entity)
    if not (entity and entity.valid) then return false end
    for _, family in ipairs(FAMILIES) do
        if entity.name == family.nest then return true end
    end
    if not entity.unit_number then return false end
    local value = root()
    local surface_state = value and value.surfaces and value.surfaces[entity.surface.index]
    local state = surface_state and surface_state.phase == "active" and surface_state.assault
    local record = state and ((state.units and state.units[entity.unit_number])
        or (state.queens and state.queens[entity.unit_number]))
    return record and record.entity == entity or false
end

local function queen_test_command(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "diggy.admin-only" }); return end
    local value = root()
    if not (zones.is_active() and value) then
        player.print({ "the-cave-advancing-collapse.queen-test-inactive" }); return
    end
    local surface = status_surface_for_player(player, value)
    local force = surface and owner_force(surface)
    local surface_state = surface and value.surfaces and value.surfaces[surface.index]
    if not surface_state or surface_state.phase ~= "active" or (force and force ~= player.force)
        or (not force and surface ~= physical.surface(player)) then
        player.print({ "the-cave-advancing-collapse.queen-test-surface" }); return
    end
    if not clearing.is_ready(surface_state) then
        player.print({ "the-cave-advancing-collapse.queen-test-preparing" }); return
    end
    local state = assault.begin_surface(surface, surface_state, game.tick)
    if recovery.is_resting(surface_state) then
        player.print({ "the-cave-advancing-collapse.queen-test-resting" }); return
    end
    prune(surface, surface_state, state)
    -- Repeating the test command locates the living Queen; it cannot flood a
    -- surface or alter wave numbers, deadlines, terrain or existing nests.
    for _, record in pairs(state.queens) do
        if valid(record.entity) then
            player.print({ "the-cave-advancing-collapse.queen-test-existing", queen_location(record.entity) })
            return
        end
    end
    local players, targets = active_context(surface, surface_state)
    local due_wave = state.queen_due_waves[1]
    local record, reason = spawn_queen(surface, surface_state, state, game.tick,
        players, targets, due_wave or math.max(1, state.wave_number))
    if not record then
        player.print({ "the-cave-advancing-collapse." .. reason })
    elseif due_wave then
        table.remove(state.queen_due_waves, 1)
    end
end

function assault.register_commands()
    commands.add_command("the-cave-advancing-queen-test",
        { "the-cave-advancing-collapse.queen-test-help" }, queen_test_command)
end

assault.BITER_NEST = BITER_NEST
assault.SPITTER_NEST = SPITTER_NEST

return assault
