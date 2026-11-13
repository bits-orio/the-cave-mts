local settings = require("scripts.game_settings").proxy(settings)

-- settings_cache.lua
-- Dummiez 2026/05/01

local settings_cache = {}

local math_min = math.min
local math_max = math.max
local next = next

-- Vanilla damage color defaults. Used as fallback values when:
-- - per-player color settings can't be resolved (player not yet cached)
-- - the remote API queries get_damage_type_color() without a player context
local VANILLA_DAMAGE_COLORS = {
  physical = { r = 255 / 255, g = 241 / 255, b = 92 / 255 },
  impact = { r = 194 / 255, g = 180 / 255, b = 141 / 255 },
  explosion = { r = 255 / 255, g = 92 / 255, b = 40 / 255 },
  fire = { r = 226 / 255, g = 132 / 255, b = 28 / 255 },
  laser = { r = 255 / 255, g = 112 / 255, b = 104 / 255 },
  electric = { r = 94 / 255, g = 218 / 255, b = 255 / 255 },
  acid = { r = 168 / 255, g = 210 / 255, b = 82 / 255 },
  poison = { r = 205 / 255, g = 146 / 255, b = 255 / 255 }
}

local VANILLA_DAMAGE_TYPES = { "physical", "impact", "explosion", "fire", "laser", "electric", "acid", "poison" }

settings_cache.VANILLA_DAMAGE_COLORS = VANILLA_DAMAGE_COLORS
settings_cache.VANILLA_DAMAGE_TYPES = VANILLA_DAMAGE_TYPES

local SHADOW_PROFILES = {
  off = {},
  light = {
    { x = -0.050, y = 0.045, a = 0.72 },
    { x = 0.050,  y = 0.045, a = 0.72 },
    { x = 0.000,  y = 0.090, a = 0.62 }
  },
  heavy = {
    { x = -0.055, y = -0.025, a = 0.72 },
    { x = 0.055,  y = -0.025, a = 0.72 },
    { x = -0.055, y = 0.055,  a = 0.82 },
    { x = 0.055,  y = 0.055,  a = 0.82 },
    { x = 0.000,  y = 0.092,  a = 0.64 }
  }
}

-- Returns the resolved shadow offsets array for a style string. Falls back to "light"
-- for unknown styles. The returned table is shared (read-only by convention) so callers
-- must not mutate it.
local function resolve_shadow_profile(style)
  return SHADOW_PROFILES[style] or SHADOW_PROFILES.light
end

local STARTUP = {}
local GROUPABLE_WHITELIST_ENTITY_TYPES = {}
local BLACKLIST_EXACT = {}
local BLACKLIST_PREFIXES = {}
local BLACKLIST_SUFFIXES = {}
local BLACKLIST_ACTIVE = false

-- Group-name normalization rules: each entry is { pattern = "...", display = "..." }.
-- Used to merge tiered enemy variants (e.g. spitter-spawn-v1-t10-rampant) into a single
-- grouping key + display name. Resolved once at init via parse_normalize_rules below.
local NORMALIZE_RULES = {}
local NORMALIZE_RULES_ACTIVE = false
-- Per-entity-name memoization cache so the rule scan happens at most once per unique
-- name. Keys are entity names; values are {group_key, display_name} or false (no match).
-- Cleared on every settings_cache.init.
local NORMALIZE_CACHE = {}

settings_cache.STARTUP = STARTUP

-- Server-override state. When OVERRIDE_ACTIVE is true, viewer_utils replaces every
-- runtime-per-user value baked onto each indicator (text/visual/color settings,
-- visibility, radius, scale, minimum_damage) with the decoded override values --
-- except for `enabled`, which always stays per-player so individual players can still
-- hide indicators on their screen. The override payload is decoded once at init from
-- the startup string setting via helpers.decode_string + helpers.json_to_table.
local OVERRIDE_ACTIVE = false
local OVERRIDE_PAYLOAD = nil
-- Last decode result for the override string. Possible values:
--   "ok"            -- override decoded and active
--   "empty"         -- string is blank, override intentionally off
--   "decode_failed" -- not a valid Base64+zlib blob
--   "json_failed"   -- decoded but isn't valid JSON
--   "shape_failed"  -- valid JSON but missing the { version, values = table } shape
-- Surfaced to players via the chat-notification flow in control.lua so a bad paste
-- is visible rather than silently no-ops.
local OVERRIDE_STATUS = "empty"
settings_cache.OVERRIDE_KEYS = {
  -- Top-level per-user values surfaced by get_cached_player_settings.
  "minimum_damage", "radius", "visibility", "scale",
  -- Nested groups baked into each indicator at creation; see build_*_settings in
  -- viewer_utils.lua for the exact field shapes.
  "text", "visual", "color"
}

