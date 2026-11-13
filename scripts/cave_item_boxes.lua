-- Fixed, one-way cave Store Box pairs, matching the Locomotive Garden.
local boxes = {}
boxes.name = "the-cave-2x2-container"
boxes.layout_version = "cave-storeboxes-v1"
local GAP = 2

local function valid(entity)
    return entity and entity.valid
end

local function find_unit(unit, surface, center)
    if not unit then return nil end
    local entity = game.get_entity_by_unit_number(unit)
    if valid(entity) and entity.surface == surface then return entity end
    for _, candidate in pairs(surface.find_entities_filtered { area = {
        { center.x - 12, center.y - 12 }, { center.x + 12, center.y + 12 } } }) do
        if candidate.unit_number == unit then return candidate end
    end
end

function boxes.position(center, portal_name, right)
    local portal = prototypes.entity[portal_name]
    local box = prototypes.entity[boxes.name]
    local offset = (portal.tile_width + box.tile_width) / 2 + GAP
    return { x = center.x + (right and offset or -offset), y = math.floor(center.y + 0.5) }
end

local function inventory(entity)
    return valid(entity) and entity.get_inventory(defines.inventory.chest) or nil
end

local function move(source, destination)
    if not (source and source.valid and destination and destination.valid) or source.is_empty() then return end
    for slot = 1, #source do
        local stack = source[slot]
        if stack.valid_for_read then
            -- Let the engine split stacks without resetting ammo/durability
            -- or other metadata when only part of a stack can move.
            destination.transfer_from_stack(stack)
        end
    end
end

