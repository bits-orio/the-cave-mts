-- A dedicated assembler; the fixed recipe provides filtered native inventories.
-- Each offer is sold independently by scripts/coin_maker.lua, never by this
-- all-ingredients recipe. The original assemblers are not modified.
local NAME = "the-cave-coin-maker"
local RECIPE = NAME .. "-sales"
local offers = require("shared.market_sell_offers")
local ingredients = {}
for _, offer in ipairs(offers) do
    if data.raw.item[offer[1]] then
        ingredients[#ingredients + 1] = {type = "item", name = offer[1], amount = offer[2]}
    end
end
local gold = {r = 1, g = 0.78, b = 0.22, a = 1}
local icons = {
    {icon = "__base__/graphics/icons/assembling-machine-3.png", icon_size = 64, tint = gold},
    {icon = "__base__/graphics/icons/coin.png", icon_size = 64, scale = 0.25, shift = {8, 8}}
}
local machine = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-3"])
machine.name = NAME
machine.localised_name = {"entity-name." .. NAME}
machine.localised_description = {"entity-description." .. NAME}
machine.icon = nil
machine.icons = table.deepcopy(icons)
machine.minable = {mining_time = 0.2, result = NAME}
machine.placeable_by = {item = NAME, count = 1}
machine.next_upgrade = nil
machine.fast_replaceable_group = NAME
machine.fluid_boxes = nil
machine.crafting_categories = {NAME}
machine.fixed_recipe = RECIPE
machine.fixed_quality = "normal"
machine.disabled_when_recipe_not_researched = false
machine.crafting_speed = 1.25
machine.energy_usage = "1.5MW"
machine.energy_source = {
    type = "electric", usage_priority = "secondary-input", drain = "500kW",
    buffer_capacity = "1MJ", emissions_per_minute = {pollution = 2}
}
machine.module_slots = 4
machine.quality_affects_module_slots = false
machine.allowed_module_categories = {"speed", "efficiency"}
machine.allowed_effects = {"speed", "consumption", "pollution"}
machine.effect_receiver = {uses_module_effects = true, uses_beacon_effects = true,
    uses_surface_effects = false, uses_local_effects = false}
machine.ingredient_count = 255
machine.map_color = {r = 1, g = 0.72, b = 0.12}
local function tint_sprites(value)
    if type(value) ~= "table" then return end
    if (value.filename or value.filenames or value.stripes) and not value.draw_as_shadow then
        value.tint = table.deepcopy(gold)
    end
    for key, child in pairs(value) do
        if key ~= "tint" and type(child) == "table" then tint_sprites(child) end
    end
end
tint_sprites(machine.graphics_set)
local item = table.deepcopy(data.raw.item["assembling-machine-3"])
item.name = NAME
item.localised_name = {"item-name." .. NAME}
item.localised_description = {"entity-description." .. NAME}
item.icon = nil
item.icons = table.deepcopy(icons)
item.place_result = NAME
item.order = "c[assembling-machine-2]-a[coin-maker]"
data:extend({
    {type = "recipe-category", name = NAME}, machine, item,
    {
        type = "recipe", name = NAME, enabled = false, energy_required = 5,
        ingredients = {
            {type = "item", name = "steel-plate", amount = 50},
            {type = "item", name = "iron-gear-wheel", amount = 200},
            {type = "item", name = "electronic-circuit", amount = 50},
            {type = "item", name = "assembling-machine-2", amount = 1}
        },
        results = {{type = "item", name = NAME, amount = 1}}
    },
    {
        type = "recipe", name = RECIPE, localised_name = {"recipe-name." .. RECIPE},
        localised_description = {"entity-description." .. NAME},
        icon = "__base__/graphics/icons/coin.png", icon_size = 64,
        categories = {NAME}, enabled = true, hidden = true, hidden_in_factoriopedia = true,
        hide_from_player_crafting = true, energy_required = 2.5,
        ingredients = ingredients, results = {{type = "item", name = "coin", amount = 1}},
        allow_productivity = false, allow_quality = false, can_set_quality = false,
        allow_as_intermediate = false, allow_intermediates = false,
        allow_decomposition = false, auto_recycle = false
    },
    {
        type = "technology", name = NAME,
        localised_name = {"technology-name." .. NAME},
        localised_description = {"technology-description." .. NAME},
        icon = "__base__/graphics/icons/coin.png", icon_size = 64,
        prerequisites = {"automation-2"},
        effects = {{type = "unlock-recipe", recipe = NAME}},
        unit = {count = 500, time = 60,
            ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}}},
        order = "a-b-b-coin-maker"
    }
})
