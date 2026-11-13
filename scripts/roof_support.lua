-- Square, tile-exact roof immunity, independent of wall strength and reach.
-- Persist only entity records and a chunk index; no world scan per tick.
local roof = {names = {}}
local by_name = {}
for _, variant in ipairs(require("shared.roof_support")) do
    by_name[variant.name] = variant
    roof.names[#roof.names + 1] = variant.name
end

local function state()
    storage.roof_support = storage.roof_support or {
        units = {}, surfaces = {}, watches = {}, previews = {}, revision = 0,
    }
    return storage.roof_support
end

function roof.is_support(entity)
    return entity and entity.valid and by_name[entity.name] ~= nil
end

function roof.bounds(entity)
    if not roof.is_support(entity) then return nil end
    local area = by_name[entity.name].area
    -- Match the engine's rotating cursor-radius offset. The 2x3 footprint
    -- has a half-tile center on one axis; its offset keeps the same number
    -- of whole protected tiles in every direction, including old placements.
    local offset = entity.prototype.radius_visualisation_specification.offset
    local dx, dy = offset.x or offset[1] or 0, offset.y or offset[2] or 0
    local direction = entity.direction
    if direction == defines.direction.east then dx, dy = -dy, dx
    elseif direction == defines.direction.south then dx, dy = -dx, -dy
    elseif direction == defines.direction.west then dx, dy = dy, -dx end
    local x = math.floor(entity.position.x + dx - area / 2 + 0.0000001)
    local y = math.floor(entity.position.y + dy - area / 2 + 0.0000001)
    return {x1 = x, y1 = y, x2 = x + area, y2 = y + area, area = area}
end

local function each_chunk(record, fn)
    for x = math.floor(record.x1 / 32), math.floor((record.x2 - 1) / 32) do
        for y = math.floor(record.y1 / 32), math.floor((record.y2 - 1) / 32) do
            fn(x .. ":" .. y)
        end
    end
end

local function remove(unit)
    local s = state()
    local record = s.units[unit]
    if not record then return nil end
    local chunks = s.surfaces[record.surface_index]
    if chunks then
        each_chunk(record, function(key)
            local bucket = chunks[key]
            if bucket then
                bucket[unit] = nil
                if not next(bucket) then chunks[key] = nil end
            end
        end)
        if not next(chunks) then s.surfaces[record.surface_index] = nil end
    end
    s.watches[record.watch] = nil
    s.units[unit] = nil
    s.revision = (s.revision or 0) + 1
    return record
end

function roof.add(entity)
    if not roof.is_support(entity) or not entity.unit_number then return false end
    -- Explicitly enable existing medium/large columns when upgrading a save
    -- from the non-rotatable prototypes. Small supports keep their old behavior.
    entity.rotatable = by_name[entity.name].rotatable == true
    local s, unit = state(), entity.unit_number
    local bounds = roof.bounds(entity)
    local old = s.units[unit]
    if old and old.surface_index == entity.surface.index
        and old.x1 == bounds.x1 and old.y1 == bounds.y1 then return false end
    remove(unit)
    bounds.entity = entity
    bounds.surface_index = entity.surface.index
    bounds.force_index = entity.force.index
    bounds.watch = script.register_on_object_destroyed(entity)
    s.units[unit] = bounds
    s.watches[bounds.watch] = unit
    s.revision = (s.revision or 0) + 1
    local chunks = s.surfaces[bounds.surface_index] or {}
    s.surfaces[bounds.surface_index] = chunks
    each_chunk(bounds, function(key)
        chunks[key] = chunks[key] or {}
        chunks[key][unit] = true
    end)
    return true
end

local function rotate_if_clear(entity, previous, wanted)
    -- Factorio restricts placed non-square buildings to 180-degree turns.
    -- Use the native bounding box and collision layers for the 90-degree turn,
    -- retaining the same entity, contents, health and mining progress.
    entity.direction = wanted
    local box = entity.bounding_box
    entity.direction = previous
    local mask = entity.prototype.collision_mask.layers
    if #entity.surface.find_tiles_filtered{area = box, collision_mask = mask, limit = 1} > 0 then return end
    for _, other in pairs(entity.surface.find_entities_filtered{area = box, collision_mask = mask}) do
        if other ~= entity and other.type ~= "entity-ghost" and other.type ~= "tile-ghost"
            and not other.prototype.collision_mask.colliding_with_tiles_only then return end
    end
    entity.direction = wanted
end

function roof.on_rotated(entity, previous_direction)
    if not roof.is_support(entity) then return nil end
    if by_name[entity.name].rotatable and previous_direction
        and (entity.direction - previous_direction) % 16 == 8 then
        rotate_if_clear(entity, previous_direction, (previous_direction + 4) % 16)
    end
    local old = state().units[entity.unit_number]
    if roof.add(entity) then return old end
    return nil
end

function roof.remove(entity)
    if not roof.is_support(entity) then return nil end
    return remove(entity.unit_number)
end

function roof.on_object_destroyed(event)
    return remove(state().watches[event.registration_number])
end

function roof.is_tile_protected(surface, x, y)
    if not (surface and surface.valid) then return false end
    local s = state()
    local chunks = s.surfaces[surface.index]
    if not chunks then return false end
    x, y = math.floor(x), math.floor(y)
    local bucket = chunks[math.floor(x / 32) .. ":" .. math.floor(y / 32)]
    if not bucket then return false end
    for unit in pairs(bucket) do
        local r = s.units[unit]
        if r and r.entity.valid and r.entity.surface.index == surface.index
            and x >= r.x1 and x < r.x2 and y >= r.y1 and y < r.y2 then
            return true
        end
    end
    return false
end

function roof.is_cell_protected(surface, x, y)
    -- Union coverage counts, but one protected tile cannot spare the other
    -- three tiles of an existing 2x2 collapse cell.
    return roof.is_tile_protected(surface, x, y)
        and roof.is_tile_protected(surface, x + 1, y)
        and roof.is_tile_protected(surface, x, y + 1)
        and roof.is_tile_protected(surface, x + 1, y + 1)
end

local function destroy_ids(ids)
    for _, id in ipairs(ids) do
        local object = rendering.get_object_by_id(id)
        if object and object.valid then object.destroy() end
    end
end

function roof.clear_preview(player_index)
    local s, preview = state(), state().previews[player_index]
    if preview then
        if preview.units then
            for _, ids in pairs(preview.units) do destroy_ids(ids) end
        else
            -- Upgrade from the original 3.2.40 single-entity preview.
            destroy_ids(preview)
        end
    end
    s.previews[player_index] = nil
end

-- Query the existing coverage-chunk index, with no entity-count limit.
-- Include squares intersecting the view even when the column is just offscreen.
function roof.visible_records(surface, area)
    local s, result, seen = state(), {}, {}
    if not (surface and surface.valid) then return result end
    local chunks = s.surfaces[surface.index]
    if not chunks then return result end
    for x = math.floor(area.x1 / 32), math.floor(area.x2 / 32) do
        for y = math.floor(area.y1 / 32), math.floor(area.y2 / 32) do
            for unit in pairs(chunks[x .. ":" .. y] or {}) do
                if not seen[unit] then
                    seen[unit] = true
                    local r = s.units[unit]
                    if r and r.entity.valid and r.surface_index == surface.index
                        and r.x1 < area.x2 and r.x2 > area.x1
                        and r.y1 < area.y2 and r.y2 > area.y1 then
                        result[#result + 1] = r
                    end
                end
            end
        end
    end
    return result
end

-- Shared by the live player view and native rendering/lifecycle checks.
function roof.sync_view(player_index, surface, area, players)
    local s = state()
    local preview = s.previews[player_index]
    if preview and (not preview.units or preview.surface_index ~= surface.index) then
        roof.clear_preview(player_index)
        preview = nil
    end
    preview = preview or {units = {}, surface_index = surface.index}
    s.previews[player_index] = preview
    local wanted = {}
    for _, record in ipairs(roof.visible_records(surface, area)) do
        local unit = record.entity.unit_number
        wanted[unit] = true
        local ids = preview.units[unit]
        local first = ids and rendering.get_object_by_id(ids[1])
        local corner = first and first.valid and first.left_top.position
        if not (corner and corner.x == record.x1 and corner.y == record.y1) then
            if ids then destroy_ids(ids) end
            preview.units[unit] = roof.draw_preview(record.entity, players)
        end
    end
    for unit, ids in pairs(preview.units) do
        if not wanted[unit] then destroy_ids(ids); preview.units[unit] = nil end
    end
    local ids = {}
    for _, pair in pairs(preview.units) do
        for _, id in ipairs(pair) do ids[#ids + 1] = id end
    end
    return ids
end

local function held_support(player)
    local stack = player.cursor_stack
    if stack and stack.valid_for_read then
        local entity = stack.prototype.place_result
        return entity and by_name[entity.name] and entity.name
    end
    local ghost = player.cursor_ghost
    local entity = ghost and ghost.name.place_result
    return entity and by_name[entity.name] and entity.name
end

function roof.on_context_changed(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid and player.connected) then
        roof.clear_preview(event.player_index)
        return
    end
    local cursor = held_support(player)
    local selected = roof.is_support(player.selected) and player.selected.unit_number
    if not (cursor or selected) then roof.clear_preview(player.index); return end
    -- LuaControl.position/surface follow the viewed controller, including
    -- remote view. The native prototype handles cursor motion without polling.
    local position, resolution = player.position, player.display_resolution
    local half_width = resolution.width / (64 * player.zoom) + 16
    local half_height = resolution.height / (64 * player.zoom) + 16
    local area = {x1 = math.floor(position.x - half_width), y1 = math.floor(position.y - half_height),
        x2 = math.ceil(position.x + half_width), y2 = math.ceil(position.y + half_height)}
    local signature = table.concat({player.surface.index, area.x1, area.y1, area.x2, area.y2,
        cursor or "", selected or 0, state().revision or 0}, ":")
    local old = state().previews[player.index]
    if old and old.signature == signature then return end
    roof.sync_view(player.index, player.surface, area, {player.index})
    state().previews[player.index].signature = signature
end

roof.on_selected = roof.on_context_changed

-- Shared by the hover handler and native headless rendering checks.
function roof.draw_preview(entity, players)
    local r = roof.bounds(entity)
    if not r then return {} end
    local ids = {}
    for _, filled in ipairs({true, false}) do
        local object = rendering.draw_rectangle {
            color = filled and {r = 0.1, g = 0.45, b = 1, a = 0.12}
                or {r = 0.2, g = 0.65, b = 1, a = 0.8},
            width = 2, filled = filled, draw_on_ground = true,
            left_top = {r.x1, r.y1}, right_bottom = {r.x2, r.y2},
            surface = entity.surface, players = players,
        }
        ids[#ids + 1] = object.id
    end
    return ids
end

function roof.refresh_previews()
    for _, player in pairs(game.connected_players) do
        roof.on_context_changed {player_index = player.index}
    end
end

function roof.rebuild()
    local old = storage.roof_support
    if old then
        for player_index in pairs(old.previews or {}) do roof.clear_preview(player_index) end
    end
    storage.roof_support = nil
    state()
    -- One-time initialization/migration, including supports already in saves.
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered {name = roof.names}) do
            roof.add(entity)
        end
    end
end

function roof.drop_surface(surface_index)
    local s = state()
    for player_index, preview in pairs(s.previews) do
        if preview.surface_index == surface_index then roof.clear_preview(player_index) end
    end
    local doomed = {}
    for unit, record in pairs(s.units) do
        if record.surface_index == surface_index then doomed[#doomed + 1] = unit end
    end
    for _, unit in ipairs(doomed) do remove(unit) end
    roof.refresh_previews()
end

function roof.debug_stats()
    local units, buckets = 0, 0
    for _ in pairs(state().units) do units = units + 1 end
    for _, chunks in pairs(state().surfaces) do
        for _ in pairs(chunks) do buckets = buckets + 1 end
    end
    return {units = units, buckets = buckets}
end

return roof
