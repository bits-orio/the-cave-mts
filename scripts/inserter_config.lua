-- The Cave Inserter Configuration
-- Fresh implementation designed for Factorio 2.0 and The Cave's research path.
-- The module intentionally does not scan, reset or migrate placed inserters.

local M = {}

local GUI_NAME = "inserter_config"
local FEATURE_TAG = "the-cave-inserter-config"
local TECH_PREFIX = "the-cave-inserter-configuration-"
local MAX_RESEARCH_LEVEL = 4
local DROP_OFFSET_RESEARCH_LEVEL = 1
local OFFSET_STEP = 0.2
local OFFSET_EPSILON = 0.05
local MAX_GUI_RANGE = 4

local function xy(position)
  if not position then return { x = 0, y = 0 } end
  return {
    x = position.x or position[1] or 0,
    y = position.y or position[2] or 0,
  }
end

local function same_position(a, b)
  a = xy(a)
  b = xy(b)
  return a.x == b.x and a.y == b.y
end

local function round_nearest(value)
  if value >= 0 then
    return math.floor(value + 0.5)
  end
  return math.ceil(value - 0.5)
end

local function tile_range(position)
  position = xy(position)
  return math.max(math.abs(position.x), math.abs(position.y))
end

local function quantize_offset_component(value)
  if value > OFFSET_EPSILON then return OFFSET_STEP end
  if value < -OFFSET_EPSILON then return -OFFSET_STEP end
  return 0
end

local function quantize_offset(offset)
  offset = xy(offset)
  return {
    x = quantize_offset_component(offset.x),
    y = quantize_offset_component(offset.y),
  }
end

local function get_prototype(entity)
  if not (entity and entity.valid) then return nil end
  if entity.type == "entity-ghost" then
    return entity.ghost_prototype
  end
  return entity.prototype
end

local function is_inserter(entity)
  return entity
    and entity.valid
    and entity.object_name == "LuaEntity"
    and (entity.type == "inserter" or (entity.type == "entity-ghost" and entity.ghost_type == "inserter"))
end

local function is_configurable(entity)
  if not is_inserter(entity) then return false end
  local prototype = get_prototype(entity)
  return prototype and prototype.allow_custom_vectors == true
end

local function player_can_use_entity(player, entity)
  if not (player and player.valid and is_configurable(entity)) then return false end
  -- Editor/god controllers can legitimately open entities without a character.
  if player.character and not player.can_reach_entity(entity) then return false end
  return true
end

-- Some modded "slim" inserters are centred on a tile edge rather than a tile.
-- Convert them to the same integer-grid model used by ordinary 1x1 inserters.
local function slim_offset(entity, is_drop)
  local result = { x = 0, y = 0 }
  local prototype = get_prototype(entity)
  if not prototype then return result end

  if prototype.tile_height == 0 and prototype.tile_width == 1 then
    local shift = is_drop and 0.5 or -0.5
    if entity.direction == defines.direction.north then
      result.y = shift
    elseif entity.direction == defines.direction.south then
      result.y = -shift
    elseif entity.direction == defines.direction.east then
      result.x = -shift
    elseif entity.direction == defines.direction.west then
      result.x = shift
    end
  end

  return result
end

local function read_pickup_tile(entity)
  local offset = slim_offset(entity, false)
  return {
    x = round_nearest(entity.pickup_position.x - entity.position.x + offset.x),
    y = round_nearest(entity.pickup_position.y - entity.position.y + offset.y),
  }
end

local function read_drop(entity)
  local offset = slim_offset(entity, true)
  local relative = {
    x = entity.drop_position.x - entity.position.x + offset.x,
    y = entity.drop_position.y - entity.position.y + offset.y,
  }
  local tile = {
    x = round_nearest(relative.x),
    y = round_nearest(relative.y),
  }
  return tile, quantize_offset({ x = relative.x - tile.x, y = relative.y - tile.y })
end

local function write_pickup_tile(entity, tile)
  tile = xy(tile)
  local offset = slim_offset(entity, false)
  entity.pickup_position = {
    x = entity.position.x + tile.x - offset.x,
    y = entity.position.y + tile.y - offset.y,
  }
