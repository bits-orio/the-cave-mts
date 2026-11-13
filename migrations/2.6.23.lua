-- Existing forces that already researched vanilla Fluid Handling receive the
-- two earlier small-tank researches, preserving the new progression chain
-- without revoking completed vanilla research.
for _, force in pairs(game.forces) do
  local fluid = force.technologies["fluid-handling"]
  if fluid and fluid.researched then
    local one = force.technologies["the-cave-storage-tank-1x1-technology"]
    local two = force.technologies["the-cave-storage-tank-2x2-technology"]
    if one then one.researched = true end
    if two then two.researched = true end
  end
end
