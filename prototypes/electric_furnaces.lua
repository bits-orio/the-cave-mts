-- The Cave integrated Electric Furnaces.
-- Adapted from Electric Furnaces 2.5.2 by GotLag.

if settings.startup["the-cave-electric-furnaces-stone-steel"].value == "enabled" then
  -- Electric Stone Furnace **************************************************************
  local electricstone = util.table.deepcopy(data.raw["furnace"]["stone-furnace"])
  electricstone.name = "electric-stone-furnace"
  electricstone.icon = "__the-cave__/graphics/icons/electric-stone-furnace.png"
  electricstone.minable.result = "electric-stone-furnace"
  electricstone.next_upgrade = "electric-steel-furnace"
---@diagnostic disable-next-line: undefined-field
  electricstone.working_sound.sound.filename = "__base__/sound/electric-furnace.ogg"
  electricstone.energy_usage = "90kW"
  electricstone.crafting_speed = 1
  electricstone.energy_source =
  {
    type = "electric",
    usage_priority = "secondary-input",
    emissions_per_minute = { pollution = 1 }
  }
  electricstone.graphics_set.animation.layers[1].filename = "__the-cave__/graphics/entity/electric-stone-furnace/electric-stone-furnace.png"
  electricstone.graphics_set.working_visualisations[1].effect = nil
  electricstone.graphics_set.working_visualisations[1].animation.layers[1] =
  {
    filename = "__the-cave__/graphics/entity/electric-stone-furnace/electric-stone-furnace-heater.png",
    priority = "extra-high",
    width = 16,
    height = 27,
    frame_count = 12,
    animation_speed = 0.5,
    draw_as_glow = true,
    shift = util.by_pixel(0.5, 18),
    scale = 0.5
  }
  electricstone.graphics_set.working_visualisations[1].animation.layers[2].repeat_count = 12
  electricstone.graphics_set.working_visualisations[2].effect = nil
  electricstone.graphics_set.working_visualisations[2].animation.repeat_count = 12

  -- Electric Steel Furnace **************************************************************
  local electricsteel = util.table.deepcopy(data.raw["furnace"]["steel-furnace"])
  electricsteel.name = "electric-steel-furnace"
  electricsteel.icon = "__the-cave__/graphics/icons/electric-steel-furnace.png"
  electricsteel.minable.result = "electric-steel-furnace"
---@diagnostic disable-next-line: undefined-field
  electricsteel.working_sound.sound.filename = "__base__/sound/electric-furnace.ogg"
  electricsteel.energy_usage = "180kW"
  electricsteel.crafting_speed = 2
  electricsteel.energy_source =
  {
    type = "electric",
    usage_priority = "secondary-input",
    emissions_per_minute = { pollution = 2 }
  }
  electricsteel.graphics_set.animation.layers[1].filename = "__the-cave__/graphics/entity/electric-steel-furnace/electric-steel-furnace.png"
  electricsteel.graphics_set.working_visualisations[1] =
  {
    fadeout = true,
    animation =
    {
      filename = "__the-cave__/graphics/entity/electric-steel-furnace/electric-steel-furnace-heater.png",
      priority = "high",
      width = 48,
      height = 20,
      frame_count = 12,
      draw_as_glow = true,
      shift = util.by_pixel(0, 20.5),
      scale = 0.5
    }
  }
  electricsteel.graphics_set.working_visualisations[2].effect = nil
  electricsteel.graphics_set.working_visualisations[3].effect = nil
  electricsteel.graphics_set.working_visualisations[4].effect = nil

  data:extend({
    electricstone,
    electricsteel
  })
end

