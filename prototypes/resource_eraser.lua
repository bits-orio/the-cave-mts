-- The Cave: optional Resource Eraser startup feature.
-- Adds a hidden cursor-only selection tool and shortcut when access is enabled.

local setting = settings and settings.startup and settings.startup["the-cave-resource-eraser-access"]
local access = setting and setting.value or "disabled"
if access == "disabled" then return end

local tool_name = "the-cave-resource-eraser-tool"
local shortcut_name = "the-cave-resource-eraser-shortcut"
local icon_path = "__base__/graphics/icons/deconstruction-planner.png"
local selection_data = {
  border_color = {r = 1.00, g = 0.20, b = 0.20, a = 1.00},
  mode = {"any-entity"},
  cursor_box_type = "pair",
  entity_type_filters = {"resource"},
  entity_filter_mode = "whitelist",
}

data:extend({
  {
    type = "selection-tool",
    name = tool_name,
    icon = icon_path,
    icon_size = 64,
    subgroup = "tool",
    order = "z[the-cave]-g[resource-eraser]",
    stack_size = 1,
    toggleable = false,
    show_in_library = false,
    select = table.deepcopy(selection_data),
    alt_select = table.deepcopy(selection_data),
    localised_name = {"item-name.the-cave-resource-eraser-tool"},
    localised_description = {"item-description.the-cave-resource-eraser-tool"},
    hidden = true,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
  },
  {
    type = "shortcut",
    name = shortcut_name,
    action = "spawn-item",
    item_to_spawn = tool_name,
    order = "z[the-cave]-g[resource-eraser]",
    localised_name = {"shortcut-name.the-cave-resource-eraser-shortcut"},
    localised_description = {"shortcut-description.the-cave-resource-eraser-shortcut"},
    icon = icon_path,
    icon_size = 64,
    small_icon = icon_path,
    small_icon_size = 64,
    disabled_small_icon = icon_path,
    disabled_small_icon_size = 64,
  }
})
