-- Private Advancing Collapse nests.
--
-- They deliberately remain unit-spawners so players can fight and destroy a
-- familiar nest entity, but native spawning is disabled.  The moving assault
-- controller owns every reinforcement and its hard population cap.  Distinct
-- names also keep these nests out of the Queen ecology and ordinary Cave
-- expansion candidate pools.

local PREFIX = "the-cave-advancing-assault-"
local UNIT_PREFIX = "the-cave-train-wave-"
local prototypes_to_add = {}

local function copy_nest(base_name, new_name)
  local source = data.raw["unit-spawner"] and data.raw["unit-spawner"][base_name]
  if not source then return end

  local nest = table.deepcopy(source)
  nest.name = new_name
  nest.localised_name = source.localised_name or { "entity-name." .. base_name }
  nest.autoplace = nil
  nest.hidden_in_factoriopedia = true
  nest.order = "z[the-cave-advancing-assault]-" .. new_name

  -- Scripted reinforcements replace native pollution spawning.  Keep a valid
  -- result_units table for prototype compatibility while making the engine's
  -- owned-unit checks impossible to satisfy.
  nest.max_count_of_owned_units = 0
  nest.max_count_of_owned_defensive_units = 0
  nest.max_friends_around_to_spawn = 0
  nest.max_defensive_friends_around_to_spawn = 0
  nest.spawning_cooldown = { 60 * 60 * 60, 60 * 60 * 60 }
  nest.absorptions_per_second = {}
  prototypes_to_add[#prototypes_to_add + 1] = nest
end

copy_nest("biter-spawner", PREFIX .. "biter-spawner")
copy_nest("spitter-spawner", PREFIX .. "spitter-spawner")
copy_nest("armoured-biter-spawner", PREFIX .. "armoured-biter-spawner")
copy_nest("arachnid-spawner-unitspawner", PREFIX .. "arachnid-spawner-unitspawner")

-- These modules have loaded before this file. Copies retain the integrated
-- families' combat stats/art, but private names bypass Queen/expansion/brood
-- ownership just like the existing scheduled Biter and Spitter attackers.
local arachnid_by_tier = {
  small = "arachnid-biter-drone-unit",
  medium = "arachnid-biter-warrior-unit",
  big = "arachnid-biter-tiger-unit",
  behemoth = "arachnid-biter-royalwarrior-unit",
}
for _, tier in ipairs({ "small", "medium", "big", "behemoth" }) do
  for _, family in ipairs({ "armoured", "arachnid" }) do
    local base_name = family == "armoured" and (tier .. "-armoured-biter") or arachnid_by_tier[tier]
    local source = data.raw.unit[base_name]
    if source then
      local unit = table.deepcopy(source)
      unit.name = UNIT_PREFIX .. tier .. "-" .. family
      unit.localised_name = source.localised_name or { "entity-name." .. base_name }
      unit.autoplace = nil
      unit.hidden_in_factoriopedia = true
      unit.order = "z[the-cave-advancing-assault]-" .. unit.name
      prototypes_to_add[#prototypes_to_add + 1] = unit
    end
  end
end

-- Independent nest-layer: reuse the existing Queen artwork, never her combat
-- or ecology controller. Units require attack parameters, so retain a valid
-- animation but remove every delivery/effect, targeting range and attack AI.
local queen_source = data.raw.unit["maf-boss-arachnid-biter-1"]
if queen_source then
  local queen = table.deepcopy(queen_source)
  queen.name = UNIT_PREFIX .. "advancing-queen"
  queen.localised_name = { "the-cave-advancing-collapse.queen-name" }
  queen.max_health = 50000
  queen.healing_per_tick = 0
  queen.autoplace = nil
  queen.hidden_in_factoriopedia = true
  queen.order = "z[the-cave-advancing-assault]-queen"
  queen.vision_distance = 0
  queen.call_for_help_radius = 0
  queen.min_pursue_time = 0
  queen.max_pursue_distance = 0
  queen.absorptions_to_join_attack = {}
  queen.warcry = nil
  queen.ai_settings = {
    destroy_when_commands_fail = false,
    allow_try_return_to_spawner = false,
    join_attacks = false,
  }
  queen.attack_parameters = {
    type = "projectile",
    range = 0,
    cooldown = 3600,
    animation = table.deepcopy(queen.run_animation),
    ammo_category = "melee",
    -- action is optional. An empty table is parsed as a Trigger lacking its
    -- required type; omit it entirely so this Queen has no attack effects.
    ammo_type = { target_type = "entity" },
  }
  prototypes_to_add[#prototypes_to_add + 1] = queen
end

if #prototypes_to_add > 0 then data:extend(prototypes_to_add) end
