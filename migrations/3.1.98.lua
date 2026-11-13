-- Make only the new recipe available on saves that already unlocked small
-- poles. Preserve every existing recipe, technology and force setting.
for _, force in pairs(game.forces) do
  local original = force.recipes["small-electric-pole"]
  local metal = force.recipes["the-cave-small-metal-electric-pole"]
  if original and original.enabled and metal then
    metal.enabled = true
  end
end
