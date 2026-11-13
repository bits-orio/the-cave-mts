-- Keep the normal character mining action/progress bar and robot behavior.
-- Only the character currently selecting a roof support is compensated for
-- force/personal speed bonuses; no force research or global speed is changed.
local mining = {}
local names = {}
for _, variant in ipairs(require("shared.roof_support")) do names[variant.name] = true end

local function records()
    storage.roof_support_mining = storage.roof_support_mining or {}
    return storage.roof_support_mining
end

function mining.clear(player_index)
    local all = records()
    local record = all[player_index]
    if not record then return end
    local character = record.character
    -- Respect a later modifier written by another system rather than restoring
    -- our older value over it. Invalid/detached characters need no player access.
    if character.valid and character.character_mining_speed_modifier == record.applied then
        character.character_mining_speed_modifier = record.original
    end
    all[player_index] = nil
end

function mining.sync(player)
    if not (player and player.valid) then return end
    local character, selected = player.character, player.selected
    if not (player.connected and player.controller_type == defines.controllers.character
        and character and character.valid and selected and selected.valid
        and names[selected.name]) then
        mining.clear(player.index)
        return
    end
    local all, record = records(), records()[player.index]
    if record and record.character ~= character then mining.clear(player.index); record = nil end
    local current = character.character_mining_speed_modifier
    if not record then
        record = {character = character, original = current}
        all[player.index] = record
    elseif current ~= record.applied then
        -- For example the admin kit can change the personal bonus while the
        -- cursor is over a support. Preserve that new bonus for other targets.
        record.original = current
    end
    local base = character.prototype.mining_speed
    local force_multiplier = 1 + character.force.manual_mining_speed_modifier
    if not (base and base > 0 and force_multiplier > 0) then
        mining.clear(player.index)
        return
    end
    local applied = 0.5 / (base * force_multiplier) - 1
    if current ~= applied then character.character_mining_speed_modifier = applied end
    record.applied = applied
end

function mining.on_context_changed(event)
    mining.sync(game.get_player(event.player_index))
end

function mining.sync_force(force)
    if not (force and force.valid) then return end
    for index in pairs(records()) do
        local player = game.get_player(index)
        if player and player.valid and player.force == force then mining.sync(player) end
    end
end

function mining.on_removed(entity)
    if not (entity and entity.valid and names[entity.name]) then return end
    for index, record in pairs(records()) do
        local player = game.get_player(index)
        if not (player and player.valid) or player.selected == entity then mining.clear(index) end
    end
end

function mining.on_tick()
    -- The table is empty when no player is selecting a roof support.
    -- Never scan surfaces or iterate all players each tick.
    for index in pairs(records()) do
        local player = game.get_player(index)
        if player then mining.sync(player) else mining.clear(index) end
    end
end

function mining.restore_all()
    for index in pairs(records()) do mining.clear(index) end
end

function mining.initialize()
    mining.restore_all()
    for _, player in pairs(game.connected_players) do mining.sync(player) end
end

return mining
