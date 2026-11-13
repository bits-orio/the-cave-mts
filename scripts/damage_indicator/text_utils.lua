-- text_utils.lua
-- Dummiez 2026/05/01

local text_utils = {}

local math_max = math.max
local math_floor = math.floor
local string_format = string.format

-- All formatting functions take an explicit `text_settings` table (typically the
-- closest viewer's per-user text settings, baked into the indicator at creation).
-- Required keys:
--   compact_numbers       (bool)
--   number_separator      ("none" | "commas" | "points")
--   show_reductions       (bool)
--   show_group_count      (bool)
--   text_template         (string, with optional __damage__ / __reduced__ tokens)
--   template_is_default   (bool, true when text_template == "__damage__")
--   template_has_damage   (bool)
--   template_has_reduced  (bool)
--   killing_blow_marker   (string, sanitized of rich-text control chars)
-- A nil text_settings argument signals "use safe defaults" -- this can happen if a cached
-- indicator is rendered after the authoritative player has left and we have no fallback.

local DEFAULT_TEXT_SETTINGS = {
  compact_numbers = false,
  number_separator = "commas",
  show_reductions = true,
  show_group_count = true,
  text_template = "__damage__",
  template_is_default = true,
  template_has_damage = true,
  template_has_reduced = false,
  killing_blow_marker = "!",
  debug_info = false,
}

text_utils.DEFAULT_TEXT_SETTINGS = DEFAULT_TEXT_SETTINGS

local function ts(text_settings)
  return text_settings or DEFAULT_TEXT_SETTINGS
end

local function add_thousands_separators(value, separator_setting)
  if separator_setting == "none" then
    return tostring(value)
  end

  local separator = separator_setting == "points" and "." or ","
  local sign = ""
  if value < 0 then
    sign = "-"
    value = -value
  end

  local text = tostring(value)
  local result = ""
  local length = #text
  for index = length, 1, -3 do
    local start_index = math_max(1, index - 2)
    local chunk = text:sub(start_index, index)
    if result == "" then
      result = chunk
    else
      result = chunk .. separator .. result
    end
  end

  return sign .. result
end

local function format_sub_1000_damage(amount)
  if amount < 10 then
    return string_format("%.1f", amount)
  end

  return tostring(math_floor(amount + 0.5))
end

function text_utils.format_damage(amount, text_settings)
  local settings = ts(text_settings)
  if amount < 1000 then
    return format_sub_1000_damage(amount)
  end

  if not settings.compact_numbers then
    return add_thousands_separators(math_floor(amount + 0.5), settings.number_separator)
  end

  if amount >= 1000000000 then
    local v = amount / 1000000000
    if v < 10 then
      return string_format("%.2fb", v)
    elseif v < 100 then
      return string_format("%.1fb", v)
    end
    return tostring(math_floor(v + 0.5)) .. "b"
  end

  if amount >= 1000000 then
    local v = amount / 1000000
    if v < 100 then
      return string_format("%.1fm", v)
    end
    return tostring(math_floor(v + 0.5)) .. "m"
  end

  local v = amount / 1000
  if v < 10 then
    return string_format("%.1fk", v)
  end
  return tostring(math_floor(v + 0.5)) .. "k"
end

local function color_reduction_text(text)
  return "[color=white]" .. text .. "[/color]"
end

function text_utils.formatted_damage_text(amount, reduced_amount, color_reduction, killing_blow, text_settings)
  local settings = ts(text_settings)
  local damage_text = text_utils.format_damage(amount, settings)
  if killing_blow and settings.killing_blow_marker and settings.killing_blow_marker ~= "" then
    damage_text = damage_text .. settings.killing_blow_marker
  end
  local has_reduced = reduced_amount and reduced_amount > 0

  if settings.template_is_default and not has_reduced then
    return damage_text
  end

  local template = settings.text_template
  local reduced_text = has_reduced and ("-" .. text_utils.format_damage(reduced_amount, settings)) or ""
  local use_colored_reduction = color_reduction ~= false
  local colored_reduced_text = use_colored_reduction and reduced_text ~= "" and color_reduction_text(reduced_text) or
      reduced_text

  local text = template
  if settings.template_has_damage then
    text = text:gsub("__damage__", damage_text)
  end
  if settings.template_has_reduced then
    text = text:gsub("__reduced__", colored_reduced_text)
  end

  if reduced_text ~= "" and settings.show_reductions and not settings.template_has_reduced then
    local reduction_segment = "(" .. reduced_text .. ")"
    text = text .. " " .. (use_colored_reduction and color_reduction_text(reduction_segment) or reduction_segment)
  end

  return text
end

local function group_count_text(indicator, color_line, text_settings)
  local settings = ts(text_settings)
  if not settings.show_group_count then
    return nil
  end

  local count = indicator.group_position_count or 1
  if count <= 1 or not indicator.groupable then
    return nil
  end

  local prefix = " [font=default-tiny-bold]"
  local suffix = "[/font]"
  if color_line then
    prefix = prefix .. "[color=white]"
    suffix = "[/color]" .. suffix
  end

  -- group_display_name (set when a group-name-normalize rule matched) overrides the
  -- localised name so the count tag shows the un-tiered/un-leveled label, e.g. just
  -- "Spitter Spawner" instead of "Spitter Spawner: Lvl. 10".
  local label
  if indicator.group_display_name then
    label = indicator.group_display_name
  else
    label = indicator.entity_localised_name or { "entity-name." .. (indicator.entity_name or "") }
  end

  return {
    "",
    prefix,
    "[",
    tostring(count),
    "x ",
    label,
    "]",
    suffix
  }
end

-- Debug-info suffix: when the closest viewer has debug_info enabled, append a
-- compact descriptor of the entity so it's easy to distinguish modded enemies
-- and identify their internal name/type/damage_type. Looks like:
--   [unit_no: 12, type: unit, name: small-biter, damage: laser]
-- Fields are omitted when unavailable (e.g. unit_number is nil for buildings).
local function debug_info_text(indicator, color_line, text_settings)
  local settings = ts(text_settings)
  if not settings.debug_info then
    return nil
  end

  local parts = {}
  local count = 0
  if indicator.debug_unit_number then
    count = count + 1
    parts[count] = "unit_no: " .. tostring(indicator.debug_unit_number)
  end
  if indicator.debug_entity_type then
    count = count + 1
    parts[count] = "type: " .. indicator.debug_entity_type
  end
  if indicator.entity_name then
    count = count + 1
    parts[count] = "name: " .. indicator.entity_name
  end
  if indicator.debug_damage_type then
    count = count + 1
    parts[count] = "damage: " .. indicator.debug_damage_type
  end
  if count == 0 then
    return nil
  end

  local body = "[" .. table.concat(parts, ", ") .. "]"
  local prefix = " [font=default-tiny-bold]"
  local suffix = "[/font]"
  if color_line then
    prefix = prefix .. "[color=white]"
    suffix = "[/color]" .. suffix
  end
  return prefix .. body .. suffix
end

function text_utils.indicator_text_with_group_count(indicator, text_value, color_line, text_settings)
  local count_text = group_count_text(indicator, color_line, text_settings)
  local debug_text = debug_info_text(indicator, color_line, text_settings)
  if not count_text and not debug_text then
    return text_value
  end

  local result = { "", text_value }
  local n = 2
  if count_text then
    n = n + 1
    result[n] = count_text
  end
  if debug_text then
    n = n + 1
    result[n] = debug_text
  end
  return result
end

return text_utils
