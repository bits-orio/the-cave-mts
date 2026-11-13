-- entity_utils.lua
-- Dummiez 2026/05/01

local settings_cache = require("scripts.damage_indicator.settings_cache")

local entities = {}

local math_abs = math.abs
local math_floor = math.floor
local string_format = string.format

entities.GROUP_POSITION_CAP = 100

function entities.damage_key(entity)
  if entity.unit_number then
    return entity.unit_number
  end

  local position = entity.position
  return string_format("p:%d:%d:%d", entity.surface.index, math_floor(position.x * 4), math_floor(position.y * 4))
end

local NON_GROUPABLE_ENTITY_TYPES = {
  character = true,
  corpse = true,
  fish = true,
  unit = true,
  ["unit-spawner"] = true,
  tree = true,
  car = true,
  ["spider-vehicle"] = true,
  locomotive = true,
  ["cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true
}

local function bounding_box_dimensions(box)
  if not box then
    return nil, nil
  end

  local left_top = box.left_top or box[1]
  local right_bottom = box.right_bottom or box[2]
  if not left_top or not right_bottom then
    return nil, nil
  end

  local left = left_top.x or left_top[1]
  local top = left_top.y or left_top[2]
  local right = right_bottom.x or right_bottom[1]
  local bottom = right_bottom.y or right_bottom[2]
  if not left or not top or not right or not bottom then
    return nil, nil
  end

  return math_abs(right - left), math_abs(bottom - top)
end

function entities.is_one_tile_groupable_building(entity)
  if not entity or not entity.valid or NON_GROUPABLE_ENTITY_TYPES[entity.type] then
    return false
  end

  if settings_cache.is_whitelist_entity_type(entity.type) then
    return true
  end

  local prototype = entity.prototype
  if entity.has_flag and not (entity.has_flag("placeable-player") or entity.has_flag("player-creation")) then
    return false
  end

  local width = entity.tile_width or (prototype and prototype.tile_width)
  local height = entity.tile_height or (prototype and prototype.tile_height)
  if width and height then
    return width <= 1 and height <= 1
  end

  width, height = bounding_box_dimensions(prototype and prototype.selection_box)
  if not width then
    width, height = bounding_box_dimensions(entity.selection_box or entity.bounding_box)
  end

  return width ~= nil and height ~= nil and width <= 1.01 and height <= 1.01
end

return entities