function settings_cache.is_override_active()
  return OVERRIDE_ACTIVE
end

function settings_cache.get_override_payload()
  return OVERRIDE_PAYLOAD
end

-- Returns the last decode-status code (see OVERRIDE_STATUS above). Use this to
-- distinguish "override is off because the string is blank" from "override failed
-- to parse and the admin needs to fix the paste".
function settings_cache.get_override_status()
  return OVERRIDE_STATUS
end

local function get_font_name()
  local font_name = STARTUP.font
  if prototypes and prototypes.font and prototypes.font[font_name] then
    return font_name
  end

  if prototypes and prototypes.font and prototypes.font["damage-indicator-font"] then
    return "damage-indicator-font"
  end

  if prototypes and prototypes.font and prototypes.font["default-bold"] then
    return "default-bold"
  end

  return nil
end

-- Normalizes a color value from a Factorio color-setting (which may be {r,g,b,a} or
-- {[1],[2],[3]}, with values in 0-1 or 0-255 range). Falls back to the provided fallback
-- table fore missing/invalid components.
local function normalize_setting_color(color, fallback)
  if type(color) ~= "table" then
    return { r = fallback.r, g = fallback.g, b = fallback.b }
  end

  local r = color.r or color[1] or fallback.r
  local g = color.g or color[2] or fallback.g
  local b = color.b or color[3] or fallback.b
  if type(r) ~= "number" then r = fallback.r end
  if type(g) ~= "number" then g = fallback.g end
  if type(b) ~= "number" then b = fallback.b end
  if r > 1 or g > 1 or b > 1 then
    r = r / 255
    g = g / 255
    b = b / 255
  end

  return {
    r = math_min(1, math_max(0, r)),
    g = math_min(1, math_max(0, g)),
    b = math_min(1, math_max(0, b))
  }
end

settings_cache.normalize_setting_color = normalize_setting_color

local RUNTIME_DEFAULTS = {
  ["damage-indicator-max-active"] = 300,
  ["damage-indicator-group-similar-distance"] = 5,
  ["damage-indicator-combine-ticks"] = 30,
  ["damage-indicator-font"] = "damage-indicator-font",
  ["damage-indicator-text-update-interval"] = 6,
  ["damage-indicator-viewport-culling"] = true,
  ["damage-indicator-viewport-margin"] = 12,
  ["damage-indicator-whitelist-entity-types"] = "asteroid",
  ["damage-indicator-whitelist-distance-bonus"] = 15,
  ["damage-indicator-saturation-threshold"] = 10,
  ["damage-indicator-blacklist-entity-names"] = "",
  ["damage-indicator-group-name-normalize"] = "^(.-)%-v%d+%-t%d+.*$",
  ["damage-indicator-server-override-string"] = ""
}

-- Shared Damage Indicator behaviour must come only from synchronized settings.
-- Never derive these values from an arbitrary connected player's runtime-per-user
-- settings: a headless server and joining client can otherwise resolve different
-- values during load and immediately diverge.
local function setting_value(name)
  if settings and settings.startup and settings.startup[name] then
    return settings.startup[name].value
  end
  if settings and settings.global and settings.global[name] then
    return settings.global[name].value
  end
  return RUNTIME_DEFAULTS[name]
end

