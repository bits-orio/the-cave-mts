local cave_worlds = require("scripts.cave_worlds")
local cave_teams = require("scripts.cave_teams")
-- Shared controller for The Cave's scripted enemy ecology:
--   * direct-dig survivors can found a same-family nest;
--   * direct-dig worms mature into one weighted random nest after one minute;
--   * one passive Arachnid Queen per depth zone travels between opened rooms,
--     excavates frontier cover when needed, lays up to three weighted nests,
--     rests five minutes, and repeats.
--
-- None of these nests receive autoplace. Once created, they are ordinary enemy
-- spawners and therefore participate in the existing Cave expansion adapter.
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local game_settings = require("scripts.game_settings")
local bob_enemies = require("scripts.bob_enemies")

local growth = {}

local STORAGE_KEY = "the_cave_enemy_nest_growth"
local STORAGE_VERSION = 1
local TICKS_PER_SECOND = 60
local WORM_MATURATION_TICKS = 60 * TICKS_PER_SECOND
local QUEEN_REGEN_DELAY = 30 * TICKS_PER_SECOND
local QUEEN_REST_TICKS = 5 * 60 * TICKS_PER_SECOND
local NO_DESTINATION_RETRY = 30 * TICKS_PER_SECOND
local SHORT_RETRY = 5 * TICKS_PER_SECOND
local SETTLER_INITIAL_COMBAT = 1 * TICKS_PER_SECOND
local SETTLER_STUCK_TICKS = 2 * 60 * TICKS_PER_SECOND
local QUEEN_STUCK_TICKS = 45 * TICKS_PER_SECOND
local QUEEN_DIG_STUCK_TICKS = 45 * TICKS_PER_SECOND
local QUEEN_DIG_AVOID_TICKS = 2 * 60 * TICKS_PER_SECOND
local QUEEN_DIG_SEARCH_RADIUS = 96
local QUEEN_DIG_CANDIDATE_LIMIT = 2048
local QUEEN_DIG_BUILDING_CLEARANCE = 16
local QUEEN_COVER_DAMAGE_MULTIPLIER = 2
local QUEEN_START_SAFE_RADIUS = 200
local QUEEN_HEALTH_MIGRATION_VERSION = 1
local QUEEN_START_SAFE_RADIUS_SQUARED = QUEEN_START_SAFE_RADIUS * QUEEN_START_SAFE_RADIUS
local QUEEN_NEST_CAP = 25
local QUEEN_POPULATION_RECHECK_TICKS = 5 * TICKS_PER_SECOND
local REISSUE_TICKS = 10 * TICKS_PER_SECOND
local ARRIVAL_RADIUS_SQUARED = 5 * 5
local DIFFERENT_ROOM_RADIUS_SQUARED = 24 * 24
local TARGET_STREAM = 62100
local WORM_FAMILY_STREAM = 62200
local QUEEN_FAMILY_STREAM = 62300

local FAMILY_NESTS = {
    biter = "biter-spawner",
    spitter = "spitter-spawner",
    snapper = "armoured-biter-spawner",
    arachnid = "arachnid-spawner-unitspawner",
}

local NEST_FAMILIES = {}
for family, name in pairs(FAMILY_NESTS) do NEST_FAMILIES[name] = family end

