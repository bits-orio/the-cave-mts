local path = ('__the-cave__/graphics/lost-city/old-abandoned-settlements')
local hit_effects = require("__base__.prototypes.entity.hit-effects")
local sounds = require("__base__.prototypes.entity.sounds")
local util = require('util')
local decorative_trigger_effects = require("__base__.prototypes.decorative.decorative-trigger-effects")

data:extend({

  -----House 1-----  
  {
    type = "container",
    name = "the-cave-lost-city-house1-1",
    icon = path.."/icons/house1icon1.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 4,
      results =
      {
        {type = "item", name = "stone", amount_min = 20, amount_max = 100},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 30},
        {type = "item", name = "solar-panel", amount_min = 0, amount_max = 1},
        {type = "item", name = "repair-pack", amount_min = 1, amount_max = 20},
        {type = "item", name = "engine-unit", amount_min = 0, amount_max = 1},
        {type = "item", name = "solid-fuel", amount_min = 0, amount_max = 50},
        {type = "item", name = "distractor-capsule", amount_min = 0, amount_max = 1},
        {type = "item", name = "defender-capsule", amount_min = 0, amount_max = 1}
      }
    },
    max_health = 200,
    corpse = "iron-chest-remnants",
    dying_explosion = "iron-chest-explosion",
    dying_trigger_effect = decorative_trigger_effects.huge_rock(),
    open_sound = sounds.metallic_chest_open,
    close_sound = sounds.metallic_chest_close,
    mined_sound = sounds.deconstruct_bricks(1.0),
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
    collision_box = {{-6.8, -1.8}, {6.7, 6.2}},
    selection_box = {{-6.8, -2.3}, {6.7, 6.2}},
    damaged_trigger_effect = hit_effects.rock(),
    inventory_size = 1760,
    impact_category = "stone",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house1/house1_1.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house1/house1S_1.png",
          priority = "extra-high",
          width = 1616,
          height = 1616,
          shift = util.by_pixel(124, -11),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house1-3",
    icon = path.."/icons/house1icon3.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 4,
      results =
      {
        {type = "item", name = "stone", amount_min = 20, amount_max = 100},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 30},
        {type = "item", name = "solar-panel", amount_min = 0, amount_max = 1},
        {type = "item", name = "repair-pack", amount_min = 1, amount_max = 20},
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
    collision_box = {{-5.7, -2}, {4.9, 7.5}},
    selection_box = {{-5.7, -2.5}, {4.9, 7.5}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1760,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house1/house1_3.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house1/house1S_3.png",
          priority = "extra-high",
          width = 1616,
          height = 1616,
          shift = util.by_pixel(124, -11),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house1-5",
    icon = path.."/icons/house1icon5.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 4,
      results =
      {
        {type = "item", name = "stone", amount_min = 20, amount_max = 100},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 30},
        {type = "item", name = "solar-panel", amount_min = 0, amount_max = 1},
        {type = "item", name = "repair-pack", amount_min = 1, amount_max = 20},
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
    collision_box = {{-6.6, -1.5}, {6.6, 6.6}},
    selection_box = {{-6.6, -3}, {6.6, 6.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1760,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house1/house1_5.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house1/house1S_5.png",
          priority = "extra-high",
          width = 1616,
          height = 1616,
          shift = util.by_pixel(124, -11),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house1-7",
    icon = path.."/icons/house1icon7.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 4,
      results =
      {
        {type = "item", name = "stone", amount_min = 20, amount_max = 100},
        {type = "item", name = "iron-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-plate", amount_min = 10, amount_max = 100},
        {type = "item", name = "copper-cable", amount_min = 10, amount_max = 30},
        {type = "item", name = "solar-panel", amount_min = 0, amount_max = 1},
        {type = "item", name = "repair-pack", amount_min = 1, amount_max = 20},
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
    collision_box = {{-4.8, -2}, {5.7, 7.4}},
    selection_box = {{-4.8, -3.5}, {5.7, 7.4}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1760,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house1/house1_7.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house1/house1S_7.png",
          priority = "extra-high",
          width = 1616,
          height = 1616,
          shift = util.by_pixel(124, -11),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },

})