end

local function write_drop(entity, tile, drop_offset)
  tile = xy(tile)
  drop_offset = quantize_offset(drop_offset)
  local offset = slim_offset(entity, true)
  entity.drop_position = {
    x = entity.position.x + tile.x + drop_offset.x - offset.x,
    y = entity.position.y + tile.y + drop_offset.y - offset.y,
  }
end

local function refresh_entity(entity)
  entity.direction = entity.direction
end

local function rotate_cardinal(position, direction)
  position = xy(position)
  local turns = math.floor(((direction or 0) % 16) / 4) % 4
  if turns == 1 then
    return { x = -position.y, y = position.x }
  elseif turns == 2 then
    return { x = -position.x, y = -position.y }
  elseif turns == 3 then
    return { x = position.y, y = -position.x }
  end
  return { x = position.x, y = position.y }
end

local function get_native_tiles(entity)
  local prototype = get_prototype(entity)
  if not (prototype and prototype.inserter_pickup_position and prototype.inserter_drop_position) then
    local pickup = read_pickup_tile(entity)
    local drop = read_drop(entity)
    return pickup, drop
  end

  local pickup = rotate_cardinal(prototype.inserter_pickup_position, entity.direction)
  local drop = rotate_cardinal(prototype.inserter_drop_position, entity.direction)
  local pickup_slim = slim_offset(entity, false)
  local drop_slim = slim_offset(entity, true)

  return {
    x = round_nearest(pickup.x + pickup_slim.x),
    y = round_nearest(pickup.y + pickup_slim.y),
  }, {
    x = round_nearest(drop.x + drop_slim.x),
    y = round_nearest(drop.y + drop_slim.y),
  }
end

local function get_research_level(force)
  if not (force and force.valid and force.technologies) then return 0 end
  for level = MAX_RESEARCH_LEVEL, 1, -1 do
    local technology = force.technologies[TECH_PREFIX .. tostring(level)]
    if technology and technology.researched then return level end
  end
  return 0
end

local function get_grid_range(entity)
  local pickup = read_pickup_tile(entity)
  local drop = read_drop(entity)
  local native_pickup, native_drop = get_native_tiles(entity)
  local range = math.max(2, tile_range(pickup), tile_range(drop), tile_range(native_pickup), tile_range(native_drop))
  return math.min(range, MAX_GUI_RANGE)
end

local function required_level_for_position(entity, position, action, native_pickup, native_drop)
  position = xy(position)
  if position.x == 0 and position.y == 0 then return nil end

  if native_pickup == nil or native_drop == nil then
    native_pickup, native_drop = get_native_tiles(entity)
  end

  if (action == "pickup" and same_position(position, native_pickup))
    or (action == "drop" and same_position(position, native_drop)) then
    return 0
  end

  local range = tile_range(position)
  local minor = math.min(math.abs(position.x), math.abs(position.y))
  if range == 0 or range > get_grid_range(entity) then return nil end
  if range == 1 then return 0 end
  if range == 2 and minor == 0 then return 1 end
  if range == 2 and minor == 2 then return 2 end
  if range == 2 and minor == 1 then return 3 end
  if range > 2 then return 3 end
  return nil
end

local function position_is_allowed(entity, position, level, action)
  local native_pickup, native_drop = get_native_tiles(entity)
  local required = required_level_for_position(entity, position, action, native_pickup, native_drop)
  return required ~= nil and required <= (level or get_research_level(entity.force))
end

local function direction_from_vector(vector)
  vector = xy(vector)
  return math.floor(math.atan2(vector.x, -vector.y) * (4 / math.pi) + 0.5) % 8
end

local function rotate_tile_90(position, clockwise)
  position = xy(position)
  if clockwise then
    return { x = -position.y, y = position.x }
  end
  return { x = position.y, y = -position.x }
end

local function rotate_offset_steps(offset, steps)
  offset = xy(offset)
  local angle = (steps % 8) * (math.pi / 4)
  local cosine = math.cos(angle)
  local sine = math.sin(angle)
  return quantize_offset({
    x = offset.x * cosine - offset.y * sine,
    y = offset.x * sine + offset.y * cosine,
  })
