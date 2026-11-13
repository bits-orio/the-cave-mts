-- The Cave integrated Damage Indicator: multiplayer-safe local renderer.
--
-- Version 2.6.4 replaces the former shared rendering/storage implementation with
-- LuaPlayer.create_local_flying_text(). Local flying text is presentation-only and
-- is not saved into the deterministic map state, so per-player display preferences
-- can no longer make script storage or render objects diverge between server/client.

local settings_cache = require("scripts.damage_indicator.settings_cache")
local server_override_gui = require("scripts.damage_indicator.server_override_gui")

local M = {}

local DEFAULT_COLORS = {
  physical = { r = 255 / 255, g = 241 / 255, b = 92 / 255 },
  impact = { r = 255 / 255, g = 216 / 255, b = 187 / 255 },
  explosion = { r = 255 / 255, g = 92 / 255, b = 40 / 255 },
  fire = { r = 226 / 255, g = 132 / 255, b = 28 / 255 },
  laser = { r = 255 / 255, g = 112 / 255, b = 104 / 255 },
  electric = { r = 94 / 255, g = 218 / 255, b = 255 / 255 },
  acid = { r = 168 / 255, g = 210 / 255, b = 82 / 255 },
  poison = { r = 205 / 255, g = 146 / 255, b = 255 / 255 },
}
local FALLBACK_COLOR = { r = 1, g = 0.96, b = 0.72 }
local RAMP_LOW = { r = 1.00, g = 0.96, b = 0.56 }
local RAMP_MID = { r = 1.00, g = 0.48, b = 0.18 }
local RAMP_HIGH = { r = 0.88, g = 0.12, b = 0.06 }

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function setting_value(setting_table, name, fallback)
  local entry = setting_table and setting_table[name]
  if entry and entry.value ~= nil then
    return entry.value
  end
  return fallback
end

local function override_or(setting_table, name, fallback)
  if settings_cache.is_override_active() then
    local payload = settings_cache.get_override_payload()
    if payload and payload[name] ~= nil then
      return payload[name]
    end
  end
  return setting_value(setting_table, name, fallback)
end

local function normalize_color(value, fallback)
  fallback = fallback or FALLBACK_COLOR
  if type(value) ~= "table" then
    return { r = fallback.r, g = fallback.g, b = fallback.b, a = 1 }
  end
  local r = tonumber(value.r or value[1]) or fallback.r
  local g = tonumber(value.g or value[2]) or fallback.g
  local b = tonumber(value.b or value[3]) or fallback.b
  local a = tonumber(value.a or value[4]) or 1
  if r > 1 or g > 1 or b > 1 then
    r, g, b = r / 255, g / 255, b / 255
  end
  if a > 1 then a = a / 255 end
  return {
    r = clamp(r, 0, 1),
    g = clamp(g, 0, 1),
    b = clamp(b, 0, 1),
    a = clamp(a, 0, 1),
  }
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function ramp_color(amount, cap)
  local t = clamp(amount / math.max(cap or 3000, 0.001), 0, 1)
  local left, right, local_t
  if t <= 0.5 then
    left, right, local_t = RAMP_LOW, RAMP_MID, t * 2
  else
    left, right, local_t = RAMP_MID, RAMP_HIGH, (t - 0.5) * 2
  end
  return {
    r = lerp(left.r, right.r, local_t),
    g = lerp(left.g, right.g, local_t),
    b = lerp(left.b, right.b, local_t),
    a = 1,
  }
end

local function custom_damage_color(damage_type_name)
  local safe = storage and storage.damage_indicator_safe
  local custom = safe and safe.custom_damage_colors
  local color = custom and custom[damage_type_name]
  if color then return normalize_color(color, FALLBACK_COLOR) end
  return nil
end

