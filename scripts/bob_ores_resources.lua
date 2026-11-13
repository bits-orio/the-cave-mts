-- Optional Bob's Ores 2.1 compatibility. Bob owns the prototypes and mining
-- products; The Cave only reveals enabled resources in its scripted world.
local settings = require("scripts.game_settings").proxy(settings)
local layout = require("scripts.bob_ore_layout")
local ore_veins = require("scripts.ore_veins")
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local zones = require("scripts.advancing_zones")
local cave_worlds = require("scripts.cave_worlds")

local bob = {}
local world_api
local cached_ores, cached_fluids
local STORAGE_KEY = "the_cave_bob_ores_resources"
local SPACING = 15
local COVER = { ["diggy-rock"] = true, ["diggy-rubble"] = true, ["diggy-tree"] = true }
local FLUIDS = { "bob-ground-water", "bob-lithia-water" }
local WELLS = { "crude-oil", "bob-ground-water", "bob-lithia-water" }
-- Integer offsets of length 15. Try opposite positions first; other positions
-- and then a 30-tile ring are bounded fallbacks for water/buildings/borders.
local OFFSETS = {
    { 15, 0 }, { 12, 9 }, { 9, 12 }, { 0, 15 }, { -9, 12 }, { -12, 9 },
    { -15, 0 }, { -12, -9 }, { -9, -12 }, { 0, -15 }, { 9, -12 }, { 12, -9 },
}
local AMOUNTS = {
    easy = { 250, 625 }, medium = { 625, 875 },
    hard = { 875, 1250 }, nightmare = { 1250, 2000 },
}

local function active()
    return script and script.active_mods and script.active_mods.bobores ~= nil
end

local function resource_enabled(name)
    local prototype = prototypes.entity[name]
    -- Bob also enables ores from companion mods at data stage. The final
    -- autoplace specification detects those, unlike the startup checkbox alone.
    return prototype and prototype.type == "resource" and prototype.autoplace_specification ~= nil
end

local function catalog()
    if cached_ores then return cached_ores, cached_fluids end
    cached_ores, cached_fluids = {}, {}
    if not active() then return cached_ores, cached_fluids end
    cached_ores = layout.catalog()
    for _, name in ipairs(FLUIDS) do
        if resource_enabled(name) then cached_fluids[#cached_fluids + 1] = name end
    end
    return cached_ores, cached_fluids
end

local function supported(surface)
    if not (active() and surface and surface.valid and type(surface.name) == "string") then return false end
    return cave_worlds.is_cave_world(surface)
end

local function nauvis_region(x, y)
    if zones.is_active() then return zones.region_at(x, y) == "nauvis" end
    local everything = settings.startup["the-cave-everything-on-nauvis"]
    if script.active_mods["space-age"] and (not everything or everything.value == "enabled" or everything.value == true) then
        return x * x + y * y < 1000 * 1000
    end
    return true
end

local function dry(tile, allow_void)
    if not (tile and tile.valid) then return false end
    local name = tile.name
    return (allow_void or name ~= "out-of-map") and not name:find("water", 1, true)
        and not name:find("ocean", 1, true) and not name:find("lava", 1, true)
end

local function materialize_ores(surface, x, y)
    local ores = catalog()
    if #ores == 0 or not nauvis_region(x, y) or not dry(surface.get_tile(x, y), false) then return end
    local ore = layout.ore_at(surface, x, y)
    if not ore or ore_veins.is_oil_reserved(surface, x, y) then return end
    local seed = surface.map_gen_settings.seed or 0
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { x - 4.95, y - 4.95 }, { x + 5.95, y + 5.95 } }, type = "resource",
    }) do
        -- Respect existing resources and wells even when Filter Mining Drills
        -- gives each resource a custom category. Same-ore neighbours are fine.
        if entity.name ~= ore.name then return end
        if math.floor(entity.position.x) == x and math.floor(entity.position.y) == y then return end
    end
    local level = depth_levels.level_for_distance(math.sqrt((x + 0.5)^2 + (y + 0.5)^2))
    local range = AMOUNTS[level.id] or AMOUNTS.easy
    surface.create_entity {
        name = ore.name, position = { x + 0.5, y + 0.5 },
        amount = hash.range(seed, x, y, 46100 + ore.index, range[1], range[2]),
    }
end

local function records(surface)
    storage[STORAGE_KEY] = storage[STORAGE_KEY] or { surfaces = {} }
    local all = storage[STORAGE_KEY].surfaces
    all[surface.index] = all[surface.index] or {}
    return all[surface.index]
end

local function oil_key(oil)
    return tostring(oil.position.x) .. ":" .. tostring(oil.position.y)
end

local function footprint_clear(surface, x, y)
    for tx = x - 1, x + 1 do
        for ty = y - 1, y + 1 do
            if not zones.is_playable(surface, tx, ty) or not dry(surface.get_tile(tx, ty), true) then return false end
        end
    end
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { x - 0.95, y - 0.95 }, { x + 1.95, y + 1.95 } },
    }) do
        if entity.valid and not COVER[entity.name] and entity.type ~= "corpse"
            and entity.type ~= "item-entity" and entity.type ~= "particle"
            and entity.type ~= "smoke-with-trigger" then return false end
    end
    for _, well in pairs(surface.find_entities_filtered {
        name = WELLS, position = { x + 0.5, y + 0.5 }, radius = SPACING,
    }) do
        local dx, dy = well.position.x - x - 0.5, well.position.y - y - 0.5
        if dx * dx + dy * dy < SPACING * SPACING - 0.001 then return false end
    end
    return true