if settings.startup["the-cave-electric-furnaces-advanced"].value == "enabled" then
  -- Electric Furnace 2 ******************************************************************
  local electric2 = util.table.deepcopy(data.raw["furnace"]["electric-furnace"])
  electric2.name = "electric-furnace-2"
  electric2.icon = "__the-cave__/graphics/icons/electric-furnace-2.png"
  electric2.minable.result = "electric-furnace-2"
  electric2.next_upgrade = "electric-furnace-3"
  electric2.module_slots = 2
  electric2.crafting_speed = 3
  electric2.energy_usage = "180kW"
  electric2.graphics_set.animation.layers[1].filename = "__the-cave__/graphics/entity/electric-furnace-2/electric-furnace-2.png"

  -- Electric Furnace 3 ******************************************************************
  local electric3 = util.table.deepcopy(data.raw["furnace"]["electric-furnace"])
  electric3.name = "electric-furnace-3"
  electric3.icon = "__the-cave__/graphics/icons/electric-furnace-3.png"
  electric3.minable.result = "electric-furnace-3"
  electric3.next_upgrade = nil
  electric3.module_slots = 4
  electric3.crafting_speed = 4
  electric3.energy_usage = "240kW"
  electric3.graphics_set.animation.layers[1].filename = "__the-cave__/graphics/entity/electric-furnace-3/electric-furnace-3.png"

  data:extend({
    electric2,
    electric3
  })
end

if settings.startup["the-cave-electric-furnaces-boiler"].value == "enabled" then
  -- Electric Boiler *********************************************************************
  local kettle = util.table.deepcopy(data.raw["boiler"]["boiler"])
  kettle.name = "electric-boiler"
  kettle.icon = "__the-cave__/graphics/icons/electric-boiler.png"
  kettle.minable.result = "electric-boiler"
  kettle.energy_consumption = "900kW"
  kettle.energy_source =
  {
    type = "electric",
    usage_priority = "secondary-input"
  }
  -- North sprite
  kettle.pictures.north.structure.layers[1].filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-N-idle.png"
  kettle.pictures.north.fire =
  {
    filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-N-fire.png",
    draw_as_glow = true,
    priority = "extra-high",
    frame_count = 1,
    width = 26,
    height = 26,
    shift = util.by_pixel(0, -8.5),
    scale = 0.5
  }
  kettle.pictures.north.fire_glow.filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-N-light.png"
  -- East sprite
  kettle.pictures.east.structure.layers[1].filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-E-idle.png"
  kettle.pictures.east.fire =
  {
    filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-E-fire.png",
    draw_as_glow = true,
    priority = "extra-high",
    frame_count = 1,
    width = 28,
    height = 28,
    shift = util.by_pixel(-9.5, -22),
    scale = 0.5
  }
  kettle.pictures.east.fire_glow.filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-E-light.png"
  -- South sprite
  kettle.pictures.south.structure.layers[1].filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-S-idle.png"
  kettle.pictures.south.fire =
  {
    filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-S-fire.png",
    draw_as_glow = true,
    priority = "extra-high",
    frame_count = 1,
    width = 26,
    height = 16,
    shift = util.by_pixel(-1, -26.5),
    scale = 0.5
  }
  kettle.pictures.south.fire_glow.filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-S-light.png"
  -- West sprite
  kettle.pictures.west.structure.layers[1].filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-W-idle.png"
  kettle.pictures.west.fire =
  {
    filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-W-fire.png",
    draw_as_glow = true,
    priority = "extra-high",
    frame_count = 1,
    width = 30,
    height = 29,
    shift = util.by_pixel(13, -23.25),
    scale = 0.5
  }
  kettle.pictures.west.fire_glow.filename = "__the-cave__/graphics/entity/electric-boiler/electric-boiler-W-light.png"
  kettle.fire_flicker_enabled = false
  kettle.fire_glow_flicker_enabled = false
  kettle.burning_cooldown = 10

  data:extend({
    kettle
  })
end
local item_sounds = require("__base__.prototypes.item_sounds")
local item_tints = require("__base__.prototypes.item-tints")

