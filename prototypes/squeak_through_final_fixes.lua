local master = settings.startup["the-cave-squeak-through"]
if not master or master.value ~= "enabled" then
  return
end

-- Avoid applying two independent Squeak Through implementations to the same
-- prototypes when a standalone edition is also installed.
if mods and (mods["squeak-through-2"] or mods["Squeak Through"]) then
  log("[The Cave] Integrated Squeak Through skipped because a standalone Squeak Through mod is active.")
  return
end

local constants = require("prototypes.squeak_through_constants")
local collision_mask_util = require("collision-mask-util")

local function enabled(setting_name)
  local setting = settings.startup[setting_name]
  return setting and setting.value == "enabled"
end

local function csv_set(setting_name)
  local result = {}
  local setting = settings.startup[setting_name]
  local value = setting and setting.value
  if type(value) ~= "string" then
    return result
  end

  for raw_entry in string.gmatch(value, "([^,]+)") do
    local entry = string.match(raw_entry, "^%s*(.-)%s*$")
    if entry and entry ~= "" then
      result[entry] = true
    end
  end

  return result
end

local function get_mask(prototype)
  if type(prototype) ~= "table" then
    return nil
  end

  local ok, mask = pcall(collision_mask_util.get_mask, prototype)
  if not ok or type(mask) ~= "table" or type(mask.layers) ~= "table" then
    return nil
  end

  return mask
end

local function masks_overlap(first, second)
  if not first or not second then
    return false
  end

  for layer, active in pairs(first.layers) do
    if active and second.layers[layer] then
      return true
    end
  end

  return false
end

local function has_flag(prototype, wanted_flag)
  if type(prototype.flags) ~= "table" then
    return false
  end

  for _, flag in pairs(prototype.flags) do
    if flag == wanted_flag then
      return true
    end
  end

  return false
end

local function point_xy(point)
  if type(point) ~= "table" then
    return nil, nil
  end
  return point.x or point[1], point.y or point[2]
end

local function pull_edge_towards_centre(value, edge_limit)
  local sign = value < 0 and -1 or 1
  local absolute = math.abs(value)
  local half_tile_base = math.floor(absolute * 2) / 2
  local edge = absolute - half_tile_base
  return sign * (half_tile_base + math.min(edge, edge_limit or 0.3))
end

local function trim_collision_box(prototype, edge_limit)
  local box = prototype.collision_box
  if type(box) ~= "table" then
    return
  end

  local left, top = point_xy(box[1])
  local right, bottom = point_xy(box[2])
  if not left or not top or not right or not bottom then
    return
  end

  local changed_box = {
    {
      pull_edge_towards_centre(left, edge_limit),
      pull_edge_towards_centre(top, edge_limit),
    },
    {
      pull_edge_towards_centre(right, edge_limit),
      pull_edge_towards_centre(bottom, edge_limit),
    },
  }

  if changed_box[1][1] ~= left
    or changed_box[1][2] ~= top
    or changed_box[2][1] ~= right
    or changed_box[2][2] ~= bottom
  then
    prototype.collision_box = changed_box
  end
end

local character_group = data.raw.character
local character = character_group and character_group.character
if not character and character_group then
  local _, first_character = next(character_group)
  character = first_character
end
if not character then
  return
end

local character_mask = get_mask(character)
if not character_mask then
  return
end

-- A tiny reduction prevents exact-boundary rounding from blocking a gap that
-- was intentionally opened by the entity collision-box trimming below.
if character.collision_box then
  local left, top = point_xy(character.collision_box[1])
  local right, bottom = point_xy(character.collision_box[2])
  if left and top and right and bottom then
    character.collision_box = {
      { math.min(0, left + 1 / 256), math.min(0, top + 1 / 256) },
      { math.max(0, right - 1 / 256), math.max(0, bottom - 1 / 256) },
    }
  end
end

local group_for_type = {}
for group_name, prototype_types in pairs(constants.groups) do
  for _, prototype_type in pairs(prototype_types) do
    group_for_type[prototype_type] = group_name
  end
end

local modify_group = {}
for group_name in pairs(constants.groups) do
  modify_group[group_name] = enabled("the-cave-squeak-through-modify-" .. group_name)
end

local blacklist_types = csv_set("the-cave-squeak-through-blacklist-types")
local blacklist_names = csv_set("the-cave-squeak-through-blacklist-names")
local remove_collision_enabled = enabled("the-cave-squeak-through-remove-collision")
local remove_types = csv_set("the-cave-squeak-through-remove-collision-types")
local remove_names = csv_set("the-cave-squeak-through-remove-collision-names")

local entities_by_name = {}
local previous_upgrades = {}

for _, prototype_group in pairs(data.raw) do
  if type(prototype_group) == "table" then
    for _, prototype in pairs(prototype_group) do
      if type(prototype) == "table"
        and type(prototype.name) == "string"
        and type(prototype.type) == "string"
        and prototype.collision_box
      then
        entities_by_name[prototype.name] = prototype
      end
    end
  end
end

for _, prototype in pairs(entities_by_name) do
  if type(prototype.next_upgrade) == "string" then
    local list = previous_upgrades[prototype.next_upgrade]
    if not list then
      list = {}
      previous_upgrades[prototype.next_upgrade] = list
    end
    list[#list + 1] = prototype
  end
end

local collision_removed = {}
local function remove_player_collision(prototype)
  if not prototype or collision_removed[prototype.name] then
    return
  end
  collision_removed[prototype.name] = true

  local mask = get_mask(prototype)
  if mask then
    local replacement = table.deepcopy(mask)
    for layer, active in pairs(character_mask.layers) do
      if active then
        replacement.layers[layer] = nil
      end
    end
    prototype.collision_mask = replacement
  end

  if type(prototype.next_upgrade) == "string" then
    remove_player_collision(entities_by_name[prototype.next_upgrade])
  end

  local downgrades = previous_upgrades[prototype.name]
  if downgrades then
    for _, downgrade in pairs(downgrades) do
      remove_player_collision(downgrade)
    end
  end
end

for _, prototype in pairs(entities_by_name) do
  local mask = get_mask(prototype)
  if mask and not mask.colliding_with_tiles_only and masks_overlap(mask, character_mask) then
    if remove_collision_enabled and (remove_names[prototype.name] or remove_types[prototype.type]) then
      remove_player_collision(prototype)
    elseif not blacklist_names[prototype.name] and not blacklist_types[prototype.type] then
      local group_name = group_for_type[prototype.type]
      if group_name
        and modify_group[group_name]
        and prototype.squeak_behaviour ~= false
        and (prototype.type == "tree" or not has_flag(prototype, "placeable-off-grid"))
      then
        trim_collision_box(prototype, constants.edge_limits[prototype.type])
      end
    end
  end
end

-- Compatibility with Realistic Reactors' invisible interface, which otherwise
-- can retain a player-blocking layer despite its visual reactor footprint.
local combinators = data.raw["constant-combinator"]
local reactor_interface = combinators and combinators["realistic-reactor-interface"]
if reactor_interface then
  remove_player_collision(reactor_interface)
end
