-- Industrial container family integrated into The Cave for Factorio 2.0.
-- Original container artwork created for The Cave.

local entity_path = "__the-cave__/graphics/entity/industrial-containers/"
local icon_path = "__the-cave__/graphics/icons/industrial-containers/"

local variants = {
  {key = "",       order = "a", logistic_mode = nil},
  {key = "filter", order = "b", filtered = true},
  {key = "red",    order = "c", logistic_mode = "passive-provider"},
  {key = "yellow", order = "d", logistic_mode = "storage", max_logistic_slots = 1},
  {key = "blue",   order = "e", logistic_mode = "requester", max_logistic_slots = 1000},
  {key = "green",  order = "f", logistic_mode = "buffer", max_logistic_slots = 1000},
  {key = "pink",   order = "g", logistic_mode = "active-provider"}
}

local function startup_capacity(name, fallback)
  local setting = settings and settings.startup and settings.startup[name]
  return setting and setting.value or fallback
end

-- Fit the visible body, including its lower base, inside the placement tiles
-- (32 pixels per tile). The transparent PNG canvas is not the body's size.
-- The same scale is used for the separate shadow and all seven variants.
local sizes = {
  {
    size = 1,
    label = "1x1",
    inventory_size = startup_capacity("the-cave-industrial-container-1x1-capacity", 200),
    image_size = 512,
    scale = 0.10,
    max_health = 350,
    item_stack_size = 50,
    crafting_time = 2
  },
  {
    size = 2,
    label = "2x2",
    inventory_size = startup_capacity("the-cave-industrial-container-2x2-capacity", 800),
    image_size = 512,
    scale = 0.14,
    max_health = 800,
    item_stack_size = 50,
    crafting_time = 2
  },
  {
    size = 4,
    label = "4x4",
    inventory_size = startup_capacity("the-cave-industrial-container-4x4-capacity", 1600),
    image_size = 1024,
    scale = 0.1575,
    max_health = 1600,
    item_stack_size = 20,
    crafting_time = 10
  },
  {
    size = 6,
    label = "6x6",
    inventory_size = startup_capacity("the-cave-industrial-container-6x6-capacity", 3000),
    image_size = 1024,
    scale = 0.20,
    max_health = 2500,
    item_stack_size = 10,
    crafting_time = 2
  }
}

local sizes_by_value = {}
for _, size in ipairs(sizes) do sizes_by_value[size.size] = size end

local steel_chest = data.raw.container["steel-chest"]
local logistic_chests = data.raw["logistic-container"]

local function suffix(key)
  return key == "" and "" or "_" .. key
end

local function prototype_name(size, key)
  return "the-cave-" .. size.label .. "-container" .. suffix(key)
end

local function source_logistic_chest(mode)
  local names = {
    ["passive-provider"] = "logistic-chest-passive-provider",
    ["active-provider"] = "logistic-chest-active-provider",
    storage = "logistic-chest-storage",
    requester = "logistic-chest-requester",
    buffer = "logistic-chest-buffer"
  }
  return mode and logistic_chests[names[mode]] or nil
end

