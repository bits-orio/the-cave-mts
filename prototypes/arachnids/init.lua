-- Integrated from Arachnids_enemy 1.2.0 (MIT). See
-- third-party/Arachnids_enemy-NOTICE.txt for authorship and modification notes.
require ("util")


local hit_effects = require("__base__/prototypes/entity/hit-effects.lua")
local sounds = require("__base__/prototypes/entity/sounds.lua")

local path = "__the-cave__/arachnids_enemy/"
require("prototypes.arachnids.green_blood")
require("prototypes.arachnids.animations")
require("prototypes.arachnids.entities")


local leviathan_tint1 = {r=1, g=0.1, b=0, a=0}
local leviathan_tint2 = {r=1, g=0.3, b=1, a=0}

local leviathan_scale=2.65



local arach_hit_effect=
  {
    type = "create-entity",
    entity_name = "arachnid-blood-explosion-hit",
    offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
    damage_type_filters = "fire"
  }





local function make_biter_area_damage(damage,radius)
return  {
					type = "area",
					radius = radius,
					force = "enemy",
					ignore_collision_condition = true,
					action_delivery =
					{
					  type = "instant",
					  target_effects =
					  {
						{
						  type = "damage",
						  damage = {amount = damage, type = "physical"}
						},
						{
						type = "create-particle",
						repeat_count = 5,
						particle_name = "explosion-remnants-particle",
						initial_height = 0.5,
						speed_from_center = 0.08,
						speed_from_center_deviation = 0.15,
						initial_vertical_speed = 0.08,
						initial_vertical_speed_deviation = 0.15,
						offset_deviation = {{-0.2, -0.2}, {0.2, 0.2}}
						},
					  }
					}
                   }
end



-- leviathan_scale
local leviathan = table.deepcopy(data.raw.unit["behemoth-biter"])
leviathan.name = "arachnid-biter-leviathan-unit"
leviathan.icon=path .. "graphics/arachnid_icon.png"
leviathan.run_animation = arachnidsrunanimation (leviathan_scale, leviathan_tint1, leviathan_tint2)
leviathan.distance_per_frame = 0.3
leviathan.movement_speed=0.3
leviathan.vision_distance = 50
leviathan.absorptions_to_join_attack = { pollution = 1000 }
leviathan.max_health = 80000
leviathan.resistances = {
      {
        type = "physical",
        decrease = 12,
        percent = 50,
      },
      {
        type = "explosion",
        decrease = 20,
        percent = 50,
      },
      {
        type = "laser",
        percent = -50,
      },
      {
        type = "impact",
        percent = 80,
      },

      {
        type = "fire",
        percent = -50,
      },
      {
        type = "electric",
        percent = -30,
      },
      {
        type = "poison",
        percent = 50,
      },
      {
        type = "acid",
        percent = 100,
      },
    }
leviathan.spawning_time_modifier = 12
leviathan.damaged_trigger_effect = arach_hit_effect
leviathan.collision_box = {{-1.2, -1.2}, {1.2, 1.2}}
leviathan.selection_box = {{-1.2, -2.4}, {1.2, 0.9}}
leviathan.sticker_box = {{-1.2, -2}, {1.2, 0}}
leviathan.dying_explosion = "arachnid-blood-explosion"
leviathan.attack_parameters =
    {
      type = "projectile",
      range = 3,
      cooldown = 35,
      ammo_category = "melee",
      ammo_type =
      {
        target_type = "entity",
        action =
        {
		   make_biter_area_damage(100,3),
          {
		  type = "direct",
          action_delivery =
          {
            type = "instant",
            target_effects =
            {
              {
                type = "damage",
                damage = { amount = 200, type = "physical"}
              },
            }
          }}
        }
      },
      sound =  arachnid_roars(0.9),
      animation =  arachnidsattackanimation (leviathan_scale, leviathan_tint1, leviathan_tint2),
	  range_mode = "bounding-box-to-bounding-box"
    }
leviathan.dying_sound = arachnid_dying(1.1)
leviathan.working_sound = arachnid_calls(1.1)
leviathan.corpse = "arachnid-leviathan-corpse"


local corpse = table.deepcopy(data.raw.corpse["arachnid-royalwarrior-corpse"])
corpse.name = "arachnid-leviathan-corpse"
corpse.localised_name = {"entity-name.arachnid-leviathan-corpse"}
corpse.animation = arachnidsdieanimation (leviathan_scale, leviathan_tint1, leviathan_tint2)
corpse.ground_patch = get_arachnids_ground_patch(leviathan_scale)
data:extend({leviathan,corpse})


local spawner = data.raw["unit-spawner"]["arachnid-spawner-unitspawner"]
spawner.icon=path .. "graphics/spawner_icon.png"
spawner.result_units = (function()
                     local res = {}
						res[1] = {"arachnid-biter-drone-unit", {{0.0, 0.3}, {0.6, 0.0}}}
						res[2] = {"arachnid-biter-warrior-unit", {{0.2, 0.0}, {0.6, 0.3}, {0.7, 0.1}}}
						res[3] = {"arachnid-biter-tiger-unit", {{0.5, 0.0}, {1.0, 0.4}}}
						res[4] = {"arachnid-biter-royalwarrior-unit", {{0.9, 0.0}, {1.0, 0.3}}}
						res[5] = {"arachnid-spitter-smallspitter-unit", {{0.25, 0.0}, {0.5, 0.3}, {0.7, 0.0}}}
						res[6] = {"arachnid-spitter-mediumspitter-unit", {{0.4, 0.0}, {0.7, 0.3}, {0.9, 0.1}}}
						res[7] = {"arachnid-spitter-bigspitter-unit", {{0.5, 0.0}, {1.0, 0.4}}}
						res[8] = {"arachnid-spitter-behemothspitter-unit", {{0.9, 0.0}, {1.0, 0.3}}}
						res[9] = {"arachnid-biter-leviathan-unit", {{0.965, 0.0}, {1.0, 0.03}}}
                     return res
                   end)()
