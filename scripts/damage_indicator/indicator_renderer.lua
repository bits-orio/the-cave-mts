-- indicator_renderer.lua
-- Dummiez 2026/05/01

local indicators = {}

local settings_cache = require("scripts.damage_indicator.settings_cache")
local color_utils = require("scripts.damage_indicator.color_utils")
local text_utils = require("scripts.damage_indicator.text_utils")
local viewer_utils = require("scripts.damage_indicator.viewer_utils")
local entity_utils = require("scripts.damage_indicator.entity_utils")
local damage_tracking = require("scripts.damage_indicator.damage_tracking")

local STARTUP = settings_cache.STARTUP
local SHADOW_COLOR = color_utils.SHADOW_COLOR
local SCALE_GROWTH_POP_SETTLE_AGE = 22
local SCALE_GROWTH_DURATION_TICKS = 60 * 60 * 2

local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_log = math.log
local math_ceil = math.ceil

local HASH_MOD = 2147483647

local function mix_seed(seed, value)
  value = math_floor(value or 0)
  seed = (seed + value * 48271 + 1) % HASH_MOD
  return (seed * 69621 + 12345) % HASH_MOD
end

local function hash_text(seed, value)
  if type(value) ~= "string" then return seed end
  for i = 1, #value do
    seed = mix_seed(seed, string.byte(value, i))
  end
  return seed
end

-- Pure event-derived pseudo-random value. This never touches Lua's shared RNG,
-- so presentation choices cannot move the simulation's random sequence apart.
local function deterministic_unit(event, salt)
  local entity = event and event.entity
  local position = (entity and entity.valid and entity.position) or { x = 0, y = 0 }
  local seed = mix_seed((event and event.tick) or (game and game.tick) or 0, salt or 0)
  seed = mix_seed(seed, entity and entity.valid and entity.surface.index or 0)
  seed = mix_seed(seed, entity and entity.valid and entity.unit_number or 0)
  seed = mix_seed(seed, math_floor((position.x or 0) * 256))
  seed = mix_seed(seed, math_floor((position.y or 0) * 256))
  seed = mix_seed(seed, math_floor(((event and event.final_damage_amount) or 0) * 1000))
  if event and event.damage_type then
    seed = hash_text(seed, event.damage_type.name)
  end
  local cause = event and event.cause
  if cause and cause.valid then
    seed = mix_seed(seed, cause.unit_number or 0)
    seed = hash_text(seed, cause.name)
  end
  return seed / HASH_MOD
end

local adjust_damage_color = color_utils.adjust_damage_color
local append_damage_color_blend = color_utils.append_damage_color_blend
local formatted_damage_text = text_utils.formatted_damage_text
local indicator_text_with_group_count = text_utils.indicator_text_with_group_count
local get_damage_origin_position = viewer_utils.get_damage_origin_position
local is_whitelist_groupable = settings_cache.is_whitelist_groupable
local is_one_tile_groupable_building = entity_utils.is_one_tile_groupable_building
local damage_key = entity_utils.damage_key

local state = nil
local ctx = {}

-- Runtime-only LuaRenderObject cache, keyed by render id.
-- LuaRenderObjects cannot be serialized to storage; this cache rebuilds on demand after load.
local render_object_cache = {}

-- Reusable buffers to avoid per-tick allocations
local _color_buf_main = { r = 0, g = 0, b = 0, a = 1 }
local _color_buf_shadow = { r = 0, g = 0, b = 0, a = 1 }
local _target_buf_pos = { x = 0, y = 0 }
local _target_buf_offset = { 0, 0 }
local _target_buf_entity = { entity = nil, offset = _target_buf_offset }

function indicators.init(context)
  ctx = context or {}
end

function indicators.set_state(new_state)
  state = new_state
end

function indicators.reset_render_cache()
  render_object_cache = {}
end

-- Resolve a render id to a LuaRenderObject, with a runtime cache.
-- Returns nil if the object no longer exists/is invalid.
local function resolve_render_object(id)
  if not id then return nil end
  local obj = render_object_cache[id]
  if obj and obj.valid then
    return obj
  end
  if obj then
    -- cached but invalid; drop it
    render_object_cache[id] = nil
  end
  obj = rendering.get_object_by_id(id)
  if obj and obj.valid then
    render_object_cache[id] = obj
    return obj
  end
  return nil
end

local function cache_render_object(obj)
  if obj and obj.valid then
    render_object_cache[obj.id] = obj
  end
end

local function base_scale_for_amount(amount, user_scale)
  local amount_scale = math_min(0.894, math_log(amount + 1) / 7)
  return (0.936 + amount_scale) * user_scale
end

-- visual_settings: the closest viewer's visual cache. When nil, drift is suppressed
-- (returns 0,0). This shouldn't happen in the main path but defends against indicators
-- whose authoritative viewer left mid-life from being recomputed without a fallback.
local function get_drift(event, aoe_origin, visual_settings)
  if not visual_settings then
    return 0, 0
  end
  local distance = visual_settings.drift_distance
  local drift_style = visual_settings.drift_style
  local random_x = (deterministic_unit(event, 17) - 0.5) * 0.18

  if drift_style == "upward" or distance <= 0 then
    return random_x, -distance
  end

  local origin = get_damage_origin_position(event, aoe_origin)
  if not origin then
    return random_x, -distance
  end

  local position = event.entity.position
  local away_x = position.x - origin.x
  local away_y = position.y - origin.y
  local length = math_sqrt(away_x * away_x + away_y * away_y)
  if length < 0.001 then
    return random_x, -distance
  end

  away_x = away_x / length
  away_y = away_y / length

  if drift_style == "mixed" then
    away_x = away_x * 0.72
    away_y = away_y * 0.72 - 0.28
    length = math_sqrt(away_x * away_x + away_y * away_y)
    if length > 0.001 then
      away_x = away_x / length
      away_y = away_y / length
    end
  end

  return away_x * distance + random_x, away_y * distance
