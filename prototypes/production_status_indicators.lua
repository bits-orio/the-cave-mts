-- Native production-status indicators for Factorio 2.x.
-- This is a data-stage implementation: no control.lua, polling or saved state.

local setting = settings and settings.startup and settings.startup["the-cave-production-status-indicators"]
if setting and setting.value == "disabled" then
  return
end

local indicator_scale = 0.15
local horizontal_position = 0.30
local bottom_margin = 0.10
local indicator_graphic = "__the-cave__/graphics/production-status/indicator.png"

local fixed_status_colours = {
  disabled = {r = 1.00, g = 0.10, b = 0.10, a = 1.00},
  full_output = {r = 1.00, g = 0.85, b = 0.05, a = 1.00},
  idle = {r = 1.00, g = 0.10, b = 0.10, a = 1.00},
  insufficient_input = {r = 1.00, g = 0.10, b = 0.10, a = 1.00},
  low_power = {r = 1.00, g = 0.45, b = 0.05, a = 1.00},
  no_minable_resources = {r = 1.00, g = 0.10, b = 0.10, a = 1.00},
  no_power = {r = 1.00, g = 0.10, b = 0.10, a = 1.00},
  working = {r = 0.10, g = 1.00, b = 0.10, a = 1.00}
}

local function coordinate(point, named, indexed)
  return point and (point[named] or point[indexed])
end

local function explicit_box(box)
  if not box then return nil end
  local left_top = box.left_top or box[1]
  local right_bottom = box.right_bottom or box[2]
  if not (left_top and right_bottom) then return nil end

  local left = coordinate(left_top, "x", 1)
  local top = coordinate(left_top, "y", 2)
  local right = coordinate(right_bottom, "x", 1)
  local bottom = coordinate(right_bottom, "y", 2)
  if not (left and top and right and bottom) then return nil end

  return {left = left, top = top, right = right, bottom = bottom}
end

local function rotate_box_clockwise(box)
  return {
    left = -box.bottom,
    top = box.left,
    right = -box.top,
    bottom = box.right
  }
end

local function indicator_position(box)
  return {
    x = box.left + ((box.right - box.left) * horizontal_position),
    y = box.bottom - indicator_scale - bottom_margin
  }
end

local function already_has_indicator(visualisations)
  for _, visualisation in pairs(visualisations or {}) do
    local animation = visualisation and visualisation.animation
    if animation and animation.filename == indicator_graphic then
      return true
    end
  end
  return false
end

local function add_indicator(prototype, graphics_set)
  if not graphics_set then return end

  local box = explicit_box(prototype.selection_box or prototype.collision_box)
  if not box then return end

  graphics_set.status_colors = graphics_set.status_colors or {}
  for status, colour in pairs(fixed_status_colours) do
    graphics_set.status_colors[status] = colour
  end

  graphics_set.working_visualisations = graphics_set.working_visualisations or {}
  if already_has_indicator(graphics_set.working_visualisations) then return end

  local rotated_box = rotate_box_clockwise(box)
  local north_south = indicator_position(box)
  local east_west = indicator_position(rotated_box)

  graphics_set.working_visualisations[#graphics_set.working_visualisations + 1] = {
    always_draw = true,
    apply_tint = "status",
    render_layer = "light-effect",
    animation = {
      filename = indicator_graphic,
      flags = {"icon"},
      size = 64,
      scale = indicator_scale,
      line_length = 1,
      frame_count = 1,
      animation_speed = 1,
      draw_as_glow = true
    },
    north_position = north_south,
    east_position = east_west,
    south_position = north_south,
    west_position = east_west
  }
end

for _, prototype_type in pairs({"assembling-machine", "furnace", "rocket-silo"}) do
  for _, prototype in pairs(data.raw[prototype_type] or {}) do
    add_indicator(prototype, prototype.graphics_set)
    add_indicator(prototype, prototype.graphics_set_flipped)
  end
end

for _, prototype in pairs(data.raw["mining-drill"] or {}) do
  add_indicator(prototype, prototype.graphics_set)
  add_indicator(prototype, prototype.wet_mining_graphics_set)
end
