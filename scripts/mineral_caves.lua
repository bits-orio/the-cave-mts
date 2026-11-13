local physical = require("scripts.player_physical")
local child_state = require("scripts.cave_child_state")
local cave_boxes = require("scripts.cave_item_boxes")
local cave_timing = require("scripts.cave_operation_time")
local settings = require("scripts.game_settings").proxy(settings)

-- Timed Iron, Copper and Coal Mineral Caves for The Cave.
--
-- Design:
--   * ordinary empty Medium+ cavern rooms have an independent 20% conversion
--     chance plus a five-miss anti-drought guarantee, leaving the existing
--     Uranium Cave roll and special-room odds intact
--   * each entrance permanently owns one resource selected from a deterministic
--     per-Force 5 Iron / 3 Copper / 2 Coal deck
--   * the lower cave is unbounded; at most ten large rooms are generated, while
--     manual tunnels and very rich single-resource veins can continue indefinitely
--   * cave interiors are dry and pitch black, with fixed Blue Belt item transfer
--     and direct cross-surface electric transfer; no fluid ports are created
--   * both upper Underground Belt endpoints, the power pole and information
--     panel are created atomically with the discovered entrance, before entry
--   * the first entry starts the shared stability timer; entry and exit stay open
--     until 00:00, then remaining players die and the entrance seals permanently

local hash = require("scripts.lib.hash")
local Simplex = require("scripts.lib.simplex")
local world = require("scripts.world")
local cave_placement = require("scripts.cave_placement")
local depth_levels = require("scripts.depth_levels")

local mineral_caves = {}
mineral_caves.scheduled = require("scripts.advancing_caves")

local SURFACE_PREFIX = "the-cave-mineral-cave-"
local MINERAL_PARENT_MIN_DISTANCE = 192
local ENTRANCE_NAMES = {
    ["the-cave-mineral-cave-entrance-1"] = true,
    ["the-cave-mineral-cave-entrance-2"] = true,
}
local EXIT_NAMES = {
    ["the-cave-mineral-cave-exit-1"] = true,
    ["the-cave-mineral-cave-exit-2"] = true,
}

local ITEM_DOWN_INPUT = "the-cave-mineral-item-down-input"
local ITEM_DOWN_OUTPUT = "the-cave-mineral-item-down-output"
local ITEM_UP_INPUT = "the-cave-mineral-item-up-input"
local ITEM_UP_OUTPUT = "the-cave-mineral-item-up-output"
local POWER_INPUT = "the-cave-mineral-power-input"
local POWER_OUTPUT = "the-cave-mineral-power-output"
local POWER_CONNECTOR = "the-cave-mineral-power-connector"
local LOWER_LAMP = "small-lamp"
local INFO_PANEL = "display-panel"

local TRANSFER_ENTITY_NAMES = {
    ITEM_DOWN_INPUT,
    ITEM_DOWN_OUTPUT,
    ITEM_UP_INPUT,
    ITEM_UP_OUTPUT,
    "big-electric-pole",
    LOWER_LAMP,
    POWER_CONNECTOR,
    POWER_INPUT,
    POWER_OUTPUT,
    INFO_PANEL,
}

local MINERAL_ROOM_LABEL = "the-cave-runtime.room-mineral-cave"
local START_CHAMBER_RADIUS = 12
local LOWER_CAVE_ORIGIN = { x = 0, y = 0 }
local DEBUG_TEST_ROOM_COUNT = 10
local EXHAUSTION_GRACE_TICKS = 5 * 60 * 60
-- Legacy fallback only; first entry uses the shared one-hour duration.
local CAVE_OPERATION_TICKS = 30 * 60 * 60
local TIMER_UPDATE_INTERVAL = 60
local POWER_BRIDGE_VERSION = 3
local TRANSFER_LAYOUT_VERSION = cave_boxes.layout_version
local UPPER_PORT_LAYOUT_VERSION = 2
local PORTAL_LABEL_LAYOUT_VERSION = 1
local EXTRACTION_VOID_HALO_VERSION = 1

local VARIANT_STREAM = 732
local SEED_STREAM = 733
local VEIN_STREAM = 8500
local DECK_STREAM = 8600

local MINERAL_VEIN_PLAN_VERSION = 1
local TENDRIL_SCALE = 1 / 40
local MINERAL_VEIN_WIDTH = 0.34
local MINERAL_VEIN_MIN_DISTANCE = START_CHAMBER_RADIUS + 4

-- Roughly eight times the current mixed-patch per-tile richness. The broad
-- double-noise field makes these caves a timed jackpot without creating every
-- resource tile in advance or placing any finite cave-wide budget in storage.
local MINERAL_TILE_AMOUNT_BY_ZONE = {
    medium = { min = 5000, max = 7000 },
    hard = { min = 7000, max = 10000 },
    nightmare = { min = 10000, max = 16000 },
}

local RESOURCE_DECK_BASE = {
    "iron", "iron", "iron", "iron", "iron",
    "copper", "copper", "copper",
    "coal", "coal",
}
local RESOURCE_DECK_FALLBACK = {
    "iron", "copper", "iron", "coal", "iron",
    "copper", "iron", "coal", "copper", "iron",
}
local RESOURCE_SETTING_BY_KEY = {
    iron = "the-cave-iron-cave",
    copper = "the-cave-copper-cave",
    coal = "the-cave-coal-cave",
}
local RESOURCE_KEY_ORDER = { "iron", "copper", "coal" }
local ALL_RESOURCE_SIGNATURE = "iron,copper,coal"
local RESOURCE_NAMES = {
    iron = "iron-ore",
    copper = "copper-ore",
    coal = "coal",
}
local RESOURCE_COLOURS = {
    iron = { r = 0.45, g = 0.72, b = 0.88 },
    copper = { r = 0.92, g = 0.42, b = 0.16 },
    coal = { r = 0.38, g = 0.38, b = 0.38 },
}

local function resource_enabled(resource_key)
    local setting_name = RESOURCE_SETTING_BY_KEY[resource_key]
    if not setting_name then return false end
    local setting = settings and settings.startup and settings.startup[setting_name]
    return not setting or setting.value == "enabled" or setting.value == true
end

local function enabled()
    for _, resource_key in ipairs(RESOURCE_KEY_ORDER) do
        if resource_enabled(resource_key) then return true end
    end
    return false
end

