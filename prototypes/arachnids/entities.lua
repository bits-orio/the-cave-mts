
-- Arachnids_enemy 1.2.0 entity definitions (MIT). The original autoplace is
-- deliberately omitted: The Cave creates all enemy rooms and ambushes by script.
require("prototypes.arachnids.sounds")

small_arachnid_scale = 0.9
small_arachnid_tint1 = {r=1, g=0.6, b=0, a=0}
small_arachnid_tint2 = {r=1 , g=0.9, b=0, a=0}

medium_arachnid_scale = 1.3
medium_arachnid_tint1 = {r=1, g=0.1, b=0, a=0.6}
medium_arachnid_tint2 = {r=1, g=0.3, b=1, a=0.6}

big_arachnid_scale = 1.5
big_arachnid_tint1 = {r=0.2, g=0.2, b=0.8, a=0.5}
big_arachnid_tint2 ={r=0, g=0.4, b=0.4, a=0.5}

behemoth_arachnid_scale = 1.9
behemoth_arachnid_tint1 = {r=0.1, g=0.9, b=0.2, a=0.6}
behemoth_arachnid_tint2 = {r=0.3, g=0.7, b=0.1,a=0.6}



arachnid_spawner_scale_0 = 1.5
arachnid_spawner_scale_1 = 1.7
arachnid_spawner_scale_2 = 2
arachnid_spawner_scale_3 = 2.2





arachnids_alternative_attacking_animation_sequence =
{
  warmup_frame_sequence = { 1, 2, 3, 4, 5, 6 },
  warmup2_frame_sequence = { 7, 7, 7, 7, 7, 7 },
  attacking_frame_sequence = { 7, 8, 9, 10, 11, 10, 9, 8, 7 },
  cooldown_frame_sequence = { 7 },
  prepared_frame_sequence = { 7 },
  back_to_walk_frame_sequence = { 6, 5, 4, 3, 2, 1 },

  warmup_animation_speed = 1 / 6 * 0.4,
  attacking_animation_speed = 1 / 16 * 0.4,
  cooldown_animation_speed = 1 / 1 * 0.4 * 0.125,
  prepared_animation_speed = 1 / 1 * 0.5 * 0.4,
  back_to_walk_animation_speed = 1 / 6 * 0.4
}



local make_unit_melee_ammo_type = function(damage_value)
  return
  {
    target_type = "entity",
    action =
    {
      type = "direct",
      action_delivery =
      {
        type = "instant",
        target_effects =
        {
          type = "damage",
          damage = { amount = damage_value , type = "physical"}
        }
      }
    }
  }
end


Arachnid_Drone_Unit = table.deepcopy(data.raw.unit["small-biter"])
Arachnid_Drone_Unit.name = "arachnid-biter-drone-unit"
Arachnid_Drone_Unit.max_health = 30
Arachnid_Drone_Unit.run_animation = arachnidsrunanimation (small_arachnid_scale, small_arachnid_tint1, small_arachnid_tint2)
Arachnid_Drone_Unit.distance_per_frame = 0.2
Arachnid_Drone_Unit.attack_parameters.ammo_type = make_unit_melee_ammo_type(15)
Arachnid_Drone_Unit.attack_parameters.sound = arachnid_roars(0.35)
Arachnid_Drone_Unit.attack_parameters.animation = arachnidsattackanimation (small_arachnid_scale, small_arachnid_tint1, small_arachnid_tint2)
Arachnid_Drone_Unit.dying_sound =  arachnid_dying(0.5)
Arachnid_Drone_Unit.working_sound =  arachnid_calls(0.75)
Arachnid_Drone_Unit.corpse = "arachnid-drone-corpse"
Arachnid_Drone_Unit.localised_name = {"entity-name.arachnid-drone"}

data:extend{Arachnid_Drone_Unit}