end

local function ease_out_cubic(t)
  if t <= 0 then
    return 0
  elseif t >= 1 then
    return 1
  end

  local inverse = 1 - t
  return 1 - inverse * inverse * inverse
end

local function make_target_new(entity, anchor_x, anchor_y, offset_x, offset_y)
  -- Allocate-once for indicator creation. Render API copies the value.
  if entity and entity.valid then
    return { entity = entity, offset = { offset_x, offset_y } }
  end
  return { x = anchor_x + offset_x, y = anchor_y + offset_y }
end

local function set_target_buf(entity, anchor_x, anchor_y, offset_x, offset_y)
  -- Reuses module-level buffers; only safe for synchronous assignment to render obj.
  if entity and entity.valid then
    _target_buf_offset[1] = offset_x
    _target_buf_offset[2] = offset_y
    _target_buf_entity.entity = entity
    _target_buf_entity.offset = _target_buf_offset
    return _target_buf_entity
  end
  _target_buf_pos.x = anchor_x + offset_x
  _target_buf_pos.y = anchor_y + offset_y
  return _target_buf_pos
end

local function update_indicator_anchor(indicator)
  if indicator.entity and indicator.entity.valid then
    indicator.anchor_x = indicator.entity.position.x
    indicator.anchor_y = indicator.entity.position.y
  else
    indicator.entity = nil
  end
end

local function destroy_indicator(indicator)
  if ctx.invalidate_group_member_cell_index then ctx.invalidate_group_member_cell_index(indicator) end
  local text_id = indicator.text_id
  if text_id then
    local text = resolve_render_object(text_id)
    if text then text.destroy() end
    render_object_cache[text_id] = nil
  end

  local shadow_ids = indicator.shadow_ids
  if shadow_ids then
    for i = 1, #shadow_ids do
      local sid = shadow_ids[i]
      if sid then
        local shadow = resolve_render_object(sid)
        if shadow then shadow.destroy() end
        render_object_cache[sid] = nil
      end
    end
  end
end

local function trim_active_indicators()
  local max_active = STARTUP.max_active
  local active = state.active
  local count = #active
  if count <= max_active then return end

  -- Remove the oldest (front) entries efficiently via shift
  local overflow = count - max_active
  for i = 1, overflow do
    local removed = active[i]
    if removed then
      destroy_indicator(removed)
      damage_tracking.clear_indicator_recent_keys(removed)
    end
  end
  -- Shift remaining entries down
  for i = 1, max_active do
    active[i] = active[i + overflow]
  end
  for i = max_active + 1, count do
    active[i] = nil
  end
end

local function same_player_list(left, right)
  if left == right then
    return true
  end
  if not left or not right or #left ~= #right then
    return false
  end

  for i = 1, #left do
    if left[i] ~= right[i] then
      return false
    end
  end
  return true
end

local function update_indicator_text(indicator, text_value, viewers, shadow_text_value)
  local text = resolve_render_object(indicator.text_id)
  if not text then
    return false
  end

  local shadow_text = shadow_text_value or text_value
  text.text = text_value

  local shadow_ids = indicator.shadow_ids
  local viewers_changed = not same_player_list(viewers, indicator.viewers_assigned)
  if shadow_ids then
    for i = 1, #shadow_ids do
      local shadow = resolve_render_object(shadow_ids[i])
      if shadow then
        shadow.text = shadow_text
        if viewers_changed then
          shadow.players = viewers
        end
      end
    end
  end

  if viewers_changed then
    text.players = viewers
    indicator.viewers_assigned = viewers
  end
  return true
end

-- Compute the effective drift start tick. Drift is parked while the entity is being
-- actively hit (quiet_ticks <= combine_ticks) and begins playing once quiet. KB
-- indicators always drift from killing_blow_tick so the kb_pulse gets fresh motion.
-- A drift_origin_override is honored when set (used by freeze_drift_into_start_offset
-- below to preserve visible position across anchor changes).
local function effective_drift_start_tick(indicator)
  if indicator.drift_origin_override then
    return indicator.drift_origin_override
  end
  if indicator.killing_blow then
    return indicator.killing_blow_tick or indicator.created_tick or 0
  end
  return (indicator.last_hit_tick or indicator.created_tick or 0) + STARTUP.combine_ticks
end

-- Bake whatever drift the indicator has accumulated so far into start_offset_*, then
-- override the drift origin to "now" so further drift restarts from the current visible
-- position. Used by move_indicator_to_anchor (group merges/appends) to preserve visible
-- position when the anchor changes mid-drift -- without this, the text snaps from
-- "anchor + start_offset + drift * eased" back to "anchor + start_offset + drift * 0"
-- on the next animate frame. The override is cleared by refresh_recent_indicator on
-- the next hit so normal hit-driven drift parking resumes.
local function freeze_drift_into_start_offset(indicator, now)
  local lifetime = indicator.lifetime or 1
  local drift_start_tick = effective_drift_start_tick(indicator)
  local drift_age = now - drift_start_tick
  if drift_age <= 0 then
    return
  end
  local progress = drift_age / lifetime
  if progress > 1 then progress = 1 end
  local eased = ease_out_cubic(progress)
  if eased <= 0 then
    return
  end
  local drift_x = indicator.drift_x or 0
  local drift_y = indicator.drift_y or 0
  indicator.start_offset_x = (indicator.start_offset_x or 0) + drift_x * eased
  indicator.start_offset_y = (indicator.start_offset_y or 0) + drift_y * eased
  -- The remaining drift to play out is whatever fraction of (drift_x, drift_y) is left.
  indicator.drift_x = drift_x * (1 - eased)
  indicator.drift_y = drift_y * (1 - eased)
  indicator.drift_origin_override = now