local function enabled_resource_signature()
    local keys = {}
    for _, resource_key in ipairs(RESOURCE_KEY_ORDER) do
        if resource_enabled(resource_key) then keys[#keys + 1] = resource_key end
    end
    return table.concat(keys, ",")
end

local function filter_enabled_resources(source)
    local result = {}
    for _, resource_key in ipairs(source) do
        if resource_enabled(resource_key) then result[#result + 1] = resource_key end
    end
    return result
end

local function root()
    storage.the_cave_mineral_caves = storage.the_cave_mineral_caves or {}
    local r = storage.the_cave_mineral_caves
    r.next_id = r.next_id or 1
    r.by_id = r.by_id or {}
    r.by_surface = r.by_surface or {}
    r.by_entity = r.by_entity or {}
    r.entrances_by_parent = r.entrances_by_parent or {}
    r.flashlight_state = r.flashlight_state or {}
    r.pending_respawns = r.pending_respawns or {}
    r.resource_decks = r.resource_decks or {}
    return r
end

local function resource_localised(resource_key)
    return { "the-cave-mineral-caves.resource-" .. tostring(resource_key or "iron") }
end

local function valid_resource_key(resource_key)
    return RESOURCE_NAMES[resource_key] and resource_key or nil
end

local function deck_is_balanced(deck)
    local distinct = {}
    for _, resource_key in ipairs(deck) do distinct[resource_key] = true end
    local distinct_count = 0
    for _ in pairs(distinct) do distinct_count = distinct_count + 1 end
    if distinct_count <= 1 then return true end

    for i = 2, #deck do
        if deck[i] == "coal" and deck[i - 1] == "coal" then return false end
    end
    for i = 3, #deck do
        if deck[i] == deck[i - 1] and deck[i] == deck[i - 2] then return false end
    end
    return true
end

local function build_resource_deck(seed, force_index, cycle)
    local source = filter_enabled_resources(RESOURCE_DECK_BASE)
    if #source == 0 then return {} end
    local fallback = filter_enabled_resources(RESOURCE_DECK_FALLBACK)
    for attempt = 1, 64 do
        local deck = {}
        for i, key in ipairs(source) do deck[i] = key end
        for i = #deck, 2, -1 do
            local j = hash.range(seed, force_index, cycle,
                DECK_STREAM + attempt * 32 + i, 1, i)
            deck[i], deck[j] = deck[j], deck[i]
        end
        if deck_is_balanced(deck) then return deck end
    end
    return fallback
end

local function resource_deck_state(surface, force)
    local r = root()
    local force_index = force.index
    local state = r.resource_decks[force_index]
    if not state then
        state = { cycle = 1, index = 1 }
        r.resource_decks[force_index] = state
    end
    local signature = enabled_resource_signature()
    if state.resource_signature == nil and signature == ALL_RESOURCE_SIGNATURE then
        -- Preserve an in-progress 3.1.73 deck when all three new switches keep
        -- their default Enabled value.
        state.resource_signature = signature
    elseif state.resource_signature ~= signature then
        -- A changed set must never retain disabled cards from a saved deck.
        state.resource_signature = signature
        state.deck = nil
        state.index = 1
    end
    if signature == "" then
        state.deck = {}
        state.index = 1
        return state
    end
    if not state.deck or state.index > #state.deck then
        local seed = surface.map_gen_settings.seed or 0
        state.deck = build_resource_deck(seed, force_index, state.cycle)
        state.index = 1
        if #state.deck > 0 then state.cycle = state.cycle + 1 end
    end
    return state
end

local function peek_next_resource_key(surface, force)
    local state = resource_deck_state(surface, force)
    return state.deck and state.deck[state.index] or nil
end

local function next_resource_key(surface, force)
    local state = resource_deck_state(surface, force)
    local key = state.deck and state.deck[state.index] or nil
    if not key then return nil end
    state.index = state.index + 1
    return key
end

local function consume_specific_resource_key(surface, force, resource_key)
    local wanted = valid_resource_key(resource_key)
    if not wanted then return nil end
    local state = resource_deck_state(surface, force)
    for i = state.index, #state.deck do
        if state.deck[i] == wanted then
            table.remove(state.deck, i)
            return wanted
        end
    end
    return nil
end

-- Cavern selection must know the next resource before it applies same-type
-- spacing. Peeking never consumes the Force's deterministic 5/3/2 deck; only a
-- successfully created natural entrance advances it.
function mineral_caves.peek_next_resource_key(surface, force)
    if not (surface and surface.valid and force and force.valid) then return nil end
    return peek_next_resource_key(surface, force)
end

function mineral_caves.is_resource_enabled(resource_key)
    return resource_enabled(resource_key)
end

local function copy_position(position)
    return { x = position.x, y = position.y }
end

local function surface_has_prefix(surface, prefix)
    return surface
        and surface.valid
        and type(surface.name) == "string"
        and surface.name:sub(1, #prefix) == prefix
end

function mineral_caves.is_mineral_cave_surface(surface)
    return surface_has_prefix(surface, SURFACE_PREFIX)
end

local function valid_surface(index)
    local surface = index and game.surfaces[index]
    return surface and surface.valid and surface or nil
end

local function add_parent_record(r, parent_surface_index, cave_id)
    local list = r.entrances_by_parent[parent_surface_index]
    if not list then
        list = {}
        r.entrances_by_parent[parent_surface_index] = list
    end
    list[#list + 1] = cave_id
end

local function remove_value(list, wanted)
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == wanted then table.remove(list, i) end
    end
end

local function record_for_surface(surface)
    if not (surface and surface.valid) then return nil end
    local id = root().by_surface[surface.index]
    return id and root().by_id[id] or nil
end

function mineral_caves.zone_id_for_surface(surface)
    local record = record_for_surface(surface)
    return record and record.zone_id or nil
end

-- Natural generation uses this read-only query to enforce the 192-tile rule
-- only between entrances carrying the same resource. Different Mineral types
-- and Uranium are deliberately allowed beside one another. Closed caves remain
-- registered because their sealed mouths stay visible forever.
function mineral_caves.has_parent_entrance_within(surface, position, radius, resource_key)
    if not (surface and surface.valid and position) then return false end
    local wanted_resource = valid_resource_key(resource_key)
    local radius_squared = (tonumber(radius) or 0) ^ 2
    for _, id in ipairs(root().entrances_by_parent[surface.index] or {}) do
        local record = root().by_id[id]
        local entrance = record and record.entrance_position
        if entrance and (not wanted_resource or record.resource_key == wanted_resource) then
            local dx, dy = entrance.x - position.x, entrance.y - position.y
            if dx * dx + dy * dy < radius_squared then return true end
        end
    end
    return false
end

local function first_placeable_resource(deck, first_index, surface, force, position, radius)
    local checked = {}
    for i = first_index, #deck do
        local resource_key = deck[i]
        if not checked[resource_key] then
            checked[resource_key] = true
            if not mineral_caves.has_parent_entrance_within(
                surface, position, radius, resource_key
            ) then
                return resource_key
            end
        end
    end
    return nil
end

-- Return the first still-unconsumed deck resource that is legal at this exact
-- planned entrance centre. If only spacing-blocked entries remain in the
-- current cycle, rotate to a fresh balanced cycle without consuming a card
-- until the entrance is actually created.
function mineral_caves.peek_placeable_resource_key(surface, force, position, radius)
    if not (surface and surface.valid and force and force.valid and position) then return nil end
    local state = resource_deck_state(surface, force)
    local resource_key = first_placeable_resource(
        state.deck, state.index, surface, force, position, radius)
    if resource_key then return resource_key end

    local seed = surface.map_gen_settings.seed or 0
    local next_deck = build_resource_deck(seed, force.index, state.cycle)
    resource_key = first_placeable_resource(next_deck, 1, surface, force, position, radius)
    if resource_key then
        -- The old tail contains no legal resource at this location. Retire that
        -- blocked tail and commit the fresh deck, but consume nothing until the
        -- actual entrance and all of its fixed hardware have been created.
        state.deck = next_deck
        state.index = 1
        state.cycle = state.cycle + 1
    end
    return resource_key
end

local function find_unit(surface_index, unit_number, names)
    local surface = valid_surface(surface_index)
    if not (surface and unit_number) then return nil end
    local filter = { name = names }
    for _, entity in pairs(surface.find_entities_filtered(filter)) do
        if entity.valid and entity.unit_number == unit_number then return entity end
    end
    return nil
end

local function destroy_unit(surface_index, unit_number, names)
    local entity = find_unit(surface_index, unit_number, names)
    if entity and entity.valid then entity.destroy() end
end

local function record_for_entity(entity)
    if not (entity and entity.valid and entity.unit_number) then return nil end
    local r = root()
    local id = r.by_entity[entity.unit_number]
    if id then return r.by_id[id] end
    for cave_id, record in pairs(r.by_id) do
        if record.entrance_unit_number == entity.unit_number
            or record.exit_unit_number == entity.unit_number then
            r.by_entity[entity.unit_number] = cave_id
            return record
        end
    end
    return nil
end

local function zone_for_position(position)
    local level = depth_levels.level_for_position(position)
    return level and level.id or "easy"
end

local function zone_localised(zone_id)
    return { "the-cave-runtime.depth-" .. tostring(zone_id or "medium") }
end

local function operation_duration_ticks(record)
    if record.timer_started_tick then
        if record.time_limit_close_tick then
            return record.time_limit_close_tick - record.timer_started_tick
        end
        return record.operation_duration_ticks or CAVE_OPERATION_TICKS
    end
    return cave_timing.duration(CAVE_OPERATION_TICKS)
end

local function normalize_record(record)
    record.status = record.status or "active"
    record.room_count = record.room_count or 0
    record.zone_id = record.zone_id or zone_for_position(record.entrance_position or { x = 0, y = 0 })
    if record.zone_id == "easy" then record.zone_id = "medium" end
    record.resource_key = valid_resource_key(record.resource_key) or "iron"
    record.resource_name = RESOURCE_NAMES[record.resource_key]
    -- Records created before this version retain their exact upper endpoint
    -- positions and rotations. Only newly discovered entrances use layout 2.
    record.upper_port_layout_version = tonumber(record.upper_port_layout_version) or 1
    record.mineral_plan_version = tonumber(record.mineral_plan_version) or 0
    -- Since 2.7.111 every open Mineral Q owns its upper infrastructure from
    -- discovery time. Keeping this stored flag true also migrates entrances
    -- discovered by older builds without requiring a first trip below.
    record.transfer_activated = record.status ~= "closed"
    record.transfer_directions = record.transfer_directions or { upper = {}, lower = {} }
    record.transfer_directions.upper = record.transfer_directions.upper or {}
    record.transfer_directions.lower = record.transfer_directions.lower or {}
    if record.timer_started_tick and not record.time_limit_close_tick then
        record.time_limit_close_tick = record.timer_started_tick + operation_duration_ticks(record)
    end
end

local function rebuild_indexes()
    local r = root()
    r.by_surface = {}
    r.by_entity = {}
    r.entrances_by_parent = {}
    for id, record in pairs(r.by_id) do
        record.id = record.id or id
        normalize_record(record)
        if record.parent_surface_index then add_parent_record(r, record.parent_surface_index, id) end
        if record.mineral_cave_surface_index and valid_surface(record.mineral_cave_surface_index) then
            r.by_surface[record.mineral_cave_surface_index] = id
        else
            record.mineral_cave_surface_index = nil
            record.exit_unit_number = nil
            record.exit_position = nil
            record.exit_label_id = nil
            record.lower_timer_id = nil
            record.lower_transfer = nil
        end
        if record.entrance_unit_number then r.by_entity[record.entrance_unit_number] = id end
        if record.exit_unit_number then r.by_entity[record.exit_unit_number] = id end
    end
end

local function render_object(id)
    if not id then return nil end
    local ok, obj = pcall(rendering.get_object_by_id, id)
    return ok and obj or nil
end

local function destroy_render_ids(ids)
    for _, id in pairs(ids or {}) do
        local obj = render_object(id)
        if obj then pcall(function() obj.destroy() end) end
    end
end

local function cleanup_legacy_closed_labels()
    for _, object in pairs(rendering.get_all_objects("the-cave")) do
        if object.valid and object.type == "text" then
            local ok, text = pcall(function() return object.text end)
            if ok and type(text) == "table"
                and text[1] == "the-cave-mineral-caves.label-sealed-resource" then
                pcall(function() object.destroy() end)
            end
        end
    end
end

local function draw_label(surface, position, text, color, scale)
    local obj = rendering.draw_text {
        text = text,
        surface = surface,
        target = position,
        color = color or { r = 1, g = 1, b = 1 },
        alignment = "center",
        vertical_alignment = "middle",
        scale = scale or 1.15,
        only_in_alt_mode = false,
        use_rich_text = true,
    }
    return obj and obj.id or nil
end

local function countdown_remaining_ticks(record, tick)
    tick = tick or game.tick
    if not record or record.status == "closed" then return 0 end
    local deadline = record.status == "exhausted" and record.close_tick or record.time_limit_close_tick
    if not deadline then return operation_duration_ticks(record) end
    return math.max(0, deadline - tick)
end

local function format_countdown(record, tick)
    local seconds = math.ceil(countdown_remaining_ticks(record, tick) / 60)
    local minutes = math.floor(seconds / 60)
    return string.format("%02d:%02d", minutes, seconds % 60)
end

local function countdown_color(record, tick)
    local remaining = countdown_remaining_ticks(record, tick)
    if remaining <= EXHAUSTION_GRACE_TICKS then return { r = 1, g = 0.18, b = 0.08 } end
    if not record.timer_started_tick then return { r = 1, g = 0.88, b = 0.2 } end
    return { r = 0.35, g = 1, b = 0.45 }
end

local function ensure_countdown_label(record, upper, tick)
    if not record or record.status == "closed" then return nil end
    local surface = valid_surface(upper and record.parent_surface_index or record.mineral_cave_surface_index)
    local center = upper and record.entrance_position or record.exit_position
    if not (surface and center) then return nil end

    local field = upper and "upper_timer_id" or "lower_timer_id"
    local object = render_object(record[field])
    if not object then
        record[field] = draw_label(surface, { x = center.x, y = center.y - 2.15 },
            format_countdown(record, tick), countdown_color(record, tick), 1.10)
        object = render_object(record[field])
    end
    if object then
        pcall(function() object.text = format_countdown(record, tick) end)
        pcall(function() object.color = countdown_color(record, tick) end)
    end
    return record[field]
end

local function update_countdown_labels(record, tick)
    ensure_countdown_label(record, true, tick)
    if record.mineral_cave_surface_index and record.exit_position then
        ensure_countdown_label(record, false, tick)
    end
end

local function start_operation_timer(record)
    if not record or record.status ~= "active" then return false end
    if record.timer_started_tick then
        update_countdown_labels(record, game.tick)
        return false
    end
    record.operation_duration_ticks = operation_duration_ticks(record)
    record.timer_started_tick = game.tick
    record.time_limit_close_tick = game.tick + record.operation_duration_ticks
    record.time_warning_sent = false
    update_countdown_labels(record, game.tick)
    local force = game.forces[record.owner_force_index]
    if force and force.valid then force.print({ "the-cave-mineral-caves.timer-started", operation_duration_ticks(record) / (60 * 60) }) end
    return true
end

local function entrance_variant(seed, position)
    if hash.roll(seed, math.floor(position.x), math.floor(position.y), VARIANT_STREAM) < 0.5 then
        return "the-cave-mineral-cave-entrance-1"
    end
    return "the-cave-mineral-cave-entrance-2"
end

local function matching_exit_name(record)
    if record and record.entrance_name == "the-cave-mineral-cave-entrance-2" then
        return "the-cave-mineral-cave-exit-2"
    end
    return "the-cave-mineral-cave-exit-1"
end

local function clear_fixed_entity_site(surface, position, protected_units)
    local tx, ty = math.floor(position.x), math.floor(position.y)
    world.carve_safe_tile(surface, tx, ty)
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { position.x - 0.45, position.y - 0.45 }, { position.x + 0.45, position.y + 0.45 } },
    }) do
        local protected = entity.valid and entity.unit_number and protected_units
            and protected_units[entity.unit_number] == true
        if entity.valid and not protected and entity.type ~= "character" and entity.name ~= "character" then
            entity.destroy()
        end
    end
end

local function clear_portal_site(surface, position)
    local cx, cy = math.floor(position.x), math.floor(position.y)
    for x = cx - 3, cx + 3 do
        for y = cy - 2, cy + 2 do
            world.carve_safe_tile(surface, x, y)
        end
    end
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { position.x - 2.25, position.y - 1.65 }, { position.x + 2.25, position.y + 1.65 } },
    }) do
        if entity.valid and entity.type ~= "character" and entity.name ~= "character" then
            entity.destroy()
        end
    end
