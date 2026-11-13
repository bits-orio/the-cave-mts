-- Hidden train power bridge entities.
-- These are never craftable or visible. Runtime script uses them to charge a
-- scripted Train Hidden Battery from the train-interior electric network and to
-- discharge that stored energy into an outside electric network near the train.
-- Input chargers scale by Train Battery research level so large batteries can
-- use stronger interior power setups without the early levels creating a huge
-- artificial load on small starter grids.

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

local function hidden_flags()
  return {
    "placeable-neutral",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "not-flammable",
    "hide-alt-info",
  }
end

local function make_legacy_hidden_accumulator(name)
  local base = data.raw.accumulator and data.raw.accumulator["accumulator"]
  if not base then return nil end
  local entity = table.deepcopy(base)
  entity.name = name
  entity.localised_name = {"", "The Cave Train Hidden Battery"}
  entity.localised_description = {"", "Hidden scripted train battery bridge used by The Cave."}
  entity.hidden = true
  entity.selectable_in_game = false
  entity.flags = hidden_flags()
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = {{0, 0}, {0, 0}}
  entity.selection_box = {{0, 0}, {0, 0}}
  entity.collision_mask = {layers = {}}
  entity.picture = empty_sprite
  entity.chargable_graphics = {
    picture = empty_sprite,
    charge_animation = empty_sprite,
    discharge_animation = empty_sprite,
  }
  entity.charge_animation = empty_sprite
  entity.discharge_animation = empty_sprite
  entity.charge_cooldown = 0
  entity.discharge_cooldown = 0
  entity.working_sound = nil
  entity.water_reflection = nil
  entity.energy_source = {
    type = "electric",
    buffer_capacity = "25000MJ",
    input_flow_limit = "0W",
    output_flow_limit = "0W",
    usage_priority = "tertiary",
    render_no_power_icon = false,
    render_no_network_icon = false,
  }
  return entity
end

local function make_hidden_interface(name, mode, flow_limit, buffer_capacity)
  local base = data.raw["electric-energy-interface"] and data.raw["electric-energy-interface"]["electric-energy-interface"]
  if not base then return nil end
  local entity = table.deepcopy(base)
  local accumulator = data.raw.accumulator and data.raw.accumulator["accumulator"]
  local locomotive = data.raw.locomotive and data.raw.locomotive["locomotive"]
  entity.name = name
  if mode == "output" then
    entity.localised_name = { "entity-name.the-cave-train-battery-output-reserve" }
    entity.localised_description = { "entity-description.the-cave-train-battery-output-reserve" }
  else
    entity.localised_name = { "entity-name.the-cave-train-battery-interior-charger" }
    entity.localised_description = { "entity-description.the-cave-train-battery-interior-charger" }
  end
  entity.hidden = true
  entity.selectable_in_game = false
  entity.flags = hidden_flags()
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = {{0, 0}, {0, 0}}
  entity.selection_box = {{0, 0}, {0, 0}}
  entity.collision_mask = {layers = {}}
  entity.gui_mode = "none"
  entity.energy_production = "0W"
  entity.energy_usage = "0W"
  entity.energy_source = {
    type = "electric",
    buffer_capacity = buffer_capacity,
    input_flow_limit = (mode == "input") and flow_limit or "0W",
    output_flow_limit = (mode == "output") and flow_limit or "0W",
    -- Keep interior charging alongside accumulators. Exterior output joins
    -- ordinary generators so it can also charge player-built accumulators.
    usage_priority = (mode == "output") and "secondary-output" or "tertiary",
    render_no_power_icon = false,
    render_no_network_icon = false,
  }
  entity.picture = empty_sprite
  entity.pictures = nil
  entity.animation = nil
  entity.animations = nil
  entity.working_sound = nil
  entity.water_reflection = nil
  entity.placeable_by = nil
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  entity.circuit_connector = nil
  entity.circuit_wire_max_distance = nil
  -- Use the locomotive icon for both one-way interfaces so Factorio's electric
  -- statistics do not make this script-owned transfer window look like a
  -- player-built accumulator.
  local icon_source = locomotive or accumulator
  if icon_source then
    entity.icon = icon_source.icon
    entity.icons = icon_source.icons
    entity.icon_size = icon_source.icon_size
  end
  return entity
end

