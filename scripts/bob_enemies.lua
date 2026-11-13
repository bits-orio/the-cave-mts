-- Optional Bob's Enemies adapter. Bob owns unit prototypes, spawn curves and
-- balance; The Cave owns room geometry, encounter pacing and its reward budget.
-- Every public entry is inert when bobenemies is absent, including old-save data.
local bob = {}
bob.room_stream, bob.super_stream, bob.worm_stream = 158, 159, 160
local hash = require("scripts.lib.hash")
local cave_evolution = require("scripts.cave_evolution")

local BREEDS = { "basic", "piercing", "electric", "acid", "explosive", "poison", "fire" }
local SIZES = { "small", "medium", "big", "huge", "giant", "titan", "behemoth", "leviathan" }
local BREED_SET, SIZE_SET = {}, {}
for _, name in ipairs(BREEDS) do BREED_SET[name] = true end
for _, name in ipairs(SIZES) do SIZE_SET[name] = true end
local UNIT_COINS = { small = 1, medium = 2, big = 3, huge = 4,
    giant = 4, titan = 5, behemoth = 5, leviathan = 10 }
local WORM_COINS = { small = 2, medium = 4, big = 8, huge = 10,
    giant = 12, titan = 14, behemoth = 16, leviathan = 32 }
local ORE_RANGES = { small = { min = 10, max = 20 }, medium = { min = 20, max = 40 },
    big = { min = 40, max = 80 }, huge = { min = 50, max = 100 },
    giant = { min = 60, max = 120 }, titan = { min = 70, max = 140 },
    behemoth = { min = 80, max = 160 }, leviathan = { min = 160, max = 320 } }
local cached_order, expansion_api

function bob.active()
    return script and script.active_mods and script.active_mods["bobenemies"] ~= nil or false
end

-- Bound once by control.lua; avoid a require cycle between rooms, ecology
-- and expansion. Newly scripted rooms/dig worms are never migration parts.
function bob.configure_expansion_api(api)
    assert(type(api) == "table" and type(api.protect_scripted_base_part) == "function",
        "The Cave: Bob expansion protection API is unavailable")
    expansion_api = api
end

function bob.protect_scripted_base_part(entity)
    if bob.active() and expansion_api then expansion_api.protect_scripted_base_part(entity) end
end

local function setting(name, fallback)
    local entry = settings and settings.startup and settings.startup[name]
    if entry then return entry.value end
    return fallback
end

local function exists(name)
    return name and prototypes and prototypes.entity and prototypes.entity[name] ~= nil
end

local function clamped_roll(roll)
    return math.max(0, math.min(0.999999999999, tonumber(roll) or 0))
end

