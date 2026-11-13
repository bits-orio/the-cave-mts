local settings = require("scripts.game_settings").proxy(settings)

-- The Cave information, settings, controls and Caves menu.
-- Everything in this module is read-only; it never changes mod settings.
local cave_teams = require("scripts.cave_teams")

local gui = {}

local BUTTON_NAME = "the_cave_information_button"
local LEGACY_TOP_BUTTON_COLUMN = "the_cave_top_button_column"
local FORTIFIED_COLUMN = "the_cave_fortified_column"
local FORTIFIED_TIMER_LABEL = "the_cave_fortified_timer_label"
local FRAME_NAME = "the_cave_information_frame"
local CLOSE_NAME = "the_cave_information_close"
local CATEGORY_PREFIX = "the_cave_information_category_"
local CATEGORY_CONTENT = "the_cave_information_category_content"
local CAVES_CONTENT = "the_cave_information_caves_content"
local CAVES_REFRESH = "the_cave_information_caves_refresh"

local FEATURE_CATEGORIES = {
    {
        key = "overview",
        cards = {
            { "overview-core-title", "overview-core-body" },
            { "overview-depth-title", "overview-depth-body" },
            { "overview-config-title", "overview-config-body" },
        },
    },
    {
        key = "exploration",
        cards = {
            { "explore-dig-title", "explore-dig-body" },
            { "explore-rooms-title", "explore-rooms-body" },
            { "explore-darkness-title", "explore-darkness-body", "the-cave-darkness-infestation" },
            { "explore-treasure-title", "explore-treasure-body" },
        },
    },
    {
        key = "resources",
        cards = {
            { "resources-veins-title", "resources-veins-body", "the-cave-mixed-resource-patches" },
            { "resources-digging-title", "resources-digging-body", "the-cave-digging-mode" },
            { "resources-missing-title", "resources-missing-body", "the-cave-ore-patch-missing" },
            { "resources-tools-title", "resources-tools-body", "the-cave-filter-mining-drills" },
        },
    },
    {
        key = "space-age",
        cards = {
            { "space-mode-title", "space-mode-body", "the-cave-everything-on-nauvis" },
            { "space-vulcanus-title", "space-vulcanus-body" },
            { "space-gleba-title", "space-gleba-body" },
            { "space-fulgora-title", "space-fulgora-body" },
            { "space-aquilo-title", "space-aquilo-body" },
        },
    },
    {
        key = "missions",
        cards = {
            { "mission-uranium-title", "mission-uranium-body", "the-cave-uranium-caves" },
            { "mission-mineral-title", "mission-mineral-body", {
                "the-cave-iron-cave",
                "the-cave-copper-cave",
                "the-cave-coal-cave",
            } },
            { "mission-vault-title", "mission-vault-body" },
            { "mission-special-title", "mission-special-body" },
        },
    },
    {
        key = "combat",
        cards = {
            { "combat-enemies-title", "combat-enemies-body" },
            { "combat-blood-title", "combat-blood-body", "the-cave-ore-blood" },
            { "combat-rockets-title", "combat-rockets-body", "the-cave-chemical-rockets" },
            { "combat-market-title", "combat-market-body" },
        },
    },
    {
        key = "trains",
        cards = {
            { "train-interior-title", "train-interior-body", "the-cave-train-interiors" },
            { "train-expansion-title", "train-expansion-body" },
            { "train-power-title", "train-power-body" },
            { "train-garden-title", "train-garden-body" },
        },
    },
    {
        key = "cavetorio",
        cards = {
            { "cavetorio-core-title", "cavetorio-core-body", "the-cave-cavetorio" },
            { "cavetorio-outpost-title", "cavetorio-outpost-body" },
            { "cavetorio-waves-title", "cavetorio-waves-body" },
        },
    },
    {
        key = "research",
        cards = {
            { "research-character-title", "research-character-body" },
            { "research-logistics-title", "research-logistics-body" },
            { "research-combat-title", "research-combat-body" },
            { "research-inserter-title", "research-inserter-body", "the-cave-inserter-configurable" },
        },
    },
    {
        key = "machines",
        cards = {
            { "machines-heat-title", "machines-heat-body" },
            { "machines-storage-title", "machines-storage-body" },
            { "machines-logistics-title", "machines-logistics-body" },
            { "machines-early-title", "machines-early-body" },
        },
    },
    {
        key = "quality-life",
        cards = {
            { "quality-start-title", "quality-start-body" },
            { "quality-teleport-title", "quality-teleport-body" },
            { "quality-feedback-title", "quality-feedback-body", "the-cave-integrated-damage-indicator" },
            { "quality-tools-title", "quality-tools-body" },
            { "quality-multiplayer-title", "quality-multiplayer-body", "the-cave-offline-player-body" },
        },
    },
}