local function resolve_color(player_settings, damage_type_name, amount)
  local mode = override_or(player_settings, "damage-indicator-color-mode", "damage-type")
  if mode == "damage-ramp" then
    local cap = override_or(player_settings, "damage-indicator-color-intensity-cap", 3000)
    return ramp_color(amount, cap)
  end

  local custom = custom_damage_color(damage_type_name)
  if custom then return custom end

  local fallback = DEFAULT_COLORS[damage_type_name] or FALLBACK_COLOR
  local value = override_or(player_settings, "damage-indicator-color-" .. damage_type_name, fallback)
  return normalize_color(value, fallback)
end

local function add_group_separator(number_string, separator)
  local sign, integer, fraction = number_string:match("^([%-]?)(%d+)(%.?%d*)$")
  if not integer then return number_string end
  local grouped = integer:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  if separator == "points" then grouped = grouped:gsub(",", ".") end
  return sign .. grouped .. (fraction or "")
end

local function compact_number(amount)
  local absolute = math.abs(amount)
  local divisor, suffix = 1, ""
  if absolute >= 1000000000 then
    divisor, suffix = 1000000000, "B"
  elseif absolute >= 1000000 then
    divisor, suffix = 1000000, "M"
  elseif absolute >= 1000 then
    divisor, suffix = 1000, "K"
  end
  if divisor == 1 then
    if absolute >= 10 then return tostring(math.floor(amount + 0.5)) end
    return string.format("%.2f", amount):gsub("0+$", ""):gsub("%.$", "")
  end
  local scaled = amount / divisor
  local decimals = math.abs(scaled) >= 100 and 0 or (math.abs(scaled) >= 10 and 1 or 2)
  return string.format("%." .. decimals .. "f", scaled):gsub("0+$", ""):gsub("%.$", "") .. suffix
end

local function format_amount(amount, player_settings)
  if override_or(player_settings, "damage-indicator-compact-numbers", false) then
    return compact_number(amount)
  end

  local text
  local absolute = math.abs(amount)
  if absolute >= 10 then
    text = tostring(math.floor(amount + 0.5))
  else
    text = string.format("%.2f", amount):gsub("0+$", ""):gsub("%.$", "")
  end

  local separator = override_or(player_settings, "damage-indicator-number-separator", "commas")
  if separator ~= "none" then
    text = add_group_separator(text, separator)
  end
  return text
end

local function sanitize_marker(value)
  if type(value) ~= "string" then return "" end
  return (value:gsub("[%[%]=/]", ""))
end

local function build_text(event, player_settings, amount)
  local damage_text = format_amount(amount, player_settings)
  local template = override_or(player_settings, "damage-indicator-text-template", "__damage__")
  if type(template) ~= "string" or template == "" then template = "__damage__" end
  local text = template:gsub("__damage__", damage_text):gsub("__reduced__", "0")

  local is_killing_blow = event.final_health ~= nil and event.final_health <= 0
  if is_killing_blow and override_or(player_settings, "damage-indicator-killing-blow", true) then
    local marker = sanitize_marker(override_or(player_settings, "damage-indicator-killing-blow-marker", "!"))
    if marker ~= "" then text = text .. marker end
  end

  if override_or(player_settings, "damage-indicator-debug-info", false) then
    local damage_type_name = event.damage_type and event.damage_type.name or "unknown"
    text = text .. " [" .. damage_type_name .. "]"
  end
  return text
end

local function force_matches(left, right)
  return left and right and left.valid and right.valid and left.index == right.index
end

local function get_damage_force(event)
  if event.cause and event.cause.valid and event.cause.force then return event.cause.force end
  if event.source and event.source.valid and event.source.force then return event.source.force end
  return nil
end

