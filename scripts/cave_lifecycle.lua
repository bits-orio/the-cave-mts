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

local function valid(object) return object and object.valid end

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

local function queue_deletion(surfaces)
    for _, surface in ipairs(surfaces) do
        if valid(surface) then game.delete_surface(surface) end
    end
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

local function evacuate(surfaces, defeated_force, fallback, clear_items)
    local removed = {}
    for _, surface in ipairs(surfaces) do removed[surface.index] = true end
    for _, player in pairs(game.players) do
        local force = teams.player_force(player)
        local affected = force == defeated_force
        local surface = physical.surface(player)
        local viewing_removed = valid(player.surface) and removed[player.surface.index]
        if affected or (valid(surface) and removed[surface.index]) or viewing_removed then
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
                if not moved then error("The Cave could not evacuate player " .. player.name) end
                if affected and clear_items then
                    soft_reset.destroy_player_guis(player)
                    soft_reset.clear_player_items(player)
                end
            else
                -- Never delete an occupied cave when its safe destination vanished.
                if valid(surface) and removed[surface.index] then
                    error("The Cave has no safe home for player " .. player.name)
                end
            end
        end
    end
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

function lifecycle.reset_force(force, reason)
    if not valid(force) or teams.is_resetting(force) then return false end
    local home = teams.home_surface(force)
    if not valid(home) then return false end
    local surfaces = lifecycle.owned_surfaces(force)
    local spawn = force.get_spawn_position(home)
    -- Block arrival and destruction callbacks for the entire synchronous reset.
    teams.set_resetting(force, true)
    local ok, err = xpcall(function()
        evacuate(surfaces, force, home, true)
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
        queue_deletion(surfaces)
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
    if not ok then error(err) end
    raise_defeat(force, reason, "force")
    return true
end

function lifecycle.on_defeated(reason, options)
    options = options or {}
    local force = game.forces[options.force_index or "player"]
    if not valid(force) or teams.is_resetting(force) then return false end
    if #teams.other_team_forces(force) > 0 then return lifecycle.reset_force(force, reason) end
    options.force_index = force.index
    return soft_reset.start(reason, options)
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

function lifecycle.on_tick()
    for index, ticket in pairs(storage.the_cave_reset_respawn_pending or {}) do
        if type(ticket) == "table" and ticket.ready_tick and ticket.ready_tick <= game.tick then
            local player = game.get_player(index)
            local force = player and teams.player_force(player)
            if valid(player) and player.connected then
                -- A team may have been released while this player was offline.
                -- Its old force index alone must not reclaim a spectator.
                if valid(force) and force.index == ticket.force_index then
                    local home = teams.home_surface(force)
                    if valid(home) and not worlds.is_template(home) then
                        local spawn = force.get_spawn_position(home)
                        local position = physical.find_position(player, home, spawn, 64) or spawn
                        if not physical.teleport(player, position, home) then
                            error("The Cave could not finish the return of player " .. player.name)
                        end
                    end
                    if ticket.clear_items then soft_reset.clear_player_items(player) end
                    teams.queue_arrival(player)
                end
                storage.the_cave_reset_respawn_pending[index] = nil
            end
        end
    end
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

function lifecycle.on_configuration_changed()
    -- Migrate base keys before looking up owners in an existing save.
    trains._migrate_force_keys()
    defeat.on_configuration_changed()
    world_events.on_configuration_changed()
    if depths.on_configuration_changed then depths.on_configuration_changed() end
    for _, force in ipairs(teams.active_forces()) do
        local home = lifecycle.base_surface(force) or teams.home_surface(force)
        if valid(home) then teams.set_home(force, home) end
    end
    for _, player in pairs(game.players) do teams.queue_arrival(player) end
end

function lifecycle.on_force_reset(event)
    lifecycle.sync_force(event.force)
    if teams.is_resetting(event.force) or soft_reset.is_active() then return end
    if lifecycle.has_base(event.force) then
        defeat.apply_truce(event.force)
        return
    end
    local surfaces = lifecycle.owned_surfaces(event.force)
    local home = teams.home_surface(event.force)
    evacuate(surfaces, nil, home, false)
    defeat.finish(event.force)
    clear_force(event.force.index, true)
    queue_deletion(surfaces)
end

function lifecycle.on_forces_merged(event)
    worlds.transfer_owner(event.source_index, event.destination.index)
    for _, module in ipairs(children) do module.transfer_force(event.source_index, event.destination.index) end
    local surfaces = lifecycle.owned_surfaces(event.source_index)
    evacuate(surfaces, nil, teams.home_surface(event.destination), false)
    defeat.finish(event.source_index)
    clear_force(event.source_index)
    queue_deletion(surfaces)
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
        evacuate(surfaces, nil, nil, false)
        defeat.finish(force)
        clear_force(force.index)
        queue_deletion(surfaces)
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

remote.add_interface("the-cave-v1", {
    get_event_id = function(name) if name == "on_force_defeated" then return defeated_event end end,
    register_adapter = teams.register_adapter,
    get_owned_surfaces = function(index)
        local names = {}
        for _, surface in ipairs(lifecycle.owned_surfaces(index)) do names[#names + 1] = surface.name end
        return names
    end,
})

lifecycle.on_area_cloned = world_events.on_area_cloned
return lifecycle
