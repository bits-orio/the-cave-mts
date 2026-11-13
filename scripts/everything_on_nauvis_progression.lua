local settings = require("scripts.game_settings").proxy(settings)

-- Runtime half of The Cave's Everything on Nauvis progression.
--
-- The four official planet-discovery technologies are completed for every
-- playable force. Their normal technology effects are applied by Factorio,
-- while all later planetary technologies still require their normal triggers,
-- resources and science packs.

local progression = {}

local SETTING_NAME = "the-cave-everything-on-nauvis"
local DISCOVERY_TECHNOLOGIES = {
  "planet-discovery-vulcanus",
  "planet-discovery-gleba",
  "planet-discovery-fulgora",
  "planet-discovery-aquilo",
}

local function enabled()
  if not (script and script.active_mods and script.active_mods["space-age"]) then
    return false
  end

  local setting = settings and settings.startup and settings.startup[SETTING_NAME]
  return not setting
    or (setting.value ~= "disabled" and setting.value ~= false)
end

local function playable_force(force)
  return force
    and force.valid
    and force.name ~= "enemy"
    and force.name ~= "neutral"
end

function progression.sync_force(force)
  if not (enabled() and playable_force(force)) then return end

  for _, technology_name in ipairs(DISCOVERY_TECHNOLOGIES) do
    local technology = force.technologies[technology_name]
    if technology and not technology.researched then
      technology.researched = true
    end
  end
end

local function sync_all_forces()
  if not (enabled() and game) then return end
  for _, force in pairs(game.forces) do
    progression.sync_force(force)
  end
end

function progression.on_init()
  sync_all_forces()
end

function progression.on_configuration_changed()
  sync_all_forces()
end

function progression.on_force_created(event)
  progression.sync_force(event and event.force)
end

function progression.on_player_created(event)
  local player = event
    and event.player_index
    and game.get_player(event.player_index)
  progression.sync_force(player and player.force)
end

function progression.on_player_changed_force(event)
  local player = event
    and event.player_index
    and game.get_player(event.player_index)
  progression.sync_force(player and player.force)
end

return progression
