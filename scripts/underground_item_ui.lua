-- Placement variants are real stacks, never a second script-owned balance.
-- Convert them back at inventory/UI boundaries; Q is handled by the engine.
local M = {}
local bases = {['underground-belt']=true, ['fast-underground-belt']=true,
    ['express-underground-belt']=true, ['turbo-underground-belt']=true, ['pipe-to-ground']=true}

function M.base_name(name)
    if not name then return nil end
    local base, level = name:match('^the%-cave%-u[brp]+%-item%-(.-)%-(%d+)$')
    level = tonumber(level)
    if bases[base] and level and level >= 1 and level <= 7 then return base end
end

function M.normalise_stack(stack)
    if not (stack and stack.valid and stack.valid_for_read) then return end
    local base = M.base_name(stack.name)
    if not base then return end
    local health = stack.health
    if stack.set_stack{name=base, count=stack.count, quality=stack.quality.name} then
        stack.health = health
    end
end

local function normalise_inventory(inventory)
    if not (inventory and inventory.valid) then return end
    for i=1,#inventory do M.normalise_stack(inventory[i]) end
end

function M.on_clear_cursor(event)
    local player=game.get_player(event.player_index)
    if not (player and player.valid) then return end
    -- Linked non-consuming input runs before the native clear action. Restore
    -- the official name first so it can merge with an existing partial stack
    -- or return to a filtered slot even when every other slot is occupied.
    M.normalise_stack(player.cursor_stack)
end

function M.on_inventory_changed(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    -- Events are limited to the affected player's inventory, never a world scan.
    normalise_inventory(player.get_main_inventory())
    normalise_inventory(player.get_inventory(defines.inventory.character_trash))
end

function M.on_dropped_item(event)
    local entity = event.entity
    if entity and entity.valid then M.normalise_stack(entity.stack) end
end

function M.on_dropped_item_into_entity(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end
    for i=1,entity.get_max_inventory_index() do normalise_inventory(entity.get_inventory(i)) end
end

function M.on_quickbar_changed(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    -- This event has no slot index. Ten pages are the native quickbar limit.
    for page=1,10 do
        for slot=1,player.quick_bar_width do
            local value = player.get_quick_bar_slot(page, slot)
            if value and value.type == 'filter' and value.filter then
                local base = M.base_name(value.filter.name)
                if base then
                    value.filter.name = base
                    player.set_quick_bar_slot(page, slot, value)
                end
            end
        end
    end
end

return M
