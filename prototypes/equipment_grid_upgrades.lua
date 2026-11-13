local prototypes = {}

local function clone_grid(base_name, level)
    local base = data.raw["equipment-grid"] and data.raw["equipment-grid"][base_name]
    if not base then return nil end
    local grid = table.deepcopy(base)
    grid.name = "the-cave-grid-" .. base_name .. "-" .. level
    grid.width = (base.width or 0) + level * 2
    grid.height = (base.height or 0) + level * 2
    prototypes[#prototypes + 1] = grid
    return grid.name
end

local function clone_armor(base_name)
    local base = data.raw.armor and data.raw.armor[base_name]
    if not (base and base.equipment_grid) then return end
    for level = 1, 3 do
        local item = table.deepcopy(base)
        item.name = "the-cave-grid-" .. base_name .. "-" .. level
        item.equipment_grid = clone_grid(base.equipment_grid, level)

        -- Internal armor upgrade item. Keep the same player-facing name/icon,
        -- but hide it from editor/Factoriopedia/crafting lists so players only
        -- see one Modular/Power/MK2 armor like Tank and Spidertron.
        item.hidden = true
        item.hidden_in_factoriopedia = true
        item.subgroup = nil
        item.order = "z[the-cave-hidden-grid]-" .. base_name .. "-" .. level
        item.localised_name = { "item-name." .. base_name }
        item.localised_description = {
            "",
            { "item-description." .. base_name },
            "\n[The Cave] Equipment grid expanded by +",
            tostring(level * 2),
            " / +",
            tostring(level * 2),
        }
        prototypes[#prototypes + 1] = item
    end
end

local function clone_vehicle(proto_type, base_name)
    local base = data.raw[proto_type] and data.raw[proto_type][base_name]
    local base_item = data.raw["item-with-entity-data"] and data.raw["item-with-entity-data"][base_name]
    if not (base and base.equipment_grid and base_item) then return end

    for level = 1, 3 do
        local internal_name = "the-cave-grid-" .. base_name .. "-" .. level

        -- A matching item-with-entity-data is required for each enlarged vehicle.
        -- Factorio can only preserve a vehicle's equipment grid in an item whose
        -- place_result points back to that exact vehicle prototype. Returning the
        -- vanilla Tank/Spidertron item here silently truncated or deleted equipment
        -- placed in the extra researched grid cells after the vehicle was mined.
        local item = table.deepcopy(base_item)
        item.name = internal_name
        item.place_result = internal_name
        item.hidden = true
        item.hidden_in_factoriopedia = true
        item.order = "z[the-cave-hidden-grid]-" .. base_name .. "-" .. level
        item.localised_name = { "item-name." .. base_name }
        item.localised_description = { "item-description." .. base_name }
        prototypes[#prototypes + 1] = item

        local entity = table.deepcopy(base)
        entity.name = internal_name
        entity.equipment_grid = clone_grid(base.equipment_grid, level)
        entity.localised_name = { "entity-name." .. base_name }
        entity.localised_description = { "entity-description." .. base_name }
        if entity.minable then
            entity.minable.result = internal_name
            entity.minable.results = nil
        end
        prototypes[#prototypes + 1] = entity
    end
end

clone_armor("modular-armor")
clone_armor("power-armor")
clone_armor("power-armor-mk2")
clone_vehicle("car", "tank")
clone_vehicle("spider-vehicle", "spidertron")

local technologies = {}
local icon = "__the-cave__/graphics/technology/equipment-grid-upgrade.png"
local tiers = {
    {
        prereq = { "modular-armor" },
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack" },
        count = 500,
        label = "Equipment Grid Upgrade 1",
        description = { "technology-description.the-cave-equipment-grid-upgrade", "2", "2" },
    },
    {
        prereq = { "the-cave-equipment-grid-upgrade-1", "power-armor" },
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" },
        count = 1500,
        label = "Equipment Grid Upgrade 2",
        description = { "technology-description.the-cave-equipment-grid-upgrade", "4", "4" },
    },
    {
        prereq = { "the-cave-equipment-grid-upgrade-2", "power-armor-mk2" },
        packs = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "utility-science-pack" },
        count = 2500,
        label = "Equipment Grid Upgrade 3",
        description = { "technology-description.the-cave-equipment-grid-upgrade", "6", "6" },
    },
}

for level, def in ipairs(tiers) do
    local ingredients = {}
    for _, pack in ipairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end
    technologies[#technologies + 1] = {
        type = "technology",
        name = "the-cave-equipment-grid-upgrade-" .. level,
        localised_name = { "technology-name.the-cave-equipment-grid-upgrade", tostring(level) },
        localised_description = def.description,
        icons = {
            { icon = icon, icon_size = 256 },
        },
        effects = {
            {
                type = "nothing",
                effect_description = { "technology-effect.the-cave-equipment-grid-upgrade", tostring(level * 2), tostring(level * 2) },
            },
        },
        prerequisites = def.prereq,
        unit = {
            count = def.count,
            ingredients = ingredients,
            time = 45,
        },
        order = "diggy-g" .. level,
    }
end

data:extend(prototypes)
data:extend(technologies)
