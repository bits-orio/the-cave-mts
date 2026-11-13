-- aoe_origins.lua
-- Dummiez 2026/05/01

local aoe_origins = {}

local EFFECT_ID_PREFIX = "damage-indicator-aoe-origin:"
local EFFECT_ID_PREFIX_LENGTH = #EFFECT_ID_PREFIX
local MAX_AGE_TICKS = 4
local DEFAULT_RADIUS = 8
local RADIUS_MARGIN = 1
-- Hard cap per surface to prevent unbounded growth from misbehaving mods that flood
-- script triggers. Drops oldest entries when exceeded.
local MAX_ORIGINS_PER_SURFACE = 64
-- Sanity clamp on the radius parsed from the effect_id. A misconfigured prototype could
-- otherwise produce an absurd radius_sq and match every entity on the surface.
local MAX_MATCH_RADIUS = 256

-- State lives in storage so it survives save/load and stays consistent across multiplayer
-- peers when a client joins mid-game. set_state() is called from control.lua's
-- ensure_storage / on_load to point us at the live storage table.
local state = nil
local last_prune_tick_by_surface = {}

function aoe_origins.set_state(new_state)
  state = new_state
  -- last_prune_tick_by_surface is a per-runtime cache; resetting it on state changes is
  -- harmless (we just prune again on next access).
  last_prune_tick_by_surface = {}
end

local function get_origins_table()
  if not state then
    return nil
  end
  local origins = state.aoe_origins_by_surface
  if not origins then
    origins = {}
    state.aoe_origins_by_surface = origins
  end
  return origins
end

local function prune_surface(surface_origins, tick)
  local write = 1
  local count = #surface_origins
  for read = 1, count do
    local origin = surface_origins[read]
    if tick - origin.tick <= MAX_AGE_TICKS then
      if write ~= read then
        surface_origins[write] = origin
      end
      write = write + 1
    end
  end
  for i = count, write, -1 do
    surface_origins[i] = nil
  end
end

local function prune_surface_once_per_tick(surface_index, surface_origins, tick)
  if last_prune_tick_by_surface[surface_index] == tick then
    return
  end
  prune_surface(surface_origins, tick)
  last_prune_tick_by_surface[surface_index] = tick
end

function aoe_origins.reset()
  if state then
    state.aoe_origins_by_surface = {}
  end
  last_prune_tick_by_surface = {}
end

function aoe_origins.record_script_trigger(event)
  local effect_id = event.effect_id
  if type(effect_id) ~= "string" or effect_id:sub(1, EFFECT_ID_PREFIX_LENGTH) ~= EFFECT_ID_PREFIX then
    return
  end

  local origins = get_origins_table()
  if not origins then
    return
  end

  local position = event.target_position or event.source_position
  if not position then
    return
  end

  local x = position.x or position[1]
  local y = position.y or position[2]
  if not x or not y then
    return
  end

  local surface_index = event.surface_index
  local surface_origins = origins[surface_index]
  if not surface_origins then
    surface_origins = {}
    origins[surface_index] = surface_origins
  else
    prune_surface_once_per_tick(surface_index, surface_origins, event.tick)
  end

  local radius = tonumber(effect_id:sub(EFFECT_ID_PREFIX_LENGTH + 1)) or DEFAULT_RADIUS
  local match_radius = radius + RADIUS_MARGIN
  if match_radius > MAX_MATCH_RADIUS then
    match_radius = MAX_MATCH_RADIUS
  end

  -- Drop oldest if we've hit the per-surface cap. Cheap because new entries are appended
  -- in tick order and prune already compacts in place.
  if #surface_origins >= MAX_ORIGINS_PER_SURFACE then
    -- Shift left by one slot.
    for i = 1, #surface_origins - 1 do
      surface_origins[i] = surface_origins[i + 1]
    end
    surface_origins[#surface_origins] = nil
  end

  surface_origins[#surface_origins + 1] = {
    tick = event.tick,
    x = x,
    y = y,
    radius_sq = match_radius * match_radius
  }
end

function aoe_origins.find_for_damage_event(event)
  local entity = event.entity
  if not entity or not entity.valid then
    return nil
  end

  local origins = get_origins_table()
  if not origins then
    return nil
  end

  local surface_index = entity.surface.index
  local surface_origins = origins[surface_index]
  if not surface_origins or #surface_origins == 0 then
    return nil
  end

  prune_surface_once_per_tick(surface_index, surface_origins, event.tick)

  local position = entity.position
  local best = nil
  local best_distance_sq = nil
  for i = #surface_origins, 1, -1 do
    local origin = surface_origins[i]
    local dx = position.x - origin.x
    local dy = position.y - origin.y
    local distance_sq = dx * dx + dy * dy
    if distance_sq <= origin.radius_sq
        and (not best_distance_sq or distance_sq < best_distance_sq) then
      best = origin
      best_distance_sq = distance_sq
    end
  end

  if best then
    return { x = best.x, y = best.y }
  end
  return nil
end

return aoe_origins
