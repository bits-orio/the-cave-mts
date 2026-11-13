-- viewer_utils.lua
-- Dummiez 2026/05/01

local settings_cache = require("scripts.damage_indicator.settings_cache")

local viewers = {}

local STARTUP = settings_cache.STARTUP

local math_abs = math.abs

local player_settings_cache = {}

-- Singleton single-element viewer lists, keyed by player_index. Reused by get_viewers
-- when exactly one viewer matched (the common SP / sparse-MP case) so we avoid allocating
-- a fresh `{player.index}` table on every damage event. Identity-stable, which also lets
-- `same_player_list` in indicator_renderer short-circuit via the `left == right` check
-- on consecutive hits from the same single viewer.
local singleton_viewer_lists = {}

local function get_singleton_viewer_list(player_index)
  local list = singleton_viewer_lists[player_index]
  if not list then
    list = { player_index }
    singleton_viewer_lists[player_index] = list
  end
  return list
end

local function force_matches(left, right)
  return left and right and left.valid and right.valid and left.index == right.index
end

-- Returns the override value for `key` if a server-override is active and the key
-- exists in the decoded payload; otherwise returns the player's actual setting value.
-- Centralizes the override branch so build_text/visual/color_settings stay readable
-- and the override fallback is consistent across every per-user setting.
local function override_or(s, key)
  if settings_cache.is_override_active() then
    local payload = settings_cache.get_override_payload()
    if payload and payload[key] ~= nil then
      return payload[key]
    end
  end
  local entry = s[key]
  return entry and entry.value
end

function viewers.get_damage_force(event)
  if event.cause and event.cause.valid and event.cause.force then
    return event.cause.force
  end

  if event.source and event.source.valid and event.source.force then
    return event.source.force
  end

  return nil
end

function viewers.get_damage_origin_position(event, aoe_origin)
  if aoe_origin then
    return aoe_origin
  end

  if event.cause and event.cause.valid and event.cause.position then
    return event.cause.position
  end

  if event.source and event.source.valid and event.source.position then
    return event.source.position
  end

  return nil
end

-- Strip rich-text control characters from a marker string so a player can't accidentally
-- inject a tag like "[color=red]" via the killing-blow marker setting and break rendering.
local function sanitize_marker(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("[%[%]=/]", ""))
end

-- Per-player text-formatting settings cached alongside visibility/scale settings.
-- Reads occur on every damage event (via get_viewers->resolve authoritative); the cache
-- is invalidated on on_runtime_mod_setting_changed and on_player_left/removed.
local function build_text_settings(s)
  local template = override_or(s, "damage-indicator-text-template")
  if not template or template == "" then
    template = "__damage__"
  end
  return {
    compact_numbers = override_or(s, "damage-indicator-compact-numbers"),
    number_separator = override_or(s, "damage-indicator-number-separator"),
    show_reductions = override_or(s, "damage-indicator-show-reductions"),
    show_group_count = override_or(s, "damage-indicator-show-group-count"),
    text_template = template,
    template_is_default = (template == "__damage__"),
    template_has_damage = template:find("__damage__", 1, true) ~= nil,
    template_has_reduced = template:find("__reduced__", 1, true) ~= nil,
    killing_blow_marker = sanitize_marker(override_or(s, "damage-indicator-killing-blow-marker") or ""),
    debug_info = override_or(s, "damage-indicator-debug-info"),
  }
end

-- Per-player color settings. Baked onto each indicator at creation by the closest
-- viewer's preferences. The eight `damage_colors` entries are normalized to 0-1 RGB
-- using settings_cache.normalize_setting_color so we don't repeat the normalization
-- on every damage event.
local function build_color_settings(s)
  local damage_colors = {}
  local types = settings_cache.VANILLA_DAMAGE_TYPES
  local defaults = settings_cache.VANILLA_DAMAGE_COLORS
  for i = 1, #types do
    local damage_type = types[i]
    -- override_or returns either the override's raw color table (r/g/b in 0-1) or the
    -- player's setting value; normalize_setting_color handles either shape and clamps.
    damage_colors[damage_type] = settings_cache.normalize_setting_color(
      override_or(s, "damage-indicator-color-" .. damage_type),
      defaults[damage_type]
    )
  end
  return {
    color_mode = override_or(s, "damage-indicator-color-mode"),
    blend_damage_type_colors = override_or(s, "damage-indicator-blend-damage-type-colors"),
    color_intensity = override_or(s, "damage-indicator-color-intensity"),
    color_intensity_cap = override_or(s, "damage-indicator-color-intensity-cap"),
    damage_colors = damage_colors,
  }
