-- The visible pole owns placement, wires, mining and wreckage. Its paired
-- native lamp owns real network consumption and power-dependent lighting.
local name = "the-cave-lamp-pole"
local icon = "__the-cave__/graphics/icons/lamp-pole.png"
local graphic = "__the-cave__/graphics/entity/lamp-pole/"

local pole = table.deepcopy(data.raw["electric-pole"]["the-cave-big-wooden-pole"])
pole.name = name
pole.localised_name = {"entity-name." .. name}
pole.localised_description = {"entity-description." .. name}
pole.icon = icon
pole.icon_size = 64
pole.minable.result = name
pole.corpse = name .. "-remnants"
pole.maximum_wire_distance = 32
pole.supply_area_distance = 3.5
local lamp_head = table.deepcopy(pole.pictures)
lamp_head.filename = graphic .. "lamp-pole-head.png"
pole.pictures = {layers = {pole.pictures, lamp_head}}
pole.fast_replaceable_group = data.raw["electric-pole"]["medium-electric-pole"].fast_replaceable_group or "electric-pole"
pole.created_effect = {
  type = "direct",
  action_delivery = {
    type = "instant",
    source_effects = {{type = "script", effect_id = name .. "-created"}},
  },
}

local item = table.deepcopy(data.raw.item["the-cave-big-wooden-pole"])
item.name = name
item.localised_name = pole.localised_name
item.localised_description = pole.localised_description
item.icon = icon
item.icon_size = 64
item.place_result = name
item.order = "a[energy]-a[big-wooden-pole]-b[lamp-pole]"
item.fuel_value = nil
item.fuel_categories = nil

local recipe = table.deepcopy(data.raw.recipe["lamp-post"])
recipe.name = name
recipe.localised_name = pole.localised_name
recipe.ingredients = {
  {type = "item", name = "steel-plate", amount = 1},
  {type = "item", name = "small-lamp", amount = 5},
  {type = "item", name = "copper-cable", amount = 4},
  {type = "item", name = "iron-plate", amount = 2},
}
recipe.results = {{type = "item", name = name, amount = 1}}

local remnants = table.deepcopy(data.raw.corpse["the-cave-basic-big-pole-remnants"])
remnants.name = name .. "-remnants"
remnants.localised_name = {"remnant-name", pole.localised_name}
remnants.icon = icon
remnants.icon_size = 64
remnants.animation[1].filename = graphic .. "lamp-pole-remnants.png"

local lamp = table.deepcopy(data.raw.lamp["lamp-post"])
lamp.name = name .. "-light"
lamp.localised_name = pole.localised_name
lamp.localised_description = pole.localised_description
lamp.icon = icon
lamp.icon_size = 64
lamp.hidden = true
lamp.hidden_in_factoriopedia = true
lamp.selectable_in_game = false
lamp.flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", "not-upgradable", "not-flammable", "not-repairable", "hide-alt-info", "not-in-kill-statistics"}
lamp.allow_copy_paste = false
lamp.collision_mask = {layers = {}}
lamp.collision_box = {{0, 0}, {0, 0}}
lamp.selection_box = {{0, 0}, {0, 0}}
lamp.minable = nil
lamp.corpse = nil
lamp.dying_explosion = nil
lamp.damaged_trigger_effect = nil
lamp.fast_replaceable_group = nil
lamp.next_upgrade = nil
lamp.water_reflection = nil
lamp.circuit_connector = nil
lamp.circuit_wire_max_distance = 0
lamp.draw_circuit_wires = false
lamp.draw_copper_wires = false
lamp.energy_usage_per_tick = "20kW"
lamp.energy_source.render_no_power_icon = false
lamp.energy_source.render_no_network_icon = false
lamp.drawing_box_vertical_extension = 5
lamp.picture_off = {filename = "__core__/graphics/empty.png", width = 1, height = 1}
lamp.picture_on = {
  filename = "__the-cave__/graphics/entity/lamp-post/lamp-light.png",
  priority = "extra-high",
  width = 90,
  height = 78,
  scale = 0.24,
  shift = util.by_pixel(-1.6, -154.5),
}

data:extend({pole, item, recipe, remnants, lamp})
table.insert(data.raw.technology["lamp-post"].effects, {type = "unlock-recipe", recipe = name})