local function player_should_see(player, player_settings, event, position, surface, amount)
  if not player.connected or player.surface.index ~= surface.index then return false end
  if not setting_value(player_settings, "damage-indicator-enabled", true) then return false end
  if amount < override_or(player_settings, "damage-indicator-minimum-damage", 0.1) then return false end

  local radius = override_or(player_settings, "damage-indicator-radius", 80)
  local dx = player.position.x - position.x
  local dy = player.position.y - position.y
  if dx * dx + dy * dy > radius * radius then return false end

  local visibility = override_or(player_settings, "damage-indicator-visibility", "nearby")
  if visibility == "nearby" then return true end

  local entity_force = event.entity and event.entity.valid and event.entity.force or nil
  local damage_force = get_damage_force(event)
  if visibility == "own-force" then
    return force_matches(player.force, entity_force) or force_matches(player.force, damage_force)
  end
  if visibility == "outgoing" then
    return force_matches(player.force, damage_force) and not force_matches(player.force, entity_force)
  end
  return true
end

local function deterministic_position(event, entity)
  local position = entity.position
  local identity = entity.unit_number
  if not identity then
    identity = math.floor((position.x + 32768) * 16) * 65537 + math.floor((position.y + 32768) * 16)
  end
  local hash = (identity * 1103515245 + event.tick * 12345) % 2147483647
  local offset_x = ((hash % 81) - 40) / 100
  local offset_y = -0.15 - (math.floor(hash / 81) % 26) / 100
  return { x = position.x + offset_x, y = position.y + offset_y }
end

local function destroy_legacy_render_object(id)
  if type(id) ~= "number" then return end
  local ok, object = pcall(rendering.get_object_by_id, id)
  if ok and object and object.valid then pcall(function() object.destroy() end) end
end

local function cleanup_legacy_shared_state()
  local legacy = storage and storage.damage_indicator
  if legacy and legacy.active then
    for _, indicator in pairs(legacy.active) do
      if type(indicator) == "table" then
        destroy_legacy_render_object(indicator.text_id)
        if type(indicator.shadow_ids) == "table" then
          for _, id in pairs(indicator.shadow_ids) do
            destroy_legacy_render_object(id)
          end
        end
      end
    end
  end
  storage.damage_indicator = nil
  storage.damage_indicator_safe = storage.damage_indicator_safe or { custom_damage_colors = {} }
  storage.damage_indicator_safe.custom_damage_colors = storage.damage_indicator_safe.custom_damage_colors or {}
end

function M.cleanup_legacy_shared_state()
  cleanup_legacy_shared_state()
  for _, player in pairs(game.connected_players) do
    player.clear_local_flying_texts()
  end
end

local function initialize_local_settings()
  settings_cache.init()
end

function M.on_init()
  cleanup_legacy_shared_state()
  initialize_local_settings()
end

function M.on_load()
  -- on_load may only rebuild local references/caches. Do not mutate storage here.
  initialize_local_settings()
end

function M.on_configuration_changed()
  cleanup_legacy_shared_state()
  initialize_local_settings()
  for _, player in pairs(game.connected_players) do
    player.clear_local_flying_texts()
  end
end

function M.on_entity_damaged(event)
  local entity = event.entity
  if not entity or not entity.valid then return end
  local amount = tonumber(event.final_damage_amount) or 0
  if amount <= 0 then return end

  local damage_type_name = event.damage_type and event.damage_type.name or "physical"
  local surface = entity.surface
  local position = deterministic_position(event, entity)

  for _, player in ipairs(game.connected_players) do
    local player_settings = settings.get_player_settings(player)
    if player_should_see(player, player_settings, event, entity.position, surface, amount) then
      local lifetime = math.floor(clamp(override_or(player_settings, "damage-indicator-lifetime", 72), 1, 3600))
      local animation_speed = clamp(override_or(player_settings, "damage-indicator-animation-speed", 1), 0, 10)
      player.create_local_flying_text {
        text = build_text(event, player_settings, amount),
        position = position,
        surface = surface,
        color = resolve_color(player_settings, damage_type_name, amount),
        time_to_live = lifetime,
        speed = 0.55 * animation_speed,
      }
    end
  end
end

