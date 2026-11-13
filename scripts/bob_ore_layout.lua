-- Shared, deterministic reservations for optional Bob ore deposits. Core and
-- Mobile Factory generation consult the same layout before revealing tiles,
-- so separation does not depend on which side of a vein is dug first.
local settings = require("scripts.game_settings").proxy(settings)
local hash = require("scripts.lib.hash")
local Simplex = require("scripts.lib.simplex")
local zones = require("scripts.advancing_zones")
local cave_worlds = require("scripts.cave_worlds")

local layout = {}
local CELL = 64
local CLEARANCE = 5
local EDGE = 3
local CACHE_LIMIT = 256
local cache, cache_keys, cache_next = {}, {}, 1
local cached_ores, enabled_names
local SIZES = { small = 1, medium = 2, large = 4, huge = 8 }
-- Fixed slots keep other deposits in place when one resource is disabled.
-- Thorium keeps its original richness index but has no upper-surface slot.
local ORES = {
    { name = "bob-tin-ore", index = 1 }, { name = "bob-lead-ore", index = 2 },
    { name = "bob-quartz", index = 3 }, { name = "bob-silver-ore", index = 4 },
    { name = "bob-zinc-ore", index = 5 }, { name = "bob-gold-ore", index = 6 },
    { name = "bob-bauxite-ore", index = 7 }, { name = "bob-rutile-ore", index = 8 },
    { name = "tungsten-ore", index = 9 }, { name = "bob-nickel-ore", index = 11 },
    { name = "bob-cobalt-ore", index = 12 }, { name = "bob-gem-ore", index = 13 },
}

local function active()
    return script and script.active_mods and script.active_mods.bobores ~= nil
end

function layout.catalog()
    if cached_ores then return cached_ores end
    cached_ores, enabled_names = {}, {}
    if active() then
        for _, ore in ipairs(ORES) do
            local prototype = prototypes.entity[ore.name]
            if prototype and prototype.type == "resource" and prototype.autoplace_specification ~= nil
                and not (ore.name == "tungsten-ore" and script.active_mods["space-age"]) then
                cached_ores[#cached_ores + 1] = ore
                enabled_names[ore.name] = true
            end
        end
    end
    return cached_ores
end

local function supported(surface, x, y)
    if not (active() and surface and surface.valid and type(surface.name) == "string") then return false end
    if not cave_worlds.is_cave_world(surface) then
        return false
    end
    if zones.is_active() then return zones.region_at(x, y) == "nauvis" end
    local everything = settings.startup["the-cave-everything-on-nauvis"]
    if script.active_mods["space-age"] and (not everything or everything.value == "enabled" or everything.value == true) then
        return x * x + y * y < 1000 * 1000
    end
    return true
end

local function deposit(seed, gx, gy)
    local key = seed .. ":" .. gx .. ":" .. gy
    local found = cache[key]
    if found then return found end
    -- One of every ore in each 4 x 3 group, shuffled as whole deposits rather
    -- than per tile. Neither rare-ore starvation nor mixed-tile noise occurs.
    local bx, by = math.floor(gx / 4), math.floor(gy / 3)
    local order = {}
    for i = 1, #ORES do order[i] = i end
    for i = #order, 2, -1 do
        local j = hash.range(seed, bx, by, 46200 + i, 1, i)
        order[i], order[j] = order[j], order[i]
    end
    local ore = ORES[order[(gy % 3) * 4 + gx % 4 + 1]]
    local setting = settings.startup["the-cave-resource-patch-size"]
    local value = setting and setting.value or "level-2"
    local size = SIZES[value] or tonumber(value:match("^level%-(%d+)$")) or 2
    size = math.max(1, math.min(8, size))
    local width, height = 24 + 3 * size, 16 + 2 * size
    if hash.range(seed, gx, gy, 46220, 0, 1) == 1 then width, height = height, width end
    local left = gx * CELL + hash.range(seed, gx, gy, 46221, EDGE + CLEARANCE, CELL - EDGE - CLEARANCE - width)
    local top = gy * CELL + hash.range(seed, gx, gy, 46222, EDGE + CLEARANCE, CELL - EDGE - CLEARANCE - height)
    found = { ore = ore, left = left, top = top, width = width, height = height }
    local old_key = cache_keys[cache_next]
    if old_key then cache[old_key] = nil end
    cache[key], cache_keys[cache_next] = found, key
    cache_next = cache_next % CACHE_LIMIT + 1
    return found
end

local function at(surface, x, y)
    if not supported(surface, x, y) or #layout.catalog() == 0 then return nil end
    local seed = surface.map_gen_settings.seed or 0
    local field = deposit(seed, math.floor(x / CELL), math.floor(y / CELL))
    if not enabled_names[field.ore.name] then return nil end
    -- Leave the whole arrival area intact, including a margin around it.
    local carve = settings.startup["diggy-carve-out-radius"]
    local radius = (carve and carve.value or 16) + 4
    local near_x = math.max(field.left - CLEARANCE, math.min(0, field.left + field.width + CLEARANCE))
    local near_y = math.max(field.top - CLEARANCE, math.min(0, field.top + field.height + CLEARANCE))
    if near_x * near_x + near_y * near_y <= radius * radius then return nil end
    return field, seed
end

function layout.is_reserved(surface, x, y)
    local field = at(surface, x, y)
    return field ~= nil and x >= field.left - CLEARANCE and x < field.left + field.width + CLEARANCE
        and y >= field.top - CLEARANCE and y < field.top + field.height + CLEARANCE
end

function layout.ore_at(surface, x, y)
    local field, seed = at(surface, x, y)
    if not field or x < field.left or x >= field.left + field.width
        or y < field.top or y >= field.top + field.height then return nil end
    -- Keep the same clearance at Nauvis/planetary boundaries, where the
    -- neighbouring resource generator does not use Bob's reservations.
    if not supported(surface, x - CLEARANCE, y - CLEARANCE)
        or not supported(surface, x + CLEARANCE, y - CLEARANCE)
        or not supported(surface, x - CLEARANCE, y + CLEARANCE)
        or not supported(surface, x + CLEARANCE, y + CLEARANCE) then return nil end
    local nx = (x + 0.5 - field.left - field.width / 2) / (field.width / 2)
    local ny = (y + 0.5 - field.top - field.height / 2) / (field.height / 2)
    -- A broad, connected core with lightly irregular edges, suitable for rows
    -- of drills. Patch Size expands the deposit without crossing its margins.
    local edge = 0.9 + 0.1 * Simplex.d2((x + 0.5) / 12, (y + 0.5) / 12, seed + 17000 + field.ore.index * 101)
    if nx * nx + ny * ny <= edge then return field.ore end
    return nil
end

function layout.clear_cache()
    cache, cache_keys, cache_next = {}, {}, 1
    cached_ores, enabled_names = nil, nil
end

return layout