Arachnid_Warrior_Unit = table.deepcopy(data.raw.unit["medium-biter"])
Arachnid_Warrior_Unit.name = "arachnid-biter-warrior-unit"
Arachnid_Warrior_Unit.max_health = 100
Arachnid_Warrior_Unit.run_animation = arachnidsrunanimation (medium_arachnid_scale, medium_arachnid_tint1, medium_arachnid_tint2)
Arachnid_Warrior_Unit.distance_per_frame = 0.225
Arachnid_Warrior_Unit.attack_parameters.ammo_type = make_unit_melee_ammo_type(30)
Arachnid_Warrior_Unit.attack_parameters.sound = arachnid_roars(0.35)
Arachnid_Warrior_Unit.attack_parameters.animation = arachnidsattackanimation (medium_arachnid_scale, medium_arachnid_tint1, medium_arachnid_tint2)
Arachnid_Warrior_Unit.dying_sound =  arachnid_dying(0.5)
Arachnid_Warrior_Unit.working_sound =  arachnid_calls(0.75)
Arachnid_Warrior_Unit.corpse = "arachnid-warrior-corpse"
Arachnid_Warrior_Unit.localised_name = {"entity-name.arachnid-warrior"}

data:extend{Arachnid_Warrior_Unit}

Arachnid_Tiger_Unit = table.deepcopy(data.raw.unit["big-biter"])
Arachnid_Tiger_Unit.name = "arachnid-biter-tiger-unit"
Arachnid_Tiger_Unit.run_animation = arachnidsrunanimation (big_arachnid_scale, big_arachnid_tint1, big_arachnid_tint2)
Arachnid_Tiger_Unit.distance_per_frame = 0.25
Arachnid_Tiger_Unit.attack_parameters.ammo_type = make_unit_melee_ammo_type(45)
Arachnid_Tiger_Unit.attack_parameters.sound = arachnid_roars(0.35)
Arachnid_Tiger_Unit.attack_parameters.animation = arachnidsattackanimation (big_arachnid_scale, big_arachnid_tint1, big_arachnid_tint2)
Arachnid_Tiger_Unit.dying_sound =  arachnid_dying(0.5)
Arachnid_Tiger_Unit.working_sound =  arachnid_calls(0.75)
Arachnid_Tiger_Unit.corpse = "arachnid-tiger-corpse"
Arachnid_Tiger_Unit.localised_name = {"entity-name.arachnid-tiger"}

data:extend{Arachnid_Tiger_Unit}

Arachnid_Royal_Warrior_Unit = table.deepcopy(data.raw.unit["behemoth-biter"])
Arachnid_Royal_Warrior_Unit.name = "arachnid-biter-royalwarrior-unit"
Arachnid_Royal_Warrior_Unit.run_animation = arachnidsrunanimation (behemoth_arachnid_scale, behemoth_arachnid_tint1, behemoth_arachnid_tint2)
Arachnid_Royal_Warrior_Unit.distance_per_frame = 0.3
Arachnid_Royal_Warrior_Unit.attack_parameters.ammo_type = make_unit_melee_ammo_type(135)
Arachnid_Royal_Warrior_Unit.attack_parameters.sound = arachnid_roars(0.35)
Arachnid_Royal_Warrior_Unit.attack_parameters.animation = arachnidsattackanimation (behemoth_arachnid_scale, behemoth_arachnid_tint1, behemoth_arachnid_tint2)
Arachnid_Royal_Warrior_Unit.dying_sound =  arachnid_dying(0.5)
Arachnid_Royal_Warrior_Unit.working_sound =  arachnid_calls(0.75)
Arachnid_Royal_Warrior_Unit.corpse = "arachnid-royalwarrior-corpse"
Arachnid_Royal_Warrior_Unit.localised_name = {"entity-name.arachnid-royalwarrior"}

data:extend{Arachnid_Royal_Warrior_Unit}

