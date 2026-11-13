local settings = require("scripts.game_settings").proxy(settings)

-- The Cave: research-gated Underground Belt Reach runtime.
--
-- Level 0 uses the untouched official Factorio item/entity. Levels 1-7 use
-- separate entity prototypes for every official belt tier. Each level has a
-- native Upgrade Planner row (yellow -> red -> blue -> Turbo), while research
-- synchronises the same tier vertically to the force's new reach level.
--
-- Placement still uses hidden placement items so Factorio draws and enforces
-- the real researched underground distance. Mining, smart pipette, blueprints,
-- ghosts and robots continue to request the official visible belt items.

local M = {}

local SETTING_NAME = "the-cave-underground-belt-reach-research"
local TECH_PREFIX = "the-cave-underground-belt-reach-"
local LEVELS = 7
local OFFICIAL_BELTS = {
    "underground-belt",
    "fast-underground-belt",
    "express-underground-belt",
    "turbo-underground-belt",
}
local BASE_BELTS = {}
for _, name in ipairs(OFFICIAL_BELTS) do BASE_BELTS[name] = true end

local function feature_enabled()
    local setting = settings and settings.startup and settings.startup[SETTING_NAME]
    if not setting then return true end
    return setting.value == "enabled" or setting.value == true
end

local function entity_variant_name(base_name, level)
    if level <= 0 then return base_name end
    return "the-cave-ubr-" .. base_name .. "-" .. tostring(level)
end

local function item_variant_name(base_name, level)
    if level <= 0 then return base_name end
    return "the-cave-ubr-item-" .. base_name .. "-" .. tostring(level)
end

local function base_and_entity_level(name)
    if BASE_BELTS[name] then return name, 0 end
    if not name then return nil, nil end
    local base, level = name:match("^the%-cave%-ubr%-(.+)%-(%d+)$")
    level = tonumber(level)
    if base and BASE_BELTS[base] and level and level >= 1 and level <= LEVELS then
        return base, level
    end
    return nil, nil
end

local function base_and_item_level(name)
    if BASE_BELTS[name] then return name, 0 end
    if not name then return nil, nil end
    local base, level = name:match("^the%-cave%-ubr%-item%-(.+)%-(%d+)$")
    level = tonumber(level)
    if base and BASE_BELTS[base] and level and level >= 1 and level <= LEVELS then
        return base, level
    end
    return nil, nil
end

local function entity_prototype_exists(name)
    if prototypes and prototypes.entity then return prototypes.entity[name] ~= nil end
    if game and game.entity_prototypes then return game.entity_prototypes[name] ~= nil end
    return false
end

local function item_prototype_exists(name)
    if prototypes and prototypes.item then return prototypes.item[name] ~= nil end
    if game and game.item_prototypes then return game.item_prototypes[name] ~= nil end
    return false
end

local function force_level(force)
    if not feature_enabled() then return 0 end
    if not (force and force.valid and force.technologies) then return 0 end

    local level = 0
    for index = 1, LEVELS do
        local technology = force.technologies[TECH_PREFIX .. index]
        if technology and technology.researched then
            level = index
        else
            break
        end
    end
    return level
end

local function ensure_storage()
    storage.the_cave_ubr_cursor_states = storage.the_cave_ubr_cursor_states or {}
    storage.the_cave_ubr_cursor_queue = storage.the_cave_ubr_cursor_queue or {}
    storage.the_cave_ubr_level_sync_jobs = storage.the_cave_ubr_level_sync_jobs or {}
    storage.the_cave_ubr_inventory_gui_open = storage.the_cave_ubr_inventory_gui_open or {}
end

local function quality_name(value)
    if not value then return nil end
    if type(value) == "string" then return value end
    local ok, name = pcall(function() return value.name end)
    return ok and name or nil
end

local function stack_quality(stack)
    local ok, quality = pcall(function() return stack.quality end)
    if not ok then return nil end
    return quality_name(quality)
end

local function set_cursor_stack(stack, name, count, quality)
    if not stack then return false end
    local spec = { name = name, count = math.max(1, count or 1) }
    if quality then spec.quality = quality end
    local health = stack.valid_for_read and stack.health or 1
    local ok, result = pcall(function() return stack.set_stack(spec) end)
    if ok and result == true then stack.health = health end
    return ok and result == true
end

