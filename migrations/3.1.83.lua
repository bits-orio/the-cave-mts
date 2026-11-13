-- Preserve every placed entity and its stored Joules. Only update availability
-- of the four Cave recipes, independently for each already-researched force.
local names = {
  "the-cave-accumulator-3x3", "the-cave-accumulator-6x6",
  "the-cave-accumulator-10x10", "the-cave-accumulator-20x20"
}
for _, force in pairs(game.forces) do
  local technology = force.technologies["electric-energy-accumulators"]
  local researched = technology and technology.researched or false
  for _, name in ipairs(names) do
    local recipe = force.recipes[name]
    if recipe then recipe.enabled = researched end
  end
end
