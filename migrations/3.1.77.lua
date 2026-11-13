-- Unlock only the new recipes, independently for each existing force. Native
-- research effects handle new games and all subsequent research normally.
local recipes = {"the-cave-accumulator-3x3", "the-cave-accumulator-6x6"}
for _, force in pairs(game.forces) do
  local technology = force.technologies["electric-energy-accumulators"]
  local researched = technology and technology.researched or false
  for _, name in ipairs(recipes) do
    local recipe = force.recipes[name]
    if recipe then recipe.enabled = researched end
  end
end