local function insert_or_spill(player, name, count, quality)
    if not (player and player.valid and name and count and count > 0) then return end

    local stack = { name = name, count = count }
    if quality then stack.quality = quality end

    local inserted = 0
    local ok_insert, result = pcall(function() return player.insert(stack) end)
    if ok_insert and type(result) == "number" then inserted = result end

    local remaining = count - inserted
    if remaining <= 0 then return end

    local spill = { name = name, count = remaining }
    if quality then spill.quality = quality end
    pcall(function()
        player.surface.spill_item_stack({
            position = player.position,
            stack = spill,
            force = player.force,
            allow_belts = false,
        })
    end)
end

local function refund_state(player, state)
    if state and state.base and (state.count or 0) > 0 then
        insert_or_spill(player, state.base, state.count, state.quality)
    end
end

local function queue_player(player_index)
    if not player_index then return end
    ensure_storage()
    storage.the_cave_ubr_cursor_queue[player_index] = true
end

local restore_player_cursor

local function synchronise_player_cursor(player_index)
    ensure_storage()
    local player = game.get_player(player_index)
    if not (player and player.valid) then
        storage.the_cave_ubr_cursor_states[player_index] = nil
        storage.the_cave_ubr_inventory_gui_open[player_index] = nil
        return
    end

    -- Never turn a normal belt stack into the internal placement item while an
    -- inventory-style GUI is open. Keeping the official item in hand
    -- preserves vanilla stack splitting and chest/inventory movement.
    if storage.the_cave_ubr_inventory_gui_open[player_index] then
        restore_player_cursor(player_index)
        return
    end

    local stack = player.cursor_stack
    local valid_for_read = stack and stack.valid_for_read
    local current_name = valid_for_read and stack.name or nil
    local current_base, current_level = base_and_item_level(current_name)
    local current_is_hidden = current_base ~= nil and current_level and current_level > 0

    if not valid_for_read or not current_base then return end

    local desired_level = force_level(player.force)
    local count = stack.count
    local quality = stack_quality(stack)

    if desired_level <= 0 then
        if current_is_hidden then
            if set_cursor_stack(stack, current_base, count, quality) then
                storage.the_cave_ubr_cursor_states[player_index] = nil
            end
        end
        return
    end

    local desired_item = item_variant_name(current_base, desired_level)
    if not item_prototype_exists(desired_item) then return end

    if not current_is_hidden or current_level ~= desired_level then
        if not set_cursor_stack(stack, desired_item, count, quality) then return end
    end
end

restore_player_cursor = function(player_index)
    ensure_storage()
    local player = game.get_player(player_index)
    local state = storage.the_cave_ubr_cursor_states[player_index]
    if not (player and player.valid) then
        storage.the_cave_ubr_cursor_states[player_index] = nil
        storage.the_cave_ubr_cursor_queue[player_index] = nil
        return
    end

    local stack = player.cursor_stack
    if stack and stack.valid_for_read then
        local base, level = base_and_item_level(stack.name)
        if base and level and level > 0 then
            local count = stack.count
            local quality = stack_quality(stack)
            if not set_cursor_stack(stack, base, count, quality) then
                insert_or_spill(player, base, count, quality)
                pcall(function() stack.clear() end)
            end
            storage.the_cave_ubr_cursor_states[player_index] = nil
            storage.the_cave_ubr_cursor_queue[player_index] = nil
            return
        end
    end

    refund_state(player, state)
    storage.the_cave_ubr_cursor_states[player_index] = nil
    storage.the_cave_ubr_cursor_queue[player_index] = nil
end

local function belt_type(entity)
    local ok, value = pcall(function() return entity.belt_to_ground_type end)
    return ok and value or nil
end

local function read_entity_quality(entity)
    local ok, quality = pcall(function() return entity.quality end)
    return ok and quality_name(quality) or nil
end

local function upgrade_entity_in_place(entity, target_name)
    if not (entity and entity.valid and target_name and entity_prototype_exists(target_name)) then
        return entity, nil
    end
    if entity.name == target_name then return entity, nil end

    -- Do not overwrite a real player/robot tier upgrade that is already queued.
    -- When that upgrade completes, on_built clamps the result to the force's
    -- current reach level without losing belt contents or the paired endpoint.
    local ok_pending, pending = pcall(function() return entity.to_be_upgraded() end)
    if ok_pending and pending then return entity, nil end

    local target = { name = target_name }
    local quality = read_entity_quality(entity)
    if quality then target.quality = quality end

    local ok_order, ordered = pcall(function()
        return entity.order_upgrade({ target = target, force = entity.force })
    end)
    if not ok_order or not ordered then return entity, nil end

    local ok_apply, first, second = pcall(function()
        return entity.apply_upgrade()
    end)
    if not ok_apply or not (first and first.valid) then
        pcall(function()
            if entity and entity.valid then entity.cancel_upgrade(entity.force) end
        end)
        return entity, nil
    end

    return first, second
