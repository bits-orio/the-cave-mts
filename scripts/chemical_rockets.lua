local settings = require("scripts.game_settings").proxy(settings)

local M = {}
local function enabled()
  local s = settings and settings.startup and settings.startup["the-cave-chemical-rockets"]
  return not s or s.value == "enabled"
end
local function sync()
  if not enabled() then return end
  for _, force in pairs(game.forces) do
    local tech = force.technologies["explosive-rocketry"]
    if tech and tech.researched then
      local r1 = force.recipes["chemical-rocket"]
      local r2 = force.recipes["incendiary-rocket"]
      if r1 then r1.enabled = true end
      if r2 then r2.enabled = true end
    end
  end
end
M.on_init = sync
M.on_configuration_changed = sync
return M
