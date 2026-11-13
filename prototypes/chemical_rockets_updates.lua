local technology = data.raw.technology and data.raw.technology["explosive-rocketry"]
if technology then
  technology.effects = technology.effects or {}
  local existing = {}
  for _, effect in pairs(technology.effects) do
    if effect.type == "unlock-recipe" then existing[effect.recipe] = true end
  end
  if not existing["chemical-rocket"] then table.insert(technology.effects, {type="unlock-recipe", recipe="chemical-rocket"}) end
  if not existing["incendiary-rocket"] then table.insert(technology.effects, {type="unlock-recipe", recipe="incendiary-rocket"}) end
end
