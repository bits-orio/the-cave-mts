-- Gameplay modules depend on this leaf coordinator, never on a team mod.
local worlds = require("scripts.cave_worlds")
local physical = require("scripts.player_physical")
local teams = {}
local callbacks = {}

local function state()
    storage.the_cave_teams = storage.the_cave_teams or {}
    local s = storage.the_cave_teams
    s.homes = s.homes or {}
    s.pending = s.pending or {}
    s.physical = s.physical or {}
    s.starts = s.starts or {}
    s.suppress = s.suppress or {}
    s.resetting = s.resetting or {}
    return s
end

local function force_for(force)
    if type(force) == "number" or type(force) == "string" then return game.forces[force] end
    return force
end

-- Adapter answers for the current tick. Every read of remote.interfaces builds
-- a new table, and per-tick systems ask the same questions many times a tick.
-- Built only from game state and keyed by game.tick, so every peer, including
-- one that just joined, derives the same contents.
local cache = {}

local function tick_cache()
    if cache.tick ~= game.tick then
        local name = storage.the_cave_team_adapter
        cache = { tick = game.tick, name = name, methods = name and remote.interfaces[name] or {}, answers = {} }
    end
    return cache
end

local function adapter_call(method, ...)
    local c = tick_cache()
    if c.name and c.methods[method] then
        local ok, result = pcall(remote.call, c.name, method, ...)
        if ok then return result end
        log("The Cave team adapter " .. c.name .. "." .. method .. ": " .. tostring(result))
    end
end

local NONE = {}

-- A per-tick memo of adapter_call(method, index).
local function adapter_answer(method, index)
    local answers = tick_cache().answers
    answers[method] = answers[method] or {}
    local result = answers[method][index]
    if result == nil then
        result = adapter_call(method, index)
        if result == nil then result = NONE end
        answers[method][index] = result
    end
    if result == NONE then return nil end
    return result
end

function teams.configure(options) callbacks = options or {} end

-- on_owned_surface_changed: cave_lifecycle generates the id in the main chunk
-- and publishes it through the-cave-v1. Modules report each surface that
-- get_owned_surfaces(force) would list where they create it or queue its
-- deletion.
local owned_surface_event = nil

function teams.set_owned_surface_event(id) owned_surface_event = id end

function teams.raise_owned_surface(surface, force, change)
    force = force_for(force)
    if not (owned_surface_event and surface and surface.valid and force and force.valid) then return end
    script.raise_event(owned_surface_event, {
        surface_index = surface.index, surface_name = surface.name, force_index = force.index, change = change,
    })
end

-- game.delete_surface for an owned surface; reports it once it is queued.
function teams.delete_owned_surface(surface, force)
    if not (surface and surface.valid) then return false end
    local queued = game.delete_surface(surface)
    if queued then teams.raise_owned_surface(surface, force, "deleted") end
    return queued
end

function teams.register_adapter(name)
    if type(name) ~= "string" or not remote.interfaces[name] then return false end
    storage.the_cave_team_adapter = name
    cache = {}
    return true
end

function teams.player_force(player)
    if not (player and player.valid) then return nil end
    local index = adapter_answer("effective_force", player.index)
    local force = index and game.forces[index]
    return force and force.valid and force or player.force
end