end

local function create_fixed_entity(surface, name, position, force, direction, skip_site_clear)
    if not skip_site_clear then clear_fixed_entity_site(surface, position) end
    local params = {
        name = name,
        position = position,
        force = force,
        create_build_effect_smoke = false,
    }
    if direction then params.direction = direction end
    local ok, entity = pcall(function() return surface.create_entity(params) end)
    if not ok or not (entity and entity.valid) then return nil end
    entity.destructible = false
    entity.minable_flag = false
    return entity
end


local function create_hidden_entity(surface, name, position, force)
    local ok, entity = pcall(function()
        return surface.create_entity {
            name = name,
            position = position,
            force = force,
            create_build_effect_smoke = false,
        }
    end)
    if not ok or not (entity and entity.valid) then return nil end
    entity.destructible = false
    entity.minable_flag = false
    return entity
end

local function entity_unit(entity)
    return entity and entity.valid and entity.unit_number or nil
end

local function mineral_info_panel_text(record)
    local resource_name = string.upper(tostring(record and record.resource_key or "iron"))
    return table.concat({
        resource_name .. " MINERAL CAVE INFORMATION",
        "ENTER/EXIT: Click entrance/exit.",
        "INPUT: surface->cave; OUTPUT: cave->surface.",
        "TIME: Shared " .. (operation_duration_ticks(record) / (60 * 60)) .. " min from first entry; keeps running outside. See pole countdowns.",
        "Dark: bring power, lamps and supplies.",
        "Rich " .. resource_name .. " veins; dig tunnels to explore.",
        "No fluid ports or acid are required.",
        "FINAL 5 MIN: Both portals stay open.",
        "00:00: Players inside die; entrance seals permanently.",
    }, "\n")
end

local function setup_info_panel(panel, record)
    if not (panel and panel.valid) then return end
    pcall(function() panel.operable = false end)
    pcall(function() panel.display_panel_icon = { type = "item", name = record.resource_name } end)
    pcall(function() panel.display_panel_text = mineral_info_panel_text(record) end)
    pcall(function() panel.display_panel_always_show = true end)
    pcall(function() panel.display_panel_show_in_chart = true end)
end

local function ensure_upper_info_panel(record)
    if not record then return false end
    local group = record.upper_transfer
    local surface = valid_surface(record.parent_surface_index)
    local center = record.entrance_position
    if not (group and surface and center) then return false end

    local panel = find_unit(surface.index, group.info_panel, INFO_PANEL)
    local panel_position = { x = center.x - 2, y = center.y - 5 }
    if not (panel and panel.valid) then
        local pole = find_unit(surface.index, group.pole, "big-electric-pole")
        local protected = pole and pole.valid and pole.unit_number and { [pole.unit_number] = true } or nil
        clear_fixed_entity_site(surface, panel_position, protected)
        local force = game.forces[record.owner_force_index] or game.forces.player
        panel = create_fixed_entity(surface, INFO_PANEL, panel_position, force, nil, true)
        if not (panel and panel.valid and panel.unit_number) then return false end
        group.info_panel = panel.unit_number
    elseif math.abs(panel.position.x - panel_position.x) > 0.1 or math.abs(panel.position.y - panel_position.y) > 0.1 then
        local ok, moved = pcall(function() return panel.teleport(panel_position) end)
        if not ok or moved == false then return false end
    end

    setup_info_panel(panel, record)
    group.info_panel = panel.unit_number
    return true
end

local function ensure_upper_indicator_lamp(record)
    if not record then return nil end
    local group = record.upper_transfer
    local surface = valid_surface(record.parent_surface_index)
    local center = record.entrance_position
    if not (group and surface and center) then return nil end
    local pole = find_unit(surface.index, group.pole, "big-electric-pole")
    if not pole then return nil end
    local lamp = find_unit(surface.index, group.indicator_lamp, LOWER_LAMP)
    local target = { x = center.x + 1, y = center.y - 5 }
    if not lamp then
        local protected = { [pole.unit_number] = true }
        if group.info_panel then protected[group.info_panel] = true end
        clear_fixed_entity_site(surface, target, protected)
        local force = game.forces[record.owner_force_index] or game.forces.player
        lamp = create_fixed_entity(surface, LOWER_LAMP, target, force, nil, true)
        group.indicator_lamp = lamp and lamp.unit_number or nil
    elseif math.abs(lamp.position.x - target.x) > 0.1 or math.abs(lamp.position.y - target.y) > 0.1 then
        pcall(function() lamp.teleport(target) end)
    end
    if lamp then
        pcall(function() lamp.operable = false end)
        pcall(function() lamp.always_on = true end)
    end
    return lamp
end


local function mineral_tile_amount_range(record)
    return MINERAL_TILE_AMOUNT_BY_ZONE[record.zone_id] or MINERAL_TILE_AMOUNT_BY_ZONE.medium
end

local function child_origin(record)
    if record and record.lower_origin then return record.lower_origin end
    if record and record.exit_position then return record.exit_position end
    return LOWER_CAVE_ORIGIN
end

-- Mineral Caves are intentionally unbounded, so every coordinate is valid.
function mineral_caves.is_position_within_bounds(surface, x, y, include_boundary)
    return true
end
local function mineral_tile_available(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    local name = tile.name or ""
    if name == "out-of-map" or name:find("water", 1, true) then return false end
    local resources = surface.find_entities_filtered {
        type = "resource",
        area = { { x, y }, { x + 1, y + 1 } },
    }
    return not resources or #resources == 0
end

local function cave_tile_is_exposed(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    local name = tile.name or ""
    if name == "out-of-map" or name:find("water", 1, true) then return false end
    local covers = surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-rubble", "diggy-tree" },
        area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
    }
    return not covers or #covers == 0
end

-- Materialize the cave's one selected resource as a broad deterministic field.
-- Two offset low-frequency noise bands overlap, so roughly most mineable floor
-- becomes ore while natural-looking paths remain available for belts and poles.
function mineral_caves.materialize_mineral(surface, x, y, force)
    if not (surface and surface.valid and mineral_caves.is_mineral_cave_surface(surface)) then return false end
    local record = record_for_surface(surface)
    if not (record and record.status == "active") then return false end
    if not (record.resource_name and prototypes.entity and prototypes.entity[record.resource_name]) then return false end

    x, y = math.floor(x), math.floor(y)
    if not mineral_tile_available(surface, x, y) then return false end

    local origin = child_origin(record)
    local dx, dy = (x + 0.5) - origin.x, (y + 0.5) - origin.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= MINERAL_VEIN_MIN_DISTANCE then return false end

    local seed = record.seed or surface.map_gen_settings.seed or 0
    local nx, ny = (x + 0.5) * TENDRIL_SCALE, (y + 0.5) * TENDRIL_SCALE
    local noise_a = math.abs(Simplex.d2(nx, ny, seed + 1100))
    local noise_b = math.abs(Simplex.d2(nx + 17.25, ny - 9.75, seed + 2200))
    if math.min(noise_a, noise_b) >= MINERAL_VEIN_WIDTH then return false end

    local amount_range = mineral_tile_amount_range(record)
    local amount = hash.range(seed, x, y, VEIN_STREAM + 21, amount_range.min, amount_range.max)
    local entity = surface.create_entity {
        name = record.resource_name,
        position = { x = x + 0.5, y = y + 0.5 },
        amount = amount,
    }
    if not (entity and entity.valid) then return false end

    record.mineral_plan_version = MINERAL_VEIN_PLAN_VERSION
    if force and force.valid and not record.resource_announced then
        record.resource_announced = true
        force.print({ "the-cave-mineral-caves.resource-discovered", resource_localised(record.resource_key) })
    end
    return true
end

local function uses_new_upper_layout(record)
    return (tonumber(record and record.upper_port_layout_version) or 1)
        >= UPPER_PORT_LAYOUT_VERSION
end

local function make_transfer_labels(surface, center, upper, record)
    local right = cave_boxes.position(center, record.entrance_name, true)
    local left = cave_boxes.position(center, record.entrance_name, false)
    return {
        draw_label(surface, { x = right.x, y = right.y - 1.4 },
            { "the-cave-mineral-caves.label-input-down" }, { r = 0.25, g = 0.85, b = 1 }, 0.9),
        draw_label(surface, { x = left.x, y = left.y - 1.4 },
            { "the-cave-mineral-caves.label-output-up" }, { r = 0.35, g = 1, b = 0.45 }, 0.9),
    }
end

local function render_ids_valid(ids, expected_count)
    if type(ids) ~= "table" or #ids ~= expected_count then return false end
    for _, id in ipairs(ids) do
        if not render_object(id) then return false end
    end
    return true
end

local function ensure_portal_label(record, upper)
    if not record then return nil end
    local surface = valid_surface(upper and record.parent_surface_index or record.mineral_cave_surface_index)
    local position = upper and record.entrance_position or record.exit_position
    if not (surface and position) then return nil end

    local field = upper and "entrance_label_id" or "exit_label_id"
    local timer_field = upper and "upper_timer_id" or "lower_timer_id"
    local version_field = upper and "upper_portal_label_layout_version"
        or "lower_portal_label_layout_version"
    if record[version_field] ~= PORTAL_LABEL_LAYOUT_VERSION then
        destroy_render_ids({ record[field], record[timer_field] })
        record[field] = nil
        record[timer_field] = nil
        record[version_field] = PORTAL_LABEL_LAYOUT_VERSION
    end
    local existing = render_object(record[field])
    if existing then return record[field] end

    local text = upper and { "the-cave-mineral-caves.entrance-name-resource",
        resource_localised(record.resource_key) } or { "the-cave-mineral-caves.return-label" }
    local color = upper and (RESOURCE_COLOURS[record.resource_key]
        or { r = 1, g = 0.88, b = 0.2 }) or { r = 0.25, g = 0.85, b = 1 }
    record[field] = draw_label(surface, { x = position.x, y = position.y - 3.4 },
        text, color, upper and 1.25 or 1.2)
    return record[field]
end

local function destroy_created_entities(entities)
    for _, entity in pairs(entities or {}) do
        if entity and entity.valid then entity.destroy() end
    end
end

local TRANSFER_DIRECTION_FIELDS = {
    upper = {
        { "item_down_input", ITEM_DOWN_INPUT },
        { "item_up_output", ITEM_UP_OUTPUT },
    },
    lower = {
        { "item_down_output", ITEM_DOWN_OUTPUT },
        { "item_up_input", ITEM_UP_INPUT },
    },
}

local function transfer_direction_store(record, upper)
    normalize_record(record)
    return upper and record.transfer_directions.upper or record.transfer_directions.lower
end

local function capture_transfer_directions(record, upper)
    if not record then return end
    local group = upper and record.upper_transfer or record.lower_transfer
    if not group then return end
    local surface_index = upper and record.parent_surface_index or record.mineral_cave_surface_index
    local store = transfer_direction_store(record, upper)
    local fields = upper and TRANSFER_DIRECTION_FIELDS.upper or TRANSFER_DIRECTION_FIELDS.lower
    for _, def in ipairs(fields) do
        local entity = find_unit(surface_index, group[def[1]], def[2])
        if entity and entity.valid then store[def[1]] = entity.direction end
    end
end

local function stored_transfer_direction(record, upper, field, fallback)
    local store = transfer_direction_store(record, upper)
    local direction = store[field]
    if direction == nil then direction = fallback end
    return direction
end

local function restore_entity_direction(entity, direction)
    if not (entity and entity.valid) or direction == nil then return end
    pcall(function() entity.direction = direction end)
end

local function restore_transfer_directions(record, upper)
    if not record then return end
    local group = upper and record.upper_transfer or record.lower_transfer
    if not group then return end
    local surface_index = upper and record.parent_surface_index or record.mineral_cave_surface_index
    local store = transfer_direction_store(record, upper)
    local fields = upper and TRANSFER_DIRECTION_FIELDS.upper or TRANSFER_DIRECTION_FIELDS.lower
    for _, def in ipairs(fields) do
        local entity = find_unit(surface_index, group[def[1]], def[2])
        restore_entity_direction(entity, store[def[1]])
    end
end

local function transfer_group_still_valid(record, upper)
    local group = upper and record.upper_transfer or record.lower_transfer
    if not group then return false end
    local surface_index = upper and record.parent_surface_index or record.mineral_cave_surface_index
    local required = upper and {
        { "item_down_input", cave_boxes.name },
        { "item_up_output", cave_boxes.name },
        { "pole", "big-electric-pole" },
    } or {
        { "item_down_output", cave_boxes.name },
        { "item_up_input", cave_boxes.name },
        { "pole", "big-electric-pole" },
        { "lamp", LOWER_LAMP },
    }
    for _, def in ipairs(required) do
        if not find_unit(surface_index, group[def[1]], def[2]) then return false end
    end
    return true
end

local function destroy_stored_transfer_group(record, upper)
    capture_transfer_directions(record, upper)
    local group = upper and record.upper_transfer or record.lower_transfer
    if not group then return end
    destroy_render_ids(group.render_ids)
    local surface_index = upper and record.parent_surface_index or record.mineral_cave_surface_index
    for field, unit in pairs(group) do
        if field ~= "render_ids" and type(unit) == "number" then
            destroy_unit(surface_index, unit, TRANSFER_ENTITY_NAMES)
        end
    end
    if upper then record.upper_transfer = nil else record.lower_transfer = nil end
end

local function refresh_transfer_group_layout(record, upper)
    local group = upper and record.upper_transfer or record.lower_transfer
    local surface = valid_surface(upper and record.parent_surface_index or record.mineral_cave_surface_index)
    local center = upper and record.entrance_position or (record.exit_position or record.entrance_position)
    if not (group and surface and center) then return false end

    -- Capture player-selected rotations before any migration, reconnect or repair.
    capture_transfer_directions(record, upper)

    -- Fixed endpoint positions are migrated once per layout version. Normal cave
    -- entry never teleports these entities again, so player rotation is preserved.
    if group.layout_version ~= TRANSFER_LAYOUT_VERSION or not render_ids_valid(group.render_ids, 2) then
        destroy_render_ids(group.render_ids)
        group.render_ids = make_transfer_labels(surface, center, upper, record)
        group.layout_version = TRANSFER_LAYOUT_VERSION
    end
    if upper and not ensure_upper_info_panel(record) then return false end
    if upper then ensure_upper_indicator_lamp(record) end
    ensure_countdown_label(record, upper, game.tick)
    restore_transfer_directions(record, upper)
    return true
end

local function destroy_group_entity(record, upper, field, names)
    local group = upper and record.upper_transfer or record.lower_transfer
    if not group then return end
    local surface_index = upper and record.parent_surface_index or record.mineral_cave_surface_index
    local entity = find_unit(surface_index, group[field], names)
    if entity and entity.valid then entity.destroy() end
    group[field] = nil
end

local function get_copper_connector(entity)
    if not (entity and entity.valid and entity.get_wire_connector) then return nil end
    local ok, connector = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    end)
    if not ok or not (connector and connector.valid) then return nil end
    return connector
