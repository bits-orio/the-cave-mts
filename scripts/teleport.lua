local physical = require("scripts.player_physical")
-- Integrated waypoint teleporter for The Cave.
-- Adapted from KhalcTeleport 1.0.3 by Khalcifer (MIT License).
local mod_gui = require("mod-gui")
local cave_worlds = require("scripts.cave_worlds")

local teleport = {}

local MAX_POINTS = 4
local SAVE_ITEM = "electronic-circuit"
local SAVE_COST = 200
local TELEPORT_ITEM = "advanced-circuit"
local TELEPORT_COST = 10
local COOLDOWN_TICKS = 2 * 60 * 60

local TOGGLE_BUTTON = "the_cave_tp_toggle_btn"
local LEGACY_TOP_BUTTON_COLUMN = "the_cave_top_button_column"
local SHORTCUT_NAME = "the-cave-open-teleporter-shortcut"
local MAIN_FRAME = "the_cave_teleporter_main_frame"
local SETTINGS_FRAME = "the_cave_teleporter_settings_frame"
local SCROLL_NAME = "the_cave_tp_scroll"
local TABLE_NAME = "the_cave_tp_table"

local function root()
    storage.the_cave_teleport = storage.the_cave_teleport or {}
    local data = storage.the_cave_teleport
    data.points = data.points or {}
    data.filters = data.filters or {}
    data.sort = data.sort or {}
    data.search = data.search or {}
    data.last_positions = data.last_positions or {}
    data.player_settings = data.player_settings or {}
    data.cooldowns = data.cooldowns or {}
    return data
end

local function valid_player(player)
    return player and player.valid
end

local function unlocked_slots(player)
    if not valid_player(player) then return 0 end
    local technologies = player.force and player.force.technologies
    if not technologies then return 0 end
    local level_3 = technologies["the-cave-teleporter-3"]
    if level_3 and level_3.researched then return 4 end
    local level_2 = technologies["the-cave-teleporter-2"]
    if level_2 and level_2.researched then return 3 end
    local level_1 = technologies["the-cave-teleporter-1"]
    if level_1 and level_1.researched then return 2 end
    return 0
end

local function count_points(points)
    local count = 0
    for _ in pairs(points or {}) do count = count + 1 end
    return count
end

local function cooldown_remaining(player)
    local ready_tick = root().cooldowns[player.index] or 0
    return math.max(0, ready_tick - game.tick)
end

local function cooldown_caption(remaining_ticks)
    local total_seconds = math.max(0, math.ceil(remaining_ticks / 60))
    return string.format("%02d:%02d", math.floor(total_seconds / 60), total_seconds % 60)
end

local function capitalize(value)
    if not value then return "Unknown" end
    return (value:gsub("^%l", string.upper))
end

local function is_valid_save_surface(surface)
    if not (surface and surface.valid) then return false end
    if surface.platform then return true end
    -- Copied cave worlds can be plain script surfaces without a planet.
    if surface.name == "nauvis"
        or cave_worlds.is_copy(surface)
        or surface.name:match("^the%-cave%-warp%-%d+$") then
        return true
    end
    local planet = surface.planet
    if not planet or planet.surface ~= surface then return false end
    local name = surface.name
    if name:find("factory", 1, true)
        or name:find("condenser", 1, true)
        or name:find("temp", 1, true) then
        return false
    end
    return true
end

local function surface_icon(surface)
    if surface.platform then return "item/space-platform-starter-pack" end
    if surface.planet then return "space-location/" .. surface.planet.name end
    -- Copied and Warp surfaces are generated cave-world equivalents of Nauvis;
    -- their own names do not have SpaceLocation sprites.
    return "space-location/nauvis"
end

local function format_time_ago(last_tick)
    if not last_tick then return { "the-cave-teleport.never" } end
    local seconds = math.floor((game.tick - last_tick) / 60)
    if seconds < 1 then return { "the-cave-teleport.just-now" } end
    if seconds < 60 then return { "the-cave-teleport.seconds-ago", seconds } end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return { "the-cave-teleport.minutes-ago", minutes } end
    local hours = math.floor(minutes / 60)
    if hours < 24 then return { "the-cave-teleport.hours-ago", hours } end
    return { "the-cave-teleport.days-ago", math.floor(hours / 24) }
