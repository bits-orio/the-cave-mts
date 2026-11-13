-- Separate craftable Cave Accumulators. Vanilla and market MK prototypes remain
-- unchanged. The engine owns energy storage, quality and charge/discharge state.
local base_entity = data.raw.accumulator and data.raw.accumulator.accumulator
local base_item = data.raw.item and data.raw.item.accumulator
local technology = data.raw.technology["electric-energy-accumulators"]
local large_graphics = require("shared.cave_accumulator_graphics")
local column_effects = require("prototypes.cave_accumulator_column_effects")
if not (base_entity and base_item and technology) then
  error("[The Cave] Cave Accumulators require the vanilla accumulator and its research.")
end

local definitions = {
  {name = "the-cave-accumulator-3x3", size = 3, capacity = "50MJ", flow = "3MW", plug_y = 1.03125,
    craft_time = 20, batteries = 50, steel = 10, green = 20, red = 10},
  {name = "the-cave-accumulator-6x6", size = 6, capacity = "250MJ", flow = "6MW", plug_y = 2.3125,
    craft_time = 30, batteries = 200, steel = 40, green = 80, red = 40},
  -- New models use the existing 3x3's power/capacity ratio (full flow in
  -- 16 2/3 seconds). Crafting times are balanced separately from capacity.
  {name = "the-cave-accumulator-10x10", size = 10, capacity = "1GJ", flow = "60MW", plug_y = 3.484375,
    craft_time = 40, batteries = 750, steel = 150, green = 300, red = 150},
  {name = "the-cave-accumulator-20x20", size = 20, capacity = "5GJ", flow = "300MW", plug_y = 7.125,
    craft_time = 50, batteries = 3000, steel = 600, green = 1200, blue = 250}
}

local function picture(path, edge, repeat_count, shadow_edge)
  return {
    layers = {
      {
        filename = path .. "body.png", width = edge, height = edge,
        priority = "high", scale = 0.5, repeat_count = repeat_count,
        animation_speed = repeat_count and 0.5 or nil
      },
      {
        filename = path .. "shadow.png", width = shadow_edge or edge * 4 / 3, height = shadow_edge or edge * 4 / 3,
        priority = "high", scale = 0.5, draw_as_shadow = true,
        repeat_count = repeat_count, animation_speed = repeat_count and 0.5 or nil
      }
    }
  }
end

local function animation(path, edge, state)
  return {
    layers = {
      picture(path, edge, 32),
      {
        filename = path .. state .. ".png", width = edge, height = edge,
        priority = "high", scale = 0.5, frame_count = 32, line_length = 8,
        animation_speed = 0.5, draw_as_glow = true
      }
    }
  }
end