end

local function copper_poles_connected(upper_pole, lower_pole)
    local upper_connector = get_copper_connector(upper_pole)
    local lower_connector = get_copper_connector(lower_pole)
    if not (upper_connector and lower_connector) then return false end
    local ok, connected = pcall(function()
        return upper_connector.is_connected_to(lower_connector, defines.wire_origin.player)
            or upper_connector.is_connected_to(lower_connector, defines.wire_origin.script)
    end)
    return ok and connected == true
end

local function connect_cross_surface_power(upper_pole, lower_pole)
    local upper_connector = get_copper_connector(upper_pole)
    local lower_connector = get_copper_connector(lower_pole)
    if not (upper_connector and lower_connector) then return false end

    local ok_connected, connected = pcall(function()
        return upper_connector.is_connected_to(lower_connector, defines.wire_origin.player)
            or upper_connector.is_connected_to(lower_connector, defines.wire_origin.script)
    end)
    if ok_connected and connected then return true end

    local ok = pcall(function()
        upper_connector.connect_to(lower_connector, false, defines.wire_origin.script)
    end)
    if not ok then return false end

    local verify_ok, verify_connected = pcall(function()
        return upper_connector.is_connected_to(lower_connector, defines.wire_origin.player)
            or upper_connector.is_connected_to(lower_connector, defines.wire_origin.script)
    end)
    return verify_ok and verify_connected == true
end

local function destroy_legacy_power_near_pole(surface, pole, names)
    if not (surface and surface.valid and pole and pole.valid) then return end
    for _, entity in pairs(surface.find_entities_filtered {
        name = names,
        position = pole.position,
        radius = 1.5,
    }) do
        if entity.valid then entity.destroy() end
    end
end

local function cleanup_legacy_power_bridge(record)
    local upper = record.upper_transfer
    if upper then
        local surface = valid_surface(record.parent_surface_index)
        local pole = find_unit(record.parent_surface_index, upper.pole, "big-electric-pole")
        destroy_group_entity(record, true, "power_connector", POWER_CONNECTOR)
        destroy_group_entity(record, true, "power", POWER_INPUT)
        destroy_legacy_power_near_pole(surface, pole, { POWER_CONNECTOR, POWER_INPUT })
    end

    local lower = record.lower_transfer
    if lower then
        local surface = valid_surface(record.mineral_cave_surface_index)
        local pole = find_unit(record.mineral_cave_surface_index, lower.pole, "big-electric-pole")
        destroy_group_entity(record, false, "power_connector", POWER_CONNECTOR)
        destroy_group_entity(record, false, "power", POWER_OUTPUT)
        destroy_legacy_power_near_pole(surface, pole, { POWER_CONNECTOR, POWER_OUTPUT })
    end
end

local function ensure_power_bridge(record)
    if not record then return false end
    local child = valid_surface(record.mineral_cave_surface_index)
    if child and record.power_connections_surface == child then return true end
    cleanup_legacy_power_bridge(record)

    local upper_group = record.upper_transfer
    local upper_pole = upper_group and find_unit(record.parent_surface_index, upper_group.pole, "big-electric-pole") or nil
    if not (upper_pole and upper_pole.valid) then return false end
    ensure_upper_indicator_lamp(record)

    local lower_group = record.lower_transfer
    if not (record.mineral_cave_surface_index and lower_group) then
        record.power_bridge_version = POWER_BRIDGE_VERSION
        return true
    end

    local lower_pole = find_unit(record.mineral_cave_surface_index, lower_group.pole, "big-electric-pole")
    if not (lower_pole and lower_pole.valid) then return false end

    local connected = connect_cross_surface_power(upper_pole, lower_pole)
    local lamp = find_unit(record.mineral_cave_surface_index, lower_group.lamp, LOWER_LAMP)
    if lamp and lamp.valid then
        local center = record.exit_position or record.entrance_position
        local target = { x = center.x + 1, y = center.y - 5 }
        if math.abs(lamp.position.x - target.x) > 0.1 or math.abs(lamp.position.y - target.y) > 0.1 then
            pcall(function() lamp.teleport(target) end)
        end
        pcall(function() lamp.operable = false end)
        pcall(function() lamp.always_on = true end)
    end

    if connected then
        record.power_bridge_version = POWER_BRIDGE_VERSION
        record.power_connections_surface = child
    end
    return connected
end

local function create_upper_transfer_group(record)
    local existing = record.upper_transfer or {}
    local parent_surface = valid_surface(record.parent_surface_index)
    local owner = game.forces[record.owner_force_index]
    local input = cave_boxes.ensure(record, "upper_input", parent_surface, record.entrance_position,
        record.entrance_name, true, owner, existing.item_down_input)
    local output = cave_boxes.ensure(record, "upper_output", parent_surface, record.entrance_position,
        record.entrance_name, false, owner, existing.item_up_output)
    if not (input and output) then return false end
    if record.upper_transfer then
        existing.item_down_input, existing.item_up_output = input.unit_number, output.unit_number
    end
    local parent = valid_surface(record.parent_surface_index)
    if not cave_placement.entrance_is_playable(parent, record.entrance_position) then return false end
    if transfer_group_still_valid(record, true) and refresh_transfer_group_layout(record, true) then
        ensure_power_bridge(record)
        return true
    end
    destroy_stored_transfer_group(record, true)
    local surface = valid_surface(record.parent_surface_index)
    local force = game.forces[record.owner_force_index] or game.forces.player
    if not (surface and force) then return false end
    local c = record.entrance_position
    local new_layout = uses_new_upper_layout(record)

    local down_input, up_output = input, output
    local power_position = { x = c.x, y = c.y - 5 }
    local pole = create_fixed_entity(surface, "big-electric-pole", power_position, force)
    local panel = nil
    local indicator_lamp = nil
    if pole and pole.valid and pole.unit_number then
        local panel_position = { x = c.x - 2, y = c.y - 5 }
        clear_fixed_entity_site(surface, panel_position, { [pole.unit_number] = true })
        panel = create_fixed_entity(surface, INFO_PANEL, panel_position, force, nil, true)
        setup_info_panel(panel, record)
        local lamp_position = { x = c.x + 1, y = c.y - 5 }
        clear_fixed_entity_site(surface, lamp_position, { [pole.unit_number] = true })
        indicator_lamp = create_fixed_entity(surface, LOWER_LAMP, lamp_position, force, nil, true)
    end
    local created = { down_input, up_output, pole, panel, indicator_lamp }
    for i = 1, 5 do
        local entity = created[i]
        if not (entity and entity.valid and entity.unit_number) then
            destroy_created_entities({ pole, panel, indicator_lamp })
            return false
        end
    end
    local group = {
        item_down_input = down_input.unit_number,
        item_up_output = up_output.unit_number,
        pole = pole.unit_number,
        info_panel = panel.unit_number,
        indicator_lamp = indicator_lamp.unit_number,
        render_ids = make_transfer_labels(surface, c, true, record),
        layout_version = TRANSFER_LAYOUT_VERSION,
    }
    record.upper_transfer = group
    pcall(function() indicator_lamp.operable = false end)
    pcall(function() indicator_lamp.always_on = true end)
    ensure_upper_info_panel(record)
    ensure_countdown_label(record, true, game.tick)
    ensure_power_bridge(record)
    return true