local CONTROL_ROWS = {
    { "Ctrl + Enter", "control-train-title", "control-train-body" },
    { "Ctrl + T", "control-teleporter-title", "control-teleporter-body" },
    { { "the-cave-info.control-automatic" }, "control-garden-title", "control-garden-body" },
    { "Backspace", "control-corpses-title", "control-corpses-body" },
    { "Shortcut bar", "control-drills-title", "control-drills-body" },
    { "Shortcut bar", "control-eraser-title", "control-eraser-body" },
    { "Ctrl + R / Ctrl + Shift + R", "control-inserter-rotate-title", "control-inserter-rotate-body" },
    { "F / Ctrl + F", "control-inserter-distance-title", "control-inserter-distance-body" },
}

local INDUSTRY_WEIGHTS = {
    ["mining-drill"] = 4,
    furnace = 2,
    ["assembling-machine"] = 3,
    lab = 5,
    ["rocket-silo"] = 100,
    ["agricultural-tower"] = 5,
}

local POWER_WEIGHTS = {
    ["ammo-turret"] = 3,
    ["electric-turret"] = 6,
    ["fluid-turret"] = 5,
    ["artillery-turret"] = 15,
    wall = 0.25,
    gate = 0.5,
}

local function startup_value(name)
    local setting = settings and settings.startup and settings.startup[name]
    return setting and setting.value or nil
end

local function value_text(value)
    if value == true then return { "the-cave-info.value-enabled" } end
    if value == false then return { "the-cave-info.value-disabled" } end
    if value == "enabled" then return { "the-cave-info.value-enabled" } end
    if value == "disabled" then return { "the-cave-info.value-disabled" } end
    return tostring(value)
end

local function setting_value_text(setting_name)
    if type(setting_name) == "table" then
        return {
            "the-cave-info.mineral-cave-values",
            value_text(startup_value(setting_name[1]) or "n/a"),
            value_text(startup_value(setting_name[2]) or "n/a"),
            value_text(startup_value(setting_name[3]) or "n/a"),
        }
    end
    return value_text(startup_value(setting_name) or "n/a")
end

local function add_wrapped_label(parent, caption, width)
    local label = parent.add { type = "label", caption = caption }
    label.style.single_line = false
    label.style.width = math.max(180, width)
    return label
end

local function add_heading(parent, caption)
    local label = parent.add { type = "label", caption = caption }
    label.style.font = "default-large-bold"
    label.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    label.style.bottom_margin = 8
    return label
end

local function add_info_card(parent, title, body, width, setting_name)
    local card = parent.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
    }
    card.style.horizontally_stretchable = true
    card.style.bottom_margin = 8

    local header = card.add { type = "flow", direction = "horizontal" }
    header.style.horizontally_stretchable = true
    local heading = header.add { type = "label", caption = title }
    heading.style.font = "default-bold"
    heading.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    if setting_name then
        local spacer = header.add { type = "empty-widget" }
        spacer.style.horizontally_stretchable = true
        local status = header.add {
            type = "label",
            caption = { "the-cave-info.current-value", setting_value_text(setting_name) },
        }
        status.style.font = "default-semibold"
        status.style.font_color = { r = 0.45, g = 0.85, b = 1 }
    end
    add_wrapped_label(card, body, width)
end

local function create_top_button(player)
    if not (player and player.valid) then return end
    local top = player.gui.top
    local fortified_column = top[FORTIFIED_COLUMN]
    if fortified_column and fortified_column.valid then
        for index, child in ipairs(top.children) do
            if child == fortified_column and index > 1 then top.swap_children(1, index); break end
        end
        return
    end

    -- Remove the temporary 3.0.21 vertical column. Keeping a 160-pixel column
    -- inside gui.top stretched the Wave panel and moved this button to its right.
    local legacy_column = top[LEGACY_TOP_BUTTON_COLUMN]
    if legacy_column and legacy_column.valid then legacy_column.destroy() end

    -- Restore the exact pre-3.0.21 structure: Information is a direct 80x80
    -- child of gui.top and occupies the first position before the Wave panel.
    local button = top[BUTTON_NAME]
    if not (button and button.valid) then
        button = top.add {
            type = "sprite-button",
            name = BUTTON_NAME,
            sprite = "the-cave-gui-icon",
            tooltip = { "the-cave-info.button-tooltip" },
            style = "slot_button",
        }
    end
    button.style.width = 80
    button.style.height = 80
    button.style.padding = 4

    for index, child in ipairs(top.children) do
        if child.name == BUTTON_NAME and index > 1 then
            top.swap_children(1, index)
            break
        end
    end
end

-- Only while inside a spiral: timer above the existing Information button.
-- Leaving restores the original direct-child layout for every other system.
function gui.set_fortified_hud(player, caption, tooltip)
    if not (player and player.valid) then return end
    local top = player.gui.top
    local column = top[FORTIFIED_COLUMN]
    if not caption then
        if column then column.destroy(); create_top_button(player) end
        return
    end
    if not column then
        local button = top[BUTTON_NAME]
        if button then button.destroy() end
        column = top.add { type = "flow", name = FORTIFIED_COLUMN, direction = "vertical" }
        column.style.vertical_spacing = 2
        local frame = column.add { type = "frame", name = "timer", direction = "vertical" }
        frame.add { type = "label", name = FORTIFIED_TIMER_LABEL, caption = caption }
        local button = column.add { type = "sprite-button", name = BUTTON_NAME,
            sprite = "the-cave-gui-icon", tooltip = { "the-cave-info.button-tooltip" }, style = "slot_button" }
        button.style.width=80; button.style.height=80; button.style.padding=4
    end
    column.timer[FORTIFIED_TIMER_LABEL].caption = caption
    column.timer.tooltip = tooltip
    create_top_button(player)