end

local function error_color_tag()
    return "[color=255,0,0]"
end

local function can_pay(player, item, amount)
    local character = physical.character_context(player)
    local inventory = character and character.get_main_inventory() or player.get_main_inventory()
    if not (inventory and inventory.valid) then return false end
    local count = inventory.get_item_count(item)
    if count >= amount then return true end
    player.print({
        "",
        "[img=utility/warning_icon] ",
        error_color_tag(),
        { "the-cave-teleport.missing" },
        " ",
        amount - count,
        "x [item=",
        item,
        "][/color]",
    })
    return false
end

local function collect_cost(player, item, amount)
    local character = physical.character_context(player)
    local inventory = character and character.get_main_inventory() or player.get_main_inventory()
    if not (inventory and inventory.valid) then return false end
    local removed = inventory.remove { name = item, count = amount }
    if removed ~= amount then return false end
    player.print({
        "",
        "[color=green]",
        { "the-cave-teleport.paid" },
        " ",
        amount,
        "x [item=",
        item,
        "][/color]",
    })
    return true
end

local function close_frames(player)
    local settings_frame = player.gui.screen[SETTINGS_FRAME]
    if settings_frame and settings_frame.valid then settings_frame.destroy() end
    local main_frame = player.gui.screen[MAIN_FRAME]
    if main_frame and main_frame.valid then main_frame.destroy() end
end

local function perform_teleport(player, target_position, target_surface_index)
    local surface = game.surfaces[target_surface_index]
    if not (surface and surface.valid) then
        player.print({ "the-cave-teleport.destination-unavailable" })
        return false
    end

    local origin_surface = physical.surface(player)
    local origin = physical.position(player)
    if not (origin_surface and origin_surface.valid and origin) then return false end
    local previous = {
        pos = { x = origin.x, y = origin.y },
        surface_index = origin_surface.index,
        surface_name = origin_surface.platform and origin_surface.platform.name
            or capitalize(origin_surface.name),
    }
    local position = physical.find_position(player, surface, target_position, 16)
    if not physical.teleport(player, position, surface) then
        player.print({ "the-cave-teleport.teleport-failed" })
        return false
    end

    root().last_positions[player.index] = previous
    player.print({ "the-cave-teleport.teleport-complete" })
    surface.create_entity { name = "medium-explosion", position = physical.position(player) }
    close_frames(player)
    return true
end

local function try_teleport(player, target_position, target_surface_index)
    if unlocked_slots(player) == 0 then
        player.print({ "the-cave-teleport.research-required" })
        return false
    end
    local remaining = cooldown_remaining(player)
    if remaining > 0 then
        player.print({ "the-cave-teleport.cooldown-message", cooldown_caption(remaining) })
        return false
    end
    if not can_pay(player, TELEPORT_ITEM, TELEPORT_COST) then
        player.print({ "the-cave-teleport.no-fuel" })
        return false
    end
    if not perform_teleport(player, target_position, target_surface_index) then return false end
    if not collect_cost(player, TELEPORT_ITEM, TELEPORT_COST) then
        player.print({ "the-cave-teleport.cost-collection-failed" })
        return false
    end
    root().cooldowns[player.index] = game.tick + COOLDOWN_TICKS
    return true
end

local function remove_legacy_toggle_button(player)
    if not valid_player(player) then return end

    -- Remove the 3.0.20 mod-gui button without touching any saved destinations.
    local legacy_flow = mod_gui.get_button_flow(player)
    local legacy_button = legacy_flow and legacy_flow[TOGGLE_BUTTON]
    if legacy_button and legacy_button.valid then legacy_button.destroy() end
    local direct_button = player.gui.top[TOGGLE_BUTTON]
    if direct_button and direct_button.valid then direct_button.destroy() end

    -- The temporary 3.0.21 column must not survive in gui.top because its
    -- 160-pixel height stretches the unrelated Wave Defense panel.
    local legacy_column = player.gui.top[LEGACY_TOP_BUTTON_COLUMN]
    if legacy_column and legacy_column.valid then
        local legacy_column_button = legacy_column[TOGGLE_BUTTON]
        if legacy_column_button and legacy_column_button.valid then legacy_column_button.destroy() end
        if #legacy_column.children == 0 then legacy_column.destroy() end
    end

    -- Version 3.1.61 moves Teleporter access to Factorio's shortcut bar.
    -- Remove the former 80x80 gui.left button from existing saves as well.
    local left_button = player.gui.left[TOGGLE_BUTTON]
    if left_button and left_button.valid then left_button.destroy() end