end

local function create_lower_transfer_group(record, surface)
    local existing = record.lower_transfer or {}
    local owner = game.forces[record.owner_force_index]
    local center = record.exit_position or record.entrance_position
    local input = cave_boxes.ensure(record, "lower_input", surface, center,
        record.entrance_name, true, owner, existing.item_down_output)
    local output = cave_boxes.ensure(record, "lower_output", surface, center,
        record.entrance_name, false, owner, existing.item_up_input)
    if not (input and output) then return false end
    if record.lower_transfer then
        existing.item_down_output, existing.item_up_input = input.unit_number, output.unit_number
    end
    if transfer_group_still_valid(record, false) and refresh_transfer_group_layout(record, false) then
        ensure_power_bridge(record)
        return true
    end
    destroy_stored_transfer_group(record, false)
    local force = game.forces[record.owner_force_index] or game.forces.player
    if not (surface and surface.valid and force) then return false end
    local c = record.exit_position or record.entrance_position

    local down_output, up_input = input, output
    local power_position = { x = c.x, y = c.y - 5 }
    local lamp_position = { x = c.x + 1, y = c.y - 5 }
    local pole = create_fixed_entity(surface, "big-electric-pole", power_position, force)
    local lamp = nil
    if pole and pole.valid and pole.unit_number then
        -- The lamp sits one tile beside the pole. Clear only the lamp tile while
        -- explicitly preserving the already-created pole whose collision box
        -- overlaps this small search area. Clearing the lamp site after placing
        -- the pole without this guard destroys the pole and makes travel fail.
        clear_fixed_entity_site(surface, lamp_position, { [pole.unit_number] = true })
        lamp = create_fixed_entity(surface, LOWER_LAMP, lamp_position, force, nil, true)
    end
    local created = { down_output, up_input, pole, lamp }
    for i = 1, 4 do
        local entity = created[i]
        if not (entity and entity.valid and entity.unit_number) then
            destroy_created_entities({ pole, lamp })
            return false
        end
    end
    pcall(function() lamp.operable = false end)
    pcall(function() lamp.always_on = true end)

    local group = {
        item_down_output = down_output.unit_number,
        item_up_input = up_input.unit_number,
        pole = pole.unit_number,
        lamp = lamp.unit_number,
        render_ids = make_transfer_labels(surface, c, false, record),
        layout_version = TRANSFER_LAYOUT_VERSION,
    }
    record.lower_transfer = group
    ensure_countdown_label(record, false, game.tick)
    ensure_power_bridge(record)
    return true
end

local function transfer_entity(record, side, field, names)
    local group = side == "upper" and record.upper_transfer or record.lower_transfer
    if not group then return nil end
    local surface_index = side == "upper" and record.parent_surface_index or record.mineral_cave_surface_index
    return find_unit(surface_index, group[field], names)
end

local function connect_item_ports(record)
    local ready = cave_boxes.ready(record)
    if ready then record.item_connections_surface = valid_surface(record.mineral_cave_surface_index) end
    return ready
end


local function create_map_gen_settings(record, parent_surface)
    local parent_settings = parent_surface.map_gen_settings or {}
    return {
        seed = record.seed,
        starting_area = 1,
        starting_points = { copy_position(LOWER_CAVE_ORIGIN) },
        peaceful_mode = parent_settings.peaceful_mode or false,
        default_enable_all_autoplace_controls = false,
        autoplace_controls = {},
    }
end

local function apply_pitch_black(surface)
    if not (surface and surface.valid) then return end
    pcall(function() surface.always_day = false end)
    pcall(function() surface.freeze_daytime = true end)
    pcall(function() surface.daytime = 0.5 end)
    pcall(function() surface.dusk = 0.25 end)
    pcall(function() surface.evening = 0.45 end)
    pcall(function() surface.morning = 0.55 end)
    pcall(function() surface.dawn = 0.75 end)
    pcall(function() surface.show_clouds = false end)
    pcall(function() surface.brightness_visual_weights = { r = 1, g = 1, b = 1 } end)
    pcall(function() surface.min_brightness = 0 end)
    pcall(function() surface.solar_power_multiplier = 0 end)
end

