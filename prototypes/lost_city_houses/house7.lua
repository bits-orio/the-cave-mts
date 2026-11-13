local path = ('__the-cave__/graphics/lost-city/old-abandoned-settlements')
local hit_effects = require("__base__.prototypes.entity.hit-effects")
local sounds = require("__base__.prototypes.entity.sounds")
local util = require('util')

data:extend({
    -----House 7-----
  
  {
    type = "container",
    name = "the-cave-lost-city-house7-1",
    icon = path.."/icons/house7icon1.png",
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
    collision_box = {{-4.1, -1.3}, {4.1, 4.6}},
    selection_box = {{-4.1, -2.0}, {4.1, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_1.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_1.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house7-2",
    icon = path.."/icons/house7icon2.png",
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
    collision_box = {{-4.1, -1.3}, {4.1, 4.6}},
    selection_box = {{-4.1, -2.0}, {4.1, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_2.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_2.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house7-3",
    icon = path.."/icons/house7icon3.png",
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
    collision_box = {{-4.3, -1.3}, {4.2, 4.6}},
    selection_box = {{-4.3, -2.0}, {4.2, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_3.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_3.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house7-4",
    icon = path.."/icons/house7icon4.png",
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
    collision_box = {{-4.1, -1.3}, {4.1, 4.6}},
    selection_box = {{-4.1, -2.0}, {4.1, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_4.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_4.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house7-5",
    icon = path.."/icons/house7icon5.png",
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
    collision_box = {{-4.1, -1.3}, {4.1, 4.6}},
    selection_box = {{-4.1, -2.0}, {4.1, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_5.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_5.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house7-6",
    icon = path.."/icons/house7icon6.png",
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
    collision_box = {{-4.1, -1.3}, {4.1, 4.6}},
    selection_box = {{-4.1, -2.0}, {4.1, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_6.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_6.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house7-7",
    icon = path.."/icons/house7icon7.png",
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
    collision_box = {{-4.3, -1.3}, {4.2, 4.6}},
    selection_box = {{-4.3, -2.0}, {4.2, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_7.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_7.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house7-8",
    icon = path.."/icons/house7icon8.png",
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
    collision_box = {{-4.1, -1.3}, {4.1, 4.6}},
    selection_box = {{-4.1, -2.0}, {4.1, 4.6}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 1024,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house7/house7_8.png",
          priority = "extra-high",
          width = 620,
          height = 650,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house7/house7S_8.png",
          priority = "extra-high",
          width = 780,
          height = 650,
          shift = util.by_pixel(0, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  }
})