local function ingredients_for(size, key)
  local definition = sizes_by_value[size]
  if size == 1 then
    if key == "" then
      return {{type = "item", name = "steel-plate", amount = 40}}
    elseif key == "filter" then
      return {
        {type = "item", name = prototype_name(definition, ""), amount = 1},
        {type = "item", name = "electronic-circuit", amount = 1}
      }
    end
    return {
      {type = "item", name = prototype_name(definition, ""), amount = 1},
      {type = "item", name = "electronic-circuit", amount = 3},
      {type = "item", name = "advanced-circuit", amount = 1}
    }
  elseif size == 2 then
    if key == "" then
      return {
        {type = "item", name = prototype_name(sizes_by_value[1], ""), amount = 4},
        {type = "item", name = "steel-plate", amount = 25}
      }
    elseif key == "filter" then
      return {
        {type = "item", name = prototype_name(definition, ""), amount = 1},
        {type = "item", name = "electronic-circuit", amount = 10}
      }
    end
    return {
      {type = "item", name = prototype_name(definition, ""), amount = 1},
      {type = "item", name = "electronic-circuit", amount = 10},
      {type = "item", name = "advanced-circuit", amount = 6},
      {type = "item", name = "steel-plate", amount = 5}
    }
  elseif size == 4 then
    if key == "" then
      return {
        {type = "item", name = prototype_name(sizes_by_value[2], ""), amount = 2},
        {type = "item", name = "steel-plate", amount = 80}
      }
    elseif key == "filter" then
      return {
        {type = "item", name = prototype_name(definition, ""), amount = 1},
        {type = "item", name = "electronic-circuit", amount = 15}
      }
    end
    return {
      {type = "item", name = prototype_name(definition, ""), amount = 1},
      {type = "item", name = "electronic-circuit", amount = 15},
      {type = "item", name = "advanced-circuit", amount = 8},
      {type = "item", name = "steel-plate", amount = 8}
    }
  end

  if key == "" then
    return {
      {type = "item", name = prototype_name(sizes_by_value[2], ""), amount = 4},
      {type = "item", name = "steel-plate", amount = 50},
      {type = "item", name = "stone-brick", amount = 25}
    }
  elseif key == "filter" then
    return {
      {type = "item", name = prototype_name(definition, ""), amount = 1},
      {type = "item", name = "electronic-circuit", amount = 20}
    }
  end
  return {
    {type = "item", name = prototype_name(definition, ""), amount = 1},
    {type = "item", name = "electronic-circuit", amount = 20},
    {type = "item", name = "advanced-circuit", amount = 10},
    {type = "item", name = "steel-plate", amount = 10}
  }
end

local prototypes = {
  {type = "item-subgroup", name = "the-cave-containers-1x1", group = "logistics", order = "a[storage]-z-a"},
  {type = "item-subgroup", name = "the-cave-containers-2x2", group = "logistics", order = "a[storage]-z-b"},
  {type = "item-subgroup", name = "the-cave-containers-4x4", group = "logistics", order = "a[storage]-z-c"},
  {type = "item-subgroup", name = "the-cave-containers-6x6", group = "logistics", order = "a[storage]-z-d"}
}

local basic_unlocks = {}
local early_logistic_unlocks = {}
local advanced_logistic_unlocks = {}
local early_logistic_modes = {
  ["passive-provider"] = true,
  storage = true
}

