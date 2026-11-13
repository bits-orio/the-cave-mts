local M = {}
local POLE = "the-cave-lamp-pole"
local LIGHT = POLE .. "-light"
local CREATED = POLE .. "-created"
-- Event-driven lifecycle; a bounded audit also handles unraised script
-- teleports/force changes (including Warp Outpost). Never scans a surface.
local AUDIT_BUDGET = 32

local function state()
    storage.the_cave_lamp_poles = storage.the_cave_lamp_poles or {
        records = {}, order = {}, registrations = {}, cursor = 1,
    }
    return storage.the_cave_lamp_poles
end

local function is_pole(entity)
    return entity and entity.valid and entity.name == POLE
end

local function remove_light(s, record)
    if record.light_registration then
        s.registrations[record.light_registration] = nil
        record.light_registration = nil
    end
    local light = record.light
    record.light = nil
    if light and light.valid then light.destroy() end
end

local function forget(s, unit)
    local record = s.records[unit]
    if not record then return end
    s.records[unit] = nil
    s.registrations[record.registration] = nil
    local last = s.order[#s.order]
    s.order[record.slot] = last
    s.order[#s.order] = nil
    if last ~= unit then s.records[last].slot = record.slot end
    remove_light(s, record)
end

local function sync(s, record)
    local pole = record.pole
    if not is_pole(pole) then
        forget(s, record.unit)
        return
    end
    local light = record.light
    if light and light.valid then
        if light.force ~= pole.force then light.force = pole.force end
        if light.surface ~= pole.surface or light.position.x ~= pole.position.x or light.position.y ~= pole.position.y then
            if not light.teleport(pole.position, pole.surface) then
                remove_light(s, record)
                light = nil
            end
        end
    end
    if not (light and light.valid) then
        remove_light(s, record)
        if not prototypes.entity[LIGHT] then return end
        light = pole.surface.create_entity {
            name = LIGHT, position = pole.position, force = pole.force,
            quality = pole.quality, create_build_effect_smoke = false,
        }
        if not (light and light.valid) then return end
        record.light = light
        record.light_registration = script.register_on_object_destroyed(light)
        s.registrations[record.light_registration] = {unit = record.unit, light = true}
    end
    light.destructible = false
    light.minable_flag = false
    light.operable = false
end

local function attach(entity)
    if not is_pole(entity) or not entity.unit_number then return end
    local s = state()
    local unit = entity.unit_number
    local record = s.records[unit]
    if not record then
        record = {pole = entity, unit = unit, slot = #s.order + 1}
        record.registration = script.register_on_object_destroyed(entity)
        s.registrations[record.registration] = {unit = unit}
        s.records[unit] = record
        s.order[record.slot] = unit
    end
    sync(s, record)
end

function M.on_built(event)
    attach(event.entity or event.created_entity or event.destination)
end

function M.on_created(event)
    if event.effect_id ~= CREATED then return end
    if is_pole(event.source_entity) then attach(event.source_entity)
    elseif is_pole(event.target_entity) then attach(event.target_entity)
    else
        local surface = game.surfaces[event.surface_index]
        local position = event.source_position or event.target_position
        if surface and surface.valid and position then
            for _, pole in pairs(surface.find_entities_filtered {name = POLE, position = position}) do
                attach(pole)
            end
        end
    end
end

function M.on_entity_cloned(event)
    local entity = event.destination
    if is_pole(entity) then
        attach(entity)
    elseif entity and entity.valid and entity.name == LIGHT then
        -- Only the cloned visible pole may create its partner. Area cloning
        -- can also copy hidden entities, in either order; discard that copy.
        entity.destroy()
    end
end

function M.on_removed(event)
    local entity = event.entity
    local s = storage.the_cave_lamp_poles
    if s and is_pole(entity) then forget(s, entity.unit_number) end
end

function M.on_object_destroyed(event)
    local s = storage.the_cave_lamp_poles
    local link = s and s.registrations[event.registration_number]
    if not link then return end
    s.registrations[event.registration_number] = nil
    if not link.light then
        forget(s, link.unit)
    else
        local record = s.records[link.unit]
        if record then
            record.light = nil
            record.light_registration = nil
            -- Defer repair: surface clearing can destroy both halves in
            -- either order. Never recreate a lamp inside its destroy event.
        end
    end
end

function M.on_nth_tick()
    local s = storage.the_cave_lamp_poles
    if not s then return end
    for _ = 1, math.min(AUDIT_BUDGET, #s.order) do
        if #s.order == 0 then break end
        if s.cursor > #s.order then s.cursor = 1 end
        local unit = s.order[s.cursor]
        sync(s, s.records[unit])
        if s.records[unit] then s.cursor = s.cursor + 1 end
    end
end

function M.on_surface_removed()
    local s = storage.the_cave_lamp_poles
    if not s then return end
    for i = #s.order, 1, -1 do
        local record = s.records[s.order[i]]
        if not is_pole(record.pole) then forget(s, record.unit) end
    end
end

function M.on_configuration_changed()
    -- New recipe only: preserve every unrelated research/recipe flag. Also
    -- handles enabling Lamp Post after this version was already installed.
    for _, force in pairs(game.forces) do
        local technology = force.technologies["lamp-post"]
        local recipe = force.recipes[POLE]
        if recipe and technology and technology.researched then recipe.enabled = true end
    end
    M.on_surface_removed()
    M.on_nth_tick()
end

M.on_init = M.on_configuration_changed
return M
