-- Engine lifecycle and defeat orchestration. The shared lookup module remains
-- a leaf so terrain, interiors and player services can all use it safely.
local teams = require("scripts.cave_teams")
local worlds = require("scripts.cave_worlds")
local world_events = require("scripts.cave_world_events")
local trains = require("scripts.train_interiors")
local shelters = require("scripts.shelter_core")
local warp = require("scripts.warp_outpost")
local defeat = require("scripts.main_train_defeat")
local soft_reset = require("scripts.soft_reset")
local advancing = require("scripts.advancing_collapse")
local charting = require("scripts.charting")
local nests = require("scripts.enemy_nest_growth")
local oil = require("scripts.ore_veins")
local bodies = require("scripts.offline_player_body")
local physical = require("scripts.player_physical")
local mirror = require("scripts.lib.mirror")
local collapse = require("scripts.collapse")
local settings = require("scripts.game_settings")
local progression = require("scripts.everything_on_nauvis_progression")
local quality = require("scripts.quality_everything")
local roof_mining = require("scripts.roof_support_mining")
local caverns = require("scripts.caverns")
local depths = require("scripts.depth_levels")
local children = {
    require("scripts.uranium_caves"), require("scripts.mineral_caves"),
    require("scripts.fortified_vaults"), (require("scripts.lost_city")),
}
local lifecycle = { teams = teams, worlds = worlds }
local defeated_event = script.generate_event_name()
local owned_surface_event = script.generate_event_name()
teams.set_owned_surface_event(owned_surface_event)

local initialize_player = nil

local function valid(object) return object and object.valid end

-- The per-player initializer the server reset runs, set by control.lua.
function lifecycle.set_player_initializer(handler)
    initialize_player = type(handler) == "function" and handler or nil
end

function lifecycle.has_base(force)
    return trains.has_base(force) or shelters.has_base(force)
end

function lifecycle.base_surface(force)
    return trains.base_surface(force) or (shelters.has_base(force) and shelters.base_surface(force))
end