local function make_hidden_pole(name, wire_distance, supply_area_distance)
  local base = data.raw["electric-pole"] and (data.raw["electric-pole"]["substation"] or data.raw["electric-pole"]["small-electric-pole"])
  if not base then return nil end
  local entity = table.deepcopy(base)
  entity.name = name
  entity.localised_name = {"", "The Cave Train Hidden Power Pole"}
  entity.localised_description = {"", "Hidden scripted power connector used by The Cave train interiors."}
  entity.hidden = true
  entity.selectable_in_game = false
  entity.flags = hidden_flags()
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = {{0, 0}, {0, 0}}
  entity.selection_box = {{0, 0}, {0, 0}}
  entity.collision_mask = {layers = {}}
  entity.supply_area_distance = supply_area_distance or 1
  -- Factorio hard-limits ElectricPolePrototype.maximum_wire_distance to 64.
  -- Use the requested reach exactly instead of inheriting the copied
  -- Substation's longer 18-tile reach. Runtime owns every copper connection.
  entity.maximum_wire_distance = math.min(64, wire_distance or 32)
  entity.auto_connect_up_to_n_wires = 0
  entity.rewire_neighbours_when_destroying = false
  entity.draw_copper_wires = false
  entity.draw_circuit_wires = false
  entity.pictures = empty_pole_sprite
  entity.radius_visualisation_picture = nil
  entity.water_reflection = nil
  return entity
end

