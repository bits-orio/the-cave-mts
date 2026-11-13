-- The Cave industrial loaders for Factorio 2.0.
-- Original concept: Exotic Industries: Loaders by PreLeyZero.
-- Replacement housing artwork: The Cave's approved industrial design.

local entity_path = "__the-cave__/graphics/entity/industrial-loaders/"
local icon_path = "__the-cave__/graphics/icons/industrial-loaders/"

local tiers = {
  {
    key = "standard",
    entity_name = "the-cave-loader",
    graphic = "loader",
    belt = "transport-belt",
    technology = "the-cave-loader-technology",
    prerequisites = {"logistics"},
    count = 75,
    science = {{"automation-science-pack", 1}},
    ingredients = {
      {type = "item", name = "transport-belt", amount = 4},
      {type = "item", name = "electronic-circuit", amount = 6},
      {type = "item", name = "iron-plate", amount = 6}
    }
  },
  {
    key = "fast",
    entity_name = "the-cave-fast-loader",
    graphic = "fast-loader",
    belt = "fast-transport-belt",
    technology = "the-cave-fast-loader-technology",
    prerequisites = {"the-cave-loader-technology", "logistics-2"},
    count = 150,
    science = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}},
    ingredients = {
      {type = "item", name = "the-cave-loader", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 20},
      {type = "item", name = "iron-gear-wheel", amount = 20}
    }
  },
  {
    key = "express",
    entity_name = "the-cave-express-loader",
    graphic = "express-loader",
    belt = "express-transport-belt",
    technology = "the-cave-express-loader-technology",
    prerequisites = {"the-cave-fast-loader-technology", "logistics-3"},
    count = 250,
    science = {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1}
    },
    ingredients = {
      {type = "item", name = "the-cave-fast-loader", amount = 1},
      {type = "item", name = "advanced-circuit", amount = 20},
      {type = "item", name = "iron-gear-wheel", amount = 40}
    }
  }
}

if data.raw["transport-belt"]["turbo-transport-belt"] then
  tiers[#tiers + 1] = {
    key = "turbo",
    entity_name = "the-cave-turbo-loader",
    graphic = "neo-loader",
    belt = "turbo-transport-belt",
    technology = "the-cave-turbo-loader-technology",
    prerequisites = {"the-cave-express-loader-technology", "turbo-transport-belt"},
    count = 500,
    science = {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
      {"production-science-pack", 1},
      {"metallurgic-science-pack", 1}
    },
    ingredients = {
      {type = "item", name = "the-cave-express-loader", amount = 1},
      {type = "item", name = "turbo-transport-belt", amount = 4},
      {type = "item", name = "processing-unit", amount = 12},
      {type = "item", name = "tungsten-plate", amount = 4}
    }
  }
end

local prototypes = {}
local item_sounds = require("__base__.prototypes.item_sounds")

local function make_structure(graphic)
  local filename = entity_path .. graphic .. ".png"
  return {
    direction_in = {
      sheet = {
        filename = filename,
        priority = "extra-high",
        shift = {0.15625, 0.0703125},
        width = 212,
        height = 170,
        y = 170,
        scale = 0.25
      }
    },
    direction_out = {
      sheet = {
        filename = filename,
        priority = "extra-high",
        shift = {0.15625, 0.0703125},
        width = 212,
        height = 170,
        scale = 0.25
      }
    }
  }
end

for index, tier in ipairs(tiers) do
  local belt = data.raw["transport-belt"][tier.belt]
  if not belt then
    error("[The Cave] Industrial Loader is missing required belt prototype '" .. tier.belt .. "'.")
  end

  local next_tier = tiers[index + 1]
  local entity = {
    type = "loader-1x1",
    name = tier.entity_name,
    localised_description = {"entity-description.the-cave-industrial-loader"},
    icon = icon_path .. tier.graphic .. ".png",
    -- Factorio 2.0 EntityPrototypeFlags only. Never copy legacy flags from the
    -- original 1.1 mod without checking them against the current prototype API.
    flags = {"placeable-neutral", "player-creation"},
    minable = {mining_time = 0.2, result = tier.entity_name},
    max_health = 300 + ((index - 1) * 100),
    corpse = "small-remnants",
    dying_explosion = "transport-belt-explosion",
    collision_box = {{-0.4, -0.45}, {0.4, 0.45}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    animation_speed_coefficient = 32,
    belt_animation_set = table.deepcopy(belt.belt_animation_set),
    container_distance = 0.75,
    -- Factorio 2.0.77 requires a positive internal transport-line range for
    -- loader-1x1 entities. Zero loads but later crashes checkConsistency.
    belt_length = 0.5,
    fast_replaceable_group = "the-cave-industrial-loader",
    next_upgrade = next_tier and next_tier.entity_name or nil,
    -- Factorio requires exactly two filters when each belt lane is filtered
    -- independently. An empty lane filter leaves that lane blocked.
    filter_count = 2,
    per_lane_filters = true,
    speed = belt.speed,
    structure = make_structure(tier.graphic),
    allow_container_interaction = true,
    allow_rail_interaction = true,
    -- The Cave's final-fixes pass raises this prototype cap to 20 whenever
    -- Early Stack Size is enabled. Starting at 1 keeps the disabled setting
    -- and non-Space-Age validation paths strictly vanilla-safe.
    max_belt_stack_size = 1,
    wait_for_full_stack = false,
    respect_insert_limits = true
  }

  local item = {
    type = "item",
    name = tier.entity_name,
    localised_name = {"entity-name." .. tier.entity_name},
    localised_description = {"entity-description.the-cave-industrial-loader"},
    icon = icon_path .. tier.graphic .. ".png",
    subgroup = "belt",
    order = "h[the-cave-loader]-" .. string.format("%02d", index),
    inventory_move_sound = item_sounds.mechanical_inventory_move,
    pick_sound = item_sounds.mechanical_inventory_pickup,
    drop_sound = item_sounds.mechanical_inventory_move,
    place_result = tier.entity_name,
    stack_size = 50
  }

  local recipe = {
    type = "recipe",
    name = tier.entity_name,
    enabled = false,
    energy_required = index + 1,
    ingredients = tier.ingredients,
    results = {{type = "item", name = tier.entity_name, amount = 1}}
  }

  local technology = {
    type = "technology",
    name = tier.technology,
    icon = icon_path .. tier.graphic .. ".png",
    icon_size = 64,
    prerequisites = tier.prerequisites,
    effects = {{type = "unlock-recipe", recipe = tier.entity_name}},
    unit = {count = tier.count, ingredients = tier.science, time = 30},
    upgrade = index > 1,
    order = "a-a-e-loader-" .. string.format("%02d", index)
  }

  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
  prototypes[#prototypes + 1] = technology
end

data:extend(prototypes)
