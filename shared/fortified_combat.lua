-- Shared only by Fortified's dedicated prototypes and room population.
local C = {}
C.families = {"biter", "spitter", "arachnid", "snapper"}
C.units = {
    biter={"small-biter","medium-biter","big-biter","behemoth-biter"},
    spitter={"small-spitter","medium-spitter","big-spitter","behemoth-spitter"},
    arachnid={"arachnid-biter-drone-unit","arachnid-biter-warrior-unit","arachnid-biter-tiger-unit","arachnid-biter-royalwarrior-unit"},
    snapper={"small-armoured-biter","medium-armoured-biter","big-armoured-biter","behemoth-armoured-biter"},
}
C.nest_bases={biter="biter-spawner",spitter="spitter-spawner",arachnid="arachnid-spawner-unitspawner",snapper="armoured-biter-spawner"}
C.offspring_aliases={}
for _,names in pairs(C.units) do
    for size=3,4 do C.offspring_aliases["the-cave-fortified-offspring-"..names[size]]=names[size] end
end
function C.nest_unit(family,size)
    local name=C.units[family][size]
    return size>=3 and "the-cave-fortified-offspring-"..name or name
end
C.profiles={
    {units=300,nests=12,worms=10,guns=6,lasers=0,flames=0,minutes=10,cooldown=150},
    {units=250,nests=12,worms=10,guns=4,lasers=4,flames=0,minutes=12,cooldown=255},
    {units=200,nests=12,worms=10,guns=4,lasers=4,flames=4,minutes=15,cooldown=360},
}
function C.nest_name(tier,family) return "the-cave-fortified-nest-"..tier.."-"..family end
C.nest_aliases={}
for tier=1,3 do for family,base in pairs(C.nest_bases) do C.nest_aliases[C.nest_name(tier,family)]=base end end
function C.unit_name(tier,family,ordinal,room)
    local size=tier<3 and tier or 3+((ordinal+(room or 0))%2)
    return C.units[family][size]
end
function C.unit_spec(tier,room,index)
    -- Alternate the two extra medium units between family pairs. Across six
    -- rooms each of the four families receives exactly 375 initial units.
    local offset=((room-1)%2)*2
    local family=C.families[(index-1+offset)%4+1]
    return C.unit_name(tier,family,math.floor((index-1)/4)+1,room),family
end
return C