Arachnid_Unit_Spawner = table.deepcopy(data.raw["unit-spawner"]["biter-spawner"])
Arachnid_Unit_Spawner.name = "arachnid-spawner-unitspawner"
Arachnid_Unit_Spawner.graphics_set = {animations = {arachnids_spawner_idle_animation(arachnid_spawner_scale_0,0),arachnids_spawner_idle_animation(arachnid_spawner_scale_1,1),arachnids_spawner_idle_animation(arachnid_spawner_scale_2,2),arachnids_spawner_idle_animation(arachnid_spawner_scale_3,3)}}
Arachnid_Unit_Spawner.decay_animation = nil
Arachnid_Unit_Spawner.corpse = "arachnid-unitspawner-corpse"
Arachnid_Unit_Spawner.result_units = (function()
                     local res = {}
						res[1] = {"arachnid-biter-drone-unit", {{0.0, 0.3}, {0.6, 0.0}}}
						res[2] = {"arachnid-biter-warrior-unit", {{0.2, 0.0}, {0.6, 0.3}, {0.7, 0.1}}}
						res[3] = {"arachnid-biter-tiger-unit", {{0.5, 0.0}, {1.0, 0.4}}}
						res[4] = {"arachnid-biter-royalwarrior-unit", {{0.9, 0.0}, {1.0, 0.3}}}
                     return res
                   end)()
Arachnid_Unit_Spawner.autoplace = nil
Arachnid_Unit_Spawner.spawning_cooldown = {150, 90}

data:extend{Arachnid_Unit_Spawner}

Arachnid_Small_Spitter_Unit = table.deepcopy(data.raw.unit["small-spitter"])
Arachnid_Small_Spitter_Unit.name = "arachnid-spitter-smallspitter-unit"
Arachnid_Small_Spitter_Unit.run_animation = arachnidsrunanimation (small_arachnid_scale, small_arachnid_tint1, small_arachnid_tint2)
Arachnid_Small_Spitter_Unit.distance_per_frame = 0.225
Arachnid_Small_Spitter_Unit.attack_parameters.animation = arachnidsattackanimation (small_arachnid_scale, small_arachnid_tint1, small_arachnid_tint2)
Arachnid_Small_Spitter_Unit.alternative_attacking_frame_sequence = arachnids_alternative_attacking_animation_sequence
Arachnid_Small_Spitter_Unit.corpse = "arachnid-smallspitter-corpse"

data:extend{Arachnid_Small_Spitter_Unit}

Arachnid_Medium_Spitter_Unit = table.deepcopy(data.raw.unit["medium-spitter"])
Arachnid_Medium_Spitter_Unit.name = "arachnid-spitter-mediumspitter-unit"
Arachnid_Medium_Spitter_Unit.run_animation = arachnidsrunanimation (medium_arachnid_scale, medium_arachnid_tint1, medium_arachnid_tint2)
Arachnid_Medium_Spitter_Unit.distance_per_frame = 0.225
Arachnid_Medium_Spitter_Unit.attack_parameters.animation = arachnidsattackanimation (medium_arachnid_scale, medium_arachnid_tint1, medium_arachnid_tint2)
Arachnid_Medium_Spitter_Unit.alternative_attacking_frame_sequence = arachnids_alternative_attacking_animation_sequence
Arachnid_Medium_Spitter_Unit.corpse = "arachnid-mediumspitter-corpse"

data:extend{Arachnid_Medium_Spitter_Unit}

Arachnid_Big_Spitter_Unit = table.deepcopy(data.raw.unit["big-spitter"])
Arachnid_Big_Spitter_Unit.name = "arachnid-spitter-bigspitter-unit"
Arachnid_Big_Spitter_Unit.run_animation = arachnidsrunanimation (big_arachnid_scale, big_arachnid_tint1, big_arachnid_tint2)
Arachnid_Big_Spitter_Unit.distance_per_frame = 0.225
Arachnid_Big_Spitter_Unit.attack_parameters.animation = arachnidsattackanimation (big_arachnid_scale, big_arachnid_tint1, big_arachnid_tint2)
Arachnid_Big_Spitter_Unit.alternative_attacking_frame_sequence = arachnids_alternative_attacking_animation_sequence
Arachnid_Big_Spitter_Unit.corpse = "arachnid-bigspitter-corpse"

