local M = {}

local LOADER_NAMES = {
  ["the-cave-loader"] = true,
  ["the-cave-fast-loader"] = true,
  ["the-cave-express-loader"] = true,
  ["the-cave-turbo-loader"] = true
}

local BELT_TYPES = {
  ["transport-belt"] = true,
  ["underground-belt"] = true,
  splitter = true
}

local BELT_LIKE_TYPES = {
  "transport-belt", "splitter", "underground-belt", "loader-1x1", "loader"
}

local LOADER_TYPES = {"loader-1x1", "loader"}

local CONTAINER_LIKE_TYPES = {
  "container", "logistic-container", "infinity-container", "linked-container",
  "assembling-machine", "furnace", "lab", "rocket-silo", "reactor", "boiler",
  "mining-drill", "agricultural-tower", "cargo-landing-pad"
}

local function opposite(direction)
  if direction == defines.direction.north then return defines.direction.south end
  if direction == defines.direction.south then return defines.direction.north end
  if direction == defines.direction.east then return defines.direction.west end
  if direction == defines.direction.west then return defines.direction.east end
  return direction
end

local function adjacent_positions(entity)
  local position = entity.position
  local output = {x = position.x, y = position.y}
  local input = {x = position.x, y = position.y}
  if entity.direction == defines.direction.north then
    output.y = output.y - 1; input.y = input.y + 1
  elseif entity.direction == defines.direction.east then
    output.x = output.x + 1; input.x = input.x - 1
  elseif entity.direction == defines.direction.south then
    output.y = output.y + 1; input.y = input.y - 1
  elseif entity.direction == defines.direction.west then
    output.x = output.x - 1; input.x = input.x + 1
  end
  return output, input
end

local function find_at(entity, position, types)
  local found = entity.surface.find_entities_filtered {
    position = position,
    type = types,
    force = entity.force
  }
  for _, candidate in pairs(found) do
    if candidate.valid and candidate ~= entity then return candidate end
  end
  return nil
end

local function snap_loader(loader)
  if not (loader and loader.valid and LOADER_NAMES[loader.name]) then return end
  local output = adjacent_positions(loader)
  local container = find_at(loader, output, CONTAINER_LIKE_TYPES)
  if container and loader.loader_type == "output" then
    loader.direction = opposite(loader.direction)
    output = adjacent_positions(loader)
  end

  local belt = find_at(loader, output, BELT_LIKE_TYPES)
  if belt and belt.direction == opposite(loader.direction) then
    loader.loader_type = loader.loader_type == "input" and "output" or "input"
  end
end

local function snap_adjacent_loaders(entity)
  if not (entity and entity.valid) then return end
  local output, input = adjacent_positions(entity)
  for _, position in pairs({output, input}) do
    -- Query by entity type instead of by the complete loader-name list. The
    -- Turbo loader is only defined when Turbo Belts are available (normally
    -- with Space Age), and Factorio rejects find filters containing even one
    -- unavailable prototype name. snap_loader still limits the result to The
    -- Cave's own loaders through LOADER_NAMES.
    local found = entity.surface.find_entities_filtered {
      position = position,
      type = LOADER_TYPES,
      force = entity.force
    }
    for _, loader in pairs(found) do snap_loader(loader) end
  end
end

function M.on_built(event)
  local entity = event and (event.entity or event.created_entity)
  if not (entity and entity.valid) then return end
  if LOADER_NAMES[entity.name] then
    snap_loader(entity)
  elseif BELT_TYPES[entity.type] then
    snap_adjacent_loaders(entity)
  end
end

return M
