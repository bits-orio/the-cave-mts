-- The Cave Wind Turbine runtime upgrade controller.
-- Uses the official writable LuaEntity::power_production property. The entity
-- is never destroyed, replaced or paired with a hidden power source.

local wind_turbine = {}

local ENTITY_NAME = "the-cave-wind-turbine"
local TECH_PREFIX = "the-cave-wind-turbine-"
local SETTING_NAME = "the-cave-wind-turbine"
local TICKS_PER_SECOND = 60

local function enabled()
    local setting = settings and settings.startup and settings.startup[SETTING_NAME]
    return not setting or setting.value == "enabled" or setting.value == true
end

-- LuaEntity::power_production and electric_buffer_size use the engine's
-- internal Joules-per-tick values, not Watts. Dividing by 60 preserves the
-- intended 1 MW, 1.5 MW and 2 MW outputs instead of making every level hit the
-- prototype's final 2 MW output-flow ceiling.
local POWER_PER_TICK_BY_LEVEL = {
    [0] = 1000000 / TICKS_PER_SECOND,
    [1] = 1000000 / TICKS_PER_SECOND,
    [2] = 1500000 / TICKS_PER_SECOND,
    [3] = 2000000 / TICKS_PER_SECOND,
}

local function force_level(force)
    if not (force and force.valid and force.technologies) then return 0 end
    for level = 3, 1, -1 do
        local technology = force.technologies[TECH_PREFIX .. tostring(level)]
        if technology and technology.researched then
            return level
        end
    end
    return 0
end

local function is_wind_research(name)
    if type(name) ~= "string" then return false end
    local level = tonumber(name:match("^the%-cave%-wind%-turbine%-(%d+)$"))
    return level ~= nil and level >= 1 and level <= 3
end

function wind_turbine.apply_to_entity(entity)
    if not (
        entity
        and entity.valid
        and entity.name == ENTITY_NAME
        and entity.force
        and entity.force.valid
    ) then
        return
    end

    local active = enabled()
    local power_per_tick = active
        and (POWER_PER_TICK_BY_LEVEL[force_level(entity.force)] or POWER_PER_TICK_BY_LEVEL[0])
        or 0

    entity.power_production = power_per_tick

    -- The prototype keeps the final 2 MW output-flow limit so level 3 can use
    -- it. Restricting the live buffer to one tick of the researched output
    -- prevents levels 1 and 2 from briefly discharging stored energy at 2 MW.
    entity.electric_buffer_size = math.max(1, power_per_tick)
    if entity.energy > power_per_tick then
        entity.energy = power_per_tick
    end
end

local function sync_force_availability(force)
    if not (force and force.valid) then return end
    local active = enabled()
    for level = 1, 3 do
        local technology = force.technologies[TECH_PREFIX .. tostring(level)]
        if technology and technology.valid then
            technology.enabled = active
            technology.visible_when_disabled = false
        end
    end
    local recipe = force.recipes[ENTITY_NAME]
    local unlock = force.technologies[TECH_PREFIX .. "1"]
    if recipe and recipe.valid then
        recipe.enabled = active and unlock and unlock.researched or false
    end
end

function wind_turbine.apply_to_force(force)
    if not (force and force.valid) then return end
    sync_force_availability(force)
    for _, surface in pairs(game.surfaces) do
        if surface and surface.valid then
            local entities = surface.find_entities_filtered {
                name = ENTITY_NAME,
                force = force,
            }
            for _, entity in pairs(entities) do
                wind_turbine.apply_to_entity(entity)
            end
        end
    end
end

function wind_turbine.apply_to_all_forces()
    for _, force in pairs(game.forces) do
        if force and force.valid and force.name ~= "neutral" and force.name ~= "enemy" then
            wind_turbine.apply_to_force(force)
        end
    end
end

function wind_turbine.on_init()
    wind_turbine.apply_to_all_forces()
end

function wind_turbine.on_configuration_changed()
    -- Repairs every existing turbine immediately after an update or mod change.
    wind_turbine.apply_to_all_forces()
end

function wind_turbine.on_built(event)
    local entity = event and (event.entity or event.created_entity)
    wind_turbine.apply_to_entity(entity)
end

function wind_turbine.on_entity_cloned(event)
    wind_turbine.apply_to_entity(event and event.destination)
end

function wind_turbine.on_research_finished(event)
    local research = event and event.research
    if not (
        research
        and research.valid
        and research.force
        and is_wind_research(research.name)
    ) then
        return
    end
    wind_turbine.apply_to_force(research.force)
end

function wind_turbine.on_research_reversed(event)
    wind_turbine.on_research_finished(event)
end

function wind_turbine.on_forces_merged(event)
    wind_turbine.apply_to_force(event and event.destination)
end

return wind_turbine
