local settings = require("scripts.game_settings").proxy(settings)

-- Optional Mobile Factory Space Age resource compatibility.
--
-- The Cave replaces Factorio's map generator with a runtime-opened void world,
-- so Mobile Factory's normal Nauvis autoplace can never reveal its two natural
-- resources. This module recreates only those two resources while preserving
-- The Cave's dig-to-reveal rules:
--   * DimensionalOre is a translated copy of the mixed simplex tendril, giving
--     it one separate, continuous vein beside the normal mixed vein.
--   * Every crude-oil well owns one reserved DimensionalFluid target exactly
--     ten tiles away. The target appears only after that cave tile is opened.
local Simplex = require("scripts.lib.simplex")
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local advancing_zones = require("scripts.advancing_zones")
local bob_ore_layout = require("scripts.bob_ore_layout")
local cave_worlds = require("scripts.cave_worlds")

local mobile = {}

local MOD_NAME = "Mobile_Factory_Space_Age"
local ORE_NAME = "DimensionalOre"
local FLUID_NAME = "DimensionalFluid"
local FACTORY_SURFACE_PREFIX = "mfSurface"
local CONTROL_ROOM_SURFACE_PREFIX = "ControlRoom"

local TENDRIL_SCALE = 1 / 40
local MIXED_SEED_OFFSET = 1100
local MIXED_WIDTH = 0.058
local ORE_OFFSET = 8
local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value

-- Unique deterministic streams for this integration.
local S_ORE_DIRECTION = 6500
local S_ORE_AMOUNT = 6501
local S_FLUID_DIRECTION = 6502

local RESOURCE_SIZE_MULTIPLIERS = {
    ["level-1"] = 1,
    ["level-2"] = 2,
    ["level-3"] = 3,
    ["level-4"] = 4,
    ["level-5"] = 5,
    ["level-6"] = 6,
    ["level-7"] = 7,
    ["level-8"] = 8,
    small = 1,
    medium = 2,
    large = 4,
    huge = 8,
}

local ORE_TILE_AMOUNTS = {
    easy = { min = 250, max = 625 },
    medium = { min = 625, max = 875 },
    hard = { min = 875, max = 1250 },
    nightmare = { min = 1250, max = 2000 },
}

local ORE_DIRECTIONS = {
    { x = 1, y = 0 },
    { x = 0, y = 1 },
    { x = -1, y = 0 },
    { x = 0, y = -1 },
}

-- Every integer vector below has length exactly 10. The extra 6/8 vectors give
-- the deterministic selector alternatives when a cardinal target is occupied.
local FLUID_OFFSETS = {
    { x = 10, y = 0 },
    { x = 8, y = 6 },
    { x = 6, y = 8 },
    { x = 0, y = 10 },
    { x = -6, y = 8 },
    { x = -8, y = 6 },
    { x = -10, y = 0 },
    { x = -8, y = -6 },
    { x = -6, y = -8 },
    { x = 0, y = -10 },
    { x = 6, y = -8 },
    { x = 8, y = -6 },
}

local function mod_active()
    return script and script.active_mods and script.active_mods[MOD_NAME] ~= nil
end

local function enabled()
    if not mod_active() then return false end
    return prototypes
        and prototypes.entity
        and prototypes.entity[ORE_NAME]
        and prototypes.entity[FLUID_NAME]
end

