local path = ('__the-cave__/graphics/lost-city/old-abandoned-settlements')
local hit_effects = require("__base__.prototypes.entity.hit-effects")
local sounds = require("__base__.prototypes.entity.sounds")
local util = require('util')

data:extend({

    {
    type = "container",
    name = "the-cave-lost-city-house3-1",
    icon = path.."/icons/house3icon1.png",
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
        {type = "item", name = "automation-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "logistic-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "chemical-science-pack", amount_min = 0, amount_max = 10},
        {type = "item", name = "military-science-pack", amount_min = 0, amount_max = 10},
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
    collision_box = {{-5, -1.6}, {5.3, 6.7}},
    selection_box = {{-5, -3.6}, {5.3, 6.7}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1760,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house3/house3_1.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house3/house3S_1.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(42, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house3-3",
    icon = path.."/icons/house3icon3.png",
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
        {type = "item", name = "automation-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "logistic-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "chemical-science-pack", amount_min = 0, amount_max = 10},
        {type = "item", name = "military-science-pack", amount_min = 0, amount_max = 10},
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
    collision_box = {{-6.2, -2}, {7.5, 5}},
    selection_box = {{-6.2, -3.5}, {7.5, 5}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1760,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house3/house3_3.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house3/house3S_3.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(42, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house3-5",
    icon = path.."/icons/house3icon5.png",
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
        {type = "item", name = "automation-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "logistic-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "chemical-science-pack", amount_min = 0, amount_max = 10},
        {type = "item", name = "military-science-pack", amount_min = 0, amount_max = 10},
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
    collision_box = {{-5.3, -4}, {5.0, 5.8}},
    selection_box = {{-5.3, -5}, {5.0, 5.8}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1760,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house3/house3_5.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house3/house3S_5.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(42, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house3-7",
    icon = path.."/icons/house3icon7.png",
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
        {type = "item", name = "automation-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "logistic-science-pack", amount_min = 0, amount_max = 20},
        {type = "item", name = "chemical-science-pack", amount_min = 0, amount_max = 10},
        {type = "item", name = "military-science-pack", amount_min = 0, amount_max = 10},
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
    collision_box = {{-7.5, -2}, {6.2, 5}},
    selection_box = {{-7.5, -3}, {6.2, 5}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1760,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house3/house3_7.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house3/house3S_7.png",
          priority = "extra-high",
          width = 1188,
          height = 1188,
          shift = util.by_pixel(42, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
})