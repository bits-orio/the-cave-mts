-- Core progression, independent of scenario and optional feature settings.
-- Reuse the existing technology so completed research and its four thermal
-- recipe unlocks retain their identity when an existing save is updated.
local technology = data.raw.technology and data.raw.technology["heating-tower"]
if not technology then return end

technology.prerequisites = { "concrete" }
technology.research_trigger = nil
technology.unit = {
  count = 200,
  ingredients = {
    { "automation-science-pack", 1 },
    { "logistic-science-pack", 1 },
  },
  time = 30,
}
