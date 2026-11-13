-- The Cave Wind Turbine
-- One visible ElectricEnergyInterface entity with a research-controlled output.
-- The prototype's output limit is the final 2 MW ceiling; runtime changes only
-- the same placed entity's official power_production value.

local ENTITY_NAME = "the-cave-wind-turbine"
local ICON = "__the-cave__/graphics/icons/wind-turbine/wind-turbine.png"
local TECHNOLOGY_ICON = "__the-cave__/graphics/technology/wind-turbine/wind-turbine.png"
local setting = settings and settings.startup and settings.startup["the-cave-wind-turbine"]
local FEATURE_ENABLED = not setting or setting.value == "enabled" or setting.value == true

-- Define this prototype directly instead of cloning Factorio's base electric
-- energy interface. The base prototype owns an accumulator-style `picture`,
-- and ElectricEnergyInterfacePrototype loads that before `animation`.
-- Keeping this table independent guarantees that only The Cave's wind turbine
-- sprite sheet below can be rendered.
local entity = {
    type = "electric-energy-interface",
}

entity.name = ENTITY_NAME
entity.localised_name = { "entity-name." .. ENTITY_NAME }
entity.localised_description = { "entity-description." .. ENTITY_NAME }
entity.hidden = not FEATURE_ENABLED
entity.hidden_in_factoriopedia = not FEATURE_ENABLED
entity.icon = ICON
entity.icons = nil
entity.icon_size = 64
entity.flags = { "placeable-neutral", "player-creation", "not-rotatable" }
entity.minable = { mining_time = 1, result = ENTITY_NAME }
entity.max_health = 400
entity.corpse = "big-remnants"
entity.dying_explosion = "medium-explosion"
entity.resistances = {
    { type = "fire", percent = 20 },
    { type = "physical", percent = 20 },
    { type = "impact", percent = 30 },
}
entity.collision_box = { { -1.4, -1.4 }, { 1.4, 1.4 } }
entity.selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } }
entity.drawing_box_vertical_extension = 2.5
entity.is_military_target = true
entity.alert_when_damaged = true
entity.gui_mode = "none"
entity.energy_source = {
    type = "electric",
    buffer_capacity = "2MJ",
    input_flow_limit = "0W",
    output_flow_limit = "2MW",
    usage_priority = "primary-output",
    drain = "0W",
    render_no_power_icon = false,
    render_no_network_icon = false,
}
entity.energy_production = FEATURE_ENABLED and "1MW" or "0W"
entity.energy_usage = "0W"
entity.continuous_animation = true
entity.animation = {
    filename = "__the-cave__/graphics/entity/wind-turbine/wind-turbine.png",
    -- Four times the image resolution, at one quarter scale: the same
    -- 300x175 world-pixel canvas, ground anchor and existing-save footprint.
    width = 1200,
    height = 700,
    scale = 0.25,
    frame_count = 20,
    line_length = 5,
    animation_speed = 0.1,
    shift = { 2.48, -1.45 },
}
entity.map_color = { r = 0.55, g = 0.82, b = 0.95 }

local function science_ingredients(names)
    local result = {}
    for _, name in ipairs(names) do
        result[#result + 1] = { name, 1 }
    end
    return result
end

local technology_definitions = {
    {
        name = "the-cave-wind-turbine-1",
        prerequisites = { "steel-processing" },
        packs = { "automation-science-pack" },
        power = "1 MW",
        unlock_recipe = true,
    },
    {
        name = "the-cave-wind-turbine-2",
        prerequisites = { "the-cave-wind-turbine-1", "logistic-science-pack" },
        packs = { "automation-science-pack", "logistic-science-pack" },
        power = "1.5 MW",
    },
    {
        name = "the-cave-wind-turbine-3",
        prerequisites = { "the-cave-wind-turbine-2", "chemical-science-pack" },
        packs = {
            "automation-science-pack",
            "logistic-science-pack",
            "chemical-science-pack",
        },
        power = "2 MW",
    },
}

local prototypes = {
    {
        type = "item",
        name = ENTITY_NAME,
        localised_name = { "item-name." .. ENTITY_NAME },
        localised_description = { "item-description." .. ENTITY_NAME },
        icon = ICON,
        icon_size = 64,
        subgroup = "energy",
        order = "b[energy-production]-z[the-cave-wind-turbine]",
        place_result = ENTITY_NAME,
        stack_size = 20,
        hidden = not FEATURE_ENABLED,
        hidden_in_factoriopedia = not FEATURE_ENABLED,
    },
    {
        type = "recipe",
        name = ENTITY_NAME,
        localised_name = { "recipe-name." .. ENTITY_NAME },
        enabled = false,
        hidden = not FEATURE_ENABLED,
        hidden_in_factoriopedia = not FEATURE_ENABLED,
        energy_required = 10,
        ingredients = {
            { type = "item", name = "iron-gear-wheel", amount = 20 },
            { type = "item", name = "steel-plate", amount = 20 },
            { type = "item", name = "electronic-circuit", amount = 20 },
            { type = "item", name = "copper-plate", amount = 20 },
        },
        results = {
            { type = "item", name = ENTITY_NAME, amount = 1 },
        },
    },
    entity,
}

for level, definition in ipairs(technology_definitions) do
    local effects = {
        {
            type = "nothing",
            effect_description = {
                "technology-effect.the-cave-wind-turbine-output",
                definition.power,
            },
        },
    }
    if definition.unlock_recipe then
        effects[#effects + 1] = {
            type = "unlock-recipe",
            recipe = ENTITY_NAME,
        }
    end

    prototypes[#prototypes + 1] = {
        type = "technology",
        name = definition.name,
        localised_name = { "technology-name." .. definition.name },
        localised_description = { "technology-description." .. definition.name },
        icon = TECHNOLOGY_ICON,
        icon_size = 256,
        prerequisites = definition.prerequisites,
        effects = effects,
        enabled = FEATURE_ENABLED,
        hidden = not FEATURE_ENABLED,
        visible_when_disabled = false,
        unit = {
            count = 100,
            ingredients = science_ingredients(definition.packs),
            time = 30,
        },
        order = "c-e-wind-turbine-" .. tostring(level),
    }
end

data:extend(prototypes)
