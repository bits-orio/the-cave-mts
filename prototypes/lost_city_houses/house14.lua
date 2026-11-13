local path = ('__the-cave__/graphics/lost-city/old-abandoned-settlements')
local hit_effects = require("__base__.prototypes.entity.hit-effects")
local sounds = require("__base__.prototypes.entity.sounds")
local util = require('util')

data:extend({

    {
    type = "container",
    name = "the-cave-lost-city-house14-1",
    icon = path.."/icons/house14icon_1.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 1,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 50},
        {type = "item", name = "iron-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-cable", amount_min = 0, amount_max = 10},
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
    collision_box = {{-3, -1.3}, {3, 2.2}},
    selection_box = {{-3, -2.3}, {3, 2.2}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 256,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house14/house14_1.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house14/house14S_1.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(57, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house14-2",
    icon = path.."/icons/house14icon_2.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 1,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 50},
        {type = "item", name = "iron-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-cable", amount_min = 0, amount_max = 10},
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
    collision_box = {{-2.2, -2.2}, {2.2, 2.9}},
    selection_box = {{-2.2, -3.2}, {2.2, 2.9}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 256,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house14/house14_2.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house14/house14S_2.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(57, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house14-3",
    icon = path.."/icons/house14icon_3.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 1,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 50},
        {type = "item", name = "iron-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-cable", amount_min = 0, amount_max = 10},
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
    collision_box = {{-3, -1.3}, {3, 2.2}},
    selection_box = {{-3, -2.3}, {3, 2.2}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 256,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house14/house14_3.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house14/house14S_3.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(57, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
  {
    type = "container",
    name = "the-cave-lost-city-house14-4",
    icon = path.."/icons/house14icon_4.png",
    icon_size = 128,
    flags = {"placeable-neutral", "placeable-off-grid", "player-creation"},
    minable =
    {
      mining_particle = "stone-particle",
      mining_time = 1,
      results =
      {
        {type = "item", name = "stone", amount_min = 10, amount_max = 50},
        {type = "item", name = "iron-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-plate", amount_min = 5, amount_max = 50},
        {type = "item", name = "copper-cable", amount_min = 0, amount_max = 10},
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
    collision_box = {{-2.2, -2.2}, {2.2, 2.9}},
    selection_box = {{-2.2, -3.2}, {2.2, 2.9}},
    damaged_trigger_effect = hit_effects.entity(),
    inventory_size = 256,
    impact_category = "metal",
    icon_draw_specification = {scale = 0.7},
    picture =
    {
      layers =
      {
        {
          filename = path.."/entity/house14/house14_4.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(0, 0),
          scale = 0.5
        },
        {
          filename = path.."/entity/house14/house14S_4.png",
          priority = "extra-high",
          width = 460,
          height = 460,
          shift = util.by_pixel(57, 0),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
  },
})