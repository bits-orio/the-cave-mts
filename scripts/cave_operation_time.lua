local settings = require("scripts.game_settings")
local timing = {}
local HOUR = 60 * 60 * 60

function timing.core()
    return not settings.enabled("the-cave-collapse-mode", false)
        and not settings.enabled("the-cave-advancing-collapse", false)
end

function timing.duration(legacy)
    -- New operations always last one hour; running deadlines are authoritative.
    return HOUR
end

return timing
