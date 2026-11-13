local settings = require("scripts.game_settings").proxy(settings)

-- The Cave region features.
-- Runtime placement for Space Age-style regions. Nauvis autoplace is bypassed
-- because The Cave builds the cave with set_tiles(), so resources/plants/enemies
-- must be spawned deterministically when a tile is opened.
local hash = require("scripts.lib.hash")
local Simplex = require("scripts.lib.simplex")
local depth_levels = require("scripts.depth_levels")
local advancing_zones = require("scripts.advancing_zones")
local progression_rooms = require("scripts.progression_rooms")

local features = {}

local S_RESOURCE, S_RESOURCE_KIND, S_PLANT, S_PLANT_KIND, S_ENEMY, S_ENEMY_KIND = 201, 202, 203, 204, 205, 206
local S_NEST, S_NEST_KIND, S_EGG = 207, 208, 209
local S_OIL, S_OIL_KIND = 210, 211
local S_FULGORA_ENV, S_FULGORA_KIND = 212, 213
local S_GLEBA_ROOM, S_GLEBA_ROOM_KIND = 214, 215
local S_VULCANUS_ROOM, S_VULCANUS_ROOM_KIND = 216, 217
local S_VULCANUS_ENV, S_VULCANUS_ENV_KIND = 218, 219
local S_AQUILO_ROOM, S_AQUILO_ROOM_KIND = 220, 221
local S_GLEBA_ENEMY_ROOM, S_GLEBA_RAFT_ROOM = 222, 223

local function exists(kind, name)
    return prototypes and prototypes[kind] and prototypes[kind][name]
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

local function region_at(x, y)
    if advancing_zones.is_active() then return advancing_zones.region_at(x, y) end
    -- Without Space Age, normal resources remain available everywhere.
    if not the_cave_space_age_enabled() then return "nauvis" end

    local ax, ay = math.abs(x), math.abs(y)
    if x * x + y * y < 1000 * 1000 then return "nauvis" end
    -- Nauvis ends at the 1000-tile radius. Every position beyond that circle
    -- belongs to the dominant-axis Space Age region; no diagonal Nauvis gaps.
    if ay >= ax then
        return y >= 0 and "gleba" or "aquilo"
    end
    return x < 0 and "vulcanus" or "fulgora"
end

features.region_at = region_at

local TENDRIL_SCALE = 1 / 40

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

local function resource_patch_size_multiplier()
    local setting = settings.startup["the-cave-resource-patch-size"]
    local value = setting and setting.value or "level-2"
    return RESOURCE_SIZE_MULTIPLIERS[value] or RESOURCE_SIZE_MULTIPLIERS["level-2"]
end

local function regional_patch_width(distance)
    -- Same depth-widening and Startup patch-size rule used by Nauvis ore veins.
    local depth_width = math.min(1 + distance / 350, 3.5)
    return depth_width * resource_patch_size_multiplier()
end

-- Space Age region resource profiles. Every entry uses the same deterministic
-- simplex-tendril rule as Nauvis; only the allowed prototypes, widths, richness
-- and spacing differ by region. Liquid tiles (lava/oil/ammoniacal ocean) remain
-- part of world terrain generation rather than ResourceEntity veins.
local RESOURCE_SETS = {
    vulcanus = {
        items = {
            { name = "tungsten-ore", noise_seed = 3210, width = 0.0060, amount = { 350, 950 }, no_depth_scale = true },
            { name = "calcite", noise_seed = 3220, width = 0.0100, amount = { 450, 1250 }, no_depth_scale = true },
            { name = "coal", noise_seed = 3230, width = 0.0120, amount = { 400, 1200 }, no_depth_scale = true },
            { name = "sulfuric-acid-geyser", noise_seed = 3240, width = 0.0032, amount = { 500000, 1000000 }, no_depth_scale = true, min_spacing = 9 },
        }
    },
    fulgora = {
        items = {
            { name = "scrap", noise_seed = 3310, width = 0.0150, amount = { 300, 1200 }, no_depth_scale = true },
        }
    },
    gleba = {
        items = {
            { name = "stone", noise_seed = 3410, width = 0.0080, amount = { 300, 950 }, no_depth_scale = true },
            { name = "iron-stromatolite", noise_seed = 3420, width = 0.0070, kind = "natural-entity", min_spacing = 4, tile = "lowland-red-vein" },
            { name = "copper-stromatolite", noise_seed = 3430, width = 0.0070, kind = "natural-entity", min_spacing = 4, tile = "lowland-olive-blubber" },
        }
    },
    aquilo = {
        items = {
            { name = "crude-oil", noise_seed = 3510, width = 0.0030, amount = { 1500000, 3000000 }, no_depth_scale = true, min_spacing = 10, spacing_names = { "crude-oil", "lithium-brine", "fluorine-vent" } },
            { name = "lithium-brine", noise_seed = 3520, width = 0.0040, amount = { 60000, 220000 }, no_depth_scale = true, min_spacing = 9, spacing_names = { "crude-oil", "lithium-brine", "fluorine-vent" } },
            { name = "fluorine-vent", noise_seed = 3530, width = 0.0032, amount = { 50000, 180000 }, no_depth_scale = true, min_spacing = 9, spacing_names = { "crude-oil", "lithium-brine", "fluorine-vent" } },
            { name = "lithium-iceberg-big", noise_seed = 3540, width = 0.0022, kind = "natural-entity", min_spacing = 18 },
            { name = "lithium-iceberg-huge", noise_seed = 3550, width = 0.0009, kind = "natural-entity", min_spacing = 36 },
        }
    }
}

local GLEBA_PLANTS = {
    -- The two harvestable Gleba crop trees are the important progression path.
    -- They need their matching natural soil under them or can_place_entity fails.
    { name = "yumako-tree", weight = 120, tile = "natural-yumako-soil", radius = 3 },
    { name = "jellystem", weight = 120, tile = "natural-jellynut-soil", radius = 3 },

    -- Wild Gleba vegetation for biome flavour. Each gets a safe Gleba land tile.
    { name = "cuttlepop", weight = 8, tile = "lowland-red-vein" },
    { name = "sunnycomb", weight = 8, tile = "lowland-red-infection" },
    { name = "slipstack", weight = 8, tile = "wetland-yumako" },
    { name = "funneltrunk", weight = 8, tile = "wetland-jellynut" },
    { name = "hairyclubnub", weight = 8, tile = "lowland-olive-blubber" },
    { name = "teflilly", weight = 8, tile = "lowland-cream-red" },
    { name = "lickmaw", weight = 8, tile = "lowland-red-vein-2" },
    { name = "stingfrond", weight = 8, tile = "lowland-red-vein-3" },
    { name = "boompuff", weight = 8, tile = "lowland-brown-blubber" },
    { name = "water-cane", weight = 8, tile = "wetland-yumako" },
}

-- The guaranteed Gleba room uses explicit placement instead of the ordinary
-- per-tile environment roll. Five of every requested wild plant are grouped
-- around its perimeter so they cannot be erased by the room preparation pass.
local GLEBA_PROGRESSION_WILD_PLANTS = {
    {
        name = "cuttlepop",
        tile = "lowland-red-vein",
        positions = { {-12, -14}, {-10, -14}, {-8, -14}, {-11, -12}, {-9, -12} },
    },
    {
        name = "sunnycomb",
        tile = "lowland-red-infection",
        positions = { {-4, -14}, {-2, -14}, {0, -14}, {2, -14}, {4, -14} },
    },
    {
        name = "slipstack",
        tile = "wetland-yumako",
        positions = { {8, -14}, {10, -14}, {12, -14}, {9, -12}, {11, -12} },
    },
    {
        name = "funneltrunk",
        tile = "wetland-jellynut",
        positions = { {-14, -10}, {-14, -8}, {-14, -6}, {-12, -9}, {-12, -7} },
    },
    {
        name = "hairyclubnub",
        tile = "lowland-olive-blubber",
        positions = { {-14, -3}, {-14, -1}, {-14, 1}, {-12, -2}, {-12, 0} },
    },
    {
        name = "teflilly",
        tile = "lowland-cream-red",
        positions = { {-14, 5}, {-14, 7}, {-14, 9}, {-12, 6}, {-12, 8} },
    },
    {
        name = "lickmaw",
        tile = "lowland-red-vein-2",
        positions = { {14, -10}, {14, -8}, {14, -6}, {12, -9}, {12, -7} },
    },
    {
        name = "stingfrond",
        tile = "lowland-red-vein-3",
        positions = { {14, -3}, {14, -1}, {14, 1}, {12, -2}, {12, 0} },
    },
    {
        name = "boompuff",
        tile = "lowland-brown-blubber",
        positions = { {14, 5}, {14, 7}, {14, 9}, {12, 6}, {12, 8} },
    },
}

local GLEBA_NESTS = {
    -- Official Space Age egg-raft prototype names. They are the intended source
    -- of the first Pentapod Eggs used for the Biochamber progression path.
    { name = "gleba-spawner-small", weight = 75, tile = "wetland-yumako", radius = 3 },
    { name = "gleba-spawner", weight = 25, tile = "wetland-jellynut", radius = 4 },
}

local GLEBA_ENEMIES_BY_LEVEL = {
    -- Wrigglers are the common swarm unit, Strafers are the ranged middle weight,
    -- and Stompers are intentionally rarer because each one is a major threat.
    easy = {
        { name = "small-wriggler-pentapod", weight = 48, pack_min = 2, pack_max = 3 },
        { name = "small-strafer-pentapod", weight = 34, pack_min = 1, pack_max = 2 },
        { name = "small-stomper-pentapod", weight = 18, pack_min = 1, pack_max = 1 },
    },
    medium = {
        { name = "small-wriggler-pentapod", weight = 24, pack_min = 2, pack_max = 3 },
        { name = "small-strafer-pentapod", weight = 18, pack_min = 1, pack_max = 2 },
        { name = "small-stomper-pentapod", weight = 8, pack_min = 1, pack_max = 1 },
        { name = "medium-wriggler-pentapod", weight = 24, pack_min = 2, pack_max = 3 },
        { name = "medium-strafer-pentapod", weight = 18, pack_min = 1, pack_max = 2 },
        { name = "medium-stomper-pentapod", weight = 8, pack_min = 1, pack_max = 1 },
    },
    hard = {
        { name = "medium-wriggler-pentapod", weight = 30, pack_min = 2, pack_max = 3 },
        { name = "medium-strafer-pentapod", weight = 22, pack_min = 1, pack_max = 2 },
        { name = "medium-stomper-pentapod", weight = 10, pack_min = 1, pack_max = 1 },
        { name = "big-wriggler-pentapod", weight = 20, pack_min = 2, pack_max = 3 },
        { name = "big-strafer-pentapod", weight = 13, pack_min = 1, pack_max = 2 },
        { name = "big-stomper-pentapod", weight = 5, pack_min = 1, pack_max = 1 },
    },
    nightmare = {
        { name = "big-wriggler-pentapod", weight = 50, pack_min = 2, pack_max = 4 },
        { name = "big-strafer-pentapod", weight = 34, pack_min = 1, pack_max = 2 },
        { name = "big-stomper-pentapod", weight = 16, pack_min = 1, pack_max = 1 },
    }
}

local GLEBA_ENEMY_NAMES = {
    "small-wriggler-pentapod", "small-strafer-pentapod", "small-stomper-pentapod",
    "medium-wriggler-pentapod", "medium-strafer-pentapod", "medium-stomper-pentapod",
    "big-wriggler-pentapod", "big-strafer-pentapod", "big-stomper-pentapod",
    "small-wriggler-pentapod-premature",
    "medium-wriggler-pentapod-premature",
    "big-wriggler-pentapod-premature",
}

local GLEBA_NEARBY_CAPS = {
    easy = 12,
    medium = 20,
    hard = 28,
    nightmare = 36,
}