data:extend{Arachnid_Big_Spitter_Unit}

Arachnid_Behemoth_Spitter_Unit = table.deepcopy(data.raw.unit["behemoth-spitter"])
Arachnid_Behemoth_Spitter_Unit.name = "arachnid-spitter-behemothspitter-unit"
Arachnid_Behemoth_Spitter_Unit.run_animation = arachnidsrunanimation (behemoth_arachnid_scale, behemoth_arachnid_tint1, behemoth_arachnid_tint2)
Arachnid_Behemoth_Spitter_Unit.distance_per_frame = 0.225
Arachnid_Behemoth_Spitter_Unit.attack_parameters.animation = arachnidsattackanimation (behemoth_arachnid_scale, behemoth_arachnid_tint1, behemoth_arachnid_tint2)
Arachnid_Behemoth_Spitter_Unit.alternative_attacking_frame_sequence = arachnids_alternative_attacking_animation_sequence
Arachnid_Behemoth_Spitter_Unit.corpse = "arachnid-behemothspitter-corpse"
data:extend{Arachnid_Behemoth_Spitter_Unit}



arachnid_drone_corpse = table.deepcopy(data.raw.corpse["small-biter-corpse"])
arachnid_drone_corpse.name = "arachnid-drone-corpse"
arachnid_drone_corpse.ground_patch = get_arachnids_ground_patch(small_arachnid_scale)
arachnid_drone_corpse.animation = arachnidsdieanimation (small_arachnid_scale, small_arachnid_tint1, small_arachnid_tint2)
arachnid_drone_corpse.decay_animation=nil
arachnid_drone_corpse.localised_name = {"entity-name.arachnid-drone-corpse"}

data:extend{arachnid_drone_corpse}

arachnid_warrior_corpse = table.deepcopy(data.raw.corpse["medium-biter-corpse"])
arachnid_warrior_corpse.name = "arachnid-warrior-corpse"
arachnid_warrior_corpse.ground_patch = get_arachnids_ground_patch(medium_arachnid_scale)
arachnid_warrior_corpse.decay_animation=nil
arachnid_warrior_corpse.animation = arachnidsdieanimation (medium_arachnid_scale, medium_arachnid_tint1, medium_arachnid_tint2)
arachnid_warrior_corpse.localised_name = {"entity-name.arachnid-warrior-corpse"}

data:extend{arachnid_warrior_corpse}

arachnid_tiger_corpse = table.deepcopy(data.raw.corpse["big-biter-corpse"])
arachnid_tiger_corpse.name = "arachnid-tiger-corpse"
arachnid_tiger_corpse.ground_patch = get_arachnids_ground_patch(big_arachnid_scale)
arachnid_tiger_corpse.animation = arachnidsdieanimation (big_arachnid_scale, big_arachnid_tint1, big_arachnid_tint2)
arachnid_tiger_corpse.decay_animation=nil
arachnid_tiger_corpse.localised_name = {"entity-name.arachnid-tiger-corpse"}

data:extend{arachnid_tiger_corpse}

arachnid_royalwarrior_corpse = table.deepcopy(data.raw.corpse["behemoth-biter-corpse"])
arachnid_royalwarrior_corpse.name = "arachnid-royalwarrior-corpse"
arachnid_royalwarrior_corpse.ground_patch = get_arachnids_ground_patch(behemoth_arachnid_scale)
arachnid_royalwarrior_corpse.animation = arachnidsdieanimation (behemoth_arachnid_scale, behemoth_arachnid_tint1, behemoth_arachnid_tint2)
arachnid_royalwarrior_corpse.decay_animation=nil
arachnid_royalwarrior_corpse.localised_name = {"entity-name.arachnid-royalwarrior-corpse"}

