-- Geometry is selected per vault so already-entered playtests keep their map.
local layouts = {}
layouts.current = 4
layouts.stage_label_scale = 5.2 -- four times the original 1.3
layouts[1] = {
    rects = {
        {0,0,250,20}, {0,20,20,250}, {20,230,250,250},
        {230,30,250,230}, {30,30,230,50}, {30,50,50,220},
        {50,200,220,220}, {200,60,220,200}, {60,60,200,80},
        {60,80,80,190}, {80,170,190,190}, {170,90,190,170},
        {90,90,170,110}, {90,110,110,160}, {110,120,150,160},
    },
    loot_counts = {12,13,13,13,13,9,9,10,10,10,6,6,6,7,7},
    totals = {standard=64, secure=48, high=32},
    offsets = {standard=0, secure=64, high=112},
    width=250, height=250, gap=10, surface_size=512,
    entrance_distance=235, arrival={x=239,y=14}, station={x=235,y=4},
    chart={{225,0},{250,20}}, surface_suffix='-spiral',
}
layouts[2] = {
    -- 350-tile first corridor; all corridor widths 20 and parallel void gaps 35.
    -- The lower/right turns need a 390x425 footprint to retain 15 connected
    -- stages and the 40x40 centre. A 350x350 bounding square cannot fit them.
    rects = {
        {0,0,350,20}, {0,20,20,425}, {20,405,390,425},
        {370,55,390,405}, {55,55,370,75}, {55,75,75,370},
        {75,350,335,370}, {315,110,335,350}, {110,110,315,130},
        {110,130,130,315}, {130,295,280,315}, {260,165,280,295},
        {165,165,260,185}, {165,185,185,260}, {185,220,225,260},
    },
    loot_counts = {8,8,8,8,8,6,6,6,6,6,4,4,4,4,4},
    totals = {standard=40, secure=30, high=20},
    offsets = {standard=0, secure=40, high=70},
    width=390, height=425, gap=35, surface_size=1024,
    entrance_distance=335, arrival={x=339,y=14}, station={x=335,y=4},
    chart={{325,0},{350,20}}, surface_suffix='-spiral-v2',
}
-- Eighteen equal rooms, odd numbers east and even numbers west of an open hall.
layouts[3] = {
    rects = {}, loot_counts = {}, stages_per_tier=6,
    hall={250,0,285,595}, hall_tile='the-cave-fortified-floor-blue',
    totals={standard=48,secure=36,high=24},
    offsets={standard=0,secure=48,high=84},
    width=535,height=595,gap=35,surface_size=2048,
    arrival={x=272,y=18},station={x=267,y=4},
    entrance={x=267,y=10},exit_only={x=267,y=582},
    chart={{250,0},{285,35}},surface_suffix='-rooms-v3',
}
for n=1,18 do
    local y=math.floor((n-1)/2)*70
    layouts[3].rects[n]=n%2==1 and {285,y,535,y+35} or {0,y,250,y+35}
    layouts[3].loot_counts[n]=n<=6 and 8 or (n<=12 and 6 or 4)
end
-- The geometry is unchanged; version 4 selects the agreed combat profile.
-- Entered version-3 raids retain their existing population and timing.
layouts[4]={}
for key,value in pairs(layouts[3]) do layouts[4][key]=value end
layouts[4].combat=true
layouts[4].surface_suffix='-rooms-v4'
function layouts.get(record)
    return assert(layouts[record and record.spiral_layout_version or layouts.current], 'Unknown Fortified spiral layout')
end
return layouts
