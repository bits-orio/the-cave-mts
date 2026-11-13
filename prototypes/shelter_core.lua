-- Fixed Shelter and its independent interior-power bridge.
-- Open/close sounds are used under GPL-3.0 from shelter-k2 by zanven.

-- Lobby selection happens after prototype creation. Keep the Shelter union of
-- prototypes available for every New Game; runtime decides whether it exists.

local path = "__the-cave__/"
local shelter_graphics = path .. "graphics/shelter/entities/shelter/"

local shelter_animation = {
  layers = {
    {
      filename = shelter_graphics .. "shelter-light.png",
      priority = "high",
      width = 256,
      height = 256,
      scale = 0.9,
      shift = { -0.05, 0 },
      draw_as_light = true,
      frame_count = 6,
      line_length = 3,
      animation_speed = 0.5,
      hr_version = {
        filename = shelter_graphics .. "hr-shelter-light.png",
        priority = "high",
        width = 512,
        height = 512,
        scale = 0.45,
        shift = { -0.05, 0 },
        draw_as_light = true,
        frame_count = 6,
        line_length = 3,
        animation_speed = 0.5,
      },
    },
    {
      filename = shelter_graphics .. "shelter.png",
      priority = "high",
      width = 256,
      height = 256,
      scale = 0.9,
      shift = { -0.05, 0 },
      frame_count = 6,
      line_length = 3,
      animation_speed = 0.5,
      hr_version = {
        filename = shelter_graphics .. "hr-shelter.png",
        priority = "high",
        width = 512,
        height = 512,
        scale = 0.45,
        shift = { -0.05, 0 },
        frame_count = 6,
        line_length = 3,
        animation_speed = 0.5,
      },
    },
    {
      filename = shelter_graphics .. "shelter-shadow.png",
      priority = "high",
      width = 256,
      height = 256,
      scale = 0.9,
      shift = { 0.42, 0 },
      frame_count = 6,
      line_length = 3,
      animation_speed = 0.5,
      draw_as_shadow = true,
      hr_version = {
        filename = shelter_graphics .. "hr-shelter-shadow.png",
        priority = "high",
        width = 512,
        height = 512,
        scale = 0.45,
        shift = { 0.42, 0 },
        frame_count = 6,
        line_length = 3,
        animation_speed = 0.5,
        draw_as_shadow = true,
      },
    },
  },
}

local shelter = table.deepcopy(data.raw.container["steel-chest"])
shelter.name = "the-cave-shelter"
shelter.localised_name = { "entity-name.the-cave-shelter" }
shelter.localised_description = { "entity-description.the-cave-shelter" }
shelter.icon = path .. "graphics/shelter/shelter.png"
shelter.icon_size = 64
shelter.flags = {
  "placeable-player",
  "player-creation",
  "not-deconstructable",
  "not-rotatable",
  "not-blueprintable",
  "not-repairable",
}
shelter.minable = nil
shelter.fast_replaceable_group = nil
shelter.next_upgrade = nil
shelter.allow_copy_paste = false
-- Keep one fixed physical ceiling and let runtime map the researched
-- 5,000-35,000 Shelter Shield pool onto it. This avoids replacing the live
-- objective (and its inventory/unit_number) when Shield research finishes.
shelter.max_health = 35000
shelter.inventory_size = 200
shelter.collision_box = { { -2.75, -2.75 }, { 2.75, 2.75 } }
shelter.selection_box = { { -3, -3 }, { 3, 3.2 } }
shelter.picture = shelter_animation
shelter.open_sound = { filename = path .. "sounds/shelter/open.ogg", volume = 1 }
shelter.close_sound = { filename = path .. "sounds/shelter/close.ogg", volume = 1 }
shelter.vehicle_impact_sound = { filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 }
shelter.resistances = nil
shelter.corpse = nil
shelter.is_military_target = true
shelter.hidden_in_factoriopedia = true

local empty_sprite = {
  filename = "__core__/graphics/empty.png",
  priority = "low",
  width = 1,
  height = 1,
  frame_count = 1,
  direction_count = 1,
}
local empty_pole_sprite = table.deepcopy(empty_sprite)
empty_pole_sprite.direction_count = 4

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

-- Keep the old hidden accumulator prototypes registered so 3.1.8 and older
-- saves can load safely. They are electrically inert; runtime recovers pending
-- interior charge, settles the mirrored exterior output, then removes only
-- these script-owned legacy entities.
local function legacy_hidden_accumulator(name)
  local entity = table.deepcopy(data.raw.accumulator.accumulator)
  entity.name = name
  entity.localised_name = { "entity-name.the-cave-shelter-hidden-battery" }
  entity.localised_description = { "entity-description.the-cave-shelter-hidden-battery" }
  entity.hidden = true
  entity.hidden_in_factoriopedia = true
  entity.selectable_in_game = false
  entity.flags = hidden_flags()
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = { { 0, 0 }, { 0, 0 } }
  entity.selection_box = { { 0, 0 }, { 0, 0 } }
  entity.collision_mask = { layers = {} }
  entity.picture = empty_sprite
  entity.chargable_graphics = {
    picture = empty_sprite,
    charge_animation = empty_sprite,
    discharge_animation = empty_sprite,
  }
  entity.charge_animation = empty_sprite
  entity.discharge_animation = empty_sprite
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