end

local function normalise_blueprint_holder(holder)
    if not holder then return false end

    local ok_read, entities = pcall(function()
        return holder.get_blueprint_entities()
    end)
    if not ok_read or not entities then return false end

    local changed = false
    for _, blueprint_entity in pairs(entities) do
        local base_name, level = base_and_entity_level(blueprint_entity.name)
        if base_name and level and level > 0 then
            blueprint_entity.name = base_name
            changed = true
        end
    end

    if not changed then return false end
    local ok_write = pcall(function()
        holder.set_blueprint_entities(entities)
    end)
    return ok_write
end

local function all_entity_names()
    local names = {}
    for _, base_name in ipairs(OFFICIAL_BELTS) do
        if entity_prototype_exists(base_name) then names[#names + 1] = base_name end
        for level = 1, LEVELS do
            local name = entity_variant_name(base_name, level)
            if entity_prototype_exists(name) then names[#names + 1] = name end
        end
    end
    return names
end

local function entity_at_descriptor(descriptor, force)
    local surface = descriptor and game.get_surface(descriptor.surface_index)
    if not (surface and force and force.valid) then return nil end

    local entities = surface.find_entities_filtered({
        position = { descriptor.x, descriptor.y },
        type = "underground-belt",
        force = force,
    })
    for _, entity in pairs(entities) do
        if entity and entity.valid then
            local base_name = base_and_entity_level(entity.name)
            if base_name then return entity end
        end
    end
    return nil
end

local function synchronise_entity_level(entity, target_level)
    if not (entity and entity.valid) then return end
    local base_name, current_level = base_and_entity_level(entity.name)
    if not base_name then return end

    local target_name = entity_variant_name(base_name, target_level)
    if not entity_prototype_exists(target_name) then target_name = base_name end
    if entity.name == target_name then return end

    upgrade_entity_in_place(entity, target_name)
end

local function enqueue_force_level_sync(force)
    if not (force and force.valid) then return end
    ensure_storage()

    local descriptors = {}
    local names = all_entity_names()
    local surfaces = {}
    for _, surface in pairs(game.surfaces or {}) do surfaces[#surfaces + 1] = surface end
    table.sort(surfaces, function(a, b) return a.index < b.index end)

    for _, surface in ipairs(surfaces) do
        local entities = surface.find_entities_filtered({ name = names, force = force })
        for _, entity in pairs(entities) do
            if entity and entity.valid then
                descriptors[#descriptors + 1] = {
                    surface_index = surface.index,
                    x = entity.position.x,
                    y = entity.position.y,
                }
            end
        end
    end
    table.sort(descriptors, function(a, b)
        if a.surface_index ~= b.surface_index then return a.surface_index < b.surface_index end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)

    storage.the_cave_ubr_level_sync_jobs[force.index] = {
        force_index = force.index,
        target_level = force_level(force),
        cursor = 1,
        descriptors = descriptors,
    }
end

local function process_level_sync_jobs()
    ensure_storage()
    local jobs = storage.the_cave_ubr_level_sync_jobs
    local budget = 128

    for force_index, job in pairs(jobs) do
        local force = game.forces[force_index]
        if not (force and force.valid) then
            jobs[force_index] = nil
        else
            while budget > 0 and job.cursor <= #job.descriptors do
                local descriptor = job.descriptors[job.cursor]
                job.cursor = job.cursor + 1
                budget = budget - 1

                local entity = entity_at_descriptor(descriptor, force)
                if entity and entity.valid then
                    synchronise_entity_level(entity, job.target_level)
                end
            end

            if job.cursor > #job.descriptors then jobs[force_index] = nil end
            if budget <= 0 then break end
        end
    end
end

-- Upgrade Planner handling is now entirely native. The level-specific entity
-- prototypes are valid, visible upgrade sources with same-level next_upgrade
-- targets, so the old cursor-stack/area-selection workaround must stay absent.
function M.on_player_selected_area(_event)
end

function M.on_player_reverse_selected_area(_event)
end

function M.on_player_alt_selected_area(_event)
end

function M.on_player_setup_blueprint(event)
    if not event then return end
    normalise_blueprint_holder(event.stack)
    normalise_blueprint_holder(event.record)
end

function M.on_player_configured_blueprint(event)
    if not (event and event.player_index) then return end
    local player = game.get_player(event.player_index)
    if player and player.valid then normalise_blueprint_holder(player.cursor_stack) end
end

function M.on_init()
    ensure_storage()
    for _, player in pairs(game.players or {}) do queue_player(player.index) end
end

function M.on_configuration_changed()
    ensure_storage()
    for _, player in pairs(game.players or {}) do restore_player_cursor(player.index) end
    storage.the_cave_ubr_cursor_queue = {}
    storage.the_cave_ubr_level_sync_jobs = {}
    for _, player in pairs(game.players or {}) do queue_player(player.index) end
    -- Always normalise existing entities after a configuration change. When
    -- the Startup feature is disabled, force_level() returns 0 and every
    -- internal variant is safely converted back to its official prototype.
    for _, force in pairs(game.forces or {}) do enqueue_force_level_sync(force) end
end

function M.on_tick(_event)
    ensure_storage()

    local queued = storage.the_cave_ubr_cursor_queue
    if next(queued) then
        storage.the_cave_ubr_cursor_queue = {}
        for player_index in pairs(queued) do synchronise_player_cursor(player_index) end
    end

    if next(storage.the_cave_ubr_level_sync_jobs) then process_level_sync_jobs() end
end

function M.on_built(event)
    local entity = event and (event.entity or event.created_entity)
    if not (entity and entity.valid) then return end
    if entity.name == "entity-ghost" or entity.type ~= "underground-belt" then return end

    local base_name = base_and_entity_level(entity.name)
    if not base_name then return end

    local wanted_level = force_level(entity.force)
    local wanted_name = entity_variant_name(base_name, wanted_level)
    if not entity_prototype_exists(wanted_name) then wanted_name = base_name end
    upgrade_entity_in_place(entity, wanted_name)

    if event.player_index then queue_player(event.player_index) end
end

function M.on_gui_opened(event)
    if not (event and event.player_index) then return end
    ensure_storage()
    storage.the_cave_ubr_inventory_gui_open[event.player_index] = true
    -- This is immediate rather than queued so the very first click into a
    -- chest or inventory sees the official transferable item stack.
    restore_player_cursor(event.player_index)
end

function M.on_gui_closed(event)
    if not (event and event.player_index) then return end
    ensure_storage()
    storage.the_cave_ubr_inventory_gui_open[event.player_index] = nil
    -- If the player is still holding an official underground belt after the
    -- GUI closes, restore the researched placement preview on the next tick.
    queue_player(event.player_index)
end

function M.on_player_cursor_stack_changed(event)
    if event and event.player_index then queue_player(event.player_index) end
end

function M.on_player_created(event)
    if event and event.player_index then queue_player(event.player_index) end
end

function M.on_player_joined_game(event)
    if event and event.player_index then queue_player(event.player_index) end
end

function M.on_player_changed_force(event)
    if event and event.player_index then queue_player(event.player_index) end
end

function M.on_research_finished(event)
    local research = event and event.research
    if not (research and research.name and research.name:find(TECH_PREFIX, 1, true) == 1) then return end
    for _, player in pairs(research.force.players or {}) do queue_player(player.index) end
    enqueue_force_level_sync(research.force)
end

function M.on_research_reversed(event)
    M.on_research_finished(event)
end

function M.on_player_left_game(event)
    if event and event.player_index then restore_player_cursor(event.player_index) end
end

function M.on_pre_player_died(event)
    if event and event.player_index then restore_player_cursor(event.player_index) end
end

function M.on_player_removed(event)
    if not (event and event.player_index) then return end
    ensure_storage()
    storage.the_cave_ubr_cursor_states[event.player_index] = nil
    storage.the_cave_ubr_cursor_queue[event.player_index] = nil
    storage.the_cave_ubr_inventory_gui_open[event.player_index] = nil
end

-- Kept as a no-op compatibility entry point for older The Cave control.lua
-- integrations. Rotation is handled natively by the placed variant entity.
function M.on_player_rotated_entity(_event)
end

return M