end

local function find_target(surface, oil, first)
    local ox, oy = math.floor(oil.position.x), math.floor(oil.position.y)
    for scale = 1, 2 do
        for offset = 0, #OFFSETS - 1 do
            local direction = OFFSETS[(first + offset - 1) % #OFFSETS + 1]
            local x, y = ox + direction[1] * scale, oy + direction[2] * scale
            if zones.is_playable(surface, x, y) then
                -- Convert only this small footprint/its frontier before checking
                -- it. Never scan, regenerate or repopulate an entire surface.
                local halo = { { x - 3, y - 3 }, { x + 3, y + 3 }, { x - 3, y + 3 }, { x + 3, y - 3 } }
                if world_api.ensure_generated_area(surface, halo) and footprint_clear(surface, x, y) then return x, y end
            end
        end
    end
end

local function fluid_amount(oil, name)
    local prototype = prototypes.entity[name]
    local oil_normal = tonumber(oil.prototype.normal_resource_amount) or 300000
    local normal = tonumber(prototype.normal_resource_amount) or 1
    local amount = (tonumber(oil.amount) or oil_normal) / math.max(1, oil_normal) * normal
    return math.min(4294967295, math.max(1, tonumber(prototype.minimum_resource_amount) or 1, math.floor(amount + 0.5)))
end

local function ensure_companions(surface, oil, force)
    if not (world_api and oil and oil.valid) then return end
    local _, fluids = catalog()
    if #fluids == 0 then return end
    local all = records(surface)
    local key = oil_key(oil)
    local record = all[key]
    if not record then record = {}; all[key] = record end
    local seed = surface.map_gen_settings.seed or 0
    local first = hash.range(seed, math.floor(oil.position.x), math.floor(oil.position.y), 46000, 1, #OFFSETS)
    for index, name in ipairs(FLUIDS) do
        if resource_enabled(name) and not record[name] then
            local x, y = find_target(surface, oil, ((first - 1 + (index - 1) * 6) % #OFFSETS) + 1)
            if x then
                local cells = {}
                -- footprint_clear rejected all resources, enemies, buildings
                -- and water. Safe carve therefore removes only Cave cover.
                for tx = x - 1, x + 1 do
                    for ty = y - 1, y + 1 do
                        local covered = surface.find_entities_filtered {
                            name = { "diggy-rock", "diggy-rubble", "diggy-tree" },
                            area = { { tx + 0.05, ty + 0.05 }, { tx + 0.95, ty + 0.95 } }, limit = 1,
                        }
                        -- Preserve existing paving and natural open ground.
                        if surface.get_tile(tx, ty).name == "out-of-map" or #covered > 0 then
                            world_api.carve_safe_tile(surface, tx, ty)
                        end
                        cells[#cells + 1] = { tx, ty }
                    end
                end
                world_api.advance_frontier(surface, cells)
                local amount = fluid_amount(oil, name)
                local well = surface.create_entity { name = name, position = { x + 0.5, y + 0.5 }, amount = amount }
                if well and well.valid then
                    -- Plain persistent data: survives reload and removal of the
                    -- optional mod, without stale LuaEntity references/refills.
                    record[name] = { x = x, y = y, amount = amount }
                    if force and force.valid then force.chart(surface, { { x - 2, y - 2 }, { x + 3, y + 3 } }) end
                end
            end
        end
    end
end

local function nearby_oil(surface, position, force)
    local _, fluids = catalog()
    if #fluids == 0 then return end
    for _, oil in pairs(surface.find_entities_filtered { name = "crude-oil", position = position, radius = 6 }) do
        ensure_companions(surface, oil, force)
    end
end

function bob.configure_world(api)
    world_api = api
end

function bob.is_active()
    return active()
end

function bob.thorium_enabled()
    return active() and resource_enabled("bob-thorium-ore") or false
end

function bob.on_configuration_changed()
    cached_ores, cached_fluids = nil, nil
    layout.clear_cache()
    -- Existing wells are adopted locally when next visited by digging. No map
    -- scan, terrain regeneration, or edits to previously opened ore patches.
end

function bob.on_open_tile(surface, x, y, force)
    if not supported(surface) or not zones.is_playable(surface, x, y) then return end
    nearby_oil(surface, { x = x + 0.5, y = y + 0.5 }, force)
    materialize_ores(surface, x, y)
end

function bob.on_dig(dig)
    if not (dig and dig.position) then return end
    bob.on_open_tile(dig.surface, math.floor(dig.position.x), math.floor(dig.position.y), dig.force)
end

function bob.on_post_dig(dig, plan)
    if not (dig and supported(dig.surface) and plan and plan.x1 and plan.y1 and plan.x2 and plan.y2) then return end
    local _, fluids = catalog()
    if #fluids == 0 then return end
    -- Fixed room wells can be placed after the last tile-opening callback.
    for _, oil in pairs(dig.surface.find_entities_filtered {
        name = "crude-oil", area = { { plan.x1 - 2, plan.y1 - 2 }, { plan.x2 + 3, plan.y2 + 3 } },
    }) do
        ensure_companions(dig.surface, oil, dig.force)
    end
end

function bob.on_surface_deleted(event)
    local root = storage[STORAGE_KEY]
    if root and event and event.surface_index then root.surfaces[event.surface_index] = nil end
end

return bob