-- Mobile Factory owns the lighting and safety rules of its private surfaces.
-- Keep this check independent from resource-prototype availability so the
-- compatibility exclusion still works if a future Mobile Factory version
-- changes either resource prototype.
function mobile.is_interior_surface(surface)
    if not (mod_active() and surface and surface.valid and type(surface.name) == "string") then
        return false
    end

    local name = surface.name
    return name:sub(1, #FACTORY_SURFACE_PREFIX) == FACTORY_SURFACE_PREFIX
        or name:sub(1, #CONTROL_ROOM_SURFACE_PREFIX) == CONTROL_ROOM_SURFACE_PREFIX
end

-- The Cave 2.7.11 and earlier applied the selected cave-lighting profile to
-- every game surface once per second. Restore only the neutral properties that
-- can remain stuck after upgrading; Mobile Factory itself continues to own
-- daytime and freeze_daytime.
function mobile.restore_interior_lighting()
    if not (mod_active() and game and game.surfaces) then return end

    for _, surface in pairs(game.surfaces) do
        if mobile.is_interior_surface(surface) then
            pcall(function() surface.always_day = false end)
            pcall(function() surface.min_brightness = 0.15 end)
            pcall(function() surface.brightness_visual_weights = { r = 0, g = 0, b = 0 } end)
            pcall(function() surface.show_clouds = true end)
            pcall(function() surface.solar_power_multiplier = 1 end)
        end
    end
end

local function supported_surface(surface)
    return cave_worlds.is_cave_world(surface)
end

local function central_nauvis_region(x, y)
    if advancing_zones.is_active() then
        return advancing_zones.region_at(x, y) == "nauvis"
    end
    local everything = settings and settings.startup and settings.startup["the-cave-everything-on-nauvis"]
    local everything_enabled = not everything or everything.value == "enabled" or everything.value == true
    local space_age = script and script.active_mods and script.active_mods["space-age"]
    if not (everything_enabled and space_age) then return true end
    return x * x + y * y < 1000 * 1000
end

local function resource_patch_size_multiplier()
    local setting = settings and settings.startup and settings.startup["the-cave-resource-patch-size"]
    local value = setting and setting.value or "level-2"
    return RESOURCE_SIZE_MULTIPLIERS[value] or RESOURCE_SIZE_MULTIPLIERS["level-2"]
end

local function tile_accepts_resource(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    local name = tile.name or ""
    if name == "out-of-map" then return false end
    if name:find("water", 1, true) or name:find("ocean", 1, true) or name:find("lava", 1, true) then
        return false
    end
    local resources = surface.find_entities_filtered {
        area = { { x, y }, { x + 1, y + 1 } },
        type = "resource",
    }
    return not resources or #resources == 0
end

local function materialize_ore(surface, tile_x, tile_y)
    if not central_nauvis_region(tile_x, tile_y) then return nil end
    if bob_ore_layout.is_reserved(surface, tile_x, tile_y) then return nil end
    if not tile_accepts_resource(surface, tile_x, tile_y) then return nil end

    local seed = surface.map_gen_settings.seed or 0
    local direction_index = hash.range(seed, 0, 0, S_ORE_DIRECTION, 1, #ORE_DIRECTIONS)
    local direction = ORE_DIRECTIONS[direction_index]
    local source_x = tile_x - direction.x * ORE_OFFSET
    local source_y = tile_y - direction.y * ORE_OFFSET
    local source_center_x = source_x + 0.5
    local source_center_y = source_y + 0.5
    local source_distance = math.sqrt(source_center_x * source_center_x + source_center_y * source_center_y)
    if source_distance <= CARVE_RADIUS + 4 then return nil end

    local noise = Simplex.d2(
        source_center_x * TENDRIL_SCALE,
        source_center_y * TENDRIL_SCALE,
        seed + MIXED_SEED_OFFSET
    )
    if math.abs(noise) >= MIXED_WIDTH * resource_patch_size_multiplier() then return nil end

    local target_center_x = tile_x + 0.5
    local target_center_y = tile_y + 0.5
    local target_distance = math.sqrt(target_center_x * target_center_x + target_center_y * target_center_y)
    local level = depth_levels.level_for_distance(target_distance)
    local range = ORE_TILE_AMOUNTS[level.id] or ORE_TILE_AMOUNTS.easy
    local amount = hash.range(seed, tile_x, tile_y, S_ORE_AMOUNT, range.min, range.max)
    return surface.create_entity {
        name = ORE_NAME,
        position = { target_center_x, target_center_y },
        amount = amount,
    }
end

local function state()
    storage.the_cave_mobile_factory_resources = storage.the_cave_mobile_factory_resources or {}
    local root = storage.the_cave_mobile_factory_resources
    root.version = 1
    root.oil_pairs = root.oil_pairs or {}
    return root
end

local function surface_pairs(surface_index)
    local root = state()
    root.oil_pairs[surface_index] = root.oil_pairs[surface_index] or {}
    return root.oil_pairs[surface_index]
end

local function position_key(x, y)
    return math.floor(x) .. ":" .. math.floor(y)
end

local function resource_at(surface, name, x, y)
    local found = surface.find_entities_filtered {
        name = name,
        position = { x + 0.5, y + 0.5 },
        radius = 0.2,
        limit = 1,
    }
    return found and found[1] or nil
end

local function pumpjack_footprint_is_clear(surface, x, y)
    local resources = surface.find_entities_filtered {
        type = "resource",
        area = {
            { x - 1, y - 1 },
            { x + 2, y + 2 },
        },
    }
    return not resources or #resources == 0
end

local function target_reserved_near(pair_records, oil_key, x, y)
    for other_key, record in pairs(pair_records) do
        if other_key ~= oil_key and record.target_x and record.target_y then
            local dx = record.target_x - x
            local dy = record.target_y - y
            -- Three-wide pumpjack footprints must not overlap. A separation of
            -- three tiles is edge-to-edge; anything closer is rejected.
            if dx * dx + dy * dy < 9 then return true end
        end
    end
    return false
end

local function hidden_or_dry_target(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    local name = tile.name or ""
    if name == "out-of-map" then return true end
    return not name:find("water", 1, true)
        and not name:find("ocean", 1, true)
        and not name:find("lava", 1, true)
end

local function target_is_open(surface, x, y, opened_x, opened_y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    local name = tile.name or ""
    if name == "out-of-map" or name:find("water", 1, true)
        or name:find("ocean", 1, true) or name:find("lava", 1, true) then
        return false
    end

    if opened_x == x and opened_y == y then
        -- on_player_mined_entity fires before the dying diggy-rock is removed.
        -- The tile is nevertheless open for this deterministic dig outcome.
        return true
    end

    local covers = surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-rubble", "diggy-tree" },
        area = { { x, y }, { x + 1, y + 1 } },
        limit = 1,
    }
    return not covers or #covers == 0
end

local function adopt_existing_fluid(surface, oil, pair_records, oil_key)
    local fluids = surface.find_entities_filtered {
        name = FLUID_NAME,
        position = oil.position,
        radius = 10.1,
    }
    for _, fluid in pairs(fluids or {}) do
        if fluid.valid then
            local dx = fluid.position.x - oil.position.x
            local dy = fluid.position.y - oil.position.y
            if math.abs(dx * dx + dy * dy - 100) < 0.01 then
                local target_x, target_y = math.floor(fluid.position.x), math.floor(fluid.position.y)
                if not target_reserved_near(pair_records, oil_key, target_x, target_y) then
                    return {
                        oil_x = math.floor(oil.position.x),
                        oil_y = math.floor(oil.position.y),
                        target_x = target_x,
                        target_y = target_y,
                        amount = tonumber(oil.amount) or 60000,
                        spawned = true,
                    }
                end
            end
        end
    end
    return nil
end

local function choose_target(surface, oil, pair_records, oil_key)
    local oil_x = math.floor(oil.position.x)
    local oil_y = math.floor(oil.position.y)
    local seed = surface.map_gen_settings.seed or 0
    local first = hash.range(seed, oil_x, oil_y, S_FLUID_DIRECTION, 1, #FLUID_OFFSETS)

    for offset_index = 0, #FLUID_OFFSETS - 1 do
        local offset = FLUID_OFFSETS[((first + offset_index - 1) % #FLUID_OFFSETS) + 1]
        local target_x = oil_x + offset.x
        local target_y = oil_y + offset.y
        local existing = resource_at(surface, FLUID_NAME, target_x, target_y)
        if existing and existing.valid
            and not target_reserved_near(pair_records, oil_key, target_x, target_y) then
            return target_x, target_y, true
        end
        if hidden_or_dry_target(surface, target_x, target_y)
            and pumpjack_footprint_is_clear(surface, target_x, target_y)
            and not target_reserved_near(pair_records, oil_key, target_x, target_y) then
            return target_x, target_y, false
        end
    end
    return nil, nil, false
end

local function release_target(record)
    record.target_x = nil
    record.target_y = nil
end

local function try_materialize_pair(surface, oil, record, opened_x, opened_y)
    if record.spawned then return true end
    if not (record.target_x and record.target_y) then return false end

    local target_x, target_y = record.target_x, record.target_y
    local existing = resource_at(surface, FLUID_NAME, target_x, target_y)
    if existing and existing.valid then
        record.spawned = true
        return true
    end
    if not target_is_open(surface, target_x, target_y, opened_x, opened_y) then return false end
    if not pumpjack_footprint_is_clear(surface, target_x, target_y) then
        release_target(record)
        return false
    end

    local amount = tonumber(record.amount) or tonumber(oil.amount) or 60000
    local created = surface.create_entity {
        name = FLUID_NAME,
        position = { target_x + 0.5, target_y + 0.5 },
        amount = amount,
    }
    if created and created.valid then
        record.spawned = true
        return true
    end
    release_target(record)
    return false
end

local function ensure_oil_pair(surface, oil, opened_x, opened_y)
    if not (oil and oil.valid) then return false end
    local pair_records = surface_pairs(surface.index)
    local oil_x = math.floor(oil.position.x)
    local oil_y = math.floor(oil.position.y)
    local oil_key = position_key(oil_x, oil_y)
    local record = pair_records[oil_key]

    if not record then
        record = adopt_existing_fluid(surface, oil, pair_records, oil_key)
        if not record then
            local target_x, target_y, spawned = choose_target(surface, oil, pair_records, oil_key)
            if not target_x then return false end
            record = {
                oil_x = oil_x,
                oil_y = oil_y,
                target_x = target_x,
                target_y = target_y,
                amount = tonumber(oil.amount) or 60000,
                spawned = spawned,
            }
        end
        pair_records[oil_key] = record
    end

    if try_materialize_pair(surface, oil, record, opened_x, opened_y) then return true end
    if record.target_x then return false end

    -- A previously reserved tile can become water or receive another resource
    -- when it is opened. Pick the next exact-distance alternative and retry.
    local target_x, target_y, spawned = choose_target(surface, oil, pair_records, oil_key)
    if not target_x then return false end
    record.target_x = target_x
    record.target_y = target_y
    record.spawned = spawned
    return try_materialize_pair(surface, oil, record, opened_x, opened_y)
end

local function pair_nearby_oil(surface, position, radius, opened_x, opened_y)
    local wells = surface.find_entities_filtered {
        name = "crude-oil",
        position = position,
        radius = radius,
    }
    for _, oil in pairs(wells or {}) do
        ensure_oil_pair(surface, oil, opened_x, opened_y)
    end
end

local function pair_oil_in_room(surface, room_plan)
    if not (room_plan and room_plan.x1 and room_plan.y1 and room_plan.x2 and room_plan.y2) then return end
    local wells = surface.find_entities_filtered {
        name = "crude-oil",
        area = {
            { room_plan.x1 - 2, room_plan.y1 - 2 },
            { room_plan.x2 + 3, room_plan.y2 + 3 },
        },
    }
    for _, oil in pairs(wells or {}) do
        ensure_oil_pair(surface, oil)
    end
end

local function process_open_tile(surface, tile_x, tile_y)
    if not (enabled() and supported_surface(surface)) then return end
    materialize_ore(surface, tile_x, tile_y)
    pair_nearby_oil(surface, { x = tile_x + 0.5, y = tile_y + 0.5 }, 12, tile_x, tile_y)
end

function mobile.on_init()
    if enabled() then state() end
end

function mobile.on_configuration_changed()
    mobile.restore_interior_lighting()
    if not enabled() then return end
    state()
    -- Upgrade existing saves: reserve or materialize one companion for every
    -- already discovered oil well on each supported Cave surface.
    for _, surface in pairs(game.surfaces) do
        if supported_surface(surface) then
            local wells = surface.find_entities_filtered { name = "crude-oil" }
            for _, oil in pairs(wells or {}) do
                ensure_oil_pair(surface, oil)
            end
        end
    end
end

function mobile.on_dig(dig)
    if not (dig and dig.surface and dig.position) then return end
    process_open_tile(dig.surface, math.floor(dig.position.x), math.floor(dig.position.y))
end

function mobile.on_open_tile(surface, tile_x, tile_y)
    process_open_tile(surface, tile_x, tile_y)
end

function mobile.on_post_dig(dig, room_plan)
    if not (enabled() and dig and dig.surface and dig.position and supported_surface(dig.surface)) then return end
    -- Progression rooms can place a fixed oil well after all their tiles were
    -- carved. Sweep the returned room bounds so even a long entrance tunnel
    -- cannot leave that late-created well unpaired.
    pair_oil_in_room(dig.surface, room_plan)
end

function mobile.on_surface_deleted(event)
    local root = storage.the_cave_mobile_factory_resources
    if root and root.oil_pairs and event and event.surface_index then
        root.oil_pairs[event.surface_index] = nil
    end
end

return mobile