spawner.damaged_trigger_effect = hit_effects.rock()
spawner.dying_explosion = nil






local names = {"arachnid-spitter-smallspitter-unit","arachnid-spitter-mediumspitter-unit","arachnid-spitter-bigspitter-unit","arachnid-spitter-behemothspitter-unit",
				"arachnid-biter-drone-unit","arachnid-biter-warrior-unit","arachnid-biter-tiger-unit","arachnid-biter-royalwarrior-unit"}
for x=1, #names do
	local unit = data.raw.unit[names[x]]
	unit.damaged_trigger_effect = arach_hit_effect
	unit.dying_explosion = "arachnid-blood-explosion"
    unit.movement_speed = unit.movement_speed * 1.2
	unit.icon=path .. "graphics/arachnid_icon.png"
	end












-- BOSSES

local arachnid_boss_health = {
  [1] = 100000,
  [2] = 150000,
  [3] = 200000,
}

local function make_boss(k)
local scale = 1.5 + k/3
local base_resist = 17+k*2
local resistances =
    {
      {
        type = "physical",
        decrease = k,
        percent = base_resist,
      },
      {
        type = "explosion",
        decrease = k,
        percent = base_resist,
      },
      {
        type = "laser",
        percent = -50+k,
      },
      {
        type = "impact",
        percent = base_resist,
      },

      {
        type = "fire",
        percent = -50+k,
      },
      {
        type = "electric",
        percent = -50+k,
      },
      {
        type = "poison",
        percent = 50,
      },
      {
        type = "acid",
        percent = 100,
      },
    }

local attack_actions = {
  {
    action_delivery = {
      target_effects = {
        damage = {
          amount = (110+k*50),
          type = "physical"
        },
        type = "damage",
        show_in_tooltip = true
      },
      type = "instant"
    },
    type = "direct"
  },
}
-- Levels 1-3 are the only Queen prototypes used by The Cave. Their passive
-- travel AI may attack a blocking frontier rock, so keep that strike strictly
-- single-target; otherwise the legacy pulse can destroy several adjacent
-- rocks and resolve several full digs from one obstacle attack.
if k > 3 then
  attack_actions[#attack_actions + 1] = make_biter_area_damage((50+k*10),k+1)
end

data:extend(
{

  {
    type = "unit",
    name = "maf-boss-arachnid-biter-"..k,
	localised_name =  {"",{"entity-name.maf-boss-arachnid-biter"}," ",tostring(k)},
    order="b-r-d-BOSS"..k,
	icon=path .. "graphics/arachnid_icon.png", icon_size=64,
    flags = {"placeable-player", "placeable-enemy", "placeable-off-grid", "breaths-air", "not-repairable"},
    -- The Cave only selects levels 1-3. Keep the upstream values for the
    -- unused higher prototypes so this balance change stays narrowly scoped.
    max_health = arachnid_boss_health[k] or 50000 * k,
    subgroup="enemies",
    resistances = resistances,
    spawning_time_modifier = 12,
    -- Queen regeneration is damage-delayed and zone-scaled by the runtime
    -- controller; passive prototype healing would bypass that 30-second delay.
    healing_per_tick = 0,
    collision_box = {{-1.2, -1.2}, {1.2, 1.2}},
    selection_box = {{-1.7, -2.4}, {1.7, 2.4}},
    sticker_box = {{-0.7, -1.2}, {0.7, 0.2}},
    distraction_cooldown = 100,
	call_for_help_radius = 100+k*5,
    min_pursue_time = 10 * 60,
    max_pursue_distance = 50,
    attack_parameters =
                {
                    type = "projectile",
                    range = 1+k/5,
                    cooldown = 35,
                    sound =  arachnid_roars(1),
                    animation = arachnidsattackanimation (scale, leviathan_tint1, leviathan_tint2),
                    ammo_category = "melee",
                    ammo_type = {
							  target_type = "entity",
								action = attack_actions,
							}
                },

    vision_distance = 30,
    movement_speed = 0.3,
    distance_per_frame = 0.3,
    absorptions_to_join_attack = { pollution = 300 + k*10 },
    corpse = "corpse-maf-boss-arachnid-biter-"..k,
    dying_explosion = "arachnid-blood-explosion",
	dying_sound = arachnid_dying(1.1),
	working_sound = arachnid_calls(1.1),
    walking_sound = sounds.biter_walk_big(1.2),
	running_sound_animation_positions = {2,},
    damaged_trigger_effect = arach_hit_effect,
	water_reflection = biter_water_reflection(scale),
    run_animation = arachnidsrunanimation (scale, leviathan_tint1, leviathan_tint2),
	ai_settings = {destroy_when_commands_fail = false},
  },
})

	local corpse = table.deepcopy(data.raw.corpse["arachnid-royalwarrior-corpse"])
	corpse.name = "corpse-maf-boss-arachnid-biter-"..k
	corpse.localised_name = {"", {"entity-name.maf-boss-arachnid-corpse"}, " ", tostring(k)}
	corpse.animation = arachnidsdieanimation (scale, leviathan_tint1, leviathan_tint2)
  corpse.ground_patch = get_arachnids_ground_patch(scale)
	data:extend({corpse})
end

for k=1,10 do make_boss(k) end
