-- Resolve extraction/mission cave evolution through the surface that owns the
-- entrance. Custom spawns read the parent immediately, while the periodic sync
-- also keeps vanilla spawners on child surfaces aligned with that same value.
local cave_evolution = {}

local ROOT_KEYS = {
    "the_cave_uranium_caves",
    "the_cave_mineral_caves",
    "the_cave_lost_city",
    "the_cave_fortified_vaults",
}

local EXTRACTION_ROOT_KEYS = {
    "the_cave_uranium_caves",
    "the_cave_mineral_caves",
}

local function valid_surface(index)
    local surface = index and game and game.surfaces[index]
    return surface and surface.valid and surface or nil
end

local function record_for_child_surface(surface, root_keys)
    if not (surface and surface.valid and storage) then return nil end
    for _, key in ipairs(root_keys or ROOT_KEYS) do
        local root = storage[key]
        local id = root and root.by_surface and root.by_surface[surface.index]
        local record = id and root.by_id and root.by_id[id]
        if record then return record end
    end
    return nil
end

-- Spawner destruction on a timed resource child surface must advance the
-- owning parent surface. The normal one-second sync then propagates that value
-- back to this child without affecting another team or another cave.
function cave_evolution.on_enemy_spawner_died(event)
    local entity = event and event.entity
    if not (entity and entity.valid and entity.type == "unit-spawner"
        and entity.force and entity.force.valid and entity.force.name == "enemy") then
        return false
    end

    local record = record_for_child_surface(entity.surface, EXTRACTION_ROOT_KEYS)
    local parent = record and valid_surface(record.parent_surface_index)
    if not parent then return false end

    local cause = event.cause
    local killer_force = cause and cause.valid and cause.force or nil
    if not (killer_force and killer_force.valid) then killer_force = event.force end
    if not (killer_force and killer_force.valid)
        or killer_force.name == "enemy" or killer_force.name == "neutral" then
        return false
    end

    local enemy = game and game.forces and game.forces.enemy
    local evolution_settings = game and game.map_settings and game.map_settings.enemy_evolution
    local destroy_factor = tonumber(evolution_settings and evolution_settings.destroy_factor) or 0
    if not (enemy and enemy.valid) or destroy_factor <= 0 then return false end

    local ok, current = pcall(function() return enemy.get_evolution_factor(parent) end)
    if not ok then return false end
    current = math.max(0, math.min(1, tonumber(current) or 0))
    local remaining = 1 - current
    local next_factor = math.min(1, current + destroy_factor * remaining * remaining)
    if next_factor <= current then return false end
    return pcall(function() enemy.set_evolution_factor(next_factor, parent) end)
end

function cave_evolution.parent_surface(surface)
    local record = record_for_child_surface(surface)
    return record and valid_surface(record.parent_surface_index) or surface
end

function cave_evolution.factor(surface)
    local enemy = game and game.forces and game.forces.enemy
    if not (enemy and enemy.valid and surface and surface.valid) then return 0 end
    local parent = cave_evolution.parent_surface(surface)
    local ok, value = pcall(function() return enemy.get_evolution_factor(parent) end)
    if not ok then value = 0 end
    return math.max(0, math.min(1, tonumber(value) or 0))
end

function cave_evolution.tier_names(surface)
    local evolution = cave_evolution.factor(surface)
    if evolution >= 0.85 then
        return "behemoth-biter", "behemoth-spitter", "behemoth-worm-turret"
    elseif evolution >= 0.55 then
        return "big-biter", "big-spitter", "big-worm-turret"
    elseif evolution >= 0.25 then
        return "medium-biter", "medium-spitter", "medium-worm-turret"
    end
    return "small-biter", "small-spitter", "small-worm-turret"
end

function cave_evolution.sync_all()
    local enemy = game and game.forces and game.forces.enemy
    if not (enemy and enemy.valid and storage) then return end
    for _, key in ipairs(ROOT_KEYS) do
        local root = storage[key]
        for child_index, id in pairs(root and root.by_surface or {}) do
            local record = root.by_id and root.by_id[id]
            local child = valid_surface(child_index)
            local parent = record and valid_surface(record.parent_surface_index)
            if child and parent then
                local ok, value = pcall(function() return enemy.get_evolution_factor(parent) end)
                if ok then
                    pcall(function()
                        enemy.set_evolution_factor(
                            math.max(0, math.min(1, tonumber(value) or 0)), child)
                    end)
                end
            end
        end
    end
end

function cave_evolution.on_tick(event)
    local tick = event and event.tick or (game and game.tick) or 0
    if tick % 60 == 0 then cave_evolution.sync_all() end
end

return cave_evolution
