-- Dig-speed progression: 35 character-mining-speed technologies — five per
-- science group, except the space group which has ten. Per-tier bonus ramps
-- linearly so the final (10th space) tier grants exactly +100%. Force-level,
-- so under MTS each team researches its own digging speed.
local GROUPS = {
    { gate = "steel-axe", steps = 5, packs = { "automation-science-pack" } },
    { gate = "logistic-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack" } },
    { gate = "chemical-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" } },
    { gate = "production-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = "utility-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack" } },
    { gate = "space-science-pack", steps = 10, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "space-science-pack" } },
}
local TOTAL_TIERS = 0
for _, group in pairs(GROUPS) do TOTAL_TIERS = TOTAL_TIERS + group.steps end
local FIRST_MODIFIER, LAST_MODIFIER = 0.2, 1.0

local technologies = {}

-- Build the union of all Lobby-selectable scenario technologies. Runtime
-- selection controls the active systems; prototypes cannot be added later.
local CAVETORIO_ENABLED = true
local TRAIN_INTERIORS_ENABLED = true
local SHELTER_DEFENSE_ENABLED = true
-- Keep the two experimental research groups independent:
-- Train Interiors owns Train Battery / Shield / Interior Expansion / Main Train Expansion.
-- CAVETORIO owns Warp Outpost / Warp Time / Safety Ring.
local SAFETY_RING_TECH_PREFIX = "the-cave-safety-ring-upgrade-"

