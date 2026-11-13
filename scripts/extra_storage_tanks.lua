local M = {}
local TANK_NAME = "the-cave-storage-tank-3x4"
local TANK_FIXED_DIRECTION = defines.direction.south

local function force_tank_direction(entity)
  if not (entity and entity.valid and entity.name == TANK_NAME) then return end
  if entity.direction ~= TANK_FIXED_DIRECTION then
    entity.direction = TANK_FIXED_DIRECTION
  end
end

function M.on_built(event)
  local entity = (event and (event.entity or event.created_entity or event.destination))
  force_tank_direction(entity)
end

function M.on_player_rotated_entity(event)
  local entity = event and event.entity
  force_tank_direction(entity)
end

return M
