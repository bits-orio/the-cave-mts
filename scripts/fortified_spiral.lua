-- Versioned Fortified rooms preserve already-entered raid rules.
local physical = require("scripts.player_physical")
local information_gui = require("scripts.information_gui")
local layouts = require("scripts.fortified_spiral_layout")
local combat = require("scripts.fortified_combat")
local M = {}
M.VERSION = layouts.current
M.layout = layouts.get
M.rects = layouts[layouts.current].rects
M.loot_counts = layouts[layouts.current].loot_counts
M.minutes = {7,8,10}
M.tiles = {"the-cave-fortified-floor-green", "the-cave-fortified-floor-yellow", "the-cave-fortified-floor-red"}
M.tiers = {"standard", "secure", "high"}
M.fixtures = {
    { units=3, nests=1, guns=1, lasers=0, flames=0 },
    { units=4, nests=2, guns=2, lasers=1, flames=0 },
    { units=6, nests=2, guns=2, lasers=1, flames=1 },
}
local types = {"unit", "unit-spawner", "turret", "ammo-turret", "electric-turret", "fluid-turret", "artillery-turret"}
local boundary_name = "the-cave-fortified-enemy-boundary"
local function is_infestation(entity)
    return entity.name:sub(1, 18) == "the-cave-darkness-"
end
function M.count(record) return #M.layout(record).rects end
function M.tier(n,record) return math.floor((n-1)/(M.layout(record).stages_per_tier or 5))+1 end
function M.stage_minutes(n,record)
    local tier=M.tier(n,record)
    return M.layout(record).combat and combat.config.profiles[tier].minutes or M.minutes[tier]
end
function M.text_key(record,suffix)
    if suffix=="rules" and M.layout(record).hall and not M.layout(record).combat then
        return "the-cave-fortified-vault.legacy-rooms-rules"
    end
    return "the-cave-fortified-vault."..(M.layout(record).hall and "rooms-" or "spiral-")..suffix
end
local function rect(n,record) local layout=M.layout(record);return n==0 and layout.hall or layout.rects[n] end
function M.area(n,record) local r=rect(n,record); return {{r[1],r[2]},{r[3],r[4]}} end
function M.inside(n,p,margin,record)
    local r=rect(n,record); margin=margin or 0
    return r and p.x>=r[1]+margin and p.x<r[3]-margin and p.y>=r[2]+margin and p.y<r[4]-margin
end
function M.stage_at(p,record)
    if M.inside(0,p,0,record) then return 0 end
    for n=1,M.count(record) do if M.inside(n,p,0,record) then return n end end
end
local function point(n,from_end,lateral,record)
    local r=M.layout(record).rects[n]; local cx,cy=(r[1]+r[3])/2,(r[2]+r[4])/2
    if M.layout(record).hall then
        return {x=n%2==1 and r[3]-from_end or r[1]+from_end,y=cy+lateral}
    end
    if n==15 then return {x=r[3]-from_end,y=cy+lateral} end
    local d=(n-1)%4
    if d==0 then return {x=r[1]+from_end,y=cy+lateral}
    elseif d==1 then return {x=cx+lateral,y=r[4]-from_end}
    elseif d==2 then return {x=r[3]-from_end,y=cy+lateral}
    else return {x=cx+lateral,y=r[2]+from_end} end
end
local function surface_for(record)
    local s=record.child_surface_index and game.surfaces[record.child_surface_index]
    return s and s.valid and s or nil
