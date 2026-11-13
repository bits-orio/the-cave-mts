-- The map starts black except roughly one chunk at the origin; the chart grows
-- as the cover is dug away. (The original scenario got this for free from
-- out-of-map tiles; our terrain is real, so we control the chart instead.)
local charting = {}

local START_CHART = { { -16, -16 }, { 15, 15 } }
local DIG_CHART_RADIUS = 4

function charting.on_init()
    storage.chart_reset = {}
end

-- Arrival owns the once-per-force/world marks. Player creation can still be
-- in another mod's lobby, before the character reaches the starting cave.
function charting.for_force_world(force, surface)
    if not (force and force.valid and surface and surface.valid) then return end
    force.clear_chart(surface)
    force.chart(surface, START_CHART)
end

function charting.on_dig(dig)
    local force = dig.force
    if not force then return end

    local p = dig.position
    force.chart(dig.surface, {
        { p.x - DIG_CHART_RADIUS, p.y - DIG_CHART_RADIUS },
        { p.x + DIG_CHART_RADIUS, p.y + DIG_CHART_RADIUS },
    })
end

return charting
