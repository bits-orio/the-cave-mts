local game_settings = require("scripts.game_settings")
local settings = game_settings.proxy(settings)

local tnt_boxes = {}

local STORAGE_KEY = "the_cave_tnt_boxes"
local COUNTDOWN_TICKS = 10 * 60
local MAX_ACTIVE_BOXES = 5
local ROCKS_PER_TICK = 48
local COVER_NAMES = { "diggy-rock", "diggy-rubble" }

local TIERS = {
    ["the-cave-tnt-box-small"] = {
        radius = 10,
        color = { r = 1.00, g = 0.82, b = 0.16, a = 1 },
        visual_rings = { { radius = 1.4, count = 6 }, { radius = 2.8, count = 8 } },
    },
    ["the-cave-tnt-box-medium"] = {
        radius = 15,
        color = { r = 1.00, g = 0.45, b = 0.10, a = 1 },
        visual_rings = { { radius = 1.6, count = 7 }, { radius = 3.2, count = 10 }, { radius = 4.8, count = 12 } },
    },
    ["the-cave-tnt-box-large"] = {
        radius = 20,
        color = { r = 1.00, g = 0.18, b = 0.12, a = 1 },
        visual_rings = { { radius = 1.8, count = 8 }, { radius = 3.6, count = 12 }, { radius = 5.4, count = 16 } },
    },
}

tnt_boxes.entity_names = {
    "the-cave-tnt-box-small",
    "the-cave-tnt-box-medium",
    "the-cave-tnt-box-large",
}

local dig_handler

local function startup_enabled(name, default_enabled)
    local setting = settings.startup[name]
    if not setting then return default_enabled ~= false end
    return setting.value == "enabled" or setting.value == true
end

function tnt_boxes.is_enabled()
    return startup_enabled("the-cave-tnt-boxes", true)
end

function tnt_boxes.is_tnt_name(name)
    return TIERS[name] ~= nil
end

function tnt_boxes.configure(api)
    dig_handler = api and api.on_dig or nil
end

local function get_state()
    local state = storage[STORAGE_KEY]
    if type(state) ~= "table" then
        state = {}
        storage[STORAGE_KEY] = state
    end
    if type(state.active) ~= "table" then state.active = {} end
    if type(state.jobs) ~= "table" then state.jobs = {} end
    return state
end

local function render_object(render_id)
    if not render_id then return nil end
    return rendering.get_object_by_id(render_id)
end

local function destroy_render(render_id)
    local object = render_object(render_id)
    if object then object.destroy() end
end

local function draw_countdown(entity, tier, seconds)
    local object = rendering.draw_text {
        text = tostring(seconds),
        surface = entity.surface,
        target = { type = "entity", entity = entity, offset = { 0, -2.25 } },
        color = tier.color,
        scale = 1.5,
        font = "default-large-bold",
        alignment = "center",
        vertical_alignment = "middle",
        scale_with_zoom = true,
        draw_on_ground = false,
        only_in_alt_mode = false,
    }
    return object and object.id or nil
end

local function quality_name(entity)
    return entity.quality and entity.quality.name or "normal"
end

local function item_definition(name, quality)
    return { name = name, count = 1, quality = quality or "normal" }
end

local function spill(surface, position, force, definition)
    surface.spill_item_stack {
        position = position,
        stack = definition,
        enable_looted = true,
        force = force,
        allow_belts = false,
        use_start_position_on_failure = true,
        drop_full_stack = true,
    }
end

local function refund_placement(event, entity, definition)
    local player = event.player_index and game.get_player(event.player_index) or nil
    local robot = event.robot
    local platform = event.platform
    if robot and not robot.valid then robot = nil end
    if platform and not platform.valid then platform = nil end

    if player and player.valid then
        if player.insert(definition) == 1 then return player end
        spill(entity.surface, player.position, player.force, definition)
        return player
    end

    if robot then
        local inventory = robot.get_inventory(defines.inventory.robot_cargo)
        if inventory and inventory.insert(definition) == 1 then return robot.last_user end
        spill(entity.surface, robot.position, robot.force, definition)
        return robot.last_user
    end

    if platform then
        local hub = platform.hub
        local inventory = hub and hub.valid and hub.get_inventory(defines.inventory.hub_main) or nil
        if inventory and inventory.insert(definition) == 1 then return nil end
        local position = hub and hub.valid and hub.position or entity.position
        spill(entity.surface, position, entity.force, definition)
    end

    return nil
end

local function notify_player(player, position, message)
    if not (player and player.valid) then return end
    player.create_local_flying_text { text = message, position = position }
    player.print(message)
end

local function cancel_placement(event, entity, message, refund)
    local position = { x = entity.position.x, y = entity.position.y }
    local definition = item_definition(entity.name, quality_name(entity))
    local player
    if refund then player = refund_placement(event, entity, definition) end
    if entity.valid then
        entity.destroy { raise_destroy = false, do_cliff_correction = false }
    end
    notify_player(player, position, message)
end