end
function M.enemies(record,n)
    local surface=surface_for(record)
    local enemies = surface and surface.find_entities_filtered {area=M.area(n,record),force="enemy",type=types} or {}
    local defenders = {}
    for _, entity in pairs(enemies) do
        if not is_infestation(entity) then defenders[#defenders + 1] = entity end
    end
    return defenders
end
local function tile_name(record,x,y)
    local layout=M.layout(record)
    if M.inside(0,{x=x,y=y},0,record) then return layout.hall_tile end
    for n in pairs(record.spiral and record.spiral.built or {}) do
        if M.inside(n,{x=x,y=y},0,record) then return M.tiles[M.tier(n,record)] end
    end
    return "out-of-map"
end
function M.on_chunk_generated(record,event)
    local tiles={}
    for x=event.area.left_top.x,event.area.right_bottom.x-1 do
        for y=event.area.left_top.y,event.area.right_bottom.y-1 do
            tiles[#tiles+1]={name=tile_name(record,x,y),position={x,y}}
        end
    end
    event.surface.set_tiles(tiles,false,false,true,false)
    event.surface.destroy_decoratives {area=event.area}
end
local function floor(record,n)
    local surface=surface_for(record);local r=rect(n,record);local tiles={}
    local name=n==0 and M.layout(record).hall_tile or M.tiles[M.tier(n,record)]
    for x=r[1],r[3]-1 do for y=r[2],r[4]-1 do
        tiles[#tiles+1]={name=name,position={x,y}}
    end end
    surface.set_tiles(tiles,false,true,true,false)
end
local function fixed(record,n,name,p)
    local surface=surface_for(record)
    assert(surface.can_place_entity{name=name,position=p,force="neutral"},"Fortified placement blocked: "..name)
    local e=assert(surface.create_entity{name=name,position=p,force="neutral",create_build_effect_smoke=false})
    local b=e.bounding_box;local r=rect(n,record)
    assert(b.left_top.x>=r[1]+1 and b.left_top.y>=r[2]+1 and b.right_bottom.x<=r[3]-1 and b.right_bottom.y<=r[4]-1,"Fortified object outside corridor")
    e.destructible=false;e.minable_flag=false
    return e
end
local function boundary(record,n)
    local layout=M.layout(record)
    if n==1 and not layout.hall then return end
    local surface=surface_for(record);local rects=layout.rects;local r=rects[n];local prev=layout.hall or rects[n-1]
    local points={}
    if r[2]==prev[4] or r[4]==prev[2] then
        local y=r[2]==prev[4] and r[2]+0.5 or r[4]-0.5
        for x=math.max(r[1],prev[1]),math.min(r[3],prev[3])-1 do points[#points+1]={x=x+0.5,y=y} end
    else
        local x=r[1]==prev[3] and r[1]+0.5 or r[3]-0.5
        for y=math.max(r[2],prev[2]),math.min(r[4],prev[4])-1 do points[#points+1]={x=x,y=y+0.5} end
    end
    local entities={}
    for _,p in ipairs(points) do
        local e=assert(surface.create_entity{name=boundary_name,position=p,force="neutral"})
        e.destructible=false;e.minable_flag=false
        entities[#entities+1]=e
    end
    record.spiral.built[n].boundaries=entities
end
local function enemy(record,n,name,index,total)
    local surface=surface_for(record);local r=M.layout(record).rects[n]
    local length=math.max(r[3]-r[1],r[4]-r[2])
    local target=point(n,length*(0.80-0.30*(index-1)/math.max(1,total-1)),((index-1)%3-1)*5,record)
    local function good(p)
        if not p or not M.inside(n,p,3,record) then return false end
        return prototypes.entity[name].type=="unit" or surface.can_place_entity{name=name,position=p,force="enemy"}
    end
    local p=surface.find_non_colliding_position(name,target,12,0.5,true)
    if not good(p) then
        p=nil
        for x=r[1]+4,r[3]-4,2 do
            for y=r[2]+4,r[4]-4,2 do
                local candidate={x=x,y=y}
                local free=surface.find_non_colliding_position(name,candidate,0,0.5,true)
                if good(free) then p=free;break end
            end
            if p then break end
        end
    end
    if not p then return nil end -- player construction can temporarily block reinforcements
    local direction=n==15 and defines.direction.west or ({defines.direction.east,defines.direction.north,defines.direction.west,defines.direction.south})[(n-1)%4+1]
    if M.layout(record).hall then direction=n%2==1 and defines.direction.west or defines.direction.east end
    local e=surface.create_entity{name=name,position=p,force="enemy",direction=direction,spawn_decorations=false}
    if not (e and e.valid) then return nil end
    if name=="gun-turret" then e.insert{name="firearm-magazine",count=1000} end
    if e.type=="fluid-turret" then
        e.insert_fluid{name="light-oil",amount=1000}
        local flames=record.spiral.built[n].flames;flames[#flames+1]=e
    end
    if e.type=="unit" then
        e.ai_settings.allow_try_return_to_spawner=false
        e.ai_settings.allow_destroy_when_commands_fail=false
    end
    return e
end
local function populate(record,n)
    if M.layout(record).combat then
        return combat.populate(record,n,M.tier(n,record),M.layout(record).rects[n],surface_for(record))
    end
    local state=record.spiral;local stage=state.built[n]
    local f=M.fixtures[M.tier(n,record)];local size=({"small","medium","big"})[M.tier(n,record)]
    local specs={{"units",size.."-biter"},{"nests","biter-spawner"},{"guns","gun-turret"},{"lasers","the-cave-enemy-laser-turret"},{"flames","flamethrower-turret"}}
    local multiplier=1+0.5*(state.peak_players-1)
    local total=0
    for _,spec in ipairs(specs) do total=total+math.ceil(f[spec[1]]*multiplier) end
    local offset=0
    stage.pending_population=false
    for _,spec in ipairs(specs) do
        local key,name=spec[1],spec[2];local wanted=math.ceil(f[key]*multiplier)
        local placed=stage.spawned[key] or 0
        for i=placed+1,wanted do
            if not enemy(record,n,name,offset+i,total) then break end
            placed=placed+1
        end
        stage.spawned[key]=placed;offset=offset+wanted
        if placed<wanted then stage.pending_population=true end
    end
end
local function reset_timer(record)
    if not record.timer_started_tick then return end
    record.raid_duration_ticks=M.stage_minutes(record.spiral.active,record)*3600
    record.close_tick=game.tick+record.raid_duration_ticks
    record.warned_five=false;record.warned_one=false
end
local function build(record,n,api)
    local s=record.spiral
    local layout=M.layout(record)
    assert(n<=M.count(record) and not s.built[n],"Duplicate Fortified corridor")
    s.built[n]={chests={},flames={},spawned={},clear=false}
    s.active=n
    floor(record,n);boundary(record,n)
    local tier=M.tiers[M.tier(n,record)];local start=0
    for i=(M.tier(n,record)-1)*(layout.stages_per_tier or 5)+1,n-1 do start=start+layout.loot_counts[i] end
    for i=1,layout.loot_counts[n] do
        local p=point(n,22+math.floor((i-1)/2)*3,i%2==0 and 5 or -5,record)
        local chest=assert(api.create_cache(record,surface_for(record),tier,start+i,n,p))
        s.built[n].chests[#s.built[n].chests+1]=chest
    end
    if not layout.hall and (n==1 or n==5 or n==10 or n==15) then
        local p=point(n,n==1 and layout.entrance_distance or 12,0,record)
        local exit=fixed(record,n,"the-cave-fortified-vault-exit-1",p)
        s.built[n].exit=exit;api.register_exit(record,exit,n)
        if n>1 then
            rendering.draw_text{surface=surface_for(record),target={p.x,p.y-4},text={"the-cave-fortified-vault.spiral-exit-only"},color={1,0.85,0.3},alignment="center",scale=1.1}
        end
        if n==1 then record.exit_unit_number=exit.unit_number;record.exit_position=exit.position end
    end
    populate(record,n);reset_timer(record)
    local r=layout.rects[n]
    local label_distance=math.max(7,math.max(r[3]-r[1],r[4]-r[2])-(layout.hall and 45 or 7))
    rendering.draw_text{surface=surface_for(record),target=point(n,label_distance,0,record),text={M.text_key(record,"stage-label"),n},color={1,1,1},alignment="center",scale=layouts.stage_label_scale,draw_on_ground=true}
    if record.timer_started_tick then
        local force=game.forces[record.owner_force_index]
        if force then force.print({M.text_key(record,"unlocked"),n,M.stage_minutes(n,record)}) end
    end
end
local function build_hall(record,api)
    local layout=M.layout(record);if not layout.hall then return end
    floor(record,0)
    local top=fixed(record,0,"the-cave-fortified-vault-exit-1",layout.entrance)
    local bottom=fixed(record,0,"the-cave-fortified-vault-exit-1",layout.exit_only)
    record.spiral.hall_exits={entrance_return=top,exit_only=bottom}
    api.register_exit(record,top,0);api.register_exit(record,bottom,M.count(record))
    record.exit_unit_number=top.unit_number;record.exit_position=top.position
    rendering.draw_text{surface=surface_for(record),target={bottom.position.x,bottom.position.y-5},text={"the-cave-fortified-vault.spiral-exit-only"},color={1,0.85,0.3},alignment="center",scale=2}
end
function M.ensure(record,parent,api)
    local existing=surface_for(record)
    if existing then return existing end
    if record.spiral then return nil,"missing-spiral-surface" end -- never refill a lost raid
    local layout=M.layout(record)
    local surface=game.create_surface("the-cave-fortified-vault-"..record.parent_surface_index.."-"..record.id..layout.surface_suffix,{
        width=layout.surface_size,height=layout.surface_size,seed=record.seed,
        autoplace_controls={},autoplace_settings={entity={treat_missing_as_default=false,settings={}},decorative={treat_missing_as_default=false,settings={}},tile={treat_missing_as_default=false,settings={}}},
    })
    record.child_surface_index=surface.index
    record.spiral={active=0,built={},peak_players=1,positions={},exit_units={}}
    api.register_surface(record,surface)
    -- Empty backing chunks only. Future corridors and entities remain unbuilt.
    local right=math.ceil(layout.width/32)*32-1
    local bottom=math.ceil(layout.height/32)*32-1
    surface.request_to_generate_chunks({(right-32)/2,(bottom-32)/2},math.ceil((math.max(right,bottom)+32)/64));surface.force_generate_chunk_requests()
    local tiles={}
    for x=-32,right do for y=-32,bottom do tiles[#tiles+1]={name="out-of-map",position={x,y}} end end
    surface.set_tiles(tiles,false,true,true,false)
    api.prepare_rewards(record)
    build_hall(record,api)
    build(record,1,api)
    api.finish_station(record,surface)
    return surface
end
function M.start_timer(record)
    if record.timer_started_tick then return end
    record.timer_started_tick=game.tick
    reset_timer(record)
end
function M.update_scaling(record)
    local s=record.spiral;if not s or s.complete then return end
    local count=0
    for _,p in pairs(game.connected_players) do
        if p.force.index==record.owner_force_index and physical.surface(p).index==record.child_surface_index then count=count+1 end
    end
    if count>s.peak_players then s.peak_players=count;populate(record,s.active) end
end
local function keep_unit_inside(record,e)
    if not (e and e.valid) then return end
    if is_infestation(e) then return end
    local n=record.spiral.active
    if e.type~="unit" then if M.stage_at(e.position,record)~=n then e.destroy() end;return end
    -- Native collisions handle walls and doorways. Being near an edge is not
    -- an escape; only recover units whose centres are outside the active room.
    if M.inside(n,e.position,0,record) then return end
    local surface=surface_for(record);local r=M.layout(record).rects[n]
    local target={x=math.max(r[1]+5,math.min(r[3]-5,e.position.x)),y=math.max(r[2]+5,math.min(r[4]-5,e.position.y))}
    local p=surface.find_non_colliding_position(e.name,target,4,0.5,true)
    if p and M.inside(n,p,2,record) then
        local commandable=e.commandable
        if commandable and commandable.valid then
            commandable.release_from_spawner()
            if commandable.parent_group then
                local temporary=surface.create_unit_group{position=e.position,force=e.force}
                temporary.add_member(e);temporary.destroy()
            end
        end
        e.teleport(p)
    end
end
function M.on_spawn(record,e)
    if is_infestation(e) then return end
    if not record.spiral or record.status=="closed" then return end
    if e.type~="unit" then
        if M.stage_at(e.position,record)~=record.spiral.active then e.destroy() end
        return
    end
    if record.spiral.complete then e.destroy();return end
    local tier=M.tier(record.spiral.active,record)
    local kind=e.name:find("spitter",1,true) and "spitter" or "biter"
    local name=({"small","medium","big"})[tier].."-"..kind
    if not M.layout(record).combat and e.name~=name then
        local surface,p=e.surface,e.position;e.destroy()
        e=surface.create_entity{name=name,position=p,force="enemy"}
    end
    if e and e.valid then
        e.ai_settings.allow_try_return_to_spawner=false
        e.ai_settings.allow_destroy_when_commands_fail=false
        keep_unit_inside(record,e)
    end
end
function M.death(record,event)
    local e=event.entity
    if e and e.valid and e.force.name=="enemy" and not is_infestation(e) then
        record.spiral.check_after=game.tick+1
        record.spiral.death_positions=record.spiral.death_positions or {}
        record.spiral.death_positions[#record.spiral.death_positions+1]=e.position
    end
end
function M.tick(record,tick,api)
    local s=record.spiral
    if not s or not record.timer_started_tick or record.status=="closed" then return false end
    if tick%60==0 then
        M.update_scaling(record)
        for _,e in ipairs(s.built[s.active].flames) do if e.valid then e.insert_fluid{name="light-oil",amount=1000} end end
    end
    if s.complete or (record.close_tick and tick>=record.close_tick) then return false end
    local due=s.check_after and tick>=s.check_after
    if not due and tick%120~=0 then return false end
    s.check_after=nil
    local surface=surface_for(record);if not surface then return false end
    if s.built[s.active].pending_population then populate(record,s.active) end
    -- Brood creation is script-side; check the small death neighborhoods next tick.
    for _,p in ipairs(s.death_positions or {}) do
        for _,e in pairs(surface.find_entities_filtered{position=p,radius=7,force="enemy",type="unit"}) do keep_unit_inside(record,e) end
    end
    s.death_positions=nil
    local remaining=M.enemies(record,s.active)
    for _,e in pairs(remaining) do if e.type=="unit" then keep_unit_inside(record,e) end end
    if #remaining>0 or s.built[s.active].pending_population then return false end
    s.built[s.active].clear=true
    if s.active==M.count(record) then s.complete=true else build(record,s.active+1,api) end
    return true
end
function M.player_position(record,player)
    local s=record.spiral;if not s or not player.character then return end
    local p=physical.position(player);local n=M.stage_at(p,record)
    local old=s.positions[player.index]
    local hall=M.layout(record).hall
    local invalid=not n or (n~=0 and not s.built[n])
    if old and n then
        if hall then invalid=invalid or (old.stage~=0 and n~=0 and n~=old.stage)
        else invalid=invalid or math.abs(n-old.stage)>1 end
    end
    if invalid then
        local target=old and old.position or M.layout(record).arrival
        if player.vehicle and player.vehicle.valid then player.vehicle.teleport(target)
        else physical.teleport(player,target,surface_for(record)) end
        return
    end
    s.positions[player.index]={stage=n,position={x=p.x,y=p.y}}
end
function M.restore_tiles(record,event)
    local surface=surface_for(record);if not surface then return end
    local tiles={}
    for _,t in pairs(event.tiles or {}) do
        local p=t.position
        tiles[#tiles+1]={name=tile_name(record,p.x,p.y),position=p}
    end
    if #tiles>0 then surface.set_tiles(tiles,false,false,true,false) end
end
function M.update_hud(player,record,tick)
    if not (record and record.spiral and record.status~="closed" and record.timer_started_tick and player.force.index==record.owner_force_index) then
        information_gui.set_fortified_hud(player,nil);return
    end
    local seconds=math.ceil(math.max(0,record.close_tick-tick)/60)
    local time=string.format("%02d:%02d",math.floor(seconds/60),seconds%60)
    information_gui.set_fortified_hud(player,{M.text_key(record,"hud"),record.spiral.active,time},{M.text_key(record,"rules")})
end
function M.refresh_labels(record)
    local surface=surface_for(record);if not surface then return end
    for _,object in pairs(rendering.get_all_objects("the-cave")) do
        if object.valid and object.type=="text" and object.surface==surface then
            local text=object.text
            if type(text)=="table" and text[1]==M.text_key(record,"stage-label") then
                object.scale=layouts.stage_label_scale
            end
        end
    end
end
return M
