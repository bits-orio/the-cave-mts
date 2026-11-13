-- Add the new 4x4 industrial container family to existing forces without
-- changing the state of any unrelated recipe or technology.

local RESEARCH_UNLOCKS = {
  ["the-cave-industrial-containers"] = {"", "filter"},
  ["the-cave-logistic-containers"] = {"red", "yellow"},
  ["logistic-system"] = {"blue", "green", "pink"}
}

for _, force in pairs(game.forces) do
  for technology_name, suffixes in pairs(RESEARCH_UNLOCKS) do
    local technology = force.technologies[technology_name]
    local researched = technology and technology.researched or false

    for _, suffix in ipairs(suffixes) do
      local recipe_name = "the-cave-4x4-container"
      if suffix ~= "" then recipe_name = recipe_name .. "_" .. suffix end

      local recipe = force.recipes[recipe_name]
      if recipe then recipe.enabled = researched end
    end
  end
end