end

local function flush_indicator_text(indicator, now)
  indicator.displayed_amount = indicator.amount
  indicator.displayed_reduced_amount = indicator.reduced_amount
  indicator.pending_text_update = false
  indicator.next_text_update_tick = now + (indicator.text_update_interval or STARTUP.text_update_interval)
  indicator.base_scale = base_scale_for_amount(indicator.displayed_amount, indicator.user_scale or 1)
  local kb = indicator.killing_blow
  local amount = indicator.displayed_amount
  local reduced = indicator.displayed_reduced_amount
  local has_reduced = reduced and reduced > 0
  -- text_settings was baked at indicator creation from the closest viewer's per-user
  -- text-formatting preferences. It stays stable across the indicator's life so the
  -- displayed format doesn't shift when the closest player changes mid-fight.
  local text_settings = indicator.text_settings
  -- Fast path: when there's no reduction, the colored and uncolored variants are identical;
  -- we can compute the base text once and share it for main + shadow.
  local main_text = formatted_damage_text(amount, reduced, true, kb, text_settings)
  local shadow_text = has_reduced and formatted_damage_text(amount, reduced, false, kb, text_settings) or main_text
  return update_indicator_text(
    indicator,
    indicator_text_with_group_count(indicator, main_text, true, text_settings),
    indicator.viewers,
    indicator_text_with_group_count(indicator, shadow_text, false, text_settings)
  )
end

-- Promote a tentative killing blow to a confirmed one. Centralizes the color-lock,
-- kb_longevity computation, drift refresh, and force-flush that previously lived
-- inline in refresh_recent_indicator. Used both for the immediate-commit path (when
-- the entity is already gone or invalid) and for the deferred-promotion path (one
-- tick after the lethal hit, when we've confirmed a damage-reduction mod didn't
-- intervene to keep the entity alive).
local function finalize_killing_blow(indicator, now, base_color_hint, aoe_origin)
  local color_settings = indicator.color_settings
  indicator.killing_blow = true
  indicator.killing_blow_tick = now
  indicator.tentative_killing_blow = nil
  indicator.tentative_killing_blow_tick = nil

  local fight_entry = state.first_damage_tick_by_key and state.first_damage_tick_by_key[indicator.key]
  local fight_start = (fight_entry and fight_entry.first) or indicator.created_tick or now
  local lifespan_ticks = now - fight_start
  local longevity = lifespan_ticks / SCALE_GROWTH_DURATION_TICKS
  if longevity < 0 then longevity = 0 elseif longevity > 1 then longevity = 1 end
  indicator.kb_longevity = longevity

  local base_color = indicator.base_type_color or base_color_hint or indicator.color
  indicator.color = adjust_damage_color(base_color, indicator.amount, color_settings)

  if indicator.entity and indicator.entity.valid then
    local synthetic_event = { entity = indicator.entity, tick = now }
    local kb_drift_x, kb_drift_y = get_drift(synthetic_event, aoe_origin, indicator.visual_settings)
    indicator.drift_x = kb_drift_x
    indicator.drift_y = kb_drift_y
  end

  indicator.pending_text_update = true
  return flush_indicator_text(indicator, now)
end

-- Cancel a tentative killing blow without promoting it. Called when a damage-reduction
-- mod (e.g. Rampant overdamage protection) clamped the lethal hit AFTER our handler
-- observed event.final_health <= 0. We never locked the color or set the "!" marker
-- in this state, so nothing visual needs undoing -- just drop the tentative flags.
local function cancel_tentative_killing_blow(indicator)
  indicator.tentative_killing_blow = nil
  indicator.tentative_killing_blow_tick = nil
end

local function detach_indicator_from_entity(indicator)
  indicator.entity = nil
  local start_offset_x = indicator.start_offset_x or 0
  local start_offset_y = indicator.start_offset_y or 0

  local base_x = indicator.current_x or ((indicator.anchor_x or 0) + start_offset_x)
  local base_y = indicator.current_y or ((indicator.anchor_y or 0) + start_offset_y)
  indicator.anchor_x = indicator.anchor_x or (base_x - start_offset_x)
  indicator.anchor_y = indicator.anchor_y or (base_y - start_offset_y)
  indicator.current_x = base_x
  indicator.current_y = base_y

  local text = resolve_render_object(indicator.text_id)
  if text then
    _target_buf_pos.x = base_x
    _target_buf_pos.y = base_y
    text.target = _target_buf_pos
  end

  local shadow_ids = indicator.shadow_ids
  if shadow_ids then
    local shadow_offsets = indicator.shadow_offsets
    for i = 1, #shadow_ids do
      local shadow = resolve_render_object(shadow_ids[i])
      local offset = shadow_offsets and shadow_offsets[i]
      if shadow and offset then
        _target_buf_pos.x = base_x + offset.x
        _target_buf_pos.y = base_y + offset.y
        shadow.target = _target_buf_pos
      end
    end
  end
end

