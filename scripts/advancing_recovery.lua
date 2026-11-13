local cave_teams = require("scripts.cave_teams")
-- Recovery protects only the saved rolling clearing on an active main surface.
-- No terrain, items, resources or player entities are removed.
local zones = require("scripts.advancing_zones")
local clearing = require("scripts.advancing_clearing")
local recovery = {}
local reward_death

function recovery.configure_rewards(callback)
    reward_death = callback
end

function recovery.is_resting(surface_state)
    local state = surface_state and surface_state.assault
    return state and state.break_until_tick ~= nil or false
end

local function state_for(surface)
    if not (surface and surface.valid and zones.is_active()
        and zones.is_main_surface(surface) and cave_teams.is_world_running(surface)) then return nil end
    local root = storage and storage.the_cave_advancing_collapse
    local state = root and root.surfaces and root.surfaces[surface.index]
    if not state then return nil end
    if state.phase == "countdown" then
        local left, right, top, bottom = clearing.bounds(state)
        state.preparation_area = state.preparation_area or {}
        state.preparation_area.break_area = { {left, top}, {right, bottom} }
        return state.preparation_area
    end
    return state.phase == "active" and recovery.is_resting(state) and state.assault or nil
end

function recovery.contains(surface, position)
    local state = state_for(surface)
    local area = state and state.break_area
    return area and position.x >= area[1][1] and position.x < area[2][1]
        and position.y >= area[1][2] and position.y < area[2][2] or false
end

local function removable(entity)
    return entity.valid and entity.force and entity.force.name == "enemy"
        and (entity.health ~= nil or entity.type == "projectile"
            or entity.type == "artillery-projectile" or entity.type == "stream")
end

function recovery.clear(surface, state, rewards)
    if not (state and state.break_area) then return end
    for _, entity in pairs(surface.find_entities_filtered {
        area = state.break_area, force = "enemy",
    }) do
        -- Bounding-box queries can include entities whose centres are outside.
        if removable(entity) and recovery.contains(surface, entity.position) then
            if rewards and reward_death and entity.health ~= nil then
                reward_death({ entity = entity }, false)
            end
            -- Avoid brood/death attacks and artificial evolution from cleanup.
            -- Initial rewards use the existing coin policy; later entrants pay
            -- no coins, so a break cannot be used as an automatic coin farm.
            if entity.valid then entity.destroy { raise_destroy = true } end
        end
    end
end

function recovery.enforce_surface(surface)
    local state = state_for(surface)
    if state then recovery.clear(surface, state, false) end
end

function recovery.on_tick()
    if not zones.is_active() then return end
    local root = storage and storage.the_cave_advancing_collapse
    if not root then return end
    for index, surface_state in pairs(root.surfaces or {}) do
        if surface_state.phase == "countdown" or recovery.is_resting(surface_state) then
            local surface = game.get_surface(index)
            if surface and surface.valid then recovery.enforce_surface(surface) end
        end
    end
end

return recovery
