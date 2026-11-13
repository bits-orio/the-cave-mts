-- Character Reach used to grant +2 manual item-pickup distance per researched
-- level. Reapply technology effects after that modifier was removed so existing
-- saves immediately lose only the accumulated legacy F-key pickup range while
-- preserving every technology's researched state.

local REACH_TECH_PREFIX = "the-cave-character-reach-upgrade-"

for _, force in pairs(game.forces) do
  local has_researched_reach = false
  for level = 1, 10 do
    local technology = force.technologies[REACH_TECH_PREFIX .. tostring(level)]
    if technology and technology.researched then
      has_researched_reach = true
      break
    end
  end

  if has_researched_reach then
    force.reset_technology_effects()
  end
end
