local settings = require("scripts.game_settings").proxy(settings)

-- The frontier void world (ADR 0007). Chunks generate as out-of-map; this
-- module builds the world at runtime: the spawn carve-out, floor reveals,
-- frontier-wall advancement, and water pools. Everything is seed-keyed
-- (ADR 0005) — identical digging yields identical worlds across teams.
local Simplex = require("scripts.lib.simplex")
local hash = require("scripts.lib.hash")
local mirror = require("scripts.lib.mirror")
local ore_veins = require("scripts.ore_veins")
local region_features = require("scripts.region_features")
local mobile_factory_resources = require("scripts.mobile_factory_resources")
local bob_ores_resources = require("scripts.bob_ores_resources")
local ore_missing = require("scripts.ore_missing")
local advancing_zones = require("scripts.advancing_zones")
local cave_worlds = require("scripts.cave_worlds")

local world = {}

local uranium_caves_api
local mineral_caves_api

function world.configure_extraction_cave_apis(uranium_api, mineral_api)
    assert(type(uranium_api) == "table" and type(uranium_api.materialize_uranium) == "function",
        "The Cave: Uranium Cave world API is unavailable")
    assert(type(mineral_api) == "table" and type(mineral_api.materialize_mineral) == "function",
        "The Cave: Mineral Cave world API is unavailable")
    uranium_caves_api = uranium_api
    mineral_caves_api = mineral_api
end

local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value

-- Hash stream ids (keep unique across all dig modules).
local S_FLOOR, S_WALL_TREE, S_STARTER, S_STARTER_ORE, S_FISH = 50, 51, 52, 53, 54
local S_STARTER_SHAPE = 55

local WATER = { scale = 1 / 30, seed = 8800, threshold = 0.78, flood_cap = 200 }
local STARTER_ORES = { "iron-ore", "copper-ore", "coal", "stone" }

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function is_uranium_cave_surface(surface)
    return surface
        and surface.valid
        and type(surface.name) == "string"
        and surface.name:find("^the%-cave%-uranium%-cave%-") ~= nil
end

local function is_mineral_cave_surface(surface)
    return surface
        and surface.valid
        and type(surface.name) == "string"
        and surface.name:find("^the%-cave%-mineral%-cave%-") ~= nil
end

local function uranium_caves_module()
    return uranium_caves_api
end

local function mineral_caves_module()
    return mineral_caves_api
end

local function is_cave_world_surface(surface)
    if not (surface and surface.valid) then return false end
    return cave_worlds.is_original(surface)
        or is_uranium_cave_surface(surface)
        or is_mineral_cave_surface(surface)
end

world.is_uranium_cave_surface = is_uranium_cave_surface
world.is_mineral_cave_surface = is_mineral_cave_surface
world.is_cave_world_surface = is_cave_world_surface

local function cavetorio_enabled()
    local st = settings and settings.startup and settings.startup["the-cave-cavetorio"]
    return st and st.value == "enabled"
end