function settings_cache.init()
  STARTUP.max_active               = setting_value("damage-indicator-max-active")
  STARTUP.group_similar_distance   = setting_value("damage-indicator-group-similar-distance")
  STARTUP.combine_ticks            = setting_value("damage-indicator-combine-ticks")
  STARTUP.font                     = setting_value("damage-indicator-font")
  STARTUP.text_update_interval     = setting_value("damage-indicator-text-update-interval")
  STARTUP.viewport_culling         = setting_value("damage-indicator-viewport-culling")
  STARTUP.viewport_margin          = setting_value("damage-indicator-viewport-margin")

  local whitelist_raw              = setting_value("damage-indicator-whitelist-entity-types") or ""
  STARTUP.whitelist_distance_bonus = setting_value("damage-indicator-whitelist-distance-bonus") or 0
  STARTUP.saturation_threshold     = setting_value("damage-indicator-saturation-threshold") or 0
  GROUPABLE_WHITELIST_ENTITY_TYPES = {}
  for token in string.gmatch(whitelist_raw, "[^,%s]+") do
    GROUPABLE_WHITELIST_ENTITY_TYPES[token] = true
  end

  BLACKLIST_EXACT = {}
  BLACKLIST_PREFIXES = {}
  BLACKLIST_SUFFIXES = {}
  local blacklist_raw = setting_value("damage-indicator-blacklist-entity-names") or ""
  for token in string.gmatch(blacklist_raw, "[^,%s]+") do
    local len = #token
    if len > 1 and token:sub(1, 1) == "*" then
      BLACKLIST_SUFFIXES[#BLACKLIST_SUFFIXES + 1] = token:sub(2)
    elseif len > 1 and token:sub(len, len) == "*" then
      BLACKLIST_PREFIXES[#BLACKLIST_PREFIXES + 1] = token:sub(1, len - 1)
    elseif token ~= "*" then
      BLACKLIST_EXACT[token] = true
    end
  end
  BLACKLIST_ACTIVE = next(BLACKLIST_EXACT) ~= nil
      or #BLACKLIST_PREFIXES > 0
      or #BLACKLIST_SUFFIXES > 0

  -- Parse normalize patterns. Format: comma-separated Lua patterns, each with one
  -- capture group `(...)` that extracts the base name from a tiered/versioned
  -- internal name. Empty entries are silently skipped.
  NORMALIZE_RULES = {}
  NORMALIZE_CACHE = {}
  local normalize_raw = setting_value("damage-indicator-group-name-normalize") or ""
  for entry in string.gmatch(normalize_raw, "[^,]+") do
    entry = entry:match("^%s*(.-)%s*$")
    if entry ~= "" then
      NORMALIZE_RULES[#NORMALIZE_RULES + 1] = entry
    end
  end
  NORMALIZE_RULES_ACTIVE = #NORMALIZE_RULES > 0

  STARTUP.font_name = get_font_name()

  STARTUP.group_similar_distance_sq = STARTUP.group_similar_distance * STARTUP.group_similar_distance

  -- Decode the server-override string. The override is implicitly enabled whenever
  -- the string is non-empty AND decodes into a valid payload. Each failure stage
  -- writes a distinct OVERRIDE_STATUS value, then -- if the status indicates a
  -- malformed paste -- raises a hard error so Factorio shows a modal dialog with
  -- a status-specific message. The error fires from settings_cache.init itself
  -- (rather than from control.lua) because init runs from all three lifecycle
  -- hooks (on_init / on_load / on_configuration_changed), so this is the single
  -- place that guarantees the error surfaces on every entry point.
  OVERRIDE_ACTIVE = false
  OVERRIDE_PAYLOAD = nil
  local raw = setting_value("damage-indicator-server-override-string") or ""
  if not raw or raw == "" then
    OVERRIDE_STATUS = "empty"
  elseif not (helpers and helpers.decode_string and helpers.json_to_table) then
    -- Defensive: helpers should always be available at runtime in Factorio 2.0, but
    -- if it isn't we mark the status as decode_failed so the lack of override at
    -- least surfaces something rather than silently swallowing the string.
    OVERRIDE_STATUS = "decode_failed"
  else
    local decoded = helpers.decode_string(raw)
    if not decoded then
      OVERRIDE_STATUS = "decode_failed"
    else
      local ok_table, payload = pcall(helpers.json_to_table, decoded)
      if not ok_table or payload == nil then
        OVERRIDE_STATUS = "json_failed"
      elseif type(payload) ~= "table" or type(payload.values) ~= "table" then
        -- Decoded into something (e.g. a blueprint export) but it lacks our
        -- `values` table -- almost always means the admin pasted the wrong string.
        OVERRIDE_STATUS = "shape_failed"
      else
        OVERRIDE_STATUS = "ok"
        OVERRIDE_ACTIVE = true
        OVERRIDE_PAYLOAD = payload.values
      end
    end
  end

  -- Surface parse failures as a hard error so the admin sees a modal Factorio
  -- error dialog instead of a silently-ignored override. The error passes a
  -- localized-message table (not a plain string) so Factorio renders it via the
  -- locale system. From on_configuration_changed / on_load / on_init this halts
  -- the load and forces the admin to fix the string before the game can proceed.
  if OVERRIDE_STATUS == "decode_failed" then
    error({ "damage-indicator-message.server-override-decode-failed" })
  elseif OVERRIDE_STATUS == "json_failed" then
    error({ "damage-indicator-message.server-override-json-failed" })
  elseif OVERRIDE_STATUS == "shape_failed" then
    error({ "damage-indicator-message.server-override-shape-failed" })
  end
end

-- Title-case a hyphen-separated internal name: "behemoth-spitter-spawn" -> "Behemoth Spitter Spawn".
-- Used as a fallback display label when a normalize pattern matches but no localised name
-- entry exists for the captured base.
local function titleize_internal_name(name)
  -- Split on hyphens, capitalize each chunk, join with spaces.
  local parts = {}
  local count = 0
  for chunk in string.gmatch(name, "[^%-]+") do
    count = count + 1
    parts[count] = chunk:sub(1, 1):upper() .. chunk:sub(2)
  end
  return table.concat(parts, " ")
end

-- Resolve an entity name through the normalize patterns. Each pattern must contain
-- one capture group that extracts the base name (e.g. `^(.-)%-v%d+%-t%d+%-rampant$`
-- captures `spitter-spawn` from `spitter-spawn-v1-t10-rampant`). The captured base
-- becomes the group identity, and a title-cased version becomes the display label.
-- Returns (group_key, display_name) on match, (nil, nil) otherwise. Memoized per
-- input name to avoid pattern scans on every damage event.
function settings_cache.resolve_normalized_name(name)
  if not NORMALIZE_RULES_ACTIVE or not name then
    return nil, nil
  end

  local cached = NORMALIZE_CACHE[name]
  if cached ~= nil then
    if cached == false then return nil, nil end
    return cached[1], cached[2]
  end

  for i = 1, #NORMALIZE_RULES do
    local pattern = NORMALIZE_RULES[i]
    local captured = name:match(pattern)
    if captured and captured ~= "" then
      local display = titleize_internal_name(captured)
      NORMALIZE_CACHE[name] = { captured, display }
      return captured, display
    end
  end

  NORMALIZE_CACHE[name] = false
  return nil, nil
end

function settings_cache.is_whitelist_entity_type(entity_type)
  return GROUPABLE_WHITELIST_ENTITY_TYPES[entity_type] or false
end

function settings_cache.is_whitelist_groupable(entity)
  return entity and entity.valid and GROUPABLE_WHITELIST_ENTITY_TYPES[entity.type] or false
end

function settings_cache.is_blacklist_active()
  return BLACKLIST_ACTIVE
end

settings_cache.resolve_shadow_profile = resolve_shadow_profile

function settings_cache.is_blacklisted_name(name)
  if BLACKLIST_EXACT[name] then
    return true
  end
  for i = 1, #BLACKLIST_PREFIXES do
    local prefix = BLACKLIST_PREFIXES[i]
    if name:sub(1, #prefix) == prefix then
      return true
    end
  end
  for i = 1, #BLACKLIST_SUFFIXES do
    local suffix = BLACKLIST_SUFFIXES[i]
    if name:sub(- #suffix) == suffix then
      return true
    end
  end
  return false
end

return settings_cache
