local path = ('__the-cave__/graphics/lost-city/old-abandoned-settlements')
local hit_effects = require("__base__.prototypes.entity.hit-effects")
local sounds = require("__base__.prototypes.entity.sounds")
local util = require('util')

data:extend({

    {
    type = "container",
    name = "the-cave-lost-city-house10-1",
    icon = path.."/icons/house10icon_1.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 3,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 75},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 25},
        {type = "item", name = "repair-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "engine-unit", amount_min = 0, amount_max = 1},
        {type = "item", name = "solid-fuel", amount_min = 0, amount_max = 50},
        {type = "item", name = "distractor-capsule", amount_min = 0, amount_max = 1},
        {type = "item", name = "defender-capsule", amount_min = 0, amount_max = 1}
      }
    },
    max_health = 200,
    corpse = "iron-chest-remnants",
    dying_explosion = "iron-chest-explosion",
    open_sound = sounds.metallic_chest_open,
    close_sound = sounds.metallic_chest_close,
    resistances =
    {
      {
        type = "fire",
        percent = 100
      },
      {
        type = "impact",
        percent = 100
      },
      {
        type = "explosion",
        percent = 100
      },
      {
        type = "acid",
        percent = 100
      },
      {
        type = "laser",
        percent = 100
      },
      {
        type = "physical",
        percent = 100
      },
      {
        type = "poison",
        percent = 100
      },
      {
        type = "electric",
        percent = 100
      }
    },
    collision_box = {{-3.5, -2.5}, {3.4, 3.7}},
    selection_box = {{-3.5, -3.2}, {3.4, 3.7}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house10/house10_1.png",
          priority = "extra-high",
          width = 640,
          height = 640,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house10/house10S_1.png",
          priority = "extra-high",
          width = 720,
          height = 640,
          shift = util.by_pixel(40, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house10-2",
    icon = path.."/icons/house10icon_2.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 3,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 75},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 25},
        {type = "item", name = "repair-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "engine-unit", amount_min = 0, amount_max = 1},
        {type = "item", name = "solid-fuel", amount_min = 0, amount_max = 50},
        {type = "item", name = "distractor-capsule", amount_min = 0, amount_max = 1},
        {type = "item", name = "defender-capsule", amount_min = 0, amount_max = 1}
      }
    },
    max_health = 200,
    corpse = "iron-chest-remnants",
    dying_explosion = "iron-chest-explosion",
    open_sound = sounds.metallic_chest_open,
    close_sound = sounds.metallic_chest_close,
    resistances =
    {
      {
        type = "fire",
        percent = 100
      },
      {
        type = "impact",
        percent = 100
      },
      {
        type = "explosion",
        percent = 100
      },
      {
        type = "acid",
        percent = 100
      },
      {
        type = "laser",
        percent = 100
      },
      {
        type = "physical",
        percent = 100
      },
      {
        type = "poison",
        percent = 100
      },
      {
        type = "electric",
        percent = 100
      }
    },
    collision_box = {{-4.1, -2.0}, {4, 3.3}},
    selection_box = {{-4.1, -3.0}, {4, 3.3}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house10/house10_2.png",
          priority = "extra-high",
          width = 640,
          height = 640,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house10/house10S_2.png",
          priority = "extra-high",
          width = 720,
          height = 640,
          shift = util.by_pixel(40, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house10-3",
    icon = path.."/icons/house10icon_3.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 3,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 75},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 25},
        {type = "item", name = "repair-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "engine-unit", amount_min = 0, amount_max = 1},
        {type = "item", name = "solid-fuel", amount_min = 0, amount_max = 50},
        {type = "item", name = "distractor-capsule", amount_min = 0, amount_max = 1},
        {type = "item", name = "defender-capsule", amount_min = 0, amount_max = 1}
      }
    },
    max_health = 200,
    corpse = "iron-chest-remnants",
    dying_explosion = "iron-chest-explosion",
    open_sound = sounds.metallic_chest_open,
    close_sound = sounds.metallic_chest_close,
    resistances =
    {
      {
        type = "fire",
        percent = 100
      },
      {
        type = "impact",
        percent = 100
      },
      {
        type = "explosion",
        percent = 100
      },
      {
        type = "acid",
        percent = 100
      },
      {
        type = "laser",
        percent = 100
      },
      {
        type = "physical",
        percent = 100
      },
      {
        type = "poison",
        percent = 100
      },
      {
        type = "electric",
        percent = 100
      }
    },
    collision_box = {{-3.4, -2.5}, {3.6, 3.7}},
    selection_box = {{-3.4, -3.4}, {3.6, 3.7}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house10/house10_3.png",
          priority = "extra-high",
          width = 640,
          height = 640,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house10/house10S_3.png",
          priority = "extra-high",
          width = 720,
          height = 640,
          shift = util.by_pixel(40, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house10-4",
    icon = path.."/icons/house10icon_4.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 3,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 75},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 75},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 25},
        {type = "item", name = "repair-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "engine-unit", amount_min = 0, amount_max = 1},
        {type = "item", name = "solid-fuel", amount_min = 0, amount_max = 50},
        {type = "item", name = "distractor-capsule", amount_min = 0, amount_max = 1},
        {type = "item", name = "defender-capsule", amount_min = 0, amount_max = 1}
      }
    },
    max_health = 200,
    corpse = "iron-chest-remnants",
    dying_explosion = "iron-chest-explosion",
    open_sound = sounds.metallic_chest_open,
    close_sound = sounds.metallic_chest_close,
    resistances =
    {
      {
        type = "fire",
        percent = 100
      },
      {
        type = "impact",
        percent = 100
      },
      {
        type = "explosion",
        percent = 100
      },
      {
        type = "acid",
        percent = 100
      },
      {
        type = "laser",
        percent = 100
      },
      {
        type = "physical",
        percent = 100
      },
      {
        type = "poison",
        percent = 100
      },
      {
        type = "electric",
        percent = 100
      }
    },
    collision_box = {{-4, -2.0}, {4.2, 3.2}},
    selection_box = {{-4, -3.0}, {4.2, 3.2}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house10/house10_4.png",
          priority = "extra-high",
          width = 640,
          height = 640,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house10/house10S_4.png",
          priority = "extra-high",
          width = 720,
          height = 640,
          shift = util.by_pixel(40, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
})