end

local function rotate_offset_between(old_tile, new_tile, offset)
  local old_direction = direction_from_vector(old_tile)
  local new_direction = direction_from_vector(new_tile)
  return rotate_offset_steps(offset, (new_direction - old_direction) % 8)
end

local function destroy_gui(player)
  if not (player and player.valid) then return end
  local relative = player.gui and player.gui.relative
  local frame = relative and relative[GUI_NAME]
  if frame and frame.valid then frame.destroy() end
end

local function destroy_all_guis()
  if not game then return end
  for _, player in pairs(game.players) do
    destroy_gui(player)
  end
end

local function entity_sprite(entity)
  local prototype = get_prototype(entity)
  if not prototype then return "item/inserter" end
  local items = prototype.items_to_place_this
  if items and items[1] and items[1].name then
    return "item/" .. items[1].name
  end
  return "entity/" .. prototype.name
end

local function add_position_grid(parent, entity, action, range, current, level, native_pickup, native_drop)
  local grid = parent.add({
    type = "table",
    name = "the_cave_inserter_" .. action .. "_grid",
    column_count = 1 + range * 2,
  })
  grid.style.horizontal_spacing = 1
  grid.style.vertical_spacing = 1

  local active_sprite = action == "pickup"
    and "the-cave-inserter-config-pickup"
    or "the-cave-inserter-config-drop"

  for y = -range, range do
    for x = -range, range do
      if x == 0 and y == 0 then
        local centre = grid.add({
          type = "sprite-button",
          name = "the_cave_inserter_centre_" .. action,
          style = "slot_sized_button",
          sprite = entity_sprite(entity),
          enabled = false,
          tooltip = get_prototype(entity).localised_name,
        })
        centre.style.size = { 32, 32 }
      else
        local required = required_level_for_position(entity, { x = x, y = y }, action, native_pickup, native_drop)
        local unlocked = required ~= nil and required <= level
        local button = grid.add({
          type = "sprite-button",
          name = "the_cave_inserter_" .. action .. "_" .. tostring(x + range + 1) .. "_" .. tostring(y + range + 1),
          style = "slot_sized_button",
          sprite = same_position(current, { x = x, y = y }) and active_sprite or nil,
          enabled = unlocked,
          tags = {
            feature = FEATURE_TAG,
            action = action,
            x = x,
            y = y,
          },
        })
        button.style.size = { 32, 32 }

        if unlocked then
          button.tooltip = action == "pickup"
            and { "gui-inserter-config.set-pickup", x, y }
            or { "gui-inserter-config.set-drop", x, y }
        elseif required then
          button.tooltip = { "gui-inserter-config.requires-research", required }
        else
          button.tooltip = { "gui-inserter-config.position-unavailable" }
        end
      end
    end
  end
end

local function add_offset_grid(parent, current_offset, level)
  local grid = parent.add({
    type = "table",
    name = "the_cave_inserter_offset_grid",
    column_count = 3,
  })
  grid.style.horizontal_spacing = 1
  grid.style.vertical_spacing = 1

  for y = -1, 1 do
    for x = -1, 1 do
      local active = same_position(current_offset, { x = x * OFFSET_STEP, y = y * OFFSET_STEP })
      local button = grid.add({
        type = "sprite-button",
        name = "the_cave_inserter_offset_" .. tostring(x + 2) .. "_" .. tostring(y + 2),
        style = "slot_sized_button",
        sprite = active and "the-cave-inserter-config-drop" or nil,
        enabled = level >= DROP_OFFSET_RESEARCH_LEVEL,
        tags = {
          feature = FEATURE_TAG,
          action = "offset",
          x = x,
          y = y,
        },
        tooltip = level >= DROP_OFFSET_RESEARCH_LEVEL
          and { "gui-inserter-config.set-offset", x, y }
          or { "gui-inserter-config.requires-research", DROP_OFFSET_RESEARCH_LEVEL },
      })
      button.style.size = { 32, 32 }
    end
  end