local function choose(list, roll)
    return list[math.floor(clamped_roll(roll) * #list) + 1]
end

local function unit_name(breed, size, kind)
    if breed == "basic" then
        local prefix = (size == "small" or size == "medium" or size == "big"
            or size == "behemoth") and "" or "bob-"
        return prefix .. size .. "-" .. kind
    end
    return "bob-" .. size .. "-" .. breed .. "-" .. kind
end

function bob.unit_info(name)
    if not bob.active() or type(name) ~= "string" then return nil end
    for _, kind in ipairs({ "biter", "spitter", "worm-turret" }) do
        local suffix = "-" .. kind
        if name:sub(-#suffix) == suffix then
            local stem = name:sub(1, -#suffix - 1)
            local size, breed = stem:match("^bob%-(%a+)%-(%a+)$")
            if not size then size, breed = stem:match("^bob%-(%a+)$"), "basic" end
            if not size then size, breed = stem, "basic" end
            if SIZE_SET[size] and BREED_SET[breed] and name == unit_name(breed, size, kind) then
                return { size = size, breed = breed, kind = kind }
            end
        end
    end
    return nil
end

function bob.coin_value(name)
    local info = bob.unit_info(name)
    return info and (info.kind == "worm-turret" and WORM_COINS or UNIT_COINS)[info.size] or nil
end

function bob.ore_range(name)
    local info = bob.unit_info(name)
    return info and info.kind ~= "worm-turret" and ORE_RANGES[info.size] or nil
end

function bob.nest_info(name)
    if not bob.active() or type(name) ~= "string" then return nil end
    for _, breed in ipairs(BREEDS) do
        local infix = breed == "basic" and "" or breed .. "-"
        for _, kind in ipairs({ "biter", "spitter", "super" }) do
            if name == "bob-" .. infix .. kind .. "-spawner"
                or (kind ~= "super" and name == "bob-0-" .. infix .. kind .. "-spawner") then
                return { breed = breed, kind = kind }
            end
        end
    end
    return nil
end

function bob.nest_names()
    local names = {}
    if not bob.active() then return names end
    for _, breed in ipairs(BREEDS) do
        local infix = breed == "basic" and "" or breed .. "-"
        for _, kind in ipairs({ "biter", "spitter", "super" }) do
            local name = "bob-" .. infix .. kind .. "-spawner"
            if exists(name) then names[#names + 1] = name end
            if kind ~= "super" then
                name = "bob-0-" .. infix .. kind .. "-spawner"
                if exists(name) then names[#names + 1] = name end
            end
        end
    end
    return names
end

function bob.worm_names()
    local names = {}
    if not bob.active() then return names end
    for _, breed in ipairs(BREEDS) do
        for _, size in ipairs(SIZES) do
            local name = unit_name(breed, size, "worm-turret")
            if exists(name) then names[#names + 1] = name end
        end
    end
    return names
end

function bob.nest_name(breed, kind, evolution)
    if not bob.active() or not BREED_SET[breed] then return nil end
    local infix = breed == "basic" and "" or breed .. "-"
    if kind == "super" and ((evolution or 0) < 0.8
        or setting("bobmods-enemies-superspawner", true) ~= true) then kind = "biter" end
    local prefix = kind ~= "super" and (evolution or 0) < 0.5 and "bob-0-" or "bob-"
    local name = prefix .. infix .. kind .. "-spawner"
    return exists(name) and name or nil
end

function bob.growth_family(name)
    local info = bob.nest_info(name) or bob.unit_info(name)
    if not info then return nil end
    return "bob:" .. info.breed .. ":" .. (info.kind == "worm-turret" and "biter" or info.kind)
end

function bob.growth_nest_name(family, surface)
    if not bob.active() or type(family) ~= "string" then return nil end
    local breed, kind = family:match("^bob:(%a+):(%a+)$")
    if not breed or (kind ~= "biter" and kind ~= "spitter" and kind ~= "super") then return nil end
    local evolution = surface and cave_evolution.factor(surface) or 0
    return bob.nest_name(breed, kind, evolution)
end

local function complete_faction(breed)
    if not exists("bob-0-" .. breed .. "-biter-spawner")
        or not exists("bob-0-" .. breed .. "-spitter-spawner")
        or not exists("bob-" .. breed .. "-biter-spawner")
        or not exists("bob-" .. breed .. "-spitter-spawner") then return false end
    for _, size in ipairs(SIZES) do
        if not exists("bob-" .. size .. "-" .. breed .. "-worm-turret") then return false end
    end
    return setting("bobmods-enemies-superspawner", true) ~= true
        or exists("bob-" .. breed .. "-super-spawner")
end

local function faction_order()
    if cached_order then return cached_order end
    local configured, seen = {}, {}
    for breed in tostring(setting("bobmods-enemies-factionlist",
        "piercing,electric,acid,explosive,poison,fire")):gmatch("([^,]+)") do
        if not seen[breed] and complete_faction(breed) then
            configured[#configured + 1], seen[breed] = breed, true
        end
    end
    -- Bob keeps its shuffled unlock order private. The Cave follows the same
    -- one-time Fisher-Yates rule for its own rooms, persisted across save/load.
    local previous = storage and storage.the_cave_bob_faction_order
    if setting("bobmods-enemies-randomizeenemies", false) == true and storage then
        local ordered = {}
        for _, breed in ipairs(previous or {}) do
            if seen[breed] then ordered[#ordered + 1], seen[breed] = breed, nil end
        end
        if #ordered == 0 and not previous then
            local seed = game and game.default_map_gen_settings and game.default_map_gen_settings.seed or 0
            for i = #configured, 2, -1 do
                local j = hash.range(seed, i, 0, 62401, 1, i)
                configured[i], configured[j] = configured[j], configured[i]
            end
            ordered = configured
        else
            for _, breed in ipairs(configured) do
                if seen[breed] then ordered[#ordered + 1] = breed end
            end
        end
        storage.the_cave_bob_faction_order = ordered
        configured = ordered
    elseif previous then
        -- Match Bob's retention of a previously randomized order if its setting
        -- is later switched off; removing a faction never resurrects it.
        local ordered = {}
        for _, breed in ipairs(previous) do
            if seen[breed] then ordered[#ordered + 1], seen[breed] = breed, nil end
        end
        for _, breed in ipairs(configured) do
            if seen[breed] then ordered[#ordered + 1] = breed end
        end
        configured = ordered
    end
    cached_order = configured
    return configured
end

function bob.available_families(evolution)
    local result = {}
    if not bob.active() then return result end
    if bob.nest_name("basic", "biter", evolution)
        and bob.nest_name("basic", "spitter", evolution) then result[#result + 1] = "basic" end
    local ordered = faction_order()
    local start = tonumber(setting("bobmods-enemies-factionsappear", 0.5)) or 0.5
    local thresholds = { start, math.max(0.25, start + 0.1), math.min(0.75, math.max(0.35, start + 0.2)) }
    local count = #ordered
    local first = math.floor(count / 3)
    local second = count % 3 == 2 and math.ceil(count / 3) or first
    for i, breed in ipairs(ordered) do
        local group = i <= first and 1 or (i <= first + second and 2 or 3)
        if BREED_SET[breed] and evolution >= thresholds[group]
            and bob.nest_name(breed, "biter", evolution)
            and bob.nest_name(breed, "spitter", evolution) then result[#result + 1] = breed end
    end
    return result
end

-- Read the actual loaded result_units rather than keeping another copy of
-- Bob's eight-tier curves. This also honours Bigger enemies sooner and the
-- configured Leviathan frequency, as well as any prototype-stage adjustment.
local function weight_at(points, evolution)
    local last_evo, last_weight
    for _, point in ipairs(points or {}) do
        local evo = point.evolution_factor or point[1]
        local weight = point.weight or point[2]
        if evo ~= nil and weight ~= nil then
            if evolution <= evo then
                if not last_evo then return math.max(0, weight) end
                local fraction = evo == last_evo and 1 or (evolution - last_evo) / (evo - last_evo)
                return math.max(0, last_weight + (weight - last_weight) * fraction)
            end
            last_evo, last_weight = evo, weight
        end
    end
    return math.max(0, last_weight or 0)
end

function bob.pick_unit(breed, kind, evolution, roll)
    if not bob.active() then return nil end
    local nest = bob.nest_name(breed, kind, evolution)
    local prototype = nest and prototypes.entity[nest]
    local entries, total = {}, 0
    for _, entry in ipairs(prototype and prototype.result_units or {}) do
        local name = entry.unit or entry[1]
        local info = bob.unit_info(name)
        if info and info.breed == breed and info.kind == kind and exists(name) then
            local weight = weight_at(entry.spawn_points or entry[2], evolution)
            if weight > 0 then
                entries[#entries + 1] = { name = name, weight = weight }
                total = total + weight
            end
        end
    end
    if total <= 0 then return nil end
    local value = clamped_roll(roll) * total
    for _, entry in ipairs(entries) do
        value = value - entry.weight
        if value < 0 then return entry.name end
    end
    return entries[#entries].name
end

function bob.pick_worm(breed, evolution, roll)
    if not bob.active() or not BREED_SET[breed] then return nil end
    -- Same adjacent-tier selection as bobenemies/control.lua:replace_worm.
    local top, count = 1, 1
    if evolution >= 0.95 then top, count = 8, 4
    elseif evolution >= 0.9 then top, count = 7, 4
    elseif evolution >= 0.8 then top, count = 6, 4
    elseif evolution >= 0.7 then top, count = 5, 4
    elseif evolution >= 0.6 then top, count = 4, 4
    elseif evolution >= 0.45 then top, count = 3, 3
    elseif evolution >= 0.3 then top, count = 2, 2 end
    local tier = top - math.floor(clamped_roll(roll) * count)
    local name = unit_name(breed, SIZES[tier], "worm-turret")
    return exists(name) and name or nil
end

function bob.room_nests(breed, evolution, roll)
    if not bob.active() then return nil end
    local biter = bob.nest_name(breed, "biter", evolution)
    local spitter = bob.nest_name(breed, "spitter", evolution)
    if not biter or not spitter then return nil end
    local names = { biter, biter, spitter }
    if evolution >= 0.8 and setting("bobmods-enemies-superspawner", true) == true and clamped_roll(roll) < 0.1 then
        names[1] = bob.nest_name(breed, "super", evolution) or biter
    end
    return names
end

function bob.choose_room(evolution, arachnid_allowed, roll)
    if not bob.active() then return nil end
    local pool = { { kind = "nest" } }
    if arachnid_allowed then pool[#pool + 1] = { kind = "arachnid" } end
    for _, breed in ipairs(bob.available_families(evolution)) do
        pool[#pool + 1] = { kind = "nest", bob_family = breed }
    end
    return choose(pool, roll)
end

function bob.choose_dig(evolution, tier, group_roll, kind_roll, tier_roll)
    if not bob.active() then return nil, nil end
    local groups = { "biter", "spitter", "snapper", "arachnid", "worm" }
    for _, breed in ipairs(bob.available_families(evolution)) do groups[#groups + 1] = "bob:" .. breed end
    local group = choose(groups, group_roll)
    local breed = group:match("^bob:(%a+)$")
    if not breed then
        local name = group == "arachnid" and (kind_roll < 0.5 and tier.arachnid_biter or tier.arachnid_spitter)
            or tier[group]
        return name, group
    end
    local kind = choose({ "biter", "spitter", "worm-turret" }, kind_roll)
    local name = kind == "worm-turret" and bob.pick_worm(breed, evolution, tier_roll)
        or bob.pick_unit(breed, kind, evolution, tier_roll)
    return name, "bob:" .. breed .. ":" .. (kind == "worm-turret" and "biter" or kind)
end

function bob.on_configuration_changed()
    cached_order = nil
    if not bob.active() then return end
    faction_order()
end

return bob