local function large_animation(path, geometry, state)
  local layers = {picture(path, geometry.edge, 32, geometry.shadow_edge)}
  for _, layer in ipairs(column_effects(geometry.size, state)) do
    layers[#layers + 1] = layer
  end
  return {layers = layers}
end

local prototypes = {}
for index, definition in ipairs(definitions) do
  local name, size = definition.name, definition.size
  local edge = size * 64
  local geometry = large_graphics[name]
  local path = "__the-cave__/graphics/entity/cave-accumulators/" .. size .. "x" .. size .. "/"
  local icon = "__the-cave__/graphics/icons/cave-accumulators/" .. size .. "x" .. size .. ".png"
  local entity = table.deepcopy(base_entity)
  entity.name = name
  entity.localised_name = {"entity-name." .. name}
  entity.localised_description = {"entity-description." .. name}
  entity.icon, entity.icon_size, entity.icons = icon, geometry and 128 or 64, nil
  entity.minable = {mining_time = base_entity.minable.mining_time, result = name}
  entity.collision_box = {{-size / 2 + 0.1, -size / 2 + 0.1}, {size / 2 - 0.1, size / 2 - 0.1}}
  entity.selection_box = {{-size / 2, -size / 2}, {size / 2, size / 2}}
  entity.fast_replaceable_group = name
  entity.next_upgrade = nil
  entity.energy_source.buffer_capacity = definition.capacity
  entity.energy_source.input_flow_limit = definition.flow
  entity.energy_source.output_flow_limit = definition.flow
  entity.chargable_graphics = table.deepcopy(base_entity.chargable_graphics)
  if geometry then
    -- Runtime draws only the front meter and cooling rotors. The native
    -- accumulator owns the body, shadows, column charge/discharge effects,
    -- electricity and circuit output.
    entity.chargable_graphics.picture = picture(path, edge, nil, geometry.shadow_edge)
    entity.chargable_graphics.charge_animation = large_animation(path, geometry, "charge")
    entity.chargable_graphics.discharge_animation = large_animation(path, geometry, "discharge")
  else
    entity.chargable_graphics.picture = picture(path, edge)
    entity.chargable_graphics.charge_animation = animation(path, edge, "charge")
    entity.chargable_graphics.discharge_animation = animation(path, edge, "discharge")
  end
  entity.water_reflection = {
    pictures = {
      filename = path .. "reflection.png", width = edge / 4, height = edge / 4,
      priority = "extra-high", scale = 2, variation_count = 1, shift = {0, size / 2}
    },
    rotate = false, orientation_to_variation = false
  }
  -- The new front-panel socket replaces the old connector artwork. Circuit
  -- behaviour, signal-A and connection range are inherited from vanilla.
  entity.circuit_connector = {
    points = {
      wire = {red = {-0.1, definition.plug_y}, green = {0.1, definition.plug_y}},
      shadow = {red = {0.15, definition.plug_y + 0.1}, green = {0.35, definition.plug_y + 0.1}}
    }
  }

  local item = table.deepcopy(base_item)
  item.name, item.place_result = name, name
  item.localised_name, item.localised_description = entity.localised_name, entity.localised_description
  item.icon, item.icon_size, item.icons = icon, entity.icon_size, nil
  item.pictures = nil
  item.order = "e[accumulator]-b[cave]-" .. index

  local ingredients = {
    {type = "item", name = "battery", amount = definition.batteries},
    {type = "item", name = "steel-plate", amount = definition.steel},
  }
  if definition.red then
    ingredients[#ingredients + 1] = {type = "item", name = "advanced-circuit", amount = definition.red}
  else
    ingredients[#ingredients + 1] = {type = "item", name = "processing-unit", amount = definition.blue}
  end
  ingredients[#ingredients + 1] = {type = "item", name = "electronic-circuit", amount = definition.green}
  local recipe = {
    type = "recipe", name = name, enabled = false,
    localised_name = {"entity-name." .. name},
    energy_required = definition.craft_time,
    ingredients = ingredients,
    results = {{type = "item", name = name, amount = 1}}
  }
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe

  if geometry then
    local gauge = geometry.gauge
    for percent = 0, 100 do
      prototypes[#prototypes + 1] = {
        type = "sprite", name = name .. "-charge-" .. percent,
        filename = path .. "gauge.png",
        width = gauge.width, height = gauge.height,
        x = (percent % 10) * gauge.width, y = math.floor(percent / 10) * gauge.height,
        scale = 0.5, shift = gauge.offset, priority = "high", draw_as_glow = true
      }
    end
    if #geometry.fans > 0 then
      local layers = {}
      for _, fan in ipairs(geometry.fans) do
        layers[#layers + 1] = {
          filename = path .. fan.filename, width = fan.width, height = fan.height,
          shift = fan.shift, scale = 0.5, frame_count = 48, line_length = 8,
          animation_speed = 1, priority = "high"
        }
      end
      prototypes[#prototypes + 1] = {type = "animation", name = name .. "-cooling-fans", layers = layers}
    end
  end
end
data:extend(prototypes)

technology.effects = technology.effects or {}
for _, definition in ipairs(definitions) do
  local found = false
  for _, effect in ipairs(technology.effects) do
    if effect.type == "unlock-recipe" and effect.recipe == definition.name then found = true; break end
  end
  if not found then
    technology.effects[#technology.effects + 1] = {type = "unlock-recipe", recipe = definition.name}
  end
end