local function pick_starter_ore(seed, x, y)
    local ores = ore_missing.filter_resource_names(STARTER_ORES)
    if #ores == 0 then ores = STARTER_ORES end
    return ores[hash.range(seed, x, y, S_STARTER_ORE, 1, #ores)]
end


-- The Cave 2.1.5: random starter-room silhouettes.
-- Uses the same size budget as the old circular spawn cave, but picks a
-- deterministic shape per new map seed.  Line/tunnel is intentionally excluded
-- from the starter pool so a new player never begins inside a narrow corridor.
-- Double-room is allowed as a slightly larger but still capped starter variant.
local STARTER_SHAPES = { "circle", "square", "rectangle", "l", "cross", "t", "u", "double" }

local function starter_shape(seed)
    return STARTER_SHAPES[hash.range(seed, 0, 0, S_STARTER_SHAPE, 1, #STARTER_SHAPES)] or "circle"
end

local function starter_shape_params(seed, shape, radius)
    if shape == "square" then
        local half = math.max(4, math.floor(radius * 0.78 + 0.5))
        return { half = half }
    end
    if shape == "rectangle" then
        local long = math.max(6, math.floor(radius * 1.15 + 0.5))
        local short = math.max(3, math.floor(radius * 0.50 + 0.5))
        local horizontal = hash.roll(seed, 0, 0, S_STARTER_SHAPE + 101) < 0.5
        return { long = long, short = short, horizontal = horizontal }
    end
    if shape == "l" then
        local arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        local width = math.max(3, math.floor(radius * 0.38 + 0.5))
        local sx = hash.roll(seed, 0, 0, S_STARTER_SHAPE + 103) < 0.5 and -1 or 1
        local sy = hash.roll(seed, 0, 0, S_STARTER_SHAPE + 104) < 0.5 and -1 or 1
        return { arm = arm, width = width, sx = sx, sy = sy }
    end
    if shape == "cross" then
        local arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        local width = math.max(2, math.floor(radius * 0.30 + 0.5))
        return { arm = arm, width = width }
    end
    if shape == "t" then
        local arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        local width = math.max(2, math.floor(radius * 0.30 + 0.5))
        local stem = math.max(6, math.floor(radius * 0.95 + 0.5))
        local dir = hash.range(seed, 0, 0, S_STARTER_SHAPE + 105, 1, 4)
        return { arm = arm, width = width, stem = stem, dir = dir }
    end
    if shape == "u" then
        local arm = math.max(7, math.floor(radius * 0.95 + 0.5))
        local width = math.max(2, math.floor(radius * 0.28 + 0.5))
        local gap = math.max(4, math.floor(radius * 0.55 + 0.5))
        local dir = hash.range(seed, 0, 0, S_STARTER_SHAPE + 106, 1, 4)
        return { arm = arm, width = width, gap = gap, dir = dir }
    end
    if shape == "double" then
        local lobe = math.max(4, math.floor(radius * 0.58 + 0.5))
        local gap = math.max(5, math.floor(radius * 0.78 + 0.5))
        local corridor = math.max(1, math.floor(radius * 0.18 + 0.5))
        local horizontal = hash.roll(seed, 0, 0, S_STARTER_SHAPE + 107) < 0.5
        return { lobe = lobe, gap = gap, corridor = corridor, horizontal = horizontal }
    end
    return {}
end

local function starter_inside_shape(x, y, radius, shape, params)
    if shape == "square" then
        return math.abs(x) <= params.half and math.abs(y) <= params.half
    end
    if shape == "rectangle" then
        if params.horizontal then
            return math.abs(x) <= params.long and math.abs(y) <= params.short
        end
        return math.abs(x) <= params.short and math.abs(y) <= params.long
    end
    if shape == "l" then
        local width, arm, sx, sy = params.width, params.arm, params.sx, params.sy
        local horizontal = math.abs(y) <= width and x >= math.min(-width, sx * arm) and x <= math.max(width, sx * arm)
        local vertical = math.abs(x) <= width and y >= math.min(-width, sy * arm) and y <= math.max(width, sy * arm)
        return horizontal or vertical
    end
    if shape == "cross" then
        local width, arm = params.width, params.arm
        return (math.abs(x) <= arm and math.abs(y) <= width) or (math.abs(x) <= width and math.abs(y) <= arm)
    end
    if shape == "t" then
        local arm, width, stem, dir = params.arm, params.width, params.stem, params.dir
        if dir == 1 then
            return (math.abs(x) <= arm and math.abs(y) <= width) or (math.abs(x) <= width and y >= 0 and y <= stem)
        elseif dir == 2 then
            return (math.abs(x) <= arm and math.abs(y) <= width) or (math.abs(x) <= width and y <= 0 and y >= -stem)
        elseif dir == 3 then
            return (math.abs(x) <= width and math.abs(y) <= arm) or (math.abs(y) <= width and x >= 0 and x <= stem)
        end
        return (math.abs(x) <= width and math.abs(y) <= arm) or (math.abs(y) <= width and x <= 0 and x >= -stem)
    end
    if shape == "u" then
        local arm, width, gap, dir = params.arm, params.width, params.gap, params.dir
        if dir == 1 then
            return (math.abs(x) <= gap + width and math.abs(y) <= width)
                or (math.abs(x + gap) <= width and y >= -arm and y <= width)
                or (math.abs(x - gap) <= width and y >= -arm and y <= width)
        elseif dir == 2 then
            return (math.abs(x) <= gap + width and math.abs(y) <= width)
                or (math.abs(x + gap) <= width and y >= -width and y <= arm)
                or (math.abs(x - gap) <= width and y >= -width and y <= arm)
        elseif dir == 3 then
            return (math.abs(y) <= gap + width and math.abs(x) <= width)
                or (math.abs(y + gap) <= width and x >= -arm and x <= width)
                or (math.abs(y - gap) <= width and x >= -arm and x <= width)
        end
        return (math.abs(y) <= gap + width and math.abs(x) <= width)
            or (math.abs(y + gap) <= width and x >= -width and x <= arm)
            or (math.abs(y - gap) <= width and x >= -width and x <= arm)
    end
    if shape == "double" then
        local lobe, gap, corridor = params.lobe, params.gap, params.corridor
        if params.horizontal then
            local left = (x + gap) * (x + gap) + y * y <= lobe * lobe
            local right = (x - gap) * (x - gap) + y * y <= lobe * lobe
            local hall = x >= -gap and x <= gap and math.abs(y) <= corridor
            return left or right or hall
        end
        local top = x * x + (y + gap) * (y + gap) <= lobe * lobe
        local bottom = x * x + (y - gap) * (y - gap) <= lobe * lobe
        local hall = y >= -gap and y <= gap and math.abs(x) <= corridor
        return top or bottom or hall
    end
    return x * x + y * y <= radius * radius
end

local function the_cave_startup_enabled(name, default_enabled)
    local setting = settings.startup[name]
    if not setting then return default_enabled ~= false end
    return setting.value == "enabled" or setting.value == true
end

local function the_cave_space_age_enabled()
    if advancing_zones.is_active() then return advancing_zones.space_age_available() end
    if not the_cave_startup_enabled("the-cave-everything-on-nauvis", true) then return false end
    return script and script.active_mods and script.active_mods["space-age"] ~= nil
end

local function tc_planet_region(x, y)
    if advancing_zones.is_active() then return advancing_zones.region_at(x, y) end
    -- Space Age regions are optional. Without Space Age, keep the whole cave
    -- in normal Nauvis/base-game mode so the mod works without the expansion.
    if not the_cave_space_age_enabled() then return "nauvis" end

    local ax, ay = math.abs(x), math.abs(y)
    local dist2 = x * x + y * y
    if dist2 < 1000 * 1000 then return "nauvis" end
    -- Nauvis ends at the 1000-tile radius. Every position beyond that circle
    -- belongs to the dominant-axis Space Age region; no diagonal Nauvis gaps.
    if ay >= ax then
        return y >= 0 and "gleba" or "aquilo"
    end
    return x < 0 and "vulcanus" or "fulgora"
end

-- Space Age resources that must never exist in the central Nauvis cave.
-- They are created deterministically by region_features.lua only after the
-- player reaches the matching region beyond the 1000-tile Nauvis radius.
local TC_SCRIPTED_PLANETARY_RESOURCES = {
    "calcite",
    "tungsten-ore",
    "sulfuric-acid-geyser",
    "scrap",
    "lithium-brine",
    "fluorine-vent",
}

local function is_main_nauvis_cave_surface(surface)
    if not (surface and surface.valid and type(surface.name) == "string") then return false end
    return surface.name == "nauvis"
        or cave_worlds.is_copy(surface)
end

local function disable_engine_entity_autoplace(surface)
    if not (surface and surface.valid) then return end
    local map_gen = surface.map_gen_settings
    map_gen.autoplace_settings = map_gen.autoplace_settings or {}
    map_gen.autoplace_settings.entity = {
        settings = {},
        treat_missing_as_default = false,
    }
    if advancing_zones.is_active() and advancing_zones.is_main_surface(surface) then
        map_gen.width = advancing_zones.ZONE_WIDTH
        map_gen.height = 0
    end
    surface.map_gen_settings = map_gen
end

local function clear_raw_chunk_resources(surface, area)
    -- Called only while converting a newly generated, not-yet-built cave chunk.
    -- No legitimate scripted ore has been placed at this point, so removing all
    -- engine-generated resources is both safer and more future-proof than a
    -- hard-coded resource-name list.
    for _, entity in pairs(surface.find_entities_filtered {
        area = area,
        type = "resource",
    }) do
        if entity.valid then entity.destroy() end
    end
end

local function cleanup_legacy_central_planetary_resources(surface)
    if not is_main_nauvis_cave_surface(surface) then return 0 end

    local names = {}
    for _, name in ipairs(TC_SCRIPTED_PLANETARY_RESOURCES) do
        if prototypes and prototypes.entity and prototypes.entity[name] then
            names[#names + 1] = name
        end
    end
    if #names == 0 then return 0 end

    local removed = 0
    -- Query a square, then use the same region classifier as live generation so
    -- legitimate resources at and beyond the 1000-tile planetary boundary are
    -- never touched.
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { -1001, -1001 }, { 1001, 1001 } },
        type = "resource",
        name = names,
    }) do
        if entity.valid and tc_planet_region(entity.position.x, entity.position.y) == "nauvis" then
            entity.destroy()
            removed = removed + 1
        end
    end
    return removed
end

local TC_REGION_TILES = {
    gleba = {
        "natural-yumako-soil", "natural-jellynut-soil", "wetland-yumako", "wetland-jellynut",
        "lowland-red-infection", "lowland-red-vein", "lowland-red-vein-2",
        "lowland-olive-blubber", "lowland-brown-blubber", "lowland-cream-red"
    },
    vulcanus = {
        "volcanic-soil-dark", "volcanic-soil-light", "volcanic-ash-dark", "volcanic-ash-light",
        "volcanic-cracks", "volcanic-folds", "volcanic-pumice-stones", "volcanic-smooth-stone"
    },
    fulgora = {
        "fulgoran-dunes", "fulgoran-dust", "fulgoran-rock", "fulgoran-sand",
        "fulgoran-machinery", "fulgoran-paving"
    },
    aquilo = {
        "snow-flat", "snow-crests", "snow-lumpy", "snow-patchy",
        "ice-rough", "ice-smooth", "brash-ice"
    }
}

local TC_ADVANCING_NAUVIS_TILES = {
    dirt = { "dirt-2", "dirt-3", "dirt-4", "dirt-5", "dirt-6" },
    ["dirt-dark"] = { "dirt-5", "dirt-6", "dirt-7" },
    grass = { "grass-1", "grass-2", "grass-3", "grass-4" },
    forest = { "grass-1", "grass-2", "grass-3", "dirt-3" },
    ["forest-dark"] = { "grass-3", "grass-4", "dirt-4", "dirt-5" },
    ["red-desert"] = { "red-desert-0", "red-desert-1", "red-desert-2" },
    ["red-desert-dark"] = { "red-desert-2", "red-desert-3", "dirt-6" },
    sand = { "sand-1", "sand-2", "sand-3" },
    dry = { "dry-dirt", "dirt-7", "sand-2" },
    garden = { "grass-1", "grass-2", "grass-4" },
    stone = { "stone-path", "dirt-4", "dirt-5" },
    mixed = { "grass-3", "dirt-3", "red-desert-1", "sand-2" },
    scrap = { "stone-path", "concrete", "dirt-6" },
    ["scrap-dark"] = { "hazard-concrete-left", "stone-path", "dirt-7" },
}

-- Alien Biomes normally owns Nauvis' engine tile autoplace. The Cave replaces
-- every generated chunk with void and reveals floor by script, so normal
-- Alien Biomes autoplace never survives. Build a runtime-safe palette from the
-- tile prototypes that actually exist after the player's Alien Biomes startup
-- choices, then use the same deterministic cave seed for organic regions.
--
-- This deliberately affects only natural Nauvis-like cave floors. Space Age
-- regions retain their progression-critical planetary terrain, Uranium Caves
-- retain their dedicated visual identity, and existing/player-built tiles are
-- never migrated.
local TC_ALIEN_BIOMES_SETTING = "the-cave-alien-biomes-support"
local TC_ALIEN_FAMILY_ORDER = { "mineral", "vegetation", "volcanic", "frozen" }
local TC_ALIEN_MINERAL_AXES = {
    "aubergine", "beige", "black", "brown", "cream", "dustyrose",
    "grey", "purple", "red", "tan", "violet", "white",
}
local TC_ALIEN_VEGETATION_AXES = {
    "blue", "green", "mauve", "olive", "orange",
    "purple", "red", "turquoise", "violet", "yellow",
}
local TC_ALIEN_VOLCANIC_AXES = { "blue", "green", "orange", "purple" }
local TC_ALIEN_MINERAL_VARIANTS = {
    "dirt-1", "dirt-2", "dirt-3", "dirt-4", "dirt-5", "dirt-6",
    "sand-1", "sand-2", "sand-3",
}
local TC_ALIEN_VOLCANIC_VARIANTS = { "heat-1", "heat-2", "heat-3", "heat-4" }
local TC_ALIEN_FROZEN_VARIANTS = {
    "snow-0", "snow-1", "snow-2", "snow-3", "snow-4",
    "snow-5", "snow-6", "snow-7", "snow-8", "snow-9",
}
local TC_ALIEN_NOISE = {
    temperature = 17101,
    moisture = 17102,
    colour = 17103,
    variant = 17104,
}

local function tc_existing_alien_tiles(prefix, axis, variants)
    local result = {}
    for _, variant in ipairs(variants) do
        local name = prefix .. (axis and ("-" .. axis) or "") .. "-" .. variant
        if prototypes and prototypes.tile and prototypes.tile[name] then
            result[#result + 1] = name
        end
    end
    return result
end

local function tc_alien_axis_palettes(prefix, axes, variants_for_axis)
    local palettes = {}
    for _, axis in ipairs(axes) do
        local variants = variants_for_axis(axis)
        local tiles = tc_existing_alien_tiles(prefix, axis, variants)
        if #tiles > 0 then
            palettes[#palettes + 1] = tiles
        end
    end
    return palettes
end

local TC_ALIEN_BIOME_PALETTES = {
    mineral = tc_alien_axis_palettes("mineral", TC_ALIEN_MINERAL_AXES, function()
        return TC_ALIEN_MINERAL_VARIANTS
    end),
    vegetation = tc_alien_axis_palettes("vegetation", TC_ALIEN_VEGETATION_AXES, function(axis)
        -- Alien Biomes defines grass-3/4 only for the green axis.
        if axis == "green" then
            return { "grass-1", "grass-2", "grass-3", "grass-4" }
        end
        return { "grass-1", "grass-2" }
    end),
    volcanic = tc_alien_axis_palettes("volcanic", TC_ALIEN_VOLCANIC_AXES, function()
        return TC_ALIEN_VOLCANIC_VARIANTS
    end),
    frozen = {
        tc_existing_alien_tiles("frozen", nil, TC_ALIEN_FROZEN_VARIANTS),
    },
}
if #TC_ALIEN_BIOME_PALETTES.frozen[1] == 0 then
    TC_ALIEN_BIOME_PALETTES.frozen = {}
end

local function tc_alien_biomes_enabled()
    local cave_setting = settings.startup[TC_ALIEN_BIOMES_SETTING]
    if cave_setting and cave_setting.value ~= "enabled" then return false end
    return script and script.active_mods and script.active_mods["alien-biomes"] ~= nil
end

local function tc_alien_biomes_supported_surface(surface)
    return cave_worlds.is_cave_world(surface)
end

local function tc_noise_index(value, count)
    if count <= 1 then return 1 end
    local normalized = math.max(0, math.min(0.999999, (value + 1) * 0.5))
    return 1 + math.floor(normalized * count)
end

local function tc_preferred_alien_family(seed, x, y)
    local temperature = Simplex.d2(x / 72, y / 72, seed + TC_ALIEN_NOISE.temperature)
    local moisture = Simplex.d2(x / 64, y / 64, seed + TC_ALIEN_NOISE.moisture)
    if temperature < -0.42 then return "frozen" end
    if temperature > 0.48 then return "volcanic" end
    if moisture > -0.08 then return "vegetation" end
    return "mineral"
end

local function tc_available_alien_family(preferred)
    local disable_vegetation = settings.startup["alien-biomes-disable-vegetation"]
    local vegetation_allowed = not disable_vegetation or disable_vegetation.value ~= "Enabled"
    local start = 1
    for i, name in ipairs(TC_ALIEN_FAMILY_ORDER) do
        if name == preferred then
            start = i
            break
        end
    end
    for offset = 0, #TC_ALIEN_FAMILY_ORDER - 1 do
        local name = TC_ALIEN_FAMILY_ORDER[((start + offset - 1) % #TC_ALIEN_FAMILY_ORDER) + 1]
        if name ~= "vegetation" or vegetation_allowed then
            local palettes = TC_ALIEN_BIOME_PALETTES[name]
            if palettes and #palettes > 0 then return palettes end
        end
    end
    return nil
end

local function tc_alien_biomes_floor(surface, seed, x, y)
    if not tc_alien_biomes_enabled() or not tc_alien_biomes_supported_surface(surface) then
        return nil
    end
    local palettes = tc_available_alien_family(tc_preferred_alien_family(seed, x, y))
    if not palettes then return nil end

    -- Slow colour noise creates broad coherent biomes; faster variant noise
    -- prevents large areas from becoming one repeated texture. Both are pure
    -- coordinate functions, so multiplayer peers and cave copies agree exactly.
    local colour_noise = Simplex.d2(x / 88, y / 88, seed + TC_ALIEN_NOISE.colour)
    local palette = palettes[tc_noise_index(colour_noise, #palettes)]
    if not palette or #palette == 0 then return nil end
    local variant_noise = Simplex.d2(x / 14, y / 14, seed + TC_ALIEN_NOISE.variant)
    return palette[tc_noise_index(variant_noise, #palette)]
end

local function tc_region_floor(surface, seed, x, y, original_floor)
    local region = tc_planet_region(x, y)
    if region == "nauvis" then
        local alien_floor = tc_alien_biomes_floor(surface, seed, x, y)
        if alien_floor then return alien_floor end
    end
    local tiles = TC_REGION_TILES[region]
    if region == "nauvis" and advancing_zones.is_active() then
        local zone = advancing_zones.zone_at(x, y)
        tiles = zone and TC_ADVANCING_NAUVIS_TILES[zone.palette] or nil
    end
    if not tiles then return original_floor end
    local bx, by = math.floor(x / 17), math.floor(y / 17)
    local start = math.abs((bx * 19349663 + by * 83492791 + seed * 31) % #tiles)
    for i = 1, #tiles do
        local name = tiles[((start + i - 1) % #tiles) + 1]
        if prototypes and prototypes.tile and prototypes.tile[name] then return name end
    end
    return original_floor
end

local function tc_remove_nauvis_resources_outside_center(surface, x, y)
    if tc_planet_region(x, y) == "nauvis" then return end
    local resources = surface.find_entities_filtered{
        area = {{x - 1, y - 1}, {x + 2, y + 2}},
        type = "resource"
    }
    for _, e in pairs(resources) do
        if e.valid and (
            e.name == "iron-ore" or e.name == "copper-ore" or e.name == "coal" or
            e.name == "stone" or e.name == "uranium-ore"
        ) then
            e.destroy()
        end
    end
end


local function floor_tile(surface, seed, x, y)
    local original = "dirt-" .. hash.range(seed, x, y, S_FLOOR, 1, 7)
    return tc_region_floor(surface, seed, x, y, original)
end

local function is_water_spot(seed, x, y)
    return Simplex.d2(x * WATER.scale, y * WATER.scale, seed + WATER.seed) > WATER.threshold
end

local function is_void(surface, x, y)
    local tile = surface.get_tile(x, y)
    return tile.valid and tile.name == "out-of-map"
end

local function is_playable_position(surface, x, y)
    return advancing_zones.is_playable(surface, x, y)
end

-- Forward declarations: ensure_chunk repairs unbuilt chunks via build_chunk.
local build_chunk, chunk_key

local function ensure_built_chunks()
    storage.built_chunks = storage.built_chunks or {}
    return storage.built_chunks
end

-- Surface indices can be reused by Factorio after a temporary extraction
-- surface is deleted.  The conversion registry is keyed by surface index, so
-- retaining the old keys makes a later cave with the same index look already
-- converted and leaves its raw green map-generator terrain untouched.
function world.forget_surface_chunks(surface_or_index)
    local surface_index = type(surface_or_index) == "table"
        and surface_or_index.index or tonumber(surface_or_index)
    if not surface_index then return 0 end
    local prefix = tostring(surface_index) .. ":"
    local removed = 0
    for key in pairs(ensure_built_chunks()) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix then
            storage.built_chunks[key] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Call immediately after creating an Uranium/Mineral child surface, before
-- requesting its first chunks.  This closes the surface-index reuse race even
-- if the deletion event for the former owner has not yet been dispatched.
function world.prepare_extraction_surface(surface)
    if not (surface and surface.valid
        and (is_uranium_cave_surface(surface) or is_mineral_cave_surface(surface))) then
        return false
    end
    world.forget_surface_chunks(surface.index)
    mirror.drop_surface(surface.index)
    return true
end

-- Repair saves that already received a raw child surface from the stale-index
-- bug.  A healthy extraction cave always has a diggy-rock frontier.  The extra
-- dense-chunk test prevents a fully mined but otherwise legitimate cave from
-- being reset: raw generator chunks have virtually all 1024 tiles exposed.
-- Only tiles are resealed; fixed portals, transfer hardware and player-built
-- entities are preserved, then the owning cave module recarves its start room.
function world.repair_raw_extraction_surface(surface)
    if not (surface and surface.valid
        and (is_uranium_cave_surface(surface) or is_mineral_cave_surface(surface))) then
        return false
    end
    if #surface.find_entities_filtered { name = "diggy-rock", limit = 1 } > 0 then return false end

    local generated = {}
    local raw_chunk_found = false
    for chunk in surface.get_chunks() do
        generated[#generated + 1] = { x = chunk.x, y = chunk.y, area = chunk.area }
        local exposed = 0
        for x = chunk.area.left_top.x, chunk.area.right_bottom.x - 1 do
            for y = chunk.area.left_top.y, chunk.area.right_bottom.y - 1 do
                local tile = surface.get_tile(x, y)
                if tile and tile.valid and tile.name ~= "out-of-map" then
                    exposed = exposed + 1
                    if exposed > 900 then
                        raw_chunk_found = true
                        break
                    end
                end
            end
            if raw_chunk_found then break end
        end
        if raw_chunk_found then break end
    end
    if not raw_chunk_found then return false end

    -- Re-enumerate because the detection loop intentionally stopped early.
    generated = {}
    world.forget_surface_chunks(surface.index)
    for chunk in surface.get_chunks() do
        generated[#generated + 1] = { x = chunk.x, y = chunk.y, area = chunk.area }
    end
    local built_chunks = ensure_built_chunks()
    for _, chunk in ipairs(generated) do
        clear_raw_chunk_resources(surface, chunk.area)
        local tiles = {}
        for x = chunk.area.left_top.x, chunk.area.right_bottom.x - 1 do
            for y = chunk.area.left_top.y, chunk.area.right_bottom.y - 1 do
                tiles[#tiles + 1] = { name = "out-of-map", position = { x, y } }
            end
        end
        surface.set_tiles(tiles, false, false, true, false)
        mirror.drop_chunk_at(surface, chunk.area.left_top.x, chunk.area.left_top.y)
        built_chunks[chunk_key(surface, chunk.x, chunk.y)] = true
    end
    return true
end

-- Convert every generated extraction-surface chunk that escaped the normal
-- generation event. Factorio may generate a threaded halo around an explicit
-- request without raising on_chunk_generated for each halo chunk; those raw
-- chunks otherwise appear as distant green terrain in map view.
--
-- This sweep is used immediately after new chunk requests, before any caller
-- carves into the newly generated area. Previously converted chunks are skipped
-- through the shared registry, so repeated frontier requests remain cheap.
function world.seal_unbuilt_extraction_chunks(surface)
    if not (surface and surface.valid
        and (is_uranium_cave_surface(surface) or is_mineral_cave_surface(surface))) then
        return 0
    end

    local chunks = {}
    for chunk in surface.get_chunks() do
        chunks[#chunks + 1] = { x = chunk.x, y = chunk.y, area = chunk.area }
    end

    local built_chunks = ensure_built_chunks()
    local sealed = 0
    for _, chunk in ipairs(chunks) do
        local key = chunk_key(surface, chunk.x, chunk.y)
        if not built_chunks[key] then
            built_chunks[key] = true
            build_chunk(surface, chunk.area)
            sealed = sealed + 1
        end
    end
    return sealed
end

local function raw_extraction_tile(name)
    if type(name) ~= "string" then return false end
    return name:find("^grass%-") ~= nil
        or name:find("^sand%-") ~= nil
        or name:find("^red%-desert%-") ~= nil
        or name:find("water", 1, true) ~= nil
end

-- Save-safe repair for already-open caves that contain only a few raw MapGen
-- halo chunks around an otherwise healthy carved cave. Never reset a normal
-- dirt cavern: a candidate must contain no out-of-map frontier at all and a
-- substantial number of unmistakable vanilla surface tiles (grass, sand,
-- red-desert or water). Player-carved extraction floors use deterministic dirt
-- tiles, so fully mined legitimate chunks are deliberately left untouched.
function world.repair_extraction_void_halo(surface)
    if not (surface and surface.valid
        and (is_uranium_cave_surface(surface) or is_mineral_cave_surface(surface))) then
        return 0
    end

    local candidates = {}
    for chunk in surface.get_chunks() do
        local raw_count = 0
        local has_void = false
        for x = chunk.area.left_top.x, chunk.area.right_bottom.x - 1 do
            for y = chunk.area.left_top.y, chunk.area.right_bottom.y - 1 do
                local tile = surface.get_tile(x, y)
                local name = tile and tile.valid and tile.name or nil
                if name == "out-of-map" then
                    has_void = true
                    break
                elseif raw_extraction_tile(name) then
                    raw_count = raw_count + 1
                end
            end
            if has_void then break end
        end
        if not has_void and raw_count >= 64 then
            candidates[#candidates + 1] = { x = chunk.x, y = chunk.y, area = chunk.area }
        end
    end

    local built_chunks = ensure_built_chunks()
    for _, chunk in ipairs(candidates) do
        clear_raw_chunk_resources(surface, chunk.area)
        local tiles = {}
        for x = chunk.area.left_top.x, chunk.area.right_bottom.x - 1 do
            for y = chunk.area.left_top.y, chunk.area.right_bottom.y - 1 do
                tiles[#tiles + 1] = { name = "out-of-map", position = { x, y } }
            end
        end
        surface.set_tiles(tiles, false, false, true, false)
        mirror.drop_chunk_at(surface, chunk.area.left_top.x, chunk.area.left_top.y)
        built_chunks[chunk_key(surface, chunk.x, chunk.y)] = true
    end
    return #candidates
end

local function ensure_chunk(surface, x, y)
    local cx, cy = math.floor(x / 32), math.floor(y / 32)
    if not surface.is_chunk_generated({ cx, cy }) then
        surface.request_to_generate_chunks({ x, y }, 0)
        surface.force_generate_chunk_requests()
    end
    -- The threaded generator produces "halo" chunks around requested ones
    -- WITHOUT firing on_chunk_generated — they'd stay as raw engine terrain.
    -- The registry makes conversion event-independent: build anything unbuilt.
    local built_chunks = ensure_built_chunks()
    local key = chunk_key(surface, cx, cy)
    if not built_chunks[key] and surface.is_chunk_generated({ cx, cy }) then
        built_chunks[key] = true
        build_chunk(surface, {
            left_top = { x = cx * 32, y = cy * 32 },
            right_bottom = { x = cx * 32 + 32, y = cy * 32 + 32 },
        })
    end
end

-- Generate and Cave-convert every chunk touched by a small scripted area
-- before callers inspect entities, collisions or spawn positions there.
-- The tunnel controller passes only its current six-tile slice, so this never
-- expands generation beyond the chunks the corridor actually enters.
function world.ensure_generated_area(surface, cells)
    if not (surface and surface.valid and type(cells) == "table" and #cells > 0) then
        return false
    end

    local chunks = {}
    local requested = false
    for _, cell in ipairs(cells) do
        local x = math.floor(tonumber(cell.x or cell[1]) or 0)
        local y = math.floor(tonumber(cell.y or cell[2]) or 0)
        local cx, cy = math.floor(x / 32), math.floor(y / 32)
        local key = tostring(cx) .. ":" .. tostring(cy)
        if not chunks[key] then
            chunks[key] = { x = cx, y = cy }
            if not surface.is_chunk_generated({ cx, cy }) then
                surface.request_to_generate_chunks({ x = cx * 32 + 16, y = cy * 32 + 16 }, 0)
                requested = true
            end
        end
    end
    if requested then
        surface.force_generate_chunk_requests()
        -- Seal the complete generated halo, not only the exact chunks touched
        -- by the six-tile tunnel slice below.
        world.seal_unbuilt_extraction_chunks(surface)
    end

    for _, chunk in pairs(chunks) do
        ensure_chunk(surface, chunk.x * 32 + 16, chunk.y * 32 + 16)
        if not surface.is_chunk_generated({ chunk.x, chunk.y }) then return false end
    end
    return true
end

-- Keep a square of Cave terrain centred on the Main Locomotive generated even
-- when no player, radar or editor camera is nearby. Radius is expressed in
-- chunks: 22 means 22 chunks above, below, left and right (45 x 45 total).
-- Copied cave worlds normally receive cloned original chunks; chunks requested
-- directly by Train Wave Defense can bypass that clone path, so brand-new team
-- chunks are sealed here before any spawn or tunnel collision check can use
-- raw map-generator terrain.
function world.ensure_generated_radius(surface, position, radius)
    if not (surface and surface.valid and position) then return false end
    radius = math.max(0, math.floor(tonumber(radius) or 0))
    local center_x = math.floor((tonumber(position.x or position[1]) or 0) / 32)
    local center_y = math.floor((tonumber(position.y or position[2]) or 0) / 32)
    local team_surface = cave_worlds.is_copy(surface)
    local team_pending = nil
    local all_generated = true
    local verification_waiting = false
    if team_surface then
        storage.train_wave_team_chunk_verification = storage.train_wave_team_chunk_verification or {}
        storage.train_wave_team_chunk_verification[surface.index] =
            storage.train_wave_team_chunk_verification[surface.index] or {}
        team_pending = storage.train_wave_team_chunk_verification[surface.index]
    end

    for cx = center_x - radius, center_x + radius do
        for cy = center_y - radius, center_y + radius do
            if not surface.is_chunk_generated({ cx, cy }) then
                all_generated = false
                if team_surface then
                    local key = tostring(cx) .. ":" .. tostring(cy)
                    if type(team_pending[key]) ~= "table" then
                        team_pending[key] = { stage = "requested", tick = game and game.tick or 0 }
                    end
                end
            end
        end
    end

    surface.request_to_generate_chunks({
        x = center_x * 32 + 16,
        y = center_y * 32 + 16,
    }, radius)

    local built_chunks = ensure_built_chunks()
    for cx = center_x - radius, center_x + radius do
        for cy = center_y - radius, center_y + radius do
            local generated = surface.is_chunk_generated({ cx, cy })
            local requested_key = tostring(cx) .. ":" .. tostring(cy)
            local pending = team_surface and team_pending[requested_key] or nil
            if generated and team_surface and type(pending) == "table" then
                local area = {
                    left_top = { x = cx * 32, y = cy * 32 },
                    right_bottom = { x = cx * 32 + 32, y = cy * 32 + 32 },
                }
                local tiles = {}
                for x = area.left_top.x, area.right_bottom.x - 1 do
                    for y = area.left_top.y, area.right_bottom.y - 1 do
                        tiles[#tiles + 1] = { name = "out-of-map", position = { x, y } }
                    end
                end
                surface.set_tiles(tiles, true, true, true, false)
                mirror.drop_chunk_at(surface, area.left_top.x, area.left_top.y)
                built_chunks[chunk_key(surface, cx, cy)] = true
                if pending.stage ~= "verify" then
                    pending.stage = "verify"
                    pending.tick = game and game.tick or 0
                    verification_waiting = true
                elseif not game or game.tick > (tonumber(pending.tick) or 0) then
                    team_pending[requested_key] = nil
                else
                    verification_waiting = true
                end
            elseif generated then
                ensure_chunk(surface, cx * 32 + 16, cy * 32 + 16)
            end
        end
    end
    -- A copier may finish its clone callback after the generation event.
    -- Hold Wave processing until a later controller pass has sealed and
    -- verified every brand-new team chunk a second time.
    if team_surface and verification_waiting then return false end
    return all_generated
end

-- Reveal the contiguous water blob touching (x, y), bounded for safety.
-- Only VOID tiles flood (revealed floor and anything built on it is safe),
-- entities are never destroyed by the tile swap, and any character clipped
-- by the new shoreline is lifted to dry land — digging into a lake must
-- never drown the digger.
local function flood_water(surface, seed, x, y)
    local tiles, seen, queue = {}, {}, { { x, y } }
    local first = true
    local min_x, min_y, max_x, max_y = x, y, x, y
    while #queue > 0 and #tiles < WATER.flood_cap do
        local t = table.remove(queue)
        local key = t[1] .. "," .. t[2]
        if not seen[key] then
            seen[key] = true
            if is_water_spot(seed, t[1], t[2]) and (first or is_void(surface, t[1], t[2])) then
                first = false
                local tile_name = "water"
                local region = tc_planet_region(t[1], t[2])

                -- Vulcanus should not generate normal water pools.
                -- Natural cave water pockets become lava instead.
                if region == "vulcanus" and prototypes.tile["lava"] then
                    tile_name = "lava"
                    if prototypes.tile["lava-hot"] and hash.roll(seed, t[1], t[2], S_FISH + 91) < 0.25 then
                        tile_name = "lava-hot"
                    end
                -- Fulgora should not generate normal water pools either.
                -- Natural cave water pockets become oil ocean for offshore-pump heavy oil.
                elseif region == "fulgora" and prototypes.tile["oil-ocean-shallow"] then
                    tile_name = "oil-ocean-shallow"
                -- Aquilo liquid terrain is ammoniacal ocean, not normal water.
                elseif region == "aquilo" and prototypes.tile["ammoniacal-ocean"] then
                    tile_name = "ammoniacal-ocean"
                    if prototypes.tile["ammoniacal-ocean-2"] and hash.roll(seed, t[1], t[2], S_FISH + 92) < 0.25 then
                        tile_name = "ammoniacal-ocean-2"
                    end
                end

                tiles[#tiles + 1] = { name = tile_name, position = { t[1], t[2] } }
                min_x, min_y = math.min(min_x, t[1]), math.min(min_y, t[2])
                max_x, max_y = math.max(max_x, t[1]), math.max(max_y, t[2])
                for _, d in pairs(DIRS4) do
                    ensure_chunk(surface, t[1] + d[1], t[2] + d[2])
                    queue[#queue + 1] = { t[1] + d[1], t[2] + d[2] }
                end
            end
        end
    end
    surface.set_tiles(tiles, true, false)
    mirror.set_tiles(surface, tiles)
    -- Rescue anyone the new shoreline clipped.
    for _, character in pairs(surface.find_entities_filtered {
        type = "character",
        area = { { min_x - 1, min_y - 1 }, { max_x + 2, max_y + 2 } },
    }) do
        local dry = surface.find_non_colliding_position("character", character.position, 16, 0.5)
        if dry then character.teleport(dry) end
    end
    -- Lakes hold fish: roughly one per seven water tiles, seed-keyed.
    -- Vulcanus water spots become lava, so do not place fish there.
    for _, t in pairs(tiles) do
        local tx, ty = t.position[1], t.position[2]
        if t.name == "water" and hash.roll(seed, tx, ty, S_FISH) < 0.15 then
            surface.create_entity { name = "fish", position = { tx + 0.5, ty + 0.5 } }
        end
    end
end

-- Turn a void tile into frontier wall: floor underneath, cover entity on top.
-- Water spots become (part of) a pool instead — water itself is the barrier.
local function make_wall(surface, seed, x, y)
    if not is_playable_position(surface, x, y) then return end
    local timed_cave = is_uranium_cave_surface(surface) or is_mineral_cave_surface(surface)
    if not timed_cave and is_water_spot(seed, x, y) then
        flood_water(surface, seed, x, y)
        return
    end
    local floor = floor_tile(surface, seed, x, y)
    surface.set_tiles({ { name = floor, position = { x, y } } })
    -- Trees are ordinary harvestable scenery, never frontier cover. Only a
    -- diggy-rock can advance the cave when mined.
    local rock = surface.create_entity { name = "diggy-rock", position = { x + 0.5, y + 0.5 }, force = "neutral" }
    mirror.set_floor(surface, x, y, floor)
    mirror.set_rock(surface, { x = x, y = y }, true)
end

-- Carve a tile fully open (cavern carving): removes any wall entity, opens
-- void as floor with its vein. skip_vein for tiles about to be re-tiled
-- (sanctuaries), where ore would end up under water or grass.
-- Returns true only when the tile transitioned void -> floor (the caller
-- charges ceiling debt per OPENED tile exactly once; already-open overlap
-- tiles paid their +1 when they were first dug or carved).
function world.carve_tile(surface, x, y, force, skip_vein, skip_region_features)
    if not is_playable_position(surface, x, y) then return false end
    local uranium_cave = is_uranium_cave_surface(surface)
    local mineral_cave = is_mineral_cave_surface(surface)
    local uranium_module = uranium_cave and uranium_caves_module() or nil
    local mineral_module = mineral_cave and mineral_caves_module() or nil
    ensure_chunk(surface, x, y)
    for _, entity in pairs(surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-tree" },
        area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
    }) do
        entity.destroy() -- no event fires for destroy(): tell the mirror
        mirror.set_rock(surface, { x = x, y = y }, false)
    end
    if not is_void(surface, x, y) then return false end

    local seed = surface.map_gen_settings.seed
    if not uranium_cave and not mineral_cave and is_water_spot(seed, x, y) then
        flood_water(surface, seed, x, y)
        return false
    end
    local floor = floor_tile(surface, seed, x, y)
    surface.set_tiles({ { name = floor, position = { x, y } } })
    mirror.set_floor(surface, x, y, floor)
    if uranium_cave then
        if uranium_module then uranium_module.materialize_uranium(surface, x, y, force) end
    elseif mineral_cave then
        if mineral_module then mineral_module.materialize_mineral(surface, x, y, force) end
    else
        if not skip_region_features then
            region_features.on_open_tile(surface, x, y, force)
        end
        if not skip_vein then
            ore_veins.materialize(surface, x, y, force)
            mobile_factory_resources.on_open_tile(surface, x, y, force)
            bob_ores_resources.on_open_tile(surface, x, y, force)
        end
    end
    return true
end

-- Resource-only clearing for the Advancing Collapse staging area. Each caller
-- owns a monotonic row cursor, so already-mined floor is never repopulated.
-- Existing resources, player buildings, rails, trains, portals and enemies are
-- preserved. No mined/died events or discovery/room/enemy hooks are dispatched.
function world.carve_resource_strip(surface, min_x, max_x, y, force)
    local halo_min_x, halo_max_x=min_x-2,max_x+1
    if advancing_zones.is_active() and advancing_zones.is_main_surface(surface) then
        -- A full-width clearing reaches the finite map edge. Factorio ignores
        -- requests outside it, so an unclipped halo could never become ready.
        halo_min_x=math.max(halo_min_x,-advancing_zones.ZONE_WIDTH/2)
        halo_max_x=math.min(halo_max_x,advancing_zones.ZONE_WIDTH/2-1)
    end
    if cave_worlds.is_copy(surface) then
        -- A direct request can bypass the ordinary original-clone path. Reuse
        -- the existing two-pass sealing guard for only the touched chunks,
        -- and wait for it before opening a row or allowing assault spawns.
        local ready = true
        for cx = math.floor(halo_min_x / 32), math.floor(halo_max_x / 32) do
            for cy = math.floor((y - 2) / 32), math.floor(y / 32) do
                if not world.ensure_generated_radius(surface, { x = cx * 32 + 16, y = cy * 32 + 16 }, 0) then
                    ready = false
                end
            end
        end
        if not ready then return false end
    end
    local cells = {}
    for x = halo_min_x, halo_max_x do
        cells[#cells + 1] = { x, y - 2 }
        cells[#cells + 1] = { x, y }
    end
    if not world.ensure_generated_area(surface, cells) then return false end

    local seed = surface.map_gen_settings.seed
    local reveal, tiles = {}, {}
    for x = min_x, max_x - 1 do
        if is_playable_position(surface, x, y) then
            local tile = surface.get_tile(x, y)
            local name = tile.name or ""
            local opened = name == "out-of-map"
                or name:find("water", 1, true) or name:find("ocean", 1, true)
                or name:find("lava", 1, true)
            if opened then
                tiles[#tiles + 1] = { name = floor_tile(surface, seed, x, y), position = { x, y } }
            end
            for _, entity in pairs(surface.find_entities_filtered {
                area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
            }) do
                if entity.valid and (entity.name == "diggy-rock" or entity.name == "diggy-rubble"
                    or entity.name == "diggy-tree"
                    or (entity.type == "tree" and entity.force.name == "neutral")) then
                    if entity.name == "diggy-rock" or entity.name == "diggy-rubble" then opened = true end
                    local position = { x = entity.position.x, y = entity.position.y }
                    entity.destroy()
                    mirror.set_rock(surface, position, false)
                end
            end
            if opened then reveal[#reveal + 1] = { x, y } end
        end
    end
    if #tiles > 0 then
        surface.set_tiles(tiles, true, false, false, false)
        mirror.set_tiles(surface, tiles)
    end
    for _, cell in ipairs(reveal) do
        local x = cell[1]
        if #surface.find_entities_filtered {
            area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
            type = "resource", limit = 1,
        } == 0 then
            ore_veins.materialize(surface, x, y, force, nil, true)
            region_features.on_resource_only_tile(surface, x, y)
            mobile_factory_resources.on_open_tile(surface, x, y)
            bob_ores_resources.on_open_tile(surface, x, y, force)
        end
    end

    -- Keep the ordinary two-wall-thick mineable frontier, but never invoke
    -- flood_water here: opening this strip cannot generate a lake or fish.
    local frontier = {}
    for ny = y - 2, y do
        for x = halo_min_x, halo_max_x do
            if (ny < y or x < min_x or x >= max_x)
                and is_playable_position(surface, x, ny) and is_void(surface, x, ny) then
                frontier[#frontier + 1] = {
                    name = floor_tile(surface, seed, x, ny), position = { x, ny },
                }
            end
        end
    end
    if #frontier > 0 then
        surface.set_tiles(frontier, true, false, false, false)
        mirror.set_tiles(surface, frontier)
        for _, tile in ipairs(frontier) do
            local x, ny = tile.position[1], tile.position[2]
            local rock = surface.create_entity {
                name = "diggy-rock", position = { x + 0.5, ny + 0.5 }, force = "neutral",
            }
            if rock and rock.valid then mirror.set_rock(surface, rock.position, true) end
        end
    end
    return true
end

-- Open one guaranteed-safe floor tile without water, ore veins, enemies, or
-- regional features. Uranium Cave arrival rooms use this so the portal can never be
-- created inside water or a hostile/resource entity.
function world.carve_safe_tile(surface, x, y)
    if not is_playable_position(surface, x, y) then return false end
    ensure_chunk(surface, x, y)
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
    }) do
        if entity.valid and (entity.name == "diggy-rock" or entity.name == "diggy-rubble"
            or entity.name == "diggy-tree" or entity.type == "resource"
            or (entity.force and entity.force.name == "enemy")) then
            if entity.name == "diggy-rock" or entity.name == "diggy-rubble" or entity.name == "diggy-tree" then
                mirror.set_rock(surface, { x = x, y = y }, false)
            end
            entity.destroy()
        end
    end

    local seed = surface.map_gen_settings.seed
    local floor = floor_tile(surface, seed, x, y)
    surface.set_tiles({ { name = floor, position = { x, y } } }, true, false)
    mirror.set_floor(surface, x, y, floor)
    return true
end

-- Advance the frontier around freshly opened tiles: void within TWO steps of
-- open floor becomes wall, keeping the boundary two layers deep so a single
-- dig never punches straight through to the void.
function world.advance_frontier(surface, tiles)
    local seed = surface.map_gen_settings.seed
    for _, t in pairs(tiles) do
        for _, d in pairs(DIRS4) do
            local n1x, n1y = t[1] + d[1], t[2] + d[2]
            if is_playable_position(surface, n1x, n1y) then
                ensure_chunk(surface, n1x, n1y)
                if is_void(surface, n1x, n1y) then
                    make_wall(surface, seed, n1x, n1y)
                end
            end
            for _, d2 in pairs(DIRS4) do
                local n2x, n2y = n1x + d2[1], n1y + d2[2]
                if is_playable_position(surface, n2x, n2y) then
                    ensure_chunk(surface, n2x, n2y)
                    if is_void(surface, n2x, n2y) then
                        make_wall(surface, seed, n2x, n2y)
                    end
                end
            end
        end
    end
end

-- Segmented units lose their individual entity representations when part of
-- the body reaches out-of-map terrain.  The ordinary cave frontier is only two
-- tiles deep, so a long Demolisher can cross it before the head has opened the
-- next layer.  Repair only the local body envelope: the occupied footprint is
-- made into open cave floor, while a thicker outer ring becomes normal
-- diggy-rock frontier.  The engine can then recreate missing segments and the
-- Demolisher destroys the new cover through the ordinary on_entity_died path.
--
-- This function never moves, clones, damages or recreates the Demolisher and
-- never removes an entity.  It returns only the emergency-opened floor tiles;
-- control.lua feeds those through the existing Demolisher resource/extraction
-- preservation path because no cover-death event existed for these void tiles.
local DEMOLISHER_ENVELOPE_BUFFER = 6
local DEMOLISHER_DEFAULT_HALF_WIDTH = 3

local function demolisher_envelope_surface(surface)
    if not (surface and surface.valid and type(surface.name) == "string") then return false end
    return is_main_nauvis_cave_surface(surface)
        or surface.name:find("^the%-cave%-warp%-") ~= nil
end

local function append_demolisher_center(centers, seen, position)
    if not (position and tonumber(position.x) and tonumber(position.y)) then return end
    local x, y = math.floor(position.x), math.floor(position.y)
    local key = x .. "," .. y
    if seen[key] then return end
    seen[key] = true
    centers[#centers + 1] = { x = x, y = y }
end

local function demolisher_half_width(segmented_unit)
    local half_width = DEMOLISHER_DEFAULT_HALF_WIDTH
    pcall(function()
        local box = segmented_unit.prototype and segmented_unit.prototype.collision_box
        if box and box.left_top and box.right_bottom then
            half_width = math.max(
                half_width,
                math.abs(tonumber(box.left_top.x) or 0),
                math.abs(tonumber(box.left_top.y) or 0),
                math.abs(tonumber(box.right_bottom.x) or 0),
                math.abs(tonumber(box.right_bottom.y) or 0)
            )
        end
    end)
    return math.max(2, math.min(8, math.ceil(half_width + 1)))
end

local function demolisher_body_centers(segmented_unit)
    local centers, seen = {}, {}
    local missing_representation = false

    -- Body nodes are cheap and describe the complete head-to-tail path even
    -- while individual segment entities are temporarily absent.
    pcall(function()
        for _, position in pairs(segmented_unit.get_body_nodes() or {}) do
            append_demolisher_center(centers, seen, position)
        end
    end)

    -- LuaSegment.position remains available for a segment whose entity
    -- representation was removed on out-of-map.  Add those exact positions so
    -- the emergency footprint covers already-missing body pieces as well.
    pcall(function()
        for _, segment in pairs(segmented_unit.segments or {}) do
            local entity = segment.entity
            if entity and entity.valid then
                append_demolisher_center(centers, seen, entity.position)
            else
                -- Reading this calculated position is deliberately limited to
                -- missing representations; the API documents it as expensive.
                local position = segment.position
                if position then
                    missing_representation = true
                    append_demolisher_center(centers, seen, position)
                end
            end
        end
    end)
    return centers, missing_representation
end

local function demolisher_envelope_touches_void(surface, centers, inner_radius, outer_radius,
        missing_representation)
    if missing_representation then return true end

    -- Probe the centre, the occupied edge and the outer safety edge.  Sampling
    -- their perimeters is much cheaper than scanning every footprint tile on
    -- every 30-tick heartbeat; a full scan runs only after a probe finds void.
    local radii = { 0, inner_radius, outer_radius }
    for _, center in ipairs(centers) do
        for _, radius in ipairs(radii) do
            if radius == 0 then
                if is_void(surface, center.x, center.y) then return true end
            else
                local step = math.max(1, math.floor(radius / 3))
                for offset = -radius, radius, step do
                    if is_void(surface, center.x + offset, center.y - radius)
                        or is_void(surface, center.x + offset, center.y + radius)
                        or is_void(surface, center.x - radius, center.y + offset)
                        or is_void(surface, center.x + radius, center.y + offset) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function demolisher_travel_direction(centers)
    if #centers < 2 then return { 0, -1 } end
    local dx = centers[1].x - centers[2].x
    local dy = centers[1].y - centers[2].y
    if math.abs(dx) >= math.abs(dy) then
        return { dx >= 0 and 1 or -1, 0 }
    end
    return { 0, dy >= 0 and 1 or -1 }
end

function world.ensure_demolisher_envelope(surface, segmented_unit)
    if not (demolisher_envelope_surface(surface) and segmented_unit) then return nil end

    local prototype_name
    local valid_unit = false
    pcall(function()
        valid_unit = segmented_unit.valid == true
        prototype_name = segmented_unit.prototype and segmented_unit.prototype.name
    end)
    if not valid_unit or type(prototype_name) ~= "string"
        or not prototype_name:find("demolisher", 1, true) then
        return nil
    end

    local centers, missing_representation = demolisher_body_centers(segmented_unit)
    if #centers == 0 then return nil end
    local inner_radius = demolisher_half_width(segmented_unit)
    local outer_radius = inner_radius + DEMOLISHER_ENVELOPE_BUFFER
    if not demolisher_envelope_touches_void(
        surface, centers, inner_radius, outer_radius, missing_representation
    ) then
        return nil
    end

    -- Generate/build only chunks touched by this bounded repair.  Repeated
    -- calls are cheap because ensure_chunk is registry-backed.
    for _, center in ipairs(centers) do
        ensure_chunk(surface, center.x - outer_radius, center.y - outer_radius)
        ensure_chunk(surface, center.x + outer_radius, center.y - outer_radius)
        ensure_chunk(surface, center.x - outer_radius, center.y + outer_radius)
        ensure_chunk(surface, center.x + outer_radius, center.y + outer_radius)
    end

    local seed = surface.map_gen_settings.seed
    local inner_seen, opened, opened_lookup, opportunities = {}, {}, {}, {}
    local floor_tiles = {}

    for _, center in ipairs(centers) do
        local opportunity
        for dy = -inner_radius, inner_radius do
            for dx = -inner_radius, inner_radius do
                if dx * dx + dy * dy <= inner_radius * inner_radius then
                    local x, y = center.x + dx, center.y + dy
                    local key = x .. "," .. y
                    if not inner_seen[key] then
                        inner_seen[key] = true
                        if is_playable_position(surface, x, y) and is_void(surface, x, y) then
                            local floor = floor_tile(surface, seed, x, y)
                            floor_tiles[#floor_tiles + 1] = { name = floor, position = { x, y } }
                            opened[#opened + 1] = { x = x, y = y }
                            opened_lookup[key] = true
                            opportunity = opportunity or { x = x, y = y }
                        end
                    elseif opened_lookup[key] and not opportunity then
                        opportunity = { x = x, y = y }
                    end
                end
            end
        end
        -- At most one virtual extraction opportunity per distinct body node;
        -- every emergency-opened tile still receives its deterministic resource.
        if opportunity then opportunities[#opportunities + 1] = opportunity end
    end

    if #floor_tiles > 0 then
        surface.set_tiles(floor_tiles, true, false)
        for _, tile in ipairs(floor_tiles) do
            local position = tile.position
            mirror.set_floor(surface, position[1], position[2], tile.name)
            mirror.set_rock(surface, { x = position[1], y = position[2] }, false)
        end
    end

    -- Build the sealed outer envelope after opening the body footprint.  Never
    -- place a rock inside the collision-width safety circle of any body node.
    local outer_seen = {}
    for _, center in ipairs(centers) do
        for dy = -outer_radius, outer_radius do
            for dx = -outer_radius, outer_radius do
                local distance2 = dx * dx + dy * dy
                if distance2 > inner_radius * inner_radius
                    and distance2 <= outer_radius * outer_radius then
                    local x, y = center.x + dx, center.y + dy
                    local key = x .. "," .. y
                    if not inner_seen[key] and not outer_seen[key] then
                        outer_seen[key] = true
                        if is_playable_position(surface, x, y) and is_void(surface, x, y) then
                            make_wall(surface, seed, x, y)
                        end
                    end
                end
            end
        end
    end

    return {
        opened = opened,
        opportunities = opportunities,
        direction = demolisher_travel_direction(centers),
        clearance = math.max(32, inner_radius + 20),
    }
end

function world.on_dig(dig)
    world.advance_frontier(dig.surface, { { math.floor(dig.position.x), math.floor(dig.position.y) } })
end

-- Chunks generate as void; chunks touching the spawn carve-out get the
-- starting cave built instead: open floor, a wall ring, and the starter patch.
-- Guarded by a registry: the engine generates the starting chunks before mod
-- handlers can see them, so on_init sweeps existing chunks through this too.
--
-- Only originals and Cave child surfaces are built here. Copied worlds
-- already contain the original's cave; ensure_chunk reaches this for a copy
-- during frontier advance, and without this
-- guard it would lay a SECOND spawn ring on top of the cloned one (every
-- ring tile doubled). The other callers already filter worlds; this covers
-- ensure_chunk and any future caller.
function build_chunk(surface, area)
    if not is_cave_world_surface(surface) then return end
    clear_raw_chunk_resources(surface, area)
    local seed = surface.map_gen_settings.seed
    local lt, rb = area.left_top, area.right_bottom

    -- Every timed extraction-cave chunk starts as sealed void. Its first safe
    -- chamber is carved explicitly around the linked entrance coordinates;
    -- never create the normal origin starter room on these child surfaces.
    if is_uranium_cave_surface(surface) or is_mineral_cave_surface(surface) then
        local tiles = {}
        for x = lt.x, rb.x - 1 do
            for y = lt.y, rb.y - 1 do
                tiles[#tiles + 1] = { name = "out-of-map", position = { x, y } }
            end
        end
        surface.set_tiles(tiles)
        mirror.drop_chunk_at(surface, lt.x, lt.y)
        return
    end

    -- CAVETORIO owns the starter landing footprint. The legacy random starter
    -- room (circle/L/U/etc.) must not be carved on warp surfaces or on Warp #1,
    -- otherwise the first map looks different from later warps and leaves a
    -- stray market/room area beside the Outpost.
    if cavetorio_enabled() then
        local tiles = {}
        for x = lt.x, rb.x - 1 do
            for y = lt.y, rb.y - 1 do
                tiles[#tiles + 1] = { name = "out-of-map", position = { x, y } }
            end
        end
        surface.set_tiles(tiles)
        mirror.drop_chunk_at(surface, lt.x, lt.y)
        return
    end

    local start_shape = starter_shape(seed)
    local outer_params = starter_shape_params(seed, start_shape, CARVE_RADIUS)
    local inner_radius = math.max(4, CARVE_RADIUS - 3)
    local inner_params = starter_shape_params(seed, start_shape, inner_radius)

    local tiles, walls, ores = {}, {}, {}
    for x = lt.x, rb.x - 1 do
        for y = lt.y, rb.y - 1 do
            local inside = starter_inside_shape(x, y, CARVE_RADIUS, start_shape, outer_params)
            if not inside then
                tiles[#tiles + 1] = { name = "out-of-map", position = { x, y } }
            elseif x >= 5 and x <= 7 and y >= -1 and y <= 1 then
                -- Starter water hole: a guaranteed 3x3 pool near the origin.
                tiles[#tiles + 1] = { name = "water", position = { x, y } }
            else
                tiles[#tiles + 1] = { name = floor_tile(surface, seed, x, y), position = { x, y } }
                local inner = starter_inside_shape(x, y, inner_radius, start_shape, inner_params)
                if not inner then
                    walls[#walls + 1] = { x, y }
                elseif hash.roll(seed, x, y, S_STARTER) < 0.12 and x * x + y * y > 4 then
                    ores[#ores + 1] = { x, y }
                end
            end
        end
    end

    surface.set_tiles(tiles)
    for _, w in pairs(walls) do
        surface.create_entity { name = "diggy-rock", position = { w[1] + 0.5, w[2] + 0.5 }, force = "neutral" }
    end
    for _, o in pairs(ores) do
        surface.create_entity {
            name = pick_starter_ore(seed, o[1], o[2]),
            position = { o[1] + 0.5, o[2] + 0.5 },
            amount = 160,
        }
    end
    -- The starter pool comes stocked.
    if lt.x <= 6 and rb.x > 6 and lt.y <= 0 and rb.y > 0 then
        for _, p in pairs({ { 5.5, 0.5 }, { 6.5, -0.5 }, { 7.5, 1.5 } }) do
            surface.create_entity { name = "fish", position = p }
        end
    end
    -- Bulk rebuild: any cached mirror of this chunk is stale wholesale.
    mirror.drop_chunk_at(surface, lt.x, lt.y)
end

function chunk_key(surface, x, y)
    return surface.index .. ":" .. x .. ":" .. y
end

function world.is_chunk_built(surface, position)
    return storage.built_chunks and storage.built_chunks[chunk_key(surface, position.x, position.y)] == true or false
end

function world.ensure_built_chunk(surface, position, area)
    if not is_cave_world_surface(surface) then return false end
    local built_chunks = ensure_built_chunks()
    local key = chunk_key(surface, position.x, position.y)
    if built_chunks[key] then return false end
    built_chunks[key] = true
    area = area or {
        left_top = { x = position.x * 32, y = position.y * 32 },
        right_bottom = { x = (position.x + 1) * 32, y = (position.y + 1) * 32 },
    }
    build_chunk(surface, area)
    return true
end

function world.on_chunk_generated(event)
    world.ensure_built_chunk(event.surface, event.position, event.area)
end

-- Chart-driven generation can produce tile-only chunks that never fire
-- on_chunk_generated — raw engine terrain, visible on the map as dirt islands
-- in the void. Charted means seen: convert on sight.
function world.on_chunk_charted(event)
    world.ensure_built_chunk(game.surfaces[event.surface_index], event.position, event.area)
end

function world.on_init(preserve_built_chunks)
    -- During the staged in-save restart, spawn chunks are generated while the
    -- normal on_chunk_generated handler is already registered. Preserve that
    -- registry so this sweep builds only generator halo chunks and never lays
    -- a second set of spawn rocks/resources over chunks already converted.
    if preserve_built_chunks then
        storage.built_chunks = storage.built_chunks or {}
    else
        storage.built_chunks = {}
    end
    local surface = game.surfaces["nauvis"]
    disable_engine_entity_autoplace(surface)
    for chunk in surface.get_chunks() do
        local key = chunk_key(surface, chunk.x, chunk.y)
        if not storage.built_chunks[key] then
            storage.built_chunks[key] = true
            build_chunk(surface, chunk.area)
        end
    end
end

function world.on_configuration_changed()
    -- Existing saves retain their own LuaSurface map-gen settings. Repair those
    -- settings as well as the planet prototype so future chunks cannot keep
    -- generating the old isolated planetary resources.
    for _, surface in pairs(game.surfaces) do
        if is_main_nauvis_cave_surface(surface) then
            disable_engine_entity_autoplace(surface)
        end
    end

    -- One-time save migration for resources already generated by 2.6.2 and
    -- earlier. Limit cleanup to the central Nauvis region; scripted resources
    -- in Fulgora/Vulcanus/Aquilo remain untouched.
    if storage.the_cave_planetary_autoplace_cleanup_version ~= 1 then
        local removed = 0
        for _, surface in pairs(game.surfaces) do
            removed = removed + cleanup_legacy_central_planetary_resources(surface)
        end
        storage.the_cave_planetary_autoplace_cleanup_version = 1
        if removed > 0 then
            log("[The Cave] removed " .. removed .. " stray central planetary resource entities")
        end
    end
end

return world
