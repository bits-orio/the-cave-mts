local settings = require("scripts.game_settings").proxy(settings)

-- The Cave 2.0: Digging Rock Economy.
-- The rock prototype gives the stone part of the reward directly. This module
-- adds the non-stone resource part so the final item-count balance is close to:
-- Stone ~30%, Iron/Copper/Coal share the remaining ~70%. Uranium joins only
-- from Medium depth onward and remains very rare.
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local ore_missing = require("scripts.ore_missing")
local region_features = require("scripts.region_features")

local dig_yield = {}

-- Hash stream ids (keep unique across all dig modules).
local S_ORE_PICK, S_ORE_COUNT = 30, 31

local EXTRA_ORES_BY_LEVEL = {
    -- Stone is handled by the rock prototype itself (1-2 stone per dig).
    -- Extra rewards are non-stone resources, giving an item-count balance close
    -- to Stone 30% and Iron/Copper/Coal sharing the remaining 70%.
    easy = {
        -- Final target including the rock's built-in stone reward:
        -- Stone 25%, Iron 30%, Copper 25%, Coal 20%.
        -- Stone is not in this extra pool, so these weights describe the
        -- 75% non-stone part only.
        { name = "iron-ore", weight = 40 },
        { name = "copper-ore", weight = 33 },
        { name = "coal", weight = 27 },
    },
    medium = {
        -- Medium+ final target: Stone 24%, Iron 29%, Copper 24%, Coal 19%, Uranium 4%.
        { name = "iron-ore", weight = 38 },
        { name = "copper-ore", weight = 32 },
        { name = "coal", weight = 25 },
    },
    hard = {
        { name = "iron-ore", weight = 38 },
        { name = "copper-ore", weight = 32 },
        { name = "coal", weight = 25 },
    },
    nightmare = {
        { name = "iron-ore", weight = 38 },
        { name = "copper-ore", weight = 32 },
        { name = "coal", weight = 25 },
    },
}

-- Inside the shared Vulcanus region, ordinary cave-rock digging expands from
-- the four-resource economy (built-in Stone plus Iron/Copper/Coal) to six
-- resources by adding the two solid Vulcanus ores. Stone remains the rock
-- prototype's guaranteed result; this pool selects the additional reward.
local VULCANUS_EXTRA_ORES = {
    { name = "iron-ore", weight = 25 },
    { name = "copper-ore", weight = 20 },
    { name = "coal", weight = 20 },
    { name = "calcite", weight = 20 },
    { name = "tungsten-ore", weight = 15 },
}

local DIGGING_MODE_MULTIPLIERS = {
    disabled = 1,
    hardcore = 0.5,
    ["digging-1"] = 1,
    ["digging-2"] = 2,
    ["digging-3"] = 3,
    ["digging-4"] = 4,
}

local function digging_mode_value()
    local setting = settings.startup["the-cave-digging-mode"]
    return setting and setting.value or "disabled"
end

local function digging_reward_multiplier()
    return DIGGING_MODE_MULTIPLIERS[digging_mode_value()] or 1
end

local EXTRA_COUNT_BY_LEVEL = {
    -- Average extra reward is now 4.5 items. With the rock's 1-2 stone
    -- built-in reward, stone lands near 25% of total item output.
    easy = { min = 3, max = 6 },
    medium = { min = 3, max = 6 },
    hard = { min = 5, max = 10 },
    nightmare = { min = 7, max = 14 },
}

local function total_weight(pool)
    local total = 0
    for _, ore in pairs(pool) do total = total + ore.weight end
    return total
end

local function pick_ore(seed, x, y, level_id, region)
    local pool = region == "vulcanus"
        and VULCANUS_EXTRA_ORES
        or (EXTRA_ORES_BY_LEVEL[level_id] or EXTRA_ORES_BY_LEVEL.easy)
    local roll = hash.roll(seed, x, y, S_ORE_PICK) * total_weight(pool)
    for _, ore in pairs(pool) do
        roll = roll - ore.weight
        if roll <= 0 then return ore.name end
    end
    return pool[#pool].name
end

function dig_yield.on_player_mined(event)
    if event.entity.name ~= "diggy-rock" and event.entity.name ~= "diggy-rubble" then return end
    local surface = event.entity.surface
    local p = event.entity.position

    local x, y = math.floor(p.x), math.floor(p.y)
    -- Ordinary digging rewards remain available from both frontier rock and
    -- collapsed rubble in every planetary region. Vulcanus additionally folds
    -- Calcite and Tungsten Ore into the deterministic extra-reward pool.
    local seed = surface.map_gen_settings.seed
    -- Lower cave surfaces are centred at (0,0), so position alone would always
    -- classify them as Easy. Inherit Medium/Hard/Nightmare from the upper
    -- entrance record instead, preserving the normal depth-based reward count.
    local level = depth_levels.level_for_surface_position(surface, p)
    local region = region_features.region_at(x, y)
    local count_range = EXTRA_COUNT_BY_LEVEL[level.id] or EXTRA_COUNT_BY_LEVEL.easy

    local count = hash.range(seed, x, y, S_ORE_COUNT, count_range.min, count_range.max)
    local multiplier = digging_reward_multiplier()
    if multiplier ~= 1 then
        count = math.max(1, math.floor(count * multiplier + 0.5))
    end

    local missing_resource = ore_missing.get_missing_resource()
    event.buffer.insert {
        name = missing_resource or pick_ore(seed, x, y, level.id, region),
        count = count,
    }
end

return dig_yield
