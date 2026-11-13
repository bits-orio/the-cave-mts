-- The Cave: Underground Pipe Reach research.
-- Prototype IDs always exist so changing the startup setting cannot invalidate
-- old saves. When disabled, the chain is hidden and cannot be researched.

local setting = settings.startup["the-cave-underground-pipe-reach-research"]
local feature_enabled = not setting or setting.value ~= "disabled"
local PREFIX = "the-cave-underground-pipe-reach-"

local function has_tech(name)
    return data.raw.technology and data.raw.technology[name] ~= nil
end

local function add_existing(prerequisites, name)
    if name and has_tech(name) then prerequisites[#prerequisites + 1] = name end
end

local function ingredients(pack_names)
    local result = {}
    for _, pack in pairs(pack_names) do result[#result + 1] = { pack, 1 } end
    return result
end

local function pipe_icons()
    local item = (data.raw.item and data.raw.item["pipe-to-ground"])
        or (data.raw["item-with-entity-data"] and data.raw["item-with-entity-data"]["pipe-to-ground"])
    if item then
        if item.icons then return table.deepcopy(item.icons) end
        if item.icon then
            return {{
                icon = item.icon,
                icon_size = item.icon_size or 64,
                icon_mipmaps = item.icon_mipmaps,
            }}
        end
    end
    return {{ icon = "__base__/graphics/icons/pipe-to-ground.png", icon_size = 64 }}
end

local defs = {
    { count = 200, total_bonus = 5,
      packs = {"automation-science-pack"}, gates = {} },
    { count = 300, total_bonus = 10,
      packs = {"automation-science-pack", "logistic-science-pack"}, gates = {"logistic-science-pack"} },
    { count = 450, total_bonus = 15,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack"}, gates = {"military-science-pack"} },
    { count = 600, total_bonus = 20,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack"}, gates = {"chemical-science-pack"} },
    { count = 750, total_bonus = 25,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack"}, gates = {"production-science-pack"} },
    { count = 900, total_bonus = 30,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}, gates = {"utility-science-pack"} },
    { count = 1000, total_bonus = 35,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"}, gates = {"space-science-pack"} },
}

local technologies = {}
for level, def in ipairs(defs) do
    local prerequisites = {}
    if level > 1 then prerequisites[#prerequisites + 1] = PREFIX .. (level - 1) end
    for _, gate in pairs(def.gates or {}) do add_existing(prerequisites, gate) end

    technologies[#technologies + 1] = {
        type = "technology",
        name = PREFIX .. level,
        localised_name = { "", { "technology-name.the-cave-underground-pipe-reach" }, " ", tostring(level) },
        localised_description = {
            "technology-description.the-cave-underground-pipe-reach",
            "5",
            tostring(def.total_bonus),
            tostring(10 + def.total_bonus),
        },
        icons = pipe_icons(),
        effects = {{
            type = "nothing",
            effect_description = {
                "technology-effect.the-cave-underground-pipe-reach",
                "5",
                tostring(def.total_bonus),
                tostring(10 + def.total_bonus),
            },
        }},
        prerequisites = prerequisites,
        unit = { count = def.count, ingredients = ingredients(def.packs), time = 30 },
        order = "the-cave-underground-pipe-reach-" .. string.format("%02d", level),
        upgrade = true,
        enabled = feature_enabled,
        hidden = not feature_enabled,
        visible_when_disabled = false,
    }
end

data:extend(technologies)
