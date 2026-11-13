local cave_worlds = require("scripts.cave_worlds")
local cave_teams = require("scripts.cave_teams")
-- Vanilla enemy expansion cannot normally select The Cave's opened rooms:
-- most 32x32 chunks are dominated by out-of-map tiles and therefore fail the
-- engine's max_colliding_tiles_coefficient test. This adapter accepts opened
-- Cave floor and uses a deliberate 10-to-2-minute Evolution-scaled cadence.
-- Maximum expansion distance, player-building avoidance and settler group size
-- still use Factorio's live enemy_expansion map settings. The Cave explicitly
-- forms a real, filtered settler group and gives it Factorio's build_base
-- command, preventing private Wave units from being recruited when the two
-- independent systems run together. Cave expansion deliberately has no minimum
-- distance or existing-base influence, allowing adjacent opened chunks to fill
-- as physical placement permits.
local hash = require("scripts.lib.hash")
local cave_evolution = require("scripts.cave_evolution")
local game_settings = require("scripts.game_settings")
local enemy_nest_growth = require("scripts.enemy_nest_growth")
local bob_enemies = require("scripts.bob_enemies")

local cave_enemy_expansion = {}

local STORAGE_KEY = "the_cave_vanilla_enemy_expansion"
local TARGET_STREAM = 278700
local CHECK_INTERVAL = 300
local OBJECTIVE_INTERVAL = 60
local OBJECTIVE_RADIUS = 200
local OBJECTIVE_RADIUS_SQUARED = OBJECTIVE_RADIUS * OBJECTIVE_RADIUS
local OBJECTIVE_COMMAND_REFRESH = 10 * 60
local WAVE_UNIT_PREFIX = "the-cave-train-wave-"
local ADVANCING_ASSAULT_NEST_PREFIX = "the-cave-advancing-assault-"
local PENDING_LIFETIME = 20 * 60 * 60
local CUSTOM_TARGET_RADIUS_SQUARED = 48 * 48
local TICKS_PER_MINUTE = 60 * 60
local MAX_EXPANSION_COOLDOWN = 10 * TICKS_PER_MINUTE
local MIN_EXPANSION_COOLDOWN = 2 * TICKS_PER_MINUTE
local ATTACK_POLLUTION_CONSUMPTION_MODIFIER = 0.1
local NORMAL_ATTACK_POLLUTION_CONSUMPTION_MODIFIER = 1.0

-- Bound by control.lua after Train Interiors and Shelter Defense have loaded.
-- The function stays outside storage so saves never serialize module closures.
local objective_api

function cave_enemy_expansion.configure_objective_api(api)
    assert(type(api) == "table" and type(api.get_objective) == "function",
        "cave_enemy_expansion objective API requires get_objective(force)")
    objective_api = api
end

local function setting_enabled()
    return game_settings.biter_expansion_enabled()
end

local function disable_unfiltered_engine_planner()
    local expansion = game and game.map_settings and game.map_settings.enemy_expansion
    if expansion then expansion.enabled = false end
end

-- A lower attack cost lets the same real pollution assign more enemies to
-- attack groups. This changes the pollution budget required by each attacker;
-- it does not change a spawner prototype's direct per-cycle absorption rate.
-- The latter is independently reduced during data-final-fixes so dense nests
-- can keep attacking without becoming an immediate pollution wall.
local function apply_attack_pollution_cost()
    local pollution = game and game.map_settings and game.map_settings.pollution
    if not pollution then return false end
    pollution.enemy_attack_pollution_consumption_modifier = setting_enabled()
        and ATTACK_POLLUTION_CONSUMPTION_MODIFIER
        or NORMAL_ATTACK_POLLUTION_CONSUMPTION_MODIFIER
    return true
end

local function is_main_cave_surface(surface)
    if not (surface and surface.valid and cave_worlds.is_cave_world(surface) and cave_teams.is_world_running(surface)) then return false end
    -- A protected mid-save installation deliberately leaves an existing
    -- vanilla world unconverted. Never add the Cave fallback to that world.
    if storage and storage.mid_save_install then return false end
    -- Main Cave worlds always retain a mineable diggy-rock frontier. This also
    -- excludes ordinary Nauvis surfaces that happen to share the same name.
    return surface.count_entities_filtered { name = "diggy-rock", limit = 1 } > 0
end

local function inside_live_objective_radius(surface, position)
    if not (objective_api and surface and surface.valid and position) then return false end
    local seen_forces = {}
    for _, force in pairs(game.forces) do
        if force and force.valid and force.name ~= "enemy" and force.name ~= "neutral"
            and not seen_forces[force.index] then
            seen_forces[force.index] = true
            local ok, entity = pcall(objective_api.get_objective, force)
            if ok and entity and entity.valid and entity.unit_number
                and entity.force == force and entity.surface == surface
                and (entity.type == "locomotive" or entity.name == "the-cave-shelter") then
                local dx = position.x - entity.position.x
                local dy = position.y - entity.position.y
                if dx * dx + dy * dy <= OBJECTIVE_RADIUS_SQUARED then return true end
            end
        end
    end
    return false
end

local function root()
    local value = storage[STORAGE_KEY]
    if type(value) ~= "table" then
        value = { version = 1, surfaces = {} }
        storage[STORAGE_KEY] = value
    end
    value.version = 1
    value.surfaces = value.surfaces or {}
    -- A short-lived 3.1.63 test build used the Train-specific field name.
    -- Adopt it lazily so those saves can move to the final objective controller.
    value.objective_attackers = value.objective_attackers or value.train_attackers or {}
    value.train_attackers = nil
    value.objective_renders = value.objective_renders or {}
    value.migration_groups = value.migration_groups or {}
    return value
end

local function state_for(surface)
    local states = root().surfaces
    local state = states[surface.index]
    if type(state) ~= "table" then
        state = {
            sequence = 0,
            next_tick = nil,
            pending_targets = {},
        }
        states[surface.index] = state
    end
    state.sequence = math.max(0, math.floor(tonumber(state.sequence) or 0))
    state.pending_targets = state.pending_targets or {}
    return state
