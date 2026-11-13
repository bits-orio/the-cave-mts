-- commands.lua
-- Dummiez 2026/05/12
--
-- Registers all in-game slash commands for the mod. Side-effect import: requiring
-- this module from control.lua calls commands.add_command for each entry. Pass the
-- module's `init` function the runtime dependencies (clear callback, GUI module)
-- since this file has no direct access to control.lua's locals.

local mod_commands = {}

-- Required dependencies, populated by init(). Kept module-local so the command
-- callbacks (which are upvalues created at register time) can close over them.
local deps = {
  clear_indicators = nil,
  server_override_gui = nil,
}

-- /damage-indicators-clear -- admin-only on multiplayer. Wipes every active
-- indicator across all players. Useful when a mod-compat issue leaves stale
-- render objects on screen.
local function on_clear_command(event)
  if event.player_index then
    local player = game.get_player(event.player_index)
    if player and not player.admin then
      player.print({ "command-output.parameters-require-admin" })
      return
    end
  end
  if deps.clear_indicators then
    deps.clear_indicators()
  end
end

-- /damage-indicators-override -- any player can run this. Opens a dialog containing
-- the encoded form of their current per-user settings, which a server admin can
-- paste into the startup `damage-indicator-server-override-string` setting to lock
-- those values for everyone in future games.
local function on_override_command(event)
  if not event.player_index then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if deps.server_override_gui then
    deps.server_override_gui.open(player)
  end
end

-- Registers all commands. Must be called once from control.lua at file load time
-- (NOT from on_init -- commands.add_command is required at every load, including
-- on_load, so callers should invoke this unconditionally at module scope).
function mod_commands.init(dependencies)
  deps.clear_indicators = dependencies.clear_indicators
  deps.server_override_gui = dependencies.server_override_gui

  commands.add_command(
    "damage-indicators-clear",
    { "command-help.damage-indicators-clear" },
    on_clear_command
  )

  commands.add_command(
    "damage-indicators-override",
    { "command-help.damage-indicators-override" },
    on_override_command
  )
end

return mod_commands
