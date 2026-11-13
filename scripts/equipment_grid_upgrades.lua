local M = {}

local TECH_PREFIX = "the-cave-equipment-grid-upgrade-"
local ARMOR_BASE = {
    ["modular-armor"] = true,
    ["power-armor"] = true,
    ["power-armor-mk2"] = true,
}
local VEHICLE_BASE = {
    ["tank"] = true,
    ["spidertron"] = true,
}
local VEHICLE_NAMES = {
    "tank", "spidertron",
    "the-cave-grid-tank-1", "the-cave-grid-tank-2", "the-cave-grid-tank-3",
    "the-cave-grid-spidertron-1", "the-cave-grid-spidertron-2", "the-cave-grid-spidertron-3",
}

local function get_level(force)
    if not (force and force.valid) then return 0 end
    local level = 0
    for i = 1, 3 do
        local tech = force.technologies[TECH_PREFIX .. i]
        if tech and tech.researched then level = i end
    end
    return level
end

local function parse_levelled_name(name)
    local base, level = name:match("^the%-cave%-grid%-(.+)%-(%d+)$")
    if base then return base, tonumber(level) end
    return nil, nil
end

local function armor_target_name(base_name, level)
    if level <= 0 then return base_name end
    return "the-cave-grid-" .. base_name .. "-" .. level
end

local function vehicle_target_name(base_name, level)
    if level <= 0 then return base_name end
    return "the-cave-grid-" .. base_name .. "-" .. level
end

local function safe_read(object, property)
    local ok, value = pcall(function() return object[property] end)
    if ok then return value end
    return nil
end

local function safe_quality_name(object)
    local quality = safe_read(object, "quality")
    if type(quality) == "string" then return quality end
    if quality then
        local ok, name = pcall(function() return quality.name end)
        if ok then return name end
    end
    return nil
end

local function spill_stack(surface, position, force, stack)
    if not (surface and surface.valid and stack and stack.name) then return end
    pcall(function()
        surface.spill_item_stack {
            position = position,
            stack = stack,
            enable_looted = true,
            allow_belts = false,
        }
    end)
end

local function snapshot_grid(grid)
    local out = {}
    if not grid then return out end
    for _, eq in pairs(grid.equipment) do
        out[#out + 1] = {
            name = eq.name,
            quality = safe_quality_name(eq),
            position = { x = eq.position.x, y = eq.position.y },
            energy = safe_read(eq, "energy"),
            shield = safe_read(eq, "shield"),
        }
    end
    return out
end

local function restore_grid(grid, items, surface, position, force)
    if not grid then
        for _, rec in ipairs(items or {}) do
            spill_stack(surface, position, force, {
                name = rec.name,
                count = 1,
                quality = rec.quality,
            })
        end
        return
    end

    for _, rec in ipairs(items or {}) do
        local spec = {
            name = rec.name,
            position = rec.position,
        }
        if rec.quality then spec.quality = rec.quality end

        local ok, placed = pcall(function()
            return grid.put(spec)
        end)
        if ok and placed then
            if rec.energy ~= nil then pcall(function() placed.energy = rec.energy end) end
            if rec.shield ~= nil then pcall(function() placed.shield = rec.shield end) end
        else
            -- Never silently delete equipment if another mod makes the new grid incompatible.
            spill_stack(surface, position, force, {
                name = rec.name,
                count = 1,
                quality = rec.quality,
            })
        end
    end
end

local function safe_get_tags(stack)
    local ok, tags = pcall(function() return stack.tags end)
    if ok then return tags end
    return nil
end

local function safe_set_tags(stack, tags)
    if not tags then return end
    pcall(function() stack.tags = tags end)
end

local function snapshot_inventory(inv)
    local slots = {}
    if not inv then return slots end
    for i = 1, #inv do
        local stack = inv[i]
        if stack.valid_for_read then
            slots[i] = {
                name = stack.name,
                count = stack.count,
                quality = safe_quality_name(stack),
                health = safe_read(stack, "health"),
                -- These properties throw when read from the wrong item type.
                durability = safe_read(stack, "durability"),
                ammo = safe_read(stack, "ammo"),
                tags = safe_get_tags(stack),
            }
        end
    end
    return slots
end

local function restore_inventory(inv, slots, surface, position, force)
    if not inv then
        for _, rec in pairs(slots or {}) do
            spill_stack(surface, position, force, {
                name = rec.name,
                count = rec.count,
                quality = rec.quality,
            })
        end
        return
    end

    inv.clear()
    for i, rec in pairs(slots or {}) do
        local stack = inv[i]
        local spec = {
            name = rec.name,
            count = rec.count,
        }
        if rec.quality then spec.quality = rec.quality end

        local ok, restored = pcall(function()
            return stack and stack.set_stack(spec)
        end)
        if ok and restored and stack and stack.valid_for_read then
            if rec.health ~= nil then pcall(function() stack.health = rec.health end) end
            if rec.durability ~= nil then pcall(function() stack.durability = rec.durability end) end
            if rec.ammo ~= nil then pcall(function() stack.ammo = rec.ammo end) end
            safe_set_tags(stack, rec.tags)
        else
            spill_stack(surface, position, force, spec)
        end
    end
end