-- Advancing Collapse can reach a planet family very early. Raw distance is
-- therefore not a useful danger scale: zone 4 is more than 2,000 tiles from
-- the origin and used to select Big Pentapods as if it were a late-game area.
-- These are live per-zone caps across the complete 510x704 ribbon zone. Egg
-- raft spawns and The Cave's own deterministic packs share the same budget.
local ADVANCING_GLEBA_LIMITS = {
    { through_zone = 5, total = 12, big = 0, maximum_tier = 1, level = "easy" },
    { through_zone = 10, total = 18, big = 1, maximum_tier = 3, level = "medium" },
    { through_zone = 20, total = 24, big = 2, maximum_tier = 3, level = "hard" },
    { through_zone = math.huge, total = 30, big = 3, maximum_tier = 3, level = "hard" },
}

local function pentapod_tier(name)
    if type(name) ~= "string" or not name:find("pentapod", 1, true) then return nil end
    if name:find("big-", 1, true) == 1 then return 3 end
    if name:find("medium-", 1, true) == 1 then return 2 end
    if name:find("small-", 1, true) == 1 then return 1 end
    return nil
end

local function advancing_gleba_profile(surface, x, y)
    if not (advancing_zones.is_active()
        and advancing_zones.is_main_surface(surface)) then
        return nil
    end
    local zone = advancing_zones.zone_at(x, y)
    if not (zone and zone.family == "gleba") then return nil end
    for _, limits in ipairs(ADVANCING_GLEBA_LIMITS) do
        if zone.index <= limits.through_zone then
            return {
                zone_index = zone.index,
                total = limits.total,
                big = limits.big,
                maximum_tier = limits.maximum_tier,
                level = limits.level,
            }
        end
    end
    return nil
end

function features.advancing_gleba_limits_at(surface, x, y)
    return advancing_gleba_profile(surface, x, y)
end

local function advancing_vulcanus_demolisher_profile(surface, x, y)
    if not (advancing_zones.is_active()
        and advancing_zones.is_main_surface(surface)) then
        return nil
    end
    local zone = advancing_zones.zone_at(x, y)
    if not (zone and zone.family == "vulcanus") then return nil end
    if zone.index <= 19 then
        return { zone_index = zone.index, chance = 0, names = {} }
    elseif zone.index <= 29 then
        return { zone_index = zone.index, chance = 0.22, names = { "small-demolisher" } }
    elseif zone.index <= 39 then
        return {
            zone_index = zone.index,
            chance = 0.30,
            names = { "small-demolisher", "small-demolisher", "medium-demolisher" },
        }
    elseif zone.index <= 49 then
        return { zone_index = zone.index, chance = 0.38, names = { "medium-demolisher" } }
    end
    return {
        zone_index = zone.index,
        chance = 0.45,
        names = { "medium-demolisher", "medium-demolisher", "big-demolisher" },
    }
end

function features.advancing_vulcanus_demolisher_limits_at(surface, x, y)
    return advancing_vulcanus_demolisher_profile(surface, x, y)
end

local VULCANUS_VOLCANIC_ROCKS = {
    -- These are the only mineable volcanic-rock simple entities exposed by Space Age.
    -- The "hot" variants are decorative-only concepts, not valid entity prototypes.
    { name = "big-volcanic-rock", weight = 74 },
    { name = "huge-volcanic-rock", weight = 26 },
}

local VULCANUS_TREES = {
    { name = "ashland-lichen-tree", weight = 85 },
    { name = "ashland-lichen-tree-flaming", weight = 15 },
}

local VULCANUS_NATURAL_NAMES = {
    "big-volcanic-rock", "huge-volcanic-rock",
    "ashland-lichen-tree", "ashland-lichen-tree-flaming",
}

local function planet_level_for_distance(distance)
    if distance >= 2500 then return "nightmare" end
    if distance >= 2000 then return "hard" end
    if distance >= 1500 then return "medium" end
    return "easy"
end