-- Connected players with their effective force, home and current world (the
-- physical surface when the force owns it, else the home), once per tick.
-- Entries can go stale within the tick, so callers check player.valid.
function teams.residents()
    local c = tick_cache()
    if not c.residents then
        local list = {}
        for _, player in pairs(game.connected_players) do
            local force = teams.player_force(player)
            local home = teams.home_surface(force)
            local surface = physical.surface(player)
            local world = surface and worlds.owner_force(surface) == force and surface or home
            list[#list + 1] = { player = player, force = force, home = home, world = world }
        end
        c.residents = list
    end
    return c.residents
end

function teams.has_base(force)
    force = force_for(force)
    return force and force.valid and callbacks.has_base and callbacks.has_base(force) or false
end

function teams.home_surface(force)
    force = force_for(force)
    if not (force and force.valid) then return nil end
    local surface = callbacks.base_surface and callbacks.base_surface(force)
    if surface and surface.valid and worlds.is_cave_world(surface) and not worlds.is_template(surface) then
        return surface
    end
    local row = state().homes[force.index]
    surface = row and game.surfaces[row.index]
    if surface and surface.valid and surface.name == row.name and worlds.is_cave_world(surface)
        and not worlds.is_template(surface) then return surface end
    -- Ownership survives the staged reset's state wipe and legacy migrations.
    for _, candidate in pairs(game.surfaces) do
        if worlds.owner_force(candidate) == force and not worlds.is_template(candidate) then return candidate end
    end
end

function teams.set_home(force, surface)
    force = force_for(force)
    if not (force and force.valid and surface and surface.valid)
        or not worlds.is_cave_world(surface) or worlds.is_template(surface) then return false end
    state().homes[force.index] = { index = surface.index, name = surface.name }
    return true
end

function teams.force_is_active(force)
    force = force_for(force)
    if not (force and force.valid) then return false end
    if teams.has_base(force) then return true end
    for index in pairs(storage.cave_worlds or {}) do
        if worlds.owner_force(index) == force and not worlds.is_template(index) then return true end
    end
    return false
end

function teams.active_forces()
    local result = {}
    for _, force in pairs(game.forces) do
        if teams.force_is_active(force) then result[#result + 1] = force end
    end
    table.sort(result, function(a, b) return a.index < b.index end)
    return result
end

function teams.other_team_forces(force)
    local result = {}
    for _, other in ipairs(teams.active_forces()) do
        if other ~= force then result[#result + 1] = other end
    end
    return result
end

function teams.team_label(force) return force.name end

function teams.owner_force(surface, acting_force)
    if surface and surface.valid then
        local child_owner = callbacks.child_owner and callbacks.child_owner(surface)
        if child_owner then return child_owner end
        local owner = worlds.owner_force(surface)
        if owner then return owner end
    end
    return acting_force and acting_force.valid and acting_force or game.forces.player
end
teams.surface_owner_force = teams.owner_force

function teams.is_ready(force)
    return force and force.valid and adapter_answer("force_ready", force.index) ~= false
end

-- A paused force's surfaces belong to the team mod's pause until it resumes.
function teams.is_paused(force)
    force = force_for(force)
    return force and force.valid and adapter_answer("force_paused", force.index) == true or false
end

function teams.force_is_running(force)
    force = force_for(force)
    return force and force.valid and teams.is_ready(force)
        and adapter_answer("force_paused", force.index) ~= true
        and not (callbacks.defeated and callbacks.defeated(force)) or false
end

function teams.is_world_running(surface)
    if not worlds.is_active(surface) then return false end
    local force = worlds.owner_force(surface)
    if teams.force_is_running(force) then return true end
    -- Several forces may share an original world. One truce or pause must not
    -- stop that world's enemies and clock for an unaffected resident team.
    for _, other in ipairs(teams.active_forces()) do
        if other ~= force and teams.home_surface(other) == surface and teams.force_is_running(other) then return true end
    end
    return false
end

function teams.is_resetting(force)
    local index = type(force) == "number" and force or force.index
    return state().resetting[index] == true
end

function teams.set_resetting(force, value)
    state().resetting[force.index] = value and true or nil
end

function teams.queue_arrival(player, delay)
    if type(player) == "number" then player = game.get_player(player) end
    if player and player.valid then state().pending[player.index] = game.tick + (delay or 2) end
end

function teams.queue_surface(surface)
    for _, player in pairs(game.players) do
        if player.character and player.character.valid and player.character.surface == surface then
            teams.queue_arrival(player)
        end
    end
end

function teams.check_arrival(player)
    if not (player and player.valid and player.controller_type == defines.controllers.character
        and player.character and player.character.valid) then return false end
    local surface, force = player.character.surface, player.force
    if not worlds.is_cave_world(surface) or worlds.is_template(surface) then return false end
    local s = state()
    s.physical[player.index] = { index = surface.index, name = surface.name }
    local until_tick = s.suppress[force.index]
    if until_tick and game.tick < until_tick then
        teams.queue_arrival(player, until_tick - game.tick)
        return false
    end
    if s.resetting[force.index] then return false end
    if not teams.is_ready(force) then teams.queue_arrival(player, 60); return false end
    local previous_home = teams.home_surface(force)
    -- Also confirms a provisional migration owner when the actual player arrives.
    worlds.set_owner(surface, force)
    if not previous_home then
        teams.set_home(force, surface)
    elseif not s.homes[force.index] then
        teams.set_home(force, previous_home)
    end
    if callbacks.arrival then callbacks.arrival(player, surface, force) end
    return true
end

function teams.start_work_needed(force, surface)
    local marks = state().starts[force.index]
    return not marks or marks[surface.index] ~= surface.name
end

function teams.mark_start_work(force, surface)
    local s = state()
    s.starts[force.index] = s.starts[force.index] or {}
    s.starts[force.index][surface.index] = surface.name
end

function teams.on_player_changed_surface(event)
    local player = game.get_player(event.player_index)
    local surface = player and player.character and player.character.valid and player.character.surface
    if not surface then return end
    local previous = state().physical[player.index]
    state().physical[player.index] = { index = surface.index, name = surface.name }
    if not previous or previous.index ~= surface.index or previous.name ~= surface.name then
        teams.queue_arrival(player)
    end
end

function teams.on_player_controller_changed(event)
    local player = game.get_player(event.player_index)
    if player and player.controller_type == defines.controllers.character then teams.queue_arrival(player) end
end

function teams.on_tick()
    local s = state()
    local ready = {}
    for index, tick in pairs(s.pending) do if tick <= game.tick then ready[#ready + 1] = index end end
    table.sort(ready)
    for _, index in ipairs(ready) do
        s.pending[index] = nil
        teams.check_arrival(game.get_player(index))
    end
end

function teams.clear_force(index, keep_home)
    local s = state()
    if not keep_home then s.homes[index] = nil end
    s.starts[index], s.suppress[index], s.resetting[index] = nil, nil, nil
end

function teams.suppress_arrivals(force, ticks)
    state().suppress[force.index] = game.tick + ticks
    for _, player in pairs(game.players) do
        if player.force == force then teams.queue_arrival(player, ticks) end
    end
end

function teams.drop_surface(index)
    local s = state()
    for _, marks in pairs(s.starts) do marks[index] = nil end
    for force_index, home in pairs(s.homes) do
        if home.index == index then s.homes[force_index] = nil end
    end
end

return teams