local function move_indicator_to_anchor(indicator, anchor_x, anchor_y)
  indicator.entity = nil
  indicator.last_entity_attached = nil
  indicator.last_offset_x = -9999
  indicator.last_offset_y = -9999

  -- Bake current drift into start_offset before we change the anchor so the visible
  -- position is preserved (no teleport when drift has already played out).
  freeze_drift_into_start_offset(indicator, game.tick)

  indicator.anchor_x = anchor_x
  indicator.anchor_y = anchor_y

  local offset_x = indicator.start_offset_x or 0
  local offset_y = indicator.start_offset_y or 0
  indicator.current_x = anchor_x + offset_x
  indicator.current_y = anchor_y + offset_y

  local text = resolve_render_object(indicator.text_id)
  if text then
    text.target = set_target_buf(nil, anchor_x, anchor_y, offset_x, offset_y)
  end

  local shadow_ids = indicator.shadow_ids
  if shadow_ids then
    local shadow_offsets = indicator.shadow_offsets
    for i = 1, #shadow_ids do
      local shadow = resolve_render_object(shadow_ids[i])
      local offset = shadow_offsets and shadow_offsets[i]
      if shadow and offset then
        shadow.target = set_target_buf(nil, anchor_x, anchor_y, offset_x + offset.x, offset_y + offset.y)
      end
    end
  end
end

local function clear_recent_key_for_entity(entity)
  if not entity or not entity.valid then
    return
  end

  if not state and ctx.ensure_storage then ctx.ensure_storage() end
  local key = damage_key(entity)
  local indicator = state.recent_by_key[key]
  if indicator then
    update_indicator_anchor(indicator)
    if indicator.pending_text_update then
      flush_indicator_text(indicator, game.tick)
    end
    if indicator.entity == entity then
      detach_indicator_from_entity(indicator)
    end
    damage_tracking.remove_recent_key(indicator, key)
  end
  -- Drop the per-key first-damage marker so a respawned/replaced entity at the same key
  -- starts fresh.
  if state.first_damage_tick_by_key then
    state.first_damage_tick_by_key[key] = nil
  end
end

local function draw_shadow_texts(text_value, surface, entity, anchor_x, anchor_y, base_offset_x, base_offset_y,
                                 base_scale, viewers, shadow_offsets, font_name, alt_mode)
  local shadow_ids = {}

  for i = 1, #shadow_offsets do
    local offset = shadow_offsets[i]
    local shadow = rendering.draw_text {
      text = text_value,
      surface = surface,
      target = make_target_new(entity, anchor_x, anchor_y, base_offset_x + offset.x, base_offset_y + offset.y),
      color = { r = SHADOW_COLOR.r, g = SHADOW_COLOR.g, b = SHADOW_COLOR.b, a = offset.a },
      scale = base_scale,
      font = font_name,
      alignment = "center",
      vertical_alignment = "middle",
      scale_with_zoom = true,
      use_rich_text = true,
      only_in_alt_mode = alt_mode,
      players = viewers
    }

    shadow_ids[i] = shadow.id
    cache_render_object(shadow)
  end

  return shadow_ids
end

