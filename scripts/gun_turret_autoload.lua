local gun_turret_autoload = {}

local GUN_TURRET_NAME = "gun-turret"
local PLACEMENT_TARGET_MAGAZINES = 10
local AREA_RELOAD_MAGAZINES_PER_PRESS = 10
local HALF_AREA_SIZE = 10
local TURRET_AMMO_INVENTORY = defines.inventory.turret_ammo
local GUN_TURRET_NAMES = { GUN_TURRET_NAME }

for level = 1, 5 do
    local name = "the-cave-range-gun-turret-" .. tostring(level)
    if prototypes and prototypes.entity and prototypes.entity[name] then
        GUN_TURRET_NAMES[#GUN_TURRET_NAMES + 1] = name
    end
end

-- Vanilla magazine order is explicit so an empty turret receives the strongest
-- standard ammunition the player is carrying. Compatible modded ammunition is
-- still supported and falls back to prototype order.
local VANILLA_AMMO_TIER = {
    ["firearm-magazine"] = 1,
    ["piercing-rounds-magazine"] = 2,
    ["uranium-rounds-magazine"] = 3,
}

local function valid_player(player)
    return player and player.valid
end

local function is_supported_gun_turret(name)
    if name == GUN_TURRET_NAME then return true end
    local level = name and name:match("^the%-cave%-range%-gun%-turret%-(%d+)$")
    return level ~= nil and tonumber(level) <= 5
end

local function valid_player_turret(turret, player)
    return turret
        and turret.valid
        and is_supported_gun_turret(turret.name)
        and turret.force == player.force
        and turret.surface == player.surface
end

local function magazine_count(inventory)
    if not (inventory and inventory.valid) then return 0 end
    return inventory.get_item_count()
end

local function stack_quality(stack)
    local quality = stack.quality
    if quality then
        return quality.name, quality.level or 0
    end
    return "normal", 0
end

local function existing_magazine(inventory)
    for index = 1, #inventory do
        local stack = inventory[index]
        if stack and stack.valid_for_read then
            local quality = stack_quality(stack)
            return {
                name = stack.name,
                quality = quality,
            }
        end
    end
end

local function candidate_is_better(candidate, current)
    if not current then return true end
    if candidate.tier ~= current.tier then
        return candidate.tier > current.tier
    end
    if candidate.quality_level ~= current.quality_level then
        return candidate.quality_level > current.quality_level
    end
    if candidate.order ~= current.order then
        return candidate.order > current.order
    end
    return candidate.slot < current.slot
end

local function best_compatible_magazine(player_inventory, turret_inventory)
    local best

    for index = 1, #player_inventory do
        local stack = player_inventory[index]
        if stack and stack.valid_for_read then
            local prototype = stack.prototype
            if prototype and prototype.ammo_category then
                local quality_name, quality_level = stack_quality(stack)
                local item = {
                    name = stack.name,
                    quality = quality_name,
                    count = 1,
                }

                if turret_inventory.can_insert(item) then
                    local candidate = {
                        name = stack.name,
                        quality = quality_name,
                        quality_level = quality_level,
                        tier = VANILLA_AMMO_TIER[stack.name] or 0,
                        order = prototype.order or "",
                        slot = index,
                    }
                    if candidate_is_better(candidate, best) then
                        best = candidate
                    end
                end
            end
        end
    end

    return best
end

local function choose_magazine(player_inventory, turret_inventory)
    return existing_magazine(turret_inventory)
        or best_compatible_magazine(player_inventory, turret_inventory)
end

local function insert_one_magazine(turret, player, player_inventory)
    if not valid_player_turret(turret, player) then return 0 end

    local turret_inventory = turret.get_inventory(TURRET_AMMO_INVENTORY)
    if not (turret_inventory and turret_inventory.valid) then return 0 end

    local magazine = choose_magazine(player_inventory, turret_inventory)
    if not magazine then return 0 end

    local item = {
        name = magazine.name,
        quality = magazine.quality,
        count = 1,
    }
    if player_inventory.get_item_count({
        name = magazine.name,
        quality = magazine.quality,
    }) < 1 then
        return 0
    end
    if not turret_inventory.can_insert(item) then return 0 end

    local removed = player_inventory.remove(item)
    if removed < 1 then return 0 end

    local inserted = turret_inventory.insert(item)
    if inserted < removed then
        -- Removing one magazine always leaves room to return it. This guard
        -- still makes the transfer lossless if another mod rejects insertion.
        player_inventory.insert({
            name = magazine.name,
            quality = magazine.quality,
            count = removed - inserted,
        })
    end

    return inserted
end

local function fill_turret_to_target(turret, player, player_inventory)
    local turret_inventory = turret.get_inventory(TURRET_AMMO_INVENTORY)
    if not (turret_inventory and turret_inventory.valid) then return 0 end

    local needed = math.max(
        0,
        PLACEMENT_TARGET_MAGAZINES - magazine_count(turret_inventory)
    )
    local inserted = 0
    for _ = 1, needed do
        local amount = insert_one_magazine(turret, player, player_inventory)
        if amount == 0 then break end
        inserted = inserted + amount
    end
    return inserted
end

local function squared_distance(position, origin)
    local dx = position.x - origin.x
    local dy = position.y - origin.y
    return dx * dx + dy * dy
end

local function sort_nearest_first(turrets, origin)
    table.sort(turrets, function(a, b)
        local a_distance = squared_distance(a.position, origin)
        local b_distance = squared_distance(b.position, origin)
        if a_distance ~= b_distance then return a_distance < b_distance end
        return (a.unit_number or 0) < (b.unit_number or 0)
    end)
end

function gun_turret_autoload.on_built(event)
    if not (
        event
        and event.name == defines.events.on_built_entity
        and event.player_index
    ) then
        return
    end

    local player = game.get_player(event.player_index)
    if not valid_player(player) then return end

    local turret = event.entity or event.created_entity
    if not valid_player_turret(turret, player) then return end

    local player_inventory = player.get_main_inventory()
    if not (player_inventory and player_inventory.valid) then return end

    local inserted = fill_turret_to_target(turret, player, player_inventory)
    if inserted > 0 then
        player.create_local_flying_text({
            text = { "the-cave-gun-turret-autoload.placed", inserted },
            position = turret.position,
            color = { r = 0.25, g = 1, b = 0.25, a = 1 },
        })
    end
end

function gun_turret_autoload.on_area_reload(event)
    if not (event and event.player_index) then return end

    local player = game.get_player(event.player_index)
    if not valid_player(player) then return end

    local player_inventory = player.get_main_inventory()
    if not (player_inventory and player_inventory.valid) then return end

    local position = player.position
    local turrets = player.surface.find_entities_filtered({
        area = {
            { position.x - HALF_AREA_SIZE, position.y - HALF_AREA_SIZE },
            { position.x + HALF_AREA_SIZE, position.y + HALF_AREA_SIZE },
        },
        name = GUN_TURRET_NAMES,
        force = player.force,
    })

    if #turrets == 0 then
        player.print({ "the-cave-gun-turret-autoload.none-found" })
        return
    end

    sort_nearest_first(turrets, position)

    local total_inserted = 0
    local touched = {}
    local touched_count = 0

    -- One magazine per turret per pass prevents the nearest turret from
    -- consuming all available ammunition while another turret stays empty.
    for _ = 1, AREA_RELOAD_MAGAZINES_PER_PRESS do
        local made_progress = false

        for _, turret in ipairs(turrets) do
            local inserted = insert_one_magazine(turret, player, player_inventory)
            if inserted > 0 then
                made_progress = true
                total_inserted = total_inserted + inserted
                local key = turret.unit_number or tostring(turret)
                if not touched[key] then
                    touched[key] = true
                    touched_count = touched_count + 1
                end
            end
        end

        if not made_progress then break end
    end

    if total_inserted > 0 then
        player.print({
            "the-cave-gun-turret-autoload.area-result",
            touched_count,
            total_inserted,
        })
    else
        player.print({ "the-cave-gun-turret-autoload.nothing-loaded" })
    end
end

return gun_turret_autoload
