-- The Cave: optional Filter Mining Drills startup feature.
-- Adds only the selection tool/shortcut at data stage. The heavy resource/drill prototype
-- conversion lives in data-final-fixes.lua so it sees resources/drills from other mods too.

local function enabled()
  local setting = settings and settings.startup and settings.startup["the-cave-filter-mining-drills"]
  return setting and setting.value == "enabled"
end

if not enabled() then return end

local tool_name = "the-cave-filter-mining-drills-tool"
local shortcut_name = "the-cave-filter-mining-drills-shortcut"
local icon_path = "__base__/graphics/icons/electric-mining-drill.png"

local base_tool = data.raw["selection-tool"] and data.raw["selection-tool"]["selection-tool"]
local tool
if base_tool then
  tool = table.deepcopy(base_tool)
else
  tool = {
    type = "selection-tool",
    subgroup = "tool",
    stack_size = 1,
  }
end

tool.name = tool_name
tool.icon = icon_path
tool.icon_size = 64
tool.localised_name = {"item-name.the-cave-filter-mining-drills-tool"}
tool.localised_description = {"item-description.the-cave-filter-mining-drills-tool"}
tool.selection_color = {r = 0.40, g = 0.80, b = 1.00, a = 1.00}
tool.alt_selection_color = tool.selection_color
tool.selection_mode = {"any-entity"}
tool.alt_selection_mode = tool.selection_mode
tool.entity_filters = nil
tool.alt_entity_filters = nil
tool.entity_type_filters = {"mining-drill"}
tool.alt_entity_type_filters = tool.entity_type_filters
tool.show_in_library = true
tool.order = "z[the-cave]-f[filter-mining-drills]"

data:extend({tool})

data:extend({
  {
    type = "sprite",
    name = "the-cave-filter-mining-drills-icon",
    filename = icon_path,
    width = 64,
    height = 64,
  },
  {
    type = "shortcut",
    name = shortcut_name,
    action = "spawn-item",
    item_to_spawn = tool_name,
    order = "z[the-cave]-f[filter-mining-drills]",
    localised_name = {"shortcut-name.the-cave-filter-mining-drills-shortcut"},
    localised_description = {"shortcut-description.the-cave-filter-mining-drills-shortcut"},
    icon = icon_path,
    icon_size = 64,
    small_icon = icon_path,
    small_icon_size = 64,
  }
})
