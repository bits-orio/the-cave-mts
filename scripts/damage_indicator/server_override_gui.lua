-- server_override_gui.lua
-- Dummiez 2026/05/12
--
-- Renders the "copy your settings as an encoded string" dialog used by the
-- /damage-indicators-override command. The encoded blob is the payload format
-- accepted by the startup setting `damage-indicator-server-override-string`.
--
-- The runtime mod-setting list mirrored here is the SAME set that viewer_utils
-- applies overrides to (see settings_cache.lua / viewer_utils.lua). When you add
-- a new runtime-per-user setting to the mod that should be server-overridable,
-- add its name to OVERRIDE_SETTING_NAMES below.

local server_override_gui = {}

-- The full list of runtime-per-user setting names baked into the server-override
-- payload. `damage-indicator-enabled` is deliberately excluded so each player can
-- still hide indicators on their own screen even when an override is active.
local OVERRIDE_SETTING_NAMES = {
  "damage-indicator-lifetime",
  "damage-indicator-animation-speed",
  "damage-indicator-color-intensity-cap",
  "damage-indicator-color-mode",
  "damage-indicator-blend-damage-type-colors",
  "damage-indicator-color-physical",
  "damage-indicator-color-impact",
  "damage-indicator-color-explosion",
  "damage-indicator-color-fire",
  "damage-indicator-color-laser",
  "damage-indicator-color-electric",
  "damage-indicator-color-acid",
  "damage-indicator-color-poison",
  "damage-indicator-color-intensity",
  "damage-indicator-drift-distance",
  "damage-indicator-drift-style",
  "damage-indicator-show-group-count",
  "damage-indicator-compact-numbers",
  "damage-indicator-number-separator",
  "damage-indicator-shadow-style",
  "damage-indicator-show-reductions",
  "damage-indicator-alt-mode",
  "damage-indicator-debug-info",
  "damage-indicator-text-template",
  "damage-indicator-killing-blow",
  "damage-indicator-killing-blow-marker",
  "damage-indicator-radius",
  "damage-indicator-visibility",
  "damage-indicator-scale",
  "damage-indicator-minimum-damage",
}

-- Set-lookup version of OVERRIDE_SETTING_NAMES, used by on_runtime_mod_setting_changed
-- to decide whether a just-changed setting is one the server is currently overriding.
local OVERRIDE_SETTING_SET = {}
for i = 1, #OVERRIDE_SETTING_NAMES do
  OVERRIDE_SETTING_SET[OVERRIDE_SETTING_NAMES[i]] = true
end

function server_override_gui.is_overridden_setting(name)
  return OVERRIDE_SETTING_SET[name] == true
end

-- GUI element names. Distinct + prefixed so on_gui_closed/on_gui_click handlers can
-- identify them deterministically without collisions against other mods or vanilla.
server_override_gui.FRAME_NAME = "damage-indicator-settings-string-frame"
server_override_gui.TEXTBOX_NAME = "damage-indicator-settings-string-textbox"
server_override_gui.CLOSE_BUTTON_NAME = "damage-indicator-settings-string-close"

local FRAME_NAME = server_override_gui.FRAME_NAME
local TEXTBOX_NAME = server_override_gui.TEXTBOX_NAME
local CLOSE_BUTTON_NAME = server_override_gui.CLOSE_BUTTON_NAME

-- Normalize a color-setting value into a plain JSON-friendly {r,g,b} table. Factorio
-- color settings come back as full ColorSetting tables which can include metatables
-- and don't serialize cleanly via table_to_json; this strips them to the three
-- fields we actually need.
local function color_to_plain(value)
  if type(value) ~= "table" then return value end
  local r = value.r or value[1] or 0
  local g = value.g or value[2] or 0
  local b = value.b or value[3] or 0
  return { r = r, g = g, b = b }
end

