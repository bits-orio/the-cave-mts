local C=require("shared.fortified_combat")
-- Big and Behemoth units normally multiply a nest's interval by 3 or 12.
-- Local offspring copies keep the agreed six-second hard-room cadence without
-- changing any ordinary unit, initial room unit, or overworld nest.
for name,base in pairs(C.offspring_aliases) do
    local unit=table.deepcopy(assert(data.raw.unit[base],base))
    unit.name=name;unit.localised_name=unit.localised_name or {"entity-name."..base}
    unit.spawning_time_modifier=1;unit.hidden_in_factoriopedia=true
    data:extend({unit})
end
-- Dedicated nests leave every overworld nest's evolution and cooldown intact.
for tier,profile in ipairs(C.profiles) do
    for _,family in ipairs(C.families) do
        local base=C.nest_bases[family]
        local nest=table.deepcopy(assert(data.raw["unit-spawner"][base],base))
        nest.name=C.nest_name(tier,family)
        nest.localised_name=nest.localised_name or {"entity-name."..base}
        nest.autoplace=nil;nest.captured_spawner_entity=nil
        nest.spawning_cooldown={profile.cooldown,profile.cooldown}
        nest.result_units={}
        for size=(tier<3 and tier or 3),(tier<3 and tier or 4) do
            nest.result_units[#nest.result_units+1]={C.nest_unit(family,size),{{0,1},{1,1}}}
        end
        data:extend({nest})
    end
end

-- This entire flame chain belongs only to Fortified enemy turrets. Player fire
-- and vanilla fire resistance are unchanged, including at overlapping positions.
local prefix="the-cave-fortified-"
local function enemy_damage(amount)
    return {type="direct",force="enemy",filter_enabled=true,ignore_collision_condition=true,
        action_delivery={type="instant",target_effects={{type="damage",damage={amount=amount,type="fire"},apply_damage_to_trees=false}}}}
end
for _,name in ipairs({"fire-flame","fire-flame-on-tree"}) do
    local fire=table.deepcopy(data.raw.fire[name])
    fire.name=prefix..name;fire.localised_name={"entity-name.fire-flame"}
    fire.damage_tick_interval=fire.damage_tick_interval or 10
    fire.on_damage_tick_effect=enemy_damage(fire.damage_per_tick.amount*fire.damage_tick_interval)
    fire.damage_per_tick={amount=0,type="fire"}
    fire.spawn_entity=prefix.."fire-flame-on-tree"
    data:extend({fire})
end
local sticker=table.deepcopy(data.raw.sticker["fire-sticker"])
sticker.name=prefix.."fire-sticker"
sticker.spread_fire_entity=prefix.."fire-flame-on-tree"
data:extend({sticker})
local stream=table.deepcopy(data.raw.stream["flamethrower-fire-stream"])
stream.name=prefix.."flamethrower-fire-stream"
for _,action in ipairs(stream.action) do
    if action.type=="area" then action.force="enemy" end
    for _,effect in ipairs(action.action_delivery.target_effects) do
        if effect.type=="create-sticker" then effect.sticker=sticker.name end
        if effect.type=="create-fire" then effect.entity_name=prefix.."fire-flame" end
    end
end
data:extend({stream})
local turret=table.deepcopy(data.raw["fluid-turret"]["flamethrower-turret"])
turret.name=prefix.."flamethrower-turret"
turret.localised_name={"entity-name.flamethrower-turret"}
turret.minable=nil;turret.placeable_by=nil;turret.next_upgrade=nil
local function replace_stream(node)
    if type(node)~="table" then return end
    for key,value in pairs(node) do
        if key=="stream" and value=="flamethrower-fire-stream" then node[key]=stream.name
        elseif type(value)=="table" then replace_stream(value) end
    end
end
replace_stream(turret.attack_parameters)
data:extend({turret})
