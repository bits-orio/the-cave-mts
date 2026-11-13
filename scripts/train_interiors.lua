local physical = require("scripts.player_physical")
local cave_worlds = require("scripts.cave_worlds")
local cave_teams = require("scripts.cave_teams")
local depth_levels = require("scripts.depth_levels")
local maintenance = require("scripts.interior_maintenance")
local item_transfer = require("scripts.interior_item_transfer")
local settings = require("scripts.game_settings").proxy(settings)

local hash = require("scripts.lib.hash")

local train_interiors = {}
train_interiors.portable_cave_accumulators = require("scripts.portable_cave_accumulators")
train_interiors.interior_pollution = require("scripts.interior_pollution")
train_interiors.wave_defense = require("scripts.train_wave_defense")
train_interiors.wave_defense.register_commands()
train_interiors.interior_pollution.register_commands()

local SURFACE_PREFIX = "the-cave-train-interior-"
local WAGON_PICK_STREAM = 91002
local TRAIN_CACHE_MIN_DISTANCE = 18 * 32
train_interiors.pollution_config = {
    sync_ticks = 3 * 60,
    transfer_version = 1,
}
train_interiors.cache_config = {
    type_weights = {
        { name = "cargo-wagon", weight = 45 },
        { name = "fluid-wagon", weight = 25 },
        { name = "locomotive", weight = 25 },
        { name = "artillery-wagon", weight = 5 },
    },
    starter_tile = "blue-refined-concrete",
    site_tile = "black-refined-concrete",
}
train_interiors.main_train_config = {
    prefix = "the-cave-main-train-expansion-",
    base_capacity = 3,
    max_level = 20,
    max_capacity = 23,
}
train_interiors.garden_config = {
    prefix = "the-cave-locomotive-garden-",
    max_level = 3,
    layout_version = 3057,
    void_layout_version = "3.0.57-storebox-pads",
    portal_layout_version = "3.0.59-upper-portal-five-tiles-down",
    portal_sprite_name = "the-cave-locomotive-garden-portal",
    surface_prefix = SURFACE_PREFIX .. "garden-",
    center_size = 18,
    stage_half_sizes = { 30, 42, 54 },
    water_width = 12,
    water_depth = 4,
    substation_island_size = 2,
    portal_size = 2,
    item_storebox_name = "the-cave-2x2-container",
    item_input_name = "the-cave-2x2-container",
    item_output_name = "the-cave-2x2-container",
    fluid_input_name = "the-cave-garden-fluid-input",
    fluid_output_name = "the-cave-garden-fluid-output",
    infrastructure_layout_version = "3.0.58-rotatable-pipes-and-safe-fluid-transfer",
    upper_portal_y_shift = 5,
    upper_transfer_y_offset = 8,
    item_input_x_offset = -10,
    fluid_input_x_offset = -6,
    item_output_x_offset = 9,
    fluid_output_x_offset = 5,
    item_storebox_visual_size = 4,
    fluid_transfer_per_sync = 5000,
    fixture_position_epsilon = 0.51,
    maintenance_layout_version = "3.2.27-fixed-garden-v1",
    fixture_fields = {
        "upper_item_input", "upper_item_output", "lower_item_input", "lower_item_output",
        "upper_fluid_input", "upper_fluid_output", "lower_fluid_input", "lower_fluid_output",
        "lower_substation",
    },
}
local INTERIOR_WAGON_SPACING = 96
local INTERIOR_LAYOUT_VERSION = 3061
local TRAIN_INTERIOR_EXPANSION = {
    prefix = "the-cave-train-interior-expansion-",
    max_level = 6,
    core_size = 18,
    -- Exact even connector widths for Level 0 through Level 6. Ten restricted
    -- blue utility rows remain immediately above and below the black corridor.
    connector_widths = { 40, 60, 80, 100, 160, 220, 280 },
    -- Level 0 starts at 40x40. Levels 1-2 grow as squares, Level 3 reaches
    -- the collision-safe 92-tile horizontal width, and Levels 4-6 expand only
    -- vertically. The 96-tile wagon spacing leaves a four-tile connector gap.
    dimensions = {
        { width = 40, height = 40 },
        { width = 60, height = 60 },
        { width = 80, height = 80 },
        { width = 92, height = 100 },
        { width = 92, height = 160 },
        { width = 92, height = 220 },
        { width = 92, height = 280 },
    },
}
local ROLLING_STOCK_SPACING = 7
train_interiors.entry_prompt = {
    gui_name = "the_cave_train_entry_prompt",
    title_name = "the_cave_train_entry_prompt_title",
    text_name = "the_cave_train_entry_prompt_text",
    range = 10,
    width = 380,
}
local HIDDEN_MAP_RADAR_NAME = "the-cave-train-hidden-radar"
local MAP_VIEW_VOID_VERSION = 3053
local TRAIN_POWER_J_PER_MJ = 1000000
local TRAIN_POWER_LEVEL_CAPACITY_MJ = {
    2000, 2500, 3200, 4200, 5500,
    7000, 9000, 12000, 15000, 20000,
    25000, 32000, 42000, 55000, 70000,
    90000, 120000, 150000, 200000, 250000,
}
-- One input-only electric interface is attached to the interior network. Its
-- prototype charge rate scales with Train Battery research, while the battery
-- itself remains independent scripted storage rather than an accumulator.
local TRAIN_POWER_LEVEL_INPUT_INTERFACE_NAMES = {
    "the-cave-train-battery-charge-interface-l1",
    "the-cave-train-battery-charge-interface-l2",
    "the-cave-train-battery-charge-interface-l3",
    "the-cave-train-battery-charge-interface-l4",
    "the-cave-train-battery-charge-interface-l5",
    "the-cave-train-battery-charge-interface-l6",
    "the-cave-train-battery-charge-interface-l7",
    "the-cave-train-battery-charge-interface-l8",
    "the-cave-train-battery-charge-interface-l9",
    "the-cave-train-battery-charge-interface-l10",
    "the-cave-train-battery-charge-interface-l11",
    "the-cave-train-battery-charge-interface-l12",
    "the-cave-train-battery-charge-interface-l13",
    "the-cave-train-battery-charge-interface-l14",
    "the-cave-train-battery-charge-interface-l15",
    "the-cave-train-battery-charge-interface-l16",
    "the-cave-train-battery-charge-interface-l17",
    "the-cave-train-battery-charge-interface-l18",
    "the-cave-train-battery-charge-interface-l19",
    "the-cave-train-battery-charge-interface-l20",
}
local TRAIN_POWER_LEVEL_CHARGE_RATE_MW = {
    50, 100, 150, 200, 250,
    300, 350, 400, 450, 500,
    550, 600, 650, 700, 750,
    800, 850, 900, 950, 1000,
}
local TRAIN_POWER_LEVEL_OUTPUT_RATE_MW = {
    50, 100, 150, 250, 400, 600,
    600, 600, 600, 600, 600, 600, 600,
    600, 600, 600, 600, 600, 600, 600,
}
local TRAIN_POWER_TECH_PREFIX = "the-cave-train-battery-upgrade-"
local TRAIN_POWER_DEFAULT_LEVEL = 0
local TRAIN_POWER_CHARGE_START_RATIO = 0.25
local TRAIN_POWER_CHARGE_STOP_RATIO = 1.0
local TRAIN_POWER_OUTPUT_ACCUMULATOR_NAME = "the-cave-train-battery-output" -- legacy prototype
local TRAIN_POWER_LEGACY_INTERNAL_POLE_NAME = "the-cave-train-battery-inside-pole"
local TRAIN_POWER_OUTPUT_POLE_NAME = "the-cave-train-battery-output-pole"
local TRAIN_POWER_LEGACY_BUS_POLE_NAME = "the-cave-train-battery-bus-pole"
train_interiors.power_range_config = {
    half_size = 10,
    range_version = "2.7.60-square-range-10-wire-connectors",
    render_version = "2.7.60-power-range-outline-10",
    line_width = 2,
    line_color = { r = 1, g = 0.78, b = 0.08, a = 0.92 },
}
local TRAIN_POWER_INTERNAL_INPUT_VERSION = "2.7.43-visible-main-substation"
train_interiors.power_bridge_config = {
    output_interface_names = {
        "the-cave-train-battery-discharge-interface-l1",
        "the-cave-train-battery-discharge-interface-l2",
        "the-cave-train-battery-discharge-interface-l3",
        "the-cave-train-battery-discharge-interface-l4",
        "the-cave-train-battery-discharge-interface-l5",
        "the-cave-train-battery-discharge-interface-l6",
        "the-cave-train-battery-discharge-interface-l7",
        "the-cave-train-battery-discharge-interface-l8",
        "the-cave-train-battery-discharge-interface-l9",
        "the-cave-train-battery-discharge-interface-l10",
        "the-cave-train-battery-discharge-interface-l11",
        "the-cave-train-battery-discharge-interface-l12",
        "the-cave-train-battery-discharge-interface-l13",
        "the-cave-train-battery-discharge-interface-l14",
        "the-cave-train-battery-discharge-interface-l15",
        "the-cave-train-battery-discharge-interface-l16",
        "the-cave-train-battery-discharge-interface-l17",
        "the-cave-train-battery-discharge-interface-l18",
        "the-cave-train-battery-discharge-interface-l19",
        "the-cave-train-battery-discharge-interface-l20",
    },
    legacy_output_interface_name = "the-cave-train-battery-discharge-interface",
    sync_interval_ticks = 15,
    version = "3.1.6-exterior-generation-first-v2",
    output_buffer_runtime_version = "3.1.8-existing-output-buffer-capacity-v1",
}
local TRAIN_LOCOMOTIVE_SUBSTATION_NAME = "the-cave-train-locomotive-substation"
local TRAIN_GARDEN_SUBSTATION_NAME = "the-cave-train-garden-substation"
local TRAIN_BATTERY_INFO_PANEL_NAME = "the-cave-train-battery-info-panel"
local TRAIN_LOCOMOTIVE_POWER_LAYOUT_VERSION = "3.0.40-main-locomotive-only-substation"
local TRAIN_BATTERY_INFO_PANEL_TEXT_VERSION = "3.3.0-plain-text"
local TRAIN_COUPLING_ASSIST_RANGE = 15.5
train_interiors.cave_safe_margin = 50
local TRAIN_SHIELD = {
    prefix = "the-cave-train-shield-upgrade-",
    variant_prefix = "the-cave-train-shield-",
    base_health = 5000,
    health_per_level = 3000,
    max_level = 10,
    repair_per_level = 5,
    repair_delay_ticks = 10 * 60,
    types = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
    base_names = { ["locomotive"] = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true },
}
local WAGON_TYPES = {
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
}


-- Forward declarations for functions used before their definitions.
local enter_wagon
local sync_train_power
local ensure_all_train_power_entities
local cleanup_train_power_for_surface
local auto_couple_nearby_trains
local try_connect


local UTILITY_LANE_DEPTH = 10
train_interiors.cargo_config = {
    storehouse_name = "the-cave-6x6-container",
    green_width = 36,
    green_base_height = 36,
    green_extra_bottom = 0,
    green_height = 36,
}
train_interiors.fluid_config = {
    tank_name = "the-cave-train-fluid-transfer-tank-5x5",
}
local UTILITY_ALLOWED_ENTITY_TYPES = {
    ["pipe"] = true,
    ["pipe-to-ground"] = true,
    ["pump"] = true,
    ["storage-tank"] = true,
    ["electric-pole"] = true,
}
-- Explicit names document and protect the complete requested vanilla/The Cave
-- pole set even though all of them currently share the electric-pole type.
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

local function enabled()
    local startup = settings and settings.startup
    local train_setting = startup and startup["the-cave-train-interiors"]
    local shelter_setting = startup and startup["the-cave-shelter-defense"]
    local train_requested = train_setting
        and (train_setting.value == "enabled" or train_setting.value == true)
    local shelter_requested = shelter_setting
        and (shelter_setting.value == "enabled" or shelter_setting.value == true)
    return train_requested and not shelter_requested
end

function train_interiors.is_enabled()
    return enabled()
end

local function external_immersive_loaded()
    return script and script.active_mods and script.active_mods["immersive_locomotives_fork"] ~= nil
end

local function active()
    return enabled() and not external_immersive_loaded()
end

local function cavetorio_enabled()
    local st = settings and settings.startup and settings.startup["the-cave-cavetorio"]
    return not st or st.value == "enabled" or st.value == true
end

local function state()
    storage.the_cave_train_interiors = storage.the_cave_train_interiors or {}
    local s = storage.the_cave_train_interiors
    s.wagons = s.wagons or {}
    s.doors = s.doors or {}
    s.players = s.players or {}
    s.spawned_forces = s.spawned_forces or {}
    -- Immutable exterior centres of each Force's first starter train. Gameplay
    -- systems that need a map-start reference must never follow the live train.
    s.starter_train_centers = s.starter_train_centers or {}
    s.surfaces = s.surfaces or {}
    s.surface_owners = s.surface_owners or {}
    s.cache_chunks = s.cache_chunks or {}
    s.cache_centers = s.cache_centers or {}
    s.unclaimed_train_parts = s.unclaimed_train_parts or {}
    s.main_train_units = s.main_train_units or {}
    s.main_battery_locomotive_units = s.main_battery_locomotive_units or {}
    s.main_train_capacity_message_tick = s.main_train_capacity_message_tick or {}
    s.selected_fluid_port_render = s.selected_fluid_port_render or {}
    s.selected_cargo_port_render = s.selected_cargo_port_render or {}
    s.selected_garden_port_render = s.selected_garden_port_render or {}
    s.selected_power_substation_render = s.selected_power_substation_render or {}
    s.selected_train_battery_render = s.selected_train_battery_render or {}
    s.map_void_versions = s.map_void_versions or {}
    s.train_power = s.train_power or {}
    s.train_shield_last_damage = s.train_shield_last_damage or {}
    s.train_shield_applied_level = s.train_shield_applied_level or {}
    s.train_shield_pools = s.train_shield_pools or {}
    s.train_layout_anchor_units = s.train_layout_anchor_units or {}
    s.train_shield_suppress_rebuild_until = s.train_shield_suppress_rebuild_until or 0
    s.gardens = s.gardens or {}
    return s
end

local function valid(e)
    return e and e.valid
end

function train_interiors._interior_expansion_level(force)
    if not (force and force.valid and force.technologies) then return 0 end
    local level = 0
    for i = 1, TRAIN_INTERIOR_EXPANSION.max_level do
        local tech = force.technologies[TRAIN_INTERIOR_EXPANSION.prefix .. i]
        if tech and tech.researched then level = i end
    end
    return level
end

function train_interiors._interior_room_dimensions(force)
    local level = math.max(0, math.min(TRAIN_INTERIOR_EXPANSION.max_level, train_interiors._interior_expansion_level(force)))
    local dimensions = TRAIN_INTERIOR_EXPANSION.dimensions[level + 1]
        or TRAIN_INTERIOR_EXPANSION.dimensions[1]
        or { width = TRAIN_INTERIOR_EXPANSION.core_size, height = TRAIN_INTERIOR_EXPANSION.core_size }
    return dimensions.width, dimensions.height
end

function train_interiors._interior_room_size(force)
    return train_interiors._interior_room_dimensions(force)
end

function train_interiors._interior_expansion_tiles(force)
    local width = train_interiors._interior_room_dimensions(force)
    return math.max(0, math.floor((width - TRAIN_INTERIOR_EXPANSION.core_size) * 0.5))
end

function train_interiors._interior_connector_width(force)
    local level = math.max(0, math.min(TRAIN_INTERIOR_EXPANSION.max_level, train_interiors._interior_expansion_level(force)))
    return TRAIN_INTERIOR_EXPANSION.connector_widths[level + 1]
        or TRAIN_INTERIOR_EXPANSION.connector_widths[1]
        or 20
end

function train_interiors._interior_connector_half_width(force)
    return train_interiors._interior_connector_width(force) * 0.5
end

function train_interiors._interior_connector_bounds(force, mid_y)
    local width = train_interiors._interior_connector_width(force)
    local top = math.floor((mid_y or 0) - (width * 0.5))
    return top, top + width
end

function train_interiors._main_train_expansion_level(force)
    if not (force and force.valid and force.technologies) then return 0 end
    local level = 0
    local cfg = train_interiors.main_train_config
    for i = 1, cfg.max_level do
        local tech = force.technologies[cfg.prefix .. i]
        if tech and tech.researched then level = i end
    end
    return level
end

function train_interiors._main_train_capacity(force)
    local cfg = train_interiors.main_train_config
    local level = math.max(0, math.min(cfg.max_level, train_interiors._main_train_expansion_level(force)))
    return math.max(cfg.base_capacity, math.min(cfg.max_capacity, cfg.base_capacity + level))
end

function train_interiors._rolling_stock_count(carriages)
    local count = 0
    for _, carriage in ipairs(carriages or {}) do
        if valid(carriage) and WAGON_TYPES[carriage.type] then count = count + 1 end
    end
    return count
end

function train_interiors._train_contains_main_train(carriages)
    local s = state()
    for _, carriage in ipairs(carriages or {}) do
        if valid(carriage) and carriage.unit_number and s.main_train_units[carriage.unit_number] then return true end
    end
    return false
end

function train_interiors._mark_unclaimed_train_part(entity, source)
    if not (valid(entity) and entity.unit_number and WAGON_TYPES[entity.type]) then return end
    local s = state()
    if s.main_train_units[entity.unit_number] then return end
    s.unclaimed_train_parts[entity.unit_number] = {
        type = entity.type,
        name = entity.name,
        surface_index = entity.surface and entity.surface.valid and entity.surface.index or nil,
        x = entity.position and entity.position.x or 0,
        y = entity.position and entity.position.y or 0,
        source = source or "world",
    }
    pcall(function() entity.minable_flag = false end)
end

function train_interiors._clear_unclaimed_train_part(entity)
    if not (entity and entity.unit_number) then return end
    state().unclaimed_train_parts[entity.unit_number] = nil
end

function train_interiors._announce_main_train_capacity_full(force)
    if not (game and force and force.valid) then return end
    local s = state()
    local key = force.index
    local last = tonumber(s.main_train_capacity_message_tick[key]) or 0
    if game.tick and game.tick - last < 180 then return end
    s.main_train_capacity_message_tick[key] = game.tick or 0
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid and player.force == force then
            player.print("[The Cave] Main Train capacity is full. Research more Main Train Expansion upgrades to add more train parts.")
        end
    end
end

function train_interiors._disconnect_rolling_stock(entity)
    if not valid(entity) then return end
    pcall(function() entity.disconnect_rolling_stock(defines.rail_direction and defines.rail_direction.front or 0) end)
    pcall(function() entity.disconnect_rolling_stock(defines.rail_direction and defines.rail_direction.back or 1) end)
end

function train_interiors._enforce_main_train_capacity(entity, silent)
    if not (valid(entity) and entity.train and entity.train.valid) then return false end
    local carriages = entity.train.carriages or {}
    if not train_interiors._train_contains_main_train(carriages) then return false end
    local capacity = train_interiors._main_train_capacity(entity.force)
    local count = train_interiors._rolling_stock_count(carriages)
    if count <= capacity then return true end
    local s = state()
    for _, carriage in ipairs(carriages) do
        if valid(carriage) and carriage.unit_number and WAGON_TYPES[carriage.type] and not s.main_train_units[carriage.unit_number] then
            train_interiors._mark_unclaimed_train_part(carriage, "capacity-full")
            train_interiors._disconnect_rolling_stock(carriage)
        end
    end
    if not silent then train_interiors._announce_main_train_capacity_full(entity.force) end
    return false
end

function train_interiors._can_register_train_part(entity, silent)
    if not (valid(entity) and entity.unit_number and WAGON_TYPES[entity.type]) then return false, "invalid" end
    local s = state()
    if s.main_train_units[entity.unit_number] then return true end
    if not (entity.train and entity.train.valid and entity.train.carriages) then return false, "not-connected" end
    local carriages = entity.train.carriages or {}
    if not train_interiors._train_contains_main_train(carriages) then return false, "not-main-train" end
    local capacity = train_interiors._main_train_capacity(entity.force)
    local count = train_interiors._rolling_stock_count(carriages)
    if count > capacity then
        train_interiors._enforce_main_train_capacity(entity, silent)
        return false, "capacity-full"
    end
    return true
end

function train_interiors._infer_main_train_units()
    local s = state()
    local has_main = false
    for _ in pairs(s.main_train_units or {}) do has_main = true break end
    if has_main then return end
    local best_by_force = {}
    for _, wagon in pairs(s.wagons or {}) do
        local entity = wagon and wagon.entity
        if valid(entity) and entity.force and entity.force.valid and entity.train and entity.train.valid then
            local force_name = entity.force.name
            local count = 0
            for _, carriage in ipairs(entity.train.carriages or {}) do
                if valid(carriage) and carriage.unit_number and s.wagons[carriage.unit_number] then count = count + 1 end
            end
            local best = best_by_force[force_name]
            if count > 0 and (not best or count > best.count) then
                best_by_force[force_name] = { count = count, carriages = entity.train.carriages }
            end
        end
    end
    for _, best in pairs(best_by_force) do
        for _, carriage in ipairs(best.carriages or {}) do
            if valid(carriage) and carriage.unit_number and s.wagons[carriage.unit_number] then
                s.main_train_units[carriage.unit_number] = true
                s.unclaimed_train_parts[carriage.unit_number] = nil
            end
        end
    end
end

local function get_player_state(player)
    local s = state()
    s.players[player.index] = s.players[player.index] or { zoom = 0.50, map_size = 220 }
    return s.players[player.index]
end

