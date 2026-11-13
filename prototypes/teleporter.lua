local icon = "__the-cave__/graphics/technology/teleporter.png"
local input_name = "the-cave-open-teleporter"
local shortcut_name = "the-cave-open-teleporter-shortcut"

local function technology(name, ingredients, prerequisites, order)
  return {
    type = "technology",
    name = name,
    -- Explicit localisation prevents Factorio's numbered-technology fallback
    -- from looking for the missing base key technology-name.the-cave-teleporter.
    localised_name = { "technology-name." .. name },
    localised_description = { "technology-description." .. name },
    icon = icon,
    icon_size = 256,
    prerequisites = prerequisites,
    unit = {
      -- Medium is the base Research Difficulty, so every ingredient costs 400.
      -- The global The Cave difficulty pass scales this to 100/200/400/800/1200/2400.
      count = 400,
      ingredients = ingredients,
      time = 30,
    },
    order = order,
  }
end

data:extend({
  {
    type = "sprite",
    name = "the-cave-teleporter-gui-icon",
    filename = icon,
    flags = { "gui-icon" },
    size = 256,
    priority = "extra-high-no-scale",
  },
  {
    type = "custom-input",
    name = input_name,
    key_sequence = "CONTROL + T",
    consuming = "game-only",
    order = "the-cave-open-teleporter",
  },
  {
    type = "shortcut",
    name = shortcut_name,
    action = "lua",
    associated_control_input = input_name,
    order = "z[the-cave]-p[teleporter]",
    localised_name = { "shortcut-name." .. shortcut_name },
    localised_description = { "shortcut-description." .. shortcut_name },
    icon = icon,
    icon_size = 256,
    small_icon = icon,
    small_icon_size = 256,
  },
  technology(
    "the-cave-teleporter-1",
    {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
    },
    { "logistic-science-pack" },
    "the-cave-teleporter-a"
  ),
  technology(
    "the-cave-teleporter-2",
    {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
    },
    { "the-cave-teleporter-1", "chemical-science-pack" },
    "the-cave-teleporter-b"
  ),
  technology(
    "the-cave-teleporter-3",
    {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
      { "utility-science-pack", 1 },
    },
    { "the-cave-teleporter-2", "utility-science-pack" },
    "the-cave-teleporter-c"
  ),
})
