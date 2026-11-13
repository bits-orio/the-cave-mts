-- The Cave: Turret Range Upgrade technologies.
-- Five vanilla/base-compatible research levels.
-- Each level is handled at runtime and adds +3 range to supported turrets.

local function has_tech(name)
    return data.raw.technology and data.raw.technology[name] ~= nil
end

local function add_existing(prerequisites, name)
    if name and has_tech(name) then
        prerequisites[#prerequisites + 1] = name
    end
end

local function ingredients(pack_names)
    local result = {}
    for _, pack in pairs(pack_names) do
        result[#result + 1] = { pack, 1 }
    end
    return result
end

local PREFIX = "the-cave-turret-range-upgrade-"

local defs = {
    {
        count = 300,
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" },
        gates = { "military-science-pack", "gun-turret" },
    },
    {
        count = 450,
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" },
        gates = { "chemical-science-pack" },
    },
    {
        count = 600,
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack" },
        gates = { "production-science-pack" },
    },
    {
        count = 800,
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" },
        gates = { "utility-science-pack" },
    },
    {
        count = 1000,
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack" },
        gates = { "space-science-pack" },
    },
}

local technologies = {}

for level, def in ipairs(defs) do
    local prerequisites = {}
    if level > 1 then
        prerequisites[#prerequisites + 1] = PREFIX .. (level - 1)
    end
    for _, gate in pairs(def.gates or {}) do
        add_existing(prerequisites, gate)
    end

    local total_bonus = level * 3
    technologies[#technologies + 1] = {
        type = "technology",
        name = PREFIX .. level,
        localised_name = { "", "Turret Range Upgrade ", tostring(level) },
        localised_description = { "", "Increases supported turret range by +3. Total turret range bonus: +", tostring(total_bonus), ". Artillery turrets are not affected." },
        icons = {
            { icon = "__the-cave__/graphics/technology/turret-range-upgrade.png", icon_size = 256 },
        },
        effects = {
            {
                type = "nothing",
                effect_description = { "", "+3 turret range (total +", tostring(total_bonus), ")" },
            },
        },
        prerequisites = prerequisites,
        unit = {
            count = def.count,
            ingredients = ingredients(def.packs),
            time = 30,
        },
        order = "the-cave-turret-range-" .. string.format("%02d", level),
    }
end

data:extend(technologies)
