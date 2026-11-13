-- Uranium Cave runtime entities.
-- All entities in this file are script-created and intentionally have no item,
-- recipe, blueprint or mining result. The visible transfer ports resemble
-- ordinary underground infrastructure while their cross-surface connection is
-- owned by scripts/uranium_caves.lua.

local function runtime_flags()
    return {
        "placeable-neutral",
        "not-deconstructable",
        "not-blueprintable",
        "not-flammable",
        "hide-alt-info",
    }
end

local function portal_prototype(name, localised_name, localised_description, filename, width, height, scale, collision_box, selection_box)
    local portal = table.deepcopy(data.raw["container"]["wooden-chest"])
    portal.name = name
    portal.localised_name = localised_name
    portal.localised_description = localised_description
    portal.icon = "__the-cave__/graphics/entity/uranium-caves/cave-entrance-icon.png"
    portal.icon_size = 64
    portal.flags = {
        "placeable-neutral",
        "not-deconstructable",
        "not-blueprintable",
        "no-automated-item-insertion",
        "no-automated-item-removal",
        "hide-alt-info",
    }
    portal.minable = nil
    portal.destructible = false
    portal.max_health = 1000
    portal.inventory_size = 1
    portal.fast_replaceable_group = nil
    portal.next_upgrade = nil
    portal.collision_box = collision_box
    portal.selection_box = selection_box
    portal.picture = {
        layers = {
            {
                filename = filename,
                priority = "extra-high",
                width = width,
                height = height,
                scale = scale,
                shift = { 0, 0 },
            },
        },
    }
    portal.circuit_connector = nil
    portal.circuit_wire_max_distance = 0
    portal.allow_copy_paste = false
    portal.hidden_in_factoriopedia = true
    portal.map_color = { r = 0.28, g = 0.20, b = 0.10, a = 1 }
    return portal
end

local entrance_1 = portal_prototype(
    "the-cave-uranium-cave-entrance-1",
    { "entity-name.the-cave-uranium-cave-entrance" },
    { "entity-description.the-cave-uranium-cave-entrance" },
    "__the-cave__/graphics/entity/uranium-caves/cave-entrance-1.png",
    400,
    289,
    0.55,
    { { -1.95, -1.35 }, { 1.95, 1.35 } },
    { { -2.2, -1.6 }, { 2.2, 1.6 } }
)

local entrance_2 = table.deepcopy(entrance_1)
entrance_2.name = "the-cave-uranium-cave-entrance-2"
entrance_2.picture.layers[1].filename = "__the-cave__/graphics/entity/uranium-caves/cave-entrance-2.png"

-- The lower exit deliberately uses the same unmistakable cave-mouth artwork as
-- the upper entrance. Its tooltip/localised name is what distinguishes Exit.
local exit_1 = portal_prototype(
    "the-cave-uranium-cave-exit-1",
    { "entity-name.the-cave-uranium-cave-exit" },
    { "entity-description.the-cave-uranium-cave-exit" },
    "__the-cave__/graphics/entity/uranium-caves/cave-entrance-1.png",
    400,
    289,
    0.55,
    { { -1.95, -1.35 }, { 1.95, 1.35 } },
    { { -2.2, -1.6 }, { 2.2, 1.6 } }
)
exit_1.map_color = { r = 0.62, g = 0.45, b = 0.20, a = 1 }

local exit_2 = table.deepcopy(exit_1)
exit_2.name = "the-cave-uranium-cave-exit-2"
exit_2.picture.layers[1].filename = "__the-cave__/graphics/entity/uranium-caves/cave-entrance-2.png"

local prototypes = { entrance_1, entrance_2, exit_1, exit_2 }

-- Item transfer ports use the engine's LinkedBelt because it preserves lanes,
-- stack size, quality and exact Blue Belt throughput across surfaces while the
-- visible entity remains an underground-style fixed endpoint.
local linked_belt_table = data.raw["linked-belt"]
local linked_base = linked_belt_table and linked_belt_table["linked-belt"]
if not linked_base and linked_belt_table then
    local _, candidate = next(linked_belt_table)
    linked_base = candidate
