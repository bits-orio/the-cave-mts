-- Separate metal alternative to the vanilla small pole. Never mutate the
-- vanilla entity, item, recipe, graphics, remnants or explosion prototypes.
local util = require("util")
local name = "the-cave-small-metal-electric-pole"
local root = "__the-cave__/graphics/entity/small-metal-electric-pole/"
local icon = "__the-cave__/graphics/icons/small-metal-electric-pole.png"

local pole = util.table.deepcopy(data.raw["electric-pole"]["small-electric-pole"])
pole.name = name
pole.localised_name = {"entity-name." .. name}
pole.localised_description = {"entity-description." .. name}
pole.icon = icon
pole.icon_size = 64
pole.icons = nil
pole.minable.result = name
pole.corpse = name .. "-remnants"
pole.dying_explosion = name .. "-explosion"
pole.impact_category = "metal"
-- Fire protection applies only to this metal pole; keep inherited protection
-- against every other damage type and leave the vanilla pole unchanged.
pole.resistances = pole.resistances or {}
local has_fire_resistance = false
for _, resistance in pairs(pole.resistances) do
  if resistance.type == "fire" then
    resistance.percent = 100
    has_fire_resistance = true
  end
end
if not has_fire_resistance then
  pole.resistances[#pole.resistances + 1] = {type = "fire", percent = 100}
end
pole.flags = pole.flags or {}
local has_not_flammable = false
for _, flag in pairs(pole.flags) do
  if flag == "not-flammable" then has_not_flammable = true end
end
if not has_not_flammable then pole.flags[#pole.flags + 1] = "not-flammable" end
pole.pictures = {
  layers = {
    {
      filename = root .. "small-metal-electric-pole.png",
      priority = "extra-high",
      width = 72, height = 220, direction_count = 4,
      shift = util.by_pixel(1.5, -42.5), scale = 0.5,
    },
    {
      filename = root .. "small-metal-electric-pole-shadow.png",
      priority = "extra-high",
      width = 256, height = 52, direction_count = 4,
      shift = util.by_pixel(51, 3), scale = 0.5, draw_as_shadow = true,
    },
  },
}
pole.water_reflection = {
  pictures = {
    filename = root .. "small-metal-electric-pole-reflection.png",
    priority = "extra-high",
    width = 12, height = 28, variation_count = 4,
    shift = util.by_pixel(5, 40), scale = 5,
  },
  rotate = false,
  orientation_to_variation = true,
}

local item = util.table.deepcopy(data.raw.item["small-electric-pole"])
item.name = name
item.localised_name = {"entity-name." .. name}
item.localised_description = {"entity-description." .. name}
item.icon = icon
item.icon_size = 64
item.icons = nil
item.place_result = name
item.order = (item.order or "a[energy]-a[small-electric-pole]") .. "-b[metal]"

local recipe = util.table.deepcopy(data.raw.recipe["small-electric-pole"])
recipe.name = name
recipe.localised_name = {"entity-name." .. name}
recipe.localised_description = {"entity-description." .. name}
recipe.ingredients = {
  {type = "item", name = "iron-plate", amount = 1},
  {type = "item", name = "copper-cable", amount = 2},
}
recipe.results = {{type = "item", name = name, amount = 2}}
recipe.main_product = name

local remnants = util.table.deepcopy(data.raw.corpse["small-electric-pole-remnants"])
remnants.name = name .. "-remnants"
remnants.localised_name = {"entity-name." .. name .. "-remnants"}
remnants.icon = icon
remnants.icon_size = 64
remnants.icons = nil
remnants.animation = make_rotated_animation_variations_from_sheet(4, {
  layers = {{
    filename = root .. "small-metal-electric-pole-base-remnants.png",
    line_length = 1, width = 180, height = 106, direction_count = 1,
    shift = util.by_pixel(17, -1), scale = 0.5,
  }},
})
remnants.animation_overlay = make_rotated_animation_variations_from_sheet(4, {
  layers = {{
    filename = root .. "small-metal-electric-pole-top-remnants.png",
    line_length = 1, width = 86, height = 120, direction_count = 1,
    shift = util.by_pixel(3.5, -21.5), scale = 0.5,
  }},
})

local explosion = util.table.deepcopy(data.raw.explosion["small-electric-pole-explosion"])
explosion.name = name .. "-explosion"
explosion.icon = icon
explosion.icon_size = 64
explosion.icons = nil
-- Retain the original effect timing and count, but use metal debris.
local function metal_particles(node)
  if type(node) ~= "table" then return end
  if node.particle_name and string.find(node.particle_name, "wooden-splinter", 1, true) then
    node.particle_name = "small-electric-pole-metal-particle-small"
  end
  for _, value in pairs(node) do
    if type(value) == "table" then metal_particles(value) end
  end
end
metal_particles(explosion.created_effect)

local big_remnants = util.table.deepcopy(data.raw.corpse["small-electric-pole-remnants"])
big_remnants.name = "the-cave-basic-big-pole-remnants"
big_remnants.localised_name = {"entity-name.the-cave-basic-big-pole-remnants"}
big_remnants.icon = "__the-cave__/graphics/icons/big-wooden-pole.png"
big_remnants.icon_size = 32
big_remnants.icons = nil
big_remnants.animation = {{
  filename = "__the-cave__/graphics/entity/basic-big-pole/basic-big-pole-remnants.png",
  width = 180, height = 128, direction_count = 1,
  shift = util.by_pixel(18, -18), scale = 0.5,
}}
big_remnants.animation_overlay = nil
big_remnants.animation_overlay_final_render_layer = nil

data:extend({pole, item, recipe, remnants, explosion, big_remnants})

-- Unlock alongside the original pole. Existing researched saves are handled
-- by the narrowly scoped 3.1.98 migration; no global technology reset is used.
for _, technology in pairs(data.raw.technology) do
  local unlock = false
  for _, effect in pairs(technology.effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe == "small-electric-pole" then
      unlock = true
      break
    end
  end
  if unlock then
    technology.effects[#technology.effects + 1] = {type = "unlock-recipe", recipe = name}
  end
end
