-- One Startup switch for the shop and every source of NEW market currency.
-- Keep prototypes and existing stacks intact for save compatibility.
local M = {}

function M.enabled()
    local setting = settings and settings.startup and settings.startup["the-cave-market"]
    return not setting or setting.value == "enabled" or setting.value == true
end

function M.starter_item_allowed(name)
    if M.enabled() then return true end
    return name ~= "coin"
        and not name:match("^the%-cave%-portable%-power%-interface%-mk[1-5]$")
end

return M
