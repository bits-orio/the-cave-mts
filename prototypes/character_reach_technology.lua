-- The Cave: native character-distance research.
--
-- These are five of Factorio's built-in character distance modifiers. Manual
-- F-key item pickup intentionally stays at vanilla range so one pickup cannot
-- drain a large belt area. Keeping the remaining progression in technology
-- prototypes means the engine owns the bonuses per force; no runtime
-- player/character rewriting, periodic polling, or multiplayer synchronisation
-- is required.

local PREFIX = "the-cave-character-reach-upgrade-"
local BONUS_PER_LEVEL = 2
local BASE_RUNNING_SPEED = 0.15
local TARGET_RUNNING_SPEED = 0.40
local RUNNING_MODIFIER_PER_LEVEL = (TARGET_RUNNING_SPEED / BASE_RUNNING_SPEED - 1) / 10
local CRAFTING_MODIFIER_PER_LEVEL = 0.90
local BASE_CRAFTING_SPEED = 1.0

local EFFECT_TYPES = {
    "character-build-distance",
    "character-reach-distance",
    "character-resource-reach-distance",
    "character-item-drop-distance",
    "character-loot-pickup-distance",
}

-- Ten levels, capped at 500 science packs. The six normal pre-space science
-- packs are introduced in their vanilla order: red, green, military, blue,
-- production, then utility. Later levels retain the complete unlocked set.
local LEVELS = {
    { count =  50, packs = { "automation-science-pack" } },
    { count = 100, gate = "logistic-science-pack", packs = {
        "automation-science-pack", "logistic-science-pack",
    } },
    { count = 150, gate = "military-science-pack", packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
    } },
    { count = 200, gate = "chemical-science-pack", packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack",
    } },
    { count = 250, packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack",
    } },
    { count = 300, gate = "production-science-pack", packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack",
    } },
    { count = 350, packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack",
    } },
    { count = 400, gate = "utility-science-pack", packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack", "utility-science-pack",
    } },
    { count = 450, packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack", "utility-science-pack",
    } },
    { count = 500, packs = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack", "utility-science-pack",
    } },
}

local function ingredients(pack_names)
    local result = {}
    for _, pack in ipairs(pack_names) do
        result[#result + 1] = { pack, 1 }
    end
    return result
end

local function effects()
    local result = {}
    for _, effect_type in ipairs(EFFECT_TYPES) do
        result[#result + 1] = {
            type = effect_type,
            modifier = BONUS_PER_LEVEL,
        }
    end
    result[#result + 1] = {
        type = "character-running-speed",
        modifier = RUNNING_MODIFIER_PER_LEVEL,
    }
    result[#result + 1] = {
        type = "character-crafting-speed",
        modifier = CRAFTING_MODIFIER_PER_LEVEL,
    }
    return result
end

local function technology_icons()
    return {
        {
            icon = "__the-cave__/graphics/technology/character-reach-upgrade.png",
            icon_size = 256,
        },
    }
end

local technologies = {}

for level, definition in ipairs(LEVELS) do
    local prerequisites = {}
    if level > 1 then
        prerequisites[#prerequisites + 1] = PREFIX .. (level - 1)
    end
    if definition.gate and data.raw.technology[definition.gate] then
        prerequisites[#prerequisites + 1] = definition.gate
    end

    local total_bonus = level * BONUS_PER_LEVEL
    local total_running_speed = BASE_RUNNING_SPEED * (1 + RUNNING_MODIFIER_PER_LEVEL * level)
    local total_crafting_speed = BASE_CRAFTING_SPEED * (1 + CRAFTING_MODIFIER_PER_LEVEL * level)
    technologies[#technologies + 1] = {
        type = "technology",
        name = PREFIX .. level,
        localised_name = {
            "",
            { "technology-name.the-cave-character-reach-upgrade" },
            " ", tostring(level),
        },
        localised_description = {
            "technology-description.the-cave-character-reach-upgrade",
            tostring(BONUS_PER_LEVEL),
            tostring(total_bonus),
            string.format("%.2f", total_running_speed),
            string.format("%.1f", total_crafting_speed),
        },
        icons = technology_icons(),
        effects = effects(),
        prerequisites = prerequisites,
        unit = {
            count = definition.count,
            ingredients = ingredients(definition.packs),
            time = 30,
        },
        order = "the-cave-character-reach-" .. string.format("%02d", level),
    }
end

data:extend(technologies)
