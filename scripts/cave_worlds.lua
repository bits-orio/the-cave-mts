-- Main cave worlds are originals or copies observed through engine events.
-- Keep this module a leaf: generation and lifecycle handlers depend on it.
local worlds = {}

local function surface_for(value)
    if type(value) == "number" or type(value) == "string" then
        return game and game.surfaces[value]
    end
    return value
end

local function rows()
    storage.cave_worlds = storage.cave_worlds or {}
    return storage.cave_worlds
end

function worlds.get(value)
    local surface = surface_for(value)
    if not (surface and surface.valid) then return nil end
    local row = storage.cave_worlds and storage.cave_worlds[surface.index]
    -- Deleted surface indices can be reused before all cleanup has run.
    if row and row.name == surface.name then return row end
end

function worlds.is_original(value)
    local surface = surface_for(value)
    return surface and surface.valid and (surface.name == "nauvis"
        or surface.name:find("^the%-cave%-warp%-") ~= nil) or false
end

function worlds.is_copy(value)
    local row = worlds.get(value)
    return row ~= nil and row.kind == "copy"
end

function worlds.is_cave_world(value)
    return worlds.is_original(value) or worlds.is_copy(value)
end

function worlds.is_template(value)
    local row = worlds.get(value)
    return row ~= nil and row.template == true
end

function worlds.ensure_original(value)
    local surface = surface_for(value)
    if not worlds.is_original(surface) then return nil end
    local row = worlds.get(surface)
    if row then return row end
    row = { name = surface.name, kind = "original" }
    rows()[surface.index] = row
    return row
end

function worlds.register_copy(value)
    local surface = surface_for(value)
    if not (surface and surface.valid) or surface.name == "nauvis"
        or surface.name:find("^the%-cave%-") then return nil, false end
    local row = worlds.get(surface)
    if row then return row, false end
    row = { name = surface.name, kind = "copy" }
    rows()[surface.index] = row
    return row, true
end

function worlds.owner_force(value)
    local row = worlds.get(value)
    local force = row and row.owner_force_index and game.forces[row.owner_force_index]
    return force and force.valid and force or nil
end

function worlds.set_owner(value, force)
    if type(force) == "number" then force = game.forces[force] end
    if not (force and force.valid) then return nil end
    local row = worlds.get(value) or worlds.ensure_original(value)
    if not row or row.template or (row.owner_force_index and row.owner_force_index ~= force.index
        and not row.provisional_owner) then
        return nil
    end
    row.owner_force_index = force.index
    row.provisional_owner = nil
    return row
end

function worlds.mark_template(value)
    local row = worlds.ensure_original(value)
    if not row or row.owner_force_index then return false end
    row.template = true
    return true
end

function worlds.is_active(value)
    return worlds.is_cave_world(value) and not worlds.is_template(value)
        and worlds.owner_force(value) ~= nil
end

function worlds.transfer_owner(source_index, destination_index)
    for index, row in pairs(storage.cave_worlds or {}) do
        if worlds.get(index) and row.owner_force_index == source_index then
            row.owner_force_index = destination_index
        end
    end
end

function worlds.drop_surface(index)
    local row = storage.cave_worlds and storage.cave_worlds[index]
    if not row then return false end
    local surface = game.surfaces[index]
    if surface and surface.valid and surface.name == row.name then return false end
    storage.cave_worlds[index] = nil
    return true
end

return worlds
