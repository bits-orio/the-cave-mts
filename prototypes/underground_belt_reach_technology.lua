-- The Cave: Underground Belt Reach research.
-- Prototype IDs always exist so changing the startup setting cannot invalidate
-- old saves. When disabled, the chain is hidden and cannot be researched.

local setting = settings.startup["the-cave-underground-belt-reach-research"]
local feature_enabled = not setting or setting.value ~= "disabled"
local PREFIX = "the-cave-underground-belt-reach-"

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

local function copy_icon_layers(proto_name)
    local item = (data.raw.item and data.raw.item[proto_name])
        or (data.raw["item-with-entity-data"] and data.raw["item-with-entity-data"][proto_name])
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
    return {{ icon = "__base__/graphics/icons/underground-belt.png", icon_size = 64 }}
end

local function shifted_layers(base_icons, shift, scale)
    local layers = {}
    for _, icon in ipairs(base_icons) do
        local layer = table.deepcopy(icon)
        layer.shift = shift
        layer.scale = (layer.scale or 1) * scale
        layers[#layers + 1] = layer
    end
    return layers
end

local function reach_icons()
    local base = copy_icon_layers("underground-belt")
    local icons = {}
    for _, layer in ipairs(shifted_layers(base, {-46, 8}, 1.45)) do icons[#icons + 1] = layer end
    for _, layer in ipairs(shifted_layers(base, {46, -8}, 1.45)) do icons[#icons + 1] = layer end
    return icons
end

local defs = {
    { count = 100, per_level_bonus = 2, total_bonus = 2,
      packs = {"automation-science-pack"}, gates = {"logistics"} },
    { count = 200, per_level_bonus = 2, total_bonus = 4,
      packs = {"automation-science-pack", "logistic-science-pack"}, gates = {"logistic-science-pack"} },
    { count = 300, per_level_bonus = 1, total_bonus = 5,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack"}, gates = {"military-science-pack"} },
    { count = 400, per_level_bonus = 1, total_bonus = 6,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack"}, gates = {"chemical-science-pack"} },
    { count = 500, per_level_bonus = 1, total_bonus = 7,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack"}, gates = {"production-science-pack"} },
    { count = 600, per_level_bonus = 1, total_bonus = 8,
      packs = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}, gates = {"utility-science-pack"} },
    { count = 700, per_level_bonus = 1, total_bonus = 9,
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
        localised_name = { "", { "technology-name.the-cave-underground-belt-reach" }, " ", tostring(level) },
        localised_description = {
            "technology-description.the-cave-underground-belt-reach",
            tostring(def.per_level_bonus),
            tostring(def.total_bonus),
        },
        icons = reach_icons(),
        effects = {{
            type = "nothing",
            effect_description = {
                "technology-effect.the-cave-underground-belt-reach",
                tostring(def.per_level_bonus),
                tostring(def.total_bonus),
            },
        }},
        prerequisites = prerequisites,
        unit = { count = def.count, ingredients = ingredients(def.packs), time = 30 },
        order = "the-cave-underground-belt-reach-" .. string.format("%02d", level),
        upgrade = true,
        enabled = feature_enabled,
        hidden = not feature_enabled,
        visible_when_disabled = false,
    }
end

data:extend(technologies)
