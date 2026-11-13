local capsule_explosion_sound = {
  {filename = "__base__/sound/fight/poison-capsule-explosion-1.ogg", volume = 0.8},
  {filename = "__base__/sound/fight/poison-capsule-explosion-2.ogg", volume = 0.8},
  {filename = "__base__/sound/fight/poison-capsule-explosion-3.ogg", volume = 0.8},
  {filename = "__base__/sound/fight/poison-capsule-explosion-4.ogg", volume = 0.8},
  {filename = "__base__/sound/fight/poison-capsule-explosion-5.ogg", volume = 0.8}
}

local base_rocket = data.raw.ammo and data.raw.ammo["rocket"]
local base_projectile = data.raw.projectile and data.raw.projectile["rocket"]
local base_fire = data.raw.fire and data.raw.fire["fire-flame"]
local base_stream = data.raw.stream and data.raw.stream["flamethrower-fire-stream"]
if not (base_rocket and base_projectile and base_fire and base_stream) then return end

local chemical_rocket_item = table.deepcopy(base_rocket)
chemical_rocket_item.name = "chemical-rocket"
chemical_rocket_item.icon = "__the-cave__/graphics/chemical_rocket/chemical-rocket.png"
chemical_rocket_item.ammo_type.action.action_delivery.projectile = "chemical-rocket"
chemical_rocket_item.order = "d[rocket-launcher]-b[explosive]-a"

local chemical_rocket_projectile = table.deepcopy(base_projectile)
chemical_rocket_projectile.name = "chemical-rocket"
chemical_rocket_projectile.action = {
  {type="direct", action_delivery={type="instant", target_effects={
    {type="create-smoke", show_in_tooltip=true, entity_name="poison-cloud", initial_height=0},
    {type="create-particle", particle_name="poison-capsule-metal-particle", repeat_count=8, initial_height=1, initial_vertical_speed=0.1, initial_vertical_speed_deviation=0.05, offset_deviation={{-0.1,-0.1},{0.1,0.1}}, speed_from_center=0.05, speed_from_center_deviation=0.01},
    {type="create-entity", entity_name="slowdown-capsule-explosion"},
    {type="invoke-tile-trigger", repeat_count=1}
  }}},
  {type="area", radius=11, force="enemy", action_delivery={type="instant", target_effects={{type="create-sticker", sticker="slowdown-sticker"}}}}
}

local incendiary_rocket_item = table.deepcopy(base_rocket)
incendiary_rocket_item.name = "incendiary-rocket"
incendiary_rocket_item.icon = "__the-cave__/graphics/chemical_rocket/incendiary-rocket.png"
incendiary_rocket_item.ammo_type.action.action_delivery.projectile = "incendiary-rocket"
incendiary_rocket_item.order = "d[rocket-launcher]-b[explosive]-b"

local fire = table.deepcopy(base_fire)
fire.name = "rocket-fire-flame"
fire.damage_per_tick.amount = 7 / 60
local stream = table.deepcopy(base_stream)
stream.name = "rocket-fire-stream"
stream.action[2].action_delivery.target_effects[1].entity_name = "rocket-fire-flame"

local incendiary_rocket_projectile = table.deepcopy(base_projectile)
incendiary_rocket_projectile.name = "incendiary-rocket"
incendiary_rocket_projectile.action = {
  {type="direct", action_delivery={type="instant", target_effects={
    {type="nested-result", action={type="area", target_entities=false, trigger_from_target=true, repeat_count=60, radius=9, action_delivery={type="stream", stream="rocket-fire-stream"}}},
    {type="play-sound", sound=capsule_explosion_sound},
    {type="invoke-tile-trigger", repeat_count=1}
  }}},
  {type="area", radius=2.5, action_delivery={type="instant", target_effects={{type="create-sticker", sticker="fire-sticker", show_in_tooltip=true}}}}
}

data:extend({fire, stream, chemical_rocket_item, chemical_rocket_projectile, incendiary_rocket_item, incendiary_rocket_projectile,
  {type="recipe", name="chemical-rocket", enabled=false, energy_required=8, ingredients={{type="item",name="rocket",amount=1},{type="item",name="poison-capsule",amount=1},{type="item",name="slowdown-capsule",amount=1}}, results={{type="item",name="chemical-rocket",amount=1}}},
  {type="recipe", name="incendiary-rocket", categories = {"crafting-with-fluid"}, enabled=false, energy_required=8, ingredients={{type="item",name="rocket",amount=1},{type="item",name="steel-plate",amount=5},{type="fluid",name="light-oil",amount=20}}, results={{type="item",name="incendiary-rocket",amount=1}}}
})