end

local function destroy_main(player)
    if not (player and player.valid) then return end
    local frame = player.gui.screen[FRAME_NAME]
    if player.opened == frame then player.opened = nil end
    if frame and frame.valid then frame.destroy() end
end

local function display_size(player)
    local resolution = player.display_resolution or { width = 1280, height = 720 }
    local scale = player.display_scale or 1
    if scale <= 0 then scale = 1 end
    return resolution.width / scale, resolution.height / scale
end

local function add_scroll(parent, height)
    local scroll = parent.add {
        type = "scroll-pane",
        vertical_scroll_policy = "auto",
        horizontal_scroll_policy = "never",
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.maximal_height = height
    scroll.style.right_padding = 8
    return scroll
end

local function add_server_section(parent, caption)
    local heading = parent.add { type = "label", caption = caption }
    heading.style.font = "default-large-bold"
    heading.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    heading.style.top_margin = 10
    heading.style.bottom_margin = 4
    return heading
end

local function add_server_line(parent, caption, width, color, bold)
    local label = add_wrapped_label(parent, caption, width)
    label.style.bottom_margin = 2
    if color then label.style.font_color = color end
    if bold then label.style.font = "default-bold" end
    return label
end

local function build_server_tab(parent, player, width, height)
    local scroll = add_scroll(parent, height)
    local panel = scroll.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
    }
    panel.style.horizontally_stretchable = true
    local line_width = width - 42

    add_server_section(panel, { "the-cave-info.server-welcome-title" })
    add_server_line(panel, { "the-cave-info.server-welcome-detailed" }, line_width)

    local total, online = #game.players, #game.connected_players
    local ticks = game.tick or 0
    local minutes = math.floor(ticks / 3600)
    local hours = math.floor(minutes / 60)
    minutes = minutes % 60
    local everything = startup_value("the-cave-everything-on-nauvis") or "disabled"
    local difficulty = startup_value("the-cave-global-difficulty") or "medium"
    local lighting = startup_value("the-cave-underground-lighting-mode") or "permanent-night"
    local cavetorio = startup_value("the-cave-cavetorio") or "disabled"
    local trains = startup_value("the-cave-train-interiors") or "disabled"
    local shelter = startup_value("the-cave-shelter-defense") or "disabled"
    local darkness = startup_value("the-cave-darkness-infestation") or "disabled"
    local collapse_mode = startup_value("the-cave-collapse-mode") or "disabled"
    local advancing_collapse = startup_value("the-cave-advancing-collapse") or "disabled"

    add_server_section(panel, { "the-cave-info.server-settings-title" })
    add_server_line(panel, { "the-cave-info.server-advancing-collapse", value_text(advancing_collapse) }, line_width)
    add_server_line(panel, { "the-cave-info.server-collapse", value_text(collapse_mode) }, line_width)
    add_server_line(panel, { "the-cave-info.server-everything", value_text(everything) }, line_width)
    add_server_line(panel, { "the-cave-info.server-cavetorio", value_text(cavetorio) }, line_width)
    add_server_line(panel, { "the-cave-info.server-shelter", value_text(shelter) }, line_width)
    add_server_line(panel, { "the-cave-info.server-trains", value_text(trains) }, line_width)
    add_server_line(panel, { "the-cave-info.server-darkness", value_text(darkness) }, line_width)
    add_server_line(panel, { "the-cave-info.server-difficulty", tostring(difficulty) }, line_width)
    add_server_line(panel, { "the-cave-info.server-lighting", tostring(lighting) }, line_width)

    add_server_section(panel, { "the-cave-info.server-features-title" })
    add_server_line(panel, { "the-cave-info.server-feature-depth" }, line_width)
    add_server_line(panel, { "the-cave-info.server-feature-rooms" }, line_width)
    add_server_line(panel, { "the-cave-info.server-feature-missions" }, line_width)
    add_server_line(panel, { "the-cave-info.server-feature-research" }, line_width)
    add_server_line(panel, { "the-cave-info.server-feature-caves" }, line_width)

    add_server_section(panel, { "the-cave-info.server-important-title" })
    -- Collapse status is deliberately the first Important line so nobody can
    -- mistake the Support Struts chain for an inactive/active hidden mechanic.
    if collapse_mode == "enabled" then
        add_server_line(panel, { "the-cave-info.server-important-collapse-enabled" }, line_width,
            { r = 1, g = 0.20, b = 0.12 }, true)
    else
        add_server_line(panel, { "the-cave-info.server-important-collapse-disabled" }, line_width,
            { r = 0.55, g = 0.85, b = 1 }, true)
    end
    if darkness == "enabled" then
        add_server_line(panel, { "the-cave-info.server-important-darkness" }, line_width,
            { r = 1, g = 0.78, b = 0.28 })
    end
    if advancing_collapse == "enabled" then
        add_server_line(panel, { "the-cave-info.server-important-advancing-directions" }, line_width,
            { r = 1, g = 0.42, b = 0.10 }, true)
    elseif everything == "enabled" then
        add_server_line(panel, { "the-cave-info.server-important-directions" }, line_width)
    else
        add_server_line(panel, { "the-cave-info.server-important-planets" }, line_width)
    end
    add_server_line(panel, { "the-cave-info.server-important-startup" }, line_width)

    add_server_section(panel, { "the-cave-info.server-map-info-title" })
    add_server_line(panel, { "the-cave-info.server-runtime", hours, minutes }, line_width, nil, true)
    add_server_line(panel, { "the-cave-info.server-online", online, total }, line_width)
    if startup_value("the-cave-offline-player-body") == "enabled" then
        add_server_line(panel, { "the-cave-info.server-offline-warning" }, line_width,
            { r = 1, g = 0.18, b = 0.22 }, true)
    else
        add_server_line(panel, { "the-cave-info.server-offline-disabled" }, line_width,
            { r = 0.60, g = 0.80, b = 0.85 })
    end