local function pick_weighted(seed, x, y, stream, list)
    local total = 0
    for _, item in pairs(list) do total = total + (item.weight or 1) end
    local roll = hash.roll(seed, x, y, stream) * total
    for _, item in pairs(list) do
        roll = roll - (item.weight or 1)
        if roll <= 0 then return item end
    end
    return list[#list]
end

local function safe_create(surface, spec)
    local ok, created = pcall(function()
        return surface.create_entity(spec)
    end)
    if ok then return created end
    return nil
end

local function resource_name(chosen)
    if not chosen then return nil end
    if chosen.name and exists("entity", chosen.name) then return chosen.name end
    if chosen.names then
        for _, n in pairs(chosen.names) do
            if exists("entity", n) then return n end
        end
    end
    return nil
end

local function create_resource_at(surface, seed, x, y, stream, chosen, distance)
    local rname = resource_name(chosen)
    if not rname then return false end
    local min_amount, max_amount = chosen.amount[1], chosen.amount[2]
    local amount = hash.range(seed, x, y, stream, min_amount, max_amount)
    if not chosen.no_depth_scale then
        amount = math.floor(amount * (1.25 + math.min(distance / 1400, 2.75)))
    end
    return safe_create(surface, {
        name = rname,
        position = { x + 0.5, y + 0.5 },
        amount = amount,
        force = "neutral"
    }) ~= nil
end

local function has_nearby_resource(surface, x, y, chosen)
    local spacing = chosen and chosen.min_spacing or 0
    if spacing <= 0 then return false end
    local names = {}

    if chosen and chosen.spacing_names then
        for _, n in ipairs(chosen.spacing_names) do names[#names + 1] = n end
    else
        if chosen.name then names[#names + 1] = chosen.name end
        if chosen.names then
            for _, n in ipairs(chosen.names) do names[#names + 1] = n end
        end
    end

    for _, n in pairs(names) do
        if exists("entity", n) then
            local found = surface.find_entities_filtered {
                name = n,
                position = { x + 0.5, y + 0.5 },
                radius = spacing,
                type = "resource"
            }
            if found and #found > 0 then return true end
        end
    end
    return false
end


local function create_elongated_patch(surface, seed, x, y, chosen, distance)
    -- Makes resource patches feel like real veins: longer footprint, lower amount per tile.
    -- Used for Fulgora scrap and Vulcanus tungsten/calcite. Deterministic orientation keeps multiplayer-safe generation.
    if not chosen.patch_rx or not chosen.patch_ry then return false end
    local rname = resource_name(chosen)
    if not rname then return false end

    local swap = hash.roll(seed, x, y, S_RESOURCE + 301) > 0.5
    local rx = chosen.patch_rx
    local ry = chosen.patch_ry
    if swap then rx, ry = ry, rx end

    local made = false
    for dx = -rx, rx do
        for dy = -ry, ry do
            local nx, ny = x + dx, y + dy
            if region_at(nx, ny) == region_at(x, y) then
                -- Ellipse-ish vein with ragged edges.
                local ex = dx / math.max(rx, 1)
                local ey = dy / math.max(ry, 1)
                local inside = (ex * ex + ey * ey) <= 1.08
                local keep = hash.roll(seed, nx, ny, S_RESOURCE + 302) <= (chosen.patch_chance or 0.8)
                if inside and keep then
                    local tile = surface.get_tile(nx, ny)
                    if tile and tile.valid and not tile.name:find("water", 1, true) then
                        local nearby = surface.find_entities_filtered {
                            area = { { nx, ny }, { nx + 1, ny + 1 } },
                            type = "resource"
                        }
                        if #nearby == 0 then
                            if create_resource_at(surface, seed, nx, ny, S_RESOURCE_KIND + 333, chosen, distance) then
                                made = true
                            end
                        end
                    end
                end
            end
        end
    end
    return made
end


local FULGORA_OIL_TILES = { "oil-ocean-shallow", "oil-ocean-deep" }

local function is_oil_ocean_tile_name(name)
    return name == "oil-ocean-shallow" or name == "oil-ocean-deep"
end

local function has_nearby_oil_ocean(surface, x, y, spacing)
    spacing = spacing or 70
    if not (exists("tile", "oil-ocean-shallow") or exists("tile", "oil-ocean-deep")) then return true end
    for _, tile in pairs(surface.find_tiles_filtered{
        area = { { x - spacing, y - spacing }, { x + spacing, y + spacing } }
    }) do
        if tile and tile.valid and is_oil_ocean_tile_name(tile.name) then return true end
    end
    return false
end

local function make_fulgora_oil_lake(surface, seed, x, y)
    -- Fulgora heavy oil should come from oil ocean + offshore pump, not pumpjack patches.
    -- This creates a small lake/shoreline inside The Cave so the vanilla offshore pump
    -- can extract heavy oil from Space Age oil-ocean tiles.
    if not exists("tile", "oil-ocean-shallow") then return false end
    if has_nearby_oil_ocean(surface, x, y, 90) then return false end

    local rx = hash.range(seed, x, y, S_OIL_KIND, 5, 8)
    local ry = hash.range(seed, x, y, S_OIL_KIND + 1, 4, 7)
    if hash.roll(seed, x, y, S_OIL_KIND + 2) > 0.5 then rx, ry = ry, rx end

    local tiles = {}
    for dx = -rx, rx do
        for dy = -ry, ry do
            local nx, ny = x + dx, y + dy
            if region_at(nx, ny) == "fulgora" then
                local ex = dx / math.max(rx, 1)
                local ey = dy / math.max(ry, 1)
                local d = ex * ex + ey * ey
                local ragged = hash.roll(seed, nx, ny, S_OIL_KIND + 3)
                if d <= 1.05 and ragged < 0.88 then
                    local current = surface.get_tile(nx, ny)
                    if current and current.valid and current.name ~= "out-of-map" then
                        local name = "oil-ocean-shallow"
                        if exists("tile", "oil-ocean-deep") and d < 0.35 and hash.roll(seed, nx, ny, S_OIL_KIND + 4) < 0.55 then
                            name = "oil-ocean-deep"
                        end
                        tiles[#tiles + 1] = { name = name, position = { nx, ny } }
                    end
                end
            end
        end
    end
    if #tiles == 0 then return false end

    local ok = pcall(function()
        surface.set_tiles(tiles, true, false, true)
        surface.destroy_decoratives { area = { { x - rx - 1, y - ry - 1 }, { x + rx + 2, y + ry + 2 } } }
    end)
    return ok
end

local function try_fulgora_oil_lake(surface, seed, x, y)
    if not exists("tile", "oil-ocean-shallow") then return false end
    -- Fairly rare, but not unfair: lakes are meant to be found while exploring Fulgora,
    -- and then pumped for unlimited heavy oil.
    if hash.roll(seed, x, y, S_OIL) > 0.0065 then return false end
    return make_fulgora_oil_lake(surface, seed, x, y)
end

-- Fulgora environmental entities. The Cave opens its terrain tile-by-tile, so
-- vanilla planet autoplace cannot create these objects for us. Spawn the real
-- Space Age prototypes deterministically as fresh Fulgora cave floor is opened.
local FULGORA_RUINS = {
    { name = "fulgoran-ruin-small",      weight = 46, min_spacing = 10, region_margin = 2 },
    { name = "fulgoran-ruin-medium",     weight = 28, min_spacing = 14, region_margin = 3 },
    { name = "fulgoran-ruin-stonehenge", weight = 12, min_spacing = 18, region_margin = 4 },
    { name = "fulgoran-ruin-big",        weight = 8,  min_spacing = 22, region_margin = 4 },
    { name = "fulgoran-ruin-huge",       weight = 4,  min_spacing = 30, region_margin = 6 },
    { name = "fulgoran-ruin-colossal",   weight = 2,  min_spacing = 40, region_margin = 8 },
}

local FULGORA_RUIN_NAMES = {
    "fulgoran-ruin-small",
    "fulgoran-ruin-medium",
    "fulgoran-ruin-stonehenge",
    "fulgoran-ruin-big",
    "fulgoran-ruin-huge",
    "fulgoran-ruin-colossal",
    "fulgoran-ruin-vault"
}

local FULGORA_VAULT_NAME = "fulgoran-ruin-vault"
local FULGORA_FULGURITE_NAMES = { "fulgurite", "fulgurite-small" }
local FULGORA_ROCK_NAMES = { "big-fulgora-rock" }

local function existing_entity_names(names)
    local result = {}
    for _, name in ipairs(names) do
        if exists("entity", name) then result[#result + 1] = name end
    end
    return result
end

local function fully_inside_fulgora(x, y, margin)
    margin = margin or 0
    if region_at(x, y) ~= "fulgora" then return false end
    if margin <= 0 then return true end
    local points = {
        { x - margin, y }, { x + margin, y },
        { x, y - margin }, { x, y + margin },
        { x - margin, y - margin }, { x - margin, y + margin },
        { x + margin, y - margin }, { x + margin, y + margin }
    }
    for _, point in ipairs(points) do
        if region_at(point[1], point[2]) ~= "fulgora" then return false end
    end
    return true
end

local function is_fulgora_land_tile(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    if tile.name == "out-of-map" or tile.name:find("water", 1, true) then return false end
    if is_oil_ocean_tile_name(tile.name) then return false end
    return true
end

local function has_nearby_named_entity(surface, x, y, radius, names)
    local valid_names = existing_entity_names(names)
    if #valid_names == 0 then return false end
    local found = surface.find_entities_filtered {
        position = { x + 0.5, y + 0.5 },
        radius = radius,
        name = valid_names
    }
    return found and #found > 0
end

local function has_resource_at(surface, x, y, radius)
    local found = surface.find_entities_filtered {
        position = { x + 0.5, y + 0.5 },
        radius = radius or 1.5,
        type = "resource"
    }
    return found and #found > 0
end

local function try_place_fulgora_entity(surface, spec, x, y, digging_force)
    if not (spec and spec.name and exists("entity", spec.name)) then return false end
    if not fully_inside_fulgora(x, y, spec.region_margin or 2) then return false end
    if not is_fulgora_land_tile(surface, x, y) then return false end
    if spec.avoid_resources and has_resource_at(surface, x, y, spec.resource_radius or 1.5) then return false end

    local entity_force = spec.player_force and (digging_force or "player") or "neutral"
    local position = { x + 0.5, y + 0.5 }
    local ok, created = pcall(function()
        if not surface.can_place_entity {
            name = spec.name,
            position = position,
            force = entity_force
        } then
            return nil
        end
        return surface.create_entity {
            name = spec.name,
            position = position,
            force = entity_force,
            raise_built = false
        }
    end)
    return ok and created and created.valid or false
end

local function try_fulgora_vault(surface, seed, x, y, digging_force)
    if not exists("entity", "fulgoran-ruin-vault") then return false end
    -- The vault is progression-relevant but enormous. Keep it rare and far from
    -- other vaults so it remains a special exploration find rather than clutter.
    if hash.roll(seed, x, y, S_FULGORA_ENV + 1) > 0.00006 then return false end
    if has_nearby_named_entity(surface, x, y, 500, { "fulgoran-ruin-vault" }) then return false end
    if has_nearby_named_entity(surface, x, y, 55, FULGORA_RUIN_NAMES) then return false end
    return try_place_fulgora_entity(surface, {
        name = "fulgoran-ruin-vault",
        region_margin = 10,
        avoid_resources = true,
        resource_radius = 6
    }, x, y, digging_force)
end

local function try_fulgora_attractor(surface, seed, x, y, digging_force)
    if not exists("entity", "fulgoran-ruin-attractor") then return false end
    if hash.roll(seed, x, y, S_FULGORA_ENV + 2) > 0.0010 then return false end
    if has_nearby_named_entity(surface, x, y, 90, { "fulgoran-ruin-attractor" }) then return false end
    return try_place_fulgora_entity(surface, {
        name = "fulgoran-ruin-attractor",
        player_force = true,
        region_margin = 22,
        avoid_resources = true,
        resource_radius = 2
    }, x, y, digging_force)
end

local function try_fulgora_fulgurite(surface, seed, x, y, digging_force)
    if not exists("entity", "fulgurite") then return false end
    if hash.roll(seed, x, y, S_FULGORA_ENV + 3) > 0.0030 then return false end
    if has_nearby_named_entity(surface, x, y, 27, FULGORA_FULGURITE_NAMES) then return false end
    return try_place_fulgora_entity(surface, {
        name = "fulgurite",
        region_margin = 4,
        avoid_resources = true,
        resource_radius = 2
    }, x, y, digging_force)
end

local function try_fulgora_ruin(surface, seed, x, y, digging_force)
    if hash.roll(seed, x, y, S_FULGORA_ENV + 4) > 0.0050 then return false end
    local chosen = pick_weighted(seed, x, y, S_FULGORA_KIND, FULGORA_RUINS)
    if not (chosen and exists("entity", chosen.name)) then return false end
    if has_nearby_named_entity(surface, x, y, chosen.min_spacing or 12, FULGORA_RUIN_NAMES) then return false end
    return try_place_fulgora_entity(surface, {
        name = chosen.name,
        region_margin = chosen.region_margin,
        avoid_resources = true,
        resource_radius = math.max(1.5, (chosen.region_margin or 2) * 0.5)
    }, x, y, digging_force)
end


-- Every normal Empty Room generated in the Fulgora region is converted into a
-- dedicated Fulgora Ruins Room by caverns.lua. The whole room is re-tiled with
-- real Space Age Fulgora ruin flooring and populated only after carving has
-- finished. This makes the room look like an actual ruined district and avoids
-- the old single-entity placement attempt silently failing.
local FULGORA_ROOM_TILES = {
    paving = "fulgoran-paving",
    walls = "fulgoran-walls",
    conduit = "fulgoran-conduit",
    machinery = "fulgoran-machinery",
}

local FULGORA_ROOM_MAIN_RUINS = {
    { name = "fulgoran-ruin-medium", weight = 38 },
    { name = "fulgoran-ruin-stonehenge", weight = 24 },
    { name = "fulgoran-ruin-big", weight = 22 },
    { name = "fulgoran-ruin-huge", weight = 12 },
    { name = "fulgoran-ruin-colossal", weight = 4 },
}

local FULGORA_ROOM_SIDE_RUINS = {
    { name = "fulgoran-ruin-small", weight = 62 },
    { name = "fulgoran-ruin-medium", weight = 28 },
    { name = "fulgoran-ruin-stonehenge", weight = 10 },
}

local function existing_tile_name(preferred, fallback)
    if preferred and exists("tile", preferred) then return preferred end
    if fallback and exists("tile", fallback) then return fallback end
    return nil
end

local function fulgora_room_tile(seed, cx, cy, x, y, half)
    local paving = existing_tile_name(FULGORA_ROOM_TILES.paving, "fulgoran-sand")
    local walls = existing_tile_name(FULGORA_ROOM_TILES.walls, paving)
    local conduit = existing_tile_name(FULGORA_ROOM_TILES.conduit, paving)
    local machinery = existing_tile_name(FULGORA_ROOM_TILES.machinery, paving)
    if not paving then return nil end

    local dx, dy = x - cx, y - cy
    local edge = math.max(math.abs(dx), math.abs(dy))
    local roll = hash.roll(seed, x, y, S_FULGORA_KIND + 810)

    -- Broken perimeter walls, crossed buried conduits, and machinery patches
    -- mimic the real Fulgora settlement-floor vocabulary without relying on
    -- vanilla noise autoplace (which The Cave bypasses with scripted carving).
    if edge >= half - 1 and roll > 0.16 then
        return walls
    end
    if (math.abs(dx) <= 1 or math.abs(dy) <= 1) and roll > 0.08 then
        return conduit
    end
    if ((math.abs(dx - math.floor(half * 0.45)) <= 2 and math.abs(dy) <= 3)
        or (math.abs(dx + math.floor(half * 0.42)) <= 2 and math.abs(dy - math.floor(half * 0.25)) <= 3))
        and roll > 0.18 then
        return machinery
    end
    if roll > 0.91 then return machinery end
    if roll > 0.77 then return walls end
    return paving
end

local function prepare_fulgora_ruin_room(surface, cx, cy, half, seed)
    local tiles = {}
    for x = cx - half, cx + half do
        for y = cy - half, cy + half do
            local tile_name = fulgora_room_tile(seed, cx, cy, x, y, half)
            if tile_name then
                tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
            end
        end
    end

    if #tiles > 0 then
        pcall(function()
            surface.set_tiles(tiles, true, false, true)
            surface.destroy_decoratives {
                area = {
                    { cx - half - 1, cy - half - 1 },
                    { cx + half + 2, cy + half + 2 }
                }
            }
        end)
    end

    -- The room is generated as an Empty Room and region features are suppressed,
    -- but old overlap, pre-2.5.45 terrain, or a resource vein can still occupy a
    -- placement cell. Remove only natural cave blockers; player structures and
    -- characters are deliberately preserved.
    local blockers = surface.find_entities_filtered {
        area = {
            { cx - half + 1, cy - half + 1 },
            { cx + half, cy + half }
        }
    }
    for _, entity in pairs(blockers or {}) do
        if entity.valid then
            local remove = entity.type == "resource"
                or entity.name == "diggy-rock"
                or entity.name == "diggy-tree"
                or entity.name == "big-fulgora-rock"
                or entity.name == "fulgurite"
                or entity.name == "fulgurite-small"
            if remove then entity.destroy() end
        end
    end
end

function features.fulgora_ruin_room_radius()
    local minimum_radius = 24
    local vault = exists("entity", "fulgoran-ruin-vault")
    local box = vault and vault.collision_box
    if not box then return minimum_radius end

    local left_top = box.left_top or box[1]
    local right_bottom = box.right_bottom or box[2]
    if not (left_top and right_bottom) then return minimum_radius end

    local extent = math.max(
        math.abs(left_top.x or left_top[1] or 0),
        math.abs(left_top.y or left_top[2] or 0),
        math.abs(right_bottom.x or right_bottom[1] or 0),
        math.abs(right_bottom.y or right_bottom[2] or 0)
    )
    -- Square carving uses radius * 0.78 as half-width. Keep a generous ring
    -- around the Vault for side ruins and player movement.
    return math.max(minimum_radius, math.ceil((extent + 8) / 0.78))
end

local function place_room_ruin(surface, name, cx, cy, half, tx, ty, search_radius)
    if not exists("entity", name) then return nil end

    local function create_at(position)
        local ok, entity = pcall(function()
            -- Natural ruins are neutral simple entities; omitting force matches
            -- vanilla creation and does not depend on player-build checks.
            return surface.create_entity {
                name = name,
                position = position,
                raise_built = false
            }
        end)
        if ok and entity and entity.valid then return entity end
        return nil
    end

    local target = { x = tx + 0.5, y = ty + 0.5 }
    local entity = create_at(target)
    if entity then return entity end

    local function valid_room_position(position)
        if not position then return false end
        local px, py = position.x or position[1], position.y or position[2]
        return px and py
            and px >= cx - half + 2 and px <= cx + half - 1
            and py >= cy - half + 2 and py <= cy + half - 1
    end

    -- First retry within the intended local sector.
    local ok_find, found = pcall(function()
        return surface.find_non_colliding_position(name, target, search_radius or 5, 0.5, true)
    end)
    if ok_find and valid_room_position(found) then
        entity = create_at(found)
        if entity then return entity end
    end

    -- Local sector blocked: retry across the whole prepared room.
    local ok_room, room_found = pcall(function()
        return surface.find_non_colliding_position(name, { x = cx + 0.5, y = cy + 0.5 }, half - 2, 0.5, true)
    end)
    if ok_room and valid_room_position(room_found) then
        entity = create_at(room_found)
        if entity then return entity end
    end

    return nil
end

local function ruin_room_state(surface, digging_force)
    storage.the_cave_fulgora_ruin_rooms = storage.the_cave_fulgora_ruin_rooms or {}
    local force_index = digging_force and digging_force.index or 1
    local key = tostring(surface.index) .. ":" .. tostring(force_index)
    local state = storage.the_cave_fulgora_ruin_rooms[key]
    if not state then
        state = { rooms = 0, vault_placed = false }
        storage.the_cave_fulgora_ruin_rooms[key] = state
    end
    return state
end

local function fulgora_recycling_recovery_flags()
    storage.the_cave_fulgora_recycling_recovery =
        storage.the_cave_fulgora_recycling_recovery or {}
    return storage.the_cave_fulgora_recycling_recovery
end

local function playable_force(force)
    return force
        and force.valid
        and force.name ~= "enemy"
        and force.name ~= "neutral"
end

local function recycling_locked(force)
    local technology = playable_force(force)
        and force.technologies
        and force.technologies["recycling"]
    return technology and not technology.researched, technology
end

local function flow_statistic_count(statistics, method_name)
    local method = statistics and statistics[method_name]
    if not method then return 0 end

    -- Factorio 2.0 accepts the entity prototype name directly. Keep a
    -- quality-aware fallback for later 2.x runtimes without changing the
    -- migration result on the supported 2.0 branch.
    local ok, count = pcall(method, FULGORA_VAULT_NAME)
    if not ok then
        ok, count = pcall(method, { name = FULGORA_VAULT_NAME, quality = "normal" })
    end
    return ok and (tonumber(count) or 0) or 0
end

local function force_mined_fulgora_vault(force)
    if not playable_force(force) then return false end

    for _, surface in pairs(game.surfaces) do
        local ok, statistics = pcall(function()
            return force.get_entity_build_count_statistics(surface)
        end)
        if ok and statistics then
            -- Entity-build statistics contain built and mined counts. A
            -- Fulgoran Vault Ruin cannot normally be built by a player force,
            -- so either non-zero side is safe evidence of the missed mining
            -- event across Factorio 2.x statistic orientations.
            local input = flow_statistic_count(statistics, "get_input_count")
            local output = flow_statistic_count(statistics, "get_output_count")
            if input > 0 or output > 0 then return true end
        end
    end
    return false
end

local function force_had_guaranteed_fulgora_vault(force)
    local states = storage.the_cave_fulgora_ruin_rooms
    if type(states) ~= "table" then return false end

    local suffix = ":" .. tostring(force.index)
    for key, state in pairs(states) do
        if type(key) == "string"
            and key:sub(-#suffix) == suffix
            and type(state) == "table"
            and state.vault_placed then
            return true
        end
    end
    return false
end

local function repair_existing_fulgora_recycling()
    if not (game and the_cave_space_age_enabled() and exists("entity", FULGORA_VAULT_NAME)) then
        return
    end

    local recovery = fulgora_recycling_recovery_flags()
    for _, force in pairs(game.forces) do
        if playable_force(force) then
            local locked, technology = recycling_locked(force)
            local discovery = force.technologies
                and force.technologies["planet-discovery-fulgora"]

            if not locked then
                recovery[force.index] = nil
            elseif discovery and discovery.researched and force_mined_fulgora_vault(force) then
                -- The force already performed the exact official mining action,
                -- but an older save could not satisfy Recycling while Planet
                -- Discovery was still an unmet prerequisite. Restore only that
                -- missed official result and let Factorio apply its recipe effects.
                technology.researched = true
                recovery[force.index] = nil
                force.print({ "the-cave-runtime.fulgora-recycling-restored" })
            elseif discovery and discovery.researched
                and force_had_guaranteed_fulgora_vault(force) then
                -- Some old/reset statistics cannot prove the earlier mining
                -- event. Queue exactly one replacement in the next Fulgora
                -- Ruins Room so the vanilla mine-entity trigger remains usable.
                recovery[force.index] = true
            end
        end
    end
end

function features.populate_fulgora_ruin_room(surface, cx, cy, radius, seed, digging_force, require_vault)
    if not (surface and surface.valid) then return 0 end

    -- Square cavern carving uses roughly radius * 0.78 as its half-width.
    local half = math.max(15, math.floor((radius or 24) * 0.78 + 0.5))
    prepare_fulgora_ruin_room(surface, cx, cy, half, seed)

    local state = ruin_room_state(surface, digging_force)
    state.rooms = (state.rooms or 0) + 1

    local placed = 0
    local main_entity = nil
    local force_index = digging_force and digging_force.valid and digging_force.index or nil
    local recovery = fulgora_recycling_recovery_flags()
    local locked = recycling_locked(digging_force)
    local recovery_requested = force_index and recovery[force_index] == true and locked
    if force_index and not locked then recovery[force_index] = nil end

    -- The first newly generated Fulgora Ruins Room for each force/surface
    -- guarantees the real progression entity. Mining this exact vanilla entity
    -- satisfies Space Age's recycling-research trigger. Existing saves which
    -- lost that one-time opportunity may request one replacement Vault.
    if (require_vault or not state.vault_placed or recovery_requested)
        and exists("entity", FULGORA_VAULT_NAME) then
        main_entity = place_room_ruin(surface, FULGORA_VAULT_NAME, cx, cy, half, cx, cy, half - 2)
        if main_entity then
            state.vault_placed = true
            if recovery_requested then recovery[force_index] = nil end
            placed = placed + 1
            if locked and playable_force(digging_force) then
                digging_force.print({ "the-cave-runtime.fulgora-recycling-vault-hint" })
            end
        end
    end

    if not main_entity then
        local chosen = pick_weighted(seed, cx, cy, S_FULGORA_KIND + 820, FULGORA_ROOM_MAIN_RUINS)
        if chosen then
            main_entity = place_room_ruin(surface, chosen.name, cx, cy, half, cx, cy, half - 2)
            if main_entity then placed = placed + 1 end
        end
    end

    -- Build a small ruined district around the main structure. Each placement
    -- searches only its local sector first, so the result remains spread out and
    -- deterministic rather than piling everything at the room centre.
    local inset = math.max(6, half - 6)
    local offsets = {
        { -inset, -inset }, { inset, -inset }, { -inset, inset }, { inset, inset },
        { 0, -inset }, { inset, 0 }, { 0, inset }, { -inset, 0 },
    }
    local side_count = hash.range(seed, cx, cy, S_FULGORA_KIND + 821, 5, 8)
    local start = hash.range(seed, cx, cy, S_FULGORA_KIND + 822, 1, #offsets)
    for i = 0, side_count - 1 do
        local offset = offsets[((start + i - 1) % #offsets) + 1]
        local chosen = pick_weighted(seed, cx + offset[1], cy + offset[2], S_FULGORA_KIND + 830 + i, FULGORA_ROOM_SIDE_RUINS)
        if chosen then
            local entity = place_room_ruin(
                surface,
                chosen.name,
                cx,
                cy,
                half,
                cx + offset[1],
                cy + offset[2],
                4
            )
            if entity then placed = placed + 1 end
        end
    end

    -- Absolute fail-safe: never announce a Ruins Room unless an actual vanilla
    -- Fulgoran ruin exists inside it. A small ruin is retried across the full room.
    if placed == 0 and exists("entity", "fulgoran-ruin-small") then
        local fallback = place_room_ruin(surface, "fulgoran-ruin-small", cx, cy, half, cx, cy, half - 2)
        if fallback then placed = 1 end
    end

    return placed, main_entity ~= nil and main_entity.valid
        and main_entity.name == FULGORA_VAULT_NAME
end

local function try_fulgora_rock(surface, seed, x, y, digging_force)
    if not exists("entity", "big-fulgora-rock") then return false end
    if hash.roll(seed, x, y, S_FULGORA_ENV + 5) > 0.0016 then return false end
    if has_nearby_named_entity(surface, x, y, 18, FULGORA_ROCK_NAMES) then return false end
    return try_place_fulgora_entity(surface, {
        name = "big-fulgora-rock",
        region_margin = 3,
        avoid_resources = true,
        resource_radius = 2
    }, x, y, digging_force)
end

local function try_fulgora_environment(surface, seed, x, y, digging_force)
    -- Priority keeps one large environmental object per opened tile and prevents
    -- stacking a ruin, fulgurite and attractor on the same position.
    if try_fulgora_vault(surface, seed, x, y, digging_force) then return true end
    if try_fulgora_attractor(surface, seed, x, y, digging_force) then return true end
    if try_fulgora_fulgurite(surface, seed, x, y, digging_force) then return true end
    if try_fulgora_ruin(surface, seed, x, y, digging_force) then return true end
    if try_fulgora_rock(surface, seed, x, y, digging_force) then return true end
    return false
end

local function tile_accepts_resource(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    local name = tile.name or ""
    if name == "out-of-map" then return false end
    if name:find("water", 1, true) or name:find("ocean", 1, true) or name:find("lava", 1, true) then return false end
    local resources = surface.find_entities_filtered {
        area = { { x, y }, { x + 1, y + 1 } },
        type = "resource"
    }
    return not resources or #resources == 0
end

local function has_nearby_natural_entity(surface, x, y, chosen)
    local spacing = chosen and chosen.min_spacing or 0
    if spacing <= 0 then return false end
    local found = surface.find_entities_filtered {
        name = chosen.name,
        position = { x + 0.5, y + 0.5 },
        radius = spacing
    }
    return found and #found > 0
end

local function create_natural_vein_entity(surface, x, y, region, chosen)
    if not (chosen and chosen.name and exists("entity", chosen.name)) then return false end
    if has_nearby_natural_entity(surface, x, y, chosen) then return false end

    if chosen.tile and exists("tile", chosen.tile) then
        pcall(function()
            surface.set_tiles({ { name = chosen.tile, position = { x, y } } }, true, false, true)
        end)
    end

    local origin = { x + 0.5, y + 0.5 }
    local position = origin
    local can_place = false
    pcall(function()
        can_place = surface.can_place_entity { name = chosen.name, position = origin, force = "neutral" }
    end)
    if not can_place then
        local ok, found = pcall(function()
            return surface.find_non_colliding_position(chosen.name, origin, 5, 0.5)
        end)
        if not (ok and found) then return false end
        if region_at(math.floor(found.x or found[1]), math.floor(found.y or found[2])) ~= region then return false end
        position = found
    end

    return safe_create(surface, {
        name = chosen.name,
        position = position,
        force = "neutral",
        raise_built = false
    }) ~= nil
end

local function try_resource(surface, seed, x, y, region, distance, resources_only)
    local set = RESOURCE_SETS[region]
    if not set then return false end

    local px, py = x + 0.5, y + 0.5
    local width_multiplier = regional_patch_width(distance)

    for index, chosen in ipairs(set.items) do
        if (not resources_only or chosen.kind ~= "natural-entity") and resource_name(chosen) then
            local noise = Simplex.d2(px * TENDRIL_SCALE, py * TENDRIL_SCALE, seed + chosen.noise_seed)
            if math.abs(noise) < chosen.width * width_multiplier then
                if chosen.kind == "natural-entity" then
                    if create_natural_vein_entity(surface, x, y, region, chosen) then
                        return true
                    end
                elseif tile_accepts_resource(surface, x, y) and not has_nearby_resource(surface, x, y, chosen) then
                    if create_resource_at(surface, seed, x, y, S_RESOURCE_KIND + 40 + index, chosen, distance) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function safe_set_tile(surface, x, y, tile_name)
    if not tile_name or not exists("tile", tile_name) then return false end
    local ok = pcall(function()
        surface.set_tiles({ { name = tile_name, position = { x, y } } }, true, false, true)
    end)
    return ok
end

local function set_gleba_soil_patch(surface, x, y, tile_name, radius)
    if not tile_name or not exists("tile", tile_name) then return false end
    radius = radius or 1
    local tiles = {}
    for dx = -radius, radius do
        for dy = -radius, radius do
            tiles[#tiles + 1] = { name = tile_name, position = { x + dx, y + dy } }
        end
    end
    local ok = pcall(function()
        surface.set_tiles(tiles, true, false, true)
        surface.destroy_decoratives { area = { { x - radius - 1, y - radius - 1 }, { x + radius + 2, y + radius + 2 } } }
    end)
    return ok
end


-- Every normal Empty Room generated in the Gleba region is converted into a
-- deterministic progression room by caverns.lua. The room contains every
-- natural trigger/resource needed to start the official Gleba research chain:
-- Iron Stromatolite, Yumako, Jellynut, Copper Stromatolite, water, and an Egg
-- Raft that yields Pentapod Eggs. Per-tile regional rolls are suppressed while
-- carving so bad luck can no longer progression-lock a force.
local GLEBA_ROOM_MIN_RADIUS = 20

local function gleba_existing_tile(preferred, fallback)
    if preferred and exists("tile", preferred) then return preferred end
    if fallback and exists("tile", fallback) then return fallback end
    return nil
end

function features.gleba_progression_room_radius()
    return GLEBA_ROOM_MIN_RADIUS
end

local function append_rect_tiles(tiles, name, x1, y1, x2, y2)
    if not name then return end
    for x = x1, x2 do
        for y = y1, y2 do
            tiles[#tiles + 1] = { name = name, position = { x, y } }
        end
    end
end

local function prepare_gleba_progression_room(surface, cx, cy, half)
    local base = gleba_existing_tile("lowland-cream-red", "lowland-red-vein")
    local yumako_soil = gleba_existing_tile("natural-yumako-soil", base)
    local jelly_soil = gleba_existing_tile("natural-jellynut-soil", base)
    local iron_ground = gleba_existing_tile("lowland-red-vein", base)
    local copper_ground = gleba_existing_tile("lowland-olive-blubber", base)
    local marsh = gleba_existing_tile("wetland-yumako", gleba_existing_tile("wetland-jellynut", base))
    local water = gleba_existing_tile("water", gleba_existing_tile("water-shallow", marsh))

    local tiles = {}
    append_rect_tiles(tiles, base, cx - half, cy - half, cx + half, cy + half)

    -- Two generous crop plots so the player can immediately mine both trigger
    -- trees and later reuse the same room for agriculture.
    append_rect_tiles(tiles, yumako_soil, cx - 13, cy - 6, cx - 3, cy + 5)
    append_rect_tiles(tiles, jelly_soil, cx + 3, cy - 6, cx + 13, cy + 5)

    -- Dedicated stromatolite shelves at the back of the room.
    append_rect_tiles(tiles, iron_ground, cx - 13, cy - 13, cx - 3, cy - 8)
    append_rect_tiles(tiles, copper_ground, cx + 3, cy - 13, cx + 13, cy - 8)

    -- Official egg rafts live on Gleba marsh tiles. A separate water pond beside
    -- the raft guarantees water for later Pentapod Egg replication recipes.
    append_rect_tiles(tiles, marsh, cx - 4, cy + 7, cx + 4, cy + 12)
    append_rect_tiles(tiles, water, cx - 3, cy + 13, cx + 3, cy + 15)

    pcall(function()
        surface.set_tiles(tiles, true, false, true)
        surface.destroy_decoratives {
            area = {
                { cx - half - 1, cy - half - 1 },
                { cx + half + 2, cy + half + 2 }
            }
        }
    end)

    -- Remove only natural cave/planet blockers left by overlap with older rooms.
    -- Player structures, trains, characters and their resources are preserved.
    local blockers = surface.find_entities_filtered {
        area = {
            { cx - half + 1, cy - half + 1 },
            { cx + half, cy + half }
        }
    }
    for _, entity in pairs(blockers or {}) do
        if entity.valid then
            local force_name = entity.force and entity.force.name or "neutral"
            local natural_force = force_name == "neutral" or force_name == "enemy"
            local natural_type = entity.type == "resource"
                or entity.type == "tree"
                or entity.type == "simple-entity"
                or entity.type == "unit"
                or entity.type == "unit-spawner"
                or entity.name == "diggy-rock"
                or entity.name == "diggy-tree"
            if natural_force and natural_type then
                pcall(function() entity.destroy() end)
            end
        end
    end
end

local function place_gleba_room_entity(surface, name, tx, ty, force, cx, cy, half, search_radius)
    if not exists("entity", name) then return nil end
    local target = { x = tx + 0.5, y = ty + 0.5 }

    local function inside_room(position)
        if not position then return false end
        local px, py = position.x or position[1], position.y or position[2]
        return px and py
            and px >= cx - half + 2 and px <= cx + half - 1
            and py >= cy - half + 2 and py <= cy + half - 1
    end

    local function create_at(position)
        local ok, entity = pcall(function()
            return surface.create_entity {
                name = name,
                position = position,
                force = force or "neutral",
                raise_built = false
            }
        end)
        if ok and entity and entity.valid then return entity end
        return nil
    end

    local entity = create_at(target)
    if entity then return entity end

    local ok_find, found = pcall(function()
        return surface.find_non_colliding_position(name, target, search_radius or 4, 0.5, true)
    end)
    if ok_find and inside_room(found) then
        entity = create_at(found)
        if entity then return entity end
    end
    return nil
end

local GLEBA_WILD_TARGET_PER_KIND = 5

local GLEBA_NATURAL_ROOM_TILES = {
    ["lowland-cream-red"] = true,
    ["lowland-red-vein"] = true,
    ["lowland-red-infection"] = true,
    ["wetland-yumako"] = true,
    ["wetland-jellynut"] = true,
    ["lowland-olive-blubber"] = true,
    ["lowland-red-vein-2"] = true,
    ["lowland-red-vein-3"] = true,
    ["lowland-brown-blubber"] = true,
    ["natural-yumako-soil"] = true,
    ["natural-jellynut-soil"] = true,
}

local function gleba_wild_target_is_safe(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid and GLEBA_NATURAL_ROOM_TILES[tile.name]) then
        return false
    end

    local entities = surface.find_entities_filtered {
        area = { { x - 0.75, y - 0.75 }, { x + 1.75, y + 1.75 } },
    }
    for _, entity in pairs(entities or {}) do
        if entity.valid then
            local natural = entity.type == "tree"
                or (entity.type == "fish" and progression_rooms.manages(surface))
                or entity.type == "simple-entity"
                or entity.type == "resource"
                or entity.type == "unit"
                or entity.type == "unit-spawner"
            if not natural then return false end
        end
    end
    return true
end

-- Adds only the missing wild plants and never clears the room. This is shared
-- by new-room generation and the one-time existing-save recovery.
function features.populate_gleba_progression_wild_plants(surface, cx, cy, radius)
    if not (surface and surface.valid) then return 0, false end
    local half = math.max(16, math.floor((radius or GLEBA_ROOM_MIN_RADIUS) * 0.78 + 0.5))
    local area = {
        { cx - half + 1, cy - half + 1 },
        { cx + half, cy + half },
    }
    local total = 0
    local all_ready = true

    for _, spec in ipairs(GLEBA_PROGRESSION_WILD_PLANTS) do
        local current = 0
        if exists("entity", spec.name) then
            current = #(surface.find_entities_filtered { name = spec.name, area = area } or {})
        end

        for _, offset in ipairs(spec.positions) do
            if current >= GLEBA_WILD_TARGET_PER_KIND then break end
            local x, y = cx + offset[1], cy + offset[2]
            if gleba_wild_target_is_safe(surface, x, y) then
                local tile_name = gleba_existing_tile(spec.tile, "lowland-cream-red")
                set_gleba_soil_patch(surface, x, y, tile_name, 0)
                local entity = place_gleba_room_entity(
                    surface, spec.name, x, y, "neutral", cx, cy, half, 3
                )
                if entity then current = current + 1 end
            end
        end

        total = total + math.min(current, GLEBA_WILD_TARGET_PER_KIND)
        if current < GLEBA_WILD_TARGET_PER_KIND then all_ready = false end
    end

    return total, all_ready
end

function features.populate_gleba_progression_room(surface, cx, cy, radius, seed, digging_force)
    if not (surface and surface.valid) then return 0, false end
    local half = math.max(16, math.floor((radius or GLEBA_ROOM_MIN_RADIUS) * 0.78 + 0.5))
    prepare_gleba_progression_room(surface, cx, cy, half)

    local counts = {
        iron = 0,
        copper = 0,
        yumako = 0,
        jelly = 0,
        egg_raft = 0,
        wild = 0,
    }

    local function place_many(kind, name, positions, force, search_radius)
        for _, pos in ipairs(positions) do
            local entity = place_gleba_room_entity(
                surface, name, cx + pos[1], cy + pos[2], force, cx, cy, half, search_radius
            )
            if entity then counts[kind] = counts[kind] + 1 end
        end
    end

    place_many("yumako", "yumako-tree", {
        {-10, -3}, {-7, 2}, {-4, -2}
    }, "neutral", 3)
    place_many("jelly", "jellystem", {
        {10, -3}, {7, 2}, {4, -2}
    }, "neutral", 3)
    place_many("iron", "iron-stromatolite", {
        {-11, -11}, {-7, -10}, {-4, -12}
    }, "neutral", 3)
    place_many("copper", "copper-stromatolite", {
        {11, -11}, {7, -10}, {4, -12}
    }, "neutral", 3)

    -- Prefer the small official Egg Raft so the guaranteed progression room is
    -- useful without turning every Empty Room into a large enemy base.
    local raft_name = exists("entity", "gleba-spawner-small") and "gleba-spawner-small" or "gleba-spawner"
    if raft_name and exists("entity", raft_name) then
        local raft = place_gleba_room_entity(surface, raft_name, cx, cy + 9, "enemy", cx, cy, half, 4)
        if raft then counts.egg_raft = 1 end
    end

    local wild_ready = false
    counts.wild, wild_ready = features.populate_gleba_progression_wild_plants(
        surface, cx, cy, radius
    )
    -- A bounded refill supplies targets displaced by the first placement pass;
    -- it adds only missing plants and never clears the starter room again.
    if not wild_ready and progression_rooms.manages(surface) then
        counts.wild, wild_ready = features.populate_gleba_progression_wild_plants(
            surface, cx, cy, radius)
    end

    local total = counts.iron + counts.copper + counts.yumako + counts.jelly
        + counts.egg_raft + counts.wild
    local progression_ready = counts.iron > 0
        and counts.yumako > 0
        and counts.jelly > 0
        and counts.egg_raft > 0
        and wild_ready

    -- Copper Stromatolite is not required for Agricultural Science, but it is
    -- deliberately included and counted so the Heating Tower trigger is also
    -- available in the same guaranteed room.
    return total, progression_ready
end

-- Every normal Empty Room generated in the Vulcanus region becomes a compact
-- progression district. It guarantees the official mine-entity research
-- triggers and every raw material needed to reach the Foundry, Big Mining Drill
-- and Metallurgic Science Pack without relying on a Demolisher kill.
local VULCANUS_ROOM_MIN_RADIUS = 32

local function vulcanus_existing_tile(preferred, fallback)
    if preferred and exists("tile", preferred) then return preferred end
    if fallback and exists("tile", fallback) then return fallback end
    return nil
end

function features.vulcanus_progression_room_radius()
    return VULCANUS_ROOM_MIN_RADIUS
end

local function prepare_vulcanus_progression_room(surface, cx, cy, half)
    local base = vulcanus_existing_tile("volcanic-soil-dark", "volcanic-ash-dark")
    local calcite_ground = vulcanus_existing_tile("volcanic-ash-light", base)
    local coal_ground = vulcanus_existing_tile("volcanic-ash-dark", base)
    local tungsten_ground = vulcanus_existing_tile("volcanic-cracks", base)
    local geyser_ground = vulcanus_existing_tile("volcanic-soil-light", base)
    local lava = vulcanus_existing_tile("lava", nil)
    local lava_hot = vulcanus_existing_tile("lava-hot", lava)

    local tiles = {}
    append_rect_tiles(tiles, base, cx - half, cy - half, cx + half, cy + half)
    append_rect_tiles(tiles, calcite_ground, cx - 14, cy - 13, cx - 5, cy - 7)
    append_rect_tiles(tiles, coal_ground, cx + 5, cy - 13, cx + 14, cy - 7)
    append_rect_tiles(tiles, tungsten_ground, cx - 14, cy + 1, cx - 5, cy + 7)
    append_rect_tiles(tiles, geyser_ground, cx + 6, cy + 1, cx + 14, cy + 7)

    local lava_count = 0
    if lava then
        for dx = -5, 5 do
            for dy = 9, 15 do
                local nx, ny = cx + dx, cy + dy
                local ex = dx / 5
                local ey = (dy - 12) / 3.5
                if ex * ex + ey * ey <= 1.05 then
                    local tile_name = lava
                    if lava_hot and ex * ex + ey * ey < 0.35 then tile_name = lava_hot end
                    tiles[#tiles + 1] = { name = tile_name, position = { nx, ny } }
                    lava_count = lava_count + 1
                end
            end
        end
    end

    pcall(function()
        surface.set_tiles(tiles, true, false, true)
        surface.destroy_decoratives {
            area = {
                { cx - half - 1, cy - half - 1 },
                { cx + half + 2, cy + half + 2 }
            }
        }
    end)

    -- Clear only natural overlap debris. Player structures, trains and characters
    -- are preserved in the rare case a new room overlaps already-used terrain.
    local blockers = surface.find_entities_filtered {
        area = {
            { cx - half + 1, cy - half + 1 },
            { cx + half, cy + half }
        }
    }
    for _, entity in pairs(blockers or {}) do
        if entity.valid then
            local force_name = entity.force and entity.force.name or "neutral"
            local natural_force = force_name == "neutral" or force_name == "enemy"
            local natural_type = entity.type == "resource"
                or entity.type == "tree"
                or entity.type == "simple-entity"
                or entity.type == "unit"
                or entity.type == "unit-spawner"
                or entity.name == "diggy-rock"
                or entity.name == "diggy-tree"
            if natural_force and natural_type then
                pcall(function() entity.destroy() end)
            end
        end
    end

    return lava_count
end

local function place_vulcanus_room_resource(surface, name, positions, amount)
    if not exists("entity", name) then return 0 end
    local count = 0
    for _, pos in ipairs(positions) do
        local ok, entity = pcall(function()
            return surface.create_entity {
                name = name,
                position = { pos[1] + 0.5, pos[2] + 0.5 },
                amount = amount,
                force = "neutral",
                raise_built = false,
            }
        end)
        if ok and entity and entity.valid then count = count + 1 end
    end
    return count
end

local function vulcanus_grid(cx, cy, x1, y1, x2, y2, step)
    local out = {}
    step = step or 1
    for x = x1, x2, step do
        for y = y1, y2, step do
            out[#out + 1] = { cx + x, cy + y }
        end
    end
    return out
end

local function vulcanus_ring(cx, cy, radius, count, phase)
    local out, seen = {}, {}
    phase = phase or 0
    for i = 0, count - 1 do
        local angle = ((i + phase) / count) * math.pi * 2
        local x = math.floor(cx + math.cos(angle) * radius + 0.5)
        local y = math.floor(cy + math.sin(angle) * radius + 0.5)
        local key = x .. ":" .. y
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = { x, y }
        end
    end
    return out
end

function features.populate_vulcanus_progression_room(surface, cx, cy, radius, seed, digging_force)
    if not (surface and surface.valid) then return 0, false end
    local half = math.max(17, math.floor((radius or VULCANUS_ROOM_MIN_RADIUS) * 0.78 + 0.5))
    local lava_count = prepare_vulcanus_progression_room(surface, cx, cy, half)
    -- This is a resource/research bootstrap room; opening it must not spawn
    -- a Demolisher among the progression materials.

    local counts = {
        calcite = place_vulcanus_room_resource(
            surface, "calcite", vulcanus_grid(cx, cy, -11, -10, -9, -8, 2), 125
        ),
        coal = place_vulcanus_room_resource(
            surface, "coal", vulcanus_grid(cx, cy, 9, -10, 11, -8, 2), 125
        ),
        tungsten = place_vulcanus_room_resource(
            surface, "tungsten-ore", vulcanus_grid(cx, cy, -11, 3, -9, 5, 2), 125
        ),
        geyser = 0,
        rocks = 0,
        big_rocks = 0,
        huge_rocks = 0,
        trees = 0,
        lava = lava_count,
    }

    if exists("entity", "sulfuric-acid-geyser") then
        local ok, geyser = pcall(function()
            return surface.create_entity {
                name = "sulfuric-acid-geyser",
                position = { cx + 10.5, cy + 4.5 },
                amount = 1000000,
                force = "neutral",
                raise_built = false,
            }
        end)
        if ok and geyser and geyser.valid then counts.geyser = 1 end
    end

    -- The progression room is deliberately generous: twenty official Big rocks
    -- guarantee the native Tungsten Carbide mining trigger, while twenty Huge
    -- rocks make the Foundry/first Big Mining Drill bootstrap overwhelmingly
    -- reliable without a force counter or scripted ore injection.
    local function place_rock_set(name, target, ring_specs, counter_name)
        if not exists("entity", name) then return end
        for _, spec in ipairs(ring_specs) do
            for _, pos in ipairs(vulcanus_ring(cx, cy, spec.radius, spec.count, spec.phase)) do
                if counts[counter_name] >= target then return end
                local entity = place_gleba_room_entity(
                    surface, name, pos[1], pos[2], "neutral", cx, cy, half, 1.5
                )
                if entity then
                    counts[counter_name] = counts[counter_name] + 1
                    counts.rocks = counts.rocks + 1
                end
            end
        end
    end

    place_rock_set("huge-volcanic-rock", 20, {
        { radius = 22, count = 40, phase = 0.25 },
        { radius = 20, count = 40, phase = 0.75 },
        { radius = 24, count = 48, phase = 0.50 },
    }, "huge_rocks")
    place_rock_set("big-volcanic-rock", 20, {
        { radius = 17, count = 36, phase = 0.50 },
        { radius = 15, count = 36, phase = 0.00 },
        { radius = 19, count = 40, phase = 0.25 },
    }, "big_rocks")

    -- Fill the cleared volcanic district with sixty cuttable lichen trees. The
    -- candidate deck is intentionally larger than the target because lava,
    -- resources, rocks and the live Demolisher may reject individual positions.
    -- Each accepted position independently keeps the previous 18% flaming-tree
    -- flavour roll and falls back to the other registered tree prototype.
    local tree_candidate_index = 0
    local function try_tree_at(tx, ty)
        if counts.trees >= 60 then return true end
        tree_candidate_index = tree_candidate_index + 1
        local flaming_first = hash.roll(
            seed, tx, ty, S_VULCANUS_ROOM + tree_candidate_index
        ) < 0.18
        local order = flaming_first
            and { "ashland-lichen-tree-flaming", "ashland-lichen-tree" }
            or { "ashland-lichen-tree", "ashland-lichen-tree-flaming" }
        for _, name in ipairs(order) do
            if exists("entity", name) then
                local entity = place_gleba_room_entity(
                    surface, name, tx, ty, "neutral", cx, cy, half, 1.5
                )
                if entity then
                    counts.trees = counts.trees + 1
                    return counts.trees >= 60
                end
            end
        end
        return false
    end

    local tree_rings = {
        { radius = 9, count = 24, phase = 0.50 },
        { radius = 12, count = 32, phase = 0.00 },
        { radius = 14, count = 36, phase = 0.50 },
        { radius = 18, count = 44, phase = 0.25 },
        { radius = 21, count = 52, phase = 0.75 },
        { radius = 23, count = 56, phase = 0.50 },
    }
    for _, spec in ipairs(tree_rings) do
        for _, pos in ipairs(vulcanus_ring(cx, cy, spec.radius, spec.count, spec.phase)) do
            if try_tree_at(pos[1], pos[2]) then break end
        end
        if counts.trees >= 60 then break end
    end

    -- Dense rooms or unusual prototype collision boxes can consume many ring
    -- candidates. A deterministic sparse-grid fallback still pursues the actual
    -- target count while preserving a clear cross through the room centre.
    if counts.trees < 60 then
        for dx = -half + 3, half - 3, 2 do
            for dy = -half + 3, half - 3, 2 do
                if math.abs(dx) > 3 and math.abs(dy) > 3 then
                    if try_tree_at(cx + dx, cy + dy) then break end
                end
            end
            if counts.trees >= 60 then break end
        end
    end

    local total = counts.calcite + counts.coal + counts.tungsten + counts.geyser
        + counts.rocks + counts.trees + counts.lava
    local progression_ready = counts.calcite > 0
        and counts.coal > 0
        and counts.tungsten > 0
        and counts.geyser > 0
        and counts.rocks > 0
        and counts.lava > 0

    return total, progression_ready
end

-- Every normal Empty Room generated in the Aquilo region becomes a compact
-- progression district. The shared Nauvis surface cannot reproduce Aquilo's
-- native freezing system per coordinate region, so this room deliberately
-- focuses only on the official mining trigger and fluid/raw-resource access.
local AQUILO_ROOM_MIN_RADIUS = 22

local function aquilo_existing_tile(preferred, fallback)
    if preferred and exists("tile", preferred) then return preferred end
    if fallback and exists("tile", fallback) then return fallback end
    return nil
end

function features.aquilo_progression_room_radius()
    return AQUILO_ROOM_MIN_RADIUS
end

local function prepare_aquilo_progression_room(surface, cx, cy, half)
    local base = aquilo_existing_tile("snow-flat", "ice-smooth")
    local brine_ground = aquilo_existing_tile("snow-crests", base)
    local fluorine_ground = aquilo_existing_tile("snow-lumpy", base)
    local oil_ground = aquilo_existing_tile("snow-patchy", base)
    local iceberg_ground = aquilo_existing_tile("ice-rough", base)
    local ocean = aquilo_existing_tile("ammoniacal-ocean", nil)
    local deep_ocean = aquilo_existing_tile("ammoniacal-ocean-2", ocean)

    local tiles = {}
    append_rect_tiles(tiles, base, cx - half, cy - half, cx + half, cy + half)
    append_rect_tiles(tiles, brine_ground, cx - 14, cy - 12, cx - 7, cy - 6)
    append_rect_tiles(tiles, fluorine_ground, cx - 3, cy - 12, cx + 3, cy - 6)
    append_rect_tiles(tiles, oil_ground, cx + 7, cy - 12, cx + 14, cy - 6)
    append_rect_tiles(tiles, iceberg_ground, cx - 6, cy - 3, cx + 6, cy + 5)

    -- A compact rectangular ammoniacal-ocean basin with a perfectly straight
    -- northern shoreline. This gives Offshore Pumps a clean placement edge
    -- without turning the whole room into an unlimited ocean field.
    local ocean_count = 0
    if ocean then
        for x = cx - 7, cx + 7 do
            for y = cy + 9, cy + 15 do
                local tile_name = ocean
                if deep_ocean and y >= cy + 12 and x >= cx - 4 and x <= cx + 4 then
                    tile_name = deep_ocean
                end
                tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
                ocean_count = ocean_count + 1
            end
        end
    end

    pcall(function()
        surface.set_tiles(tiles, true, false, true)
        surface.destroy_decoratives {
            area = {
                { cx - half - 1, cy - half - 1 },
                { cx + half + 2, cy + half + 2 }
            }
        }
    end)

    -- Clear natural cave/planet debris only. Player structures and vehicles are
    -- already protected by caverns.lua's full-footprint validation.
    local blockers = surface.find_entities_filtered {
        area = {
            { cx - half + 1, cy - half + 1 },
            { cx + half, cy + half }
        }
    }
    for _, entity in pairs(blockers or {}) do
        if entity.valid then
            local force_name = entity.force and entity.force.name or "neutral"
            local natural_force = force_name == "neutral" or force_name == "enemy"
            local natural_type = entity.type == "resource"
                or entity.type == "tree"
                or entity.type == "simple-entity"
                or entity.type == "unit"
                or entity.type == "unit-spawner"
                or entity.name == "diggy-rock"
                or entity.name == "diggy-tree"
            if natural_force and natural_type then
                pcall(function() entity.destroy() end)
            end
        end
    end

    return ocean_count
end

local function place_aquilo_room_resource(surface, name, x, y, amount)
    if not exists("entity", name) then return nil end
    local ok, entity = pcall(function()
        return surface.create_entity {
            name = name,
            position = { x + 0.5, y + 0.5 },
            amount = amount,
            force = "neutral",
            raise_built = false,
        }
    end)
    if ok and entity and entity.valid then return entity end
    return nil
end

function features.populate_aquilo_progression_room(surface, cx, cy, radius, seed, digging_force)
    if not (surface and surface.valid) then return 0, false end
    local half = math.max(17, math.floor((radius or AQUILO_ROOM_MIN_RADIUS) * 0.78 + 0.5))
    local ocean_count = prepare_aquilo_progression_room(surface, cx, cy, half)

    local counts = {
        brine = place_aquilo_room_resource(surface, "lithium-brine", cx - 10, cy - 9, 15000) and 1 or 0,
        fluorine = place_aquilo_room_resource(surface, "fluorine-vent", cx, cy - 9, 15000) and 1 or 0,
        oil = place_aquilo_room_resource(surface, "crude-oil", cx + 10, cy - 9, 25000) and 1 or 0,
        iceberg = 0,
        ocean = ocean_count,
    }

    -- Mining this exact official entity is the native trigger for Lithium
    -- Processing. One guaranteed formation is enough; natural Aquilo veins and
    -- formations elsewhere remain the long-term resource source.
    if exists("entity", "lithium-iceberg-big") then
        local iceberg = place_gleba_room_entity(
            surface, "lithium-iceberg-big", cx, cy + 1, "neutral", cx, cy, half, 6
        )
        if iceberg then counts.iceberg = 1 end
    end

    local total = counts.brine + counts.fluorine + counts.oil + counts.iceberg + counts.ocean
    local progression_ready = counts.brine > 0
        and counts.fluorine > 0
        and counts.oil > 0
        and counts.iceberg > 0
        and counts.ocean > 0

    return total, progression_ready
end

local function has_nearby_vulcanus_natural(surface, x, y, radius)
    -- LuaSurface.find_entities_filtered throws if even one name in a name-list
    -- is not a registered prototype. Filter at runtime so optional-mod/prototype
    -- differences can never turn normal cave digging into a non-recoverable error.
    local valid_names = {}
    for _, name in ipairs(VULCANUS_NATURAL_NAMES) do
        if exists("entity", name) then valid_names[#valid_names + 1] = name end
    end
    if #valid_names == 0 then return false end

    local ok, found = pcall(function()
        return surface.find_entities_filtered {
            name = valid_names,
            position = { x + 0.5, y + 0.5 },
            radius = radius or 7,
        }
    end)
    return ok and found and #found > 0
end

local function try_place_vulcanus_natural(surface, name, x, y, search_radius)
    if not exists("entity", name) then return false end
    local target = { x = x + 0.5, y = y + 0.5 }
    local function valid_region(pos)
        return pos and region_at(math.floor(pos.x or pos[1]), math.floor(pos.y or pos[2])) == "vulcanus"
    end
    local can_place = false
    pcall(function()
        can_place = surface.can_place_entity { name = name, position = target, force = "neutral" }
    end)
    local position = can_place and target or nil
    if not position then
        local ok, found = pcall(function()
            return surface.find_non_colliding_position(name, target, search_radius or 3, 0.5, true)
        end)
        if ok and valid_region(found) then position = found end
    end
    if not position then return false end
    return safe_create(surface, {
        name = name,
        position = position,
        force = "neutral",
        raise_built = false,
    }) ~= nil
end

local function try_vulcanus_environment(surface, seed, x, y)
    if has_nearby_vulcanus_natural(surface, x, y, 6) then return false end

    if hash.roll(seed, x, y, S_VULCANUS_ENV) < 0.006 then
        local chosen = pick_weighted(seed, x, y, S_VULCANUS_ENV_KIND, VULCANUS_VOLCANIC_ROCKS)
        if chosen and try_place_vulcanus_natural(surface, chosen.name, x, y, 5) then return true end
    end

    if hash.roll(seed, x, y, S_VULCANUS_ENV + 1) < 0.028 then
        local chosen = pick_weighted(seed, x, y, S_VULCANUS_ENV_KIND + 1, VULCANUS_TREES)
        if chosen and try_place_vulcanus_natural(surface, chosen.name, x, y, 3) then return true end
    end

    return false
end

local function try_place_on_gleba_tile(surface, spec, x, y)
    -- Gleba simple test pass:
    -- Do NOT paint a large 7x7 soil patch around every plant/nest.
    -- Only correct the actual opened tile, so the cave/tunnel room shape stays visible
    -- like Fulgora and Vulcanus.
    if spec.tile and exists("tile", spec.tile) then
        pcall(function()
            surface.set_tiles({ { name = spec.tile, position = { x, y } } }, true, false, true)
        end)
    end

    local pos = { x + 0.5, y + 0.5 }
    local force = spec.force or "neutral"
    local area = { { x - 1.5, y - 1.5 }, { x + 2.5, y + 2.5 } }

    -- Keep the cleanup tiny; the old version cleared a big patch and made Gleba feel unlike the other regions.
    local blockers = surface.find_entities_filtered { area = area }
    for _, e in pairs(blockers) do
        if e.valid and e.type ~= "character" and e.type ~= "resource" and e.type ~= "unit-spawner" and e.type ~= "turret" then
            if spec.force ~= "enemy" then pcall(function() e.destroy() end) end
        end
    end

    local ok, placed = pcall(function()
        if surface.can_place_entity { name = spec.name, position = pos, force = force } then
            return surface.create_entity { name = spec.name, position = pos, force = force }
        end
        return surface.create_entity { name = spec.name, position = pos, force = force, raise_built = false }
    end)
    if ok and placed then return true end
    return false
end

local function try_gleba_plant(surface, seed, x, y)
    if hash.roll(seed, x, y, S_PLANT) > 0.78 then return false end
    local chosen = pick_weighted(seed, x, y, S_PLANT_KIND, GLEBA_PLANTS)
    if chosen and exists("entity", chosen.name) then
        if try_place_on_gleba_tile(surface, chosen, x, y) then return true end
    end

    -- Fallback scan: if the weighted pick failed due to tile/collision rules,
    -- try another valid Gleba plant instead of leaving the biome empty.
    local start = hash.range(seed, x, y, S_PLANT_KIND + 23, 1, #GLEBA_PLANTS)
    for i = 0, #GLEBA_PLANTS - 1 do
        local spec = GLEBA_PLANTS[((start + i - 1) % #GLEBA_PLANTS) + 1]
        if exists("entity", spec.name) and try_place_on_gleba_tile(surface, spec, x, y) then
            return true
        end
    end
    return false
end

local function try_gleba_nest(surface, seed, x, y, distance)
    local chance = 0.018 + math.min(distance / 3500, 0.022)
    if hash.roll(seed, x, y, S_NEST) > chance then return false end
    local chosen = pick_weighted(seed, x, y, S_NEST_KIND, GLEBA_NESTS)
    if chosen and exists("entity", chosen.name) then
        local spec = { name = chosen.name, tile = chosen.tile, force = "enemy" }
        if try_place_on_gleba_tile(surface, spec, x, y) then return true end
    end
    for _, spec in pairs(GLEBA_NESTS) do
        if exists("entity", spec.name) then
            local nest_spec = { name = spec.name, tile = spec.tile, force = "enemy" }
            if try_place_on_gleba_tile(surface, nest_spec, x, y) then return true end
        end
    end
    return false
end

function features.on_gleba_nest_removed(entity, buffer)
    if not (entity and entity.valid and entity.name and entity.name:find("gleba", 1, true)) then return end
    if not exists("item", "pentapod-egg") then return end
    local seed = entity.surface.map_gen_settings.seed
    local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
    local amount = hash.range(seed, x, y, S_EGG, 1, 4)
    local stack = { name = "pentapod-egg", count = amount }
    if buffer and buffer.valid then
        pcall(function() buffer.insert(stack) end)
    else
        pcall(function() entity.surface.spill_item_stack { position = entity.position, stack = stack, enable_looted = true, force = "player" } end)
    end
end

local function gleba_nearby_cap()
    return GLEBA_NEARBY_CAPS[depth_levels.global_difficulty()] or GLEBA_NEARBY_CAPS.medium
end

local function count_nearby_pentapods(surface, position, radius, limit)
    return surface.count_entities_filtered {
        type = "unit",
        name = GLEBA_ENEMY_NAMES,
        force = "enemy",
        position = position,
        radius = radius or 80,
        limit = limit,
    }
end

local function count_zone_pentapods(surface, profile)
    if not profile then return 0, 0 end
    local area = advancing_zones.zone_area(profile.zone_index)
    local total = surface.count_entities_filtered {
        type = "unit",
        name = GLEBA_ENEMY_NAMES,
        force = "enemy",
        area = area,
        limit = profile.total + 1,
    }
    local big_names = {
        "big-wriggler-pentapod",
        "big-strafer-pentapod",
        "big-stomper-pentapod",
        "big-wriggler-pentapod-premature",
    }
    local big = surface.count_entities_filtered {
        type = "unit",
        name = big_names,
        force = "enemy",
        area = area,
        limit = profile.big + 1,
    }
    return total, big
end

local function spec_allowed_by_advancing_profile(spec, profile, current_big)
    if not profile then return true end
    local tier = spec and pentapod_tier(spec.name)
    if not tier or tier > profile.maximum_tier then return false end
    if tier == 3 and current_big >= profile.big then return false end
    return true
end

local function create_enemy_near(surface, name, target, search_radius)
    if not exists("entity", name) then return false end
    local spot = surface.find_non_colliding_position(name, target, search_radius or 6, 0.5, true)
        or surface.find_non_colliding_position(name, target, search_radius or 6, 1, true)
    if not spot then return false end
    local ok, entity = pcall(function()
        return surface.create_entity { name = name, position = spot, force = "enemy" }
    end)
    return ok and entity and entity.valid or false
end

local function spawn_gleba_pack(surface, seed, cx, cy, radius, level_id, requested, stream, fixed_spec)
    local pool = GLEBA_ENEMIES_BY_LEVEL[level_id] or GLEBA_ENEMIES_BY_LEVEL.easy
    local cap = gleba_nearby_cap()
    local centre = { x = cx + 0.5, y = cy + 0.5 }
    local nearby = count_nearby_pentapods(surface, centre, 80, cap)
    local allowance = math.max(0, cap - nearby)
    local profile = advancing_gleba_profile(surface, cx, cy)
    local zone_total, zone_big = count_zone_pentapods(surface, profile)
    if profile then allowance = math.min(allowance, math.max(0, profile.total - zone_total)) end
    local target_count = math.min(math.max(0, requested or 0), allowance)
    local spawned = 0
    local attempt = 0

    while spawned < target_count and attempt < target_count * 5 + 8 do
        attempt = attempt + 1
        local spec = fixed_spec or pick_weighted(seed, cx + attempt, cy - attempt, stream + attempt * 13, pool)
        if spec
            and exists("entity", spec.name)
            and spec_allowed_by_advancing_profile(spec, profile, zone_big) then
            local angle_roll = hash.roll(seed, cx, cy, stream + attempt * 13 + 1)
            local radius_roll = hash.roll(seed, cx, cy, stream + attempt * 13 + 2)
            local angle = angle_roll * math.pi * 2
            local distance = math.max(2, radius_roll * math.max(3, (radius or 8) - 3))
            local target = {
                x = cx + 0.5 + math.cos(angle) * distance,
                y = cy + 0.5 + math.sin(angle) * distance,
            }
            if create_enemy_near(surface, spec.name, target, 7) then
                spawned = spawned + 1
                zone_total = zone_total + 1
                if pentapod_tier(spec.name) == 3 then zone_big = zone_big + 1 end
            end
        end
    end
    return spawned
end

function features.spawn_gleba_room_pack(surface, cx, cy, radius, seed, stream)
    if not (surface and surface.valid) then return 0 end
    local distance = math.sqrt(cx * cx + cy * cy)
    local profile = advancing_gleba_profile(surface, cx, cy)
    local level_id = profile and profile.level or planet_level_for_distance(distance)
    local base = ({ easy = 3, medium = 4, hard = 5, nightmare = 6 })[level_id] or 3
    local scaled = math.max(1, math.floor(base * depth_levels.global_difficulty_multiplier() + 0.5))
    return spawn_gleba_pack(surface, seed, cx, cy, radius, level_id, math.min(scaled, 8), stream or S_GLEBA_ENEMY_ROOM)
end

function features.spawn_gleba_room_raft(surface, cx, cy, radius, seed, stream)
    if not (surface and surface.valid) then return false end
    stream = stream or S_GLEBA_RAFT_ROOM
    local preferred = pick_weighted(seed, cx, cy, stream, GLEBA_NESTS)
    local specs = { preferred }
    for _, spec in ipairs(GLEBA_NESTS) do
        if not preferred or spec.name ~= preferred.name then specs[#specs + 1] = spec end
    end

    -- Try several deterministic positions. The footprint is kept fully inside
    -- the carved room, so painting the required marsh never opens cave outside
    -- the room boundary.
    local offsets = {
        { 0, 0 },
        { -0.38, -0.30 }, { 0.38, -0.30 },
        { -0.38, 0.32 }, { 0.38, 0.32 },
    }
    for spec_index, chosen in ipairs(specs) do
        if chosen and exists("entity", chosen.name) and exists("tile", chosen.tile) then
            local patch_radius = chosen.radius or 3
            local max_offset = math.max(0, math.floor((radius or 10) - patch_radius - 2))
            local start = hash.range(seed, cx, cy, stream + spec_index * 17, 1, #offsets)
            for i = 0, #offsets - 1 do
                local offset = offsets[((start + i - 1) % #offsets) + 1]
                local tx = math.floor(cx + offset[1] * max_offset)
                local ty = math.floor(cy + offset[2] * max_offset)
                local tiles = {}
                for dx = -patch_radius, patch_radius do
                    for dy = -patch_radius, patch_radius do
                        if dx * dx + dy * dy <= patch_radius * patch_radius + 1 then
                            tiles[#tiles + 1] = { name = chosen.tile, position = { tx + dx, ty + dy } }
                        end
                    end
                end
                pcall(function() surface.set_tiles(tiles, true, false, true) end)
                local pos = { x = tx + 0.5, y = ty + 0.5 }
                local ok, entity = pcall(function()
                    if surface.can_place_entity { name = chosen.name, position = pos, force = "enemy" } then
                        return surface.create_entity {
                            name = chosen.name,
                            position = pos,
                            force = "enemy",
                            raise_built = false,
                        }
                    end
                    return nil
                end)
                if ok and entity and entity.valid then return true end
            end
        end
    end
    return false
end

local function try_gleba_enemy(surface, seed, x, y)
    local distance = math.sqrt(x * x + y * y)
    local profile = advancing_gleba_profile(surface, x, y)
    local level_id = profile and profile.level or planet_level_for_distance(distance)
    local chance = 0.022 * depth_levels.global_difficulty_multiplier()
    if hash.roll(seed, x, y, S_ENEMY) > math.min(1, chance) then return false end

    local cap = gleba_nearby_cap()
    local centre = { x = x + 0.5, y = y + 0.5 }
    if count_nearby_pentapods(surface, centre, 80, cap) >= cap then return false end

    local pool = GLEBA_ENEMIES_BY_LEVEL[level_id] or GLEBA_ENEMIES_BY_LEVEL.easy
    local spec = pick_weighted(seed, x, y, S_ENEMY_KIND, pool)
    if not spec then return false end
    local requested = hash.range(seed, x, y, S_ENEMY_KIND + 1, spec.pack_min or 1, spec.pack_max or 1)
    return spawn_gleba_pack(surface, seed, x, y, 7, level_id, requested, S_ENEMY_KIND + 20, spec) > 0
end

local function try_enemy(surface, seed, x, y, region)
    if region == "gleba" then return try_gleba_enemy(surface, seed, x, y) end
    -- Demolishers cannot reliably fit inside the normal three-tile cave tunnels.
    -- Progression rooms also leave them out so their bootstrap materials are usable.
    return false
end

function features.on_dig(dig)
    if not (dig and dig.surface and dig.surface.valid and dig.position) then return end
    local x, y = math.floor(dig.position.x), math.floor(dig.position.y)
    local region = region_at(x, y)
    if region == "nauvis" then return end

    local tile = dig.surface.get_tile(x, y)
    if not (tile and tile.valid) then return end
    local tile_name = tile.name or ""
    if tile_name == "out-of-map" or tile_name:find("water", 1, true)
        or tile_name:find("ocean", 1, true) or tile_name:find("lava", 1, true) then
        return
    end

    local seed = dig.surface.map_gen_settings.seed
    local distance = math.sqrt((x + 0.5) * (x + 0.5) + (y + 0.5) * (y + 0.5))
    try_resource(dig.surface, seed, x, y, region, distance)
end

-- Scripted Collapse clearance reveals floor resources only: no rooms, nests,
-- enemies, lakes, ruins, plants or collision-bearing natural vein entities.
function features.on_resource_only_tile(surface, x, y)
    if not (surface and surface.valid and tile_accepts_resource(surface, x, y)) then return end
    local region = region_at(x, y)
    if region == "nauvis" then return end
    local distance = math.sqrt((x + 0.5) ^ 2 + (y + 0.5) ^ 2)
    try_resource(surface, surface.map_gen_settings.seed, x, y, region, distance, true)
end

function features.on_open_tile(surface, x, y, force)
    if not (surface and surface.valid) then return end
    local region = region_at(x, y)
    if region == "nauvis" then return end

    local tile = surface.get_tile(x, y)
    if not tile.valid or tile.name == "out-of-map" or tile.name:find("water", 1, true) then return end

    local seed = surface.map_gen_settings.seed
    local distance = math.sqrt(x * x + y * y)

    -- Fulgora heavy oil: rare oil-ocean pockets for offshore pumps.
    -- If an oil lake is placed, skip resource/plant placement on that tile.
    if region == "fulgora" and try_fulgora_oil_lake(surface, seed, x, y) then return end

    -- Resources first; if a resource takes the tile, don't also place a plant.
    local placed_resource = try_resource(surface, seed, x, y, region, distance)
    if not placed_resource and region == "fulgora" then
        try_fulgora_environment(surface, seed, x, y, force)
    elseif not placed_resource and region == "gleba" then
        -- Nests first: they are rare and important for pentapod eggs.
        local placed_nest = try_gleba_nest(surface, seed, x, y, distance)
        if not placed_nest then
            try_gleba_plant(surface, seed, x, y)
        end
    elseif not placed_resource and region == "vulcanus" then
        try_vulcanus_environment(surface, seed, x, y)
    end
    try_enemy(surface, seed, x, y, region)
end

local function destroy_pentapod_without_rewards(entity)
    if not (entity and entity.valid) then return end
    pcall(function() entity.destroy() end)
end

function features.on_entity_spawned(event)
    local entity = event and event.entity
    if not (entity and entity.valid and entity.type == "unit" and pentapod_tier(entity.name)) then
        return
    end
    local profile = advancing_gleba_profile(
        entity.surface,
        entity.position.x,
        entity.position.y
    )
    if not profile then return end

    local tier = pentapod_tier(entity.name)
    local total, big = count_zone_pentapods(entity.surface, profile)
    if tier > profile.maximum_tier
        or total > profile.total
        or (tier == 3 and big > profile.big) then
        destroy_pentapod_without_rewards(entity)
    end
end

local function rebalance_surface_pentapods(surface)
    if not (surface and surface.valid and advancing_zones.is_main_surface(surface)) then return end
    local units = surface.find_entities_filtered {
        type = "unit",
        name = GLEBA_ENEMY_NAMES,
        force = "enemy",
    }
    local groups = {}
    for _, entity in pairs(units or {}) do
        if entity and entity.valid then
            local profile = advancing_gleba_profile(surface, entity.position.x, entity.position.y)
            if profile then
                groups[profile.zone_index] = groups[profile.zone_index] or {
                    profile = profile,
                    units = {},
                }
                local list = groups[profile.zone_index].units
                list[#list + 1] = entity
            end
        end
    end

    for _, group in pairs(groups) do
        table.sort(group.units, function(a, b)
            local tier_a = pentapod_tier(a.name) or 99
            local tier_b = pentapod_tier(b.name) or 99
            if tier_a ~= tier_b then return tier_a < tier_b end
            return (a.unit_number or 0) < (b.unit_number or 0)
        end)
        local kept = 0
        local kept_big = 0
        for _, entity in ipairs(group.units) do
            local tier = pentapod_tier(entity.name) or 99
            local allowed = tier <= group.profile.maximum_tier
                and kept < group.profile.total
                and (tier ~= 3 or kept_big < group.profile.big)
            if allowed then
                kept = kept + 1
                if tier == 3 then kept_big = kept_big + 1 end
            else
                destroy_pentapod_without_rewards(entity)
            end
        end
    end
end

local function rebalance_surface_demolishers(surface)
    if not (surface and surface.valid and advancing_zones.is_main_surface(surface)) then return end
    local demolishers = surface.find_entities_filtered {
        name = { "small-demolisher", "medium-demolisher", "big-demolisher" },
        force = "enemy",
    }
    for _, entity in pairs(demolishers or {}) do
        if entity and entity.valid then
            local profile = advancing_vulcanus_demolisher_profile(
                surface, entity.position.x, entity.position.y
            )
            if profile then
                local allowed = {}
                for _, name in ipairs(profile.names) do allowed[name] = true end
                if #profile.names == 0 then
                    entity.destroy()
                elseif not allowed[entity.name] then
                    local position = { x = entity.position.x, y = entity.position.y }
                    local force = entity.force
                    local replacement_name = profile.names[1]
                    entity.destroy()
                    pcall(function()
                        surface.create_entity {
                            name = replacement_name,
                            position = position,
                            force = force,
                        }
                    end)
                end
            end
        end
    end
end

function features.on_configuration_changed()
    if not game then return end
    repair_existing_fulgora_recycling()
    if not advancing_zones.space_age_available() then return end
    for _, surface in pairs(game.surfaces) do
        rebalance_surface_pentapods(surface)
        rebalance_surface_demolishers(surface)
    end
end

return features
