-- Existing pipes and unbuilt ghosts must match the same force-local blueprint
-- names as new builds. Research/configuration enqueue only affected entities.
local blueprints=require('scripts.underground_blueprints')
local pipes=require('scripts.underground_pipe_reach')
local M={}
local bases={'underground-belt','fast-underground-belt','express-underground-belt','turbo-underground-belt','pipe-to-ground'}
local function names(kind)
    local result={}
    for _,base in ipairs(bases) do
        if not kind or (base=='pipe-to-ground')==(kind=='pipe') then
            if prototypes.entity[base] then result[#result+1]=base end
            for level=1,7 do
                local name='the-cave-'..(base=='pipe-to-ground' and 'upr-' or 'ubr-')..base..'-'..level
                if prototypes.entity[name] then result[#result+1]=name end
            end
        end
    end
    return result
end

function M.on_built(event)
    local entity=event.entity or event.created_entity
    if not (entity and entity.valid and entity.type=='entity-ghost') then return end
    local target=blueprints.target_name(entity.ghost_name,entity.force)
    if target~=entity.ghost_name then
        -- Native ghost upgrade retains wires, tags, quality and item requests.
        entity.order_upgrade{target={name=target,quality=entity.quality.name},force=entity.force}
    end
end

function M.enqueue(force,kind)
    if not (force and force.valid) then return end
    storage.the_cave_underground_world_jobs=storage.the_cave_underground_world_jobs or {}
    local entities={}
    local previous=storage.the_cave_underground_world_jobs[force.index]
    if previous and kind=='belt' then
        for i=previous.index,#previous.entities do entities[#entities+1]=previous.entities[i] end
    end
    local ghost_names=names(nil)
    for _,surface in pairs(game.surfaces) do
        if kind~='belt' then
            for _,entity in pairs(surface.find_entities_filtered{name=names('pipe'),force=force}) do
                entities[#entities+1]=entity
            end
        end
        for _,entity in pairs(surface.find_entities_filtered{type='entity-ghost',ghost_name=ghost_names,force=force}) do
            entities[#entities+1]=entity
        end
    end
    storage.the_cave_underground_world_jobs[force.index]={entities=entities,index=1}
end

function M.on_tick()
    local jobs=storage.the_cave_underground_world_jobs
    if not jobs then return end
    local budget=128
    for force_index,job in pairs(jobs) do
        local force=game.forces[force_index]
        while force and budget>0 and job.index<=#job.entities do
            local entity=job.entities[job.index];job.index=job.index+1;budget=budget-1
            if entity and entity.valid and entity.force==force then
                if entity.type=='entity-ghost' then M.on_built{entity=entity}
                else pipes.synchronise_entity(entity) end
            end
        end
        if not force or job.index>#job.entities then jobs[force_index]=nil end
        if budget==0 then break end
    end
end

function M.on_research_finished(event)
    local r=event.research
    local kind=r and r.name:match('^the%-cave%-underground%-(%a+)%-reach%-')
    if kind=='belt' or kind=='pipe' then M.enqueue(r.force,kind) end
end

function M.on_configuration_changed()
    for _,force in pairs(game.forces) do M.enqueue(force) end
end
return M
