-- grouping.lua
-- Dummiez 2026/05/01

local grouping = {}

local settings_cache = require("scripts.damage_indicator.settings_cache")
local color_utils = require("scripts.damage_indicator.color_utils")
local damage_tracking = require("scripts.damage_indicator.damage_tracking")
local entity_utils = require("scripts.damage_indicator.entity_utils")

local STARTUP = settings_cache.STARTUP
local DEFAULT_COLOR = color_utils.DEFAULT_COLOR
local GROUP_POSITION_CAP = entity_utils.GROUP_POSITION_CAP

local math_min = math.min
local math_max = math.max
local math_floor = math.floor

local adjust_damage_color = color_utils.adjust_damage_color
local append_damage_color_blend = color_utils.append_damage_color_blend
local is_whitelist_groupable = settings_cache.is_whitelist_groupable

local state = nil
local ctx = {}
local group_member_cell_cache = {}

function grouping.init(context)
  ctx = context or {}
end

function grouping.set_state(new_state)
  state = new_state
end

function grouping.reset_cache()
  group_member_cell_cache = {}
end

local group_member_cell_index

local function group_member_distance_sq(indicator, position, max_distance, max_distance_sq)
  local member_positions = indicator.group_member_positions
  if not member_positions then
    local dx = position.x - (indicator.anchor_x or 0)
    local dy = position.y - (indicator.anchor_y or 0)
    return dx * dx + dy * dy
  end

  local min_x = indicator.group_min_x
  if min_x
      and (position.x < min_x - max_distance
        or position.x > indicator.group_max_x + max_distance
        or position.y < indicator.group_min_y - max_distance
        or position.y > indicator.group_max_y + max_distance) then
    return nil
  end

  local best_distance_sq = nil
  local cells = group_member_cell_index(indicator, max_distance)
  local cx = math_floor(position.x / max_distance)
  local cy = math_floor(position.y / max_distance)
  if cells then
    for nx = cx - 1, cx + 1 do
      local column = cells[nx]
      if column then
        for ny = cy - 1, cy + 1 do
          local bucket = column[ny]
          if bucket then
            for i = 1, #bucket do
              local member = bucket[i]
              local dx = position.x - member.x
              local dy = position.y - member.y
              local distance_sq = dx * dx + dy * dy
              if distance_sq <= max_distance_sq and (not best_distance_sq or distance_sq < best_distance_sq) then
                best_distance_sq = distance_sq
              end
            end
          end
        end
      end
    end
  end

  return best_distance_sq
end

local function group_distance_for_whitelist(is_whitelist_group)
  local distance = STARTUP.group_similar_distance
  if not distance or distance <= 0 then
    return nil, nil
  end

  if is_whitelist_group then
    distance = distance + (STARTUP.whitelist_distance_bonus or 0)
  end

  return distance, distance * distance
end

local function group_member_positions(indicator)
  local member_positions = indicator.group_member_positions
  if member_positions then
    return member_positions
  end

  if indicator.anchor_x and indicator.anchor_y then
    member_positions = { { x = indicator.anchor_x, y = indicator.anchor_y } }
    indicator.group_member_positions = member_positions
    indicator.group_min_x = indicator.anchor_x
    indicator.group_max_x = indicator.anchor_x
    indicator.group_min_y = indicator.anchor_y
    indicator.group_max_y = indicator.anchor_y
    return member_positions
  end

  return nil
end

local function invalidate_group_member_cell_index(indicator)
  group_member_cell_cache[indicator] = nil
end

local function recalculate_group_member_bounds(indicator)
  local member_positions = indicator.group_member_positions
  if not member_positions or #member_positions == 0 then
    indicator.group_min_x = indicator.anchor_x
    indicator.group_max_x = indicator.anchor_x
    indicator.group_min_y = indicator.anchor_y
    indicator.group_max_y = indicator.anchor_y
    return
  end

  local first = member_positions[1]
  local min_x = first.x
  local max_x = first.x
  local min_y = first.y
  local max_y = first.y
  for i = 2, #member_positions do
    local member = member_positions[i]
    min_x = math_min(min_x, member.x)
    max_x = math_max(max_x, member.x)
    min_y = math_min(min_y, member.y)
    max_y = math_max(max_y, member.y)
  end

  indicator.group_min_x = min_x
  indicator.group_max_x = max_x
  indicator.group_min_y = min_y
  indicator.group_max_y = max_y
