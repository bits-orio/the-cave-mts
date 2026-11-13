local settings = require("scripts.game_settings").proxy(settings)

-- First-join, read-only introduction for The Cave.
-- This GUI deliberately never writes mod settings or gameplay state other
-- than the per-player acknowledgement flag.
local welcome = {}

local FRAME_NAME = "the_cave_welcome_frame"
local CONFIRM_NAME = "the_cave_welcome_confirm"

local function root()
    storage.the_cave_welcome = storage.the_cave_welcome or { seen = {} }
    storage.the_cave_welcome.seen = storage.the_cave_welcome.seen or {}
    return storage.the_cave_welcome
end

local function startup_enabled(name, default_enabled)
    local setting = settings and settings.startup and settings.startup[name]
    if not setting then return default_enabled ~= false end
    return setting.value == "enabled" or setting.value == true
end

local function logical_display_size(player)
    local resolution = player.display_resolution or { width = 1280, height = 720 }
    local scale = player.display_scale or 1
    if scale <= 0 then scale = 1 end
    return resolution.width / scale, resolution.height / scale
end

local function add_section(parent, title, body, content_width)
    local card = parent.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
    }
    card.style.horizontally_stretchable = true
    card.style.bottom_margin = 8

    local heading = card.add { type = "label", caption = title }
    heading.style.font = "default-bold"
    heading.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    heading.style.bottom_margin = 4

    local description = card.add { type = "label", caption = body }
    description.style.single_line = false
    description.style.width = content_width
end

local function destroy(player, acknowledged)
    if not (player and player.valid) then return end
    local frame = player.gui.screen[FRAME_NAME]
    if acknowledged then root().seen[player.index] = true end
    if player.opened == frame then player.opened = nil end
    if frame and frame.valid then frame.destroy() end
end

local function show(player)
    if not (player and player.valid and player.connected) then return end
    if root().seen[player.index] then return end

    local existing = player.gui.screen[FRAME_NAME]
    if existing and existing.valid then
        player.opened = existing
        return
    end

    local logical_width, logical_height = logical_display_size(player)
    local frame_width = math.floor(math.min(640, math.max(460, logical_width - 80)))
    local content_width = frame_width - 58
    local scroll_height = math.floor(math.min(570, math.max(300, logical_height - 210)))

    local frame = player.gui.screen.add {
        type = "frame",
        name = FRAME_NAME,
        direction = "vertical",
    }
    frame.style.width = frame_width

    local title = frame.add { type = "label", caption = { "the-cave-welcome.title" } }
    title.style.font = "heading-1"
    title.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    title.style.horizontal_align = "center"
    title.style.horizontally_stretchable = true

    local subtitle = frame.add { type = "label", caption = { "the-cave-welcome.subtitle" } }
    subtitle.style.font = "default-bold"
    subtitle.style.horizontal_align = "center"
    subtitle.style.horizontally_stretchable = true
    subtitle.style.bottom_margin = 8

    local scroll = frame.add {
        type = "scroll-pane",
        style = "scroll_pane",
        vertical_scroll_policy = "auto",
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.maximal_height = scroll_height
    scroll.style.right_padding = 8

    add_section(
        scroll,
        { "the-cave-welcome.begin-title" },
        { "the-cave-welcome.begin-body" },
        content_width
    )

    local darkness_active = startup_enabled("the-cave-darkness-infestation", true)
    add_section(
        scroll,
        darkness_active and { "the-cave-welcome.darkness-on-title" }
            or { "the-cave-welcome.darkness-off-title" },
        darkness_active and { "the-cave-welcome.darkness-on-body" }
            or { "the-cave-welcome.darkness-off-body" },
        content_width
    )

    local advancing_collapse = startup_enabled("the-cave-advancing-collapse", false)
    if advancing_collapse then
        add_section(
            scroll,
            { "the-cave-welcome.advancing-collapse-title" },
            { "the-cave-welcome.advancing-collapse-body" },
            content_width
        )
    else
        local everything_on = startup_enabled("the-cave-everything-on-nauvis", true)
        add_section(
            scroll,
            everything_on and { "the-cave-welcome.nauvis-on-title" }
                or { "the-cave-welcome.nauvis-off-title" },
            everything_on and { "the-cave-welcome.nauvis-on-body" }
                or { "the-cave-welcome.nauvis-off-body" },
            content_width
        )
    end

    if startup_enabled("the-cave-cavetorio", true) then
        add_section(
            scroll,
            { "the-cave-welcome.cavetorio-title" },
            { "the-cave-welcome.cavetorio-body" },
            content_width
        )
    end

    add_section(
        scroll,
        { "the-cave-welcome.features-title" },
        { "the-cave-welcome.features-body" },
        content_width
    )

    local footer = frame.add { type = "flow", direction = "horizontal" }
    footer.style.top_margin = 8
    footer.style.horizontally_stretchable = true

    local spacer = footer.add { type = "empty-widget" }
    spacer.style.horizontally_stretchable = true

    footer.add {
        type = "button",
        name = CONFIRM_NAME,
        caption = { "the-cave-welcome.confirm" },
        style = "confirm_button",
    }

    frame.auto_center = true
    player.opened = frame
end

function welcome.on_init()
    root()
end

function welcome.on_configuration_changed()
    root()
    for _, player in pairs(game.connected_players) do
        show(player)
    end
end

function welcome.on_player_created(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    show(player)
end

function welcome.on_player_joined_game(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    show(player)
end

function welcome.on_gui_click(event)
    local element = event and event.element
    if not (element and element.valid and element.name == CONFIRM_NAME) then return end
    destroy(game.get_player(event.player_index), true)
end

function welcome.on_gui_closed(event)
    local element = event and event.element
    if not (element and element.valid and element.name == FRAME_NAME) then return end
    destroy(game.get_player(event.player_index), true)
end

return welcome