end

local function find_category(key)
    for _, category in ipairs(FEATURE_CATEGORIES) do
        if category.key == key then return category end
    end
    return FEATURE_CATEGORIES[1]
end

local function build_category_content(container, key, width)
    container.clear()
    local category = find_category(key)
    local advancing = startup_value("the-cave-advancing-collapse") == "enabled"
    local advancing_space_titles = {
        ["space-vulcanus-title"] = "space-vulcanus-advancing-title",
        ["space-gleba-title"] = "space-gleba-advancing-title",
        ["space-fulgora-title"] = "space-fulgora-advancing-title",
        ["space-aquilo-title"] = "space-aquilo-advancing-title",
    }
    add_heading(container, { "the-cave-info.category-" .. category.key })
    for _, card in ipairs(category.cards) do
        local title_key = advancing and advancing_space_titles[card[1]] or card[1]
        local body_key = card[2]
        if body_key == "overview-depth-body" and advancing then
            title_key = "overview-evolution-title"
            body_key = "overview-evolution-body"
        end
        if body_key == "space-mode-body" and advancing then
            body_key = "space-mode-advancing-body"
        end
        add_info_card(
            container,
            { "the-cave-info." .. title_key },
            { "the-cave-info." .. body_key },
            width,
            card[3]
        )
    end
end

local function build_mod_info_tab(parent, width, height)
    local body = parent.add { type = "flow", direction = "horizontal" }
    body.style.horizontally_stretchable = true

    local menu = add_scroll(body, height)
    local menu_width = math.min(230, math.max(175, math.floor(width * 0.24)))
    menu.style.horizontally_stretchable = false
    menu.style.width = menu_width
    menu.style.right_margin = 8
    for _, category in ipairs(FEATURE_CATEGORIES) do
        local button = menu.add {
            type = "button",
            name = CATEGORY_PREFIX .. category.key,
            caption = { "the-cave-info.category-" .. category.key },
            tags = { cave_category = category.key },
        }
        button.style.horizontally_stretchable = true
        button.style.horizontal_align = "left"
        button.style.bottom_margin = 2
    end

    local content = body.add {
        type = "scroll-pane",
        name = CATEGORY_CONTENT,
        vertical_scroll_policy = "auto",
        horizontal_scroll_policy = "never",
    }
    content.style.horizontally_stretchable = true
    content.style.maximal_height = height
    content.style.right_padding = 8
    local content_width = math.max(250, width - menu_width - 42)
    build_category_content(content, "overview", content_width)
end

local function is_our_setting(name)
    return name:sub(1, 9) == "the-cave-" or name:sub(1, 6) == "diggy-"
        or name:sub(1, 17) == "damage-indicator-"
end

local LEGACY_SETTINGS = {
    ["diggy-dig-nest-chance"] = true,
    ["diggy-collapse-enabled"] = true,
    ["diggy-wall-support"] = true,
    ["diggy-strut-strength-max"] = true,
    ["diggy-cavern-countdown"] = true,
    ["diggy-wall-crowding"] = true,
    ["diggy-collapse-broadcast"] = true,
    ["diggy-crushed-remains"] = true,
}

local CAPACITY_ORDER = {
    ["the-cave-wooden-chest-capacity"] = 1,
    ["the-cave-iron-chest-capacity"] = 2,
    ["the-cave-steel-chest-capacity"] = 3,
    ["the-cave-logistic-chest-capacity"] = 4,
    ["the-cave-industrial-container-1x1-capacity"] = 5,
    ["the-cave-industrial-container-2x2-capacity"] = 6,
    ["the-cave-industrial-container-4x4-capacity"] = 7,
    ["the-cave-industrial-container-6x6-capacity"] = 8,
}

local STACK_ORDER = {
    ["the-cave-early-stack-size"] = 1,
    ["the-cave-iron-ore-stack-size"] = 2,
    ["the-cave-copper-ore-stack-size"] = 3,
    ["the-cave-coal-stack-size"] = 4,
    ["the-cave-stone-stack-size"] = 5,
    ["the-cave-uranium-ore-stack-size"] = 6,
    ["the-cave-scrap-stack-size"] = 7,
}

