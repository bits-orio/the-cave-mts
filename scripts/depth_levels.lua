local settings = require("scripts.game_settings").proxy(settings)

-- The Cave depth levels.
-- Multiplayer-safe: this uses only deterministic position distance from the
-- starting area, and stores only per-force announcement state.
local depth = {}
local advancing_zones = require("scripts.advancing_zones")
local cave_evolution = require("scripts.cave_evolution")

function depth.uses_evolution_only(surface)
    return advancing_zones.is_active() and advancing_zones.is_main_surface(surface)
end

local uranium_caves_api
local mineral_caves_api

function depth.configure_extraction_cave_apis(uranium_api, mineral_api)
    assert(type(uranium_api) == "table" and type(uranium_api.zone_id_for_surface) == "function",
        "The Cave: Uranium Cave depth API is unavailable")
    assert(type(mineral_api) == "table" and type(mineral_api.zone_id_for_surface) == "function",
        "The Cave: Mineral Cave depth API is unavailable")
    uranium_caves_api = uranium_api
    mineral_caves_api = mineral_api
end

local LEVELS = {
    { id = "easy",      title_key = "the-cave-runtime.depth-easy",      min = 0,    enemy_mult = 1.00, cavern_bonus = 0 },
    { id = "medium",    title_key = "the-cave-runtime.depth-medium",    min = 300,  enemy_mult = 1.15, cavern_bonus = 8 },
    { id = "hard",      title_key = "the-cave-runtime.depth-hard",      min = 700,  enemy_mult = 1.35, cavern_bonus = 16 },
    { id = "nightmare", title_key = "the-cave-runtime.depth-nightmare", min = 1000, enemy_mult = 1.65, cavern_bonus = 28 },
}

depth.LEVELS = LEVELS

local GLOBAL_DIFFICULTY_MULTIPLIERS = {
    easy = 0.50,
    medium = 1.00,
    hard = 1.50,
    nightmare = 2.00,
}

-- Mobile-enemy count scaling is intentionally separate from the older general
-- difficulty multiplier above. These ratios preserve Medium as the baseline,
-- while hard caps prevent direct digs and combat rooms from ever returning to
-- the old CPU-heavy hundred-unit spikes.
local MOBILE_ENEMY_COUNT_MULTIPLIERS = {
    easy = 0.50,          -- 1.5 / 3
    medium = 1.00,        -- 3 / 3
    hard = 5 / 3,         -- 5 / 3
    nightmare = 8 / 3,    -- 8 / 3
}

local MOBILE_ENEMY_COUNT_CAPS = {
    easy = 10,
    medium = 18,
    hard = 28,
    nightmare = 35,
}

local GLOBAL_LOOT_MULTIPLIERS = {
    easy = 1.25,
    medium = 1.00,
    hard = 0.90,
    nightmare = 0.75,
}

function depth.global_difficulty()
    local setting = settings.startup["the-cave-global-difficulty"]
    return (setting and setting.value) or "medium"
end

function depth.global_difficulty_multiplier()
    return GLOBAL_DIFFICULTY_MULTIPLIERS[depth.global_difficulty()] or 1.00
end

function depth.mobile_enemy_count_multiplier()
    return MOBILE_ENEMY_COUNT_MULTIPLIERS[depth.global_difficulty()] or 1.00
end

function depth.mobile_enemy_count_cap()
    return MOBILE_ENEMY_COUNT_CAPS[depth.global_difficulty()] or MOBILE_ENEMY_COUNT_CAPS.medium
end

function depth.scale_mobile_enemy_count(base_count)
    local base = math.max(0, tonumber(base_count) or 0)
    if base <= 0 then return 0 end
    local scaled = math.max(1, math.floor(base * depth.mobile_enemy_count_multiplier() + 0.5))
    return math.min(scaled, depth.mobile_enemy_count_cap())
end

function depth.global_loot_multiplier()
    return GLOBAL_LOOT_MULTIPLIERS[depth.global_difficulty()] or 1.00
end

function depth.distance(position)
    return math.sqrt(position.x * position.x + position.y * position.y)
end

function depth.level_for_distance(distance)
    local current = LEVELS[1]
    for _, level in pairs(LEVELS) do
        if distance >= level.min then current = level end
    end
    return current
