-- Enemy-only laser turret support for cavern rooms.
--
-- The active implementation uses a dedicated copy of the vanilla laser turret
-- with a void energy source. It can fire normally without joining any electric
-- network, so nearby player poles can never receive power from cavern guards.
--
-- The two legacy helper prototypes are retained temporarily so old saves can
-- load safely. Their power output is disabled and runtime migration removes
-- every remaining instance.

local empty_sprite = {
  filename = "__core__/graphics/empty.png",
  priority = "low",
  width = 1,
  height = 1,
  frame_count = 1,
  direction_count = 1,
}

local empty_pole_sprite = {
  filename = "__core__/graphics/empty.png",
  priority = "low",
  width = 1,
  height = 1,
  frame_count = 1,
  direction_count = 4,
}

local function make_enemy_laser_turret()
  local base = data.raw["electric-turret"] and data.raw["electric-turret"]["laser-turret"]
  if not base then return nil end

  local entity = table.deepcopy(base)
  entity.name = "the-cave-enemy-laser-turret"
  entity.localised_name = {"entity-name.laser-turret"}
  entity.energy_source = {
    type = "void",
    render_no_power_icon = false,
    render_no_network_icon = false,
  }

  -- This prototype is created only by The Cave's cavern generator. Keep the
  -- rest of the vanilla prototype intact so graphics, health, resistances,
  -- mining result and combat behaviour remain compatible with other mods.
  entity.hidden = true

  return entity
end

local function make_legacy_power_interface()
  local base = data.raw["electric-energy-interface"] and data.raw["electric-energy-interface"]["electric-energy-interface"]
  local entity = base and table.deepcopy(base) or {
    type = "electric-energy-interface",
    collision_box = {{0, 0}, {0, 0}},
    selection_box = {{0, 0}, {0, 0}},
  }

  entity.name = "the-cave-enemy-laser-power"
  entity.localised_name = {"entity-name.the-cave-enemy-laser-power"}
  entity.flags = {"placeable-neutral", "not-on-map", "not-blueprintable", "not-deconstructable", "hide-alt-info"}
  entity.hidden = true
  entity.selectable_in_game = false
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = {{0, 0}, {0, 0}}
  entity.selection_box = {{0, 0}, {0, 0}}
  entity.collision_mask = {layers = {}}
  entity.picture = empty_sprite
  entity.gui_mode = "none"

  -- Deliberately inert. This prevents any legacy entity from supplying free
  -- power before the configuration migration removes it from the save.
  entity.energy_source = {
    type = "electric",
    buffer_capacity = "1J",
    input_flow_limit = "0W",
    output_flow_limit = "0W",
    usage_priority = "primary-output",
    render_no_power_icon = false,
    render_no_network_icon = false,
  }
  entity.energy_production = "0W"
  entity.energy_usage = "0W"

  return entity
end

local function make_legacy_hidden_pole()
  local base = data.raw["electric-pole"] and (data.raw["electric-pole"]["substation"] or data.raw["electric-pole"]["small-electric-pole"])
  if not base then return nil end

  local entity = table.deepcopy(base)
  entity.name = "the-cave-enemy-laser-power-pole"
  entity.localised_name = {"entity-name.the-cave-enemy-laser-power-pole"}
  entity.flags = {"placeable-neutral", "not-on-map", "not-blueprintable", "not-deconstructable", "hide-alt-info"}
  entity.hidden = true
  entity.selectable_in_game = false
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = {{0, 0}, {0, 0}}
  entity.selection_box = {{0, 0}, {0, 0}}
  entity.collision_mask = {layers = {}}
  entity.draw_copper_wires = false
  entity.draw_circuit_wires = false
  entity.pictures = empty_pole_sprite
  entity.radius_visualisation_picture = nil
  entity.water_reflection = nil

  return entity
end

local prototypes = {}

local enemy_laser = make_enemy_laser_turret()
if enemy_laser then prototypes[#prototypes + 1] = enemy_laser end

local legacy_power = make_legacy_power_interface()
if legacy_power then prototypes[#prototypes + 1] = legacy_power end

local legacy_pole = make_legacy_hidden_pole()
if legacy_pole then prototypes[#prototypes + 1] = legacy_pole end

data:extend(prototypes)