end

local function append_group_member_position(indicator, position)
  local member_positions = indicator.group_member_positions
  if not member_positions then
    local anchor_x = indicator.anchor_x or position.x
    local anchor_y = indicator.anchor_y or position.y
    member_positions = { { x = anchor_x, y = anchor_y } }
    indicator.group_member_positions = member_positions
    indicator.group_min_x = anchor_x
    indicator.group_max_x = anchor_x
    indicator.group_min_y = anchor_y
    indicator.group_max_y = anchor_y
  end

  member_positions[#member_positions + 1] = { x = position.x, y = position.y }
  indicator.group_min_x = math_min(indicator.group_min_x or position.x, position.x)
  indicator.group_max_x = math_max(indicator.group_max_x or position.x, position.x)
  indicator.group_min_y = math_min(indicator.group_min_y or position.y, position.y)
  indicator.group_max_y = math_max(indicator.group_max_y or position.y, position.y)

  local count = #member_positions
  if count > GROUP_POSITION_CAP then
    -- Single shift instead of repeated table.remove(arr, 1) which would be O(n^2).
    local overflow = count - GROUP_POSITION_CAP
    for i = 1, GROUP_POSITION_CAP do
      member_positions[i] = member_positions[i + overflow]
    end
    for i = GROUP_POSITION_CAP + 1, count do
      member_positions[i] = nil
    end
    recalculate_group_member_bounds(indicator)
  end

  invalidate_group_member_cell_index(indicator)
end

local function group_anchor_position(indicator)
  local member_positions = indicator.group_member_positions
  local retained_count = member_positions and #member_positions or 0
  if retained_count > 0 then
    local sum_x = 0
    local sum_y = 0
    for i = 1, retained_count do
      local member = member_positions[i]
      sum_x = sum_x + member.x
      sum_y = sum_y + member.y
    end
    return sum_x / retained_count, sum_y / retained_count
  end

  local count = indicator.group_position_count or 1
  return (indicator.group_anchor_sum_x or indicator.anchor_x or 0) / count,
      (indicator.group_anchor_sum_y or indicator.anchor_y or 0) / count
end

group_member_cell_index = function(indicator, cell_size)
  local member_positions = group_member_positions(indicator)
  if not member_positions then
    return nil, 0
  end

  local cached = group_member_cell_cache[indicator]
  if cached and cached.cell_size == cell_size then
    return cached.cells, cached.cell_count
  end

  local cells = {}
  local cell_count = 0
  for i = 1, #member_positions do
    local member = member_positions[i]
    local cx = math_floor(member.x / cell_size)
    local cy = math_floor(member.y / cell_size)
    local column = cells[cx]
    if not column then
      column = {}
      cells[cx] = column
    end
    local bucket = column[cy]
    if not bucket then
      bucket = {}
      column[cy] = bucket
      cell_count = cell_count + 1
    end
    bucket[#bucket + 1] = member
  end

  group_member_cell_cache[indicator] = {
    cell_size = cell_size,
    cells = cells,
    cell_count = cell_count
  }
  return cells, cell_count
end

local function groups_are_chain_connected(left, right, max_distance, max_distance_sq)
  if left.group_min_x and right.group_min_x
      and (left.group_min_x > right.group_max_x + max_distance
        or left.group_max_x < right.group_min_x - max_distance
        or left.group_min_y > right.group_max_y + max_distance
        or left.group_max_y < right.group_min_y - max_distance) then
    return false
  end

  local cell_size = max_distance
  local left_cells, left_cell_count = group_member_cell_index(left, cell_size)
  local right_cells, right_cell_count = group_member_cell_index(right, cell_size)
  if not left_cells or not right_cells then
    return false
  end

  local scan_cells = left_cells
  local match_cells = right_cells
  if right_cell_count < left_cell_count then
    scan_cells = right_cells
    match_cells = left_cells
  end

  for cx, column in pairs(scan_cells) do
    for cy, bucket in pairs(column) do
      for nx = cx - 1, cx + 1 do
        local match_column = match_cells[nx]
        if match_column then
          for ny = cy - 1, cy + 1 do
            local match_bucket = match_column[ny]
            if match_bucket then
              for i = 1, #bucket do
                local left_member = bucket[i]
                for j = 1, #match_bucket do
                  local right_member = match_bucket[j]
                  local dx = left_member.x - right_member.x
                  local dy = left_member.y - right_member.y
                  if dx * dx + dy * dy <= max_distance_sq then
                    return true
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  return false
end

local function union_viewers(left, right)
  if not left then return right end
  if not right then return left end
  -- Common SP/small-group case: identical single-player sets.
  if #left == 1 and #right == 1 and left[1] == right[1] then
    return left
  end

  local result = {}
  local count = 0
  local seen = {}

  for i = 1, #left do
    local player_index = left[i]
    if not seen[player_index] then
      count = count + 1
      result[count] = player_index
      seen[player_index] = true
    end
  end

  for i = 1, #right do
    local player_index = right[i]
    if not seen[player_index] then
      count = count + 1
      result[count] = player_index
      seen[player_index] = true
    end
  end

  return result
end

local function remove_active_indicator_entry(indicator)
  local active = state.active
  for i = #active, 1, -1 do
    if active[i] == indicator then
      table.remove(active, i)
      return
    end
  end
end

local function merge_group_indicator(target, source, now)
  target.amount = target.amount + (source.amount or 0)
  target.reduced_amount = (target.reduced_amount or 0) + (source.reduced_amount or 0)
  target.last_hit_tick = math_max(target.last_hit_tick or now, source.last_hit_tick or now)
  target.viewers = union_viewers(target.viewers, source.viewers)
  target.user_scale = math_max(target.user_scale or 1, source.user_scale or 1)

  local source_keys = source.recent_keys
  if source_keys then
    for key in pairs(source_keys) do
      damage_tracking.add_recent_key(target, key)
    end
    source.recent_keys = nil
  elseif source.key then
    damage_tracking.add_recent_key(target, source.key)
  end

  local source_count = source.group_position_count or 1
  target.group_position_count = (target.group_position_count or 1) + source_count
  target.group_anchor_sum_x = (target.group_anchor_sum_x or target.anchor_x or 0) +
      (source.group_anchor_sum_x or source.anchor_x or 0)
  target.group_anchor_sum_y = (target.group_anchor_sum_y or target.anchor_y or 0) +
      (source.group_anchor_sum_y or source.anchor_y or 0)

  local target_members = group_member_positions(target)
  local source_members = group_member_positions(source)
  if target_members and source_members then
    for i = 1, #source_members do
      append_group_member_position(target, source_members[i])
    end
  end
  recalculate_group_member_bounds(target)

  -- Use the target's baked color_settings so the merge result respects the original
  -- (closest-at-creation) viewer's blend/mode preferences. Source and target should
  -- normally have compatible settings since they were spawned from the same closest
  -- viewer's perspective within the combine window, but defaulting to target's keeps
  -- the math consistent if they ever diverge.
  local color_settings = target.color_settings
  if color_settings and color_settings.blend_damage_type_colors and color_settings.color_mode == "damage-type" then
    local source_total = source.color_blend_total or source.amount or 0
    local source_base_color = source.base_type_color or source.color or DEFAULT_COLOR
    target.color_blend_total = (target.color_blend_total or target.amount or 0) + source_total
    target.color_blend_r = (target.color_blend_r or 0) + (source.color_blend_r or source_base_color.r * source_total)
    target.color_blend_g = (target.color_blend_g or 0) + (source.color_blend_g or source_base_color.g * source_total)
    target.color_blend_b = (target.color_blend_b or 0) + (source.color_blend_b or source_base_color.b * source_total)
    local total = target.color_blend_total
    if total > 0 then
      target.base_type_color = {
        r = target.color_blend_r / total,
        g = target.color_blend_g / total,
        b = target.color_blend_b / total
      }
    end
  end

  target.color = adjust_damage_color(target.base_type_color or target.color, target.amount, color_settings)
  target.pending_text_update = true

  local anchor_x, anchor_y = group_anchor_position(target)
  ctx.move_indicator_to_anchor(target, anchor_x, anchor_y)
  ctx.flush_indicator_text(target, now)

  ctx.destroy_indicator(source)
  remove_active_indicator_entry(source)
end

local function merge_connected_group_indicators(target, now)
  local max_distance, max_distance_sq = group_distance_for_whitelist(target.whitelist_groupable)
  if not max_distance or not max_distance_sq or max_distance_sq <= 0 then
    return
  end

  -- Single-pass merge: previously this restarted a full scan from the top of state.active
  -- after every successful merge, giving O(cluster_size * active_count) behavior. Since
  -- groups_are_chain_connected uses cell-index bounds that GROW as the target absorbs
  -- members, we may miss some candidates that only become reachable after an early merge
  -- expands the target's bounding box. We handle that with a single retry pass: collect
  -- everything reachable from the (possibly-expanded) target after the first sweep, and
  -- stop when a pass yields zero merges. In practice the second pass picks up the
  -- transitive-closure tail and the third pass is empty.
  local target_group_name = target.group_name or target.entity_name
  local target_surface_index = target.surface_index
  local target_whitelist_groupable = target.whitelist_groupable
  local combine_ticks = STARTUP.combine_ticks
  local active = state.active

  local merged_any
  repeat
    merged_any = false
    for i = #active, 1, -1 do
      local other = active[i]
      if other
          and other ~= target
          and other.groupable
          and not other.killing_blow
          and (other.group_name or other.entity_name) == target_group_name
          and other.surface_index == target_surface_index
          and other.whitelist_groupable == target_whitelist_groupable
          and other.last_hit_tick
          and now - other.last_hit_tick <= combine_ticks
          and groups_are_chain_connected(target, other, max_distance, max_distance_sq)
          and ctx.resolve_render_object(other.text_id) then
        merge_group_indicator(target, other, now)
        merged_any = true
        -- Don't break: continue scanning the rest of the array in this same pass.
        -- merge_group_indicator removes `other` from active via remove_active_indicator_entry,
        -- so the index `i` we're about to decrement still points to a valid (un-merged)
        -- entry or off the end of the array. Since we iterate downward, removal of entries
        -- at indices >= i doesn't shift the entries we haven't visited yet.
      end
    end
  until not merged_any
end

-- Saturation grouping: when there are more than STARTUP.saturation_threshold distinct
-- indicators of the same group identity within whitelist_distance_bonus of the new hit,
-- force-fold them into the closest one and return it. This bounds render-object count
-- in pathological cases (asteroid storms, biter waves, etc.) where the normal grouping
-- distance is too tight to catch everything. group_key is the normalized identity --
-- callers pass entity.group_name (resolved via settings_cache.resolve_normalized_name)
-- when a tier-normalize rule matched, otherwise raw entity.name.
local function find_saturation_group_target(group_key, surface_index, position, tick)
  local threshold = STARTUP.saturation_threshold
  if not threshold or threshold <= 0 then
    return nil
  end

  local max_distance = STARTUP.whitelist_distance_bonus
  if not max_distance or max_distance <= 0 then
    return nil
  end
  local max_distance_sq = max_distance * max_distance
  local combine_ticks = STARTUP.combine_ticks

  local active = state.active
  local matches = {}
  local match_count = 0
  local best_indicator = nil
  local best_distance_sq = max_distance_sq

  for i = 1, #active do
    local indicator = active[i]
    if indicator
        and not indicator.killing_blow
        and (indicator.group_name or indicator.entity_name) == group_key
        and indicator.surface_index == surface_index
        and indicator.anchor_x
        and indicator.anchor_y
        and indicator.last_hit_tick
        and tick - indicator.last_hit_tick <= combine_ticks then
      local dx = position.x - indicator.anchor_x
      local dy = position.y - indicator.anchor_y
      local distance_sq = dx * dx + dy * dy
      if distance_sq <= max_distance_sq then
        match_count = match_count + 1
        matches[match_count] = indicator
        if distance_sq < best_distance_sq then
          best_distance_sq = distance_sq
          best_indicator = indicator
        end
      end
    end
  end

  if match_count < threshold or not best_indicator then
    return nil
  end

  -- Eager-merge all the saturation matches into best_indicator so future hits
  -- piggyback on the consolidated indicator instead of compounding the count.
  -- Mark the target as groupable so subsequent merges and the append path treat
  -- it as a group; force_grouped distinguishes it from "naturally" groupable
  -- indicators if downstream logic ever needs to know.
  best_indicator.groupable = true
  best_indicator.force_grouped = true
  if not ctx.resolve_render_object(best_indicator.text_id) then
    return nil
  end

  for i = 1, match_count do
    local other = matches[i]
    if other ~= best_indicator and ctx.resolve_render_object(other.text_id) then
      other.groupable = true
      merge_group_indicator(best_indicator, other, tick)
    end
  end

  return best_indicator
end

local function find_nearby_group_indicator(entity, position, key, tick, entity_groupable)
  local entity_whitelist_groupable = is_whitelist_groupable(entity) or nil
  local max_distance, max_distance_sq = group_distance_for_whitelist(entity_whitelist_groupable)
  if not max_distance or not max_distance_sq or max_distance_sq <= 0 or not entity_groupable then
    return nil
  end

  local entity_name = entity.name
  local entity_group_name = settings_cache.resolve_normalized_name(entity_name) or entity_name
  local surface_index = entity.surface.index
  local combine_ticks = STARTUP.combine_ticks
  local active = state.active
  local best_indicator = nil
  local best_distance_sq = max_distance_sq

  for i = #active, 1, -1 do
    local indicator = active[i]
    if indicator
        and indicator.groupable
        and not indicator.killing_blow
        and (indicator.group_name or indicator.entity_name) == entity_group_name
        and indicator.surface_index == surface_index
        and indicator.whitelist_groupable == entity_whitelist_groupable
        and indicator.anchor_x
        and indicator.anchor_y
        and indicator.last_hit_tick
        and tick - indicator.last_hit_tick <= combine_ticks
        and (not indicator.recent_keys or not indicator.recent_keys[key]) then
      local distance_sq = group_member_distance_sq(indicator, position, max_distance, max_distance_sq)
      if distance_sq and distance_sq <= best_distance_sq and ctx.resolve_render_object(indicator.text_id) then
        best_indicator = indicator
        best_distance_sq = distance_sq
      end
    end
  end

  return best_indicator
end

-- killing_blow / aoe_origin are optional; when set, the appended hit promotes the
-- group indicator to KB state (tentative_killing_blow flow handles the deferred
-- visual lock-in). Default false preserves the old behavior for non-KB callers.
local function append_to_group_indicator(event, indicator, key, viewers, user_scale, color, amount, reduced_amount,
                                         aoe_origin, killing_blow, kb_aoe_origin)
  damage_tracking.add_recent_key(indicator, key)

  local position = event.entity.position
  local group_position_count = (indicator.group_position_count or 1) + 1
  local group_anchor_sum_x = (indicator.group_anchor_sum_x or indicator.anchor_x or position.x) + position.x
  local group_anchor_sum_y = (indicator.group_anchor_sum_y or indicator.anchor_y or position.y) + position.y
  indicator.group_position_count = group_position_count
  indicator.group_anchor_sum_x = group_anchor_sum_x
  indicator.group_anchor_sum_y = group_anchor_sum_y
  append_group_member_position(indicator, position)

  if not ctx.refresh_recent_indicator(event, indicator, viewers, user_scale, color, amount, reduced_amount, killing_blow or false, kb_aoe_origin or aoe_origin) then
    damage_tracking.clear_indicator_recent_keys(indicator)
    return false
  end

  local anchor_x, anchor_y = group_anchor_position(indicator)
  ctx.move_indicator_to_anchor(indicator, anchor_x, anchor_y)
  -- Don't trigger merge sweep on KB: the indicator is now in tentative-KB state and
  -- subsequent merges would mix in non-KB indicators which then inherit the KB visual
  -- on promotion -- which is fine for the same-type group, but we want the KB-promoted
  -- indicator to be the merge target (already is, since this IS the indicator we
  -- appended into). So just continue with the normal merge sweep.
  merge_connected_group_indicators(indicator, event.tick)
  return true
end

grouping.invalidate_group_member_cell_index = invalidate_group_member_cell_index
grouping.find_nearby_group_indicator = find_nearby_group_indicator
grouping.find_saturation_group_target = find_saturation_group_target
grouping.append_to_group_indicator = append_to_group_indicator
grouping.merge_connected_group_indicators = merge_connected_group_indicators

return grouping