local function is_train_surface(surface)
    return surface and surface.valid and type(surface.name) == "string" and surface.name:sub(1, #SURFACE_PREFIX) == SURFACE_PREFIX
end

function train_interiors.is_train_surface(surface)
    return is_train_surface(surface)
end

local function cleanup_legacy_exit_cars()
    -- 2.1.58 migration: older Train Interior test builds used fake car entities
    -- as exit doors. The hotkey toggle has replaced them, so remove any leftover
    -- cars on hidden train surfaces to free the interior rooms completely.
    if not game then return end
    local s = state()
    s.doors = {}
    for _, wagon in pairs(s.wagons or {}) do
        wagon.doors = {}
    end
    for _, surface in pairs(game.surfaces) do
        if is_train_surface(surface) then
            for _, entity in pairs(surface.find_entities_filtered { name = "car" }) do
                if entity.valid then pcall(function() entity.destroy() end) end
            end
        end
    end
end


local function is_water_tile(surface, position)
    if not (surface and surface.valid and position) then return true end
    local tile = surface.get_tile(position.x, position.y)
    if not (tile and tile.valid) then return true end
    local name = tile.name or ""
    if name == "out-of-map" then return true end
    if name:find("water", 1, true) then return true end
    if name:find("deepwater", 1, true) then return true end
    return false
end

local function safe_land_position(surface, center, radius, entity_name)
    if not (surface and surface.valid and center) then return nil end
    entity_name = entity_name or "character"
    radius = radius or 16
    local candidates = {
        {0, -3}, {0, 3}, {3, 0}, {-3, 0},
        {4, -4}, {-4, -4}, {4, 4}, {-4, 4},
        {0, -6}, {0, 6}, {6, 0}, {-6, 0},
        {8, -4}, {-8, -4}, {8, 4}, {-8, 4},
    }
    for _, off in pairs(candidates) do
        local target = { x = center.x + off[1], y = center.y + off[2] }
        local p = surface.find_non_colliding_position(entity_name, target, 8, 0.5)
        if p and not is_water_tile(surface, p) then return p end
    end
    local p = surface.find_non_colliding_position(entity_name, center, radius, 0.5)
    if p and not is_water_tile(surface, p) then return p end
    return nil
end

function train_interiors._runtime_tile_or_fallback(name, fallback)
    if prototypes and prototypes.tile and name and prototypes.tile[name] then return name end
    if prototypes and prototypes.tile and fallback and prototypes.tile[fallback] then return fallback end
    return "refined-concrete"
end

function train_interiors._fill_rect_tiles(surface, left, top, width, height, tile_name)
    if not (surface and surface.valid) then return end
    local chosen_tile = train_interiors._runtime_tile_or_fallback(tile_name or "black-refined-concrete", "refined-concrete")
    local tiles = {}
    local right = left + width - 1
    local bottom = top + height - 1
    for x = left, right do
        for y = top, bottom do
            tiles[#tiles + 1] = { name = chosen_tile, position = { x = x, y = y } }
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles, true) end
end

function train_interiors._exact_rect_bounds(center, width, height)
    local left = math.floor(center.x - width * 0.5)
    local top = math.floor(center.y - height * 0.5)
    return left, top, left + width, top + height
end

local function clear_area(surface, area)
    if not (surface and surface.valid) then return end
    for _, entity in pairs(surface.find_entities_filtered { area = area }) do
        if entity.valid then
            local t = entity.type
            if t == "tree" or t == "simple-entity" or t == "cliff" or entity.name == "diggy-rock" or entity.name == "diggy-tree" or entity.name == "diggy-rubble" then
                pcall(function() entity.destroy() end)
            end
        end
    end
end

local function fill_land(surface, center, half_x, half_y, tile_name)
    local tiles = {}
    local chosen_tile = train_interiors._runtime_tile_or_fallback(tile_name or "black-refined-concrete", "refined-concrete")
    for x = math.floor(center.x - half_x), math.floor(center.x + half_x) do
        for y = math.floor(center.y - half_y), math.floor(center.y + half_y) do
            tiles[#tiles + 1] = { name = chosen_tile, position = { x = x, y = y } }
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles, true) end
end

local function ensure_train_surface_map_settings(surface)
    if not (surface and surface.valid) then return end
    -- Old test surfaces were created with a tiny fixed map size. They render
    -- fine in normal view after set_tiles(), but normal map view can remain
    -- black outside generated/charted chunks. Keep train-interior surfaces
    -- unbounded and generated around the rooms.
    pcall(function()
        local settings = surface.map_gen_settings
        if settings then
            settings.width = 0
            settings.height = 0
            surface.map_gen_settings = settings
        end
    end)
end

local function create_hidden_surface(name)
    if game.surfaces[name] then
        local existing = game.surfaces[name]
        ensure_train_surface_map_settings(existing)
        return existing
    end
    local surface = game.create_surface(name, {
        water = 0,
        starting_area = 1,
        cliff_settings = { cliff_elevation_interval = 0, cliff_elevation_0 = 0 },
        autoplace_settings = {
            entity = { treat_missing_as_default = false },
            tile = { treat_missing_as_default = false },
            decorative = { treat_missing_as_default = false },
        },
    })
    ensure_train_surface_map_settings(surface)
    surface.no_enemies_mode = true
    surface.freeze_daytime = true
    surface.daytime = 0.1
    surface.always_day = true
    surface.request_to_generate_chunks({0, 0}, 2)
    surface.force_generate_chunk_requests()
    -- Do not hide train interior surfaces from forces. When a player presses M
    -- while standing inside the train, a hidden surface can render as a black map.
    -- The surface is still internal because only this mod teleports players here.
    for _, force in pairs(game.forces) do
        pcall(function() force.set_surface_hidden(surface, false) end)
    end
    return surface
end

local function room_area(offset_x, force)
    offset_x = offset_x or 0
    local width, height = train_interiors._interior_room_dimensions(force)
    local half_width = width * 0.5
    local half_height = height * 0.5
    return {
        left_top = { x = offset_x - half_width, y = -half_height },
        right_bottom = { x = offset_x + half_width, y = half_height },
    }
end

local function area_bounds(area)
    area = area or room_area(0)
    return area.left_top.x, area.right_bottom.x, area.left_top.y, area.right_bottom.y
end

local function area_center(area)
    local left, right, top, bottom = area_bounds(area)
    return { x = (left + right) * 0.5, y = (top + bottom) * 0.5 }
end

function train_interiors._center_core_bounds(area)
    local c = area_center(area)
    local half = TRAIN_INTERIOR_EXPANSION.core_size * 0.5
    return math.floor(c.x - half), math.floor(c.x + half), math.floor(c.y - half), math.floor(c.y + half)
end

function train_interiors._extended_green_core_bounds(area)
    local c = area_center(area)
    local cfg = train_interiors.cargo_config
    local left = math.floor(c.x - (cfg.green_width * 0.5))
    -- Every supported rolling-stock room uses the same centered 36x36 green
    -- area. A Level 0 room is 40x40, leaving two non-green tiles on each side.
    local top = math.floor(c.y - (cfg.green_height * 0.5))
    return left, left + cfg.green_width, top, top + cfg.green_height
end

function train_interiors._cargo_green_core_bounds(area)
    return train_interiors._extended_green_core_bounds(area)
end

function train_interiors._wagon_uses_extended_green_core(wagon)
    if not (wagon and valid(wagon.entity)) then return false end
    local entity_type = wagon.entity.type
    return entity_type == "locomotive"
        or entity_type == "cargo-wagon"
        or entity_type == "fluid-wagon"
        or entity_type == "artillery-wagon"
end

function train_interiors._entry_pad_bounds(area)
    local c = area_center(area)
    return math.floor(c.x - 2), math.floor(c.x + 2), math.floor(c.y - 2), math.floor(c.y + 2)
end

local function generate_surface_area(surface, area, extra)
    if not (surface and surface.valid and area) then return end
    extra = extra or 8
    local left, right, top, bottom = area_bounds(area)
    local center = { x = (left + right) * 0.5, y = (top + bottom) * 0.5 }
    local width = math.abs(right - left) + extra * 2
    local height = math.abs(bottom - top) + extra * 2
    -- request_to_generate_chunks radius is measured in chunks from the center.
    -- The old formula used the full width/height divided by 32, which generated
    -- too many surrounding chunks and made green Nauvis terrain show around train
    -- interiors in map view. Use half-size coverage instead.
    local radius = math.max(1, math.ceil(math.max(width, height) / 64) + 1)
    ensure_train_surface_map_settings(surface)
    pcall(function() surface.request_to_generate_chunks(center, radius) end)
    pcall(function() surface.force_generate_chunk_requests() end)
end

local function tile_or_fallback(name, fallback)
    if prototypes and prototypes.tile and prototypes.tile[name] then return name end
    return fallback or "refined-concrete"
end

local function add_room_tiles(tiles, wagon)
    local left, right, top, bottom = area_bounds(wagon.area)
    local floor_tile = tile_or_fallback("black-refined-concrete", "refined-concrete")
    -- 2.2.53: separate the build core and restricted utility lanes visually.
    -- The old hazard concrete blended the center with the top/bottom lanes.
    local core_tile = tile_or_fallback("green-refined-concrete", tile_or_fallback("green-concrete", floor_tile))
    local entry_tile = tile_or_fallback("refined-concrete", floor_tile)
    local utility_tile = tile_or_fallback("blue-refined-concrete", tile_or_fallback("blue-concrete", floor_tile))
    local cap_tile = utility_tile

    -- Locomotive, Cargo Wagon, Fluid Wagon and Artillery Wagon rooms all use the
    -- same centered 36x36 green area. Research follows the explicit rectangular
    -- Level 0-6 dimensions above. Utility lanes remain exactly ten tiles outside
    -- the current top and bottom edges, so repainting an upgrade converts each
    -- old blue lane to normal floor and creates one new lane at each outer edge.
    for x = left, right - 1 do
        for y = top, bottom - 1 do
            tiles[#tiles + 1] = { name = floor_tile, position = { x = x, y = y } }
        end
        for y = top - UTILITY_LANE_DEPTH, top - 1 do
            tiles[#tiles + 1] = { name = utility_tile, position = { x = x, y = y } }
        end
        for y = bottom, bottom + UTILITY_LANE_DEPTH - 1 do
            tiles[#tiles + 1] = { name = utility_tile, position = { x = x, y = y } }
        end
    end

    -- Fixed center core, with a reserved 4x4 entry landing pad.
    local core_left, core_right, core_top, core_bottom
    if train_interiors._wagon_uses_extended_green_core(wagon) then
        core_left, core_right, core_top, core_bottom = train_interiors._extended_green_core_bounds(wagon.area)
    else
        core_left, core_right, core_top, core_bottom = train_interiors._center_core_bounds(wagon.area)
    end
    for x = core_left, core_right - 1 do
        for y = core_top, core_bottom - 1 do
            tiles[#tiles + 1] = { name = core_tile, position = { x = x, y = y } }
        end
    end

    local pad_left, pad_right, pad_top, pad_bottom = train_interiors._entry_pad_bounds(wagon.area)
    for x = pad_left, pad_right - 1 do
        for y = pad_top, pad_bottom - 1 do
            tiles[#tiles + 1] = { name = entry_tile, position = { x = x, y = y } }
        end
    end

    -- Add simple left/right caps so cargo/fluid interiors no longer look cut off
    -- or bald at the ends. This is tile-only and does not add new sprites.
    for y = top - UTILITY_LANE_DEPTH, bottom + UTILITY_LANE_DEPTH - 1 do
        tiles[#tiles + 1] = { name = cap_tile, position = { x = left, y = y } }
        tiles[#tiles + 1] = { name = cap_tile, position = { x = right - 1, y = y } }
    end

    -- Keep locomotive water fixed inside the 18x18 center core. The 12x4 pond
    -- contains a centered 6x4 dry island, leaving exactly 3x4 water on each
    -- side. In the persistent Main Locomotive, its fixed Substation and
    -- information panel share this island. Secondary rooms keep the same floor
    -- geometry but receive neither fixture. Existing-save expansion tiles are
    -- converted to water only
    -- when no entity already occupies them, so an old Offshore Pump or machine
    -- is never deleted by the migration.
    if wagon.entity and wagon.entity.type == "locomotive" then
        local core_left, core_right, core_top = train_interiors._center_core_bounds(wagon.area)
        local c = area_center(wagon.area)
        local water_width = 12
        local water_depth = 4
        local water_left = math.floor(c.x - (water_width * 0.5))
        local water_right = water_left + water_width - 1
        local water_top = core_top
        local water_bottom = core_top + water_depth - 1
        local island_left = water_left + 3
        local island_right = island_left + 5
        local island_top = water_top
        local island_bottom = water_bottom
        water_left = math.max(core_left, water_left)
        water_right = math.min(core_right - 1, water_right)
        for x = water_left, water_right do
            for y = water_top, water_bottom do
                local is_substation_island = x >= island_left and x <= island_right
                    and y >= island_top and y <= island_bottom
                local current_tile = wagon.surface and wagon.surface.valid and wagon.surface.get_tile(x, y) or nil
                local tile_was_water = current_tile and current_tile.valid
                    and current_tile.name:find("water", 1, true) ~= nil
                local occupied = false
                if (is_substation_island or not tile_was_water) and wagon.surface and wagon.surface.valid then
                    for _, entity in pairs(wagon.surface.find_entities_filtered {
                        area = { { x, y }, { x + 1, y + 1 } },
                    }) do
                        if valid(entity)
                            and entity.type ~= "character"
                            and entity.name ~= "fish"
                            and entity.name ~= TRAIN_LOCOMOTIVE_SUBSTATION_NAME
                            and entity.name ~= TRAIN_GARDEN_SUBSTATION_NAME then
                            occupied = true
                            break
                        end
                    end
                end
                if is_substation_island and occupied and tile_was_water then
                    -- Preserve the supporting water below an existing Offshore
                    -- Pump instead of forcing the full island through it.
                    tiles[#tiles + 1] = { name = current_tile.name, position = { x = x, y = y } }
                elseif not is_substation_island and (tile_was_water or not occupied) then
                    tiles[#tiles + 1] = { name = "water", position = { x = x, y = y } }
                end
            end
        end

        -- The Garden portal is a rendered 2x2 floor overlay owned only by the
        -- persistent Main Locomotive. Keep the tiles below it as normal green
        -- center-core floor. This also repaints the obsolete yellow square in
        -- every secondary locomotive without touching any entity on those tiles.
    end
end

local function paint_room_tiles(wagon)
    if not (wagon and wagon.surface and wagon.surface.valid and wagon.area) then return end
    generate_surface_area(wagon.surface, {
        left_top = { x = wagon.area.left_top.x - 8, y = wagon.area.left_top.y - UTILITY_LANE_DEPTH - 8 },
        right_bottom = { x = wagon.area.right_bottom.x + 8, y = wagon.area.right_bottom.y + UTILITY_LANE_DEPTH + 8 },
    }, 8)
    local tiles = {}
    add_room_tiles(tiles, wagon)
    if #tiles > 0 then wagon.surface.set_tiles(tiles, true) end
end

local function make_surface_visible_for_force(surface, force)
    if not (surface and surface.valid and force and force.valid and is_train_surface(surface)) then return end
    -- set_surface_hidden(true) makes normal map view unreliable/black on these
    -- scripted interior surfaces. Keep it visible to the force while chart/radar
    -- handles what is actually revealed.
    pcall(function() force.set_surface_hidden(surface, false) end)
end

local function ensure_wagon_map_radar(wagon)
    -- 2.1.72: do not place real radar entities anymore. The previous hidden
    -- radar test could show white square artifacts in normal map view, and it
    -- still did not reveal ungenerated train-surface chunks reliably. Map view
    -- is now handled by generated chunks + force.chart(). Clean up any old test
    -- radars that were created by 2.1.71.
    if wagon and valid(wagon.map_radar) then
        pcall(function() wagon.map_radar.destroy() end)
    end
    if wagon then wagon.map_radar = nil end
    if wagon and wagon.surface and wagon.surface.valid then
        local s = state()
        s.map_radar_cleaned = s.map_radar_cleaned or {}
        local surface = wagon.surface
        if s.map_radar_cleaned[surface.index] == surface then return nil end
        for _, radar in pairs(surface.find_entities_filtered { name = HIDDEN_MAP_RADAR_NAME }) do
            if valid(radar) then pcall(function() radar.destroy() end) end
        end
        s.map_radar_cleaned[surface.index] = surface
    end
    return nil
end

local function ensure_all_map_radars()
    for _, wagon in pairs(state().wagons or {}) do
        ensure_wagon_map_radar(wagon)
        if wagon and wagon.surface and wagon.surface.valid and valid(wagon.entity) and wagon.entity.force and wagon.entity.force.valid then
            make_surface_visible_for_force(wagon.surface, wagon.entity.force)
        end
    end
end


local function collect_surface_wagons(surface)
    local wagons = {}
    if not (surface and surface.valid) then return wagons end
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and wagon.surface and wagon.surface.valid and wagon.surface.name == surface.name and wagon.area then
            wagons[#wagons + 1] = wagon
        end
    end
    table.sort(wagons, function(a, b)
        local ai = a.layout_index or 0
        local bi = b.layout_index or 0
        if ai ~= bi then return ai < bi end
        local al = a.area and a.area.left_top and a.area.left_top.x or 0
        local bl = b.area and b.area.left_top and b.area.left_top.x or 0
        return al < bl
    end)
    return wagons
end

-- Return the one persistent Main Locomotive that owns the Train Battery input
-- for this force. The starter locomotive is marked explicitly on creation.
-- Existing saves deterministically adopt the oldest registered locomotive, and
-- coupling a newer locomotive to the front never steals the charging role.
function train_interiors._main_battery_locomotive_wagon(surface)
    if not (surface and surface.valid) then return nil end
    local s = state()
    local candidates = {}
    local force_index = nil
    for _, wagon in ipairs(collect_surface_wagons(surface)) do
        local entity = wagon and wagon.entity
        if valid(entity) and entity.type == "locomotive" and entity.unit_number
            and s.main_train_units[entity.unit_number] then
            candidates[#candidates + 1] = wagon
            force_index = force_index or (entity.force and entity.force.valid and entity.force.index)
        end
    end
    if #candidates == 0 or not force_index then return nil end

    local selected_unit = s.main_battery_locomotive_units[force_index]
    if selected_unit then
        for _, wagon in ipairs(candidates) do
            if wagon.entity.unit_number == selected_unit then return wagon end
        end
    end

    table.sort(candidates, function(a, b)
        return (a.entity.unit_number or math.huge) < (b.entity.unit_number or math.huge)
    end)
    local selected = candidates[1]
    if selected and valid(selected.entity) then
        s.main_battery_locomotive_units[force_index] = selected.entity.unit_number
    end
    return selected
end

function train_interiors._destroy_locomotive_power_labels(wagon)
    if not wagon then return end
    for _, id in pairs(wagon.locomotive_power_label_render_ids or {}) do
        local ok, obj = pcall(function() return rendering.get_object_by_id(id) end)
        if ok and obj then pcall(function() obj.destroy() end) end
    end
    wagon.locomotive_power_label_render_ids = {}
end

function train_interiors._draw_locomotive_power_labels(wagon, is_main)
    -- Compatibility no-op: the label above the Main Locomotive Substation is
    -- now drawn only for the player currently selecting that Substation.
    train_interiors._destroy_locomotive_power_labels(wagon)
end

function train_interiors._setup_train_battery_info_panel(panel)
    if not valid(panel) then return end
    pcall(function() panel.destructible = false end)
    pcall(function() panel.minable_flag = false end)
    pcall(function() panel.operable = false end)
    pcall(function() panel.display_panel_icon = { type = "virtual", name = "signal-info" } end)
    -- Native panel text is a string capped at 500 characters in 2.1. Keep the
    -- exterior range and one-way charging warning before that limit.
    panel.display_panel_text = table.concat({
        "TRAIN BATTERY",
        "Generate power inside; wire the interior grid to the Main Train Battery Substation. It powers machines and the garden, and charges the Train Battery.",
        "Player accumulators remain local storage. Wagon rooms need explicit connections.",
        "OUTSIDE: connect within the Main Locomotive's yellow 10-tile POWER RANGE. The battery powers machines and charges accumulators alongside exterior generators. Outside power cannot charge it.",
        "Only the main locomotive has a fixed substation.",
    }, "\n")
    -- Factorio natively reveals Display Panel information when the panel is
    -- selected. Keep it hidden at all other times to avoid permanent clutter.
    pcall(function() panel.display_panel_always_show = false end)
    pcall(function() panel.display_panel_show_in_chart = false end)
end

function train_interiors._remove_secondary_locomotive_power_fixtures(wagon)
    if not wagon then return end
    local substation = wagon.locomotive_substation
    local panel = wagon.train_battery_info_panel
    local needs_room_scan = wagon.locomotive_power_layout_version ~= TRAIN_LOCOMOTIVE_POWER_LAYOUT_VERSION
        or valid(substation)
        or valid(panel)

    if valid(substation) then pcall(function() substation.destroy() end) end
    wagon.locomotive_substation = nil

    if valid(panel) then pcall(function() panel.destroy() end) end
    wagon.train_battery_info_panel = nil
    wagon.train_battery_info_panel_setup_version = nil

    -- Old saves can contain a valid fixed entity whose LuaEntity reference was
    -- lost from the wagon record. Remove only The Cave's non-craftable managed
    -- prototypes inside this secondary room; player-built power entities and
    -- every other room entity remain untouched.
    -- The version marker makes this a one-time migration scan. Normal 15-tick
    -- power synchronization only clears an unexpected live reference and does
    -- not repeatedly search two entity filters in every secondary room.
    if needs_room_scan and wagon.surface and wagon.surface.valid and wagon.area then
        for _, entity_name in pairs({ TRAIN_LOCOMOTIVE_SUBSTATION_NAME, TRAIN_BATTERY_INFO_PANEL_NAME }) do
            for _, entity in pairs(wagon.surface.find_entities_filtered {
                name = entity_name,
                area = wagon.area,
            }) do
                if valid(entity) then pcall(function() entity.destroy() end) end
            end
        end
    end

    train_interiors._destroy_locomotive_power_labels(wagon)
    wagon.locomotive_power_is_main = false
    wagon.locomotive_power_layout_version = TRAIN_LOCOMOTIVE_POWER_LAYOUT_VERSION
end

function train_interiors._ensure_locomotive_power_fixtures(wagon)
    if not (wagon and wagon.surface and wagon.surface.valid and wagon.area and valid(wagon.entity)) then return end
    if wagon.entity.type ~= "locomotive" then return end
    local surface = wagon.surface
    local force = wagon.entity.force
    if not (force and force.valid) then return end
    -- Resolve ownership force-wide, not only from this surface. A newly found
    -- locomotive must never adopt the Main role merely because its temporary
    -- pre-coupling interior is on a different surface.
    local main_wagon = train_interiors._garden_main_locomotive_wagon(force)
    local is_main = main_wagon and valid(main_wagon.entity)
        and main_wagon.entity.unit_number == wagon.entity.unit_number or false
    if not is_main then
        train_interiors._remove_secondary_locomotive_power_fixtures(wagon)
        return
    end

    local center = area_center(wagon.area)
    local _, _, core_top = train_interiors._center_core_bounds(wagon.area)
    local substation_position = { x = center.x, y = core_top + 2 }
    -- Display panels use an odd 1x1 placement grid, so their stable center is
    -- half a tile. Using an integer here makes Factorio snap the created panel
    -- by 0.5 tiles and the position check would recreate it every 15 ticks.
    local panel_position = { x = center.x + 2.5, y = core_top + 2.5 }

    if wagon.locomotive_power_layout_version == TRAIN_LOCOMOTIVE_POWER_LAYOUT_VERSION
        and wagon.locomotive_power_is_main == true
        and valid(wagon.locomotive_substation)
        and wagon.locomotive_substation.name == TRAIN_LOCOMOTIVE_SUBSTATION_NAME
        and wagon.locomotive_substation.surface == surface
        and wagon.locomotive_substation.force == force
        and math.abs(wagon.locomotive_substation.position.x - substation_position.x) < 0.001
        and math.abs(wagon.locomotive_substation.position.y - substation_position.y) < 0.001
        and valid(wagon.train_battery_info_panel)
        and wagon.train_battery_info_panel.name == TRAIN_BATTERY_INFO_PANEL_NAME
        and wagon.train_battery_info_panel.surface == surface
        and wagon.train_battery_info_panel.force == force
        and math.abs(wagon.train_battery_info_panel.position.x - panel_position.x) < 0.001
        and math.abs(wagon.train_battery_info_panel.position.y - panel_position.y) < 0.001
        and wagon.train_battery_info_panel_setup_version == TRAIN_BATTERY_INFO_PANEL_TEXT_VERSION then
        return
    end

    local substation = wagon.locomotive_substation
    local substation_recreated = false
    if valid(substation) and (substation.name ~= TRAIN_LOCOMOTIVE_SUBSTATION_NAME or substation.surface ~= surface) then
        pcall(function() substation.destroy() end)
        substation = nil
        substation_recreated = true
    end
    if valid(substation) then
        if math.abs(substation.position.x - substation_position.x) > 0.01
            or math.abs(substation.position.y - substation_position.y) > 0.01 then
            pcall(function() substation.teleport(substation_position) end)
        end
    elseif prototypes.entity[TRAIN_LOCOMOTIVE_SUBSTATION_NAME] then
        local ok, created = pcall(function()
            return surface.create_entity {
                name = TRAIN_LOCOMOTIVE_SUBSTATION_NAME,
                position = substation_position,
                force = force,
                create_build_effect_smoke = false,
            }
        end)
        substation = ok and created or nil
        substation_recreated = valid(substation)
    end
    if valid(substation) then
        pcall(function() substation.destructible = false end)
        pcall(function() substation.minable_flag = false end)
        wagon.locomotive_substation = substation
    else
        wagon.locomotive_substation = nil
        return
    end

    local panel = wagon.train_battery_info_panel
    local panel_recreated = false
    if valid(panel) and (panel.name ~= TRAIN_BATTERY_INFO_PANEL_NAME
        or panel.surface ~= surface
        or math.abs(panel.position.x - panel_position.x) > 0.01
        or math.abs(panel.position.y - panel_position.y) > 0.01) then
        pcall(function() panel.destroy() end)
        panel = nil
        wagon.train_battery_info_panel_setup_version = nil
    end
    if not valid(panel) and prototypes.entity[TRAIN_BATTERY_INFO_PANEL_NAME] then
        local can_place = false
        pcall(function()
            can_place = surface.can_place_entity {
                name = TRAIN_BATTERY_INFO_PANEL_NAME,
                position = panel_position,
                force = force,
            }
        end)
        if can_place then
            local ok, created = pcall(function()
                return surface.create_entity {
                    name = TRAIN_BATTERY_INFO_PANEL_NAME,
                    position = panel_position,
                    force = force,
                    create_build_effect_smoke = false,
                }
            end)
            if ok and valid(created) then
                panel = created
                panel_recreated = true
            end
        end
    end
    if valid(panel) then
        if panel_recreated
            or wagon.train_battery_info_panel_setup_version ~= TRAIN_BATTERY_INFO_PANEL_TEXT_VERSION then
            train_interiors._setup_train_battery_info_panel(panel)
            wagon.train_battery_info_panel_setup_version = TRAIN_BATTERY_INFO_PANEL_TEXT_VERSION
        end
        wagon.train_battery_info_panel = panel
    else
        wagon.train_battery_info_panel = nil
        wagon.train_battery_info_panel_setup_version = nil
    end

    if wagon.locomotive_power_layout_version ~= TRAIN_LOCOMOTIVE_POWER_LAYOUT_VERSION
        or wagon.locomotive_power_is_main ~= is_main
        or substation_recreated then
        train_interiors._destroy_locomotive_power_labels(wagon)
    end
    wagon.locomotive_power_is_main = is_main
    wagon.locomotive_power_layout_version = TRAIN_LOCOMOTIVE_POWER_LAYOUT_VERSION
end

function train_interiors._ensure_all_locomotive_power_fixtures(surface)
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and (not surface or wagon.surface == surface) then
            train_interiors._ensure_locomotive_power_fixtures(wagon)
        end
    end
end

local function train_surface_bounds_from_wagons(wagons)
    local min_x, min_y, max_x, max_y
    for _, wagon in pairs(wagons or {}) do
        if wagon and wagon.area then
            local left, right, top, bottom = area_bounds(wagon.area)
            local a_left = left - 10
            local a_right = right + 10
            local a_top = top - UTILITY_LANE_DEPTH - 3 - 10
            local a_bottom = bottom + UTILITY_LANE_DEPTH + 10
            min_x = min_x and math.min(min_x, a_left) or a_left
            max_x = max_x and math.max(max_x, a_right) or a_right
            min_y = min_y and math.min(min_y, a_top) or a_top
            max_y = max_y and math.max(max_y, a_bottom) or a_bottom
        end
    end
    return min_x, min_y, max_x, max_y
end

local function tile_inside_wagon_floor(wagon, x, y)
    if not (wagon and wagon.area) then return false end
    local left, right, top, bottom = area_bounds(wagon.area)
    return x >= left and x < right and y >= top - UTILITY_LANE_DEPTH and y < bottom + UTILITY_LANE_DEPTH
end

local function tile_inside_train_connector(wagons, x, y, connector_width, include_utility_lanes)
    local extra = include_utility_lanes and UTILITY_LANE_DEPTH or 0
    for i = 1, #wagons - 1 do
        local left_wagon = wagons[i]
        local right_wagon = wagons[i + 1]
        if left_wagon and right_wagon and left_wagon.area and right_wagon.area then
            local _, left_right, top, bottom = area_bounds(left_wagon.area)
            local right_left = right_wagon.area.left_top.x
            local mid_y = math.floor((top + bottom) * 0.5)
            local connector_top = math.floor(mid_y - (connector_width * 0.5))
            local connector_bottom = connector_top + connector_width
            if x >= left_right and x < right_left
                and y >= connector_top - extra
                and y < connector_bottom + extra then
                return true
            end
        end
    end
    return false
end

local function ensure_train_map_void(surface)
    if not (surface and surface.valid and is_train_surface(surface)) then return end
    local wagons = collect_surface_wagons(surface)
    if #wagons == 0 then return end

    local min_x, min_y, max_x, max_y = train_surface_bounds_from_wagons(wagons)
    if not min_x then return end

    local connector_force = nil
    local signature_parts = { tostring(MAP_VIEW_VOID_VERSION), tostring(#wagons) }
    for _, wagon in pairs(wagons) do
        if wagon and wagon.area then
            local left, right, top, bottom = area_bounds(wagon.area)
            signature_parts[#signature_parts + 1] = table.concat({ tostring(left), tostring(right), tostring(top), tostring(bottom) }, ",")
            if not connector_force and valid(wagon.entity) then connector_force = wagon.entity.force end
        end
    end
    local signature = table.concat(signature_parts, "|")
    local s = state()
    local key = surface.name
    if s.map_void_versions[key] == signature then return end

    -- Chunks generated for map view use normal Nauvis grass by default. Paint a
    -- chunk-aligned black void around the whole train, but keep the rooms,
    -- utility lanes and belt-friendly connectors intact. This removes the green
    -- terrain halo without rebuilding or touching player-built machines inside.
    local void_tile = tile_or_fallback("out-of-map", "out-of-map")
    local pad = 96
    local left = math.floor((min_x - pad) / 32) * 32
    local right = math.ceil((max_x + pad) / 32) * 32
    local top = math.floor((min_y - pad) / 32) * 32
    local bottom = math.ceil((max_y + pad) / 32) * 32
    -- Connector width is identical for every wagon on this force-owned train
    -- surface. Resolve the research level once for the whole pass; doing it from
    -- tile_inside_train_connector multiplied the technology lookup by every
    -- scanned tile and every connector, causing long main-thread freezes when an
    -- Interior Expansion research changed the room/map-void signature.
    local connector_width = train_interiors._interior_connector_width(connector_force)

    local tiles = {}
    local function flush_tiles()
        if #tiles > 0 then
            surface.set_tiles(tiles, true)
            tiles = {}
        end
    end

    for x = left, right - 1 do
        for y = top, bottom - 1 do
            local keep = false
            for _, wagon in pairs(wagons) do
                if tile_inside_wagon_floor(wagon, x, y) then
                    keep = true
                    break
                end
            end
            if not keep and tile_inside_train_connector(wagons, x, y, connector_width, true) then keep = true end
            if not keep then
                tiles[#tiles + 1] = { name = void_tile, position = { x = x, y = y } }
                if #tiles >= 20000 then flush_tiles() end
            end
        end
    end
    flush_tiles()
    s.map_void_versions[key] = signature
end

local function chart_train_surface(surface, force)
    -- Train interior surfaces are generated by script. Normal map view only works
    -- reliably after chunks are generated and charted for the player's force, so
    -- do both instead of using real radar entities.
    if not (surface and surface.valid and force and force.valid and is_train_surface(surface)) then return end
    make_surface_visible_for_force(surface, force)

    local min_x, min_y, max_x, max_y
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and wagon.surface and wagon.surface.valid and wagon.surface.name == surface.name and wagon.area then
            local left, right, top, bottom = area_bounds(wagon.area)
            local a_left = left - 10
            local a_right = right + 10
            local a_top = top - UTILITY_LANE_DEPTH - 10
            local a_bottom = bottom + UTILITY_LANE_DEPTH + 10
            generate_surface_area(surface, { left_top = { x = a_left, y = a_top }, right_bottom = { x = a_right, y = a_bottom } }, 10)
            min_x = min_x and math.min(min_x, a_left) or a_left
            max_x = max_x and math.max(max_x, a_right) or a_right
            min_y = min_y and math.min(min_y, a_top) or a_top
            max_y = max_y and math.max(max_y, a_bottom) or a_bottom
        end
    end

    if not min_x then return end
    ensure_train_map_void(surface)
    pcall(function()
        force.chart(surface, {
            left_top = { x = math.floor(min_x), y = math.floor(min_y) },
            right_bottom = { x = math.ceil(max_x), y = math.ceil(max_y) },
        })
    end)
end

local function chart_wagon_interior(wagon, force)
    if wagon and wagon.surface and wagon.surface.valid and force and force.valid then
        chart_train_surface(wagon.surface, force)
    end
end

local function chart_all_train_interiors()
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and wagon.surface and wagon.surface.valid and valid(wagon.entity) and wagon.entity.force and wagon.entity.force.valid then
            chart_wagon_interior(wagon, wagon.entity.force)
        end
    end
end

local function repaint_all_train_rooms()
    local s = state()
    for _, wagon in pairs(s.wagons or {}) do
        if wagon and wagon.surface and wagon.surface.valid and wagon.area then
            paint_room_tiles(wagon)
            train_interiors._ensure_locomotive_power_fixtures(wagon)
        end
    end
end

local function position_in_utility_lane(wagon, position)
    if not (wagon and wagon.area and position) then return false end
    local left, right, top, bottom = area_bounds(wagon.area)
    local x, y = position.x, position.y
    if x < left or x >= right then return false end
    return (y >= top - UTILITY_LANE_DEPTH and y < top)
        or (y >= bottom and y < bottom + UTILITY_LANE_DEPTH)
end

local function find_utility_lane_wagon(surface, position)
    if not (surface and surface.valid and is_train_surface(surface) and position) then return nil end
    local s = state()
    for _, wagon in pairs(s.wagons or {}) do
        if wagon and wagon.surface == surface and position_in_utility_lane(wagon, position) then
            return wagon
        end
    end

    -- Connector utility lanes sit immediately outside the current black floor.
    -- Resolve the force once, then test the ten blue rows above and below each
    -- ordered wagon connection.
    local wagons = collect_surface_wagons(surface)
    local connector_force = nil
    for _, wagon in ipairs(wagons) do
        if valid(wagon.entity) and wagon.entity.force and wagon.entity.force.valid then
            connector_force = wagon.entity.force
            break
        end
    end
    local connector_width = train_interiors._interior_connector_width(connector_force)
    local x, y = position.x, position.y
    for i = 1, #wagons - 1 do
        local left_wagon = wagons[i]
        local right_wagon = wagons[i + 1]
        if left_wagon and right_wagon and left_wagon.area and right_wagon.area then
            local _, left_right, top, bottom = area_bounds(left_wagon.area)
            local right_left = right_wagon.area.left_top.x
            local mid_y = math.floor((top + bottom) * 0.5)
            local connector_top = math.floor(mid_y - (connector_width * 0.5))
            local connector_bottom = connector_top + connector_width
            local in_top_lane = y >= connector_top - UTILITY_LANE_DEPTH
                and y < connector_top
            local in_bottom_lane = y >= connector_bottom
                and y < connector_bottom + UTILITY_LANE_DEPTH
            if x >= left_right and x < right_left and (in_top_lane or in_bottom_lane) then
                return left_wagon
            end
        end
    end
    return nil
end

function train_interiors._boxes_overlap(a, b)
    if not (a and b and a.left_top and a.right_bottom and b.left_top and b.right_bottom) then return false end
    return a.left_top.x < b.right_bottom.x and a.right_bottom.x > b.left_top.x
        and a.left_top.y < b.right_bottom.y and a.right_bottom.y > b.left_top.y
end

function train_interiors._entry_pad_area(wagon)
    if not (wagon and wagon.area) then return nil end
    local left, right, top, bottom = train_interiors._entry_pad_bounds(wagon.area)
    return { left_top = { x = left, y = top }, right_bottom = { x = right, y = bottom } }
end

function train_interiors._find_entry_pad_wagon_for_entity(entity)
    if not (valid(entity) and entity.surface and entity.surface.valid and is_train_surface(entity.surface)) then return nil end
    local box = entity.bounding_box
    if not box then
        local p = entity.position
        box = { left_top = { x = p.x - 0.1, y = p.y - 0.1 }, right_bottom = { x = p.x + 0.1, y = p.y + 0.1 } }
    end
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and wagon.surface == entity.surface then
            local pad = train_interiors._entry_pad_area(wagon)
            if train_interiors._boxes_overlap(box, pad) then return wagon end
        end
    end
    return nil
end

function train_interiors._entity_overlaps_garden_landing_pad(entity)
    if not (valid(entity) and entity.surface and entity.surface.valid
        and train_interiors._is_garden_surface
        and train_interiors._is_garden_surface(entity.surface)
        and train_interiors._garden_landing_pad_bounds) then
        return false
    end
    local box = entity.bounding_box
    if not box then
        local p = entity.position
        box = { left_top = { x = p.x - 0.1, y = p.y - 0.1 }, right_bottom = { x = p.x + 0.1, y = p.y + 0.1 } }
    end
    local left, right, top, bottom = train_interiors._garden_landing_pad_bounds()
    return train_interiors._boxes_overlap(box, {
        left_top = { x = left, y = top },
        right_bottom = { x = right, y = bottom },
    })
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

local function refund_or_spill_built_entity(event, entity)
    if train_interiors.portable_cave_accumulators.refund_placement(event) then return end
    local item_name = entity and entity.name
    if not (item_name and prototypes and prototypes.item and prototypes.item[item_name]) then
        return
    end
    local count = 1
    local player = event and event.player_index and game.get_player(event.player_index) or nil
    if player and player.valid then
        local inserted = player.insert { name = item_name, count = count }
        if inserted < count and entity.surface and entity.surface.valid then
            entity.surface.spill_item_stack { position = entity.position, stack = { name = item_name, count = count - inserted }, force = entity.force, allow_belts = false }
        end
    elseif entity.surface and entity.surface.valid then
        entity.surface.spill_item_stack { position = entity.position, stack = { name = item_name, count = count }, force = entity.force, allow_belts = false }
    end
end

local function reject_invalid_utility_lane_build(event, entity)
    if not (valid(entity) and entity.surface and entity.surface.valid) then return false end
    if not is_train_surface(entity.surface) then return false end

    local wagon = find_utility_lane_wagon(entity.surface, entity.position)
    if not wagon then return false end
    if allowed_on_utility_lane(entity) then return false end

    local entity_name, entity_type = utility_lane_entity_identity(entity)
    local blocked_offshore_pump = UTILITY_BLOCKED_ENTITY_NAMES[entity_name] or UTILITY_BLOCKED_ENTITY_NAMES[entity_type]
    local player = event and event.player_index and game.get_player(event.player_index) or nil
    if player and player.valid then
        if blocked_offshore_pump then
            player.print("[The Cave] Offshore pumps are not allowed on train utility lanes. Place them directly beside the interior water instead.")
        else
            player.print("[The Cave] This train utility lane only allows pipes, underground pipes, pumps, storage tanks and electric poles.")
        end
    end
    refund_or_spill_built_entity(event, entity)
    pcall(function() entity.destroy() end)
    return true
end

function train_interiors._reject_reserved_entry_pad_build(event, entity)
    local garden_landing = train_interiors._entity_overlaps_garden_landing_pad(entity)
    if not garden_landing and not train_interiors._find_entry_pad_wagon_for_entity(entity) then return false end
    local player = event and event.player_index and game.get_player(event.player_index) or nil
    if player and player.valid then
        if garden_landing then
            player.print({ "the-cave-train-garden.landing-pad-must-stay-clear" })
        else
            player.print("[The Cave] The center 4x4 train entry pad must stay clear.")
        end
    end
    refund_or_spill_built_entity(event, entity)
    pcall(function() entity.destroy() end)
    return true
end

function train_interiors._reject_garden_portal_build(event, entity)
    if not (train_interiors._find_garden_portal_for_entity and train_interiors._find_garden_portal_for_entity(entity)) then return false end
    local player = event and event.player_index and game.get_player(event.player_index) or nil
    if player and player.valid then
        player.print({ "the-cave-train-garden.portal-must-stay-clear" })
    end
    refund_or_spill_built_entity(event, entity)
    pcall(function() entity.destroy() end)
    return true
end

local CARGO_PORT_LAYOUT_VERSION = 3056
local FLUID_PORT_LAYOUT_VERSION = 3056
local ITEM_TRANSFER_SNAPSHOT_VERSION = 2
train_interiors.ARTILLERY_EMPTY_ROOM_VERSION = 3038
local FLUID_TRANSFER_PER_SYNC = 5000
local FLUID_TRANSFER_SNAPSHOT_VERSION = 2

local function is_cargo_transfer_container(entity)
    return valid(entity)
        and (entity.name == train_interiors.cargo_config.storehouse_name or entity.name == "steel-chest")
end

local function cargo_storehouse_definitions(wagon)
    local center = area_center(wagon.area)
    return {
        -- Keep the established left Export / right Import roles and place the
        -- complete 6x6 footprints at the lower corners of the 36x36 green area.
        { position = { x = center.x - 14, y = center.y + 14 }, role = "export" },
        { position = { x = center.x + 14, y = center.y + 14 }, role = "import" },
    }
end

function train_interiors._transfer_entity_role(wagon, entity)
    if not valid(entity) then return nil end
    if wagon.transfer_roles and entity.unit_number and wagon.transfer_roles[entity.unit_number] then
        return wagon.transfer_roles[entity.unit_number]
    end
    if wagon.area and entity.position then
        return (entity.position.x >= area_center(wagon.area).x) and "import" or "export"
    end
    return nil
end

function train_interiors._transfer_position_matches(entity, position)
    return valid(entity) and position
        and math.abs(entity.position.x - position.x) <= 0.01
        and math.abs(entity.position.y - position.y) <= 0.01
end

-- Reposition the already-final two-entity layout in place. Teleporting preserves
-- every item/fluid stack and its metadata. If either destination is blocked,
-- roll back the first move and retain the old live layout unchanged.
function train_interiors._try_reposition_fixed_transfer_pair(wagon, definitions, expected_name, version_field, version)
    if not (wagon and wagon.surface and wagon.surface.valid and wagon.area and valid(wagon.entity)) then return false end

    local entities = {}
    local count = 0
    for _, entity in pairs(wagon.transfer_entities or {}) do
        if valid(entity) and entity.name == expected_name then
            local role = train_interiors._transfer_entity_role(wagon, entity)
            if not role or entities[role] then return false end
            entities[role] = entity
            count = count + 1
        end
    end
    if count ~= 2 or not (entities.export and entities.import) then return false end

    local targets = {}
    for _, definition in ipairs(definitions or {}) do targets[definition.role] = definition.position end
    if not (targets.export and targets.import) then return false end

    local originals = {
        export = { x = entities.export.position.x, y = entities.export.position.y },
        import = { x = entities.import.position.x, y = entities.import.position.y },
    }
    local moved = {}
    for _, role in ipairs({ "export", "import" }) do
        local entity = entities[role]
        if not train_interiors._transfer_position_matches(entity, targets[role]) then
            local ok, teleported = pcall(function() return entity.teleport(targets[role]) end)
            if not ok or teleported == false or not train_interiors._transfer_position_matches(entity, targets[role]) then
                for i = #moved, 1, -1 do
                    local rollback_role = moved[i]
                    pcall(function() entities[rollback_role].teleport(originals[rollback_role]) end)
                end
                return false
            end
            moved[#moved + 1] = role
        end
    end

    wagon.transfer_entities = { entities.export, entities.import }
    wagon.transfer_roles = {}
    if entities.export.unit_number then wagon.transfer_roles[entities.export.unit_number] = "export" end
    if entities.import.unit_number then wagon.transfer_roles[entities.import.unit_number] = "import" end
    wagon[version_field] = version
    return true
end

local function cargo_storehouse_positions_available(surface, wagon)
    if not (surface and surface.valid and wagon and valid(wagon.entity)) then return false end
    for _, definition in ipairs(cargo_storehouse_definitions(wagon)) do
        local ok, available = pcall(function()
            return surface.can_place_entity {
                name = train_interiors.cargo_config.storehouse_name,
                position = definition.position,
                force = wagon.entity.force,
            }
        end)
        if not ok or not available then return false end
    end
    return true
end

local function create_cargo_storehouses(surface, wagon)
    wagon.transfer_entities = {}
    wagon.transfer_roles = {}
    for _, definition in ipairs(cargo_storehouse_definitions(wagon)) do
        local storehouse = surface.create_entity {
            name = train_interiors.cargo_config.storehouse_name,
            position = definition.position,
            force = wagon.entity.force,
            create_build_effect_smoke = false,
        }
        if storehouse then
            storehouse.destructible = false
            storehouse.minable_flag = false
            storehouse.operable = true
            wagon.transfer_entities[#wagon.transfer_entities + 1] = storehouse
            wagon.transfer_roles[storehouse.unit_number or #wagon.transfer_entities] = definition.role
        end
    end
    wagon.cargo_port_layout_version = CARGO_PORT_LAYOUT_VERSION
    wagon.item_transfer_snapshot = nil
end


local function move_inventory_contents_preserving(source, destination)
    if not (source and source.valid and destination and destination.valid) then return end
    if source.is_empty() then return end
    for slot = 1, #source do
        local stack = source[slot]
        if stack and stack.valid_for_read then
            local count = stack.count
            local inserted = 0
            local ok = pcall(function() inserted = destination.insert(stack) end)
            if not ok then
                local definition = train_interiors._item_stack_definition(stack)
                if definition then inserted = destination.insert(definition) end
            end
            if inserted >= count then
                stack.clear()
            elseif inserted > 0 then
                stack.count = count - inserted
            end
        end
    end
end

local function migrate_cargo_port_layout()
    local s = state()
    for _, wagon in pairs(s.wagons or {}) do
        if valid(wagon.entity)
            and wagon.surface and wagon.surface.valid
            and wagon.area
            and wagon.entity.type == "cargo-wagon"
            and wagon.cargo_port_layout_version ~= CARGO_PORT_LAYOUT_VERSION then

            local repositioned = train_interiors._try_reposition_fixed_transfer_pair(
                wagon,
                cargo_storehouse_definitions(wagon),
                train_interiors.cargo_config.storehouse_name,
                "cargo_port_layout_version",
                CARGO_PORT_LAYOUT_VERSION
            )

            if not repositioned and cargo_storehouse_positions_available(wagon.surface, wagon) then

                local center_x = area_center(wagon.area).x
                local existing_containers = {}
                local existing_roles = {}

                for _, container in pairs(wagon.transfer_entities or {}) do
                    if is_cargo_transfer_container(container) then
                        existing_containers[#existing_containers + 1] = container
                        local role = nil
                        if wagon.transfer_roles and container.unit_number then
                            role = wagon.transfer_roles[container.unit_number]
                        end
                        if not role then
                            role = (container.position.x >= center_x) and "import" or "export"
                        end
                        existing_roles[container.unit_number or container] = role
                    end
                end

                -- Create both final Storehouses while every legacy chest still exists.
                -- Only emptied legacy containers are removed, so a capacity or API
                -- failure cannot silently delete item stacks or their quality data.
                create_cargo_storehouses(wagon.surface, wagon)

                local destination_inventories = {}
                for _, container in pairs(wagon.transfer_entities or {}) do
                    if valid(container) and container.name == train_interiors.cargo_config.storehouse_name then
                        local inv = container.get_inventory(defines.inventory.chest)
                        local role = wagon.transfer_roles and container.unit_number and wagon.transfer_roles[container.unit_number]
                        if role and inv and inv.valid then destination_inventories[role] = inv end
                    end
                end

                for _, container in ipairs(existing_containers) do
                    if valid(container) then
                        local role = existing_roles[container.unit_number or container]
                        local source = container.get_inventory(defines.inventory.chest)
                        move_inventory_contents_preserving(source, destination_inventories[role])
                        if source and source.valid and source.is_empty() then
                            pcall(function() container.destroy() end)
                        else
                            -- The two Storehouses normally have more capacity than all
                            -- twelve legacy chests per direction. Retain any exceptional
                            -- remainder as a live transfer container instead of deleting it.
                            wagon.transfer_entities[#wagon.transfer_entities + 1] = container
                            if container.unit_number and role then wagon.transfer_roles[container.unit_number] = role end
                        end
                    end
                end
                wagon.item_transfer_snapshot = nil
            end
        end
    end
end

function train_interiors._is_mod_owned_transfer_chest(entity)
    if not (valid(entity) and entity.name == "steel-chest") then return false end
    local minable_ok, minable_value = pcall(function() return entity.minable_flag end)
    local destructible_ok, destructible_value = pcall(function() return entity.destructible end)
    if minable_ok and minable_value == false then return true end
    if destructible_ok and destructible_value == false then return true end
    return false
end

function train_interiors._item_stack_definition(stack)
    if not (stack and stack.valid_for_read) then return nil end
    local definition = { name = stack.name, count = stack.count }
    local ok, quality = pcall(function() return stack.quality end)
    if ok and quality then definition.quality = quality.name or quality end
    return definition
end

-- Artillery interiors are deliberately plain factory rooms. Older builds
-- treated Artillery Wagons as Cargo Wagons and created 24 transfer chests even
-- though an artillery inventory cannot participate in the Cargo transfer
-- system. Remove only those non-minable mod-owned chests. Any manually stored
-- items are spilled onto the same interior floor before the chest is removed,
-- so updating an existing save cannot silently delete player property.
function train_interiors._migrate_artillery_empty_rooms()
    local s = state()
    for _, wagon in pairs(s.wagons or {}) do
        if valid(wagon.entity)
            and wagon.entity.type == "artillery-wagon"
            and wagon.surface and wagon.surface.valid
            and wagon.area then

            local chests = {}
            local seen = {}
            for _, chest in pairs(wagon.transfer_entities or {}) do
                if train_interiors._is_mod_owned_transfer_chest(chest) and not seen[chest.unit_number or chest] then
                    seen[chest.unit_number or chest] = true
                    chests[#chests + 1] = chest
                end
            end
            for _, chest in pairs(wagon.surface.find_entities_filtered {
                area = wagon.area,
                name = "steel-chest",
            }) do
                if train_interiors._is_mod_owned_transfer_chest(chest) and not seen[chest.unit_number or chest] then
                    seen[chest.unit_number or chest] = true
                    chests[#chests + 1] = chest
                end
            end

            local all_removed = true
            for _, chest in pairs(chests) do
                if valid(chest) then
                    local inventory = chest.get_inventory(defines.inventory.chest)
                    local contents_preserved = true
                    if inventory and inventory.valid then
                        for i = 1, #inventory do
                            local stack = inventory[i]
                            local definition = train_interiors._item_stack_definition(stack)
                            if definition then
                                local ok, spilled = pcall(function()
                                    return wagon.surface.spill_item_stack {
                                        position = chest.position,
                                        stack = definition,
                                        enable_looted = true,
                                        force = wagon.entity.force,
                                        allow_belts = false,
                                    }
                                end)
                                if ok and type(spilled) == "table" and #spilled > 0 then stack.clear()
                                else contents_preserved = false end
                            end
                        end
                    end
                    if contents_preserved then
                        local ok, destroyed = pcall(function() return chest.destroy() end)
                        if not ok or destroyed == false or valid(chest) then all_removed = false end
                    else
                        all_removed = false
                    end
                end
            end

            if all_removed then
                wagon.transfer_entities = {}
                wagon.transfer_roles = {}
                wagon.item_transfer_snapshot = nil
                wagon.cargo_port_layout_version = nil
                wagon.artillery_empty_room_version = train_interiors.ARTILLERY_EMPTY_ROOM_VERSION
            end
        end
    end
end

local function is_mod_owned_storage_tank(entity)
    if not train_interiors._is_fluid_transfer_tank(entity) then return false end
    local minable_ok, minable_value = pcall(function() return entity.minable_flag end)
    local destructible_ok, destructible_value = pcall(function() return entity.destructible end)
    if minable_ok and minable_value == false then return true end
    if destructible_ok and destructible_value == false then return true end
    return false
end

function train_interiors._is_fluid_transfer_tank(entity)
    return valid(entity)
        and (entity.name == "storage-tank" or entity.name == train_interiors.fluid_config.tank_name)
end

function train_interiors._fluid_tank_definitions(wagon)
    local center = area_center(wagon.area)
    return {
        -- The complete 5x5 footprints remain inside the shared 36x36 green area.
        { position = { x = center.x - 14, y = center.y + 14 }, role = "export" },
        { position = { x = center.x + 13, y = center.y + 14 }, role = "import" },
    }
end

function train_interiors._fluid_tank_positions_available(surface, wagon)
    if not (surface and surface.valid and wagon and valid(wagon.entity)) then return false end
    for _, definition in ipairs(train_interiors._fluid_tank_definitions(wagon)) do
        local ok, available = pcall(function()
            return surface.can_place_entity {
                name = train_interiors.fluid_config.tank_name,
                position = definition.position,
                force = wagon.entity.force,
            }
        end)
        if not ok or not available then return false end
    end
    return true
end

local function create_fluid_tanks(surface, wagon)
    -- Fluid wagon ports mirror the cargo port direction rule:
    --   right 5x5 tank = import from the real outside fluid wagon
    --   left  5x5 tank = export back into the real outside fluid wagon
    -- Both tanks sit in the lower corners of the fixed 36x36 green transfer area.
    local definitions = train_interiors._fluid_tank_definitions(wagon)

    -- Some experimental saves can contain old mod-owned tanks that are no longer
    -- referenced by wagon.transfer_entities. Remove only non-minable/non-destructible
    -- transfer tanks in this fluid-wagon room, so player-built tanks are not touched.
    for _, entity in pairs(surface.find_entities_filtered {
        area = wagon.area,
        name = { "storage-tank", train_interiors.fluid_config.tank_name },
    }) do
        if is_mod_owned_storage_tank(entity) then
            pcall(function() entity.destroy() end)
        end
    end

    wagon.transfer_entities = {}
    wagon.transfer_roles = {}
    for _, definition in ipairs(definitions) do
        local tank = surface.create_entity {
            name = train_interiors.fluid_config.tank_name,
            position = definition.position,
            force = wagon.entity.force,
            create_build_effect_smoke = false,
        }
        if tank then
            tank.destructible = false
            tank.minable_flag = false
            tank.operable = true
            wagon.transfer_entities[#wagon.transfer_entities + 1] = tank
            wagon.transfer_roles[tank.unit_number or #wagon.transfer_entities] = definition.role
        end
    end
    wagon.fluid_port_layout_version = (#wagon.transfer_entities == 2) and FLUID_PORT_LAYOUT_VERSION or nil
    wagon.fluid_transfer_snapshot = nil
end

local function destroy_interior_entities(wagon)
    local s = state()
    for _, door in pairs(wagon.doors or {}) do
        if valid(door) then
            s.doors[door.unit_number] = nil
            pcall(function() door.destroy() end)
        end
    end
    for _, entity in pairs(wagon.transfer_entities or {}) do
        if valid(entity) then pcall(function() entity.destroy() end) end
    end
    if valid(wagon.map_radar) then
        pcall(function() wagon.map_radar.destroy() end)
    end
    wagon.map_radar = nil
    wagon.doors = {}
    wagon.transfer_entities = {}
    wagon.transfer_roles = {}
    wagon.item_transfer_snapshot = nil
    wagon.fluid_transfer_snapshot = nil
    wagon.cargo_port_layout_version = nil
    wagon.fluid_port_layout_version = nil
end

local function build_room(wagon)
    local surface = wagon.surface
    local left, right, top, bottom = area_bounds(wagon.area)
    paint_room_tiles(wagon)

    if wagon.entity.type == "locomotive" and prototypes.entity["fish"] then
        local cx = area_center(wagon.area).x
        for x = math.floor(cx - 6), math.floor(cx + 5), 3 do
            surface.create_entity { name = "fish", position = { x = x, y = top + 11 } }
        end
    end

    if wagon.entity.type == "cargo-wagon" then
        create_cargo_storehouses(surface, wagon)
    elseif wagon.entity.type == "fluid-wagon" then
        create_fluid_tanks(surface, wagon)
    end

    train_interiors._ensure_locomotive_power_fixtures(wagon)
    ensure_wagon_map_radar(wagon)
end

local function build_connector(surface, left_area, right_area, force, preserve_existing)
    local _, left_right, top, bottom = area_bounds(left_area)
    local right_left = right_area.left_top.x
    local mid_y = math.floor((top + bottom) * 0.5)
    local connector_top, connector_bottom = train_interiors._interior_connector_bounds(force, mid_y)
    local floor_tile = tile_or_fallback("black-refined-concrete", "refined-concrete")
    local utility_tile = tile_or_fallback("blue-refined-concrete", tile_or_fallback("blue-concrete", floor_tile))
    local tiles = {}
    for x = left_right, right_left - 1 do
        for y = connector_top, connector_bottom - 1 do
            -- Existing train interiors are expanded additively. Keep every old
            -- connector tile (including player flooring) untouched and convert
            -- only the surrounding void into new floor. A genuinely new wagon
            -- connection still receives its complete connector for the first time.
            local tile = preserve_existing and surface.get_tile(x, y) or nil
            local old_managed_lane = tile and tile.valid
                and (tile.name == "blue-refined-concrete" or tile.name == "blue-concrete")
            if not preserve_existing or (tile and tile.valid and tile.name == "out-of-map") or old_managed_lane then
                tiles[#tiles + 1] = { name = floor_tile, position = { x = x, y = y } }
            end
        end

        local top_lane_first = connector_top - UTILITY_LANE_DEPTH
        local top_lane_last = connector_top - 1
        local bottom_lane_first = connector_bottom
        local bottom_lane_last = connector_bottom + UTILITY_LANE_DEPTH - 1
        for y = top_lane_first, top_lane_last do
            local tile = preserve_existing and surface.get_tile(x, y) or nil
            if not preserve_existing or (tile and tile.valid and tile.name == "out-of-map") then
                tiles[#tiles + 1] = { name = utility_tile, position = { x = x, y = y } }
            end
        end
        for y = bottom_lane_first, bottom_lane_last do
            local tile = preserve_existing and surface.get_tile(x, y) or nil
            if not preserve_existing or (tile and tile.valid and tile.name == "out-of-map") then
                tiles[#tiles + 1] = { name = utility_tile, position = { x = x, y = y } }
            end
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles, true) end
end

local function clear_train_surface_area(surface, count)
    local max_spacing = math.max(INTERIOR_WAGON_SPACING, 88) -- 88 was used by older test layouts.
    local area = {
        left_top = { x = -60, y = -60 },
        right_bottom = { x = ((count - 1) * max_spacing) + 60, y = 60 },
    }
    for _, entity in pairs(surface.find_entities_filtered { area = area }) do
        if valid(entity) and entity.type ~= "character" and entity.name ~= "character" then
            pcall(function() entity.destroy() end)
        end
    end

    -- Clear old test connector floors as well as entities, otherwise obsolete
    -- connector tiles can visually remain after a spacing-layout change.
    local void_tile = tile_or_fallback("out-of-map", "out-of-map")
    local tiles = {}
    for x = math.floor(area.left_top.x), math.floor(area.right_bottom.x - 1) do
        for y = math.floor(area.left_top.y), math.floor(area.right_bottom.y - 1) do
            tiles[#tiles + 1] = { name = void_tile, position = { x = x, y = y } }
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles, true) end
end

local rebuild_train_for_entity
local register_all_existing
local exit_wagon
local migrate_fluid_port_layout

local function train_signature(carriages)
    local parts = {}
    for i, carriage in ipairs(carriages or {}) do
        if valid(carriage) and carriage.unit_number then
            local name = carriage.name or carriage.type
            local base = tostring(name):match("^" .. TRAIN_SHIELD.variant_prefix:gsub("%-", "%%-") .. "(.+)%-%d+$")
            if base and TRAIN_SHIELD.base_names[base] then name = base end
            parts[#parts + 1] = table.concat({
                tostring(i),
                tostring(carriage.unit_number),
                tostring(carriage.type),
                tostring(name),
            }, ":")
        else
            parts[#parts + 1] = tostring(i) .. ":invalid"
        end
    end
    return table.concat(parts, "|")
end

-- Factorio may expose LuaTrain.carriages in the opposite order after a
-- rear-facing locomotive is coupled. The physical train is valid, but using
-- that transient list direction would mirror the complete interior. Normalize
-- the list against the permanent left-to-right room coordinates. Unit numbers,
-- not rolling-stock type or locomotive direction, own room identity.
function train_interiors._normalized_train_carriages(store, carriages, surface)
    local forward = {}
    for _, carriage in ipairs(carriages or {}) do
        if valid(carriage) and carriage.unit_number and WAGON_TYPES[carriage.type] then
            forward[#forward + 1] = carriage
        end
    end
    if #forward <= 1 or not (surface and surface.valid) then return forward end

    -- Direct Startup can finish the starter couplings one or more events after
    -- spawned_forces is set. Keep a separate orientation lock pending until the
    -- complete original Main Train has actually been observed. During that
    -- short pending window, normalize its partial and full local carriage list
    -- to left-to-right Fluid, Cargo, Locomotive. Once all three unique parts are
    -- present, the lock closes permanently and the established-layout logic
    -- below handles every later train change exactly as before.
    store.starter_layout_normalized_forces = store.starter_layout_normalized_forces or {}
    local starter_rank = {
        ["fluid-wagon"] = 1,
        ["cargo-wagon"] = 2,
        ["locomotive"] = 3,
    }
    local first_force = forward[1].force
    local force_index = first_force and first_force.valid and first_force.index or nil
    local starter_set = force_index ~= nil
        and #forward <= 3
        and store.starter_layout_normalized_forces[force_index] == false
    local seen_types = {}
    if starter_set then
        for _, carriage in ipairs(forward) do
            local carriage_force = carriage.force
            local carriage_type = carriage.type
            if not (carriage_force and carriage_force.valid and carriage_force.index == force_index)
                or not (store.main_train_units and store.main_train_units[carriage.unit_number])
                or not starter_rank[carriage_type]
                or seen_types[carriage_type] then
                starter_set = false
                break
            end
            seen_types[carriage_type] = true
        end
    end
    if starter_set then
        table.sort(forward, function(a, b)
            return starter_rank[a.type] < starter_rank[b.type]
        end)
        if #forward == 3
            and seen_types["fluid-wagon"]
            and seen_types["cargo-wagon"]
            and seen_types["locomotive"] then
            store.starter_layout_normalized_forces[force_index] = true
        end
        return forward
    end

    local reverse = {}
    for i = #forward, 1, -1 do reverse[#reverse + 1] = forward[i] end

    local function inversion_score(list)
        local centers = {}
        for _, carriage in ipairs(list) do
            local wagon = store.wagons[carriage.unit_number]
            if wagon and wagon.surface and wagon.surface.valid
                and wagon.surface.name == surface.name and wagon.area then
                centers[#centers + 1] = area_center(wagon.area).x
            end
        end
        local inversions = 0
        for i = 1, #centers - 1 do
            for j = i + 1, #centers do
                if centers[i] > centers[j] then inversions = inversions + 1 end
            end
        end
        return inversions, #centers
    end

    local forward_score, established = inversion_score(forward)
    local reverse_score = inversion_score(reverse)
    if established >= 2 and reverse_score < forward_score then return reverse end
    return forward
end

-- Keep an established train interior fixed in world-space when rolling stock is
-- coupled to either end. LuaTrain.carriages is re-indexed after a front coupling;
-- deriving every room from (index - 1) used to re-label all existing rooms one
-- slot to the right even though the player's machines stayed at their old
-- coordinates. A persistent anchor wagon provides a movable origin for the list:
-- the new carriage receives the free room before/after the existing layout, while
-- every established carriage keeps exactly the same interior coordinates.
local function train_layout_origin_x(store, carriages, surface)
    if not (store and surface and surface.valid) then return 0 end
    store.train_layout_anchor_units = store.train_layout_anchor_units or {}

    local anchor_unit = store.train_layout_anchor_units[surface.name]
    local anchor_wagon = anchor_unit and store.wagons[anchor_unit] or nil
    local anchor_index = nil

    if anchor_wagon and anchor_wagon.surface and anchor_wagon.surface.valid
        and anchor_wagon.surface.name == surface.name and anchor_wagon.area then
        for i, carriage in ipairs(carriages or {}) do
            if valid(carriage) and carriage.unit_number == anchor_unit then
                anchor_index = i
                break
            end
        end
    end

    if not anchor_index then
        anchor_unit = nil
        anchor_wagon = nil
        local best_layout_index = math.huge
        local best_x = math.huge
        for i, carriage in ipairs(carriages or {}) do
            if valid(carriage) and carriage.unit_number then
                local wagon = store.wagons[carriage.unit_number]
                if wagon and wagon.surface and wagon.surface.valid and wagon.surface.name == surface.name and wagon.area then
                    local center_x = area_center(wagon.area).x
                    local old_index = tonumber(wagon.layout_index) or math.huge
                    if old_index < best_layout_index or (old_index == best_layout_index and center_x < best_x) then
                        anchor_unit = carriage.unit_number
                        anchor_wagon = wagon
                        anchor_index = i
                        best_layout_index = old_index
                        best_x = center_x
                    end
                end
            end
        end
        if anchor_unit then store.train_layout_anchor_units[surface.name] = anchor_unit end
    end

    if not (anchor_wagon and anchor_wagon.area and anchor_index) then return 0 end
    return area_center(anchor_wagon.area).x - ((anchor_index - 1) * INTERIOR_WAGON_SPACING)
end

local function same_train_layout_built(store, carriages, surface, signature, layout_origin_x)
    if not (surface and surface.valid and signature) then return false end
    for i, carriage in ipairs(carriages or {}) do
        if not (valid(carriage) and carriage.unit_number and WAGON_TYPES[carriage.type]) then return false end
        local wagon = store.wagons[carriage.unit_number]
        if not (wagon and wagon.surface and wagon.surface.valid and wagon.surface.name == surface.name) then return false end
        if wagon.train_signature ~= signature or wagon.layout_index ~= i then return false end
        if wagon.interior_layout_version ~= INTERIOR_LAYOUT_VERSION then return false end
        if not wagon.area then return false end
        local expected = room_area((layout_origin_x or 0) + ((i - 1) * INTERIOR_WAGON_SPACING), carriage.force)
        if wagon.area.left_top.x ~= expected.left_top.x
            or wagon.area.right_bottom.x ~= expected.right_bottom.x
            or wagon.area.left_top.y ~= expected.left_top.y
            or wagon.area.right_bottom.y ~= expected.right_bottom.y then
            return false
        end
    end
    return true
end

-- A live, established room is immutable. If a future Factorio ordering edge
-- case cannot be normalized without moving one of those rooms, stop before any
-- tiles, chests, tanks, wiring or player-built entities are touched.
function train_interiors._established_layout_is_safe(store, carriages, surface, layout_origin_x)
    for i, carriage in ipairs(carriages or {}) do
        if valid(carriage) and carriage.unit_number then
            local wagon = store.wagons[carriage.unit_number]
            if wagon and wagon.surface and wagon.surface.valid
                and wagon.surface.name == surface.name and wagon.area then
                local actual = area_center(wagon.area)
                local expected = area_center(room_area(
                    (layout_origin_x or 0) + ((i - 1) * INTERIOR_WAGON_SPACING),
                    carriage.force
                ))
                if math.abs(actual.x - expected.x) > 0.01
                    or math.abs(actual.y - expected.y) > 0.01 then
                    return false, carriage.unit_number
                end
            end
        end
    end
    return true
end

function train_interiors._announce_layout_safety_stop(force, unit_number)
    if not (game and force and force.valid) then return end
    local s = state()
    s.train_layout_warning_tick = s.train_layout_warning_tick or {}
    local key = force.index
    local last = tonumber(s.train_layout_warning_tick[key]) or -1000000
    if (game.tick or 0) - last < 300 then return end
    s.train_layout_warning_tick[key] = game.tick or 0
    local message = "[The Cave] Train Interior layout safety lock stopped an unsafe room reorder. Existing rooms and contents were left unchanged."
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid and player.force == force then player.print(message) end
    end
    log(message .. " Unit: " .. tostring(unit_number or "unknown"))
end

function train_interiors._train_surface_for_carriages(store, carriages)
    local scored = {}
    for _, carriage in ipairs(carriages or {}) do
        if valid(carriage) and carriage.unit_number then
            local wagon = store.wagons[carriage.unit_number]
            if wagon and wagon.surface and wagon.surface.valid then
                local name = wagon.surface.name
                scored[name] = scored[name] or { surface = wagon.surface, count = 0, established = 0, locomotives = 0 }
                local score = scored[name]
                score.count = score.count + 1
                if wagon.train_signature or wagon.layout_index then score.established = score.established + 1 end
                if carriage.type == "locomotive" then score.locomotives = score.locomotives + 1 end
            end
        end
    end

    local best = nil
    for _, score in pairs(scored) do
        if not best
            or score.count > best.count
            or (score.count == best.count and score.established > best.established)
            or (score.count == best.count and score.established == best.established and score.locomotives > best.locomotives) then
            best = score
        end
    end
    if best and best.surface then return best.surface end
    return nil
end

function train_interiors._room_needs_transfer_entities(wagon)
    if not (wagon and valid(wagon.entity)) then return false end
    if wagon.entity.type == "cargo-wagon" then
        if wagon.cargo_port_layout_version ~= CARGO_PORT_LAYOUT_VERSION then
            -- Preserve legacy transfer chests until the enlarged room has been
            -- painted and both final Storehouse footprints are clear. The second
            -- configuration migration pass will then replace them without loss.
            for _, container in pairs(wagon.transfer_entities or {}) do
                if is_cargo_transfer_container(container) then return false end
            end
            return true
        end
        local roles = { import = false, export = false }
        for _, container in pairs(wagon.transfer_entities or {}) do
            if valid(container) and container.name == train_interiors.cargo_config.storehouse_name and container.unit_number then
                local role = wagon.transfer_roles and wagon.transfer_roles[container.unit_number]
                if role then roles[role] = true end
            end
        end
        return not (roles.import and roles.export)
    end
    if wagon.entity.type == "fluid-wagon" then
        if wagon.fluid_port_layout_version ~= FLUID_PORT_LAYOUT_VERSION then
            -- Keep the four legacy tanks alive until the migration has verified
            -- both new 5x5 footprints and can preserve each direction's fluid.
            for _, tank in pairs(wagon.transfer_entities or {}) do
                if train_interiors._is_fluid_transfer_tank(tank) then return false end
            end
            return true
        end
        local roles = { import = false, export = false }
        local count = 0
        for _, tank in pairs(wagon.transfer_entities or {}) do
            if valid(tank) and tank.name == train_interiors.fluid_config.tank_name then
                count = count + 1
                local role = wagon.transfer_roles and tank.unit_number and wagon.transfer_roles[tank.unit_number] or nil
                if not role and wagon.area and tank.position then
                    role = (tank.position.x >= area_center(wagon.area).x) and "import" or "export"
                end
                if role then roles[role] = true end
            end
        end
        return count ~= 2 or not (roles.import and roles.export)
    end
    return false
end

function train_interiors._ensure_room_present(wagon, moved_surface, moved_center)
    if not (wagon and wagon.surface and wagon.surface.valid and wagon.area) then return end
    paint_room_tiles(wagon)
    -- Research expansion changes only the room boundaries; its fixed center core
    -- and transfer ports stay in the same world positions. Rebuild scripted
    -- chests/tanks only if the room actually moves to another surface/center or
    -- a port-layout migration is needed, preserving their contents on size-only
    -- upgrades.
    if moved_surface or moved_center or train_interiors._room_needs_transfer_entities(wagon) then
        destroy_interior_entities(wagon)
        if valid(wagon.entity) then
            if wagon.entity.type == "cargo-wagon" then
                create_cargo_storehouses(wagon.surface, wagon)
            elseif wagon.entity.type == "fluid-wagon" then
                create_fluid_tanks(wagon.surface, wagon)
            end
        end
    end
    train_interiors._ensure_locomotive_power_fixtures(wagon)
    ensure_wagon_map_radar(wagon)
end

local function register_wagon(entity, skip_rebuild, force_main_train)
    if not active() then return nil end
    if not valid(entity) or not entity.unit_number or not WAGON_TYPES[entity.type] then return nil end
    local s = state()
    if force_main_train and entity.type == "locomotive" and entity.force and entity.force.valid
        and not s.main_battery_locomotive_units[entity.force.index] then
        s.main_battery_locomotive_units[entity.force.index] = entity.unit_number
    end
    if force_main_train then
        s.main_train_units[entity.unit_number] = true
        s.unclaimed_train_parts[entity.unit_number] = nil
    elseif not s.wagons[entity.unit_number] then
        local allowed = train_interiors._can_register_train_part(entity, skip_rebuild)
        if not allowed then return nil end
        s.main_train_units[entity.unit_number] = true
        s.unclaimed_train_parts[entity.unit_number] = nil
    elseif not s.main_train_units[entity.unit_number] then
        local allowed = train_interiors._can_register_train_part(entity, skip_rebuild)
        if not allowed then return nil end
        s.main_train_units[entity.unit_number] = true
        s.unclaimed_train_parts[entity.unit_number] = nil
    end
    if not skip_rebuild and train_interiors.apply_train_shield_to_entity then
        local shielded = train_interiors.apply_train_shield_to_entity(entity)
        if valid(shielded) then entity = shielded end
    end
    if s.wagons[entity.unit_number] then
        s.wagons[entity.unit_number].entity = entity
        s.wagons[entity.unit_number].force_index = entity.force.index
        s.wagons[entity.unit_number].exterior_surface_index = entity.surface.index
        s.wagons[entity.unit_number].exterior_surface_name = entity.surface.name
        if force_main_train then s.main_train_units[entity.unit_number] = true end
        if not skip_rebuild and rebuild_train_for_entity then rebuild_train_for_entity(entity) end
        return s.wagons[entity.unit_number]
    end

    pcall(function() entity.minable_flag = false end)
    local surface = create_hidden_surface(SURFACE_PREFIX .. tostring(entity.unit_number))
    local wagon = {
        entity = entity,
        force_index = entity.force.index,
        exterior_surface_index = entity.surface.index,
        exterior_surface_name = entity.surface.name,
        surface = surface,
        surface_name = surface.name,
        area = room_area(0, entity.force),
        doors = {},
        transfer_entities = {},
        item_transfer_snapshot = nil,
        interior_layout_version = INTERIOR_LAYOUT_VERSION,
    }
    s.wagons[entity.unit_number] = wagon
    s.main_train_units[entity.unit_number] = true
    s.unclaimed_train_parts[entity.unit_number] = nil
    s.surfaces[surface.name] = true
    s.surface_owners[surface.name] = entity.force.index
    s.train_layout_anchor_units[surface.name] = s.train_layout_anchor_units[surface.name] or entity.unit_number
    if not skip_rebuild then
        build_room(wagon)
        if rebuild_train_for_entity then rebuild_train_for_entity(entity) end
    end
    return wagon
end

function train_interiors.register_main_train_part(entity)
    return register_wagon(entity, false, true)
end

rebuild_train_for_entity = function(entity)
    if not active() then return end
    if game and (state().train_shield_suppress_rebuild_until or 0) >= (game.tick or 0) then return end
    if not valid(entity) or not entity.train or not entity.train.valid then return end
    local carriages = entity.train.carriages or {}
    if #carriages == 0 then return end
    local first = carriages[1]
    if not valid(first) or not first.unit_number then return end

    local s = state()
    if not train_interiors._train_contains_main_train(carriages) then return end
    train_interiors._enforce_main_train_capacity(entity, true)
    carriages = entity.train and entity.train.valid and entity.train.carriages or carriages
    local surface = train_interiors._train_surface_for_carriages(s, carriages)
        or create_hidden_surface(SURFACE_PREFIX .. "train-" .. tostring(first.unit_number))
    s.surfaces[surface.name] = true
    s.surface_owners[surface.name] = entity.force.index
    carriages = train_interiors._normalized_train_carriages(s, carriages, surface)
    local signature = train_signature(carriages)
    local layout_origin_x = train_layout_origin_x(s, carriages, surface)
    local layout_safe, unsafe_unit = train_interiors._established_layout_is_safe(s, carriages, surface, layout_origin_x)
    if not layout_safe then
        train_interiors._announce_layout_safety_stop(entity.force, unsafe_unit)
        return
    end
    local previously_on_surface = {}
    for _, carriage in ipairs(carriages) do
        if valid(carriage) and carriage.unit_number then
            local existing = s.wagons[carriage.unit_number]
            previously_on_surface[carriage.unit_number] = existing
                and existing.area
                and existing.surface
                and existing.surface.valid
                and existing.surface.name == surface.name
                or false
        end
    end

    -- If this connected LuaTrain is already represented by one shared interior,
    -- only repaint the entry pads and keep all player-built entities untouched.
    if same_train_layout_built(s, carriages, surface, signature, layout_origin_x) then
        for _, carriage in ipairs(carriages) do
            local wagon = valid(carriage) and carriage.unit_number and s.wagons[carriage.unit_number]
            if wagon then train_interiors._ensure_room_present(wagon, false, false) end
        end
        return
    end

    -- Never clear the whole train surface here. Earlier Shield builds rebuilt the
    -- train by destroying/recreating rolling stock or interior rooms, which could
    -- delete player-built machines and split each wagon into its own interior. This
    -- migration only reassigns wagon records to one shared surface and paints/builds
    -- missing rooms/connectors.
    local built = {}
    for i, carriage in ipairs(carriages) do
        if valid(carriage) and carriage.unit_number and WAGON_TYPES[carriage.type] then
            local wagon = s.wagons[carriage.unit_number] or register_wagon(carriage, true)
            if wagon then
                local previous_surface = wagon.surface and wagon.surface.valid and wagon.surface or nil
                local previous_surface_name = previous_surface and previous_surface.name or nil
                local previous_center = wagon.area and area_center(wagon.area) or nil
                local expected_area = room_area(layout_origin_x + ((i - 1) * INTERIOR_WAGON_SPACING), carriage.force)
                local expected_center = area_center(expected_area)
                local moved_surface = previous_surface_name ~= surface.name
                local moved_center = not previous_center
                    or previous_center.x ~= expected_center.x
                    or previous_center.y ~= expected_center.y
                wagon.entity = carriage
                wagon.force_index = carriage.force.index
                wagon.exterior_surface_index = carriage.surface.index
                wagon.exterior_surface_name = carriage.surface.name
                wagon.surface = surface
                wagon.surface_name = surface.name
                wagon.area = expected_area
                wagon.train_signature = signature
                wagon.layout_index = i
                wagon.layout_origin_x = layout_origin_x
                wagon.interior_layout_version = INTERIOR_LAYOUT_VERSION
                train_interiors._ensure_room_present(wagon, moved_surface, moved_center)
                if moved_surface and previous_surface and previous_surface.valid and game and game.connected_players then
                    for _, player in pairs(game.connected_players) do
                        if physical.on_surface(player, previous_surface) then
                            local center = area_center(wagon.area)
                            local target = { x = center.x, y = center.y }
                            local p = physical.find_position(player, surface, target, 3)
                            if physical.teleport(player, p, surface) then
                                local ps = get_player_state(player)
                                ps.last_wagon_unit = carriage.unit_number
                            end
                        end
                    end
                end
                built[#built + 1] = wagon
            end
        end
    end

    for i = 1, #built - 1 do
        local left_wagon = built[i]
        local right_wagon = built[i + 1]
        local left_unit = valid(left_wagon.entity) and left_wagon.entity.unit_number
        local right_unit = valid(right_wagon.entity) and right_wagon.entity.unit_number
        local preserve_existing = left_unit and right_unit
            and previously_on_surface[left_unit]
            and previously_on_surface[right_unit]
            or false
        local force = valid(left_wagon.entity) and left_wagon.entity.force
            or (valid(right_wagon.entity) and right_wagon.entity.force)
        build_connector(surface, left_wagon.area, right_wagon.area, force, preserve_existing)
    end

    if ensure_train_map_void then ensure_train_map_void(surface) end
    if ensure_all_train_power_entities then ensure_all_train_power_entities() end

    for _, wagon in pairs(built) do
        if valid(wagon.entity) and wagon.entity.force and wagon.entity.force.valid then
            chart_wagon_interior(wagon, wagon.entity.force)
        end
    end

    -- Ctrl+Enter is now the supported entry/exit control.
    -- Do not create physical fake car doors anymore; they consumed interior space
    -- and are no longer needed now that entry and exit use Ctrl+Enter.
end

function train_interiors.on_train_created(event)
    if not active() then return end
    if game and (state().train_shield_suppress_rebuild_until or 0) >= (game.tick or 0) then return end
    if event and event.train and event.train.valid and event.train.carriages and event.train.carriages[1] then
        rebuild_train_for_entity(event.train.carriages[1])
    else
        register_all_existing()
    end
end

register_all_existing = function()
    if not active() then return end
    train_interiors._infer_main_train_units()
    local s = state()
    local seen_trains = {}
    for unit, wagon in pairs(s.wagons or {}) do
        local entity = wagon and wagon.entity
        if valid(entity) and entity.train and entity.train.valid and train_interiors._train_contains_main_train(entity.train.carriages or {}) then
            local train_key = nil
            pcall(function() train_key = entity.train.id end)
            if not train_key and entity.train.carriages and entity.train.carriages[1] and entity.train.carriages[1].unit_number then
                train_key = "first-" .. tostring(entity.train.carriages[1].unit_number)
            end
            seen_trains[train_key or ("entity-" .. tostring(entity.unit_number))] = entity
        elseif not valid(entity) then
            s.wagons[unit] = nil
            s.main_train_units[unit] = nil
        end
    end
    for _, entity in pairs(seen_trains) do
        if valid(entity) then rebuild_train_for_entity(entity) end
    end
end

function train_interiors.on_init()
    state()
    cleanup_legacy_exit_cars()
    if active() then
        register_all_existing()
        train_interiors._initialize_pollution_transfer()
    end
    train_interiors.wave_defense.on_init(active())
end

function train_interiors.on_configuration_changed()
    train_interiors._migrate_force_keys()
    local s = state()
    s.map_radar_cleaned = nil
    for _, garden in pairs(s.gardens or {}) do garden.infrastructure_ready = nil end
    for _, record in pairs(s.train_power or {}) do record.external_pole_cache = nil end
    -- Retire saved approval timers and every old vote window, including those
    -- belonging to offline players. Normal seat occupancy remains enforced.
    s.train_pilot_access = nil
    s.train_pilot_vote = nil
    for _, player in pairs(game.players) do
        local frame = player.gui.top["the_cave_train_pilot_vote_frame"]
        if frame and frame.valid then frame.destroy() end
    end
    if train_interiors._clear_all_train_entry_prompts then train_interiors._clear_all_train_entry_prompts() end
    cleanup_legacy_exit_cars()
    if active() then
        -- Preserve existing import/export contents before register/rebuild can
        -- recreate port entities for a new layout version.
        train_interiors._migrate_artillery_empty_rooms()
        migrate_cargo_port_layout()
        migrate_fluid_port_layout()
        register_all_existing()
        if train_interiors.apply_train_shield_to_all then train_interiors.apply_train_shield_to_all(true) end
        train_interiors._migrate_artillery_empty_rooms()
        migrate_cargo_port_layout()
        migrate_fluid_port_layout()
        repaint_all_train_rooms()
        if train_interiors.ensure_all_garden_rooms then train_interiors.ensure_all_garden_rooms() end
        ensure_all_map_radars()
        if ensure_all_train_power_entities then ensure_all_train_power_entities() end
        chart_all_train_interiors()
        train_interiors._initialize_pollution_transfer()
    end
    train_interiors.wave_defense.on_configuration_changed(active())
end

local function inventory_counts(inventories)
    local counts = {}
    for _, inv in pairs(inventories) do
        if inv and inv.valid and not inv.is_empty() then
            for key, value in pairs(inv.get_contents()) do
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
                    counts[name] = counts[name] or {}
                    counts[name][quality] = (counts[name][quality] or 0) + count
                end
            end
        end
    end
    return counts
end

local function total_count(counts)
    local total = 0
    for _, qualities in pairs(counts or {}) do
        for _, count in pairs(qualities or {}) do total = total + count end
    end
    return total
end

local function move_one_stack(source, dest, name, quality, count)
    return item_transfer.move_count(source, dest, name, quality, count)
end

local function move_from_one_to_many_balanced(source, destinations, name, quality, count)
    if not (source and source.valid) or count <= 0 then return 0 end
    local valid_dests = {}
    for _, dest in pairs(destinations or {}) do
        if dest and dest.valid then valid_dests[#valid_dests + 1] = dest end
    end
    if #valid_dests == 0 then return 0 end

    local remaining = count
    local moved_total = 0
    local blocked_rounds = 0

    -- Fill import containers as evenly as possible instead of dumping into the
    -- first one. This remains compatible with legacy multi-chest interiors while
    -- current Cargo Wagons use one Storehouse per direction.
    while remaining > 0 and blocked_rounds < #valid_dests do
        table.sort(valid_dests, function(a, b)
            return (a.get_item_count { name = name, quality = quality } or 0)
                < (b.get_item_count { name = name, quality = quality } or 0)
        end)
        local moved_this_round = 0
        for _, dest in ipairs(valid_dests) do
            if remaining <= 0 then break end
            local share = math.max(1, math.ceil(remaining / #valid_dests))
            local moved = move_one_stack(source, dest, name, quality, share)
            if moved > 0 then
                remaining = remaining - moved
                moved_total = moved_total + moved
                moved_this_round = moved_this_round + moved
            end
        end
        if moved_this_round <= 0 then
            blocked_rounds = blocked_rounds + 1
        else
            blocked_rounds = 0
        end
    end

    return moved_total
end

local function move_from_many_to_one(sources, dest, name, quality, count)
    if not (dest and dest.valid) or count <= 0 then return 0 end
    local remaining = count
    for _, source in pairs(sources) do
        if remaining <= 0 then break end
        if source and source.valid then
            local available = source.get_item_count { name = name, quality = quality }
            if available > 0 then
                local requested = math.min(available, remaining)
                local moved = move_one_stack(source, dest, name, quality, requested)
                remaining = remaining - moved
            end
        end
    end
    return count - remaining
end

local function cargo_port_role(wagon, container)
    if not valid(container) then return nil end
    if wagon.transfer_roles and container.unit_number and wagon.transfer_roles[container.unit_number] then
        return wagon.transfer_roles[container.unit_number]
    end
    -- Migration fallback for interiors created by older test builds: classify
    -- existing fixed transfer containers by side without rebuilding the room.
    if wagon.area and container.position then
        local center_x = area_center(wagon.area).x
        return (container.position.x >= center_x) and "import" or "export"
    end
    return "import"
end

local function sync_cargo(wagon)
    if not valid(wagon.entity) then return end
    if wagon.entity.type ~= "cargo-wagon" then return end
    local wagon_inv = wagon.entity.get_inventory(defines.inventory.cargo_wagon)
    if not (wagon_inv and wagon_inv.valid) then return end

    local import_invs = {}
    local export_invs = {}
    for _, container in pairs(wagon.transfer_entities or {}) do
        if is_cargo_transfer_container(container) then
            local inv = container.get_inventory(defines.inventory.chest)
            if inv and inv.valid then
                local role = cargo_port_role(wagon, container)
                if role == "export" then
                    export_invs[#export_invs + 1] = inv
                else
                    import_invs[#import_invs + 1] = inv
                end
            end
        end
    end
    if #import_invs == 0 and #export_invs == 0 then return end

    local current_wagon = inventory_counts { wagon_inv }
    local current_import = inventory_counts(import_invs)
    local current_export = inventory_counts(export_invs)
    local pending_import = {}

    -- Version-1 snapshots aggregated all qualities under the item name. Preserve
    -- normal-quality baselines during migration, but deliberately leave every
    -- non-normal quality at zero so already-stuck stacks are retried once in the
    -- correct direction without re-importing established normal export cargo.
    if wagon.item_transfer_snapshot
        and wagon.item_transfer_snapshot.version ~= ITEM_TRANSFER_SNAPSHOT_VERSION then
        local migrated_wagon, migrated_export = {}, {}
        for name, qualities in pairs(current_wagon) do
            if (qualities.normal or 0) > 0 then migrated_wagon[name] = { normal = qualities.normal } end
        end
        for name, qualities in pairs(current_export) do
            if (qualities.normal or 0) > 0 then migrated_export[name] = { normal = qualities.normal } end
        end
        wagon.item_transfer_snapshot = {
            version = ITEM_TRANSFER_SNAPSHOT_VERSION,
            wagon = migrated_wagon,
            import_chests = current_import,
            export_chests = migrated_export,
        }
    end

    if not wagon.item_transfer_snapshot or not wagon.item_transfer_snapshot.import_chests then
        -- First tick / migration behavior:
        --   wagon contents are imported into the interior Import Storehouse
        --   Export Storehouse contents are sent back out into the real wagon.
        if total_count(current_wagon) > 0 and #import_invs > 0 then
            for name, qualities in pairs(current_wagon) do
                for quality, count in pairs(qualities) do
                    local moved = move_from_one_to_many_balanced(wagon_inv, import_invs, name, quality, count)
                    if moved < count then
                        pending_import[name] = pending_import[name] or {}
                        pending_import[name][quality] = count - moved
                    end
                end
            end
        end
        if total_count(current_export) > 0 then
            for name, qualities in pairs(current_export) do
                for quality, count in pairs(qualities) do
                    move_from_many_to_one(export_invs, wagon_inv, name, quality, count)
                end
            end
        end
        wagon.item_transfer_snapshot = {
            version = ITEM_TRANSFER_SNAPSHOT_VERSION,
            wagon = inventory_counts { wagon_inv },
            import_chests = inventory_counts(import_invs),
            export_chests = inventory_counts(export_invs),
            pending_import = pending_import,
        }
        return
    end

    local previous_wagon = wagon.item_transfer_snapshot.wagon or {}
    local previous_import = wagon.item_transfer_snapshot.import_chests or {}
    local previous_export = wagon.item_transfer_snapshot.export_chests or {}
    local item_names = {}
    for name in pairs(current_wagon) do item_names[name] = true end
    for name in pairs(current_import) do item_names[name] = true end
    for name in pairs(current_export) do item_names[name] = true end
    for name in pairs(previous_wagon) do item_names[name] = true end
    for name in pairs(previous_import) do item_names[name] = true end
    for name in pairs(previous_export) do item_names[name] = true end

    for name in pairs(item_names) do
        local qualities = {}
        for quality in pairs(current_wagon[name] or {}) do qualities[quality] = true end
        for quality in pairs(current_import[name] or {}) do qualities[quality] = true end
        for quality in pairs(current_export[name] or {}) do qualities[quality] = true end
        for quality in pairs(previous_wagon[name] or {}) do qualities[quality] = true end
        for quality in pairs(previous_import[name] or {}) do qualities[quality] = true end
        for quality in pairs(previous_export[name] or {}) do qualities[quality] = true end

        for quality in pairs(qualities) do
            local current = ((current_wagon[name] or {})[quality] or 0)
            local waiting = (((wagon.item_transfer_snapshot.pending_import or {})[name] or {})[quality] or 0)
            -- Include blocked imports, but subtract withdrawals since the last
            -- sync. Never retry items already delivered to the wagon as exports.
            local wagon_added = math.min(current, math.max(0, waiting + current
                - ((previous_wagon[name] or {})[quality] or 0)))
            -- This is a dedicated export inventory: every remaining item is
            -- eligible, including payloads blocked before this update.
            local export_added = ((current_export[name] or {})[quality] or 0)

            -- Outside -> wagon -> train interior Import Storehouse.
            if wagon_added > 0 then
                local moved = move_from_one_to_many_balanced(wagon_inv, import_invs, name, quality, wagon_added)
                if moved < wagon_added then
                    pending_import[name] = pending_import[name] or {}
                    pending_import[name][quality] = wagon_added - moved
                end
            end

            -- Train interior -> Export Storehouse -> real cargo wagon.
            -- Import containers are intentionally ignored here so imported items do not loop
            -- straight back out again. Players can use inserters/filters inside the
            -- train to decide what goes to the export side.
            if export_added > 0 then
                move_from_many_to_one(export_invs, wagon_inv, name, quality, export_added)
            end
        end
    end

    wagon.item_transfer_snapshot = {
        version = ITEM_TRANSFER_SNAPSHOT_VERSION,
        wagon = inventory_counts { wagon_inv },
        import_chests = inventory_counts(import_invs),
        export_chests = inventory_counts(export_invs),
        pending_import = pending_import,
    }
end

local function fluid_at(entity)
    if not valid(entity) then return nil end
    local ok, fluid = pcall(function() return entity.get_fluid(1) end)
    if ok then return fluid end
    return nil
end

local function fluid_info(entity)
    local f = fluid_at(entity)
    if f and f.name and f.amount and f.amount > 0 then
        return { name = f.name, amount = f.amount, temperature = f.temperature }
    end
    return nil
end

local function insert_fluid_safe(entity, fluid)
    if not (valid(entity) and fluid and fluid.name and fluid.amount and fluid.amount > 0) then return 0 end
    local ok, inserted = pcall(function()
        return entity.insert_fluid { name = fluid.name, amount = fluid.amount, temperature = fluid.temperature }
    end)
    if ok and inserted then return inserted end
    return 0
end

local function remove_fluid_safe(entity, fluid)
    if not (valid(entity) and fluid and fluid.name and fluid.amount and fluid.amount > 0) then return 0 end
    local ok, removed = pcall(function()
        return entity.extract_fluid { name = fluid.name, amount = fluid.amount }
    end)
    if ok and removed then return removed end
    return 0
end

local function move_fluid_one_to_one(source, dest, max_amount)
    if not (valid(source) and valid(dest) and max_amount and max_amount > 0) then return 0 end
    local sf = fluid_info(source)
    if not sf then return 0 end
    local requested = math.min(sf.amount, max_amount)
    if requested <= 0 then return 0 end

    local removed = remove_fluid_safe(source, { name = sf.name, amount = requested, temperature = sf.temperature })
    if removed <= 0 then return 0 end

    local inserted = insert_fluid_safe(dest, { name = sf.name, amount = removed, temperature = sf.temperature })
    if inserted < removed then
        -- Destination cannot accept all of this fluid, usually because it is full
        -- or already contains a different fluid. Return the remainder to avoid loss.
        insert_fluid_safe(source, { name = sf.name, amount = removed - inserted, temperature = sf.temperature })
    end
    return inserted
end

local function move_fluid_one_to_many_balanced(source, destinations, max_amount)
    if not (valid(source) and max_amount and max_amount > 0) then return 0 end
    local sf = fluid_info(source)
    if not sf then return 0 end

    local valid_dests = {}
    for _, dest in pairs(destinations or {}) do
        if valid(dest) then
            local df = fluid_info(dest)
            if not df or df.name == sf.name then
                valid_dests[#valid_dests + 1] = dest
            end
        end
    end
    if #valid_dests == 0 then return 0 end

    local remaining = math.min(max_amount, sf.amount)
    local moved_total = 0
    local blocked_rounds = 0
    while remaining > 1 and blocked_rounds < #valid_dests do
        table.sort(valid_dests, function(a, b)
            local af = fluid_info(a)
            local bf = fluid_info(b)
            return ((af and af.amount) or 0) < ((bf and bf.amount) or 0)
        end)
        local moved_this_round = 0
        for _, dest in ipairs(valid_dests) do
            if remaining <= 1 then break end
            local share = math.max(1, remaining / #valid_dests)
            local moved = move_fluid_one_to_one(source, dest, share)
            if moved > 0 then
                remaining = remaining - moved
                moved_total = moved_total + moved
                moved_this_round = moved_this_round + moved
            end
        end
        if moved_this_round <= 0 then
            blocked_rounds = blocked_rounds + 1
        else
            blocked_rounds = 0
        end
    end

    return moved_total
end

local function move_fluid_many_to_one(sources, dest, max_per_source)
    if not valid(dest) then return 0 end
    local moved_total = 0
    for _, source in pairs(sources or {}) do
        if valid(source) then
            moved_total = moved_total + move_fluid_one_to_one(source, dest, max_per_source or FLUID_TRANSFER_PER_SYNC)
        end
    end
    return moved_total
end

local function fluid_tank_role(wagon, tank)
    if not valid(tank) then return nil end
    if wagon.transfer_roles and tank.unit_number and wagon.transfer_roles[tank.unit_number] then
        return wagon.transfer_roles[tank.unit_number]
    end
    if wagon.area and tank.position then
        local center_x = area_center(wagon.area).x
        return (tank.position.x >= center_x) and "import" or "export"
    end
    return "import"
end

migrate_fluid_port_layout = function()
    local s = state()
    for _, wagon in pairs(s.wagons or {}) do
        if valid(wagon.entity)
            and wagon.surface and wagon.surface.valid
            and wagon.area
            and wagon.entity.type == "fluid-wagon"
            and wagon.fluid_port_layout_version ~= FLUID_PORT_LAYOUT_VERSION then

            local repositioned = train_interiors._try_reposition_fixed_transfer_pair(
                wagon,
                train_interiors._fluid_tank_definitions(wagon),
                train_interiors.fluid_config.tank_name,
                "fluid_port_layout_version",
                FLUID_PORT_LAYOUT_VERSION
            )

            if not repositioned and train_interiors._fluid_tank_positions_available(wagon.surface, wagon) then

                local preserved = { import = nil, export = nil }
                local existing_tanks = {}
                local migration_safe = true
                for _, tank in pairs(wagon.transfer_entities or {}) do
                    if train_interiors._is_fluid_transfer_tank(tank) then
                        existing_tanks[#existing_tanks + 1] = tank
                        local f = fluid_info(tank)
                        if f then
                            local role = fluid_tank_role(wagon, tank) or "import"
                            preserved[role] = preserved[role] or { name = f.name, amount = 0, temperature = f.temperature }
                            if preserved[role].name == f.name then
                                preserved[role].amount = preserved[role].amount + f.amount
                                preserved[role].temperature = f.temperature or preserved[role].temperature
                            else
                                -- One 5x5 tank cannot contain two different fluids.
                                -- Keep the complete legacy layout instead of deleting either.
                                migration_safe = false
                            end
                        end
                    end
                end

                if migration_safe then
                    for _, tank in pairs(existing_tanks) do
                        if valid(tank) then pcall(function() tank.destroy() end) end
                    end

                    create_fluid_tanks(wagon.surface, wagon)

                    -- Preserve fluids in their original direction during layout-only changes.
                    -- Older single-tank layouts still fall back to the role inferred from position.
                    for role, preserved_fluid in pairs(preserved) do
                        if preserved_fluid and preserved_fluid.amount > 0 then
                            local targets = {}
                            for _, tank in pairs(wagon.transfer_entities or {}) do
                                if train_interiors._is_fluid_transfer_tank(tank) and fluid_tank_role(wagon, tank) == role then
                                    targets[#targets + 1] = tank
                                end
                            end
                            local remaining = preserved_fluid.amount
                            for _, tank in pairs(targets) do
                                if remaining <= 0 then break end
                                local inserted = insert_fluid_safe(tank, { name = preserved_fluid.name, amount = remaining, temperature = preserved_fluid.temperature })
                                remaining = remaining - inserted
                            end
                        end
                    end
                end
            end
        end
    end
end

local function sync_fluid(wagon)
    if not valid(wagon.entity) or wagon.entity.type ~= "fluid-wagon" then return end

    local import_tanks = {}
    local export_tanks = {}
    for _, tank in pairs(wagon.transfer_entities or {}) do
        if train_interiors._is_fluid_transfer_tank(tank) then
            local role = fluid_tank_role(wagon, tank)
            if role == "export" then
                export_tanks[#export_tanks + 1] = tank
            else
                import_tanks[#import_tanks + 1] = tank
            end
        end
    end
    if #import_tanks == 0 and #export_tanks == 0 then return end

    -- Version 2 snapshots track only fluid that entered the real wagon through
    -- the interior's left-side export tanks. Legacy snapshots tracked every
    -- observed wagon fluid and could therefore leave a full exterior wagon
    -- permanently marked as already imported after the import tanks were drained.
    local snapshot = wagon.fluid_transfer_snapshot
    local previous_wagon = snapshot
        and snapshot.version == FLUID_TRANSFER_SNAPSHOT_VERSION
        and snapshot.wagon
        or nil
    local current_wagon_before = fluid_info(wagon.entity)
    local protected_export = 0
    if current_wagon_before
        and previous_wagon
        and previous_wagon.name == current_wagon_before.name then
        protected_export = math.min(current_wagon_before.amount, math.max(0, previous_wagon.amount or 0))
    end

    -- Everything currently in the real wagon except the still-present protected
    -- export amount came from outside and remains eligible for import. If the
    -- right-side tanks are full, the unimported remainder is retried next sync.
    local import_request = current_wagon_before
        and math.max(0, current_wagon_before.amount - protected_export)
        or 0

    if import_request > 0 and #import_tanks > 0 then
        move_fluid_one_to_many_balanced(wagon.entity, import_tanks, import_request)
    end

    -- Left-side export tanks -> real fluid wagon. This retries every sync while
    -- fluid remains in an export tank, so a full wagon can drain later.
    local moved_export = 0
    if #export_tanks > 0 then
        moved_export = move_fluid_many_to_one(export_tanks, wagon.entity, FLUID_TRANSFER_PER_SYNC)
    end

    local current_wagon_after = fluid_info(wagon.entity)
    if current_wagon_after then
        local protected_after = moved_export
        if current_wagon_before and current_wagon_after.name == current_wagon_before.name then
            protected_after = protected_export + moved_export
        end
        protected_after = math.min(current_wagon_after.amount, math.max(0, protected_after))

        if protected_after > 0 then
            wagon.fluid_transfer_snapshot = {
                version = FLUID_TRANSFER_SNAPSHOT_VERSION,
                wagon = {
                    name = current_wagon_after.name,
                    amount = protected_after,
                    temperature = current_wagon_after.temperature,
                },
            }
        else
            wagon.fluid_transfer_snapshot = { version = FLUID_TRANSFER_SNAPSHOT_VERSION, wagon = nil }
        end
    else
        wagon.fluid_transfer_snapshot = { version = FLUID_TRANSFER_SNAPSHOT_VERSION, wagon = nil }
    end

end

local function train_power_researched_level(force)
    if not (force and force.valid and force.technologies) then return TRAIN_POWER_DEFAULT_LEVEL end
    local level = 0
    for i = 1, #TRAIN_POWER_LEVEL_CAPACITY_MJ do
        local tech = force.technologies[TRAIN_POWER_TECH_PREFIX .. i]
        if tech and tech.researched then
            level = i
        end
    end
    return level
end

local function train_power_capacity_j(record, force)
    local level
    if force and force.valid then
        level = train_power_researched_level(force)
        if record then record.level = level end
    else
        level = tonumber(record and record.level) or TRAIN_POWER_DEFAULT_LEVEL
    end
    level = math.floor(tonumber(level) or 0)
    if level <= 0 then return 0, 0 end
    level = math.max(1, math.min(#TRAIN_POWER_LEVEL_CAPACITY_MJ, level))
    return (TRAIN_POWER_LEVEL_CAPACITY_MJ[level] or 0) * TRAIN_POWER_J_PER_MJ, level
end

local function train_power_input_name_for_level(level)
    level = math.max(1, math.min(#TRAIN_POWER_LEVEL_INPUT_INTERFACE_NAMES, tonumber(level) or 1))
    return TRAIN_POWER_LEVEL_INPUT_INTERFACE_NAMES[level] or TRAIN_POWER_LEVEL_INPUT_INTERFACE_NAMES[1]
end

function train_interiors._train_power_output_name_for_level(level)
    local names = train_interiors.power_bridge_config.output_interface_names
    level = math.max(1, math.min(#names, tonumber(level) or 1))
    return names[level] or names[1]
end

local function train_power_charge_rate_mw_for_level(level)
    level = math.max(1, math.min(#TRAIN_POWER_LEVEL_CHARGE_RATE_MW, tonumber(level) or 1))
    return TRAIN_POWER_LEVEL_CHARGE_RATE_MW[level] or TRAIN_POWER_LEVEL_CHARGE_RATE_MW[1] or 0
end

local function train_power_output_rate_mw_for_level(level)
    level = math.max(1, math.min(#TRAIN_POWER_LEVEL_OUTPUT_RATE_MW, tonumber(level) or 1))
    return TRAIN_POWER_LEVEL_OUTPUT_RATE_MW[level] or TRAIN_POWER_LEVEL_OUTPUT_RATE_MW[1] or 0
end

local function train_power_record(surface)
    if not (surface and surface.valid) then return nil end
    local s = state()
    local key = surface.name
    local record = s.train_power[key]
    if not record then
        record = {
            level = TRAIN_POWER_DEFAULT_LEVEL,
            energy = 0,
            output_reserved = 0,
            last_output_energy = 0,
            last_charge_rate_mw = 0,
            charge_enabled = false,
        }
        s.train_power[key] = record
    end
    local capacity = train_power_capacity_j(record)
    record.energy = math.max(0, math.min(tonumber(record.energy) or 0, capacity))
    record.output_reserved = math.max(0, tonumber(record.output_reserved) or 0)
    record.last_output_energy = math.max(0, tonumber(record.last_output_energy) or 0)
    return record
end

local function train_power_anchor_wagon(surface)
    local main = train_interiors._main_battery_locomotive_wagon(surface)
    if main then return main end
    local wagons = collect_surface_wagons(surface)
    local fallback = nil
    for _, wagon in ipairs(wagons) do
        if wagon and valid(wagon.entity) then
            fallback = fallback or wagon
            if wagon.entity.type == "locomotive" then return wagon end
        end
    end
    return fallback
end

local function train_power_internal_position_for_wagon(wagon)
    if wagon and valid(wagon.locomotive_substation) then
        return { x = wagon.locomotive_substation.position.x, y = wagon.locomotive_substation.position.y }
    end
    if wagon and wagon.area then
        local center = area_center(wagon.area)
        local _, _, core_top = train_interiors._center_core_bounds(wagon.area)
        return { x = center.x, y = core_top + 2 }
    end
    return { x = 0, y = 50 }
end

local function train_power_external_position(wagon)
    if not (wagon and valid(wagon.entity)) then return nil end
    -- Centre the collisionless output bridge on the Main Locomotive so the
    -- scripted 10-tile square exactly matches its visible POWER RANGE outline.
    return { x = wagon.entity.position.x, y = wagon.entity.position.y }
end

-- Existing saves may contain many hours of pollution trapped on interior
-- surfaces. Discard that historical backlog once when this feature is first
-- installed; only pollution produced after the upgrade is vented outside.
function train_interiors._initialize_pollution_transfer()
    local s = state()
    if s.pollution_transfer_version == train_interiors.pollution_config.transfer_version then return false end
    for surface_name in pairs(s.surfaces or {}) do
        local surface = game and game.surfaces[surface_name] or nil
        if valid(surface) then train_interiors.interior_pollution.clear(surface) end
    end
    s.pollution_transfer_version = train_interiors.pollution_config.transfer_version
    return true
end

function train_interiors._sync_pollution()
    if train_interiors._initialize_pollution_transfer() then return end
    local s = state()
    local handled_surfaces = {}

    -- Coupled wagons share one interior surface. Vent that surface only once,
    -- at the live exterior Main Locomotive (or the first valid carriage when a
    -- disconnected interior has no locomotive). Moving the train changes only
    -- the next vent position; pollution already left behind is never cleared.
    for _, wagon in pairs(s.wagons or {}) do
        local surface = wagon and wagon.surface
        if valid(surface) and not handled_surfaces[surface.index] then
            handled_surfaces[surface.index] = true
            local anchor = train_power_anchor_wagon(surface)
            local exterior_entity = anchor and anchor.entity
            if valid(exterior_entity) then
                train_interiors.interior_pollution.transfer {
                    key = "train:" .. tostring(surface.index),
                    mode = "Train",
                    interior_surface = surface,
                    exterior_surface = exterior_entity.surface,
                    position = exterior_entity.position,
                }
            end
        end
    end

    -- The locomotive Garden is a second factory-capable interior surface. Its
    -- real pollution follows the same Main Locomotive exterior vent.
    for force_key, garden in pairs(s.gardens or {}) do
        local garden_surface = garden and garden.surface_name and game.surfaces[garden.surface_name] or nil
        local force = garden and garden.force_index and game.forces[garden.force_index]
            or (garden and garden.force_name and game.forces[garden.force_name])
        local anchor = force and train_interiors._garden_main_locomotive_wagon
            and train_interiors._garden_main_locomotive_wagon(force) or nil
        local exterior_entity = anchor and anchor.entity
        if valid(garden_surface) and valid(exterior_entity) then
            train_interiors.interior_pollution.transfer {
                key = "garden:" .. tostring(force_key),
                mode = "Train Garden",
                interior_surface = garden_surface,
                exterior_surface = exterior_entity.surface,
                position = exterior_entity.position,
            }
        end
    end
end

local function destroy_if_valid(entity)
    if valid(entity) then pcall(function() entity.destroy() end) end
end

local function destroy_entity_table(tbl)
    if type(tbl) ~= "table" then return end
    for _, entity in pairs(tbl) do
        destroy_if_valid(entity)
    end
end

local function ensure_hidden_train_power_entity(record, field, surface, name, position, force)
    if not (record and surface and surface.valid and name and position and force and force.valid) then return nil end
    local entity = record[field]
    if valid(entity) and entity.name == name and entity.surface == surface then
        if math.abs(entity.position.x - position.x) > 0.001
            or math.abs(entity.position.y - position.y) > 0.001 then
            pcall(function() entity.teleport(position) end)
        end
    else
        destroy_if_valid(entity)
        local ok, created = pcall(function()
            return surface.create_entity {
                name = name,
                position = position,
                force = force,
                create_build_effect_smoke = false,
            }
        end)
        entity = (ok and created and created.valid) and created or nil
        if entity then
            pcall(function() entity.destructible = false end)
            pcall(function() entity.minable_flag = false end)
            pcall(function() entity.operable = false end)
        end
        record[field] = entity
    end
    return entity
end

function train_interiors._safe_destroy_train_power_render(object)
    pcall(function()
        if object and object.valid then object.destroy() end
    end)
end

function train_interiors._destroy_train_power_range_render(record)
    local range_render = record and record.power_range_render
    if not range_render then return end
    train_interiors._safe_destroy_train_power_render(range_render.outline)
    train_interiors._safe_destroy_train_power_render(range_render.label)
    record.power_range_render = nil
end

function train_interiors._ensure_train_power_range_render(record, locomotive)
    if not (record and valid(locomotive) and locomotive.force and locomotive.force.valid) then
        train_interiors._destroy_train_power_range_render(record)
        return
    end

    local existing = record.power_range_render
    if existing
        and existing.version == train_interiors.power_range_config.render_version
        and existing.locomotive_unit_number == locomotive.unit_number
        and existing.surface_index == locomotive.surface.index
        and existing.outline and existing.outline.valid
        and existing.label and existing.label.valid then
        return
    end
    train_interiors._destroy_train_power_range_render(record)

    local outline = nil
    local label = nil
    local ok = pcall(function()
        outline = rendering.draw_rectangle {
            surface = locomotive.surface,
            left_top = {
                type = "entity",
                entity = locomotive,
                offset = { -train_interiors.power_range_config.half_size, -train_interiors.power_range_config.half_size },
            },
            right_bottom = {
                type = "entity",
                entity = locomotive,
                offset = { train_interiors.power_range_config.half_size, train_interiors.power_range_config.half_size },
            },
            color = train_interiors.power_range_config.line_color,
            width = train_interiors.power_range_config.line_width,
            filled = false,
            forces = { locomotive.force },
            only_in_alt_mode = false,
            draw_on_ground = false,
            render_mode = "game",
        }
        label = rendering.draw_text {
            surface = locomotive.surface,
            target = {
                type = "entity",
                entity = locomotive,
                offset = { 0, -train_interiors.power_range_config.half_size - 1.25 },
            },
            text = { "the-cave-train-power.power-range-label" },
            color = train_interiors.power_range_config.line_color,
            scale = 0.9,
            alignment = "center",
            vertical_alignment = "bottom",
            forces = { locomotive.force },
            only_in_alt_mode = false,
            draw_on_ground = false,
            render_mode = "game",
        }
    end)
    if not ok or not (outline and outline.valid and label and label.valid) then
        train_interiors._safe_destroy_train_power_render(outline)
        train_interiors._safe_destroy_train_power_render(label)
        return
    end
    record.power_range_render = {
        outline = outline,
        label = label,
        version = train_interiors.power_range_config.render_version,
        locomotive_unit_number = locomotive.unit_number,
        surface_index = locomotive.surface.index,
    }
end

function train_interiors._get_train_power_copper_connector(entity, create)
    if not (valid(entity) and entity.get_wire_connector) then return nil end
    local ok, connector = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, create == true)
    end)
    if ok and connector and connector.valid then return connector end
    return nil
end

function train_interiors._pole_inside_train_power_square(pole, center, half_size)
    return valid(pole)
        and pole.position
        and math.abs(pole.position.x - center.x) <= half_size + 0.001
        and math.abs(pole.position.y - center.y) <= half_size + 0.001
end

function train_interiors._eligible_train_power_pole(hidden_pole, pole, center, half_size)
    return valid(pole)
        and pole.type == "electric-pole"
        and pole.unit_number ~= hidden_pole.unit_number
        and pole.surface == hidden_pole.surface
        and pole.force == hidden_pole.force
        and pole.name ~= TRAIN_POWER_LEGACY_INTERNAL_POLE_NAME
        and pole.name ~= TRAIN_POWER_OUTPUT_POLE_NAME
        and pole.name ~= TRAIN_POWER_LEGACY_BUS_POLE_NAME
        and train_interiors._pole_inside_train_power_square(pole, center, half_size)
end

function train_interiors._prune_hidden_pole_connections(hidden_pole, center, half_size)
    local connector = train_interiors._get_train_power_copper_connector(hidden_pole, true)
    if not connector then return nil end
    local ok, connections = pcall(function() return connector.real_connections end)
    if not ok or type(connections) ~= "table" then return connector end
    for _, connection in pairs(connections) do
        local target_connector = connection and connection.target
        local target_pole = nil
        pcall(function() target_pole = target_connector and target_connector.owner end)
        if not train_interiors._eligible_train_power_pole(hidden_pole, target_pole, center, half_size) then
            pcall(function()
                connector.disconnect_from(target_connector, connection.origin)
            end)
        end
    end
    return connector
end

function train_interiors._connect_hidden_pole_to_player_poles(hidden_pole, center, half_size, record)
    if not (valid(hidden_pole) and center) then return end
    half_size = half_size or train_interiors.power_range_config.half_size
    local connector = train_interiors._prune_hidden_pole_connections(hidden_pole, center, half_size)
    if not connector then return end
    -- Preserve the public helper's uncached behavior when no record is supplied.
    local poles = maintenance.poles(record or {}, hidden_pole, center, half_size)
    for _, pole in pairs(poles or {}) do
        if train_interiors._eligible_train_power_pole(hidden_pole, pole, center, half_size) then
            local target = train_interiors._get_train_power_copper_connector(pole, true)
            if target then
                local already_connected = false
                pcall(function()
                    already_connected = connector.is_connected_to(target, defines.wire_origin.player)
                        or connector.is_connected_to(target, defines.wire_origin.script)
                end)
                if not already_connected then
                    -- The visible rule is a square. Bypass the prototype's
                    -- circular reach check only for poles already proven to be
                    -- inside that exact 10-tile square, including its corners.
                    pcall(function()
                        connector.connect_to(target, false, defines.wire_origin.script)
                    end)
                end
            end
        end
    end
end

function train_interiors._settle_train_power_output(record, output, reserved_energy)
    if not record then return 0 end
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

local function ensure_train_power_entities_for_surface(surface)
    if not (surface and surface.valid and is_train_surface(surface)) then return nil end
    train_interiors._ensure_all_locomotive_power_fixtures(surface)
    local anchor_wagon = train_power_anchor_wagon(surface)
    if not (anchor_wagon and valid(anchor_wagon.entity) and anchor_wagon.entity.force and anchor_wagon.entity.force.valid) then return nil end

    local record = train_power_record(surface)
    if not record then return nil end
    local force = anchor_wagon.entity.force
    local external_pos = train_power_external_position(anchor_wagon)
    if not external_pos then return nil end

    -- One-time save migration from the old hidden-accumulator bridge. Account
    -- for pending input/output energy first, then remove only The Cave's own
    -- hidden entities. Player-built accumulators are never scanned or changed.
    if record.bridge_version ~= train_interiors.power_bridge_config.version then
        local staged_output = valid(record.output_interface) and record.output_interface or record.output_accumulator
        local reserved_output = math.max(0, tonumber(record.output_reserved) or 0)
        if reserved_output <= 0 then
            reserved_output = math.max(0, tonumber(record.last_output_energy) or 0)
        end
        train_interiors._settle_train_power_output(record, staged_output, reserved_output)

        -- Capture real interior-grid energy that entered an old charger after
        -- its previous 15-tick sync, without ever counting the mirrored output
        -- accumulator as stored energy.
        local recovered_input_energy = 0
        local recovered_input_units = {}
        local function recover_input_energy(entity)
            if not valid(entity) then return end
            local key = entity.unit_number or entity
            if recovered_input_units[key] then return end
            recovered_input_units[key] = true
            recovered_input_energy = recovered_input_energy + math.max(0, tonumber(entity.energy) or 0)
        end
        recover_input_energy(record.input_interface)
        recover_input_energy(record.input_accumulator)
        for _, input in pairs(record.input_accumulators or {}) do recover_input_energy(input) end

        destroy_if_valid(record.input_interface)
        destroy_if_valid(record.input_accumulator)
        destroy_if_valid(record.inside_pole)
        destroy_entity_table(record.input_accumulators)
        destroy_entity_table(record.inside_poles)
        destroy_entity_table(record.inside_bus_poles)
        for _, pole in pairs(surface.find_entities_filtered { type = "electric-pole" }) do
            if valid(pole) and (pole.name == TRAIN_POWER_LEGACY_INTERNAL_POLE_NAME
                or pole.name == TRAIN_POWER_LEGACY_BUS_POLE_NAME) then
                destroy_if_valid(pole)
            end
        end
        for _, accumulator in pairs(surface.find_entities_filtered { type = "accumulator" }) do
            if valid(accumulator) and type(accumulator.name) == "string"
                and accumulator.name:find("^the%-cave%-train%-battery%-input") then
                recover_input_energy(accumulator)
                destroy_if_valid(accumulator)
            end
        end
        record.energy = math.max(0, tonumber(record.energy) or 0) + recovered_input_energy

        destroy_if_valid(record.output_interface)
        destroy_if_valid(record.output_accumulator)
        local outer_surface = anchor_wagon.entity.surface
        local output_area = {
            { external_pos.x - 0.25, external_pos.y - 0.25 },
            { external_pos.x + 0.25, external_pos.y + 0.25 },
        }
        for _, legacy_output_name in ipairs({
            TRAIN_POWER_OUTPUT_ACCUMULATOR_NAME,
            train_interiors.power_bridge_config.legacy_output_interface_name,
        }) do
            for _, legacy_output in pairs(outer_surface.find_entities_filtered {
                name = legacy_output_name,
                area = output_area,
                force = force,
            }) do
                destroy_if_valid(legacy_output)
            end
        end

        record.input_interface = nil
        record.output_interface = nil
        record.input_accumulator = nil
        record.output_accumulator = nil
        record.inside_pole = nil
        record.input_accumulators = {}
        record.inside_poles = {}
        record.inside_bus_poles = {}
        record.internal_input_version = TRAIN_POWER_INTERNAL_INPUT_VERSION
        record.bridge_version = train_interiors.power_bridge_config.version
        record.output_reserved = 0
        record.last_output_energy = 0
    end

    local capacity, researched_level = train_power_capacity_j(record, force)
    record.level = researched_level
    record.energy = math.max(0, math.min(tonumber(record.energy) or 0, capacity))
    if capacity <= 0 then
        record.energy = 0
        record.output_reserved = 0
        record.last_output_energy = 0
        record.charge_enabled = false
        destroy_if_valid(record.input_interface)
        destroy_if_valid(record.input_accumulator)
        destroy_if_valid(record.inside_pole)
        destroy_entity_table(record.input_accumulators)
        destroy_entity_table(record.inside_poles)
        destroy_entity_table(record.inside_bus_poles)
        destroy_if_valid(record.output_interface)
        destroy_if_valid(record.output_accumulator)
        destroy_if_valid(record.output_pole)
        train_interiors._destroy_train_power_range_render(record)
        record.input_interface = nil
        record.input_accumulator = nil
        record.inside_pole = nil
        record.input_accumulators = {}
        record.inside_poles = {}
        record.inside_bus_poles = {}
        record.output_interface = nil
        record.output_accumulator = nil
        record.output_pole = nil
        return record
    end

    -- Keep old per-wagon test matrices empty. The single input-only interface
    -- is covered only by the visible Main Locomotive substation.
    destroy_entity_table(record.input_accumulators)
    record.input_accumulators = {}

    local input_pos = train_power_internal_position_for_wagon(anchor_wagon)
    local input_name = train_power_input_name_for_level(researched_level)
    local should_have_input_charger = valid(anchor_wagon.locomotive_substation)
        and (record.charge_enabled ~= false)
        and ((tonumber(record.energy) or 0) < capacity)
    if should_have_input_charger then
        local input = ensure_hidden_train_power_entity(record, "input_interface", surface, input_name, input_pos, force)
        if valid(input) then
            pcall(function() input.disabled_by_script = false end)
        end
    else
        -- Disconnect the input-only interface while hysteresis pauses charging,
        -- so a full train battery draws exactly 0 W from the interior network.
        destroy_if_valid(record.input_interface)
        record.input_interface = nil
    end

    -- No hidden interior pole or relay is allowed to survive this version.
    destroy_if_valid(record.inside_pole)
    record.inside_pole = nil

    if record.output_range_version ~= train_interiors.power_range_config.range_version then
        -- Recreate once so every old save drops stretched/automatic copper
        -- connections left by the removed pre-2.0 neighbour API.
        destroy_if_valid(record.output_pole)
        record.output_pole = nil
        record.output_range_version = train_interiors.power_range_config.range_version
    end

    -- A zero-area pole must exist before the interface is created/teleported,
    -- otherwise Factorio can leave that interface outside the electric network.
    local output_pole = ensure_hidden_train_power_entity(record, "output_pole", anchor_wagon.entity.surface, TRAIN_POWER_OUTPUT_POLE_NAME, external_pos, force)
    local output_name = train_interiors._train_power_output_name_for_level(researched_level)
    if valid(record.output_interface) and (record.output_interface.name ~= output_name
        or record.output_interface.surface ~= anchor_wagon.entity.surface
        or record.output_interface.force ~= force
        or record.output_connection_version ~= 1
        or (valid(output_pole) and output_pole.electric_network_id
            and record.output_interface.electric_network_id ~= output_pole.electric_network_id)) then
        train_interiors._settle_train_power_output(record, record.output_interface, record.output_reserved)
        destroy_if_valid(record.output_interface)
        record.output_interface = nil
    end
    local output = ensure_hidden_train_power_entity(
        record,
        "output_interface",
        anchor_wagon.entity.surface,
        output_name,
        external_pos,
        force
    )

    -- Prototype buffer-size changes do not resize an ElectricEnergyInterface
    -- that already exists in a save. Repair that one runtime property in place
    -- exactly once, without destroying/recreating the bridge or running the
    -- battery migration again. The target equals the energy staged during one
    -- normal 15-tick sync window, so discharge rate and available energy are
    -- unchanged while the network GUI reports 150 / 150 MJ at level 6.
    if valid(output)
        and record.output_buffer_runtime_version ~= train_interiors.power_bridge_config.output_buffer_runtime_version then
        local target_output_buffer_j = train_power_output_rate_mw_for_level(researched_level)
            * TRAIN_POWER_J_PER_MJ
            * train_interiors.power_bridge_config.sync_interval_ticks / 60
        local repaired = pcall(function()
            output.electric_buffer_size = target_output_buffer_j
            if (tonumber(output.energy) or 0) > target_output_buffer_j then
                output.energy = target_output_buffer_j
            end
        end)
        if repaired then
            record.output_buffer_runtime_version = train_interiors.power_bridge_config.output_buffer_runtime_version
        end
    end

    if valid(output) then record.output_connection_version = 1 end

    train_interiors._connect_hidden_pole_to_player_poles(
        output_pole, anchor_wagon.entity.position, train_interiors.power_range_config.half_size, record)
    if valid(output) and valid(output_pole) then
        train_interiors._ensure_train_power_range_render(record, anchor_wagon.entity)
    else
        train_interiors._destroy_train_power_range_render(record)
    end

    -- The interface buffers are only one-way transfer windows. Scripted energy
    -- in record.energy is the sole authoritative Train Battery storage.
    if valid(output) then pcall(function() output.disabled_by_script = false end) end

    return record
end

ensure_all_train_power_entities = function()
    local seen = {}
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and wagon.surface and wagon.surface.valid and is_train_surface(wagon.surface) and not seen[wagon.surface.name] then
            seen[wagon.surface.name] = true
            ensure_train_power_entities_for_surface(wagon.surface)
        end
    end
end

cleanup_train_power_for_surface = function(surface_name)
    if not surface_name then return end
    local s = state()
    local record = s.train_power and s.train_power[surface_name]
    if not record then return end
    destroy_if_valid(record.input_interface)
    destroy_if_valid(record.input_accumulator)
    destroy_if_valid(record.inside_pole)
    destroy_entity_table(record.input_accumulators)
    destroy_entity_table(record.inside_poles)
    destroy_entity_table(record.inside_bus_poles)
    destroy_if_valid(record.output_interface)
    destroy_if_valid(record.output_accumulator)
    destroy_if_valid(record.output_pole)
    train_interiors._destroy_train_power_range_render(record)
    record.inside_bus_poles = nil
    s.train_power[surface_name] = nil
end

local function update_train_power_charge_mode(record, capacity)
    if not record then return false end
    capacity = tonumber(capacity) or 0
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
        -- Hysteresis high mark: once the scripted train battery reaches 100%,
        -- remove/disable the hidden interior chargers so the train's interior
        -- power grid is not kept under constant charging load.
        if energy >= capacity * TRAIN_POWER_CHARGE_STOP_RATIO then
            record.charge_enabled = false
        end
    else
        -- Hysteresis low mark: stay on the train battery until it drops to 25%,
        -- then reconnect the hidden interior chargers and refill back to 100%.
        if energy <= capacity * TRAIN_POWER_CHARGE_START_RATIO then
            record.charge_enabled = true
        end
    end

    return record.charge_enabled ~= previous
end

local function sync_train_power_surface(surface)
    local record = ensure_train_power_entities_for_surface(surface)
    if not record then return end
    local anchor_wagon = train_power_anchor_wagon(surface)
    local force = anchor_wagon and valid(anchor_wagon.entity) and anchor_wagon.entity.force or nil
    local capacity, level = train_power_capacity_j(record, force)
    record.level = level
    record.energy = math.max(0, math.min(tonumber(record.energy) or 0, capacity))
    if capacity <= 0 then
        record.energy = 0
        record.output_reserved = 0
        record.last_output_energy = 0
        record.last_charge_rate_mw = 0
        record.last_charge_sample_tick = game and game.tick or record.last_charge_sample_tick
        record.charge_enabled = false
        return
    end

    -- Settle only the small amount staged in the output-only interface. Because
    -- its prototype input_flow_limit is 0 W, outside generation cannot increase
    -- this buffer or charge the scripted Train Battery in reverse.
    local output = record.output_interface
    train_interiors._settle_train_power_output(record, output, record.output_reserved)
    record.energy = math.max(0, math.min(record.energy, capacity))

    local absorbed_this_sync = 0
    local input = record.input_interface
    if valid(input) then
        local charged = math.max(0, tonumber(input.energy) or 0)
        if record.charge_enabled and charged > 0 and record.energy < capacity then
            local accepted = math.min(charged, capacity - record.energy)
            record.energy = record.energy + accepted
            absorbed_this_sync = absorbed_this_sync + accepted
        end
        pcall(function() input.energy = 0 end)
        pcall(function() input.disabled_by_script = not (record.charge_enabled and record.energy < capacity) end)
    end

    local now_tick = game and game.tick or nil
    if record.charge_enabled and absorbed_this_sync > 0 then
        local last_tick = tonumber(record.last_charge_sample_tick) or now_tick
        local elapsed_ticks = 15
        if now_tick and last_tick and now_tick > last_tick then
            elapsed_ticks = now_tick - last_tick
        end
        if elapsed_ticks <= 0 then elapsed_ticks = 15 end
        record.last_charge_rate_mw = (absorbed_this_sync * 60 / elapsed_ticks) / TRAIN_POWER_J_PER_MJ
        record.last_charge_sample_tick = now_tick or record.last_charge_sample_tick
    elseif not record.charge_enabled or record.energy >= capacity
        or (now_tick and tonumber(record.last_charge_sample_tick)
            and now_tick > tonumber(record.last_charge_sample_tick)) then
        record.last_charge_rate_mw = 0
        record.last_charge_sample_tick = now_tick or record.last_charge_sample_tick
    end

    record.energy = math.max(0, math.min(record.energy, capacity))
    if update_train_power_charge_mode(record, capacity) then
        ensure_train_power_entities_for_surface(surface)
        output = record.output_interface
    end

    -- Stage at most one normal sync interval at the established output rate.
    -- This output shares secondary-output priority with exterior generators;
    -- native distribution also lets it charge exterior accumulators.
    local output_rate_w = train_power_output_rate_mw_for_level(level) * TRAIN_POWER_J_PER_MJ
    local staged_energy = math.min(
        record.energy,
        output_rate_w * train_interiors.power_bridge_config.sync_interval_ticks / 60
    )
    if valid(output) then
        pcall(function() output.energy = staged_energy end)
        record.output_reserved = staged_energy
        record.last_output_energy = staged_energy
    else
        record.output_reserved = 0
        record.last_output_energy = 0
    end
end

sync_train_power = function()
    local seen = {}
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and wagon.surface and wagon.surface.valid and is_train_surface(wagon.surface) and not seen[wagon.surface.name] then
            seen[wagon.surface.name] = true
            sync_train_power_surface(wagon.surface)
        end
    end
end

local function fluid_port_for_entity(entity)
    if not train_interiors._is_fluid_transfer_tank(entity) then return nil, nil end
    local s = state()
    for _, wagon in pairs(s.wagons or {}) do
        if valid(wagon.entity) and wagon.entity.type == "fluid-wagon" then
            for _, tank in pairs(wagon.transfer_entities or {}) do
                if valid(tank) and tank.unit_number == entity.unit_number then
                    return wagon, fluid_tank_role(wagon, tank)
                end
            end
        end
    end
    return nil, nil
end

local function destroy_render_handle(handle)
    if not handle then return end
    if type(handle) == "table" then
        -- Main Locomotive status uses a small metadata record so its existing
        -- objects can be refreshed without destroying and recreating the box.
        -- Every older/other hover label remains a plain array of render ids.
        local render_ids = handle.render_ids or handle
        for _, render_id in pairs(render_ids) do
            local obj = rendering.get_object_by_id(render_id)
            if obj then obj.destroy() end
        end
        return
    end
    local obj = rendering.get_object_by_id(handle)
    if obj then obj.destroy() end
end

local function clear_selected_port_labels(player)
    if not (player and player.valid) then return end
    local s = state()
    local render_sets = {
        s.selected_fluid_port_render,
        s.selected_cargo_port_render,
        s.selected_garden_port_render,
        s.selected_power_substation_render,
        s.selected_train_battery_render,
    }
    for _, render_set in pairs(render_sets) do
        local old_render_handle = render_set and render_set[player.index]
        if old_render_handle then
            destroy_render_handle(old_render_handle)
            render_set[player.index] = nil
        end
    end
end

local function clear_selected_train_battery_label(player)
    if not (player and player.valid) then return end
    local render_set = state().selected_train_battery_render
    local old_render_handle = render_set and render_set[player.index]
    if old_render_handle then
        destroy_render_handle(old_render_handle)
        render_set[player.index] = nil
    end
end

local function format_train_power_number(value)
    local n = math.floor((tonumber(value) or 0) + 0.5)
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end
    local s = tostring(n)
    while true do
        local formatted, replacements = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = formatted
        if replacements == 0 then break end
    end
    return sign .. s
end

local function format_train_power_rate_mw(value)
    local n = tonumber(value) or 0
    if n < 0.05 then return "0" end
    if n < 10 then return string.format("%.1f", n) end
    return format_train_power_number(n)
end

local function format_train_battery_status(record)
    if not record then return nil end
    local capacity_j, level = train_power_capacity_j(record)
    if level <= 0 or capacity_j <= 0 then
        return "Train Battery"
            .. "\nNot Installed"
            .. "\nResearch Train Battery Upgrade 1"
            .. "\nPower Export: Disabled"
    end
    local energy_j = math.max(0, math.min(tonumber(record.energy) or 0, capacity_j))
    local energy_mj = energy_j / TRAIN_POWER_J_PER_MJ
    local capacity_mj = capacity_j / TRAIN_POWER_J_PER_MJ
    local percent = math.floor((energy_j * 100 / capacity_j) + 0.5)
    local mode = record.charge_enabled and "Charging" or "Standby"
    return "Train Battery Level " .. tostring(level)
        .. "\nCharge: " .. format_train_power_number(energy_mj) .. " / " .. format_train_power_number(capacity_mj) .. " MJ"
        .. "\nCharge: " .. tostring(percent) .. "%"
        .. "\nCharging Speed: " .. format_train_power_rate_mw(record.last_charge_rate_mw) .. " / " .. format_train_power_number(train_power_charge_rate_mw_for_level(level)) .. " MW"
        .. "\nCharging Mode: " .. mode
end

local function train_shield_pool_status(entity)
    if not (valid(entity) and WAGON_TYPES[entity.type]) then return 0, 0, false, false, 0 end
    local pool = TRAIN_SHIELD.ensure_pool(entity, false)
    if not pool then return 0, 0, false, false, 0 end
    TRAIN_SHIELD.sync_physical_train(entity)
    local now = game and game.tick or 0
    local damaged = (tonumber(pool.health) or 0) < (tonumber(pool.max_health) or 0)
    local waiting = false
    if damaged and ((now - (tonumber(pool.last_damage) or 0)) < TRAIN_SHIELD.repair_delay_ticks) then waiting = true end
    return tonumber(pool.health) or 0, tonumber(pool.max_health) or 0, damaged, waiting, tonumber(pool.carriage_count) or 0
end

local function format_train_shield_status(entity)
    if not (valid(entity) and WAGON_TYPES[entity.type]) then return nil end
    local level = TRAIN_SHIELD.level(entity.force)
    local health, max_health, damaged, waiting, carriage_count = train_shield_pool_status(entity)
    local repair = TRAIN_SHIELD.repair_per_second(level)
    local mode = "Standby"
    if damaged and repair > 0 then
        mode = waiting and "Waiting" or "Repairing"
    elseif damaged then
        mode = "Damaged"
    end
    return "Train Shield Level " .. tostring(level)
        .. "\nTrain Shield: " .. format_train_power_number(health) .. " / " .. format_train_power_number(max_health) .. " HP"
        .. "\nSelf Repair: " .. format_train_power_number(repair) .. " HP/sec"
        .. "\nRepair Mode: " .. mode
        .. "\nLinked Train: " .. format_train_power_number(carriage_count) .. " parts"
end

local function wagon_for_external_locomotive(entity)
    if not (valid(entity) and entity.type == "locomotive" and entity.unit_number) then return nil end
    local wagon = state().wagons[entity.unit_number]
    if wagon and valid(wagon.entity) and wagon.entity.unit_number == entity.unit_number and wagon.surface and wagon.surface.valid then
        return wagon
    end
    return nil
end

local function update_player_train_battery_label(player)
    if not (player and player.valid) then return end
    local selected = player.selected
    local wagon = wagon_for_external_locomotive(selected)
    if not wagon then
        clear_selected_train_battery_label(player)
        return
    end

    -- Battery and Shield status belongs to the one persistent Main Locomotive.
    -- Secondary locomotives keep their normal Factorio hover information and
    -- never duplicate the Main Train status box.
    local main_wagon = train_interiors._main_battery_locomotive_wagon(wagon.surface)
    if not (main_wagon and valid(main_wagon.entity)
        and main_wagon.entity.unit_number == selected.unit_number) then
        clear_selected_train_battery_label(player)
        return
    end

    if sync_train_power_surface then sync_train_power_surface(wagon.surface) end
    local record = train_power_record(wagon.surface)
    local caption = format_train_battery_status(record)
    local shield_caption = format_train_shield_status(selected)
    if caption and shield_caption then
        caption = caption .. "\n" .. shield_caption
    elseif shield_caption then
        caption = shield_caption
    end
    if not caption then
        clear_selected_train_battery_label(player)
        return
    end

    -- Factorio's rendering.draw_text does not reliably display newline characters
    -- as separate lines in world text. Draw the locomotive battery status as
    -- separate text objects so the label is genuinely multi-line in-game.
    local lines = {}
    for line in tostring(caption):gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    if #lines == 0 then return end

    local render_set = state().selected_train_battery_render
    local existing = render_set[player.index]
    if type(existing) == "table"
        and existing.unit_number == selected.unit_number
        and type(existing.render_ids) == "table"
        and type(existing.text_ids) == "table"
        and #existing.text_ids == #lines then
        local valid_objects = true
        for _, render_id in ipairs(existing.render_ids) do
            local object = rendering.get_object_by_id(render_id)
            if not (object and object.valid) then
                valid_objects = false
                break
            end
        end
        if valid_objects then
            for i, render_id in ipairs(existing.text_ids) do
                local text_object = rendering.get_object_by_id(render_id)
                if not (text_object and text_object.valid and text_object.type == "text") then
                    valid_objects = false
                    break
                end
                text_object.text = lines[i]
            end
        end
        if valid_objects then
            -- Keep the existing panel alive and update it in place. Avoiding a
            -- once-per-second destroy/recreate cycle prevents visible blinking.
            for _, render_id in ipairs(existing.render_ids) do
                local object = rendering.get_object_by_id(render_id)
                if object and object.valid then object.time_to_live = 90 end
            end
            return
        end
    end

    clear_selected_train_battery_label(player)

    local render_ids = {}
    local text_ids = {}
    -- Put the existing player-local yellow status text on an opaque grey world
    -- panel anchored to the selected Main Locomotive. This keeps the familiar
    -- hover behaviour while separating the text from terrain, lamps, wires and
    -- rolling-stock graphics. The nearby Ctrl+Enter screen prompt is untouched.
    local box_left = -7.25
    local box_right = 7.25
    local box_top = -9.55
    local box_bottom = -0.20
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

    -- Use Factorio's entity-target-with-offset form. The older target + target_offset
    -- form can collapse multiple text objects onto the same point for locomotive
    -- selection labels, which made all battery lines overlap.
    local base_y = -8.75
    local line_spacing = 0.85
    for i, line in ipairs(lines) do
        local render_obj = rendering.draw_text {
            text = line,
            surface = selected.surface,
            target = { entity = selected, offset = { 0, base_y + ((i - 1) * line_spacing) } },
            color = { r = 1.0, g = 0.82, b = 0.15, a = 1 },
            scale = 0.95,
            font = "default-large-bold",
            alignment = "center",
            -- The rectangle is measured in world tiles, so the text must scale
            -- with that same world panel at every camera zoom level.
            scale_with_zoom = false,
            players = { player.index },
            time_to_live = 90,
        }
        if render_obj then
            render_ids[#render_ids + 1] = render_obj.id
            text_ids[#text_ids + 1] = render_obj.id
        end
    end

    if #render_ids > 0 then
        state().selected_train_battery_render[player.index] = {
            unit_number = selected.unit_number,
            render_ids = render_ids,
            text_ids = text_ids,
        }
    end
end

local function refresh_selected_train_battery_labels()
    for _, player in pairs(game.connected_players or {}) do
        update_player_train_battery_label(player)
    end
end

local function cargo_port_for_entity(entity)
    if not is_cargo_transfer_container(entity) then return nil, nil end
    local s = state()
    for _, wagon in pairs(s.wagons or {}) do
        if valid(wagon.entity) and wagon.entity.type == "cargo-wagon" then
            for _, chest in pairs(wagon.transfer_entities or {}) do
                if valid(chest) and chest.unit_number == entity.unit_number then
                    return wagon, cargo_port_role(wagon, chest)
                end
            end
        end
    end
    return nil, nil
end

function train_interiors._garden_transfer_role_for_entity(entity)
    if not (valid(entity) and entity.unit_number) then return nil end
    for _, garden in pairs(state().gardens or {}) do
        for _, field in ipairs({ "upper_item_input", "lower_item_input" }) do
            local fixture = garden[field]
            if valid(fixture) and fixture.unit_number == entity.unit_number then return "input" end
        end
        for _, field in ipairs({ "upper_item_output", "lower_item_output" }) do
            local fixture = garden[field]
            if valid(fixture) and fixture.unit_number == entity.unit_number then return "output" end
        end
    end
    local cfg = train_interiors.garden_config
    if entity.name == cfg.fluid_input_name then return "input" end
    if entity.name == cfg.fluid_output_name then return "output" end
    return nil
end

function train_interiors._locomotive_power_substation_role(entity)
    if not (valid(entity) and entity.unit_number) then return nil end
    for _, wagon in pairs(state().wagons or {}) do
        local substation = wagon and wagon.locomotive_substation
        if valid(substation) and substation.unit_number == entity.unit_number then
            local force = valid(wagon.entity) and wagon.entity.force or nil
            local main_wagon = force and train_interiors._garden_main_locomotive_wagon(force) or nil
            local is_main = main_wagon and valid(main_wagon.entity) and valid(wagon.entity)
                and main_wagon.entity.unit_number == wagon.entity.unit_number or false
            return is_main and "main" or nil
        end
    end
    return nil
end

local function cargo_port_label_target(wagon, selected_container, role)
    if not (wagon and valid(selected_container)) then return selected_container end
    if selected_container.name == train_interiors.cargo_config.storehouse_name then return selected_container end
    local selected_top = selected_container.position.y < ((wagon.area.left_top.y + wagon.area.right_bottom.y) * 0.5)
    local sum_x, sum_y, count = 0, 0, 0
    for _, chest in pairs(wagon.transfer_entities or {}) do
        if is_cargo_transfer_container(chest) and cargo_port_role(wagon, chest) == role then
            local chest_top = chest.position.y < ((wagon.area.left_top.y + wagon.area.right_bottom.y) * 0.5)
            if chest_top == selected_top then
                sum_x = sum_x + chest.position.x
                sum_y = sum_y + chest.position.y
                count = count + 1
            end
        end
    end
    if count > 0 then
        return { x = sum_x / count, y = sum_y / count }
    end
    return selected_container
end

local function draw_port_label(player, selected, caption, color, target, target_offset, render_store_name)
    local render_obj = rendering.draw_text {
        text = caption,
        surface = selected.surface,
        target = target or selected,
        target_offset = target_offset or { 0, -2.75 },
        color = color,
        scale = 1.25,
        font = "default-large-bold",
        alignment = "center",
        scale_with_zoom = true,
        players = { player.index },
        time_to_live = 60 * 60,
    }
    if render_obj then
        state()[render_store_name][player.index] = render_obj.id
    end
end

function train_interiors._draw_selected_power_substation_label(player, selected, role)
    if not (player and player.valid and valid(selected) and role == "main") then return end
    local lines = {
        { text = { "the-cave-train-power.main-label" }, color = { r = 1.0, g = 0.78, b = 0.12, a = 1 }, scale = 1.05 },
        { text = { "the-cave-train-power.main-sublabel" }, color = { r = 1.0, g = 0.92, b = 0.55, a = 1 }, scale = 0.82 },
    }
    local render_ids = {}
    for i, line in ipairs(lines) do
        local object = rendering.draw_text {
            text = line.text,
            surface = selected.surface,
            target = { entity = selected, offset = { 0, -2.35 + ((i - 1) * 0.82) } },
            color = line.color,
            scale = line.scale,
            font = "default-large-bold",
            alignment = "center",
            vertical_alignment = "middle",
            scale_with_zoom = true,
            players = { player.index },
            time_to_live = 60 * 60,
        }
        if object then render_ids[#render_ids + 1] = object.id end
    end
    if #render_ids > 0 then
        state().selected_power_substation_render[player.index] = render_ids
    end
end

function train_interiors.on_selected_entity_changed(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    clear_selected_port_labels(player)

    local selected = player.selected

    if selected and selected.valid and selected.type == "locomotive" then
        update_player_train_battery_label(player)
        return
    end

    local power_substation_role = train_interiors._locomotive_power_substation_role(selected)
    if power_substation_role then
        train_interiors._draw_selected_power_substation_label(player, selected, power_substation_role)
        return
    end

    local _, fluid_role = fluid_port_for_entity(selected)
    if fluid_role then
        local caption = (fluid_role == "export") and "Only Export" or "Only Import"
        local color = (fluid_role == "export") and { r = 1, g = 0.78, b = 0.25, a = 1 } or { r = 0.35, g = 0.85, b = 1, a = 1 }
        local label_y = selected.name == train_interiors.fluid_config.tank_name and -3.75 or -2.75
        draw_port_label(player, selected, caption, color, selected, { 0, label_y }, "selected_fluid_port_render")
        return
    end

    local cargo_wagon, cargo_role = cargo_port_for_entity(selected)
    if cargo_role then
        local caption = (cargo_role == "export") and "Only Export" or "Only Import"
        local color = (cargo_role == "export") and { r = 1, g = 0.78, b = 0.25, a = 1 } or { r = 0.35, g = 0.85, b = 1, a = 1 }
        local label_target = cargo_port_label_target(cargo_wagon, selected, cargo_role)
        local label_y = selected.name == train_interiors.cargo_config.storehouse_name and -3.5 or -1.75
        draw_port_label(player, selected, caption, color, label_target, { 0, label_y }, "selected_cargo_port_render")
        return
    end

    local garden_role = train_interiors._garden_transfer_role_for_entity(selected)
    if garden_role then
        local caption = (garden_role == "output")
            and { "the-cave-train-garden.output-label" }
            or { "the-cave-train-garden.input-label" }
        local color = (garden_role == "output")
            and { r = 1, g = 0.78, b = 0.25, a = 1 }
            or { r = 0.35, g = 0.85, b = 1, a = 1 }
        local label_y = selected.name == train_interiors.garden_config.item_storebox_name and -2.75 or -1.75
        draw_port_label(player, selected, caption, color, selected, { 0, label_y },
            "selected_garden_port_render")
    end
end

local function dist_sq(a, b)
    if not (a and b) then return 999999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return dx * dx + dy * dy
end

local function check_exit_door_proximity()
    -- Legacy no-op. Physical car doors were removed in 2.1.58.
    -- Entry and exit are handled by Ctrl+Enter.
    return
end

function train_interiors._rebuild_train_interiors_for_force(force)
    if not (force and force.valid) then return end
    local seen = {}
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and valid(wagon.entity) and wagon.entity.force == force then
            local key = "entity-" .. tostring(wagon.entity.unit_number)
            if wagon.entity.train and wagon.entity.train.valid and wagon.entity.train.carriages and wagon.entity.train.carriages[1] then
                key = "train-" .. tostring(wagon.entity.train.carriages[1].unit_number)
            end
            if not seen[key] then
                seen[key] = true
                rebuild_train_for_entity(wagon.entity)
            end
        end
    end
    chart_all_train_interiors()
end

function train_interiors.on_research_finished(event)
    if not (event and event.research and event.research.name) then return end
    local name = event.research.name
    local power_changed = name:find(TRAIN_POWER_TECH_PREFIX, 1, true) ~= nil
    local shield_changed = name:find(TRAIN_SHIELD.prefix, 1, true) ~= nil
    local interior_changed = name:find(TRAIN_INTERIOR_EXPANSION.prefix, 1, true) ~= nil
    local main_train_changed = name:find(train_interiors.main_train_config.prefix, 1, true) ~= nil
    local garden_changed = train_interiors.garden_config and name:find(train_interiors.garden_config.prefix, 1, true) ~= nil
    if not power_changed and not shield_changed and not interior_changed and not main_train_changed and not garden_changed then return end
    if shield_changed and train_interiors.apply_train_shield_to_all then
        train_interiors.apply_train_shield_to_all(true)
        refresh_selected_train_battery_labels()
    end
    if power_changed then
        ensure_all_train_power_entities()
        refresh_selected_train_battery_labels()
    end
    if interior_changed or main_train_changed then
        train_interiors._rebuild_train_interiors_for_force(event.research.force)
    end
    if garden_changed then
        train_interiors.ensure_garden_room(event.research.force)
        repaint_all_train_rooms()
        chart_all_train_interiors()
    end
end

function train_interiors.on_tick(event)
    if active() and event.tick % 60 == 0 then train_interiors._retry_removed_wagon_cleanup() end
    if not active() then return end
    if event.tick % train_interiors.pollution_config.sync_ticks == 0 then
        train_interiors._sync_pollution()
    end
    if event.tick % 15 == 0 then
        for unit, wagon in pairs(state().wagons) do
            if not valid(wagon.entity) then
                state().wagons[unit] = nil
            else
                sync_cargo(wagon)
                sync_fluid(wagon)
            end
        end
        if sync_train_power then sync_train_power() end
        if train_interiors._sync_all_garden_transfers then train_interiors._sync_all_garden_transfers() end
    end
    if event.tick % 30 == 0 and train_interiors._update_train_entry_prompts then
        train_interiors._update_train_entry_prompts()
    end
    if event.tick % 30 == 0 then
        train_interiors.wave_defense.on_tick(event)
    end
    if event.tick % 60 == 0 then
        if train_interiors.tick_train_shield_self_repair then train_interiors.tick_train_shield_self_repair(event.tick) end
        if auto_couple_nearby_trains then auto_couple_nearby_trains() end
        train_interiors.update_minimaps()
        refresh_selected_train_battery_labels()
    end
end

local function draw_minimap(player, wagon)
    if not (valid(player) and wagon and valid(wagon.entity)) then return end
    local ps = get_player_state(player)
    local map_size = tonumber(ps.map_size) or 220
    -- Keep the train outside view compact. Old saves may have a larger stored
    -- map size from middle-click resizing, so clamp it back to a safe range.
    if map_size < 200 then map_size = 200 end
    if map_size > 260 then map_size = 260 end
    ps.map_size = map_size
    local zoom = tonumber(ps.zoom) or 0.50
    -- Old saves used a wider zoom, which often showed empty black charted space.
    if zoom < 0.45 then zoom = 0.45 end
    if zoom > 2 then zoom = 2 end
    ps.zoom = zoom
    local frame_width = map_size + 20
    local frame = player.gui.left["the_cave_train_minimap"]
    if not frame then
        frame = player.gui.left.add { type = "frame", name = "the_cave_train_minimap", direction = "vertical", caption = "Train outside view" }
    end

    -- Keep the train outside view compact. Without fixed frame sizing the left
    -- GUI can stretch across the screen and leaves a large empty panel beside
    -- the camera, which is wasted space inside the train interior.
    frame.style.minimal_width = frame_width
    frame.style.maximal_width = frame_width
    pcall(function() frame.style.natural_width = frame_width end)
    pcall(function() frame.style.horizontally_stretchable = false end)
    pcall(function() frame.style.horizontally_squashable = false end)

    local controls = frame["the_cave_train_controls"]
    if controls and controls.valid then controls.destroy() end

    local camera = frame["the_cave_train_camera"]
    if not camera then
        camera = frame.add {
            type = "camera",
            name = "the_cave_train_camera",
            surface_index = wagon.entity.surface.index,
            position = wagon.entity.position,
            zoom = zoom,
            tooltip = "Left click: zoom in | Right click: zoom out | Middle click: resize",
        }
    else
        camera.surface_index = wagon.entity.surface.index
        camera.position = wagon.entity.position
        camera.zoom = zoom
    end
    camera.style.minimal_width = map_size
    camera.style.minimal_height = map_size
    camera.style.maximal_width = map_size
    camera.style.maximal_height = map_size
    pcall(function() camera.style.natural_width = map_size end)
    pcall(function() camera.style.natural_height = map_size end)
end

function train_interiors.kill_minimap(player)
    if not valid(player) then return end
    local frame = player.gui.left["the_cave_train_minimap"]
    if frame then frame.destroy() end
end

local function wagon_for_surface(surface)
    if not is_train_surface(surface) then return nil end
    for _, wagon in pairs(state().wagons) do
        if wagon.surface and wagon.surface.valid and wagon.surface.name == surface.name then return wagon end
    end
    return nil
end

local function wagon_for_player_surface(player)
    if not (player and player.valid and is_train_surface(physical.surface(player))) then return nil end
    local ps = get_player_state(player)
    if ps.last_wagon_unit then
        local wagon = state().wagons[ps.last_wagon_unit]
        if wagon and wagon.surface and wagon.surface.valid and wagon.surface.name == physical.surface(player).name then return wagon end
    end
    return wagon_for_surface(physical.surface(player))
end

-- Return the current exterior recovery point for this player's Main Train.
-- The lookup is performed when recovery is needed, never when the player
-- disconnects, so a train that moves or changes surface during the five-minute
-- grace period is followed to its live position. The deterministic fallback
-- also survives rolling-stock unit-number changes by selecting another
-- registered Main Train part belonging to the same force.
function train_interiors.get_player_recovery_target(player)
    if not active() or not (player and player.valid and player.force and player.force.valid) then return nil end

    local s = state()
    local ps = s.players[player.index]
    local preferred_unit = ps and ps.last_wagon_unit or nil
    if preferred_unit and s.main_train_units[preferred_unit] then
        local preferred = s.wagons[preferred_unit]
        local entity = preferred and preferred.entity
        if valid(entity) and entity.force == player.force and entity.surface and entity.surface.valid then
            local position = safe_land_position(entity.surface, entity.position, 64, "character")
            if position then
                return { surface = entity.surface, position = position, unit_number = entity.unit_number }
            end
        end
    end

    local units = {}
    for unit in pairs(s.main_train_units or {}) do
        units[#units + 1] = unit
    end
    table.sort(units)

    local fallback_entity = nil
    for _, unit in ipairs(units) do
        local wagon = s.wagons[unit]
        local entity = wagon and wagon.entity
        if valid(entity) and entity.force == player.force and entity.surface and entity.surface.valid then
            if entity.type == "locomotive" then
                fallback_entity = entity
                break
            end
            fallback_entity = fallback_entity or entity
        end
    end

    if not valid(fallback_entity) then return nil end
    local position = safe_land_position(fallback_entity.surface, fallback_entity.position, 64, "character")
    if not position then return nil end
    return {
        surface = fallback_entity.surface,
        position = position,
        unit_number = fallback_entity.unit_number,
    }
end

local function locomotive_for_train_surface(surface)
    if not is_train_surface(surface) then return nil end
    for _, wagon in pairs(state().wagons) do
        if wagon.surface and wagon.surface.valid and wagon.surface.name == surface.name and valid(wagon.entity) and wagon.entity.type == "locomotive" then
            return wagon
        end
    end
    return nil
end

function train_interiors._garden_stage(force)
    if not (force and force.valid and force.technologies) then return 0 end
    local cfg = train_interiors.garden_config
    local level = 0
    for i = 1, cfg.max_level do
        local tech = force.technologies[cfg.prefix .. i]
        if tech and tech.researched then level = i end
    end
    return level
end

function train_interiors._garden_surface_name(force)
    if not (force and force.valid) then return nil end
    return train_interiors.garden_config.surface_prefix .. tostring(force.index or force.name)
end

function train_interiors._is_garden_surface(surface)
    if not (surface and surface.valid) then return false end
    return surface.name:sub(1, #train_interiors.garden_config.surface_prefix) == train_interiors.garden_config.surface_prefix
end

function train_interiors._garden_area(stage)
    local cfg = train_interiors.garden_config
    local half = cfg.stage_half_sizes[math.max(1, math.min(cfg.max_level, tonumber(stage) or 1))] or cfg.stage_half_sizes[1]
    return { left_top = { x = -half, y = -half }, right_bottom = { x = half, y = half } }
end

function train_interiors._garden_center_bounds()
    local half = train_interiors.garden_config.center_size * 0.5
    return math.floor(-half), math.floor(half), math.floor(-half), math.floor(half)
end

function train_interiors._garden_water_bounds()
    local cfg = train_interiors.garden_config
    local _, _, core_top = train_interiors._garden_center_bounds()
    local water_left = math.floor(-(cfg.water_width * 0.5))
    local water_right = water_left + cfg.water_width
    -- Keep the pond two tiles inside the green 18x18 core, matching the
    -- established Garden placement while changing its box to exactly 12x4.
    local water_top = core_top - cfg.water_depth + 2
    local water_bottom = water_top + cfg.water_depth
    return water_left, water_right, water_top, water_bottom
end

function train_interiors._garden_substation_island_bounds()
    local cfg = train_interiors.garden_config
    local left, right, top, bottom = train_interiors._garden_water_bounds()
    local size = math.max(2, tonumber(cfg.substation_island_size) or 2)
    local island_left = math.floor(((left + right) - size) * 0.5)
    local island_top = math.floor(((top + bottom) - size) * 0.5)
    return island_left, island_left + size, island_top, island_top + size
end

function train_interiors._garden_portal_bounds()
    -- Exact 2x2 lower portal, centred on the established 4x4 opening so the
    -- route does not move when its active area and artwork become smaller.
    return -1, 1, 5, 7
end

function train_interiors._garden_landing_pad_bounds()
    -- Match the train's fixed 4x4 grey center entry pad exactly.
    return -2, 2, -2, 2
end

function train_interiors._locomotive_garden_entry_bounds(area)
    local c = area_center(area)
    local y_shift = tonumber(train_interiors.garden_config.upper_portal_y_shift) or 0
    -- Keep the exact 2x2 opening while moving only the upper portal downward.
    return math.floor(c.x - 1), math.floor(c.x + 1),
        math.floor(c.y + 5 + y_shift), math.floor(c.y + 7 + y_shift)
end

function train_interiors._garden_transfer_positions(left, right, top, bottom, y_offset)
    local cfg = train_interiors.garden_config
    local center_x = (left + right) * 0.5
    local center_y = ((top + bottom) * 0.5) + (tonumber(y_offset) or 0)
    return {
        -- The fluid endpoints retain their established horizontal coordinates.
        -- Each Store Box sits four tile centres farther outward, matching its
        -- four-tile artwork and leaving one visibly empty tile beside the Pipe.
        item_input = { x = center_x + cfg.item_input_x_offset, y = center_y },
        fluid_input = { x = center_x + cfg.fluid_input_x_offset, y = center_y },
        item_output = { x = center_x + cfg.item_output_x_offset, y = center_y },
        fluid_output = { x = center_x + cfg.fluid_output_x_offset, y = center_y },
    }
end

function train_interiors._garden_storebox_pad_contains(x, y)
    local cfg = train_interiors.garden_config
    local left, right, top, bottom = train_interiors._garden_portal_bounds()
    local center_x = (left + right) * 0.5
    local center_y = (top + bottom) * 0.5
    local half = cfg.item_storebox_visual_size * 0.5
    local pad_top = math.floor(center_y - half)
    local pad_bottom = math.floor(center_y + half)
    local input_left = math.floor(center_x + cfg.item_input_x_offset - half)
    local input_right = math.floor(center_x + cfg.item_input_x_offset + half)
    local output_left = math.floor(center_x + cfg.item_output_x_offset - half)
    local output_right = math.floor(center_x + cfg.item_output_x_offset + half)
    return y >= pad_top and y < pad_bottom
        and ((x >= input_left and x < input_right)
            or (x >= output_left and x < output_right))
end

function train_interiors._position_in_bounds(position, left, right, top, bottom)
    return position and position.x >= left and position.x < right and position.y >= top and position.y < bottom
end

function train_interiors._garden_for_surface(surface)
    if not (surface and surface.valid) then return nil end
    for _, garden in pairs(state().gardens or {}) do
        if garden.surface_name == surface.name then return garden end
    end
    return nil
end

local function garden_void_chunk_key(position)
    if not position then return nil end
    return tostring(math.floor(position.x)) .. ":" .. tostring(math.floor(position.y))
end

function train_interiors._garden_chunk_void_is_current(garden, surface, position)
    local key = garden_void_chunk_key(position)
    return key
        and garden
        and surface
        and surface.valid
        and garden.voided_surface_index == surface.index
        and garden.voided_chunk_versions
        and garden.voided_chunk_versions[key] == train_interiors.garden_config.void_layout_version
        or false
end

function train_interiors._mark_garden_chunk_voided(garden, surface, position)
    local key = garden_void_chunk_key(position)
    if not (key and garden and surface and surface.valid) then return end
    if garden.voided_surface_index ~= surface.index then
        garden.voided_chunk_versions = {}
        garden.voided_surface_index = surface.index
    end
    garden.voided_chunk_versions = garden.voided_chunk_versions or {}
    garden.voided_chunk_versions[key] = train_interiors.garden_config.void_layout_version
end

function train_interiors._garden_tile_is_layout(garden, x, y)
    if not garden then return false end
    local raw_stage = math.max(0,
        math.min(train_interiors.garden_config.max_level, tonumber(garden.stage) or 0))
    if raw_stage > 0 then
        local area = train_interiors._garden_area(raw_stage)
        local left, right, top, bottom = area_bounds(area)
        return x >= left and x < right and y >= top and y < bottom
    end

    -- Stage 0 exposes the established green center plus the two small green
    -- pads needed beneath the fixed Store Box artwork. Everything else remains
    -- void until Garden research expands the floor.
    local core_left, core_right, core_top, core_bottom =
        train_interiors._garden_center_bounds()
    if x >= core_left and x < core_right and y >= core_top and y < core_bottom then
        return true
    end
    if train_interiors._garden_storebox_pad_contains(x, y) then return true end
    local water_left, water_right, water_top, water_bottom =
        train_interiors._garden_water_bounds()
    return x >= water_left and x < water_right and y >= water_top and y < water_bottom
end

function train_interiors._void_garden_area(surface, area, garden)
    if not (surface and surface.valid and train_interiors._is_garden_surface(surface)
        and area and area.left_top and area.right_bottom) then
        return 0
    end

    local tiles = {}
    local converted = 0
    local function flush()
        if #tiles > 0 then
            -- Never delete a player, machine or fixed Garden fixture while
            -- replacing the terrain beneath it during an existing-save repair.
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
            if not train_interiors._garden_tile_is_layout(garden, x, y) then
                tiles[#tiles + 1] = { name = "out-of-map", position = { x = x, y = y } }
                converted = converted + 1
                if #tiles >= 8192 then flush() end
            end
        end
    end
    flush()
    return converted
end

function train_interiors._void_generated_garden_chunks(surface, garden)
    if not (surface and surface.valid and train_interiors._is_garden_surface(surface)) then
        return 0
    end
    local converted = 0
    for chunk in surface.get_chunks() do
        local left = chunk.x * 32
        local top = chunk.y * 32
        converted = converted + train_interiors._void_garden_area(surface, {
            left_top = { x = left, y = top },
            right_bottom = { x = left + 32, y = top + 32 },
        }, garden)
        train_interiors._mark_garden_chunk_voided(garden, surface, chunk)
    end
    return converted
end

function train_interiors._find_locomotive_wagon_for_force(force)
    if not (force and force.valid) then return nil end
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and valid(wagon.entity) and wagon.entity.type == "locomotive"
            and wagon.entity.force and wagon.entity.force.valid and wagon.entity.force.index == force.index then
            return wagon
        end
    end
    return nil
end

function train_interiors._garden_main_locomotive_on_surface(surface)
    if not (surface and surface.valid and is_train_surface(surface)
        and not train_interiors._is_garden_surface(surface)) then
        return nil
    end
    local force = nil
    for _, wagon in pairs(state().wagons or {}) do
        local entity = wagon and wagon.entity
        if wagon and wagon.surface == surface and valid(entity) and entity.type == "locomotive"
            and entity.force and entity.force.valid then
            force = entity.force
            break
        end
    end
    if not (force and train_interiors._garden_main_locomotive_wagon) then return nil end
    local main = train_interiors._garden_main_locomotive_wagon(force)
    if main and main.surface == surface and valid(main.entity) then return main end
    return nil
end

function train_interiors._find_locomotive_garden_entry_wagon(surface, position)
    if not (surface and surface.valid and position and is_train_surface(surface)) then return nil end
    if train_interiors._is_garden_surface(surface) then return nil end
    local wagon = train_interiors._garden_main_locomotive_on_surface(surface)
    if wagon and wagon.surface == surface and valid(wagon.entity) and wagon.entity.type == "locomotive" then
        local left, right, top, bottom = train_interiors._locomotive_garden_entry_bounds(wagon.area)
        if train_interiors._position_in_bounds(position, left, right, top, bottom) then return wagon end
    end
    return nil
end

function train_interiors._paint_garden_room(garden, force)
    if not (garden and garden.surface_name and force and force.valid) then return end
    local surface = game.surfaces[garden.surface_name]
    if not (surface and surface.valid) then return end

    local raw_stage = math.max(0, math.min(train_interiors.garden_config.max_level, tonumber(garden.stage) or 0))
    -- Stage 0 still uses the Stage 1 bounds as a cleanup canvas so old oversized buildable
    -- floor from older test versions is removed, but the final Stage 0 layout only keeps
    -- the small green box, water, and yellow portal.
    local area = train_interiors._garden_area(math.max(1, raw_stage))
    generate_surface_area(surface, area, 32)

    local floor_tile = tile_or_fallback("refined-concrete", "concrete")
    local center_tile = tile_or_fallback("green-refined-concrete", tile_or_fallback("green-concrete", floor_tile))
    local landing_tile = tile_or_fallback("refined-concrete", floor_tile)
    local yumako_tile = tile_or_fallback("artificial-yumako-soil", tile_or_fallback("natural-yumako-soil", floor_tile))
    local jellynut_tile = tile_or_fallback("artificial-jellynut-soil", tile_or_fallback("natural-jellynut-soil", floor_tile))
    local void_tile = tile_or_fallback("out-of-map", "out-of-map")

    local left, right, top, bottom = area_bounds(area)
    local core_left, core_right, core_top, core_bottom = train_interiors._garden_center_bounds()
    local p_left, p_right, p_top, p_bottom = train_interiors._garden_portal_bounds()
    local landing_left, landing_right, landing_top, landing_bottom = train_interiors._garden_landing_pad_bounds()

    local water_left, water_right, water_top, water_bottom = train_interiors._garden_water_bounds()
    local island_left, island_right, island_top, island_bottom = train_interiors._garden_substation_island_bounds()

    -- Move players to the final grey landing pad before any repaint. This keeps
    -- migrations safe without placing anyone on the automatic portal itself.
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

    local pad = 24
    local paint_left = left - pad
    local paint_right = right + pad
    local paint_top = top - pad
    local paint_bottom = bottom + pad

    local tiles = {}
    local function flush()
        if #tiles > 0 then
            surface.set_tiles(tiles, true)
            tiles = {}
        end
    end

    local function in_bounds(x, y, l, r, t, b)
        return x >= l and x < r and y >= t and y < b
    end

    -- Existing Garden saves may have an Offshore Pump or another player entity
    -- on one of the two newly widened pond columns. Preserve the supporting
    -- tile instead of deleting the entity during the layout migration.
    local function protected_occupant_on_tile(x, y)
        for _, entity in pairs(surface.find_entities_filtered {
            area = { { x, y }, { x + 1, y + 1 } },
        }) do
            if valid(entity)
                and entity.type ~= "character"
                and entity.name ~= "fish"
                and entity.name ~= TRAIN_LOCOMOTIVE_SUBSTATION_NAME
                and entity.name ~= TRAIN_GARDEN_SUBSTATION_NAME then
                return true
            end
        end
        return false
    end

    for x = paint_left, paint_right - 1 do
        for y = paint_top, paint_bottom - 1 do
            local tile = void_tile

            if in_bounds(x, y, island_left, island_right, island_top, island_bottom) then
                local current = surface.get_tile(x, y)
                tile = protected_occupant_on_tile(x, y) and current.name or center_tile
            elseif in_bounds(x, y, water_left, water_right, water_top, water_bottom) then
                local current = surface.get_tile(x, y)
                tile = protected_occupant_on_tile(x, y) and current.name or "water"
            elseif in_bounds(x, y, landing_left, landing_right, landing_top, landing_bottom) then
                tile = landing_tile
            elseif in_bounds(x, y, p_left, p_right, p_top, p_bottom) then
                -- The artwork is rendered above normal core flooring. Keeping
                -- normal floor underneath makes secondary-locomotive cleanup
                -- and transparent sprite corners visually consistent.
                tile = center_tile
            elseif train_interiors._garden_storebox_pad_contains(x, y) then
                -- The Store Box art is visually four tiles wide, so retain a
                -- matching green pad even though its placement prototype uses
                -- the existing compact Industrial Storebox collision footprint.
                tile = center_tile
            elseif in_bounds(x, y, core_left, core_right, core_top, core_bottom) then
                tile = center_tile
            elseif raw_stage > 0 and x >= left and x < right and y >= top and y < bottom then
                if x < 0 then
                    tile = yumako_tile
                else
                    tile = jellynut_tile
                end
            end

            tiles[#tiles + 1] = { name = tile, position = { x = x, y = y } }
            if #tiles >= 20000 then flush() end
        end
    end
    flush()

    pcall(function()
        force.chart(surface, {
            left_top = { x = math.floor(core_left - 8), y = math.floor(water_top - 8) },
            right_bottom = { x = math.ceil(core_right + 8), y = math.ceil(p_bottom + 8) },
        })
    end)
end

train_interiors._garden_infrastructure_fields = {
    "upper_item_input",
    "upper_fluid_input",
    "upper_item_output",
    "upper_fluid_output",
    "lower_item_input",
    "lower_fluid_input",
    "lower_item_output",
    "lower_fluid_output",
    "lower_substation",
}

train_interiors._garden_item_field_names = {
    upper_item_input = true,
    upper_item_output = true,
    lower_item_input = true,
    lower_item_output = true,
}

train_interiors._garden_transfer_direction_fields = {
    "upper_item_input",
    "upper_fluid_input",
    "upper_item_output",
    "upper_fluid_output",
    "lower_item_input",
    "lower_fluid_input",
    "lower_item_output",
    "lower_fluid_output",
}

function train_interiors._capture_garden_transfer_directions(garden)
    if not garden then return end
    garden.infrastructure_directions = garden.infrastructure_directions or {}
    for _, field in pairs(train_interiors._garden_transfer_direction_fields) do
        local entity = garden[field]
        if valid(entity) then garden.infrastructure_directions[field] = entity.direction end
    end
end

function train_interiors._clear_garden_infrastructure_labels(garden)
    if not garden then return end
    for _, id in pairs(garden.infrastructure_label_render_ids or {}) do
        local ok, object = pcall(function() return rendering.get_object_by_id(id) end)
        if ok and object then pcall(function() object.destroy() end) end
    end
    garden.infrastructure_label_render_ids = {}
end

function train_interiors._destroy_garden_portal_renders(garden)
    if not garden then return end
    for _, field in pairs({ "upper_portal_render_id", "lower_portal_render_id" }) do
        local id = garden[field]
        if id then
            local ok, object = pcall(function() return rendering.get_object_by_id(id) end)
            if ok and object then pcall(function() object.destroy() end) end
        end
        garden[field] = nil
    end
end

function train_interiors._destroy_garden_infrastructure(garden)
    if not garden then return end
    train_interiors._clear_garden_infrastructure_labels(garden)
    train_interiors._destroy_garden_portal_renders(garden)
    for _, field in pairs(train_interiors._garden_infrastructure_fields) do
        local entity = garden[field]
        -- Item endpoints may contain player property. Keep their references so
        -- the next infrastructure owner can migrate them into its Store Boxes.
        if not (train_interiors._garden_item_field_names[field] and valid(entity)) then
            if valid(entity) then
                if entity.type == "linked-belt" then
                    pcall(function() entity.disconnect_linked_belts() end)
                end
                pcall(function() entity.destroy() end)
            end
            garden[field] = nil
        end
    end
end

function train_interiors._garden_main_locomotive_wagon(force)
    if not (force and force.valid) then return nil end
    local s = state()
    local selected_unit = s.main_battery_locomotive_units[force.index]
    local fallback = nil
    for _, wagon in pairs(s.wagons or {}) do
        local entity = wagon and wagon.entity
        if valid(entity) and entity.type == "locomotive" and entity.unit_number
            and entity.force and entity.force.valid and entity.force.index == force.index
            and s.main_train_units[entity.unit_number] then
            if entity.unit_number == selected_unit then return wagon end
            if not fallback or entity.unit_number < fallback.entity.unit_number then fallback = wagon end
        end
    end
    if fallback and valid(fallback.entity) then
        s.main_battery_locomotive_units[force.index] = fallback.entity.unit_number
    end
    return fallback
end

-- Public force-local lookup for systems which must follow the live Main
-- Locomotive. It deliberately uses the same immutable Main Train ownership as
-- the Train Battery and never returns a locomotive on an interior surface.
function train_interiors.main_locomotive_for_force(force)
    if not active() or not (force and force.valid) then return nil end
    local wagon = train_interiors._garden_main_locomotive_wagon(force)
    local entity = wagon and wagon.entity
    if not (valid(entity) and entity.type == "locomotive"
        and entity.force == force and entity.surface and entity.surface.valid
        and not is_train_surface(entity.surface)) then
        return nil
    end
    return entity
end

-- Cleanup ownership survives the owning entity. The saved owner is retained
-- through a force merge until the coordinator retires
-- the source force's rooms.
function train_interiors.has_base(force)
    return train_interiors.main_locomotive_for_force(force) ~= nil
end

function train_interiors.base_surface(force)
    local locomotive = train_interiors.main_locomotive_for_force(force)
    return locomotive and locomotive.surface or nil
end

-- Migration can retire a misplaced starter without touching ordinary trains.
-- The caller evacuates and collects rooms before destroying these entities.
function train_interiors.base_entities(force)
    local force_index = type(force) == "number" and force or force and force.index
    if not force_index then return {} end
    local s = state()
    local result = {}
    for unit, wagon in pairs(s.wagons) do
        local entity = wagon and wagon.entity
        local owner = wagon and (wagon.force_index or (valid(entity) and entity.force.index))
        if owner == force_index and s.main_train_units[unit] and valid(entity) then
            result[#result + 1] = entity
        end
    end
    table.sort(result, function(a, b) return a.unit_number < b.unit_number end)
    return result
end

function train_interiors._migrate_force_keys()
    local s = state()
    for _, field in ipairs({ "spawned_forces", "starter_train_centers",
        "starter_layout_normalized_forces", "main_battery_locomotive_units",
        "main_train_capacity_message_tick", "train_layout_warning_tick", "gardens" }) do
        local values = s[field]
        local names = {}
        for key in pairs(values or {}) do
            if type(key) == "string" then names[#names + 1] = key end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local force = game.forces[name]
            if force and force.valid and values[force.index] == nil then
                values[force.index] = values[name]
            end
            values[name] = nil
        end
    end
    for _, wagon in pairs(s.wagons) do
        local entity = wagon and wagon.entity
        if valid(entity) then
            wagon.force_index = entity.force.index
            wagon.exterior_surface_index = entity.surface.index
            wagon.exterior_surface_name = entity.surface.name
            if valid(wagon.surface) then
                wagon.surface_name = wagon.surface.name
                s.surface_owners[wagon.surface.name] = entity.force.index
            end
            local _, aliases = TRAIN_SHIELD.train_key_candidates(entity)
            for _, key in ipairs(aliases) do
                if s.train_shield_pools[key] then s.train_shield_pools[key].force_index = entity.force.index end
            end
        end
    end
    for name in pairs(s.surfaces) do
        if not s.surface_owners[name] then
            local unit = tonumber(name:match("(%d+)$"))
            local wagon = unit and s.wagons[unit]
            local surface = game.surfaces[name]
            if wagon then
                s.surface_owners[name] = wagon.force_index
            elseif valid(surface) then
                -- Old layouts kept their vacated rooms. Their fixtures still
                -- identify the force even after the wagon moved to a new room.
                for _, entity in pairs(surface.find_entities()) do
                    if entity.force ~= game.forces.neutral and entity.force ~= game.forces.enemy then
                        s.surface_owners[name] = entity.force.index
                        break
                    end
                end
            end
        end
    end
    for index, garden in pairs(s.gardens) do s.surface_owners[garden.surface_name] = index end
    for _, center in pairs(s.starter_train_centers) do
        local surface = center.surface_index and game.surfaces[center.surface_index]
        if valid(surface) then center.surface_name = surface.name end
    end
    for unit, record in pairs(s.unclaimed_train_parts) do
        local surface = record.surface_index and game.surfaces[record.surface_index]
        if valid(surface) and record.source == "world" and not s.main_train_units[unit] then
            for _, entity in pairs(surface.find_entities_filtered {
                position = { record.x, record.y }, type = record.type,
            }) do
                if entity.unit_number == unit then entity.force = game.forces.neutral end
            end
        end
    end
end

function train_interiors.owned_surfaces(force)
    local force_index = type(force) == "number" and force or force and force.index
    if not force_index then return {} end
    local s = state()
    local result, seen = {}, {}
    local function add(surface)
        if valid(surface) and not seen[surface.index] then
            seen[surface.index] = true
            result[#result + 1] = surface
        end
    end
    for _, records in ipairs({ s.wagons, s.pending_wagon_cleanup or {} }) do
        for _, wagon in pairs(records) do
            local owner = wagon.force_index or (valid(wagon.entity) and wagon.entity.force.index)
            if owner == force_index then add(wagon.surface) end
        end
    end
    for name, owner in pairs(s.surface_owners) do
        if owner == force_index then add(game.surfaces[name]) end
    end
    local garden = s.gardens[force_index]
    if garden then add(game.surfaces[garden.surface_name]) end
    return result
end

function train_interiors.clear_force(force_index)
    local s = state()
    local units, surface_names = {}, {}
    for _, surface in ipairs(train_interiors.owned_surfaces(force_index)) do
        surface_names[surface.name] = true
    end
    for name, owner in pairs(s.surface_owners) do
        if owner == force_index then surface_names[name] = true end
    end
    for _, records in ipairs({ s.wagons, s.pending_wagon_cleanup or {} }) do
        for unit, wagon in pairs(records) do
            local owner = wagon.force_index or (valid(wagon.entity) and wagon.entity.force.index)
            if owner == force_index then
                units[unit] = true
                for _, door in pairs(wagon.doors or {}) do
                    if valid(door) then s.doors[door.unit_number] = nil end
                end
                records[unit] = nil
            end
        end
    end
    for unit in pairs(units) do
        s.main_train_units[unit] = nil
        s.unclaimed_train_parts[unit] = nil
        s.train_shield_last_damage[unit] = nil
        s.train_shield_applied_level[unit] = nil
        s.train_shield_pools["entity:" .. tostring(unit)] = nil
        s.train_shield_pools["first:" .. tostring(unit)] = nil
    end
    for key, pool in pairs(s.train_shield_pools) do
        if pool.force_index == force_index then s.train_shield_pools[key] = nil end
    end
    for name in pairs(surface_names) do
        cleanup_train_power_for_surface(name)
        s.surfaces[name] = nil
        s.surface_owners[name] = nil
        s.map_void_versions[name] = nil
        s.train_layout_anchor_units[name] = nil
        s.train_shield_pools["surface:" .. name] = nil
    end
    for _, field in ipairs({ "spawned_forces", "starter_train_centers",
        "starter_layout_normalized_forces", "main_battery_locomotive_units",
        "main_train_capacity_message_tick", "train_layout_warning_tick", "gardens" }) do
        if s[field] then s[field][force_index] = nil end
    end
    for player_index, ps in pairs(s.players) do
        local player = game.get_player(player_index)
        local player_force = player and player.valid and cave_teams.player_force(player)
        if units[ps.last_wagon_unit] or units[ps.garden_return_wagon_unit]
            or (player_force and player_force.valid and player_force.index == force_index) then
            ps.last_wagon_unit = nil
            ps.garden_return_wagon_unit = nil
            ps.exit_cooldown_tick = nil
            ps.garden_portal_cooldown_tick = nil
            if player and player.valid then train_interiors.kill_minimap(player) end
        end
    end
end

function train_interiors.sync_force(force)
    if not (active() and force and force.valid) then return end
    -- Our reset has already collected the rooms it will delete. A foreign
    -- research reset keeps the live base and refreshes its research fixtures.
    if cave_teams.is_resetting(force) or storage.the_cave_soft_reset then return end
    for _, wagon in pairs(state().wagons) do
        if valid(wagon.entity) and wagon.entity.force == force then
            train_interiors.apply_train_shield_to_entity(wagon.entity, true)
        end
    end
    train_interiors._rebuild_train_interiors_for_force(force)
    if train_interiors.has_base(force) then train_interiors.ensure_garden_room(force) end
end

function train_interiors.on_entity_cloned(event)
    if not event or not (valid(event.source) and valid(event.destination)) then return end
    local source, destination = event.source, event.destination
    local s = state()
    if not (source.unit_number and destination.unit_number and s.unclaimed_train_parts[source.unit_number]) then return end
    -- Cave warp destinations only receive moved entities. Their records are
    -- relocated by the warp/shield code, while team copies need a second row.
    if destination.surface.name:sub(1, 14) == "the-cave-warp-" then return end
    train_interiors._mark_unclaimed_train_part(destination, s.unclaimed_train_parts[source.unit_number].source)
end

function train_interiors.on_surface_deleted(event)
    local index = event and event.surface_index
    if not index then return end
    local s = state()
    local prefix = tostring(index) .. ":"
    for key in pairs(s.cache_chunks) do
        if key:sub(1, #prefix) == prefix then s.cache_chunks[key] = nil end
    end
    for i = #s.cache_centers, 1, -1 do
        if s.cache_centers[i].surface_index == index then table.remove(s.cache_centers, i) end
    end
    for unit, record in pairs(s.unclaimed_train_parts) do
        if record.surface_index == index then s.unclaimed_train_parts[unit] = nil end
    end
end

-- Cavern rooms must never be opened close enough to erase or trap any part of
-- the live Main Train. Querying an expanded candidate footprint makes the rule
-- scale with the complete connected LuaTrain: every locomotive and wagon owns
-- its own 50-tile safe margin, regardless of train length or direction.
function train_interiors.cave_area_is_safe(surface, area)
    if not active() then return true end
    if not (surface and surface.valid and type(area) == "table"
        and area[1] and area[2]) then
        return false
    end

    local x1, y1 = area[1][1] or area[1].x, area[1][2] or area[1].y
    local x2, y2 = area[2][1] or area[2].x, area[2][2] or area[2].y
    if not (x1 and y1 and x2 and y2) then return false end
    local left, top = math.min(x1, x2), math.min(y1, y2)
    local right, bottom = math.max(x1, x2), math.max(y1, y2)

    local s = state()
    local candidates = surface.find_entities_filtered {
        area = {
            { left - train_interiors.cave_safe_margin, top - train_interiors.cave_safe_margin },
            { right + train_interiors.cave_safe_margin, bottom + train_interiors.cave_safe_margin },
        },
        type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
    }
    for _, carriage in pairs(candidates or {}) do
        if valid(carriage) and carriage.unit_number and WAGON_TYPES[carriage.type] then
            local carriages = carriage.train and carriage.train.valid
                and carriage.train.carriages or { carriage }
            if s.main_train_units[carriage.unit_number]
                or train_interiors._train_contains_main_train(carriages) then
                return false
            end
        end
    end
    return true
end

function train_interiors._garden_render_object(id)
    if not id then return nil end
    local ok, object = pcall(function() return rendering.get_object_by_id(id) end)
    if ok then return object end
    return nil
end

function train_interiors._ensure_garden_portal_render(garden, field, surface, left, right, top, bottom, force)
    if not (garden and field and surface and surface.valid and force and force.valid) then return nil end
    local existing = train_interiors._garden_render_object(garden[field])
    if existing then return existing end

    garden[field] = nil
    local target = { x = (left + right) * 0.5, y = (top + bottom) * 0.5 }
    local ok, object = pcall(function()
        return rendering.draw_sprite {
            sprite = train_interiors.garden_config.portal_sprite_name,
            surface = surface,
            target = target,
            forces = { force },
            draw_on_ground = true,
            only_in_alt_mode = false,
        }
    end)
    if ok and object then garden[field] = object.id end
    return ok and object or nil
end

function train_interiors._same_garden_entity_location(entity, surface, name, position)
    return valid(entity)
        and entity.surface == surface
        and entity.name == name
        -- Some 1x1 prototypes snap script-created positions onto a half-tile
        -- grid. Accept that one-time snap so fixtures are not destroyed and
        -- recreated every sync (the same failure mode fixed for the Display Panel).
        and math.abs(entity.position.x - position.x) <= train_interiors.garden_config.fixture_position_epsilon
        and math.abs(entity.position.y - position.y) <= train_interiors.garden_config.fixture_position_epsilon
end

function train_interiors._protect_garden_fixture(entity, direction)
    if not valid(entity) then return nil end
    pcall(function() entity.destructible = false end)
    pcall(function() entity.minable_flag = false end)
    pcall(function() entity.operable = true end)
    -- Pipe endpoints are fixed in position but must remain player-rotatable so
    -- players can connect a local pipe network from any side. Store Boxes and
    -- the Substation remain locked because rotation has no useful meaning.
    pcall(function() entity.rotatable = entity.type == "pipe-to-ground" end)
    if direction ~= nil then
        pcall(function() entity.direction = direction end)
    end
    return entity
end

function train_interiors._ensure_garden_fixture(garden, field, surface, name, position, force, direction)
    local entity = garden[field]
    if train_interiors._same_garden_entity_location(entity, surface, name, position) then
        -- Never reapply the creation direction to an established Pipe. This
        -- check runs every 15 ticks and must preserve the player's rotation.
        return train_interiors._protect_garden_fixture(entity)
    end
    -- Reposition a matching fixed endpoint in place before considering a
    -- rebuild. This preserves linked-belt items and underground-pipe fluid when
    -- an established layout receives a coordinate-only update.
    if valid(entity) and entity.surface == surface and entity.name == name then
        if entity.type == "linked-belt" then
            pcall(function() entity.disconnect_linked_belts() end)
        end
        local ok, teleported = pcall(function() return entity.teleport(position) end)
        if ok and teleported ~= false
            and train_interiors._same_garden_entity_location(entity, surface, name, position) then
            garden[field] = train_interiors._protect_garden_fixture(entity)
            return garden[field]
        end
    end
    if valid(entity) then
        if entity.type == "linked-belt" then pcall(function() entity.disconnect_linked_belts() end) end
        pcall(function() entity.destroy() end)
    end
    garden[field] = nil

    for _, candidate in pairs(surface.find_entities_filtered {
        name = name,
        position = position,
        radius = 0.8,
        force = force,
    }) do
        if train_interiors._same_garden_entity_location(candidate, surface, name, position) then
            garden[field] = train_interiors._protect_garden_fixture(candidate)
            return garden[field]
        end
    end

    local can_place = false
    pcall(function()
        can_place = surface.can_place_entity { name = name, position = position, force = force }
    end)
    if not can_place then return nil end

    local ok, created = pcall(function()
        return surface.create_entity {
            name = name,
            position = position,
            direction = direction,
            force = force,
            create_build_effect_smoke = false,
        }
    end)
    if ok and valid(created) then
        garden[field] = train_interiors._protect_garden_fixture(created, direction)
    end
    return garden[field]
end

function train_interiors._garden_fixture_is_script_owned(entity)
    if not valid(entity) then return false end
    local minable_ok, minable = pcall(function() return entity.minable_flag end)
    local destructible_ok, destructible = pcall(function() return entity.destructible end)
    return (minable_ok and minable == false) or (destructible_ok and destructible == false)
end

function train_interiors._garden_storebox_inventory(entity)
    if not (valid(entity) and entity.name == train_interiors.garden_config.item_storebox_name) then return nil end
    local ok, inventory = pcall(function() return entity.get_inventory(defines.inventory.chest) end)
    return ok and inventory and inventory.valid and inventory or nil
end

function train_interiors._move_legacy_garden_belt_items(legacy, storebox)
    if not (valid(legacy) and legacy.type == "linked-belt" and valid(storebox)) then return false end
    local inventory = train_interiors._garden_storebox_inventory(storebox)
    if not inventory then return false end

    local max_line_index = 2
    pcall(function() max_line_index = math.max(1, legacy.get_max_transport_line_index()) end)
    local all_empty = true
    for line_index = 1, max_line_index do
        local line = nil
        pcall(function() line = legacy.get_transport_line(line_index) end)
        if line and line.valid then
            while true do
                local line_length = 0
                pcall(function() line_length = #line end)
                if line_length <= 0 then break end

                local stack = nil
                pcall(function() stack = line[line_length] end)
                if not (stack and stack.valid_for_read) then
                    all_empty = false
                    break
                end

                local count = stack.count
                local inserted = 0
                pcall(function() inserted = inventory.insert(stack) end)
                if inserted <= 0 then
                    all_empty = false
                    break
                elseif inserted >= count then
                    pcall(function() stack.clear() end)
                else
                    pcall(function() stack.count = count - inserted end)
                end
            end
            local remaining = 0
            pcall(function() remaining = line.get_item_count() end)
            if remaining > 0 then all_empty = false end
        end
    end
    return all_empty
end

function train_interiors._ensure_garden_storebox(garden, field, surface, position, force)
    local cfg = train_interiors.garden_config
    local entity = garden[field]
    if train_interiors._same_garden_entity_location(entity, surface, cfg.item_storebox_name, position) then
        return train_interiors._protect_garden_fixture(entity)
    end

    if valid(entity) and entity.name == cfg.item_storebox_name and entity.surface == surface then
        local ok, teleported = pcall(function() return entity.teleport(position) end)
        if ok and teleported ~= false
            and train_interiors._same_garden_entity_location(entity, surface, cfg.item_storebox_name, position) then
            garden[field] = train_interiors._protect_garden_fixture(entity)
            return garden[field]
        end
    end

    local legacy = valid(entity) and entity.type == "linked-belt" and entity or nil
    local storebox = nil
    for _, candidate in pairs(surface.find_entities_filtered {
        name = cfg.item_storebox_name,
        position = position,
        radius = 0.8,
        force = force,
    }) do
        if train_interiors._same_garden_entity_location(candidate, surface, cfg.item_storebox_name, position)
            and train_interiors._garden_fixture_is_script_owned(candidate) then
            storebox = candidate
            break
        end
    end

    if not valid(storebox) then
        local can_place = false
        pcall(function()
            can_place = surface.can_place_entity {
                name = cfg.item_storebox_name,
                position = position,
                force = force,
            }
        end)
        if can_place then
            pcall(function()
                storebox = surface.create_entity {
                    name = cfg.item_storebox_name,
                    position = position,
                    force = force,
                    create_build_effect_smoke = false,
                }
            end)
        end
    end

    if not valid(storebox) then return legacy end
    storebox = train_interiors._protect_garden_fixture(storebox)

    if legacy then
        pcall(function() legacy.disconnect_linked_belts() end)
        if train_interiors._move_legacy_garden_belt_items(legacy, storebox) then
            pcall(function() legacy.destroy() end)
        else
            garden.legacy_item_ports = garden.legacy_item_ports or {}
            garden.legacy_item_ports[field] = legacy
        end
    elseif valid(entity) and entity.unit_number ~= storebox.unit_number then
        if entity.name == cfg.item_storebox_name then
            local source_inventory = train_interiors._garden_storebox_inventory(entity)
            local target_inventory = train_interiors._garden_storebox_inventory(storebox)
            move_inventory_contents_preserving(source_inventory, target_inventory)
            if source_inventory and source_inventory.valid and source_inventory.is_empty() then
                pcall(function() entity.destroy() end)
            else
                garden.legacy_storeboxes = garden.legacy_storeboxes or {}
                garden.legacy_storeboxes[field] = entity
            end
        else
            pcall(function() entity.destroy() end)
        end
    end

    garden[field] = storebox
    return storebox
end

function train_interiors._drain_legacy_garden_item_ports(garden)
    if not garden then return end
    if garden.legacy_item_ports then
        for field, legacy in pairs(garden.legacy_item_ports) do
            local storebox = garden[field]
            if not valid(legacy) then
                garden.legacy_item_ports[field] = nil
            elseif valid(storebox) and train_interiors._move_legacy_garden_belt_items(legacy, storebox) then
                pcall(function() legacy.destroy() end)
                garden.legacy_item_ports[field] = nil
            end
        end
    end
    if garden.legacy_storeboxes then
        for field, legacy in pairs(garden.legacy_storeboxes) do
            local storebox = garden[field]
            if not valid(legacy) then
                garden.legacy_storeboxes[field] = nil
            elseif valid(storebox) then
                local source_inventory = train_interiors._garden_storebox_inventory(legacy)
                local target_inventory = train_interiors._garden_storebox_inventory(storebox)
                move_inventory_contents_preserving(source_inventory, target_inventory)
                if source_inventory and source_inventory.valid and source_inventory.is_empty() then
                    pcall(function() legacy.destroy() end)
                    garden.legacy_storeboxes[field] = nil
                end
            end
        end
    end
end

function train_interiors._connect_garden_item_pair(input, output)
    if not (valid(input) and valid(output) and input.type == "linked-belt" and output.type == "linked-belt") then
        return false
    end
    local ok = pcall(function()
        if input.linked_belt_neighbour ~= output then
            input.disconnect_linked_belts()
            output.disconnect_linked_belts()
            input.linked_belt_type = "input"
            output.linked_belt_type = "output"
            input.connect_linked_belts(output)
        end
    end)
    return ok and input.linked_belt_neighbour == output
end

function train_interiors._get_garden_copper_connector(entity)
    if not valid(entity) then return nil end
    local ok, connector = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    end)
    if not ok or not (connector and connector.valid) then return nil end
    return connector
end

function train_interiors._connect_garden_power(upper_substation, lower_substation)
    local upper = train_interiors._get_garden_copper_connector(upper_substation)
    local lower = train_interiors._get_garden_copper_connector(lower_substation)
    if not (upper and lower) then return false end

    local check_ok, connected = pcall(function() return maintenance.connectors_linked(upper, lower) end)
    if check_ok and connected then return true end

    local connect_ok = pcall(function()
        upper.connect_to(lower, false, defines.wire_origin.script)
    end)
    if not connect_ok then return false end
    local verify_ok, verified = pcall(function() return maintenance.connectors_linked(upper, lower) end)
    return verify_ok and verified == true
end

function train_interiors._capture_garden_power_connections(entity)
    local connector = train_interiors._get_garden_copper_connector(entity)
    if not connector then return {} end
    local ok, connections = pcall(function() return connector.real_connections end)
    if not ok or type(connections) ~= "table" then return {} end

    local captured = {}
    for _, connection in pairs(connections) do
        local target = connection and connection.target
        if target and target.valid then
            captured[#captured + 1] = {
                target = target,
                origin = connection.origin or defines.wire_origin.script,
            }
        end
    end
    return captured
end

function train_interiors._restore_garden_power_connections(entity, connections)
    local connector = train_interiors._get_garden_copper_connector(entity)
    if not connector then return end
    for _, connection in pairs(connections or {}) do
        local target = connection and connection.target
        if target and target.valid then
            pcall(function()
                connector.connect_to(target, false,
                    connection.origin or defines.wire_origin.script)
            end)
        end
    end
end

function train_interiors._migrate_garden_substation(garden, surface, position, force)
    if not (garden and surface and surface.valid and position and force and force.valid) then return end
    local legacy = garden.lower_substation
    if valid(legacy) and legacy.surface == surface
        and legacy.name == TRAIN_GARDEN_SUBSTATION_NAME then
        return
    end
    if not (valid(legacy) and legacy.surface == surface
        and legacy.name == TRAIN_LOCOMOTIVE_SUBSTATION_NAME) then
        legacy = nil
        for _, candidate in pairs(surface.find_entities_filtered {
            name = TRAIN_LOCOMOTIVE_SUBSTATION_NAME,
            position = position,
            radius = 0.8,
            force = force,
        }) do
            if valid(candidate) then
                legacy = candidate
                break
            end
        end
    end
    if not valid(legacy) then return end

    -- Preserve player copper wires while replacing only the old script-owned
    -- lower Garden fixture. The scripted cross-surface link is also restored
    -- below and then verified by _connect_garden_power on every sync.
    local connections = train_interiors._capture_garden_power_connections(legacy)
    local destroyed_ok = pcall(function() legacy.destroy() end)
    if not destroyed_ok or valid(legacy) then
        garden.lower_substation = legacy
        return
    end
    garden.lower_substation = nil
    local replacement = train_interiors._ensure_garden_fixture(garden, "lower_substation", surface,
        TRAIN_GARDEN_SUBSTATION_NAME, position, force)
    train_interiors._restore_garden_power_connections(replacement, connections)
end

function train_interiors._draw_garden_infrastructure_labels(garden, upper_surface, upper_positions, lower_surface, lower_positions)
    -- Compatibility cleanup for saves created before 3.0.39. The portal is now
    -- automatic, so no PRESS / ENTER world text is rendered on either floor.
    train_interiors._clear_garden_infrastructure_labels(garden)
end

function train_interiors._garden_infrastructure_ready(garden, force, upper_wagon, lower_surface)
    return garden.infrastructure_layout_version == train_interiors.garden_config.infrastructure_layout_version
        and garden.portal_layout_version == train_interiors.garden_config.portal_layout_version
        and garden.infrastructure_upper_wagon_unit == upper_wagon.entity.unit_number
        and garden.infrastructure_upper_surface_name == upper_wagon.surface.name
        and maintenance.layout_ready(garden, force, upper_wagon.surface, lower_surface,
            area_center(upper_wagon.area), train_interiors.garden_config.maintenance_layout_version,
            upper_wagon.locomotive_substation, garden.lower_substation)
        and valid(train_interiors._garden_render_object(garden.upper_portal_render_id))
        and valid(train_interiors._garden_render_object(garden.lower_portal_render_id))
end

function train_interiors._ensure_garden_infrastructure(garden, force)
    if not (garden and garden.surface_name and force and force.valid) then return nil end
    local lower_surface = game.surfaces[garden.surface_name]
    local upper_wagon = train_interiors._garden_main_locomotive_wagon(force)
    if not (lower_surface and lower_surface.valid and upper_wagon and upper_wagon.area
        and upper_wagon.surface and upper_wagon.surface.valid and valid(upper_wagon.entity)) then
        return nil
    end

    if train_interiors._garden_infrastructure_ready(garden, force, upper_wagon, lower_surface) then
        if next(garden.legacy_item_ports or {}) or next(garden.legacy_storeboxes or {}) then
            train_interiors._drain_legacy_garden_item_ports(garden)
        end
        return garden
    end
    garden.infrastructure_ready = nil
    train_interiors._ensure_locomotive_power_fixtures(upper_wagon)
    train_interiors._capture_garden_transfer_directions(garden)
    local upper_unit = upper_wagon.entity.unit_number
    local infrastructure_owner_changed = garden.infrastructure_upper_wagon_unit ~= upper_unit
        or garden.infrastructure_upper_surface_name ~= upper_wagon.surface.name
    if infrastructure_owner_changed then
        train_interiors._destroy_garden_infrastructure(garden)
    end
    if infrastructure_owner_changed
        or garden.infrastructure_layout_version ~= train_interiors.garden_config.infrastructure_layout_version then
        garden.infrastructure_layout_version = train_interiors.garden_config.infrastructure_layout_version
        garden.infrastructure_upper_wagon_unit = upper_unit
        garden.infrastructure_upper_surface_name = upper_wagon.surface.name
    end

    local u_left, u_right, u_top, u_bottom = train_interiors._locomotive_garden_entry_bounds(upper_wagon.area)
    -- The portal moved down, but the Store Boxes and fluid Pipes must not move
    -- with it. Subtract the portal-only shift from their relative Y offset.
    local upper_transfer_y_offset = train_interiors.garden_config.upper_transfer_y_offset
        - (tonumber(train_interiors.garden_config.upper_portal_y_shift) or 0)
    local upper_positions = train_interiors._garden_transfer_positions(
        u_left, u_right, u_top, u_bottom, upper_transfer_y_offset)
    local l_left, l_right, l_top, l_bottom = train_interiors._garden_portal_bounds()
    local lower_positions = train_interiors._garden_transfer_positions(l_left, l_right, l_top, l_bottom)
    local function transfer_direction(field)
        return (garden.infrastructure_directions and garden.infrastructure_directions[field])
            or defines.direction.south
    end
    if garden.portal_layout_version ~= train_interiors.garden_config.portal_layout_version then
        train_interiors._clear_garden_infrastructure_labels(garden)
        train_interiors._destroy_garden_portal_renders(garden)
        garden.portal_layout_version = train_interiors.garden_config.portal_layout_version
    end
    train_interiors._ensure_garden_portal_render(garden, "upper_portal_render_id",
        upper_wagon.surface, u_left, u_right, u_top, u_bottom, force)
    train_interiors._ensure_garden_portal_render(garden, "lower_portal_render_id",
        lower_surface, l_left, l_right, l_top, l_bottom, force)

    train_interiors._ensure_garden_storebox(garden, "upper_item_input", upper_wagon.surface,
        upper_positions.item_input, force)
    train_interiors._ensure_garden_fixture(garden, "upper_fluid_input", upper_wagon.surface,
        train_interiors.garden_config.fluid_input_name,
        upper_positions.fluid_input, force, transfer_direction("upper_fluid_input"))
    train_interiors._ensure_garden_storebox(garden, "upper_item_output", upper_wagon.surface,
        upper_positions.item_output, force)
    train_interiors._ensure_garden_fixture(garden, "upper_fluid_output", upper_wagon.surface,
        train_interiors.garden_config.fluid_output_name,
        upper_positions.fluid_output, force, transfer_direction("upper_fluid_output"))

    train_interiors._ensure_garden_storebox(garden, "lower_item_input", lower_surface,
        lower_positions.item_input, force)
    train_interiors._ensure_garden_fixture(garden, "lower_fluid_input", lower_surface,
        train_interiors.garden_config.fluid_input_name,
        lower_positions.fluid_input, force, transfer_direction("lower_fluid_input"))
    train_interiors._ensure_garden_storebox(garden, "lower_item_output", lower_surface,
        lower_positions.item_output, force)
    train_interiors._ensure_garden_fixture(garden, "lower_fluid_output", lower_surface,
        train_interiors.garden_config.fluid_output_name,
        lower_positions.fluid_output, force, transfer_direction("lower_fluid_output"))

    local island_left, island_right, island_top, island_bottom = train_interiors._garden_substation_island_bounds()
    local substation_position = {
        x = (island_left + island_right) * 0.5,
        y = (island_top + island_bottom) * 0.5,
    }
    train_interiors._migrate_garden_substation(garden, lower_surface, substation_position, force)
    train_interiors._ensure_garden_fixture(garden, "lower_substation", lower_surface,
        TRAIN_GARDEN_SUBSTATION_NAME,
        substation_position, force)

    train_interiors._drain_legacy_garden_item_ports(garden)
    train_interiors._connect_garden_power(upper_wagon.locomotive_substation, garden.lower_substation)
    train_interiors._draw_garden_infrastructure_labels(
        garden, upper_wagon.surface, upper_positions, lower_surface, lower_positions)
    train_interiors._capture_garden_transfer_directions(garden)
    maintenance.remember_layout(garden, force, upper_wagon.surface, lower_surface,
        area_center(upper_wagon.area), train_interiors.garden_config.maintenance_layout_version,
        train_interiors.garden_config.fixture_fields,
        upper_wagon.locomotive_substation, garden.lower_substation)
    return garden
end

function train_interiors._transfer_garden_items(source, target)
    local source_inventory = train_interiors._garden_storebox_inventory(source)
    local target_inventory = train_interiors._garden_storebox_inventory(target)
    if not (source_inventory and target_inventory) then return end
    -- Move complete stacks directly so quality and stack metadata survive. The
    -- helper removes only the count accepted by the destination, leaving every
    -- remainder safely in the source Store Box when the target is full.
    move_inventory_contents_preserving(source_inventory, target_inventory)
end

function train_interiors._transfer_garden_fluid(source, target, amount_limit)
    if not (valid(source) and valid(target)) then return 0 end
    local source_fluid = fluid_info(source)
    if not source_fluid then return 0 end
    local target_fluid = fluid_info(target)
    if target_fluid and target_fluid.name ~= source_fluid.name then return 0 end

    local requested = math.min(source_fluid.amount,
        amount_limit or train_interiors.garden_config.fluid_transfer_per_sync)
    if requested <= 0 then return 0 end

    -- Work through Factorio's entity fluid API so the connected pipe segment
    -- determines how much it can really supply and accept. Directly assigning
    -- one fluidbox can be clamped by the engine and fail across the two surfaces.
    local removed = remove_fluid_safe(source, {
        name = source_fluid.name,
        amount = requested,
        temperature = source_fluid.temperature,
    })
    if removed <= 0 then return 0 end

    local inserted = insert_fluid_safe(target, {
        name = source_fluid.name,
        amount = removed,
        temperature = source_fluid.temperature,
    })
    local remainder = removed - inserted
    if remainder > 0 then
        -- Never lose fluid when the destination network is full or temporarily
        -- cannot accept the complete transfer.
        insert_fluid_safe(source, {
            name = source_fluid.name,
            amount = remainder,
            temperature = source_fluid.temperature,
        })
    end
    return inserted
end

function train_interiors._sync_all_garden_transfers()
    for _, garden in pairs(state().gardens or {}) do
        local force = (garden.force_index and game.forces[garden.force_index])
            or (garden.force_name and game.forces[garden.force_name])
        if force and force.valid and train_interiors._ensure_garden_infrastructure(garden, force) then
            train_interiors._transfer_garden_items(garden.upper_item_input, garden.lower_item_input)
            train_interiors._transfer_garden_items(garden.lower_item_output, garden.upper_item_output)
            train_interiors._transfer_garden_fluid(garden.upper_fluid_input, garden.lower_fluid_input,
                train_interiors.garden_config.fluid_transfer_per_sync)
            train_interiors._transfer_garden_fluid(garden.lower_fluid_output, garden.upper_fluid_output,
                train_interiors.garden_config.fluid_transfer_per_sync)
        end
    end
end

function train_interiors.ensure_garden_room(force)
    if not (force and force.valid and train_interiors.has_base(force)) then return nil end
    local stage = train_interiors._garden_stage(force)

    local s = state()
    local key = force.index
    local name = train_interiors._garden_surface_name(force)
    if not name then return nil end

    local surface = create_hidden_surface(name)
    -- Garden floors use ordinary pole coverage. Older builds accidentally made
    -- the entire surface one Space-Platform-style electric network, bypassing
    -- every electric pole. Destroy that network during save migration; the
    -- real scripted copper link between the two fixed substations is retained.
    pcall(function()
        if surface.has_global_electric_network and surface.destroy_global_electric_network then
            surface.destroy_global_electric_network()
        end
    end)

    s.surfaces[name] = true
    s.surface_owners[name] = force.index
    local garden = s.gardens[key] or {}
    garden.force_name = force.name
    garden.force_index = force.index
    garden.surface_name = name
    garden.stage = stage
    s.gardens[key] = garden

    if garden.void_layout_version ~= train_interiors.garden_config.void_layout_version
        or garden.voided_surface_index ~= surface.index
        or type(garden.voided_chunk_versions) ~= "table" then
        garden.voided_chunk_versions = {}
        garden.voided_surface_index = surface.index
        train_interiors._void_generated_garden_chunks(surface, garden)
        garden.void_layout_version = train_interiors.garden_config.void_layout_version
    end

    if garden.painted_stage ~= stage or garden.layout_version ~= train_interiors.garden_config.layout_version then
        if train_interiors._paint_garden_room(garden, force) == false then return nil end
        garden.painted_stage = stage
        garden.layout_version = train_interiors.garden_config.layout_version
    end
    if train_interiors._ensure_garden_infrastructure then
        train_interiors._ensure_garden_infrastructure(garden, force)
    end
    return garden
end

function train_interiors.ensure_all_garden_rooms()
    if not game then return end
    for _, force in pairs(game.forces) do
        if force and force.valid then train_interiors.ensure_garden_room(force) end
    end
end

function train_interiors._garden_exit_for_player(player)
    if not physical.can_travel(player) then return false end
    if not (player and player.valid and train_interiors._is_garden_surface(physical.surface(player))) then return nil end
    local garden = train_interiors._garden_for_surface(physical.surface(player))
    if not garden then return nil end
    local left, right, top, bottom = train_interiors._garden_portal_bounds()
    if train_interiors._position_in_bounds(physical.position(player), left, right, top, bottom) then return garden end
    return nil
end

function train_interiors._teleport_to_garden(player, wagon)
    if not physical.can_travel(player) then return false end
    if not (player and player.valid and wagon and valid(wagon.entity) and wagon.entity.force and wagon.entity.force.valid) then return false end
    if wagon.entity.force ~= player.force
        or train_interiors._find_locomotive_garden_entry_wagon(physical.surface(player), physical.position(player)) ~= wagon then return false end
    local garden = train_interiors.ensure_garden_room(wagon.entity.force)
    if not garden then
        player.print("[The Cave] Garden room is not available yet.")
        return true
    end
    local surface = game.surfaces[garden.surface_name]
    if not (surface and surface.valid) then return true end
    local left, right, top, bottom = train_interiors._garden_landing_pad_bounds()
    local target = { x = (left + right) * 0.5, y = (top + bottom) * 0.5 }
    local p = physical.find_position(player, surface, target, 1.5, 0.25)
    pcall(function() player.driving = false end)
    local ps = get_player_state(player)
    if not physical.teleport(player, p, surface) then return true end
    ps.garden_portal_cooldown_tick = game.tick + 15
    ps.last_wagon_unit = wagon.entity.unit_number
    ps.garden_return_wagon_unit = wagon.entity.unit_number
    ps.exit_cooldown_tick = game.tick + 30
    train_interiors.kill_minimap(player)
    return true
end

function train_interiors._teleport_from_garden(player, garden)
    if not physical.can_travel(player) then return false end
    if not (player and player.valid and garden) then return true end
    if train_interiors._garden_exit_for_player(player) ~= garden then return false end
    local ps = get_player_state(player)
    local wagon = train_interiors._garden_main_locomotive_wagon(player.force)
    if not (wagon and wagon.surface and wagon.surface.valid and wagon.area) then
        player.print("[The Cave] No connected locomotive interior was found for this Garden.")
        return true
    end
    local left, right, top, bottom = train_interiors._entry_pad_bounds(wagon.area)
    local target = { x = (left + right) * 0.5, y = (top + bottom) * 0.5 }
    local p = physical.find_position(player, wagon.surface, target, 1.5, 0.25)
    pcall(function() player.driving = false end)
    if not physical.teleport(player, p, wagon.surface) then return true end
    ps.garden_portal_cooldown_tick = game.tick + 15
    ps.last_wagon_unit = valid(wagon.entity) and wagon.entity.unit_number or ps.last_wagon_unit
    ps.garden_return_wagon_unit = ps.last_wagon_unit
    ps.exit_cooldown_tick = game.tick + 30
    chart_wagon_interior(wagon, player.force)
    draw_minimap(player, wagon)
    return true
end

function train_interiors._try_use_garden_portal(player)
    if not physical.can_travel(player) then return false end
    if not (player and player.valid and physical.surface(player) and physical.surface(player).valid) then return false end
    local ps = get_player_state(player)
    if (tonumber(ps.garden_portal_cooldown_tick) or 0) > (game.tick or 0) then return false end

    local garden = train_interiors._garden_exit_for_player(player)
    if garden then return train_interiors._teleport_from_garden(player, garden) end

    local wagon = train_interiors._find_locomotive_garden_entry_wagon(physical.surface(player), physical.position(player))
    if wagon then return train_interiors._teleport_to_garden(player, wagon) end

    return false
end

function train_interiors.on_player_changed_position(event)
    if not active() then return end
    local player = event and event.player_index and game.get_player(event.player_index) or nil
    if not (player and player.valid and player.character and player.character.valid) then return end
    train_interiors._try_use_garden_portal(player)
end

function train_interiors._find_garden_portal_for_entity(entity)
    if not (valid(entity) and entity.surface and entity.surface.valid) then return nil end
    local box = entity.bounding_box
    if not box then
        local p = entity.position
        box = { left_top = { x = p.x - 0.1, y = p.y - 0.1 }, right_bottom = { x = p.x + 0.1, y = p.y + 0.1 } }
    end

    if train_interiors._is_garden_surface(entity.surface) then
        local left, right, top, bottom = train_interiors._garden_portal_bounds()
        local pad = { left_top = { x = left, y = top }, right_bottom = { x = right, y = bottom } }
        if train_interiors._boxes_overlap(box, pad) then return "garden-exit" end
        return nil
    end

    if is_train_surface(entity.surface) then
        local wagon = train_interiors._garden_main_locomotive_on_surface(entity.surface)
        if wagon and wagon.surface == entity.surface and valid(wagon.entity) and wagon.entity.type == "locomotive" then
            local left, right, top, bottom = train_interiors._locomotive_garden_entry_bounds(wagon.area)
            local pad = { left_top = { x = left, y = top }, right_bottom = { x = right, y = bottom } }
            if train_interiors._boxes_overlap(box, pad) then return "locomotive-garden-entry" end
        end
    end
    return nil
end

function train_interiors._paint_garden_reserved_tiles(surface, left, right, top, bottom, tile_name)
    if not (surface and surface.valid) then return end
    local reserved_tile = tile_or_fallback(tile_name, "refined-concrete")
    local tiles = {}
    for x = left, right - 1 do
        for y = top, bottom - 1 do
            tiles[#tiles + 1] = { name = reserved_tile, position = { x = x, y = y } }
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles, true) end
end

function train_interiors.on_tiles_changed(surface, tiles)
    if not (surface and surface.valid and tiles) then return end

    if train_interiors._is_garden_surface(surface) then
        local p_left, p_right, p_top, p_bottom = train_interiors._garden_portal_bounds()
        local l_left, l_right, l_top, l_bottom = train_interiors._garden_landing_pad_bounds()
        local portal_changed = false
        local landing_changed = false
        for _, t in pairs(tiles) do
            if t.position then
                if train_interiors._position_in_bounds(t.position, p_left, p_right, p_top, p_bottom) then
                    portal_changed = true
                end
                if train_interiors._position_in_bounds(t.position, l_left, l_right, l_top, l_bottom) then
                    landing_changed = true
                end
            end
        end
        if portal_changed then
            local center_tile = tile_or_fallback("green-refined-concrete", tile_or_fallback("green-concrete", "refined-concrete"))
            train_interiors._paint_garden_reserved_tiles(surface, p_left, p_right, p_top, p_bottom, center_tile)
        end
        if landing_changed then
            train_interiors._paint_garden_reserved_tiles(surface, l_left, l_right, l_top, l_bottom, "refined-concrete")
        end
        return
    end

    if not is_train_surface(surface) then return end
    local main_wagon = train_interiors._garden_main_locomotive_on_surface(surface)
    local main_unit = main_wagon and valid(main_wagon.entity) and main_wagon.entity.unit_number or nil
    for _, wagon in pairs(state().wagons or {}) do
        if wagon and wagon.surface == surface and valid(wagon.entity) and wagon.area then
            local entry_left, entry_right, entry_top, entry_bottom = train_interiors._entry_pad_bounds(wagon.area)
            local portal_left, portal_right, portal_top, portal_bottom
            if main_unit and wagon.entity.unit_number == main_unit and wagon.entity.type == "locomotive" then
                portal_left, portal_right, portal_top, portal_bottom = train_interiors._locomotive_garden_entry_bounds(wagon.area)
            end
            local entry_changed = false
            local portal_changed = false
            for _, t in pairs(tiles) do
                if t.position then
                    if train_interiors._position_in_bounds(t.position,
                        entry_left, entry_right, entry_top, entry_bottom) then
                        entry_changed = true
                    end
                    if portal_left and train_interiors._position_in_bounds(t.position,
                        portal_left, portal_right, portal_top, portal_bottom) then
                        portal_changed = true
                    end
                end
            end
            if entry_changed then
                train_interiors._paint_garden_reserved_tiles(surface,
                    entry_left, entry_right, entry_top, entry_bottom, "refined-concrete")
            end
            if portal_changed then
                local core_tile = tile_or_fallback("green-refined-concrete", tile_or_fallback("green-concrete", "refined-concrete"))
                train_interiors._paint_garden_reserved_tiles(surface,
                    portal_left, portal_right, portal_top, portal_bottom, core_tile)
            end
        end
    end
end


local function nearest_rolling_stock_for_player(player, radius)
    if not physical.can_travel(player) then return false end
    if not (player and player.valid and physical.surface(player) and physical.surface(player).valid) then return nil end
    radius = radius or 10
    local selected = player.selected
    if valid(selected) and selected.unit_number and WAGON_TYPES[selected.type] and selected.force == player.force and selected.surface == physical.surface(player) and dist_sq(physical.position(player), selected.position) <= (radius * radius) then
        return selected
    end

    local area = {
        { physical.position(player).x - radius, physical.position(player).y - radius },
        { physical.position(player).x + radius, physical.position(player).y + radius },
    }
    local best, best_dist
    for _, entity_type in pairs(TRAIN_SHIELD.types) do
        for _, entity in pairs(physical.surface(player).find_entities_filtered { type = entity_type, area = area, force = player.force }) do
            if valid(entity) and entity.unit_number and WAGON_TYPES[entity.type] then
                local d = dist_sq(physical.position(player), entity.position)
                if d <= (radius * radius) and (not best_dist or d < best_dist) then
                    best, best_dist = entity, d
                end
            end
        end
    end
    return best
end

function train_interiors._entry_prompt_logical_display_size(player)
    local resolution = player and player.display_resolution or { width = 1280, height = 720 }
    local scale = player and player.display_scale or 1
    if not scale or scale <= 0 then scale = 1 end
    return resolution.width / scale, resolution.height / scale
end

function train_interiors._position_train_entry_prompt(player, frame)
    if not (player and player.valid and frame and frame.valid) then return end
    local logical_width, logical_height = train_interiors._entry_prompt_logical_display_size(player)
    local x = math.max(0, math.floor((logical_width - train_interiors.entry_prompt.width) * 0.5))
    -- Keep the compact prompt comfortably above Factorio's bottom quickbar.
    local y = math.max(80, math.floor(logical_height - 280))
    pcall(function() frame.location = { x = x, y = y } end)
end

function train_interiors._clear_train_entry_prompt(player)
    if not (player and player.valid and player.gui and player.gui.screen) then return end
    local frame = player.gui.screen[train_interiors.entry_prompt.gui_name]
    if frame and frame.valid then pcall(function() frame.destroy() end) end
end

function train_interiors._clear_all_train_entry_prompts()
    if not game then return end
    for _, player in pairs(game.players or {}) do
        train_interiors._clear_train_entry_prompt(player)
    end
end

function train_interiors._prompt_train_for_player(player)
    if not physical.can_travel(player) then return nil end
    if not (player and player.valid and player.connected and physical.surface(player) and physical.surface(player).valid) then return nil end
    if is_train_surface(physical.surface(player)) then return nil end
    if not (player.character and player.character.valid) then return nil end

    local driving = false
    pcall(function() driving = player.vehicle and player.vehicle.valid end)
    if driving then return nil end

    local entity = nearest_rolling_stock_for_player(player, train_interiors.entry_prompt.range)
    if not valid(entity) or not entity.unit_number then return nil end
    local s = state()
    if s.main_train_units[entity.unit_number] or s.wagons[entity.unit_number] then return entity end

    -- A newly coupled part is also enterable before its first hotkey press
    -- registers the room, provided the connected Main Train is still within its
    -- researched capacity. Keep this check read-only so the proximity GUI never
    -- disconnects or mutates rolling stock.
    if entity.train and entity.train.valid and entity.train.carriages then
        local carriages = entity.train.carriages or {}
        local within_capacity = train_interiors._rolling_stock_count(carriages)
            <= train_interiors._main_train_capacity(entity.force)
        if within_capacity and train_interiors._train_contains_main_train(carriages) then return entity end
    end
    return nil
end

function train_interiors._ensure_train_entry_prompt(player)
    if not (player and player.valid and player.gui and player.gui.screen) then return nil end
    local frame = player.gui.screen[train_interiors.entry_prompt.gui_name]
    if not (frame and frame.valid) then
        frame = player.gui.screen.add {
            type = "frame",
            name = train_interiors.entry_prompt.gui_name,
            direction = "vertical",
        }
        frame.style.width = train_interiors.entry_prompt.width
        frame.style.horizontal_align = "center"
        frame.style.padding = 6

        local title = frame.add {
            type = "label",
            name = train_interiors.entry_prompt.title_name,
            caption = { "the-cave-train-interiors.entry-prompt-title" },
        }
        title.style.font = "default-bold"
        title.style.font_color = { r = 0.35, g = 0.85, b = 1 }
        title.style.horizontal_align = "center"
        title.style.horizontally_stretchable = true
        title.style.bottom_margin = 2

        local text = frame.add {
            type = "label",
            name = train_interiors.entry_prompt.text_name,
            caption = {
                "",
                { "the-cave-train-interiors.entry-prompt-enter" },
                "\n",
                { "the-cave-train-interiors.entry-prompt-exit" },
            },
        }
        text.style.font = "default-bold"
        text.style.font_color = { r = 1, g = 0.78, b = 0.20 }
        text.style.horizontal_align = "center"
        text.style.horizontally_stretchable = true
        text.style.single_line = false
    end
    train_interiors._position_train_entry_prompt(player, frame)
    pcall(function() frame.bring_to_front() end)
    return frame
end

function train_interiors._update_train_entry_prompt(player)
    local entity = train_interiors._prompt_train_for_player(player)
    if not entity then
        train_interiors._clear_train_entry_prompt(player)
        return
    end

    local frame = train_interiors._ensure_train_entry_prompt(player)
    if not (frame and frame.valid) then return end
    local text = frame[train_interiors.entry_prompt.text_name]
    if not (text and text.valid) then return end

    text.caption = {
        "",
        { "the-cave-train-interiors.entry-prompt-enter" },
        "\n",
        { "the-cave-train-interiors.entry-prompt-exit" },
    }
    text.style.font_color = { r = 1, g = 0.78, b = 0.20 }
end

function train_interiors._update_train_entry_prompts()
    if not game then return end
    for _, player in pairs(game.connected_players or {}) do
        train_interiors._update_train_entry_prompt(player)
    end
end


local function set_locomotive_driver(player, loco)
    if not physical.can_travel(player) then return false end
    if not (valid(player) and valid(loco) and loco.type == "locomotive") then return false end

    local occupied = false
    pcall(function()
        local driver = loco.get_driver and loco.get_driver() or nil
        if driver and driver ~= player and driver ~= player.character then occupied = true end
    end)
    if occupied then
        player.print("[The Cave] This locomotive already has a driver.")
        return false
    end

    local p = safe_land_position(loco.surface, loco.position, 32, player.character.name)
    pcall(function() player.driving = false end)
    if player.character and player.character.valid and player.character.driving then
        pcall(function() player.character.driving = false end)
    end
    if not physical.teleport(player, p, loco.surface) then return false end
    train_interiors.kill_minimap(player)

    local ok = false
    ok = pcall(function() loco.set_driver(player) end)
    if not ok and player.character and player.character.valid then
        ok = pcall(function() loco.set_driver(player.character) end)
    end
    if not ok then
        player.print("[The Cave] Could not enter drive mode automatically. You are next to the locomotive; press Enter to drive it.")
        return false
    end
    local ps = get_player_state(player)
    ps.last_wagon_unit = loco.unit_number
    ps.exit_cooldown_tick = game.tick + 60
    return true
end

local function drive_train_from_inside(player)
    local wagon = wagon_for_player_surface(player)
    if not wagon then return false end
    local loco_wagon = valid(wagon.entity) and wagon.entity.type == "locomotive" and wagon or locomotive_for_train_surface(wagon.surface)
    if not (loco_wagon and valid(loco_wagon.entity)) then
        player.print("[The Cave] No locomotive is connected to this train interior.")
        return false
    end
    return set_locomotive_driver(player, loco_wagon.entity)
end

function train_interiors.enter_nearest_interior(player)
    if not physical.can_travel(player) then return false end
    if not active() then return end
    if not (player and player.valid) then return end

    -- One Ctrl+Enter enters or exits the nearest valid train interior.
    if is_train_surface(physical.surface(player)) then
        local wagon = wagon_for_player_surface(player)
        if not wagon then
            player.print("[The Cave] No connected train was found for this interior.")
            return
        end

        exit_wagon(player, wagon, nil)
        return
    end

    local entity = nearest_rolling_stock_for_player(player, 10)
    if not valid(entity) then
        player.print("[The Cave] Stand close to a locomotive or wagon, then use Enter Train Interior.")
        return
    end

    -- Unclaimed parts only become enterable after they are connected to the Main
    -- Train and the current Main Train capacity allows them.
    local existing_wagon = state().wagons[entity.unit_number]
    if not existing_wagon then
        if rebuild_train_for_entity then rebuild_train_for_entity(entity) end
        local allowed, reason = train_interiors._can_register_train_part(entity, true)
        if not allowed then
            if reason == "capacity-full" then
                player.print("[The Cave] Main Train capacity is full. Research more Main Train Expansion upgrades to add more train parts.")
            else
                player.print("[The Cave] This abandoned train part is not connected to your Main Train. Connect it to the Main Train before entering.")
            end
            return
        end
    end

    if rebuild_train_for_entity then rebuild_train_for_entity(entity) end
    local wagon = state().wagons[entity.unit_number]
    if not wagon then
        local allowed, reason = train_interiors._can_register_train_part(entity, true)
        if allowed then wagon = register_wagon(entity) end
        if not wagon then
            if reason == "capacity-full" then
                player.print("[The Cave] Main Train capacity is full. Research more Main Train Expansion upgrades to add more train parts.")
            else
                player.print("[The Cave] This abandoned train part is not connected to your Main Train. Connect it to the Main Train before entering.")
            end
            return
        end
    end
    enter_wagon(player, wagon, entity)
end

function train_interiors.on_enter_interior_hotkey(event)
    if not active() then return end
    local player = game.get_player(event.player_index)
    train_interiors.enter_nearest_interior(player)
end

function train_interiors.on_lua_shortcut(event)
    if not active() then return end
    if event.prototype_name ~= "the-cave-enter-train-interior-shortcut" then return end
    local player = game.get_player(event.player_index)
    train_interiors.enter_nearest_interior(player)
end

function train_interiors.update_minimaps()
    for _, player in pairs(game.connected_players) do
        local wagon = wagon_for_player_surface(player)
        if wagon and valid(wagon.entity) then
            make_surface_visible_for_force(wagon.surface, player.force)
            ensure_wagon_map_radar(wagon)
            chart_wagon_interior(wagon, player.force)
            draw_minimap(player, wagon)
        else
            train_interiors.kill_minimap(player)
        end
    end
end

function train_interiors.on_gui_click(event)
    -- Wave Defense is shared by Train Interiors and Shelter Defense. Handle
    -- its own toggle before the Train Interiors-only guard so Shelter players
    -- can expand and collapse the shared status panel as well.
    if train_interiors.wave_defense.on_gui_click(event) then return end
    if not active() then return end
    local element = event.element
    if not (element and element.valid) then return end
    local player = game.get_player(event.player_index)
    if not player then return end

    if element.name == "the_cave_train_drive_button" then
        drive_train_from_inside(player)
        return
    end

    if element.name ~= "the_cave_train_camera" then return end
    local ps = get_player_state(player)
    if event.button == defines.mouse_button_type.right then
        ps.zoom = math.max(0.30, (ps.zoom or 0.50) - 0.07)
        element.zoom = ps.zoom
    elseif event.button == defines.mouse_button_type.left then
        ps.zoom = math.min(2, (ps.zoom or 0.50) + 0.07)
        element.zoom = ps.zoom
    elseif event.button == defines.mouse_button_type.middle then
        ps.map_size = (ps.map_size or 220) + 30
        if ps.map_size > 260 then ps.map_size = 200 end
        element.style.minimal_width = ps.map_size
        element.style.minimal_height = ps.map_size
        element.style.maximal_width = ps.map_size
        element.style.maximal_height = ps.map_size
        local frame = element.parent
        if frame and frame.valid and frame.name == "the_cave_train_minimap" then
            local frame_width = ps.map_size + 20
            frame.style.minimal_width = frame_width
            frame.style.maximal_width = frame_width
            pcall(function() frame.style.natural_width = frame_width end)
        end
    end
end

enter_wagon = function(player, wagon, source_entity)
    if not physical.can_travel(player) then return false end
    if not (wagon and valid(wagon.entity) and wagon.entity.force == player.force
        and physical.on_surface(player, wagon.entity.surface)
        and dist_sq(physical.position(player), wagon.entity.position) <= 100) then return false end
    if not (valid(player) and wagon and valid(wagon.entity) and valid(wagon.surface)) then return end
    if train_interiors._clear_train_entry_prompt then train_interiors._clear_train_entry_prompt(player) end
    if player.character and player.character.valid and player.character.driving then
        pcall(function() player.character.driving = false end)
    end
    pcall(function() player.driving = false end)
    -- Do not rebuild here. The interior surface must persist between
    -- exits and re-entries, otherwise player-built machines inside the train
    -- get wiped. Train layout rebuilding is handled by build/train-change events.
    local center = area_center(wagon.area)
    -- Entry-only landing: outside-to-inside Ctrl+Enter now lands on the fixed
    -- 4x4 center pad. Exit logic stays unchanged and works from anywhere inside.
    local target = { x = center.x, y = center.y }
    local p = physical.find_position(player, wagon.surface, target, 2, 0.25)
        or physical.find_position(player, wagon.surface, target, 4, 0.5)
    if not physical.teleport(player, p, wagon.surface) then return false end
    local ps = get_player_state(player)
    ps.last_wagon_unit = wagon.entity.unit_number
    ps.exit_cooldown_tick = game.tick + 60
    chart_wagon_interior(wagon, player.force)
    draw_minimap(player, wagon)
end

exit_wagon = function(player, wagon, door)
    if not physical.can_travel(player) or not (wagon and physical.on_surface(player, wagon.surface)) then return false end
    if not (valid(player) and wagon and valid(wagon.entity)) then return end
    if player.character and player.character.valid and player.character.driving then
        pcall(function() player.character.driving = false end)
    end
    pcall(function() player.driving = false end)
    local center = area_center(wagon.area)
    local offset = 3
    if door and door.position and door.position.x < center.x then offset = -3 end
    local target = { x = wagon.entity.position.x + offset, y = wagon.entity.position.y }
    local p = safe_land_position(wagon.entity.surface, target, 32, player.character.name)
        or safe_land_position(wagon.entity.surface, wagon.entity.position, 64, player.character.name)
    if not physical.teleport(player, p, wagon.entity.surface) then return false end
    local ps = get_player_state(player)
    ps.last_wagon_unit = wagon.entity.unit_number
    train_interiors.kill_minimap(player)
end

function train_interiors.on_player_driving_changed_state(event)
    if not active() then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if player.controller_type == defines.controllers.remote then return end
    local entity = event.entity
    if not valid(entity) then return end
    local s = state()

    if entity.unit_number and WAGON_TYPES[entity.type] then
        -- Do not hijack vanilla train driving/passenger mode.
        -- Entering a real locomotive with Enter must stay normal Factorio drive mode,
        -- Train interiors are entered through the dedicated shortcut/hotkey instead.
        local wagon = s.wagons[entity.unit_number] or register_wagon(entity)
        if wagon and valid(wagon.entity) then
            local ps = get_player_state(player)
            ps.last_wagon_unit = wagon.entity.unit_number
        end
    end
end

local function cleanup_wagon(wagon)
    if not wagon then return true end
    if wagon.surface and wagon.surface.valid then
        for _, player in pairs(game.players) do
            local inside = physical.on_surface(player, wagon.surface)
            if player.valid and (inside or player.surface == wagon.surface) then
                local force = cave_teams.player_force(player)
                local entity = valid(wagon.entity) and wagon.entity.force == force and wagon.entity or nil
                local target_surface = entity and entity.surface or cave_teams.home_surface(force)
                if not valid(target_surface) or cave_worlds.is_template(target_surface) then return false end
                local target_position = entity and entity.position or force.get_spawn_position(target_surface)
                local p = target_position
                if inside then p = physical.find_position(player, target_surface, target_position, 64) end
                if not physical.evacuate(player, wagon.surface, target_surface, p) then return false end
                if inside then train_interiors.kill_minimap(player) end
            end
        end
        if cleanup_train_power_for_surface then cleanup_train_power_for_surface(wagon.surface.name) end
        local ok, queued = pcall(function() return game.delete_surface(wagon.surface) end)
        if not ok or not queued then return false end
    end
    for _, door in pairs(wagon.doors or {}) do if valid(door) then door.destroy() end end
    return true
end

-- Failed safety moves are retried in the existing tick handler, including after save/load.
function train_interiors._retry_removed_wagon_cleanup()
    local pending = state().pending_wagon_cleanup
    if not pending then return end
    for unit, wagon in pairs(pending) do
        if cleanup_wagon(wagon) then pending[unit] = nil end
    end
end

function train_interiors.on_entity_removed(entity)
    if not active() then return end
    if not (valid(entity) and entity.unit_number and WAGON_TYPES[entity.type]) then return end
    local s = state()
    local wagon = s.wagons[entity.unit_number]
    if wagon then
        if not cleanup_wagon(wagon) then
            s.pending_wagon_cleanup = s.pending_wagon_cleanup or {}
            s.pending_wagon_cleanup[entity.unit_number] = wagon
        end
        s.wagons[entity.unit_number] = nil
    end
    if entity.force and entity.force.valid
        and s.main_battery_locomotive_units[entity.force.index] == entity.unit_number then
        s.main_battery_locomotive_units[entity.force.index] = nil
    end
    s.main_train_units[entity.unit_number] = nil
    s.unclaimed_train_parts[entity.unit_number] = nil
end

function train_interiors.on_entity_died(event)
    train_interiors.wave_defense.on_entity_died(event)
    if event and event.entity then train_interiors.on_entity_removed(event.entity) end
end

function train_interiors.on_built(event)
    if not active() then return end
    local entity = event.entity or event.created_entity
    if train_interiors._reject_reserved_entry_pad_build(event, entity) then return end
    if train_interiors._reject_garden_portal_build(event, entity) then return end
    if reject_invalid_utility_lane_build(event, entity) then return end
    register_wagon(entity)
end

local function create_rail(surface, force, pos)
    local ok, rail = pcall(function()
        return surface.create_entity {
            name = "straight-rail",
            position = pos,
            direction = defines.direction.east,
            force = force,
            create_build_effect_smoke = false,
            raise_built = true,
        }
    end)
    if ok then return rail end
    return nil
end

local function create_train_entity(surface, force, name, pos, claim_to_main_train)
    -- Always create the stable base rolling-stock prototype. Train Shield is a
    -- scripted shared pool and never changes the physical entity afterwards.
    local create_name = name
    local ok, entity = pcall(function()
        return surface.create_entity {
            name = create_name,
            position = pos,
            direction = defines.direction.east,
            force = force,
            create_build_effect_smoke = false,
            raise_built = claim_to_main_train ~= false,
        }
    end)
    if ok and entity and entity.valid then
        pcall(function() entity.minable_flag = false end)
        if claim_to_main_train == false then
            train_interiors._mark_unclaimed_train_part(entity, "world")
        else
            register_wagon(entity, false, true)
        end
        return entity
    end
    return nil
end

local function prepare_train_area(surface, center, half_x, half_y, tile_name)
    surface.request_to_generate_chunks(center, 2)
    surface.force_generate_chunk_requests()
    fill_land(surface, center, half_x or 28, half_y or 8, tile_name)
    clear_area(surface, { { center.x - (half_x or 30), center.y - (half_y or 10) }, { center.x + (half_x or 30), center.y + (half_y or 10) } })
end

function train_interiors._prepare_exact_train_area(surface, center, width, height, tile_name)
    if not (surface and surface.valid and center) then return end
    surface.request_to_generate_chunks(center, 2)
    surface.force_generate_chunk_requests()
    local left, top, right, bottom = train_interiors._exact_rect_bounds(center, width, height)
    train_interiors._fill_rect_tiles(surface, left, top, width, height, tile_name)
    clear_area(surface, { { left, top }, { right, bottom } })
end

try_connect = function(a, direction)
    if not valid(a) then return false end
    local ok, result = pcall(function() return a.connect_rolling_stock(direction) end)
    return ok and result == true
end


function TRAIN_SHIELD.base_name(name)
    if TRAIN_SHIELD.base_names[name] then return name, nil end
    local base, level = tostring(name or ""):match("^" .. TRAIN_SHIELD.variant_prefix:gsub("%-", "%%-") .. "(.+)%-(%d+)$")
    if base and TRAIN_SHIELD.base_names[base] then return base, tonumber(level) end
    return nil, nil
end

function TRAIN_SHIELD.level(force)
    if not (force and force.valid and force.technologies) then return 0 end
    local level = 0
    for i = 1, TRAIN_SHIELD.max_level do
        local tech = force.technologies[TRAIN_SHIELD.prefix .. i]
        if tech and tech.researched then level = i end
    end
    return level
end

function TRAIN_SHIELD.max_health(level)
    level = math.max(0, math.min(TRAIN_SHIELD.max_level, tonumber(level) or 0))
    return TRAIN_SHIELD.base_health + (TRAIN_SHIELD.health_per_level * level)
end

function TRAIN_SHIELD.repair_per_second(level)
    level = math.max(0, math.min(TRAIN_SHIELD.max_level, tonumber(level) or 0))
    return TRAIN_SHIELD.repair_per_level * level
end

function TRAIN_SHIELD.collect_inventory_contents(entity, inventory_id)
    local ok, inv = pcall(function() return entity.get_inventory(inventory_id) end)
    if not (ok and inv and inv.valid) then return nil end
    local contents = nil
    pcall(function() contents = inv.get_contents() end)
    return contents
end

function TRAIN_SHIELD.restore_inventory_contents(entity, inventory_id, contents)
    if not contents then return end
    local ok, inv = pcall(function() return entity.get_inventory(inventory_id) end)
    if not (ok and inv and inv.valid) then return end
    for key, value in pairs(contents) do
        local name, count
        if type(key) == "string" then
            name, count = key, value
        elseif type(value) == "table" then
            name, count = value.name, value.count
        end
        if type(name) == "string" and tonumber(count) and count > 0 then
            pcall(function() inv.insert { name = name, count = count } end)
        end
    end
end

function TRAIN_SHIELD.collect_fluidbox_contents(entity)
    local fluids = {}
    local ok, count = pcall(function() return entity.fluids_count end)
    if not (ok and count) then return fluids end
    for i = 1, count do
        local fluid = nil
        pcall(function() fluid = entity.get_fluid(i) end)
        if fluid then fluids[i] = fluid end
    end
    return fluids
end

function TRAIN_SHIELD.restore_fluidbox_contents(entity, fluids)
    if type(fluids) ~= "table" then return end
    if not valid(entity) then return end
    for i, fluid in pairs(fluids) do
        pcall(function() entity.set_fluid(i, fluid) end)
    end
end

function TRAIN_SHIELD.current_effective_level(entity)
    if not (valid(entity) and entity.unit_number) then return 0 end
    local s = state()
    local stored = s.train_shield_applied_level and s.train_shield_applied_level[entity.unit_number]
    if stored ~= nil then return tonumber(stored) or 0 end
    local _, variant_level = TRAIN_SHIELD.base_name(entity.name)
    return tonumber(variant_level) or 0
end

function TRAIN_SHIELD.carriages(entity)
    if valid(entity) and entity.train and entity.train.valid and entity.train.carriages then
        return entity.train.carriages
    end
    if valid(entity) then return { entity } end
    return {}
end

function TRAIN_SHIELD.train_key_candidates(entity)
    if not (valid(entity) and entity.unit_number and WAGON_TYPES[entity.type]) then return nil, {} end
    local s = state()
    local aliases = { "entity:" .. tostring(entity.unit_number) }
    local surface_scores = {}
    local best_surface, best_count = nil, 0
    local first_unit = nil
    if entity.train and entity.train.valid then
        local train_id = nil
        pcall(function() train_id = entity.train.id end)
        if train_id ~= nil then aliases[#aliases + 1] = "train:" .. tostring(train_id) end
        for _, carriage in ipairs(entity.train.carriages or {}) do
            if valid(carriage) and carriage.unit_number and WAGON_TYPES[carriage.type] then
                first_unit = first_unit or carriage.unit_number
                aliases[#aliases + 1] = "entity:" .. tostring(carriage.unit_number)
                local wagon = s.wagons and s.wagons[carriage.unit_number]
                if wagon and wagon.surface and wagon.surface.valid then
                    local name = "surface:" .. wagon.surface.name
                    surface_scores[name] = (surface_scores[name] or 0) + 1
                end
            end
        end
    end
    if first_unit then aliases[#aliases + 1] = "first:" .. tostring(first_unit) end
    for name, count in pairs(surface_scores) do
        aliases[#aliases + 1] = name
        if count > best_count then
            best_surface, best_count = name, count
        end
    end
    if best_surface then return best_surface, aliases end
    if entity.train and entity.train.valid then
        local train_id = nil
        pcall(function() train_id = entity.train.id end)
        if train_id ~= nil then return "train:" .. tostring(train_id), aliases end
        if first_unit then return "first:" .. tostring(first_unit), aliases end
    end
    return "entity:" .. tostring(entity.unit_number), aliases
end

function TRAIN_SHIELD.train_health_ratio(entity, level)
    local max_health = TRAIN_SHIELD.max_health(level)
    local total, total_max = 0, 0
    for _, carriage in ipairs(TRAIN_SHIELD.carriages(entity)) do
        if valid(carriage) and WAGON_TYPES[carriage.type] then
            local h = tonumber(carriage.health) or max_health
            if h > max_health then h = max_health end
            if h < 0 then h = 0 end
            total = total + h
            total_max = total_max + max_health
        end
    end
    if total_max <= 0 then return 1 end
    return math.max(0.01, math.min(1, total / total_max))
end

function TRAIN_SHIELD.ensure_pool(entity, preserve_ratio)
    if not (valid(entity) and entity.unit_number and WAGON_TYPES[entity.type]) then return nil end
    local s = state()
    local key, aliases = TRAIN_SHIELD.train_key_candidates(entity)
    if not key then return nil end
    local pools = s.train_shield_pools
    local pool = pools[key]
    if not pool then
        for _, alias in ipairs(aliases or {}) do
            if pools[alias] then
                pool = pools[alias]
                pools[alias] = nil
                pools[key] = pool
                break
            end
        end
    end
    local level = TRAIN_SHIELD.level(entity.force)
    local max_health = TRAIN_SHIELD.max_health(level)
    if not pool then
        local ratio = TRAIN_SHIELD.train_health_ratio(entity, level)
        pool = { health = max_health * ratio, max_health = max_health, level = level, last_damage = 0 }
        pools[key] = pool
    elseif (tonumber(pool.level) or 0) ~= level or (tonumber(pool.max_health) or 0) ~= max_health then
        local old_max = tonumber(pool.max_health) or TRAIN_SHIELD.max_health(tonumber(pool.level) or 0)
        local old_health = tonumber(pool.health) or old_max
        local ratio = old_max > 0 and math.max(0.01, math.min(1, old_health / old_max)) or 1
        pool.level = level
        pool.max_health = max_health
        if preserve_ratio then
            pool.health = max_health * ratio
        else
            pool.health = math.min(max_health, old_health)
        end
    end
    pool.key = key
    pool.force_index = entity.force.index
    pool.max_health = max_health
    pool.level = level
    pool.health = math.max(0, math.min(max_health, tonumber(pool.health) or max_health))
    local count = 0
    for _, carriage in ipairs(TRAIN_SHIELD.carriages(entity)) do
        if valid(carriage) and WAGON_TYPES[carriage.type] then count = count + 1 end
    end
    pool.carriage_count = count
    return pool, key
end

function TRAIN_SHIELD.physical_health_for_carriage(carriage, pool)
    local pool_max = math.max(1, tonumber(pool and pool.max_health) or 1)
    local pool_health = math.max(0, math.min(pool_max, tonumber(pool and pool.health) or pool_max))
    local ratio = pool_health / pool_max
    local prototype_max = TRAIN_SHIELD.max_health(TRAIN_SHIELD.max_level)
    pcall(function()
        if carriage and tonumber(carriage.max_health) then
            prototype_max = tonumber(carriage.max_health)
        end
    end)
    prototype_max = math.max(1, prototype_max or TRAIN_SHIELD.max_health(TRAIN_SHIELD.max_level))
    if pool_health > 0 then
        return math.max(1, math.min(prototype_max, prototype_max * ratio))
    end
    return 0
end

function TRAIN_SHIELD.sync_physical_train(entity)
    local pool = TRAIN_SHIELD.ensure_pool(entity, false)
    if not pool then return nil end
    if (tonumber(pool.health) or 0) <= 0 then return pool end
    local s = state()
    for _, carriage in ipairs(TRAIN_SHIELD.carriages(entity)) do
        if valid(carriage) and carriage.unit_number and WAGON_TYPES[carriage.type] then
            local h = TRAIN_SHIELD.physical_health_for_carriage(carriage, pool)
            pcall(function() carriage.minable_flag = false end)
            pcall(function() carriage.health = h end)
            s.train_shield_applied_level[carriage.unit_number] = tonumber(pool.level) or 0
        end
    end
    return pool
end

function TRAIN_SHIELD.migrate_unit_references(old_unit, new_entity)
    if not (old_unit and valid(new_entity) and new_entity.unit_number) then return end
    local new_unit = new_entity.unit_number
    if old_unit == new_unit then return end
    local s = state()
    local wagon = s.wagons and s.wagons[old_unit]
    if wagon then
        s.wagons[old_unit] = nil
        wagon.entity = new_entity
        wagon.force_index = new_entity.force.index
        wagon.exterior_surface_index = new_entity.surface.index
        wagon.exterior_surface_name = new_entity.surface.name
        s.wagons[new_unit] = wagon
    end
    if s.main_train_units and s.main_train_units[old_unit] then
        s.main_train_units[old_unit] = nil
        s.main_train_units[new_unit] = true
    end
    if new_entity.force and new_entity.force.valid
        and s.main_battery_locomotive_units
        and s.main_battery_locomotive_units[new_entity.force.index] == old_unit then
        s.main_battery_locomotive_units[new_entity.force.index] = new_unit
    end
    if s.unclaimed_train_parts and s.unclaimed_train_parts[old_unit] then
        local rec = s.unclaimed_train_parts[old_unit]
        s.unclaimed_train_parts[old_unit] = nil
        rec.type = new_entity.type
        rec.name = new_entity.name
        rec.surface_index = new_entity.surface and new_entity.surface.valid and new_entity.surface.index or rec.surface_index
        rec.x = new_entity.position and new_entity.position.x or rec.x
        rec.y = new_entity.position and new_entity.position.y or rec.y
        s.unclaimed_train_parts[new_unit] = rec
    end
    if s.train_shield_applied_level and s.train_shield_applied_level[old_unit] ~= nil then
        s.train_shield_applied_level[new_unit] = s.train_shield_applied_level[old_unit]
        s.train_shield_applied_level[old_unit] = nil
    end
    if s.train_shield_last_damage and s.train_shield_last_damage[old_unit] ~= nil then
        s.train_shield_last_damage[new_unit] = s.train_shield_last_damage[old_unit]
        s.train_shield_last_damage[old_unit] = nil
    end
    for surface_name, anchor_unit in pairs(s.train_layout_anchor_units or {}) do
        if anchor_unit == old_unit then s.train_layout_anchor_units[surface_name] = new_unit end
    end
    for _, ps in pairs(s.players or {}) do
        if ps.last_wagon_unit == old_unit then ps.last_wagon_unit = new_unit end
    end
end

function TRAIN_SHIELD.inventory_ids_for_entity(entity)
    local ids = {}
    local inv = defines and defines.inventory or {}
    if entity.type == "locomotive" then
        ids[#ids + 1] = inv.fuel
        ids[#ids + 1] = inv.burnt_result
    elseif entity.type == "cargo-wagon" then
        ids[#ids + 1] = inv.cargo_wagon
    elseif entity.type == "artillery-wagon" then
        ids[#ids + 1] = inv.artillery_wagon_ammo
    end
    return ids
end

function TRAIN_SHIELD.capture_entity_contents(entity)
    local data = { inventories = {}, fluids = nil }
    for _, inventory_id in pairs(TRAIN_SHIELD.inventory_ids_for_entity(entity)) do
        if inventory_id then data.inventories[inventory_id] = TRAIN_SHIELD.collect_inventory_contents(entity, inventory_id) end
    end
    if entity.type == "fluid-wagon" then data.fluids = TRAIN_SHIELD.collect_fluidbox_contents(entity) end
    return data
end

function TRAIN_SHIELD.restore_entity_contents(entity, data)
    if not (valid(entity) and type(data) == "table") then return end
    for inventory_id, contents in pairs(data.inventories or {}) do
        TRAIN_SHIELD.restore_inventory_contents(entity, inventory_id, contents)
    end
    if entity.type == "fluid-wagon" and data.fluids then TRAIN_SHIELD.restore_fluidbox_contents(entity, data.fluids) end
end

function TRAIN_SHIELD.replace_entity_with_variant(entity, target_name, preserve_ratio)
    -- Permanent safety interlock. Older builds called this helper from
    -- research/load/register paths and destroyed/recreated live rolling stock.
    -- Keep it as a harmless compatibility no-op so no stale call can ever
    -- change prototype, unit_number, direction, train order or coupling.
    if not (valid(entity) and entity.unit_number and WAGON_TYPES[entity.type]) then return entity end
    TRAIN_SHIELD.ensure_pool(entity, preserve_ratio)
    TRAIN_SHIELD.sync_physical_train(entity)
    return entity
end

function TRAIN_SHIELD.apply_entity_health(entity, preserve_ratio)
    if not (valid(entity) and entity.unit_number and WAGON_TYPES[entity.type]) then return entity end
    -- Shield upgrades are numeric only. Never replace live rolling stock.
    TRAIN_SHIELD.ensure_pool(entity, preserve_ratio)
    TRAIN_SHIELD.sync_physical_train(entity)
    return entity
end

function train_interiors.apply_train_shield_to_entity(entity, preserve_ratio)
    if not (active() and valid(entity) and entity.unit_number and WAGON_TYPES[entity.type] and not is_train_surface(entity.surface)) then return entity end
    return TRAIN_SHIELD.apply_entity_health(entity, preserve_ratio)
end

function train_interiors.apply_train_shield_to_all(preserve_ratio)
    if not active() then return end
    local seen = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid and not is_train_surface(surface) then
            for _, entity_type in pairs(TRAIN_SHIELD.types) do
                for _, entity in pairs(surface.find_entities_filtered { type = entity_type }) do
                    if valid(entity) and WAGON_TYPES[entity.type] then
                        local applied = train_interiors.apply_train_shield_to_entity(entity, preserve_ratio)
                        if valid(applied) then entity = applied end
                        local _, key = TRAIN_SHIELD.ensure_pool(entity, preserve_ratio)
                        if key and not seen[key] then
                            seen[key] = true
                            TRAIN_SHIELD.sync_physical_train(entity)
                        end
                    end
                end
            end
        end
    end
end

local function demolisher_damage_entity(entity)
    if not valid(entity) then return false end
    local name
    pcall(function() name = entity.name end)
    if type(name) == "string" and name:find("demolisher", 1, true) then return true end

    -- Body/tail damage can arrive through a segment entity.  Keep a guarded
    -- prototype fallback for modded segments whose entity name omits the word.
    local segmented_name
    pcall(function()
        local unit = entity.segmented_unit
        segmented_name = unit and unit.valid and unit.prototype and unit.prototype.name
    end)
    return type(segmented_name) == "string"
        and segmented_name:find("demolisher", 1, true) ~= nil
end

local function damage_is_from_demolisher(event)
    return event and (demolisher_damage_entity(event.cause)
        or demolisher_damage_entity(event.source))
end

local function restore_ignored_damage(entity, event)
    if not valid(entity) then return end
    local damage = tonumber(event and event.final_damage_amount)
        or tonumber(event and event.original_damage_amount) or 0
    local final_health = tonumber(event and event.final_health)
        or tonumber(entity.health) or 0
    local maximum = math.huge
    pcall(function()
        maximum = tonumber(entity.prototype and entity.prototype.max_health) or maximum
    end)
    pcall(function()
        if tonumber(entity.max_health) then maximum = tonumber(entity.max_health) end
    end)
    pcall(function()
        entity.health = math.max(1, math.min(maximum, final_health + math.max(0, damage)))
    end)
end

local function protected_train_interiors_stock(entity)
    if not (entity and entity.unit_number) then return false, false end
    local s = state()
    local unit = entity.unit_number
    local managed = s.main_train_units[unit] == true or s.wagons[unit] ~= nil
    local unclaimed = s.unclaimed_train_parts[unit] ~= nil
    return managed or unclaimed, managed
end

function train_interiors.on_entity_damaged(event)
    local wave_damage_ignored = train_interiors.wave_defense.on_entity_damaged(event) == true
    if wave_damage_ignored then return true end
    if not (active() and event and valid(event.entity) and event.entity.unit_number and WAGON_TYPES[event.entity.type]) then return end

    -- The Demolisher is cave terrain machinery, not a train combat encounter.
    -- Ignore only its damage to Train-Interiors-owned rolling stock.  Ordinary
    -- trains outside these registries and every other damage source keep the
    -- exact existing Train Shield behaviour.
    local protected, managed = protected_train_interiors_stock(event.entity)
    if protected and damage_is_from_demolisher(event) then
        -- Restore first so a previously missing shield pool cannot initialise
        -- from the already-damaged physical-health ratio.
        restore_ignored_damage(event.entity, event)
        if managed then
            TRAIN_SHIELD.ensure_pool(event.entity, false)
            TRAIN_SHIELD.sync_physical_train(event.entity)
        end
        -- Tell control.lua not to render a misleading damage number for a hit
        -- that was synchronously ignored.  No repair-delay timer is touched.
        return true
    end

    local pool, key = TRAIN_SHIELD.ensure_pool(event.entity, false)
    if not pool then return end
    local tick = event.tick or game.tick
    local damage = tonumber(event.final_damage_amount) or tonumber(event.original_damage_amount) or 0
    if damage <= 0 then damage = 1 end
    pool.health = math.max(0, (tonumber(pool.health) or tonumber(pool.max_health) or 0) - damage)
    pool.last_damage = tick
    if key then state().train_shield_last_damage[key] = tick end
    state().train_shield_last_damage[event.entity.unit_number] = tick
    if pool.health > 0 then
        TRAIN_SHIELD.sync_physical_train(event.entity)
    else
        pcall(function() event.entity.die(event.force, event.cause) end)
    end
end

function train_interiors.tick_train_shield_self_repair(tick)
    if not active() then return end
    local s = state()
    local seen = {}
    for unit, wagon in pairs(s.wagons) do
        local entity = wagon and wagon.entity
        if valid(entity) and entity.unit_number and WAGON_TYPES[entity.type] then
            local pool, key = TRAIN_SHIELD.ensure_pool(entity, false)
            if pool and key and not seen[key] then
                seen[key] = true
                local level = tonumber(pool.level) or TRAIN_SHIELD.level(entity.force)
                local rate = TRAIN_SHIELD.repair_per_second(level)
                local last_damage = tonumber(pool.last_damage) or 0
                if rate > 0 and (tick - last_damage) >= TRAIN_SHIELD.repair_delay_ticks then
                    local max_health = tonumber(pool.max_health) or TRAIN_SHIELD.max_health(level)
                    local health = tonumber(pool.health) or max_health
                    if health > 0 and health < max_health then
                        pool.health = math.min(max_health, health + rate)
                    end
                end
                TRAIN_SHIELD.sync_physical_train(entity)
            end
        else
            s.wagons[unit] = nil
        end
    end
end

local function rail_front_direction()
    return defines.rail_direction and defines.rail_direction.front or 0
end

local function rail_back_direction()
    return defines.rail_direction and defines.rail_direction.back or 1
end

local function same_connected_train(a, b)
    if not (valid(a) and valid(b) and a.train and b.train and a.train.valid and b.train.valid) then return false end
    return a.train == b.train
end

-- Capacity is the Auto-Couple switch. A free researched slot allows one more
-- rolling-stock part; a full Main Train must not issue even a temporary connect
-- command. Without this preflight, the existing capacity enforcement correctly
-- disconnected an extra part, but the one-second assist scan connected it again,
-- creating an endless connect/rebuild/disconnect loop while it remained nearby.
--
-- Keep this check dynamic instead of storing a separate lock: finishing Main
-- Train Expansion research or losing a registered part immediately creates free
-- capacity, while filling the last slot immediately closes Auto-Couple again.
function train_interiors._auto_couple_capacity_allows(a, b)
    if not (valid(a) and valid(b)
        and a.train and a.train.valid and a.train.carriages
        and b.train and b.train.valid and b.train.carriages) then
        return false
    end

    local a_carriages = a.train.carriages or {}
    local b_carriages = b.train.carriages or {}
    local a_contains_main = train_interiors._train_contains_main_train(a_carriages)
    local b_contains_main = train_interiors._train_contains_main_train(b_carriages)
    if not (a_contains_main or b_contains_main) then return false end

    local force = a_contains_main and a.force or b.force
    local capacity = train_interiors._main_train_capacity(force)
    local combined_count = train_interiors._rolling_stock_count(a_carriages)
        + train_interiors._rolling_stock_count(b_carriages)
    return combined_count <= capacity
end

local function auto_couple_pair(a, b)
    if not (valid(a) and valid(b)) then return false end
    if a == b then return false end
    if not (a.unit_number and b.unit_number) then return false end
    if not (WAGON_TYPES[a.type] and WAGON_TYPES[b.type]) then return false end
    if a.surface ~= b.surface then return false end
    if is_train_surface(a.surface) then return false end
    if same_connected_train(a, b) then return false end
    if dist_sq(a.position, b.position) > TRAIN_COUPLING_ASSIST_RANGE * TRAIN_COUPLING_ASSIST_RANGE then return false end
    if not train_interiors._auto_couple_capacity_allows(a, b) then return false end

    local claimed = {}
    if a.force ~= b.force then
        local s = state()
        local main, found = a, b
        if not train_interiors._train_contains_main_train(a.train.carriages) then main, found = b, a end
        if not train_interiors._train_contains_main_train(main.train.carriages)
            or found.force ~= game.forces.neutral
            or (cave_worlds.owner_force(main.surface) ~= main.force
                and cave_teams.home_surface(main.force) ~= main.surface) then return false end
        for _, part in ipairs(found.train.carriages) do
            if not (valid(part) and s.unclaimed_train_parts[part.unit_number]
                and part.force == game.forces.neutral) then return false end
            claimed[#claimed + 1] = part
        end
        -- Neutral finds can be coupled by any team on its own world. Restore
        -- neutrality if the rails are not aligned; approaching is not claiming.
        for _, part in ipairs(claimed) do part.force = main.force end
    end

    -- Vanilla coupling can be very touchy in cave finds because the abandoned
    -- rolling stock is spawned in compact rail pockets. Try both coupler ends
    -- on both entities; Factorio will return false unless the rolling stock is
    -- actually aligned and close enough to connect.
    local front = rail_front_direction()
    local back = rail_back_direction()
    local connected = try_connect(a, front)
        or try_connect(a, back)
        or try_connect(b, front)
        or try_connect(b, back)

    if connected then
        local root = valid(a) and a or b
        if valid(root) then rebuild_train_for_entity(root) end
        return true
    end
    for _, part in ipairs(claimed) do
        if valid(part) then part.force = game.forces.neutral end
    end
    return false
end

auto_couple_nearby_trains = function()
    if not active() then return end
    local s = state()
    local tried = {}
    local range = TRAIN_COUPLING_ASSIST_RANGE
    for unit, wagon in pairs(s.wagons) do
        local entity = wagon and wagon.entity
        if valid(entity) and entity.unit_number and WAGON_TYPES[entity.type] and not is_train_surface(entity.surface) then
            local pos = entity.position
            local area = { { pos.x - range, pos.y - range }, { pos.x + range, pos.y + range } }
            for _, entity_type in pairs(TRAIN_SHIELD.types) do
                for _, candidate in pairs(entity.surface.find_entities_filtered { area = area, type = entity_type }) do
                    if valid(candidate) and candidate.unit_number and candidate.unit_number ~= entity.unit_number then
                        local a = math.min(entity.unit_number, candidate.unit_number)
                        local b = math.max(entity.unit_number, candidate.unit_number)
                        local key = tostring(a) .. ":" .. tostring(b)
                        if not tried[key] then
                            tried[key] = true
                            if auto_couple_pair(entity, candidate) then
                                return
                            end
                        end
                    end
                end
            end
        else
            s.wagons[unit] = nil
        end
    end
end

local function place_train_set(surface, force, center, include_fluid)
    -- In CAVETORIO, the Warp Outpost owns the starter footprint. Keep the
    -- starter train pad exactly inside the Level 0 25x25 Outpost; the old
    -- 40x20 train pad leaked left/right outside the first Outpost before
    -- Warp #2 normalized the surface.
    if cavetorio_enabled() then
        train_interiors._prepare_exact_train_area(surface, center, 25, 25, train_interiors.cache_config.starter_tile)
    else
        train_interiors._prepare_exact_train_area(surface, center, 40, 20, train_interiors.cache_config.starter_tile)
    end
    for x = -10, 10, 2 do
        create_rail(surface, force, { x = center.x + x, y = center.y })
    end
    -- Locomotive faces east. Wagons are directly coupled behind it to the west.
    local fluid
    if include_fluid and prototypes.entity["fluid-wagon"] then
        fluid = create_train_entity(surface, force, "fluid-wagon", { x = center.x - ROLLING_STOCK_SPACING, y = center.y })
    end
    local cargo = create_train_entity(surface, force, "cargo-wagon", { x = center.x, y = center.y })
    local loco = create_train_entity(surface, force, "locomotive", { x = center.x + ROLLING_STOCK_SPACING, y = center.y })
    if loco and loco.valid then
        local fuel = loco.get_inventory(defines.inventory.fuel)
        if fuel then
            if prototypes.item["solid-fuel"] then fuel.insert { name = "solid-fuel", count = 50 }
            else fuel.insert { name = "coal", count = 100 } end
        end
        try_connect(loco, defines.rail_direction and defines.rail_direction.back or 1)
    end
    if cargo and cargo.valid then
        try_connect(cargo, defines.rail_direction and defines.rail_direction.back or 1)
        try_connect(cargo, defines.rail_direction and defines.rail_direction.front or 0)
    end
    if fluid and fluid.valid then
        try_connect(fluid, defines.rail_direction and defines.rail_direction.front or 0)
    end
    if loco then rebuild_train_for_entity(loco) end
    return loco, cargo, fluid
end

local function find_starter_train_position(surface, origin, avoid_bases)
    local offsets = {
        {0, 12}, {0, -12}, {12, 0}, {-12, 0},
        {14, 14}, {-14, 14}, {14, -14}, {-14, -14},
        {0, 20}, {0, -20}, {20, 0}, {-20, 0},
    }
    if avoid_bases then
        -- Shared worlds keep the original first offset, then find room beside
        -- existing teams instead of laying the new train over their base.
        for radius = 32, 256, 32 do
            for x = -radius, radius, 32 do
                offsets[#offsets + 1] = { x, radius }
                offsets[#offsets + 1] = { x, -radius }
            end
            for y = -radius + 32, radius - 32, 32 do
                offsets[#offsets + 1] = { radius, y }
                offsets[#offsets + 1] = { -radius, y }
            end
        end
    end
    for _, off in ipairs(offsets) do
        local center = { x = origin.x + off[1], y = origin.y + off[2] }
        local available = true
        if avoid_bases then
            local area = { { center.x - 21, center.y - 13 }, { center.x + 21, center.y + 13 } }
            for _, entity in pairs(surface.find_entities_filtered { area = area }) do
                if valid(entity) and (WAGON_TYPES[entity.type]
                    or (entity.type ~= "character" and entity.force ~= game.forces.neutral
                        and entity.force ~= game.forces.enemy)) then
                    available = false
                    break
                end
            end
        end
        if available then return center end
    end
    return nil
end

-- Returns the first starter-train centre, never the train's current position.
-- Older saves did not retain that centre; their static Force spawn plus the
-- established starter offset reconstructs it without consulting a moved train.
function train_interiors.initial_starter_train_center(surface, force)
    if not active() or not (surface and surface.valid and force and force.valid) then return nil end
    local s = state()
    local existing = s.starter_train_centers[force.index]
    if existing and existing.surface_index == surface.index
        and (not existing.surface_name or existing.surface_name == surface.name)
        and tonumber(existing.x) and tonumber(existing.y) then
        return { x = existing.x, y = existing.y }
    end
    if not s.spawned_forces[force.index] then return nil end
    local origin = force.get_spawn_position(surface) or { x = 0, y = 0 }
    local center = find_starter_train_position(surface, origin)
    s.starter_train_centers[force.index] = {
        x = center.x,
        y = center.y,
        surface_index = surface.index,
        surface_name = surface.name,
    }
    return { x = center.x, y = center.y }
end

function train_interiors.on_arrival(player)
    if not active() or not (player and player.valid) then return false end
    if player.controller_type ~= defines.controllers.character or not valid(player.character) then return false end
    local force = player.character.force
    if train_interiors.has_base(force) then return true end
    local s = state()
    if s.spawned_forces[force.index] then return false end
    local surface = player.character.surface
    if not cave_worlds.is_cave_world(surface) or cave_worlds.is_template(surface) then return false end
    if cave_worlds.is_copy(surface) and cave_worlds.owner_force(surface) ~= force then return false end
    local origin = player.character.position
    local shared = false
    for _, wagon in pairs(s.wagons) do
        if valid(wagon.entity) and wagon.entity.surface == surface and wagon.entity.force ~= force then
            shared = true
            break
        end
    end
    local center = find_starter_train_position(surface, origin, shared)
    if not center then
        player.print("[The Cave] No free space for a starter train near this arrival.")
        return false
    end
    s.starter_layout_normalized_forces = s.starter_layout_normalized_forces or {}
    s.starter_layout_normalized_forces[force.index] = false
    local loco, cargo, fluid = place_train_set(surface, force, center, true)
    if loco or cargo or fluid then
        s.starter_train_centers[force.index] = {
            x = center.x,
            y = center.y,
            surface_index = surface.index,
            surface_name = surface.name,
        }
        s.spawned_forces[force.index] = true
        player.print("[The Cave] Starter Train placed nearby: 1 locomotive, 1 cargo wagon and 1 fluid wagon.")
    else
        s.starter_layout_normalized_forces[force.index] = nil
        player.print("[The Cave] Starter Train could not be placed. Check for rail/rolling stock prototype conflicts.")
    end
    return train_interiors.has_base(force)
end

-- The arrival coordinator waits for lobbies and deferred team teleports.
train_interiors.spawn_starter_train_for_player = train_interiors.on_arrival

function train_interiors.on_player_created(event)
end

-- Resolve the Main Train at the moment of joining. A force spawn point is
-- static and remains at the original map start after the train has moved, so it
-- must never be used as the Train Interiors join destination. Lobby and Soft
-- Reset guards run in control.lua before this handler.
function train_interiors.on_player_joined_game(event)
    if not active() then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local target = train_interiors.get_player_recovery_target(player)
    if target and target.surface and target.surface.valid and target.position then
        physical.teleport(player, target.position, target.surface)
    end
end

function train_interiors.on_player_respawned(event)
    if not active() then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local target = train_interiors.get_player_recovery_target(player)
    if target and target.surface and target.surface.valid and target.position then
        physical.teleport(player, target.position, target.surface)
    end
end

function train_interiors.on_player_changed_surface(event)
    if not active() then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    if train_interiors._clear_train_entry_prompt then train_interiors._clear_train_entry_prompt(player) end
    if not is_train_surface(physical.surface(player)) then train_interiors.kill_minimap(player) end
end

function train_interiors.on_player_left_game(event)
    local player = game.get_player(event.player_index)
    if player then
        if train_interiors._clear_train_entry_prompt then train_interiors._clear_train_entry_prompt(player) end
        train_interiors.kill_minimap(player)
    end
end

function train_interiors._chunk_key(surface, pos)
    return tostring(surface.index) .. ":" .. tostring(pos.x) .. ":" .. tostring(pos.y)
end

function train_interiors._train_cache_zone_id(position)
    local level = depth_levels.level_for_position(position)
    return (level and level.id) or "easy"
end

function train_interiors._cache_too_close(surface, center)
    local s = state()
    for _, cache in pairs(s.cache_centers or {}) do
        if cache.surface_index == surface.index then
            local dx = (cache.x or 0) - center.x
            local dy = (cache.y or 0) - center.y
            if dx * dx + dy * dy < TRAIN_CACHE_MIN_DISTANCE * TRAIN_CACHE_MIN_DISTANCE then return true end
        end
    end
    return false
end

function train_interiors._remember_cache(surface, center, zone_id, part_name)
    local s = state()
    s.cache_centers[#s.cache_centers + 1] = {
        surface_index = surface.index,
        x = center.x,
        y = center.y,
        zone_id = zone_id,
        part_name = part_name,
    }
end

function train_interiors._choose_abandoned_train_part(seed, chunk_pos)
    local total = 0
    for _, candidate in pairs(train_interiors.cache_config.type_weights) do
        if prototypes and prototypes.entity and prototypes.entity[candidate.name] then
            total = total + candidate.weight
        end
    end
    if total <= 0 then return nil end
    local roll = hash.range(seed, chunk_pos.x, chunk_pos.y, WAGON_PICK_STREAM, 1, total)
    local cursor = 0
    for _, candidate in pairs(train_interiors.cache_config.type_weights) do
        if prototypes and prototypes.entity and prototypes.entity[candidate.name] then
            cursor = cursor + candidate.weight
            if roll <= cursor then return candidate.name end
        end
    end
    return "cargo-wagon"
end

function train_interiors._prepare_abandoned_train_part_site(surface, center)
    -- Abandoned site: exact 10-long by 4-wide pad (4x10 footprint), three straight rails, one train part.
    -- The chunk that owns this centre is already generated. Do not call the
    -- generic train-area helper here: it force-generates neighbouring chunks,
    -- which can recursively enter this guaranteed cache generator.
    local left, top, right, bottom = train_interiors._exact_rect_bounds(center, 10, 4)
    train_interiors._fill_rect_tiles(surface, left, top, 10, 4, train_interiors.cache_config.site_tile)
    clear_area(surface, { { left, top }, { right, bottom } })
    for x = -2, 2, 2 do
        create_rail(surface, game.forces.neutral, { x = center.x + x, y = center.y })
    end
end

function train_interiors._hide_cache_chunk(surface, chunk_pos)
    -- Best effort: if cave charting generated this chunk before the player physically reached it,
    -- uncharting keeps abandoned train finds from being spoiled on the map.
    for _, force in pairs(game.forces) do
        pcall(function() force.unchart_chunk(chunk_pos, surface) end)
    end
end

function train_interiors.on_chunk_generated(event)
    -- Guaranteed abandoned train-part finds in newly generated cave chunks.
    -- Once exploration reaches a chunk centre at least 18 chunks (576 tiles) from every
    -- previous find, place the next part. The Main Train's separate capacity
    -- limit remains authoritative, so world finds do not need zone/global caps.
    if not active() then return end
    local surface = event and event.surface
    if not (surface and surface.valid) then return end
    if train_interiors._is_garden_surface(surface) then
        local garden = train_interiors._garden_for_surface(surface)
        if not train_interiors._garden_chunk_void_is_current(garden, surface, event.position) then
            train_interiors._void_garden_area(surface, event.area, garden)
            train_interiors._mark_garden_chunk_voided(garden, surface, event.position)
        end
        return
    end
    if surface.name ~= "nauvis" then return end
    local pos = event.position
    if not pos then return end
    local key = train_interiors._chunk_key(surface, pos)
    local s = state()
    if s.cache_chunks[key] then return end
    s.cache_chunks[key] = true

    local center = { x = pos.x * 32 + 16, y = pos.y * 32 + 16 }
    local zone_id = train_interiors._train_cache_zone_id(center)
    if train_interiors._cache_too_close(surface, center) then return end

    local seed = surface.map_gen_settings and surface.map_gen_settings.seed or 1
    local picked = train_interiors._choose_abandoned_train_part(seed, pos)
    if not picked then return end
    train_interiors._prepare_abandoned_train_part_site(surface, center)
    local entity = create_train_entity(surface, game.forces.neutral, picked, center, false)
    if entity then
        train_interiors._remember_cache(surface, center, zone_id, picked)
        train_interiors._hide_cache_chunk(surface, pos)
    end
end

function train_interiors.on_chunk_charted(event)
    if not (active() and event and game) then return false end
    local surface = event.surface_index and game.surfaces[event.surface_index]
    if not train_interiors._is_garden_surface(surface) then return false end
    local garden = train_interiors._garden_for_surface(surface)
    if not train_interiors._garden_chunk_void_is_current(garden, surface, event.position) then
        train_interiors._void_garden_area(surface, event.area, garden)
        train_interiors._mark_garden_chunk_voided(garden, surface, event.position)
    end
    return true
end

return train_interiors