end

local function evolution_for(surface)
    return cave_evolution.factor(surface)
end

-- The Cave intentionally accelerates the standard cadence. The interval is
-- ten minutes at zero Evolution, eight at 25%, six at 50%, four at 75%, and
-- two at full Evolution.
local function cave_cooldown(surface)
    local evolution = evolution_for(surface)
    return math.max(1, math.floor(
        MAX_EXPANSION_COOLDOWN
            - evolution * (MAX_EXPANSION_COOLDOWN - MIN_EXPANSION_COOLDOWN)
            + 0.5
    ))
end

-- The live Map settings are authoritative. At zero evolution the official
-- minimum party is used; evolution interpolates the party toward its official
-- maximum.
local function vanilla_group_size(surface)
    local expansion = game.map_settings.enemy_expansion
    local minimum = math.max(1, math.floor(tonumber(expansion.settler_group_min_size) or 5))
    local maximum = math.max(1, math.floor(tonumber(expansion.settler_group_max_size) or 20))
    if minimum > maximum then minimum, maximum = maximum, minimum end
    local evolution = evolution_for(surface)
    return math.max(1, math.floor(minimum + evolution * (maximum - minimum) + 0.5))
end

local function chunk_key(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

local function add_chunk_count(counts, position)
    local x = math.floor(position.x / 32)
    local y = math.floor(position.y / 32)
    local key = chunk_key(x, y)
    counts[key] = (counts[key] or 0) + 1
end

local function enemy_spawners(surface)
    local eligible = {}
    for _, spawner in pairs(surface.find_entities_filtered {
        type = "unit-spawner",
        force = "enemy",
    }) do
        if type(spawner.name) ~= "string"
            or spawner.name:sub(1, #ADVANCING_ASSAULT_NEST_PREFIX)
                ~= ADVANCING_ASSAULT_NEST_PREFIX then
            eligible[#eligible + 1] = spawner
        end
    end
    return eligible
end

-- Factorio's official candidate score counts every player-owned building.
-- LuaEntityPrototype.is_building uses the same engine classification, so
-- pipes, belts, rails, walls and other inexpensive structures influence Cave
-- expansion exactly as they do on ordinary Nauvis.
local function player_building_counts(surface)
    local counts = {}
    for _, force in pairs(game.forces) do
        if force.valid and force.name ~= "enemy" and force.name ~= "neutral" then
            for _, entity in pairs(surface.find_entities_filtered { force = force }) do
                if entity.valid and entity.prototype and entity.prototype.is_building then
                    add_chunk_count(counts, entity.position)
                end
            end
        end
    end
    return counts
end

local function influence(counts, center_x, center_y, radius, coefficient)
    local total = 0
    radius = math.max(0, math.floor(tonumber(radius) or 0))
    coefficient = tonumber(coefficient) or 0
    -- The Factorio 2.0 documentation specifies a square neighbourhood and
    -- Manhattan distance for each coefficient exponent.
    for dx = -radius, radius do
        for dy = -radius, radius do
            local count = counts[chunk_key(center_x + dx, center_y + dy)] or 0
            if count > 0 then
                total = total + count * (coefficient ^ (math.abs(dx) + math.abs(dy)))
            end
        end
    end
    return total
end

local function candidate_score(candidate, player_counts, expansion)
    local player = influence(
        player_counts,
        candidate.x,
        candidate.y,
        expansion.enemy_building_influence_radius,
        expansion.neighbouring_chunk_coefficient
    ) * (tonumber(expansion.building_coefficient) or 0.1)

    -- Existing enemy bases deliberately contribute zero influence. Adjacent
    -- and already occupied chunks therefore keep the same base weight and can
    -- continue densifying until entity collision leaves no legal position.
    return 1 / (1 + player)
end

local function candidate_position(surface, chunk_x, chunk_y)
    local left = chunk_x * 32
    local top = chunk_y * 32
    -- Keep the initial structure wholly inside the candidate chunk. The
    -- engine's migration then decides the exact mix and placement of every
    -- spawner and worm produced by the arriving settlers.
    local box = {
        { left + 3, top + 3 },
        { left + 29, top + 29 },
    }
    local position = surface.find_non_colliding_position_in_box(
        "biter-spawner",
        box,
        1,
        true
    )
    if not position then return nil end
    local tile = surface.get_tile(position)
    if not (tile and tile.valid) or tile.name == "out-of-map" then return nil end
    return { x = position.x, y = position.y }
end

local function collect_candidates(surface, spawners, expansion)
    local maximum_distance = math.max(0, math.floor(tonumber(expansion.max_expansion_distance) or 7))
    if maximum_distance <= 0 then return {} end

    local by_key = {}
    local maximum_squared = maximum_distance * maximum_distance
    for _, spawner in pairs(spawners) do
        if spawner.valid then
            local source_x = math.floor(spawner.position.x / 32)
            local source_y = math.floor(spawner.position.y / 32)
            for dx = -maximum_distance, maximum_distance do
                for dy = -maximum_distance, maximum_distance do
                    if dx * dx + dy * dy <= maximum_squared then
                        local x = source_x + dx
                        local y = source_y + dy
                        local key = chunk_key(x, y)
                        if not by_key[key] and surface.is_chunk_generated { x, y } then
                            by_key[key] = { x = x, y = y }
                        end
                    end
                end
            end
        end
    end

    local candidates = {}
    for _, candidate in pairs(by_key) do candidates[#candidates + 1] = candidate end
    table.sort(candidates, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)

    local eligible = {}
    for _, candidate in ipairs(candidates) do
        local position = candidate_position(surface, candidate.x, candidate.y)
        if position and not inside_live_objective_radius(surface, position) then
            candidate.position = position
            eligible[#eligible + 1] = candidate
        end
    end
    return eligible
end

local function choose_weighted_candidate(surface, state, candidates, expansion)
    if #candidates == 0 then return nil end
    local player_counts = player_building_counts(surface)
    local total = 0
    for _, candidate in ipairs(candidates) do
        candidate.score = candidate_score(candidate, player_counts, expansion)
        total = total + candidate.score
    end
    if total <= 0 then return nil end

    local seed = tonumber(surface.map_gen_settings.seed) or 0
    local roll = hash.roll(seed, surface.index, state.sequence, TARGET_STREAM) * total
    local accumulated = 0
    for _, candidate in ipairs(candidates) do
        accumulated = accumulated + candidate.score
        if roll < accumulated then return candidate end
    end
    return candidates[#candidates]
end

local function prune_pending(state, tick)
    local kept = {}
    for _, target in ipairs(state.pending_targets or {}) do
        if tonumber(target.expires_tick) and target.expires_tick >= tick then
            kept[#kept + 1] = target
        end
    end
    state.pending_targets = kept
end

local function nearby_base_parts(surface, position)
    local parts = {}
    for _, kind in ipairs({ "unit-spawner", "turret" }) do
        for _, entity in pairs(surface.find_entities_filtered {
            type = kind, force = "enemy", position = position, radius = 48,
        }) do
            if entity.valid and entity.unit_number then parts[#parts + 1] = entity end
        end
    end
    return parts
end

function cave_enemy_expansion.protect_scripted_base_part(entity)
    if not bob_enemies.active() or not (entity and entity.valid and entity.unit_number
        and entity.surface) or (entity.type ~= "unit-spawner" and entity.type ~= "turret") then return end
    local value = storage[STORAGE_KEY]
    local state = value and value.surfaces and value.surfaces[entity.surface.index]
    if not state then return end
    for _, target in ipairs(state.pending_targets or {}) do
        if target.existing_parts then
            local dx, dy = entity.position.x - target.x, entity.position.y - target.y
            if dx * dx + dy * dy <= CUSTOM_TARGET_RADIUS_SQUARED then
                target.existing_parts[entity.unit_number] = true
            end
        end
    end
end

local function remember_custom_target(state, position, tick, nest_name, migration_group_id)
    prune_pending(state, tick)
    local record = {
        x = position.x,
        y = position.y,
        nest_name = nest_name,
        migration_group_id = migration_group_id,
        expires_tick = tick + PENDING_LIFETIME,
    }
    if bob_enemies.active() and nest_name then
        local migration = root().migration_groups[migration_group_id]
        local surface = migration and game.surfaces[migration.surface_index]
        if surface and surface.valid then
            record.existing_parts = {}
            for _, entity in ipairs(nearby_base_parts(surface, position)) do
                record.existing_parts[entity.unit_number] = true
            end
        end
    end
    state.pending_targets[#state.pending_targets + 1] = record
end

local function remove_pending_migration(value, surface_index, migration_group_id)
    local state = value.surfaces[surface_index]
    if not (state and state.pending_targets) then return end
    local kept = {}
    for _, target in ipairs(state.pending_targets) do
        if target.migration_group_id ~= migration_group_id then
            kept[#kept + 1] = target
        end
    end
    state.pending_targets = kept
end

local function matching_custom_target(state, position, tick)
    prune_pending(state, tick)
    local nearest, nearest_distance
    for _, target in ipairs(state.pending_targets) do
        local dx = position.x - target.x
        local dy = position.y - target.y
        local distance = dx * dx + dy * dy
        if distance <= CUSTOM_TARGET_RADIUS_SQUARED
            and (not nearest_distance or distance < nearest_distance) then
            nearest = target
            nearest_distance = distance
        end
    end
    return nearest
end

-- The native API accepts a destination rather than an explicit source nest.
-- The closest nest is therefore the deterministic parent of the migration.
-- Recognised Cave families reproduce their own family; unknown planetary
-- spawners retain Factorio's native random base mix for compatibility.
local function nearest_source_nest(spawners, position)
    local nearest, nearest_distance, nearest_number
    for _, spawner in pairs(spawners) do
        if spawner.valid then
            local dx = spawner.position.x - position.x
            local dy = spawner.position.y - position.y
            local distance = dx * dx + dy * dy
            local unit_number = tonumber(spawner.unit_number) or 0
            if not nearest_distance or distance < nearest_distance
                or (distance == nearest_distance and unit_number < nearest_number) then
                nearest = spawner
                nearest_distance = distance
                nearest_number = unit_number
            end
        end
    end
    return nearest
end

local function replace_custom_spawner(entity, desired_name)
    if not (entity and entity.valid and entity.type == "unit-spawner") then return false end
    if not desired_name or entity.name == desired_name then return true end
    local surface = entity.surface
    local spot = surface.find_non_colliding_position(desired_name, entity.position, 16, 0.5)
    if not spot then return false end
    local parameters = {
        name = desired_name,
        position = spot,
        force = entity.force,
    }
    if bob_enemies.active() then parameters.quality = entity.quality end
    local replacement = surface.create_entity(parameters)
    if not (replacement and replacement.valid) then return false end
    entity.destroy { raise_destroy = false }
    return true
end

-- Bob may replace an engine-created base part before our on_biter_base_built
-- handler sees it, leaving event.entity invalid. Reconcile only new parts in
-- our active migration's bounded destination, never a surface-wide scan.
-- The baseline also protects already-existing and neighbouring room nests.
local function reconcile_bob_target(surface, state, target)
    if not bob_enemies.active() or not target.existing_parts then return end
    local value = root()
    local migration = value.migration_groups[target.migration_group_id]
    if not migration then return end
    local breed = bob_enemies.nest_info(target.nest_name)
    for _, entity in ipairs(nearby_base_parts(surface, { x = target.x, y = target.y })) do
        if not target.existing_parts[entity.unit_number] then
            local owner, nearest
            for _, candidate in ipairs(state.pending_targets or {}) do
                if candidate.existing_parts and candidate.nest_name
                    and value.migration_groups[candidate.migration_group_id]
                    and not candidate.existing_parts[entity.unit_number] then
                    local dx, dy = entity.position.x - candidate.x, entity.position.y - candidate.y
                    local distance = dx * dx + dy * dy
                    if distance <= CUSTOM_TARGET_RADIUS_SQUARED and (not nearest or distance < nearest
                        or (distance == nearest and candidate.migration_group_id < owner.migration_group_id)) then
                        owner, nearest = candidate, distance
                    end
                end
            end
            if owner == target then
                local old_number = entity.unit_number
                target.existing_parts[old_number] = true
                if entity.type == "unit-spawner" then
                    migration.built_any_part = true
                    if entity.name ~= target.nest_name then
                        local spot = surface.find_non_colliding_position(target.nest_name, entity.position, 16, 0.5)
                        local replacement = spot and surface.create_entity {
                            name = target.nest_name, position = spot, force = entity.force, quality = entity.quality,
                        }
                        if replacement and replacement.valid then
                            target.existing_parts[replacement.unit_number] = true
                            entity.destroy { raise_destroy = false }
                        else target.existing_parts[old_number] = nil end
                    end
                elseif breed then
                    local info = bob_enemies.unit_info(entity.name)
                    if info and info.kind == "worm-turret" then
                        migration.built_any_part = true
                        local name = bob_enemies.pick_worm(breed.breed, cave_evolution.factor(surface),
                            hash.roll(surface.map_gen_settings.seed, target.migration_group_id, old_number, TARGET_STREAM + 71))
                        if name and entity.name ~= name then
                            local spot = surface.find_non_colliding_position(name, entity.position, 4, 0.5)
                            local replacement = spot and surface.create_entity {
                                name = name, position = spot, force = entity.force, quality = entity.quality,
                            }
                            if replacement and replacement.valid then
                                target.existing_parts[replacement.unit_number] = true
                                entity.destroy { raise_destroy = false }
                            else target.existing_parts[old_number] = nil end
                        end
                    end
                end
            end
        end
    end
end

local function reconcile_bob_migrations(surface_index)
    if not bob_enemies.active() then return end
    local value = root()
    for index, state in pairs(value.surfaces) do
        local surface = game.surfaces[index]
        if (not surface_index or index == surface_index) and surface and surface.valid then
            for _, target in ipairs(state.pending_targets or {}) do
                if value.migration_groups[target.migration_group_id] then
                    reconcile_bob_target(surface, state, target)
                end
            end
        end
    end
end

local function valid_entity(entity)
    return entity and entity.valid
end

local function is_wave_unit(entity)
    return valid_entity(entity) and type(entity.name) == "string"
        and entity.name:sub(1, #WAVE_UNIT_PREFIX) == WAVE_UNIT_PREFIX
end

local function unit_commandable(entity)
    if not valid_entity(entity) then return nil end
    local commandable = nil
    pcall(function() commandable = entity.commandable end)
    return commandable and commandable.valid and commandable or nil
end

local function set_unit_command(entity, command)
    local commandable = unit_commandable(entity)
    if commandable then
        local ok = pcall(function() commandable.set_command(command) end)
        if ok then return true end
    end
    local commanded = false
    pcall(function()
        if entity and entity.set_command then
            entity.set_command(command)
            commanded = true
        end
    end)
    return commanded
end

local function command_normal_combat(entity)
    if not valid_entity(entity) then return false end
    return set_unit_command(entity, {
        type = defines.command.attack_area,
        destination = { x = entity.position.x, y = entity.position.y },
        radius = 32,
        distraction = defines.distraction.by_enemy,
    })
end

local function available_expansion_settler(entity, surface, enemy_force, attackers)
    if not (valid_entity(entity) and entity.type == "unit" and entity.unit_number
        and entity.surface == surface and entity.force == enemy_force)
        or is_wave_unit(entity) or enemy_nest_growth.is_active_queen(entity)
        or attackers[entity.unit_number]
        or inside_live_objective_radius(surface, entity.position) then
        return false
    end

    local commandable = unit_commandable(entity)
    if not commandable then return false end
    local parent_group = nil
    local spawner = nil
    pcall(function() parent_group = commandable.parent_group end)
    pcall(function() spawner = commandable.spawner end)
    return parent_group == nil and valid_entity(spawner)
        and spawner.type == "unit-spawner" and spawner.force == enemy_force
end

-- Build the migration only from real, currently available spawner-owned units.
-- Explicit membership is the ownership boundary: Wave units, active Queens and
-- enemies already committed to an objective can never enter this group.
local function filtered_expansion_units(surface, source, count, expansion, attackers)
    local maximum_distance = math.max(0,
        math.floor(tonumber(expansion.max_expansion_distance) or 7))
    local search_radius = math.max(64, (maximum_distance + 1) * 32)
    local enemy_force = game.forces.enemy
    local candidates = surface.find_entities_filtered {
        position = source.position,
        radius = search_radius,
        type = "unit",
        force = enemy_force,
    }
    local eligible = {}
    for _, entity in pairs(candidates) do
        if available_expansion_settler(entity, surface, enemy_force, attackers) then
            local dx = entity.position.x - source.position.x
            local dy = entity.position.y - source.position.y
            eligible[#eligible + 1] = {
                entity = entity,
                distance = dx * dx + dy * dy,
            }
        end
    end
    table.sort(eligible, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.entity.unit_number < b.entity.unit_number
    end)
    if #eligible < count then return {} end

    local selected = {}
    for index = 1, count do selected[index] = eligible[index].entity end
    return selected
end

local function destroy_group(group)
    pcall(function()
        if group and group.valid then group.destroy() end
    end)
end

local function group_valid(group)
    local ok, valid = pcall(function() return group and group.valid end)
    return ok and valid == true
end

local function cleanup_migration_group(value, group_id)
    local record = value.migration_groups[group_id]
    if not record then return end
    if bob_enemies.active() then reconcile_bob_migrations(record.surface_index) end
    destroy_group(record.group)
    value.migration_groups[group_id] = nil
    if not record.built_any_part then
        remove_pending_migration(value, record.surface_index, group_id)
    end
end

local function cleanup_all_migration_groups(value)
    local ids = {}
    for group_id in pairs(value.migration_groups or {}) do
        if type(group_id) == "number" then ids[#ids + 1] = group_id end
    end
    table.sort(ids)
    for _, group_id in ipairs(ids) do cleanup_migration_group(value, group_id) end
end

local function sweep_migration_groups(value, tick)
    local ids = {}
    for group_id in pairs(value.migration_groups or {}) do
        if type(group_id) == "number" then ids[#ids + 1] = group_id end
    end
    table.sort(ids)
    for _, group_id in ipairs(ids) do
        local record = value.migration_groups[group_id]
        if record then
            if not group_valid(record.group) then
                if bob_enemies.active() then reconcile_bob_migrations(record.surface_index) end
                value.migration_groups[group_id] = nil
                if not record.built_any_part then
                    remove_pending_migration(value, record.surface_index, group_id)
                end
            elseif tick >= (tonumber(record.expires_tick) or 0) then
                cleanup_migration_group(value, group_id)
            end
        end
    end
end

local function dispatch_filtered_expansion(
    surface, source, destination, count, expansion, tick)
    local value = root()
    local enemy_force = game.forces.enemy
    local candidates = filtered_expansion_units(
        surface, source, count, expansion, value.objective_attackers)
    if #candidates < count then return false end

    local group = nil
    local created = pcall(function()
        group = surface.create_unit_group {
            position = { x = source.position.x, y = source.position.y },
            force = enemy_force,
        }
    end)
    if not created or not (group and group.valid) then return false end

    local group_id = nil
    pcall(function() group_id = group.unique_id end)
    if type(group_id) ~= "number" then
        destroy_group(group)
        return false
    end

    local members = {}
    local membership_ok = true
    for _, entity in ipairs(candidates) do
        -- Recheck immediately before mutation because another synchronous event
        -- may have invalidated or reassigned a candidate while the group formed.
        if available_expansion_settler(
            entity, surface, enemy_force, value.objective_attackers) then
            local commandable = unit_commandable(entity)
            local unit_number = entity.unit_number
            local added = pcall(function() group.add_member(entity) end)
            local parent_group = nil
            pcall(function() parent_group = commandable.parent_group end)
            if parent_group == group then
                members[#members + 1] = {
                    entity = entity,
                    unit_number = unit_number,
                }
            end
            if not added or parent_group ~= group then
                membership_ok = false
                break
            end
        else
            membership_ok = false
            break
        end
    end

    -- One last aggregate check catches a synchronous group event which moved
    -- an earlier member while a later member was being added.
    if membership_ok then
        for _, member in ipairs(members) do
            local entity = member.entity
            local commandable = unit_commandable(entity)
            local parent_group = nil
            if commandable then pcall(function() parent_group = commandable.parent_group end) end
            if not commandable or parent_group ~= group or is_wave_unit(entity)
                or enemy_nest_growth.is_active_queen(entity)
                or value.objective_attackers[member.unit_number] then
                membership_ok = false
                break
            end
        end
    end

    if not membership_ok or #members < count then
        -- Factorio restores each member's pre-group command when this temporary
        -- group is destroyed; no ordinary unit is destroyed by the rollback.
        destroy_group(group)
        return false
    end

    -- A build_base command given to an empty group fails on its first AI
    -- update. Set it only after every member has joined and passed the final
    -- aggregate ownership check above.
    local command_set = pcall(function()
        group.set_command {
            type = defines.command.build_base,
            destination = { x = destination.x, y = destination.y },
            distraction = defines.distraction.by_enemy,
            ignore_planner = true,
        }
    end)
    local assigned_command = nil
    if command_set then pcall(function() assigned_command = group.command end) end
    if not command_set or type(assigned_command) ~= "table"
        or assigned_command.type ~= defines.command.build_base then
        destroy_group(group)
        return false
    end

    value.migration_groups[group_id] = {
        group = group,
        surface_index = surface.index,
        expires_tick = tick + PENDING_LIFETIME,
        built_any_part = false,
    }
    local started = pcall(function() group.start_moving() end)
    if not started then
        cleanup_migration_group(value, group_id)
        return false
    end

    -- start_moving is the commit point. Only a successfully dispatched group
    -- releases its selected units from their original spawners.
    for _, member in ipairs(members) do
        local entity = member.entity
        local commandable = unit_commandable(entity)
        local parent_group = nil
        if commandable then pcall(function() parent_group = commandable.parent_group end) end
        if commandable and parent_group == group
            and not value.objective_attackers[member.unit_number] then
            pcall(function() commandable.release_from_spawner() end)
        end
    end
    return group_id
end

local function attempt_expansion(surface, state, tick)
    local expansion = game.map_settings.enemy_expansion
    local spawners = enemy_spawners(surface)
    if #spawners == 0 then return false end

    local candidates = collect_candidates(surface, spawners, expansion)
    local target = choose_weighted_candidate(surface, state, candidates, expansion)
    if not target then return false end

    local source = nearest_source_nest(spawners, target.position)
    local source_family = source and enemy_nest_growth.nest_family_for_name(source.name) or nil
    local desired_nest = source_family and enemy_nest_growth.nest_name_for_family(source_family, surface) or nil
    if desired_nest then
        -- Validate the parent family's real footprint before dispatching the
        -- native settlers. This matters especially for the wider Snapper nest.
        local family_spot = surface.find_non_colliding_position(
            desired_nest, target.position, 16, 0.5
        )
        if not family_spot then return false end
        target.position = { x = family_spot.x, y = family_spot.y }
    end
    if inside_live_objective_radius(surface, target.position) then return false end

    -- Real enemies walk to the selected Cave floor and sacrifice themselves.
    -- Unlike LuaSurface.build_enemy_base, membership is explicit and therefore
    -- cannot capture private Wave Defense units.
    local migration_group_id = dispatch_filtered_expansion(
        surface,
        source,
        target.position,
        vanilla_group_size(surface),
        expansion,
        tick
    )
    if migration_group_id then
        remember_custom_target(
            state, target.position, tick, desired_nest, migration_group_id)
    end
    return type(migration_group_id) == "number"
end

local function schedule_next(surface, state, tick)
    state.next_tick = tick + cave_cooldown(surface)
end

local function main_cave_surfaces()
    local surfaces = {}
    for _, surface in pairs(game.surfaces) do
        if is_main_cave_surface(surface) then surfaces[#surfaces + 1] = surface end
    end
    table.sort(surfaces, function(a, b) return a.index < b.index end)
    return surfaces
end

local function sorted_unit_numbers(records)
    local values = {}
    for unit_number in pairs(records or {}) do
        if type(unit_number) == "number" then values[#values + 1] = unit_number end
    end
    table.sort(values)
    return values
end

-- Resolve exactly one force-local Train or Shelter objective. Sorting and the
-- overlap tie-break below keep multiplayer peers deterministic.
local function collect_objectives()
    local objectives = {}
    local seen_forces = {}
    if not objective_api then return objectives, {}, {}, {} end

    for _, force in pairs(game.forces) do
        if force and force.valid and force.name ~= "enemy" and force.name ~= "neutral"
            and not seen_forces[force.index] then
            seen_forces[force.index] = true
            local ok, entity = pcall(objective_api.get_objective, force)
            if ok and valid_entity(entity) and entity.unit_number
                and entity.force == force and entity.surface and entity.surface.valid
                and (entity.type == "locomotive" or entity.name == "the-cave-shelter")
                and is_main_cave_surface(entity.surface) then
                objectives[#objectives + 1] = {
                    entity = entity,
                    force = force,
                    force_index = force.index,
                    force_name = force.name,
                }
            end
        end
    end
    table.sort(objectives, function(a, b) return a.force_index < b.force_index end)

    local by_force_index = {}
    local by_force_name = {}
    local by_objective_unit = {}
    for _, objective in ipairs(objectives) do
        by_force_index[objective.force_index] = objective
        by_force_name[objective.force_name] = objective
        by_objective_unit[objective.entity.unit_number] = objective
    end
    return objectives, by_force_index, by_force_name, by_objective_unit
end

local function destroy_render(object)
    pcall(function()
        if object and object.valid then object.destroy() end
    end)
end

local function destroy_all_objective_renders(value)
    for force_index, record in pairs(value.objective_renders or {}) do
        destroy_render(record and record.object)
        value.objective_renders[force_index] = nil
    end
end

local function command_objective_attack(unit, target)
    if not (valid_entity(unit) and valid_entity(target)
        and unit.surface == target.surface) then
        return false
    end
    return set_unit_command(unit, {
        type = defines.command.attack,
        target = target,
        distraction = defines.distraction.none,
    })
end

local function protect_objective_ai(unit, previous)
    local original_join = previous and previous.original_join_attacks
    local original_return = previous and previous.original_allow_try_return_to_spawner
    local original_destroy = previous and previous.original_allow_destroy_when_commands_fail
    pcall(function()
        local ai = unit.ai_settings
        if ai then
            if original_join == nil then original_join = ai.join_attacks end
            if original_return == nil then
                original_return = ai.allow_try_return_to_spawner
            end
            if original_destroy == nil then
                original_destroy = ai.allow_destroy_when_commands_fail
            end
            ai.join_attacks = false
            ai.allow_try_return_to_spawner = false
            ai.allow_destroy_when_commands_fail = false
        end
    end)
    return original_join, original_return, original_destroy
end

local function restore_objective_ai(unit, record)
    pcall(function()
        local ai = unit.ai_settings
        if ai then
            if type(record.original_join_attacks) == "boolean" then
                ai.join_attacks = record.original_join_attacks
            end
            if type(record.original_allow_try_return_to_spawner) == "boolean" then
                ai.allow_try_return_to_spawner =
                    record.original_allow_try_return_to_spawner
            end
            if type(record.original_allow_destroy_when_commands_fail) == "boolean" then
                ai.allow_destroy_when_commands_fail =
                    record.original_allow_destroy_when_commands_fail
            end
        end
    end)
end

local function assign_objective_attacker(records, unit, objective, tick)
    if not (valid_entity(unit) and unit.unit_number and objective
        and valid_entity(objective.entity))
        or is_wave_unit(unit) or enemy_nest_growth.is_active_queen(unit) then
        return false
    end
    if not enemy_nest_growth.claim_objective_attacker(unit) then return false end

    local previous = records[unit.unit_number]
    local original_join, original_return, original_destroy =
        protect_objective_ai(unit, previous)
    if not command_objective_attack(unit, objective.entity) then
        if previous then
            restore_objective_ai(unit, previous)
        else
            restore_objective_ai(unit, {
                original_join_attacks = original_join,
                original_allow_try_return_to_spawner = original_return,
                original_allow_destroy_when_commands_fail = original_destroy,
            })
        end
        command_normal_combat(unit)
        return false
    end

    records[unit.unit_number] = {
        entity = unit,
        target = objective.entity,
        force_index = objective.force_index,
        force_name = objective.force_name,
        surface_index = unit.surface.index,
        next_command_tick = tick + OBJECTIVE_COMMAND_REFRESH,
        original_join_attacks = original_join,
        original_allow_try_return_to_spawner = original_return,
        original_allow_destroy_when_commands_fail = original_destroy,
    }
    return true
end

local function current_objective(
    record, unit, by_force_index, by_force_name, by_objective_unit)
    if type(record) ~= "table" or not valid_entity(unit) then return nil end
    local objective = record.force_index and by_force_index[record.force_index] or nil
    if not objective and record.force_name then objective = by_force_name[record.force_name] end
    if not objective and valid_entity(record.target) and record.target.unit_number then
        objective = by_objective_unit[record.target.unit_number]
    end
    if objective and valid_entity(objective.entity)
        and objective.entity.surface == unit.surface then
        return objective
    end
    return nil
end

local function process_existing_attackers(
    records, by_force_index, by_force_name, by_objective_unit, tick)
    for _, unit_number in ipairs(sorted_unit_numbers(records)) do
        local record = records[unit_number]
        local unit = record and record.entity
        if not (valid_entity(unit) and unit.type == "unit"
            and unit.unit_number == unit_number and unit.force and unit.force.valid
            and unit.force.name == "enemy") then
            records[unit_number] = nil
        elseif is_wave_unit(unit) or enemy_nest_growth.is_active_queen(unit) then
            -- A provisional save may have captured one of these. Drop only our
            -- stale ownership; their original controller restores its command.
            restore_objective_ai(unit, record)
            records[unit_number] = nil
        else
            local objective = current_objective(
                record, unit, by_force_index, by_force_name, by_objective_unit)
            if not objective then
                restore_objective_ai(unit, record)
                command_normal_combat(unit)
                records[unit_number] = nil
            elseif objective.entity ~= record.target
                or objective.force_index ~= record.force_index
                or objective.force_name ~= record.force_name
                or tick >= (tonumber(record.next_command_tick) or 0) then
                if not assign_objective_attacker(records, unit, objective, tick) then
                    records[unit_number] = nil
                end
            end
        end
    end
end

local function acquire_nearby_attackers(records, objectives, tick)
    local candidates = {}
    for _, objective in ipairs(objectives) do
        local target = objective.entity
        for _, unit in pairs(target.surface.find_entities_filtered {
            position = target.position,
            radius = OBJECTIVE_RADIUS,
            type = "unit",
            force = "enemy",
        }) do
            if valid_entity(unit) and unit.unit_number and not records[unit.unit_number]
                and not is_wave_unit(unit) and not enemy_nest_growth.is_active_queen(unit) then
                local dx = unit.position.x - target.position.x
                local dy = unit.position.y - target.position.y
                local distance = dx * dx + dy * dy
                if distance <= OBJECTIVE_RADIUS_SQUARED then
                    local existing = candidates[unit.unit_number]
                    if not existing or distance < existing.distance
                        or distance == existing.distance
                            and objective.force_index < existing.objective.force_index then
                        candidates[unit.unit_number] = {
                            unit = unit,
                            objective = objective,
                            distance = distance,
                        }
                    end
                end
            end
        end
    end

    for _, unit_number in ipairs(sorted_unit_numbers(candidates)) do
        local candidate = candidates[unit_number]
        assign_objective_attacker(
            records, candidate.unit, candidate.objective, tick)
    end
end

local function release_objective_attackers(value)
    local records = value.objective_attackers or {}
    for _, unit_number in ipairs(sorted_unit_numbers(records)) do
        local record = records[unit_number]
        local unit = record and record.entity
        if valid_entity(unit) and not is_wave_unit(unit)
            and not enemy_nest_growth.is_active_queen(unit) then
            restore_objective_ai(unit, record)
            command_normal_combat(unit)
        end
        records[unit_number] = nil
    end
end

local function update_objective_control(value, tick)
    if not setting_enabled() then
        release_objective_attackers(value)
        destroy_all_objective_renders(value)
        return
    end

    local objectives, by_force_index, by_force_name, by_objective_unit =
        collect_objectives()
    -- 3.1.65 removes the visible objective circle. Clear render handles left
    -- by 3.1.64 while keeping the invisible 200-tile controller unchanged.
    destroy_all_objective_renders(value)
    process_existing_attackers(
        value.objective_attackers,
        by_force_index,
        by_force_name,
        by_objective_unit,
        tick
    )
    acquire_nearby_attackers(value.objective_attackers, objectives, tick)
end

local function command_print(command, message)
    local player = command.player_index and game.get_player(command.player_index) or nil
    if player and player.valid then player.print(message) else game.print(message) end
end

local function expansion_enabled()
    return setting_enabled()
end

local function test_status(command, surfaces)
    local enabled_text = expansion_enabled()
        and { "the-cave-enemy-expansion.enabled" }
        or { "the-cave-enemy-expansion.disabled" }
    for _, surface in ipairs(surfaces) do
        local state = root().surfaces[surface.index]
        local remaining_text = { "the-cave-enemy-expansion.not-scheduled" }
        if state and tonumber(state.next_tick) then
            local remaining_seconds = math.max(0, math.ceil((state.next_tick - game.tick) / 60))
            remaining_text = { "the-cave-enemy-expansion.seconds", remaining_seconds }
        end
        command_print(command, {
            "the-cave-enemy-expansion.test-status",
            surface.name,
            string.format("%.1f", evolution_for(surface) * 100),
            surface.count_entities_filtered { type = "unit-spawner", force = "enemy" },
            remaining_text,
            enabled_text,
        })
    end
end

local function test_command(command)
    local player = command.player_index and game.get_player(command.player_index) or nil
    if player and not player.admin then
        player.print({ "the-cave-enemy-expansion.admin-only" })
        return
    end

    local surfaces = main_cave_surfaces()
    if #surfaces == 0 then
        command_print(command, { "the-cave-enemy-expansion.no-surface" })
        return
    end

    local parameter = (command.parameter or "status"):match("^%s*(.-)%s*$")
    if parameter == "" or parameter:lower() == "status" then
        test_status(command, surfaces)
        return
    end

    local percent = tonumber(parameter)
    if not percent or percent < 0 or percent > 100 then
        command_print(command, { "the-cave-enemy-expansion.command-help" })
        return
    end

    local factor = percent / 100
    local rounded_percent = string.format("%.1f", percent)
    for _, surface in ipairs(surfaces) do
        game.forces.enemy.set_evolution_factor(factor, surface)
        local state = state_for(surface)
        schedule_next(surface, state, game.tick)
        command_print(command, {
            "the-cave-enemy-expansion.test-set",
            surface.name,
            rounded_percent,
            math.ceil((state.next_tick - game.tick) / 60),
            surface.count_entities_filtered { type = "unit-spawner", force = "enemy" },
        })
    end
    cave_evolution.sync_all()

    if not expansion_enabled() then
        command_print(command, { "the-cave-enemy-expansion.disabled-warning" })
    end
end

function cave_enemy_expansion.register_commands()
    commands.add_command(
        "the-cave-expansion-test",
        { "the-cave-enemy-expansion.command-help" },
        test_command
    )
end

function cave_enemy_expansion.on_init(reset_state)
    if reset_state then
        local old = storage[STORAGE_KEY]
        if type(old) == "table" then
            old.surfaces = old.surfaces or {}
            old.objective_renders = old.objective_renders or {}
            old.migration_groups = old.migration_groups or {}
            destroy_all_objective_renders(old)
            cleanup_all_migration_groups(old)
        end
        storage[STORAGE_KEY] = nil
    end
    local value = root()
    disable_unfiltered_engine_planner()
    apply_attack_pollution_cost()
    update_objective_control(value, game.tick)
end

function cave_enemy_expansion.on_configuration_changed()
    local value = root()
    for surface_index in pairs(value.surfaces) do
        local surface = game.surfaces[surface_index]
        if not (surface and surface.valid) then value.surfaces[surface_index] = nil end
    end
    sweep_migration_groups(value, game.tick)
    if not setting_enabled() then
        cleanup_all_migration_groups(value)
        value.surfaces = {}
    end
    disable_unfiltered_engine_planner()
    apply_attack_pollution_cost()
    update_objective_control(value, game.tick)
end

function cave_enemy_expansion.on_setting_changed()
    local value = root()
    -- Enabling starts a fresh Cave cooldown; disabling discards all Cave
    -- fallback timers and pending migration bookkeeping immediately.
    if not setting_enabled() then cleanup_all_migration_groups(value) end
    value.surfaces = {}
    disable_unfiltered_engine_planner()
    apply_attack_pollution_cost()
    update_objective_control(value, game.tick)
end

function cave_enemy_expansion.on_objective_nth_tick(event)
    if not (event and event.tick and event.tick % OBJECTIVE_INTERVAL == 0) then return end
    update_objective_control(root(), event.tick)
end

function cave_enemy_expansion.on_nth_tick(event)
    if not (event and event.tick and event.tick % CHECK_INTERVAL == 0) then return end
    disable_unfiltered_engine_planner()
    local value = root()
    sweep_migration_groups(value, event.tick)
    local expansion = game.map_settings.enemy_expansion
    if not setting_enabled() then return end

    for _, surface in pairs(game.surfaces) do
        if is_main_cave_surface(surface) then
            local state = state_for(surface)
            prune_pending(state, event.tick)
            if not state.next_tick then
                schedule_next(surface, state, event.tick)
            elseif event.tick >= state.next_tick then
                -- Expansion consumes the global attempt even when no suitable
                -- candidate or migration can be produced, so advance first.
                state.sequence = state.sequence + 1
                schedule_next(surface, state, event.tick)
                attempt_expansion(surface, state, event.tick)
            end
        end
    end
end

function cave_enemy_expansion.on_biter_base_built(event)
    local entity = event and event.entity
    if bob_enemies.active() then reconcile_bob_migrations() end
    if not (entity and entity.valid and entity.surface and is_main_cave_surface(entity.surface)) then return end
    local state = state_for(entity.surface)

    -- Parts created by our filtered build_base migration already have a
    -- dispatch-based Cave cooldown. Rebuild only its spawner parts as the
    -- source family; worms and other native base parts remain untouched.
    local custom_target = matching_custom_target(state, entity.position, event.tick)
    if custom_target then
        local group_id = custom_target.migration_group_id
        local migration = group_id and root().migration_groups[group_id] or nil
        if migration then migration.built_any_part = true end
        if custom_target.nest_name and entity.type == "unit-spawner" then
            replace_custom_spawner(entity, custom_target.nest_name)
        end
        return
    end

    -- A genuinely vanilla Cave migration resets the fallback timer so the two
    -- planners cannot double-expand.
    if state.last_native_build_tick
        and event.tick - state.last_native_build_tick <= 600
        and state.last_native_build_position then
        local dx = entity.position.x - state.last_native_build_position.x
        local dy = entity.position.y - state.last_native_build_position.y
        if dx * dx + dy * dy <= CUSTOM_TARGET_RADIUS_SQUARED then return end
    end

    state.last_native_build_tick = event.tick
    state.last_native_build_position = { x = entity.position.x, y = entity.position.y }
    schedule_next(entity.surface, state, event.tick)
end

function cave_enemy_expansion.on_surface_deleted(event)
    if not (event and event.surface_index) then return end
    local value = root()
    local group_ids = {}
    for group_id, record in pairs(value.migration_groups) do
        if record and record.surface_index == event.surface_index then
            group_ids[#group_ids + 1] = group_id
        end
    end
    table.sort(group_ids)
    for _, group_id in ipairs(group_ids) do
        cleanup_migration_group(value, group_id)
    end
    value.surfaces[event.surface_index] = nil
    for unit_number, record in pairs(value.objective_attackers) do
        if record and record.surface_index == event.surface_index then
            value.objective_attackers[unit_number] = nil
        end
    end
    for force_index, record in pairs(value.objective_renders) do
        if record and record.surface_index == event.surface_index then
            destroy_render(record.object)
            value.objective_renders[force_index] = nil
        end
    end
end

function cave_enemy_expansion.on_ai_command_completed(event)
    if not (event and event.unit_number) or event.was_distracted then return end
    local value = root()
    if value.migration_groups[event.unit_number] then
        -- build_base reports fail even after successfully sacrificing its last
        -- member and creating base parts. The per-group built flag controls only
        -- pending-target cleanup; any surviving completed group is disbanded.
        cleanup_migration_group(value, event.unit_number)
    end
end

function cave_enemy_expansion.on_entity_died(event)
    local entity = event and event.entity
    if entity and entity.valid and entity.unit_number then
        root().objective_attackers[entity.unit_number] = nil
    end
end

return cave_enemy_expansion
