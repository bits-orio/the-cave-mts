-- Factorio 2.0 separates the remote controller from the physical controller.
-- Keep body position/surface paired; never use a camera to decide physical access.
local physical = {}
local travelling = {} -- Synchronous event guard only; no persistent save state.

local function valid(object)
    return object and object.valid
end

function physical.character_context(player)
    if not valid(player) then return nil, nil, nil end
    local character = player.character
    if not valid(character) or not valid(character.surface) then return nil, nil, nil end
    return character, character.surface, character.position
end

function physical.surface(player)
    if not valid(player) then return nil end
    local _, surface = physical.character_context(player)
    return surface or player.physical_surface
end

function physical.position(player)
    if not valid(player) then return nil end
    local _, _, position = physical.character_context(player)
    return position or player.physical_position
end

function physical.on_surface(player, surface)
    return valid(surface) and physical.surface(player) == surface
end

function physical.can_travel(player)
    return valid(player)
        and not travelling[player.index]
        and player.controller_type == defines.controllers.character
        and physical.character_context(player) ~= nil
end

function physical.can_use_entity(player, entity)
    return physical.can_travel(player) and valid(entity)
        and physical.on_surface(player, entity.surface)
        and player.can_reach_entity(entity)
end

function physical.find_position(player, surface, preferred, radius, precision)
    if not (valid(player) and valid(surface) and preferred) then return nil end
    local character = physical.character_context(player)
    return surface.find_non_colliding_position(character and character.name or "character",
        preferred, radius or 16, precision or 0.5)
end

-- Forced transfers must remain available while the player views another map.
-- Factorio 2.1 no longer exits remote view implicitly. Leave the camera before
-- teleporting, then verify the body before a caller commits or deletes a surface.
function physical.teleport(player, position, surface)
    if not (valid(player) and valid(surface) and position) or travelling[player.index] then return false end
    local index = player.index
    travelling[index] = true
    local ok, moved = pcall(function()
        if player.controller_type == defines.controllers.remote then
            player.exit_remote_view()
            if player.controller_type == defines.controllers.remote then return false end
        end
        return player.teleport(position, surface)
    end)
    travelling[index] = nil
    if not ok or moved ~= true or not physical.on_surface(player, surface) then return false end
    local actual = physical.position(player)
    if not actual then return false end
    local dx, dy = actual.x - (position.x or position[1]), actual.y - (position.y or position[2])
    return dx * dx + dy * dy <= 0.0625
end

-- A platform or rocket rider cannot leave remote view, so it cannot be teleported.
function physical.is_riding(player)
    if not valid(player) then return false end
    local surface = player.physical_surface
    return valid(surface) and surface.platform ~= nil or valid(player.cargo_pod) or false
end

-- A remote observer of a surface being removed must only have their view moved.
-- This must not teleport, kill, or empty the character on a different surface.
function physical.move_view_off_surface(player, source, destination, position)
    if not valid(player) or player.surface ~= source then return true end
    if player.controller_type ~= defines.controllers.remote
        or not valid(destination) or not position then return false end
    local ok = pcall(function()
        player.set_controller { type = defines.controllers.remote, surface = destination, position = position }
    end)
    return ok and player.surface ~= source
end

function physical.evacuate(player, source, destination, position)
    if physical.on_surface(player, source) and not physical.teleport(player, position, destination) then return false end
    return physical.move_view_off_surface(player, source, destination, position)
end

return physical
