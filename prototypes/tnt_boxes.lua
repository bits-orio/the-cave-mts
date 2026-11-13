local util = require("__core__/lualib/util")

local ICON_ROOT = "__the-cave__/graphics/tnt-boxes/icons/"
local ENTITY_ROOT = "__the-cave__/graphics/tnt-boxes/entities/"

local tiers = {
    {
        name = "the-cave-tnt-box-small",
        order = "a[small]",
        technology = "the-cave-tnt-box",
        technology_order = "a[small]",
        prerequisites = { "military-science-pack" },
        research_count = 100,
        explosives = 15,
        map_color = { r = 0.91, g = 0.72, b = 0.12, a = 1 },
    },
    {
        name = "the-cave-tnt-box-medium",
        order = "b[medium]",
        technology = "the-cave-tnt-box-medium",
        technology_order = "b[medium]",
        prerequisites = { "the-cave-tnt-box" },
        research_count = 300,
        explosives = 30,
        map_color = { r = 0.94, g = 0.39, b = 0.08, a = 1 },
    },
    {
        name = "the-cave-tnt-box-large",
        order = "c[large]",
        technology = "the-cave-tnt-box-large",
        technology_order = "c[large]",
        prerequisites = { "the-cave-tnt-box-medium" },
        research_count = 600,
        explosives = 60,
        map_color = { r = 0.86, g = 0.12, b = 0.10, a = 1 },
    },
}

local prototypes = {
    {
        type = "item-subgroup",
        name = "the-cave-tnt-boxes",
        group = "combat",
        -- A dedicated row immediately after vanilla's turret subgroup (order i)
        -- and before the hidden ammo-category subgroup (order j).
        order = "i-a[tnt-boxes]",
    },
}

for _, tier in ipairs(tiers) do
    local icon = ICON_ROOT .. tier.name .. ".png"
    local entity_sprite = ENTITY_ROOT .. tier.name .. ".png"
    local shadow_sprite = ENTITY_ROOT .. tier.name .. "-shadow.png"

    prototypes[#prototypes + 1] = {
        type = "item",
        name = tier.name,
        icon = icon,
        icon_size = 64,
        subgroup = "the-cave-tnt-boxes",
        order = tier.order,
        place_result = tier.name,
        stack_size = 5,
    }

    prototypes[#prototypes + 1] = {
        type = "simple-entity-with-owner",
        name = tier.name,
        icon = icon,
        icon_size = 64,
        flags = {
            "placeable-player",
            "player-creation",
            "not-blueprintable",
            "not-deconstructable",
            "not-flammable",
        },
        minable = { mining_time = 0.2, result = tier.name },
        max_health = 1000,
        destructible = false,
        is_military_target = false,
        alert_when_damaged = false,
        create_ghost_on_death = false,
        corpse = nil,
        dying_explosion = nil,
        collision_box = { { -0.9, -0.9 }, { 0.9, 0.9 } },
        selection_box = { { -1, -1 }, { 1, 1 } },
        tile_width = 2,
        tile_height = 2,
        drawing_box_vertical_extension = 1.0,
        remove_decoratives = "true",
        allow_copy_paste = false,
        map_color = tier.map_color,
        picture = {
            layers = {
                {
                    filename = entity_sprite,
                    priority = "extra-high",
                    width = 256,
                    height = 256,
                    shift = util.by_pixel(0, -12),
                    scale = 0.4,
                },
                {
                    filename = shadow_sprite,
                    priority = "extra-high",
                    width = 320,
                    height = 160,
                    -- Keep the contact shadow under the crate while leaving the
                    -- longer cast shadow visible to its lower-right.
                    shift = util.by_pixel(36, 23),
                    draw_as_shadow = true,
                    scale = 0.4,
                },
            },
        },
    }

    prototypes[#prototypes + 1] = {
        type = "recipe",
        name = tier.name,
        -- Characters have crafting and hand-crafting only. Advanced crafting
        -- keeps all three TNT recipes exclusive to assembling machines.
        categories = {"advanced-crafting"},
        enabled = false,
        energy_required = 30,
        ingredients = {
            { type = "item", name = "iron-chest", amount = 1 },
            { type = "item", name = "explosives", amount = tier.explosives },
        },
        results = { { type = "item", name = tier.name, amount = 1 } },
    }

    prototypes[#prototypes + 1] = {
        type = "technology",
        name = tier.technology,
        icon = "__the-cave__/graphics/tnt-boxes/technology/tnt-box.png",
        icon_size = 256,
        prerequisites = tier.prerequisites,
        effects = {
            { type = "unlock-recipe", recipe = tier.name },
        },
        unit = {
            count = tier.research_count,
            ingredients = {
                { "automation-science-pack", 1 },
                { "logistic-science-pack", 1 },
                { "military-science-pack", 1 },
            },
            time = 30,
        },
        order = "e-a[tnt-box]-" .. tier.technology_order,
    }
end

data:extend(prototypes)
