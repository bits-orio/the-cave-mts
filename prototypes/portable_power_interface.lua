-- The Cave Portable Power Interface series
-- Market-only, limited-output emergency power sources based on Factorio's built-in electric-energy-interface.

local variants = {
  { suffix = "mk1", label = "MK1", power = "50kW",  price = 100, order = "a" },
  { suffix = "mk2", label = "MK2", power = "80kW",  price = 200, order = "b" },
  { suffix = "mk3", label = "MK3", power = "100kW", price = 400, order = "c" },
  { suffix = "mk4", label = "MK4", power = "150kW", price = 600, order = "d" },
  { suffix = "mk5", label = "MK5", power = "250kW", price = 800, order = "e" },
}

local base_interface = data.raw["electric-energy-interface"] and data.raw["electric-energy-interface"]["electric-energy-interface"]
local accumulator = data.raw.accumulator and data.raw.accumulator["accumulator"]

local icon = "__base__/graphics/icons/accumulator.png"
if base_interface and base_interface.icon then
  icon = base_interface.icon
elseif accumulator and accumulator.icon then
  icon = accumulator.icon
end

local function make_entity(v)
  local name = "the-cave-portable-power-interface-" .. v.suffix
  local entity

  if base_interface then
    entity = table.deepcopy(base_interface)
  else
    entity = {
      type = "electric-energy-interface",
      flags = { "placeable-player", "player-creation" },
      collision_box = { { -0.7, -0.7 }, { 0.7, 0.7 } },
      selection_box = { { -1, -1 }, { 1, 1 } },
    }
  end

  entity.name = name
  entity.localised_name = { "entity-name." .. name }
  entity.localised_description = { "entity-description." .. name }
  entity.icon = icon
  entity.icons = nil
  entity.flags = { "placeable-player", "player-creation" }
  entity.minable = { mining_time = 0.2, result = name }
  entity.max_health = 200
  entity.is_military_target = true
  entity.alert_when_damaged = true
  entity.gui_mode = "none"
  entity.corpse = entity.corpse or (accumulator and accumulator.corpse) or "medium-remnants"
  entity.dying_explosion = entity.dying_explosion or (accumulator and accumulator.dying_explosion) or "medium-explosion"
  entity.collision_box = entity.collision_box or (accumulator and accumulator.collision_box) or { { -0.7, -0.7 }, { 0.7, 0.7 } }
  entity.selection_box = entity.selection_box or (accumulator and accumulator.selection_box) or { { -1, -1 }, { 1, 1 } }
  entity.energy_source = {
    type = "electric",
    buffer_capacity = "1MJ",
    input_flow_limit = "0kW",
    output_flow_limit = v.power,
    usage_priority = "primary-output",
    render_no_power_icon = false,
    render_no_network_icon = false,
  }
  entity.energy_production = v.power
  entity.energy_usage = "0kW"
  entity.order = "the-cave-portable-power-" .. v.order

  return entity
end

local prototypes = {}
for _, v in pairs(variants) do
  local name = "the-cave-portable-power-interface-" .. v.suffix
  prototypes[#prototypes + 1] = {
    type = "item",
    name = name,
    localised_name = { "item-name." .. name },
    localised_description = { "item-description." .. name },
    icon = icon,
    subgroup = "energy",
    order = "z[the-cave-portable-power]-" .. v.order,
    place_result = name,
    stack_size = 10,
  }
  prototypes[#prototypes + 1] = make_entity(v)
end

data:extend(prototypes)