local function upgrade_equipped_armor(player)
    if not (player and player.valid and player.character) then return end
    local inv = player.get_inventory(defines.inventory.character_armor)
    if not inv then return end
    local stack = inv[1]
    if not (stack and stack.valid_for_read) then return end

    local base_name = stack.name
    local parsed_base = parse_levelled_name(stack.name)
    if parsed_base and ARMOR_BASE[parsed_base] then
        base_name = parsed_base
    elseif not ARMOR_BASE[base_name] then
        return
    end

    local target = armor_target_name(base_name, get_level(player.force))
    if stack.name == target then return end

    local health = stack.health
    local grid_items = snapshot_grid(stack.grid)

    -- Armor items are not item-with-tags, so do not read/write stack.tags here.
    stack.set_stack { name = target, count = 1 }
    if health then pcall(function() stack.health = health end) end
    restore_grid(stack.grid, grid_items)
end

local INVENTORY_IDS = {
    defines.inventory.car_trunk,
    defines.inventory.car_ammo,
    defines.inventory.fuel,
    defines.inventory.burnt_result,
    defines.inventory.spider_trunk,
    defines.inventory.spider_ammo,
}

local function upgrade_vehicle_entity(entity)
    if not (entity and entity.valid) then return entity end

    local base_name = entity.name
    local parsed_base = parse_levelled_name(entity.name)
    if parsed_base and VEHICLE_BASE[parsed_base] then
        base_name = parsed_base
    elseif not VEHICLE_BASE[base_name] then
        return entity
    end

    local target = vehicle_target_name(base_name, get_level(entity.force))
    if entity.name == target then return entity end

    local data = {
        surface = entity.surface,
        position = entity.position,
        direction = entity.direction,
        force = entity.force,
        orientation = entity.orientation,
        health = entity.health,
        color = entity.color,
        disabled_by_script = entity.disabled_by_script,
        destructible = entity.destructible,
        name_label = nil,
        grid = snapshot_grid(entity.grid),
        inventories = {},
        driver = nil,
        passenger = nil,
    }

    pcall(function() data.name_label = entity.entity_label end)
    pcall(function() data.driver = entity.get_driver() end)
    pcall(function() data.passenger = entity.get_passenger() end)

    for _, inv_id in ipairs(INVENTORY_IDS) do
        local ok, inv = pcall(function() return entity.get_inventory(inv_id) end)
        if ok and inv then
            data.inventories[inv_id] = snapshot_inventory(inv)
        end
    end

    if data.driver then pcall(function() entity.set_driver(nil) end) end
    if data.passenger then pcall(function() entity.set_passenger(nil) end) end

    local old_surface = data.surface
    local old_pos = { x = data.position.x, y = data.position.y }
    entity.destroy()

    local new = old_surface.create_entity {
        name = target,
        position = old_pos,
        direction = data.direction,
        force = data.force,
        create_build_effect_smoke = false,
    }
    if not new then
        for _, slots in pairs(data.inventories) do
            restore_inventory(nil, slots, old_surface, old_pos, data.force)
        end
        restore_grid(nil, data.grid, old_surface, old_pos, data.force)
        return nil
    end

    pcall(function() new.orientation = data.orientation end)
    if data.health then pcall(function() new.health = data.health end) end
    if data.color then pcall(function() new.color = data.color end) end
    pcall(function() new.disabled_by_script = data.disabled_by_script end)
    pcall(function() new.destructible = data.destructible end)
    if data.name_label then pcall(function() new.entity_label = data.name_label end) end

    for inv_id, slots in pairs(data.inventories) do
        local ok, inv = pcall(function() return new.get_inventory(inv_id) end)
        if ok and inv then
            restore_inventory(inv, slots, old_surface, old_pos, data.force)
        else
            restore_inventory(nil, slots, old_surface, old_pos, data.force)
        end
    end
    restore_grid(new.grid, data.grid, old_surface, old_pos, data.force)

    if data.driver then pcall(function() new.set_driver(data.driver) end) end
    if data.passenger then pcall(function() new.set_passenger(data.passenger) end) end

    return new
end

function M.on_init()
end

function M.on_configuration_changed()
    for _, player in pairs(game.players) do
        upgrade_equipped_armor(player)
    end
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            for _, entity in pairs(surface.find_entities_filtered { name = VEHICLE_NAMES }) do
                upgrade_vehicle_entity(entity)
            end
        end
    end
end

function M.on_player_created(event)
    local player = game.get_player(event.player_index)
    if player then upgrade_equipped_armor(player) end
end

function M.on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    if player then upgrade_equipped_armor(player) end
end

function M.on_player_armor_inventory_changed(event)
    local player = game.get_player(event.player_index)
    if player then upgrade_equipped_armor(player) end
end

function M.on_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid) then return end
    if VEHICLE_BASE[entity.name] or parse_levelled_name(entity.name) then
        upgrade_vehicle_entity(entity)
    end
end

function M.on_research_finished(event)
    local research = event.research
    if not (research and research.valid and research.name:find(TECH_PREFIX, 1, true)) then return end
    for _, player in pairs(game.players) do
        if player.valid and player.force == research.force then
            upgrade_equipped_armor(player)
        end
    end
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            for _, entity in pairs(surface.find_entities_filtered {
                name = VEHICLE_NAMES,
                force = research.force,
            }) do
                upgrade_vehicle_entity(entity)
            end
        end
    end
end

return M
