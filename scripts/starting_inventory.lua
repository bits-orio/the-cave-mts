-- Retry only undelivered starting kits. This queue survives save/load and is
-- wiped with the rest of The Cave state at the start of each fresh round.
local faster_start = require("scripts.faster_start")
local starter_pack = require("scripts.starter_pack")

local M = {}
local RETRY_TICKS = 30

local function reset_active()
  local reset = storage.the_cave_soft_reset
  return reset and reset.active
end

local function complete(player_index)
  return faster_start.delivery_complete(player_index)
    and starter_pack.delivery_complete(player_index)
end

local function try_delivery(player_index, pending)
  local player = game.get_player(player_index)
  if not (player and player.valid) then
    pending[player_index] = nil
    return
  end
  if reset_active() then return end

  -- Equip the armor before filling the main inventory with the selected pack.
  -- Each module retains its own once-per-round delivery flag.
  faster_start.give_to_player(player, false)
  starter_pack.give_to_player(player)
  if complete(player_index) then pending[player_index] = nil end
end

function M.on_player_ready(event)
  local player_index = event and event.player_index
  if not player_index then return end
  local pending = storage.the_cave_starting_inventory_pending
  if complete(player_index) then
    if pending then pending[player_index] = nil end
    return
  end
  if not pending then
    pending = {}
    storage.the_cave_starting_inventory_pending = pending
  end
  pending[player_index] = true
  try_delivery(player_index, pending)
end

function M.on_configuration_changed()
  -- Repair an already affected save without resetting delivered-kit flags.
  for _, player in pairs(game.players) do
    M.on_player_ready { player_index = player.index }
  end
end

function M.on_tick(event)
  local pending = storage.the_cave_starting_inventory_pending
  if not pending or event.tick % RETRY_TICKS ~= 0 or reset_active() then return end
  for player_index in pairs(pending) do
    local player = game.get_player(player_index)
    if not (player and player.valid) then
      pending[player_index] = nil
    elseif player.connected then
      try_delivery(player_index, pending)
    end
  end
  if not next(pending) then storage.the_cave_starting_inventory_pending = nil end
end

function M.on_player_removed(event)
  local pending = storage.the_cave_starting_inventory_pending
  if pending and event then pending[event.player_index] = nil end
end

return M