end

-- Per-player visual/animation settings. Baked onto each indicator at creation by the
-- closest viewer's preferences. `shadow_offsets` is a reference to a shared profile
-- table from settings_cache; do not mutate.
local function build_visual_settings(s)
  local shadow_style = override_or(s, "damage-indicator-shadow-style")
  return {
    lifetime = override_or(s, "damage-indicator-lifetime"),
    animation_speed = override_or(s, "damage-indicator-animation-speed"),
    drift_distance = override_or(s, "damage-indicator-drift-distance"),
    drift_style = override_or(s, "damage-indicator-drift-style"),
    shadow_style = shadow_style,
    shadow_offsets = settings_cache.resolve_shadow_profile(shadow_style),
    alt_mode = override_or(s, "damage-indicator-alt-mode"),
    killing_blow_enabled = override_or(s, "damage-indicator-killing-blow"),
  }
end

local function get_cached_player_settings(player)
  local cached = player_settings_cache[player.index]
  if cached then return cached end

  local s = settings.get_player_settings(player)
  -- Note: `enabled` is intentionally NOT routed through override_or. Per the design,
  -- the server-override controls display uniformity but each player must always be
  -- able to opt out of seeing indicators on their own screen.
  local radius = override_or(s, "damage-indicator-radius")
  cached = {
    enabled = s["damage-indicator-enabled"].value,
    minimum_damage = override_or(s, "damage-indicator-minimum-damage"),
    radius = radius,
    radius_sq = radius * radius,
    visibility = override_or(s, "damage-indicator-visibility"),
    scale = override_or(s, "damage-indicator-scale"),
    text = build_text_settings(s),
    visual = build_visual_settings(s),
    color = build_color_settings(s),
  }
  player_settings_cache[player.index] = cached
  return cached
end

-- Returns the cached text-formatting settings for the given player, or nil if the player
-- isn't cached and we can't resolve them (e.g. mid-load before init). Used as the
-- authoritative-viewer fallback when an indicator's baked text settings need to be
-- consulted for a specific player.
function viewers.get_player_text_settings(player_index)
  local cached = player_settings_cache[player_index]
  return cached and cached.text or nil
end

-- Multiplayer-safe fixed viewport approximation. LuaPlayer display resolution,
-- display scale and zoom are presentation-side values and must never decide whether
-- shared indicator state is created. Radius remains the main per-player culling gate;
-- this rectangle only keeps the original off-screen performance optimisation.
local SAFE_VIEW_HALF_WIDTH = 30
local SAFE_VIEW_HALF_HEIGHT = 17

local function is_inside_player_view(player, position, tick)
  if not STARTUP.viewport_culling then
    return true
  end

  local margin = STARTUP.viewport_margin
  local pos = player.position
  local dx = math_abs(position.x - pos.x)
  local dy = math_abs(position.y - pos.y)
  return dx <= (SAFE_VIEW_HALF_WIDTH + margin) and dy <= (SAFE_VIEW_HALF_HEIGHT + margin)
end

-- Returns: visible (bool), distance_sq (number, only meaningful when visible=true).
-- distance_sq is reused by get_viewers to pick the closest viewer as the authoritative
-- one for per-player visual settings, without recomputing the squared distance.
local function player_can_see(player, ps, entity_force, position, surface, damage_force, tick)
  if not player.connected or player.surface.index ~= surface.index then
    return false, 0
  end

  local dx = player.position.x - position.x
  local dy = player.position.y - position.y
  local distance_sq = dx * dx + dy * dy
  if distance_sq > ps.radius_sq then
    return false, distance_sq
  end

  if not is_inside_player_view(player, position, tick) then
    return false, distance_sq
  end

  local visibility = ps.visibility
  if visibility == "nearby" then
    return true, distance_sq
  end

  local player_force = player.force
  if visibility == "own-force" then
    if force_matches(player_force, entity_force) or force_matches(player_force, damage_force) then
      return true, distance_sq
    end
    return false, distance_sq
  end

  if force_matches(player_force, damage_force) and not force_matches(player_force, entity_force) then
    return true, distance_sq
  end
  return false, distance_sq
