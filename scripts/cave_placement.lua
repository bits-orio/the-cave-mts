-- Shared hard-map boundary checks. Underground out-of-map tiles may be dug;
-- the finite map edge and terrain already consumed by Advancing Collapse may not.
local zones = require("scripts.advancing_zones")
local placement = {}
local train_api

function placement.configure_train_safety_api(api) train_api = api end

-- Inclusive tile bounds. Reserve the partially consumed collapse row as well.
local function limits(surface)
    local map = surface.map_gen_settings or {}
    local left, top, right, bottom = -math.huge, -math.huge, math.huge, math.huge
    if (map.width or 0) > 0 then
        left, right = math.ceil(-map.width / 2), math.ceil(map.width / 2) - 1
    end
    if (map.height or 0) > 0 then
        top, bottom = math.ceil(-map.height / 2), math.ceil(map.height / 2) - 1
    end
    if zones.is_active() and zones.is_main_surface(surface) then
        left, right = math.max(left, -zones.ZONE_WIDTH / 2), math.min(right, zones.ZONE_WIDTH / 2 - 1)
        bottom = math.min(bottom, zones.SOUTH_VOID_Y - 1)
        local root = storage and storage.the_cave_advancing_collapse
        local state = root and root.surfaces and root.surfaces[surface.index]
        if state and state.phase == "active" and state.line_y then
            bottom = math.min(bottom, state.line_y - 1)
        end
    end
    return left, top, right, bottom
end

function placement.area_is_playable(surface, x1, y1, x2, y2)
    if not (surface and surface.valid) then return false end
    local left, top, right, bottom = limits(surface)
    return x1 <= x2 and y1 <= y2 and x1 >= left and y1 >= top and x2 <= right and y2 <= bottom
end

-- Includes every upper port, pipe, pole, lamp, panel, the portal and a walking
-- halo / return landing. All four portal families use this same bounded pad.
function placement.entrance_bounds(position)
    local x, y = math.floor(position.x), math.floor(position.y)
    return x - 10, y - 8, x + 8, y + 6
end

function placement.entrance_is_playable(surface, position)
    if not position then return false end
    return placement.area_is_playable(surface, placement.entrance_bounds(position))
end

function placement.plan_bounds(plan, with_entrance)
    local x1, y1, x2, y2 = plan.x1, plan.y1, plan.x2, plan.y2
    if with_entrance then
        local a, b, c, d = placement.entrance_bounds(
            plan.entrance_position or { x = plan.cx + 0.5, y = plan.cy + 0.5 })
        x1, y1, x2, y2 = math.min(x1, a), math.min(y1, b), math.max(x2, c), math.max(y2, d)
    end
    return x1, y1, x2, y2
end

-- Translate geometry, never reroll the room identity or change its dimensions.
-- The caller rechecks regional identity, spacing, assets and train clearance.
function placement.fit_plan(surface, plan, with_entrance)
    local x1, y1, x2, y2 = placement.plan_bounds(plan, with_entrance)
    local left, top, right, bottom = limits(surface)
    -- One tile for the frontier, even at a hard map edge.
    left, top, right, bottom = left + 1, top + 1, right - 1, bottom - 1
    if x2 - x1 > right - left or y2 - y1 > bottom - top then return nil end
    local dx = math.max(left - x1, math.min(0, right - x2))
    local dy = math.max(top - y1, math.min(0, bottom - y2))
    if dx == 0 and dy == 0 then return plan end
    local fitted = {}
    for k, v in pairs(plan) do fitted[k] = v end
    fitted.cx, fitted.cy = plan.cx + dx, plan.cy + dy
    fitted.x1, fitted.x2 = plan.x1 + dx, plan.x2 + dx
    fitted.y1, fitted.y2 = plan.y1 + dy, plan.y2 + dy
    fitted.boundary_adjusted = true
    return fitted
end