end

local function get_preview_settings(player_index)
    local data = root()
    data.player_settings[player_index] = data.player_settings[player_index] or {
        zoom_camera = 0.1,
        zoom_minimap = 0.5,
        minimap = false,
    }
    return data.player_settings[player_index]
end

local function refresh_list(player)
    local main_frame = player.gui.screen[MAIN_FRAME]
    local scroll = main_frame and main_frame[SCROLL_NAME]
    if not (scroll and scroll.valid) then return end
    scroll.clear()

    local table_gui = scroll.add { type = "table", name = TABLE_NAME, column_count = 3 }
    table_gui.style.horizontally_stretchable = true
    table_gui.style.horizontal_spacing = 8

    local data = root()
    local current_filter = data.filters[player.index]
    local search_query = (data.search[player.index] or ""):lower()
    local points = data.points[player.index] or {}
    local indices = {}
    for index, point in pairs(points) do
        local surface = point and game.surfaces[point.surface_index]
        if surface and surface.valid then indices[#indices + 1] = index end
    end

    local sort_type = data.sort[player.index] or 1
    if sort_type == 1 then
        table.sort(indices, function(a, b) return a < b end)
    elseif sort_type == 2 then
        table.sort(indices, function(a, b) return a > b end)
    else
        table.sort(indices, function(a, b)
            local a_time = points[a].last_used or 0
            local b_time = points[b].last_used or 0
            if a_time ~= b_time then return a_time > b_time end
            return a > b
        end)
    end

    local preview_settings = get_preview_settings(player.index)
    local zoom = preview_settings.minimap and preview_settings.zoom_minimap
        or preview_settings.zoom_camera
    local remaining = cooldown_remaining(player)
    local slot_limit = unlocked_slots(player)

    for _, index in ipairs(indices) do
        local point = points[index]
        local surface = game.surfaces[point.surface_index]
        local matches_surface = current_filter == nil
            or (current_filter == "platforms_group" and surface.platform ~= nil)
            or point.surface_index == current_filter
        local point_name = (point.name or ("Point " .. index)):lower()
        local matches_search = search_query == "" or point_name:find(search_query, 1, true)

        if matches_surface and matches_search then
            local slot_locked = index > slot_limit
            local preview_frame = table_gui.add { type = "frame", style = "inside_shallow_frame" }
            preview_frame.style.minimal_width = 125
            preview_frame.style.maximal_width = 125
            preview_frame.style.minimal_height = 125
            preview_frame.style.maximal_height = 125
            preview_frame.style.padding = 0

            local preview
            if preview_settings.minimap then
                preview = preview_frame.add {
                    type = "minimap",
                    position = point.pos,
                    surface_index = point.surface_index,
                    force = player.force.name,
                    zoom = zoom,
                }
            else
                preview = preview_frame.add {
                    type = "camera",
                    position = point.pos,
                    surface_index = point.surface_index,
                    zoom = zoom,
                }
            end
            preview.style.minimal_width = 125
            preview.style.maximal_width = 125
            preview.style.minimal_height = 125
            preview.style.maximal_height = 125

            local info = table_gui.add { type = "flow", direction = "vertical" }
            info.style.horizontally_stretchable = true
            info.style.padding = { 0, 5, 0, 5 }
            local name_field = info.add {
                type = "textfield",
                name = "the_cave_tp_rename_" .. index,
                text = point.name or ("Point " .. index),
            }
            name_field.style.horizontally_stretchable = true

            local display_surface_name = surface.name
            local icon = surface_icon(surface)
            info.add {
                type = "label",
                caption = "[img=" .. icon .. "] " .. capitalize(display_surface_name),
            }
            local position_row = info.add { type = "flow", direction = "horizontal" }
            local x_label = position_row.add {
                type = "label",
                caption = string.format("X: %.0f", point.pos.x),
            }
            x_label.style.font_color = { r = 1, g = 0.3, b = 0.3 }
            position_row.add { type = "label", caption = " " }
            local y_label = position_row.add {
                type = "label",
                caption = string.format("Y: %.0f", point.pos.y),
            }
            y_label.style.font_color = { r = 0.3, g = 1, b = 0.3 }

            local time_label = info.add {
                type = "label",
                name = "the_cave_tp_time_label_" .. index,
                caption = { "", { "the-cave-teleport.last-visit" }, " ", format_time_ago(point.last_used) },
            }
            time_label.style.font = "default-small-semibold"
            time_label.style.font_color = { r = 0.7, g = 0.7, b = 0.7 }

            local button_flow = table_gui.add { type = "flow", direction = "vertical" }
            button_flow.style.minimal_width = 120
            local teleport_row = button_flow.add { type = "flow", direction = "horizontal" }
            teleport_row.style.vertical_align = "center"
            local go_button = teleport_row.add {
                type = "button",
                name = "the_cave_tp_go_" .. index,
                caption = slot_locked and { "the-cave-teleport.slot-locked" }
                    or (remaining > 0 and cooldown_caption(remaining)
                    or { "the-cave-teleport.teleport" }),
                enabled = not slot_locked and remaining <= 0,
                tooltip = slot_locked and { "the-cave-teleport.slot-locked-tooltip", index }
                    or nil,
            }
            go_button.style.horizontally_stretchable = true
            teleport_row.add {
                type = "sprite",
                sprite = "item/" .. TELEPORT_ITEM,
                tooltip = { "the-cave-teleport.teleport-cost-tooltip", TELEPORT_COST, TELEPORT_ITEM },
            }
            local delete_button = button_flow.add {
                type = "button",
                name = "the_cave_tp_del_" .. index,
                caption = { "the-cave-teleport.delete" },
                style = "red_back_button",
            }
            delete_button.style.horizontally_stretchable = true
            delete_button.style.top_margin = 2
        end
    end
end

local function draw_settings(player)
    local main_frame = player.gui.screen[MAIN_FRAME]
    if not (main_frame and main_frame.valid) then return end
    local existing = player.gui.screen[SETTINGS_FRAME]
    if existing and existing.valid then
        existing.destroy()
        return
    end

    local preview_settings = get_preview_settings(player.index)
    local frame = player.gui.screen.add {
        type = "frame",
        name = SETTINGS_FRAME,
        direction = "vertical",
        caption = { "the-cave-teleport.preview-settings" },
    }
    frame.location = { x = main_frame.location.x + 555, y = main_frame.location.y }
    local inner = frame.add {
        type = "frame",
        style = "inside_shallow_frame_with_padding",
        direction = "vertical",
    }
    local mode_caption = preview_settings.minimap and { "the-cave-teleport.minimap-zoom" }
        or { "the-cave-teleport.camera-zoom" }
    inner.add { type = "label", caption = { "", mode_caption, " (0.03 - 1.0):" } }
    local zoom = preview_settings.minimap and preview_settings.zoom_minimap
        or preview_settings.zoom_camera
    local field = inner.add {
        type = "textfield",
        name = "the_cave_tp_setting_zoom",
        text = tostring(zoom),
    }
    field.style.width = 100
    field.numeric = true
    field.allow_decimal = true
    inner.add { type = "label", caption = { "the-cave-teleport.view-mode" }, style = "bold_label" }
    local switch_flow = inner.add { type = "flow", direction = "horizontal" }
    switch_flow.style.vertical_align = "center"
    switch_flow.add { type = "label", caption = { "the-cave-teleport.real" } }
    switch_flow.add {
        type = "switch",
        name = "the_cave_tp_setting_minimap",
        switch_state = preview_settings.minimap and "right" or "left",
    }
    switch_flow.add { type = "label", caption = { "the-cave-teleport.minimap" } }
end

local function draw_main(player)
    close_frames(player)
    if unlocked_slots(player) == 0 then
        player.print({ "the-cave-teleport.research-required" })
        return
    end
    local data = root()
    local frame = player.gui.screen.add { type = "frame", name = MAIN_FRAME, direction = "vertical" }
    local title_bar = frame.add { type = "flow", direction = "horizontal" }
    title_bar.drag_target = frame
    title_bar.add { type = "label", caption = { "the-cave-teleport.title" }, style = "frame_title" }
    local filler = title_bar.add { type = "empty-widget", style = "draggable_space_header" }
    filler.style.horizontally_stretchable = true
    filler.style.height = 24
    filler.drag_target = frame
    title_bar.add {
        type = "sprite-button",
        name = "the_cave_tp_open_settings",
        sprite = "utility/notification",
        style = "frame_action_button",
        tooltip = { "the-cave-teleport.settings" },
    }
    title_bar.add {
        type = "sprite-button",
        name = "the_cave_tp_close_main",
        sprite = "utility/close",
        style = "frame_action_button",
    }
    frame.style.width = 550
    frame.auto_center = true
    player.opened = frame

    local add_flow = frame.add { type = "flow", direction = "horizontal" }
    add_flow.style.vertical_align = "center"
    local add_button = add_flow.add {
        type = "button",
        name = "the_cave_tp_add_current_pos",
        caption = { "the-cave-teleport.save-current-position" },
        style = "confirm_button",
    }
    add_button.style.horizontally_stretchable = true
    add_flow.add { type = "label", caption = { "the-cave-teleport.cost", SAVE_COST } }
    add_flow.add {
        type = "sprite",
        sprite = "item/" .. SAVE_ITEM,
        tooltip = { "the-cave-teleport.save-cost-tooltip", SAVE_COST, SAVE_ITEM },
    }

    local filters = frame.add { type = "flow", direction = "vertical" }
    filters.style.margin = { 5, 0, 5, 0 }
    local top_controls = filters.add { type = "table", column_count = 2 }
    top_controls.style.horizontally_stretchable = true
    top_controls.style.bottom_margin = 5
    local all_button = top_controls.add {
        type = "button",
        name = "the_cave_tp_filter_all",
        caption = { "the-cave-teleport.all" },
        style = data.filters[player.index] == nil and "confirm_button" or "button",
    }
    all_button.style.horizontally_stretchable = true
    all_button.style.minimal_width = 260
    local dropdown = top_controls.add {
        type = "drop-down",
        name = "the_cave_tp_sort_dropdown",
        items = {
            { "the-cave-teleport.oldest-first" },
            { "the-cave-teleport.newest-first" },
            { "the-cave-teleport.recently-visited" },
        },
        selected_index = data.sort[player.index] or 1,
    }
    dropdown.style.horizontally_stretchable = true
    dropdown.style.minimal_width = 260

    local surfaces = {}
    local has_platform = false
    for _, point in pairs(data.points[player.index] or {}) do
        local surface = game.surfaces[point.surface_index]
        if surface and surface.valid then
            if surface.platform then has_platform = true else surfaces[point.surface_index] = surface.name end
        end
    end
    local sorted_surfaces = {}
    for index, name in pairs(surfaces) do
        sorted_surfaces[#sorted_surfaces + 1] = { index = index, name = name }
    end
    table.sort(sorted_surfaces, function(a, b) return a.name < b.name end)
    local filter_table = filters.add { type = "table", column_count = 4 }
    filter_table.style.horizontally_stretchable = true
    if has_platform then
        local button = filter_table.add {
            type = "button",
            name = "the_cave_tp_filter_platforms",
            caption = { "", "[img=item/space-platform-starter-pack] ", { "the-cave-teleport.platforms" } },
            style = data.filters[player.index] == "platforms_group" and "confirm_button" or "button",
        }
        button.style.horizontally_stretchable = true
        button.style.minimal_width = 120
    end
    for _, surface_data in ipairs(sorted_surfaces) do
        local button = filter_table.add {
            type = "button",
            name = "the_cave_tp_filter_surf_" .. surface_data.index,
            caption = "[img=" .. surface_icon(game.surfaces[surface_data.index]) .. "] "
                .. capitalize(surface_data.name),
            style = data.filters[player.index] == surface_data.index and "confirm_button" or "button",
        }
        button.style.horizontally_stretchable = true
        button.style.minimal_width = 120
    end

    local search_flow = filters.add { type = "flow", direction = "horizontal" }
    search_flow.style.vertical_align = "center"
    search_flow.style.top_margin = 5
    search_flow.add { type = "label", caption = { "the-cave-teleport.search" } }
    local search = search_flow.add {
        type = "textfield",
        name = "the_cave_tp_search_filter",
        text = data.search[player.index] or "",
    }
    search.style.width = 150
    local last = data.last_positions[player.index]
    local remaining = cooldown_remaining(player)
    local back = search_flow.add {
        type = "button",
        name = "the_cave_tp_go_back",
        caption = remaining > 0 and ("↩ " .. cooldown_caption(remaining))
            or { "", "↩ ", { "the-cave-teleport.back-to" }, " ", last and last.surface_name or "---" },
        enabled = last ~= nil and remaining <= 0,
        style = "tool_button_blue",
    }
    back.style.horizontally_stretchable = true
    back.style.left_margin = 10

    local scroll = frame.add {
        type = "scroll-pane",
        name = SCROLL_NAME,
        vertical_scroll_policy = "always",
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.maximal_height = 500
    refresh_list(player)
end

local function toggle_main(player)
    if not valid_player(player) then return false end
    if unlocked_slots(player) == 0 then
        player.print({ "the-cave-teleport.research-required" })
        return true
    end
    local frame = player.gui.screen[MAIN_FRAME]
    if frame and frame.valid then close_frames(player) else draw_main(player) end
    return true
end

local function update_cooldown_buttons(player)
    local frame = player.gui.screen[MAIN_FRAME]
    if not (frame and frame.valid) then return end
    local data = root()
    local remaining = cooldown_remaining(player)
    local slot_limit = unlocked_slots(player)
    local last = data.last_positions[player.index]
    local function visit(parent)
        for _, element in pairs(parent.children) do
            local destination_index = element.name
                and tonumber(element.name:match("^the_cave_tp_go_(%d+)$"))
            if destination_index then
                local slot_locked = destination_index > slot_limit
                element.caption = slot_locked and { "the-cave-teleport.slot-locked" }
                    or (remaining > 0 and cooldown_caption(remaining)
                    or { "the-cave-teleport.teleport" })
                element.enabled = not slot_locked and remaining <= 0
                element.tooltip = slot_locked
                    and { "the-cave-teleport.slot-locked-tooltip", destination_index }
                    or ""
            elseif element.name == "the_cave_tp_go_back" then
                element.caption = remaining > 0 and ("↩ " .. cooldown_caption(remaining))
                    or { "", "↩ ", { "the-cave-teleport.back-to" }, " ", last and last.surface_name or "---" }
                element.enabled = last ~= nil and remaining <= 0
            end
            visit(element)
        end
    end
    visit(frame)
end

local function update_time_labels(player)
    local frame = player.gui.screen[MAIN_FRAME]
    local scroll = frame and frame[SCROLL_NAME]
    local table_gui = scroll and scroll[TABLE_NAME]
    if not (table_gui and table_gui.valid) then return end
    local points = root().points[player.index] or {}
    local function visit(parent)
        for _, element in pairs(parent.children) do
            local index = element.name and tonumber(element.name:match("^the_cave_tp_time_label_(%d+)$"))
            if index and points[index] then
                element.caption = {
                    "",
                    { "the-cave-teleport.last-visit" },
                    " ",
                    format_time_ago(points[index].last_used),
                }
            end
            visit(element)
        end
    end
    visit(table_gui)
end

local function remove_surface_points(surface_index)
    local data = root()
    for player_index, points in pairs(data.points) do
        for index = #points, 1, -1 do
            if points[index].surface_index == surface_index then table.remove(points, index) end
        end
        if data.filters[player_index] == surface_index then data.filters[player_index] = nil end
    end
    for player_index, last in pairs(data.last_positions) do
        if last.surface_index == surface_index then data.last_positions[player_index] = nil end
    end
end

function teleport.on_init()
    root()
    for _, player in pairs(game.players) do remove_legacy_toggle_button(player) end
end

function teleport.on_configuration_changed()
    root()
    local invalid_surfaces = {}
    for _, points in pairs(root().points) do
        for _, point in pairs(points) do
            if not game.surfaces[point.surface_index] then invalid_surfaces[point.surface_index] = true end
        end
    end
    for surface_index in pairs(invalid_surfaces) do remove_surface_points(surface_index) end
    for _, player in pairs(game.players) do
        close_frames(player)
        remove_legacy_toggle_button(player)
    end
end

function teleport.on_player_created(event)
    remove_legacy_toggle_button(game.get_player(event.player_index))
end

function teleport.on_player_joined_game(event)
    remove_legacy_toggle_button(game.get_player(event.player_index))
end

function teleport.on_player_removed(event)
    local data = root()
    data.points[event.player_index] = nil
    data.filters[event.player_index] = nil
    data.sort[event.player_index] = nil
    data.search[event.player_index] = nil
    data.last_positions[event.player_index] = nil
    data.player_settings[event.player_index] = nil
    data.cooldowns[event.player_index] = nil
end

function teleport.on_surface_deleted(event)
    remove_surface_points(event.surface_index)
end

function teleport.on_custom_input(event)
    toggle_main(game.get_player(event.player_index))
end

function teleport.on_lua_shortcut(event)
    if not event or event.prototype_name ~= SHORTCUT_NAME then return false end
    toggle_main(game.get_player(event.player_index))
    return true
end

function teleport.on_gui_click(event)
    local element = event.element
    if not (element and element.valid) then return false end
    local name = element.name or ""
    if name:sub(1, 12) ~= "the_cave_tp_" then return false end
    local player = game.get_player(event.player_index)
    if not valid_player(player) then return true end
    local data = root()

    if name == TOGGLE_BUTTON then
        return toggle_main(player)
    elseif name == "the_cave_tp_close_main" then
        close_frames(player)
        return true
    elseif name == "the_cave_tp_open_settings" then
        draw_settings(player)
        return true
    elseif name == "the_cave_tp_go_back" then
        local last = data.last_positions[player.index]
        if last then try_teleport(player, last.pos, last.surface_index) end
        return true
    elseif name == "the_cave_tp_add_current_pos" then
        if player.controller_type == defines.controllers.remote then
            player.print({ "the-cave-teleport.cannot-save-map-view" })
            return true
        end
        if not is_valid_save_surface(player.surface) then
            player.print({ "the-cave-teleport.cannot-save-here" })
            return true
        end
        data.points[player.index] = data.points[player.index] or {}
        local points = data.points[player.index]
        local slot_limit = unlocked_slots(player)
        if count_points(points) >= slot_limit then
            if slot_limit >= MAX_POINTS then
                player.print({ "the-cave-teleport.maximum-points" })
            else
                player.print({ "the-cave-teleport.current-slot-limit", slot_limit })
            end
            return true
        end
        if not can_pay(player, SAVE_ITEM, SAVE_COST) then
            player.print({ "the-cave-teleport.not-enough-save-materials" })
            return true
        end
        local same_surface_count = 0
        for _, point in pairs(points) do
            if point.surface_index == player.surface_index then same_surface_count = same_surface_count + 1 end
        end
        local base_name = player.surface.platform and player.surface.platform.name
            or capitalize(player.surface.name)
        table.insert(points, {
            name = base_name .. " " .. (same_surface_count + 1),
            pos = { x = player.position.x, y = player.position.y },
            surface_index = player.surface_index,
            last_used = game.tick,
        })
        if not collect_cost(player, SAVE_ITEM, SAVE_COST) then
            table.remove(points)
            player.print({ "the-cave-teleport.cost-collection-failed" })
            return true
        end
        player.print({ "the-cave-teleport.position-saved" })
        draw_main(player)
        return true
    elseif name == "the_cave_tp_filter_all" then
        data.filters[player.index] = nil
        draw_main(player)
        return true
    elseif name == "the_cave_tp_filter_platforms" then
        data.filters[player.index] = "platforms_group"
        draw_main(player)
        return true
    end

    local surface_index = tonumber(name:match("^the_cave_tp_filter_surf_(%d+)$"))
    if surface_index then
        data.filters[player.index] = surface_index
        draw_main(player)
        return true
    end
    local go_index = tonumber(name:match("^the_cave_tp_go_(%d+)$"))
    if go_index then
        if go_index > unlocked_slots(player) then
            player.print({ "the-cave-teleport.slot-locked-message", go_index })
            return true
        end
        local point = data.points[player.index] and data.points[player.index][go_index]
        if point and try_teleport(player, point.pos, point.surface_index) then point.last_used = game.tick end
        return true
    end
    local delete_index = tonumber(name:match("^the_cave_tp_del_(%d+)$"))
    if delete_index then
        if element.style.name == "red_back_button" then
            element.style = "confirm_button"
            element.caption = { "the-cave-teleport.are-you-sure" }
        elseif data.points[player.index] and data.points[player.index][delete_index] then
            table.remove(data.points[player.index], delete_index)
            refresh_list(player)
        end
        return true
    end
    return true
end

function teleport.on_gui_selection_state_changed(event)
    local element = event.element
    if not (element and element.valid and element.name == "the_cave_tp_sort_dropdown") then return end
    root().sort[event.player_index] = element.selected_index
    local player = game.get_player(event.player_index)
    if player then refresh_list(player) end
end

function teleport.on_gui_switch_state_changed(event)
    local element = event.element
    if not (element and element.valid and element.name == "the_cave_tp_setting_minimap") then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local preview_settings = get_preview_settings(player.index)
    preview_settings.minimap = element.switch_state == "right"
    local settings_frame = player.gui.screen[SETTINGS_FRAME]
    if settings_frame and settings_frame.valid then
        local inner = settings_frame.children[1]
        local field = inner and inner["the_cave_tp_setting_zoom"]
        if field and field.valid then
            field.text = tostring(preview_settings.minimap and preview_settings.zoom_minimap
                or preview_settings.zoom_camera)
        end
    end
    refresh_list(player)
end

function teleport.on_gui_text_changed(event)
    local element = event.element
    if not (element and element.valid) then return end
    local name = element.name or ""
    local player = game.get_player(event.player_index)
    if not player then return end
    if name == "the_cave_tp_search_filter" then
        root().search[player.index] = element.text
        refresh_list(player)
    elseif name == "the_cave_tp_setting_zoom" then
        local value = tonumber(element.text)
        if value and value >= 0.03 and value <= 1 then
            local preview_settings = get_preview_settings(player.index)
            if preview_settings.minimap then
                preview_settings.zoom_minimap = value
            else
                preview_settings.zoom_camera = value
            end
            refresh_list(player)
        end
    else
        local index = tonumber(name:match("^the_cave_tp_rename_(%d+)$"))
        local points = root().points[player.index]
        if index and points and points[index] then points[index].name = element.text end
    end
end

function teleport.on_gui_closed(event)
    local element = event.element
    if not (element and element.valid and element.name == MAIN_FRAME) then return end
    local player = game.get_player(event.player_index)
    if player then close_frames(player) end
end

local function refresh_research_for_force(force)
    if not (force and force.valid) then return end
    for _, player in pairs(force.players) do
        remove_legacy_toggle_button(player)
        local frame = player.gui.screen[MAIN_FRAME]
        if frame and frame.valid then
            if unlocked_slots(player) > 0 then draw_main(player) else close_frames(player) end
        end
    end
end

function teleport.on_research_finished(event)
    local research = event and event.research
    if research and research.name:match("^the%-cave%-teleporter%-%d+$") then
        refresh_research_for_force(research.force)
    end
end

function teleport.on_research_reversed(event)
    local research = event and event.research
    if research and research.name:match("^the%-cave%-teleporter%-%d+$") then
        refresh_research_for_force(research.force)
    end
end

function teleport.on_tick(event)
    if event.tick % 60 ~= 0 then return end
    for _, player in pairs(game.connected_players) do update_cooldown_buttons(player) end
    if event.tick % 300 == 0 then
        for _, player in pairs(game.connected_players) do update_time_labels(player) end
    end
end

return teleport