local function carve_start_chamber(surface, position, force)
    local cx, cy = math.floor(position.x), math.floor(position.y)
    local opened = {}
    local r2 = START_CHAMBER_RADIUS * START_CHAMBER_RADIUS
    for x = cx - START_CHAMBER_RADIUS, cx + START_CHAMBER_RADIUS do
        for y = cy - START_CHAMBER_RADIUS, cy + START_CHAMBER_RADIUS do
            local dx, dy = x - cx, y - cy
            local edge_noise = hash.roll(surface.map_gen_settings.seed or 0, x, y, 744)
            local inside = dx * dx + dy * dy <= r2
                and (dx * dx + dy * dy <= (START_CHAMBER_RADIUS - 2) ^ 2 or edge_noise > 0.28)
            if inside then
                world.carve_safe_tile(surface, x, y)
                opened[#opened + 1] = { x, y }
            end
        end
    end
    world.advance_frontier(surface, opened)

    for _, entity in pairs(surface.find_entities_filtered {
        area = { { cx - 8, cy - 8 }, { cx + 9, cy + 9 } },
    }) do
        if entity.valid and entity.name ~= "character" and entity.type ~= "character" then
            if entity.name == "diggy-rock" or entity.name == "diggy-rubble" or entity.name == "diggy-tree"
                or entity.type == "resource" or (entity.force and entity.force.name == "enemy") then
                entity.destroy()
            end
        end
    end
end

local function ensure_matching_exit(record, surface, owner_force)
    if not (record and surface and surface.valid and owner_force and owner_force.valid) then return nil end
    local desired_name = matching_exit_name(record)
    local old_unit = record.exit_unit_number
    local existing = find_unit(surface.index, old_unit,
        { "the-cave-mineral-cave-exit-1", "the-cave-mineral-cave-exit-2" })
    if existing and existing.valid and existing.name == desired_name then
        record.exit_position = copy_position(existing.position)
        root().by_entity[existing.unit_number] = record.id
        ensure_portal_label(record, false)
        return existing
    end

    if existing and existing.valid then
        root().by_entity[existing.unit_number] = nil
        existing.destroy()
    end
    local exit_position = copy_position(record.exit_position or record.entrance_position)
    clear_fixed_entity_site(surface, exit_position)
    local exit = surface.create_entity { name = desired_name, position = exit_position, force = owner_force }
    if not (exit and exit.valid and exit.unit_number) then return nil end
    exit.destructible = false
    exit.minable_flag = false
    record.exit_unit_number = exit.unit_number
    record.exit_position = copy_position(exit.position)
    root().by_entity[exit.unit_number] = record.id
    ensure_portal_label(record, false)
    return exit
end

local function ensure_mineral_cave_surface(record)
    local existing = valid_surface(record.mineral_cave_surface_index)
    if existing then
        if record.power_connections_surface == existing
            and record.item_connections_surface == existing and cave_boxes.ready(record) then return existing end
        if not record.lower_origin then
            record.lower_origin = copy_position(record.exit_position or record.entrance_position or LOWER_CAVE_ORIGIN)
        end
        apply_pitch_black(existing)
        local owner_force = game.forces[record.owner_force_index] or game.forces.player
        if not ensure_matching_exit(record, existing, owner_force) then return nil, "exit-failed" end
        if not create_lower_transfer_group(record, existing) then return nil, "transfer-failed" end
        if not connect_item_ports(record) or not ensure_power_bridge(record) then
            return nil, "transfer-failed"
        end
        return existing
    end
    local parent = valid_surface(record.parent_surface_index)
    if not parent then return nil, "missing-parent" end

    record.lower_origin = copy_position(LOWER_CAVE_ORIGIN)
    local r = root()
    local name = SURFACE_PREFIX .. tostring(record.parent_surface_index) .. "-" .. tostring(record.id)
    local surface = game.surfaces[name]
    local created_surface = false
    if not (surface and surface.valid) then
        surface = game.create_surface(name, create_map_gen_settings(record, parent))
        created_surface = surface and surface.valid or false
    end
    if not (surface and surface.valid) then return nil, "surface-failed" end
    if created_surface then world.prepare_extraction_surface(surface) end

    record.mineral_cave_surface_index = surface.index
    r.by_surface[surface.index] = record.id
    apply_pitch_black(surface)
    surface.request_to_generate_chunks(record.lower_origin, 4)
    surface.force_generate_chunk_requests()
    world.seal_unbuilt_extraction_chunks(surface)
    record.extraction_void_halo_version = EXTRACTION_VOID_HALO_VERSION

    local owner_force = game.forces[record.owner_force_index] or game.forces.player
    carve_start_chamber(surface, record.lower_origin, owner_force)

    record.exit_position = copy_position(record.lower_origin)
    local exit = ensure_matching_exit(record, surface, owner_force)
    if not exit then
        local failed = surface.index
        game.delete_surface(surface)
        r.by_surface[failed] = nil
        record.mineral_cave_surface_index = nil
        return nil, "exit-failed"
    end

    if not create_lower_transfer_group(record, surface) then
        return nil, "transfer-failed"
    end
    if not connect_item_ports(record) or not ensure_power_bridge(record) then
        return nil, "transfer-failed"
    end

    owner_force.chart(surface, {
        { record.lower_origin.x - START_CHAMBER_RADIUS - 3, record.lower_origin.y - START_CHAMBER_RADIUS - 3 },
        { record.lower_origin.x + START_CHAMBER_RADIUS + 3, record.lower_origin.y + START_CHAMBER_RADIUS + 3 },
    })
    return surface
end

local function create_entrance(
    surface, target_position, force, bypass_zone, requested_resource_key, bypass_spacing, consume_requested_resource
)
    if not enabled() then return nil, "disabled" end
    if not (surface and surface.valid and force and force.valid) then return nil, "invalid" end
    if mineral_caves.is_mineral_cave_surface(surface)
        or (type(surface.name) == "string" and surface.name:find("^the%-cave%-uranium%-cave%-")) then
        return nil, "nested"
    end

    local explicit_resource_key = valid_resource_key(requested_resource_key)
    if explicit_resource_key and not resource_enabled(explicit_resource_key) then
        return nil, "resource-disabled"
    end
    local resource_key = explicit_resource_key or peek_next_resource_key(surface, force)
    if not resource_key then return nil, "disabled" end
    local scheduled = mineral_caves.scheduled.is_planned_entrance(surface, target_position, resource_key)
    if not scheduled and not bypass_zone and mineral_caves.scheduled.manages(surface, target_position) then
        return nil, "scheduled-zone"
    end

    -- Legacy discovery keeps its same-resource spacing guard. New Advancing
    -- zones instead use the shared eight-neighbour ring across all six types;
    -- explicit administrator layout tests retain their existing bypass.
    if not bypass_spacing and not scheduled then
        if mineral_caves.has_parent_entrance_within(
            surface, target_position, MINERAL_PARENT_MIN_DISTANCE, resource_key
        ) then
            return nil, "same-resource-too-close"
        end
    end

    local zone_id = zone_for_position(target_position)
    if zone_id == "easy" and not bypass_zone and not scheduled then return nil, "easy-zone" end

    local seed = surface.map_gen_settings.seed or 0
    local name = entrance_variant(seed, target_position)
    local position = copy_position(target_position)
    if not cave_placement.prepare_entrance(surface, position, world) then return nil, "outside-or-blocked" end
    clear_portal_site(surface, position)
    local entity = surface.create_entity { name = name, position = position, force = force }
    if not (entity and entity.valid and entity.unit_number) then return nil, "create-failed" end
    entity.destructible = false
    entity.minable_flag = false

    local r = root()
    local id = r.next_id
    r.next_id = id + 1
    if zone_id == "easy" then zone_id = "medium" end
    local cave_seed = hash.range(seed, math.floor(position.x), math.floor(position.y), SEED_STREAM + (id % 997), 1, 2147483646)
    local record = {
        id = id,
        parent_surface_index = surface.index,
        entrance_position = copy_position(entity.position),
        entrance_unit_number = entity.unit_number,
        entrance_name = entity.name,
        owner_force_index = force.index,
        seed = cave_seed,
        zone_id = zone_id,
        resource_key = resource_key,
        resource_name = RESOURCE_NAMES[resource_key],
        room_count = 0,
        mineral_plan_version = MINERAL_VEIN_PLAN_VERSION,
        status = "active",
        created_tick = game.tick,
        design_version = 1,
        lower_origin = copy_position(LOWER_CAVE_ORIGIN),
        power_bridge_version = POWER_BRIDGE_VERSION,
        transfer_activated = true,
        upper_port_layout_version = UPPER_PORT_LAYOUT_VERSION,
    }
    r.by_id[id] = record
    r.by_entity[entity.unit_number] = id
    add_parent_record(r, surface.index, id)
    ensure_portal_label(record, true)

    -- Build the complete upper entrance now, not on first entry. If any fixed
    -- endpoint cannot be created, roll back the entrance as one transaction so
    -- the world never keeps a visible but unusable partial Mineral Q.
    if not create_upper_transfer_group(record) then
        cave_boxes.destroy(record)
        destroy_render_ids({ record.entrance_label_id, record.upper_timer_id })
        r.by_entity[entity.unit_number] = nil
        r.by_id[id] = nil
        remove_value(r.entrances_by_parent[surface.index], id)
        if entity.valid then entity.destroy() end
        if r.next_id == id + 1 then r.next_id = id end
        return nil, "upper-transfer-failed"
    end

    -- Advance the deterministic resource deck only after the entrance and all
    -- upper hardware have been committed successfully.
    if consume_requested_resource and explicit_resource_key then
        consume_specific_resource_key(surface, force, explicit_resource_key)
    elseif not explicit_resource_key then
        next_resource_key(surface, force)
    end
    ensure_power_bridge(record)
    return record
end

function mineral_caves.prepare_dig(dig)
    if not (dig and dig.surface and mineral_caves.is_mineral_cave_surface(dig.surface)) then return end
    dig.is_mineral_cave = true
    local record = record_for_surface(dig.surface)
    if not record then return end
    if record.status ~= "active" then
        dig.allow_room_generation = false
    end
end

function mineral_caves.on_cavern_opened(dig, room_plan, room_label)
    if not (dig and dig.surface and dig.surface.valid and room_plan) then return false end

    if mineral_caves.is_mineral_cave_surface(dig.surface) then
        local record = record_for_surface(dig.surface)
        if record then
            record.room_count = (record.room_count or 0) + 1
        end
        return false
    end

    if not enabled() then return false end

    if not (type(room_label) == "table" and room_label[1] == MINERAL_ROOM_LABEL) then return false end
    local position = room_plan.entrance_position or { x = room_plan.cx + 0.5, y = room_plan.cy + 0.5 }
    local resource_key = valid_resource_key(room_plan.mineral_resource_key)
        or peek_next_resource_key(dig.surface, dig.force)
    local record = create_entrance(dig.surface, position, dig.force, false,
        resource_key, false, not room_plan.scheduled_cave)
    if record and dig.force then
        dig.force.print({ "the-cave-mineral-caves.entrance-discovered",
            resource_localised(record.resource_key), zone_localised(record.zone_id) })
    end
    return record ~= nil
end

local function character_prototype_name(player)
    if player.character and player.character.valid then return player.character.name end
    return "character"
end

local function find_player_position(player, surface, preferred, radius)
    return surface.find_non_colliding_position(character_prototype_name(player), preferred, radius or 12, 0.5)
end

local function force_allowed(player, record)
    return not record.owner_force_index or player.force.index == record.owner_force_index
end

local function another_running_cave(record)
    for id, candidate in pairs(root().by_id) do
        if id ~= record.id
            and candidate.owner_force_index == record.owner_force_index
            and candidate.status ~= "closed"
            and candidate.timer_started_tick then
            return candidate
        end
    end
    return nil
end

local function activate_upper_infrastructure(record)
    if not record then return false end
    local child = valid_surface(record.mineral_cave_surface_index)
    if child and record.power_connections_surface == child
        and record.item_connections_surface == child and cave_boxes.ready(record) then return true end
    record.transfer_activated = true
    if not create_upper_transfer_group(record) then
        record.transfer_activated = false
        return false
    end
    ensure_power_bridge(record)
    update_countdown_labels(record, game.tick)
    return true
end

local function enable_player_flashlight_in_cave(player)
    if not (player and player.valid) then return end
    local r = root()
    if r.flashlight_state[player.index] == nil then
        local ok, state = pcall(function() return player.is_flashlight_enabled() end)
        r.flashlight_state[player.index] = ok and state or true
    end
    pcall(function() player.enable_flashlight() end)
end

local function restore_player_flashlight(player)
    if not (player and player.valid) then return end
    local r = root()
    local state = r.flashlight_state[player.index]
    if state == nil then return end
    r.flashlight_state[player.index] = nil
    if state == false then
        pcall(function() player.disable_flashlight() end)
    else
        pcall(function() player.enable_flashlight() end)
    end
end

local function enter_mineral_cave(player, record)
    if not physical.can_travel(player) then return false end
    if record.status == "closed" then
        player.print({ "the-cave-mineral-caves.cave-closed" })
        return false
    -- "exhausted" is also the live five-minute warning state. Keep travel
    -- two-way until its real deadline; on_tick performs the permanent seal.
    elseif record.status == "exhausted"
        and (not record.close_tick or game.tick >= record.close_tick) then
        player.print({ "the-cave-mineral-caves.cave-closing" })
        return false
    end
    if player.vehicle then player.print({ "the-cave-mineral-caves.leave-vehicle" }) return false end
    if not force_allowed(player, record) then player.print({ "the-cave-mineral-caves.wrong-force" }) return false end
    -- Discovery is unrestricted; only starting a new Mineral
    -- operation is serialised. Already-running legacy records stay re-enterable.
    local running = not record.timer_started_tick and another_running_cave(record) or nil
    if running then
        player.print({ "the-cave-mineral-caves.another-active", resource_localised(running.resource_key) })
        return false
    end

    if not activate_upper_infrastructure(record) then
        player.print({ "the-cave-mineral-caves.travel-failed", "upper-transfer-failed" })
        return false
    end

    local surface, reason = ensure_mineral_cave_surface(record)
    if not surface then player.print({ "the-cave-mineral-caves.travel-failed", reason or "unknown" }) return false end
    local exit_position = record.exit_position or record.entrance_position
    local preferred = { x = exit_position.x, y = exit_position.y + 3.5 }
    local position = find_player_position(player, surface, preferred, 12)
    if physical.teleport(player, position, surface) then
        start_operation_timer(record)
        enable_player_flashlight_in_cave(player)
        player.force.chart(surface, { { position.x - 16, position.y - 16 }, { position.x + 16, position.y + 16 } })
        player.print({ "the-cave-mineral-caves.entered",
            resource_localised(record.resource_key), zone_localised(record.zone_id) })
        return true
    end
    player.print({ "the-cave-mineral-caves.travel-failed", "teleport" })
    return false
end

local function leave_mineral_cave(player, record)
    if not physical.can_travel(player) then return false end
    if player.vehicle then player.print({ "the-cave-mineral-caves.leave-vehicle" }) return false end
    local parent = child_state.return_surface(player, record.parent_surface_index)
    if not parent then player.print({ "the-cave-mineral-caves.parent-missing" }) return false end
    local preferred = parent.index == record.parent_surface_index
        and { x = record.entrance_position.x, y = record.entrance_position.y + 3.5 }
        or child_state.spawn_position(player, parent)
    local position = find_player_position(player, parent, preferred, 14)
    if physical.teleport(player, position, parent) then
        restore_player_flashlight(player)
        player.print({ "the-cave-mineral-caves.left" })
        return true
    end
    player.print({ "the-cave-mineral-caves.travel-failed", "teleport" })
    return false
end

function mineral_caves.on_gui_opened(event)
    local entity = event and event.entity
    if not (entity and entity.valid) then return false end
    if not ENTRANCE_NAMES[entity.name] and not EXIT_NAMES[entity.name] then return false end
    local player = event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return true end
    player.opened = nil
    if not physical.can_use_entity(player, entity) then return true end
    local record = record_for_entity(entity)
    if not record then player.print({ "the-cave-mineral-caves.unlinked" }) return true end
    if ENTRANCE_NAMES[entity.name] then enter_mineral_cave(player, record) else leave_mineral_cave(player, record) end
    return true
end

local function begin_forced_evacuation(record)
    if not record or record.status ~= "active" then return end
    record.status = "exhausted"
    record.closing_reason = "admin-test"
    record.exhausted_tick = game.tick
    record.close_tick = game.tick + EXHAUSTION_GRACE_TICKS
    local force = game.forces[record.owner_force_index]
    if force and force.valid then force.print({ "the-cave-mineral-caves.exhausted-warning", 5 }) end
    update_countdown_labels(record, game.tick)
end

local function begin_time_evacuation(record, tick)
    if not record or record.status ~= "active" or not record.time_limit_close_tick then return end
    tick = tick or game.tick
    if record.time_limit_close_tick - tick > EXHAUSTION_GRACE_TICKS then return end
    record.status = "exhausted"
    record.closing_reason = "time"
    record.close_tick = record.time_limit_close_tick
    if not record.time_warning_sent then
        record.time_warning_sent = true
        local force = game.forces[record.owner_force_index]
        if force and force.valid then force.print({ "the-cave-mineral-caves.time-warning", 5 }) end
    end
    update_countdown_labels(record, tick)
end

function mineral_caves.on_resource_depleted(event)
    -- Resource depletion never closes a Mineral Cave. The strict shared
    -- First-entry stability timer is the only normal mission deadline.
end

function mineral_caves.exhaust_test_cave(player)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "the-cave-mineral-caves.admin-only" }) return end
    local record = record_for_surface(player.surface)
    if not record then
        player.print({ "the-cave-mineral-caves.exhaust-test-inside" })
        return
    end
    if record.status ~= "active" then
        player.print({ "the-cave-mineral-caves.exhaust-test-status" })
        return
    end
    begin_forced_evacuation(record)
    player.print({ "the-cave-mineral-caves.exhaust-test-started" })
