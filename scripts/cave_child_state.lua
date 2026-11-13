-- Shared lifecycle bookkeeping for the four child-cave registries. The reset
-- coordinator owns player evacuation and surface deletion.
local cave_worlds = require("scripts.cave_worlds")
local cave_teams = require("scripts.cave_teams")
local child_state = {}

local function force_index(force)
    return type(force) == "number" and force or force and force.index
end

local function child_surface(record, field, prefix, parent_in_name)
    local index = record[field]
    local surface = index and game.get_surface(index)
    local name = prefix .. (parent_in_name and (tostring(record.parent_surface_index) .. "-") or "") .. tostring(record.id)
    return surface and surface.valid and surface.name == name and surface or nil
end

function child_state.owned_surfaces(root, force, field, prefix, parent_in_name)
    local result = {}
    local index = force_index(force)
    if not index then return result end
    for _, record in pairs(root.by_id or {}) do
        if record.owner_force_index == index then
            local surface = child_surface(record, field, prefix, parent_in_name)
            if surface then result[#result + 1] = surface end
        end
    end
    table.sort(result, function(a, b) return a.index < b.index end)
    return result
end

-- on_owned_surface_changed for a child cave the record's force owns.
function child_state.surface_created(record, surface)
    cave_teams.raise_owned_surface(surface, record.owner_force_index, "created")
end

function child_state.delete_surface(record, surface)
    return cave_teams.delete_owned_surface(surface, record and record.owner_force_index)
end

function child_state.owner_force(root, surface, field, prefix, parent_in_name)
    if not (surface and surface.valid) then return nil end
    local id = root.by_surface and root.by_surface[surface.index]
    local record = id and root.by_id[id]
    if not (record and child_surface(record, field, prefix, parent_in_name) == surface) then return nil end
    local force = game.forces[record.owner_force_index]
    return force and force.valid and force or nil
end

function child_state.transfer_force(root, source_index, destination_index)
    for _, record in pairs(root.by_id or {}) do
        if record.owner_force_index == source_index then record.owner_force_index = destination_index end
    end
    -- Existing running cities survive a merge. The source's per-force progress
    -- is retired; records and their timers remain attached to the new owner.
    if root.active_by_force then
        root.active_by_force[destination_index] = root.active_by_force[destination_index] or root.active_by_force[source_index]
        root.active_by_force[source_index] = nil
    end
    if root.completed_by_force then root.completed_by_force[source_index] = nil end
    if root.resource_decks then root.resource_decks[source_index] = nil end
end

local function destroy_render(id)
    if not id then return end
    local ok, object = pcall(rendering.get_object_by_id, id)
    if ok and object and object.valid then object.destroy() end
end

local function dispose_record_handles(record)
    -- These fields are rendering IDs, not entity unit numbers or cave IDs.
    -- Parent-surface labels outlive entity deletion unless explicitly removed.
    for _, field in ipairs {
        "entrance_label_id", "exit_label_id", "upper_timer_id", "lower_timer_id",
        "sealed_label_id", "safe_zone_outline_id", "safe_zone_label_id", "reward_label_id",
        "upper_item_down_label_id", "upper_item_up_label_id",
        "lower_item_down_label_id", "lower_item_up_label_id",
    } do
        destroy_render(record[field])
        record[field] = nil
    end
    for _, id in pairs(record.closed_render_ids or {}) do destroy_render(id) end
    record.closed_render_ids = nil
    for _, field in ipairs { "upper_transfer", "lower_transfer" } do
        local group = record[field]
        for _, id in pairs(group and group.render_ids or {}) do destroy_render(id) end
        if group then group.render_ids = nil end
    end
    for _, npc in pairs(record.npcs or {}) do
        destroy_render(npc.label_id)
        npc.label_id = nil
    end
    if record.active_tag and record.active_tag.valid then record.active_tag.destroy() end
    record.active_tag = nil
    for _, mission in pairs(record.missions or {}) do
        if mission.mining_tag and mission.mining_tag.valid then mission.mining_tag.destroy() end
        mission.mining_tag = nil
    end
    -- Only these saved legacy buffers are script-owned inventories. Ordinary
    -- entity inventories are disposed with their entities by the reset caller.
    for _, buffer in pairs(record.legacy_item_buffers or {}) do
        if buffer.valid then buffer.destroy() end
    end
    record.legacy_item_buffers = nil
end

function child_state.clear_force(root, index)
    local removed, surfaces = {}, {}
    for id, record in pairs(root.by_id or {}) do
        if record.owner_force_index == index then
            dispose_record_handles(record)
            removed[id] = true
            for _, field in ipairs { "uranium_cave_surface_index", "mineral_cave_surface_index", "child_surface_index", "surface_index" } do
                if record[field] then surfaces[record[field]] = true end
            end
            root.by_id[id] = nil
        end
    end
    for _, field in ipairs { "by_surface", "by_entity" } do
        for key, id in pairs(root[field] or {}) do
            if removed[id] then
                root[field][key] = nil
                if field == "by_entity" and root.entity_cache then root.entity_cache[key] = nil end
            end
        end
    end
    for parent, ids in pairs(root.entrances_by_parent or {}) do
        for i = #ids, 1, -1 do if removed[ids[i]] then table.remove(ids, i) end end
        if #ids == 0 then root.entrances_by_parent[parent] = nil end
    end
    for _, field in ipairs { "pending_respawns", "alarm_units", "hacks" } do
        for key, record in pairs(root[field] or {}) do
            local id = type(record) == "table" and (record.cave_id or record.city_id or record.record_id)
            if id and removed[id] then root[field][key] = nil end
        end
    end
    for unit, entity in pairs(root.entity_cache or {}) do
        if not entity.valid or surfaces[entity.surface.index] then root.entity_cache[unit] = nil end
    end
    for _, field in ipairs { "active_by_force", "completed_by_force", "resource_decks" } do
        if root[field] then root[field][index] = nil end
    end
end

function child_state.return_surface(player, parent_index)
    local parent = parent_index and game.get_surface(parent_index)
    if parent and parent.valid and not cave_worlds.is_template(parent) then return parent end
    return cave_teams.home_surface(cave_teams.player_force(player))
end

function child_state.spawn_position(player, surface)
    local force = cave_teams.player_force(player)
    return force and force.valid and force.get_spawn_position(surface) or nil
end

return child_state
