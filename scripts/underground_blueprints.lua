-- Adapt held blueprints/books; library records use a disposable private copy.
local settings = require('scripts.game_settings').proxy(settings)
local M = {}
local belts = {['underground-belt']=true,['fast-underground-belt']=true,
    ['express-underground-belt']=true,['turbo-underground-belt']=true}

function M.base_name(name)
    if belts[name] or name=='pipe-to-ground' then return name end
    local base,level = (name or ''):match('^the%-cave%-u[brp]+%-(.-)%-(%d+)$')
    level=tonumber(level)
    if (belts[base] or base=='pipe-to-ground') and level and level>=1 and level<=7 then return base end
end

function M.target_name(name, force)
    local base=M.base_name(name)
    if not base then return name end
    local kind=base=='pipe-to-ground' and 'pipe' or 'belt'
    local option=settings.startup['the-cave-underground-'..kind..'-reach-research']
    local level=0
    if not option or option.value==true or option.value=='enabled' then
        for i=1,7 do
            local tech=force.technologies['the-cave-underground-'..kind..'-reach-'..i]
            if not (tech and tech.researched) then break end
            level=i
        end
    end
    local target=level>0 and ('the-cave-'..(kind=='pipe' and 'upr-' or 'ubr-')..base..'-'..level) or base
    return prototypes.entity[target] and target or base
end

local function selected(holder, player, record)
    if record then
        while holder and holder.valid and holder.type=='blueprint-book' do
            holder=holder.get_selected_record(player)
        end
        return holder and holder.valid and holder.type=='blueprint' and holder or nil
    end
    while holder and holder.valid_for_read and holder.is_blueprint_book do
        local inv=holder.get_inventory(defines.inventory.item_main)
        local index=holder.active_index
        holder=inv and index and inv[index] or nil
    end
    return holder and holder.valid_for_read and holder.is_blueprint and holder or nil
end

local function needs_adaptation(holder,force)
    for _,entity in pairs(holder.get_blueprint_entities() or {}) do
        if M.target_name(entity.name,force)~=entity.name then return true end
    end
    return false
end

local function rewrite(stack, force)
    if not (stack and stack.valid and stack.valid_for_read) then return end
    if stack.is_blueprint_book then
        local inv=stack.get_inventory(defines.inventory.item_main)
        for i=1,#inv do rewrite(inv[i],force) end
    elseif stack.is_blueprint then
        local entities=stack.get_blueprint_entities()
        local changed=false
        for _,entity in pairs(entities or {}) do
            local base=M.base_name(entity.name)
            if base then
                local target=force and M.target_name(base,force) or base
                if target~=entity.name then entity.name=target;changed=true end
            end
        end
        -- Do not recenter snapped/relative blueprints or rewrite other fields.
        if changed then stack.set_blueprint_entities(entities,false) end
    end
end

function M.queue(event)
    if not event.player_index then return end
    storage.the_cave_underground_blueprint_queue=storage.the_cave_underground_blueprint_queue or {}
    storage.the_cave_underground_blueprint_queue[event.player_index]=true
end

function M.prepare(player)
    if not (player and player.valid) or player.opened or not player.is_cursor_blueprint() then return end
    local record=player.cursor_record
    local root=record or player.cursor_stack
    local leaf=selected(root,player,record~=nil)
    if not (leaf and needs_adaptation(leaf,player.force)) then return end
    if record then
        -- Library records stay in their library. The disposable working copy
        -- keeps book navigation without modifying another player's source.
        local exported=record.export_record()
        if not player.clear_cursor() then return end
        if player.cursor_stack.import_stack(exported)~=0 then return end
        player.cursor_stack_temporary=true
    end
    rewrite(player.cursor_stack,player.force)
end

function M.on_tick()
    local queued=storage.the_cave_underground_blueprint_queue
    if not queued or not next(queued) then return end
    storage.the_cave_underground_blueprint_queue={}
    for index in pairs(queued) do M.prepare(game.get_player(index)) end
end

function M.on_gui_opened(event)
    local player=game.get_player(event.player_index)
    if player then rewrite(player.cursor_stack,nil) end
end

function M.on_inventory_changed(event)
    local player=game.get_player(event.player_index)
    local inv=player and player.get_main_inventory()
    if not inv then return end
    -- A temporary copy can be deliberately put in inventory. Store the portable
    -- official names there too, just like freshly captured blueprints.
    for i=1,#inv do
        local stack=inv[i]
        if stack.valid_for_read and (stack.is_blueprint or stack.is_blueprint_book) then rewrite(stack,nil) end
    end
end

function M.on_research_finished(event)
    local research=event.research
    if research and research.valid and research.name:match('^the%-cave%-underground%-') then
        for _,player in pairs(research.force.players) do M.queue{player_index=player.index} end
    end
end

function M.on_configuration_changed()
    for _,player in pairs(game.players) do
        M.on_inventory_changed{player_index=player.index}
        M.queue{player_index=player.index}
    end
end

return M