local function add_prerequisite(prerequisites, name)
    if name then prerequisites[#prerequisites + 1] = name end
end

local function safety_ring_prerequisite(tier)
    -- Train technologies must remain independently researchable when the Lobby
    -- selects Train Interiors without CAVETORIO.
    return nil
end
local tier = 0
local cumulative = 0
for group_index, group in ipairs(GROUPS) do
    for step = 1, group.steps do
        tier = tier + 1
        local prerequisites = {}
        if tier == 1 then
            prerequisites = { group.gate }
        elseif step == 1 then
            prerequisites = { "diggy-dig-speed-" .. (tier - 1), group.gate }
        else
            prerequisites = { "diggy-dig-speed-" .. (tier - 1) }
        end

        local ingredients = {}
        for _, pack in pairs(group.packs) do
            ingredients[#ingredients + 1] = { pack, 1 }
        end

        local modifier = FIRST_MODIFIER + (LAST_MODIFIER - FIRST_MODIFIER) * (tier - 1) / (TOTAL_TIERS - 1)
        modifier = math.floor(modifier * 100 + 0.5) / 100
        cumulative = cumulative + modifier

        technologies[#technologies + 1] = {
            type = "technology",
            name = "diggy-dig-speed-" .. tier,
            localised_name = { "", { "technology-name.diggy-dig-speed" }, " " .. tier },
            localised_description = { "technology-description.diggy-dig-speed-exact",
                tostring(math.floor(modifier * 100 + 0.5)),
                tostring(math.floor(cumulative * 100 + 0.5)) },
            icons = {
                { icon = "__base__/graphics/technology/steel-axe.png", icon_size = 256 },
            },
            effects = {
                { type = "character-mining-speed", modifier = modifier },
            },
            prerequisites = prerequisites,
            unit = {
                count = math.floor(50 * group_index * step * 1.25),
                ingredients = ingredients,
                time = 15 + group_index * 15,
            },
            order = "diggy-" .. string.format("%02d", tier),
        }
    end
end

-- Support reach: ten early-to-late tiers, each extending how far wall/reactor
-- supports project stress relief by one tile. The chain begins with Automation
-- science and ends at Utility science; Space science is intentionally excluded.
-- In Disabled mode the complete chain remains as hidden prototypes for save
-- compatibility, but it cannot be researched or clutter the technology tree.
local COLLAPSES_ENABLED = true
local SUPPORT_TIERS = {
    { gate = nil, packs = { "automation-science-pack" } },
    { gate = "logistic-science-pack", packs = { "automation-science-pack", "logistic-science-pack" } },
    { gate = "military-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
}

for tier, def in ipairs(SUPPORT_TIERS) do
    local prerequisites = {}
    if tier == 1 then
        prerequisites = { def.gate }
    elseif def.gate then
        prerequisites = { "diggy-support-reach-" .. (tier - 1), def.gate }
    else
        prerequisites = { "diggy-support-reach-" .. (tier - 1) }
    end
    local ingredients = {}
    for _, pack in pairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end
    technologies[#technologies + 1] = {
        type = "technology",
        name = "diggy-support-reach-" .. tier,
        localised_name = { "", { "technology-name.diggy-support-reach" }, " " .. tier },
        localised_description = { "technology-description.diggy-support-reach-exact",
            tostring(3 + tier), tostring(4 + tier) },
        icons = {
            { icon = "__base__/graphics/technology/stone-wall.png", icon_size = 256 },
        },
        effects = {
            { type = "nothing", effect_description = { "technology-effect.diggy-support-reach-exact",
                tostring(3 + tier), tostring(4 + tier) } },
        },
        prerequisites = prerequisites,
        unit = {
            count = 100 * tier,
            ingredients = ingredients,
            time = 45,
        },
        hidden = not COLLAPSES_ENABLED,
        order = "diggy-s" .. tier,
    }
end


-- Train Battery progression: the starter train begins with no battery installed.
-- Researching Upgrade 1 installs the first hidden train battery, then later
-- upgrades increase only the MJ capacity. Power export stays disabled until the
-- first upgrade is complete.
local TRAIN_BATTERY_TECH_PREFIX = "the-cave-train-battery-upgrade-"
local TRAIN_BATTERY_TECHS = {
    { capacity = 2000, count = 200, packs = { "automation-science-pack" } },
    { capacity = 2500, count = 400, packs = { "automation-science-pack" } },
    { capacity = 3200, count = 600, packs = { "automation-science-pack" } },
    { capacity = 4200, count = 800, packs = { "automation-science-pack", "logistic-science-pack" } },
    { capacity = 5500, count = 1000, packs = { "automation-science-pack", "logistic-science-pack" } },
    { capacity = 7000, count = 1200, packs = { "automation-science-pack", "logistic-science-pack" } },
    { capacity = 9000, count = 1400, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { capacity = 12000, count = 1600, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { capacity = 15000, count = 1800, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { capacity = 20000, count = 2000, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { capacity = 25000, count = 2200, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { capacity = 32000, count = 2400, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { capacity = 42000, count = 2600, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { capacity = 55000, count = 2800, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { capacity = 70000, count = 3000, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { capacity = 90000, count = 3200, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 120000, count = 3400, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 150000, count = 3600, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 200000, count = 3800, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 250000, count = 4000, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
}
local TRAIN_SHIELD_BATTERY_PREREQUISITE_LEVELS = 6

if TRAIN_INTERIORS_ENABLED then
for tier, def in ipairs(TRAIN_BATTERY_TECHS) do
    local ingredients = {}
    for _, pack in pairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end

    local tech = {
        type = "technology",
        name = TRAIN_BATTERY_TECH_PREFIX .. tier,
        localised_name = { "", "Train Battery Upgrade ", tostring(tier) },
        localised_description = { "", "Unlocks or upgrades the train's hidden battery storage to ", tostring(def.capacity), " MJ. The locomotive can export stored power to nearby external electric poles." },
        icons = {
            { icon = "__the-cave__/graphics/technology/train-battery.png", icon_size = 256 },
        },
        effects = {
            { type = "nothing", effect_description = { "", "Train Battery capacity: ", tostring(def.capacity), " MJ" } },
        },
        unit = {
            count = def.count,
            ingredients = ingredients,
            time = 15,
        },
        order = "the-cave-train-battery-" .. string.format("%02d", tier),
    }
    local prerequisites = {}
    if tier > 1 then add_prerequisite(prerequisites, TRAIN_BATTERY_TECH_PREFIX .. (tier - 1)) end
    add_prerequisite(prerequisites, safety_ring_prerequisite(tier))
    if #prerequisites > 0 then tech.prerequisites = prerequisites end
    technologies[#technologies + 1] = tech
end
end


-- Train Interior Expansion: Level 0 starts at 40x40 with a 40-tile-wide
-- connector. Levels 1-2 expand as squares, then width caps at 92 while height
-- grows through 100, 160, 220 and 280. Every connector matches room height.
-- The chain ends at Utility Science; Space Science is intentionally excluded.
local TRAIN_INTERIOR_EXPANSION_TECH_PREFIX = "the-cave-train-interior-expansion-"
local TRAIN_INTERIOR_EXPANSION_TECHS = {
    { width = 60, height = 60, connector_width = 60, count = 100, gate = nil, packs = { "automation-science-pack" } },
    { width = 80, height = 80, connector_width = 80, count = 280, gate = "logistic-science-pack", packs = { "automation-science-pack", "logistic-science-pack" } },
    { width = 92, height = 100, connector_width = 100, count = 460, gate = "military-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { width = 92, height = 160, connector_width = 160, count = 640, gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { width = 92, height = 220, connector_width = 220, count = 820, gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { width = 92, height = 280, connector_width = 280, count = 1000, gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
}

if TRAIN_INTERIORS_ENABLED then
for tier, def in ipairs(TRAIN_INTERIOR_EXPANSION_TECHS) do
    local ingredients = {}
    for _, pack in pairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end

    local tech = {
        type = "technology",
        name = TRAIN_INTERIOR_EXPANSION_TECH_PREFIX .. tier,
        localised_name = { "", "Train Interior Expansion ", tostring(tier) },
        localised_description = { "", "Expands every connected train-wagon interior from the fixed center core. Interior size becomes ", tostring(def.width), "×", tostring(def.height), " tiles and connector width becomes ", tostring(def.connector_width), " tiles." },
        icons = {
            { icon = "__the-cave__/graphics/technology/train-interior-expansion.png", icon_size = 256 },
        },
        effects = {
            { type = "nothing", effect_description = { "", "Train interior: ", tostring(def.width), "×", tostring(def.height), " tiles; connector width: ", tostring(def.connector_width), " tiles" } },
        },
        unit = {
            count = def.count,
            ingredients = ingredients,
            time = 30,
        },
        order = "the-cave-train-interior-expansion-" .. string.format("%02d", tier),
    }
    local prerequisites = {}
    if tier > 1 then add_prerequisite(prerequisites, TRAIN_INTERIOR_EXPANSION_TECH_PREFIX .. (tier - 1)) end
    add_prerequisite(prerequisites, safety_ring_prerequisite(tier))
    if def.gate then add_prerequisite(prerequisites, def.gate) end
    if #prerequisites > 0 then tech.prerequisites = prerequisites end
    technologies[#technologies + 1] = tech
end
end



-- Toolbelt inventory expansion: 10 simple character-inventory upgrades.
-- Each tier adds +10 inventory slots, for +100 total by the final tier.
-- This chain uses only base/vanilla science packs and ends at Space Science,
-- without requiring any Space Age planet science packs.
local THE_CAVE_TOOLBELT_TECH_PREFIX = "the-cave-toolbelt-upgrade-"

local function toolbelt_upgrade_icons()
    local base_toolbelt = data.raw.technology and data.raw.technology["toolbelt"] or nil
    if base_toolbelt then
        if base_toolbelt.icons then return table.deepcopy(base_toolbelt.icons) end
        if base_toolbelt.icon then
            return {
                {
                    icon = base_toolbelt.icon,
                    icon_size = base_toolbelt.icon_size or 256,
                    icon_mipmaps = base_toolbelt.icon_mipmaps,
                },
            }
        end
    end
    return {
        { icon = "__base__/graphics/technology/toolbelt.png", icon_size = 256 },
    }
end

local THE_CAVE_TOOLBELT_TECHS = {
    { count = 100, gate = nil, packs = { "automation-science-pack" } },
    { count = 200, gate = "logistic-science-pack", packs = { "automation-science-pack", "logistic-science-pack" } },
    { count = 300, gate = "military-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { count = 400, gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { count = 500, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { count = 600, gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { count = 700, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { count = 800, gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { count = 900, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { count = 1000, gate = "space-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack" } },
}

local toolbelt_icons = toolbelt_upgrade_icons()
for tier, def in ipairs(THE_CAVE_TOOLBELT_TECHS) do
    local ingredients = {}
    for _, pack in pairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end

    local tech = {
        type = "technology",
        name = THE_CAVE_TOOLBELT_TECH_PREFIX .. tier,
        localised_name = { "", "Toolbelt Upgrade ", tostring(tier) },
        localised_description = { "", "Adds +10 character inventory slots. Total bonus from this chain after this upgrade: +", tostring(tier * 10), " slots." },
        icons = table.deepcopy(toolbelt_icons),
        effects = {
            { type = "character-inventory-slots-bonus", modifier = 10 },
        },
        unit = {
            count = def.count,
            ingredients = ingredients,
            time = 30,
        },
        order = "the-cave-toolbelt-" .. string.format("%02d", tier),
    }
    local prerequisites = {}
    if tier > 1 then prerequisites[#prerequisites + 1] = THE_CAVE_TOOLBELT_TECH_PREFIX .. (tier - 1) end
    if def.gate then prerequisites[#prerequisites + 1] = def.gate end
    if #prerequisites > 0 then tech.prerequisites = prerequisites end
    technologies[#technologies + 1] = tech
end


-- Main Train Expansion: controls how many train parts can be accepted into the
-- single Main Train. The starter train begins with 3 parts; each upgrade adds
-- +1 accepted part, up to 23 total. The chain ends at Utility Science.
local MAIN_TRAIN_EXPANSION_TECH_PREFIX = "the-cave-main-train-expansion-"
local MAIN_TRAIN_EXPANSION_TECHS = {
    { capacity = 4, count = 200, gate = nil, packs = { "automation-science-pack" } },
    { capacity = 5, count = 400, gate = nil, packs = { "automation-science-pack" } },
    { capacity = 6, count = 600, gate = nil, packs = { "automation-science-pack" } },
    { capacity = 7, count = 800, gate = "logistic-science-pack", packs = { "automation-science-pack", "logistic-science-pack" } },
    { capacity = 8, count = 1000, gate = nil, packs = { "automation-science-pack", "logistic-science-pack" } },
    { capacity = 9, count = 1200, gate = nil, packs = { "automation-science-pack", "logistic-science-pack" } },
    { capacity = 10, count = 1400, gate = "military-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { capacity = 11, count = 1600, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { capacity = 12, count = 1800, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { capacity = 13, count = 2000, gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { capacity = 14, count = 2200, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { capacity = 15, count = 2400, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { capacity = 16, count = 2600, gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { capacity = 17, count = 2800, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { capacity = 18, count = 3000, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { capacity = 19, count = 3200, gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 20, count = 3400, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 21, count = 3600, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 22, count = 3800, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { capacity = 23, count = 4000, gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
}

if TRAIN_INTERIORS_ENABLED then
for tier, def in ipairs(MAIN_TRAIN_EXPANSION_TECHS) do
    local ingredients = {}
    for _, pack in pairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end

    local tech = {
        type = "technology",
        name = MAIN_TRAIN_EXPANSION_TECH_PREFIX .. tier,
        localised_name = { "", "Main Train Expansion ", tostring(tier) },
        localised_description = { "", "Increases the maximum number of accepted parts in the Main Train by 1. New maximum: ", tostring(def.capacity), " train parts." },
        icons = {
            { icon = "__the-cave__/graphics/technology/main-train-expansion.png", icon_size = 256 },
        },
        effects = {
            { type = "nothing", effect_description = { "", "Main Train capacity: ", tostring(def.capacity), " train parts" } },
        },
        unit = {
            count = def.count,
            ingredients = ingredients,
            time = 30,
        },
        order = "the-cave-main-train-expansion-" .. string.format("%02d", tier),
    }
    local prerequisites = {}
    if tier > 1 then add_prerequisite(prerequisites, MAIN_TRAIN_EXPANSION_TECH_PREFIX .. (tier - 1)) end
    -- Levels above six share the sixth and final Interior Expansion prerequisite.
    add_prerequisite(prerequisites, TRAIN_INTERIOR_EXPANSION_TECH_PREFIX .. math.min(tier, #TRAIN_INTERIOR_EXPANSION_TECHS))
    if def.gate then add_prerequisite(prerequisites, def.gate) end
    if #prerequisites > 0 then tech.prerequisites = prerequisites end
    technologies[#technologies + 1] = tech
end
end

-- Locomotive Garden: Train Interiors Space Age garden room.
-- Keep the technology visible when Train Interiors and Agricultural science exist.
-- Stage 1 is placed after Planet Discovery: Gleba when that technology exists.
local LOCOMOTIVE_GARDEN_TECH_PREFIX = "the-cave-locomotive-garden-"
local LOCOMOTIVE_GARDEN_GLEBA_DISCOVERY =
    data.raw.technology["planet-discovery-gleba"] and "planet-discovery-gleba" or nil
local LOCOMOTIVE_GARDEN_ENABLED = TRAIN_INTERIORS_ENABLED
    and data.raw.item
    and data.raw.item["agricultural-science-pack"]

if LOCOMOTIVE_GARDEN_ENABLED then
    local LOCOMOTIVE_GARDEN_TECHS = {
        { count = 200, stage = 1 },
        { count = 400, stage = 2 },
        { count = 600, stage = 3 },
    }

    for tier, def in ipairs(LOCOMOTIVE_GARDEN_TECHS) do
        local tech = {
            type = "technology",
            name = LOCOMOTIVE_GARDEN_TECH_PREFIX .. tier,
            localised_name = tier == 1 and { "", "Locomotive Garden" } or { "", "Locomotive Garden ", tostring(tier) },
            localised_description = {
                "",
                "Unlocks or expands the CAVETORIO Locomotive Garden room. The Garden room has a fixed green build core, internal water, and expanding Yumako/Jellynut growing soil."
            },
            icons = {
                { icon = "__the-cave__/graphics/technology/locomotive-garden.png", icon_size = 256 },
            },
            effects = {
                { type = "nothing", effect_description = { "", "Locomotive Garden stage ", tostring(def.stage) } },
            },
            prerequisites = tier == 1 and (LOCOMOTIVE_GARDEN_GLEBA_DISCOVERY and { LOCOMOTIVE_GARDEN_GLEBA_DISCOVERY } or {}) or { LOCOMOTIVE_GARDEN_TECH_PREFIX .. (tier - 1) },
            unit = {
                count = def.count,
                ingredients = { { "agricultural-science-pack", 1 } },
                time = 30,
            },
            order = "the-cave-locomotive-garden-" .. string.format("%02d", tier),
        }
        technologies[#technologies + 1] = tech
    end
end



-- Train Shield progression: reinforces every Cave rolling stock. This is one
-- shared research chain for base Factorio and Space Age, ending at Utility
-- Science without requiring Space Science.
local TRAIN_SHIELD_TECH_PREFIX = "the-cave-train-shield-upgrade-"
local TRAIN_SHIELD_TECHS = {
    { health = 8000, repair = 5, count = 200, packs = { "automation-science-pack" } },
    { health = 11000, repair = 10, count = 400, packs = { "automation-science-pack", "logistic-science-pack" } },
    { health = 14000, repair = 15, count = 600, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { health = 17000, repair = 20, count = 800, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { health = 20000, repair = 25, count = 1000, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { health = 23000, repair = 30, count = 1200, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { health = 26000, repair = 35, count = 1400, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { health = 29000, repair = 40, count = 1600, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { health = 32000, repair = 45, count = 1800, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { health = 35000, repair = 50, count = 2000, packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
}

if TRAIN_INTERIORS_ENABLED then
for tier, def in ipairs(TRAIN_SHIELD_TECHS) do
    local ingredients = {}
    for _, pack in pairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end

    local tech = {
        type = "technology",
        name = TRAIN_SHIELD_TECH_PREFIX .. tier,
        localised_name = { "", "Train Shield Upgrade ", tostring(tier) },
        localised_description = { "", "Reinforces the whole connected Cave train with a shared shield. Train Shield max health becomes ", tostring(def.health), " HP and self-repair becomes ", tostring(def.repair), " HP/sec." },
        icons = {
            { icon = "__the-cave__/graphics/technology/train-shield.png", icon_size = 256 },
        },
        effects = {
            { type = "nothing", effect_description = { "", "Shared Train Shield health: ", tostring(def.health), " HP" } },
            { type = "nothing", effect_description = { "", "Self-repair: ", tostring(def.repair), " HP/sec" } },
        },
        unit = {
            count = def.count,
            ingredients = ingredients,
            time = 30,
        },
        order = "the-cave-train-shield-" .. string.format("%02d", tier),
    }
    local prerequisites = {}
    if tier > 1 then add_prerequisite(prerequisites, TRAIN_SHIELD_TECH_PREFIX .. (tier - 1)) end
    if tier <= TRAIN_SHIELD_BATTERY_PREREQUISITE_LEVELS then
        add_prerequisite(prerequisites, TRAIN_BATTERY_TECH_PREFIX .. tier)
    elseif tier == 7 then
        add_prerequisite(prerequisites, safety_ring_prerequisite(7))
    end
    if #prerequisites > 0 then tech.prerequisites = prerequisites end
    technologies[#technologies + 1] = tech
end
end



-- Experimental Warp Outpost Expansion: grows the surface footprint that is
-- preserved between Cavetorio-style warps. Uses only base Factorio science packs
-- and ends at Space Science, with no Space Age planet science.
local WARP_OUTPOST_EXPANSION_TECH_PREFIX = "the-cave-warp-outpost-expansion-"
local WARP_OUTPOST_TIME_TECH_PREFIX = "the-cave-warp-outpost-time-"
local WARP_OUTPOST_EXPANSION_COUNTS = { 1000, 2000, 3500, 5000, 7000, 8500, 10000 }
local WARP_OUTPOST_TIME_COUNTS = { 300, 650, 1000, 1400, 1750, 2150, 2500 }
local SAFETY_RING_COUNTS = { 300, 500, 750, 1000, 1300, 1600, 2000 }
local SAFETY_RING_RADII = { 20, 30, 40, 50, 60, 70, 80 }
local SAFETY_RING_COOLDOWNS = { 1, 1, 1, 1, 1, 1, 1 }
local WARP_OUTPOST_PACKS = {
    { gate = nil, packs = { "automation-science-pack" } },
    { gate = "logistic-science-pack", packs = { "automation-science-pack", "logistic-science-pack" } },
    { gate = "military-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
    { gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
    { gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { gate = "space-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack" } },
}
local WARP_OUTPOST_SIZES = { "50x50", "75x75", "100x100", "125x125", "150x150", "175x175", "200x200" }
local WARP_OUTPOST_TIMES = {
    { minutes = 45, countdown = 30, cooldown = 30 },
    { minutes = 60, countdown = 40, cooldown = 45 },
    { minutes = 80, countdown = 60, cooldown = 60 },
    { minutes = 100, countdown = 80, cooldown = 90 },
    { minutes = 120, countdown = 100, cooldown = 120 },
    { minutes = 140, countdown = 110, cooldown = 150 },
    { minutes = 160, countdown = 120, cooldown = 180 },
}

local function add_warp_outpost_tech_chain(prefix, kind, icon, order_prefix, counts, effect_builder)
    for tier, def in ipairs(WARP_OUTPOST_PACKS) do
        local ingredients = {}
        for _, pack in pairs(def.packs) do
            ingredients[#ingredients + 1] = { pack, 1 }
        end
        local tech = {
            type = "technology",
            name = prefix .. tier,
            localised_name = { "", kind, " ", tostring(tier) },
            localised_description = { "", effect_builder(tier, true) },
            icons = {
                { icon = icon, icon_size = 256 },
            },
            effects = {
                { type = "nothing", effect_description = { "", effect_builder(tier, false) } },
            },
            unit = {
                count = counts[tier],
                ingredients = ingredients,
                time = 30,
            },
            order = order_prefix .. string.format("%02d", tier),
        }
        local prerequisites = {}
        if tier > 1 then add_prerequisite(prerequisites, prefix .. (tier - 1)) end
        if prefix == WARP_OUTPOST_EXPANSION_TECH_PREFIX then
            add_prerequisite(prerequisites, safety_ring_prerequisite(tier))
        elseif prefix == WARP_OUTPOST_TIME_TECH_PREFIX then
            add_prerequisite(prerequisites, WARP_OUTPOST_EXPANSION_TECH_PREFIX .. tier)
        end
        if def.gate then add_prerequisite(prerequisites, def.gate) end
        if #prerequisites > 0 then tech.prerequisites = prerequisites end
        technologies[#technologies + 1] = tech
    end
end

if CAVETORIO_ENABLED then
add_warp_outpost_tech_chain(
    WARP_OUTPOST_EXPANSION_TECH_PREFIX,
    "Warp Outpost Expansion",
    "__the-cave__/graphics/technology/warp-outpost-expansion.png",
    "the-cave-warp-outpost-expansion-",
    WARP_OUTPOST_EXPANSION_COUNTS,
    function(tier)
        return "Increases the Warp Outpost preserved footprint to " .. WARP_OUTPOST_SIZES[tier] .. ". Anything fully inside the Outpost is preserved during experimental warps."
    end
)

add_warp_outpost_tech_chain(
    WARP_OUTPOST_TIME_TECH_PREFIX,
    "Warp Outpost Time",
    "__the-cave__/graphics/technology/warp-outpost-time.png",
    "the-cave-warp-outpost-time-",
    WARP_OUTPOST_TIME_COUNTS,
    function(tier)
        local def = WARP_OUTPOST_TIMES[tier]
        return "Extends each cave cycle to " .. def.minutes .. " minutes. Manual Warp countdown: " .. def.countdown .. " sec. Safety cooldown: " .. def.cooldown .. " sec."
    end
)

add_warp_outpost_tech_chain(
    SAFETY_RING_TECH_PREFIX,
    "Safety Ring Upgrade",
    "__the-cave__/graphics/technology/safety-ring.png",
    "the-cave-safety-ring-",
    SAFETY_RING_COUNTS,
    function(tier)
        return "Expands the Safety Ring to " .. tostring(SAFETY_RING_RADII[tier]) .. " tiles. Enables or strengthens attack waves. Boss every 10 waves; rest every 50 waves."
    end
)
end

-- Shelter mode is the mutually-exclusive fixed-core alternative to Train
-- Interiors. Its technology names and chains are intentionally independent so
-- no Train research or saved Train progression is changed.
if SHELTER_DEFENSE_ENABLED then
    local SHELTER_PACKS = {
        { gate = nil, packs = { "automation-science-pack" } },
        { gate = "logistic-science-pack", packs = { "automation-science-pack", "logistic-science-pack" } },
        { gate = "military-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" } },
        { gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" } },
        { gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" } },
        { gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    }

    local function ingredients_for(packs)
        local result = {}
        for _, pack in ipairs(packs) do result[#result + 1] = { pack, 1 } end
        return result
    end

    local function add_shelter_chain(prefix, defs, icon, order, name_key, description_key, time)
        for level, def in ipairs(defs) do
            local pack_def = SHELTER_PACKS[math.min(level, #SHELTER_PACKS)]
            local prerequisites = {}
            if level > 1 then prerequisites[#prerequisites + 1] = prefix .. (level - 1) end
            if pack_def.gate then prerequisites[#prerequisites + 1] = pack_def.gate end
            technologies[#technologies + 1] = {
                type = "technology",
                name = prefix .. level,
                localised_name = { name_key, tostring(level) },
                localised_description = { description_key, tostring(def.a), def.b and tostring(def.b) or "" },
                icons = { { icon = icon, icon_size = 256 } },
                effects = {
                    { type = "nothing", effect_description = { description_key, tostring(def.a), def.b and tostring(def.b) or "" } },
                },
                prerequisites = #prerequisites > 0 and prerequisites or nil,
                unit = {
                    count = def.count,
                    ingredients = ingredients_for(pack_def.packs),
                    time = time,
                },
                order = order .. string.format("%02d", level),
            }
        end
    end

    -- Shelter Garden Floor mirrors the proven three-stage Train Garden
    -- progression without sharing Train research state. It is available only
    -- when Space Age's Agricultural science pack exists.
    local shelter_garden_available = data.raw.item
        and data.raw.item["agricultural-science-pack"]
    if shelter_garden_available then
        local garden_discovery = data.raw.technology["planet-discovery-gleba"]
            and "planet-discovery-gleba" or nil
        local garden_counts = { 200, 400, 600 }
        for level, count in ipairs(garden_counts) do
            local prerequisites = {}
            if level == 1 then
                if garden_discovery then prerequisites[#prerequisites + 1] = garden_discovery end
            else
                prerequisites[#prerequisites + 1] = "the-cave-shelter-garden-" .. (level - 1)
            end
            technologies[#technologies + 1] = {
                type = "technology",
                name = "the-cave-shelter-garden-" .. level,
                localised_name = { "technology-name.the-cave-shelter-garden", tostring(level) },
                localised_description = { "technology-description.the-cave-shelter-garden", tostring(level) },
                icons = {
                    -- A Shelter-specific research image: never reuse the
                    -- Locomotive Garden icon inside Shelter Defense.
                    {
                        icon = "__the-cave__/graphics/shelter/shelter.png",
                        icon_size = 64,
                        scale = 4,
                        tint = { r = 0.62, g = 1, b = 0.62, a = 1 },
                    },
                },
                effects = {
                    { type = "nothing", effect_description = {
                        "technology-description.the-cave-shelter-garden-effect", tostring(level) } },
                },
                prerequisites = #prerequisites > 0 and prerequisites or nil,
                unit = {
                    count = count,
                    ingredients = { { "agricultural-science-pack", 1 } },
                    time = 30,
                },
                order = "the-cave-shelter-garden-" .. string.format("%02d", level),
            }
        end
    end

    add_shelter_chain(
        "the-cave-shelter-interior-expansion-",
        {
            { a = 90, b = 90, count = 100 },
            { a = 120, b = 120, count = 225 },
            { a = 150, b = 150, count = 350 },
            { a = 180, b = 180, count = 475 },
            { a = 210, b = 210, count = 625 },
            { a = 240, b = 240, count = 750 },
            { a = 270, b = 270, count = 875 },
            { a = 300, b = 300, count = 1000 },
        },
        "__the-cave__/graphics/technology/train-interior-expansion.png",
        "the-cave-shelter-interior-expansion-",
        "technology-name.the-cave-shelter-interior-expansion",
        "technology-description.the-cave-shelter-interior-expansion",
        30
    )

    -- Shelter Battery is a separate research chain but intentionally mirrors
    -- all 20 Train Battery stages, costs and science packs exactly.
    local shelter_charge_rates = {
        50, 100, 150, 200, 250,
        300, 350, 400, 450, 500,
        550, 600, 650, 700, 750,
        800, 850, 900, 950, 1000,
    }
    local shelter_output_rates = {
        50, 100, 150, 250, 400, 600,
        600, 600, 600, 600, 600, 600, 600,
        600, 600, 600, 600, 600, 600, 600,
    }
    for level, def in ipairs(TRAIN_BATTERY_TECHS) do
        local prerequisites = {}
        if level > 1 then prerequisites[#prerequisites + 1] = "the-cave-shelter-battery-upgrade-" .. (level - 1) end
        technologies[#technologies + 1] = {
            type = "technology",
            name = "the-cave-shelter-battery-upgrade-" .. level,
            localised_name = { "technology-name.the-cave-shelter-battery-upgrade", tostring(level) },
            localised_description = { "technology-description.the-cave-shelter-battery-upgrade",
                tostring(def.capacity), tostring(shelter_charge_rates[level]), tostring(shelter_output_rates[level]) },
            icons = { { icon = "__the-cave__/graphics/technology/shelter-battery.png", icon_size = 256 } },
            effects = {
                { type = "nothing", effect_description = { "technology-description.the-cave-shelter-battery-upgrade",
                    tostring(def.capacity), tostring(shelter_charge_rates[level]), tostring(shelter_output_rates[level]) } },
            },
            prerequisites = #prerequisites > 0 and prerequisites or nil,
            unit = { count = def.count, ingredients = ingredients_for(def.packs), time = 15 },
            order = "the-cave-shelter-battery-" .. string.format("%02d", level),
        }
    end

    -- Shelter Shield uses the proven Train Shield balance on the single fixed
    -- objective: 5,000 base HP, +3,000 HP and +5 HP/sec per level.
    for level, def in ipairs(TRAIN_SHIELD_TECHS) do
        local prerequisites = {}
        if level > 1 then
            prerequisites[#prerequisites + 1] = "the-cave-shelter-shield-upgrade-" .. (level - 1)
        end
        if level <= TRAIN_SHIELD_BATTERY_PREREQUISITE_LEVELS then
            prerequisites[#prerequisites + 1] = "the-cave-shelter-battery-upgrade-" .. level
        end
        technologies[#technologies + 1] = {
            type = "technology",
            name = "the-cave-shelter-shield-upgrade-" .. level,
            localised_name = { "technology-name.the-cave-shelter-shield-upgrade", tostring(level) },
            localised_description = { "technology-description.the-cave-shelter-shield-upgrade",
                tostring(def.health), tostring(def.repair) },
            icons = { { icon = "__the-cave__/graphics/technology/shelter-shield.png", icon_size = 256 } },
            effects = {
                { type = "nothing", effect_description = {
                    "technology-description.the-cave-shelter-shield-health", tostring(def.health) } },
                { type = "nothing", effect_description = {
                    "technology-description.the-cave-shelter-shield-repair", tostring(def.repair) } },
            },
            prerequisites = #prerequisites > 0 and prerequisites or nil,
            unit = { count = def.count, ingredients = ingredients_for(def.packs), time = 30 },
            order = "the-cave-shelter-shield-" .. string.format("%02d", level),
        }
    end

    local attack_counts = { 100, 225, 350, 475, 625, 750, 875, 1000 }
    for level = 1, 8 do
        local pack_def = SHELTER_PACKS[math.min(level, 6)]
        local prerequisites = {}
        if level > 1 then prerequisites[#prerequisites + 1] = "the-cave-shelter-attack-distance-" .. (level - 1) end
        if level <= 6 and pack_def.gate then prerequisites[#prerequisites + 1] = pack_def.gate end
        local attack_chunks = 10 + level * 2
        technologies[#technologies + 1] = {
            type = "technology",
            name = "the-cave-shelter-attack-distance-" .. level,
            localised_name = { "technology-name.the-cave-shelter-attack-distance", tostring(level) },
            localised_description = { "technology-description.the-cave-shelter-attack-distance", tostring(attack_chunks), tostring(attack_chunks + 2) },
            icons = { { icon = "__the-cave__/graphics/technology/shelter-attack-distance.png", icon_size = 256 } },
            effects = {
                { type = "nothing", effect_description = { "technology-description.the-cave-shelter-attack-distance", tostring(attack_chunks), tostring(attack_chunks + 2) } },
            },
            prerequisites = #prerequisites > 0 and prerequisites or nil,
            unit = { count = attack_counts[level], ingredients = ingredients_for(pack_def.packs), time = 30 },
            order = "the-cave-shelter-attack-distance-" .. string.format("%02d", level),
            visible_when_disabled = false,
        }
    end
end

data:extend(technologies)
