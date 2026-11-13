-- The Cave scrap salvage system.
--
-- Resource artwork is adapted from "Scrap Resource" 2.0.0 by RedRafe
-- under the MIT License.  See THIRD_PARTY_Scrap_Resource_MIT_LICENSE.txt and
-- THIRD_PARTY_Scrap_Resource_NOTICE.txt in the mod root.

local SCRAP_ITEM = "the-cave-scrap"
local SCRAP_RESOURCE = "the-cave-scrap-resource"
local SCRAP_RECIPE = "the-cave-scrap-sorting"
local ICON = "__the-cave__/graphics/entity/scrap-resource/icon-scrap.png"
local RESOURCE_SHEET = "__the-cave__/graphics/entity/scrap-resource/hd-scrap.png"

local iron = data.raw.resource and data.raw.resource["iron-ore"]
assert(iron, "The Cave scrap salvage requires the base iron-ore resource prototype")

-- Scrap is an ordinary solid resource, available to characters and basic drills
-- from the start of the game. Uranium keeps its own research and acid rules.
local scrap_resource = table.deepcopy(iron)
scrap_resource.name = SCRAP_RESOURCE
scrap_resource.localised_name = { "entity-name.the-cave-scrap-resource" }
scrap_resource.localised_description = { "entity-description.the-cave-scrap-resource" }
scrap_resource.icon = ICON
scrap_resource.icon_size = 64
scrap_resource.autoplace = nil
scrap_resource.order = "a-b-z[the-cave-scrap]"
scrap_resource.subgroup = "raw-resource"
scrap_resource.map_color = { r = 0.20, g = 0.20, b = 0.20, a = 1 }
scrap_resource.mining_visualisation_tint = { r = 0.34, g = 0.34, b = 0.34, a = 1 }
-- The Scrap Resource sheet has one variation. Do not inherit an ore overlay
-- whose variation count could differ from the replacement artwork.
scrap_resource.stages_effect = nil
scrap_resource.factoriopedia_simulation = nil
scrap_resource.stage_counts = { 1 }
scrap_resource.stages = {
    sheet = {
        filename = RESOURCE_SHEET,
        priority = "extra-high",
        size = 128,
        variation_count = 1,
        frame_count = 64,
        line_length = 8,
        scale = 0.5,
    },
}
scrap_resource.minable = table.deepcopy(iron.minable)
scrap_resource.minable.result = nil
scrap_resource.minable.results = {
    { type = "item", name = SCRAP_ITEM, amount = 10 },
}
-- Clear fluid requirements explicitly, including any added to iron by a mod.
scrap_resource.minable.required_fluid = nil
scrap_resource.minable.fluid_amount = nil

local scrap_item = {
    type = "item",
    name = SCRAP_ITEM,
    localised_name = { "item-name.the-cave-scrap" },
    localised_description = { "item-description.the-cave-scrap" },
    icon = ICON,
    icon_size = 64,
    subgroup = "raw-resource",
    order = "z[the-cave]-a[scrap]",
    stack_size = 100,
}

-- Independent result rolls.  Every successful roll returns 3-7 items.  The
-- common pool is intentionally capped while the advanced salvage has stronger
-- jackpot chances.  All listed products are available in Factorio Base Game
-- 2.0; the existence check also protects compatibility with overhaul mods that
-- remove or replace a vanilla item.
local requested_results = {
    { name = "plastic-bar",             probability = 0.30,  amount_min = 3, amount_max = 7 },
    { name = "sulfur",                  probability = 0.30,  amount_min = 3, amount_max = 7 },
    { name = "solid-fuel",              probability = 0.30,  amount_min = 3, amount_max = 7 },
    { name = "electronic-circuit",      probability = 0.30,  amount_min = 3, amount_max = 7 },
    { name = "battery",                 probability = 0.20,  amount_min = 3, amount_max = 7 },
    { name = "water-barrel",            probability = 0.12,  amount_min = 3, amount_max = 7 },
    { name = "engine-unit",             probability = 0.10,  amount_min = 3, amount_max = 7 },
    { name = "crude-oil-barrel",        probability = 0.09,  amount_min = 3, amount_max = 7 },
    { name = "petroleum-gas-barrel",    probability = 0.09,  amount_min = 3, amount_max = 7 },
    { name = "light-oil-barrel",        probability = 0.08,  amount_min = 3, amount_max = 7 },
    { name = "heavy-oil-barrel",        probability = 0.06,  amount_min = 3, amount_max = 7 },
    { name = "advanced-circuit",        probability = 0.06,  amount_min = 3, amount_max = 7 },
    { name = "lubricant-barrel",        probability = 0.08,  amount_min = 3, amount_max = 7 },
    { name = "electric-engine-unit",    probability = 0.08,  amount_min = 3, amount_max = 7 },
    { name = "rocket-fuel",             probability = 0.07,  amount_min = 3, amount_max = 7 },
    { name = "processing-unit",         probability = 0.065, amount_min = 3, amount_max = 7 },
    { name = "sulfuric-acid-barrel",    probability = 0.06,  amount_min = 3, amount_max = 7 },
    { name = "low-density-structure",   probability = 0.06,  amount_min = 3, amount_max = 7 },
    { name = "flying-robot-frame",      probability = 0.057, amount_min = 3, amount_max = 7 },
}

local results = {}
for _, product in ipairs(requested_results) do
    if data.raw.item and data.raw.item[product.name] then
        results[#results + 1] = {
            type = "item",
            name = product.name,
            amount = product.amount,
            amount_min = product.amount_min,
            amount_max = product.amount_max,
            independent_probability = product.probability,
        }
    end
end
assert(#results > 0, "The Cave scrap sorting has no valid Base Game output items")

local scrap_recipe = {
    type = "recipe",
    name = SCRAP_RECIPE,
    localised_name = { "recipe-name.the-cave-scrap-sorting" },
    localised_description = { "recipe-description.the-cave-scrap-sorting" },
    icon = ICON,
    icon_size = 64,
    categories = {"crafting"},
    subgroup = "intermediate-product",
    order = "z[the-cave]-a[scrap-sorting]",
    enabled = true,
    energy_required = 5,
    ingredients = {
        { type = "item", name = SCRAP_ITEM, amount = 10 },
    },
    results = results,
    main_product = "",
    hide_from_player_crafting = true,
    allow_as_intermediate = false,
    allow_intermediates = false,
    allow_decomposition = false,
    always_show_made_in = true,
    allow_productivity = false,
    allow_quality = true,
}

data:extend({ scrap_item, scrap_resource, scrap_recipe })