local function drain_belt(legacy, destination)
    if not destination then return false end
    legacy.disconnect_linked_belts()
    for index = 1, legacy.get_max_transport_line_index() do
        local line = legacy.get_transport_line(index)
        while #line > 0 do
            local stack = line[#line]
            local inserted = destination.transfer_from_stack(stack)
            if inserted <= 0 then return false end
        end
    end
    return true
end

local function protect(entity)
    entity.destructible = false
    entity.minable_flag = false
    entity.operable = true
    entity.rotatable = false
    return entity
end

local function clear_ground_items(surface, target)
    for _, item in pairs(surface.find_entities_filtered { type = "item-entity", area = {
        { target.x - 1, target.y - 1 }, { target.x + 1, target.y + 1 } } }) do
        local position = surface.find_non_colliding_position("item-on-ground",
            { x = target.x, y = target.y + 3 }, 8, 0.5)
        if not position or not item.teleport(position) then return false end
    end
    return true
end

function boxes.ensure(record, field, surface, center, portal_name, right, force, legacy_unit)
    if not (surface and surface.valid and force and force.valid) then return nil end
    record.item_storeboxes = record.item_storeboxes or {}
    record.legacy_item_ports = record.legacy_item_ports or {}
    record.legacy_item_buffers = record.legacy_item_buffers or {}
    local data = record.item_storeboxes
    local entity = data[field]
    local target = boxes.position(center, portal_name, right)
    local previous = find_unit(legacy_unit, surface, center)
    if not valid(entity) and valid(previous) and previous.name == boxes.name then
        entity = previous
        data[field] = entity
    end
    if valid(entity) and entity.surface == surface and entity.force == force then
        if math.abs(entity.position.x - target.x) > 0.01 or math.abs(entity.position.y - target.y) > 0.01 then
            if not entity.teleport(target) then return nil end
        end
        entity = protect(entity)
    else
        local legacy = previous
        if valid(legacy) and legacy.type == "linked-belt" and legacy.surface == surface and legacy.force == force then
            record.legacy_item_ports[field] = legacy
            legacy.disconnect_linked_belts()
            -- Linked belts cannot be teleported. Preserve their native stacks
            -- in a saved inventory before freeing the old port's footprint.
            if not surface.can_place_entity { name = boxes.name, position = target, force = force } then
                local buffer = record.legacy_item_buffers[field]
                if not (buffer and buffer.valid) then
                    buffer = game.create_inventory(64)
                    record.legacy_item_buffers[field] = buffer
                end
                if not drain_belt(legacy, buffer) then return nil end
                legacy.destroy()
                record.legacy_item_ports[field] = nil
            end
        end
        if not surface.can_place_entity { name = boxes.name, position = target, force = force } then
            if not clear_ground_items(surface, target) then return nil end
            if not surface.can_place_entity { name = boxes.name, position = target, force = force } then return nil end
        end
        entity = surface.create_entity { name = boxes.name, position = target, force = force,
            create_build_effect_smoke = false }
        if not valid(entity) then return nil end
        data[field] = protect(entity)
    end
    local legacy = record.legacy_item_ports[field]
    if valid(legacy) and drain_belt(legacy, inventory(entity)) then
        legacy.destroy()
        record.legacy_item_ports[field] = nil
    elseif not valid(legacy) then record.legacy_item_ports[field] = nil end
    local buffer = record.legacy_item_buffers[field]
    if buffer and buffer.valid then
        move(buffer, inventory(entity))
        if buffer.is_empty() then buffer.destroy(); record.legacy_item_buffers[field] = nil end
    end
    return entity
end

local function belongs(record, field, entity)
    if not (valid(entity) and entity.name == boxes.name
        and entity.force == game.forces[record.owner_force_index]) then return false end
    local child = record.mineral_cave_surface_index or record.uranium_cave_surface_index or record.surface_index
    return entity.surface.index == (field:sub(1, 5) == "upper" and record.parent_surface_index or child)
end

function boxes.ready(record)
    local data = record and record.item_storeboxes
    if not data then return false end
    for _, field in ipairs { "upper_input", "upper_output", "lower_input", "lower_output" } do
        local entity = data[field]
        if not belongs(record, field, entity) then return false end
    end
    local child_index = record.mineral_cave_surface_index or record.uranium_cave_surface_index or record.surface_index
    return data.upper_input.surface.index == record.parent_surface_index
        and data.lower_input.surface.index == child_index
        and data.upper_input.surface ~= data.lower_input.surface
        and data.upper_input.surface == data.upper_output.surface
        and data.lower_input.surface == data.lower_output.surface
end

function boxes.sync(record)
    local data = record and record.item_storeboxes
    if not data then return end
    for field, legacy in pairs(record.legacy_item_ports or {}) do
        if not valid(legacy) then record.legacy_item_ports[field] = nil
        elseif belongs(record, field, data[field]) and drain_belt(legacy, inventory(data[field])) then
            legacy.destroy()
            record.legacy_item_ports[field] = nil
        end
    end
    for field, buffer in pairs(record.legacy_item_buffers or {}) do
        if not buffer.valid then record.legacy_item_buffers[field] = nil
        elseif belongs(record, field, data[field]) then
            move(buffer, inventory(data[field]))
            if buffer.is_empty() then buffer.destroy(); record.legacy_item_buffers[field] = nil end
        end
    end
    if not boxes.ready(record) then return end
    move(inventory(data.upper_input), inventory(data.lower_input))
    move(inventory(data.lower_output), inventory(data.upper_output))
end

function boxes.spill(record)
    local parent = record and game.surfaces[record.parent_surface_index]
    if not (parent and parent.valid) then return end
    for _, entity in pairs(record.item_storeboxes or {}) do
        local contents = inventory(entity)
        if contents then
            for slot = 1, #contents do
                local stack = contents[slot]
                if stack.valid_for_read then
                    parent.spill_item_stack { position = record.entrance_position, stack = stack,
                        enable_looted = true, force = entity.force, allow_belts = false }
                    stack.clear()
                end
            end
        end
    end
    for _, contents in pairs(record.legacy_item_buffers or {}) do
        if contents.valid then
            for slot = 1, #contents do
                local stack = contents[slot]
                if stack.valid_for_read then
                    parent.spill_item_stack { position = record.entrance_position, stack = stack,
                        enable_looted = true, force = game.forces[record.owner_force_index], allow_belts = false }
                    stack.clear()
                end
            end
        end
    end
end

function boxes.destroy(record)
    for _, entity in pairs(record.item_storeboxes or {}) do if valid(entity) then entity.destroy() end end
    for _, entity in pairs(record.legacy_item_ports or {}) do if valid(entity) then entity.destroy() end end
    for _, buffer in pairs(record.legacy_item_buffers or {}) do if buffer.valid then buffer.destroy() end end
    record.item_storeboxes, record.legacy_item_ports, record.legacy_item_buffers = nil, nil, nil
end

return boxes
