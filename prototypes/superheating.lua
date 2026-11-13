-- Integrated from Superheating 1.1.2 by GotLag.
-- Prototype names are intentionally preserved so saves can migrate cleanly
-- after disabling the standalone Superheating mod and enabling The Cave.
local item_sounds = require("__base__.prototypes.item_sounds")
local item_tints = require("__base__.prototypes.item-tints")

local function setting_enabled(name, fallback)
  local setting = settings and settings.startup and settings.startup[name]
  if not setting then return fallback ~= false end
  return setting.value == "enabled" or setting.value == true
end

if not setting_enabled("the-cave-superheating", true) then return end

local superheaters_enabled = setting_enabled("the-cave-superheating-superheaters", true)
local single_stage = setting_enabled("the-cave-superheating-single-stage", false)
local liquid_fuel_enabled = setting_enabled("the-cave-superheating-liquid-fuel", true)
local base_boiler = data.raw.boiler and data.raw.boiler.boiler

if not base_boiler then return end

local graphics_root = "__the-cave__/graphics/superheating/"
local effects = {}

local function add_unlock(recipe_name)
  if data.raw.recipe and data.raw.recipe[recipe_name] then
    effects[#effects + 1] = {type = "unlock-recipe", recipe = recipe_name}
  end
end

-- Solid-fuel superheater.
if superheaters_enabled then
  local superheater = util.table.deepcopy(base_boiler)
  superheater.name = "superheater"
  superheater.icon = graphics_root .. "icons/superheater.png"
  superheater.minable = superheater.minable or {mining_time = 0.2}
  superheater.minable.result = "superheater"
  superheater.fast_replaceable_group = "superheater"
  superheater.target_temperature = 465
  superheater.minimum_input_temperature = 165
  superheater.fluid_box.filter = "steam"
  superheater.energy_consumption = "3.6MW"
  superheater.energy_source.effectivity = 2
  superheater.pictures.north.structure.layers[1].filename = graphics_root .. "entity/superheater/boiler-N-idle.png"
  superheater.pictures.east.structure.layers[1].filename = graphics_root .. "entity/superheater/boiler-E-idle.png"
  superheater.pictures.south.structure.layers[1].filename = graphics_root .. "entity/superheater/boiler-S-idle.png"
  superheater.pictures.west.structure.layers[1].filename = graphics_root .. "entity/superheater/boiler-W-idle.png"

  if single_stage then
    superheater.fast_replaceable_group = "boiler"
    superheater.localised_description = {"entity-description.superheater-single-stage"}
    superheater.minimum_input_temperature = nil
    superheater.fluid_box.filter = "water"
    superheater.energy_consumption = "5.4MW"
    superheater.energy_source.effectivity = 1.5
  end

  data:extend({
    superheater,
    {
      type = "item",
      name = "superheater",
      icon = graphics_root .. "icons/superheater.png",
      subgroup = "energy",
      order = "b[steam-power]-a[boiler]a",
      inventory_move_sound = item_sounds.steam_inventory_move,
      pick_sound = item_sounds.steam_inventory_pickup,
      drop_sound = item_sounds.steam_inventory_move,
      place_result = "superheater",
      stack_size = 50,
      random_tint_color = item_tints.iron_rust
    },
    {
      type = "recipe",
      name = "superheater",
      icon = graphics_root .. "icons/superheater-i.png",
      energy_required = 1,
      enabled = false,
      ingredients = {
        {type = "item", name = "steel-furnace", amount = 1},
        {type = "item", name = "copper-plate", amount = 20},
        {type = "item", name = "pipe", amount = 4}
      },
      results = {{type = "item", name = "superheater", amount = 1}}
    }
  })
end

-- Liquid-fuel boiler.
if liquid_fuel_enabled then
  local oil_boiler = util.table.deepcopy(base_boiler)
  oil_boiler.name = "oil-boiler"
  oil_boiler.icon = graphics_root .. "icons/oil-boiler.png"
  oil_boiler.minable = oil_boiler.minable or {mining_time = 0.2}
  oil_boiler.minable.result = "oil-boiler"
  oil_boiler.energy_source = {
    type = "fluid",
    effectivity = 1,
    burns_fluid = true,
    scale_fluid_usage = true,
    fluid_box = {
      volume = 200,
      pipe_covers = pipecoverspictures(),
      pipe_connections = {
        {flow_direction = "input", direction = defines.direction.south, position = {0, 0.5}}
      },
      production_type = "input"
    },
    emissions_per_minute = {pollution = 30},
    light_flicker = {
      color = {0, 0, 0},
      minimum_intensity = 0.6,
      maximum_intensity = 0.95
    },
    smoke = {
      {
        name = "smoke",
        north_position = util.by_pixel(-38, -47.5),
        south_position = util.by_pixel(38.5, -32),
        east_position = util.by_pixel(20, -70),
        west_position = util.by_pixel(-19, -8.5),
        frequency = 15,
        starting_vertical_speed = 0.0,
        starting_frame_deviation = 60
      }
    }
  }
  oil_boiler.pictures.north.structure.layers[1].filename = graphics_root .. "entity/oil-boiler/boiler-N-idle.png"
  oil_boiler.pictures.east.structure.layers[1].filename = graphics_root .. "entity/oil-boiler/boiler-E-idle.png"
  oil_boiler.pictures.south.structure.layers[1].filename = graphics_root .. "entity/oil-boiler/boiler-S-idle.png"
  oil_boiler.pictures.west.structure.layers[1].filename = graphics_root .. "entity/oil-boiler/boiler-W-idle.png"

  data:extend({
    oil_boiler,
    {
      type = "item",
      name = "oil-boiler",
      icon = graphics_root .. "icons/oil-boiler.png",
      subgroup = "energy",
      order = "b[steam-power]-a[boiler]za",
      inventory_move_sound = item_sounds.steam_inventory_move,
      pick_sound = item_sounds.steam_inventory_pickup,
      drop_sound = item_sounds.steam_inventory_move,
      place_result = "oil-boiler",
      stack_size = 50,
      random_tint_color = item_tints.iron_rust
    },
    {
      type = "recipe",
      name = "oil-boiler",
      energy_required = 1,
      enabled = false,
      ingredients = {
        {type = "item", name = "boiler", amount = 1},
        {type = "item", name = "pump", amount = 1}
      },
      results = {{type = "item", name = "oil-boiler", amount = 1}}
    }
  })
end

-- Liquid-fuel superheater.
if superheaters_enabled and liquid_fuel_enabled then
  local oil_superheater = util.table.deepcopy(base_boiler)
  oil_superheater.name = "oil-superheater"
  oil_superheater.icon = graphics_root .. "icons/oil-superheater.png"
  oil_superheater.minable = oil_superheater.minable or {mining_time = 0.2}
  oil_superheater.minable.result = "oil-superheater"
  oil_superheater.fast_replaceable_group = "superheater"
  oil_superheater.target_temperature = 465
  oil_superheater.minimum_input_temperature = 165
  oil_superheater.fluid_box.filter = "steam"
  oil_superheater.energy_consumption = "3.6MW"
  oil_superheater.energy_source = {
    type = "fluid",
    effectivity = 2,
    burns_fluid = true,
    scale_fluid_usage = true,
    fluid_box = {
      volume = 200,
      pipe_covers = pipecoverspictures(),
      pipe_connections = {
        {flow_direction = "input", direction = defines.direction.south, position = {0, 0.5}}
      },
      production_type = "input"
    },
    emissions_per_minute = {pollution = 30},
    light_flicker = {
      color = {0, 0, 0},
      minimum_intensity = 0.6,
      maximum_intensity = 0.95
    },
    smoke = {
      {
        name = "smoke",
        north_position = util.by_pixel(-38, -47.5),
        south_position = util.by_pixel(38.5, -32),
        east_position = util.by_pixel(20, -70),
        west_position = util.by_pixel(-19, -8.5),
        frequency = 15,
        starting_vertical_speed = 0.0,
        starting_frame_deviation = 60
      }
    }
  }
  oil_superheater.pictures.north.structure.layers[1].filename = graphics_root .. "entity/oil-superheater/boiler-N-idle.png"
  oil_superheater.pictures.east.structure.layers[1].filename = graphics_root .. "entity/oil-superheater/boiler-E-idle.png"
  oil_superheater.pictures.south.structure.layers[1].filename = graphics_root .. "entity/oil-superheater/boiler-S-idle.png"
  oil_superheater.pictures.west.structure.layers[1].filename = graphics_root .. "entity/oil-superheater/boiler-W-idle.png"

  if single_stage then
    oil_superheater.fast_replaceable_group = "boiler"
    oil_superheater.localised_description = {"entity-description.oil-superheater-single-stage"}
    oil_superheater.minimum_input_temperature = nil
    oil_superheater.fluid_box.filter = "water"
    oil_superheater.energy_consumption = "5.4MW"
    oil_superheater.energy_source.effectivity = 1.5
  end

  data:extend({
    oil_superheater,
    {
      type = "item",
      name = "oil-superheater",
      icon = graphics_root .. "icons/oil-superheater.png",
      subgroup = "energy",
      order = "b[steam-power]-a[boiler]zb",
      inventory_move_sound = item_sounds.steam_inventory_move,
      pick_sound = item_sounds.steam_inventory_pickup,
      drop_sound = item_sounds.steam_inventory_move,
      place_result = "oil-superheater",
      stack_size = 50,
      random_tint_color = item_tints.iron_rust
    },
    {
      type = "recipe",
      name = "oil-superheater",
      icon = graphics_root .. "icons/oil-superheater-i.png",
      energy_required = 1,
      enabled = false,
      ingredients = {
        {type = "item", name = "superheater", amount = 1},
        {type = "item", name = "pump", amount = 1}
      },
      results = {{type = "item", name = "oil-superheater", amount = 1}}
    }
  })
end

-- Shared technology is only needed when at least one integrated machine exists.
if superheaters_enabled or liquid_fuel_enabled then
  data:extend({
    {
      type = "technology",
      name = "superheating",
      icon_size = 256,
      icon = graphics_root .. "technology/superheating.png",
      effects = effects,
      prerequisites = {"flammables", "advanced-material-processing"},
      unit = {
        count = 100,
        ingredients = {
          {"automation-science-pack", 1},
          {"logistic-science-pack", 1}
        },
        time = 30
      }
    }
  })

  if superheaters_enabled then
    add_unlock("steam-turbine")
    add_unlock("superheater")
  end
  if liquid_fuel_enabled then
    add_unlock("oil-boiler")
  end
  if superheaters_enabled and liquid_fuel_enabled then
    add_unlock("oil-superheater")
  end

  data.raw.technology["superheating"].effects = effects
end
