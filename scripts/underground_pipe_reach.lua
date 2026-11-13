local settings = require("scripts.game_settings").proxy(settings)

-- The Cave: research-gated Underground Pipe Reach runtime.
--
-- Level 0 uses the untouched official Factorio pipe-to-ground item/entity, so
-- the native placement guide and connection limit remain exactly 10 tiles.
-- After research, the official item is changed only while it is in a player's
-- cursor to a hidden, placement item whose place_result is the matching
-- hidden entity variant. The engine therefore draws and enforces the real
-- researched distance natively.
--
-- Mining, smart pipette, blueprints and construction robots continue to use
-- the original pipe-to-ground item through each variant entity's placeable_by
-- and minable definitions. Newly built entities are always clamped to the
-- current force research level, so blueprints cannot bypass research.

local M = {}

local SETTING_NAME = "the-cave-underground-pipe-reach-research"
local TECH_PREFIX = "the-cave-underground-pipe-reach-"
local LEVELS = 7
local BASE_NAME = "pipe-to-ground"

local function feature_enabled()
    local setting = settings and settings.startup and settings.startup[SETTING_NAME]
    if not setting then return true end
    return setting.value == "enabled" or setting.value == true
end

local function entity_variant_name(level)
    if level <= 0 then return BASE_NAME end
    return "the-cave-upr-" .. BASE_NAME .. "-" .. tostring(level)
end

local function item_variant_name(level)
    if level <= 0 then return BASE_NAME end
    return "the-cave-upr-item-" .. BASE_NAME .. "-" .. tostring(level)
end

local function base_and_entity_level(name)
    if name == BASE_NAME then return BASE_NAME, 0 end
    if not name then return nil, nil end
    local level = tonumber(name:match("^the%-cave%-upr%-pipe%-to%-ground%-(%d+)$"))
    if level and level >= 1 and level <= LEVELS then return BASE_NAME, level end
    return nil, nil
end

local function base_and_item_level(name)
    if name == BASE_NAME then return BASE_NAME, 0 end
    if not name then return nil, nil end
    local level = tonumber(name:match("^the%-cave%-upr%-item%-pipe%-to%-ground%-(%d+)$"))
    if level and level >= 1 and level <= LEVELS then return BASE_NAME, level end
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
    storage.the_cave_upr_cursor_states = storage.the_cave_upr_cursor_states or {}
    storage.the_cave_upr_cursor_queue = storage.the_cave_upr_cursor_queue or {}
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
    storage.the_cave_upr_cursor_queue[player_index] = true
end

local restore_player_cursor

local function synchronise_player_cursor(player_index)
    ensure_storage()
    local player = game.get_player(player_index)
    if not (player and player.valid) then
        storage.the_cave_upr_cursor_states[player_index] = nil
        return
    end

    if player.opened then restore_player_cursor(player_index); return end

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
                storage.the_cave_upr_cursor_states[player_index] = nil
            end
        end
        return
    end

    local desired_item = item_variant_name(desired_level)
    if not item_prototype_exists(desired_item) then return end

    if not current_is_hidden or current_level ~= desired_level then
        if not set_cursor_stack(stack, desired_item, count, quality) then return end
    end
end

restore_player_cursor = function(player_index)
    ensure_storage()
    local player = game.get_player(player_index)
    local state = storage.the_cave_upr_cursor_states[player_index]
    if not (player and player.valid) then
        storage.the_cave_upr_cursor_states[player_index] = nil
        storage.the_cave_upr_cursor_queue[player_index] = nil
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
            storage.the_cave_upr_cursor_states[player_index] = nil
            storage.the_cave_upr_cursor_queue[player_index] = nil
            return
        end
    end

    refund_state(player, state)
    storage.the_cave_upr_cursor_states[player_index] = nil
    storage.the_cave_upr_cursor_queue[player_index] = nil
end

local function read_entity_quality(entity)
    local ok, quality = pcall(function() return entity.quality end)
    return ok and quality_name(quality) or nil
end

local function copy_fluid(fluid)
    if not fluid then return nil end
    local result = {
        name = fluid.name,
        amount = fluid.amount,
        temperature = fluid.temperature,
    }
    local quality = quality_name(fluid.quality)
    if quality then result.quality = quality end
    return result
end

local function read_fluids(entity)
    local result = {}
    pcall(function()
        for index = 1, entity.fluids_count do
            local fluid = entity.get_fluid(index)
            if fluid then result[index] = copy_fluid(fluid) end
        end
    end)
    return result
end

local function restore_fluids(entity, fluids)
    if not (entity and entity.valid and fluids) then return end
    pcall(function()
        for index, fluid in pairs(fluids) do
            entity.set_fluid(index, fluid)
        end
    end)
end

