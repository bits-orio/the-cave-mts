-- The Cave 2.7.29: complete the Everything on Nauvis progression path without
-- deleting planets, rewriting unrelated technologies, or globally disabling
-- surface conditions.
--
-- Space Age normally unlocks Space Science by building an Asteroid Collector
-- after creating a Space Platform, and its recipe is restricted to gravity 0.
-- In Everything on Nauvis mode, replace only that trigger with Warptorio's
-- four-pack laboratory gate and remove only the official gravity-0 condition.

local setting = settings
  and settings.startup
  and settings.startup["the-cave-everything-on-nauvis"]
local enabled = not setting
  or (setting.value ~= "disabled" and setting.value ~= false)

if not (enabled and mods and mods["space-age"]) then return end

local function remove_exact_zero_gravity(conditions)
  if type(conditions) ~= "table" then return conditions end

  local kept = {}
  for _, condition in ipairs(conditions) do
    local is_official_space_condition = type(condition) == "table"
      and condition.property == "gravity"
      and condition.min == 0
      and condition.max == 0

    if not is_official_space_condition then
      kept[#kept + 1] = condition
    end
  end

  return #kept > 0 and kept or nil
end

local recipe = data.raw.recipe and data.raw.recipe["space-science-pack"]
if recipe then
  recipe.surface_conditions = remove_exact_zero_gravity(recipe.surface_conditions)
end

local technology = data.raw.technology
  and data.raw.technology["space-science-pack"]
if technology then
  -- Preserve unrelated prerequisites added by compatibility mods, but remove
  -- the official Space Platform gate and add Warptorio's two ground-industry
  -- prerequisites deterministically.
  local prerequisites = {}
  local seen = {}

  for _, prerequisite in ipairs(technology.prerequisites or {}) do
    if prerequisite ~= "space-platform" and not seen[prerequisite] then
      prerequisites[#prerequisites + 1] = prerequisite
      seen[prerequisite] = true
    end
  end

  for _, prerequisite in ipairs({ "processing-unit", "low-density-structure" }) do
    if data.raw.technology[prerequisite] and not seen[prerequisite] then
      prerequisites[#prerequisites + 1] = prerequisite
      seen[prerequisite] = true
    end
  end

  technology.prerequisites = prerequisites
  technology.research_trigger = nil
  technology.unit = {
    count = 100,
    ingredients = {
      { "metallurgic-science-pack", 1 },
      { "agricultural-science-pack", 1 },
      { "chemical-science-pack", 1 },
      { "electromagnetic-science-pack", 1 },
    },
    time = 60,
  }
end
