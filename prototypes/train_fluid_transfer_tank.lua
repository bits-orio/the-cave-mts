-- Fixed 5x5 Fluid Wagon transfer tank.
--
-- This hidden runtime fixture deliberately does not depend on the optional
-- Extra Storage Tanks startup setting or its research chain. It reuses the
-- integrated 5x5 artwork and fluid-box geometry but has no item or recipe.

local shared = require("prototypes.extra_storage_tanks.shared")
local spfunc = require("prototypes.extra_storage_tanks.special_functions")

local entity_name = "the-cave-train-fluid-transfer-tank-5x5"
local graphic_name = shared.STORAGE_TANK_NAME["5x5"]

if not (data.raw["storage-tank"] and data.raw["storage-tank"][entity_name]) then
  local entity_data = {
    MiningTime = 1.0,
    Health = 900,
    SelectionBox = {{-2.5, -2.5}, {2.5, 2.5}},
    CollisionOffset = -0.1,
    IconDrawSpec = {scale = 2, shift = {0, -0.25}},
    FluidCapacity = 70000,
    PipeConnections = {
      {direction = defines.direction.north, position = {-2, -2}},
      {direction = defines.direction.north, position = {2, -2}},
      {direction = defines.direction.east, position = {2, -2}},
      {direction = defines.direction.east, position = {2, 2}},
      {direction = defines.direction.south, position = {2, 2}},
      {direction = defines.direction.south, position = {-2, 2}},
      {direction = defines.direction.west, position = {-2, 2}},
      {direction = defines.direction.west, position = {-2, -2}},
    },
    WireConnections = spfunc.create_four_identical_wire_connections({25, -61.5, 33.5, 12}),
    EntitySprites = spfunc.create_entity_graphics_and_shadow(graphic_name, {
      Scale = 0.5,
      Frames = 1,
      EntityWidth = 320,
      EntityHeight = 384,
      EntityShift = {0, -0.5},
      ShadowWidth = 384,
      ShadowHeight = 352,
      ShadowShift = {0.5, 0.25},
    }),
    WindowIsTall = false,
    WindowBox = {{-10 / 64, 56 / 64}, {10 / 64, 119 / 64}},
    WindowScale = 0.8,
    FluidFlowLength = 575,
    FluidScale = 1.2,
    FluidFlowScale = 1.0,
    SoundSizeCategory = "large",
    SoundVolume = 0.6,
    HeatingEnergy = "300kW",
  }

  local entity = spfunc.create_entity(entity_name, entity_data)
  entity.icon = shared.ICON_PATH .. graphic_name .. ".png"
  entity.localised_name = {"entity-name.the-cave-train-fluid-transfer-tank-5x5"}
  entity.localised_description = {"entity-description.the-cave-train-fluid-transfer-tank-5x5"}
  entity.flags = {
    "placeable-neutral",
    "not-deconstructable",
    "not-blueprintable",
    "not-flammable",
    "hide-alt-info",
  }
  entity.minable = nil
  entity.destructible = false
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  entity.hidden_in_factoriopedia = true
  entity.is_military_target = false
  entity.alert_when_damaged = false
  entity.create_ghost_on_death = false
  entity.corpse = nil
  entity.dying_explosion = nil

  data:extend({entity})
end
