local settings = require("scripts.game_settings").proxy(settings)

-- The Cave: Ore Patch Protection
-- Optional startup rule. When enabled, new invalid buildings on resource patches
-- are destroyed, and invalid blueprint ghosts are removed. Existing buildings are
-- intentionally not scanned or removed.

local ore_protection = {}

local WARNING_INTERVAL = 300 -- 5 seconds at 60 UPS
local MESSAGE = "Ore Patch Protection: Invalid buildings cannot be placed on resource patches."

local ALLOWED_TYPES = {
    ["mining-drill"] = true,

    ["container"] = true,
    ["logistic-container"] = true,

    ["transport-belt"] = true,
    ["underground-belt"] = true,
    ["splitter"] = true,

    ["electric-pole"] = true,

    -- Vanilla / Space Age rail system
    ["straight-rail"] = true,
    ["curved-rail"] = true,
    ["elevated-straight-rail"] = true,
    ["elevated-curved-rail"] = true,
    ["rail-ramp"] = true,
    ["rail-support"] = true,
    ["rail-signal"] = true,
    ["rail-chain-signal"] = true,
    ["train-stop"] = true,

    -- Train rolling stock
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,

    -- Vehicles
    ["car"] = true,
    ["spider-vehicle"] = true,
}

local function enabled()
    local setting = settings.startup["the-cave-ore-patch-protection"]
    return setting and (setting.value == "enabled" or setting.value == true)
end

local function event_entity(event)
    return event and (event.entity or event.created_entity or event.destination)
end

local function effective_type(entity)
    if not (entity and entity.valid) then return nil end
    if entity.type == "entity-ghost" then
        return entity.ghost_type
    end
    return entity.type
end

local function is_allowed(entity)
    local t = effective_type(entity)
    return t and ALLOWED_TYPES[t] == true
end

local function has_resource_under(entity)
    if not (entity and entity.valid and entity.surface and entity.surface.valid) then return false end
    local area = entity.bounding_box
    if not area then return false end

    local resources = entity.surface.find_entities_filtered {
        area = area,
        type = "resource",
        limit = 1,
    }

    return resources and resources[1] ~= nil
end

local function get_player_from_event(event, entity)
    if event and event.player_index then
        return game.get_player(event.player_index)
    end

    -- Robot builds often have no player_index. Try to attribute to the entity's
    -- last user when Factorio provides one. If not available, stay silent rather
    -- than spamming everyone on the server.
    if entity and entity.valid then
        local ok, player = pcall(function() return entity.last_user end)
        if ok and player and player.valid then return player end
    end

    if event and event.robot and event.robot.valid then
        local ok, player = pcall(function() return event.robot.last_user end)
        if ok and player and player.valid then return player end
    end

    return nil
end

local function warn_player(player)
    if not (player and player.valid and player.connected) then return end
    storage.ore_patch_protection_warnings = storage.ore_patch_protection_warnings or {}

    local now = game.tick
    local last = storage.ore_patch_protection_warnings[player.index] or -WARNING_INTERVAL
    if now - last < WARNING_INTERVAL then return end

    storage.ore_patch_protection_warnings[player.index] = now
    player.print(MESSAGE)
end

function ore_protection.on_init()
    storage.ore_patch_protection_warnings = storage.ore_patch_protection_warnings or {}
end

local function item_to_refund(entity)
    if not (entity and entity.valid) then return nil end

    -- Ghosts do not consume an item yet, so they must not refund anything.
    if entity.type == "entity-ghost" then return nil end

    local ok, items = pcall(function()
        return entity.prototype.items_to_place_this
    end)

    if ok and items and items[1] and items[1].name then
        return items[1].name
    end

    return nil
end

local function refund_or_spill(entity, player)
    local item_name = item_to_refund(entity)
    if not item_name then return end

    local stack = { name = item_name, count = 1 }

    if player and player.valid and player.character then
        local inserted = player.insert(stack)
        if inserted >= 1 then return end
    end

    -- If the player inventory is full, or if this was robot/script placement
    -- with no player owner, spill the item safely near the invalid placement.
    if entity and entity.valid and entity.surface and entity.surface.valid then
        entity.surface.spill_item_stack {
            position = entity.position,
            stack = stack,
            enable_looted = true,
            allow_belts = false,
        }
    end
end

function ore_protection.on_built(event, refund_consumed_item)
    if not enabled() then return false end

    local entity = event_entity(event)
    if not (entity and entity.valid) then return false end

    -- Old buildings are not scanned. This function only reacts to new builds or
    -- new ghosts. If no resource exists anymore, the land is free to build on.
    if not has_resource_under(entity) then return false end
    if is_allowed(entity) then return false end

    local player = get_player_from_event(event, entity)

    -- Blueprint/entity ghosts are already handled correctly: remove the invalid
    -- ghost only. No refund is needed because no real item was consumed.
    if entity.type ~= "entity-ghost" then
        if not (refund_consumed_item and refund_consumed_item(event)) then
            refund_or_spill(entity, player)
        end
    end

    if entity.valid then
        entity.destroy()
    end

    warn_player(player)

    return true
end

return ore_protection
