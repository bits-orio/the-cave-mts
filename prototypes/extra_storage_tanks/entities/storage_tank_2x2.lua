local shared = require("prototypes.extra_storage_tanks.shared")
local spfunc = require("prototypes.extra_storage_tanks.special_functions")
local entity_name = shared.STORAGE_TANK_NAME["2x2"]

local entity_data = {
  MiningTime = 0.25,
  Health = 400,
  SelectionBox = {{-1,-1},{1,1}},
  CollisionOffset = -0.1,
  DrawBoxVertExt = 0.15,
  IconDrawSpec = {scale = 1, shift = {0,-0.25}},
  FluidCapacity = 8000,
  PipeConnections = {
    {direction = defines.direction.north, position = {0.5,-0.5}},
    {direction = defines.direction.east, position = {0.5,-0.5}},
    {direction = defines.direction.west, position = {-0.5,-0.5}}
  },
  WireConnections = spfunc.create_four_different_wire_connections(
    {25,-20,0,0}, {25,-20,0,0}, {27,20,0,0}, {27,20,0,0}
  ),
  EntitySprites = spfunc.create_entity_graphics_and_shadow(entity_name, {
    Scale=0.5, Frames=4, EntityWidth=128, EntityHeight=160,
    EntityShift={0,-0.25}, ShadowWidth=160, ShadowHeight=128, ShadowShift={0.25,0.5}
  }),
  WindowIsTall=false,
  WindowBox={{-7/64,10/64},{7/64,49/64}},
  WindowScale=0.5,
  FluidFlowLength=405,
  FluidScale=1.0,
  FluidFlowScale=1.0,
  SoundSizeCategory="large",
  SoundVolume=0.5,
  HeatingEnergy="55kW"
}

local explosion_data = {SoundSizeCat="medium", AnimSizeCat="medium", AnimScale=0.75, AnimHeight=0, DebrisAmountX=0.8, DebrisSpeedX=0.9}
local remnants_data = {TileRadius=1, PixelShift={17,12}}
local item_data = {SoundSizeCat="large", StackSize=50, Weight=20, Order="b[fluid]-b[storage-tank-2x2]"}
local recipe_data = {EnergyNeed=2.0, IronPlates=10, SteelPlates=2}

data:extend({
  spfunc.create_explosion(entity_name, explosion_data),
  spfunc.create_remnants(entity_name, remnants_data),
  spfunc.create_entity(entity_name, entity_data),
  spfunc.create_item(entity_name, item_data),
  spfunc.create_recipe(entity_name, recipe_data)
})