end

local function create_gui(player, entity)
  destroy_gui(player)
  if not player_can_use_entity(player, entity) then return end

  local pickup = read_pickup_tile(entity)
  local drop, drop_offset = read_drop(entity)
  local native_pickup, native_drop = get_native_tiles(entity)
  local level = get_research_level(entity.force)
  local range = get_grid_range(entity)
  local prototype = get_prototype(entity)

  local root = player.gui.relative.add({
    type = "frame",
    name = GUI_NAME,
    caption = { "", { "gui-inserter-config.configuration" }, " — ", prototype.localised_name },
    anchor = {
      gui = defines.relative_gui_type.inserter_gui,
      position = defines.relative_gui_position.right,
    },
    tags = { feature = FEATURE_TAG },
  })

  root.style.horizontally_stretchable = false
  root.style.vertically_stretchable = false

  local content = root.add({ type = "frame", name = "frame_content", style = "entity_frame" })
  content.style.horizontally_stretchable = false

  local flow = content.add({ type = "flow", name = "flow_content", direction = "vertical" })
  flow.style.horizontally_stretchable = false

  local current_positions = flow.add({
    type = "label",
    name = "current_positions",
    caption = {
      "",
      { "gui-inserter-config.current" },
      "  ",
      { "gui-inserter-config.pickup" },
      ": [", tostring(pickup.x), ", ", tostring(pickup.y), "]   ",
      { "gui-inserter-config.drop" },
      ": [", tostring(drop.x), ", ", tostring(drop.y), "]",
    },
  })
  current_positions.style.horizontally_stretchable = false

  -- Keep each section only as wide as its actual grid. The previous two-column
  -- table stretched both frames to the full width of the longest label below,
  -- leaving large empty grey areas around the buttons.
  local main = flow.add({ type = "flow", name = "position_tables", direction = "horizontal" })
  main.style.horizontal_spacing = 8
  main.style.horizontally_stretchable = false

  local pickup_section = main.add({ type = "flow", name = "pickup_section", direction = "vertical" })
  pickup_section.style.horizontally_stretchable = false
  pickup_section.add({ type = "label", caption = { "gui-inserter-config.pickup" }, style = "heading_2_label" })
  local pickup_frame = pickup_section.add({ type = "frame", name = "pickup_frame", style = "inside_shallow_frame_with_padding" })
  pickup_frame.style.horizontally_stretchable = false
  add_position_grid(pickup_frame, entity, "pickup", range, pickup, level, native_pickup, native_drop)

  local drop_section = main.add({ type = "flow", name = "drop_section", direction = "vertical" })
  drop_section.style.horizontally_stretchable = false
  drop_section.add({ type = "label", caption = { "gui-inserter-config.drop" }, style = "heading_2_label" })
  local drop_frame = drop_section.add({ type = "frame", name = "drop_frame", style = "inside_shallow_frame_with_padding" })
  drop_frame.style.horizontally_stretchable = false
  add_position_grid(drop_frame, entity, "drop", range, drop, level, native_pickup, native_drop)

  local line = flow.add({ type = "line", name = "offset_line", style = "inside_shallow_frame_with_padding_line" })
  line.style.top_margin = 8
  line.style.width = math.max(360, 72 * (1 + range * 2))

  flow.add({ type = "label", caption = { "gui-inserter-config.drop-offset" }, style = "heading_2_label" })
  local offset_row = flow.add({ type = "flow", name = "offset_row", direction = "horizontal" })
  offset_row.style.horizontally_stretchable = false
  local offset_frame = offset_row.add({ type = "frame", name = "offset_frame", style = "inside_shallow_frame_with_padding" })
  offset_frame.style.horizontally_stretchable = false
  add_offset_grid(offset_frame, drop_offset, level)

  local instructions = flow.add({
    type = "label",
    name = "instructions",
    caption = { "gui-inserter-config.instructions" },
  })
  instructions.style.single_line = false
  instructions.style.maximal_width = math.max(360, 72 * (1 + range * 2))
end