local FAMILY_NEST_NAMES = {}
for _, name in pairs(FAMILY_NESTS) do FAMILY_NEST_NAMES[#FAMILY_NEST_NAMES + 1] = name end
for _, name in ipairs(bob_enemies.nest_names()) do FAMILY_NEST_NAMES[#FAMILY_NEST_NAMES + 1] = name end
table.sort(FAMILY_NEST_NAMES)

local QUEEN_LEVELS = {
    easy = 1,
    medium = 1,
    hard = 2,
    nightmare = 3,
}

local QUEEN_NAMES = {}
for level = 1, 10 do
    QUEEN_NAMES[#QUEEN_NAMES + 1] = "maf-boss-arachnid-biter-" .. tostring(level)
end

local QUEEN_NAME_SET = {}
for _, name in ipairs(QUEEN_NAMES) do QUEEN_NAME_SET[name] = true end

local ZONE_ORDER = { "easy", "medium", "hard", "nightmare" }

-- Bound by control.lua after all modules are loaded. Keeping the function out
-- of storage makes it safe across save/load while letting Train Interiors own
-- the immutable first-train reference.
local start_anchor_api

function growth.configure_start_anchor_api(api)
    assert(type(api) == "table" and type(api.get_start_anchor) == "function",
        "enemy_nest_growth start-anchor API requires get_start_anchor(surface)")
    start_anchor_api = api
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

local function distance_squared(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

local function outside_queen_start_zone(anchor, position)
    return anchor and position
        and distance_squared(anchor, position) >= QUEEN_START_SAFE_RADIUS_SQUARED
end

-- Reject destinations whose direct route cuts through the protected start
-- circle. Factorio may still choose a curved path, so process_queen also keeps
-- a live last-safe-position guard as a second line of defence.
local function segment_outside_queen_start_zone(anchor, from, destination)
    if not outside_queen_start_zone(anchor, from)
        or not outside_queen_start_zone(anchor, destination) then
        return false
    end
    local dx = destination.x - from.x
    local dy = destination.y - from.y
    local length_squared = dx * dx + dy * dy
    if length_squared <= 0 then return true end
    local t = ((anchor.x - from.x) * dx + (anchor.y - from.y) * dy) / length_squared
    t = math.max(0, math.min(1, t))
    local nearest = { x = from.x + dx * t, y = from.y + dy * t }
    return distance_squared(anchor, nearest) >= QUEEN_START_SAFE_RADIUS_SQUARED
end

local function root()
    local value = storage[STORAGE_KEY]
    if type(value) ~= "table" or value.version ~= STORAGE_VERSION then
        value = {
            version = STORAGE_VERSION,
            surfaces = {},
            next_worm_tick = nil,
        }
        storage[STORAGE_KEY] = value
    end
    value.surfaces = value.surfaces or {}
    return value
end

local function state_for(surface)
    local value = root()
    local state = value.surfaces[surface.index]
    if type(state) ~= "table" then
        state = {
            settlers = {},
            worms = {},
            queens = {},
        }
        value.surfaces[surface.index] = state
    end
    state.settlers = state.settlers or {}
    state.worms = state.worms or {}
    state.queens = state.queens or {}
    return state
end

local function queen_start_anchor(surface, state)
    local existing = copy_position(state.queen_start_anchor)
    if existing then
        state.queen_start_anchor = existing
        return existing
    end

    local anchor
    if start_anchor_api then
        local ok, result = pcall(start_anchor_api.get_start_anchor, surface)
        if ok then anchor = copy_position(result) end
    end
    -- The ordinary Cave start is at the Force spawn. The injected provider is
    -- expected to supply it; zero is a conservative compatibility fallback.
    anchor = anchor or { x = 0, y = 0 }
    state.queen_start_anchor = copy_position(anchor)
    return anchor
end

function growth.capture_start_anchor(surface)
    if not (surface and surface.valid) then return nil end
    if not growth.is_main_cave_surface(surface) then return nil end
    return copy_position(queen_start_anchor(surface, state_for(surface)))
end

local function refresh_queen_nest_counts(surface, state, tick)
    local counts = { easy = 0, medium = 0, hard = 0, nightmare = 0 }
    for _, nest in pairs(surface.find_entities_filtered {
        name = FAMILY_NEST_NAMES,
        force = "enemy",
    }) do
        if nest and nest.valid then
            local level = depth_levels.level_for_surface_position(surface, nest.position)
            if level and counts[level.id] ~= nil then
                counts[level.id] = counts[level.id] + 1
            end
        end
    end
    state.queen_nest_counts = counts
    state.queen_nest_counts_tick = tick
    return counts
end

local function queen_zone_nest_count(surface, state, zone_id, tick, force_refresh)
    local counts = state.queen_nest_counts
    local counted_tick = tonumber(state.queen_nest_counts_tick)
    if force_refresh or type(counts) ~= "table" or not counted_tick
        or tick - counted_tick >= QUEEN_POPULATION_RECHECK_TICKS then
        counts = refresh_queen_nest_counts(surface, state, tick)
    end
    return tonumber(counts[zone_id]) or 0
end

local function sorted_numeric_keys(values)
    local keys = {}
    for key in pairs(values or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
    return keys
end

local function sorted_surface_indexes(states)
    return sorted_numeric_keys(states)
end

function growth.is_main_cave_surface(surface)
    if not (surface and surface.valid and cave_worlds.is_cave_world(surface)) then return false end
    if storage and storage.mid_save_install then return false end
    return surface.count_entities_filtered { name = "diggy-rock", limit = 1 } > 0
end

function growth.nest_name_for_family(family, surface)
    return FAMILY_NESTS[family] or bob_enemies.growth_nest_name(family, surface)
end

function growth.nest_family_for_name(name)
    return NEST_FAMILIES[name] or bob_enemies.growth_family(name)
end

local function expansion_enabled()
    return game_settings.biter_expansion_enabled()
end

local function queen_enabled()
    return game_settings.arachnid_queen_enabled()
end

local function valid_floor(surface, position)
    local tile = surface.get_tile(position)
    return tile and tile.valid and tile.name ~= "out-of-map"
end

local function player_building_near(surface, position, radius)
    for _, entity in pairs(surface.find_entities_filtered {
        position = position,
        radius = radius,
    }) do
        if entity.valid and entity.force then
            local force_name = entity.force.name
            if force_name ~= "enemy" and force_name ~= "neutral"
                and entity.prototype and entity.prototype.is_building then
                return true
            end
        end
    end
    return false
end

local function command_entity(entity, command)
    if not (entity and entity.valid) then return false end
    local commanded = false
    pcall(function()
        if entity.commandable and entity.commandable.valid then
            entity.commandable.set_command(command)
            commanded = true
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

local function detach_unit_from_ai_sources(entity)
    if not (entity and entity.valid) then return end
    local commandable
    pcall(function() commandable = entity.commandable end)
    if commandable and commandable.valid then
        pcall(function() commandable.release_from_spawner() end)
    end

    -- A native group can otherwise replace an explicit per-unit command. Moving
    -- the unit through a temporary group and immediately disbanding that group
    -- detaches only it; no other enemy or command is destroyed.
    local grouped = false
    pcall(function() grouped = commandable and commandable.parent_group ~= nil end)
    if not grouped then pcall(function() grouped = entity.unit_group ~= nil end) end
    if not grouped then return end
    pcall(function()
        local temporary = entity.surface.create_unit_group {
            position = entity.position,
            force = entity.force,
        }
        temporary.add_member(entity)
        temporary.destroy()
    end)
end

-- Transfer one ordinary mobile enemy out of the ecology and native group
-- planners before Biter Expansion gives it a permanent Train/Shelter target.
-- The active Arachnid Queen always remains under her passive nesting controller.
function growth.claim_objective_attacker(entity)
    if not (entity and entity.valid and entity.type == "unit"
        and entity.unit_number and entity.surface) then
        return false
    end
    if growth.is_active_queen(entity) then return false end

    local surface_state = root().surfaces[entity.surface.index]
    if surface_state and surface_state.settlers then
        surface_state.settlers[entity.unit_number] = nil
    end
    detach_unit_from_ai_sources(entity)
    return true
end

local function command_stop(entity)
    return command_entity(entity, {
        type = defines.command.stop,
        distraction = defines.distraction.none,
    })
end

local function command_travel(entity, destination, passive)
    return command_entity(entity, {
        type = defines.command.go_to_location,
        destination = copy_position(destination),
        radius = 3,
        -- Settlers keep ordinary combat distractions while travelling. Queens
        -- ignore every distraction and are therefore completely passive.
        distraction = passive and defines.distraction.none or defines.distraction.by_enemy,
    })
end

local function command_dig(entity, rock)
    if not (rock and rock.valid) then return false end
    return command_entity(entity, {
        type = defines.command.attack,
        target = rock,
        -- The Queen attacks only the selected neutral Cave cover. Players,
        -- buildings and nearby combat remain distractions she must ignore.
        distraction = defines.distraction.none,
    })
end

local function command_normal_combat(entity)
    if not (entity and entity.valid) then return end
    command_entity(entity, {
        type = defines.command.attack_area,
        destination = copy_position(entity.position),
        radius = 32,
        distraction = defines.distraction.by_enemy,
    })
end

-- The largest custom spawner is used as the clearance probe. Any of the four
-- weighted nest families will fit at a position accepted by this prototype.
local function nest_site(surface, nest_name, center, stream_offset)
    local seed = tonumber(surface.map_gen_settings.seed) or 0
    local cx = math.floor(center.x)
    local cy = math.floor(center.y)
    local start = hash.range(seed, cx, cy, TARGET_STREAM + (stream_offset or 0), 0, 11)
    for step = 0, 11 do
        local angle = ((start + step) % 12) * math.pi / 6
        local target = {
            x = center.x + math.cos(angle) * 9,
            y = center.y + math.sin(angle) * 9,
        }
        local spot = surface.find_non_colliding_position(nest_name, target, 2, 0.25)
        if spot and valid_floor(surface, spot) and not player_building_near(surface, spot, 4) then
            return copy_position(spot)
        end
    end
    return nil
end

local function queen_nest_sites(surface, center, stream_offset, required_count, start_anchor)
    required_count = math.max(1, math.min(3, math.floor(tonumber(required_count) or 3)))
    local probe_name = FAMILY_NESTS.snapper
    local seed = tonumber(surface.map_gen_settings.seed) or 0
    local cx = math.floor(center.x)
    local cy = math.floor(center.y)
    local start = hash.range(seed, cx, cy, TARGET_STREAM + 100 + (stream_offset or 0), 0, 7)
    for rotation = 0, 7 do
        local angle = ((start + rotation) % 8) * math.pi / 4
        local sites = {}
        local valid = true
        for i = 1, required_count do
            -- Keep the original three-point geometry even when the cap permits
            -- only one or two final nests.
            local theta = angle + (i - 1) * (2 * math.pi / 3)
            local target = {
                x = center.x + math.cos(theta) * 10,
                y = center.y + math.sin(theta) * 10,
            }
            local spot = surface.find_non_colliding_position(probe_name, target, 1.5, 0.25)
            if not spot or not valid_floor(surface, spot)
                or player_building_near(surface, spot, 4)
                or (start_anchor and not outside_queen_start_zone(start_anchor, spot)) then
                valid = false
                break
            end
            for _, previous in ipairs(sites) do
                if distance_squared(previous, spot) < 8 * 8 then
                    valid = false
                    break
                end
            end
            if not valid then break end
            sites[#sites + 1] = copy_position(spot)
        end
        if valid and #sites == required_count then return sites end
    end
    return nil
end

local function room_footprints(surface)
    local all = storage.cavern_room_footprints
    return type(all) == "table" and all[surface.index] or nil
end

local function destination_in_opened_room(
    surface, entity, sequence, exclude, required_nest_count, zone_id, start_anchor
)
    local rooms = room_footprints(surface)
    if type(rooms) ~= "table" or #rooms == 0 then return nil end
    local seed = tonumber(surface.map_gen_settings.seed) or 0
    local unit_number = tonumber(entity.unit_number) or 0
    local start = hash.range(seed, unit_number, sequence, TARGET_STREAM + 200, 1, #rooms)

    for offset = 0, #rooms - 1 do
        local room = rooms[((start + offset - 1) % #rooms) + 1]
        if room and tonumber(room.cx) and tonumber(room.cy) then
            local center = { x = room.cx + 0.5, y = room.cy + 0.5 }
            local room_zone = depth_levels.level_for_surface_position(surface, center).id
            if (not zone_id or room_zone == zone_id)
                and (not exclude or distance_squared(center, exclude) >= DIFFERENT_ROOM_RADIUS_SQUARED)
                and not player_building_near(surface, center, 13)
                and (not start_anchor or outside_queen_start_zone(start_anchor, center)) then
                local span_x = math.floor(math.max(2, math.min(8,
                    ((room.x2 or room.cx + 8) - (room.x1 or room.cx - 8)) / 2 - 2)))
                local span_y = math.floor(math.max(2, math.min(8,
                    ((room.y2 or room.cy + 8) - (room.y1 or room.cy - 8)) / 2 - 2)))
                local dx = hash.range(seed, unit_number, sequence + offset, TARGET_STREAM + 201, -span_x, span_x)
                local dy = hash.range(seed, unit_number, sequence + offset, TARGET_STREAM + 202, -span_y, span_y)
                local target = { x = center.x + dx, y = center.y + dy }
                local spot = surface.find_non_colliding_position(entity.name, target, 7, 0.5)
                if spot and valid_floor(surface, spot)
                    and not player_building_near(surface, spot, 12)
                    and (not start_anchor or (
                        outside_queen_start_zone(start_anchor, spot)
                        and segment_outside_queen_start_zone(start_anchor, entity.position, spot)
                    ))
                    and (not required_nest_count or queen_nest_sites(
                        surface,
                        spot,
                        sequence + offset,
                        required_nest_count,
                        start_anchor
                    )) then
                    return copy_position(spot)
                end
            end
        end
    end
    return nil
end

local function same_position(a, b, radius_squared)
    return a and b and distance_squared(a, b) <= (radius_squared or 1)
end

-- If every opened room is too crowded for the Queen's next nest batch, select a real
-- frontier rock in the Queen's own zone. Candidates are sorted so multiplayer
-- peers make the same choice, and positions near player buildings are skipped.
local function queen_dig_target(surface, queen, record, tick)
    local candidates = surface.find_entities_filtered {
        name = "diggy-rock",
        position = queen.position,
        radius = QUEEN_DIG_SEARCH_RADIUS,
        -- Cave cover is tile-dense. A bounded deterministic batch keeps one
        -- Queen search from sorting tens of thousands of LuaEntity references.
        limit = QUEEN_DIG_CANDIDATE_LIMIT,
    }
    table.sort(candidates, function(a, b)
        local da = distance_squared(queen.position, a.position)
        local db = distance_squared(queen.position, b.position)
        if da ~= db then return da < db end
        local au, bu = tonumber(a.unit_number) or 0, tonumber(b.unit_number) or 0
        if au ~= bu then return au < bu end
        if a.position.x ~= b.position.x then return a.position.x < b.position.x end
        return a.position.y < b.position.y
    end)

    local avoid_active = record.avoid_dig_position
        and tick < (record.avoid_dig_until or 0)
    for _, rock in ipairs(candidates) do
        if rock and rock.valid then
            local position = copy_position(rock.position)
            local level = depth_levels.level_for_surface_position(surface, position)
            if level.id == record.zone_id
                and not (avoid_active and same_position(position, record.avoid_dig_position, 2 * 2))
                and not player_building_near(surface, position, QUEEN_DIG_BUILDING_CLEARANCE)
                and outside_queen_start_zone(record.start_anchor, position)
                and segment_outside_queen_start_zone(
                    record.start_anchor, queen.position, position
                ) then
                -- A nearby legal Queen position proves there is an exposed side
                -- from which the explicit attack command can reach this rock.
                local approach = surface.find_non_colliding_position(
                    queen.name, position, 6, 0.5
                )
                if approach and valid_floor(surface, approach)
                    and outside_queen_start_zone(record.start_anchor, approach)
                    and segment_outside_queen_start_zone(
                        record.start_anchor, queen.position, approach
                    ) then
                    return rock
                end
            end
        end
    end
    return nil
end

-- Old saves may not have footprints for every historical opened room. Mobile
-- settlers get a conservative floor fallback; Queens deliberately wait for a
-- registered room because they must reserve space for their next nest batch.
local function fallback_settler_destination(surface, entity, sequence, nest_name)
    local seed = tonumber(surface.map_gen_settings.seed) or 0
    local unit_number = tonumber(entity.unit_number) or 0
    for attempt = 1, 24 do
        local dx = hash.range(seed, unit_number, sequence + attempt, TARGET_STREAM + 300, -160, 160)
        local dy = hash.range(seed, unit_number, sequence + attempt, TARGET_STREAM + 301, -160, 160)
        local target = { x = entity.position.x + dx, y = entity.position.y + dy }
        if distance_squared(target, entity.position) >= DIFFERENT_ROOM_RADIUS_SQUARED then
            local spot = surface.find_non_colliding_position(entity.name, target, 10, 0.5)
            if spot and valid_floor(surface, spot) and not player_building_near(surface, spot, 12)
                and nest_site(surface, nest_name, spot, sequence + attempt) then
                return copy_position(spot)
            end
        end
    end
    return nil
end

local function weighted_nest_family(seed, x, y, stream)
    local roll = hash.roll(seed, x, y, stream)
    if roll < 0.20 then return "biter" end
    if roll < 0.40 then return "spitter" end
    if roll < 0.70 then return "snapper" end
    return "arachnid"
end

local function create_nest(surface, family, position)
    local name = growth.nest_name_for_family(family, surface)
    if not name then return nil end
    local entity = surface.create_entity {
        name = name,
        position = position,
        force = "enemy",
    }
    bob_enemies.protect_scripted_base_part(entity)
    return entity and entity.valid and entity or nil
end

local function recompute_next_worm_tick(value)
    local next_tick = nil
    for _, surface_index in ipairs(sorted_surface_indexes(value.surfaces)) do
        local state = value.surfaces[surface_index]
        for _, unit_number in ipairs(sorted_numeric_keys(state.worms or {})) do
            local record = state.worms[unit_number]
            if record and tonumber(record.transform_tick)
                and (not next_tick or record.transform_tick < next_tick) then
                next_tick = record.transform_tick
            end
        end
    end
    value.next_worm_tick = next_tick
end

function growth.register_direct_dig_spawn(entity, family)
    if not (entity and entity.valid and entity.unit_number) then return false end
    local bob_unit = bob_enemies.unit_info(entity.name)
    if family == "worm" or (bob_unit and bob_unit.kind == "worm-turret") then
        if not expansion_enabled() then return false end
        local value = root()
        local transform_tick = game.tick + WORM_MATURATION_TICKS
        state_for(entity.surface).worms[entity.unit_number] = {
            entity = entity,
            transform_tick = transform_tick,
            sequence = 0,
            family = family ~= "worm" and bob_unit and bob_enemies.growth_family(entity.name) or nil,
        }
        if not value.next_worm_tick or transform_tick < value.next_worm_tick then
            value.next_worm_tick = transform_tick
        end
        return true
    end

    if not growth.nest_name_for_family(family, entity.surface) or not expansion_enabled() then return false end
    state_for(entity.surface).settlers[entity.unit_number] = {
        entity = entity,
        family = family,
        origin = copy_position(entity.position),
        target = nil,
        sequence = 0,
        retry_tick = game.tick + SETTLER_INITIAL_COMBAT,
        last_progress_tick = game.tick,
        next_command_tick = game.tick,
    }
    return true
end

local function process_due_worms(tick)
    local value = root()
    if not value.next_worm_tick or tick < value.next_worm_tick then return end

    for _, surface_index in ipairs(sorted_surface_indexes(value.surfaces)) do
        local state = value.surfaces[surface_index]
        for _, unit_number in ipairs(sorted_numeric_keys(state.worms)) do
            local record = state.worms[unit_number]
            local worm = record and record.entity
            if not (worm and worm.valid) then
                state.worms[unit_number] = nil
            elseif cave_teams.is_world_running(worm.surface) and tick >= record.transform_tick then
                if not expansion_enabled() then
                    state.worms[unit_number] = nil
                else
                    local surface = worm.surface
                    local seed = tonumber(surface.map_gen_settings.seed) or 0
                    if not record.family then
                        record.family = weighted_nest_family(
                            seed,
                            unit_number,
                            math.floor(worm.position.x) + math.floor(worm.position.y) * 31,
                            WORM_FAMILY_STREAM
                        )
                    end
                    local family = record.family
                    local nest_name = growth.nest_name_for_family(family, surface)
                    if not nest_name then
                        state.worms[unit_number] = nil
                    else
                        local site = nest_site(surface, nest_name, worm.position,
                            WORM_FAMILY_STREAM + (record.sequence or 0))
                        local nest = site and create_nest(surface, family, site) or nil
                        if nest then
                            -- Placement succeeded first; the direct-dig Worm is only
                            -- now removed, so a blocked conversion can never erase it.
                            worm.destroy { raise_destroy = false }
                            state.worms[unit_number] = nil
                        else
                            record.sequence = (record.sequence or 0) + 1
                            record.transform_tick = tick + TICKS_PER_SECOND
                        end
                    end
                end
            end
        end
    end
    recompute_next_worm_tick(value)
end

local function settle_mobile_unit(state, unit_number, record, tick)
    local entity = record.entity
    if not (entity and entity.valid) then
        state.settlers[unit_number] = nil
        return
    end
    local nest_name = growth.nest_name_for_family(record.family, entity.surface)
    if not nest_name then
        command_normal_combat(entity)
        state.settlers[unit_number] = nil
        return
    end
    if not expansion_enabled() then
        command_normal_combat(entity)
        state.settlers[unit_number] = nil
        return
    end

    if record.target then
        local remaining = distance_squared(entity.position, record.target)
        if remaining <= ARRIVAL_RADIUS_SQUARED then
            local site = nest_site(entity.surface, nest_name, entity.position,
                record.sequence)
            if site and create_nest(entity.surface, record.family, site) then
                command_normal_combat(entity)
                state.settlers[unit_number] = nil
                return
            end
            record.target = nil
            record.retry_tick = tick + SHORT_RETRY
            return
        end

        if not record.best_distance or remaining < record.best_distance - 1 then
            record.best_distance = remaining
            record.last_progress_tick = tick
        elseif tick - (record.last_progress_tick or tick) >= SETTLER_STUCK_TICKS then
            record.target = nil
            record.retry_tick = tick + SHORT_RETRY
            return
        end

        if tick >= (record.next_command_tick or 0) then
            command_travel(entity, record.target, false)
            record.next_command_tick = tick + REISSUE_TICKS
        end
        return
    end

    if tick < (record.retry_tick or 0) then return end
    record.sequence = (record.sequence or 0) + 1
    local destination = destination_in_opened_room(
        entity.surface, entity, record.sequence, entity.position, false
    ) or fallback_settler_destination(
        entity.surface, entity, record.sequence, nest_name
    )
    if not destination then
        record.retry_tick = tick + NO_DESTINATION_RETRY
        return
    end

    record.target = destination
    record.best_distance = distance_squared(entity.position, destination)
    record.last_progress_tick = tick
    record.next_command_tick = tick + REISSUE_TICKS
    command_travel(entity, destination, false)
end

local function queen_record_for_entity(entity)
    if not (entity and entity.valid and entity.unit_number and entity.surface) then return nil end
    local state = root().surfaces[entity.surface.index]
    if not state then return nil end
    for _, zone_id in ipairs(ZONE_ORDER) do
        local record = state.queens and state.queens[zone_id]
        if record and record.unit_number == entity.unit_number then return record, state, zone_id end
    end
    return nil
end

function growth.is_active_queen(entity)
    if not queen_enabled() then return false end
    if not (entity and entity.valid and QUEEN_NAME_SET[entity.name]) then return false end
    return queen_record_for_entity(entity) ~= nil
end

local function new_queen_record(entity, zone_id, origin, start_anchor)
    return {
        entity = entity,
        unit_number = entity.unit_number,
        zone_id = zone_id,
        origin = copy_position(origin or entity.position),
        current_site = copy_position(origin or entity.position),
        phase = "seeking",
        target = nil,
        retry_tick = game.tick + TICKS_PER_SECOND,
        sequence = 0,
        last_damage_tick = game.tick,
        next_command_tick = game.tick,
        last_progress_tick = game.tick,
        dig_target = nil,
        avoid_dig_position = nil,
        avoid_dig_until = nil,
        start_anchor = copy_position(start_anchor),
        last_safe_position = copy_position(entity.position),
        next_population_check_tick = game.tick,
    }
end

function growth.try_spawn_queen(surface, center, radius, zone_id)
    if not queen_enabled() then return false end
    if not growth.is_main_cave_surface(surface) or not cave_teams.is_world_running(surface) then return false end
    local level = QUEEN_LEVELS[zone_id]
    if not level then return false end
    local state = state_for(surface)
    local anchor = queen_start_anchor(surface, state)
    center = copy_position(center)
    if not center or not outside_queen_start_zone(anchor, center) then return false end
    local existing = state.queens[zone_id]
    if existing and existing.entity and existing.entity.valid then return false end
    state.queens[zone_id] = nil

    local name = "maf-boss-arachnid-biter-" .. tostring(level)
    local spot = surface.find_non_colliding_position(name, center, math.max(3, radius - 2), 0.5)
    if not spot or not outside_queen_start_zone(anchor, spot) then return false end
    local queen = surface.create_entity {
        name = name,
        position = spot,
        force = "enemy",
    }
    if not (queen and queen.valid and queen.unit_number) then return false end

    state.queens[zone_id] = new_queen_record(queen, zone_id, center, anchor)
    detach_unit_from_ai_sources(queen)
    command_stop(queen)
    return true
end

local function pause_queen_for_population(record, tick, count)
    record.phase = "population-capped"
    record.target = nil
    record.dig_target = nil
    record.dig_target_position = nil
    record.dig_target_health = nil
    record.last_zone_nest_count = count
    record.next_population_check_tick = tick + QUEEN_POPULATION_RECHECK_TICKS
    record.next_command_tick = tick + REISSUE_TICKS
    command_stop(record.entity)
end

local function lay_queen_nests(state, record, tick)
    local queen = record.entity
    if not (queen and queen.valid) then return false end
    local surface = queen.surface
    local current_count = queen_zone_nest_count(
        surface, state, record.zone_id, tick, true
    )
    local remaining_capacity = QUEEN_NEST_CAP - current_count
    if remaining_capacity <= 0 then
        pause_queen_for_population(record, tick, current_count)
        return true
    end

    local nest_count = math.min(3, remaining_capacity)
    local sites = queen_nest_sites(
        surface,
        queen.position,
        record.sequence,
        nest_count,
        record.start_anchor
    )
    if not sites then return false end

    local seed = tonumber(surface.map_gen_settings.seed) or 0
    local families = {}
    for i = 1, nest_count do
        families[i] = weighted_nest_family(
            seed,
            record.unit_number + i * 7919,
            record.sequence,
            QUEEN_FAMILY_STREAM + i
        )
    end

    local created = {}
    for i = 1, nest_count do
        local nest = create_nest(surface, families[i], sites[i])
        if not nest then
            for _, entity in ipairs(created) do
                if entity.valid then entity.destroy { raise_destroy = false } end
            end
            return false
        end
        created[#created + 1] = nest
    end

    record.sequence = record.sequence + 1
    record.phase = "waiting"
    record.target = nil
    record.dig_target = nil
    record.current_site = copy_position(queen.position)
    local new_count = current_count + #created
    state.queen_nest_counts[record.zone_id] = new_count
    state.queen_nest_counts_tick = tick
    if new_count >= QUEEN_NEST_CAP then
        pause_queen_for_population(record, tick, new_count)
    else
        record.next_action_tick = tick + QUEEN_REST_TICKS
        record.next_command_tick = tick + REISSUE_TICKS
        command_stop(queen)
    end
    return true
end

local function heal_queen(record, tick)
    local queen = record.entity
    if not (queen and queen.valid and queen.health) then return end
    if tick - (record.last_damage_tick or tick) < QUEEN_REGEN_DELAY then return end
    local maximum = queen.max_health or queen.health
    if queen.health < maximum then
        -- Controller runs once per second: 0.5% of maximum health each pass.
        queen.health = math.min(maximum, queen.health + maximum * 0.005)
    end
end

local function return_queen_to_safe_side(state, zone_id, record, tick)
    local queen = record.entity
    local anchor = copy_position(record.start_anchor)
        or queen_start_anchor(queen.surface, state)
    record.start_anchor = copy_position(anchor)

    if outside_queen_start_zone(anchor, queen.position) then
        record.last_safe_position = copy_position(queen.position)
        return true
    end

    command_stop(queen)
    local fallback = copy_position(record.last_safe_position)
    local spot
    if fallback and outside_queen_start_zone(anchor, fallback) then
        spot = queen.surface.find_non_colliding_position(queen.name, fallback, 8, 0.5)
        if not (spot and outside_queen_start_zone(anchor, spot)) then spot = fallback end
    end

    local moved = false
    if spot then
        local ok, result = pcall(function() return queen.teleport(spot) end)
        moved = ok and result ~= false and outside_queen_start_zone(anchor, queen.position)
    end
    if not moved then
        -- A legacy Queen saved inside the protected start area has no legal
        -- history to restore. Removing her frees the zone slot for the next
        -- eligible room beyond tile 200.
        queen.destroy { raise_destroy = false }
        state.queens[zone_id] = nil
        return false
    end

    record.phase = "seeking"
    record.target = nil
    record.dig_target = nil
    record.dig_target_position = nil
    record.dig_target_health = nil
    record.current_site = copy_position(queen.position)
    record.last_safe_position = copy_position(queen.position)
    record.retry_tick = tick + SHORT_RETRY
    record.next_population_check_tick = tick
    return true
end

local function queen_population_allows_activity(state, record, tick)
    if tick >= (record.next_population_check_tick or 0) then
        local count = queen_zone_nest_count(
            record.entity.surface, state, record.zone_id, tick, false
        )
        record.last_zone_nest_count = count
        record.next_population_check_tick = tick + QUEEN_POPULATION_RECHECK_TICKS
        if count >= QUEEN_NEST_CAP then
            pause_queen_for_population(record, tick, count)
            return false
        end
        if record.phase == "population-capped" then
            record.phase = "seeking"
            record.retry_tick = tick
            record.next_command_tick = tick
        end
    end

    if record.phase ~= "population-capped" then return true end
    if tick >= (record.next_command_tick or 0) then
        command_stop(record.entity)
        record.next_command_tick = tick + REISSUE_TICKS
    end
    return false
end

local function begin_queen_digging(record, rock, tick)
    local queen = record.entity
    if not (queen and queen.valid and rock and rock.valid) then return false end
    if not outside_queen_start_zone(record.start_anchor, rock.position)
        or not segment_outside_queen_start_zone(
            record.start_anchor, queen.position, rock.position
        ) then
        return false
    end
    record.phase = "digging"
    record.target = nil
    record.dig_target = rock
    record.dig_target_position = copy_position(rock.position)
    record.dig_target_health = tonumber(rock.health)
    record.best_distance = distance_squared(queen.position, rock.position)
    record.last_progress_tick = tick
    record.next_command_tick = tick + REISSUE_TICKS
    command_dig(queen, rock)
    return true
end

local function process_queen_digging(record, tick)
    local queen = record.entity
    local rock = record.dig_target
    if rock and rock.valid and (
        not outside_queen_start_zone(record.start_anchor, rock.position)
        or not segment_outside_queen_start_zone(
            record.start_anchor, queen.position, rock.position
        )
    ) then
        record.phase = "seeking"
        record.dig_target = nil
        record.dig_target_position = nil
        record.dig_target_health = nil
        record.retry_tick = tick + SHORT_RETRY
        command_stop(queen)
        return
    end
    if not (rock and rock.valid and rock.name == "diggy-rock") then
        -- Whether the Queen or a player removed it, the world is current before
        -- the next one-second ecology pass. Recheck registered rooms first.
        record.phase = "seeking"
        record.dig_target = nil
        record.dig_target_position = nil
        record.dig_target_health = nil
        record.retry_tick = tick + TICKS_PER_SECOND
        return
    end

    local remaining = distance_squared(queen.position, rock.position)
    local health = tonumber(rock.health)
    local progressed = false
    if not record.best_distance or remaining < record.best_distance - 1 then
        record.best_distance = remaining
        progressed = true
    end
    if health and (not record.dig_target_health or health < record.dig_target_health) then
        record.dig_target_health = health
        progressed = true
    end
    if progressed then
        record.last_progress_tick = tick
    elseif tick - (record.last_progress_tick or tick) >= QUEEN_DIG_STUCK_TICKS then
        -- Do not immediately select the same unreachable wall again. The short
        -- position blacklist is local to this Queen and expires automatically.
        record.avoid_dig_position = copy_position(rock.position)
        record.avoid_dig_until = tick + QUEEN_DIG_AVOID_TICKS
        record.phase = "seeking"
        record.dig_target = nil
        record.dig_target_position = nil
        record.dig_target_health = nil
        record.retry_tick = tick + SHORT_RETRY
        command_stop(queen)
        return
    end

    if tick >= (record.next_command_tick or 0) then
        command_dig(queen, rock)
        record.next_command_tick = tick + REISSUE_TICKS
    end
end

local function process_queen(state, zone_id, record, tick)
    local queen = record.entity
    if not (queen and queen.valid) then
        state.queens[zone_id] = nil
        return
    end

    detach_unit_from_ai_sources(queen)
    heal_queen(record, tick)
    if not return_queen_to_safe_side(state, zone_id, record, tick) then return end
    if not queen_population_allows_activity(state, record, tick) then return end

    if record.phase == "digging" then
        process_queen_digging(record, tick)
        return
    end

    if record.phase == "waiting" then
        if tick >= (record.next_command_tick or 0) then
            command_stop(queen)
            record.next_command_tick = tick + REISSUE_TICKS
        end
        if tick < (record.next_action_tick or tick) then return end
        record.phase = "seeking"
        record.retry_tick = tick
    end

    if record.phase == "moving" and record.target then
        if not outside_queen_start_zone(record.start_anchor, record.target)
            or not segment_outside_queen_start_zone(
                record.start_anchor, queen.position, record.target
            ) then
            record.phase = "seeking"
            record.target = nil
            record.retry_tick = tick + SHORT_RETRY
            command_stop(queen)
            return
        end
        local remaining = distance_squared(queen.position, record.target)
        if remaining <= ARRIVAL_RADIUS_SQUARED then
            if not lay_queen_nests(state, record, tick) then
                record.phase = "seeking"
                record.target = nil
                record.retry_tick = tick + SHORT_RETRY
                command_stop(queen)
            end
            return
        end

        if not record.best_distance or remaining < record.best_distance - 1 then
            record.best_distance = remaining
            record.last_progress_tick = tick
        elseif tick - (record.last_progress_tick or tick) >= QUEEN_STUCK_TICKS then
            record.target = nil
            local rock = queen_dig_target(queen.surface, queen, record, tick)
            if rock and begin_queen_digging(record, rock, tick) then return end
            record.phase = "seeking"
            record.retry_tick = tick + SHORT_RETRY
            command_stop(queen)
            return
        end

        if tick >= (record.next_command_tick or 0) then
            command_travel(queen, record.target, true)
            record.next_command_tick = tick + REISSUE_TICKS
        end
        return
    end

    if tick < (record.retry_tick or 0) then
        command_stop(queen)
        return
    end

    record.sequence = (record.sequence or 0) + 1
    -- 3.1.54 could save an empty current_site when an Arachnid room supplied
    -- its centre in Factorio's array-form MapPosition. Normalise valid legacy
    -- positions and repair an invalid one from the Queen's current position.
    local current_site = copy_position(record.current_site) or copy_position(queen.position)
    record.current_site = current_site
    local remaining_capacity = math.max(1,
        QUEEN_NEST_CAP - (tonumber(record.last_zone_nest_count) or 0))
    local required_nest_count = math.min(3, remaining_capacity)
    local destination = destination_in_opened_room(
        queen.surface,
        queen,
        record.sequence,
        current_site,
        required_nest_count,
        record.zone_id,
        record.start_anchor
    )
    if not destination then
        local rock = queen_dig_target(queen.surface, queen, record, tick)
        if rock and begin_queen_digging(record, rock, tick) then return end
        record.retry_tick = tick + NO_DESTINATION_RETRY
        command_stop(queen)
        return
    end

    record.phase = "moving"
    record.target = destination
    record.best_distance = distance_squared(queen.position, destination)
    record.last_progress_tick = tick
    record.next_command_tick = tick + REISSUE_TICKS
    command_travel(queen, destination, true)
end

local function process_one_second(tick)
    local value = root()
    local queens_active = queen_enabled()
    for _, surface_index in ipairs(sorted_surface_indexes(value.surfaces)) do
        local state = value.surfaces[surface_index]
        local surface = game.surfaces[surface_index]
        if not (surface and surface.valid) then
            value.surfaces[surface_index] = nil
        elseif cave_teams.is_world_running(surface) then
            for _, unit_number in ipairs(sorted_numeric_keys(state.settlers)) do
                local record = state.settlers[unit_number]
                if record then settle_mobile_unit(state, unit_number, record, tick) end
            end
            if queens_active then
                for _, zone_id in ipairs(ZONE_ORDER) do
                    local record = state.queens[zone_id]
                    if record then process_queen(state, zone_id, record, tick) end
                end
            end
        end
    end
end

-- Movement commands are evaluated by the engine between one-second ecology
-- passes. A lightweight per-tick boundary guard prevents a fast Queen from
-- visibly crossing back into the protected start area between those passes.
local function guard_queen_start_boundaries(tick)
    if not queen_enabled() then return end
    local value = root()
    for _, surface_index in ipairs(sorted_surface_indexes(value.surfaces)) do
        local state = value.surfaces[surface_index]
        for _, zone_id in ipairs(ZONE_ORDER) do
            local record = state.queens and state.queens[zone_id]
            local queen = record and record.entity
            if record and queen and queen.valid then
                if cave_teams.is_world_running(queen.surface) then
                    return_queen_to_safe_side(state, zone_id, record, tick)
                end
            elseif record then
                state.queens[zone_id] = nil
            end
        end
    end
end

local function remove_existing_queens()
    local value = root()
    for _, surface_index in ipairs(sorted_surface_indexes(value.surfaces)) do
        local state = value.surfaces[surface_index]
        for _, zone_id in ipairs(ZONE_ORDER) do
            local record = state.queens and state.queens[zone_id]
            local queen = record and record.entity
            if queen and queen.valid then queen.destroy { raise_destroy = false } end
        end
        state.queens = {}
    end

    -- Also remove an unregistered legacy Queen that an older save may contain.
    -- These integrated boss prototypes are not used by another Cave system.
    for _, surface in pairs(game.surfaces) do
        for _, queen in pairs(surface.find_entities_filtered {
            name = QUEEN_NAMES,
            force = "enemy",
        }) do
            if queen.valid then queen.destroy { raise_destroy = false } end
        end
    end
end

local function adopt_existing_queens()
    local value = root()
    for _, surface in pairs(game.surfaces) do
        if growth.is_main_cave_surface(surface) then
            local state = state_for(surface)
            local anchor = queen_start_anchor(surface, state)
            local found = surface.find_entities_filtered {
                name = QUEEN_NAMES,
                force = "enemy",
            }
            table.sort(found, function(a, b)
                return (a.unit_number or 0) < (b.unit_number or 0)
            end)
            for _, queen in ipairs(found) do
                if queen.valid and queen.unit_number then
                    local already = queen_record_for_entity(queen)
                    if not already then
                        if not outside_queen_start_zone(anchor, queen.position) then
                            queen.destroy { raise_destroy = false }
                        else
                            local zone_id = depth_levels.level_for_surface_position(
                                surface, queen.position
                            ).id
                            local slot = state.queens[zone_id]
                            if not (slot and slot.entity and slot.entity.valid) then
                                local desired_name = "maf-boss-arachnid-biter-"
                                    .. tostring(QUEEN_LEVELS[zone_id] or QUEEN_LEVELS.easy)
                                if queen.name ~= desired_name then
                                    -- Saves that skipped 3.1.51 may still contain
                                    -- legacy levels 4-10. Replace them with the
                                    -- zone-capped Queen while preserving health %.
                                    local old = queen
                                    local ratio = math.max(0, math.min(1,
                                        (old.health or 1) / (old.max_health or 1)))
                                    local spot = surface.find_non_colliding_position(
                                        desired_name, old.position, 10, 0.5
                                    )
                                    local replacement = spot
                                        and outside_queen_start_zone(anchor, spot)
                                        and surface.create_entity {
                                        name = desired_name,
                                        position = spot,
                                        force = old.force,
                                    } or nil
                                    if replacement and replacement.valid then
                                        replacement.health = math.max(1,
                                            replacement.max_health * ratio)
                                        old.destroy { raise_destroy = false }
                                        queen = replacement
                                    end
                                end
                                state.queens[zone_id] = new_queen_record(
                                    queen, zone_id, queen.position, anchor
                                )
                                detach_unit_from_ai_sources(queen)
                                command_stop(queen)
                            else
                                -- Stable 3.1.51 could leave several bosses alive in
                                -- one zone. Consolidate them to the new one-Queen cap.
                                queen.destroy { raise_destroy = false }
                            end
                        end
                    end
                end
            end
        end
    end
    recompute_next_worm_tick(value)
end

function growth.on_init(reset_state)
    if reset_state then storage[STORAGE_KEY] = nil end
    root().queen_health_migration_version = QUEEN_HEALTH_MIGRATION_VERSION
end

function growth.on_configuration_changed()
    local value = root()
    for surface_index in pairs(value.surfaces) do
        local surface = game.surfaces[surface_index]
        if not (surface and surface.valid) then value.surfaces[surface_index] = nil end
    end
    if queen_enabled() then
        adopt_existing_queens()
        if value.queen_health_migration_version ~= QUEEN_HEALTH_MIGRATION_VERSION then
            local old_health = {
                ["maf-boss-arachnid-biter-1"] = 10000,
                ["maf-boss-arachnid-biter-2"] = 15000,
                ["maf-boss-arachnid-biter-3"] = 20000,
            }
            for _, state in pairs(value.surfaces) do
                for _, record in pairs(state.queens or {}) do
                    local queen = record and record.entity
                    local previous_max = queen and queen.valid and old_health[queen.name]
                    if previous_max and queen.health and queen.health <= previous_max then
                        queen.health = math.min(queen.max_health, queen.health * 10)
                    end
                end
            end
            value.queen_health_migration_version = QUEEN_HEALTH_MIGRATION_VERSION
        end
    else
        remove_existing_queens()
        value.queen_health_migration_version = QUEEN_HEALTH_MIGRATION_VERSION
    end
end

function growth.on_tick(event)
    if not (event and event.tick) then return end
    guard_queen_start_boundaries(event.tick)
    process_due_worms(event.tick)
    if event.tick % TICKS_PER_SECOND == 0 then process_one_second(event.tick) end
end

local applying_queen_cover_damage = false

-- Duplicate the Queen strike only against Cave cover. LuaEntity.damage keeps
-- normal resistance and death handling and preserves the Queen as the death
-- cause; the guard prevents the bonus hit recursively multiplying itself.
function growth.apply_queen_cover_damage(event)
    if applying_queen_cover_damage then return false end
    local entity = event and event.entity
    local cause = event and event.cause
    if not (entity and entity.valid and entity.health) then return false end
    if entity.name ~= "diggy-rock" and entity.name ~= "diggy-rubble" then return false end
    if not growth.is_active_queen(cause) then return false end

    local amount = tonumber(event.original_damage_amount)
        or tonumber(event.final_damage_amount) or 0
    amount = amount * (QUEEN_COVER_DAMAGE_MULTIPLIER - 1)
    if amount <= 0 then return false end

    local damage_type = event.damage_type and event.damage_type.name or "physical"
    applying_queen_cover_damage = true
    local ok = pcall(function()
        entity.damage(amount, cause.force, damage_type, cause, cause)
    end)
    applying_queen_cover_damage = false
    return ok
end

function growth.on_entity_damaged(event)
    local entity = event and event.entity
    if not (entity and entity.valid and QUEEN_NAME_SET[entity.name]) then return end
    local record = queen_record_for_entity(entity)
    if not record then return end
    record.last_damage_tick = event.tick or game.tick
    -- Damage must never change a Queen into a retaliation command.
    detach_unit_from_ai_sources(entity)
    if record.start_anchor
        and not outside_queen_start_zone(record.start_anchor, entity.position) then
        command_stop(entity)
    elseif record.phase == "moving" and record.target then
        command_travel(entity, record.target, true)
    elseif record.phase == "digging" and record.dig_target and record.dig_target.valid then
        command_dig(entity, record.dig_target)
    else
        command_stop(entity)
    end
end

function growth.on_entity_died(event)
    local entity = event and event.entity
    if not (entity and entity.valid and entity.unit_number and entity.surface) then return end
    local state = root().surfaces[entity.surface.index]
    if not state then return end
    if state.settlers then state.settlers[entity.unit_number] = nil end
    if state.worms then state.worms[entity.unit_number] = nil end
    if QUEEN_NAME_SET[entity.name] then
        for _, zone_id in ipairs(ZONE_ORDER) do
            local record = state.queens[zone_id]
            if record and record.unit_number == entity.unit_number then
                state.queens[zone_id] = nil
                break
            end
        end
    end
end

function growth.on_surface_deleted(event)
    if not (event and event.surface_index) then return end
    local value = root()
    value.surfaces[event.surface_index] = nil
    recompute_next_worm_tick(value)
end

return growth