end

function depth.level_for_position(position)
    return depth.level_for_distance(depth.distance(position))
end

function depth.level_by_id(id)
    for _, level in ipairs(LEVELS) do
        if level.id == id then return level end
    end
    return nil
end

-- Timed extraction-cave surfaces inherit the zone of their upper entrance.
-- The APIs are injected once at script load because both cave modules require
-- this module and Factorio's package.loaded keys are not stable lookup names.
function depth.level_for_surface_position(surface, position)
    -- Existing room/reward tables need an internal tier key. On this ribbon
    -- derive that key from evolution, never position. Do not add a second
    -- difficulty bonus to enemies that already use evolution for their tier.
    -- Mission/extraction surfaces and all other modes keep their own profiles.
    if depth.uses_evolution_only(surface) then
        local evolution = cave_evolution.factor(surface)
        local index = evolution >= 0.85 and 4 or (evolution >= 0.55 and 3
            or (evolution >= 0.25 and 2 or 1))
        local profile = LEVELS[index]
        return { id = profile.id, title_key = "the-cave-runtime.depth-evolution",
            min = 0, enemy_mult = 1, cavern_bonus = profile.cavern_bonus }
    end
    if uranium_caves_api then
        local zone_id = uranium_caves_api.zone_id_for_surface(surface)
        local inherited = zone_id and depth.level_by_id(zone_id) or nil
        if inherited then return inherited end
    end
    if mineral_caves_api then
        local zone_id = mineral_caves_api.zone_id_for_surface(surface)
        local inherited = zone_id and depth.level_by_id(zone_id) or nil
        if inherited then return inherited end
    end
    return depth.level_for_position(position)
end

function depth.on_init()
    storage.the_cave_depth_levels = storage.the_cave_depth_levels or {}
end

function depth.on_configuration_changed()
    for _, key in ipairs({ "the_cave_depth_levels", "the_cave_max_depth" }) do
        local values = storage[key] or {}
        storage[key] = values
        local names = {}
        for name in pairs(values) do
            if type(name) == "string" then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local value = values[name]
            local force = game.forces[name]
            if force and force.valid then
                if key == "the_cave_max_depth" then
                    values[force.index] = math.max(tonumber(values[force.index]) or 0, tonumber(value) or 0)
                else
                    local old = depth.level_by_id(values[force.index])
                    local incoming = depth.level_by_id(value)
                    if incoming and (not old or incoming.min > old.min) then values[force.index] = value end
                end
            end
            values[name] = nil
        end
    end
end

function depth.clear_force(force_index)
    if storage.the_cave_depth_levels then storage.the_cave_depth_levels[force_index] = nil end
    if storage.the_cave_max_depth then storage.the_cave_max_depth[force_index] = nil end
end

function depth.on_dig(dig)
    if not dig or not dig.force then return end
    storage.the_cave_depth_levels = storage.the_cave_depth_levels or {}
    storage.the_cave_max_depth = storage.the_cave_max_depth or {}

    local force_index = dig.force.index
    local inherited_level = depth.level_for_surface_position(dig.surface, dig.position)
    local current_distance = math.max(depth.distance(dig.position), inherited_level and inherited_level.min or 0)
    local max_distance = storage.the_cave_max_depth[force_index] or 0

    if current_distance > max_distance then
        max_distance = current_distance
        storage.the_cave_max_depth[force_index] = max_distance
    end

    -- Preserve measured exploration distance without announcing depth tiers.
    if depth.uses_evolution_only(dig.surface) then return end
    local level = depth.level_for_distance(max_distance)
    local previous = storage.the_cave_depth_levels[force_index]

    if previous ~= level.id then
        storage.the_cave_depth_levels[force_index] = level.id
        dig.force.print({ "the-cave-runtime.entering-depth", { level.title_key } })
    end
end

function depth.enemy_multiplier(position, surface)
    return depth.level_for_surface_position(surface, position).enemy_mult * depth.global_difficulty_multiplier()
end

function depth.cavern_length_bonus(position, surface)
    return depth.level_for_surface_position(surface, position).cavern_bonus
end

return depth