end

local function destroy_transfer_group(record, upper)
    destroy_stored_transfer_group(record, upper)
end

local remove_record

local function close_exhausted_cave(record)
    if not record or record.status ~= "exhausted" then return end
    local child = valid_surface(record.mineral_cave_surface_index)
    if child then
        for _, player in pairs(game.players) do
            if player.valid and physical.surface(player) and physical.surface(player).valid and physical.surface(player).index == child.index then
                root().pending_respawns[player.index] = {
                    parent_surface_index = record.parent_surface_index,
                    cave_id = record.id,
                }
                if player.character and player.character.valid then
                    pcall(function() player.character.die() end)
                else
                    local fallback = child_state.return_surface(player, record.parent_surface_index)
                    if fallback and physical.teleport(player,
                        physical.find_position(player, fallback, child_state.spawn_position(player, fallback), 24), fallback) then
                        root().pending_respawns[player.index] = nil
                        restore_player_flashlight(player)
                    end
                end
            end
        end
    end

    record.status = "closed"
    record.closed_tick = game.tick
    local force = game.forces[record.owner_force_index]
    if force and force.valid then
        force.print({ "the-cave-mineral-caves.cave-sealed", resource_localised(record.resource_key) })
    end
    remove_record(record.id, true, true, true)
end

local function tick_exhaustion(record, tick)
    if record.status ~= "exhausted" then return false end
    local remaining = math.max(0, (record.close_tick or tick) - tick)
    return remaining <= 0
end

