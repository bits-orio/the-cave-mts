-- Runtime-only entities for timed Iron, Copper and Coal Mineral Caves.
-- Reuse the proven Uranium Cave cave-mouth, linked-belt and power prototypes,
-- but keep distinct names so both systems can coexist without shared records.

local prototypes = {}

local function clone_entity(prototype_type, source_name, target_name, localised_name, localised_description)
    local source = data.raw[prototype_type] and data.raw[prototype_type][source_name]
    assert(source, "The Cave Mineral Caves require prototype " .. prototype_type .. "/" .. source_name)
    local entity = table.deepcopy(source)
    entity.name = target_name
    entity.localised_name = localised_name
    entity.localised_description = localised_description
    entity.hidden_in_factoriopedia = true
    prototypes[#prototypes + 1] = entity
    return entity
end

local entrance_1 = clone_entity(
    "container",
    "the-cave-uranium-cave-entrance-1",
    "the-cave-mineral-cave-entrance-1",
    { "entity-name.the-cave-mineral-cave-entrance" },
    { "entity-description.the-cave-mineral-cave-entrance" }
)
entrance_1.map_color = { r = 0.70, g = 0.50, b = 0.16, a = 1 }

local entrance_2 = clone_entity(
    "container",
    "the-cave-uranium-cave-entrance-2",
    "the-cave-mineral-cave-entrance-2",
    { "entity-name.the-cave-mineral-cave-entrance" },
    { "entity-description.the-cave-mineral-cave-entrance" }
)
entrance_2.map_color = entrance_1.map_color

local exit_1 = clone_entity(
    "container",
    "the-cave-uranium-cave-exit-1",
    "the-cave-mineral-cave-exit-1",
    { "entity-name.the-cave-mineral-cave-exit" },
    { "entity-description.the-cave-mineral-cave-exit" }
)
exit_1.map_color = { r = 0.38, g = 0.78, b = 0.36, a = 1 }

local exit_2 = clone_entity(
    "container",
    "the-cave-uranium-cave-exit-2",
    "the-cave-mineral-cave-exit-2",
    { "entity-name.the-cave-mineral-cave-exit" },
    { "entity-description.the-cave-mineral-cave-exit" }
)
exit_2.map_color = exit_1.map_color

local item_port_defs = {
    { "the-cave-uranium-item-down-input", "the-cave-mineral-item-down-input" },
    { "the-cave-uranium-item-down-output", "the-cave-mineral-item-down-output" },
    { "the-cave-uranium-item-up-input", "the-cave-mineral-item-up-input" },
    { "the-cave-uranium-item-up-output", "the-cave-mineral-item-up-output" },
}
for _, def in ipairs(item_port_defs) do
    clone_entity(
        "linked-belt",
        def[1],
        def[2],
        { "entity-name." .. def[2] },
        { "entity-description." .. def[2] }
    )
end

clone_entity(
    "electric-pole",
    "the-cave-uranium-power-connector",
    "the-cave-mineral-power-connector",
    { "entity-name.the-cave-mineral-power-bridge" },
    { "entity-description.the-cave-mineral-power-bridge" }
)
clone_entity(
    "accumulator",
    "the-cave-uranium-power-input",
    "the-cave-mineral-power-input",
    { "entity-name.the-cave-mineral-power-bridge" },
    { "entity-description.the-cave-mineral-power-bridge" }
)
clone_entity(
    "accumulator",
    "the-cave-uranium-power-output",
    "the-cave-mineral-power-output",
    { "entity-name.the-cave-mineral-power-bridge" },
    { "entity-description.the-cave-mineral-power-bridge" }
)

data:extend(prototypes)
