-- color_utils.lua
-- Dummiez 2026/05/01

local settings_cache = require("scripts.damage_indicator.settings_cache")

local colors = {}

local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local string_byte = string.byte

local DEFAULT_COLOR = { r = 1.00, g = 0.96, b = 0.72 }
local COLOR_WHITE = { r = 1, g = 1, b = 1 }
local COLOR_INTENSITY_HIGH = { r = 0.48, g = 0.34, b = 0.28 }
local DAMAGE_RAMP_LOW = { r = 1.00, g = 0.96, b = 0.56 }
local DAMAGE_RAMP_MID = { r = 1.00, g = 0.48, b = 0.18 }
local DAMAGE_RAMP_HIGH = { r = 0.88, g = 0.12, b = 0.06 }

-- Baked-in support for common modded damage types. Mods can still override these
-- through the remote interface.
local MODDED_DAMAGE_COLORS = {
  ["frost"] = { r = 130 / 255, g = 220 / 255, b = 255 / 255 },
  ["radioactive"] = { r = 22 / 255, g = 255 / 255, b = 86 / 255 },
  ["bob-pierce"] = { r = 17 / 255, g = 176 / 255, b = 242 / 255 },
  ["bob-plasma"] = { r = 0 / 255, g = 212 / 255, b = 223 / 255 },
}

colors.DEFAULT_COLOR = DEFAULT_COLOR
colors.SHADOW_COLOR = { r = 0.02, g = 0.02, b = 0.02 }

local function clamp(value, minimum, maximum)
  return math_min(maximum, math_max(minimum, value))
end

function colors.normalize_color(color)
  if type(color) ~= "table" then
    return nil
  end

  local r = color.r or color[1]
  local g = color.g or color[2]
  local b = color.b or color[3]
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
    return nil
  end

  if r > 1 or g > 1 or b > 1 then
    r = r / 255
    g = g / 255
    b = b / 255
  end

  return {
    r = clamp(r, 0, 1),
    g = clamp(g, 0, 1),
    b = clamp(b, 0, 1)
  }
end

function colors.copy_color(color)
  return { r = color.r, g = color.g, b = color.b }
end

local function mix_color(left, right, amount)
  return {
    r = left.r + (right.r - left.r) * amount,
    g = left.g + (right.g - left.g) * amount,
    b = left.b + (right.b - left.b) * amount
  }
end

-- Default color settings used when no per-player color cache is available (rare;
-- e.g. remote API calls without a player context, or fallback paths during early init).
local DEFAULT_COLOR_SETTINGS = {
  color_mode = "damage-type",
  blend_damage_type_colors = true,
  color_intensity = true,
  color_intensity_cap = 3000,
  damage_colors = settings_cache.VANILLA_DAMAGE_COLORS,
}

colors.DEFAULT_COLOR_SETTINGS = DEFAULT_COLOR_SETTINGS

local function cs(color_settings)
  return color_settings or DEFAULT_COLOR_SETTINGS
end

local function damage_ramp_color(amount, color_settings)
  local cap = color_settings.color_intensity_cap
  if cap <= 0 then
    cap = 2000
  end

  local intensity = clamp(amount / cap, 0, 1)
  local eased = intensity * intensity * (3 - 2 * intensity)

  if eased < 0.55 then
    return mix_color(DAMAGE_RAMP_LOW, DAMAGE_RAMP_MID, eased / 0.55)
  end

  return mix_color(DAMAGE_RAMP_MID, DAMAGE_RAMP_HIGH, (eased - 0.55) / 0.45)
end

function colors.adjust_damage_color(color, amount, color_settings)
  local settings = cs(color_settings)
  if settings.color_mode == "damage-ramp" then
    return damage_ramp_color(amount, settings)
  end

  if not settings.color_intensity then
    return colors.copy_color(color)
  end

  local cap = settings.color_intensity_cap
  if cap <= 0 then
    return colors.copy_color(color)
  end

  local intensity = clamp(amount / cap, 0, 1)
  local eased = intensity * intensity * (3 - 2 * intensity)
  local low_r = color.r + (COLOR_WHITE.r - color.r) * 0.18
  local low_g = color.g + (COLOR_WHITE.g - color.g) * 0.18
  local low_b = color.b + (COLOR_WHITE.b - color.b) * 0.18
  local high_r = color.r + (COLOR_INTENSITY_HIGH.r - color.r) * 0.12
  local high_g = color.g + (COLOR_INTENSITY_HIGH.g - color.g) * 0.12
  local high_b = color.b + (COLOR_INTENSITY_HIGH.b - color.b) * 0.12

  return {
    r = low_r + (high_r - low_r) * eased,
    g = low_g + (high_g - low_g) * eased,
    b = low_b + (high_b - low_b) * eased
  }