local function refresh_open_for_entity(entity)
  if not (entity and entity.valid) then return end
  for _, player in pairs(game.players) do
    if player.opened == entity then
      create_gui(player, entity)
    end
  end
end

local function refresh_open_for_force(force)
  if not (force and force.valid) then return end
  for _, player in pairs(force.players) do
    if is_configurable(player.opened) then
      create_gui(player, player.opened)
    end
  end
end

local function apply_pickup(entity, new_tile)
  local old_pickup = read_pickup_tile(entity)
  local old_drop, old_offset = read_drop(entity)
  if same_position(old_pickup, new_tile) then return false end

  if same_position(old_drop, new_tile) then
    write_pickup_tile(entity, old_drop)
    write_drop(entity, old_pickup, rotate_offset_between(old_drop, old_pickup, old_offset))
  else
    write_pickup_tile(entity, new_tile)
  end
  refresh_entity(entity)
  return true
end

local function apply_drop(entity, new_tile)
  local old_pickup = read_pickup_tile(entity)
  local old_drop, old_offset = read_drop(entity)
  if same_position(old_drop, new_tile) then return false end

  local new_offset = rotate_offset_between(old_drop, new_tile, old_offset)
  if same_position(old_pickup, new_tile) then
    write_pickup_tile(entity, old_drop)
    write_drop(entity, old_pickup, new_offset)
  else
    write_drop(entity, new_tile, new_offset)
  end
  refresh_entity(entity)
  return true
end

local function selected_inserter(player)
  local entity = player and player.selected
  if player_can_use_entity(player, entity) then return entity end
  return nil
end

function M.on_init()
  destroy_all_guis()
end

function M.on_configuration_changed()
  -- Replace any persisted GUI from 2.5.11 or earlier. Existing inserter vectors
  -- are deliberately preserved exactly as they are.
  destroy_all_guis()
end

function M.on_player_created(event)
  local player = event and event.player_index and game.get_player(event.player_index)
  destroy_gui(player)
end

function M.on_gui_opened(event)
  local player = event and event.player_index and game.get_player(event.player_index)
  if not player then return end
  if event.entity and player_can_use_entity(player, event.entity) then
    create_gui(player, event.entity)
  else
    destroy_gui(player)
  end
end

function M.on_gui_closed(event)
  local player = event and event.player_index and game.get_player(event.player_index)
  if not player then return end
  if (event.entity and is_inserter(event.entity))
    or (event.element and event.element.valid and event.element.name == GUI_NAME) then
    destroy_gui(player)
  end
end

function M.on_gui_click(event)
  if not (event and event.element and event.element.valid) then return end
  local tags = event.element.tags
  if not tags or tags.feature ~= FEATURE_TAG then return end

  local player = game.get_player(event.player_index)
  local entity = player and player.opened
  if not player_can_use_entity(player, entity) then
    destroy_gui(player)
    return
  end

  local action = tags.action
  local changed = false
  if action == "pickup" or action == "drop" then
    local new_tile = { x = tonumber(tags.x), y = tonumber(tags.y) }
    local level = get_research_level(entity.force)
    if not position_is_allowed(entity, new_tile, level, action) then return end
    changed = action == "pickup" and apply_pickup(entity, new_tile) or apply_drop(entity, new_tile)
  elseif action == "offset" then
    if get_research_level(entity.force) < DROP_OFFSET_RESEARCH_LEVEL then return end
    local drop = read_drop(entity)
    local new_offset = {
      x = tonumber(tags.x) * OFFSET_STEP,
      y = tonumber(tags.y) * OFFSET_STEP,
    }
    write_drop(entity, drop, new_offset)
    refresh_entity(entity)
    changed = true
  end

  if changed then refresh_open_for_entity(entity) end
end

function M.on_player_rotated_entity(event)
  if event and is_configurable(event.entity) then
    refresh_open_for_entity(event.entity)
  end
end

function M.on_entity_settings_pasted(event)
  -- Factorio copies the inserter vectors itself. Do not force the destination
  -- direction or rewrite either vector; only redraw a GUI that is currently open.
  if event and is_configurable(event.destination) then
    refresh_open_for_entity(event.destination)
  end
