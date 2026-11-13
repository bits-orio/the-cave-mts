-- Runtime-only entities for the experimental Lost City mission prototype.
-- The cave-mouth artwork is owned by The Cave. Permitted settlement artwork
-- is bundled under graphics/lost-city and used by the standalone house set.

local prototypes = {}

local function clone_entity(prototype_type, source_name, target_name, localised_name, localised_description)
    local source = data.raw[prototype_type] and data.raw[prototype_type][source_name]
    assert(source, "The Cave Lost City requires prototype " .. prototype_type .. "/" .. source_name)
    local entity = table.deepcopy(source)
    entity.name = target_name
    entity.localised_name = localised_name
    entity.localised_description = localised_description
    entity.hidden_in_factoriopedia = true
    prototypes[#prototypes + 1] = entity
    return entity
end

local entrance = clone_entity(
    "container",
    "the-cave-uranium-cave-entrance-1",
    "the-cave-lost-city-entrance",
    { "entity-name.the-cave-lost-city-entrance" },
    { "entity-description.the-cave-lost-city-entrance" }
)
entrance.map_color = { r = 0.50, g = 0.20, b = 0.72, a = 1 }

local exit = clone_entity(
    "container",
    "the-cave-uranium-cave-exit-2",
    "the-cave-lost-city-exit",
    { "entity-name.the-cave-lost-city-exit" },
    { "entity-description.the-cave-lost-city-exit" }
)
exit.map_color = { r = 0.25, g = 0.75, b = 0.85, a = 1 }

local function mission_chest(name, localised_name, localised_description, map_color)
    local chest = table.deepcopy(data.raw.container["steel-chest"])
    chest.name = name
    chest.localised_name = localised_name
    chest.localised_description = localised_description
    chest.flags = {
        "placeable-neutral",
        "not-deconstructable",
        "not-blueprintable",
        "no-automated-item-insertion",
        "no-automated-item-removal",
        "hide-alt-info",
    }
    chest.minable = nil
    chest.destructible = false
    chest.max_health = 2000
    chest.inventory_size = 48
    chest.fast_replaceable_group = nil
    chest.next_upgrade = nil
    chest.allow_copy_paste = false
    chest.hidden_in_factoriopedia = true
    chest.map_color = map_color
    return chest
end

prototypes[#prototypes + 1] = mission_chest(
    "the-cave-lost-city-supply-crate",
    { "entity-name.the-cave-lost-city-supply-crate" },
    { "entity-description.the-cave-lost-city-supply-crate" },
    { r = 0.95, g = 0.65, b = 0.12, a = 1 }
)

prototypes[#prototypes + 1] = mission_chest(
    "the-cave-lost-city-reward-crate",
    { "entity-name.the-cave-lost-city-reward-crate" },
    { "entity-description.the-cave-lost-city-reward-crate" },
    { r = 0.20, g = 0.90, b = 0.35, a = 1 }
)

data:extend(prototypes)