-- Builds the override-payload table from a player's current settings and encodes it
-- via helpers.table_to_json -> helpers.encode_string. The output is a single Base64
-- + zlib blob (the same format Factorio uses for blueprint strings).
local function encode_player_settings_string(player)
  local s = settings.get_player_settings(player)
  local values = {}
  for i = 1, #OVERRIDE_SETTING_NAMES do
    local name = OVERRIDE_SETTING_NAMES[i]
    local entry = s[name]
    if entry then
      local v = entry.value
      -- Color settings need flattening; everything else is already JSON-serializable.
      if name:find("damage-indicator-color-", 1, true) == 1
          and name ~= "damage-indicator-color-mode"
          and name ~= "damage-indicator-color-intensity"
          and name ~= "damage-indicator-color-intensity-cap" then
        v = color_to_plain(v)
      end
      values[name] = v
    end
  end
  local payload = { version = 1, values = values }
  local json = helpers.table_to_json(payload)
  return helpers.encode_string(json) or ""
end

server_override_gui.encode_player_settings_string = encode_player_settings_string

-- Opens the encoded-settings copy dialog on the player's screen. Destroys any
-- existing instance first so re-running the command refreshes contents instead of
-- stacking duplicate frames.
function server_override_gui.open(player)
  if not player or not player.valid then return end

  local existing = player.gui.screen[FRAME_NAME]
  if existing then existing.destroy() end

  local encoded = encode_player_settings_string(player)

  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical",
  })
  frame.auto_center = true
  -- Width is set on the inner elements; the frame wraps them.
  frame.style.maximal_height = 800

  -- Title bar: caption left, draggable space middle (right-side close icon is
  -- intentionally omitted; we provide a green confirm button in the footer instead).
  local title_bar = frame.add({ type = "flow", direction = "horizontal" })
  title_bar.drag_target = frame
  title_bar.add({
    type = "label",
    caption = { "gui-damage-indicator.settings-string-title" },
    style = "frame_title",
    ignored_by_interaction = true
  })
  local drag_filler = title_bar.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  })
  drag_filler.style.horizontally_stretchable = true
  drag_filler.style.height = 24
  drag_filler.style.right_margin = 4

  -- Inset content area styled like a vanilla properties panel.
  local inner = frame.add({
    type = "frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  })

  local help_label = inner.add({
    type = "label",
    caption = { "gui-damage-indicator.settings-string-help" },
  })
  help_label.style.single_line = false
  help_label.style.width = 560
  help_label.style.rich_text_setting = defines.rich_text_setting.enabled
  help_label.style.bottom_margin = 8

  local textbox = inner.add({
    type = "text-box",
    name = TEXTBOX_NAME,
    text = encoded
  })
  textbox.read_only = true
  textbox.word_wrap = true
  textbox.style.width = 560
  textbox.style.minimal_height = 80
  textbox.style.maximal_height = 400
  textbox.select_all()

  -- Footer with a right-aligned green confirm button (closest vanilla style to the
  -- "tool_button_green" look while still supporting a text caption).
  local footer = frame.add({ type = "flow", direction = "horizontal" })
  footer.style.top_padding = 4
  local footer_filler = footer.add({ type = "empty-widget" })
  footer_filler.style.horizontally_stretchable = true
  footer.add({
    type = "button",
    name = CLOSE_BUTTON_NAME,
    caption = { "gui-damage-indicator.settings-string-close" },
    style = "confirm_button"
  })

  -- Register the frame as the active GUI so Escape/E close it via on_gui_closed.
  player.opened = frame
end

-- Click-routing helper: returns true if the element belongs to this GUI and the
-- click was handled (i.e. the frame was destroyed). Lets the main on_gui_click
-- handler in control.lua delegate without duplicating the lookup logic.
function server_override_gui.handle_gui_click(event)
  if not event.element or not event.element.valid then return false end
  if event.element.name ~= CLOSE_BUTTON_NAME then return false end
  local player = game.get_player(event.player_index)
  if not player then return false end
  local frame = player.gui.screen[FRAME_NAME]
  if frame then frame.destroy() end
  return true
end

-- on_gui_closed routing helper: same idea -- returns true if this module handled
-- the close. on_gui_closed fires for the registered `player.opened` frame when the
-- player presses Escape/E.
function server_override_gui.handle_gui_closed(event)
  if not event.element or not event.element.valid then return false end
  if event.element.name ~= FRAME_NAME then return false end
  event.element.destroy()
  return true
end

return server_override_gui