end
assert(linked_base, "The Cave Uranium Cave requires Factorio's base linked-belt prototype")
local underground_base = data.raw["underground-belt"] and data.raw["underground-belt"]["express-underground-belt"]
local express_speed = underground_base and underground_base.speed
    or (data.raw["transport-belt"] and data.raw["transport-belt"]["express-transport-belt"] and data.raw["transport-belt"]["express-transport-belt"].speed)
    or 0.09375

local function make_item_port(name, localised_name, localised_description)
    local entity
    entity = table.deepcopy(linked_base)
    entity.name = name
    entity.localised_name = localised_name
    entity.localised_description = localised_description
    entity.icon = "__base__/graphics/icons/express-underground-belt.png"
    entity.icon_size = 64
    entity.flags = runtime_flags()
    entity.minable = nil
    entity.destructible = false
    entity.max_health = 1000
    entity.speed = express_speed
    entity.fast_replaceable_group = nil
    entity.next_upgrade = nil
    entity.allow_copy_paste = false
    entity.hidden_in_factoriopedia = true
    entity.is_military_target = false
    entity.alert_when_damaged = false
    entity.create_ghost_on_death = false
    entity.corpse = nil
    entity.dying_explosion = nil
    if entity.type == "linked-belt" then
        entity.allow_clone_connection = false
        entity.allow_blueprint_connection = false
        entity.allow_side_loading = true
    end
    return entity
end