local function replace_entity(entity, target_name)
    if not (entity and entity.valid and target_name and entity_prototype_exists(target_name)) then
        return entity
    end
    if entity.name == target_name then return entity end

    local snapshot = {
        name = entity.name,
        surface = entity.surface,
        position = { x = entity.position.x, y = entity.position.y },
        direction = entity.direction,
        force = entity.force,
        quality = read_entity_quality(entity),
        health = entity.health,
        fluids = read_fluids(entity),
    }

    local params = {
        name = target_name,
        position = snapshot.position,
        direction = snapshot.direction,
        force = snapshot.force,
        create_build_effect_smoke = false,
        raise_built = false,
    }
    if snapshot.quality then params.quality = snapshot.quality end

    entity.destroy({ raise_destroy = false })
    local ok_create, replacement = pcall(function()
        return snapshot.surface.create_entity(params)
    end)

    if not ok_create or not (replacement and replacement.valid) then
        params.name = snapshot.name
        local ok_restore, restored = pcall(function()
            return snapshot.surface.create_entity(params)
        end)
        if ok_restore and restored and restored.valid then
            restore_fluids(restored, snapshot.fluids)
            if snapshot.health and restored.health then
                local maximum = restored.max_health
                restored.health = maximum and math.min(snapshot.health, maximum) or snapshot.health
            end
            return restored
        end
        return nil
    end

    restore_fluids(replacement, snapshot.fluids)
    if snapshot.health and replacement.health then
        local maximum = replacement.max_health
        replacement.health = maximum and math.min(snapshot.health, maximum) or snapshot.health
    end
    return replacement
end

local function normalise_blueprint_holder(holder)
    if not holder then return false end

    local ok_read, entities = pcall(function()
        return holder.get_blueprint_entities()
    end)
    if not ok_read or not entities then return false end

    local changed = false
    for _, blueprint_entity in pairs(entities) do
        local _, level = base_and_entity_level(blueprint_entity.name)
        if level and level > 0 then
            blueprint_entity.name = BASE_NAME
            changed = true
        end
    end

    if not changed then return false end
    local ok_write = pcall(function()
        holder.set_blueprint_entities(entities)
    end)
    return ok_write
end

local function normalise_all_variants()
    if feature_enabled() then return end

    local names = {}
    for level = 1, LEVELS do names[#names + 1] = entity_variant_name(level) end

    for _, surface in pairs(game.surfaces or {}) do
        local entities = surface.find_entities_filtered({ name = names })
        for _, entity in pairs(entities) do
            if entity and entity.valid then replace_entity(entity, BASE_NAME) end
        end
    end
end

function M.on_init()
    ensure_storage()
    for _, player in pairs(game.players or {}) do queue_player(player.index) end
end

function M.on_configuration_changed()
    ensure_storage()
    for _, player in pairs(game.players or {}) do restore_player_cursor(player.index) end
    storage.the_cave_upr_cursor_queue = {}
    normalise_all_variants()
    for _, player in pairs(game.players or {}) do queue_player(player.index) end
end

function M.on_tick(_event)
    ensure_storage()
    local queued = storage.the_cave_upr_cursor_queue
    if not next(queued) then return end
    storage.the_cave_upr_cursor_queue = {}
    for player_index in pairs(queued) do synchronise_player_cursor(player_index) end
end

function M.synchronise_entity(entity)
    if not (entity and entity.valid and base_and_entity_level(entity.name)) then return end
    if entity.to_be_upgraded() then return end
    local target = entity_variant_name(force_level(entity.force))
    if not entity_prototype_exists(target) then target=BASE_NAME end
    return replace_entity(entity, target)
end

function M.on_built(event)
    local entity = event and (event.entity or event.created_entity)
    if not (entity and entity.valid) then return end
    if entity.name == "entity-ghost" or entity.type ~= "pipe-to-ground" then return end

    local base_name = base_and_entity_level(entity.name)
    if not base_name then return end

    local wanted_level = force_level(entity.force)
    local wanted_name = entity_variant_name(wanted_level)
    if not entity_prototype_exists(wanted_name) then wanted_name = BASE_NAME end
    replace_entity(entity, wanted_name)

    if event.player_index then queue_player(event.player_index) end
end

function M.on_player_setup_blueprint(event)
    if not event then return end
    -- Never store the hidden reach prototype in a newly created blueprint or
    -- blueprint-book record. The normal Pipe to Ground name keeps blueprints
    -- portable; construction is clamped to the destination force at build time.
    normalise_blueprint_holder(event.stack)
    normalise_blueprint_holder(event.record)
end

function M.on_player_configured_blueprint(event)
    if not (event and event.player_index) then return end
    local player = game.get_player(event.player_index)
    if player and player.valid then normalise_blueprint_holder(player.cursor_stack) end
end

function M.on_gui_opened(event)
    if event.player_index then restore_player_cursor(event.player_index) end
end

function M.on_gui_closed(event)
    if event.player_index then queue_player(event.player_index) end
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
    storage.the_cave_upr_cursor_states[event.player_index] = nil
    storage.the_cave_upr_cursor_queue[event.player_index] = nil
end

return M