local function prune_active(state)
    local count = 0
    for unit_number, record in pairs(state.active) do
        local entity = record.entity
        if entity and entity.valid and TIERS[entity.name] then
            count = count + 1
        else
            destroy_render(record.render_id)
            state.active[unit_number] = nil
        end
    end
    return count
end

local function register_box(entity, player_index, detonate_tick)
    local state = get_state()
    local tier = TIERS[entity.name]
    local unit_number = entity.unit_number
    if not (tier and unit_number) then return false end

    entity.destructible = false
    local seconds = math.max(1, math.ceil((detonate_tick - game.tick) / 60))
    state.active[unit_number] = {
        entity = entity,
        surface_index = entity.surface.index,
        player_index = player_index,
        force_name = entity.force and entity.force.name or nil,
        detonate_tick = detonate_tick,
        render_id = draw_countdown(entity, tier, seconds),
        shown_seconds = seconds,
    }
    return true
end

function tnt_boxes.on_built(event)
    local entity = event.entity or event.created_entity or event.destination
    if not (entity and entity.valid and TIERS[entity.name]) then return false end

    local state = get_state()
    if entity.unit_number and state.active[entity.unit_number] then return true end

    local player_build_event = event.name == defines.events.on_built_entity
        or (defines.events.on_space_platform_built_entity
            and event.name == defines.events.on_space_platform_built_entity)
    local player_built = player_build_event and event.player_index ~= nil
    if not tnt_boxes.is_enabled() then
        cancel_placement(event, entity, { "the-cave-tnt-boxes.unavailable" },
            player_built or event.robot ~= nil or event.platform ~= nil)
        return true
    end

    -- Construction robots, scripted builds, clones and platform automation do
    -- not own TNT placement. If a robot somehow receives a direct ghost order,
    -- cancel it transactionally and return the same-quality item.
    if not player_built then
        cancel_placement(event, entity, { "the-cave-tnt-boxes.player-placement-only" },
            event.robot ~= nil or event.platform ~= nil)
        return true
    end

    if prune_active(state) >= MAX_ACTIVE_BOXES then
        cancel_placement(event, entity, { "the-cave-tnt-boxes.maximum-active", MAX_ACTIVE_BOXES }, true)
        return true
    end

    if not register_box(entity, event.player_index, game.tick + COUNTDOWN_TICKS) then
        cancel_placement(event, entity, { "the-cave-tnt-boxes.registration-failed" }, true)
    end
    return true
end

function tnt_boxes.on_removed(event)
    local entity = event and event.entity
    if not (entity and TIERS[entity.name]) then return false end
    local state = get_state()
    local unit_number = entity.unit_number
    local record = unit_number and state.active[unit_number] or nil
    if record then
        destroy_render(record.render_id)
        state.active[unit_number] = nil
    end
    return true
end

local function create_visual_explosion(surface, position, tier)
    surface.create_entity {
        name = "grenade-explosion",
        position = position,
        create_build_effect_smoke = false,
    }
    for ring_index, ring in ipairs(tier.visual_rings) do
        local phase = ring_index * 0.41
        for index = 1, ring.count do
            local angle = phase + (index - 1) * (math.pi * 2 / ring.count)
            surface.create_entity {
                name = "grenade-explosion",
                position = {
                    x = position.x + math.cos(angle) * ring.radius,
                    y = position.y + math.sin(angle) * ring.radius,
                },
                create_build_effect_smoke = false,
            }
        end
    end
end

local function targets_in_circle(surface, position, radius)
    local targets = {}
    local radius_squared = radius * radius
    local entities = surface.find_entities_filtered {
        position = position,
        radius = radius,
        name = COVER_NAMES,
    }
    for _, entity in pairs(entities) do
        if entity.valid then
            local dx = entity.position.x - position.x
            local dy = entity.position.y - position.y
            local distance_squared = dx * dx + dy * dy
            if distance_squared <= radius_squared then
                targets[#targets + 1] = {
                    name = entity.name,
                    position = { x = entity.position.x, y = entity.position.y },
                    distance_squared = distance_squared,
                    unit_number = entity.unit_number or 0,
                }
            end
        end
    end
    table.sort(targets, function(a, b)
        if a.distance_squared ~= b.distance_squared then
            return a.distance_squared < b.distance_squared
        end
        if a.position.y ~= b.position.y then return a.position.y < b.position.y end
        if a.position.x ~= b.position.x then return a.position.x < b.position.x end
        return a.unit_number < b.unit_number
    end)
    return targets
end

local function detonate(state, unit_number, record)
    local entity = record.entity
    if not (entity and entity.valid) then
        destroy_render(record.render_id)
        state.active[unit_number] = nil
        return
    end

    local tier = TIERS[entity.name]
    local surface = entity.surface
    local position = { x = entity.position.x, y = entity.position.y }
    local targets = targets_in_circle(surface, position, tier.radius)
    local force_name = entity.force and entity.force.name or record.force_name

    destroy_render(record.render_id)
    state.active[unit_number] = nil
    create_visual_explosion(surface, position, tier)
    entity.destroy { raise_destroy = false, do_cliff_correction = false }

    if #targets > 0 then
        state.jobs[#state.jobs + 1] = {
            surface_index = surface.index,
            player_index = record.player_index,
            force_name = force_name,
            targets = targets,
            next_target = 1,
        }
    end