for _, size in ipairs(sizes) do
  for _, variant in ipairs(variants) do
    local key = variant.key
    local name = prototype_name(size, key)
    local image_suffix = suffix(key)
    local source = source_logistic_chest(variant.logistic_mode)

    local entity = {
      type = variant.logistic_mode and "logistic-container" or "container",
      name = name,
      icon = icon_path .. size.label .. "-container" .. image_suffix .. ".png",
      flags = {"placeable-neutral", "player-creation"},
      minable = {mining_time = 1, result = name},
      max_health = size.max_health,
      corpse = steel_chest.corpse,
      dying_explosion = steel_chest.dying_explosion,
      damaged_trigger_effect = steel_chest.damaged_trigger_effect,
      resistances = table.deepcopy(steel_chest.resistances),
      open_sound = table.deepcopy(steel_chest.open_sound),
      close_sound = table.deepcopy(steel_chest.close_sound),
      impact_category = steel_chest.impact_category,
      selection_box = {{-size.size / 2, -size.size / 2}, {size.size / 2, size.size / 2}},
      collision_box = {
        {-size.size / 2 + 0.15, -size.size / 2 + 0.15},
        {size.size / 2 - 0.15, size.size / 2 - 0.15}
      },
      tile_width = size.size,
      tile_height = size.size,
      inventory_size = size.inventory_size,
      inventory_type = variant.filtered and "with_filters_and_bar" or "with_bar",
      picture = {
        layers = {
          {
            filename = entity_path .. size.label .. "-container" .. image_suffix .. ".png",
            priority = "extra-high",
            width = size.image_size,
            height = size.image_size,
            scale = size.scale
          },
          {
            filename = entity_path .. size.label .. "-container_shadow.png",
            priority = "extra-high",
            width = size.image_size,
            height = size.image_size,
            scale = size.scale,
            draw_as_shadow = true
          }
        }
      },
      circuit_connector = table.deepcopy(steel_chest.circuit_connector),
      circuit_wire_max_distance = steel_chest.circuit_wire_max_distance,
      fast_replaceable_group = "the-cave-container-" .. size.label,
      scale_info_icons = true
    }

    if variant.logistic_mode then
      entity.logistic_mode = variant.logistic_mode
      entity.max_logistic_slots = variant.max_logistic_slots or (source and source.max_logistic_slots) or 0
      entity.render_not_in_network_icon = source and source.render_not_in_network_icon
      entity.open_sound = table.deepcopy(source and source.open_sound or entity.open_sound)
      entity.close_sound = table.deepcopy(source and source.close_sound or entity.close_sound)
    end

    local item = {
      type = "item",
      name = name,
      localised_name = {"entity-name." .. name},
      localised_description = {"entity-description.the-cave-industrial-container"},
      icon = icon_path .. size.label .. "-container" .. image_suffix .. ".png",
      subgroup = "the-cave-containers-" .. size.label,
      order = variant.order,
      place_result = name,
      stack_size = size.item_stack_size
    }

    local recipe = {
      type = "recipe",
      name = name,
      enabled = false,
      energy_required = size.crafting_time,
      ingredients = ingredients_for(size.size, key),
      results = {{type = "item", name = name, amount = 1}}
    }

    prototypes[#prototypes + 1] = entity
    prototypes[#prototypes + 1] = item
    prototypes[#prototypes + 1] = recipe

    local unlock = {type = "unlock-recipe", recipe = name}
    if variant.logistic_mode then
      if early_logistic_modes[variant.logistic_mode] then
        early_logistic_unlocks[#early_logistic_unlocks + 1] = unlock
      else
        advanced_logistic_unlocks[#advanced_logistic_unlocks + 1] = unlock
      end
    else
      basic_unlocks[#basic_unlocks + 1] = unlock
    end
  end
end

prototypes[#prototypes + 1] = {
  type = "technology",
  name = "the-cave-industrial-containers",
  icon = icon_path .. "2x2-container.png",
  icon_size = 64,
  prerequisites = {"steel-processing"},
  effects = basic_unlocks,
  unit = {
    count = 100,
    ingredients = {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1}
    },
    time = 30
  },
  order = "a-a-c"
}

prototypes[#prototypes + 1] = {
  type = "technology",
  name = "the-cave-logistic-containers",
  icon = icon_path .. "2x2-container_red.png",
  icon_size = 64,
  prerequisites = {"the-cave-industrial-containers", "logistic-robotics"},
  effects = early_logistic_unlocks,
  unit = {
    count = 250,
    ingredients = {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1}
    },
    time = 30
  },
  order = "a-a-d"
}

data:extend(prototypes)

-- Preserve Factorio's intended logistic progression. Passive Provider and
-- Storage variants belong to the early Logistic Robotics tier above, while
-- Requester, Buffer and Active Provider variants inherit the native Logistic
-- System gate. Factorio itself changes that gate from Utility science in the
-- base game to Space science when Space Age is active.
local logistic_system = data.raw.technology["logistic-system"]
if logistic_system then
  logistic_system.effects = logistic_system.effects or {}
  for _, unlock in ipairs(advanced_logistic_unlocks) do
    logistic_system.effects[#logistic_system.effects + 1] = unlock
  end
end