if settings.startup["the-cave-electric-furnaces-stone-steel"].value == "enabled" then
  local stone_icon = ""
  local steel_icon = ""
  
  if settings.startup["the-cave-electric-furnaces-distinct-icons"].value == "enabled" then
    stone_icon = "__the-cave__/graphics/icons/electric-stone-furnace-i.png"
    steel_icon = "__the-cave__/graphics/icons/electric-steel-furnace-i.png"
  else
    stone_icon = "__the-cave__/graphics/icons/electric-stone-furnace.png"
    steel_icon = "__the-cave__/graphics/icons/electric-steel-furnace.png"
  end

  data:extend({
    {
      type = "item",
      name = "electric-stone-furnace",
      icon = stone_icon,
      subgroup = "smelting-machine",
      order = "a[stone-furnace]b",
      place_result = "electric-stone-furnace",
      inventory_move_sound = item_sounds.brick_inventory_move,
      pick_sound = item_sounds.brick_inventory_pickup,
      drop_sound = item_sounds.brick_inventory_move,
      stack_size = 50
    },
    {
      type = "item",
      name = "electric-steel-furnace",
      icon = steel_icon,
      subgroup = "smelting-machine",
      order = "b[steel-furnace]b",
      inventory_move_sound = item_sounds.metal_large_inventory_move,
      pick_sound = item_sounds.metal_large_inventory_pickup,
      drop_sound = item_sounds.metal_large_inventory_move,
      place_result = "electric-steel-furnace",
      stack_size = 50
    }
  })
end

if settings.startup["the-cave-electric-furnaces-advanced"].value == "enabled" then
  data:extend({
    {
      type = "item",
      name = "electric-furnace-2",
      icon = "__the-cave__/graphics/icons/electric-furnace-2.png",
      subgroup = "smelting-machine",
      order = "c[electric-furnace]b",
      inventory_move_sound = item_sounds.electric_large_inventory_move,
      pick_sound = item_sounds.electric_large_inventory_pickup,
      drop_sound = item_sounds.electric_large_inventory_move,
      place_result = "electric-furnace-2",
      stack_size = 50,
      weight = 20*kg
    },
    {
      type = "item",
      name = "electric-furnace-3",
      icon = "__the-cave__/graphics/icons/electric-furnace-3.png",
      subgroup = "smelting-machine",
      order = "c[electric-furnace]c",
      inventory_move_sound = item_sounds.electric_large_inventory_move,
      pick_sound = item_sounds.electric_large_inventory_pickup,
      drop_sound = item_sounds.electric_large_inventory_move,
      place_result = "electric-furnace-3",
      stack_size = 50,
      weight = 20*kg
    }
  })
end

if settings.startup["the-cave-electric-furnaces-boiler"].value == "enabled" then
  data:extend({
    {
      type = "item",
      name = "electric-boiler",
      icon = "__the-cave__/graphics/icons/electric-boiler.png",
      subgroup = "energy",
      order = "b[steam-power]-a[boiler]b",
      inventory_move_sound = item_sounds.steam_inventory_move,
      pick_sound = item_sounds.steam_inventory_pickup,
      drop_sound = item_sounds.steam_inventory_move,
      place_result = "electric-boiler",
      stack_size = 50,
      random_tint_color = item_tints.iron_rust
    }
  })
end
if settings.startup["the-cave-electric-furnaces-stone-steel"].value == "enabled" then
  data:extend({
    {
      type = "recipe",
      name = "electric-stone-furnace",
      icon = "__the-cave__/graphics/icons/electric-stone-furnace-i.png",
      ingredients =
      {
        {type="item", name="stone-furnace", amount=1},
        {type="item", name="electronic-circuit", amount=1},
        {type="item", name="iron-plate", amount=1}
      },
      results = {{type="item", name="electric-stone-furnace", amount=1}},
      enabled = false
    },
    {
      type = "recipe",
      name = "electric-steel-furnace",
      icon = "__the-cave__/graphics/icons/electric-steel-furnace-i.png",
      ingredients = {
        {type="item", name="steel-furnace", amount=1},
        {type="item", name="electronic-circuit", amount=5},
        {type="item", name="iron-plate", amount=5}
      },
      results = {{type="item", name="electric-steel-furnace", amount=1}},
      energy_required = 3,
      enabled = false
    }
  })
