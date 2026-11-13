local settings = require("scripts.game_settings").proxy(settings)

-- The Cave: Auto Inventory Repair
-- Adapted from Inventory Repair by calcwizard (MIT License).
-- Repairs damaged placeable item stacks in player main inventories using repair packs.

local inventory_repair = {}

local MATH_CEIL = math.ceil
local INTERVAL = 30

local function state()
    storage.the_cave_inventory_repair = storage.the_cave_inventory_repair or {}
    local s = storage.the_cave_inventory_repair
    s.players = s.players or {}
    s.repair_tools = s.repair_tools or {}
    return s
end

local function enabled()
    local setting = settings and settings.startup and settings.startup["the-cave-auto-inventory-repair"]
    if not setting then return true end
    return setting.value == "enabled" or setting.value == true
end

local function reverse_table(t)
    local len = #t
    for i = 1, len / 2 do
        t[i], t[len - i + 1] = t[len - i + 1], t[i]
    end
end

local function get_quality_list()
    local qualities = { "normal" }
    if prototypes and prototypes.quality then
        qualities = {}
        for name in pairs(prototypes.quality) do
            if name ~= "quality-unknown" then
                table.insert(qualities, name)
            end
        end
        if #qualities == 0 then qualities = { "normal" } end
        table.sort(qualities, function(q1, q2)
            local p1 = prototypes.quality[q1]
            local p2 = prototypes.quality[q2]
            return (p1 and p1.level or 0) > (p2 and p2.level or 0)
        end)
    end
    return qualities
end

function inventory_repair.index_tools()
    local s = state()
    local qualities = get_quality_list()
    local tools, inf_tools = {}, {}

    local filtered = {}
    if prototypes and prototypes.get_item_filtered then
        filtered = prototypes.get_item_filtered({ { filter = "type", type = "repair-tool" } }) or {}
    end

    for name, proto in pairs(filtered) do
        if proto.infinite then
            table.insert(inf_tools, name)
        else
            table.insert(tools, name)
        end
    end

    table.sort(inf_tools, function(a, b)
        return (prototypes.item[a].speed or 0) > (prototypes.item[b].speed or 0)
    end)

    -- Use normal finite repair packs first when possible, preserving better/faster tools.
    table.sort(tools, function(a, b)
        return (prototypes.item[a].speed or 0) > (prototypes.item[b].speed or 0)
    end)
    reverse_table(tools)

    s.repair_tools = {}

    -- Infinite tools first because they cost no durability.
    for _, name in pairs(inf_tools) do
        for _, quality in pairs(qualities) do
            table.insert(s.repair_tools, { name = name, quality = quality })
        end
    end

    for _, name in pairs(tools) do
        for _, quality in pairs(qualities) do
            table.insert(s.repair_tools, { name = name, quality = quality })
        end
    end
end

local function get_max_health(place_result, quality)
    if not place_result then return nil end
    if place_result.get_max_health then
        local ok, result = pcall(function() return place_result.get_max_health(quality) end)
        if ok and result then return result end
    end
    -- LuaEntityPrototype.max_health is not exposed in the Factorio 2.0 runtime API.
    -- If a third-party prototype does not support get_max_health, skip it safely.
    return nil
end

-- Performs one interval of repair on a damaged item stack using one repair tool stack.
local function repair_item(repair_pack, damaged_item, time)
    if not (repair_pack and repair_pack.valid_for_read and damaged_item and damaged_item.valid_for_read) then
        return false
    end

    local place_result = damaged_item.prototype and damaged_item.prototype.place_result
    if not place_result then return false end

    local max_health = get_max_health(place_result, damaged_item.quality)
    if not (max_health and max_health > 0 and damaged_item.health and damaged_item.health < 1) then
        return false
    end

    local curr_health = damaged_item.health * max_health
    local repair_modifier = place_result.repair_speed_modifier or 1
    local pack_speed = repair_pack.prototype and repair_pack.prototype.speed or 0
    local count = math.max(1, damaged_item.count or 1)
    local speed = pack_speed * repair_modifier / count
    if speed <= 0 then return false end

    local repair_amount = time
    if max_health - curr_health < repair_amount * speed then
        repair_amount = (max_health - curr_health) / speed
    end
    repair_amount = MATH_CEIL(repair_amount)
    if repair_amount <= 0 then return false end

    local remaining_durability = repair_pack.prototype.infinite and (1 / 0) or repair_pack.durability
    if not remaining_durability then return false end
    if remaining_durability < repair_amount then
        repair_amount = remaining_durability
    end
    if repair_amount <= 0 then return false end

    local ok = pcall(function() repair_pack.drain_durability(repair_amount) end)
    if not ok then return false end

    damaged_item.health = math.min(1, (curr_health + repair_amount * speed) / max_health)
    return true