end

local function current_player_index(player_index)
    if not player_index then return nil end
    local player = game.get_player(player_index)
    return player and player.valid and player.index or nil
end

local function target_entity(surface, target)
    local entities = surface.find_entities_filtered {
        position = target.position,
        radius = 0.1,
        name = target.name,
        limit = 1,
    }
    return entities[1]
end

local function process_jobs(state)
    if #state.jobs == 0 then return end
    if not dig_handler then error("The Cave TNT Boxes: Dig callback is not configured") end

    local remaining = ROCKS_PER_TICK
    while remaining > 0 and #state.jobs > 0 do
        local job = state.jobs[1]
        local surface = game.surfaces[job.surface_index]
        if not (surface and surface.valid) then
            table.remove(state.jobs, 1)
        else
            local target = job.targets[job.next_target]
            if not target then
                table.remove(state.jobs, 1)
            else
                job.next_target = job.next_target + 1
                remaining = remaining - 1
                local entity = target_entity(surface, target)
                if entity and entity.valid then
                    local force = job.force_name and game.forces[job.force_name] or nil
                    dig_handler {
                        entity = entity,
                        force = force,
                        player_index = current_player_index(job.player_index),
                        the_cave_tnt_box = true,
                    }
                    if entity.valid then
                        entity.destroy { raise_destroy = false, do_cliff_correction = false }
                    end
                end
            end
        end
    end
end

function tnt_boxes.on_tick(event)
    local state = get_state()
    local now = event.tick
    local due = {}

    for unit_number, record in pairs(state.active) do
        local entity = record.entity
        if not (entity and entity.valid and TIERS[entity.name]) then
            destroy_render(record.render_id)
            state.active[unit_number] = nil
        elseif now >= record.detonate_tick then
            due[#due + 1] = unit_number
        else
            local seconds = math.max(1, math.ceil((record.detonate_tick - now) / 60))
            if seconds ~= record.shown_seconds then
                local object = render_object(record.render_id)
                if object then
                    object.text = tostring(seconds)
                else
                    record.render_id = draw_countdown(entity, TIERS[entity.name], seconds)
                end
                record.shown_seconds = seconds
            end
        end
    end

    table.sort(due)
    for _, unit_number in ipairs(due) do
        local record = state.active[unit_number]
        if record then detonate(state, unit_number, record) end
    end

    process_jobs(state)
end

local function reset_state()
    local old = storage[STORAGE_KEY]
    if type(old) == "table" and type(old.active) == "table" then
        for _, record in pairs(old.active) do destroy_render(record.render_id) end
    end
    storage[STORAGE_KEY] = { active = {}, jobs = {} }
end

local function find_existing_boxes()
    local entities = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            for _, entity in pairs(surface.find_entities_filtered { name = tnt_boxes.entity_names }) do
                entities[#entities + 1] = entity
            end
        end
    end
    table.sort(entities, function(a, b)
        return (a.unit_number or 0) < (b.unit_number or 0)
    end)
    return entities
end

local function adopt_existing_boxes()
    if not tnt_boxes.is_enabled() then return end
    local state = get_state()
    local active_count = prune_active(state)
    for _, entity in ipairs(find_existing_boxes()) do
        if entity.valid and not state.active[entity.unit_number] then
            if active_count < MAX_ACTIVE_BOXES then
                if register_box(entity, nil, game.tick + COUNTDOWN_TICKS) then
                    active_count = active_count + 1
                end
            else
                local definition = item_definition(entity.name, quality_name(entity))
                local surface, position, force = entity.surface, entity.position, entity.force
                entity.destroy { raise_destroy = false, do_cliff_correction = false }
                spill(surface, position, force, definition)
            end
        end
    end
end

function tnt_boxes.on_init()
    reset_state()
    adopt_existing_boxes()
end

function tnt_boxes.on_configuration_changed()
    if not tnt_boxes.is_enabled() then
        reset_state()
        return
    end
    get_state()
    adopt_existing_boxes()
end

function tnt_boxes.on_surface_deleted(event)
    local state = get_state()
    for unit_number, record in pairs(state.active) do
        if record.surface_index == event.surface_index then
            destroy_render(record.render_id)
            state.active[unit_number] = nil
        end
    end
    local kept = {}
    for _, job in ipairs(state.jobs) do
        if job.surface_index ~= event.surface_index then kept[#kept + 1] = job end
    end
    state.jobs = kept
end

function tnt_boxes.on_player_removed(event)
    local state = get_state()
    for _, record in pairs(state.active) do
        if record.player_index == event.player_index then record.player_index = nil end
    end
    for _, job in ipairs(state.jobs) do
        if job.player_index == event.player_index then job.player_index = nil end
    end
end

return tnt_boxes
