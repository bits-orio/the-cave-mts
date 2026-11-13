-- damage_tracking.lua
-- Dummiez 2026/05/01

local damage_tracking = {}

local next = next

local entity_utils = require("scripts.damage_indicator.entity_utils")

local state = nil
local ctx = {}
local external_damage_reductions_pending = false

function damage_tracking.init(context)
  ctx = context or {}
end

function damage_tracking.set_state(new_state)
  state = new_state
  external_damage_reductions_pending = state
      and state.external_damage_reductions
      and next(state.external_damage_reductions) ~= nil
      or false
end

function damage_tracking.has_pending_external_damage_reductions()
  return external_damage_reductions_pending
end

function damage_tracking.reset_external_damage_reductions_pending()
  external_damage_reductions_pending = false
end

local function add_recent_key(indicator, key)
  if not indicator or not key then
    return
  end

  indicator.recent_keys = indicator.recent_keys or {}
  indicator.recent_keys[key] = true
  indicator.key = indicator.key or key
  state.recent_by_key[key] = indicator
end

local function remove_recent_key(indicator, key)
  if indicator and indicator.recent_keys then
    indicator.recent_keys[key] = nil
  end
  if state.recent_by_key[key] == indicator then
    state.recent_by_key[key] = nil
  end
end

local function clear_indicator_recent_keys(indicator)
  if not indicator then
    return
  end

  local recent_keys = indicator.recent_keys
  if recent_keys then
    for key in pairs(recent_keys) do
      if state.recent_by_key[key] == indicator then
        state.recent_by_key[key] = nil
      end
    end
    indicator.recent_keys = nil
  end

  if indicator.key and state.recent_by_key[indicator.key] == indicator then
    state.recent_by_key[indicator.key] = nil
  end
end

-- Tracks the first damage tick of an ongoing fight per entity key. Used to compute KB
-- longevity (how long the entity took damage before dying), which scales the kb_pulse
-- amplitude. Entries are reset to a fresh fight when the entity has been idle longer
-- than reset_after_idle_ticks, and reaped by sweep_first_damage_ticks.
local function track_first_damage_tick(key, entity_name, tick, reset_after_idle_ticks)
  local first_damage_map = state.first_damage_tick_by_key
  if not first_damage_map then
    first_damage_map = {}
    state.first_damage_tick_by_key = first_damage_map
  end

  local fight = first_damage_map[key]
  local idle_ticks = fight and (tick - (fight.last or fight.first or tick)) or 0
  if not fight
      or fight.name ~= entity_name
      or idle_ticks < 0
      or (reset_after_idle_ticks and idle_ticks > reset_after_idle_ticks) then
    fight = { first = tick, last = tick, name = entity_name }
    first_damage_map[key] = fight
  else
    fight.last = tick
  end
end

local function record_damage_reduction_for_display(report)
  if type(report) ~= "table" or not report.entity or not report.entity.valid then
    return false
  end

  local original_damage = tonumber(report.original_damage)
  local final_damage = tonumber(report.final_damage)
  local reduced_damage = tonumber(report.reduced_damage)
  if not original_damage or not final_damage or not reduced_damage or reduced_damage <= 0 then
    return false
  end

  if not state and ctx.ensure_storage then ctx.ensure_storage() end
  if not state then return false end

  local key = entity_utils.damage_key(report.entity)
  local current_tick = game.tick
  local report_tick = tonumber(report.tick) or current_tick
  if report_tick > current_tick or report_tick < current_tick - 600 then
    report_tick = current_tick
  end

  state.external_damage_reductions[key] = {
    tick = report_tick,
    source = report.source,
    original_damage = original_damage,
    final_damage = final_damage,
    reduced_damage = reduced_damage
  }

  if ctx.apply_external_damage_reduction_to_recent
      and ctx.apply_external_damage_reduction_to_recent(key, state.external_damage_reductions[key]) then
    state.external_damage_reductions[key] = nil
    return true
  end

  external_damage_reductions_pending = true
  if ctx.update_tick_handler then
    ctx.update_tick_handler()
  end
  return true
end

local function consume_external_damage_reduction(key, tick)
  local report = state.external_damage_reductions[key]
  if type(report) ~= "table" then
    return nil
  end

  if report.tick == tick then
    state.external_damage_reductions[key] = nil
    return report
  end

  if tick - (report.tick or 0) > 120 then
    state.external_damage_reductions[key] = nil
  end

  return nil
end

function damage_tracking.cleanup_external_damage_reductions(tick)
  if not external_damage_reductions_pending or tick % 60 ~= 0 then
    return
  end

  local edr = state.external_damage_reductions
  local has_external_damage_reductions = false
  for key, report in pairs(edr) do
    if type(report) ~= "table" or tick - (report.tick or 0) > 120 then
      edr[key] = nil
    else
      has_external_damage_reductions = true
    end
  end
  external_damage_reductions_pending = has_external_damage_reductions
end

function damage_tracking.sweep_first_damage_ticks(tick, max_age_ticks)
  if tick % 300 ~= 0 or not state.first_damage_tick_by_key then
    return
  end

  local cutoff = tick - max_age_ticks
  for key, fight in pairs(state.first_damage_tick_by_key) do
    if (fight.last or fight.first or 0) < cutoff then
      state.first_damage_tick_by_key[key] = nil
    end
  end
end

damage_tracking.add_recent_key = add_recent_key
damage_tracking.remove_recent_key = remove_recent_key
damage_tracking.clear_indicator_recent_keys = clear_indicator_recent_keys
damage_tracking.track_first_damage_tick = track_first_damage_tick
damage_tracking.record_damage_reduction_for_display = record_damage_reduction_for_display
damage_tracking.consume_external_damage_reduction = consume_external_damage_reduction

return damage_tracking