function M.on_runtime_mod_setting_changed(event)
  if event.setting and string.sub(event.setting, 1, 17) == "damage-indicator-" then
    initialize_local_settings()
  end
  if event.player_index and event.setting == "damage-indicator-enabled" then
    local player = game.get_player(event.player_index)
    if player and not setting_value(settings.get_player_settings(player), "damage-indicator-enabled", true) then
      player.clear_local_flying_texts()
    end
  end
end

function M.on_player_joined_game(event)
  local player = game.get_player(event.player_index)
  if player and settings_cache.get_override_status() == "ok" then
    player.print({ "damage-indicator-message.server-override-active" })
  end
end

function M.on_player_left_game(_) end
function M.on_player_removed(_) end
function M.on_script_trigger_effect(_) end
function M.on_player_changed_position(_) end
function M.on_entity_gone(_) end
function M.on_tick(_) end

function M.on_gui_click(event)
  server_override_gui.handle_gui_click(event)
end

function M.on_gui_closed(event)
  server_override_gui.handle_gui_closed(event)
end

local function clear_local_damage_texts(command)
  if command.player_index then
    local player = game.get_player(command.player_index)
    if player and not player.admin then
      player.print({ "command-output.parameters-require-admin" })
      return
    end
  end
  for _, player in pairs(game.connected_players) do
    player.clear_local_flying_texts()
  end
end

local function open_override_gui(command)
  if not command.player_index then return end
  local player = game.get_player(command.player_index)
  if player then server_override_gui.open(player) end
end

commands.add_command("damage-indicators-clear", { "command-help.damage-indicators-clear" }, clear_local_damage_texts)
commands.add_command("damage-indicators-override", { "command-help.damage-indicators-override" }, open_override_gui)

if not remote.interfaces["damage-indicator"] then
  remote.add_interface("damage-indicator", {
    version = function() return 2 end,
    set_damage_type_color = function(damage_type_name, color)
      if type(damage_type_name) ~= "string" or damage_type_name == "" then
        error("damage_type_name must be a non-empty string")
      end
      local normalized = normalize_color(color, FALLBACK_COLOR)
      storage.damage_indicator_safe = storage.damage_indicator_safe or { custom_damage_colors = {} }
      storage.damage_indicator_safe.custom_damage_colors = storage.damage_indicator_safe.custom_damage_colors or {}
      storage.damage_indicator_safe.custom_damage_colors[damage_type_name] = normalized
      return true
    end,
    set_damage_type_colors = function(colors_by_damage_type)
      if type(colors_by_damage_type) ~= "table" then error("colors_by_damage_type must be a table") end
      storage.damage_indicator_safe = storage.damage_indicator_safe or { custom_damage_colors = {} }
      storage.damage_indicator_safe.custom_damage_colors = storage.damage_indicator_safe.custom_damage_colors or {}
      for name, color in pairs(colors_by_damage_type) do
        if type(name) ~= "string" or name == "" then error("damage type names must be non-empty strings") end
        storage.damage_indicator_safe.custom_damage_colors[name] = normalize_color(color, FALLBACK_COLOR)
      end
      return true
    end,
    clear_damage_type_color = function(damage_type_name)
      local safe = storage.damage_indicator_safe
      if safe and safe.custom_damage_colors then safe.custom_damage_colors[damage_type_name] = nil end
      return true
    end,
    get_damage_type_color = function(damage_type_name)
      return custom_damage_color(damage_type_name) or DEFAULT_COLORS[damage_type_name] or FALLBACK_COLOR
    end,
    list_custom_damage_type_colors = function()
      local result = {}
      local safe = storage.damage_indicator_safe
      for name, color in pairs((safe and safe.custom_damage_colors) or {}) do
        result[name] = { r = color.r, g = color.g, b = color.b, a = color.a }
      end
      return result
    end,
    -- Kept for compatibility with Stable Foundations. The local-only renderer uses
    -- Factorio's final_damage_amount directly and intentionally stores no pending report.
    record_stable_foundations_damage_reduction = function(_) return false end,
  })
end

return M
