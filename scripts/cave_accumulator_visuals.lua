-- Visuals only: never writes energy, capacity, force, quality or electric flow.
-- Native accumulators remain independent members of their own power networks.
local visuals = {}
local geometry = require("shared.cave_accumulator_graphics")
local NAMES = {"the-cave-accumulator-10x10", "the-cave-accumulator-20x20"}
local FAN_SPEED = 5 / 18 -- 48 frames per 2.88-second revolution, as in the preview.

local function state()
    storage.cave_accumulator_visuals = storage.cave_accumulator_visuals or {
        records = {}, registrations = {}
    }
    return storage.cave_accumulator_visuals
end

local function object(id)
    if not id then return nil end
    local result = rendering.get_object_by_id(id)
    return result and result.valid and result or nil
end

local function clear_renders(record)
    local gauge, fans = object(record.gauge_id), object(record.fans_id)
    if gauge then gauge.destroy() end
    if fans then fans.destroy() end
    record.gauge_id, record.fans_id, record.percent = nil, nil, nil
end

local function remove(s, unit_number)
    local record = s.records[unit_number]
    if not record then return end
    clear_renders(record)
    if record.registration then s.registrations[record.registration] = nil end
    s.records[unit_number] = nil
end

local function supported(entity)
    return entity and entity.valid and geometry[entity.name] ~= nil
        and entity.unit_number ~= nil
end

local function update(record)
    local entity = record.entity
    local capacity = entity.electric_buffer_size or 0
    local energy = entity.energy or 0
    -- Reading the live buffer preserves actual Quality/mod-adjusted capacity.
    local ratio = capacity > 0 and math.max(0, math.min(1, energy / capacity)) or 0
    local percent = math.min(100, math.floor(ratio * 100 + 0.000001))
    local gauge = object(record.gauge_id)
    if not gauge then
        gauge = rendering.draw_sprite {
            sprite = entity.name .. "-charge-" .. percent,
            target = entity, surface = entity.surface, forces = {entity.force},
            render_layer = "higher-object-above", only_in_alt_mode = false
        }
        record.gauge_id = gauge.id
        record.percent = percent
    elseif record.percent ~= percent then
        gauge.sprite = entity.name .. "-charge-" .. percent
        record.percent = percent
    end

    local fans
    if #geometry[entity.name].fans > 0 then
        fans = object(record.fans_id)
        if not fans then
            fans = rendering.draw_animation {
                animation = entity.name .. "-cooling-fans",
                animation_speed = FAN_SPEED, animation_offset = entity.unit_number % 48,
                target = entity, surface = entity.surface, forces = {entity.force},
                render_layer = "higher-object-above", only_in_alt_mode = false
            }
            record.fans_id = fans.id
        end
    end
    -- Rendering is restricted to the current owner. Force merges/transfers are
    -- picked up without retaining a deleted LuaForce or mixing force state.
    if record.force_index ~= entity.force.index then
        gauge.forces = {entity.force}
        if fans then fans.forces = {entity.force} end
        record.force_index = entity.force.index
    end
end

local function register(entity)
    if not supported(entity) then return end
    local s = state()
    local unit_number = entity.unit_number
    local record = s.records[unit_number]
    if record and record.entity ~= entity then
        remove(s, unit_number)
        record = nil
    end
    if not record then
        record = {entity = entity, registration = script.register_on_object_destroyed(entity)}
        s.records[unit_number] = record
        s.registrations[record.registration] = unit_number
    end
    update(record)
end

function visuals.on_built(event)
    register(event.entity or event.created_entity or event.destination)
end

function visuals.on_object_destroyed(event)
    local s = storage.cave_accumulator_visuals
    if not s then return end
    local unit_number = s.registrations[event.registration_number]
    if unit_number then remove(s, unit_number) end
end

function visuals.on_surface_removed(event)
    local s = storage.cave_accumulator_visuals
    if not s then return end
    for unit_number, record in pairs(s.records) do
        local entity = record.entity
        if not entity.valid or entity.surface.index == event.surface_index then
            remove(s, unit_number)
        end
    end
end

function visuals.on_nth_tick()
    local s = storage.cave_accumulator_visuals
    if not s then return end
    -- Only registered large accumulators, six times per second. No scans of
    -- surfaces/chunks/players and no work on ordinary or market accumulators.
    for unit_number, record in pairs(s.records) do
        if supported(record.entity) then update(record) else remove(s, unit_number) end
    end
end

local function discover_once()
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered {name = NAMES}) do register(entity) end
    end
end

function visuals.on_init()
    if storage.cave_accumulator_visuals then
        for _, record in pairs(storage.cave_accumulator_visuals.records) do clear_renders(record) end
    end
    storage.cave_accumulator_visuals = {records = {}, registrations = {}}
    discover_once()
end

function visuals.on_configuration_changed()
    if not storage.cave_accumulator_visuals then
        state()
        discover_once()
        return
    end
    local s = state()
    for unit_number, record in pairs(s.records) do
        if supported(record.entity) then
            clear_renders(record)
            update(record)
        else
            remove(s, unit_number)
        end
    end
end

-- Stored entity references and render IDs survive save/load. No on_load writes
-- or registration side effects are necessary; invalidated renders self-repair.
return visuals
