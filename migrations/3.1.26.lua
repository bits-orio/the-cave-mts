-- The old Logistic Containers technology unlocked all five logistic modes at
-- the early 250-pack tier. Keep existing forces consistent with the corrected
-- prototype progression without resetting any unrelated technology effects.

local ADVANCED_SIZES = {"1x1", "2x2", "6x6"}
local ADVANCED_SUFFIXES = {"blue", "green", "pink"}

for _, force in pairs(game.forces) do
  local logistic_system = force.technologies["logistic-system"]
  local advanced_unlocked = logistic_system and logistic_system.researched or false

  for _, size in ipairs(ADVANCED_SIZES) do
    for _, suffix in ipairs(ADVANCED_SUFFIXES) do
      local recipe_name = "the-cave-" .. size .. "-container_" .. suffix
      local recipe = force.recipes[recipe_name]
      if recipe then
        recipe.enabled = advanced_unlocked
      end
    end
  end
end
