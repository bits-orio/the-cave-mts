local physical = require("scripts.player_physical")
local portable_cave_accumulators = require("scripts.portable_cave_accumulators")
local settings = require("scripts.game_settings").proxy(settings)
local interior_pollution = require("scripts.interior_pollution")

local shelter_core = {
    worlds = require("scripts.cave_worlds"),
    teams = require("scripts.cave_teams"),
    defeat = require("scripts.main_train_defeat"),
}
local shelter_garden = { maintenance = require("scripts.interior_maintenance") }
shelter_garden.item_transfer = require("scripts.interior_item_transfer")
local train_wave_defense = require("scripts.train_wave_defense")

local SURFACE_PREFIX = "the-cave-shelter-interior-"
local GARDEN_SURFACE_PREFIX = "the-cave-shelter-garden-surface-"
local SHELTER_NAME = "the-cave-shelter"
local SUBSTATION_NAME = "the-cave-shelter-substation"
local GARDEN_SUBSTATION_NAME = "the-cave-shelter-garden-substation"
local OUTPUT_POLE_NAME = "the-cave-shelter-output-pole"
local LEGACY_OUTPUT_ACCUMULATOR_NAME = "the-cave-shelter-battery-output"
local INPUT_INTERFACE_NAMES = {}
local OUTPUT_INTERFACE_NAMES = {}
local LEGACY_OUTPUT_BUFFER_NAMES = {}
for level = 1, 20 do
    INPUT_INTERFACE_NAMES[level] = "the-cave-shelter-battery-charge-interface-l" .. level
    OUTPUT_INTERFACE_NAMES[level] = "the-cave-shelter-battery-discharge-interface-l" .. level
    LEGACY_OUTPUT_BUFFER_NAMES[level] = "the-cave-shelter-battery-discharge-buffer-l" .. level
end
local LEGACY_INPUT_NAMES = {
    "the-cave-shelter-battery-input-l1",
    "the-cave-shelter-battery-input-l2",
    "the-cave-shelter-battery-input-l3",
    "the-cave-shelter-battery-input-l4",
    "the-cave-shelter-battery-input-l5",
    "the-cave-shelter-battery-input-l6",
}
local POWER_BRIDGE_VERSION = "3.1.73-train-interface-parity-v1"
local OUTPUT_BUFFER_RUNTIME_VERSION = "3.1.73-train-window-v1"
local OUTPUT_RANGE_VERSION = "3.1.73-wire-only-pole-v1"
local POWER_SYNC_INTERVAL_TICKS = 15
local INTERIOR_POLLUTION_SYNC_TICKS = 3 * 60
local INTERIOR_POLLUTION_TRANSFER_VERSION = 1
local EXPANSION_PREFIX = "the-cave-shelter-interior-expansion-"
local BATTERY_PREFIX = "the-cave-shelter-battery-upgrade-"
local SHIELD_PREFIX = "the-cave-shelter-shield-upgrade-"
local ATTACK_DISTANCE_PREFIX = "the-cave-shelter-attack-distance-"
local GARDEN_PREFIX = "the-cave-shelter-garden-"
local STOREHOUSE_NAME = "the-cave-6x6-container"
local GARDEN_STOREBOX_NAME = "the-cave-2x2-container"
local FLUID_INPUT_NAME = "the-cave-shelter-fluid-input"
local FLUID_OUTPUT_NAME = "the-cave-shelter-fluid-output"
local TRANSFER_LAYOUT_VERSION = 6
local GARDEN_LAYOUT_VERSION = "3.1.70-shelter-garden-v1"
local GARDEN_INFRASTRUCTURE_VERSION = "3.1.70-items-only-v1"
local GARDEN_VOID_LAYOUT_VERSION = "3.1.70-stage-floor-v1"
local GARDEN_SURFACE_VERSION = "3.1.70-ordinary-grid-v1"
local GARDEN_MAX_LEVEL = 3
local GARDEN_STAGE_HALF_SIZES = { 30, 42, 54 }
local GARDEN_CENTER_SIZE = 18
local GARDEN_WATER_WIDTH = 12
local GARDEN_WATER_DEPTH = 4
local GARDEN_PORTAL_SPRITE = "the-cave-shelter-garden-portal"
local GARDEN_UPPER_ITEM_INPUT = { x = -6, y = -15 }
local GARDEN_UPPER_ITEM_OUTPUT = { x = 5, y = -15 }
local GARDEN_LOWER_ITEM_INPUT = { x = -10, y = 6 }
local GARDEN_LOWER_ITEM_OUTPUT = { x = 9, y = 6 }
local ITEM_TRANSFER_SNAPSHOT_VERSION = 2
local FLUID_TRANSFER_PER_SYNC = 5000
local MAX_HEALTH = 5000
local SHIELD_HEALTH_PER_LEVEL = 3000
local SHIELD_MAX_LEVEL = 10
local SHIELD_REPAIR_PER_LEVEL = 5
local SHIELD_REPAIR_DELAY_TICKS = 10 * 60
local SHIELD_PHYSICAL_MAX_HEALTH = MAX_HEALTH + SHIELD_HEALTH_PER_LEVEL * SHIELD_MAX_LEVEL
local SHIELD_VERSION = "3.1.69-fixed-shelter-shield-v1"
local RESPAWN_OFFSET = { x = 0, y = 10 }
local POWER_RANGE_HALF_SIZE = 7.5
local UTILITY_LANE_DEPTH = 10
local LEGACY_UTILITY_LANE_DEPTH = 4
local POWER_CAPACITY_MJ = {
    2000, 2500, 3200, 4200, 5500,
    7000, 9000, 12000, 15000, 20000,
    25000, 32000, 42000, 55000, 70000,
    90000, 120000, 150000, 200000, 250000,
}
local POWER_CHARGE_RATE_MW = {
    50, 100, 150, 200, 250,
    300, 350, 400, 450, 500,
    550, 600, 650, 700, 750,
    800, 850, 900, 950, 1000,
}
local POWER_OUTPUT_RATE_MW = {
    50, 100, 150, 250, 400, 600,
    600, 600, 600, 600, 600, 600, 600,
    600, 600, 600, 600, 600, 600, 600,
}
local ROOM_DIMENSIONS = {
    { width = 40, height = 40 },
    { width = 90, height = 90 },
    { width = 120, height = 120 },
    { width = 150, height = 150 },
    { width = 180, height = 180 },
    { width = 210, height = 210 },
    { width = 240, height = 240 },
    { width = 270, height = 270 },
    { width = 300, height = 300 },
}
local UTILITY_ALLOWED_ENTITY_TYPES = {
    ["pipe"] = true,
    ["pipe-to-ground"] = true,
    ["pump"] = true,
    ["storage-tank"] = true,
    ["electric-pole"] = true,
}
local UTILITY_ALLOWED_ENTITY_NAMES = {
    ["small-electric-pole"] = true,
    ["medium-electric-pole"] = true,
    ["big-electric-pole"] = true,
    ["substation"] = true,
    ["the-cave-big-wooden-pole"] = true,
}
local UTILITY_BLOCKED_ENTITY_NAMES = {
    ["offshore-pump"] = true,
}
local J_PER_MJ = 1000000
local ENTRY_PROMPT = "the_cave_shelter_entry_prompt"
local LEGACY_HOVER_FRAME = "the_cave_shelter_hover"
local DEFEAT_FRAME = "the_cave_shelter_defeat"
local OUTSIDE_VIEW_FRAME = "the_cave_shelter_minimap"
local OUTSIDE_VIEW_CAMERA = "the_cave_shelter_camera"

local soft_reset_handler = nil

local function valid(object)
    return object and object.valid
end

local function startup_modes()
    local startup = settings and settings.startup
    local train_setting = startup and startup["the-cave-train-interiors"]
    local shelter_setting = startup and startup["the-cave-shelter-defense"]
    local train_requested = train_setting
        and (train_setting.value == "enabled" or train_setting.value == true)
    local shelter_requested = shelter_setting
        and (shelter_setting.value == "enabled" or shelter_setting.value == true)
    return shelter_requested and not train_requested,
        shelter_requested and train_requested
end

local function startup_enabled()
    local enabled = startup_modes()
    return enabled
end

local function print_startup_conflict()
    local _, conflict = startup_modes()
    if not (conflict and game) then return end
    game.print({ "the-cave-shelter.settings-conflict" }, { r = 1, g = 0.25, b = 0.10 })
end

function shelter_core.is_enabled()
    return startup_enabled()
end