local item_ports = {
    {
        "the-cave-uranium-item-down-input",
        { "entity-name.the-cave-uranium-item-down-input" },
        { "entity-description.the-cave-uranium-item-down-input" },
    },
    {
        "the-cave-uranium-item-down-output",
        { "entity-name.the-cave-uranium-item-down-output" },
        { "entity-description.the-cave-uranium-item-down-output" },
    },
    {
        "the-cave-uranium-item-up-input",
        { "entity-name.the-cave-uranium-item-up-input" },
        { "entity-description.the-cave-uranium-item-up-input" },
    },
    {
        "the-cave-uranium-item-up-output",
        { "entity-name.the-cave-uranium-item-up-output" },
        { "entity-description.the-cave-uranium-item-up-output" },
    },
}
for _, def in ipairs(item_ports) do
    local entity = make_item_port(def[1], def[2], def[3])
    if entity then prototypes[#prototypes + 1] = entity end
end

-- Deprecated fluid ports retained only to load old saves safely.
-- Runtime never creates or transfers through them; migration deletes tracked ports.
local pipe_base = data.raw["pipe-to-ground"] and data.raw["pipe-to-ground"]["pipe-to-ground"]
local function make_fluid_port(name, localised_name, localised_description)
    if not pipe_base then return nil end
    local entity = table.deepcopy(pipe_base)
    entity.name = name
    entity.localised_name = localised_name
    entity.localised_description = localised_description
    entity.icon = "__base__/graphics/icons/pipe-to-ground.png"
    entity.icon_size = 64
    entity.flags = runtime_flags()
    entity.minable = nil
    entity.destructible = false
    entity.max_health = 1000
    entity.fast_replaceable_group = nil
    entity.next_upgrade = nil
    entity.allow_copy_paste = false
    entity.hidden_in_factoriopedia = true
    entity.is_military_target = false
    entity.alert_when_damaged = false
    entity.create_ghost_on_death = false
    entity.corpse = nil
    entity.dying_explosion = nil
    -- Prevent these fixed ports from pairing with an ordinary nearby
    -- Pipe-to-ground through the same surface. The visible mouth still connects
    -- to a normal player pipe network on its exposed side.
    if entity.fluid_box and entity.fluid_box.pipe_connections then
        for _, connection in pairs(entity.fluid_box.pipe_connections) do
            if connection.max_underground_distance then
                connection.max_underground_distance = 1
            end
        end
    end
    return entity
end

local fluid_ports = {
    {
        "the-cave-uranium-fluid-down-input",
        { "entity-name.the-cave-uranium-fluid-down-input" },
        { "entity-description.the-cave-uranium-fluid-down-input" },
    },
    {
        "the-cave-uranium-fluid-down-output",
        { "entity-name.the-cave-uranium-fluid-down-output" },
        { "entity-description.the-cave-uranium-fluid-down-output" },
    },
    {
        "the-cave-uranium-fluid-up-input",
        { "entity-name.the-cave-uranium-fluid-up-input" },
        { "entity-description.the-cave-uranium-fluid-up-input" },
    },
    {
        "the-cave-uranium-fluid-up-output",
        { "entity-name.the-cave-uranium-fluid-up-output" },
        { "entity-description.the-cave-uranium-fluid-up-output" },
    },
}
for _, def in ipairs(fluid_ports) do
    local entity = make_fluid_port(def[1], def[2], def[3])
    if entity then prototypes[#prototypes + 1] = entity end
end

-- Legacy Uranium Cave bridge prototypes retained only so 2.5.56/2.5.57 test
-- saves can load and migrate safely. Runtime 2.5.58 destroys these old hidden
-- entities and directly joins the two visible Big Electric Poles with a scripted
-- cross-surface copper wire.
local empty_sprite = {
    filename = "__core__/graphics/empty.png",
    priority = "low",
    width = 1,
    height = 1,
    frame_count = 1,
    direction_count = 1,
}

local empty_pole_sprite = {
    filename = "__core__/graphics/empty.png",
    priority = "low",
    width = 1,
    height = 1,
    frame_count = 1,
    direction_count = 4,
}

local function make_hidden_power_pole()
    local base = data.raw["electric-pole"] and (data.raw["electric-pole"]["substation"] or data.raw["electric-pole"]["small-electric-pole"])
    if not base then return nil end
    local entity = table.deepcopy(base)
    entity.name = "the-cave-uranium-power-connector"
    entity.localised_name = { "entity-name.the-cave-uranium-power-bridge" }
    entity.localised_description = { "entity-description.the-cave-uranium-power-bridge" }
    entity.hidden = true
    entity.selectable_in_game = false
    entity.flags = {
        "placeable-neutral",
        "not-on-map",
        "not-blueprintable",
        "not-deconstructable",
        "not-flammable",
        "hide-alt-info",
    }
    entity.minable = nil
    entity.destructible = false
    entity.collision_box = { { 0, 0 }, { 0, 0 } }
    entity.selection_box = { { 0, 0 }, { 0, 0 } }
    entity.collision_mask = { layers = {} }
    entity.supply_area_distance = 3
    entity.maximum_wire_distance = 6
    entity.draw_copper_wires = false
    entity.draw_circuit_wires = false
    entity.pictures = empty_pole_sprite
    entity.radius_visualisation_picture = nil
    entity.water_reflection = nil
    return entity
end

local function make_hidden_power(name, mode)
    local base = data.raw.accumulator and data.raw.accumulator.accumulator
    if not base then return nil end
    local entity = table.deepcopy(base)
    entity.name = name
    entity.localised_name = { "entity-name.the-cave-uranium-power-bridge" }
    entity.localised_description = { "entity-description.the-cave-uranium-power-bridge" }
    entity.hidden = true
    entity.selectable_in_game = false
    entity.flags = {
        "placeable-neutral",
        "not-on-map",
        "not-blueprintable",
        "not-deconstructable",
        "not-flammable",
        "hide-alt-info",
    }
    entity.minable = nil
    entity.destructible = false
    entity.collision_box = { { 0, 0 }, { 0, 0 } }
    entity.selection_box = { { 0, 0 }, { 0, 0 } }
    entity.collision_mask = { layers = {} }
    entity.picture = empty_sprite
    entity.chargable_graphics = {
        picture = empty_sprite,
        charge_animation = empty_sprite,
        discharge_animation = empty_sprite,
    }
    entity.charge_animation = empty_sprite
    entity.discharge_animation = empty_sprite
    entity.charge_cooldown = 0
    entity.discharge_cooldown = 0
    entity.working_sound = nil
    entity.water_reflection = nil
    entity.energy_source = {
        type = "electric",
        buffer_capacity = "100MJ",
        input_flow_limit = mode == "input" and "10GW" or "0W",
        output_flow_limit = mode == "output" and "10GW" or "0W",
        usage_priority = mode == "output" and "primary-output" or "secondary-input",
        render_no_power_icon = false,
        render_no_network_icon = false,
    }
    return entity
end

local power_connector = make_hidden_power_pole()
local power_input = make_hidden_power("the-cave-uranium-power-input", "input")
local power_output = make_hidden_power("the-cave-uranium-power-output", "output")
if power_connector then prototypes[#prototypes + 1] = power_connector end
if power_input then prototypes[#prototypes + 1] = power_input end
if power_output then prototypes[#prototypes + 1] = power_output end

data:extend(prototypes)