local SUPERHEATING_ORDER = {
    ["the-cave-superheating-crude-oil-value"] = 1,
    ["the-cave-superheating-heavy-oil-value"] = 2,
    ["the-cave-superheating-light-oil-value"] = 3,
    ["the-cave-superheating-petroleum-gas-value"] = 4,
}

local SETTING_BUCKETS = {
    { key = "enabled", title = "the-cave-info.settings-enabled" },
    { key = "disabled", title = "the-cave-info.settings-disabled" },
    { key = "modes", title = "the-cave-info.settings-modes" },
    { key = "capacities", title = "the-cave-info.settings-capacities" },
    { key = "stacks", title = "the-cave-info.settings-stacks" },
    { key = "superheating", title = "the-cave-info.settings-superheating" },
    { key = "numeric", title = "the-cave-info.settings-numeric" },
    { key = "other", title = "the-cave-info.settings-other" },
    { key = "legacy", title = "the-cave-info.settings-legacy" },
}

local function setting_bucket(name, value)
    if LEGACY_SETTINGS[name] then return "legacy" end
    if value == true or value == "enabled" then return "enabled" end
    if value == false or value == "disabled" then return "disabled" end
    if CAPACITY_ORDER[name] or name:find("chest%-capacity") or name:find("container.*capacity") then
        return "capacities"
    end
    if STACK_ORDER[name] or name:find("stack%-size") then return "stacks" end
    if SUPERHEATING_ORDER[name] or name:find("^the%-cave%-superheating%-.*%-value$") then
        return "superheating"
    end
    if name:find("mode") or name:find("difficulty") or name:find("access")
        or name:find("patch%-size") or name:find("blacklist")
        or name:find("remove%-collision") then
        return "modes"
    end
    if type(value) == "number" then return "numeric" end
    return "other"
end

local function setting_sort_key(name, bucket)
    if bucket == "capacities" then return CAPACITY_ORDER[name] or 1000 end
    if bucket == "stacks" then return STACK_ORDER[name] or 1000 end
    if bucket == "superheating" then return SUPERHEATING_ORDER[name] or 1000 end
    return 0
end

local function setting_localised_name(name)
    return { "mod-setting-name." .. name }
end