end

function M.on_research_finished(event)
  if event and event.research and event.research.name:find(TECH_PREFIX, 1, true) == 1 then
    refresh_open_for_force(event.research.force)
  end
end

function M.on_research_reversed(event)
  if event and event.research and event.research.name:find(TECH_PREFIX, 1, true) == 1 then
    -- Reversing research only locks future selections. Existing inserters are
    -- never reset, which keeps blueprints and multiplayer builds safe.
    refresh_open_for_force(event.research.force)
  end
end

function M.on_rotation_adjust(event)
  local player = event and event.player_index and game.get_player(event.player_index)
  local entity = selected_inserter(player)
  if not entity then return end

  local input = event.input_name or ""
  local target_drop = input:find("drop", 1, true) ~= nil
  local clockwise = input:find("reverse", 1, true) == nil
  local level = get_research_level(entity.force)
  local current = target_drop and read_drop(entity) or read_pickup_tile(entity)
  local other = target_drop and read_pickup_tile(entity) or read_drop(entity)
  local candidate = current

  for _ = 1, 4 do
    candidate = rotate_tile_90(candidate, clockwise)
    if not same_position(candidate, other) and position_is_allowed(entity, candidate, level, target_drop and "drop" or "pickup") then
      local changed = target_drop and apply_drop(entity, candidate) or apply_pickup(entity, candidate)
      if changed then refresh_open_for_entity(entity) end
      return
    end
  end
end

local function distance_candidates(entity, current, other, level, action)
  local candidates = {}
  local direction = direction_from_vector(current)
  local range = get_grid_range(entity)
  for y = -range, range do
    for x = -range, range do
      local position = { x = x, y = y }
      if (x ~= 0 or y ~= 0)
        and direction_from_vector(position) == direction
        and not same_position(position, other)
        and position_is_allowed(entity, position, level, action) then
        candidates[#candidates + 1] = position
      end
    end
  end
  table.sort(candidates, function(a, b)
    local ar, br = tile_range(a), tile_range(b)
    if ar ~= br then return ar < br end
    local am, bm = math.abs(a.x) + math.abs(a.y), math.abs(b.x) + math.abs(b.y)
    if am ~= bm then return am < bm end
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  return candidates
end

function M.on_distance_adjust(event)
  local player = event and event.player_index and game.get_player(event.player_index)
  local entity = selected_inserter(player)
  if not entity then return end

  local target_drop = (event.input_name or ""):find("drop", 1, true) ~= nil
  local current = target_drop and read_drop(entity) or read_pickup_tile(entity)
  local other = target_drop and read_pickup_tile(entity) or read_drop(entity)
  local level = get_research_level(entity.force)
  local candidates = distance_candidates(entity, current, other, level, target_drop and "drop" or "pickup")
  if #candidates == 0 then return end

  local current_index = 0
  for index, candidate in ipairs(candidates) do
    if same_position(candidate, current) then
      current_index = index
      break
    end
  end
  local candidate = candidates[(current_index % #candidates) + 1]
  local changed = target_drop and apply_drop(entity, candidate) or apply_pickup(entity, candidate)
  if changed then refresh_open_for_entity(entity) end
end

function M.on_offset_adjust(event)
  local player = event and event.player_index and game.get_player(event.player_index)
  local entity = selected_inserter(player)
  if not entity or get_research_level(entity.force) < DROP_OFFSET_RESEARCH_LEVEL then return end

  local drop, offset = read_drop(entity)
  local lateral = (event.input_name or ""):find("lateral", 1, true) ~= nil
  local distance_axis
  if math.abs(drop.x) > math.abs(drop.y) then
    distance_axis = "x"
  else
    distance_axis = "y"
  end
  local axis = lateral and (distance_axis == "x" and "y" or "x") or distance_axis
  local value = round_nearest(offset[axis] / OFFSET_STEP)
  value = ((value + 2) % 3) - 1
  offset[axis] = value * OFFSET_STEP
  write_drop(entity, drop, offset)
  refresh_entity(entity)
  refresh_open_for_entity(entity)
end

return M