end

local function find_damaged_item(inventory)
    if not inventory then return nil end
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read
            and stack.health
            and stack.health < 1
            and stack.prototype
            and stack.prototype.place_result then
            return stack
        end
    end
    return nil
end

local function find_repair_pack(inventory)
    if not inventory then return nil end
    local s = state()
    for _, tool in pairs(s.repair_tools or {}) do
        local stack = inventory.find_item_stack(tool)
        if stack and stack.valid_for_read then
            return stack
        end
    end
    return nil
end

local function instant_repair(player)
    local inventory = player.get_main_inventory()
    if not inventory then return end
    local repaired = false
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read and stack.health and stack.health < 1 then
            stack.health = 1
            repaired = true
        end
    end
    if repaired and player.auto_sort_main_inventory then
        inventory.sort_and_merge()
    end
end

local function check_inventory_for_repairs(player, time)
    if not (player and player.valid and player.connected) then return false end
    local inventory = player.get_main_inventory()
    if not inventory then return false end

    local repair_pack = find_repair_pack(inventory)
    if not repair_pack then return false end

    local damaged_item = find_damaged_item(inventory)
    if not damaged_item then return false end

    local performed = repair_item(repair_pack, damaged_item, time)
    if performed then
        if damaged_item.valid_for_read and damaged_item.health == 1 and player.auto_sort_main_inventory then
            inventory.sort_and_merge()
        end
        pcall(function()
            player.play_sound({ path = "the-cave-inventory-repair", position = player.position })
        end)
    end
    return performed
end

function inventory_repair.register_player(player_index)
    if not enabled() then return end
    if not player_index then return end
    state().players[player_index] = true
end

function inventory_repair.deregister_player(player_index)
    if not player_index then return end
    state().players[player_index] = nil
end

function inventory_repair.register_all_connected_players()
    if not enabled() then return end
    local s = state()
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid then
            s.players[player.index] = true
        end
    end
end

function inventory_repair.on_init()
    state()
    inventory_repair.index_tools()
    inventory_repair.register_all_connected_players()
end

function inventory_repair.on_configuration_changed()
    state()
    inventory_repair.index_tools()
    inventory_repair.register_all_connected_players()
end

function inventory_repair.on_player_created(event)
    inventory_repair.register_player(event.player_index)
end

function inventory_repair.on_player_joined_game(event)
    inventory_repair.register_player(event.player_index)
end

function inventory_repair.on_player_main_inventory_changed(event)
    inventory_repair.register_player(event.player_index)
end

function inventory_repair.on_player_left_game(event)
    inventory_repair.deregister_player(event.player_index)
end

function inventory_repair.on_runtime_mod_setting_changed(event)
    -- Auto Inventory Repair is a startup setting, so this is kept only as a safe no-op
    -- in case older saves still fire/runtime-check this handler.
    if event.setting ~= "the-cave-auto-inventory-repair" then return end
    if enabled() then
        inventory_repair.register_all_connected_players()
    else
        state().players = {}
    end
end

function inventory_repair.on_tick(event)
    if not enabled() then return end
    if event.tick % INTERVAL ~= 0 then return end

    local s = state()
    for player_index in pairs(s.players or {}) do
        local player = game.get_player(player_index)
        if not (player and player.valid and player.connected) then
            s.players[player_index] = nil
        elseif player.cheat_mode or player.controller_type == defines.controllers.editor then
            instant_repair(player)
            s.players[player_index] = nil
        else
            if not check_inventory_for_repairs(player, INTERVAL) then
                s.players[player_index] = nil
            end
        end
    end
end

return inventory_repair