function placement.area_is_clear(surface, x1, y1, x2, y2, protected_units)
    for _, entity in pairs(surface.find_entities_filtered { area = {{x1, y1}, {x2 + 1, y2 + 1}} }) do
        if entity.valid and not (protected_units and protected_units[entity.unit_number]) then
            local force = entity.force and entity.force.name or "neutral"
            local natural = entity.name == "diggy-rock" or entity.name == "diggy-rubble"
                or entity.name == "diggy-tree" or entity.type == "resource" or entity.type == "tree"
            if not natural and force ~= "enemy" then return false end
        end
    end
    return true
end

function placement.entrance_site_is_safe(surface, position, protected_units)
    if not placement.entrance_is_playable(surface, position) then return false end
    local x1, y1, x2, y2 = placement.entrance_bounds(position)
    if train_api and not train_api.cave_area_is_safe(surface, {{x1, y1}, {x2 + 1, y2 + 1}}) then return false end
    return placement.area_is_clear(surface, x1, y1, x2, y2, protected_units)
end

-- Called only after the whole site passes validation, before creating anything.
-- world is passed in to avoid a require cycle through region features.
function placement.prepare_entrance(surface, position, world)
    if not placement.entrance_site_is_safe(surface, position) then return false end
    local x1, y1, x2, y2 = placement.entrance_bounds(position)
    local frontier = {}
    for y = y1, y2 do
        for x = x1, x2 do
            world.carve_safe_tile(surface, x, y)
            frontier[#frontier + 1] = {x, y}
        end
    end
    world.advance_frontier(surface, frontier)
    return true
end

-- Lost City searches for hardware positions. Constrain the *result* including
-- its footprint; the engine's collision search alone can accept black tiles.
function placement.find_upper_position(surface, name, preferred, radius, center)
    local x1, y1, x2, y2 = placement.entrance_bounds(center)
    local function acceptable(p)
        local right_margin = name == "big-electric-pole" and 2 or 1
        return p and p.x - 1 >= x1 and p.y - 1 >= y1
            and p.x + right_margin <= x2 + 1 and p.y + 1 <= y2 + 1
            and placement.area_is_playable(surface, math.floor(p.x - 1), math.floor(p.y - 1),
                math.ceil(p.x + 1) - 1, math.ceil(p.y + 1) - 1)
    end
    local candidate = surface.find_non_colliding_position(name, preferred, radius, 0.5)
    if acceptable(candidate) then return candidate end
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.abs(dx) == distance or math.abs(dy) == distance then
                    local p = { x = preferred.x + dx, y = preferred.y + dy }
                    if acceptable(p) and surface.can_place_entity { name = name, position = p } then return p end
                end
            end
        end
    end
    return nil
end

-- Configuration-time repair for legacy entrances crossing a hard map edge.
-- Clone the complete upper group before committing any record or destroying
-- its source. This also supports linked belts, which cannot be teleported.
-- Child surfaces, timers, rewards and operation progress stay on the same record.
function placement.repair_entrance(record, root, world, fields, min_distance)
    if not (record and record.status ~= "closed" and record.entrance_position) then return false end
    local surface = game.surfaces[record.parent_surface_index]
    if not (surface and surface.valid) then return false end
    local center = record.entrance_position
    local x1, y1, x2, y2 = placement.entrance_bounds(center)
    -- Do not rescue a cave from the advancing collapse or move a closed cave.
    if zones.is_active() and zones.is_main_surface(surface) then
        local _, _, _, bottom = limits(surface)
        if y2 > bottom then return false end
    end
    local slots, wanted, old_entities = {}, {}, {}
    local function add_slot(store, key)
        local unit = store and store[key]
        if type(unit) == "number" then
            slots[#slots + 1] = { store = store, key = key, unit = unit }
            wanted[unit] = true
        end
    end
    add_slot(record, "entrance_unit_number")
    for _, key in ipairs(fields) do add_slot(record, key) end
    for _, key in ipairs { "item_down_input", "item_up_output", "fluid_down_input", "fluid_up_output",
        "pole", "info_panel", "indicator_lamp", "power", "power_connector" } do
        add_slot(record.upper_transfer, key)
    end
    for _, entity in pairs(surface.find_entities_filtered {
        area = {{center.x - 40, center.y - 40}, {center.x + 40, center.y + 40}},
    }) do
        if entity.valid and wanted[entity.unit_number] then old_entities[entity.unit_number] = entity end
    end
    if not old_entities[record.entrance_unit_number] then return false end
    -- Require all recorded hardware. A missing component is left to its owning
    -- module's repair, never discarded by this boundary migration.
    for _, slot in ipairs(slots) do if not old_entities[slot.unit] then return false end end
    for _, entity in pairs(old_entities) do
        x1, y1 = math.min(x1, math.floor(entity.position.x - 2)), math.min(y1, math.floor(entity.position.y - 2))
        x2, y2 = math.max(x2, math.ceil(entity.position.x + 2)), math.max(y2, math.ceil(entity.position.y + 2))
    end
    if placement.area_is_playable(surface, x1, y1, x2, y2) then return false end
    local plan = { cx = math.floor(center.x), cy = math.floor(center.y), x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    local fit = placement.fit_plan(surface, plan, true)
    if not fit then return false end
    local inward = center.x > 0 and -1 or 1
    for _, offset in ipairs {0, 24, 48, 72} do
        local dx, dy = fit.cx - plan.cx + inward * offset, fit.cy - plan.cy
        local target = {x = center.x + dx, y = center.y + dy}
        local a, b, c, d = x1 + dx, y1 + dy, x2 + dx, y2 + dy
        local legal = math.abs(dx) <= 128 and math.abs(dy) <= 128
            and placement.area_is_playable(surface, a, b, c, d)
            and placement.area_is_clear(surface, a, b, c, d, wanted)
            and (not train_api or train_api.cave_area_is_safe(surface, {{a, b}, {c + 1, d + 1}}))
        if legal and min_distance and min_distance > 0 then
            for _, other in pairs(root.by_id) do
                if other ~= record and other.parent_surface_index == record.parent_surface_index
                    and other.entrance_position and other.resource_key == record.resource_key then
                    local ox, oy = other.entrance_position.x - target.x, other.entrance_position.y - target.y
                    if ox * ox + oy * oy < min_distance * min_distance then legal = false break end
                end
            end
        end
        if legal then
            local tiles = {}
            for y = b, d do for x = a, c do
                world.carve_safe_tile(surface, x, y)
                tiles[#tiles + 1] = {x, y}
            end end
            world.advance_frontier(surface, tiles)
            local clones, complete = {}, true
            for _, slot in ipairs(slots) do
                local source = old_entities[slot.unit]
                if not clones[slot.unit] then
                    local ok, entity = pcall(function() return source.clone {
                        position = {x = source.position.x + dx, y = source.position.y + dy},
                        surface = surface, create_build_effect_smoke = false,
                    } end)
                    if not ok or not (entity and entity.valid and entity.unit_number) then complete = false break end
                    clones[slot.unit] = entity
                end
            end
            if complete then
                local old_portal = record.entrance_unit_number
                for _, slot in ipairs(slots) do slot.store[slot.key] = clones[slot.unit].unit_number end
                record.entrance_position = target
                root.by_entity[old_portal] = nil
                root.by_entity[record.entrance_unit_number] = record.id
                for _, entity in pairs(old_entities) do entity.destroy() end
                for _, field in ipairs {"entrance_label_id", "upper_timer_id", "upper_item_down_label_id", "upper_item_up_label_id"} do
                    local object = record[field] and rendering.get_object_by_id(record[field])
                    if object and object.valid then object.destroy() end
                    record[field] = nil
                end
                local group = record.upper_transfer
                if group then
                    for _, id in pairs(group.render_ids or {}) do
                        local object = rendering.get_object_by_id(id)
                        if object and object.valid then object.destroy() end
                    end
                    group.render_ids = {}
                end
                local force = game.forces[record.owner_force_index]
                if force then force.chart(surface, {{a, b}, {c + 1, d + 1}}) end
                log("The Cave: moved out-of-map entrance " .. record.id .. " to " .. target.x .. ", " .. target.y)
                return true
            end
            for _, entity in pairs(clones) do if entity.valid then entity.destroy() end end
        end
    end
    return false
end

return placement
