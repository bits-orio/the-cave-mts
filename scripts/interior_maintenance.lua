-- Saved, validated references for fixed interior fixtures and exterior poles.
-- Dynamic inventories, fluid networks and battery energy are never cached here.
local maintenance = {}
local POLE_RESCAN_TICKS = 300

local function valid(object)
    return object and object.valid
end

local function revisions()
    storage.the_cave_interior_pole_revisions = storage.the_cave_interior_pole_revisions or {}
    return storage.the_cave_interior_pole_revisions
end

function maintenance.on_built(entity)
    if not (valid(entity) and entity.type == "electric-pole") then return end
    local changes = storage.the_cave_interior_pole_revisions
    if not changes then return end
    local index = entity.surface.index
    changes[index] = (changes[index] or 0) + 1
end

function maintenance.reset()
    storage.the_cave_interior_pole_revisions = nil
end

function maintenance.on_surface_deleted(event)
    local changes = storage.the_cave_interior_pole_revisions
    if changes then changes[event.surface_index] = nil end
end

function maintenance.poles(record, hidden_pole, center, half_size)
    if not (record and valid(hidden_pole) and center) then return {} end
    local surface, force = hidden_pole.surface, hidden_pole.force
    local revision = revisions()[surface.index] or 0
    local tick = game.tick
    local cache = record.external_pole_cache
    -- Moving trains must refresh their square immediately. A stationary bridge
    -- refreshes on builds and periodically for script-created/moved poles whose
    -- mod did not raise a build event. Eligibility is still checked by callers.
    if not cache or cache.pole ~= hidden_pole or cache.surface ~= surface
        or cache.force ~= force or cache.x ~= center.x or cache.y ~= center.y
        or cache.half_size ~= half_size or cache.revision ~= revision
        or tick - cache.tick >= POLE_RESCAN_TICKS then
        cache = {
            pole = hidden_pole, surface = surface, force = force,
            x = center.x, y = center.y, half_size = half_size,
            revision = revision, tick = tick,
            targets = surface.find_entities_filtered {
                type = "electric-pole", force = force,
                area = {
                    { center.x - half_size, center.y - half_size },
                    { center.x + half_size, center.y + half_size },
                },
            },
        }
        record.external_pole_cache = cache
    end
    return cache.targets
end

function maintenance.connectors_linked(upper, lower)
    if not (valid(upper) and valid(lower)) then return false end
    return upper.is_connected_to(lower, defines.wire_origin.player)
        or upper.is_connected_to(lower, defines.wire_origin.script)
end

local function snapshot(entity)
    if not valid(entity) then return nil end
    return {
        entity = entity, surface = entity.surface, force = entity.force,
        name = entity.name, x = entity.position.x, y = entity.position.y,
    }
end

local function unchanged(fixture, entity)
    return fixture and valid(entity) and fixture.entity == entity
        and entity.surface == fixture.surface and entity.force == fixture.force
        and entity.name == fixture.name
        and math.abs(entity.position.x - fixture.x) < 0.001
        and math.abs(entity.position.y - fixture.y) < 0.001
end

function maintenance.remember_layout(record, force, upper_surface, lower_surface,
        anchor, version, fields, upper_substation, lower_substation)
    record.infrastructure_ready = nil
    if not (valid(force) and valid(upper_surface) and valid(lower_surface)
        and valid(upper_substation) and valid(lower_substation)) then return end
    local upper = upper_substation.get_wire_connector(defines.wire_connector_id.pole_copper, false)
    local lower = lower_substation.get_wire_connector(defines.wire_connector_id.pole_copper, false)
    if not maintenance.connectors_linked(upper, lower) then return end
    local fixtures = {}
    for _, field in ipairs(fields) do
        local fixture = snapshot(record[field])
        if not fixture or fixture.force ~= force then return end
        fixtures[field] = fixture
    end
    record.infrastructure_ready = {
        force = force, upper_surface = upper_surface, lower_surface = lower_surface,
        x = anchor.x, y = anchor.y, version = version, fixtures = fixtures,
        upper_substation = snapshot(upper_substation),
        lower_substation = snapshot(lower_substation),
        upper_connector = upper, lower_connector = lower,
    }
end

function maintenance.layout_ready(record, force, upper_surface, lower_surface,
        anchor, version, upper_substation, lower_substation)
    local marker = record and record.infrastructure_ready
    if not (marker and valid(force) and valid(upper_surface) and valid(lower_surface)
        and anchor and marker.force == force
        and marker.upper_surface == upper_surface and marker.lower_surface == lower_surface
        and marker.x == anchor.x and marker.y == anchor.y and marker.version == version
        and unchanged(marker.upper_substation, upper_substation)
        and unchanged(marker.lower_substation, lower_substation)) then return false end
    for field, fixture in pairs(marker.fixtures) do
        if not unchanged(fixture, record[field]) then return false end
    end
    -- Verify the native wire directly, without an entity search or a reconnect.
    -- This also recovers a wire removed by another mod while both poles survive.
    return maintenance.connectors_linked(marker.upper_connector, marker.lower_connector)
end

return maintenance