end

if settings.startup["the-cave-electric-furnaces-advanced"].value == "enabled" then
  data:extend({
    {
      type = "recipe",
      name = "electric-furnace-2",
      ingredients =
      {
        {type="item", name="efficiency-module", amount=4},
        {type="item", name="electric-furnace", amount=1}
      },
      results = {{type="item", name="electric-furnace-2", amount=1}},
      energy_required = 5,
      enabled = false
    },
    {
      type = "recipe",
      name = "electric-furnace-3",
      ingredients =
      {
        {type="item", name="speed-module-2", amount=4},
        {type="item", name="electric-furnace-2", amount=1}
      },
      results ={{type="item", name="electric-furnace-3", amount=1}},
      energy_required = 5,
      enabled = false
    }
  })
end

if settings.startup["the-cave-electric-furnaces-boiler"].value == "enabled" then
  local kettlerecipe =
  {
    type = "recipe",
    name = "electric-boiler",
    icon = "__the-cave__/graphics/icons/electric-boiler-i.png",
    ingredients =
    {
      {type="item", name="boiler", amount=1},
      {type="item", name="electronic-circuit", amount=1},
      {type="item", name="iron-plate", amount=1}
    },
    results = {{type="item", name="electric-boiler", amount=1}},
    enabled = false
  }
  if settings.startup["the-cave-electric-furnaces-stone-steel"].value == "enabled" then
    kettlerecipe.ingredients =
    {
      {type="item", name="electric-stone-furnace", amount=1},
      {type="item", name="pipe", amount=4}
    }
  end
  data:extend({
    kettlerecipe
  })
end
if settings.startup["the-cave-electric-furnaces-stone-steel"].value == "enabled" then
  table.insert(data.raw.technology["electronics"].effects, {type = "unlock-recipe", recipe = "electric-stone-furnace"})
  table.insert(data.raw.technology["advanced-material-processing"].effects, {type = "unlock-recipe", recipe = "electric-steel-furnace"})
end

if settings.startup["the-cave-electric-furnaces-advanced"].value == "enabled" then
  data:extend({
    {
      type = "technology",
      name = "advanced-material-processing-3",
      icon = "__base__/graphics/technology/advanced-material-processing-2.png",
      icon_size = 256,
      effects =
      {
        {
          type = "unlock-recipe",
          recipe = "electric-furnace-2"
        }
      },
      prerequisites = {"advanced-material-processing-2", "efficiency-module", "production-science-pack"},
      unit =
      {
        count = 300,
        ingredients =
        {
          {"automation-science-pack", 1},
          {"logistic-science-pack", 1},
          {"chemical-science-pack", 1},
          {"production-science-pack", 1}
        },
        time = 30
      }
    },
    {
      type = "technology",
      name = "advanced-material-processing-4",
      icon = "__base__/graphics/technology/advanced-material-processing-2.png",
      icon_size = 256,
      effects =
      {
        {
          type = "unlock-recipe",
          recipe = "electric-furnace-3"
        }
      },
      prerequisites = {"advanced-material-processing-3", "speed-module-2", "utility-science-pack"},
      unit =
      {
        count = 450,
        ingredients =
        {
          {"automation-science-pack", 1},
          {"logistic-science-pack", 1},
          {"chemical-science-pack", 1},
          {"production-science-pack", 1},
          {"utility-science-pack", 1}
        },
        time = 30
      }
    }
  })
end

if settings.startup["the-cave-electric-furnaces-boiler"].value == "enabled" then
  table.insert(data.raw.technology["steam-power"].effects, {type = "unlock-recipe", recipe = "electric-boiler"})
end