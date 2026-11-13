local settings = require("scripts.game_settings").proxy(settings)

local drill_filter = {}

local CONNECTOR = "__tcdf__"
local TOOL_NAME = "the-cave-filter-mining-drills-tool"
local FRAME_NAME = "the-cave-filter-mining-drills-frame"
local PREFIX = "the-cave-drill-filter"
local NONE = "__none__"

local function enabled()
    local setting = settings and settings.startup and settings.startup["the-cave-filter-mining-drills"]
    return setting and setting.value == "enabled"
end

local function split_filtered_name(name)
    if type(name) ~= "string" then return nil, nil end
    local pos = string.find(name, CONNECTOR, 1, true)
    if not pos then return name, nil end
    local base = string.sub(name, 1, pos - 1)
    local resource = string.sub(name, pos + string.len(CONNECTOR))
    if resource == "" then resource = nil end
    return base, resource
end

local function get_entity_prototype(name)
    if not name then return nil end
    local ok, result = pcall(function()
        return prototypes.get_entity_filtered({{filter = "name", name = name}})[name]
    end)
    if ok then return result end
    return nil
end

local function get_resource_prototype(name)
    local proto = get_entity_prototype(name)
    if proto and proto.type == "resource" then return proto end
    return nil
end

local function is_valid_sprite(path)
    if helpers and helpers.is_valid_sprite_path then
        local ok, valid = pcall(helpers.is_valid_sprite_path, path)
        return ok and valid
    end
    return true
end

local function resource_sprite(resource_name)
    local entity_sprite = "entity/" .. resource_name
    if is_valid_sprite(entity_sprite) then return entity_sprite end
    local item_sprite = "item/" .. resource_name
    if is_valid_sprite(item_sprite) then return item_sprite end
    return "utility/missing_icon"
end

local function ensure_storage()
    storage.the_cave_drill_filter = storage.the_cave_drill_filter or {}
    storage.the_cave_drill_filter.players = storage.the_cave_drill_filter.players or {}
    storage.the_cave_drill_filter.resources = storage.the_cave_drill_filter.resources or {}
end

local function refresh_resources()
    ensure_storage()
    local resources = {}
    local ok, protos = pcall(function()
        return prototypes.get_entity_filtered({{filter = "type", type = "resource"}})
    end)
    if ok and protos then
        for resource_name, proto in pairs(protos) do
            if proto.resource_category == resource_name then
                resources[resource_name] = {
                    localised_name = proto.localised_name,
                    sprite = resource_sprite(resource_name),
                }
            end
        end
    end
    storage.the_cave_drill_filter.resources = resources
end

function drill_filter.on_init()
    if not enabled() then return end
    refresh_resources()
end

function drill_filter.on_configuration_changed()
    if not enabled() then
        storage.the_cave_drill_filter = nil
        return
    end
    refresh_resources()
end

local function remove_gui(player)
    if player and player.valid and player.gui and player.gui.screen and player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end
end

drill_filter.remove_gui = remove_gui

