local quality_everything = {}

local function enabled()
    local setting = settings and settings.startup and settings.startup["the-cave-base-quality"]
    if not (setting and tonumber(setting.value) and tonumber(setting.value) > 0) then
        return false
    end
    return prototypes and prototypes.quality and prototypes.quality["uncommon"] ~= nil
end

local function unlock_uncommon(force)
    if not (enabled() and force and force.valid) then return end
    pcall(function() force.unlock_quality("uncommon") end)
end

function quality_everything.sync_force(force)
    unlock_uncommon(force)
end

function quality_everything.sync_all_forces()
    if not enabled() then return end
    for _, force in pairs(game.forces) do
        unlock_uncommon(force)
    end
end

function quality_everything.on_init()
    quality_everything.sync_all_forces()
end

function quality_everything.on_configuration_changed()
    quality_everything.sync_all_forces()
end

function quality_everything.on_force_created(event)
    unlock_uncommon(event and event.force)
end

return quality_everything
