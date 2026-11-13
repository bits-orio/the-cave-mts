local settings = require("scripts.game_settings").proxy(settings)

local M = {}
local market_policy = require("scripts.market_policy")

local SETTING_NAME = "the-cave-starter-pack"
local COLLAPSE_WALL_COUNT = 2000

local LEVEL_INDEX = {
  small = 1,
  medium = 2,
  large = 3,
  lazy = 4,
}

-- Counts are ordered as: Small, Medium, Large, Lazy.
local ITEMS = {
  {name = "repair-pack", counts = {10, 20, 30, 50}},
  {name = "the-cave-big-wooden-pole", counts = {10, 20, 30, 50}},
  {name = "small-electric-pole", counts = {20, 40, 60, 100}},
  {name = "the-cave-portable-power-interface-mk5", counts = {2, 4, 6, 10}},
  {name = "recycler", counts = {1, 1, 1, 2}, space_age = true},
  {name = "burner-mining-drill", counts = {2, 4, 6, 10}},
  {name = "solid-fuel", counts = {40, 80, 120, 200}},
  {name = "wood", counts = {80, 160, 240, 400}},
  {name = "coin", counts = {200, 400, 600, 1000}},
  {name = "iron-plate", counts = {40, 80, 120, 200}},
  {name = "copper-plate", counts = {40, 80, 120, 200}},
  {name = "steel-plate", counts = {20, 40, 60, 100}},
  {name = "pipe", counts = {40, 80, 120, 200}},
  {name = "pipe-to-ground", counts = {10, 20, 30, 50}},
  {name = "boiler", counts = {1, 2, 3, 4}},
  {name = "steam-engine", counts = {2, 4, 6, 8}},
  {name = "burner-inserter", counts = {10, 20, 30, 50}},
  {name = "inserter", counts = {10, 20, 30, 50}},
  {name = "long-handed-inserter", counts = {10, 20, 30, 50}},
  {name = "fast-inserter", counts = {10, 20, 30, 50}},
  {name = "bulk-inserter", counts = {4, 8, 12, 20}},
  {name = "stone-brick", counts = {80, 160, 240, 400}},
  {name = "transport-belt", counts = {40, 80, 120, 200}},
  {name = "underground-belt", counts = {4, 8, 12, 20}},
  {name = "splitter", counts = {2, 4, 6, 10}},
  {name = "the-cave-loader", counts = {10, 10, 10, 10}},
  {name = "the-cave-tnt-box-large", counts = {10, 10, 10, 10}},
  {name = "rail", counts = {200, 200, 200, 200}},
  {name = "wooden-chest", counts = {4, 8, 12, 20}},
  {name = "iron-chest", counts = {4, 8, 12, 20}},
  {name = "steel-chest", counts = {4, 8, 12, 20}},
  {name = "gun-turret", counts = {2, 4, 6, 10}},
  {name = "firearm-magazine", counts = {80, 160, 240, 400}},
  {name = "speed-module", counts = {4, 8, 12, 20}},
  {name = "efficiency-module", counts = {10, 20, 30, 50}},
  {name = "productivity-module", counts = {8, 16, 24, 40}},
  {name = "quality-module", counts = {8, 16, 24, 40}, space_age = true},
  {name = "fast-transport-belt", counts = {20, 40, 60, 100}},
  {name = "fast-underground-belt", counts = {4, 8, 12, 20}},
  {name = "fast-splitter", counts = {2, 4, 6, 10}},
  {name = "medium-electric-pole", counts = {10, 20, 30, 50}},
  {name = "big-electric-pole", counts = {10, 20, 30, 50}},
  {name = "substation", counts = {2, 4, 6, 10}},
  {name = "solar-panel", counts = {10, 20, 30, 50}},
  {name = "accumulator", counts = {10, 20, 30, 50}},
  {name = "offshore-pump", counts = {1, 1, 2, 4}},
  {name = "stone-furnace", counts = {4, 8, 12, 20}},
  {name = "small-lamp", counts = {10, 20, 30, 50}},
  {name = "electric-mining-drill", counts = {1, 3, 6, 10}},
  {name = "assembling-machine-2", counts = {4, 8, 12, 20}},
  {name = "assembling-machine-3", counts = {3, 6, 9, 15}},
}

local function selected_package()
  local setting = settings and settings.startup and settings.startup[SETTING_NAME]
  local value = setting and setting.value or "medium"
  if value == "disabled" or LEVEL_INDEX[value] then return value end
  return "medium"