local prototypes = {}
-- All old hidden accumulator prototypes remain registered so existing saves
-- load safely.  They are intentionally inert; runtime migrates their state to
-- the independent scripted battery and then destroys only these mod-owned
-- entities.
local legacy_input = make_legacy_hidden_accumulator("the-cave-train-battery-input")
if legacy_input then prototypes[#prototypes + 1] = legacy_input end

-- Legacy level and tap variants are kept only for save compatibility.
local legacy_target_charge_mw_by_level = { 50, 100, 150, 250, 400, 600 }
-- Battery charging increases by 50 MW per researched level.
local target_charge_mw_by_level = {
  50, 100, 150, 200, 250,
  300, 350, 400, 450, 500,
  550, 600, 650, 700, 750,
  800, 850, 900, 950, 1000,
}
-- Exterior discharge keeps the established rate progression unchanged.
local target_output_mw_by_level = {
  50, 100, 150, 250, 400, 600,
  600, 600, 600, 600, 600, 600, 600,
  600, 600, 600, 600, 600, 600, 600,
}
-- Runtime refreshes the output every 15 ticks.  Size the output buffer to that
-- exact 0.25-second transfer window instead of a full second. This reserve is
-- backed by scripted battery energy; the established output rate is unchanged.
local output_transfer_window_seconds = 15 / 60
local max_train_power_taps = 8
local level_inputs = {}
for level, target_mw in ipairs(legacy_target_charge_mw_by_level) do
  -- Keep the old level-only names as safe fallbacks for old saves/scripts.
  level_inputs[#level_inputs + 1] = {
    name = "the-cave-train-battery-input-l" .. tostring(level),
    limit = tostring(target_mw) .. "MW"
  }
  for taps = 1, max_train_power_taps do
    local per_tap_kw = math.ceil((target_mw * 1000) / taps)
    level_inputs[#level_inputs + 1] = {
      name = "the-cave-train-battery-input-l" .. tostring(level) .. "-t" .. tostring(taps),
      limit = tostring(per_tap_kw) .. "kW"
    }
  end
end

for _, def in ipairs(level_inputs) do
  local input = make_legacy_hidden_accumulator(def.name)
  if input then prototypes[#prototypes + 1] = input end
end

local output = make_legacy_hidden_accumulator("the-cave-train-battery-output")
if output then prototypes[#prototypes + 1] = output end

-- New one-way interfaces.  The interior interface can only consume power;
-- the exterior interface can only provide power.  Neither is an accumulator,
-- so it cannot merge player accumulators with the scripted train battery.
for level, target_mw in ipairs(target_charge_mw_by_level) do
  local input = make_hidden_interface(
    "the-cave-train-battery-charge-interface-l" .. tostring(level),
    "input",
    tostring(target_mw) .. "MW",
    tostring(target_mw) .. "MJ"
  )
  if input then prototypes[#prototypes + 1] = input end
end

-- Retain the 3.1.5 single-output prototype so those saves can load. It is
-- electrically inert and runtime replaces it with the researched-level output.
local legacy_discharge_interface = make_hidden_interface(
  "the-cave-train-battery-discharge-interface",
  "output",
  "0W",
  "2500MJ"
)
if legacy_discharge_interface then prototypes[#prototypes + 1] = legacy_discharge_interface end

for level, target_mw in ipairs(target_output_mw_by_level) do
  local transfer_window_mj = target_mw * output_transfer_window_seconds
  local output_interface = make_hidden_interface(
    "the-cave-train-battery-discharge-interface-l" .. tostring(level),
    "output",
    tostring(target_mw) .. "MW",
    tostring(transfer_window_mj) .. "MJ"
  )
  if output_interface then prototypes[#prototypes + 1] = output_interface end
end
-- Wire-only hidden poles: supply area 0 so they do not directly power every entity on the wagon floor.
-- They only bridge player-built electric pole networks into the shared train battery bus.
local inside_pole = make_hidden_pole("the-cave-train-battery-inside-pole", 64, 0)
if inside_pole then prototypes[#prototypes + 1] = inside_pole end
local bus_pole = make_hidden_pole("the-cave-train-battery-bus-pole", 64, 0)
if bus_pole then prototypes[#prototypes + 1] = bus_pole end
local output_pole = make_hidden_pole("the-cave-train-battery-output-pole", 10, 0)
if output_pole then prototypes[#prototypes + 1] = output_pole end

-- Only the persistent Main Locomotive receives this visible, script-owned
-- distribution Substation. It is deliberately a separate prototype so the
-- 36x36 coverage and 36-tile wire reach do not alter vanilla or Market MK
-- Substations; secondary locomotives never instantiate it.
local substation_source = data.raw["electric-pole"] and data.raw["electric-pole"]["substation"]
if substation_source then
  local substation = table.deepcopy(substation_source)
  substation.name = "the-cave-train-locomotive-substation"
  substation.localised_name = { "entity-name.the-cave-train-locomotive-substation" }
  substation.localised_description = { "entity-description.the-cave-train-locomotive-substation" }
  substation.flags = {
    "placeable-neutral",
    "not-deconstructable",
    "not-blueprintable",
    "not-flammable",
  }
  substation.minable = nil
  substation.destructible = false
  substation.is_military_target = false
  substation.fast_replaceable_group = nil
  substation.next_upgrade = nil
  substation.allow_copy_paste = false
  substation.hidden_in_factoriopedia = true
  substation.maximum_wire_distance = 36
  substation.supply_area_distance = 18
  prototypes[#prototypes + 1] = substation

  -- The lower Garden fixture is a wire connector, not free floor-wide power.
  -- Keep one tile of supply area only so the protected 2x2 fixture can join
  -- the electric network while every normal Garden machine still needs a
  -- player-built pole. The Main Locomotive keeps its established 36x36
  -- Substation coverage through the separate prototype above.
  local garden_substation = table.deepcopy(substation)
  garden_substation.name = "the-cave-train-garden-substation"
  garden_substation.localised_name = { "entity-name.the-cave-train-garden-substation" }
  garden_substation.localised_description = { "entity-description.the-cave-train-garden-substation" }
  garden_substation.supply_area_distance = 1
  prototypes[#prototypes + 1] = garden_substation
end

-- The Main Locomotive also receives a protected information panel. Runtime
-- fills it with the localized Train Battery wiring instructions.
local panel_source = data.raw["display-panel"] and data.raw["display-panel"]["display-panel"]
if panel_source then
  local panel = table.deepcopy(panel_source)
  panel.name = "the-cave-train-battery-info-panel"
  panel.localised_name = { "entity-name.the-cave-train-battery-info-panel" }
  panel.localised_description = { "entity-description.the-cave-train-battery-info-panel" }
  panel.flags = {
    "placeable-neutral",
    "not-deconstructable",
    "not-blueprintable",
    "not-flammable",
  }
  panel.minable = nil
  panel.destructible = false
  panel.is_military_target = false
  panel.fast_replaceable_group = nil
  panel.next_upgrade = nil
  panel.allow_copy_paste = false
  panel.hidden_in_factoriopedia = true
  prototypes[#prototypes + 1] = panel
end

if #prototypes > 0 then data:extend(prototypes) end
