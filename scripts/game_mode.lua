-- Compatibility helpers for callers which need a single summary of the
-- independent Startup settings. Gameplay activation always reads the individual
-- settings so compatible features can be combined.

local game_mode = {}

local function startup_value(name, fallback)
    local startup = settings and settings.startup
    local setting = startup and startup[name]
    if setting and setting.value ~= nil then return setting.value end
    return fallback
end

function game_mode.current()
    local train = startup_value("the-cave-train-interiors", "disabled")
    local shelter = startup_value("the-cave-shelter-defense", "disabled")
    if train == "enabled" and shelter == "enabled" then return "conflict" end
    if startup_value("the-cave-cavetorio", "disabled") == "enabled" then return "cavetorio" end
    if shelter == "enabled" then return "shelter-defense" end
    if train == "enabled" then return "train-interiors" end
    if startup_value("the-cave-advancing-collapse", "disabled") == "enabled" then return "advancing-collapse" end
    if startup_value("the-cave-collapse-mode", "disabled") == "enabled" then return "cave-collapses" end
    if game_mode.digging_level() ~= "disabled" then return "digging" end
    return "normal-the-cave"
end

function game_mode.is(name)
    if name == "train-interiors" then return game_mode.train_enabled() end
    if name == "shelter-defense" then
        return startup_value("the-cave-shelter-defense", "disabled") == "enabled"
            and startup_value("the-cave-train-interiors", "disabled") ~= "enabled"
    end
    if name == "cavetorio" then return startup_value("the-cave-cavetorio", "disabled") == "enabled" end
    if name == "advancing-collapse" then return startup_value("the-cave-advancing-collapse", "disabled") == "enabled" end
    if name == "cave-collapses" then return startup_value("the-cave-collapse-mode", "disabled") == "enabled" end
    if name == "digging" then return game_mode.digging_level() ~= "disabled" end
    if name == "normal-the-cave" then return game_mode.current() == "normal-the-cave" end
    return false
end

function game_mode.train_enabled()
    return startup_value("the-cave-train-interiors", "disabled") == "enabled"
        and startup_value("the-cave-shelter-defense", "disabled") ~= "enabled"
end

function game_mode.digging_level()
    return startup_value("the-cave-digging-mode", "disabled")
end

return game_mode