end

-- Returns: viewer_list, highest_scale, text_settings, visual_settings, color_settings, player_index
--   viewer_list: list of player indices that should see this indicator
--   highest_scale: max user_scale among viewers (drives indicator base_scale)
--   text_settings, visual_settings, color_settings: the closest viewer's per-user
--     preferences. All three are baked into the indicator at creation so its display is
--     stable across the indicator's life (no flicker when the closest player changes
--     mid-fight; the original closest viewer's choices stay in effect until fade).
--   player_index: the closest viewer's player_index (for cache lookups).
-- Closest player wins regardless of scale; this is fairer in multiplayer (no permanent
-- second-class viewer) and "closest" maps well to "the one most likely to be looking at
-- the impact". The cost is one extra distance comparison per visible viewer, and we
-- already computed the squared distance for the radius check.
function viewers.get_viewers(event, position, surface, damage_force, ignore_minimum_damage)
  local viewer_list = nil
  local viewer_count = 0
  local highest_scale = 0
  local closest_distance_sq = nil
  local closest_text_settings = nil
  local closest_visual_settings = nil
  local closest_color_settings = nil
  local closest_player_index = nil
  local final_damage = event.final_damage_amount or 0
  local tick = event.tick
  -- Hoist entity.force out of the per-player loop: each entity.force lookup is a
  -- Lua->C++ call, so reading it once is meaningfully cheaper in MP.
  local entity = event.entity
  local entity_force = (entity and entity.valid) and entity.force or nil

  for _, player in ipairs(game.connected_players) do
    local ps = get_cached_player_settings(player)
    if ps.enabled
        and (ignore_minimum_damage or final_damage >= ps.minimum_damage) then
      local visible, distance_sq = player_can_see(player, ps, entity_force, position, surface, damage_force, tick)
      if visible then
        viewer_count = viewer_count + 1
        if viewer_count == 1 then
          -- Fast path: reuse a per-player singleton list. Stable identity lets
          -- same_player_list() short-circuit via reference equality on the next hit.
          viewer_list = get_singleton_viewer_list(player.index)
        else
          if viewer_count == 2 then
            -- Promote: we previously returned the singleton list; copy it into a
            -- fresh array now that we need to append a second entry. Never mutate
            -- the singleton, since it may already be referenced by a live indicator.
            viewer_list = { viewer_list[1], player.index }
          else
            viewer_list[viewer_count] = player.index
          end
        end
        if ps.scale > highest_scale then
          highest_scale = ps.scale
        end
        if not closest_distance_sq or distance_sq < closest_distance_sq then
          closest_distance_sq = distance_sq
          closest_text_settings = ps.text
          closest_visual_settings = ps.visual
          closest_color_settings = ps.color
          closest_player_index = player.index
        end
      end
    end
  end

  if viewer_count == 0 then
    return nil, 0, nil, nil, nil, nil
  end

  return viewer_list, highest_scale, closest_text_settings, closest_visual_settings, closest_color_settings,
      closest_player_index
end

function viewers.clear_player_settings(player_index)
  player_settings_cache[player_index] = nil
  -- Drop the singleton viewer list too. Live indicators may still hold a reference
  -- to it (their `viewers` field), which is fine -- the list contents stay valid;
  -- we just don't reuse it for future events involving this player_index.
  singleton_viewer_lists[player_index] = nil
end

-- Wipe every player's cached settings. Used on on_configuration_changed so that the
-- next read picks up a freshly-toggled server-override (or any other startup change
-- that flows through build_text/visual/color_settings).
function viewers.clear_all_player_settings()
  player_settings_cache = {}
  singleton_viewer_lists = {}
end

function viewers.clear_viewport(player_index)
  -- Kept for callback compatibility. The deterministic viewport uses only the
  -- synchronized player position and therefore has no presentation cache to clear.
end

function viewers.reset_viewport_cache()
  -- Kept for load compatibility; no local display-derived cache is retained.
end

return viewers