end

local function space_age_active()
  return script and script.active_mods and script.active_mods["space-age"] ~= nil
end

local function state()
  storage.the_cave_starter_pack = storage.the_cave_starter_pack or {given = {}, collapse_walls_given = {}}
  storage.the_cave_starter_pack.given = storage.the_cave_starter_pack.given or {}
  storage.the_cave_starter_pack.collapse_walls_given =
    storage.the_cave_starter_pack.collapse_walls_given or {}
  return storage.the_cave_starter_pack
end

local function collapses_enabled()
  local setting = settings and settings.startup and settings.startup["the-cave-collapse-mode"]
  return setting and setting.value == "enabled"
end

local function mark_existing_players_as_processed(s)
  if not game then return end
  for _, player in pairs(game.players) do
    s.given[player.index] = true
  end
end

local function spill_remainder(player, name, count)
    if count <= 0 then return end
    if not market_policy.starter_item_allowed(name) then return end
  local surface = player.surface
  local prototype = prototypes.item[name]
  if not (surface and surface.valid and prototype) then return end

  local stack_size = math.max(1, prototype.stack_size or 1)
  while count > 0 do
    local amount = math.min(count, stack_size)
    surface.spill_item_stack{
      position = player.position,
      stack = {name = name, count = amount},
      enable_looted = true,
      force = player.force,
    }
    count = count - amount
  end
end

local function give_collapse_walls(player, s, inventory)
  if not collapses_enabled() or s.collapse_walls_given[player.index] then return false end
  if not prototypes.item["stone-wall"] then return false end

  local inserted = inventory.insert{name = "stone-wall", count = COLLAPSE_WALL_COUNT}
  if inserted < COLLAPSE_WALL_COUNT then
    spill_remainder(player, "stone-wall", COLLAPSE_WALL_COUNT - inserted)
  end
  s.collapse_walls_given[player.index] = true
  return true
end

function M.delivery_complete(player_index)
  local s = state()
  local pack_done = selected_package() == "disabled" or s.given[player_index] == true
  local walls_done = not collapses_enabled() or s.collapse_walls_given[player_index] == true
    or not prototypes.item["stone-wall"]
  return pack_done and walls_done
end

function M.give_to_player(player)
  -- Reset evacuation may still clear inventories until every player returns.
  local reset = storage.the_cave_soft_reset
  if reset and reset.active then return false end
  if not (player and player.valid) then return false end

  local s = state()
  local pack_done = s.given[player.index] == true
  local walls_due = collapses_enabled() and not s.collapse_walls_given[player.index]
  if pack_done and not walls_due then return false end

  local character = player.cutscene_character or player.character
  if not (character and character.valid) then return false end
  local inventory = character.get_main_inventory()
  if not (inventory and inventory.valid) then return false end

  local changed = give_collapse_walls(player, s, inventory)
  if pack_done then return changed end

  local package = selected_package()
  if package == "disabled" then
    s.given[player.index] = true
    return changed
  end

  local level = LEVEL_INDEX[package]
  local has_space_age = space_age_active()

  for _, entry in ipairs(ITEMS) do
    if (not entry.space_age or has_space_age) and prototypes.item[entry.name]
        and market_policy.starter_item_allowed(entry.name) then
      local count = entry.counts[level]
      if count and count > 0 then
        local inserted = inventory.insert{name = entry.name, count = count}
        if inserted < count then
          spill_remainder(player, entry.name, count - inserted)
        end
      end
    end
  end

  s.given[player.index] = true
  return true
end

function M.on_init()
  local s = state()
  -- A mod added to an existing save must not hand a full starter package to
  -- every established player. install_guard sets this flag before this call.
  if storage.mid_save_install then
    mark_existing_players_as_processed(s)
  end
end

function M.on_configuration_changed()
  local existed = storage.the_cave_starter_pack ~= nil
  local s = state()
  -- First introduction of this feature into an existing The Cave save:
  -- preserve established players, while future new players still get a pack.
  if not existed then
    mark_existing_players_as_processed(s)
  end
  if collapses_enabled() and game then
    for _, player in pairs(game.players) do
      M.give_to_player(player)
    end
  end
end

function M.on_player_created(event)
  if event and event.player_index then
    M.give_to_player(game.get_player(event.player_index))
  end
end

function M.on_player_joined_game(event)
  if event and event.player_index then
    M.give_to_player(game.get_player(event.player_index))
  end
end

return M
