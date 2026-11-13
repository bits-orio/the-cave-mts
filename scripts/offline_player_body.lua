local settings = require("scripts.game_settings").proxy(settings)

-- The Cave: recoverable offline-player bodies for multiplayer servers.
--
-- Players are kicked after five minutes of Factorio-reported inactivity. A
-- separate five-minute offline grace period begins after any disconnect,
-- including an AFK kick. Rejoining before that deadline cancels recovery.
-- After the grace period, every occupied personal item stack is moved into a
-- permanent character corpse near the live Main Train when Train Interiors is
-- active, or at the normal force spawn point otherwise.
--
-- Reliability notes:
--   * Both pre-leave and post-leave events schedule the timer.
--   * A periodic reconciliation pass catches players whose disconnect event was
--     missed (for example, when installing/updating while somebody is offline).
--   * Direct character-corpse creation is attempted at many deterministic
--     recovery positions so a crowded destination cannot silently block it.
--   * Stack movement is transactional and uses swap_stack to preserve all item
--     metadata, including armor grids, blueprints, quality, durability and tags.

local offline_player_body = {}
local train_interiors = require("scripts.train_interiors")
local cave_worlds = require("scripts.cave_worlds")
local cave_teams = require("scripts.cave_teams")

local SETTING_NAME = "the-cave-offline-player-body"
local FIVE_MINUTES_TICKS = 5 * 60 * 60
local AFK_CHECK_INTERVAL_TICKS = 60
local RETRY_DELAY_TICKS = 60 * 60
local RECONCILE_INTERVAL_TICKS = 10 * 60
local MAX_RECOVERY_SEARCH_RADIUS = 48
local RECOVERY_SEARCH_STEP = 2

-- Main inventory is emptied before armor is removed. Armor is deliberately
-- transferred last so removing an armor inventory-size bonus cannot invalidate
-- occupied main-inventory slots. Rollback runs in reverse and restores armor
-- before restoring any main-inventory slots.
local PERSONAL_INVENTORIES = {
    defines.inventory.character_main,
    defines.inventory.character_guns,
    defines.inventory.character_ammo,
    defines.inventory.character_trash,
    defines.inventory.character_armor,
}

local function enabled()
    local setting = settings and settings.startup and settings.startup[SETTING_NAME]
    return setting and setting.value == "enabled"
end

local function root()
    storage.the_cave_offline_player_body = storage.the_cave_offline_player_body or {}
    local state = storage.the_cave_offline_player_body
    state.pending = state.pending or {}
    state.offline_since = state.offline_since or {}
    state.processed = state.processed or {}
    state.afk_kick_requested = state.afk_kick_requested or {}
    state.last_worlds = state.last_worlds or {}
    state.next_due_tick = tonumber(state.next_due_tick) or nil
    state.last_reconcile_tick = tonumber(state.last_reconcile_tick) or 0
    return state
end

local function notify_admins(message)
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.admin then
            player.print(message)
        end
    end
end

local function get_inventory(player, inventory_id)
    local ok, inventory

    -- For disconnected players the public main-inventory accessor is the most
    -- reliable route because their character is stashed by the engine.
    if inventory_id == defines.inventory.character_main then
        ok, inventory = pcall(function()
            return player.get_main_inventory()
        end)
    else
        ok, inventory = pcall(function()
            return player.get_inventory(inventory_id)
        end)
    end

    if not ok or not (inventory and inventory.valid) then
        return nil
    end
    return inventory
end

local function get_source_stack(player, source)
    if source.cursor then
        local ok, stack = pcall(function()
            return player.cursor_stack
        end)
        if ok and stack and stack.valid then
            return stack
        end
        return nil
    end

    local inventory = get_inventory(player, source.inventory_id)
    if not inventory or source.slot_index < 1 or source.slot_index > #inventory then
        return nil
    end

    local stack = inventory[source.slot_index]
    if stack and stack.valid then
        return stack
    end
    return nil
end

