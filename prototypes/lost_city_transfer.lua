-- Fixed Blue-belt-speed item ports for the Lost City. Linked belts preserve
-- lanes, stack size and quality across surfaces while presenting the same
-- underground-style endpoints used by Uranium and Mineral Qs.

local prototypes = {}

local function clone_port(source_name, target_name)
    local source = data.raw["linked-belt"] and data.raw["linked-belt"][source_name]
    assert(source, "The Cave Lost City requires linked-belt/" .. source_name)
    local entity = table.deepcopy(source)
    entity.name = target_name
    entity.localised_name = { "entity-name." .. target_name }
    entity.localised_description = { "entity-description." .. target_name }
    entity.hidden_in_factoriopedia = true
    prototypes[#prototypes + 1] = entity
end

clone_port("the-cave-mineral-item-down-input", "the-cave-lost-city-item-down-input")
clone_port("the-cave-mineral-item-down-output", "the-cave-lost-city-item-down-output")
clone_port("the-cave-mineral-item-up-input", "the-cave-lost-city-item-up-input")
clone_port("the-cave-mineral-item-up-output", "the-cave-lost-city-item-up-output")

data:extend(prototypes)
