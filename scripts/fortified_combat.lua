local C=require("shared.fortified_combat")
local M={config=C}
local nest_order={"arachnid","snapper","biter","arachnid","snapper","spitter","arachnid","snapper","biter","arachnid","snapper","spitter"}
local function position(room,r,distance,lateral)
    return {x=room%2==1 and r[1]+distance or r[3]-distance,y=(r[2]+r[4])/2+lateral}
end
function M.static_plan(room,tier,r)
    local plan={};local p=C.profiles[tier]
    local function add(key,name,distance,lateral)
        plan[#plan+1]={key=key,name=name,position=position(room,r,distance,lateral)}
    end
    for i,family in ipairs(nest_order) do
        add("nests",C.nest_name(tier,family),40+math.floor((i-1)/2)*24,i%2==1 and -10 or 10)
    end
    for i=1,10 do
        local size=tier<3 and ({"small","medium"})[tier] or (i%2==1 and "big" or "behemoth")
        add("worms",size.."-worm-turret",134+math.floor((i-1)/2)*17,i%2==1 and -3 or 3)
    end
    local total=p.guns+p.lasers+p.flames;local columns=math.ceil(total/2)
    local counts={guns=0,lasers=0,flames=0};local i=0
    while i<total do
        for _,spec in ipairs({{"guns","gun-turret"},{"lasers","the-cave-enemy-laser-turret"},{"flames","the-cave-fortified-flamethrower-turret"}}) do
            if counts[spec[1]]<p[spec[1]] then
                i=i+1;counts[spec[1]]=counts[spec[1]]+1
                add(spec[1],spec[2],170+math.floor((i-1)/2)*75/(columns-1),i%2==1 and -10 or 10)
            end
        end
    end
    return plan
end
function M.populate(record,room,tier,r,surface)
    local stage=record.spiral.built[room];local profile=C.profiles[tier]
    stage.combat_placed=stage.combat_placed or {}
    stage.pending_population=false
    -- Defences are fixed at the agreed counts; only mobile reinforcements scale.
    for i,spec in ipairs(M.static_plan(room,tier,r)) do
        if not stage.combat_placed[i] then
            local direction=room%2==1 and defines.direction.west or defines.direction.east
            if not surface.can_place_entity{name=spec.name,position=spec.position,direction=direction,force="enemy"} then
                stage.pending_population=true;return
            end
            local e=surface.create_entity{name=spec.name,position=spec.position,direction=direction,force="enemy",spawn_decorations=false,snap_to_grid=false}
            if not (e and e.valid) then stage.pending_population=true;return end
            if spec.key=="guns" then e.insert{name="firearm-magazine",count=1000} end
            if spec.key=="flames" then
                e.insert_fluid{name="light-oil",amount=1000};stage.flames[#stage.flames+1]=e
            end
            stage.combat_placed[i]=true
            stage.spawned[spec.key]=(stage.spawned[spec.key] or 0)+1
        end
    end
    local wanted=math.ceil(profile.units*(1+0.5*(record.spiral.peak_players-1)))
    stage.spawned.families=stage.spawned.families or {}
    local lanes={-13,13,-7,7,-3,3,-10,10,0}
    for i=(stage.spawned.units or 0)+1,wanted do
        local name,family=C.unit_spec(tier,room,i)
        -- Quantiles give a low entrance density and gradually more enemies
        -- near the rewards. Later joins add units without refilling dead ones.
        local distance=12+226*math.sqrt(((i-1)%profile.units+0.5)/profile.units)
        local target=position(room,r,distance,lanes[(i-1)%#lanes+1])
        local p=surface.find_non_colliding_position(name,target,10,0.5,true)
        if not p or p.x<r[1]+2 or p.x>=r[3]-2 or p.y<r[2]+2 or p.y>=r[4]-2 then
            stage.pending_population=true;break
        end
        local e=surface.create_entity{name=name,position=p,force="enemy"}
        if not (e and e.valid) then stage.pending_population=true;break end
        e.ai_settings.allow_try_return_to_spawner=false
        e.ai_settings.allow_destroy_when_commands_fail=false
        stage.spawned.units=i
        stage.spawned.families[family]=(stage.spawned.families[family] or 0)+1
    end
end
return M