local function hidden_power_interface(name, mode, flow_limit, buffer_capacity)
  local base = data.raw["electric-energy-interface"]
    and data.raw["electric-energy-interface"]["electric-energy-interface"]
  if not base then return nil end
  local entity = table.deepcopy(base)
  entity.name = name
  if mode == "output" then
    entity.localised_name = { "entity-name.the-cave-shelter-battery-output-reserve" }
    entity.localised_description = { "entity-description.the-cave-shelter-battery-output-reserve" }
  else
    entity.localised_name = { "entity-name.the-cave-shelter-battery-interior-charger" }
    entity.localised_description = { "entity-description.the-cave-shelter-battery-interior-charger" }
  end
  entity.hidden = true
  entity.hidden_in_factoriopedia = true
  entity.selectable_in_game = false
  entity.flags = hidden_flags()
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = { { 0, 0 }, { 0, 0 } }
  entity.selection_box = { { 0, 0 }, { 0, 0 } }
  entity.collision_mask = { layers = {} }
  entity.gui_mode = "none"
  entity.energy_production = "0W"
  entity.energy_usage = "0W"
  entity.energy_source = {
    type = "electric",
    buffer_capacity = buffer_capacity,
    input_flow_limit = mode == "input" and flow_limit or "0W",
    output_flow_limit = mode == "output" and flow_limit or "0W",
    -- Interior accumulators charge alongside the Shelter Battery. Exterior
    -- output joins generators and can charge player-built accumulators.
    usage_priority = mode == "output" and "secondary-output" or "tertiary",
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
  -- Use the Shelter icon in electric-network statistics so neither transfer
  -- window is mistaken for a player-built accumulator.
  entity.icon = shelter.icon
  entity.icons = shelter.icons
  entity.icon_size = shelter.icon_size
  return entity
end

-- Keep the short-lived 3.1.72 accumulator names registered so existing saves
-- can load. They are electrically inert; runtime transfers their pending
-- state to the same one-way ElectricEnergyInterface used by Train Interiors.
local function hidden_output_accumulator(name, flow_limit, buffer_capacity)
  local base = data.raw.accumulator and data.raw.accumulator.accumulator
  if not base then return nil end
  local entity = table.deepcopy(base)
  entity.name = name
  entity.localised_name = { "entity-name.the-cave-shelter-battery-output-reserve" }
  entity.localised_description = { "entity-description.the-cave-shelter-battery-output-reserve" }
  entity.hidden = true
  entity.hidden_in_factoriopedia = true
  entity.selectable_in_game = false
  entity.flags = hidden_flags()
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = { { 0, 0 }, { 0, 0 } }
  entity.selection_box = { { 0, 0 }, { 0, 0 } }
  entity.collision_mask = { layers = {} }
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
  entity.placeable_by = nil
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  entity.circuit_connector = nil
  entity.circuit_wire_max_distance = nil
  entity.energy_source = {
    type = "electric",
    buffer_capacity = buffer_capacity,
    input_flow_limit = "0W",
    output_flow_limit = flow_limit,
    usage_priority = "tertiary",
    render_no_power_icon = false,
    render_no_network_icon = false,
  }
  entity.icon = shelter.icon
  entity.icons = shelter.icons
  entity.icon_size = shelter.icon_size
  return entity
end

local function hidden_pole()
  local entity = table.deepcopy(data.raw["electric-pole"].substation)
  entity.name = "the-cave-shelter-output-pole"
  entity.localised_name = { "entity-name.the-cave-shelter-hidden-battery" }
  entity.hidden = true
  entity.hidden_in_factoriopedia = true
  entity.selectable_in_game = false
  entity.flags = hidden_flags()
  entity.minable = nil
  entity.destructible = false
  entity.collision_box = { { 0, 0 }, { 0, 0 } }
  entity.selection_box = { { 0, 0 }, { 0, 0 } }
  entity.collision_mask = { layers = {} }
  -- Match the working Train Battery bridge: this pole is wire-only. The
  -- colocated output interface joins it at the exact same position, while
  -- player poles are connected explicitly by runtime inside the 15x15 square.
  entity.supply_area_distance = 0
  entity.maximum_wire_distance = 11
  entity.auto_connect_up_to_n_wires = 0
  entity.rewire_neighbours_when_destroying = false
  entity.draw_copper_wires = false
  entity.draw_circuit_wires = false
  entity.pictures = empty_pole_sprite
  entity.radius_visualisation_picture = nil
  entity.water_reflection = nil
  return entity
end

local substation = table.deepcopy(data.raw["electric-pole"].substation)
substation.name = "the-cave-shelter-substation"
substation.localised_name = { "entity-name.the-cave-shelter-substation" }
substation.localised_description = { "entity-description.the-cave-shelter-substation" }
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
-- Match the Main Locomotive Substation exactly: the fixed 36x36 green Shelter
-- core receives direct coverage, and the hidden one-way charger beneath this
-- fixture remains on the same interior electric network.
substation.supply_area_distance = 18

-- Separate lower Garden connector. It deliberately shares the Shelter
-- Substation's 36-tile wire reach but, like the Train Garden connector, keeps
-- direct supply limited to its own protected 2x2 footprint. Garden machines
-- therefore still use ordinary player-built electric poles.
local garden_substation = table.deepcopy(substation)
garden_substation.name = "the-cave-shelter-garden-substation"
garden_substation.localised_name = { "entity-name.the-cave-shelter-garden-substation" }
garden_substation.localised_description = { "entity-description.the-cave-shelter-garden-substation" }
garden_substation.supply_area_distance = 1

local function protected_fluid_port(name)
  local base = data.raw["pipe-to-ground"] and data.raw["pipe-to-ground"]["pipe-to-ground"]
  if not base then return nil end
  local entity = table.deepcopy(base)
  entity.name = name
  entity.localised_name = { "entity-name." .. name }
  entity.localised_description = { "entity-description." .. name }
  entity.icon = "__base__/graphics/icons/pipe-to-ground.png"
  entity.icon_size = 64
  entity.flags = {
    "placeable-neutral",
    "not-deconstructable",
    "not-blueprintable",
    "not-flammable",
    "hide-alt-info",
  }
  entity.minable = nil
  entity.destructible = false
  entity.max_health = 1000
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  entity.allow_copy_paste = false
  entity.hidden_in_factoriopedia = true
  entity.is_military_target = false
  entity.alert_when_damaged = false
  entity.create_ghost_on_death = false
  entity.corpse = nil
  entity.dying_explosion = nil
  if entity.fluid_box and entity.fluid_box.pipe_connections then
    for _, connection in pairs(entity.fluid_box.pipe_connections) do
      if connection.max_underground_distance then
        connection.max_underground_distance = 1
      end
    end
  end
  return entity
end

local prototypes = { shelter, hidden_pole(), substation, garden_substation }
local fluid_input = protected_fluid_port("the-cave-shelter-fluid-input")
local fluid_output = protected_fluid_port("the-cave-shelter-fluid-output")
if fluid_input then prototypes[#prototypes + 1] = fluid_input end
if fluid_output then prototypes[#prototypes + 1] = fluid_output end

-- Shelter Battery mirrors the complete Train Battery progression. Charging
-- continues to rise through level 20, while exterior output retains the
-- established 600 MW ceiling from level 6 onward.
local charge_rate_mw = {
  50, 100, 150, 200, 250,
  300, 350, 400, 450, 500,
  550, 600, 650, 700, 750,
  800, 850, 900, 950, 1000,
}
local output_rate_mw = {
  50, 100, 150, 250, 400, 600,
  600, 600, 600, 600, 600, 600, 600,
  600, 600, 600, 600, 600, 600, 600,
}
local output_transfer_window_seconds = 15 / 60
for level, mw in ipairs(charge_rate_mw) do
  -- Only levels 1-6 existed as accumulator-based inputs. Retain those names
  -- for old-save loading; levels 7-20 are new one-way interfaces only.
  if level <= 6 then
    prototypes[#prototypes + 1] = legacy_hidden_accumulator(
      "the-cave-shelter-battery-input-l" .. level
    )
  end
  local input = hidden_power_interface(
    "the-cave-shelter-battery-charge-interface-l" .. level,
    "input",
    tostring(mw) .. "MW",
    tostring(mw) .. "MJ"
  )
  if input then prototypes[#prototypes + 1] = input end

end

for level, mw in ipairs(output_rate_mw) do
  local output_window_mj = mw * output_transfer_window_seconds
  -- Use the exact proven Train Battery output type and one-sync buffer size.
  local output = hidden_power_interface(
    "the-cave-shelter-battery-discharge-interface-l" .. level,
    "output",
    tostring(mw) .. "MW",
    tostring(output_window_mj) .. "MJ"
  )
  if output then prototypes[#prototypes + 1] = output end

  -- Load compatibility only for 3.1.72. Runtime removes these accumulators.
  local legacy_output = hidden_output_accumulator(
    "the-cave-shelter-battery-discharge-buffer-l" .. level,
    "0W",
    tostring(output_window_mj) .. "MJ"
  )
  if legacy_output then prototypes[#prototypes + 1] = legacy_output end
end
prototypes[#prototypes + 1] = legacy_hidden_accumulator("the-cave-shelter-battery-output")
data:extend(prototypes)
