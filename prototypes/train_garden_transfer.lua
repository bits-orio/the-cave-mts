-- Fixed Locomotive Garden fluid endpoints and legacy item endpoints.
--
-- New layouts use protected Industrial Store Boxes for items. These hidden
-- linked-belt prototypes remain registered only so established saves can load
-- them and migrate their remaining items without prototype deletion. Fluids
-- use protected, player-rotatable Pipe-to-ground endpoints and move one-way
-- between floors through the runtime entity-fluid API.

local function runtime_flags()
  return {
    "placeable-neutral",
    "not-deconstructable",
    "not-blueprintable",
    "not-flammable",
    "hide-alt-info",
  }
end

local prototypes = {}

local linked_belt_table = data.raw["linked-belt"]
local linked_base = linked_belt_table and linked_belt_table["linked-belt"]
if not linked_base and linked_belt_table then
  local _, candidate = next(linked_belt_table)
  linked_base = candidate
end
assert(linked_base, "The Cave Locomotive Garden requires Factorio's base linked-belt prototype")

local underground_base = data.raw["underground-belt"]
  and data.raw["underground-belt"]["express-underground-belt"]
local express_speed = underground_base and underground_base.speed
  or (data.raw["transport-belt"]
    and data.raw["transport-belt"]["express-transport-belt"]
    and data.raw["transport-belt"]["express-transport-belt"].speed)
  or 0.09375

local function make_item_port(name, locale_key)
  local entity = table.deepcopy(linked_base)
  entity.name = name
  entity.localised_name = { "entity-name." .. locale_key }
  entity.localised_description = { "entity-description." .. locale_key }
  entity.icon = "__base__/graphics/icons/express-underground-belt.png"
  entity.icon_size = 64
  entity.flags = runtime_flags()
  entity.minable = nil
  entity.destructible = false
  entity.max_health = 1000
  entity.speed = express_speed
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  entity.allow_copy_paste = false
  entity.hidden_in_factoriopedia = true
  entity.is_military_target = false
  entity.alert_when_damaged = false
  entity.create_ghost_on_death = false
  entity.corpse = nil
  entity.dying_explosion = nil
  entity.allow_clone_connection = false
  entity.allow_blueprint_connection = false
  entity.allow_side_loading = true
  return entity
end

prototypes[#prototypes + 1] = make_item_port(
  "the-cave-garden-item-input",
  "the-cave-garden-item-input"
)
prototypes[#prototypes + 1] = make_item_port(
  "the-cave-garden-item-output",
  "the-cave-garden-item-output"
)

local pipe_base = data.raw["pipe-to-ground"] and data.raw["pipe-to-ground"]["pipe-to-ground"]
local function make_fluid_port(name, locale_key)
  if not pipe_base then return nil end
  local entity = table.deepcopy(pipe_base)
  entity.name = name
  entity.localised_name = { "entity-name." .. locale_key }
  entity.localised_description = { "entity-description." .. locale_key }
  entity.icon = "__base__/graphics/icons/pipe-to-ground.png"
  entity.icon_size = 64
  entity.flags = runtime_flags()
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
        -- The visible endpoint connects to an ordinary player pipe on its open
        -- side, but cannot accidentally pair with another same-surface port.
        connection.max_underground_distance = 1
      end
    end
  end
  return entity
end

local fluid_input = make_fluid_port(
  "the-cave-garden-fluid-input",
  "the-cave-garden-fluid-input"
)
if fluid_input then prototypes[#prototypes + 1] = fluid_input end

local fluid_output = make_fluid_port(
  "the-cave-garden-fluid-output",
  "the-cave-garden-fluid-output"
)
if fluid_output then prototypes[#prototypes + 1] = fluid_output end

data:extend(prototypes)