local function add_settings_group(parent, title, source, width)
    local grouped = {}
    local count = 0
    for name, setting in pairs(source) do
        if is_our_setting(name) then
            local bucket = setting_bucket(name, setting.value)
            grouped[bucket] = grouped[bucket] or {}
            grouped[bucket][#grouped[bucket] + 1] = name
            count = count + 1
        end
    end

    local group = parent.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
    }
    group.style.horizontally_stretchable = true
    group.style.bottom_margin = 10
    local heading = group.add { type = "label", caption = { title, count } }
    heading.style.font = "default-large-bold"
    heading.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    heading.style.bottom_margin = 6

    for _, definition in ipairs(SETTING_BUCKETS) do
        local names = grouped[definition.key] or {}
        if #names > 0 then
            table.sort(names, function(a, b)
                local ao = setting_sort_key(a, definition.key)
                local bo = setting_sort_key(b, definition.key)
                if ao == bo then return a < b end
                return ao < bo
            end)

            local subheading = group.add { type = "label", caption = { definition.title, #names } }
            subheading.style.font = "default-bold"
            subheading.style.font_color = { r = 0.72, g = 0.88, b = 1 }
            subheading.style.top_margin = 6
            subheading.style.bottom_margin = 3

            local grid = group.add { type = "table", column_count = 2 }
            grid.style.horizontal_spacing = 16
            grid.style.vertical_spacing = 4
            for _, name in ipairs(names) do
                local setting = source[name]
                local label = grid.add {
                    type = "label",
                    caption = setting_localised_name(name),
                    tooltip = name,
                }
                label.style.width = math.max(200, math.floor(width * 0.62))
                label.style.single_line = false
                local value = grid.add { type = "label", caption = value_text(setting.value) }
                value.style.font = "default-semibold"
                value.style.font_color = { r = 0.35, g = 0.88, b = 1 }
            end
        end
    end
end

local function build_settings_tab(parent, player, width, height)
    local scroll = add_scroll(parent, height)
    add_heading(scroll, { "the-cave-info.settings-title" })
    add_wrapped_label(scroll, { "the-cave-info.settings-read-only" }, width)
    add_settings_group(scroll, "the-cave-info.settings-startup", settings.startup, width)
    add_settings_group(scroll, "the-cave-info.settings-map", settings.global, width)
    add_settings_group(scroll, "the-cave-info.settings-player", settings.get_player_settings(player), width)
end

local function build_controls_tab(parent, width, height)
    local scroll = add_scroll(parent, height)
    add_heading(scroll, { "the-cave-info.controls-title" })
    add_wrapped_label(scroll, { "the-cave-info.controls-intro" }, width)
    for _, row in ipairs(CONTROL_ROWS) do
        local card = scroll.add {
            type = "frame",
            direction = "horizontal",
            style = "inside_shallow_frame_with_padding",
        }
        card.style.horizontally_stretchable = true
        card.style.bottom_margin = 6
        local key = card.add { type = "label", caption = row[1] }
        key.style.font = "default-bold"
        key.style.font_color = { r = 0.45, g = 0.85, b = 1 }
        local key_width = math.min(210, math.floor(width * 0.25))
        key.style.width = key_width
        local text = card.add { type = "flow", direction = "vertical" }
        local title = text.add { type = "label", caption = { "the-cave-info." .. row[2] } }
        title.style.font = "default-bold"
        add_wrapped_label(text, { "the-cave-info." .. row[3] }, width - key_width - 55)
    end
end

local function force_entity_score(force, weights)
    local score = 0
    for entity_type, weight in pairs(weights) do
        for _, surface in pairs(game.surfaces) do
            local count = surface.count_entities_filtered {
                force = force,
                type = entity_type,
            }
            if count > 0 then score = score + count * weight end
        end
    end
    return math.floor(score + 0.5)
end

local function force_technology_score(force)
    local score, researched = 0, 0
    for _, technology in pairs(force.technologies) do
        if technology.researched then
            researched = researched + 1
            score = score + 10 + math.min(30, math.max(0, (technology.level or 1) - 1))
        end
    end
    return score, researched
end

local function player_coin_count(player)
    if not player or not player.valid then return 0 end
    if not (prototypes and prototypes.item and prototypes.item["coin"]) then return 0 end
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then return 0 end
    return inventory.get_item_count("coin")
end

local function force_players(force)
    local players, names, online_players = 0, {}, {}
    for _, player in pairs(game.players) do
        if player.valid and player.force == force then
            players = players + 1
            names[#names + 1] = player.name
            if player.connected then
                online_players[#online_players + 1] = {
                    name = player.name,
                    coins = player_coin_count(player),
                }
            end
        end
    end
    table.sort(names)
    table.sort(online_players, function(a, b) return a.name < b.name end)
    return players, #online_players, names, online_players
end

local function cave_name(force)
    if force.name == "player" then return { "the-cave-info.default-cave-name" } end
    return cave_teams.team_label(force)
end

local function threat_text(value)
    if value >= 7000 then return { "the-cave-info.threat-extreme" } end
    if value >= 3500 then return { "the-cave-info.threat-critical" } end
    if value >= 1500 then return { "the-cave-info.threat-severe" } end
    if value >= 500 then return { "the-cave-info.threat-high" } end
    return { "the-cave-info.threat-low" }
end

local function short_number(value)
    value = math.floor(value + 0.5)
    if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
    if value >= 1000 then return string.format("%.1fK", value / 1000) end
    return tostring(value)
end

local function cave_rows()
    local rows = {}
    for _, force in pairs(game.forces) do
        if force.name ~= "enemy" and force.name ~= "neutral" then
            local players, online, names, online_players = force_players(force)
            if players > 0 then
                local industry = force_entity_score(force, INDUSTRY_WEIGHTS)
                local defence = force_entity_score(force, POWER_WEIGHTS)
                local technology, researched = force_technology_score(force)
                local depths = storage.the_cave_max_depth or {}
                local depth = tonumber(depths[force.index]) or 0
                local power = math.floor(players * 25 + online * 75 + defence + depth / 5)
                local score = power + technology + industry + math.floor(depth / 2)
                rows[#rows + 1] = {
                    force = force,
                    players = players,
                    online = online,
                    names = names,
                    online_players = online_players,
                    power = power,
                    technology = technology,
                    researched = researched,
                    industry = industry,
                    threat = power + math.floor(technology * 0.35),
                    score = score,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.score == b.score then return a.force.name < b.force.name end
        return a.score > b.score
    end)
    return rows
end

local function add_cave_cell(table_element, caption, width, tooltip, bold)
    local label = table_element.add { type = "label", caption = caption, tooltip = tooltip }
    label.style.width = width
    label.style.horizontal_align = "center"
    label.style.vertical_align = "center"
    label.style.single_line = false
    if bold then label.style.font = "default-bold" end
    return label
end

local function cave_column_widths(width)
    local spacing = 8
    local table_width = math.max(350, width - 34)
    local cave_width = math.max(110, math.floor(table_width * 0.235))
    local number_width = math.floor((table_width - cave_width - spacing * 5) / 5)
    return spacing, cave_width, math.max(40, number_width)
end

local function add_caves_header(parent, width)
    local spacing, cave_width, number_width = cave_column_widths(width)
    local header = parent.add { type = "table", column_count = 6 }
    header.style.horizontal_spacing = spacing
    header.style.vertical_spacing = 3
    header.style.bottom_margin = 4
    add_cave_cell(header, { "the-cave-info.cave-column" }, cave_width, nil, true)
    add_cave_cell(header, { "the-cave-info.score-column" }, number_width, nil, true)
    add_cave_cell(header, { "the-cave-info.power-column" }, number_width, nil, true)
    add_cave_cell(header, { "the-cave-info.threat-column" }, number_width, nil, true)
    add_cave_cell(header, { "the-cave-info.technology-column" }, number_width, nil, true)
    add_cave_cell(header, { "the-cave-info.industry-column" }, number_width, nil, true)
end

local function coin_rows(caves)
    local rows = {}
    for _, cave in ipairs(caves) do
        for _, player in ipairs(cave.online_players) do
            rows[#rows + 1] = {
                name = player.name,
                coins = player.coins,
                force = cave.force,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.coins == b.coins then return a.name < b.name end
        return a.coins > b.coins
    end)
    return rows
end

local function add_coin_leaderboard(parent, caves, width)
    add_heading(parent, { "the-cave-info.coin-leaderboard-title" })
    local players = coin_rows(caves)
    if #players == 0 then
        add_wrapped_label(parent, { "the-cave-info.no-online-players" }, width)
        return
    end

    local spacing, rank_width = 8, 42
    local table_width = math.max(350, width - 34)
    local coins_width = math.max(90, math.floor(table_width * 0.25))
    local player_width = table_width - rank_width - coins_width - spacing * 2
    local frame = parent.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
    }
    frame.style.horizontally_stretchable = true
    local table_element = frame.add {
        type = "table",
        name = "the_cave_information_coin_table",
        column_count = 3,
    }
    table_element.style.horizontal_spacing = spacing
    table_element.style.vertical_spacing = 6
    add_cave_cell(table_element, "#", rank_width, nil, true)
    add_cave_cell(table_element, { "the-cave-info.player-column" }, player_width, nil, true)
    add_cave_cell(table_element, { "the-cave-info.coins-column" }, coins_width, nil, true)

    for rank, player in ipairs(players) do
        local tooltip = { "the-cave-info.player-team-tooltip", cave_name(player.force) }
        local rank_caption = rank <= 3 and { "the-cave-info.rank-star", rank } or "#" .. rank
        add_cave_cell(table_element, rank_caption, rank_width, tooltip, true)
        local name = add_cave_cell(table_element, player.name, player_width, tooltip, true)
        name.style.font_color = { r = 80 / 255, g = 190 / 255, b = 1 }
        add_cave_cell(table_element, { "", "[item=coin] ", short_number(player.coins) },
            coins_width, tostring(player.coins), true)
    end
end

local function rebuild_caves(container, width, height)
    container.clear()
    local rows = cave_rows()
    local online = #game.connected_players

    local top = container.add { type = "flow", direction = "horizontal" }
    top.style.horizontally_stretchable = true
    top.style.vertical_align = "center"
    local title = top.add {
        type = "label",
        caption = { "the-cave-info.caves-title", #rows, online },
    }
    title.style.font = "default-large-bold"
    title.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    local spacer = top.add { type = "empty-widget" }
    spacer.style.horizontally_stretchable = true
    top.add {
        type = "button",
        name = CAVES_REFRESH,
        caption = { "the-cave-info.refresh" },
    }

    add_wrapped_label(container, { "the-cave-info.caves-description" }, width - 20)

    local rows_scroll = container.add {
        type = "scroll-pane",
        vertical_scroll_policy = "auto",
        horizontal_scroll_policy = "never",
    }
    rows_scroll.style.horizontally_stretchable = true
    rows_scroll.style.maximal_height = math.max(180, height - 105)
    rows_scroll.style.right_padding = 8

    add_heading(rows_scroll, { "the-cave-info.team-statistics-title" })
    add_caves_header(rows_scroll, width)
    local spacing, cave_width, number_width = cave_column_widths(width)

    for _, row in ipairs(rows) do
        local row_frame = rows_scroll.add {
            type = "frame",
            direction = "vertical",
            style = "inside_shallow_frame_with_padding",
        }
        row_frame.style.horizontally_stretchable = true
        row_frame.style.bottom_margin = 4
        row_frame.style.minimal_height = 58

        local table_element = row_frame.add { type = "table", column_count = 6 }
        table_element.style.horizontal_spacing = spacing
        table_element.style.vertical_spacing = 2
        local tooltip = { "the-cave-info.cave-tooltip", table.concat(row.names, ", "), row.online, row.players }
        add_cave_cell(table_element, {
            "the-cave-info.cave-name-line", cave_name(row.force), row.online, row.players,
        }, cave_width, tooltip, true)
        add_cave_cell(table_element, short_number(row.score), number_width, nil, true)
        add_cave_cell(table_element, short_number(row.power), number_width, nil, true)
        add_cave_cell(table_element, threat_text(row.threat), number_width, nil, true)
        add_cave_cell(table_element, {
            "the-cave-info.technology-line", short_number(row.technology), row.researched,
        }, number_width,
            { "the-cave-info.researched-tooltip", row.researched }, true)
        add_cave_cell(table_element, short_number(row.industry), number_width, nil, true)
    end

    if #rows == 0 then
        add_wrapped_label(container, { "the-cave-info.no-caves" }, width)
    end
    add_coin_leaderboard(rows_scroll, rows, width)
end

local function build_caves_tab(parent, width, height)
    local panel = parent.add {
        type = "frame",
        name = CAVES_CONTENT,
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
    }
    panel.style.horizontally_stretchable = true
    panel.style.vertically_stretchable = true
    panel.style.left_margin = 8
    panel.style.right_margin = 8
    panel.style.top_margin = 8
    panel.style.bottom_margin = 8
    rebuild_caves(panel, width - 34, height - 20)
end

local function add_tab(pane, caption, builder)
    local tab = pane.add { type = "tab", caption = caption }
    local content = pane.add { type = "flow", direction = "vertical" }
    content.style.horizontally_stretchable = true
    content.style.vertically_stretchable = true
    pane.add_tab(tab, content)
    builder(content)
end

local function show_main(player)
    local existing = player.gui.screen[FRAME_NAME]
    if existing and existing.valid then
        destroy_main(player)
        return
    end

    local logical_width, logical_height = display_size(player)
    local width = math.floor(math.min(1080, math.max(500, logical_width - 60)))
    local height = math.floor(math.min(680, math.max(430, logical_height - 90)))
    local inner_width = width - 64
    local content_height = height - 145

    local frame = player.gui.screen.add {
        type = "frame",
        name = FRAME_NAME,
        direction = "vertical",
        tags = {
            information_width = width,
            information_inner_width = inner_width,
            information_content_height = content_height,
        },
    }
    frame.style.width = width
    frame.style.height = height

    local header = frame.add { type = "flow", direction = "horizontal" }
    header.style.horizontally_stretchable = true
    header.style.vertical_align = "center"
    local title = header.add { type = "label", caption = { "the-cave-info.window-title" } }
    title.style.font = "heading-1"
    title.style.font_color = { r = 1, g = 0.86, b = 0.12 }
    local drag = header.add { type = "empty-widget", style = "draggable_space_header" }
    drag.style.horizontally_stretchable = true
    drag.style.height = 28
    header.add {
        type = "sprite-button",
        name = CLOSE_NAME,
        sprite = "utility/close",
        style = "frame_action_button",
        tooltip = { "gui.close" },
    }

    local pane = frame.add { type = "tabbed-pane" }
    pane.style.horizontally_stretchable = true
    pane.style.vertically_stretchable = true
    add_tab(pane, { "the-cave-info.tab-server" }, function(content)
        build_server_tab(content, player, inner_width, content_height)
    end)
    add_tab(pane, { "the-cave-info.tab-mod" }, function(content)
        build_mod_info_tab(content, inner_width, content_height)
    end)
    add_tab(pane, { "the-cave-info.tab-settings" }, function(content)
        build_settings_tab(content, player, inner_width, content_height)
    end)
    add_tab(pane, { "the-cave-info.tab-controls" }, function(content)
        build_controls_tab(content, inner_width, content_height)
    end)
    add_tab(pane, { "the-cave-info.tab-caves" }, function(content)
        build_caves_tab(content, inner_width, content_height)
    end)

    frame.auto_center = true
    player.opened = frame
end

function gui.on_init()
    for _, player in pairs(game.players) do create_top_button(player) end
end

function gui.on_configuration_changed()
    for _, player in pairs(game.players) do
        destroy_main(player)
        create_top_button(player)
    end
end

function gui.on_player_created(event)
    create_top_button(game.get_player(event.player_index))
end

function gui.on_player_joined_game(event)
    create_top_button(game.get_player(event.player_index))
end

function gui.on_gui_click(event)
    local element = event and event.element
    if not (element and element.valid) then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    if element.name == BUTTON_NAME then
        show_main(player)
    elseif element.name == CLOSE_NAME then
        destroy_main(player)
    elseif element.name == CAVES_REFRESH then
        local frame = player.gui.screen[FRAME_NAME]
        local content = frame and frame[CAVES_CONTENT]
        if not content and frame then
            local found = frame.children
            local function search(children)
                for _, child in pairs(children or {}) do
                    if child.name == CAVES_CONTENT then return child end
                    local result = search(child.children)
                    if result then return result end
                end
            end
            content = search(found)
        end
        if not frame then return end
        local inner_width = tonumber(frame.tags.information_inner_width) or 900
        local content_height = tonumber(frame.tags.information_content_height) or 500
        if content and content.valid then rebuild_caves(content, inner_width - 34, content_height - 20) end
    elseif element.name:sub(1, #CATEGORY_PREFIX) == CATEGORY_PREFIX then
        local frame = player.gui.screen[FRAME_NAME]
        if not frame then return end
        local function search(node, name)
            if node.name == name then return node end
            for _, child in pairs(node.children or {}) do
                local result = search(child, name)
                if result then return result end
            end
        end
        local content = search(frame, CATEGORY_CONTENT)
        local category = element.tags and element.tags.cave_category
        if content and category then
            local inner_width = tonumber(frame.tags.information_inner_width) or 840
            local menu_width = math.min(230, math.max(175, math.floor(inner_width * 0.24)))
            build_category_content(content, category, math.max(250, inner_width - menu_width - 42))
        end
    end
end

function gui.on_gui_closed(event)
    local element = event and event.element
    if element and element.valid and element.name == FRAME_NAME then
        destroy_main(game.get_player(event.player_index))
    end
end

return gui