function mineral_caves.on_tick(event)
    local tick = event and event.tick or game.tick
    local closing = {}
    local cleanup_pending = {}
    for _, record in pairs(root().by_id) do
        if tick % 15 == 0 and record.status ~= "closed" then cave_boxes.sync(record) end
        if record.mineral_cave_surface_index and record.status ~= "closed" then
            local surface = valid_surface(record.mineral_cave_surface_index)
            if surface then
                if tick % 60 == 0 then
                    for _, player in pairs(game.connected_players) do
                        if player.valid and physical.surface(player).index == surface.index then
                            enable_player_flashlight_in_cave(player)
                        end
                    end
                end
            end
        end
        if record.status == "active" and record.timer_started_tick then begin_time_evacuation(record, tick) end
        if record.status ~= "closed" and tick % TIMER_UPDATE_INTERVAL == 0 then update_countdown_labels(record, tick) end
        if record.status == "closed" then cleanup_pending[#cleanup_pending + 1] = record.id
        elseif tick_exhaustion(record, tick) then closing[#closing + 1] = record end
    end
    for _, record in ipairs(closing) do close_exhausted_cave(record) end
    for _, id in ipairs(cleanup_pending) do remove_record(id, true, true, true) end
end

local function clean_existing_child(record)
    local surface = valid_surface(record.mineral_cave_surface_index)
    if not surface then return end
    apply_pitch_black(surface)

    if not record.lower_origin then
        record.lower_origin = copy_position(record.exit_position or record.entrance_position or LOWER_CAVE_ORIGIN)
    end
    if not record.exit_position then record.exit_position = copy_position(record.lower_origin) end

    -- 2.7.121 could leave a reused child-surface index marked as already
    -- Cave-converted.  Repair that raw green surface in place and rebuild the
    -- normal sealed frontier/start chamber without deleting portal hardware.
    if world.repair_raw_extraction_surface(surface) then
        local owner_force = game.forces[record.owner_force_index] or game.forces.player
        carve_start_chamber(surface, record.lower_origin, owner_force)
        record.exit_position = copy_position(record.lower_origin)
    end
    if (tonumber(record.extraction_void_halo_version) or 0) < EXTRACTION_VOID_HALO_VERSION then
        world.repair_extraction_void_halo(surface)
        record.extraction_void_halo_version = EXTRACTION_VOID_HALO_VERSION
    end

    local mineral_migrating = record.mineral_plan_version ~= MINERAL_VEIN_PLAN_VERSION
        or (record.design_version or 0) < 1
    for _, entity in pairs(surface.find_entities_filtered { type = "resource" }) do
        if entity.valid then
            if entity.name == record.resource_name then
                if mineral_migrating then entity.destroy() end
            else
                entity.destroy()
            end
        end
    end

    -- Remove the old engine-level 200x200 dimensions. Width/height zero means
    -- no MapGen distance cap; The Cave's digging system can keep opening tiles.
    local settings = surface.map_gen_settings
    settings.width = 0
    settings.height = 0
    settings.starting_points = { copy_position(LOWER_CAVE_ORIGIN) }
    pcall(function() surface.map_gen_settings = settings end)

    -- Rebuild all already-exposed generated tiles, including positions beyond
    -- the former 200x200 resource square. Covered rock tiles remain untouched
    -- and will receive their deterministic vein result when they are opened.
    if mineral_migrating then
        for chunk in surface.get_chunks() do
            local area = chunk.area
            for x = area.left_top.x, area.right_bottom.x - 1 do
                for y = area.left_top.y, area.right_bottom.y - 1 do
                    if cave_tile_is_exposed(surface, x, y) then
                        mineral_caves.materialize_mineral(surface, x, y, nil)
                    end
                end
            end
        end
    end

    record.mineral_plan_version = MINERAL_VEIN_PLAN_VERSION
    record.design_version = 1
end

function mineral_caves.on_player_changed_surface(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if mineral_caves.is_mineral_cave_surface(physical.surface(player)) then
        enable_player_flashlight_in_cave(player)
    else
        restore_player_flashlight(player)
    end
end

function mineral_caves.on_player_rotated_entity(event)
    local entity = event and event.entity
    if not (entity and entity.valid and entity.unit_number) then return end
    local name = entity.name
    if name ~= ITEM_DOWN_INPUT and name ~= ITEM_DOWN_OUTPUT
        and name ~= ITEM_UP_INPUT and name ~= ITEM_UP_OUTPUT then
        return
    end

    for _, record in pairs(root().by_id) do
        local groups = {
            { upper = true, group = record.upper_transfer },
            { upper = false, group = record.lower_transfer },
        }
        for _, entry in ipairs(groups) do
            local group = entry.group
            if group then
                local fields = entry.upper and TRANSFER_DIRECTION_FIELDS.upper or TRANSFER_DIRECTION_FIELDS.lower
                for _, def in ipairs(fields) do
                    if group[def[1]] == entity.unit_number then
                        transfer_direction_store(record, entry.upper)[def[1]] = entity.direction
                        return
                    end
                end
            end
        end
    end
end

function mineral_caves.on_player_respawned(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local pending = root().pending_respawns[player.index]
    local record = record_for_surface(physical.surface(player))
    if not pending and not record then return end
    local surface = child_state.return_surface(player, pending and pending.parent_surface_index or record.parent_surface_index)
    if not (surface and surface.valid) then return end
    local preferred = child_state.spawn_position(player, surface)
    local position = find_player_position(player, surface, preferred, 24)
    if not physical.teleport(player, position, surface) then return end
    root().pending_respawns[player.index] = nil
    restore_player_flashlight(player)
    player.print({ "the-cave-mineral-caves.forced-respawn" })
end

function mineral_caves.on_init()
    root()
end

function mineral_caves.on_configuration_changed()
    root()
    rebuild_indexes()
    cleanup_legacy_closed_labels()
    local closed_ids = {}
    for id, record in pairs(root().by_id) do
        if record.status == "closed" then closed_ids[#closed_ids + 1] = id end
    end
    for _, id in ipairs(closed_ids) do remove_record(id, true, true, true) end
    for _, record in pairs(root().by_id) do
        normalize_record(record)
        record.power_connections_surface = nil
        record.item_connections_surface = nil
        if record.status ~= "closed" then
            cave_placement.repair_entrance(record, root(), world, {}, MINERAL_PARENT_MIN_DISTANCE)
            ensure_portal_label(record, true)
            record.transfer_activated = true
            create_upper_transfer_group(record)
            ensure_power_bridge(record)
        end
        if record.status ~= "closed" and record.mineral_cave_surface_index then
            clean_existing_child(record)
            local surface = valid_surface(record.mineral_cave_surface_index)
            if surface then
                if not record.exit_position then record.exit_position = copy_position(record.entrance_position) end
                local owner_force = game.forces[record.owner_force_index] or game.forces.player
                ensure_matching_exit(record, surface, owner_force)
                create_lower_transfer_group(record, surface)
                ensure_power_bridge(record)
                connect_item_ports(record)
                if record.status == "active" and not record.timer_started_tick then
                    for _, player in pairs(game.players) do
                        if player.valid and physical.surface(player) and physical.surface(player).valid and physical.surface(player).index == surface.index then
                            start_operation_timer(record)
                            break
                        end
                    end
                end
            end
        end
        if record.status ~= "closed" then update_countdown_labels(record, game.tick) end
    end
    -- Reconcile players immediately when updating from builds that forced the flashlight off.
    for _, player in pairs(game.players) do
        if player.valid and mineral_caves.is_mineral_cave_surface(physical.surface(player)) then
            enable_player_flashlight_in_cave(player)
        else
            restore_player_flashlight(player)
        end
    end
end

local function fallback_surface_and_position(player)
    local surface = child_state.return_surface(player)
    if not surface then return nil, nil end
    return surface, child_state.spawn_position(player, surface)
end

local function evacuate_and_delete_child(record, silent)
    local child = valid_surface(record.mineral_cave_surface_index)
    if not child then return true end
    for _, player in pairs(game.players) do
        local inside = physical.on_surface(player, child)
        if player.valid and (inside or player.surface == child) then
            local fallback, preferred = fallback_surface_and_position(player)
            if not fallback then return false end
            local position = preferred
            if inside then position = find_player_position(player, fallback, preferred, 16) end
            -- Do not use the raw spawn as a physical landing if the bounded search failed.
            if inside and not position then return false end
            if not physical.evacuate(player, child, fallback, position) then return false end
            if inside then
                restore_player_flashlight(player)
                if not silent then player.print({ "the-cave-mineral-caves.parent-removed" }) end
            end
        end
    end
    if not child.valid then return true end
    local ok, queued = pcall(function() return game.delete_surface(child) end)
    return ok and queued == true
end

remove_record = function(id, delete_child, destroy_portals, silent_evacuation)
    local r = root()
    local record = r.by_id[id]
    if not record then return end
    destroy_transfer_group(record, true)
    destroy_transfer_group(record, false)
    destroy_render_ids({ record.entrance_label_id, record.exit_label_id, record.upper_timer_id, record.lower_timer_id })
    destroy_render_ids(record.closed_render_ids)
    if destroy_portals then
        destroy_unit(record.parent_surface_index, record.entrance_unit_number,
            { "the-cave-mineral-cave-entrance-1", "the-cave-mineral-cave-entrance-2" })
        destroy_unit(record.mineral_cave_surface_index, record.exit_unit_number, { "the-cave-mineral-cave-exit-1", "the-cave-mineral-cave-exit-2" })
    end
    if delete_child and not evacuate_and_delete_child(record, silent_evacuation) then
        record.status = "closed"
        return false
    end
    if record.entrance_unit_number then r.by_entity[record.entrance_unit_number] = nil end
    if record.exit_unit_number then r.by_entity[record.exit_unit_number] = nil end
    if record.mineral_cave_surface_index then r.by_surface[record.mineral_cave_surface_index] = nil end
    remove_value(r.entrances_by_parent[record.parent_surface_index], id)
    cave_boxes.destroy(record)
    r.by_id[id] = nil
    return true
end

function mineral_caves.on_surface_deleted(event)
    local surface_index = event and event.surface_index
    if not surface_index then return end
    local r = root()
    local child_id = r.by_surface[surface_index]
    if child_id then
        local record = r.by_id[child_id]
        r.by_surface[surface_index] = nil
        if record then
            if record.exit_unit_number then r.by_entity[record.exit_unit_number] = nil end
            record.mineral_cave_surface_index = nil
            record.exit_unit_number = nil
            record.exit_position = nil
            record.exit_label_id = nil
            record.lower_timer_id = nil
            record.lower_transfer = nil
        end
        return
    end
    local ids = {}
    for _, id in ipairs(r.entrances_by_parent[surface_index] or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do remove_record(id, true) end
    r.entrances_by_parent[surface_index] = nil
end

function mineral_caves.on_surface_cleared(event)
    local surface_index = event and event.surface_index
    if not surface_index then return end
    local r = root()
    local child_id = r.by_surface[surface_index]
    if child_id then
        local record = r.by_id[child_id]
        r.by_surface[surface_index] = nil
        if record then
            if record.exit_unit_number then r.by_entity[record.exit_unit_number] = nil end
            record.mineral_cave_surface_index = nil
            record.exit_unit_number = nil
            record.exit_position = nil
            record.exit_label_id = nil
            record.lower_timer_id = nil
            record.lower_transfer = nil
        end
        local child = valid_surface(surface_index)
        if child then game.delete_surface(child) end
        return
    end
    local ids = {}
    for _, id in ipairs(r.entrances_by_parent[surface_index] or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do remove_record(id, true) end
    r.entrances_by_parent[surface_index] = nil
end

function mineral_caves.spawn_test_entrance(player, requested_resource_key)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "the-cave-mineral-caves.admin-only" }) return end
    if not enabled() then player.print({ "the-cave-mineral-caves.disabled" }) return end
    if mineral_caves.is_mineral_cave_surface(player.surface) then player.print({ "the-cave-mineral-caves.no-nesting" }) return end
    local resource_key = valid_resource_key(requested_resource_key)
    if not resource_key then
        player.print({ "the-cave-mineral-caves.test-usage" })
        return
    end
    local target = { x = player.position.x + 10, y = player.position.y }
    local record, reason = create_entrance(player.surface, target, player.force, true, resource_key, true)
    if record then
        player.print({ "the-cave-mineral-caves.test-created", record.id,
            resource_localised(record.resource_key), zone_localised(record.zone_id) })
    else
        player.print({ "the-cave-mineral-caves.test-failed", reason or "unknown" })
    end
end

function mineral_caves.spawn_all_test_entrances(player)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "the-cave-mineral-caves.admin-only" }) return end
    if not enabled() then player.print({ "the-cave-mineral-caves.disabled" }) return end
    if mineral_caves.is_mineral_cave_surface(player.surface) then
        player.print({ "the-cave-mineral-caves.no-nesting" })
        return
    end

    local tests = {
        { key = "iron", dx = -24 },
        { key = "copper", dx = 0 },
        { key = "coal", dx = 24 },
    }
    local created = 0
    for _, test in ipairs(tests) do
        local target = { x = player.position.x + test.dx, y = player.position.y + 16 }
        local record = create_entrance(player.surface, target, player.force, true, test.key, true)
        if record then created = created + 1 end
    end
    player.print({ "the-cave-mineral-caves.test-all-created", created })
end

local function debug_carve_disc(surface, cx, cy, radius, force, opened)
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= radius * radius then
                world.carve_tile(surface, x, y, force, false, true)
                opened[#opened + 1] = { x, y }
            end
        end
    end
end

local function debug_carve_corridor(surface, from, to, force, opened)
    local x, y = from.x, from.y
    while x ~= to.x do
        x = x + (to.x > x and 1 or -1)
        for w = -1, 1 do
            world.carve_tile(surface, x, y + w, force, false, true)
            opened[#opened + 1] = { x, y + w }
        end
    end
    while y ~= to.y do
        y = y + (to.y > y and 1 or -1)
        for w = -1, 1 do
            world.carve_tile(surface, x + w, y, force, false, true)
            opened[#opened + 1] = { x + w, y }
        end
    end
end

function mineral_caves.open_room_test(player)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "the-cave-mineral-caves.admin-only" }) return end
    local record = record_for_surface(player.surface)
    if not record then
        player.print({ "the-cave-mineral-caves.room-test-inside" })
        return
    end
    if record.status ~= "active" then
        player.print({ "the-cave-mineral-caves.cave-closed" })
        return
    end
    if record.debug_rooms_opened then
        player.print({ "the-cave-mineral-caves.room-test-already" })
        return
    end

    local origin = child_origin(record)
    local relative_centres = {
        { x = 0, y = 34 }, { x = 34, y = 34 }, { x = 34, y = 68 },
        { x = 0, y = 68 }, { x = -34, y = 68 }, { x = -34, y = 102 },
        { x = 0, y = 102 }, { x = 34, y = 102 }, { x = 68, y = 102 },
        { x = 68, y = 68 },
    }
    local centres = {}
    for i, relative in ipairs(relative_centres) do
        centres[i] = {
            x = math.floor(origin.x + relative.x),
            y = math.floor(origin.y + relative.y),
        }
        player.surface.request_to_generate_chunks(centres[i], 2)
    end
    player.surface.force_generate_chunk_requests()

    local opened = {}
    local previous = { x = math.floor(origin.x), y = math.floor(origin.y + START_CHAMBER_RADIUS) }
    for _, centre in ipairs(centres) do
        debug_carve_corridor(player.surface, previous, centre, player.force, opened)
        debug_carve_disc(player.surface, centre.x, centre.y, 11, player.force, opened)
        previous = centre
    end
    world.advance_frontier(player.surface, opened)
    record.room_count = DEBUG_TEST_ROOM_COUNT
    record.debug_rooms_opened = true
    player.force.chart(player.surface, {
        { origin.x - 55, origin.y - 5 }, { origin.x + 85, origin.y + 120 },
    })
    player.print({ "the-cave-mineral-caves.room-test-created",
        DEBUG_TEST_ROOM_COUNT, resource_localised(record.resource_key) })
end


function mineral_caves.power_test_status(player)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "the-cave-mineral-caves.admin-only" }) return end

    local record = record_for_surface(player.surface)
    if not record then
        local best, best_d2 = nil, math.huge
        for _, candidate in pairs(root().by_id) do
            if candidate.parent_surface_index == player.surface.index and candidate.entrance_position then
                local dx = player.position.x - candidate.entrance_position.x
                local dy = player.position.y - candidate.entrance_position.y
                local d2 = dx * dx + dy * dy
                if d2 < best_d2 then best, best_d2 = candidate, d2 end
            end
        end
        if best_d2 <= 80 * 80 then record = best end
    end
    if not record then player.print({ "the-cave-mineral-caves.power-test-no-cave" }) return end

    ensure_power_bridge(record)
    local upper_pole = transfer_entity(record, "upper", "pole", "big-electric-pole")
    local lower_pole = transfer_entity(record, "lower", "pole", "big-electric-pole")
    local lamp = transfer_entity(record, "lower", "lamp", LOWER_LAMP)
    local connected = copper_poles_connected(upper_pole, lower_pole)

    local function pole_net(entity)
        local connector = get_copper_connector(entity)
        if not connector then return "missing" end
        local ok, value = pcall(function() return connector.network_id end)
        if not ok or value == nil then return "none" end
        return tostring(value)
    end
    local function entity_net(entity)
        if not (entity and entity.valid) then return "missing" end
        local ok, value = pcall(function() return entity.electric_network_id end)
        if not ok or value == nil then return "none" end
        return tostring(value)
    end
    local function energy_j(entity)
        if not (entity and entity.valid) then return "missing" end
        return string.format("%.1f", tonumber(entity.energy) or 0)
    end

    player.print({ "the-cave-mineral-caves.power-test-direct-status",
        connected and "CONNECTED" or "DISCONNECTED",
        pole_net(upper_pole), pole_net(lower_pole), entity_net(lamp), energy_j(lamp)
    })
end

function mineral_caves.register_commands()
    local function spawn_handler(event)
        local player = event.player_index and game.get_player(event.player_index)
        if not player then return end
        local parameter = event.parameter and event.parameter:lower():match("^%s*(.-)%s*$") or ""
        if parameter == "all" then
            mineral_caves.spawn_all_test_entrances(player)
        else
            mineral_caves.spawn_test_entrance(player, parameter)
        end
    end
    local function exhaust_handler(event)
        local player = event.player_index and game.get_player(event.player_index)
        if player then mineral_caves.exhaust_test_cave(player) end
    end
    local function power_handler(event)
        local player = event.player_index and game.get_player(event.player_index)
        if player then mineral_caves.power_test_status(player) end
    end
    local function room_handler(event)
        local player = event.player_index and game.get_player(event.player_index)
        if player then mineral_caves.open_room_test(player) end
    end
    commands.add_command("the-cave-mineral-cave-test", { "the-cave-mineral-caves.command-help" }, spawn_handler)
    commands.add_command("the-cave-mineral-room-test", { "the-cave-mineral-caves.command-room-help" }, room_handler)
    commands.add_command("the-cave-mineral-cave-exhaust-test", { "the-cave-mineral-caves.command-exhaust-help" }, exhaust_handler)
    commands.add_command("the-cave-mineral-power-test", { "the-cave-mineral-caves.command-power-help" }, power_handler)
end

function mineral_caves.owned_surfaces(force)
    return child_state.owned_surfaces(root(), force, "mineral_cave_surface_index", SURFACE_PREFIX, true)
end

function mineral_caves.owner_force(surface)
    return child_state.owner_force(root(), surface, "mineral_cave_surface_index", SURFACE_PREFIX, true)
end

function mineral_caves.clear_force(force_index)
    child_state.clear_force(root(), force_index)
end

function mineral_caves.transfer_force(source_index, destination_index)
    child_state.transfer_force(root(), source_index, destination_index)
end

return mineral_caves