local function selected_drills_from_entities(entities)
    local result = {}
    for _, entity in pairs(entities or {}) do
        if entity and entity.valid and entity.type == "mining-drill" then
            result[#result + 1] = entity
        end
    end
    return result
end

local function add_category(set, name)
    if type(name) == "string" and name ~= "" then set[name] = true end
end

local function read_categories(category_table)
    local result = {}
    if type(category_table) ~= "table" then return result end
    for key, value in pairs(category_table) do
        if type(key) == "number" then
            add_category(result, value)
        elseif value then
            add_category(result, key)
        end
    end
    return result
end

local function sorted_resource_names(set)
    local names = {}
    for name in pairs(set or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function draw_filter_icon(entity, resource_name)
    if not (entity and entity.valid and resource_name) then return end
    pcall(function()
        rendering.draw_sprite{
            sprite = "utility/entity_info_dark_background",
            target = entity,
            surface = entity.surface,
            only_in_alt_mode = true,
            x_scale = 0.75,
            y_scale = 0.75,
        }
    end)
    pcall(function()
        rendering.draw_sprite{
            sprite = resource_sprite(resource_name),
            target = entity,
            surface = entity.surface,
            only_in_alt_mode = true,
            x_scale = 0.55,
            y_scale = 0.55,
        }
    end)
end

function drill_filter.on_built(event)
    if not enabled() then return end
    local entity = event and (event.entity or event.created_entity)
    if not (entity and entity.valid and entity.type == "mining-drill") then return end
    local _, resource_name = split_filtered_name(entity.name)
    if resource_name then draw_filter_icon(entity, resource_name) end
end

local function change_entity_filter(entity, resource_name)
    if not (entity and entity.valid and entity.type == "mining-drill") then return end

    local base_name, old_resource = split_filtered_name(entity.name)
    if not base_name then return end

    local new_name
    if resource_name == nil or resource_name == "" or resource_name == NONE then
        if not old_resource then return end
        new_name = base_name
    else
        if old_resource == resource_name then return end
        new_name = base_name .. CONNECTOR .. resource_name
    end

    if not get_entity_prototype(new_name) then return end

    local params = {
        name = new_name,
        position = entity.position,
        force = entity.force,
        direction = entity.direction,
        fast_replace = true,
        spill = false,
        create_build_effect_smoke = false,
    }

    pcall(function()
        if entity.quality then params.quality = entity.quality end
    end)

    local health = entity.health
    local new_entity = entity.surface.create_entity(params)
    if new_entity and new_entity.valid then
        -- Factorio 2.0 LuaEntityPrototype does not expose max_health here.
        -- A newly created entity starts at full health, so use its current health as the safe cap.
        if health then
            pcall(function()
                local cap = new_entity.health or health
                new_entity.health = math.min(health, cap)
            end)
        end
        local _, new_resource = split_filtered_name(new_entity.name)
        if new_resource then draw_filter_icon(new_entity, new_resource) end
    end
end

local function open_gui(player, entities)
    if not (player and player.valid) then return end
    remove_gui(player)
    ensure_storage()

    local drills = selected_drills_from_entities(entities)
    if #drills == 0 then return end
    storage.the_cave_drill_filter.players[player.index] = drills

    local possible = {}
    local current = {}
    local count_filtered = 0

    for _, entity in pairs(drills) do
        if entity.valid then
            local base_name, resource_name = split_filtered_name(entity.name)
            if resource_name then
                current[resource_name] = (current[resource_name] or 0) + 1
                count_filtered = count_filtered + 1
            end
            local proto = get_entity_prototype(base_name)
            if proto and proto.type == "mining-drill" then
                local categories = read_categories(proto.resource_categories)
                for category in pairs(categories) do
                    if storage.the_cave_drill_filter.resources[category] then
                        possible[category] = true
                    end
                end
            end
        end
    end

    local resource_names = sorted_resource_names(possible)
    if #resource_names == 0 then return end

    local frame = player.gui.screen.add{
        type = "frame",
        name = FRAME_NAME,
        direction = "vertical",
        caption = {"the-cave-drill-filter.frame-caption"},
    }
    pcall(function() frame.force_auto_center() end)

    local inner = frame.add{type = "frame", direction = "vertical", style = "inside_deep_frame"}
    inner.style.top_margin = 6
    inner.style.padding = 8

    inner.add{type = "label", caption = {"the-cave-drill-filter.selected-count", tostring(#drills)}}

    local columns = math.max(4, math.ceil(math.sqrt(#resource_names + 1)))
    local table_gui = inner.add{type = "table", name = "resource_table", column_count = columns, style = "slot_table"}
    table_gui.add{
        type = "sprite-button",
        name = PREFIX .. CONNECTOR .. NONE,
        sprite = "utility/missing_icon",
        style = "slot_button",
        number = #drills - count_filtered,
        tooltip = {"the-cave-drill-filter.no-filter"},
    }

    for _, resource_name in pairs(resource_names) do
        local proto = get_resource_prototype(resource_name)
        local tooltip = proto and proto.localised_name or {"entity-name." .. resource_name}
        table_gui.add{
            type = "sprite-button",
            name = PREFIX .. CONNECTOR .. resource_name,
            sprite = resource_sprite(resource_name),
            style = "slot_button",
            number = current[resource_name] or 0,
            tooltip = tooltip,
        }
    end

    local buttons = frame.add{type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow"}
    buttons.drag_target = frame
    local spacer = buttons.add{type = "empty-widget", style = "draggable_space"}
    spacer.style.horizontally_stretchable = true
    spacer.style.vertically_stretchable = true
    spacer.drag_target = frame
    buttons.add{type = "button", name = PREFIX .. CONNECTOR .. "close", caption = {"gui.close"}, style = "back_button"}
end

function drill_filter.on_player_selected_area(event)
    if not enabled() then return end
    if not event or event.item ~= TOOL_NAME then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    open_gui(player, event.entities)
end

function drill_filter.on_gui_click(event)
    if not enabled() then return end
    local element = event and event.element
    if not (element and element.valid and element.name) then return end
    local name = element.name
    if string.sub(name, 1, string.len(PREFIX .. CONNECTOR)) ~= PREFIX .. CONNECTOR then return end

    local player = game.get_player(event.player_index)
    if not player then return end
    local selected = string.sub(name, string.len(PREFIX .. CONNECTOR) + 1)
    if selected == "close" then
        remove_gui(player)
        return
    end

    ensure_storage()
    local drills = storage.the_cave_drill_filter.players[player.index] or {}
    local resource_name = selected
    if selected == NONE then resource_name = nil end

    for _, entity in pairs(drills) do
        if entity and entity.valid then
            change_entity_filter(entity, resource_name)
        end
    end
    storage.the_cave_drill_filter.players[player.index] = nil
    remove_gui(player)
end

function drill_filter.on_gui_closed(event)
    if not enabled() then return end
    local player = game.get_player(event.player_index)
    if player then remove_gui(player) end
end

return drill_filter
