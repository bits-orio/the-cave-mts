local physical = require("scripts.player_physical")
-- Staged in-save restart for The Cave.
--
-- A dedicated server host cannot be restarted from a normal Factorio mod.
-- Instead, this module rebuilds only the surfaces and persistent state owned by
-- The Cave. Players are evacuated to a temporary lobby before any destructive
-- work starts. Each destructive phase is checkpointed in `storage`, so saving
-- or restarting the dedicated server during the rebuild is safe.

local soft_reset = {}
local main_train_defeat = require("scripts.main_train_defeat")
local cave_worlds = require("scripts.cave_worlds")

local LOBBY_SURFACE_NAME = "the-cave-reset-lobby"
local OWNED_SURFACE_PREFIXES = {
    "the-cave-train-interior-",
    "the-cave-shelter-interior-",
    "the-cave-shelter-garden-surface-",
    "the-cave-uranium-cave-",
    "the-cave-mineral-cave-",
    "the-cave-fortified-vault-",
    "the-cave-lost-city-",
    "the-cave-warp-",
}
local TICKS_BETWEEN_STAGES = 1

local callbacks = {}

local function current_state()
    return storage and storage.the_cave_soft_reset or nil
end

local function valid(object)
    return object and object.valid
end

local function starts_with(value, prefix)
    return type(value) == "string" and value:sub(1, #prefix) == prefix
end

local function is_main_surface_name(name)
    local surface = game.surfaces[name]
    return valid(surface) and (name == "nauvis" or cave_worlds.is_copy(surface))
end

local function is_owned_child_surface_name(name)
    if name == LOBBY_SURFACE_NAME then return false end
    for _, prefix in ipairs(OWNED_SURFACE_PREFIXES) do
        if starts_with(name, prefix) then return true end
    end
    return false
end

local function sorted_player_indexes()
    local indexes = {}
    for _, player in pairs(game.players or {}) do
        if valid(player) then indexes[#indexes + 1] = player.index end
    end
    table.sort(indexes)
    return indexes
end

local function sorted_surface_names(predicate)
    local names = {}
    for _, surface in pairs(game.surfaces or {}) do
        if valid(surface) and predicate(surface.name) then names[#names + 1] = surface.name end
    end
    table.sort(names)
    return names
end

local function print_all(message, color)
    if not game then return end
    for _, player in pairs(game.connected_players or {}) do
        if valid(player) then player.print(message, color) end
    end
end

local function play_alarm()
    for _, player in pairs(game.connected_players or {}) do
        if valid(player) then
            pcall(function() player.play_sound { path = "utility/console_message" } end)
        end
    end
end

local function destroy_owned_gui_tree(element)
    if not (element and element.valid) then return end
    local children = {}
    for _, child in pairs(element.children or {}) do children[#children + 1] = child end
    for _, child in ipairs(children) do
        if child and child.valid then
            local name = child.name or ""
            if starts_with(name, "the_cave_") or starts_with(name, "diggy_") or name == "inserter_config" then
                child.destroy()
            else
                destroy_owned_gui_tree(child)
            end
        end
    end
end

local function destroy_owned_player_guis(player)
    if not (valid(player) and player.gui) then return end
    for _, root_name in ipairs({ "top", "left", "center", "screen", "relative" }) do
        local root = player.gui[root_name]
        if root and root.valid then destroy_owned_gui_tree(root) end
    end
end

local function cancel_player_crafting(player)
    if not valid(player) then return end
    pcall(function()
        while (tonumber(player.crafting_queue_size) or 0) > 0 do
            local queue = player.crafting_queue
            local item = queue and queue[1]
            if not item then break end
            player.cancel_crafting { index = 1, count = item.count or 4294967295 }
        end
    end)
end

local function clear_player_items(player)
    if not valid(player) then return end
    cancel_player_crafting(player)
    pcall(function() player.clear_items_inside() end)
    pcall(function()
        if player.cursor_stack and player.cursor_stack.valid then player.cursor_stack.clear() end
    end)

    local character = player.character
    if valid(character) then
        for _, inventory_id in ipairs({
            defines.inventory.character_main,
            defines.inventory.character_guns,
            defines.inventory.character_ammo,
            defines.inventory.character_armor,
            defines.inventory.character_trash,
        }) do
            local inventory = character.get_inventory(inventory_id)
            if inventory and inventory.valid then inventory.clear() end
        end
    end
end

local function lobby_position(player_index)
    local slot = math.max(0, (tonumber(player_index) or 1) - 1)
    return {
        x = -12 + (slot % 7) * 4,
        y = -12 + math.floor(slot / 7) * 4,
    }
end

local function ensure_lobby_surface()
    local surface = game.surfaces[LOBBY_SURFACE_NAME]
    if not valid(surface) then
        surface = game.create_surface(LOBBY_SURFACE_NAME, {
            water = 0,
            starting_area = 1,
            cliff_settings = { cliff_elevation_interval = 0, cliff_elevation_0 = 0 },
            autoplace_settings = {
                entity = { settings = {}, treat_missing_as_default = false },
                tile = { settings = {}, treat_missing_as_default = false },
                decorative = { settings = {}, treat_missing_as_default = false },
            },
        })
    end
    if not valid(surface) then error("could not create the temporary reset lobby") end

    surface.no_enemies_mode = true
    surface.freeze_daytime = true
    surface.always_day = true
    surface.daytime = 0.1
    surface.request_to_generate_chunks({ 0, 0 }, 1)
    surface.force_generate_chunk_requests()

    local tile_name = prototypes.tile["refined-concrete"] and "refined-concrete"
        or (prototypes.tile["stone-path"] and "stone-path" or "landfill")
    local tiles = {}
    for x = -24, 24 do
        for y = -24, 24 do
            tiles[#tiles + 1] = { name = tile_name, position = { x = x, y = y } }
        end
    end
    surface.set_tiles(tiles, true, true)
    return surface
end

local function force_has_players(force)
    if not valid(force) then return false end
    for _, player in pairs(force.players or {}) do
        if valid(player) then return true end
    end
    return false
end

local function participant_forces()
    if callbacks.active_forces then return callbacks.active_forces() end
    local forces = {}
    for _, force in pairs(game.forces) do
        if force_has_players(force) then forces[#forces + 1] = force end
    end
    return forces
end

local function effective_force(player)
    return callbacks.player_force and callbacks.player_force(player) or player.force
end

local function home_surface(force, reset)
    local name = valid(force) and reset and reset.force_home_surfaces and reset.force_home_surfaces[force.index]
    local surface = name and game.surfaces[name]
    if not valid(surface) and callbacks.home_surface then surface = callbacks.home_surface(force) end
    if valid(surface) and not cave_worlds.is_template(surface) then return surface end
end

local function snapshot_force_relations()
    local snapshots = {}
    for _, force in pairs(participant_forces()) do
        if valid(force) then
            local record = {
                index = force.index,
                name = force.name,
                friends = {},
                cease_fire = {},
                share_chart = force.share_chart,
            }
            for _, other in pairs(game.forces) do
                if valid(other) and other ~= force then
                    record.friends[other.name] = force.get_friend(other)
                    record.cease_fire[other.name] = force.get_cease_fire(other)
                end
            end
            snapshots[#snapshots + 1] = record
        end
    end
    table.sort(snapshots, function(a, b) return a.index < b.index end)
    return snapshots
end

local function should_evacuate(player, reset)
    if reset.evacuated_players and reset.evacuated_players[player.index] then return true end
    local surface = physical.surface(player)
    if not valid(surface) then return false end
    if is_main_surface_name(surface.name) or is_owned_child_surface_name(surface.name) then return true end
    -- Preserve the single-team planet return behavior, while leaving another
    -- mod's waiting room and its spectators alone.
    local force = effective_force(player)
    return surface.planet ~= nil and valid(force)
        and reset.reset_force_indexes and reset.reset_force_indexes[force.index] == true
end

local function choose_player_target_surface(player, reset)
    local surface = home_surface(effective_force(player), reset)
    if valid(surface) then return surface.name end
    surface = physical.surface(player)
    if valid(surface) and surface.name ~= LOBBY_SURFACE_NAME
        and not is_owned_child_surface_name(surface.name) and not cave_worlds.is_template(surface) then
        return surface.name
    end
    -- Visitors inside a deleted child cave have no home of their own. Return
    -- them beside the participating force instead of into the template.
    for _, record in ipairs(reset.force_snapshots or {}) do
        surface = home_surface(game.forces[record.index], reset)
        if valid(surface) then return surface.name end
    end
end

local function evacuate_player(player, lobby, clear_items)
    if not valid(player) then return end
    destroy_owned_player_guis(player)
    pcall(function() player.opened = nil end)
    pcall(function() if player.driving then player.driving = false end end)

    local target = lobby_position(player.index)
    if not physical.teleport(player, target, lobby) then
        error("could not evacuate player " .. tostring(player.name or player.index) .. " to the reset lobby")
    end
    -- Only clear the character after the safety move succeeds. A teleport
    -- failure therefore cannot strand a player on the old map after already
    -- deleting their inventory.
    if clear_items then clear_player_items(player) end
end

local function next_seed(old_seed, started_tick)
    local seed = tonumber(old_seed) or 0
    local tick = tonumber(started_tick) or 0
    return math.floor((seed + tick + 104729) % 4294967296)
end

local function restore_force_relations(reset)
    for _, record in ipairs(reset.force_snapshots or {}) do
        local force = game.forces[record.name] or game.forces[record.index]
        if valid(force) then
            if record.share_chart ~= nil then force.share_chart = record.share_chart end
            for other_name, value in pairs(record.friends or {}) do
                local other = game.forces[other_name]
                if valid(other) and other ~= force then force.set_friend(other, value == true) end
            end
            for other_name, value in pairs(record.cease_fire or {}) do
                local other = game.forces[other_name]
                if valid(other) and other ~= force then force.set_cease_fire(other, value == true) end
            end
        end
    end
    -- Players remain protected until the last return, including after a force
    -- reset or runtime initializer rewrites its relationships.
    main_train_defeat.apply_truce()
end

local function advance(reset, stage, delay)
    reset.stage = stage
    reset.next_tick = (game.tick or 0) + (delay or TICKS_BETWEEN_STAGES)
end

local function stage_prepare(reset)
    game.reset_game_state()
    local lobby = ensure_lobby_surface()
    reset.main_surface_names = sorted_surface_names(is_main_surface_name)
    if #reset.main_surface_names == 0 or not game.surfaces["nauvis"] then
        error("the required nauvis surface is missing")
    end
    reset.owned_surface_names = sorted_surface_names(is_owned_child_surface_name)
    reset.force_snapshots = snapshot_force_relations()
    main_train_defeat.patch_force_snapshots(reset.force_snapshots)
    reset.player_target_surfaces = reset.player_target_surfaces or {}
    reset.player_origins = reset.player_origins or {}
    reset.force_home_surfaces = reset.force_home_surfaces or {}
    reset.reset_force_indexes = {}
    reset.evacuated_players = reset.evacuated_players or {}
    for _, record in ipairs(reset.force_snapshots) do
        reset.reset_force_indexes[record.index] = true
        local home = home_surface(game.forces[record.index], reset)
        if valid(home) then reset.force_home_surfaces[record.index] = home.name end
    end
    for _, player in pairs(game.players or {}) do
        if valid(player) and should_evacuate(player, reset) then
            reset.evacuated_players[player.index] = true
            reset.player_target_surfaces[player.index] = choose_player_target_surface(player, reset)
            local surface, position = physical.surface(player), physical.position(player)
            if valid(surface) and position then
                reset.player_origins[player.index] = { surface_name = surface.name, position = { x = position.x, y = position.y } }
            end
        end
    end

    local nauvis = game.surfaces["nauvis"]
    reset.new_seed = next_seed(nauvis and nauvis.map_gen_settings and nauvis.map_gen_settings.seed, reset.started_tick)
    reset.owned_surface_cursor = 1
    reset.main_surface_cursor = 1
    reset.force_cursor = 1
    reset.generate_cursor = 1
    reset.returned_players = {}
    reset.lobby_surface_index = lobby.index
    print_all({ "the-cave-soft-reset.evacuating" }, { r = 1, g = 0.75, b = 0.15 })
    advance(reset, "evacuate")
end

local function stage_evacuate(reset)
    local lobby = ensure_lobby_surface()
    for _, player in pairs(game.players or {}) do
        if reset.evacuated_players[player.index] then evacuate_player(player, lobby, true) end
    end
    advance(reset, "delete-owned-surfaces")
end

local function stage_delete_owned_surfaces(reset)
    local cursor = tonumber(reset.owned_surface_cursor) or 1
    local name = reset.owned_surface_names and reset.owned_surface_names[cursor] or nil
    if not name then
        print_all({ reset.shelter_mode and "the-cave-soft-reset.rebuilding-shelter"
            or "the-cave-soft-reset.rebuilding" }, { r = 1, g = 0.75, b = 0.15 })
        advance(reset, "clear-main-surfaces")
        return
    end

    local surface = game.surfaces[name]
    if valid(surface) then
        for _, player in pairs(game.players or {}) do
            if physical.on_surface(player, surface) then
                error("player " .. tostring(player.name or player.index) .. " remained on owned surface " .. name)
            end
            local lobby = game.surfaces[LOBBY_SURFACE_NAME]
            if not physical.move_view_off_surface(player, surface, lobby, lobby_position(player.index)) then
                error("could not move a remote observer off surface " .. name)
            end
        end
        game.delete_surface(surface)
    end
    reset.owned_surface_cursor = cursor + 1
    reset.next_tick = (game.tick or 0) + TICKS_BETWEEN_STAGES
end

local function stage_clear_main_surfaces(reset)
    local cursor = tonumber(reset.main_surface_cursor) or 1
    local name = reset.main_surface_names and reset.main_surface_names[cursor] or nil
    if not name then
        advance(reset, "wipe-the-cave-state")
        return
    end

    local surface = game.surfaces[name]
    if valid(surface) then
        for _, player in pairs(game.players or {}) do
            if physical.on_surface(player, surface) then
                error("player " .. tostring(player.name or player.index) .. " remained on main surface " .. name)
            end
            local lobby = game.surfaces[LOBBY_SURFACE_NAME]
            if not physical.move_view_off_surface(player, surface, lobby, lobby_position(player.index)) then
                error("could not move a remote observer off surface " .. name)
            end
        end
        surface.clear(false)
        local map_gen = surface.map_gen_settings
        map_gen.seed = reset.new_seed
        surface.map_gen_settings = map_gen
        surface.clear_pollution()
    end
    reset.main_surface_cursor = cursor + 1
    reset.next_tick = (game.tick or 0) + TICKS_BETWEEN_STAGES
end

local function stage_wipe_the_cave_state(reset)
    if callbacks.before_wipe_state then callbacks.before_wipe_state(reset) end
    local worlds = storage.cave_worlds
    local migration_version = storage.the_cave_worlds_migration_version
    local team_adapter = storage.the_cave_team_adapter
    for key in pairs(storage) do storage[key] = nil end
    storage.cave_worlds = worlds
    storage.the_cave_worlds_migration_version = migration_version
    storage.the_cave_team_adapter = team_adapter
    storage.the_cave_soft_reset = reset
    advance(reset, "reset-forces")
end

local function stage_reset_forces(reset)
    local cursor = tonumber(reset.force_cursor) or 1
    local record = reset.force_snapshots and reset.force_snapshots[cursor] or nil
    if not record then
        local enemy = game.forces.enemy
        if valid(enemy) then
            for _, name in ipairs(reset.main_surface_names or {}) do
                local surface = game.surfaces[name]
                if valid(surface) then enemy.set_evolution_factor(0, surface) end
            end
        end
        restore_force_relations(reset)
        advance(reset, "generate-main-surfaces")
        return
    end

    local force = game.forces[record.name] or game.forces[record.index]
    if valid(force) then
        force.reset()
        force.clear_chart()
    end
    reset.force_cursor = cursor + 1
    reset.next_tick = (game.tick or 0) + TICKS_BETWEEN_STAGES
end

local function stage_generate_main_surfaces(reset)
    local cursor = tonumber(reset.generate_cursor) or 1
    local name = reset.main_surface_names and reset.main_surface_names[cursor] or nil
    if not name then
        advance(reset, "initialize-runtime")
        return
    end

    local surface = game.surfaces[name]
    if valid(surface) then
        surface.request_to_generate_chunks({ 0, 0 }, 2)
        surface.force_generate_chunk_requests()
    end
    reset.generate_cursor = cursor + 1
    reset.next_tick = (game.tick or 0) + TICKS_BETWEEN_STAGES
end

local function stage_initialize_runtime(reset)
    if type(callbacks.initialize_runtime) ~= "function" then
        error("The Cave runtime initializer is unavailable")
    end
    callbacks.initialize_runtime()
    restore_force_relations(reset)

    for _, record in ipairs(reset.force_snapshots or {}) do
        local force = game.forces[record.name] or game.forces[record.index]
        if valid(force) then
            local surface = home_surface(force, reset)
            if valid(surface) then force.set_spawn_position({ 0, 0 }, surface) end
        end
    end
    if type(callbacks.post_initialize_runtime) == "function" then
        callbacks.post_initialize_runtime(reset)
    end
    local countdown = math.max(0, tonumber(reset.post_reset_countdown_ticks) or 0)
    if countdown > 0 then
        reset.lobby_countdown_ends_tick = (game.tick or 0) + countdown
        reset.lobby_countdown_last_second = nil
        advance(reset, "lobby-countdown", 0)
    else
        advance(reset, "return-players")
    end
end

local function stage_lobby_countdown(reset)
    local remaining = math.max(0,
        (tonumber(reset.lobby_countdown_ends_tick) or (game.tick or 0)) - (game.tick or 0))
    local seconds = math.ceil(remaining / 60)
    if seconds ~= reset.lobby_countdown_last_second then
        reset.lobby_countdown_last_second = seconds
        print_all({ "the-cave-soft-reset.lobby-countdown", seconds }, { r = 1, g = 0.75, b = 0.15 })
    end
    if remaining <= 0 then
        advance(reset, "return-players")
    else
        reset.next_tick = (game.tick or 0) + math.min(60, remaining)
    end
end

local function stage_return_players(reset)
    local pending_index = nil
    for _, player_index in ipairs(sorted_player_indexes()) do
        if reset.evacuated_players[player_index] and not reset.returned_players[player_index] then
            pending_index = player_index
            break
        end
    end
    if not pending_index then
        advance(reset, "finish")
        return
    end

    local player = game.get_player(pending_index)
    if valid(player) then
        main_train_defeat.respawn_before_return(player)
        local force = effective_force(player)
        local target_name = reset.player_target_surfaces[pending_index]
        local surface = target_name and game.surfaces[target_name]
        if not valid(surface) or cave_worlds.is_template(surface) then surface = home_surface(force, reset) end
        local origin = reset.player_origins and reset.player_origins[pending_index]
        if not valid(surface) and origin then surface = game.surfaces[origin.surface_name] end
        if not valid(surface) or cave_worlds.is_template(surface) then
            error("return surface is missing for player " .. tostring(player.name or player.index))
        end
        local home = home_surface(force, reset)
        local spawn = valid(home) and home == surface and force.get_spawn_position(surface)
            or (origin and origin.surface_name == surface.name and origin.position)
            or (valid(force) and force.get_spawn_position(surface)) or { x = 0, y = 0 }
        local target = physical.find_position(player, surface, spawn, 32)
        if not physical.teleport(player, target, surface) then
            error("could not return player " .. tostring(player.name or player.index) .. " to the rebuilt cave")
        end
        if type(callbacks.initialize_player) == "function" then callbacks.initialize_player(player.index) end
        main_train_defeat.protect_player(player)
    end
    reset.returned_players[pending_index] = true
    reset.next_tick = (game.tick or 0) + TICKS_BETWEEN_STAGES
end

local function stage_finish(reset)
    local lobby = game.surfaces[LOBBY_SURFACE_NAME]
    if valid(lobby) then
        for _, player in pairs(game.players or {}) do
            if physical.on_surface(player, lobby) then
                error("player " .. tostring(player.name or player.index) .. " is still in the reset lobby")
            end
            if not physical.move_view_off_surface(player, lobby, physical.surface(player), physical.position(player)) then
                error("could not move a remote observer off the reset lobby")
            end
        end
        game.delete_surface(lobby)
    end
    game.reset_game_state()
    main_train_defeat.finish()
    storage.the_cave_soft_reset = nil
    if callbacks.on_finished then callbacks.on_finished(reset) end
    print_all({ reset.shelter_mode and "the-cave-soft-reset.complete-shelter"
        or "the-cave-soft-reset.complete" }, { r = 0.2, g = 1, b = 0.25 })
    play_alarm()
end

local STAGES = {
    ["prepare"] = stage_prepare,
    ["evacuate"] = stage_evacuate,
    ["delete-owned-surfaces"] = stage_delete_owned_surfaces,
    ["clear-main-surfaces"] = stage_clear_main_surfaces,
    ["wipe-the-cave-state"] = stage_wipe_the_cave_state,
    ["reset-forces"] = stage_reset_forces,
    ["generate-main-surfaces"] = stage_generate_main_surfaces,
    ["initialize-runtime"] = stage_initialize_runtime,
    ["lobby-countdown"] = stage_lobby_countdown,
    ["return-players"] = stage_return_players,
    ["finish"] = stage_finish,
}

local function fail(reset, message)
    reset.failed = true
    reset.error = tostring(message or "unknown soft-reset error")
    reset.failed_tick = game.tick or 0
    log("[The Cave] SOFT RESET STOPPED at stage '" .. tostring(reset.stage) .. "': " .. reset.error)
    print_all({
        "the-cave-soft-reset.failed",
        tostring(reset.stage or "unknown"),
        reset.error,
    }, { r = 1, g = 0.15, b = 0.1 })
    play_alarm()
end

function soft_reset.configure(options)
    callbacks = options or {}
end

function soft_reset.is_active()
    local reset = current_state()
    return reset and reset.active == true
end

function soft_reset.start(reason, options)
    if soft_reset.is_active() then return false end
    options = options or {}
    storage.the_cave_soft_reset = {
        active = true,
        failed = false,
        reason = reason or "main-train-destroyed",
        force_index = options.force_index,
        stage = "prepare",
        started_tick = game.tick or 0,
        next_tick = game.tick or 0,
        post_reset_countdown_ticks = math.max(0, tonumber(options.post_reset_countdown_ticks) or 0),
        shelter_mode = options.shelter_mode == true,
        main_train_defeat = main_train_defeat.state(),
    }
    game.reset_game_state()
    if callbacks.on_started then callbacks.on_started(storage.the_cave_soft_reset) end
    return true
end

function soft_reset.on_tick(event)
    local reset = current_state()
    if not (reset and reset.active) then return false end
    if reset.failed then return true end
    -- A save may have been made halfway through a 3.3.1 staged restart.
    if not reset.evacuated_players then
        reset.evacuated_players = {}
        for index in pairs(reset.player_target_surfaces or {}) do reset.evacuated_players[index] = true end
    end
    local now = event and event.tick or (game.tick or 0)
    if now < (tonumber(reset.next_tick) or 0) then return true end

    local handler = STAGES[reset.stage]
    if not handler then
        fail(reset, "unknown reset stage: " .. tostring(reset.stage))
        return true
    end

    local ok, err = xpcall(function() handler(reset) end, debug.traceback)
    if not ok then fail(reset, err) end
    return true
end

function soft_reset.hold_player(player)
    local reset = current_state()
    if not (reset and reset.active and valid(player)) then return false end
    if not should_evacuate(player, reset) then return false end
    reset.evacuated_players = reset.evacuated_players or {}
    reset.evacuated_players[player.index] = true
    reset.player_target_surfaces = reset.player_target_surfaces or {}
    if not reset.player_target_surfaces[player.index] then
        reset.player_target_surfaces[player.index] = choose_player_target_surface(player, reset)
    end
    if reset.returned_players then reset.returned_players[player.index] = nil end
    -- A join/respawn can arrive between the final return and lobby cleanup.
    -- Return that player again before completing the reset.
    if reset.stage == "finish" then advance(reset, "return-players") end

    local lobby = game.surfaces[LOBBY_SURFACE_NAME]
    if valid(lobby) then
        local ok, err = xpcall(function() evacuate_player(player, lobby, true) end, debug.traceback)
        if not ok and not reset.failed then fail(reset, err) end
    else
        destroy_owned_player_guis(player)
    end
    if player.connected then
        player.print({ reset.shelter_mode and "the-cave-soft-reset.in-progress-shelter"
            or "the-cave-soft-reset.in-progress" })
    end
    return true
end

-- The force-reset coordinator uses exactly the same inventory/crafting cleanup.
soft_reset.recovery_surface = ensure_lobby_surface
soft_reset.clear_player_items = clear_player_items
soft_reset.destroy_player_guis = destroy_owned_player_guis

function soft_reset.status_text()
    local reset = current_state()
    if not (reset and reset.active) then return "idle" end
    if reset.failed then return "failed at " .. tostring(reset.stage) .. ": " .. tostring(reset.error) end
    return "running: " .. tostring(reset.stage)
end

return soft_reset
