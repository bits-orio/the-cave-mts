-- Reassert the agreed restrictions after the optional Everything Has Quality
-- pass. Only this new machine and its internal inventory recipe are affected.
local name = "the-cave-coin-maker"
local machine = data.raw["assembling-machine"][name]
machine.module_slots = 4
machine.quality_affects_module_slots = false
machine.allowed_module_categories = {"speed", "efficiency"}
machine.allowed_effects = {"speed", "consumption", "pollution"}
machine.effect_receiver = {uses_module_effects = true, uses_beacon_effects = true,
    uses_surface_effects = false, uses_local_effects = false}
local recipe = data.raw.recipe[name .. "-sales"]
recipe.allow_quality = false
recipe.allow_productivity = false
recipe.can_set_quality = false
-- Resolve optional sell items after all data-stage definitions are available.
recipe.ingredients = {}
for _, offer in ipairs(require("shared.market_sell_offers")) do
    if data.raw.item[offer[1]] then
        recipe.ingredients[#recipe.ingredients + 1] = {type = "item", name = offer[1], amount = offer[2]}
    end
end
