-- Temporary safety belongs to the force whose Main Train or shelter was lost.
-- Keep asymmetric enemy relationships so ending one truce cannot affect a team
-- whose own countdown is still running.
local defeat = {}
local callbacks = {}

local function valid(object)
    return object and object.valid
end

local function force_index(force)
    return type(force) == "number" and force or (valid(force) and force.index or nil)
end

local function player_force(player)
    return callbacks.player_force and callbacks.player_force(player) or player.force
end

function defeat.configure(options)
    callbacks = options or {}
end

function defeat.state(force)
    local reset = storage.the_cave_soft_reset
    local states = storage.the_cave_main_train_defeat or (reset and reset.main_train_defeat)
    if force ~= nil then return states and states[force_index(force)] or nil end
    return states
end

function defeat.is_active(force)
    local state = defeat.state(force)
    return state ~= nil and (force ~= nil or next(state) ~= nil)
end

function defeat.blocks_all()
    if not defeat.is_active() then return false end
    for _, force in pairs(callbacks.active_forces and callbacks.active_forces() or {}) do
        if valid(force) and not defeat.is_active(force) then return false end
    end
    return true
end

local function protect_force(force, state)
    local enemy = game.forces.enemy
    if not (valid(force) and valid(enemy)) or force == enemy or force.name == "neutral" then return end
    if not state.relations then
        state.relations = {
            friend = force.get_friend(enemy),
            cease_fire = force.get_cease_fire(enemy),
            enemy_friend = enemy.get_friend(force),
            enemy_cease_fire = enemy.get_cease_fire(force),
        }
    end
    force.set_friend(enemy, true)
    force.set_cease_fire(enemy, true)
    enemy.set_friend(force, true)
    enemy.set_cease_fire(force, true)
end

function defeat.apply_truce(force)
    local states = defeat.state()
    if not states then return end
    for index, state in pairs(states) do
        if force == nil or index == force_index(force) then protect_force(game.forces[index], state) end
    end
end

function defeat.protect_player(player)
    if not valid(player) then return end
    local states = defeat.state()
    if not states then return end
    local force = player_force(player)
    local index = force_index(force)
    -- A spectator/force change does not keep immunity from the old team.
    for other_index, state in pairs(states) do
        local previous = state.characters[player.index]
        if previous and other_index ~= index then
            if valid(previous.entity) then previous.entity.destructible = previous.destructible end
            state.characters[player.index] = nil
        end
    end
    local state = index and states[index]
    if not state then return end
    protect_force(force, state)
    local character = player.cutscene_character or player.character
    if not valid(character) then return end
    local previous = state.characters[player.index]
    if not previous or previous.entity ~= character then
        if previous and valid(previous.entity) then previous.entity.destructible = previous.destructible end
        state.characters[player.index] = { entity = character, destructible = character.destructible }
    end
    character.destructible = false
end

function defeat.begin(force)
    force = force or game.forces.player
    if not valid(force) then return end
    local states = defeat.state() or {}
    storage.the_cave_main_train_defeat = states
    states[force.index] = states[force.index] or { force_index = force.index, characters = {} }
    defeat.apply_truce(force)
    for _, player in pairs(game.players) do defeat.protect_player(player) end
end

function defeat.on_tick(event)
    if not defeat.is_active() then return false end
    if event.tick % 60 == 0 then
        defeat.apply_truce()
        for _, player in pairs(game.players) do defeat.protect_player(player) end
    end
    return defeat.blocks_all()
end

function defeat.patch_force_snapshots(snapshots)
    for _, snapshot in ipairs(snapshots) do
        local state = defeat.state(snapshot.index)
        local original = state and state.relations
        if original then
            snapshot.friends.enemy = original.friend
            snapshot.cease_fire.enemy = original.cease_fire
        end
    end
end

function defeat.respawn_before_return(player)
    -- A death timer identifies a dead participant. Spectators and editor/god
    -- controllers with no death timer keep their selected controller.
    if not valid(player) or player.ticks_to_respawn == nil then return end
    if not player.connected then
        storage.the_cave_reset_respawn_pending = storage.the_cave_reset_respawn_pending or {}
        if type(storage.the_cave_reset_respawn_pending[player.index]) ~= "table" then
            storage.the_cave_reset_respawn_pending[player.index] = true
        end
        return
    end
    player.ticks_to_respawn = nil
    if not valid(player.character) then
        error("could not respawn player " .. tostring(player.name or player.index) .. " before returning to the cave")
    end
    defeat.protect_player(player)
end

function defeat.on_player_joined(player)
    if not valid(player) then return end
    local pending = storage.the_cave_reset_respawn_pending
    if pending and pending[player.index] then
        defeat.respawn_before_return(player)
        local ticket = pending[player.index]
        if type(ticket) == "table" then
            -- Other mods can grant starting items from the respawn/join events.
            -- The coordinator finalizes this return after those events settle.
            ticket.ready_tick = game.tick + 2
        else
            pending[player.index] = nil
            if not next(pending) then storage.the_cave_reset_respawn_pending = nil end
        end
    end
    defeat.protect_player(player)
end

function defeat.finish(force)
    local states = defeat.state()
    if not states then return end
    local enemy = game.forces.enemy
    for index, state in pairs(states) do
        if force == nil or index == force_index(force) then
            local target = game.forces[index]
            local record = state.relations
            if valid(target) and valid(enemy) and record then
                target.set_friend(enemy, record.friend)
                target.set_cease_fire(enemy, record.cease_fire)
                enemy.set_friend(target, record.enemy_friend)
                enemy.set_cease_fire(target, record.enemy_cease_fire)
            end
            for _, character in pairs(state.characters or {}) do
                if valid(character.entity) then character.entity.destructible = character.destructible end
            end
            states[index] = nil
        end
    end
    if not next(states) then
        storage.the_cave_main_train_defeat = nil
        local reset = storage.the_cave_soft_reset
        if reset then reset.main_train_defeat = nil end
    end
end

function defeat.on_configuration_changed()
    local old = defeat.state()
    if not (old and old.forces) then return end
    local states = {}
    for name, record in pairs(old.forces) do
        local force = game.forces[record.index] or game.forces[name]
        if valid(force) then
            states[force.index] = { force_index = force.index, relations = record, characters = {} }
        end
    end
    for index, record in pairs(old.characters or {}) do
        local player = game.get_player(index)
        local force = valid(player) and player_force(player)
        local state = valid(force) and states[force.index]
        if state then state.characters[index] = record
        elseif valid(record.entity) then record.entity.destructible = record.destructible end
    end
    storage.the_cave_main_train_defeat = next(states) and states or nil
    local reset = storage.the_cave_soft_reset
    if reset then reset.main_train_defeat = storage.the_cave_main_train_defeat end
end

return defeat
