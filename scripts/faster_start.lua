local settings = require("scripts.game_settings").proxy(settings)

local M = {}

local ARMOR = "simple-modular-armor"
local ROBOT = "fission-construction-robot"
local ENABLE_SETTING = "the-cave-faster-start"

local function enabled()
  local setting = settings and settings.startup and settings.startup[ENABLE_SETTING]
  return not setting or setting.value == "enabled" or setting.value == true
end

local function state()
  storage.the_cave_faster_start = storage.the_cave_faster_start or {given = {}}
  storage.the_cave_faster_start.given = storage.the_cave_faster_start.given or {}
  return storage.the_cave_faster_start
end

local function add_equipment(grid, name)
  if not (grid and prototypes.equipment[name]) then return end
  local equipment = grid.put{name = name}
  if equipment and equipment.valid then equipment.energy = equipment.max_energy end
end

local function insert(inventory, name, count)
  if not (inventory and inventory.valid and prototypes.item[name]) then return nil end
  local inserted = inventory.insert{name = name, count = count or 1}
  if inserted <= 0 then return nil end
  return inventory.find_item_stack(name)
end

function M.delivery_complete(player_index)
  return not enabled() or state().given[player_index] == true
end

function M.give_to_player(player, force)
  -- Reset evacuation may still clear inventories until every player returns.
  local reset = storage.the_cave_soft_reset
  if reset and reset.active then return false end
  if not enabled() then return false end
  if not (player and player.valid) then return false end

  local s = state()
  if s.given[player.index] and not force then return false end

  local character = player.cutscene_character or player.character
  if not (character and character.valid) then return false end

  local armor_inventory = character.get_inventory(defines.inventory.character_armor)
  local main_inventory = character.get_main_inventory()
  if not (armor_inventory and armor_inventory.valid
      and main_inventory and main_inventory.valid) then return false end

  -- Existing kit counts as already delivered; never duplicate it on join.
  if armor_inventory.get_item_count(ARMOR) > 0 or main_inventory.get_item_count(ARMOR) > 0
      or main_inventory.get_item_count(ROBOT) > 0 then
    s.given[player.index] = true
    return false
  end

  local armor
  if armor_inventory.is_empty() then
    armor = insert(armor_inventory, ARMOR, 1)
  else
    armor = insert(main_inventory, ARMOR, 1)
  end
  if not armor or not armor.valid_for_read or not armor.grid then return false end

  add_equipment(armor.grid, "simple-exoskeleton-equipment")
  add_equipment(armor.grid, "simple-fission-reactor-equipment")
  add_equipment(armor.grid, "personal-roboport-equipment")
  add_equipment(armor.grid, "battery-equipment")
  add_equipment(armor.grid, "battery-equipment")
  insert(main_inventory, ROBOT, 50)

  s.given[player.index] = true
  return true
end

function M.on_init()
  state()
end

function M.on_configuration_changed()
  local s = state()
  -- Old standalone FasterStart stored LuaPlayer references. The integrated
  -- implementation intentionally uses stable player indexes instead.
  if type(s.given) ~= "table" then s.given = {} end
end

function M.on_player_created(event)
  if event and event.player_index then
    M.give_to_player(game.get_player(event.player_index), false)
  end
end

function M.on_player_joined_game(event)
  if event and event.player_index then
    M.give_to_player(game.get_player(event.player_index), false)
  end
end

function M.command(event)
  local player = event.player_index and game.get_player(event.player_index)
  if not player then return end
  local given = M.give_to_player(player, false)
  if given then
    player.print({"the-cave-faster-start.kit-given"})
  else
    player.print({"the-cave-faster-start.kit-not-given"})
  end
end

return M