data:extend{arachnid_royalwarrior_corpse}

arachnid_unitspawner_corpse = table.deepcopy(data.raw.corpse["biter-spawner-corpse"])
arachnid_unitspawner_corpse.name = "arachnid-unitspawner-corpse"
arachnid_unitspawner_corpse.animation = {arachnids_spawner_die_animation(arachnid_spawner_scale_0,0),arachnids_spawner_die_animation(arachnid_spawner_scale_1,1),arachnids_spawner_die_animation(arachnid_spawner_scale_2,2),arachnids_spawner_die_animation(arachnid_spawner_scale_3,3)}
arachnid_unitspawner_corpse.decay_animation=nil
arachnid_unitspawner_corpse.dying_speed = 0.04
arachnid_unitspawner_corpse.localised_name = {"entity-name.arachnid-unitspawner-corpse"}

data:extend{arachnid_unitspawner_corpse}

arachnid_smallspitter_corpse = table.deepcopy(data.raw.corpse["small-spitter-corpse"])
arachnid_smallspitter_corpse.name = "arachnid-smallspitter-corpse"
arachnid_smallspitter_corpse.ground_patch = get_arachnids_ground_patch(small_arachnid_scale)
arachnid_smallspitter_corpse.animation = arachnidsdieanimation (small_arachnid_scale, small_arachnid_tint1, small_arachnid_tint2)
arachnid_smallspitter_corpse.decay_animation=nil
arachnid_smallspitter_corpse.localised_name = {"entity-name.arachnid-smallspitter-corpse"}

data:extend{arachnid_smallspitter_corpse}

arachnid_mediumspitter_corpse = table.deepcopy(data.raw.corpse["medium-spitter-corpse"])
arachnid_mediumspitter_corpse.name = "arachnid-mediumspitter-corpse"
arachnid_mediumspitter_corpse.ground_patch = get_arachnids_ground_patch(medium_arachnid_scale)
arachnid_mediumspitter_corpse.animation = arachnidsdieanimation (medium_arachnid_scale, medium_arachnid_tint1, medium_arachnid_tint2)
arachnid_mediumspitter_corpse.decay_animation=nil
arachnid_mediumspitter_corpse.localised_name = {"entity-name.arachnid-mediumspitter-corpse"}

data:extend{arachnid_mediumspitter_corpse}

arachnid_bigspitter_corpse = table.deepcopy(data.raw.corpse["big-spitter-corpse"])
arachnid_bigspitter_corpse.name = "arachnid-bigspitter-corpse"
arachnid_bigspitter_corpse.ground_patch = get_arachnids_ground_patch(big_arachnid_scale)
arachnid_bigspitter_corpse.animation = arachnidsdieanimation (big_arachnid_scale, big_arachnid_tint1, big_arachnid_tint2)
arachnid_bigspitter_corpse.decay_animation=nil
arachnid_bigspitter_corpse.localised_name = {"entity-name.arachnid-bigspitter-corpse"}

data:extend{arachnid_bigspitter_corpse}

arachnid_behemothspitter_corpse = table.deepcopy(data.raw.corpse["behemoth-spitter-corpse"])
arachnid_behemothspitter_corpse.name = "arachnid-behemothspitter-corpse"
arachnid_behemothspitter_corpse.ground_patch = get_arachnids_ground_patch(behemoth_arachnid_scale)
arachnid_behemothspitter_corpse.animation = arachnidsdieanimation (behemoth_arachnid_scale, behemoth_arachnid_tint1, behemoth_arachnid_tint2)
arachnid_behemothspitter_corpse.decay_animation=nil
arachnid_behemothspitter_corpse.localised_name = {"entity-name.arachnid-behemothspitter-corpse"}

data:extend{arachnid_behemothspitter_corpse}