end

function colors.append_damage_color_blend(indicator, color, amount, color_settings)
  local settings = cs(color_settings)
  if not settings.blend_damage_type_colors or settings.color_mode ~= "damage-type" then
    return indicator.base_type_color or color
  end

  if not color or amount <= 0 then
    return indicator.base_type_color or color
  end

  local total = indicator.color_blend_total
  if not total or total <= 0 then
    local base_color = indicator.base_type_color or color
    total = math_max(0, (indicator.amount or 0) - amount)
    indicator.color_blend_total = total
    indicator.color_blend_r = base_color.r * total
    indicator.color_blend_g = base_color.g * total
    indicator.color_blend_b = base_color.b * total
  end

  total = total + amount
  indicator.color_blend_total = total
  indicator.color_blend_r = (indicator.color_blend_r or 0) + color.r * amount
  indicator.color_blend_g = (indicator.color_blend_g or 0) + color.g * amount
  indicator.color_blend_b = (indicator.color_blend_b or 0) + color.b * amount

  local blended = {
    r = indicator.color_blend_r / total,
    g = indicator.color_blend_g / total,
    b = indicator.color_blend_b / total
  }
  indicator.base_type_color = blended
  return blended
end

local function hash_string(value)
  local hash = 5381
  for index = 1, #value do
    hash = ((hash * 33) + string_byte(value, index)) % 2147483647
  end

  return hash
end

local function hsv_to_rgb(hue, saturation, value)
  local sector = math_floor(hue * 6)
  local fraction = hue * 6 - sector
  local p = value * (1 - saturation)
  local q = value * (1 - fraction * saturation)
  local t = value * (1 - (1 - fraction) * saturation)
  sector = sector % 6

  if sector == 0 then
    return { r = value, g = t, b = p }
  elseif sector == 1 then
    return { r = q, g = value, b = p }
  elseif sector == 2 then
    return { r = p, g = value, b = t }
  elseif sector == 3 then
    return { r = p, g = q, b = value }
  elseif sector == 4 then
    return { r = t, g = p, b = value }
  end

  return { r = value, g = p, b = q }
end

function colors.generated_color_for_damage_type(damage_type)
  if not damage_type then
    return colors.copy_color(DEFAULT_COLOR)
  end

  local hash = hash_string(damage_type)
  local hue = ((hash * 0.61803398875) % 1)
  local saturation = 0.66 + ((math_floor(hash / 17) % 18) / 100)
  local value = 0.88 + ((math_floor(hash / 97) % 10) / 100)
  return hsv_to_rgb(hue, saturation, value)
end

function colors.color_for_damage_type(event, state, color_settings)
  local damage_type = event.damage_type and event.damage_type.name
  return colors.color_for_damage_type_name(damage_type, state, color_settings)
end

-- Resolves a color for a damage-type name. Resolution order:
--   1. Mod-registered custom_damage_colors (remote API). Global, shared.
--   2. The provided color_settings.damage_colors map (per-player, baked from the closest
--      viewer's eight color settings). When color_settings is nil (e.g. remote API
--      callers without a player context), falls back to vanilla defaults.
--   3. Hardcoded MODDED_DAMAGE_COLORS table (frost, radioactive).
--   4. Hash-based deterministic color for unknown damage types.
function colors.color_for_damage_type_name(damage_type, state, color_settings)
  local custom_color = damage_type and state.custom_damage_colors[damage_type]
  if custom_color then
    return colors.copy_color(custom_color)
  end

  local settings = cs(color_settings)
  local builtin_color = damage_type and settings.damage_colors and settings.damage_colors[damage_type]
  if builtin_color then
    return colors.copy_color(builtin_color)
  end

  local modded_color = MODDED_DAMAGE_COLORS[damage_type]
  if modded_color then
    return colors.copy_color(modded_color)
  end

  return colors.generated_color_for_damage_type(damage_type)
end

return colors