function shelter_core.is_shelter_garden_surface(surface)
    return valid(surface)
        and type(surface.name) == "string"
        and surface.name:sub(1, #GARDEN_SURFACE_PREFIX) == GARDEN_SURFACE_PREFIX
end

function shelter_core.is_shelter_surface(surface)
    return valid(surface)
        and type(surface.name) == "string"
        and (surface.name:sub(1, #SURFACE_PREFIX) == SURFACE_PREFIX
            or shelter_core.is_shelter_garden_surface(surface))
end

local function root(create)
    if not storage then return nil end
    if create then
        storage.the_cave_shelter_core = storage.the_cave_shelter_core or {}
    end
    local value = storage.the_cave_shelter_core
    if value and create then
        value.forces = value.forces or {}
        value.by_entity_unit = value.by_entity_unit or {}
        value.defeats = value.defeats or {}
        value.player_states = value.player_states or {}
        value.selected_port_render = value.selected_port_render or {}
        value.selected_shelter_render = value.selected_shelter_render or {}
        value.selected_substation_render = value.selected_substation_render or {}
    end
    return value
end

local function record_for_force(force)
    local state = root(false)
    return state and force and state.forces and state.forces[force.index] or nil
end

function shelter_core.get_anchor(force)
    local record = record_for_force(force)
    return record and valid(record.entity) and record.entity or nil
end

local function researched_level(force, prefix, maximum)
    if not (force and force.valid and force.technologies) then return 0 end
    local level = 0
    for index = 1, maximum do
        local technology = force.technologies[prefix .. index]
        if technology and technology.researched then level = index end
    end
    return level
end

local function shelter_shield_level(force)
    return researched_level(force, SHIELD_PREFIX, SHIELD_MAX_LEVEL)
end

local function shelter_shield_max_health(level)
    level = math.max(0, math.min(SHIELD_MAX_LEVEL, tonumber(level) or 0))
    return MAX_HEALTH + SHIELD_HEALTH_PER_LEVEL * level
end

local function shelter_shield_repair_per_second(level)
    level = math.max(0, math.min(SHIELD_MAX_LEVEL, tonumber(level) or 0))
    return SHIELD_REPAIR_PER_LEVEL * level
end

local function shelter_physical_max_health(entity)
    local maximum = SHIELD_PHYSICAL_MAX_HEALTH
    pcall(function()
        local prototype = entity and entity.prototype
        if prototype and prototype.get_max_health then
            maximum = tonumber(prototype.get_max_health(entity.quality)) or maximum
        end
    end)
    pcall(function()
        if tonumber(entity and entity.max_health) then maximum = tonumber(entity.max_health) end
    end)
    return math.max(1, tonumber(maximum) or SHIELD_PHYSICAL_MAX_HEALTH)
end

local function sync_shelter_physical_health(record)
    local entity = record and record.entity
    if not valid(entity) then return false end
    local maximum = math.max(1, tonumber(record.shield_max_health) or MAX_HEALTH)
    local health = math.max(0, math.min(maximum,
        tonumber(record.shield_health) or maximum))
    if health <= 0 then return false end
    local physical = shelter_physical_max_health(entity)
    pcall(function()
        entity.health = math.max(1, math.min(physical, physical * health / maximum))
    end)
    return true
end

local function ensure_shelter_shield(record, force, preserve_ratio)
    if not (record and valid(record.entity)) then return nil end
    force = force or record.entity.force
    local level = shelter_shield_level(force)
    local maximum = shelter_shield_max_health(level)
    local old_maximum = tonumber(record.shield_max_health)
    local old_health = tonumber(record.shield_health)

    if record.shield_version ~= SHIELD_VERSION then
        local ratio = 1
        if old_maximum and old_maximum > 0 and old_health then
            ratio = old_health / old_maximum
        else
            -- Before 3.1.69 the prototype ceiling was exactly 5,000 HP. A
            -- loaded entity retains that numeric health after the data-stage
            -- ceiling grows to 35,000, so use the former ceiling once when
            -- converting an existing save into the scripted Shield pool.
            local legacy_health = math.max(0, tonumber(record.entity.health) or MAX_HEALTH)
            if legacy_health > MAX_HEALTH then
                -- Factorio normally retains the old numeric HP, but tolerate
                -- another mod/runtime having scaled it to the new prototype
                -- ceiling before this migration runs.
                ratio = legacy_health / shelter_physical_max_health(record.entity)
            else
                ratio = legacy_health / MAX_HEALTH
            end
        end
        record.shield_health = maximum * math.max(0, math.min(1, ratio))
        record.shield_max_health = maximum
        record.shield_level = level
        record.shield_last_damage_tick = tonumber(record.shield_last_damage_tick) or 0
        record.shield_version = SHIELD_VERSION
    elseif old_maximum ~= maximum or tonumber(record.shield_level) ~= level then
        old_maximum = math.max(1, old_maximum or shelter_shield_max_health(record.shield_level))
        old_health = math.max(0, math.min(old_maximum, old_health or old_maximum))
        local ratio = old_health / old_maximum
        record.shield_health = preserve_ratio and (maximum * ratio)
            or math.min(maximum, old_health)
        record.shield_max_health = maximum
        record.shield_level = level
    end

    record.shield_level = level
    record.shield_max_health = maximum
    record.shield_health = math.max(0, math.min(maximum,
        tonumber(record.shield_health) or maximum))
    record.shield_last_damage_tick = tonumber(record.shield_last_damage_tick) or 0
    record.shield_version = SHIELD_VERSION
    sync_shelter_physical_health(record)
    return record
end

function shelter_core.attack_distance_chunks(force)
    return 10 + researched_level(force, ATTACK_DISTANCE_PREFIX, 8) * 2
end

function shelter_core.generation_radius_chunks(force)
    return shelter_core.attack_distance_chunks(force) + 2
end

local function surface_for_record(record)
    if not (record and record.surface_index) then return nil end
    return game.surfaces[record.surface_index]
end

local function garden_surface_for_record(record)
    local garden = record and record.garden
    if not (garden and garden.surface_index) then return nil end
    return game.surfaces[garden.surface_index]
end

local function external_surface_for_record(record)
    if not (record and record.external_surface_index) then return nil end
    return game.surfaces[record.external_surface_index]
end

local function initialize_shelter_pollution_transfer()
    local state = root(true)
    if state.pollution_transfer_version == INTERIOR_POLLUTION_TRANSFER_VERSION then return false end
    for _, record in pairs(state.forces or {}) do
        interior_pollution.clear(surface_for_record(record))
        interior_pollution.clear(garden_surface_for_record(record))
    end
    state.pollution_transfer_version = INTERIOR_POLLUTION_TRANSFER_VERSION
    return true
end

local function sync_shelter_pollution()
    if initialize_shelter_pollution_transfer() then return end
    local state = root(false)
    for force_index, record in pairs(state and state.forces or {}) do
        local shelter = record and record.entity
        local interior = surface_for_record(record)
        if valid(shelter) and valid(interior) then
            interior_pollution.transfer {
                key = "shelter:" .. tostring(force_index),
                mode = "Shelter",
                interior_surface = interior,
                exterior_surface = shelter.surface,
                position = shelter.position,
            }
            local garden_surface = garden_surface_for_record(record)
            if valid(garden_surface) then
                interior_pollution.transfer {
                    key = "shelter-garden:" .. tostring(force_index),
                    mode = "Shelter Garden",
                    interior_surface = garden_surface,
                    exterior_surface = shelter.surface,
                    position = shelter.position,
                }
            end
        end
    end
end

local function room_bounds(dimensions)
    local total_width = dimensions.width + UTILITY_LANE_DEPTH * 2
    local total_height = dimensions.height + UTILITY_LANE_DEPTH * 2
    local left = -math.floor(total_width / 2)
    local top = -math.floor(total_height / 2)
    return left, left + total_width - 1, top, top + total_height - 1
end

local function legacy_room_bounds(dimensions)
    local left = -math.floor(dimensions.width / 2)
    local top = -math.floor(dimensions.height / 2)
    return left, left + dimensions.width - 1, top, top + dimensions.height - 1
end

local function tile_or_fallback(name, fallback)
    return prototypes.tile[name] and name or fallback
end

local function paint_room(record, force, initial)
    local surface = surface_for_record(record)
    if not valid(surface) then return end
    local level = researched_level(force, EXPANSION_PREFIX, 8)
    local dimensions = ROOM_DIMENSIONS[level + 1] or ROOM_DIMENSIONS[1]
    -- New Shelter games start at the locked 40x40 floor. Do not contract an
    -- already occupied 60x60 level-zero room from an older save; it keeps its
    -- grandfathered footprint until Expansion 1 grows it to 90x90.
    if not initial and level == 0 and record.expansion_level == 0
        and record.room_dimensions
        and (record.room_dimensions.width > dimensions.width
            or record.room_dimensions.height > dimensions.height) then
        dimensions = record.room_dimensions
    end
    local left, right, top, bottom = room_bounds(dimensions)
    local floor = tile_or_fallback("black-refined-concrete", "refined-concrete")
    local utility = tile_or_fallback("blue-refined-concrete", tile_or_fallback("blue-concrete", floor))
    local core = tile_or_fallback("green-refined-concrete", tile_or_fallback("green-concrete", floor))
    local tiles = {}
    local old_left, old_right, old_top, old_bottom
    local previous_utility_lane_depth = math.max(1,
        math.floor(tonumber(record.utility_lane_depth) or LEGACY_UTILITY_LANE_DEPTH))
    local lane_outside_room = record.utility_lane_outside_room == true
    local dimensions_changed = record.room_dimensions
        and (record.room_dimensions.width ~= dimensions.width
            or record.room_dimensions.height ~= dimensions.height)

    if not initial and record.room_dimensions then
        if lane_outside_room then
            old_left, old_right, old_top, old_bottom = room_bounds(record.room_dimensions)
        else
            -- 3.0.14 and earlier counted the blue lane inside the advertised
            -- room dimensions. Read that legacy footprint once so its blue
            -- tiles become normal floor before the new outside lane is added.
            old_left, old_right, old_top, old_bottom = legacy_room_bounds(record.room_dimensions)
        end
        if dimensions_changed or not lane_outside_room then
            for x = old_left, old_right do
                for y = old_top, old_bottom do
                    local old_tile = surface.get_tile(x, y)
                    -- Existing test saves can still own the former four-tile
                    -- blue lane. Remove that complete legacy border before
                    -- painting the new ten-tile lane at the expanded edge.
                    local old_border = x < old_left + previous_utility_lane_depth
                        or x > old_right - previous_utility_lane_depth
                        or y < old_top + previous_utility_lane_depth
                        or y > old_bottom - previous_utility_lane_depth
                    if old_border and old_tile and old_tile.valid
                        and (old_tile.name == "blue-refined-concrete" or old_tile.name == "blue-concrete") then
                        tiles[#tiles + 1] = { name = floor, position = { x = x, y = y } }
                    end
                end
            end
        end
    end

    for x = left, right do
        for y = top, bottom do
            local old_tile = surface.get_tile(x, y)
            local inside_previous_room = false
            if old_left then
                inside_previous_room = x >= old_left and x <= old_right
                    and y >= old_top and y <= old_bottom
            end
            local current_border = x < left + UTILITY_LANE_DEPTH
                or x > right - UTILITY_LANE_DEPTH
                or y < top + UTILITY_LANE_DEPTH
                or y > bottom - UTILITY_LANE_DEPTH
            local needs_current_lane = current_border and old_tile and old_tile.valid
                and old_tile.name ~= utility
            if initial or not inside_previous_room or needs_current_lane
                or (old_tile and old_tile.valid and old_tile.name == "out-of-map") then
                local name = floor
                if current_border then
                    name = utility
                end
                tiles[#tiles + 1] = { name = name, position = { x = x, y = y } }
            end
        end
    end

    -- Match the established Train Interiors start geometry: a fixed 36x36
    -- green transfer/build core inside the 40x40 level-zero main floor.
    for x = -18, 17 do
        for y = -18, 17 do
            tiles[#tiles + 1] = { name = core, position = { x = x, y = y } }
        end
    end
    local water = tile_or_fallback("water", floor)
    for x = -6, 5 do
        for y = -8, -5 do
            local name = (x >= -3 and x <= 2) and core or water
            tiles[#tiles + 1] = { name = name, position = { x = x, y = y } }
        end
    end
    local pad = tile_or_fallback("refined-concrete", floor)
    for x = -2, 1 do
        for y = -2, 1 do
            tiles[#tiles + 1] = { name = pad, position = { x = x, y = y } }
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles, true, false, false, false) end
    record.expansion_level = level
    record.room_dimensions = dimensions
    record.utility_lane_depth = UTILITY_LANE_DEPTH
    record.utility_lane_outside_room = true
end

local function void_area(surface, area, preserve_dimensions)
    if not (valid(surface) and area and area.left_top and area.right_bottom) then return end
    local preserve_left, preserve_right, preserve_top, preserve_bottom
    if preserve_dimensions then
        preserve_left, preserve_right, preserve_top, preserve_bottom = room_bounds(preserve_dimensions)
    end
    local tiles = {}
    local function flush()
        if #tiles > 0 then
            surface.set_tiles(tiles, true, false, false, false)
            tiles = {}
        end
    end
    local left = math.floor(area.left_top.x)
    local right = math.ceil(area.right_bottom.x) - 1
    local top = math.floor(area.left_top.y)
    local bottom = math.ceil(area.right_bottom.y) - 1
    for x = left, right do
        for y = top, bottom do
            local preserve = preserve_dimensions
                and x >= preserve_left and x <= preserve_right
                and y >= preserve_top and y <= preserve_bottom
            if not preserve then
                tiles[#tiles + 1] = { name = "out-of-map", position = { x = x, y = y } }
                if #tiles >= 8192 then flush() end
            end
        end
    end
    flush()
end

local function void_generated_chunks(surface, preserve_dimensions)
    if not valid(surface) then return end
    for chunk in surface.get_chunks() do
        local left = chunk.x * 32
        local top = chunk.y * 32
        void_area(surface, {
            left_top = { x = left, y = top },
            right_bottom = { x = left + 32, y = top + 32 },
        }, preserve_dimensions)
    end
end

local function record_for_surface(surface)
    local state = root(false)
    if not (valid(surface) and state and state.forces) then return nil end
    for _, record in pairs(state.forces) do
        if record and (record.surface_index == surface.index
            or (record.garden and record.garden.surface_index == surface.index)) then
            return record
        end
    end
    return nil
end

local function chart_shelter_interior(record, force)
    local surface = surface_for_record(record)
    if not (valid(surface) and force and force.valid) then return end
    local dimensions = record.room_dimensions or ROOM_DIMENSIONS[1]
    local left, right, top, bottom = room_bounds(dimensions)
    -- Keep the private interior selectable in normal map view, then reveal
    -- exactly the current main floor plus its four ten-tile utility lanes.
    pcall(function() force.set_surface_hidden(surface, false) end)
    pcall(function()
        force.chart(surface, {
            { left, top },
            { right + 1, bottom + 1 },
        })
    end)
end

local function configure_interior_surface(surface)
    -- Shelter interiors use ordinary pole coverage. Explicitly retire a global
    -- electric network if an old/editor/modded save ever enabled one here.
    -- This call is idempotent and runs during existing-save configuration.
    pcall(function()
        if surface.has_global_electric_network and surface.destroy_global_electric_network then
            surface.destroy_global_electric_network()
        end
    end)
    surface.no_enemies_mode = true
    surface.freeze_daytime = true
    surface.always_day = true
    surface.daytime = 0.1
    surface.solar_power_multiplier = 1
    surface.show_clouds = false
end

local function create_interior_surface(force)
    local name = SURFACE_PREFIX .. tostring(force.index)
    local surface = game.surfaces[name]
    if not valid(surface) then
        surface = game.create_surface(name, {
            water = 0,
            starting_area = 1,
            cliff_settings = { cliff_elevation_interval = 0, cliff_elevation_0 = 0 },
            autoplace_settings = {
                entity = { settings = {}, treat_missing_as_default = false },
                decorative = { settings = {}, treat_missing_as_default = false },
            },
        })
    end
    configure_interior_surface(surface)
    surface.request_to_generate_chunks({ 0, 0 }, 6)
    surface.force_generate_chunk_requests()
    -- Interior chunks use the normal map generator underneath. Blank every
    -- generated chunk before the scripted room is painted so no Nauvis or
    -- Space Age planetary terrain can appear around the Shelter.
    void_generated_chunks(surface, nil)
    return surface
end

local function protect_transfer_fixture(entity)
    if not valid(entity) then return nil end
    entity.destructible = false
    entity.minable_flag = false
    entity.operable = true
    return entity
end

local function matching_fixture(entity, surface, name, position)
    return valid(entity)
        and entity.surface == surface
        and entity.name == name
        and math.abs(entity.position.x - position.x) <= 0.6
        and math.abs(entity.position.y - position.y) <= 0.6
end

local function find_or_create_fixture(surface, current, name, position, force, direction)
    if matching_fixture(current, surface, name, position) then
        return protect_transfer_fixture(current)
    end
    for _, candidate in pairs(surface.find_entities_filtered {
        name = name,
        position = position,
        radius = 0.8,
        force = force,
    }) do
        if matching_fixture(candidate, surface, name, position) then
            return protect_transfer_fixture(candidate)
        end
    end
    local ok, created = pcall(function()
        return surface.create_entity {
            name = name,
            position = position,
            direction = direction,
            force = force,
            create_build_effect_smoke = false,
        }
    end)
    return ok and protect_transfer_fixture(created) or nil
end

local function move_inventory_contents(source, destination)
    if not (source and source.valid and destination and destination.valid) then return end
    if source.is_empty() then return end
    for slot = 1, #source do
        local stack = source[slot]
        if stack and stack.valid_for_read then
            local count = stack.count
            local inserted = 0
            local ok = pcall(function() inserted = destination.insert(stack) end)
            if not ok then
                local definition = { name = stack.name, count = count }
                local quality_ok, quality = pcall(function() return stack.quality end)
                if quality_ok and quality then definition.quality = quality.name or quality end
                inserted = destination.insert(definition)
            end
            if inserted >= count then
                stack.clear()
            elseif inserted > 0 then
                stack.count = count - inserted
            end
        end
    end
end

-- Shelter Garden Floor -----------------------------------------------------
--
-- This is intentionally a Shelter-owned copy of the established Train Garden
-- behaviour. The surfaces, technology state, fixtures and player portals are
-- independent, while the proven floor sizes and item-transfer directions stay
-- identical. Shelter Garden has item Store Boxes only: no fluid endpoints are
-- created or synchronized anywhere in this subsystem.

local function garden_stage(force)
    return researched_level(force, GARDEN_PREFIX, GARDEN_MAX_LEVEL)
end

local function garden_area(stage)
    stage = math.max(1, math.min(GARDEN_MAX_LEVEL, tonumber(stage) or 1))
    local half = GARDEN_STAGE_HALF_SIZES[stage] or GARDEN_STAGE_HALF_SIZES[1]
    return -half, half, -half, half
end

local function garden_center_bounds()
    local half = GARDEN_CENTER_SIZE * 0.5
    return math.floor(-half), math.floor(half), math.floor(-half), math.floor(half)
end

local function garden_water_bounds()
    local _, _, core_top = garden_center_bounds()
    local left = math.floor(-(GARDEN_WATER_WIDTH * 0.5))
    local right = left + GARDEN_WATER_WIDTH
    local top = core_top - GARDEN_WATER_DEPTH + 2
    return left, right, top, top + GARDEN_WATER_DEPTH
end

local function garden_substation_island_bounds()
    local left, right, top, bottom = garden_water_bounds()
    local size = 2
    local island_left = math.floor(((left + right) - size) * 0.5)
    local island_top = math.floor(((top + bottom) - size) * 0.5)
    return island_left, island_left + size, island_top, island_top + size
end

local function garden_upper_portal_bounds()
    -- Locked Shelter placement: exact 2x2 portal centred at (0, -12).
    return -1, 1, -13, -11
end

local function garden_lower_portal_bounds()
    -- Match the established Train Garden lower portal geometry exactly.
    return -1, 1, 5, 7
end

local function garden_landing_bounds()
    return -2, 2, -2, 2
end

local function position_in_bounds(position, left, right, top, bottom)
    return position and position.x >= left and position.x < right
        and position.y >= top and position.y < bottom
end

local function boxes_overlap(a, b)
    return a and b
        and a.right_bottom.x > b.left_top.x
        and a.left_top.x < b.right_bottom.x
        and a.right_bottom.y > b.left_top.y
        and a.left_top.y < b.right_bottom.y
end

local function garden_lower_storebox_pad_contains(x, y)
    local half = 2 -- artwork is visually 4x4 although collision is 2x2
    local function contains(center)
        return x >= math.floor(center.x - half) and x < math.floor(center.x + half)
            and y >= math.floor(center.y - half) and y < math.floor(center.y + half)
    end
    return contains(GARDEN_LOWER_ITEM_INPUT) or contains(GARDEN_LOWER_ITEM_OUTPUT)
end

local function garden_tile_is_layout(garden, x, y)
    local stage = math.max(0, math.min(GARDEN_MAX_LEVEL,
        tonumber(garden and garden.stage) or 0))
    if stage > 0 then
        local left, right, top, bottom = garden_area(stage)
        return x >= left and x < right and y >= top and y < bottom
    end

    local left, right, top, bottom = garden_center_bounds()
    if x >= left and x < right and y >= top and y < bottom then return true end
    if garden_lower_storebox_pad_contains(x, y) then return true end
    left, right, top, bottom = garden_water_bounds()
    return x >= left and x < right and y >= top and y < bottom
end

local function garden_void_area(surface, area, garden)
    if not (valid(surface) and shelter_core.is_shelter_garden_surface(surface)
        and area and area.left_top and area.right_bottom) then return 0 end
    local tiles = {}
    local converted = 0
    local function flush()
        if #tiles > 0 then
            surface.set_tiles(tiles, true, false, false, false)
            tiles = {}
        end
    end
    local left = math.floor(area.left_top.x)
    local right = math.ceil(area.right_bottom.x) - 1
    local top = math.floor(area.left_top.y)
    local bottom = math.ceil(area.right_bottom.y) - 1
    for x = left, right do
        for y = top, bottom do
            if not garden_tile_is_layout(garden, x, y) then
                tiles[#tiles + 1] = { name = "out-of-map", position = { x = x, y = y } }
                converted = converted + 1
                if #tiles >= 8192 then flush() end
            end
        end
    end
    flush()
    return converted
end

local function garden_void_generated_chunks(surface, garden)
    if not valid(surface) then return end
    for chunk in surface.get_chunks() do
        local left = chunk.x * 32
        local top = chunk.y * 32
        garden_void_area(surface, {
            left_top = { x = left, y = top },
            right_bottom = { x = left + 32, y = top + 32 },
        }, garden)
    end
    garden.void_layout_version = GARDEN_VOID_LAYOUT_VERSION
    garden.voided_surface_index = surface.index
end

local function configure_garden_surface(surface)
    if not valid(surface) then return end
    pcall(function()
        local map_settings = surface.map_gen_settings
        map_settings.width = 0
        map_settings.height = 0
        surface.map_gen_settings = map_settings
    end)
    pcall(function()
        if surface.has_global_electric_network and surface.destroy_global_electric_network then
            surface.destroy_global_electric_network()
        end
    end)
    surface.no_enemies_mode = true
    surface.freeze_daytime = true
    surface.always_day = true
    surface.daytime = 0.1
    surface.solar_power_multiplier = 1
    surface.show_clouds = false
end

function shelter_garden.create_surface(record, force)
    record.garden = record.garden or {}
    local garden = record.garden
    local name = GARDEN_SURFACE_PREFIX .. tostring(force.index)
    local surface = game.surfaces[name]
    local created = false
    if not valid(surface) then
        surface = game.create_surface(name, {
            water = 0,
            starting_area = 1,
            cliff_settings = { cliff_elevation_interval = 0, cliff_elevation_0 = 0 },
            autoplace_settings = {
                entity = { settings = {}, treat_missing_as_default = false },
                tile = { settings = {}, treat_missing_as_default = false },
                decorative = { settings = {}, treat_missing_as_default = false },
            },
        })
        created = true
    end
    if not valid(surface) then return nil end

    garden.force_index = force.index
    garden.surface_index = surface.index
    garden.surface_name = surface.name
    garden.stage = garden_stage(force)
    if created or garden.surface_version ~= GARDEN_SURFACE_VERSION then
        configure_garden_surface(surface)
        garden.surface_version = GARDEN_SURFACE_VERSION
    end
    if created or garden.generated_surface_index ~= surface.index then
        -- Stage 3 is 108x108. Four chunks around the origin cover it plus the
        -- cleanup margin, and later chunk events void anything generated outside.
        surface.request_to_generate_chunks({ x = 0, y = 0 }, 4)
        surface.force_generate_chunk_requests()
        garden.generated_surface_index = surface.index
    end
    pcall(function() force.set_surface_hidden(surface, false) end)
    return surface
end

function shelter_garden.paint(record, force)
    local garden = record and record.garden
    local surface = garden_surface_for_record(record)
    if not (garden and valid(surface) and force and force.valid) then return end

    local stage = garden_stage(force)
    garden.stage = stage
    local cleanup_stage = math.max(1, stage, tonumber(garden.painted_stage) or 0)
    local left, right, top, bottom = garden_area(cleanup_stage)
    local core_left, core_right, core_top, core_bottom = garden_center_bounds()
    local portal_left, portal_right, portal_top, portal_bottom = garden_lower_portal_bounds()
    local landing_left, landing_right, landing_top, landing_bottom = garden_landing_bounds()
    local water_left, water_right, water_top, water_bottom = garden_water_bounds()
    local island_left, island_right, island_top, island_bottom = garden_substation_island_bounds()

    local target = {
        x = (landing_left + landing_right) * 0.5,
        y = (landing_top + landing_bottom) * 0.5,
    }
    for _, player in pairs(game.connected_players or {}) do
        if physical.on_surface(player, surface) then
            local safe = physical.find_position(player, surface, target, 4, 0.25)
            pcall(function() player.driving = false end)
            if not physical.teleport(player, safe, surface) then return false end
        end
    end

    local center_tile = tile_or_fallback("green-refined-concrete",
        tile_or_fallback("green-concrete", "refined-concrete"))
    local landing_tile = tile_or_fallback("refined-concrete", center_tile)
    local yumako_tile = tile_or_fallback("artificial-yumako-soil",
        tile_or_fallback("natural-yumako-soil", landing_tile))
    local jellynut_tile = tile_or_fallback("artificial-jellynut-soil",
        tile_or_fallback("natural-jellynut-soil", landing_tile))
    local void_tile = tile_or_fallback("out-of-map", "out-of-map")

    local function in_bounds(x, y, l, r, t, b)
        return x >= l and x < r and y >= t and y < b
    end
    local function protected_occupant_on_tile(x, y)
        for _, entity in pairs(surface.find_entities_filtered {
            area = { { x, y }, { x + 1, y + 1 } },
        }) do
            if valid(entity) and entity.type ~= "character" and entity.name ~= "fish"
                and entity.name ~= GARDEN_SUBSTATION_NAME then
                return true
            end
        end
        return false
    end

    local margin = 24
    local tiles = {}
    local function flush()
        if #tiles > 0 then
            surface.set_tiles(tiles, true, false, false, false)
            tiles = {}
        end
    end
    for x = left - margin, right + margin - 1 do
        for y = top - margin, bottom + margin - 1 do
            local tile = void_tile
            if in_bounds(x, y, island_left, island_right, island_top, island_bottom) then
                local current = surface.get_tile(x, y)
                tile = protected_occupant_on_tile(x, y) and current.name or center_tile
            elseif in_bounds(x, y, water_left, water_right, water_top, water_bottom) then
                local current = surface.get_tile(x, y)
                tile = protected_occupant_on_tile(x, y) and current.name or "water"
            elseif in_bounds(x, y, landing_left, landing_right, landing_top, landing_bottom) then
                tile = landing_tile
            elseif in_bounds(x, y, portal_left, portal_right, portal_top, portal_bottom) then
                tile = center_tile
            elseif garden_lower_storebox_pad_contains(x, y) then
                tile = center_tile
            elseif in_bounds(x, y, core_left, core_right, core_top, core_bottom) then
                tile = center_tile
            elseif stage > 0 and in_bounds(x, y, left, right, top, bottom) then
                tile = x < 0 and yumako_tile or jellynut_tile
            end
            tiles[#tiles + 1] = { name = tile, position = { x = x, y = y } }
            if #tiles >= 20000 then flush() end
        end
    end
    flush()
    garden.painted_stage = stage
    garden.layout_version = GARDEN_LAYOUT_VERSION
    garden_void_generated_chunks(surface, garden)

    pcall(function()
        local chart_left, chart_right, chart_top, chart_bottom
        if stage > 0 then
            chart_left, chart_right, chart_top, chart_bottom = garden_area(stage)
        else
            chart_left, chart_right, chart_top, chart_bottom = -20, 20, -20, 20
        end
        force.chart(surface, {
            { chart_left, chart_top },
            { chart_right, chart_bottom },
        })
    end)
end

local function garden_render_object(id)
    if not id then return nil end
    local ok, object = pcall(function() return rendering.get_object_by_id(id) end)
    return ok and object or nil
end

local function destroy_garden_portal_renders(garden)
    for _, field in ipairs({ "upper_portal_render_id", "lower_portal_render_id" }) do
        local object = garden_render_object(garden and garden[field])
        if object then pcall(function() object.destroy() end) end
        if garden then garden[field] = nil end
    end
end

local function ensure_garden_portal_render(garden, field, surface, left, right, top, bottom, force)
    local current = garden_render_object(garden[field])
    if current then return current end
    garden[field] = nil
    local ok, object = pcall(function()
        return rendering.draw_sprite {
            sprite = GARDEN_PORTAL_SPRITE,
            surface = surface,
            target = { x = (left + right) * 0.5, y = (top + bottom) * 0.5 },
            forces = { force },
            draw_on_ground = true,
            only_in_alt_mode = false,
        }
    end)
    if ok and object then garden[field] = object.id end
    return ok and object or nil
end

local function garden_fixture_script_owned(entity)
    if not valid(entity) then return false end
    local minable_ok, minable = pcall(function() return entity.minable_flag end)
    local destructible_ok, destructible = pcall(function() return entity.destructible end)
    return (minable_ok and minable == false) or (destructible_ok and destructible == false)
end

local function garden_storebox_inventory(entity)
    if not (valid(entity) and entity.name == GARDEN_STOREBOX_NAME) then return nil end
    local ok, inventory = pcall(function() return entity.get_inventory(defines.inventory.chest) end)
    return ok and inventory and inventory.valid and inventory or nil
end

local function ensure_garden_storebox(garden, field, surface, position, force)
    local entity = garden[field]
    if matching_fixture(entity, surface, GARDEN_STOREBOX_NAME, position) then
        return protect_transfer_fixture(entity)
    end
    if valid(entity) and entity.surface == surface and entity.name == GARDEN_STOREBOX_NAME then
        local ok, moved = pcall(function() return entity.teleport(position) end)
        if ok and moved ~= false and matching_fixture(entity, surface, GARDEN_STOREBOX_NAME, position) then
            garden[field] = protect_transfer_fixture(entity)
            return garden[field]
        end
        -- A blocked migration keeps the live item property untouched and is
        -- retried during the next synchronization pass.
        return entity
    end

    local replacement = nil
    for _, candidate in pairs(surface.find_entities_filtered {
        name = GARDEN_STOREBOX_NAME,
        position = position,
        radius = 0.8,
        force = force,
    }) do
        if matching_fixture(candidate, surface, GARDEN_STOREBOX_NAME, position)
            and garden_fixture_script_owned(candidate) then
            replacement = candidate
            break
        end
    end
    if not valid(replacement) then
        local can_place = false
        pcall(function()
            can_place = surface.can_place_entity {
                name = GARDEN_STOREBOX_NAME,
                position = position,
                force = force,
            }
        end)
        if can_place then
            pcall(function()
                replacement = surface.create_entity {
                    name = GARDEN_STOREBOX_NAME,
                    position = position,
                    force = force,
                    create_build_effect_smoke = false,
                }
            end)
        end
    end
    if not valid(replacement) then return entity end
    replacement = protect_transfer_fixture(replacement)
    if valid(entity) and entity.unit_number ~= replacement.unit_number then
        local source = garden_storebox_inventory(entity)
        local destination = garden_storebox_inventory(replacement)
        move_inventory_contents(source, destination)
        if source and source.valid and source.is_empty() then
            pcall(function() entity.destroy() end)
        end
    end
    garden[field] = replacement
    return replacement
end

local function garden_copper_connector(entity)
    if not (valid(entity) and entity.get_wire_connector) then return nil end
    local ok, connector = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    end)
    return ok and connector and connector.valid and connector or nil
end

local function garden_connectors_linked(upper, lower)
    local ok, connected = pcall(function()
        return upper.is_connected_to(lower, defines.wire_origin.player)
            or upper.is_connected_to(lower, defines.wire_origin.script)
    end)
    return ok and connected == true
end

local function connect_garden_power(upper_substation, lower_substation)
    local upper = garden_copper_connector(upper_substation)
    local lower = garden_copper_connector(lower_substation)
    if not (upper and lower) then return false end
    if garden_connectors_linked(upper, lower) then return true end
    local connect_ok, connected = pcall(function()
        return upper.connect_to(lower, false, defines.wire_origin.script)
    end)
    if not connect_ok or connected == false then return false end
    return garden_connectors_linked(upper, lower)
end

function shelter_garden.infrastructure_ready(record, force)
    local garden = record and record.garden
    if not garden then return false end
    local upper_surface = surface_for_record(record)
    local lower_surface = garden_surface_for_record(record)
    return garden.infrastructure_version == GARDEN_INFRASTRUCTURE_VERSION
        and garden.layout_version == GARDEN_LAYOUT_VERSION
        and garden.void_layout_version == GARDEN_VOID_LAYOUT_VERSION
        and garden.stage == garden_stage(force) and garden.painted_stage == garden.stage
        and shelter_garden.maintenance.layout_ready(garden, force, upper_surface, lower_surface,
            { x = 0, y = 0 }, GARDEN_INFRASTRUCTURE_VERSION,
            record.substation, garden.lower_substation)
        and valid(garden_render_object(garden.upper_portal_render_id))
        and valid(garden_render_object(garden.lower_portal_render_id))
end

function shelter_garden.ensure_infrastructure(record, force)
    local garden = record and record.garden
    local upper_surface = surface_for_record(record)
    local lower_surface = garden_surface_for_record(record)
    if not (garden and valid(upper_surface) and valid(lower_surface)
        and force and force.valid) then return nil end

    if shelter_garden.infrastructure_ready(record, force) then return garden end
    garden.infrastructure_ready = nil
    if garden.infrastructure_version ~= GARDEN_INFRASTRUCTURE_VERSION then
        destroy_garden_portal_renders(garden)
        garden.infrastructure_version = GARDEN_INFRASTRUCTURE_VERSION
    end

    local upper_left, upper_right, upper_top, upper_bottom = garden_upper_portal_bounds()
    local lower_left, lower_right, lower_top, lower_bottom = garden_lower_portal_bounds()
    ensure_garden_portal_render(garden, "upper_portal_render_id", upper_surface,
        upper_left, upper_right, upper_top, upper_bottom, force)
    ensure_garden_portal_render(garden, "lower_portal_render_id", lower_surface,
        lower_left, lower_right, lower_top, lower_bottom, force)

    ensure_garden_storebox(garden, "upper_item_input", upper_surface,
        GARDEN_UPPER_ITEM_INPUT, force)
    ensure_garden_storebox(garden, "upper_item_output", upper_surface,
        GARDEN_UPPER_ITEM_OUTPUT, force)
    ensure_garden_storebox(garden, "lower_item_input", lower_surface,
        GARDEN_LOWER_ITEM_INPUT, force)
    ensure_garden_storebox(garden, "lower_item_output", lower_surface,
        GARDEN_LOWER_ITEM_OUTPUT, force)

    record.substation = find_or_create_fixture(upper_surface, record.substation,
        SUBSTATION_NAME, { x = -0.5, y = -6.5 }, force)
    local island_left, island_right, island_top, island_bottom = garden_substation_island_bounds()
    garden.lower_substation = find_or_create_fixture(lower_surface, garden.lower_substation,
        GARDEN_SUBSTATION_NAME, {
            x = (island_left + island_right) * 0.5,
            y = (island_top + island_bottom) * 0.5,
        }, force)
    connect_garden_power(record.substation, garden.lower_substation)
    shelter_garden.maintenance.remember_layout(garden, force, upper_surface, lower_surface,
        { x = 0, y = 0 }, GARDEN_INFRASTRUCTURE_VERSION,
        { "upper_item_input", "upper_item_output", "lower_item_input", "lower_item_output", "lower_substation" },
        record.substation, garden.lower_substation)
    return garden
end

function shelter_garden.ensure(record, force, force_repaint)
    if not (record and force and force.valid) then return nil end
    local surface = shelter_garden.create_surface(record, force)
    if not valid(surface) then return nil end
    local garden = record.garden
    local stage = garden_stage(force)
    if force_repaint or garden.stage ~= stage
        or garden.painted_stage ~= stage
        or garden.layout_version ~= GARDEN_LAYOUT_VERSION
        or garden.void_layout_version ~= GARDEN_VOID_LAYOUT_VERSION
        or garden.voided_surface_index ~= surface.index then
        garden.stage = stage
        if shelter_garden.paint(record, force) == false then return nil end
    end
    shelter_garden.ensure_infrastructure(record, force)
    return garden
end

local function sync_garden_items(record, force)
    local garden = record.garden
    if not shelter_garden.infrastructure_ready(record, force) then
        garden = shelter_garden.ensure(record, force, false)
    end
    if not garden then return end
    move_inventory_contents(
        garden_storebox_inventory(garden.upper_item_input),
        garden_storebox_inventory(garden.lower_item_input))
    move_inventory_contents(
        garden_storebox_inventory(garden.lower_item_output),
        garden_storebox_inventory(garden.upper_item_output))
end

local function create_fixed_storehouses(record, force)
    local surface = surface_for_record(record)
    if not valid(surface) then return end
    local previous_entities = record.transfer_entities or {}
    local previous_roles = record.transfer_roles or {}
    local definitions = {
        -- Same lower-corner placement as the Train Interiors Cargo Wagon:
        -- left Storehouse exports, right Storehouse imports.
        { role = "output", position = { x = -14, y = 14 }, temporary = { x = -22, y = 22 } },
        { role = "input", position = { x = 14, y = 14 }, temporary = { x = 22, y = 22 } },
    }

    local replacements = {}
    for _, definition in ipairs(definitions) do
        local current = nil
        for _, entity in ipairs(previous_entities) do
            if matching_fixture(entity, surface, STOREHOUSE_NAME, definition.position) then
                current = entity
                break
            end
        end
        if not valid(current) then
            for _, entity in ipairs(previous_entities) do
                if valid(entity) and entity.name == STOREHOUSE_NAME
                    and previous_roles[entity.unit_number] == definition.role then
                    pcall(function() entity.teleport(definition.position) end)
                    if matching_fixture(entity, surface, STOREHOUSE_NAME, definition.position) then
                        current = entity
                        break
                    end
                end
            end
        end
        if valid(current) then
            replacements[definition.role] = protect_transfer_fixture(current)
        else
            local old_role_entities = {}
            for _, entity in ipairs(previous_entities) do
                if valid(entity) and entity.name ~= STOREHOUSE_NAME
                    and previous_roles[entity.unit_number] == definition.role then
                    old_role_entities[#old_role_entities + 1] = entity
                end
            end

            if #old_role_entities > 0 then
                -- The old six Steel Chests occupy the Storehouse footprint.
                -- Stage their complete inventories in a temporary Storehouse,
                -- remove only emptied old chests, then move the protected
                -- Storehouse into its final fixed position.
                local temporary_position = surface.find_non_colliding_position(
                    STOREHOUSE_NAME, definition.temporary, 12, 1) or definition.temporary
                local temporary = find_or_create_fixture(
                    surface, nil, STOREHOUSE_NAME, temporary_position, force)
                if valid(temporary) then
                    local temporary_inventory = temporary.get_inventory(defines.inventory.chest)
                    for _, old in ipairs(old_role_entities) do
                        local source = old.get_inventory(defines.inventory.chest)
                        move_inventory_contents(source, temporary_inventory)
                    end
                    local all_empty = true
                    for _, old in ipairs(old_role_entities) do
                        local source = old.get_inventory(defines.inventory.chest)
                        if not (source and source.valid and source.is_empty()) then
                            all_empty = false
                            break
                        end
                    end
                    if all_empty then
                        for _, old in ipairs(old_role_entities) do
                            pcall(function() old.destroy() end)
                        end
                        pcall(function() temporary.teleport(definition.position) end)
                        if matching_fixture(temporary, surface, STOREHOUSE_NAME, definition.position) then
                            current = temporary
                        end
                    end
                end
            end
            replacements[definition.role] = current or find_or_create_fixture(
                surface, nil, STOREHOUSE_NAME, definition.position, force)
        end
    end

    local next_entities, next_roles = {}, {}
    for _, definition in ipairs(definitions) do
        local replacement = replacements[definition.role]
        if valid(replacement) then
            local destination = replacement.get_inventory(defines.inventory.chest)
            for _, old in ipairs(previous_entities) do
                if valid(old) and old.unit_number ~= replacement.unit_number
                    and previous_roles[old.unit_number] == definition.role then
                    local source = old.get_inventory(defines.inventory.chest)
                    move_inventory_contents(source, destination)
                    if source and source.valid and source.is_empty() then
                        pcall(function() old.destroy() end)
                    end
                end
            end
            next_entities[#next_entities + 1] = replacement
            next_roles[replacement.unit_number] = definition.role
        else
            for _, old in ipairs(previous_entities) do
                if valid(old) and previous_roles[old.unit_number] == definition.role then
                    next_entities[#next_entities + 1] = old
                    next_roles[old.unit_number] = definition.role
                end
            end
        end
    end
    record.transfer_entities = next_entities
    record.transfer_roles = next_roles
end

local function create_fluid_ports(record, force)
    local interior = surface_for_record(record)
    local exterior = external_surface_for_record(record)
    if not (valid(interior) and valid(exterior) and valid(record.entity)) then return end

    local old = record.fluid_ports or {}
    local migrating_layout = record.transfer_layout_version ~= TRANSFER_LAYOUT_VERSION
    local definitions = {
        { field = "interior_output_left", surface = interior, name = FLUID_OUTPUT_NAME,
            position = { x = -17.5, y = 16.5 }, role = "output", force_north = true },
        { field = "interior_output_right", surface = interior, name = FLUID_OUTPUT_NAME,
            position = { x = -10.5, y = 16.5 }, role = "output", force_north = true },
        { field = "interior_input_left", surface = interior, name = FLUID_INPUT_NAME,
            position = { x = 10.5, y = 16.5 }, role = "input", force_north = true },
        { field = "interior_input_right", surface = interior, name = FLUID_INPUT_NAME,
            position = { x = 17.5, y = 16.5 }, role = "input", force_north = true },
        { field = "exterior_input", surface = exterior, name = FLUID_INPUT_NAME,
            position = { x = record.entity.position.x - 2, y = record.entity.position.y + 4 }, role = "input" },
        { field = "exterior_output", surface = exterior, name = FLUID_OUTPUT_NAME,
            position = { x = record.entity.position.x + 1, y = record.entity.position.y + 4 }, role = "output" },
    }

    record.fluid_ports = {}
    record.fluid_transfer_roles = {}
    local layout_complete = true
    for _, definition in ipairs(definitions) do
        local old_entity = old[definition.field]
        local preserved_direction = valid(old_entity) and old_entity.direction or defines.direction.north
        if migrating_layout and definition.force_north then
            preserved_direction = defines.direction.north
        end
        if valid(old_entity) and old_entity.surface == definition.surface
            and old_entity.name == definition.name then
            -- Moving the existing entity preserves its complete fluidbox. The
            -- new internal layout deliberately faces north once; later checks
            -- preserve whatever direction the player selects.
            pcall(function() old_entity.teleport(definition.position) end)
        end
        local compatible_old = valid(old_entity)
            and old_entity.surface == definition.surface
            and old_entity.name == definition.name
        local entity
        if compatible_old and not matching_fixture(
            old_entity, definition.surface, definition.name, definition.position) then
            -- The destination can be occupied in an established save. Keep the
            -- old live port and all of its fluid instead of deleting anything;
            -- transfer_layout_ready will retry after the destination is clear.
            entity = protect_transfer_fixture(old_entity)
            layout_complete = false
        else
            entity = find_or_create_fixture(definition.surface, old_entity,
                definition.name, definition.position, force, preserved_direction)
        end
        if not matching_fixture(entity, definition.surface, definition.name, definition.position) then
            layout_complete = false
        end
        if valid(entity) then
            if migrating_layout and definition.force_north
                and matching_fixture(entity, definition.surface, definition.name, definition.position) then
                pcall(function() entity.direction = defines.direction.north end)
            end
            -- All six Shelter Pipe-to-ground ports are fixed in position but
            -- player-rotatable in all four directions. Never overwrite the
            -- selected direction during layout checks or configuration changes.
            pcall(function() entity.rotatable = true end)
        end
        record.fluid_ports[definition.field] = entity
        if valid(entity) and entity.unit_number then
            record.fluid_transfer_roles[entity.unit_number] = definition.role
        end
        if valid(entity) and valid(old_entity) and old_entity.unit_number ~= entity.unit_number then
            pcall(function() old_entity.destroy() end)
        end
    end
    if layout_complete then record.transfer_layout_version = TRANSFER_LAYOUT_VERSION end
end

local function ensure_transfer_layout(record, force)
    create_fixed_storehouses(record, force)
    create_fluid_ports(record, force)
end

local function transfer_layout_ready(record)
    if not (record and record.transfer_layout_version == TRANSFER_LAYOUT_VERSION) then return false end
    local interior = surface_for_record(record)
    local exterior = external_surface_for_record(record)
    if not (valid(interior) and valid(exterior) and valid(record.entity)) then return false end
    local storehouse_positions = {
        output = { x = -14, y = 14 },
        input = { x = 14, y = 14 },
    }
    local roles = { input = false, output = false }
    for _, entity in ipairs(record.transfer_entities or {}) do
        local role = valid(entity) and record.transfer_roles and record.transfer_roles[entity.unit_number]
        local position = role and storehouse_positions[role] or nil
        if position and matching_fixture(entity, interior, STOREHOUSE_NAME, position) then
            roles[role] = true
        end
    end
    if not (roles.input and roles.output) then return false end
    local fluid_definitions = {
        { field = "interior_output_left", surface = interior, name = FLUID_OUTPUT_NAME,
            position = { x = -17.5, y = 16.5 } },
        { field = "interior_output_right", surface = interior, name = FLUID_OUTPUT_NAME,
            position = { x = -10.5, y = 16.5 } },
        { field = "interior_input_left", surface = interior, name = FLUID_INPUT_NAME,
            position = { x = 10.5, y = 16.5 } },
        { field = "interior_input_right", surface = interior, name = FLUID_INPUT_NAME,
            position = { x = 17.5, y = 16.5 } },
        { field = "exterior_input", surface = exterior, name = FLUID_INPUT_NAME,
            position = { x = record.entity.position.x - 2, y = record.entity.position.y + 4 } },
        { field = "exterior_output", surface = exterior, name = FLUID_OUTPUT_NAME,
            position = { x = record.entity.position.x + 1, y = record.entity.position.y + 4 } },
    }
    for _, definition in ipairs(fluid_definitions) do
        if not matching_fixture(record.fluid_ports and record.fluid_ports[definition.field],
            definition.surface, definition.name, definition.position) then return false end
    end
    return true
end

local function create_interior_fixtures(record, force)
    local surface = surface_for_record(record)
    if not valid(surface) then return end
    record.substation = surface.create_entity {
        name = SUBSTATION_NAME,
        position = { x = -0.5, y = -6.5 },
        force = force,
        create_build_effect_smoke = false,
    }
    if valid(record.substation) then
        record.substation.destructible = false
        record.substation.minable_flag = false
    end
    ensure_transfer_layout(record, force)
end

local function safe_external_spawn(record, force)
    local surface = external_surface_for_record(record)
    local entity = record and record.entity
    if not (valid(surface) and valid(entity)) then return nil end
    local desired = {
        x = entity.position.x + RESPAWN_OFFSET.x,
        y = entity.position.y + RESPAWN_OFFSET.y,
    }
    local position = surface.find_non_colliding_position("character", desired, 12, 0.5) or desired
    force.set_spawn_position(position, surface)
    record.spawn_position = { x = position.x, y = position.y }
    return position
end

local function clear_shelter_placement(surface, position)
    local area = {
        { position.x - 4, position.y - 4 },
        { position.x + 4, position.y + 4 },
    }
    for _, entity in pairs(surface.find_entities_filtered { area = area }) do
        if valid(entity) and (entity.type == "tree" or entity.type == "simple-entity" or entity.type == "cliff") then
            pcall(function() entity.destroy() end)
        end
    end
end

local function create_shelter_for_force(force, exterior_surface)
    local state = root(true)
    local existing = state.forces[force.index]
    if existing and valid(existing.entity) then return existing end
    if not (valid(exterior_surface) and shelter_core.worlds.is_cave_world(exterior_surface))
        or shelter_core.worlds.is_template(exterior_surface) then return nil end

    local base = force.get_spawn_position(exterior_surface) or { x = 0, y = 0 }
    local position = exterior_surface.find_non_colliding_position(SHELTER_NAME, base, 32, 0.5) or base
    clear_shelter_placement(exterior_surface, position)
    local entity = exterior_surface.create_entity {
        name = SHELTER_NAME,
        position = position,
        force = force,
        create_build_effect_smoke = false,
    }
    if not valid(entity) then
        log("[The Cave] Could not place the fixed Shelter for force " .. force.name)
        return nil
    end
    entity.health = SHIELD_PHYSICAL_MAX_HEALTH
    entity.minable_flag = false
    entity.destructible = true
    pcall(function() entity.rotatable = false end)

    local interior = create_interior_surface(force)
    local initial_shield_level = shelter_shield_level(force)
    local initial_shield_health = shelter_shield_max_health(initial_shield_level)
    local record = {
        force_index = force.index,
        entity = entity,
        external_surface_index = exterior_surface.index,
        surface_index = interior.index,
        energy = 0,
        output_reserved = 0,
        last_output_energy = 0,
        last_charge_rate_mw = 0,
        last_output_rate_mw = 0,
        last_charge_sample_tick = nil,
        charge_enabled = false,
        bridge_version = POWER_BRIDGE_VERSION,
        item_transfer_snapshot = nil,
        fluid_ports = {},
        fluid_transfer_roles = {},
        transfer_layout_version = TRANSFER_LAYOUT_VERSION,
        shield_health = initial_shield_health,
        shield_max_health = initial_shield_health,
        shield_level = initial_shield_level,
        shield_last_damage_tick = 0,
        shield_version = SHIELD_VERSION,
        defeated = false,
    }
    state.forces[force.index] = record
    state.by_entity_unit[entity.unit_number] = force.index
    paint_room(record, force, true)
    create_interior_fixtures(record, force)
    shelter_garden.ensure(record, force, true)
    ensure_shelter_shield(record, force, false)
    chart_shelter_interior(record, force)
    safe_external_spawn(record, force)
    return record
end

local function count_inventory(inventory)
    local result = {}
    if not (inventory and inventory.valid) or inventory.is_empty() then return result end
    for key, value in pairs(inventory.get_contents()) do
        local name, quality, count
        if type(value) == "number" then
            name, quality, count = key, "normal", value
        elseif type(value) == "table" then
            name = value.name or key
            count = value.count or value.amount or 0
            quality = value.quality
            if type(quality) == "table" then quality = quality.name end
            if type(quality) ~= "string" then quality = "normal" end
        end
        if name and count and count > 0 then
            result[name] = result[name] or {}
            result[name][quality] = (result[name][quality] or 0) + count
        end
    end
    return result
end

local function count_inventories(inventories)
    local result = {}
    for _, inventory in ipairs(inventories) do
        for name, qualities in pairs(count_inventory(inventory)) do
            result[name] = result[name] or {}
            for quality, count in pairs(qualities) do
                result[name][quality] = (result[name][quality] or 0) + count
            end
        end
    end
    return result
end

local function distribute_items(source, inventories, name, quality, count)
    local remaining = count
    for index, inventory in ipairs(inventories) do
        if remaining <= 0 then break end
        local destinations_left = #inventories - index + 1
        local requested = math.max(1, math.ceil(remaining / destinations_left))
        local moved = shelter_garden.item_transfer.move_count(source, inventory, name, quality, requested)
        remaining = remaining - moved
    end
    return count - remaining
end

local function move_from_inventory(source, destinations, name, quality, count)
    return distribute_items(source, destinations, name, quality, count)
end

local function move_from_many(sources, destination, name, quality, count)
    local remaining = count
    for _, source in ipairs(sources) do
        if remaining <= 0 then break end
        remaining = remaining - shelter_garden.item_transfer.move_count(source, destination, name, quality, remaining)
    end
    return count - remaining
end

local function transfer_inventories(record)
    if not valid(record.entity) then return end
    local external = record.entity.get_inventory(defines.inventory.chest)
    if not (external and external.valid) then return end
    local inputs, outputs = {}, {}
    for _, chest in ipairs(record.transfer_entities or {}) do
        if valid(chest) then
            local inventory = chest.get_inventory(defines.inventory.chest)
            local role = record.transfer_roles and record.transfer_roles[chest.unit_number]
            if inventory and inventory.valid then
                if role == "output" then outputs[#outputs + 1] = inventory
                else inputs[#inputs + 1] = inventory end
            end
        end
    end
    local current_external = count_inventory(external)
    local current_input = count_inventories(inputs)
    local current_output = count_inventories(outputs)
    local snapshot = record.item_transfer_snapshot
    local pending_import = {}

    -- Old snapshots aggregated every quality under one item name. Keep current
    -- normal stacks as the baseline, while treating existing non-normal stacks
    -- in the external Shelter or Output Storehouse as newly added so they are
    -- retried once in their intended direction after an update.
    if snapshot and snapshot.version ~= ITEM_TRANSFER_SNAPSHOT_VERSION then
        local migrated_external, migrated_output = {}, {}
        for name, qualities in pairs(current_external) do
            if (qualities.normal or 0) > 0 then migrated_external[name] = { normal = qualities.normal } end
        end
        for name, qualities in pairs(current_output) do
            if (qualities.normal or 0) > 0 then migrated_output[name] = { normal = qualities.normal } end
        end
        snapshot = {
            version = ITEM_TRANSFER_SNAPSHOT_VERSION,
            external = migrated_external,
            input = current_input,
            output = migrated_output,
        }
        record.item_transfer_snapshot = snapshot
    end

    if snapshot then
        local names = {}
        for name in pairs(current_external) do names[name] = true end
        for name in pairs(current_output) do names[name] = true end
        for name in pairs(snapshot.external or {}) do names[name] = true end
        for name in pairs(snapshot.output or {}) do names[name] = true end
        for name in pairs(names) do
            local qualities = {}
            for quality in pairs(current_external[name] or {}) do qualities[quality] = true end
            for quality in pairs(current_input[name] or {}) do qualities[quality] = true end
            for quality in pairs(current_output[name] or {}) do qualities[quality] = true end
            for quality in pairs((snapshot.external or {})[name] or {}) do qualities[quality] = true end
            for quality in pairs((snapshot.input or {})[name] or {}) do qualities[quality] = true end
            for quality in pairs((snapshot.output or {})[name] or {}) do qualities[quality] = true end
            for quality in pairs(qualities) do
                local current = ((current_external[name] or {})[quality] or 0)
                local waiting = (((snapshot.pending_import or {})[name] or {})[quality] or 0)
                local external_added = math.min(current, math.max(0, waiting + current
                    - (((snapshot.external or {})[name] or {})[quality] or 0)))
                -- Dedicated output inventories can always retry their contents.
                local output_added = ((current_output[name] or {})[quality] or 0)
                if external_added > 0 then
                    local moved = move_from_inventory(external, inputs, name, quality, external_added)
                    if moved < external_added then
                        pending_import[name] = pending_import[name] or {}
                        pending_import[name][quality] = external_added - moved
                    end
                end
                if output_added > 0 then
                    move_from_many(outputs, external, name, quality, output_added)
                end
            end
        end
        current_external = count_inventory(external)
        current_input = count_inventories(inputs)
        current_output = count_inventories(outputs)
    end
    record.item_transfer_snapshot = {
        version = ITEM_TRANSFER_SNAPSHOT_VERSION,
        external = current_external,
        input = current_input,
        output = current_output,
        pending_import = pending_import,
    }
end

local function fluid_info(entity)
    if not valid(entity) then return nil end
    local ok, fluid = pcall(function() return entity.get_fluid(1) end)
    if not ok or not fluid or (tonumber(fluid.amount) or 0) <= 0 then return nil end
    return {
        name = fluid.name,
        amount = fluid.amount,
        temperature = fluid.temperature,
    }
end

local function remove_fluid_safe(entity, fluid)
    if not (valid(entity) and fluid and fluid.name and (tonumber(fluid.amount) or 0) > 0) then return 0 end
    local ok, removed = pcall(function()
        return entity.extract_fluid { name = fluid.name, amount = fluid.amount }
    end)
    return ok and (tonumber(removed) or 0) or 0
end

local function insert_fluid_safe(entity, fluid)
    if not (valid(entity) and fluid and fluid.name and (tonumber(fluid.amount) or 0) > 0) then return 0 end
    local ok, inserted = pcall(function()
        return entity.insert_fluid {
            name = fluid.name,
            amount = fluid.amount,
            temperature = fluid.temperature,
        }
    end)
    return ok and (tonumber(inserted) or 0) or 0
end

local function move_fluid(source, destination, limit)
    if not (valid(source) and valid(destination)) then return 0 end
    local source_fluid = fluid_info(source)
    if not source_fluid then return 0 end
    local destination_fluid = fluid_info(destination)
    if destination_fluid and destination_fluid.name ~= source_fluid.name then return 0 end
    local requested = math.min(source_fluid.amount, limit or FLUID_TRANSFER_PER_SYNC)
    if requested <= 0 then return 0 end

    -- Operate through Factorio's entity fluid API instead of assigning a
    -- single Pipe-to-ground fluidbox. This transfers against the connected
    -- fluid segment on each surface and reports the amount actually accepted.
    local removed = remove_fluid_safe(source, {
        name = source_fluid.name,
        amount = requested,
    })
    if removed <= 0 then return 0 end
    local inserted = insert_fluid_safe(destination, {
        name = source_fluid.name,
        amount = removed,
        temperature = source_fluid.temperature,
    })
    local remainder = removed - inserted
    if remainder > 0 then
        -- A full or incompatible destination must never delete fluid.
        insert_fluid_safe(source, {
            name = source_fluid.name,
            amount = remainder,
            temperature = source_fluid.temperature,
        })
    end
    return inserted
end

local function move_fluid_balanced(source, destinations, limit)
    local compatible = {}
    local source_fluid = fluid_info(source)
    if not source_fluid then return 0 end
    for _, destination in ipairs(destinations) do
        local present = fluid_info(destination)
        if valid(destination) and (not present or present.name == source_fluid.name) then
            compatible[#compatible + 1] = destination
        end
    end
    table.sort(compatible, function(a, b)
        local af, bf = fluid_info(a), fluid_info(b)
        return ((af and af.amount) or 0) < ((bf and bf.amount) or 0)
    end)
    local remaining = math.min(source_fluid.amount, limit or FLUID_TRANSFER_PER_SYNC)
    local moved = 0
    for index, destination in ipairs(compatible) do
        if remaining <= 0 then break end
        local share = remaining / (#compatible - index + 1)
        local amount = move_fluid(source, destination, share)
        remaining = remaining - amount
        moved = moved + amount
    end
    return moved
end

local function transfer_fluids(record)
    local ports = record.fluid_ports or {}
    if valid(ports.exterior_input) then
        move_fluid_balanced(ports.exterior_input, {
            ports.interior_input_left,
            ports.interior_input_right,
        }, FLUID_TRANSFER_PER_SYNC)
    end
    if valid(ports.exterior_output) then
        local remaining = FLUID_TRANSFER_PER_SYNC
        remaining = remaining - move_fluid(ports.interior_output_left, ports.exterior_output, remaining)
        if remaining > 0 then
            move_fluid(ports.interior_output_right, ports.exterior_output, remaining)
        end
    end
end

local function destroy_entity(entity)
    if valid(entity) then pcall(function() entity.destroy() end) end
end

local function destroy_render(object)
    if object and object.valid then pcall(function() object.destroy() end) end
end

local function get_copper_connector(entity, create)
    if not (valid(entity) and entity.get_wire_connector) then return nil end
    local ok, connector = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, create == true)
    end)
    return ok and connector and connector.valid and connector or nil
end

local function eligible_external_pole(hidden_pole, pole, center)
    return valid(pole)
        and pole.type == "electric-pole"
        and pole.surface == hidden_pole.surface
        and pole.force == hidden_pole.force
        and pole.name ~= OUTPUT_POLE_NAME
        and math.abs(pole.position.x - center.x) <= POWER_RANGE_HALF_SIZE + 0.001
        and math.abs(pole.position.y - center.y) <= POWER_RANGE_HALF_SIZE + 0.001
end

local function connect_output_poles(record)
    local hidden_pole = record.output_pole
    local shelter = record.entity
    if not (valid(hidden_pole) and valid(shelter)) then return end
    local connector = get_copper_connector(hidden_pole, true)
    if not connector then return end
    local ok, connections = pcall(function() return connector.real_connections end)
    if ok and type(connections) == "table" then
        for _, connection in pairs(connections) do
            local target_connector = connection and connection.target
            local owner = nil
            pcall(function() owner = target_connector and target_connector.owner end)
            if not eligible_external_pole(hidden_pole, owner, shelter.position) then
                pcall(function() connector.disconnect_from(target_connector, connection.origin) end)
            end
        end
    end
    local center = shelter.position
    local poles = shelter_garden.maintenance.poles(record, hidden_pole, center, POWER_RANGE_HALF_SIZE)
    for _, pole in ipairs(poles) do
        if eligible_external_pole(hidden_pole, pole, center) then
            local target = get_copper_connector(pole, true)
            if target then
                local connected = false
                pcall(function()
                    connected = connector.is_connected_to(target, defines.wire_origin.player)
                        or connector.is_connected_to(target, defines.wire_origin.script)
                end)
                if not connected then
                    pcall(function() connector.connect_to(target, false, defines.wire_origin.script) end)
                end
            end
        end
    end
end

local function battery_level(force)
    return researched_level(force, BATTERY_PREFIX, 20)
end

local function capacity_j(level)
    return ((POWER_CAPACITY_MJ[level] or 0) * J_PER_MJ)
end

local function ensure_power_range_render(record)
    if record.power_range_render
        and record.power_range_render.outline and record.power_range_render.outline.valid
        and record.power_range_render.label and record.power_range_render.label.valid then return end
    destroy_render(record.power_range_render and record.power_range_render.outline)
    destroy_render(record.power_range_render and record.power_range_render.label)
    record.power_range_render = nil
    if not valid(record.entity) then return end
    local shelter = record.entity
    local outline = rendering.draw_rectangle {
        surface = shelter.surface,
        left_top = { type = "entity", entity = shelter, offset = { -POWER_RANGE_HALF_SIZE, -POWER_RANGE_HALF_SIZE } },
        right_bottom = { type = "entity", entity = shelter, offset = { POWER_RANGE_HALF_SIZE, POWER_RANGE_HALF_SIZE } },
        color = { r = 1, g = 0.78, b = 0.08, a = 0.92 },
        width = 2,
        filled = false,
        forces = { shelter.force },
        draw_on_ground = false,
        only_in_alt_mode = false,
    }
    local label = rendering.draw_text {
        surface = shelter.surface,
        target = { type = "entity", entity = shelter, offset = { 0, -POWER_RANGE_HALF_SIZE - 1.25 } },
        text = { "the-cave-shelter.power-range-label" },
        color = { r = 1, g = 0.78, b = 0.08, a = 0.92 },
        scale = 0.9,
        alignment = "center",
        vertical_alignment = "bottom",
        forces = { shelter.force },
        draw_on_ground = false,
        only_in_alt_mode = false,
    }
    record.power_range_render = { outline = outline, label = label }
end

local function settle_output_reserve(record, output, reserved_energy)
    local reserved = math.max(0, tonumber(reserved_energy) or 0)
    local current = 0
    if valid(output) then
        current = math.min(reserved, math.max(0, tonumber(output.energy) or 0))
    end
    local consumed = math.max(0, reserved - current)
    record.energy = math.max(0, (tonumber(record.energy) or 0) - consumed)
    if valid(output) then pcall(function() output.energy = 0 end) end
    record.output_reserved = 0
    record.last_output_energy = 0
    return consumed
end

local function destroy_named_entities(surface, names, force, on_entity)
    if not valid(surface) then return end
    for _, entity in pairs(surface.find_entities_filtered { name = names, force = force } or {}) do
        if valid(entity) then
            if on_entity then on_entity(entity) end
            destroy_entity(entity)
        end
    end
end

local function migrate_legacy_power_bridge(record, force, capacity)
    if record.bridge_version == POWER_BRIDGE_VERSION then return end
    record.energy = math.max(0, math.min(tonumber(record.energy) or 0, capacity))

    -- Settle the 3.1.72 output accumulator before replacing it. An older
    -- ElectricEnergyInterface is cleared without treating an engine-normalized
    -- empty buffer as real exterior consumption.
    local staged_output = valid(record.output_interface) and record.output_interface
        or (valid(record.output_accumulator) and record.output_accumulator or nil)
    local reserved_output = math.max(0, tonumber(record.output_reserved) or 0)
    if reserved_output <= 0 then
        reserved_output = math.max(0, tonumber(record.last_output_energy) or 0)
    end
    if valid(staged_output) and staged_output.type == "accumulator" then
        settle_output_reserve(record, staged_output, reserved_output)
    elseif valid(staged_output) then
        pcall(function() staged_output.energy = 0 end)
        record.output_reserved = 0
        record.last_output_energy = 0
    end

    -- Recover pending energy from every mod-owned interior charger before
    -- recreating the single Train-style input interface. Player entities are
    -- never scanned or modified.
    local recovered_units = {}
    local function recover_legacy_input(entity)
        if not valid(entity) then return end
        local key = entity.unit_number or entity
        if recovered_units[key] then return end
        recovered_units[key] = true
        local available = math.max(0, tonumber(entity.energy) or 0)
        local accepted = math.min(available, math.max(0, capacity - record.energy))
        record.energy = math.min(capacity, record.energy + accepted)
        pcall(function() entity.energy = 0 end)
    end
    recover_legacy_input(record.input_interface)
    recover_legacy_input(record.input_accumulator)
    local interior = surface_for_record(record)
    destroy_named_entities(interior, INPUT_INTERFACE_NAMES, force, recover_legacy_input)
    destroy_named_entities(interior, LEGACY_INPUT_NAMES, force, recover_legacy_input)

    destroy_entity(record.input_interface)
    destroy_entity(record.input_accumulator)
    destroy_entity(record.output_interface)
    destroy_entity(record.output_accumulator)
    if valid(record.entity) then
        destroy_named_entities(record.entity.surface, OUTPUT_INTERFACE_NAMES, force)
        destroy_named_entities(record.entity.surface, LEGACY_OUTPUT_BUFFER_NAMES, force)
        destroy_named_entities(record.entity.surface, { LEGACY_OUTPUT_ACCUMULATOR_NAME }, force)
    end
    record.input_interface = nil
    record.input_accumulator = nil
    record.output_interface = nil
    record.output_accumulator = nil
    record.output_reserved = 0
    record.last_output_energy = 0
    record.output_buffer_runtime_version = nil
    record.bridge_version = POWER_BRIDGE_VERSION
end

local function absorb_input_charge(record, input, capacity, allow_charge)
    if not valid(input) then return 0 end
    local available = math.max(0, tonumber(input.energy) or 0)
    local accepted = 0
    if allow_charge then
        accepted = math.min(available, math.max(0, capacity - record.energy))
        record.energy = math.min(capacity, record.energy + accepted)
    end
    pcall(function() input.energy = 0 end)
    return accepted
end

local function update_charge_mode(record, capacity)
    if capacity <= 0 then
        local changed = record.charge_enabled ~= false
        record.charge_enabled = false
        return changed
    end
    local energy = math.max(0, math.min(tonumber(record.energy) or 0, capacity))
    local previous = record.charge_enabled
    if previous == nil then
        record.charge_enabled = energy < capacity
        previous = record.charge_enabled
    end
    if record.charge_enabled then
        if energy >= capacity then record.charge_enabled = false end
    elseif energy <= capacity * 0.25 then
        record.charge_enabled = true
    end
    return record.charge_enabled ~= previous
end

local function ensure_power_entity(record, field, surface, name, position, force)
    if not (record and valid(surface) and name and position and force and force.valid) then return nil end
    local entity = record[field]
    -- Match Train Interiors exactly: keep the live transfer entity and move it
    -- in place. Factorio may normalize a collisionless entity's requested
    -- position to its placement grid; comparing that normalized position with
    -- the raw Shelter centre used to destroy and recreate the charged buffer
    -- every 15 ticks, making its staged energy look consumed.
    if valid(entity) and entity.name == name and entity.surface == surface
        and entity.force == force then
        if math.abs(entity.position.x - position.x) > 0.001
            or math.abs(entity.position.y - position.y) > 0.001 then
            pcall(function() entity.teleport(position) end)
        end
    else
        destroy_entity(entity)
        local ok, created = pcall(function()
            entity = surface.create_entity {
                name = name,
                position = position,
                force = force,
                create_build_effect_smoke = false,
            }
            return entity
        end)
        entity = (ok and created and created.valid) and created or nil
        if entity then
            pcall(function() entity.destructible = false end)
            pcall(function() entity.minable_flag = false end)
            pcall(function() entity.operable = false end)
        end
    end
    record[field] = entity
    return entity
end

local function remove_power(record)
    destroy_entity(record.input_interface)
    destroy_entity(record.output_interface)
    destroy_entity(record.input_accumulator)
    destroy_entity(record.output_accumulator)
    destroy_entity(record.output_pole)
    record.input_interface = nil
    record.output_interface = nil
    record.input_accumulator = nil
    record.output_accumulator = nil
    record.output_pole = nil
    destroy_render(record.power_range_render and record.power_range_render.outline)
    destroy_render(record.power_range_render and record.power_range_render.label)
    record.power_range_render = nil
    record.output_reserved = 0
    record.last_output_energy = 0
end

local function ensure_power_entities(record, force, level)
    if not valid(record.entity) then
        remove_power(record)
        return
    end
    local capacity = capacity_j(level)
    record.energy = math.max(0, math.min(tonumber(record.energy) or 0, capacity))
    migrate_legacy_power_bridge(record, force, capacity)
    if level <= 0 then
        remove_power(record)
        record.energy = 0
        record.charge_enabled = false
        return
    end

    local interior = surface_for_record(record)
    if not valid(interior) then return end
    update_charge_mode(record, capacity)

    local input_name = INPUT_INTERFACE_NAMES[level]
    local input_position = { x = -0.5, y = -6.5 }
    local input = record.input_interface
    if valid(input) and (input.name ~= input_name or input.surface ~= interior) then
        absorb_input_charge(record, input, capacity, record.charge_enabled == true)
        destroy_entity(input)
        record.input_interface = nil
        input = nil
    end
    local should_charge = record.charge_enabled == true and record.energy < capacity
    if should_charge then
        input = ensure_power_entity(record, "input_interface", interior, input_name, input_position, force)
        if valid(input) then pcall(function() input.disabled_by_script = false end) end
    else
        absorb_input_charge(record, input, capacity, false)
        destroy_entity(input)
        record.input_interface = nil
    end

    if record.output_range_version ~= OUTPUT_RANGE_VERSION then
        -- Recreate once so a 3.1.72 pole cannot retain its former direct supply
        -- area or any stale automatic/script copper connections.
        destroy_entity(record.output_pole)
        record.output_pole = nil
        record.output_range_version = OUTPUT_RANGE_VERSION
    end

    -- Create the zero-area pole first so the output joins its native network.
    local output_pole = ensure_power_entity(record, "output_pole", record.entity.surface,
        OUTPUT_POLE_NAME, record.entity.position, force)
    local output_name = OUTPUT_INTERFACE_NAMES[level]
    local output = record.output_interface
    if valid(output) and (output.name ~= output_name or output.surface ~= record.entity.surface
        or output.force ~= force or record.output_connection_version ~= 1
        or (valid(output_pole) and output_pole.electric_network_id
            and output.electric_network_id ~= output_pole.electric_network_id)) then
        settle_output_reserve(record, output, record.output_reserved)
        destroy_entity(output)
        record.output_interface = nil
    end
    output = ensure_power_entity(record, "output_interface", record.entity.surface,
        output_name, record.entity.position, force)
    if valid(output) then record.output_connection_version = 1 end

    -- Prototype changes do not resize an already-created interface in every
    -- save. Apply the same one-sync output window repair used by Train
    -- Interiors, once per migrated Shelter record.
    if valid(output) and record.output_buffer_runtime_version ~= OUTPUT_BUFFER_RUNTIME_VERSION then
        local target_output_buffer_j = (POWER_OUTPUT_RATE_MW[level] or 0)
            * J_PER_MJ * POWER_SYNC_INTERVAL_TICKS / 60
        local repaired = pcall(function()
            output.electric_buffer_size = target_output_buffer_j
            if (tonumber(output.energy) or 0) > target_output_buffer_j then
                output.energy = target_output_buffer_j
            end
        end)
        if repaired then record.output_buffer_runtime_version = OUTPUT_BUFFER_RUNTIME_VERSION end
    end
    if valid(output) then pcall(function() output.disabled_by_script = false end) end

    ensure_power_range_render(record)
    connect_output_poles(record)
end

local function sync_power(record, force, elapsed_ticks)
    local level = battery_level(force)
    ensure_power_entities(record, force, level)
    if level <= 0 then
        record.last_charge_rate_mw = 0
        record.last_output_rate_mw = 0
        return
    end

    local capacity = capacity_j(level)
    local output = record.output_interface
    local consumed = settle_output_reserve(record, output, record.output_reserved)
    record.energy = math.max(0, math.min(record.energy, capacity))

    local charged = absorb_input_charge(record, record.input_interface, capacity,
        record.charge_enabled == true and record.energy < capacity)
    elapsed_ticks = math.max(1, tonumber(elapsed_ticks) or POWER_SYNC_INTERVAL_TICKS)
    record.last_charge_rate_mw = (charged * 60 / elapsed_ticks) / J_PER_MJ
    record.last_output_rate_mw = (consumed * 60 / elapsed_ticks) / J_PER_MJ
    record.last_charge_sample_tick = game and game.tick or record.last_charge_sample_tick

    if update_charge_mode(record, capacity) then
        ensure_power_entities(record, force, level)
        output = record.output_interface
    end

    -- Stage only one 15-tick transfer window at the researched Shelter Battery
    -- rate. Output shares generation with exterior generators and can also
    -- charge exterior accumulators through native electric distribution.
    local output_rate_w = (POWER_OUTPUT_RATE_MW[level] or 0) * J_PER_MJ
    local staged = math.min(record.energy,
        output_rate_w * POWER_SYNC_INTERVAL_TICKS / 60)
    if valid(output) then
        pcall(function() output.energy = staged end)
        record.output_reserved = staged
        record.last_output_energy = staged
    else
        record.output_reserved = 0
        record.last_output_energy = 0
    end
end

local function clear_gui(player, name)
    if not (valid(player) and player.gui and player.gui.screen) then return end
    local element = player.gui.screen[name]
    if element and element.valid then element.destroy() end
end

local function position_screen_frame(player, frame, width, y_from_bottom)
    local resolution = player.display_resolution or { width = 1920, height = 1080 }
    local scale = tonumber(player.display_scale) or 1
    local screen_width = resolution.width / scale
    local screen_height = resolution.height / scale
    frame.location = {
        x = math.max(0, math.floor((screen_width - width) * 0.5)),
        y = math.max(0, math.floor(screen_height - y_from_bottom)),
    }
end

local function disable_external_shelter_research(force)
    if not (force and force.valid) then return end
    local technology = force.technologies and force.technologies["kr-shelter"]
    if technology then technology.enabled = false end
    local recipe = force.recipes and force.recipes["kr-shelter"]
    if recipe then recipe.enabled = false end
end

local function player_state(player)
    local state = root(true)
    state.player_states[player.index] = state.player_states[player.index] or {}
    return state.player_states[player.index]
end

local function player_record_inside(player)
    if not shelter_core.is_shelter_surface(physical.surface(player)) then return nil end
    local state = root(false)
    for _, record in pairs(state and state.forces or {}) do
        if record.surface_index == physical.surface(player).index and record.force_index == player.force.index then return record end
    end
    return nil
end

function shelter_garden.player_record_in_complex(player)
    local record = player_record_inside(player)
    if record then return record end
    if shelter_core.is_shelter_garden_surface(player and physical.surface(player)) then
        record = record_for_surface(physical.surface(player))
        if record and record.force_index == player.force.index then return record end
    end
    return nil
end

local function kill_outside_view(player)
    if not (valid(player) and player.gui and player.gui.left) then return end
    local frame = player.gui.left[OUTSIDE_VIEW_FRAME]
    if frame and frame.valid then frame.destroy() end
end

local function draw_outside_view(player, record)
    if not (valid(player) and record and valid(record.entity)) then
        kill_outside_view(player)
        return
    end
    local ps = player_state(player)
    local map_size = tonumber(ps.outside_view_size) or 200
    if map_size ~= 200 and map_size ~= 230 and map_size ~= 260 then map_size = 200 end
    local zoom = math.max(0.45, math.min(2, tonumber(ps.outside_view_zoom) or 0.50))
    ps.outside_view_size = map_size
    ps.outside_view_zoom = zoom

    local frame = player.gui.left[OUTSIDE_VIEW_FRAME]
    if not (frame and frame.valid) then
        frame = player.gui.left.add {
            type = "frame",
            name = OUTSIDE_VIEW_FRAME,
            direction = "vertical",
            caption = { "the-cave-shelter.outside-view-title" },
        }
    end
    local frame_width = map_size + 20
    frame.style.minimal_width = frame_width
    frame.style.maximal_width = frame_width
    pcall(function() frame.style.natural_width = frame_width end)
    pcall(function() frame.style.horizontally_stretchable = false end)
    pcall(function() frame.style.horizontally_squashable = false end)

    local camera = frame[OUTSIDE_VIEW_CAMERA]
    if not (camera and camera.valid) then
        camera = frame.add {
            type = "camera",
            name = OUTSIDE_VIEW_CAMERA,
            surface_index = record.entity.surface.index,
            position = record.entity.position,
            zoom = zoom,
            tooltip = { "the-cave-shelter.outside-view-tooltip" },
        }
    else
        camera.surface_index = record.entity.surface.index
        camera.position = record.entity.position
        camera.zoom = zoom
    end
    camera.style.minimal_width = map_size
    camera.style.minimal_height = map_size
    camera.style.maximal_width = map_size
    camera.style.maximal_height = map_size
    pcall(function() camera.style.natural_width = map_size end)
    pcall(function() camera.style.natural_height = map_size end)
end

local function update_outside_views()
    for _, player in pairs(game.connected_players or {}) do
        local record = shelter_garden.player_record_in_complex(player)
        if record and valid(record.entity) then
            draw_outside_view(player, record)
        else
            kill_outside_view(player)
        end
    end
end

function shelter_core.on_gui_click(event)
    local element = event and event.element
    if not (startup_enabled() and element and element.valid
        and element.name == OUTSIDE_VIEW_CAMERA) then return false end
    local player = event.player_index and game.get_player(event.player_index)
    if not valid(player) then return true end
    local ps = player_state(player)
    if event.button == defines.mouse_button_type.right then
        ps.outside_view_zoom = math.max(0.45, (ps.outside_view_zoom or 0.50) - 0.07)
        element.zoom = ps.outside_view_zoom
    elseif event.button == defines.mouse_button_type.left then
        ps.outside_view_zoom = math.min(2, (ps.outside_view_zoom or 0.50) + 0.07)
        element.zoom = ps.outside_view_zoom
    elseif event.button == defines.mouse_button_type.middle then
        local current = tonumber(ps.outside_view_size) or 200
        if current == 200 then
            ps.outside_view_size = 230
        elseif current == 230 then
            ps.outside_view_size = 260
        else
            ps.outside_view_size = 200
        end
        local record = player_record_inside(player)
        if record then draw_outside_view(player, record) end
    end
    return true
end

local function nearby_record(player)
    if not physical.can_travel(player) then return nil end
    local record = record_for_force(player.force)
    if not (record and valid(record.entity) and physical.surface(player) == record.entity.surface) then return nil end
    local dx = physical.position(player).x - record.entity.position.x
    local dy = physical.position(player).y - record.entity.position.y
    return dx * dx + dy * dy <= 100 and record or nil
end

local function update_entry_prompt(player)
    if not physical.can_travel(player) then clear_gui(player, ENTRY_PROMPT) return end
    local inside = player_record_inside(player)
    local outside = not inside and nearby_record(player) or nil
    if not inside and not outside then
        clear_gui(player, ENTRY_PROMPT)
        return
    end
    local frame = player.gui.screen[ENTRY_PROMPT]
    if not (frame and frame.valid) then
        frame = player.gui.screen.add { type = "frame", name = ENTRY_PROMPT, direction = "vertical" }
        frame.style.width = 380
        frame.style.padding = 6
        frame.style.horizontal_align = "center"
        local title = frame.add { type = "label", name = "title", caption = { "the-cave-shelter.entry-prompt-title" } }
        title.style.font = "default-bold"
        title.style.font_color = { r = 0.35, g = 0.85, b = 1 }
        title.style.horizontally_stretchable = true
        title.style.horizontal_align = "center"
    end
    local prompt_label = frame.the_cave_shelter_prompt_text
    if not (prompt_label and prompt_label.valid) then
        prompt_label = frame.add {
            type = "label",
            name = "the_cave_shelter_prompt_text",
            caption = "",
        }
        prompt_label.style.font = "default-bold"
        prompt_label.style.single_line = false
        prompt_label.style.horizontally_stretchable = true
        prompt_label.style.horizontal_align = "center"
    end
    prompt_label.caption = inside
        and { "the-cave-shelter.press-exit" }
        or { "the-cave-shelter.press-enter" }
    prompt_label.style.font_color = { r = 1, g = 0.78, b = 0.20 }
    -- Match the proven Train Interiors prompt placement. The old 155 offset
    -- overlapped multi-row quickbars at common UI scales.
    position_screen_frame(player, frame, 380, 280)
    pcall(function() frame.bring_to_front() end)
end

local function number_text(value)
    local number = math.floor((tonumber(value) or 0) + 0.5)
    local text = tostring(number)
    while true do
        local changed, count = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
        text = changed
        if count == 0 then break end
    end
    return text
end

local function rate_text(value)
    value = tonumber(value) or 0
    if value < 0.05 then return "0" end
    if value < 10 then return string.format("%.1f", value) end
    return number_text(value)
end

local function power_status(record, level)
    if level <= 0 then return { "the-cave-shelter.power-not-installed" } end
    local charging = record.charge_enabled == true
    local supplying = (tonumber(record.last_output_rate_mw) or 0) > 0.05
    local capacity = capacity_j(level)
    local energy = math.max(0, tonumber(record.energy) or 0)
    if energy <= 0 and (tonumber(record.last_charge_rate_mw) or 0) <= 0.05 then
        return { "the-cave-shelter.power-depleted" }
    end
    if charging and supplying then return { "the-cave-shelter.power-charging-supplying" } end
    if charging then return { "the-cave-shelter.power-charging" } end
    if supplying then return { "the-cave-shelter.power-supplying" } end
    if energy >= capacity then return { "the-cave-shelter.power-full" } end
    return { "the-cave-shelter.power-standby" }
end

local function shield_repair_status(record, level)
    local health = tonumber(record.shield_health) or 0
    local maximum = tonumber(record.shield_max_health) or shelter_shield_max_health(level)
    if health >= maximum then return { "the-cave-shelter.repair-standby" } end
    if shelter_shield_repair_per_second(level) <= 0 then
        return { "the-cave-shelter.repair-damaged" }
    end
    local tick = game and game.tick or 0
    if tick - (tonumber(record.shield_last_damage_tick) or 0) < SHIELD_REPAIR_DELAY_TICKS then
        return { "the-cave-shelter.repair-waiting" }
    end
    return { "the-cave-shelter.repairing" }
end

local function clear_shelter_hover_render(player)
    if valid(player) then clear_gui(player, LEGACY_HOVER_FRAME) end
    local state = root(false)
    local existing = state and state.selected_shelter_render
        and state.selected_shelter_render[player.index] or nil
    if type(existing) == "table" and type(existing.render_ids) == "table" then
        for _, render_id in ipairs(existing.render_ids) do
            local object = rendering.get_object_by_id(render_id)
            destroy_render(object)
        end
    else
        destroy_render(existing)
    end
    if state and state.selected_shelter_render then
        state.selected_shelter_render[player.index] = nil
    end
end

local function update_hover(player)
    -- Remove the former fixed screen panel when upgrading an in-progress test
    -- save. Shelter status now belongs to a player-local world panel.
    clear_gui(player, LEGACY_HOVER_FRAME)
    local selected = player.selected
    local record = selected and selected.name == SHELTER_NAME and record_for_force(selected.force) or nil
    if not (record and valid(record.entity) and selected.unit_number == record.entity.unit_number) then
        clear_shelter_hover_render(player)
        return
    end
    local level = battery_level(selected.force)
    ensure_shelter_shield(record, selected.force, false)
    local shield_level = shelter_shield_level(selected.force)
    local energy_mj = (tonumber(record.energy) or 0) / J_PER_MJ
    local maximum_mj = POWER_CAPACITY_MJ[level] or 0
    local percent = maximum_mj > 0 and math.floor(energy_mj * 100 / maximum_mj + 0.5) or 0
    local health = math.max(0, math.floor((tonumber(record.shield_health) or 0) + 0.5))
    local maximum_health = math.max(1,
        math.floor((tonumber(record.shield_max_health) or MAX_HEALTH) + 0.5))
    local lines = {
        { "the-cave-shelter.hover-title" },
        { "the-cave-shelter.hover-shield-level", tostring(shield_level) },
        { "the-cave-shelter.hover-integrity", number_text(health), number_text(maximum_health) },
        { "the-cave-shelter.hover-damage", number_text(math.max(0, maximum_health - health)) },
        { "the-cave-shelter.hover-self-repair", number_text(shelter_shield_repair_per_second(shield_level)) },
        { "the-cave-shelter.hover-repair-mode", shield_repair_status(record, shield_level) },
        { "the-cave-shelter.hover-battery", number_text(energy_mj), number_text(maximum_mj), tostring(percent) },
        { "the-cave-shelter.hover-power-status", power_status(record, level) },
        { "the-cave-shelter.hover-charge-rate", rate_text(record.last_charge_rate_mw), number_text(POWER_CHARGE_RATE_MW[level] or 0) },
    }

    local state = root(true)
    local existing = state.selected_shelter_render[player.index]
    if type(existing) == "table"
        and existing.unit_number == selected.unit_number
        and type(existing.render_ids) == "table"
        and type(existing.text_ids) == "table"
        and #existing.text_ids == #lines then
        local render_valid = true
        for _, render_id in ipairs(existing.render_ids) do
            local object = rendering.get_object_by_id(render_id)
            if not (object and object.valid) then
                render_valid = false
                break
            end
        end
        if render_valid then
            for index, render_id in ipairs(existing.text_ids) do
                local object = rendering.get_object_by_id(render_id)
                if not (object and object.valid and object.type == "text") then
                    render_valid = false
                    break
                end
                object.text = lines[index]
            end
        end
        if render_valid then
            for _, render_id in ipairs(existing.render_ids) do
                local object = rendering.get_object_by_id(render_id)
                if object and object.valid then object.time_to_live = 90 end
            end
            return
        end
    end

    clear_shelter_hover_render(player)
    state = root(true)
    local render_ids = {}
    local text_ids = {}
    local box_left, box_right = -8.25, 8.25
    local box_top, box_bottom = -13.0, -3.45
    local background = rendering.draw_rectangle {
        surface = selected.surface,
        left_top = { type = "entity", entity = selected, offset = { box_left, box_top } },
        right_bottom = { type = "entity", entity = selected, offset = { box_right, box_bottom } },
        color = { r = 0.20, g = 0.20, b = 0.20, a = 0.92 },
        filled = true,
        draw_on_ground = false,
        players = { player.index },
        time_to_live = 90,
        render_mode = "game",
    }
    if background then render_ids[#render_ids + 1] = background.id end
    local outline = rendering.draw_rectangle {
        surface = selected.surface,
        left_top = { type = "entity", entity = selected, offset = { box_left, box_top } },
        right_bottom = { type = "entity", entity = selected, offset = { box_right, box_bottom } },
        color = { r = 0.68, g = 0.68, b = 0.68, a = 1 },
        width = 2,
        filled = false,
        draw_on_ground = false,
        players = { player.index },
        time_to_live = 90,
        render_mode = "game",
    }
    if outline then render_ids[#render_ids + 1] = outline.id end

    local base_y = -12.25
    local line_spacing = 1.0
    for index, line in ipairs(lines) do
        local object = rendering.draw_text {
            text = line,
            surface = selected.surface,
            target = { entity = selected, offset = { 0, base_y + ((index - 1) * line_spacing) } },
            color = index == 1
                and { r = 0.35, g = 0.85, b = 1, a = 1 }
                or { r = 0.95, g = 0.95, b = 0.95, a = 1 },
            scale = index == 1 and 0.95 or 0.82,
            font = "default-large-bold",
            alignment = "center",
            scale_with_zoom = false,
            players = { player.index },
            time_to_live = 90,
        }
        if object then
            render_ids[#render_ids + 1] = object.id
            text_ids[#text_ids + 1] = object.id
        end
    end
    if #render_ids > 0 then
        state.selected_shelter_render[player.index] = {
            unit_number = selected.unit_number,
            render_ids = render_ids,
            text_ids = text_ids,
        }
    end
end

local function clear_substation_render(player)
    local state = root(false)
    local existing = state and state.selected_substation_render
        and state.selected_substation_render[player.index] or nil
    if type(existing) == "table" and type(existing.render_ids) == "table" then
        for _, render_id in ipairs(existing.render_ids) do
            local object = rendering.get_object_by_id(render_id)
            destroy_render(object)
        end
    else
        destroy_render(existing)
    end
    if state and state.selected_substation_render then
        state.selected_substation_render[player.index] = nil
    end
end

local function update_substation_label(player)
    local selected = player.selected
    local record = selected and selected.name == SUBSTATION_NAME
        and record_for_force(selected.force) or nil
    if not (record and valid(record.substation)
        and selected.unit_number == record.substation.unit_number
        and selected.surface.index == record.surface_index) then
        clear_substation_render(player)
        return
    end

    local state = root(true)
    local existing = state.selected_substation_render[player.index]
    if type(existing) == "table"
        and existing.unit_number == selected.unit_number
        and type(existing.render_ids) == "table" then
        local all_valid = true
        for _, render_id in ipairs(existing.render_ids) do
            local object = rendering.get_object_by_id(render_id)
            if not (object and object.valid) then
                all_valid = false
                break
            end
            object.time_to_live = 90
        end
        if all_valid then return end
    end

    clear_substation_render(player)
    state = root(true)
    local lines = {
        {
            text = { "the-cave-shelter-power.main-label" },
            color = { r = 1.0, g = 0.78, b = 0.12, a = 1 },
            scale = 1.05,
        },
        {
            text = { "the-cave-shelter-power.main-sublabel" },
            color = { r = 1.0, g = 0.92, b = 0.55, a = 1 },
            scale = 0.82,
        },
    }
    local render_ids = {}
    for index, line in ipairs(lines) do
        local object = rendering.draw_text {
            text = line.text,
            surface = selected.surface,
            target = { entity = selected, offset = { 0, -2.35 + ((index - 1) * 0.82) } },
            color = line.color,
            scale = line.scale,
            font = "default-large-bold",
            alignment = "center",
            vertical_alignment = "middle",
            scale_with_zoom = true,
            players = { player.index },
            time_to_live = 90,
        }
        if object then render_ids[#render_ids + 1] = object.id end
    end
    if #render_ids > 0 then
        state.selected_substation_render[player.index] = {
            unit_number = selected.unit_number,
            render_ids = render_ids,
        }
    end
end

local function clear_port_render(player)
    local state = root(false)
    local render = state and state.selected_port_render and state.selected_port_render[player.index]
    destroy_render(render)
    if state and state.selected_port_render then state.selected_port_render[player.index] = nil end
end

local function update_port_label(player)
    clear_port_render(player)
    local selected = player.selected
    if not (valid(selected) and selected.unit_number) then return end
    local state = root(false)
    local record = state and state.forces and state.forces[player.force.index]
    local role = record and (
        (record.transfer_roles and record.transfer_roles[selected.unit_number])
        or (record.fluid_transfer_roles and record.fluid_transfer_roles[selected.unit_number]))
    local garden_role = nil
    local garden = record and record.garden
    if garden then
        for _, field in ipairs({ "upper_item_input", "lower_item_input" }) do
            if valid(garden[field]) and garden[field].unit_number == selected.unit_number then
                garden_role = "input"
            end
        end
        for _, field in ipairs({ "upper_item_output", "lower_item_output" }) do
            if valid(garden[field]) and garden[field].unit_number == selected.unit_number then
                garden_role = "output"
            end
        end
    end
    role = garden_role or role
    if not role then return end
    local is_storehouse = selected.name == STOREHOUSE_NAME
    local label_offset = is_storehouse and -3.5
        or (selected.name == GARDEN_STOREBOX_NAME and -2.75 or -1.15)
    local label_text
    if garden_role then
        label_text = garden_role == "input"
            and { "the-cave-shelter.garden-input" }
            or { "the-cave-shelter.garden-output" }
    else
        label_text = role == "input"
            and { "the-cave-shelter.input" }
            or { "the-cave-shelter.output" }
    end
    state.selected_port_render[player.index] = rendering.draw_text {
        surface = selected.surface,
        target = { type = "entity", entity = selected, offset = { 0, label_offset } },
        text = label_text,
        color = role == "input" and { r = 0.25, g = 1, b = 0.35, a = 1 } or { r = 1, g = 0.55, b = 0.15, a = 1 },
        scale = 1,
        alignment = "center",
        players = { player.index },
        only_in_alt_mode = false,
    }
end

local function teleport_inside(player, record)
    if not physical.can_travel(player) or nearby_record(player) ~= record then return false end
    local surface = surface_for_record(record)
    if not valid(surface) then return false end
    local origin_surface = physical.surface(player)
    local origin = physical.position(player)
    local target = physical.find_position(player, surface, { x = -0.5, y = -0.5 }, 8)
    if not physical.teleport(player, target, surface) then return false end
    local state = player_state(player)
    state.external_surface_index = origin_surface.index
    state.external_position = { x = origin.x, y = origin.y }
    state.confirm_enter_until = nil
    state.confirm_exit_until = nil
    chart_shelter_interior(record, player.force)
    return true
end

local function teleport_outside(player, record)
    if not physical.can_travel(player) or player_record_inside(player) ~= record then return false end
    local state = player_state(player)
    local surface = state.external_surface_index and game.surfaces[state.external_surface_index]
        or external_surface_for_record(record)
    if not valid(surface) then return false end
    local desired = state.external_position
        or (valid(record.entity) and { x = record.entity.position.x, y = record.entity.position.y + 5 })
        or record.spawn_position
        or { x = 0, y = 10 }
    local target = physical.find_position(player, surface, desired, 16)
    if not physical.teleport(player, target, surface) then return false end
    kill_outside_view(player)
    state.confirm_enter_until = nil
    state.confirm_exit_until = nil
    return true
end

function shelter_core.on_enter_hotkey(event)
    if not startup_enabled() then return false end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not valid(player) or not physical.can_travel(player) then return true end
    local inside = player_record_inside(player)
    local state = player_state(player)
    -- Confirmation was removed in 3.1.49. Clear legacy values from existing
    -- saves so one Ctrl+Enter always performs exactly one enter/exit action.
    state.confirm_enter_until = nil
    state.confirm_exit_until = nil
    if inside then
        teleport_outside(player, inside)
        update_entry_prompt(player)
        return true
    end

    local record = nearby_record(player)
    if not record then
        state.confirm_enter_until = nil
        player.print({ "the-cave-shelter.stand-near" })
        return true
    end
    if record.defeated or not valid(record.entity) then
        player.print({ "the-cave-shelter.entry-disabled" })
        return true
    end
    teleport_inside(player, record)
    update_entry_prompt(player)
    return true
end

function shelter_core.on_lua_shortcut(event)
    if not startup_enabled() or event.prototype_name ~= "the-cave-enter-train-interior-shortcut" then return false end
    return shelter_core.on_enter_hotkey(event)
end

local function update_defeat_gui(seconds, force)
    for _, player in pairs(game.connected_players or {}) do
        if shelter_core.teams.player_force(player) == force then
            local frame = player.gui.screen[DEFEAT_FRAME]
            if not (frame and frame.valid) then
                frame = player.gui.screen.add { type = "frame", name = DEFEAT_FRAME, direction = "vertical" }
                frame.style.width = 430
                frame.style.padding = 12
                local title = frame.add { type = "label", name = "title", caption = { "the-cave-shelter.defeat-title" } }
                title.style.font = "heading-1"
                title.style.font_color = { r = 1, g = 0.2, b = 0.1 }
                title.style.horizontally_stretchable = true
                title.style.horizontal_align = "center"
                local label = frame.add { type = "label", name = "countdown", caption = "" }
                label.style.font = "heading-2"
                label.style.horizontally_stretchable = true
                label.style.horizontal_align = "center"
            end
            frame.countdown.caption = { "the-cave-shelter.defeat-countdown", seconds }
            frame.auto_center = true
        end
    end
end

local function clear_defeat_gui(force)
    for _, player in pairs(game.players or {}) do
        if not force or shelter_core.teams.player_force(player) == force then clear_gui(player, DEFEAT_FRAME) end
    end
end

local function begin_defeat(record)
    local state = root(true)
    if state.defeats[record.force_index] then return end
    record.defeated = true
    state.defeats[record.force_index] = {
        force_index = record.force_index,
        ends_tick = game.tick + 30 * 60,
        last_seconds = nil,
    }
    local force = game.forces[record.force_index]
    if force and force.valid then force.print({ "the-cave-shelter.destroyed" }, { r = 1, g = 0.2, b = 0.1 }) end
    if train_wave_defense.set_force_paused then train_wave_defense.set_force_paused(force, true) end
    shelter_core.defeat.begin(force)
    update_defeat_gui(30, force)
end

function shelter_core.set_soft_reset_handler(handler)
    soft_reset_handler = handler
end

function shelter_core.on_entity_damaged(event)
    if not startup_enabled() then return false end
    local entity = event and event.entity
    if not (valid(entity) and entity.name == SHELTER_NAME) then return false end
    local record = record_for_force(entity.force)
    if not (record and valid(record.entity) and record.entity.unit_number == entity.unit_number) then return false end
    ensure_shelter_shield(record, entity.force, false)
    local source_force = event.force
    if not (source_force and source_force.valid) then
        local cause = event.cause
        source_force = valid(cause) and cause.force or nil
    end
    local enemy_damage = source_force and source_force.valid and source_force.name == "enemy"
    if not enemy_damage then
        -- Shelter Defense accepts enemy-force damage only. Restore the physical
        -- representation from the untouched scripted pool without starting the
        -- Shield repair delay.
        sync_shelter_physical_health(record)
        return true
    end
    local damage = math.max(0,
        tonumber(event.final_damage_amount) or tonumber(event.original_damage_amount) or 0)
    if damage <= 0 then return false end
    record.shield_health = math.max(0,
        (tonumber(record.shield_health) or tonumber(record.shield_max_health) or MAX_HEALTH) - damage)
    record.shield_last_damage_tick = event.tick or game.tick
    if record.shield_health > 0 then
        sync_shelter_physical_health(record)
    else
        begin_defeat(record)
        pcall(function() entity.die(source_force, event.cause) end)
    end
    return false
end

function shelter_core.on_entity_died(event)
    if not startup_enabled() then return false end
    local entity = event and event.entity
    if not (entity and entity.name == SHELTER_NAME) then return false end
    local state = root(false)
    local force_index = entity.unit_number and state and state.by_entity_unit and state.by_entity_unit[entity.unit_number]
    local record = force_index and state.forces[force_index]
    if record then begin_defeat(record) end
    return record ~= nil
end

local function update_defeat()
    local state = root(false)
    if not (state and state.defeats) then return end
    local indexes = {}
    for index in pairs(state.defeats) do indexes[#indexes + 1] = index end
    table.sort(indexes)
    for _, index in ipairs(indexes) do
        local countdown = state.defeats[index]
        local force = game.forces[index]
        if countdown and valid(force) then
            local remaining = math.max(0, (tonumber(countdown.ends_tick) or game.tick) - game.tick)
            local seconds = math.ceil(remaining / 60)
            if seconds ~= countdown.last_seconds then
                countdown.last_seconds = seconds
                update_defeat_gui(seconds, force)
            end
            if remaining <= 0 then
                clear_defeat_gui(force)
                state.defeats[index] = nil
                if type(soft_reset_handler) == "function" then
                    soft_reset_handler("shelter-destroyed", {
                        force_index = index,
                        post_reset_countdown_ticks = 30 * 60,
                        shelter_mode = true,
                    })
                end
            end
        end
    end
end

function shelter_core.on_defeat_tick()
    update_defeat()
end

function shelter_core.on_selected_entity_changed(event)
    if not startup_enabled() then return end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not valid(player) then return end
    update_hover(player)
    update_substation_label(player)
    update_port_label(player)
end

function shelter_core.on_chunk_generated(event)
    if not startup_enabled() then return false end
    local surface = event and event.surface
    if not shelter_core.is_shelter_surface(surface) then return false end

    if shelter_core.is_shelter_garden_surface(surface) then
        local record = record_for_surface(surface)
        local garden = record and record.garden
        garden_void_area(surface, event.area, garden)
        return true
    end

    -- The creation pass pre-generates enough chunks for the complete 300x300
    -- progression. Later map-view generation therefore belongs outside the
    -- active room and is converted directly to void without rescanning the
    -- whole room for every generated chunk.
    local record = record_for_surface(surface)
    void_area(surface, event.area, record and record.room_dimensions or nil)
    return true
end

function shelter_core.on_chunk_charted(event)
    if not (startup_enabled() and event and game) then return false end
    local surface = event.surface_index and game.surfaces[event.surface_index]
    if not shelter_core.is_shelter_garden_surface(surface) then return false end
    local record = record_for_surface(surface)
    garden_void_area(surface, event.area, record and record.garden or nil)
    return true
end

function shelter_core.on_research_finished(event)
    if not startup_enabled() then return end
    local research = event and event.research
    local force = research and research.force
    if not (force and force.valid and research.name) then return end
    if research.name == "kr-shelter" then
        disable_external_shelter_research(force)
        return
    end
    local record = record_for_force(force)
    if not record then return end
    if record.defeated then return end
    if research.name:sub(1, #EXPANSION_PREFIX) == EXPANSION_PREFIX then
        paint_room(record, force, false)
        void_generated_chunks(surface_for_record(record), record.room_dimensions)
        chart_shelter_interior(record, force)
        force.print({ "the-cave-shelter.expanded", record.room_dimensions.width, record.room_dimensions.height })
    elseif research.name:sub(1, #BATTERY_PREFIX) == BATTERY_PREFIX then
        ensure_power_entities(record, force, battery_level(force))
        force.print({ "the-cave-shelter.battery-upgraded", battery_level(force) })
    elseif research.name:sub(1, #SHIELD_PREFIX) == SHIELD_PREFIX then
        ensure_shelter_shield(record, force, true)
        force.print({ "the-cave-shelter.shield-upgraded", shelter_shield_level(force) })
    elseif research.name:sub(1, #GARDEN_PREFIX) == GARDEN_PREFIX then
        shelter_garden.ensure(record, force, true)
        force.print({ "the-cave-shelter.garden-upgraded", garden_stage(force) })
    elseif research.name:sub(1, #ATTACK_DISTANCE_PREFIX) == ATTACK_DISTANCE_PREFIX then
        if train_wave_defense.on_shelter_distance_researched then
            train_wave_defense.on_shelter_distance_researched(force)
        end
        force.print({ "the-cave-shelter.attack-distance-upgraded", shelter_core.attack_distance_chunks(force), shelter_core.generation_radius_chunks(force) })
    end
end

function shelter_core.on_research_reversed(event)
    if not startup_enabled() then return end
    local research = event and event.research
    local force = research and research.force
    if not (research and research.name and force and force.valid) then return end
    local record = record_for_force(force)
    if not (record and not record.defeated) then return end
    if research.name:sub(1, #BATTERY_PREFIX) == BATTERY_PREFIX then
        ensure_power_entities(record, force, battery_level(force))
    elseif research.name:sub(1, #SHIELD_PREFIX) == SHIELD_PREFIX then
        ensure_shelter_shield(record, force, true)
    elseif research.name:sub(1, #GARDEN_PREFIX) == GARDEN_PREFIX then
        shelter_garden.ensure(record, force, true)
    end
end

local function refund_entity(event, entity)
    if portable_cave_accumulators.refund_placement(event) then return end
    local item_name = entity.name
    if not prototypes.item[item_name] then return end
    local player = event and event.player_index and game.get_player(event.player_index)
    if player and player.valid then
        local inserted = player.insert { name = item_name, count = 1 }
        if inserted < 1 then entity.surface.spill_item_stack { position = entity.position, stack = { name = item_name, count = 1 }, force = entity.force, allow_belts = false } end
        return
    end
    local robot = event and event.robot
    local inserted = 0
    if valid(robot) then
        pcall(function() inserted = robot.insert { name = item_name, count = 1 } end)
    end
    if inserted < 1 then
        entity.surface.spill_item_stack { position = entity.position, stack = { name = item_name, count = 1 }, force = entity.force, allow_belts = false }
    end
end

local function utility_lane_entity_identity(entity)
    if not valid(entity) then return nil, nil end
    local name, entity_type = entity.name, entity.type
    if entity_type == "entity-ghost" then
        pcall(function() name = entity.ghost_name or name end)
        pcall(function() entity_type = entity.ghost_type or entity_type end)
    end
    return name, entity_type
end

local function allowed_on_utility_lane(entity)
    local name, entity_type = utility_lane_entity_identity(entity)
    if not name then return false end
    if UTILITY_BLOCKED_ENTITY_NAMES[name] or UTILITY_BLOCKED_ENTITY_NAMES[entity_type] then return false end
    return UTILITY_ALLOWED_ENTITY_NAMES[name] == true
        or UTILITY_ALLOWED_ENTITY_TYPES[entity_type] == true
end

local function position_in_utility_lane(record, position)
    if not (record and record.room_dimensions and position) then return false end
    local left, right, top, bottom = room_bounds(record.room_dimensions)
    local x, y = position.x, position.y
    if x < left or x >= right + 1 or y < top or y >= bottom + 1 then return false end
    return x < left + UTILITY_LANE_DEPTH
        or x >= right + 1 - UTILITY_LANE_DEPTH
        or y < top + UTILITY_LANE_DEPTH
        or y >= bottom + 1 - UTILITY_LANE_DEPTH
end

local function reject_invalid_utility_lane_build(event, entity)
    if not (valid(entity) and entity.surface and entity.surface.valid) then return false end
    local record = record_for_surface(entity.surface)
    if not (record and position_in_utility_lane(record, entity.position)) then return false end
    if allowed_on_utility_lane(entity) then return false end

    local name, entity_type = utility_lane_entity_identity(entity)
    local blocked_offshore_pump = UTILITY_BLOCKED_ENTITY_NAMES[name]
        or UTILITY_BLOCKED_ENTITY_NAMES[entity_type]
    local player = event and event.player_index and game.get_player(event.player_index)
    if player and player.valid then
        player.print(blocked_offshore_pump
            and { "the-cave-shelter.utility-lane-offshore" }
            or { "the-cave-shelter.utility-lane-only" })
    end
    refund_entity(event, entity)
    pcall(function() entity.destroy() end)
    return true
end

function shelter_core.on_built(event)
    if not startup_enabled() then return false end
    local entity = event and (event.entity or event.created_entity)
    if not (valid(entity) and shelter_core.is_shelter_surface(entity.surface)) then return false end
    if entity.name == SUBSTATION_NAME or entity.name == GARDEN_SUBSTATION_NAME then return false end

    local box = entity.bounding_box
    if shelter_core.is_shelter_garden_surface(entity.surface) then
        local portal_left, portal_right, portal_top, portal_bottom = garden_lower_portal_bounds()
        local landing_left, landing_right, landing_top, landing_bottom = garden_landing_bounds()
        local overlaps_portal = boxes_overlap(box, {
            left_top = { x = portal_left, y = portal_top },
            right_bottom = { x = portal_right, y = portal_bottom },
        })
        local overlaps_landing = boxes_overlap(box, {
            left_top = { x = landing_left, y = landing_top },
            right_bottom = { x = landing_right, y = landing_bottom },
        })
        if entity.type ~= "character" and (overlaps_portal or overlaps_landing) then
            refund_entity(event, entity)
            pcall(function() entity.destroy() end)
            local player = event.player_index and game.get_player(event.player_index)
            if valid(player) then
                player.print(overlaps_portal
                    and { "the-cave-shelter.garden-portal-blocked" }
                    or { "the-cave-shelter.garden-landing-pad-blocked" })
            end
            return true
        end
        return false
    end

    if reject_invalid_utility_lane_build(event, entity) then return true end
    local overlaps_pad = box
        and box.right_bottom.x > -2 and box.left_top.x < 2
        and box.right_bottom.y > -2 and box.left_top.y < 2
    local portal_left, portal_right, portal_top, portal_bottom = garden_upper_portal_bounds()
    local overlaps_garden_portal = boxes_overlap(box, {
        left_top = { x = portal_left, y = portal_top },
        right_bottom = { x = portal_right, y = portal_bottom },
    })
    if entity.type ~= "character" and (overlaps_pad or overlaps_garden_portal) then
        refund_entity(event, entity)
        pcall(function() entity.destroy() end)
        local player = event.player_index and game.get_player(event.player_index)
        if player and player.valid then
            player.print(overlaps_garden_portal
                and { "the-cave-shelter.garden-portal-blocked" }
                or { "the-cave-shelter.entry-pad-blocked" })
        end
        return true
    end
    return false
end

function shelter_core.on_tiles_changed(surface, tiles)
    if not (startup_enabled() and shelter_core.is_shelter_surface(surface)) then return false end
    if shelter_core.is_shelter_garden_surface(surface) then
        local portal_left, portal_right, portal_top, portal_bottom = garden_lower_portal_bounds()
        local landing_left, landing_right, landing_top, landing_bottom = garden_landing_bounds()
        local center = tile_or_fallback("green-refined-concrete",
            tile_or_fallback("green-concrete", "refined-concrete"))
        local landing = tile_or_fallback("refined-concrete", center)
        local corrections = {}
        for _, changed in pairs(tiles or {}) do
            local position = changed.position or changed
            local x, y = math.floor(position.x), math.floor(position.y)
            local expected = nil
            if position_in_bounds({ x = x, y = y },
                portal_left, portal_right, portal_top, portal_bottom) then
                expected = center
            elseif position_in_bounds({ x = x, y = y },
                landing_left, landing_right, landing_top, landing_bottom) then
                expected = landing
            end
            if expected and surface.get_tile(x, y).name ~= expected then
                corrections[#corrections + 1] = {
                    name = expected,
                    position = { x = x, y = y },
                }
            end
        end
        if #corrections > 0 then
            surface.set_tiles(corrections, true, false, false, false)
        end
        return #corrections > 0
    end
    local record = record_for_surface(surface)
    local left, right, top, bottom
    if record and record.room_dimensions then
        left, right, top, bottom = room_bounds(record.room_dimensions)
    end
    local core = tile_or_fallback("green-refined-concrete", tile_or_fallback("green-concrete", "refined-concrete"))
    local water = tile_or_fallback("water", core)
    local pad = tile_or_fallback("refined-concrete", core)
    local utility = tile_or_fallback("blue-refined-concrete", tile_or_fallback("blue-concrete", core))
    local corrections = {}
    for _, changed in pairs(tiles or {}) do
        local position = changed.position or changed
        local x, y = math.floor(position.x), math.floor(position.y)
        local expected = nil
        if left and (x < left or x > right or y < top or y > bottom) then
            expected = "out-of-map"
        elseif left and (x < left + UTILITY_LANE_DEPTH
            or x > right - UTILITY_LANE_DEPTH
            or y < top + UTILITY_LANE_DEPTH
            or y > bottom - UTILITY_LANE_DEPTH) then
            expected = utility
        end
        if x >= -18 and x <= 17 and y >= -18 and y <= 17 then
            expected = core
            if x >= -6 and x <= 5 and y >= -8 and y <= -5
                and not (x >= -3 and x <= 2) then
                expected = water
            elseif x >= -2 and x <= 1 and y >= -2 and y <= 1 then
                expected = pad
            end
        end
        if expected and surface.get_tile(x, y).name ~= expected then
            corrections[#corrections + 1] = { name = expected, position = { x = x, y = y } }
        end
    end
    if #corrections > 0 then surface.set_tiles(corrections, true, false, false, false) end
    return #corrections > 0
end

function shelter_garden.teleport_to(player, record)
    if not physical.can_travel(player) or not (record and record.force_index == player.force.index
        and physical.on_surface(player, surface_for_record(record))) then return false end
    if not position_in_bounds(physical.position(player), garden_upper_portal_bounds()) then return false end
    local garden = shelter_garden.ensure(record, player.force, false)
    local surface = garden_surface_for_record(record)
    if not (garden and valid(surface)) then return false end
    local left, right, top, bottom = garden_landing_bounds()
    local target = { x = (left + right) * 0.5, y = (top + bottom) * 0.5 }
    local safe = physical.find_position(player, surface, target, 1.5, 0.25)
    local state = player_state(player)
    pcall(function() player.driving = false end)
    if not physical.teleport(player, safe, surface) then return false end
    state.garden_portal_cooldown_tick = game.tick + 15
    kill_outside_view(player)
    return true
end

function shelter_garden.teleport_from(player, record)
    if not physical.can_travel(player) or not (record and record.force_index == player.force.index
        and physical.on_surface(player, garden_surface_for_record(record))) then return false end
    if not position_in_bounds(physical.position(player), garden_lower_portal_bounds()) then return false end
    local surface = surface_for_record(record)
    if not valid(surface) then return false end
    local left, right, top, bottom = garden_landing_bounds()
    local target = { x = (left + right) * 0.5, y = (top + bottom) * 0.5 }
    local safe = physical.find_position(player, surface, target, 1.5, 0.25)
    local state = player_state(player)
    pcall(function() player.driving = false end)
    if not physical.teleport(player, safe, surface) then return false end
    state.garden_portal_cooldown_tick = game.tick + 15
    chart_shelter_interior(record, player.force)
    return true
end

function shelter_core.on_player_changed_position(event)
    if not startup_enabled() then return false end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not physical.can_travel(player) then return false end
    local state = player_state(player)
    if (tonumber(state.garden_portal_cooldown_tick) or 0) > game.tick then return false end

    if shelter_core.is_shelter_garden_surface(physical.surface(player)) then
        local record = record_for_surface(physical.surface(player))
        if record then
            local left, right, top, bottom = garden_lower_portal_bounds()
            if position_in_bounds(physical.position(player), left, right, top, bottom) then
                return shelter_garden.teleport_from(player, record)
            end
        end
        return false
    end

    local record = player_record_inside(player)
    if not record then return false end
    local left, right, top, bottom = garden_upper_portal_bounds()
    if position_in_bounds(physical.position(player), left, right, top, bottom) then
        return shelter_garden.teleport_to(player, record)
    end
    return false
end

function shelter_core.on_player_respawned(event)
    if not startup_enabled() then return end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not valid(player) then return end
    local record = record_for_force(player.force)
    if not record then return end
    local surface = external_surface_for_record(record)
    local target = record.spawn_position or safe_external_spawn(record, player.force)
    if valid(surface) and target then
        target = physical.find_position(player, surface, target, 12)
        physical.teleport(player, target, surface)
    end
end

function shelter_core.on_player_changed_surface(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    if not valid(player) then return end
    clear_shelter_hover_render(player)
    clear_substation_render(player)
    clear_port_render(player)
    local inside = shelter_garden.player_record_in_complex(player)
    if inside then
        chart_shelter_interior(inside, player.force)
        draw_outside_view(player, inside)
    else
        kill_outside_view(player)
    end
    update_entry_prompt(player)
end

function shelter_core.on_player_created(event)
    if not startup_enabled() then return end
    local state = root(false)
    if not (state and state.new_game_enabled) then return end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not valid(player) then return end
    disable_external_shelter_research(player.force)
    local record = record_for_force(player.force)
    if not (state.defeats and state.defeats[player.force.index]) then clear_gui(player, DEFEAT_FRAME) end
    if record then
        shelter_garden.ensure(record, player.force, false)
        safe_external_spawn(record, player.force)
    end
end

function shelter_core.has_base(force)
    return shelter_core.get_anchor(force) ~= nil
end

function shelter_core.base_surface(force)
    local record = record_for_force(force)
    local surface = external_surface_for_record(record)
    return valid(surface) and surface or nil
end

function shelter_core.on_arrival(player)
    if not startup_enabled() or not valid(player)
        or player.controller_type ~= defines.controllers.character then return nil end
    local state = root(false)
    if not (state and state.new_game_enabled) then return nil end
    local character, surface = physical.character_context(player)
    if not (valid(character) and shelter_core.worlds.is_cave_world(surface)) or shelter_core.worlds.is_template(surface) then return nil end
    local force = shelter_core.teams.player_force(player)
    if not valid(force) or shelter_core.defeat.is_active(force) then return nil end
    if shelter_core.worlds.is_copy(surface) and shelter_core.worlds.owner_force(surface) ~= force then return nil end
    local record = record_for_force(force)
    if record and (valid(record.entity) or record.defeated) then return record end
    disable_external_shelter_research(force)
    -- The old initializer built the fixed shelter before the character existed.
    -- Move the arriving character aside so it does not change that layout.
    local spawn = force.get_spawn_position(surface)
    local aside = physical.find_position(player, surface, { x = spawn.x, y = spawn.y + 10 }, 32)
    if not aside or not physical.teleport(player, aside, surface) then return nil end
    record = create_shelter_for_force(force, surface)
    if record then
        local target = physical.find_position(player, surface, force.get_spawn_position(surface), 12)
        if target then physical.teleport(player, target, surface) end
    end
    return record
end

function shelter_core.owned_surfaces(force)
    local index = type(force) == "number" and force or (valid(force) and force.index)
    local state = root(false)
    local record = state and state.forces and state.forces[index]
    local surfaces = {}
    for _, surface in pairs({ surface_for_record(record), garden_surface_for_record(record) }) do
        if valid(surface) then surfaces[#surfaces + 1] = surface end
    end
    return surfaces
end

function shelter_core.clear_force(force_index)
    local state = root(false)
    if not state then return end
    local force = game.forces[force_index]
    for unit, owner in pairs(state.by_entity_unit or {}) do
        if owner == force_index then state.by_entity_unit[unit] = nil end
    end
    if state.forces then state.forces[force_index] = nil end
    if state.defeats then state.defeats[force_index] = nil end
    for _, player in pairs(game.players) do
        if valid(force) and shelter_core.teams.player_force(player) == force then
            state.player_states[player.index] = nil
            clear_gui(player, DEFEAT_FRAME)
            clear_gui(player, ENTRY_PROMPT)
            clear_shelter_hover_render(player)
            clear_substation_render(player)
            clear_port_render(player)
            kill_outside_view(player)
        end
    end
end

function shelter_core.sync_force(force)
    if not startup_enabled() or not valid(force) then return end
    disable_external_shelter_research(force)
    local reset = storage.the_cave_soft_reset
    if shelter_core.teams.is_resetting(force) or (reset and reset.active) then return end
    local record = record_for_force(force)
    if record and valid(record.entity) then
        record.external_pole_cache = nil
        if record.garden then record.garden.infrastructure_ready = nil end
        ensure_shelter_shield(record, force, false)
        ensure_power_entities(record, force, battery_level(force))
        shelter_garden.ensure(record, force, true)
        safe_external_spawn(record, force)
    end
end

function shelter_core.on_player_joined_game(event)
    if not startup_enabled() then return end
    shelter_core.on_player_created(event)
end

function shelter_core.refresh_spawn_positions()
    local state = root(false)
    if not state then return end
    for force_index, record in pairs(state.forces or {}) do
        local force = game.forces[force_index]
        if force and force.valid and valid(record.entity) then safe_external_spawn(record, force) end
    end
end

function shelter_core.on_soft_reset_world_ready(reset)
    -- Arrival creates the shelter after players have returned from the reset
    -- lobby. Keep the research restrictions while the map is being rebuilt.
    if not startup_enabled() then return end
    for _, snapshot in ipairs(reset and reset.force_snapshots or {}) do
        local force = game.forces[snapshot.index]
        if valid(force) then disable_external_shelter_research(force) end
    end
end

function shelter_core.on_init(is_soft_reset)
    if not startup_enabled() then
        if not is_soft_reset then print_startup_conflict() end
        return
    end
    if is_soft_reset then
        local reset = storage and storage.the_cave_soft_reset
        if not (reset and reset.shelter_mode == true) then return end
    end
    local state = root(true)
    state.new_game_enabled = true
    state.created_by_version = "3.0.1"
    state.is_soft_reset_world = is_soft_reset == true
    for _, force in pairs(game.forces or {}) do disable_external_shelter_research(force) end
    initialize_shelter_pollution_transfer()
    if train_wave_defense.on_shelter_init then train_wave_defense.on_shelter_init(true) end
end

function shelter_core.on_configuration_changed()
    local old = root(false)
    if old and old.defeat then
        old.defeats = old.defeats or {}
        old.defeats[old.defeat.force_index] = old.defeat
        shelter_core.defeat.begin(game.forces[old.defeat.force_index])
        old.defeat = nil
    end
    if not startup_enabled() then
        for _, player in pairs(game.players or {}) do
            clear_gui(player, ENTRY_PROMPT)
            clear_shelter_hover_render(player)
            clear_substation_render(player)
            kill_outside_view(player)
            clear_gui(player, DEFEAT_FRAME)
        end
        print_startup_conflict()
        return
    end
    local state = root(false)
    -- Compatibility lock: upgrading an old save never injects a Shelter into
    -- an occupied base. Only saves born in Shelter mode own this marker.
    if not (state and state.new_game_enabled) then return end
    for _, force in pairs(game.forces or {}) do disable_external_shelter_research(force) end
    for force_index, record in pairs(state.forces or {}) do
        local force = game.forces[force_index]
        if force and force.valid then
            record.external_pole_cache = nil
            if record.garden then record.garden.infrastructure_ready = nil end
            disable_external_shelter_research(force)
            if valid(record.entity) then
                record.entity.minable_flag = false
                pcall(function() record.entity.rotatable = false end)
                ensure_shelter_shield(record, force, true)
                configure_interior_surface(surface_for_record(record))
                paint_room(record, force, false)
                void_generated_chunks(surface_for_record(record), record.room_dimensions)
                chart_shelter_interior(record, force)
                ensure_transfer_layout(record, force)
                shelter_garden.ensure(record, force, true)
                -- Migrate the old hidden-accumulator bridge immediately when
                -- an existing Shelter save loads this version.
                ensure_power_entities(record, force, battery_level(force))
                safe_external_spawn(record, force)
            end
        end
    end
    if train_wave_defense.on_shelter_configuration_changed then
        train_wave_defense.on_shelter_configuration_changed(true)
    end
    initialize_shelter_pollution_transfer()
end

function shelter_core.on_tick(event)
    if not startup_enabled() or not (event and event.tick) then return end
    local state = root(false)
    if not (state and state.new_game_enabled) then return end
    if event.tick % INTERIOR_POLLUTION_SYNC_TICKS == 0 then
        sync_shelter_pollution()
    end
    if event.tick % 15 == 0 then
        for _, player in pairs(game.connected_players or {}) do update_entry_prompt(player) end
        for force_index, record in pairs(state.forces or {}) do
            local force = game.forces[force_index]
            if force and force.valid and not record.defeated then
                if not transfer_layout_ready(record) then
                    ensure_transfer_layout(record, force)
                end
                transfer_fluids(record)
                sync_garden_items(record, force)
                sync_power(record, force, POWER_SYNC_INTERVAL_TICKS)
            end
        end
    end
    if event.tick % 60 == 0 then
        for force_index, record in pairs(state.forces or {}) do
            local force = game.forces[force_index]
            if force and force.valid and not record.defeated then
                ensure_shelter_shield(record, force, false)
                local shield_level = shelter_shield_level(force)
                local repair_rate = shelter_shield_repair_per_second(shield_level)
                local shield_health = tonumber(record.shield_health) or 0
                local shield_maximum = tonumber(record.shield_max_health)
                    or shelter_shield_max_health(shield_level)
                if repair_rate > 0 and shield_health > 0 and shield_health < shield_maximum
                    and event.tick - (tonumber(record.shield_last_damage_tick) or 0)
                        >= SHIELD_REPAIR_DELAY_TICKS then
                    record.shield_health = math.min(shield_maximum, shield_health + repair_rate)
                    sync_shelter_physical_health(record)
                end
                transfer_inventories(record)
            end
        end
        for _, player in pairs(game.connected_players or {}) do
            update_hover(player)
            update_substation_label(player)
            update_port_label(player)
        end
        update_outside_views()
    end
    update_defeat()
    if train_wave_defense.on_tick then train_wave_defense.on_tick(event) end
end

return shelter_core
