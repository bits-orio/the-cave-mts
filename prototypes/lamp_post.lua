local hit_effects = require("__base__/prototypes/entity/hit-effects")
local item_sounds = require("__base__.prototypes.item_sounds")
local item_tints = require("__base__.prototypes.item-tints")

data.extend({
  {
    type = "lamp",
    name = "lamp-post",
    icon = "__the-cave__/graphics/icons/lamp-post.png",
    flags = {"placeable-neutral", "player-creation"},
    fast_replaceable_group = "lamp",
    minable = {mining_time = 0.1, result = "lamp-post"},
    max_health = 200,
    corpse = "lamp-post-remnants",
    dying_explosion = "lamp-explosion",
    collision_box = {{-0.15, -0.15}, {0.15, 0.15}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    damaged_trigger_effect = hit_effects.entity({{-0.2, -2},{0.2, 0.2}}),
    drawing_box_vertical_extension = 2,
    impact_category = "glass",
    open_sound = {filename = "__base__/sound/open-close/electric-small-open.ogg", volume = 0.7},
    close_sound = {filename = "__base__/sound/open-close/electric-small-close.ogg", volume = 0.7},
    energy_source =
    {
      type = "electric",
      usage_priority = "lamp"
    },
    energy_usage_per_tick = "20kW",
    darkness_for_all_lamps_on = 0.5,
    darkness_for_all_lamps_off = 0.3,
    light = {intensity = 0.95, size = 80, color = {1, 0.85, 1}},
    light_when_colored = {intensity = 0, size = 10, color = {1, 0.85, 1}},
    glow_size = 12,
    glow_color_intensity = 1,
    glow_render_mode = "multiplicative",
    picture_off =
    {
      layers =
      {
        {
          filename = "__the-cave__/graphics/entity/lamp-post/lamp-post.png",
          priority = "extra-high",
          width = 59,
          height = 178,
          shift = util.by_pixel(-2.25, -39.5),
          scale = 0.5
        },
        {
          filename = "__the-cave__/graphics/entity/lamp-post/lamp-post-shadow.png",
          priority = "extra-high",
          width = 237,
          height = 50,
          shift = util.by_pixel(52.75, -3),
          draw_as_shadow = true,
          scale = 0.5
        }
      }
    },
    picture_on =
    {
      layers = {
        {
          filename = "__the-cave__/graphics/entity/lamp-post/lamp-light.png",
          priority = "high",
          width = 90,
          height = 78,
          shift = util.by_pixel(1, -79),
          scale = 0.4
        },
      }
    },
    signal_to_color_mapping =
    {
      {type = "virtual", name = "signal-red",    color = {1, 0, 0}},
      {type = "virtual", name = "signal-green",  color = {0, 1, 0}},
      {type = "virtual", name = "signal-blue",   color = {0, 0, 1}},
      {type = "virtual", name = "signal-yellow", color = {1, 1, 0}},
      {type = "virtual", name = "signal-pink",   color = {1, 0, 1}},
      {type = "virtual", name = "signal-cyan",   color = {0, 1, 1}},
      {type = "virtual", name = "signal-white",  color = {1, 1, 1}},
      {type = "virtual", name = "signal-grey",   color = {0.5, 0.5, 0.5}},
      {type = "virtual", name = "signal-black",  color = {0, 0, 0}}
    },
    default_red_signal = { type = "virtual", name = "signal-red" },
    default_green_signal = { type = "virtual", name = "signal-green" },
    default_blue_signal = { type = "virtual", name = "signal-blue" },
    default_rgb_signal = { type = "virtual", name = "signal-white" },

    circuit_connector = circuit_connector_definitions["lamp"],
    circuit_wire_max_distance = default_circuit_wire_max_distance,
    water_reflection =
      {
        pictures =
        {
          filename = "__the-cave__/graphics/entity/lamp-post/lamp-post-reflection.png",
          priority = "extra-high",
          width = 12,
          height = 24,
          shift = util.by_pixel(0, 45),
          variation_count = 1,
          scale = 5
        },
        rotate = false,
        orientation_to_variation = false
      },
  },
  {
    type = "corpse",
    name = "lamp-post-remnants",
    localised_name = {"remnant-name", {"entity-name.small-lamp"}},
    icon = "__the-cave__/graphics/icons/lamp-post.png",
    hidden_in_factoriopedia = true,
    flags = {"placeable-neutral", "not-on-map"},
    subgroup = "circuit-network-remnants",
    order = "a-a-a",
    collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    tile_width = 1,
    tile_height = 1,
    selectable_in_game = false,
    time_before_removed = 60 * 60 * 15, -- 15 minutes
    expires = false,
    final_render_layer = "remnants",
    remove_on_tile_placement = false,
    animation = make_rotated_animation_variations_from_sheet (1,
    {
      filename = "__the-cave__/graphics/entity/lamp-post/remnants/lamp-post-remnants.png",
      line_length = 1,
      width = 102,
      height = 96,
      direction_count = 1,
      shift = util.by_pixel(-1, 3),
      scale = 0.5
    })
  },
  --------------- ITEM
  {
    type = "item",
    name = "lamp-post",
    localised_name = {"entity-name.lamp-post"},
    localised_description = {"entity-description.lamp-post"},
    icon = "__the-cave__/graphics/icons/lamp-post.png",
    subgroup = "circuit-network",
    order = "a[light]-a[small-lamp]-b",
    inventory_move_sound = item_sounds.electric_small_inventory_move,
    pick_sound = item_sounds.electric_small_inventory_pickup,
    drop_sound = item_sounds.electric_small_inventory_move,
    place_result = "lamp-post",
    stack_size = 50,
    weight = 5*kg,
  },
  --------------- RECIPE
  {
    type = "recipe",
    name = "lamp-post",
    categories = {"crafting"},
    enabled = false,
    energy_required = 4,
    ingredients =
    {
      {type = "item", name = "small-lamp", amount = 5},
      {type = "item", name = "steel-plate", amount = 1},
    },
    results = {{type="item", name="lamp-post", amount=1}},
    allow_productivity = true,
  },
  --------------- TECH
  {
    type = "technology",
    name = "lamp-post",
    localised_name = {"entity-name.lamp-post"},
    localised_description = {"entity-description.lamp-post"},
    icon = "__the-cave__/graphics/technology/lamp-post.png",
    icon_size = 256,
    effects =
    {
      {
        type = "unlock-recipe",
        recipe = "lamp-post"
      }
    },
    prerequisites = {"lamp"},
    unit =
    {
      count = 50,
      ingredients = {
          {"automation-science-pack", 1},
          {"logistic-science-pack", 1},
        },
      time = 30
    }
  }
})