local function add_indicator(event, viewers, user_scale, color, key, amount, reduced_amount, killing_blow,
                             base_type_color, groupable, aoe_origin, text_settings, visual_settings, color_settings)
  local position = event.entity.position
  local offset_x = (deterministic_unit(event, 31) - 0.5) * 0.72
  local offset_y = -0.65 - deterministic_unit(event, 47) * 0.45
  local has_reduced = reduced_amount and reduced_amount > 0
  -- Killing blow is deferred until next tick (see refresh_recent_indicator note); the
  -- text spawns WITHOUT the "!" marker and gets flushed on promotion if the entity
  -- actually died, or stays normal if a damage-reduction mod kept it alive.
  local text_value = formatted_damage_text(amount, reduced_amount, true, false, text_settings)
  local shadow_text_value = has_reduced and formatted_damage_text(amount, reduced_amount, false, false, text_settings) or
      text_value
  local base_scale = base_scale_for_amount(amount, user_scale)
  -- Visual settings come from the closest viewer's per-user preferences. When nil
  -- (extremely rare; would require all viewers to have left during creation), fall back
  -- to safe defaults so the indicator is still well-formed.
  local animation_speed = (visual_settings and visual_settings.animation_speed) or 1
  local lifetime_setting = (visual_settings and visual_settings.lifetime) or 72
  local lifetime = math_max(1, math_ceil(lifetime_setting / animation_speed))
  local text_update_interval = STARTUP.text_update_interval
  local shadow_offsets = (visual_settings and visual_settings.shadow_offsets) or {}
  local font_name = STARTUP.font_name
  local alt_mode = (visual_settings and visual_settings.alt_mode) or false
  local drift_x, drift_y = get_drift(event, aoe_origin, visual_settings)
  local target = make_target_new(event.entity, position.x, position.y, offset_x, offset_y)

  local shadow_ids = draw_shadow_texts(shadow_text_value, event.entity.surface, event.entity, position.x, position.y,
    offset_x, offset_y, base_scale, viewers, shadow_offsets, font_name, alt_mode)

  local text = rendering.draw_text {
    text = text_value,
    surface = event.entity.surface,
    target = target,
    color = { r = color.r, g = color.g, b = color.b, a = 1 },
    scale = base_scale,
    font = font_name,
    alignment = "center",
    vertical_alignment = "middle",
    scale_with_zoom = true,
    use_rich_text = true,
    only_in_alt_mode = alt_mode,
    players = viewers
  }

  text.bring_to_front()
  cache_render_object(text)
  local initial_base_type_color = base_type_color or color

  -- Resolve groupable up front so we can avoid allocating group bookkeeping tables for
  -- entities that can never participate in a group.
  local resolved_groupable = groupable
  if resolved_groupable == nil then
    resolved_groupable = is_one_tile_groupable_building(event.entity)
  end

  -- KB is deferred by one tick (see finalize_killing_blow / animate_indicator). We stash
  -- the lethal-hit metadata onto tentative_kb_* fields and let the deferred promotion
  -- (or cancellation) handle kb_longevity, color lock, and drift refresh.
  local tentative_killing_blow = killing_blow or nil
  local tentative_killing_blow_tick = killing_blow and event.tick or nil
  local tentative_kb_base_color = killing_blow and (base_type_color or color) or nil
  local tentative_kb_aoe_origin = killing_blow and aoe_origin or nil

  -- Only allocate group-tracking tables when the indicator can actually participate in
  -- grouping. Non-groupable indicators (units, vehicles, characters, etc.) skip these
  -- entirely; the grouping module lazy-initializes them if it ever needs to.
  local combine_ticks = STARTUP.combine_ticks
  local recent_keys = (resolved_groupable or combine_ticks > 0) and { [key] = true } or nil
  local group_member_positions = resolved_groupable and { { x = position.x, y = position.y } } or nil
  local group_min_x = resolved_groupable and position.x or nil
  local group_max_x = resolved_groupable and position.x or nil
  local group_min_y = resolved_groupable and position.y or nil
  local group_max_y = resolved_groupable and position.y or nil
  local group_anchor_sum_x = resolved_groupable and position.x or nil
  local group_anchor_sum_y = resolved_groupable and position.y or nil

  -- Debug-info fields. Cheap to capture once at creation; the text composer reads them
  -- only when the closest viewer has debug_info enabled. unit_number is nil for buildings,
  -- which is fine -- the suffix simply omits that field.
  local debug_unit_number = event.entity.unit_number
  local debug_entity_type = event.entity.type
  local debug_damage_type = event.damage_type and event.damage_type.name or nil

  -- Group-name normalization: tiered enemy variants (e.g. Rampant's t10, t8, t6 spawners)
  -- collapse to a single grouping identity so they merge regardless of tier. group_name
  -- is the rule pattern when matched (otherwise the raw entity_name) and is what
  -- grouping comparisons use. group_display_name is the user-facing override that
  -- replaces the localised name in the group count tag.
  local resolved_group_name, group_display_name = settings_cache.resolve_normalized_name(event.entity.name)
  local group_name = resolved_group_name or event.entity.name

  local indicator = {
    text_id = text.id,
    shadow_ids = shadow_ids,
    shadow_offsets = shadow_offsets,
    key = key,
    recent_keys = recent_keys,
    entity = event.entity,
    entity_name = event.entity.name,
    entity_localised_name = event.entity.localised_name,
    group_name = group_name,
    group_display_name = group_display_name,
    surface_index = event.entity.surface.index,
    debug_unit_number = debug_unit_number,
    debug_entity_type = debug_entity_type,
    debug_damage_type = debug_damage_type,
    amount = amount,
    reduced_amount = reduced_amount,
    displayed_amount = amount,
    displayed_reduced_amount = reduced_amount,
    pending_text_update = false,
    next_text_update_tick = event.tick + text_update_interval,
    text_update_interval = text_update_interval,
    viewers = viewers,
    viewers_assigned = viewers,
    user_scale = user_scale,
    created_tick = event.tick,
    last_hit_tick = event.tick,
    lifetime = lifetime,
    animation_speed = animation_speed,
    anchor_x = position.x,
    anchor_y = position.y,
    start_offset_x = offset_x,
    start_offset_y = offset_y,
    drift_x = drift_x,
    drift_y = drift_y,
    base_scale = base_scale,
    color = color,
    groupable = resolved_groupable,
    whitelist_groupable = is_whitelist_groupable(event.entity) or nil,
    group_position_count = 1,
    group_anchor_sum_x = group_anchor_sum_x,
    group_anchor_sum_y = group_anchor_sum_y,
    group_member_positions = group_member_positions,
    group_min_x = group_min_x,
    group_max_x = group_max_x,
    group_min_y = group_min_y,
    group_max_y = group_max_y,
    -- Base damage-type color. By default this is locked to the first hit; when color
    -- blending is enabled it becomes the damage-weighted average of combined hits.
    base_type_color = initial_base_type_color,
    color_blend_total = amount,
    color_blend_r = initial_base_type_color.r * amount,
    color_blend_g = initial_base_type_color.g * amount,
    color_blend_b = initial_base_type_color.b * amount,
    killing_blow = nil,
    killing_blow_tick = nil,
    kb_longevity = nil,
    tentative_killing_blow = tentative_killing_blow,
    tentative_killing_blow_tick = tentative_killing_blow_tick,
    tentative_kb_base_color = tentative_kb_base_color,
    tentative_kb_aoe_origin = tentative_kb_aoe_origin,
    -- Closest viewer's per-user text settings, baked at creation. Stays stable for the
    -- indicator's life so its display format doesn't shift on combine when the closest
    -- player changes. nil here is fine: text_utils falls back to safe defaults.
    text_settings = text_settings,
    -- Closest viewer's visual/animation settings, baked at creation. lifetime,
    -- animation_speed, shadow_offsets, and alt_mode are already copied into individual
    -- indicator fields above (since they're consumed by various animate paths); keeping
    -- the reference here lets refresh_recent_indicator recompute drift on KB events
    -- using the same drift_distance/drift_style that the indicator originally used.
    visual_settings = visual_settings,
    -- Closest viewer's color settings, baked at creation. Drives type-color resolution,
    -- intensity ramp, blend behavior, and the cap. Stays stable for the indicator's life
    -- so the color blending math (color_blend_total/r/g/b accumulators) keeps using a
    -- consistent reference even if the closest viewer or their preferences change later.
    color_settings = color_settings,
    -- last_* for animation no-op detection
    last_scale = -1,
    last_alpha = -1,
    last_color_r = -1,
    last_color_g = -1,
    last_color_b = -1,
    last_offset_x = -9999,
    last_offset_y = -9999,
  }

  local active = state.active
  active[#active + 1] = indicator
  state.recent_by_key[key] = indicator
  if ctx.update_tick_handler then
    ctx.update_tick_handler()
  end
  trim_active_indicators()
end

local function refresh_recent_indicator(event, indicator, viewers, user_scale, color, amount, reduced_amount,
                                        killing_blow, aoe_origin)
  -- Bake any drift that played out before this hit lands. If the indicator had been
  -- quiet long enough for drift to start (last_hit_tick + combine_ticks <= now), drift
  -- has been advancing. Updating last_hit_tick below would snap drift back to 0 on the
  -- next animate frame, teleporting the text. Freezing first preserves visible position.
  -- (No-op when drift was parked: drift_age <= 0 -> early return inside the helper.)
  freeze_drift_into_start_offset(indicator, event.tick)
  -- Clear the override the freeze just set (and any prior one from move_indicator_to_anchor).
  -- On normal hits we want hit-driven parking back -- drift restarts combine_ticks after
  -- last_hit_tick, not immediately. The KB branch below handles its own drift start via
  -- killing_blow_tick, so clearing here is correct for both paths.
  indicator.drift_origin_override = nil
  indicator.amount = indicator.amount + amount
  indicator.reduced_amount = (indicator.reduced_amount or 0) + (reduced_amount or 0)
  indicator.last_hit_tick = event.tick
  indicator.pending_text_update = true
  indicator.viewers = viewers
  indicator.user_scale = user_scale
  -- Refresh the latest damage type so the debug suffix reflects the most recent hit.
  if event.damage_type and event.damage_type.name then
    indicator.debug_damage_type = event.damage_type.name
  end
  -- Use the indicator's baked color_settings so blend math and the intensity ramp keep
  -- using a stable reference even when the closest viewer or their preferences change
  -- mid-fight.
  local color_settings = indicator.color_settings
  local base_type_color = append_damage_color_blend(indicator, color, amount, color_settings)
  -- The damage-type identity (base hue) is normally locked to the first hit's damage
  -- type. When blending is enabled, the base hue becomes a damage-weighted average of
  -- all combined hits instead. In both cases the amount-based intensity ramp is then
  -- re-applied so accumulating damage gets visibly darker/redder as expected.
  -- In damage-ramp color mode, adjust_damage_color ignores the base color entirely
  -- and recomputes from amount, so this branch behaves the same as before in that mode.
  if not indicator.killing_blow then
    indicator.color = adjust_damage_color(base_type_color or color, indicator.amount, color_settings)
  end
  if killing_blow and not indicator.killing_blow then
    -- Defer the killing-blow lock by one tick. Damage-reduction mods (e.g. Rampant's
    -- overdamage protection) can intercept a lethal hit AFTER our handler reads
    -- event.final_health <= 0, clamping damage and keeping the entity alive. By
    -- waiting one tick we can verify (in animate_indicator) that the entity actually
    -- died before locking in the "!" marker, kb_pulse, and color freeze. The deferred
    -- promotion path will recompute the final color/kb_longevity then. The cached drift
    -- vector and aoe_origin are stashed so the deferred promotion can refresh drift
    -- using the same data this hit would have used.
    indicator.tentative_killing_blow = true
    indicator.tentative_killing_blow_tick = event.tick
    indicator.tentative_kb_base_color = base_type_color or color
    indicator.tentative_kb_aoe_origin = aoe_origin
  end

  if event.tick < (indicator.next_text_update_tick or event.tick) then
    return true
  end

  return flush_indicator_text(indicator, event.tick)
end

local function apply_external_damage_reduction_to_recent(key, report)
  local indicator = state.recent_by_key[key]
  if not indicator
      or indicator.killing_blow
      or indicator.last_hit_tick ~= report.tick then
    return false
  end

  local original_damage = report.original_damage or 0
  local final_damage = report.final_damage or 0
  local reduced_damage = report.reduced_damage or 0
  if original_damage <= 0 or reduced_damage <= 0 then
    return false
  end

  local adjusted_amount = (indicator.amount or 0) - original_damage + final_damage
  if adjusted_amount < 0 then
    adjusted_amount = 0
  end
  indicator.amount = adjusted_amount
  indicator.reduced_amount = (indicator.reduced_amount or 0) + reduced_damage

  -- Use the indicator's baked color_settings so the blend gate and intensity ramp match
  -- whatever the indicator was created with.
  local color_settings = indicator.color_settings or color_utils.DEFAULT_COLOR_SETTINGS
  if color_settings.blend_damage_type_colors and color_settings.color_mode == "damage-type" then
    local old_total = indicator.color_blend_total
    local new_total = old_total and (old_total - original_damage + final_damage) or nil
    if old_total and old_total > 0 and new_total and new_total > 0 then
      local scale = new_total / old_total
      indicator.color_blend_total = new_total
      indicator.color_blend_r = (indicator.color_blend_r or 0) * scale
      indicator.color_blend_g = (indicator.color_blend_g or 0) * scale
      indicator.color_blend_b = (indicator.color_blend_b or 0) * scale
      indicator.base_type_color = {
        r = indicator.color_blend_r / new_total,
        g = indicator.color_blend_g / new_total,
        b = indicator.color_blend_b / new_total
      }
    end
  end

  indicator.color = adjust_damage_color(indicator.base_type_color or indicator.color, indicator.amount, color_settings)
  indicator.pending_text_update = true
  indicator.next_text_update_tick = game.tick
  return true
end

local function animate_indicator(indicator, now)
  local text = resolve_render_object(indicator.text_id)
  if not text then
    destroy_indicator(indicator)
    return false
  end

  -- Tentative-killing-blow resolution: two ticks after observing event.final_health <= 0,
  -- decide whether to promote (entity is actually dead) or cancel (a damage-reduction
  -- mod like Rampant intervened and the entity is still alive). The 2-tick wait gives
  -- damage-reduction mods that defer their health restoration (e.g. via on_tick or a
  -- queued action rather than synchronous in on_entity_damaged) time to land before
  -- we lock the indicator's KB state. Beyond ~2 ticks the visual "!" delay becomes
  -- perceptible (~33ms), so this is the upper bound for the tradeoff.
  if indicator.tentative_killing_blow and now >= (indicator.tentative_killing_blow_tick or now) + 2 then
    local entity = indicator.entity
    local entity_alive = entity and entity.valid and (entity.health or 0) > 0
    if entity_alive then
      cancel_tentative_killing_blow(indicator)
    else
      if not finalize_killing_blow(indicator, now,
            indicator.tentative_kb_base_color, indicator.tentative_kb_aoe_origin) then
        destroy_indicator(indicator)
        return false
      end
      indicator.tentative_kb_base_color = nil
      indicator.tentative_kb_aoe_origin = nil
    end
  end

  if indicator.pending_text_update and now >= (indicator.next_text_update_tick or now) then
    if not flush_indicator_text(indicator, now) then
      destroy_indicator(indicator)
      return false
    end
  end

  update_indicator_anchor(indicator)
  if indicator.pending_text_update and not indicator.entity then
    if not flush_indicator_text(indicator, now) then
      destroy_indicator(indicator)
      return false
    end
  end

  if not indicator.anchor_x or not indicator.anchor_y then
    destroy_indicator(indicator)
    return false
  end

  local lifetime = indicator.lifetime
  local age = now - indicator.created_tick
  local fade_start = 0.64
  local quiet_ticks = now - (indicator.last_hit_tick or indicator.created_tick)
  local quiet_gate = STARTUP.combine_ticks
  -- Drift is parked while the entity is being actively hit (quiet_ticks <= combine_ticks)
  -- so the text doesn't float far from the entity during sustained combat. It begins
  -- playing only after the quiet gate. KB indicators drift from killing_blow_tick so
  -- the kb_pulse gets fresh motion.
  local drift_age = now - effective_drift_start_tick(indicator)
  if drift_age < 0 then drift_age = 0 end
  local progress = drift_age / lifetime
  if progress > 1 then progress = 1 end
  -- Drift starts fast, then eases to a stop while still ending at the configured distance.
  local eased = ease_out_cubic(progress)
  local fade_progress = 0
  if quiet_ticks > quiet_gate then
    local fade_ticks = math_max(1, math_floor(lifetime * (1 - fade_start)))
    fade_progress = (quiet_ticks - quiet_gate) / fade_ticks
    if fade_progress > 1 then fade_progress = 1 end
  end

  if fade_progress >= 1 then
    destroy_indicator(indicator)
    return false
  end

  local alpha = 1 - fade_progress

  -- Punchy pop with overshoot and a small undershoot bounce, then settle.
  -- pop_age 0..4: rapid rise from 0.20 -> 1.85 (snap-in)
  -- pop_age 4..10: drop 1.85 -> 0.92 (overshoot relax)
  -- pop_age 10..16: rise 0.92 -> 1.05 (small bounce)
  -- pop_age 16..22: settle 1.05 -> 1.00
  -- pop_age 22+:    1.00
  local pop
  local pop_age = age * indicator.animation_speed
  if pop_age < 4 then
    pop = 0.20 + 0.4125 * pop_age
  elseif pop_age < 10 then
    pop = 1.85 - 0.155 * (pop_age - 4)
  elseif pop_age < 16 then
    pop = 0.92 + 0.02167 * (pop_age - 10)
  elseif pop_age < 22 then
    pop = 1.05 - 0.00833 * (pop_age - 16)
  else
    pop = 1
  end

  -- Killing-blow gets a longevity-scaled pop on the kill: a 1-shot kill stays small,
  -- a kill that took ~2 minutes of sustained damage gets a peak of +150%. Curve mirrors
  -- the spawn pop shape — sharp asymmetric rise to peak, fast drop, brief small undershoot,
  -- then settle to a persistent baseline that the text fades at.
  if indicator.killing_blow then
    local kb_age = (now - (indicator.killing_blow_tick or indicator.created_tick)) * indicator.animation_speed
    local longevity = indicator.kb_longevity or 0
    -- Attenuate the spawn pop only as longevity rises and the kb_pulse grows large enough
    -- to overshadow it. At longevity=0 (one-shot kill) the spawn pop is fully preserved so
    -- the text still snaps in punchily; at longevity=1 (sustained fight) the spawn pop is
    -- reduced to 30% so it doesn't double up with the large kb_pulse peak.
    local pop_retention = 1 - longevity * 0.7
    pop = 1 + (pop - 1) * pop_retention
    -- Peak amplitude scales from +0.25 (one-shot) up to +1.75 (fully sustained).
    local peak_amp = 0.25 + 1.5 * longevity
    -- Persistent baseline scales from +0.10 (one-shot) up to +0.60 (fully sustained).
    local baseline_amp = 0.10 + 0.50 * longevity
    -- Brief overshoot below baseline before settling, gives the snap-back feel.
    local undershoot_amp = baseline_amp * 0.85
    local kb_pulse
    if kb_age < 5 then
      -- Sharp rise: ease-out from 0 to peak in 5 ticks.
      local t = kb_age / 5
      kb_pulse = 1 + peak_amp * (1 - (1 - t) * (1 - t))
    elseif kb_age < 11 then
      -- Fast drop: peak -> small undershoot below baseline over 6 ticks.
      local t = (kb_age - 5) / 6
      kb_pulse = 1 + peak_amp + (undershoot_amp - peak_amp) * t
    elseif kb_age < 18 then
      -- Snap back up: undershoot -> baseline over 7 ticks (ease-out).
      local t = (kb_age - 11) / 7
      kb_pulse = 1 + undershoot_amp + (baseline_amp - undershoot_amp) * (1 - (1 - t) * (1 - t))
    else
      kb_pulse = 1 + baseline_amp
    end
    pop = pop * kb_pulse
  end

  local growth_delay_ticks = SCALE_GROWTH_POP_SETTLE_AGE / indicator.animation_speed
  local growth_progress = (age - growth_delay_ticks) / SCALE_GROWTH_DURATION_TICKS
  if growth_progress < 0 then
    growth_progress = 0
  elseif growth_progress > 1 then
    growth_progress = 1
  end
  local long_lived_scale    = 1 + growth_progress
  local scale               = indicator.base_scale * long_lived_scale * pop * (1 - 0.08 * progress)
  local offset_x            = indicator.start_offset_x + indicator.drift_x * eased
  local offset_y            = indicator.start_offset_y + indicator.drift_y * eased

  -- Skip render-side updates when nothing visible changed
  local same_scale          = (scale == indicator.last_scale)
  local same_alpha          = (alpha == indicator.last_alpha)
  local color               = indicator.color
  local same_color          = color
      and color.r == indicator.last_color_r
      and color.g == indicator.last_color_g
      and color.b == indicator.last_color_b
  local same_offx           = (offset_x == indicator.last_offset_x)
  local same_offy           = (offset_y == indicator.last_offset_y)
  local entity_following    = (indicator.entity ~= nil)

  -- Even if scalars match, when following an entity we must keep target updated as the entity moves.
  -- The render API handles entity-attached targets automatically though; only push target when offsets change OR entity changed.
  local needs_target_update = (not same_offx) or (not same_offy)
      or indicator.last_entity_attached ~= entity_following

  indicator.current_x       = indicator.anchor_x + offset_x
  indicator.current_y       = indicator.anchor_y + offset_y

  if needs_target_update then
    text.target = set_target_buf(indicator.entity, indicator.anchor_x, indicator.anchor_y, offset_x, offset_y)
    indicator.last_offset_x = offset_x
    indicator.last_offset_y = offset_y
    indicator.last_entity_attached = entity_following
  end

  if not same_scale then
    text.scale = scale
    indicator.last_scale = scale
  end

  if not same_alpha or not same_color then
    _color_buf_main.r = color.r
    _color_buf_main.g = color.g
    _color_buf_main.b = color.b
    _color_buf_main.a = alpha
    text.color = _color_buf_main
    indicator.last_alpha = alpha
    indicator.last_color_r = color.r
    indicator.last_color_g = color.g
    indicator.last_color_b = color.b
  end

  local shadow_ids = indicator.shadow_ids
  if shadow_ids then
    local shadow_offsets = indicator.shadow_offsets
    local shadow_scale = scale * 1.015
    for i = 1, #shadow_ids do
      local shadow = resolve_render_object(shadow_ids[i])
      local s_offset = shadow_offsets and shadow_offsets[i]
      if shadow and s_offset then
        if needs_target_update then
          shadow.target = set_target_buf(indicator.entity, indicator.anchor_x, indicator.anchor_y, offset_x + s_offset.x,
            offset_y + s_offset.y)
        end
        if not same_scale then
          shadow.scale = shadow_scale
        end
        if not same_alpha then
          _color_buf_shadow.r = SHADOW_COLOR.r
          _color_buf_shadow.g = SHADOW_COLOR.g
          _color_buf_shadow.b = SHADOW_COLOR.b
          _color_buf_shadow.a = alpha * s_offset.a
          shadow.color = _color_buf_shadow
        end
      end
    end
  end

  return true
end

indicators.resolve_render_object = resolve_render_object
indicators.cache_render_object = cache_render_object
indicators.base_scale_for_amount = base_scale_for_amount
indicators.update_indicator_anchor = update_indicator_anchor
indicators.destroy_indicator = destroy_indicator
indicators.trim_active_indicators = trim_active_indicators
indicators.update_indicator_text = update_indicator_text
indicators.flush_indicator_text = flush_indicator_text
indicators.detach_indicator_from_entity = detach_indicator_from_entity
indicators.move_indicator_to_anchor = move_indicator_to_anchor
indicators.clear_recent_key_for_entity = clear_recent_key_for_entity
indicators.add_indicator = add_indicator
indicators.refresh_recent_indicator = refresh_recent_indicator
indicators.apply_external_damage_reduction_to_recent = apply_external_damage_reduction_to_recent
indicators.animate_indicator = animate_indicator

return indicators