local function collect_sources(player)
    local sources = {}

    for _, inventory_id in ipairs(PERSONAL_INVENTORIES) do
        local inventory = get_inventory(player, inventory_id)
        if inventory then
            for slot_index = 1, #inventory do
                local stack = inventory[slot_index]
                if stack and stack.valid_for_read then
                    sources[#sources + 1] = {
                        inventory_id = inventory_id,
                        slot_index = slot_index,
                    }
                end
            end
        end
    end

    local ok, cursor = pcall(function()
        return player.cursor_stack
    end)
    if ok and cursor and cursor.valid and cursor.valid_for_read then
        sources[#sources + 1] = { cursor = true }
    end

    return sources
end

local function remember_world(player)
    if not (player and player.valid) then return end
    local force = cave_teams.player_force(player)
    local home = force and cave_teams.home_surface(force)
    local character = player.character
    local surface = character and character.valid and character.surface
    if not (home and surface and surface.valid and surface.index == home.index
        and cave_worlds.is_cave_world(surface) and not cave_worlds.is_template(surface)) then return end
    root().last_worlds[player.index] = {
        surface_index = surface.index,
        name = surface.name,
        force_index = force.index,
    }
end

local function append_spawn_ring(positions, spawn, radius)
    if radius == 0 then
        positions[#positions + 1] = { x = spawn.x, y = spawn.y }
        return
    end

    -- Deterministic clockwise square ring. Two-tile spacing keeps multiple
    -- offline bodies separately selectable around the chosen recovery point.
    for dx = -radius, radius, RECOVERY_SEARCH_STEP do
        positions[#positions + 1] = { x = spawn.x + dx, y = spawn.y - radius }
    end
    for dy = -radius + RECOVERY_SEARCH_STEP, radius, RECOVERY_SEARCH_STEP do
        positions[#positions + 1] = { x = spawn.x + radius, y = spawn.y + dy }
    end
    for dx = radius - RECOVERY_SEARCH_STEP, -radius, -RECOVERY_SEARCH_STEP do
        positions[#positions + 1] = { x = spawn.x + dx, y = spawn.y + radius }
    end
    for dy = radius - RECOVERY_SEARCH_STEP, -radius + RECOVERY_SEARCH_STEP, -RECOVERY_SEARCH_STEP do
        positions[#positions + 1] = { x = spawn.x - radius, y = spawn.y + dy }
    end
end

local function build_recovery_positions(center, player_index)
    local positions = {}

    for radius = 0, MAX_RECOVERY_SEARCH_RADIUS, RECOVERY_SEARCH_STEP do
        append_spawn_ring(positions, center, radius)
    end

    -- Rotate the deterministic list per player so simultaneous disconnects do
    -- not always compete for exactly the same first recovery position.
    if #positions > 1 then
        local offset = (math.max(1, tonumber(player_index) or 1) - 1) % #positions
        if offset > 0 then
            local rotated = {}
            for index = 1, #positions do
                rotated[index] = positions[((index + offset - 1) % #positions) + 1]
            end
            positions = rotated
        end
    end

    return positions
end

local function create_recovery_corpse(surface, force, player, inventory_size, center)
    local positions = build_recovery_positions(center, player.index)

    for _, position in ipairs(positions) do
        local occupied = surface.count_entities_filtered {
            name = "character-corpse",
            position = position,
            radius = 0.70,
            limit = 1,
        }

        if occupied == 0 then
            local ok, corpse = pcall(function()
                return surface.create_entity {
                    name = "character-corpse",
                    position = position,
                    force = force,
                    inventory_size = inventory_size,
                    player_index = player.index,
                    color = player.color,
                    preserve_ghosts_and_corpses = true,
                }
            end)

            if ok and corpse and corpse.valid then
                return corpse, position
            end
        end
    end

    return nil, nil
end

local function recovery_destination(player)
    local force = cave_teams.player_force(player)
    local home = force and cave_teams.home_surface(force)
    if not (force and force.valid and home and home.valid
        and cave_worlds.is_cave_world(home) and not cave_worlds.is_template(home)) then
        return nil, nil, nil, nil
    end

    local remembered = root().last_worlds[player.index]
    local surface = remembered and game.get_surface(remembered.surface_index)
    if not (surface and surface.valid and surface.name == remembered.name
        and remembered.force_index == force.index and surface.index == home.index) then
        surface = home
    end

    if train_interiors and train_interiors.get_player_recovery_target then
        local target = train_interiors.get_player_recovery_target(player)
        if target and target.surface and target.surface.valid and target.position
            and target.surface.index == surface.index then
            return target.surface, target.position, "train", force
        end
    end
    return surface, force.get_spawn_position(surface), "spawn", force
end

local function protect_corpse(corpse, player)
    pcall(function() corpse.corpse_expires = false end)
    pcall(function() corpse.corpse_immune_to_entity_placement = true end)
    pcall(function() corpse.character_corpse_player_index = player.index end)
    pcall(function() corpse.character_corpse_tick_of_death = game.tick end)
    pcall(function()
        corpse.character_corpse_death_cause = {
            "the-cave-offline-player-body.death-cause",
            player.name,
        }
    end)
end

local function rollback_transfer(player, corpse_inventory, moved)
    local complete = true

    for index = #moved, 1, -1 do
        local record = moved[index]
        local source_stack = get_source_stack(player, record.source)
        local corpse_stack = corpse_inventory[record.corpse_slot]

        if not (source_stack and source_stack.valid and corpse_stack and corpse_stack.valid) then
            complete = false
        elseif source_stack.valid_for_read or not corpse_stack.valid_for_read then
            complete = false
        else
            local ok, swapped = pcall(function()
                return source_stack.swap_stack(corpse_stack)
            end)
            if not ok or not swapped then
                complete = false
            end
        end
    end

    return complete
end

local function move_player_inventory_to_recovery(player)
    local sources = collect_sources(player)
    if #sources == 0 then
        return "empty", 0, "no-items"
    end

    local surface, center, destination_kind, force = recovery_destination(player)
    if not (surface and surface.valid and center and force and force.valid) then
        return "retry", 0, "surface-or-force-unavailable"
    end

    local corpse, position = create_recovery_corpse(surface, force, player, #sources, center)
    if not (corpse and corpse.valid and position) then
        return "retry", 0, "recovery-corpse-creation-failed"
    end

    protect_corpse(corpse, player)

    local corpse_inventory = corpse.get_inventory(defines.inventory.character_corpse)
    if not (corpse_inventory and corpse_inventory.valid and #corpse_inventory >= #sources) then
        corpse.destroy()
        return "retry", 0, "corpse-inventory-unavailable"
    end

    local moved = {}
    local transfer_failed = false
    local failure_detail = "stack-transfer-failed"

    for corpse_slot, source in ipairs(sources) do
        local source_stack = get_source_stack(player, source)
        local destination_stack = corpse_inventory[corpse_slot]

        if not (source_stack and source_stack.valid and source_stack.valid_for_read
            and destination_stack and destination_stack.valid and not destination_stack.valid_for_read) then
            transfer_failed = true
            failure_detail = "source-or-destination-stack-invalid"
            break
        end

        local ok, swapped = pcall(function()
            return destination_stack.swap_stack(source_stack)
        end)
        if not ok or not swapped then
            transfer_failed = true
            failure_detail = "swap-stack-rejected"
            break
        end

        moved[#moved + 1] = {
            source = source,
            corpse_slot = corpse_slot,
        }
    end

    if transfer_failed then
        local rolled_back = rollback_transfer(player, corpse_inventory, moved)
        if rolled_back then
            corpse.destroy()
            return "retry", 0, failure_detail
        end

        -- Extremely defensive fallback: if the engine refuses a rollback, keep
        -- the non-expiring corpse and the remaining player inventory exactly as
        -- they are. This avoids deleting or duplicating any stack.
        protect_corpse(corpse, player)
        return "partial", #moved, failure_detail
    end

    force.print {
        "the-cave-offline-player-body.created",
        player.name,
        #sources,
        destination_kind == "train"
            and { "the-cave-offline-player-body.destination-train" }
            or { "the-cave-offline-player-body.destination-spawn" },
        string.format("[gps=%g,%g,%s]", position.x, position.y, surface.name),
    }

    return "success", #sources, nil
end

local function recompute_next_due(state)
    local next_due = nil
    for _, record in pairs(state.pending) do
        local due = record and tonumber(record.due_tick)
        if due and (not next_due or due < next_due) then
            next_due = due
        end
    end
    state.next_due_tick = next_due
end

local function schedule_player(player, tick)
    if not (player and player.valid) then return end
    local force = cave_teams.player_force(player)
    if not (force and cave_teams.force_is_active(force) and cave_teams.home_surface(force)) then return end
    remember_world(player)

    local state = root()
    local player_index = player.index
    local left_tick = tonumber(tick) or game.tick
    local existing_since = tonumber(state.offline_since[player_index])

    if not existing_since or left_tick < existing_since then
        state.offline_since[player_index] = left_tick
    else
        left_tick = existing_since
    end

    state.processed[player_index] = nil

    local due_tick = left_tick + FIVE_MINUTES_TICKS
    local existing = state.pending[player_index]
    if existing and tonumber(existing.due_tick) then
        due_tick = math.min(due_tick, tonumber(existing.due_tick))
    end

    state.pending[player_index] = {
        due_tick = due_tick,
        player_name = player.name,
        force_index = force.index,
        attempts = existing and tonumber(existing.attempts) or 0,
        last_error = existing and existing.last_error or nil,
    }

    if not state.next_due_tick or due_tick < state.next_due_tick then
        state.next_due_tick = due_tick
    end
end

local function reconcile_offline_players(tick)
    local state = root()

    for _, player in pairs(game.players) do
        if player and player.valid then
            local player_index = player.index

            if player.connected then
                remember_world(player)
                state.pending[player_index] = nil
                state.offline_since[player_index] = nil
                state.processed[player_index] = nil
            elseif not state.processed[player_index] and not state.pending[player_index] then
                -- When a save is upgraded while a player is already offline we
                -- cannot know the historical disconnect tick. Start a fresh
                -- five-minute safety window from the first reconciliation.
                schedule_player(player, tonumber(state.offline_since[player_index]) or tick)
            end
        end
    end

    state.last_reconcile_tick = tick
    recompute_next_due(state)
end

local function kick_afk_players(tick)
    if tick % AFK_CHECK_INTERVAL_TICKS ~= 0 then return end
    if not (game and game.is_multiplayer and game.is_multiplayer()) then return end

    local state = root()
    local player_indices = {}
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.connected then
            player_indices[#player_indices + 1] = player.index
        end
    end
    table.sort(player_indices)

    for _, player_index in ipairs(player_indices) do
        local player = game.get_player(player_index)
        if player and player.valid and player.connected then
            local afk_ticks = tonumber(player.afk_time) or 0
            if cave_teams.force_is_active(player.force) and afk_ticks >= FIVE_MINUTES_TICKS then
                local requested_tick = tonumber(state.afk_kick_requested[player_index])
                if not requested_tick or tick - requested_tick >= AFK_CHECK_INTERVAL_TICKS then
                    state.afk_kick_requested[player_index] = tick
                    game.kick_player(
                        player,
                        "AFK for five minutes. Rejoin within five minutes to keep your inventory."
                    )
                end
            else
                state.afk_kick_requested[player_index] = nil
            end
        end
    end
end

function offline_player_body.on_init()
    local state = root()
    if not enabled() then
        state.pending = {}
        state.offline_since = {}
        state.processed = {}
        state.afk_kick_requested = {}
        state.next_due_tick = nil
        return
    end

    reconcile_offline_players(game.tick)
end

function offline_player_body.on_configuration_changed()
    offline_player_body.on_init()
end

function offline_player_body.on_pre_player_left_game(event)
    if not enabled() then return end

    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end

    schedule_player(player, event.tick)
end

function offline_player_body.on_player_left_game(event)
    if not enabled() then return end

    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end

    -- This is intentionally registered as a second safety net. If the pre-leave
    -- event was delivered, schedule_player preserves the earlier due tick.
    schedule_player(player, event.tick)
    root().afk_kick_requested[event.player_index] = nil
end

function offline_player_body.on_player_joined_game(event)
    local state = root()
    state.pending[event.player_index] = nil
    state.offline_since[event.player_index] = nil
    state.processed[event.player_index] = nil
    state.afk_kick_requested[event.player_index] = nil
    remember_world(game.get_player(event.player_index))
    recompute_next_due(state)
end

function offline_player_body.on_player_removed(event)
    local state = root()
    state.pending[event.player_index] = nil
    state.offline_since[event.player_index] = nil
    state.processed[event.player_index] = nil
    state.afk_kick_requested[event.player_index] = nil
    state.last_worlds[event.player_index] = nil
    recompute_next_due(state)
end

function offline_player_body.on_arrival(player)
    remember_world(player)
end

function offline_player_body.on_player_changed_surface(event)
    remember_world(game.get_player(event.player_index))
end

function offline_player_body.on_player_controller_changed(event)
    remember_world(game.get_player(event.player_index))
end

function offline_player_body.on_surface_deleted(event)
    local state = root()
    local live = game.get_surface(event.surface_index)
    for player_index, record in pairs(state.last_worlds) do
        if record.surface_index == event.surface_index
            and not (live and live.valid and live.name == record.name) then
            state.last_worlds[player_index] = nil
        end
    end
end

function offline_player_body.on_tick(event)
    if not enabled() then return end

    local state = root()
    local tick = event.tick
    kick_afk_players(tick)

    if tick - (tonumber(state.last_reconcile_tick) or 0) >= RECONCILE_INTERVAL_TICKS then
        reconcile_offline_players(tick)
    end

    if not state.next_due_tick or tick < state.next_due_tick then
        return
    end

    -- Snapshot and sort due player indices before mutating the pending table.
    -- Besides avoiding in-loop table traversal changes, this keeps simultaneous
    -- disconnect processing deterministic in multiplayer lockstep.
    local due_players = {}
    for player_index, record in pairs(state.pending) do
        local due_tick = record and tonumber(record.due_tick)
        if due_tick and tick >= due_tick then
            due_players[#due_players + 1] = player_index
        end
    end
    table.sort(due_players)

    for _, player_index in ipairs(due_players) do
        local record = state.pending[player_index]
        if record then
            local player = game.get_player(player_index)

            if not (player and player.valid) then
                state.pending[player_index] = nil
                state.offline_since[player_index] = nil
                state.processed[player_index] = nil
            elseif player.connected then
                state.pending[player_index] = nil
                state.offline_since[player_index] = nil
                state.processed[player_index] = nil
            else
                local result, moved_count, detail = move_player_inventory_to_recovery(player)

                if result == "success" or result == "empty" then
                    state.pending[player_index] = nil
                    state.processed[player_index] = true
                elseif result == "retry" then
                    record.attempts = (tonumber(record.attempts) or 0) + 1
                    record.last_error = detail
                    record.due_tick = tick + RETRY_DELAY_TICKS
                    notify_admins {
                        "the-cave-offline-player-body.retry",
                        player.name,
                        record.attempts,
                        detail or "unknown",
                    }
                elseif result == "partial" then
                    state.pending[player_index] = nil
                    state.processed[player_index] = true
                    notify_admins {
                        "the-cave-offline-player-body.partial",
                        player.name,
                        moved_count,
                        detail or "unknown",
                    }
                end
            end
        end
    end

    recompute_next_due(state)
end

return offline_player_body