function lifecycle.owned_surfaces(force)
    local result, seen = {}, {}
    local function append(module)
        for _, surface in pairs(module.owned_surfaces(force)) do
            if valid(surface) and not worlds.is_cave_world(surface) and not seen[surface.index] then
                result[#result + 1], seen[surface.index] = surface, true
            end
        end
    end
    append(trains)
    append(shelters)
    for _, module in ipairs(children) do append(module) end
    table.sort(result, function(a, b) return a.index < b.index end)
    return result
end

-- A surface someone could not be moved off stays until it is empty.
local function queue_deletion(surfaces, occupied, force_index)
    for _, surface in ipairs(surfaces) do
        if valid(surface) and occupied and occupied[surface.index] then
            storage.the_cave_occupied_deletions = storage.the_cave_occupied_deletions or {}
            storage.the_cave_occupied_deletions[surface.index] = { name = surface.name, force_index = force_index }
        elseif valid(surface) then
            teams.delete_owned_surface(surface, force_index)
        end
    end
end

-- A move that failed is retried from lifecycle.on_tick instead of stopping
-- the reset. It waits while the player is in remote view, which another mod
-- may hold them in.
local function defer_return(player, force, home)
    storage.the_cave_reset_respawn_pending = storage.the_cave_reset_respawn_pending or {}
    local pending = storage.the_cave_reset_respawn_pending
    -- Keep a dead offline player's ticket, which still has to clear the respawn kit.
    local ticket = type(pending[player.index]) == "table" and pending[player.index] or {}
    ticket.force_index, ticket.home_index, ticket.home_name = force.index, home.index, home.name
    ticket.ready_tick = ticket.ready_tick or game.tick + 60
    ticket.deferred = true
    pending[player.index] = ticket
    log("[The Cave] could not move player " .. player.name .. " yet; retrying")
end

local function clear_force(index, keep_home)
    trains.wave_defense.clear_force(index)
    trains.clear_force(index)
    shelters.clear_force(index)
    warp.clear_force(index)
    advancing.clear_force(index)
    oil.clear_force(index)
    for _, module in ipairs(children) do module.clear_force(index) end
    if caverns.clear_force then caverns.clear_force(index) end
    if caverns.progression.clear_force then caverns.progression.clear_force(index) end
    if depths.clear_force then depths.clear_force(index) end
    teams.clear_force(index, keep_home)
end

function lifecycle.sync_force(force)
    if not valid(force) then return end
    settings.apply_to_force(force)
    settings.lock_advancing_train_recipes(force)
    settings.apply_roof_support_research(force)
    roof_mining.sync_force(force)
    progression.sync_force(force)
    quality.sync_force(force)
    shelters.sync_force(force)
    trains.sync_force(force)
end

-- Returns the removed surfaces that still hold a player who could not be moved.
local function evacuate(surfaces, defeated_force, fallback, clear_items)
    local removed, occupied = {}, {}
    for _, surface in ipairs(surfaces) do removed[surface.index] = true end
    for _, player in pairs(game.players) do
        local force = teams.player_force(player)
        local affected = force == defeated_force
        local surface = physical.surface(player)
        local viewing_removed = valid(player.surface) and removed[player.surface.index]
        local on_removed = valid(surface) and removed[surface.index]
        if affected and not on_removed and physical.is_riding(player) then
            -- A platform or rocket stays with its rider; only the team's items go.
            if clear_items then
                soft_reset.destroy_player_guis(player)
                soft_reset.clear_player_items(player)
            end
        elseif affected or on_removed or viewing_removed then
            if affected then
                local deferred = not player.connected and player.ticks_to_respawn ~= nil
                defeat.respawn_before_return(player)
                if deferred then
                    local home = teams.home_surface(force)
                    storage.the_cave_reset_respawn_pending = storage.the_cave_reset_respawn_pending or {}
                    storage.the_cave_reset_respawn_pending[player.index] = {
                        force_index = force.index, home_index = home and home.index,
                        home_name = home and home.name, clear_items = clear_items,
                    }
                end
            end
            local home = teams.home_surface(force) or fallback
            if valid(home) and storage.the_cave_deleting_world == home.index then home = nil end
            if not valid(home) and ((valid(surface) and removed[surface.index]) or viewing_removed) then
                home = soft_reset.recovery_surface()
            end
            if valid(home) and not removed[home.index] and not worlds.is_template(home) then
                local spawn = valid(force) and force.get_spawn_position(home) or { x = 0, y = 0 }
                local position = physical.find_position(player, home, spawn, 64) or spawn
                local moved = true
                if affected or (valid(surface) and removed[surface.index]) then
                    player.driving = false
                    moved = physical.teleport(player, position, home)
                elseif viewing_removed then
                    moved = physical.move_view_off_surface(player, player.surface, home, position)
                end
                if not moved then
                    if on_removed then occupied[surface.index] = true end
                    defer_return(player, force, home)
                end
                if affected and clear_items then
                    soft_reset.destroy_player_guis(player)
                    soft_reset.clear_player_items(player)
                end
            elseif on_removed then
                -- Never delete an occupied cave when its safe destination vanished.
                occupied[surface.index] = true
                log("[The Cave] no safe home for player " .. player.name .. "; keeping " .. surface.name)
            end
        end
    end
    return occupied
end

local function occupied_vehicle(entity)
    if entity.type ~= "car" and entity.type ~= "spider-vehicle" and entity.type ~= "locomotive"
        and entity.type ~= "cargo-wagon" and entity.type ~= "fluid-wagon"
        and entity.type ~= "artillery-wagon" then return false end
    local ok, driver = pcall(function() return entity.get_driver() end)
    if ok and driver then return true end
    local passenger_ok, passenger = pcall(function() return entity.get_passenger() end)
    return passenger_ok and passenger ~= nil
end

local function raise_defeat(force, reason, scope)
    if not valid(force) then return end
    script.raise_event(defeated_event, {
        force_index = force.index, force_name = force.name, reason = reason, scope = scope,
    })
end

-- A failed force reset ends that force's truce and countdown, so the team is
-- never left in a truce with no base and the last-team fallback never fires.
local function fail_force_reset(force, err)
    log("[The Cave] force reset failed for " .. force.name .. ": " .. tostring(err))
    defeat.finish(force)
    warp.clear_force(force.index)
    return false
end

function lifecycle.reset_force(force, reason)
    if not valid(force) or teams.is_resetting(force) then return false end
    local home = teams.home_surface(force)
    if not valid(home) then return fail_force_reset(force, "no home world") end
    local surfaces = lifecycle.owned_surfaces(force)
    local spawn = force.get_spawn_position(home)
    -- Block arrival and destruction callbacks for the entire synchronous reset.
    teams.set_resetting(force, true)
    local ok, err = xpcall(function()
        local occupied = evacuate(surfaces, force, home, true)
        local relations, share_chart = {}, force.share_chart
        for _, other in pairs(game.forces) do
            if other ~= force and other ~= game.forces.enemy then
                relations[other.index] = { friend = force.get_friend(other), cease_fire = force.get_cease_fire(other) }
            end
        end
        force.reset()
        for index, row in pairs(relations) do
            local other = game.forces[index]
            if valid(other) then
                force.set_friend(other, row.friend)
                force.set_cease_fire(other, row.cease_fire)
            end
        end
        force.share_chart = share_chart
        force.set_spawn_position(spawn, home)
        defeat.finish(force)
        -- Clear defeat/base bookkeeping before raise_destroy can notify the train
        -- detector again. The surfaces have already been collected and evacuated.
        clear_force(force.index, true)
        teams.set_resetting(force, true)
        queue_deletion(surfaces, occupied, force.index)
        for _, entity in pairs(home.find_entities_filtered { force = force }) do
            if valid(entity) and entity.type ~= "character" and not occupied_vehicle(entity) then
                entity.destroy { raise_destroy = true }
            end
        end
        mirror.drop_surface(home.index)
        collapse.drop_surface_cache(home.index)
        if worlds.owner_force(home) == force then
            game.forces.enemy.set_evolution_factor(0, home)
            advancing.reset_world(home)
        end
        force.clear_chart(home)
        charting.for_force_world(force, home)
        teams.set_home(force, home)
        teams.suppress_arrivals(force, 60)
    end, debug.traceback)
    teams.set_resetting(force, false)
    if not ok then return fail_force_reset(force, err) end
    -- The evacuation removed the defeated players' Cave GUIs. Build them again
    -- as the server reset does; delivered starter kits stay delivered.
    if initialize_player then
        for _, player in pairs(game.players) do
            if teams.player_force(player) == force then initialize_player(player.index) end
        end
    end
    raise_defeat(force, reason, "force")
    return true
end

function lifecycle.on_defeated(reason, options)
    options = options or {}
    local force = game.forces[options.force_index or "player"]
    if not valid(force) or teams.is_resetting(force) then return false end
    if #teams.other_team_forces(force) > 0 then return lifecycle.reset_force(force, reason), "force" end
    options.force_index = force.index
    return soft_reset.start(reason, options), "server"
end

function lifecycle.on_server_reset_started(reset)
    raise_defeat(game.forces[reset.force_index or "player"], reset.reason, "server")
end

function lifecycle.on_server_reset_finished(reset)
    for index, ticket in pairs(storage.the_cave_reset_respawn_pending or {}) do
        if ticket == true then
            local player = game.get_player(index)
            local force = player and teams.player_force(player)
            local home = force and teams.home_surface(force)
            if valid(force) then
                storage.the_cave_reset_respawn_pending[index] = {
                    force_index = force.index, home_index = home and home.index,
                    home_name = home and home.name, clear_items = true,
                }
            end
        end
    end
    for index in pairs(reset.evacuated_players or {}) do teams.queue_arrival(index) end
end

local function delete_emptied_surfaces()
    local occupied = storage.the_cave_occupied_deletions
    if not occupied or game.tick % 60 ~= 0 then return end
    for index, row in pairs(occupied) do
        local surface = game.surfaces[index]
        local empty = true
        if valid(surface) and surface.name == row.name then
            for _, player in pairs(game.players) do
                if physical.surface(player) == surface then empty = false end
            end
            if empty then teams.delete_owned_surface(surface, row.force_index) end
        end
        if empty then occupied[index] = nil end
    end
    if not next(occupied) then storage.the_cave_occupied_deletions = nil end
end

local function ticket_home(force, ticket)
    local home = teams.home_surface(force)
    if valid(home) or not ticket.deferred then return home end
    home = ticket.home_index and game.surfaces[ticket.home_index]
    if valid(home) and home.name == ticket.home_name then return home end
end

function lifecycle.on_tick()
    for index, ticket in pairs(storage.the_cave_reset_respawn_pending or {}) do
        if type(ticket) == "table" and ticket.ready_tick and ticket.ready_tick <= game.tick then
            local player = game.get_player(index)
            local force = player and teams.player_force(player)
            if valid(player) and player.connected then
                local moved = true
                -- A team may have been released while this player was offline.
                -- Its old force index alone must not reclaim a spectator.
                if valid(force) and force.index == ticket.force_index then
                    local home = ticket_home(force, ticket)
                    if ticket.deferred and (player.controller_type == defines.controllers.remote
                        or physical.is_riding(player)) then
                        moved = false
                    elseif valid(home) and not worlds.is_template(home) then
                        local spawn = force.get_spawn_position(home)
                        local position = physical.find_position(player, home, spawn, 64) or spawn
                        moved = physical.teleport(player, position, home)
                    end
                    if moved then
                        if ticket.clear_items then soft_reset.clear_player_items(player) end
                        teams.queue_arrival(player)
                    end
                end
                -- A failed return waits and tries again instead of stopping the game.
                if moved then storage.the_cave_reset_respawn_pending[index] = nil
                else ticket.ready_tick = game.tick + 60 end
            end
        end
    end
    delete_emptied_surfaces()
end

function lifecycle.on_arrival(player, surface, force)
    if defeat.is_active(force) or soft_reset.is_active() then return end
    if not lifecycle.has_base(force) and (worlds.is_original(surface) or worlds.owner_force(surface) == force) then
        trains.on_arrival(player)
        shelters.on_arrival(player)
    end
    local base = lifecycle.base_surface(force)
    if valid(base) then teams.set_home(force, base) end
    if not surface.name:find("^the%-cave%-warp%-") and teams.start_work_needed(force, surface) then
        charting.for_force_world(force, surface)
        nests.capture_start_anchor(surface)
        teams.mark_start_work(force, surface)
    end
    advancing.start_world(surface)
    oil.on_arrival(player)
    bodies.on_arrival(player)
end

function lifecycle.on_init()
    world_events.on_init()
end

-- 3.3.1 cleared and charted each force once, recorded in storage.chart_reset.
-- Seed those forces' start marks so an upgraded save keeps its explored map.
local function migrate_chart_marks()
    for key in pairs(storage.chart_reset or {}) do
        local force = game.forces[key]
        if valid(force) then
            local home = teams.home_surface(force)
            if valid(home) then teams.mark_start_work(force, home) end
            for index in pairs(storage.cave_worlds or {}) do
                if worlds.owner_force(index) == force then teams.mark_start_work(force, game.surfaces[index]) end
            end
        end
    end
end

function lifecycle.on_configuration_changed()
    -- Migrate base keys before looking up owners in an existing save.
    trains._migrate_force_keys()
    defeat.on_configuration_changed()
    local migrated = world_events.on_configuration_changed()
    if depths.on_configuration_changed then depths.on_configuration_changed() end
    for _, force in ipairs(teams.active_forces()) do
        local home = lifecycle.base_surface(force) or teams.home_surface(force)
        if valid(home) then teams.set_home(force, home) end
    end
    if migrated then migrate_chart_marks() end
    for _, player in pairs(game.players) do teams.queue_arrival(player) end
end

function lifecycle.on_force_reset(event)
    lifecycle.sync_force(event.force)
    if teams.is_resetting(event.force) or soft_reset.is_active() then return end
    -- Another mod may reset research without ending the team. Teardown belongs
    -- to on_pre_surface_deleted and on_forces_merged.
    defeat.apply_truce(event.force)
end

function lifecycle.on_forces_merged(event)
    worlds.transfer_owner(event.source_index, event.destination.index)
    for _, module in ipairs(children) do module.transfer_force(event.source_index, event.destination.index) end
    local surfaces = lifecycle.owned_surfaces(event.source_index)
    local occupied = evacuate(surfaces, nil, teams.home_surface(event.destination), false)
    defeat.finish(event.source_index)
    clear_force(event.source_index)
    queue_deletion(surfaces, occupied, event.source_index)
    lifecycle.sync_force(event.destination)
    local s = storage.the_cave_teams
    if s then s.starts[event.destination.index] = nil end
    for _, player in pairs(event.destination.players) do teams.queue_arrival(player) end
end

function lifecycle.on_pre_surface_deleted(event)
    local surface = game.surfaces[event.surface_index]
    if not valid(surface) or not worlds.is_cave_world(surface) or soft_reset.is_active() then return end
    local affected = {}
    for _, force in ipairs(teams.active_forces()) do
        if teams.home_surface(force) == surface then affected[#affected + 1] = force end
    end
    storage.the_cave_deleting_world = surface.index
    for _, force in ipairs(affected) do
        local surfaces = lifecycle.owned_surfaces(force)
        -- Foreign deletion normally follows the team mod's evacuation. Keep a
        -- visitor safe on the still-live main world if it has no other home.
        local occupied = evacuate(surfaces, nil, nil, false)
        defeat.finish(force)
        clear_force(force.index)
        queue_deletion(surfaces, occupied, force.index)
    end
    storage.the_cave_deleting_world = nil
end

function lifecycle.on_surface_deleted(event)
    if game.surfaces[event.surface_index] then return end
    world_events.on_surface_deleted(event)
    teams.drop_surface(event.surface_index)
    trains.on_surface_deleted(event)
    oil.on_surface_deleted(event)
    bodies.on_surface_deleted(event)
end

teams.configure {
    has_base = lifecycle.has_base, base_surface = lifecycle.base_surface,
    arrival = lifecycle.on_arrival, defeated = defeat.is_active,
    child_owner = function(surface)
        for _, module in ipairs(children) do
            local force = module.owner_force(surface)
            if force then return force end
        end
    end,
}
defeat.configure { active_forces = teams.active_forces, player_force = teams.player_force }
world_events.configure {
    on_copy_registered = teams.queue_surface,
    on_source_chunk_generated = trains.on_chunk_generated,
    resolve_owner = function(surface)
        for _, force in pairs(game.forces) do
            if lifecycle.base_surface(force) == surface then return force end
        end
        for _, player in pairs(game.players) do
            if player.controller_type == defines.controllers.character and valid(player.character)
                and player.character.surface == surface then return player.force end
        end
    end,
}

-- the-cave-v1. get_event_id(name) returns the id of one of these events; look
-- it up again in on_init, on_configuration_changed and on_load, never cache it.
--   on_force_defeated: { force_index, force_name, reason, scope = "force" | "server" }
--   on_owned_surface_changed: { surface_index, surface_name, force_index,
--       change = "created" | "deleted" }, raised whenever The Cave creates, or
--       queues the deletion of, a surface that get_owned_surfaces(force) lists
--       (train interiors and garden, shelter interior and garden, uranium,
--       mineral, fortified vault and lost city caves). "deleted" comes while the
--       surface is still valid; the engine deletes it later.
remote.add_interface("the-cave-v1", {
    get_event_id = function(name)
        if name == "on_force_defeated" then return defeated_event end
        if name == "on_owned_surface_changed" then return owned_surface_event end
    end,
    register_adapter = teams.register_adapter,
    get_owned_surfaces = function(index)
        local names = {}
        for _, surface in ipairs(lifecycle.owned_surfaces(index)) do names[#names + 1] = surface.name end
        return names
    end,
})

lifecycle.on_area_cloned = world_events.on_area_cloned
return lifecycle
