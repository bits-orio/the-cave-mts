local physical = require("scripts.player_physical")
local settings = require("scripts.game_settings").proxy(settings)

-- The Cave experimental Warp Outpost / Cavetorio prototype.
-- This is intentionally self-contained and conservative: it moves the current
-- Outpost footprint to a fresh cave surface, keeps a HUD/timer, and records a
-- runtime cave profile for testing the algorithm before the full system is split
-- into production files.

local train_interiors = require("scripts.train_interiors")
local main_train_defeat = require("scripts.main_train_defeat")
local cave_teams = require("scripts.cave_teams")
local cave_worlds = require("scripts.cave_worlds")

local warp_outpost = {}
local main_train_defeat_handler

local WARP_SURFACE_PREFIX = "the-cave-warp-"
local GUI_FLOW = "the_cave_warp_outpost_flow"
local GUI_BUTTON = "the_cave_warp_manual_button"
local GUI_CAVE_INFO_BUTTON = "the_cave_warp_cave_info_button"
local GUI_TRAIN_INFO_BUTTON = "the_cave_warp_train_info_button"
local GUI_STATUS = "the_cave_warp_status_label"
local GUI_EXTRA = "the_cave_warp_extra_label"
local GUI_ATTACK_WAVE = "the_cave_warp_attack_wave_label"
local GUI_NEXT_ATTACK = "the_cave_warp_next_attack_label"
local GUI_HEADER = "the_cave_warp_header_flow"
local GUI_CAVE_PANEL = "the_cave_warp_cave_info_panel"
local GUI_TRAIN_PANEL = "the_cave_warp_main_train_info_panel"
local MAIN_TRAIN_DEFEAT_GUI = "the_cave_main_train_defeat_frame"
local MAIN_TRAIN_DEFEAT_LABEL = "the_cave_main_train_defeat_label"
local MAIN_TRAIN_DEFEAT_COUNTDOWN_SECONDS = 30
local GUI_CAVE_ROWS = {
    warp = "the_cave_warp_cave_row_warp",
    zone = "the_cave_warp_cave_row_zone",
    region = "the_cave_warp_cave_row_region",
    nightmare_depth = "the_cave_warp_cave_row_nightmare_depth",
    time_left = "the_cave_warp_cave_row_time_left",
    lighting = "the_cave_warp_cave_row_lighting",
    resources = "the_cave_warp_cave_row_resources",
    cave_difficulty = "the_cave_warp_cave_row_cave_difficulty",
    research_difficulty = "the_cave_warp_cave_row_research_difficulty",
    digging = "the_cave_warp_cave_row_digging",
    ore_protection = "the_cave_warp_cave_row_ore_protection",
    ore_missing = "the_cave_warp_cave_row_ore_missing",
    mixed_resources = "the_cave_warp_cave_row_mixed_resources",
}
local GUI_TRAIN_ROWS = {
    train_parts = "the_cave_warp_train_row_train_parts",
    locomotives = "the_cave_warp_train_row_locomotives",
    cargo_wagons = "the_cave_warp_train_row_cargo_wagons",
    fluid_wagons = "the_cave_warp_train_row_fluid_wagons",
    artillery_wagons = "the_cave_warp_train_row_artillery_wagons",
    outpost_size = "the_cave_warp_train_row_outpost_size",
    safety_ring = "the_cave_warp_train_row_safety_ring",
    warp_time = "the_cave_warp_train_row_warp_time",
    battery = "the_cave_warp_train_row_battery",
}

local TICKS_PER_SECOND = 60
local TICKS_PER_MINUTE = 60 * TICKS_PER_SECOND
local OUTPOST_CLEAR_RING = 10 -- fallback/default Safety Ring radius before research

local EXPANSION_PREFIX = "the-cave-warp-outpost-expansion-"
local TIME_PREFIX = "the-cave-warp-outpost-time-"
local SAFETY_RING_PREFIX = "the-cave-safety-ring-upgrade-"

local SIZE_LEVELS = {
    [0] = { width = 25, height = 25, label = "25x25" },
    [1] = { width = 50, height = 50, label = "50x50" },
    [2] = { width = 75, height = 75, label = "75x75" },
    [3] = { width = 100, height = 100, label = "100x100" },
    [4] = { width = 125, height = 125, label = "125x125" },
    [5] = { width = 150, height = 150, label = "150x150" },
    [6] = { width = 175, height = 175, label = "175x175" },
    [7] = { width = 200, height = 200, label = "200x200" },
}

local TIME_LEVELS = {
    [0] = { minutes = 30, countdown = 20, cooldown = 10 },
    [1] = { minutes = 45, countdown = 30, cooldown = 30 },
    [2] = { minutes = 60, countdown = 40, cooldown = 45 },
    [3] = { minutes = 80, countdown = 60, cooldown = 60 },
    [4] = { minutes = 100, countdown = 80, cooldown = 90 },
    [5] = { minutes = 120, countdown = 100, cooldown = 120 },
    [6] = { minutes = 140, countdown = 110, cooldown = 150 },
    [7] = { minutes = 160, countdown = 120, cooldown = 180 },
}

-- Safety Ring progression. Level 0 is the quiet starter ring with no scripted
-- wave attacks. Upgrade 1+ expands the clear defensive area and enables the
-- scripted Point A -> Point B attack waves. The radius is measured outward from
-- each edge of the Warp Outpost footprint, not from the map origin.
local SAFETY_RING_LEVELS = {
    [0] = { radius = 10, label = "10 tiles", cooldown_minutes = nil },
    [1] = { radius = 20, label = "20 tiles", cooldown_minutes = 1 },
    [2] = { radius = 30, label = "30 tiles", cooldown_minutes = 1 },
    [3] = { radius = 40, label = "40 tiles", cooldown_minutes = 1 },
    [4] = { radius = 50, label = "50 tiles", cooldown_minutes = 1 },
    [5] = { radius = 60, label = "60 tiles", cooldown_minutes = 1 },
    [6] = { radius = 70, label = "70 tiles", cooldown_minutes = 1 },
    [7] = { radius = 80, label = "80 tiles", cooldown_minutes = 1 },
}

-- Wave definitions are intentionally data-only so balance can be adjusted later
-- without rewriting the algorithm. Counts are per corner per mini-wave.
local SAFETY_RING_WAVES = {
    [1] = {
        { corners = 2, counts = { ["small-biter"] = 8, ["small-spitter"] = 2 } },
    },
    [2] = {
        { corners = 2, counts = { ["small-biter"] = 10, ["medium-biter"] = 2, ["small-spitter"] = 3 } },
    },
    [3] = {
        { corners = 3, counts = { ["medium-biter"] = 8, ["small-spitter"] = 4, ["medium-spitter"] = 1 } },
    },
    [4] = {
        { corners = 2, counts = { ["medium-biter"] = 10, ["big-biter"] = 2, ["medium-spitter"] = 3 } },
        { corners = 2, counts = { ["medium-biter"] = 10, ["big-biter"] = 2, ["medium-spitter"] = 3 } },
    },
    [5] = {
        { corners = 3, counts = { ["big-biter"] = 8, ["medium-biter"] = 4, ["medium-spitter"] = 3, ["big-spitter"] = 1 } },
        { corners = 2, counts = { ["big-biter"] = 8, ["medium-biter"] = 4, ["medium-spitter"] = 3, ["big-spitter"] = 1 } },
    },
    [6] = {
        { corners = 3, counts = { ["big-biter"] = 10, ["behemoth-biter"] = 2, ["big-spitter"] = 3, ["behemoth-spitter"] = 1 } },
        { corners = 3, counts = { ["big-biter"] = 10, ["behemoth-biter"] = 2, ["big-spitter"] = 3, ["behemoth-spitter"] = 1 } },
    },
    [7] = {
        { corners = 4, counts = { ["big-biter"] = 10, ["behemoth-biter"] = 4, ["big-spitter"] = 3, ["behemoth-spitter"] = 2 } },
        { corners = 3, counts = { ["big-biter"] = 10, ["behemoth-biter"] = 4, ["big-spitter"] = 3, ["behemoth-spitter"] = 2 } },
    },
}

local SAFETY_RING_KILL_RATIO_TO_CLEAR = 0.75
local SAFETY_RING_WAVE_TIMEOUT_TICKS = 10 * TICKS_PER_MINUTE
local SAFETY_RING_REST_EVERY_WAVES = 50
local SAFETY_RING_REST_TICKS = 5 * TICKS_PER_MINUTE
local SAFETY_RING_BOSS_EVERY_WAVES = 10


local LIGHTING_OPTIONS = { "normal", "permanent-day", "permanent-night", "pitch-black" }

local function state()
    storage.the_cave_warp_outpost = storage.the_cave_warp_outpost or {}
    local s = storage.the_cave_warp_outpost
    s.warp_number = tonumber(s.warp_number) or 1
    s.current_surface_name = s.current_surface_name or "nauvis"
    s.outpost_center = s.outpost_center or nil
    s.next_auto_warp_tick = tonumber(s.next_auto_warp_tick) or nil
    s.manual_cooldown_until = tonumber(s.manual_cooldown_until) or 0
    s.manual_countdown_until = tonumber(s.manual_countdown_until) or nil
    s.manual_votes = s.manual_votes or {}
    s.cleanup_queue = s.cleanup_queue or {}
    s.offline_return_queue = s.offline_return_queue or {}
    s.surface_profiles = s.surface_profiles or {}
    s.warned_minutes = s.warned_minutes or {}
    s.nightmare_unlocked_announced = s.nightmare_unlocked_announced or false
    s.gui_mode = s.gui_mode or {}
    s.pending_wire_restores = s.pending_wire_restores or {}
    s.safety_ring = s.safety_ring or {}
    s.safety_ring.active_units = s.safety_ring.active_units or {}
    s.safety_ring.pending_mini_waves = s.safety_ring.pending_mini_waves or {}
    s.safety_ring.cooldown_until = tonumber(s.safety_ring.cooldown_until) or nil
    s.safety_ring.last_level = tonumber(s.safety_ring.last_level) or 0
    s.safety_ring.wave_number = tonumber(s.safety_ring.wave_number) or 0
    s.safety_ring.current_wave_number = tonumber(s.safety_ring.current_wave_number) or nil
    s.safety_ring.current_wave_total = tonumber(s.safety_ring.current_wave_total) or 0
    s.safety_ring.current_wave_started_tick = tonumber(s.safety_ring.current_wave_started_tick) or nil
    s.safety_ring.rest_until = tonumber(s.safety_ring.rest_until) or nil
    s.safety_ring.rest_wave_number = tonumber(s.safety_ring.rest_wave_number) or nil
    s.safety_ring.current_wave_boss = s.safety_ring.current_wave_boss or false
    s.main_train_registered_forces = s.main_train_registered_forces or {}
    s.main_train_defeats = s.main_train_defeats or {}
    s.main_train_defeat_tick = tonumber(s.main_train_defeat_tick) or nil
    s.main_train_defeat_last_second = tonumber(s.main_train_defeat_last_second) or nil
    s.main_train_defeat_finished = s.main_train_defeat_finished or false
    return s
end

local function cavetorio_enabled()
    local st = settings and settings.startup and settings.startup["the-cave-cavetorio"]
    return not st or st.value == "enabled"
end

local function destroy_player_gui(player)
    if not (player and player.valid and player.gui) then return end
    local top = player.gui.top
    if top then
        local flow = top[GUI_FLOW]
        if flow and flow.valid then flow.destroy() end
    end
    local screen = player.gui.screen
    if screen then
        local cave_panel = screen[GUI_CAVE_PANEL]
        if cave_panel and cave_panel.valid then cave_panel.destroy() end
        local train_panel = screen[GUI_TRAIN_PANEL]
        if train_panel and train_panel.valid then train_panel.destroy() end
    end
end

local function destroy_all_gui()
    if not game then return end
    for _, player in pairs(game.players or {}) do
        destroy_player_gui(player)
    end
end

local function valid(e) return e and e.valid end

local function player_force()
    return game.forces.player or (game.players[1] and game.players[1].force)
end

local function researched_level(force, prefix, max_level)
    if not (force and force.valid and force.technologies) then return 0 end
    local level = 0
    for i = 1, max_level do
        local tech = force.technologies[prefix .. i]
        if tech and tech.researched then level = i end
    end
    return level
end

local function outpost_size(force)
    local level = researched_level(force or player_force(), EXPANSION_PREFIX, 7)
    return SIZE_LEVELS[level] or SIZE_LEVELS[0], level
end

local function outpost_time(force)
    local level = researched_level(force or player_force(), TIME_PREFIX, 7)
    return TIME_LEVELS[level] or TIME_LEVELS[0], level
end

local function safety_ring(force)
    local level = researched_level(force or player_force(), SAFETY_RING_PREFIX, 7)
    return SAFETY_RING_LEVELS[level] or SAFETY_RING_LEVELS[0], level
end

local function safety_ring_radius(force)
    local def = safety_ring(force)
    return math.max(0, tonumber(def.radius) or OUTPOST_CLEAR_RING)
end

local format_time

local function count_active_safety_ring_units(sr)
    local count = 0
    for _, unit in pairs((sr and sr.active_units) or {}) do
        if valid(unit) then count = count + 1 end
    end
    return count
end

local function safety_ring_hud_text(force, now)
    local ring_def, ring_level = safety_ring(force)
    local sr = state().safety_ring
    if ring_level <= 0 or not ring_def.cooldown_minutes then
        return "    |    Attack Wave: Off  ", "    |    Next Attack: Off  "
    end

    local wave_number = tonumber(sr.wave_number) or 0
    local active_count = count_active_safety_ring_units(sr)
    local pending_count = #(sr.pending_mini_waves or {})
    local wave_suffix = ""
    if sr.rest_until and now < sr.rest_until then
        wave_number = tonumber(sr.rest_wave_number) or wave_number
        wave_suffix = " Rest"
    elseif sr.current_wave_boss then
        wave_suffix = " Boss"
    end
    local wave_text = "    |    Attack Wave: #" .. tostring(wave_number) .. wave_suffix .. "  "
    local next_text

    if sr.rest_until and now < sr.rest_until then
        next_text = "    |    Next Attack: Rest " .. format_time(sr.rest_until - now) .. "  "
    elseif active_count > 0 or pending_count > 0 then
        local total = tonumber(sr.current_wave_total) or active_count
        if total > 0 then
            next_text = "    |    Next Attack: Active (" .. tostring(active_count) .. " / " .. tostring(total) .. " alive)  "
        else
            next_text = "    |    Next Attack: Active (" .. tostring(active_count) .. " alive)  "
        end
    elseif sr.cooldown_until then
        next_text = "    |    Next Attack: " .. format_time((sr.cooldown_until or now) - now) .. "  "
    else
        next_text = "    |    Next Attack: Ready  "
    end

    return wave_text, next_text
end


local function blue_outpost_tile()
    if prototypes and prototypes.tile then
        if prototypes.tile["blue-refined-concrete"] then return "blue-refined-concrete" end
        if prototypes.tile["refined-concrete"] then return "refined-concrete" end
        if prototypes.tile["concrete"] then return "concrete" end
    end
    return "refined-concrete"
end

local function is_enemy_entity(entity)
    if not valid(entity) then return false end
    if entity.force and entity.force.valid and entity.force.name == "enemy" then return true end
    if entity.type == "unit" or entity.type == "unit-spawner" then return true end
    if entity.name == "demolisher" or entity.name == "small-demolisher" or entity.name == "medium-demolisher" or entity.name == "big-demolisher" then return true end
    return false
end

local ROLLING_STOCK_TYPES = {
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
}


function format_time(ticks)
    ticks = math.max(0, math.floor(tonumber(ticks) or 0))
    local seconds = math.floor((ticks + 59) / 60)
    local minutes = math.floor(seconds / 60)
    seconds = seconds % 60
    return string.format("%02d:%02d", minutes, seconds)
end

local function display_profile_value(value)
    value = tostring(value or "")
    if value == "" then return "Unknown" end
    value = value:gsub("%-", " ")
    return (value:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

local function digging_enabled(profile)
    return profile and profile.digging_mode and profile.digging_mode ~= "disabled"
end

local function resource_level_text(profile)
    if digging_enabled(profile) then return "Disabled by Digging Mode" end
    return display_profile_value((profile and profile.resource_level) or "level-2")
end

local function rect_bounds(center, size)
    local width, height = size.width, size.height
    local left = math.floor(center.x - width / 2)
    local top = math.floor(center.y - height / 2)
    local right = left + width
    local bottom = top + height
    return left, top, right, bottom
end

local function area_from_bounds(left, top, right, bottom)
    return { { left, top }, { right, bottom } }
end

local function entity_fully_inside(entity, left, top, right, bottom)
    if not valid(entity) then return false end
    local box = entity.bounding_box
    if not box then
        local p = entity.position
        return p and p.x >= left and p.x <= right and p.y >= top and p.y <= bottom
    end
    return box.left_top.x >= left and box.right_bottom.x <= right
        and box.left_top.y >= top and box.right_bottom.y <= bottom
end

local function point_inside(position, left, top, right, bottom)
    return position and position.x >= left and position.x <= right and position.y >= top and position.y <= bottom
end

-- 2.2.57: The old 50-tile enemy safe zone was removed because it
-- behaved like an invisible wall: attacking biters disappeared as soon as
-- they entered the buffer.  The only protection around the Outpost now is
-- the one-time clear ring, which is prepared during landing/expansion and
-- does not delete enemies later during combat.
function warp_outpost.enforce_enemy_safe_zone_now(surface, position, reason)
    return 0
end

local function find_any_main_train_center(surface)
    local tsi = storage.the_cave_train_interiors
    if not (tsi and tsi.wagons and tsi.main_train_units) then return nil end
    local sx, sy, count = 0, 0, 0
    for unit in pairs(tsi.main_train_units) do
        local wagon = tsi.wagons[unit]
        local entity = wagon and wagon.entity
        if valid(entity) and entity.surface == surface then
            sx = sx + entity.position.x
            sy = sy + entity.position.y
            count = count + 1
        end
    end
    if count > 0 then return { x = sx / count, y = sy / count } end
    return nil
end

local function current_surface()
    local s = state()
    local surface = s.current_surface_name and game.surfaces[s.current_surface_name]
    if surface and surface.valid then return surface end
    surface = game.surfaces["nauvis"]
    if surface and surface.valid then
        s.current_surface_name = surface.name
        return surface
    end
    for _, candidate in pairs(game.surfaces) do
        if candidate and candidate.valid and not candidate.name:find("^the%-cave%-train%-interior%-") then
            s.current_surface_name = candidate.name
            return candidate
        end
    end
    return nil
end

local function ensure_outpost_center(surface)
    local s = state()
    if s.outpost_center and surface and surface.valid and surface.name == s.current_surface_name then
        return s.outpost_center
    end
    local center = find_any_main_train_center(surface) or { x = 0, y = 12 }
    center = { x = math.floor(center.x + 0.5), y = math.floor(center.y + 0.5) }
    s.outpost_center = center
    return center
end

local function print_all(msg)
    if not game then return end
    if type(msg) ~= "string" and type(msg) ~= "table" then msg = tostring(msg) end
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid then player.print(msg) end
    end
end

local function play_alarm()
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid then
            pcall(function() player.play_sound { path = "utility/console_message" } end)
        end
    end
end


local TRAIN_POWER_CAPACITY_MJ = { 6000, 8000, 12000, 16000, 20000, 25000 }
local TRAIN_BATTERY_TECH_PREFIX_FOR_HUD = "the-cave-train-battery-upgrade-"

local function researched_train_battery_level(force)
    if not (force and force.valid and force.technologies) then return 0 end
    local level = 0
    for i = 1, #TRAIN_POWER_CAPACITY_MJ do
        local tech = force.technologies[TRAIN_BATTERY_TECH_PREFIX_FOR_HUD .. i]
        if tech and tech.researched then level = i end
    end
    return level
end

local function main_train_capacity_for_hud(force)
    local ok, capacity = pcall(function()
        if train_interiors and train_interiors._main_train_capacity then
            return train_interiors._main_train_capacity(force)
        end
    end)
    if ok and tonumber(capacity) then return tonumber(capacity) end
    return 3
end

local function prune_main_train_storage(external_surface_name)
    local tsi = storage.the_cave_train_interiors
    if not (tsi and tsi.main_train_units) then return end
    tsi.wagons = tsi.wagons or {}
    for unit in pairs(tsi.main_train_units) do
        local wagon = tsi.wagons[unit]
        local entity = wagon and wagon.entity
        local remove = not valid(entity)
        if not remove and external_surface_name and entity.surface and entity.surface.valid then
            local is_interior = train_interiors and train_interiors.is_train_surface and train_interiors.is_train_surface(entity.surface)
            if not is_interior and entity.surface.name ~= external_surface_name then remove = true end
        end
        if remove then
            tsi.main_train_units[unit] = nil
        end
    end
end

local function main_train_info(force)
    local current_name = state().current_surface_name
    prune_main_train_storage(current_name)
    local tsi = storage.the_cave_train_interiors or {}
    local counts = { total = 0, locomotive = 0, cargo = 0, fluid = 0, artillery = 0 }
    for unit in pairs(tsi.main_train_units or {}) do
        local wagon = tsi.wagons and tsi.wagons[unit]
        local entity = wagon and wagon.entity
        if valid(entity) then
            counts.total = counts.total + 1
            if entity.type == "locomotive" then counts.locomotive = counts.locomotive + 1
            elseif entity.type == "cargo-wagon" then counts.cargo = counts.cargo + 1
            elseif entity.type == "fluid-wagon" then counts.fluid = counts.fluid + 1
            elseif entity.type == "artillery-wagon" then counts.artillery = counts.artillery + 1
            end
        end
    end
    counts.capacity = main_train_capacity_for_hud(force)
    return counts
end

local function train_battery_text_for_hud(force)
    local level = researched_train_battery_level(force)
    if level <= 0 then return "Battery: Not Installed" end
    local capacity_mj = TRAIN_POWER_CAPACITY_MJ[level] or 0
    local tsi = storage.the_cave_train_interiors or {}
    local energy_j = 0
    for _, record in pairs(tsi.train_power or {}) do
        energy_j = energy_j + (tonumber(record and record.energy) or 0)
    end
    local energy_mj = math.floor((energy_j / 1000000) + 0.5)
    local pct = capacity_mj > 0 and math.floor((energy_mj * 100 / capacity_mj) + 0.5) or 0
    return "Battery: Level " .. tostring(level) .. " (" .. tostring(energy_mj) .. " / " .. tostring(capacity_mj) .. " MJ, " .. tostring(pct) .. "%)"
end

local function style_info_label(label)
    if not (label and label.valid and label.style) then return end
    pcall(function()
        label.style.font = "default-large"
        label.style.font_color = { 1, 1, 1 }
        label.style.bottom_margin = 2
        -- Keep info rows compact; do not let labels force a full-screen panel.
        pcall(function() label.style.single_line = true end)
    end)
end

local function add_info_label(parent, name)
    local label = parent.add { type = "label", name = name, caption = "" }
    style_info_label(label)
    return label
end

local function valid_gui_row(parent, name)
    local row = parent and parent.valid and parent[name]
    return row and row.valid
end

local function style_info_panel(panel)
    if not (panel and panel.valid and panel.style) then return end
    pcall(function()
        panel.style.padding = 8
        panel.style.vertical_spacing = 3
        panel.style.font = "default-large-bold"

        -- Compact popup panel width. Without these limits Factorio can stretch
        -- the info frame across the whole top GUI, leaving a large empty area.
        panel.style.minimal_width = 420
        panel.style.maximal_width = 560
        pcall(function() panel.style.natural_width = 520 end)
        pcall(function() panel.style.horizontally_stretchable = false end)
        pcall(function() panel.style.horizontally_squashable = true end)
    end)
    for _, child in pairs(panel.children or {}) do
        style_info_label(child)
    end
end

local function style_top_hud_bar(header)
    if not (header and header.valid and header.style) then return end
    pcall(function()
        header.style.minimal_height = 56
        header.style.maximal_height = 56
        header.style.padding = 8
        header.style.horizontal_spacing = 14
        header.style.vertically_stretchable = false
    end)
end

local function style_top_hud_button(button)
    if not (button and button.valid and button.style) then return end
    pcall(function()
        button.style.minimal_height = 38
        button.style.minimal_width = 125
        button.style.left_padding = 12
        button.style.right_padding = 12
        button.style.font = "default-bold"
    end)
end

local function style_top_hud_label(label, minimal_width)
    if not (label and label.valid and label.style) then return end
    pcall(function()
        label.style.font = "default-large-bold"
        label.style.font_color = { 1, 1, 1 }
        label.style.left_margin = 8
        label.style.right_margin = 6
        label.style.top_margin = 9
        if minimal_width then label.style.minimal_width = minimal_width end
    end)
end

local function style_top_hud(header)
    if not (header and header.valid) then return end
    style_top_hud_bar(header)
    style_top_hud_button(header[GUI_BUTTON])
    style_top_hud_button(header[GUI_CAVE_INFO_BUTTON])
    style_top_hud_button(header[GUI_TRAIN_INFO_BUTTON])
    style_top_hud_label(header[GUI_STATUS], 300)
    style_top_hud_label(header[GUI_ATTACK_WAVE], 180)
    style_top_hud_label(header[GUI_NEXT_ATTACK], 220)
    style_top_hud_label(header[GUI_EXTRA], 160)
end

local function update_player_gui(player)
    if not (player and player.valid) then return end
    if not cavetorio_enabled() then
        destroy_player_gui(player)
        return
    end
    local s = state()
    local top = player.gui and player.gui.top
    local screen = player.gui and player.gui.screen
    if not (top and screen) then return end

    local flow = top[GUI_FLOW]
    local function rebuild()
        if flow and flow.valid then flow.destroy() end
        flow = top.add { type = "flow", name = GUI_FLOW, direction = "vertical" }
        local header = flow.add { type = "frame", name = GUI_HEADER, direction = "horizontal" }
        header.add { type = "button", name = GUI_BUTTON, caption = "Manual Warp" }
        header.add { type = "button", name = GUI_CAVE_INFO_BUTTON, caption = "Cave Info" }
        header.add { type = "button", name = GUI_TRAIN_INFO_BUTTON, caption = "Main Train Info" }
        header.add { type = "label", name = GUI_STATUS, caption = "" }
        header.add { type = "label", name = GUI_ATTACK_WAVE, caption = "" }
        header.add { type = "label", name = GUI_NEXT_ATTACK, caption = "" }
        header.add { type = "label", name = GUI_EXTRA, caption = "" }
        style_top_hud(header)

        -- The expanded info panels must live in player.gui.screen, not in
        -- player.gui.top. Top GUI elements are stretched by Factorio's top bar,
        -- which caused Cave Info / Main Train Info to become full-screen-wide.
        local old_cave_panel = screen[GUI_CAVE_PANEL]
        if old_cave_panel and old_cave_panel.valid then old_cave_panel.destroy() end
        local old_train_panel = screen[GUI_TRAIN_PANEL]
        if old_train_panel and old_train_panel.valid then old_train_panel.destroy() end

        local cave_panel = screen.add { type = "frame", name = GUI_CAVE_PANEL, caption = "Cave Info", direction = "vertical" }
        pcall(function() cave_panel.location = { x = 8, y = 70 } end)
        style_info_panel(cave_panel)
        add_info_label(cave_panel, GUI_CAVE_ROWS.warp)
        add_info_label(cave_panel, GUI_CAVE_ROWS.zone)
        add_info_label(cave_panel, GUI_CAVE_ROWS.region)
        add_info_label(cave_panel, GUI_CAVE_ROWS.nightmare_depth)
        add_info_label(cave_panel, GUI_CAVE_ROWS.time_left)
        add_info_label(cave_panel, GUI_CAVE_ROWS.lighting)
        add_info_label(cave_panel, GUI_CAVE_ROWS.resources)
        add_info_label(cave_panel, GUI_CAVE_ROWS.cave_difficulty)
        add_info_label(cave_panel, GUI_CAVE_ROWS.research_difficulty)
        add_info_label(cave_panel, GUI_CAVE_ROWS.digging)
        add_info_label(cave_panel, GUI_CAVE_ROWS.ore_protection)
        add_info_label(cave_panel, GUI_CAVE_ROWS.ore_missing)
        add_info_label(cave_panel, GUI_CAVE_ROWS.mixed_resources)

        local train_panel = screen.add { type = "frame", name = GUI_TRAIN_PANEL, caption = "Main Train Info", direction = "vertical" }
        pcall(function() train_panel.location = { x = 8, y = 70 } end)
        style_info_panel(train_panel)
        add_info_label(train_panel, GUI_TRAIN_ROWS.train_parts)
        add_info_label(train_panel, GUI_TRAIN_ROWS.locomotives)
        add_info_label(train_panel, GUI_TRAIN_ROWS.cargo_wagons)
        add_info_label(train_panel, GUI_TRAIN_ROWS.fluid_wagons)
        add_info_label(train_panel, GUI_TRAIN_ROWS.artillery_wagons)
        add_info_label(train_panel, GUI_TRAIN_ROWS.outpost_size)
        add_info_label(train_panel, GUI_TRAIN_ROWS.safety_ring)
        add_info_label(train_panel, GUI_TRAIN_ROWS.warp_time)
        add_info_label(train_panel, GUI_TRAIN_ROWS.battery)
    end

    local must_rebuild = false
    if not (flow and flow.valid) then
        must_rebuild = true
    else
        local header = flow[GUI_HEADER]
        if not (header and header.valid and header.type == "frame" and header[GUI_BUTTON] and header[GUI_CAVE_INFO_BUTTON] and header[GUI_TRAIN_INFO_BUTTON] and header[GUI_STATUS] and header[GUI_ATTACK_WAVE] and header[GUI_NEXT_ATTACK] and header[GUI_EXTRA]) then
            must_rebuild = true
        end
        -- If old full-width top-bar panels exist, rebuild and move them to
        -- player.gui.screen.
        if flow[GUI_CAVE_PANEL] or flow[GUI_TRAIN_PANEL] then
            must_rebuild = true
        end
        local cave_panel = screen[GUI_CAVE_PANEL]
        local train_panel = screen[GUI_TRAIN_PANEL]
        if not (cave_panel and cave_panel.valid and train_panel and train_panel.valid) then
            must_rebuild = true
        else
            for _, row_name in pairs(GUI_CAVE_ROWS) do
                if not valid_gui_row(cave_panel, row_name) then must_rebuild = true break end
            end
            for _, row_name in pairs(GUI_TRAIN_ROWS) do
                if not valid_gui_row(train_panel, row_name) then must_rebuild = true break end
            end
        end
    end
    if must_rebuild then rebuild() end

    local header = flow[GUI_HEADER]
    style_top_hud(header)
    local button = header[GUI_BUTTON]
    local status = header[GUI_STATUS]
    local attack_wave_label = header[GUI_ATTACK_WAVE]
    local next_attack_label = header[GUI_NEXT_ATTACK]
    local extra = header[GUI_EXTRA]
    local cave_panel = screen[GUI_CAVE_PANEL]
    local train_panel = screen[GUI_TRAIN_PANEL]
    style_info_panel(cave_panel)
    style_info_panel(train_panel)
    pcall(function() cave_panel.location = { x = 8, y = 70 } end)
    pcall(function() train_panel.location = { x = 8, y = 70 } end)

    local force = player_force()
    local size_def, size_level = outpost_size(force)
    local tdef, time_level = outpost_time(force)
    local profile = s.surface_profiles[s.current_surface_name] or {}
    local now = game.tick or 0
    local left = s.next_auto_warp_tick and (s.next_auto_warp_tick - now) or (tdef.minutes * TICKS_PER_MINUTE)
    local left_text = format_time(left)
    local manual_cooldown_left = (s.manual_cooldown_until or 0) - now
    if manual_cooldown_left > 0 then
        status.caption = string.format("  Warp #%d    |    Zone: %s    |    Warp Cooldown: %s  ",
            s.warp_number or 1, display_profile_value(profile.zone or "Easy"), format_time(manual_cooldown_left))
        attack_wave_label.caption = "    |    Attack Wave: Off  "
        next_attack_label.caption = ""
    else
        status.caption = string.format("  Warp #%d    |    Zone: %s    |    Time: %s  ",
            s.warp_number or 1, display_profile_value(profile.zone or "Easy"), left_text)
        local attack_wave_text, next_attack_text = safety_ring_hud_text(force, now)
        attack_wave_label.caption = attack_wave_text
        next_attack_label.caption = next_attack_text
    end

    if s.manual_countdown_until then
        button.caption = "Warp Starting"
        button.enabled = false
    elseif now < (s.manual_cooldown_until or 0) then
        button.caption = "Warp Cooldown"
        button.enabled = false
    else
        button.caption = "Manual Warp"
        button.enabled = true
    end

    if s.manual_countdown_until then
        extra.caption = " Manual Warp in: " .. format_time(s.manual_countdown_until - now)
    elseif now < (s.manual_cooldown_until or 0) then
        extra.caption = ""
    elseif s.manual_votes and next(s.manual_votes) then
        local votes = 0
        for _ in pairs(s.manual_votes) do votes = votes + 1 end
        local required = math.floor(#game.connected_players / 2) + 1
        extra.caption = " Votes: " .. votes .. "/" .. required
    else
        extra.caption = ""
    end

    local mode = s.gui_mode[player.index]
    cave_panel.visible = mode == "cave"
    train_panel.visible = mode == "train"

    cave_panel[GUI_CAVE_ROWS.warp].caption = "Warp: #" .. tostring(s.warp_number or 1)
    cave_panel[GUI_CAVE_ROWS.zone].caption = "Zone: " .. display_profile_value(profile.zone or "Easy")
    cave_panel[GUI_CAVE_ROWS.region].caption = "Region: " .. display_profile_value(profile.region or "Normal Cave")
    local show_depth = (profile.zone == "Nightmare") or (profile.region and profile.region ~= "Normal Cave")
    cave_panel[GUI_CAVE_ROWS.nightmare_depth].visible = show_depth
    cave_panel[GUI_CAVE_ROWS.nightmare_depth].caption = "Nightmare Depth: " .. tostring(math.floor(tonumber(profile.distance) or 0)) .. " tiles"
    cave_panel[GUI_CAVE_ROWS.time_left].caption = "Time Left: " .. left_text .. " / " .. tostring(tdef.minutes) .. " min"
    cave_panel[GUI_CAVE_ROWS.lighting].caption = "Lighting: " .. display_profile_value(profile.lighting or "normal")
    cave_panel[GUI_CAVE_ROWS.resources].caption = "Resource Level: " .. resource_level_text(profile)
    cave_panel[GUI_CAVE_ROWS.cave_difficulty].caption = "Cave Difficulty: " .. display_profile_value(profile.cave_difficulty or "easy")
    cave_panel[GUI_CAVE_ROWS.research_difficulty].caption = "Research Difficulty: " .. display_profile_value(profile.research_level_difficulty or "medium")
    cave_panel[GUI_CAVE_ROWS.digging].caption = "Digging: " .. display_profile_value(profile.digging_mode or "disabled")
    cave_panel[GUI_CAVE_ROWS.ore_protection].caption = "Ore Protection: " .. display_profile_value(profile.ore_patch_protection or "Disabled")
    cave_panel[GUI_CAVE_ROWS.ore_missing].caption = "Ore Missing: " .. display_profile_value(profile.ore_patch_missing or "Disabled")
    cave_panel[GUI_CAVE_ROWS.mixed_resources].caption = "Mixed Resources: " .. display_profile_value(profile.mixed_resource_patches or "Enabled")

    local counts = main_train_info(force)
    train_panel[GUI_TRAIN_ROWS.train_parts].caption = "Train Parts: " .. tostring(counts.total) .. " / " .. tostring(counts.capacity)
    train_panel[GUI_TRAIN_ROWS.locomotives].caption = "Locomotives: " .. tostring(counts.locomotive)
    train_panel[GUI_TRAIN_ROWS.cargo_wagons].caption = "Cargo Wagons: " .. tostring(counts.cargo)
    train_panel[GUI_TRAIN_ROWS.fluid_wagons].caption = "Fluid Wagons: " .. tostring(counts.fluid)
    train_panel[GUI_TRAIN_ROWS.artillery_wagons].caption = "Artillery Wagons: " .. tostring(counts.artillery)
    train_panel[GUI_TRAIN_ROWS.outpost_size].caption = "Outpost Size: " .. tostring(size_def.label) .. " (Expansion " .. tostring(size_level) .. ")"
    local ring_def, ring_level = safety_ring(force)
    local ring_attack = ring_level > 0 and "Attack cooldown: 1 min" or "Attacks: Off"
    train_panel[GUI_TRAIN_ROWS.safety_ring].caption = "Safety Ring: " .. tostring(ring_def.label) .. " (Upgrade " .. tostring(ring_level) .. ", " .. ring_attack .. ")"
    train_panel[GUI_TRAIN_ROWS.warp_time].caption = "Warp Time: " .. tostring(tdef.minutes) .. " min (Time Upgrade " .. tostring(time_level) .. ")"
    train_panel[GUI_TRAIN_ROWS.battery].caption = train_battery_text_for_hud(force)
end
local function refresh_gui()
    for _, player in pairs(game.players or {}) do update_player_gui(player) end
end

local function lighting_mode_for_surface(surface)
    local s = state()
    local profile = surface and surface.valid and s.surface_profiles[surface.name]
    return profile and profile.lighting or nil
end

function warp_outpost.get_lighting_mode(surface)
    if not cavetorio_enabled() then return nil end
    return lighting_mode_for_surface(surface)
end

local function random_pick(rng, list)
    return list[rng(1, #list)]
end

local function allowed_zones(warp_number)
    if warp_number <= 10 then return { "Easy" } end
    if warp_number <= 24 then return { "Easy", "Medium" } end
    if warp_number <= 59 then return { "Easy", "Medium", "Hard" } end
    return { "Easy", "Medium", "Hard", "Nightmare" }
end

local function rng_for(warp_number)
    local seed = (game and game.default_map_gen_settings and game.default_map_gen_settings.seed) or 0
    local n = (seed + warp_number * 1103515245 + (game.tick or 0)) % 2147483647
    return function(min, max)
        n = (n * 1664525 + 1013904223) % 4294967296
        local v = min + (n % (max - min + 1))
        return v
    end
end

local function random_bool(rng) return rng(1, 100) <= 50 and "Enabled" or "Disabled" end

local function build_profile(warp_number)
    local rng = rng_for(warp_number)
    local zone = random_pick(rng, allowed_zones(warp_number))
    local region = "Normal Cave"
    local distance = 150
    if zone == "Easy" then distance = rng(90, 260)
    elseif zone == "Medium" then distance = rng(320, 660)
    elseif zone == "Hard" then distance = rng(720, 980)
    else
        distance = 1000 + math.max(0, warp_number - 60) * 10
        local regions = { "Near Gleba", "Near Vulcanus", "Near Fulgora", "Near Aquilo" }
        region = random_pick(rng, regions)
    end

    local digging_by_zone = {
        Easy = { "disabled", "digging-1" },
        Medium = { "digging-1", "digging-2" },
        Hard = { "digging-2", "digging-3" },
        Nightmare = { "digging-3", "digging-4", "hardcore" },
    }
    local resource_by_zone = {
        Easy = { "level-2", "level-3", "level-4" },
        Medium = { "level-1", "level-2", "level-3" },
        Hard = { "level-1", "level-2" },
        Nightmare = { "level-1" },
    }
    local cave_difficulty_by_zone = {
        Easy = { "easy" },
        Medium = { "easy", "medium" },
        Hard = { "medium", "hard" },
        Nightmare = { "hard", "nightmare" },
    }
    local research_by_zone = {
        Easy = { "very-easy", "easy", "medium" },
        Medium = { "easy", "medium" },
        Hard = { "medium", "hard" },
        Nightmare = { "hard", "very-hard", "marathon" },
    }

    local digging_mode = random_pick(rng, digging_by_zone[zone] or digging_by_zone.Easy)
    local profile = {
        zone = zone,
        region = region,
        distance = distance,
        lighting = random_pick(rng, LIGHTING_OPTIONS),
        mixed_resource_patches = random_bool(rng),
        ore_patch_missing = zone == "Easy" and "Disabled" or random_bool(rng),
        ore_blood = random_bool(rng),
        digging_mode = digging_mode,
        ore_patch_protection = zone == "Easy" and "Disabled" or random_bool(rng),
        research_level_difficulty = random_pick(rng, research_by_zone[zone] or research_by_zone.Easy),
        resource_level = digging_mode ~= "disabled" and "disabled" or random_pick(rng, resource_by_zone[zone] or resource_by_zone.Easy),
        cave_difficulty = random_pick(rng, cave_difficulty_by_zone[zone] or cave_difficulty_by_zone.Easy),
    }
    return profile
end


local function prune_safety_ring_units(sr)
    local active = {}
    for _, unit in pairs(sr.active_units or {}) do
        if valid(unit) then active[#active + 1] = unit end
    end
    sr.active_units = active
    return #active
end

local function safety_ring_reset_wave_state()
    local s = state()
    s.safety_ring.active_units = {}
    s.safety_ring.pending_mini_waves = {}
    s.safety_ring.cooldown_until = nil
    s.safety_ring.current_wave_number = nil
    s.safety_ring.current_wave_total = 0
    s.safety_ring.current_wave_started_tick = nil
    s.safety_ring.rest_until = nil
    s.safety_ring.rest_wave_number = nil
    s.safety_ring.current_wave_boss = false
end

local function safety_ring_corner_positions(center, size, gap)
    local left, top, right, bottom = rect_bounds(center, size)
    local inset = 4
    return {
        NE = { x = right + gap - inset, y = top - gap + inset },
        NW = { x = left - gap + inset, y = top - gap + inset },
        SE = { x = right + gap - inset, y = bottom + gap - inset },
        SW = { x = left - gap + inset, y = bottom + gap - inset },
    }
end

local function safety_ring_pick_corners(rng, count)
    local pool = { "NE", "NW", "SE", "SW" }
    local picked = {}
    count = math.max(1, math.min(4, tonumber(count) or 1))
    for i = 1, count do
        local index = rng(1, #pool)
        picked[#picked + 1] = pool[index]
        table.remove(pool, index)
    end
    return picked
end

local function safety_ring_all_corners()
    return { "NE", "NW", "SE", "SW" }
end

local function safety_ring_command_unit(unit, target, radius)
    if not valid(unit) then return false end
    local command = {
        type = defines.command.attack_area,
        destination = target,
        radius = radius,
        distraction = defines.distraction.by_enemy,
    }
    local ok = false
    pcall(function()
        if unit.commandable and unit.commandable.valid then
            unit.commandable.set_command(command)
            ok = true
        end
    end)
    if not ok then
        pcall(function()
            if unit.set_command then
                unit.set_command(command)
                ok = true
            end
        end)
    end
    return ok
end

local function safety_ring_spawn_one(surface, name, position, target, attack_radius)
    if not (surface and surface.valid and prototypes and prototypes.entity and prototypes.entity[name]) then return nil end
    local p = surface.find_non_colliding_position(name, position, 12, 1)
        or surface.find_non_colliding_position(name, position, 24, 2)
    if not p then return nil end
    local unit
    local ok = pcall(function()
        unit = surface.create_entity {
            name = name,
            position = p,
            force = game.forces.enemy,
            create_build_effect_smoke = false,
        }
    end)
    if not ok or not valid(unit) then return nil end
    pcall(function()
        if unit.ai_settings then unit.ai_settings.allow_destroy_when_commands_fail = false end
    end)
    safety_ring_command_unit(unit, target, attack_radius)
    return unit
end

local function safety_ring_spawn_corner(surface, corner_pos, mini_def, target, attack_radius)
    local spawned = {}
    for name, count in pairs(mini_def.counts or {}) do
        local n = tonumber(count) or 0
        for _ = 1, n do
            local unit = safety_ring_spawn_one(surface, name, corner_pos, target, attack_radius)
            if valid(unit) then spawned[#spawned + 1] = unit end
        end
    end
    return spawned
end

local function safety_ring_spawn_mini_wave(level, mini_def, forced_corners)
    if not cavetorio_enabled() then return 0 end
    local surface = current_surface()
    if not (surface and surface.valid) then return 0 end
    local force = player_force()
    local size_def = outpost_size(force)
    local ring_def = SAFETY_RING_LEVELS[level] or SAFETY_RING_LEVELS[0]
    if not ring_def or not ring_def.cooldown_minutes then return 0 end
    local center = ensure_outpost_center(surface)
    local gap = tonumber(ring_def.radius) or OUTPOST_CLEAR_RING
    local positions = safety_ring_corner_positions(center, size_def, gap)
    local rng = rng_for((state().warp_number or 1) * 1000 + (game.tick or 0) + level * 17)
    local corners = forced_corners or safety_ring_pick_corners(rng, mini_def.corners or 1)
    local attack_radius = math.max(32, math.ceil(math.max(size_def.width or 25, size_def.height or 25) / 2) + 8)
    local sr = state().safety_ring
    local created = 0
    for _, key in pairs(corners) do
        local pos = positions[key]
        if pos then
            local units = safety_ring_spawn_corner(surface, pos, mini_def, center, attack_radius)
            for _, unit in pairs(units) do
                sr.active_units[#sr.active_units + 1] = unit
                created = created + 1
            end
        end
    end
    sr.current_wave_total = (tonumber(sr.current_wave_total) or 0) + created
    return created
end

local function safety_ring_start_rest_wave(sr, wave_number)
    sr.wave_number = wave_number
    sr.current_wave_number = nil
    sr.current_wave_total = 0
    sr.current_wave_started_tick = nil
    sr.current_wave_boss = false
    sr.active_units = {}
    sr.pending_mini_waves = {}
    sr.cooldown_until = nil
    sr.rest_wave_number = wave_number
    sr.rest_until = (game.tick or 0) + SAFETY_RING_REST_TICKS
    print_all("[The Cave] Safety Ring rest wave #" .. tostring(wave_number) .. " started. Attacks are paused for 5 minutes.")
end

local function safety_ring_start_attack_cycle(level)
    local wave_defs = SAFETY_RING_WAVES[level]
    if not wave_defs or not wave_defs[1] then return 0 end
    local sr = state().safety_ring
    local wave_number = (tonumber(sr.wave_number) or 0) + 1
    if wave_number % SAFETY_RING_REST_EVERY_WAVES == 0 then
        safety_ring_start_rest_wave(sr, wave_number)
        return 0
    end

    local is_boss = (wave_number % SAFETY_RING_BOSS_EVERY_WAVES == 0)
    sr.pending_mini_waves = {}
    sr.active_units = {}
    sr.current_wave_total = 0
    sr.current_wave_started_tick = game.tick or 0
    sr.current_wave_number = wave_number
    sr.current_wave_boss = is_boss
    sr.rest_until = nil
    sr.rest_wave_number = nil

    local forced_corners = is_boss and safety_ring_all_corners() or nil
    local created = safety_ring_spawn_mini_wave(level, wave_defs[1], forced_corners)
    if #wave_defs > 1 then
        for i = 2, #wave_defs do
            sr.pending_mini_waves[#sr.pending_mini_waves + 1] = {
                tick = (game.tick or 0) + (i - 1) * 30 * TICKS_PER_SECOND,
                level = level,
                index = i,
                boss = is_boss,
            }
        end
    end
    if created > 0 then
        sr.wave_number = wave_number
        if is_boss then
            print_all("[The Cave] WARNING: Safety Ring boss wave #" .. tostring(wave_number) .. " started. Enemies are attacking from all directions.")
        else
            print_all("[The Cave] Safety Ring attack wave #" .. tostring(wave_number) .. " started. Enemies are moving toward the Warp Outpost.")
        end
    else
        sr.current_wave_number = nil
        sr.current_wave_total = 0
        sr.current_wave_started_tick = nil
        sr.current_wave_boss = false
    end
    return created
end

local function safety_ring_process_pending_mini_waves(sr)
    local pending = {}
    local now = game.tick or 0
    for _, entry in pairs(sr.pending_mini_waves or {}) do
        if now >= (entry.tick or 0) then
            local defs = SAFETY_RING_WAVES[entry.level or 0]
            local def = defs and defs[entry.index or 0]
            if def then
                local forced = entry.boss and safety_ring_all_corners() or nil
                safety_ring_spawn_mini_wave(entry.level, def, forced)
            end
        else
            pending[#pending + 1] = entry
        end
    end
    sr.pending_mini_waves = pending
end

local function safety_ring_current_wave_cleared(sr, active_count)
    local total = tonumber(sr.current_wave_total) or 0
    if total <= 0 then return active_count <= 0 end
    local remaining_allowed = math.floor((total * (1 - SAFETY_RING_KILL_RATIO_TO_CLEAR)) + 0.0001)
    return active_count <= remaining_allowed
end

local function safety_ring_ignore_current_wave_and_start_cooldown(sr, ring_def)
    sr.active_units = {}
    sr.pending_mini_waves = {}
    sr.current_wave_number = nil
    sr.current_wave_total = 0
    sr.current_wave_started_tick = nil
    sr.current_wave_boss = false
    sr.cooldown_until = (game.tick or 0) + (tonumber(ring_def.cooldown_minutes) or 1) * TICKS_PER_MINUTE
end

local function process_safety_ring_waves()
    if not cavetorio_enabled() then return end
    local force = player_force()
    local ring_def, level = safety_ring(force)
    local sr = state().safety_ring
    sr.last_level = level
    if level <= 0 or not ring_def.cooldown_minutes then
        sr.cooldown_until = nil
        sr.pending_mini_waves = {}
        sr.active_units = {}
        sr.current_wave_number = nil
        sr.current_wave_total = 0
        sr.current_wave_started_tick = nil
        sr.rest_until = nil
        sr.rest_wave_number = nil
        sr.current_wave_boss = false
        return
    end

    local now = game.tick or 0
    if sr.rest_until then
        if now < sr.rest_until then return end
        sr.rest_until = nil
        sr.rest_wave_number = nil
        sr.cooldown_until = nil
        safety_ring_start_attack_cycle(level)
        return
    end

    safety_ring_process_pending_mini_waves(sr)
    local active_count = prune_safety_ring_units(sr)
    local pending_count = #(sr.pending_mini_waves or {})
    if active_count > 0 or pending_count > 0 then
        local started = tonumber(sr.current_wave_started_tick) or now
        if pending_count == 0 and safety_ring_current_wave_cleared(sr, active_count) then
            safety_ring_ignore_current_wave_and_start_cooldown(sr, ring_def)
            return
        end
        if now - started >= SAFETY_RING_WAVE_TIMEOUT_TICKS then
            safety_ring_ignore_current_wave_and_start_cooldown(sr, ring_def)
            return
        end
        return
    end

    if not sr.cooldown_until then
        sr.cooldown_until = now + (tonumber(ring_def.cooldown_minutes) or 1) * TICKS_PER_MINUTE
        return
    end
    if now >= sr.cooldown_until then
        sr.cooldown_until = nil
        safety_ring_start_attack_cycle(level)
    end
end

local function profile_destination(profile)
    local d = math.floor(profile.distance or 150)
    if profile.region == "Near Fulgora" then return { x = d, y = 0 } end
    if profile.region == "Near Vulcanus" then return { x = -d, y = 0 } end
    if profile.region == "Near Gleba" then return { x = 0, y = d } end
    if profile.region == "Near Aquilo" then return { x = 0, y = -d } end
    local zone = profile.zone or "Easy"
    if zone == "Medium" then return { x = d, y = 0 } end
    if zone == "Hard" then return { x = -d, y = 0 } end
    return { x = 0, y = d }
end

local function ensure_surface(name)
    local existing = game.surfaces[name]
    if existing and existing.valid then return existing end

    -- Use a deliberately empty map-gen profile for warp surfaces. The cave
    -- world system and the landing cleanup build the actual playable area.
    local mg = {
        width = 0,
        height = 0,
        autoplace_settings = {
            entity = { settings = {}, treat_missing_as_default = false },
            decorative = { settings = {}, treat_missing_as_default = false },
            tile = { settings = {}, treat_missing_as_default = true },
        },
        cliff_settings = { name = "cliff", cliff_elevation_0 = 1024, cliff_elevation_interval = 10, richness = 0 },
    }
    local nauvis = game.surfaces["nauvis"]
    pcall(function()
        if nauvis and nauvis.valid and nauvis.map_gen_settings and nauvis.map_gen_settings.seed then
            mg.seed = nauvis.map_gen_settings.seed + #game.surfaces + 1000
        end
    end)
    local ok, surface = pcall(function() return game.create_surface(name, mg) end)
    if ok then return surface end
    return nil
end

local function clean_destination_footprint(surface, center, size)
    local left, top, right, bottom = rect_bounds(center, size)

    -- The destination must look like The Cave, not like a normal outside map.
    -- Clear a generous visible buffer to void, then restore only the Outpost
    -- footprint and its mineable rock border. This also prevents ore/water/lava
    -- or Ore Patch Protection from deleting the imported base.
    local buffer = math.max(196, math.ceil(math.max(size.width, size.height) / 2) + safety_ring_radius(player_force()) + 48)
    local clear_left, clear_top = left - buffer, top - buffer
    local clear_right, clear_bottom = right + buffer, bottom + buffer
    local chunk_radius = math.max(6, math.ceil((math.max(size.width, size.height) + buffer * 2) / 64) + 2)
    surface.request_to_generate_chunks(center, chunk_radius)
    surface.force_generate_chunk_requests()

    local clear_area = area_from_bounds(clear_left, clear_top, clear_right, clear_bottom)
    for _, entity in pairs(surface.find_entities_filtered { area = clear_area }) do
        if valid(entity) and entity.type ~= "character" then
            pcall(function() entity.destroy { raise_destroy = false } end)
        end
    end
    pcall(function() surface.destroy_decoratives { area = clear_area } end)

    local tiles = {}
    for x = clear_left, clear_right do
        for y = clear_top, clear_bottom do
            tiles[#tiles + 1] = { name = "out-of-map", position = { x = x, y = y } }
            if #tiles >= 4096 then
                pcall(function() surface.set_tiles(tiles, true, false, true, true) end)
                tiles = {}
            end
        end
    end
    if #tiles > 0 then pcall(function() surface.set_tiles(tiles, true, false, true, true) end) end
end

local function snapshot_tiles(surface, left, top, right, bottom)
    local tiles = {}
    for x = left, right - 1 do
        for y = top, bottom - 1 do
            local name = "dirt-1"
            pcall(function() name = surface.get_tile(x, y).name end)
            tiles[#tiles + 1] = { name = name, rel_x = x - left, rel_y = y - top }
        end
    end
    return tiles
end

local function paste_tiles(surface, dest_left, dest_top, tile_snapshot)
    local tiles = {}
    for _, t in pairs(tile_snapshot or {}) do
        tiles[#tiles + 1] = { name = t.name, position = { x = dest_left + t.rel_x, y = dest_top + t.rel_y } }
    end
    if #tiles > 0 then pcall(function() surface.set_tiles(tiles, true, false, true, true) end) end
end


local seal_outpost_ring

local function clear_outpost_clear_ring(surface, center, size)
    if not (surface and surface.valid and center and size) then return end
    local left, top, right, bottom = rect_bounds(center, size)
    local gap = safety_ring_radius(player_force())
    if gap <= 0 then return end

    local outer_left, outer_top = left - gap, top - gap
    local outer_right, outer_bottom = right + gap, bottom + gap
    local ring_area = area_from_bounds(outer_left, outer_top, outer_right, outer_bottom)

    -- This dynamic Safety Ring replaces the old 50-tile enemy-only safe zone.
    -- It is prepared only during landing/expansion/research and does not delete
    -- attacking enemies later, so normal turret/wall defense still matters.
    -- It must be completely build-safe terrain so border rocks, water, lava,
    -- oil/resource patches, trees, cliffs, or ore-protection effects cannot
    -- appear right beside transferred turrets/flamethrowers/pipes.
    -- Protect already transferred player-owned entities inside the Outpost; the
    -- ring itself is not transferred and is recreated as empty ground.
    for _, entity in pairs(surface.find_entities_filtered { area = ring_area }) do
        if valid(entity) and entity.type ~= "character" and not entity_fully_inside(entity, left, top, right, bottom) then
            local keep_player_building = entity.force and entity.force.valid and entity.force.name == "player" and not is_enemy_entity(entity)
            if not keep_player_building then
                pcall(function() entity.destroy { raise_destroy = false } end)
            end
        end
    end
    pcall(function() surface.destroy_decoratives { area = ring_area } end)

    local floor_tile = "dirt-1"
    local tiles = {}
    for x = outer_left, outer_right - 1 do
        for y = outer_top, outer_bottom - 1 do
            if not (x >= left and x < right and y >= top and y < bottom) then
                tiles[#tiles + 1] = { name = floor_tile, position = { x = x, y = y } }
                if #tiles >= 4096 then
                    pcall(function() surface.set_tiles(tiles, true, false, true, true) end)
                    tiles = {}
                end
            end
        end
    end
    if #tiles > 0 then pcall(function() surface.set_tiles(tiles, true, false, true, true) end) end
end

local function clear_outpost_footprint_for_platform(surface, left, top, right, bottom)
    local area = area_from_bounds(left, top, right, bottom)
    for _, entity in pairs(surface.find_entities_filtered { area = area }) do
        if valid(entity) and entity.type ~= "character" then
            local remove = false
            if is_enemy_entity(entity) then remove = true end
            if entity.force and entity.force.valid and entity.force.name == "neutral" then remove = true end
            if entity.type == "resource" or entity.type == "tree" or entity.type == "simple-entity" or entity.type == "cliff" then remove = true end
            if entity.name == "diggy-rock" or entity.name == "diggy-tree" or entity.name == "diggy-rubble" then remove = true end
            if remove then pcall(function() entity.destroy { raise_destroy = false } end) end
        end
    end
    pcall(function() surface.destroy_decoratives { area = area } end)
end

local function paint_outpost_tiles(surface, center, size)
    local left, top, right, bottom = rect_bounds(center, size)
    clear_outpost_footprint_for_platform(surface, left, top, right, bottom)
    local tile_name = blue_outpost_tile()
    local tiles = {}
    for x = left, right - 1 do
        for y = top, bottom - 1 do
            tiles[#tiles + 1] = { name = tile_name, position = { x = x, y = y } }
            if #tiles >= 4096 then
                pcall(function() surface.set_tiles(tiles, true, false, true, true) end)
                tiles = {}
            end
        end
    end
    if #tiles > 0 then pcall(function() surface.set_tiles(tiles, true, false, true, true) end) end
end


local function reset_initial_landing_to_void(surface, center, size)
    if not (surface and surface.valid and center and size) then return end
    local left, top, right, bottom = rect_bounds(center, size)
    local margin = 32
    local area = area_from_bounds(left - margin, top - margin, right + margin, bottom + margin)

    for _, entity in pairs(surface.find_entities_filtered { area = area }) do
        if valid(entity) and entity.type ~= "character" then
            local keep = entity_fully_inside(entity, left, top, right, bottom) and entity.name ~= "market"
            if not keep then
                pcall(function() entity.destroy { raise_destroy = false } end)
            end
        end
    end
    pcall(function() surface.destroy_decoratives { area = area } end)

    local tiles = {}
    for x = left - margin, right + margin - 1 do
        for y = top - margin, bottom + margin - 1 do
            if not (x >= left and x < right and y >= top and y < bottom) then
                tiles[#tiles + 1] = { name = "out-of-map", position = { x = x, y = y } }
                if #tiles >= 4096 then
                    pcall(function() surface.set_tiles(tiles, true, false, true, true) end)
                    tiles = {}
                end
            end
        end
    end
    if #tiles > 0 then pcall(function() surface.set_tiles(tiles, true, false, true, true) end) end
end

local function apply_current_outpost_footprint(reason)
    if not cavetorio_enabled() then return end
    local surface = current_surface()
    if not (surface and surface.valid) then return end
    local force = player_force()
    local size_def, size_level = outpost_size(force)
    local center = ensure_outpost_center(surface)
    local s = state()
    local initial_nauvis = surface.name == "nauvis" and (tonumber(s.warp_number) or 1) <= 1

    -- Warp #1 is special because the starter train is spawned after on_init.
    -- Normalize twice: first to remove the legacy starter cave, then again
    -- after the starter train pad is placed so no old 40x20 blue floor leaks
    -- beyond the Level 0 25x25 Outpost.
    if initial_nauvis and reason == "init" and not s.initial_landing_normalized then
        reset_initial_landing_to_void(surface, center, size_def)
        s.initial_landing_normalized = true
    elseif initial_nauvis and reason == "player-created" and not s.initial_landing_normalized_after_train then
        reset_initial_landing_to_void(surface, center, size_def)
        s.initial_landing_normalized_after_train = true
    end

    paint_outpost_tiles(surface, center, size_def)
    clear_outpost_clear_ring(surface, center, size_def)
    seal_outpost_ring(surface, center, size_def)
    if reason ~= "player-created" then
        print_all("[The Cave] Warp Outpost footprint updated: " .. tostring(size_def.label) .. " (Expansion " .. tostring(size_level) .. ").")
    end
end

function seal_outpost_ring(surface, center, size)
    if not (prototypes and prototypes.entity and prototypes.entity["diggy-rock"]) then return end
    local left, top, right, bottom = rect_bounds(center, size)
    local force = game.forces.neutral or "neutral"
    local floor_tile = "dirt-1"
    local gap = safety_ring_radius(player_force())

    -- Keep the researched Safety Ring as an empty service/defense ring between
    -- the blue Outpost footprint and the mineable cave-rock border.
    local rock_left = left - gap - 1
    local rock_top = top - gap - 1
    local rock_right = right + gap
    local rock_bottom = bottom + gap

    local function place_wall_tile(x, y)
        for _, e in pairs(surface.find_entities_filtered { area = { { x, y }, { x + 1, y + 1 } } }) do
            if valid(e) and e.type ~= "character" then pcall(function() e.destroy { raise_destroy = false } end) end
        end
        pcall(function() surface.set_tiles({ { name = floor_tile, position = { x = x, y = y } } }, true, false, true, true) end)
        pcall(function() surface.create_entity { name = "diggy-rock", position = { x = x + 0.5, y = y + 0.5 }, force = force, create_build_effect_smoke = false } end)
    end

    for x = rock_left, rock_right do
        place_wall_tile(x, rock_top)
        place_wall_tile(x, rock_bottom)
    end
    for y = rock_top + 1, rock_bottom - 1 do
        place_wall_tile(rock_left, y)
        place_wall_tile(rock_right, y)
    end
end

local function collect_outpost_entities(surface, center, size)
    local left, top, right, bottom = rect_bounds(center, size)
    local entities = {}
    local has_main_train = false
    local tsi = storage.the_cave_train_interiors or {}
    local main_units = tsi.main_train_units or {}
    for _, entity in pairs(surface.find_entities_filtered { area = area_from_bounds(left, top, right, bottom) }) do
        if valid(entity) and entity.type ~= "character" and not is_enemy_entity(entity) and entity_fully_inside(entity, left, top, right, bottom) then
            entities[#entities + 1] = entity
            if entity.unit_number and main_units[entity.unit_number] then has_main_train = true end
        end
    end
    return entities, has_main_train, left, top, right, bottom
end

local function sort_entities_for_teleport(entities)
    table.sort(entities, function(a, b)
        local order = { ["straight-rail"] = 1, ["curved-rail-a"] = 1, ["curved-rail-b"] = 1,
            ["locomotive"] = 3, ["cargo-wagon"] = 3, ["fluid-wagon"] = 3, ["artillery-wagon"] = 3 }
        local oa = order[a.type] or order[a.name] or 2
        local ob = order[b.type] or order[b.name] or 2
        if oa == ob then return (a.unit_number or 0) < (b.unit_number or 0) end
        return oa < ob
    end)
end

local function collect_entity_unit_set(entities)
    local set = {}
    for _, entity in pairs(entities or {}) do
        if valid(entity) and entity.unit_number then set[entity.unit_number] = true end
    end
    return set
end

local function add_wire_snapshot(snapshots, seen, from_entity, from_connector_id, to_entity, to_connector_id, origin)
    if not (valid(from_entity) and valid(to_entity) and from_entity.unit_number and to_entity.unit_number) then return end
    if from_entity.unit_number == to_entity.unit_number and tostring(from_connector_id) == tostring(to_connector_id) then return end

    local a_unit, a_id = from_entity.unit_number, from_connector_id
    local b_unit, b_id = to_entity.unit_number, to_connector_id
    local left_key = tostring(a_unit) .. ":" .. tostring(a_id)
    local right_key = tostring(b_unit) .. ":" .. tostring(b_id)
    if right_key < left_key then
        a_unit, a_id, b_unit, b_id = b_unit, b_id, a_unit, a_id
    end

    local origin_key = tostring(origin or "player")
    local key = tostring(a_unit) .. ":" .. tostring(a_id) .. ">" .. tostring(b_unit) .. ":" .. tostring(b_id) .. ":" .. origin_key
    if seen[key] then return end
    seen[key] = true
    snapshots[#snapshots + 1] = {
        a = a_unit,
        a_connector = a_id,
        b = b_unit,
        b_connector = b_id,
        origin = origin,
    }
end

local function snapshot_wire_connections(entities)
    local units = collect_entity_unit_set(entities)
    local snapshots = {}
    local seen = {}
    for _, entity in pairs(entities or {}) do
        if valid(entity) and entity.unit_number and entity.get_wire_connectors then
            local ok, connectors = pcall(function() return entity.get_wire_connectors(false) end)
            if ok and type(connectors) == "table" then
                for connector_id, connector in pairs(connectors) do
                    if connector and connector.valid then
                        local ok_real, real_connections = pcall(function() return connector.real_connections end)
                        if ok_real and type(real_connections) == "table" then
                            for _, connection in ipairs(real_connections) do
                                local target = connection and connection.target
                                local target_owner = nil
                                local target_connector_id = nil
                                pcall(function() target_owner = target and target.owner end)
                                pcall(function() target_connector_id = target and target.wire_connector_id end)
                                if valid(target_owner) and target_owner.unit_number and units[target_owner.unit_number] and target_connector_id ~= nil then
                                    add_wire_snapshot(snapshots, seen, entity, connector_id, target_owner, target_connector_id, connection.origin)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return snapshots
end

local function restore_wire_connections_now(snapshots, entity_map)
    local restored = 0
    for _, link in pairs(snapshots or {}) do
        local a = entity_map and entity_map[link.a]
        local b = entity_map and entity_map[link.b]
        if valid(a) and valid(b) and a.get_wire_connector and b.get_wire_connector then
            local ok_a, connector_a = pcall(function() return a.get_wire_connector(link.a_connector, true) end)
            local ok_b, connector_b = pcall(function() return b.get_wire_connector(link.b_connector, true) end)
            if ok_a and ok_b and connector_a and connector_a.valid and connector_b and connector_b.valid then
                local ok_connect, did_connect = pcall(function()
                    return connector_a.connect_to(connector_b, false, link.origin)
                end)
                if ok_connect and did_connect then restored = restored + 1 end
            end
        end
    end
    return restored
end

local function queue_wire_restore(snapshots, entity_map)
    if not snapshots or #snapshots == 0 then return end
    local s = state()
    s.pending_wire_restores[#s.pending_wire_restores + 1] = {
        tick = (game.tick or 0) + 1,
        attempts = 0,
        snapshots = snapshots,
        entity_map = entity_map,
    }
end

local function process_pending_wire_restores()
    local s = state()
    local now = game.tick or 0
    local keep = {}
    for _, job in pairs(s.pending_wire_restores or {}) do
        if now >= (job.tick or 0) then
            job.attempts = (job.attempts or 0) + 1
            restore_wire_connections_now(job.snapshots, job.entity_map)
            -- Run twice. Some entities/networks are only stable after one more tick.
            if job.attempts < 2 then
                job.tick = now + 1
                keep[#keep + 1] = job
            end
        else
            keep[#keep + 1] = job
        end
    end
    s.pending_wire_restores = keep
end

local function find_cloned_entity(dest_surface, entity, target, used_units)
    if not (dest_surface and dest_surface.valid and entity and target) then return nil end
    local area = { { target.x - 1.5, target.y - 1.5 }, { target.x + 1.5, target.y + 1.5 } }
    local candidates = dest_surface.find_entities_filtered { area = area, name = entity.name }
    local best, best_dist
    for _, candidate in pairs(candidates or {}) do
        if valid(candidate) and candidate.type == entity.type and (not candidate.unit_number or not used_units[candidate.unit_number]) then
            local dx = (candidate.position.x or 0) - target.x
            local dy = (candidate.position.y or 0) - target.y
            local dist = dx * dx + dy * dy
            if not best or dist < best_dist then
                best = candidate
                best_dist = dist
            end
        end
    end
    return best
end

local function relink_main_train_records(entity_map)
    local tsi = storage.the_cave_train_interiors
    if not (tsi and tsi.wagons and tsi.main_train_units) then return end
    for old_unit, new_entity in pairs(entity_map or {}) do
        if valid(new_entity) and new_entity.unit_number and ROLLING_STOCK_TYPES[new_entity.type] then
            local old_record = tsi.wagons[old_unit]
            local was_main = tsi.main_train_units[old_unit] == true
            local new_unit = new_entity.unit_number
            if old_record then
                if old_unit ~= new_unit then
                    local accidental = tsi.wagons[new_unit]
                    if accidental and accidental ~= old_record then
                        -- A clone/register path may have created an empty replacement record.
                        -- Drop that record so the original interior surface stays attached.
                        tsi.wagons[new_unit] = nil
                    end
                    tsi.wagons[old_unit] = nil
                    tsi.main_train_units[old_unit] = nil
                    if tsi.unclaimed_train_parts then tsi.unclaimed_train_parts[old_unit] = nil end
                end
                old_record.entity = new_entity
                tsi.wagons[new_unit] = old_record
                if was_main then tsi.main_train_units[new_unit] = true end
                if tsi.unclaimed_train_parts then tsi.unclaimed_train_parts[new_unit] = nil end
                if old_record.surface and old_record.surface.valid and tsi.surfaces then tsi.surfaces[old_record.surface.name] = true end
            elseif was_main then
                -- Fallback for a registered unit without an interior record. Keep it registered,
                -- but do not rebuild/replace existing train interiors here.
                tsi.main_train_units[old_unit] = nil
                tsi.main_train_units[new_unit] = true
            end
        end
    end
    prune_main_train_storage()
end

local function transfer_entities(entities, dest_surface, offset)
    sort_entities_for_teleport(entities)
    local moved = 0
    local entity_map = {}
    local used_units = {}
    for _, entity in pairs(entities) do
        if valid(entity) then
            local old_unit = entity.unit_number
            local target = { x = entity.position.x + offset.x, y = entity.position.y + offset.y }
            local new_entity = nil
            local ok = pcall(function() return entity.teleport(target, dest_surface) end)
            if ok and valid(entity) and entity.surface == dest_surface then
                new_entity = entity
                moved = moved + 1
            else
                -- Experimental fallback: clone the entity if direct teleport is not supported.
                local ok_clone, clones = pcall(function()
                    return dest_surface.clone_entities {
                        entities = { entity },
                        destination_offset = offset,
                        destination_surface = dest_surface,
                        snap_to_grid = false,
                    }
                end)
                if ok_clone and type(clones) == "table" then
                    for _, clone in pairs(clones) do
                        if valid(clone) and clone.name == entity.name and clone.type == entity.type then
                            new_entity = clone
                            break
                        end
                    end
                end
                if not valid(new_entity) then
                    new_entity = find_cloned_entity(dest_surface, entity, target, used_units)
                end
                if valid(new_entity) then
                    moved = moved + 1
                    pcall(function() entity.destroy { raise_destroy = false } end)
                end
            end
            if old_unit and valid(new_entity) then
                entity_map[old_unit] = new_entity
                if new_entity.unit_number then used_units[new_entity.unit_number] = true end
            end
        end
    end
    return moved, entity_map
end

local function any_registered_main_train_alive(force)
    local tsi = storage.the_cave_train_interiors
    if not (tsi and tsi.main_train_units and tsi.wagons) then return false end
    for unit in pairs(tsi.main_train_units) do
        local wagon = tsi.wagons[unit]
        if wagon and valid(wagon.entity) and wagon.entity.force == force then return true end
    end
    return false
end

function warp_outpost._update_main_train_defeat_gui(remaining_seconds, force)
    if not game then return end
    local remaining = math.max(0, math.floor(tonumber(remaining_seconds) or 0))
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid and cave_teams.player_force(player) == force and player.gui and player.gui.screen then
            local screen = player.gui.screen
            local frame = screen[MAIN_TRAIN_DEFEAT_GUI]
            if not (frame and frame.valid) then
                frame = screen.add {
                    type = "frame",
                    name = MAIN_TRAIN_DEFEAT_GUI,
                    caption = { "the-cave-train-interiors.main-train-defeat-title" },
                    direction = "vertical",
                }
                frame.add {
                    type = "label",
                    name = MAIN_TRAIN_DEFEAT_LABEL,
                    caption = "",
                }
            end

            local label = frame[MAIN_TRAIN_DEFEAT_LABEL]
            if label and label.valid then
                label.caption = remaining > 0
                    and { "the-cave-train-interiors.main-train-defeat-countdown", remaining }
                    or { "the-cave-train-interiors.main-train-defeat-game-over" }
                pcall(function()
                    label.style.font = "default-large-bold"
                    label.style.font_color = { 1, 0.25, 0.1 }
                    label.style.horizontal_align = "center"
                    label.style.horizontally_stretchable = true
                end)
            end

            pcall(function()
                frame.style.minimal_width = 520
                frame.style.maximal_width = 520
                local scale = math.max(0.1, tonumber(player.display_scale) or 1)
                local resolution = player.display_resolution or { width = 1920, height = 1080 }
                local logical_width = (tonumber(resolution.width) or 1920) / scale
                frame.location = {
                    x = math.max(0, math.floor((logical_width - 520) * 0.5)),
                    y = 72,
                }
            end)
        end
    end
end

local function defeat_message(force, message, alarm)
    for _, player in pairs(game.connected_players) do
        if cave_teams.player_force(player) == force then
            if message then player.print(message) end
            if alarm then player.play_sound { path = "utility/console_message" } end
        end
    end
end

local function trigger_defeat(force)
    force = force or player_force() -- CAVETORIO keeps its single-force outpost.
    if not valid(force) then return end
    local s = state()
    if s.main_train_defeats[force.index] then return end
    storage.the_cave_warp_outpost_defeated = storage.the_cave_warp_outpost_defeated or {}
    storage.the_cave_warp_outpost_defeated[force.index] = true
    main_train_defeat.begin(force)
    s.main_train_registered_forces[force.index] = true
    s.main_train_defeats[force.index] = {
        ends_tick = (game.tick or 0) + MAIN_TRAIN_DEFEAT_COUNTDOWN_SECONDS * TICKS_PER_SECOND,
        last_second = MAIN_TRAIN_DEFEAT_COUNTDOWN_SECONDS,
    }
    warp_outpost._update_main_train_defeat_gui(MAIN_TRAIN_DEFEAT_COUNTDOWN_SECONDS, force)
    defeat_message(force, {
        "the-cave-train-interiors.main-train-defeat-start",
        MAIN_TRAIN_DEFEAT_COUNTDOWN_SECONDS,
    }, true)
end

function warp_outpost.set_main_train_defeat_handler(handler)
    main_train_defeat_handler = type(handler) == "function" and handler or nil
end

function warp_outpost.check_main_train_defeat()
    if not (train_interiors and train_interiors.is_enabled and train_interiors.is_enabled()) then return end
    local tsi = storage.the_cave_train_interiors
    if not (tsi and tsi.main_train_units) then return end
    local s = state()
    for unit in pairs(tsi.main_train_units) do
        local wagon = tsi.wagons and tsi.wagons[unit]
        local force = wagon and valid(wagon.entity) and wagon.entity.force
        if valid(force) then s.main_train_registered_forces[force.index] = true end
    end
    for index in pairs(s.main_train_registered_forces) do
        local force = game.forces[index]
        if valid(force) and not s.main_train_defeats[index] and not any_registered_main_train_alive(force) then
            trigger_defeat(force)
        end
    end
end

function warp_outpost.check_main_train_part_destroyed(entity)
    if not (train_interiors and train_interiors.is_enabled and train_interiors.is_enabled()) then return end
    if not (entity and entity.unit_number and entity.type) then return end
    local force = entity.force
    if not valid(force) then return end
    local s = state()
    if s.main_train_defeats[force.index] then return end
    local tsi = storage.the_cave_train_interiors
    if not (tsi and tsi.main_train_units and tsi.main_train_units[entity.unit_number]) then return end
    s.main_train_registered_forces[force.index] = true

    local other_part_alive, other_locomotive_alive = false, false
    for unit in pairs(tsi.main_train_units) do
        if unit ~= entity.unit_number then
            local wagon = tsi.wagons and tsi.wagons[unit]
            local other = wagon and wagon.entity
            if valid(other) and other.force == force then
                other_part_alive = true
                if other.type == "locomotive" then other_locomotive_alive = true end
            end
        end
    end
    if (entity.type == "locomotive" and not other_locomotive_alive) or not other_part_alive then
        trigger_defeat(force)
    end
end

function warp_outpost.clear_force(force_index)
    local s = storage.the_cave_warp_outpost
    if s then
        if s.main_train_defeats then s.main_train_defeats[force_index] = nil end
        if s.main_train_registered_forces then s.main_train_registered_forces[force_index] = nil end
    end
    local defeated = storage.the_cave_warp_outpost_defeated
    if type(defeated) == "table" then defeated[force_index] = nil end
    local force = game.forces[force_index]
    for _, player in pairs(game.players) do
        if cave_teams.player_force(player) == force then
            local frame = player.gui.screen[MAIN_TRAIN_DEFEAT_GUI]
            if frame and frame.valid then frame.destroy() end
        end
    end
end

function warp_outpost._process_main_train_defeat_countdown(event)
    local s = storage.the_cave_warp_outpost
    if not (s and s.main_train_defeats) then return false end
    local now = event and event.tick or game.tick
    local active = false
    local indexes = {}
    for index in pairs(s.main_train_defeats) do indexes[#indexes + 1] = index end
    table.sort(indexes)
    for _, index in ipairs(indexes) do
        local countdown = s.main_train_defeats[index]
        local force = game.forces[index]
        if countdown and valid(force) and not countdown.finished then
            active = true
            local remaining = math.max(0, math.ceil((countdown.ends_tick - now) / TICKS_PER_SECOND))
            if remaining ~= countdown.last_second then
                countdown.last_second = remaining
                warp_outpost._update_main_train_defeat_gui(remaining, force)
                if remaining == 20 or remaining == 10 or (remaining > 0 and remaining <= 5) then
                    defeat_message(force, { "the-cave-train-interiors.main-train-defeat-warning", remaining },
                        remaining == 10 or remaining <= 5)
                end
            end
            if remaining <= 0 then
                countdown.finished = true
                defeat_message(force, { "the-cave-train-interiors.main-train-defeat-finished" }, true)
                local ok, started = false, "reset coordinator unavailable"
                if main_train_defeat_handler then
                    ok, started = pcall(main_train_defeat_handler, "main-train-destroyed", { force_index = index })
                end
                if not (ok and started == true) then
                    log("[The Cave] Main Train reset handoff failed for force " .. index .. ": " .. tostring(started))
                    -- A failed team reset must never finish the other teams' game.
                    if main_train_defeat.blocks_all() then
                        pcall(function()
                            game.set_lose_ending_info {
                                title = { "the-cave-train-interiors.main-train-defeat-ending-title" },
                                message = { "the-cave-train-interiors.main-train-defeat-ending-message" },
                                final_message = { "the-cave-train-interiors.main-train-defeat-ending-final" },
                            }
                            game.set_game_state { game_finished = true, player_won = false, can_continue = false }
                        end)
                    end
                end
            end
        end
    end
    return active and main_train_defeat.blocks_all()
end

local function clear_player_inventory_and_equipment(player)
    if not (player and player.valid) then return end
    pcall(function() player.clear_items_inside() end)
    local character = player.character
    if character and character.valid then
        for _, inv_id in pairs({
            defines.inventory.character_main,
            defines.inventory.character_guns,
            defines.inventory.character_ammo,
            defines.inventory.character_armor,
            defines.inventory.character_trash,
        }) do
            local inv = character.get_inventory(inv_id)
            if inv and inv.valid then inv.clear() end
        end
    end
end

local function recover_warp_player(player, surface, target, clear_items)
    local character = physical.character_context(player)
    if character and character.driving then pcall(function() character.driving = false end) end
    if player.driving then pcall(function() player.driving = false end) end
    local safe = physical.find_position(player, surface, target, 8)
    if not physical.teleport(player, safe, surface) then return false end
    if clear_items then
        clear_player_inventory_and_equipment(player)
        player.print("[The Cave] You were outside the Warp Outpost and were recovered on the next map with an empty inventory.")
    end
    return true
end

local function teleport_players(source_surface, source_center, source_size, dest_surface, dest_center)
    local left, top, right, bottom = rect_bounds(source_center, source_size)
    local pending = {}
    for _, player in pairs(game.players or {}) do
        if player and player.valid and player.connected then
            local position = physical.position(player)
            local inside = physical.on_surface(player, source_surface) and position
                and point_inside(position, left, top, right, bottom)
            local target = inside and { x = position.x + (dest_center.x - source_center.x), y = position.y + (dest_center.y - source_center.y) }
                or { x = dest_center.x, y = dest_center.y + 2 }
            local origin_surface = physical.surface(player)
            if not recover_warp_player(player, dest_surface, target, not inside) then
                pending[player.index] = { target = target, clear_items = not inside,
                    origin_surface_index = origin_surface and origin_surface.index }
                player.print("[The Cave] Warp recovery is waiting for a safe landing. Your inventory has been retained.")
            end
        end
    end
    return pending
end

local function announce_profile(profile, warp_number, time_def)
    local msg = "[The Cave] New Cave Profile\n"
        .. "Warp: #" .. tostring(warp_number) .. "\n"
        .. "Zone: " .. tostring(profile.zone or "Easy") .. "\n"
        .. "Region: " .. tostring(profile.region or "Normal Cave") .. "\n"
        .. "Lighting: " .. display_profile_value(profile.lighting or "permanent-night") .. "\n"
        .. "Digging Mode: " .. display_profile_value(profile.digging_mode or "disabled") .. "\n"
        .. "Resources: " .. resource_level_text(profile) .. "\n"
        .. "Research Difficulty: " .. display_profile_value(profile.research_level_difficulty or "medium") .. "\n"
        .. "Ore Protection: " .. display_profile_value(profile.ore_patch_protection or "Disabled") .. "\n"
        .. "Ore Missing: " .. display_profile_value(profile.ore_patch_missing or "Disabled") .. "\n"
        .. "Cave Difficulty: " .. display_profile_value(profile.cave_difficulty or "medium") .. "\n"
        .. "Warp Time: " .. tostring(time_def.minutes) .. " minutes"
    print_all(msg)
end

local NIGHTMARE_UNLOCK_MESSAGE = "[The Cave] WARNING: Nightmare Zones Unlocked.\n\nYou have reached Warp #60.\nFrom now on, Nightmare destinations can appear.\n\nEach new warp beyond #60 increases Nightmare depth by +10 tiles.\nThe caves will become deeper, darker, and more dangerous.\nPrepare your Warp Outpost."

local function maybe_announce_nightmare_unlock(warp_number)
    local s = state()
    if warp_number >= 60 and not s.nightmare_unlocked_announced then
        s.nightmare_unlocked_announced = true
        play_alarm()
        print_all(NIGHTMARE_UNLOCK_MESSAGE)
    end
end

function warp_outpost.perform_warp(reason)
    if not cavetorio_enabled() then return end
    local s = state()
    local source = current_surface()
    if not (source and source.valid) then return end
    local force = player_force()
    local size_def = outpost_size(force)
    local time_def = outpost_time(force)
    local source_center = ensure_outpost_center(source)
    local entities, has_main_train, src_left, src_top, src_right, src_bottom = collect_outpost_entities(source, source_center, size_def)
    if not has_main_train then
        print_all("[The Cave] Warp failed: no registered Main Train part is fully inside the Warp Outpost.")
        trigger_defeat()
        return
    end

    local next_warp_number = (s.warp_number or 1) + 1
    local profile = build_profile(next_warp_number)
    local dest_center = profile_destination(profile)
    local surface_name = WARP_SURFACE_PREFIX .. tostring(next_warp_number)
    local dest = ensure_surface(surface_name)
    if not (dest and dest.valid) then
        print_all("[The Cave] Warp failed: could not create the next cave surface.")
        return
    end

    local dest_left, dest_top = rect_bounds(dest_center, size_def)
    local tile_snapshot = snapshot_tiles(source, src_left, src_top, src_right, src_bottom)

    clean_destination_footprint(dest, dest_center, size_def)
    paste_tiles(dest, dest_left, dest_top, tile_snapshot)

    local wire_snapshot = snapshot_wire_connections(entities)
    local offset = { x = dest_center.x - source_center.x, y = dest_center.y - source_center.y }
    local moved, entity_map = transfer_entities(entities, dest, offset)
    relink_main_train_records(entity_map)
    -- The existing one-force outpost carries ownership with its Main Train.
    -- Record it before player teleports can trigger arrival handlers.
    local main_units = storage.the_cave_train_interiors.main_train_units or {}
    for _, moved_entity in pairs(entity_map) do
        if valid(moved_entity) and moved_entity.unit_number and main_units[moved_entity.unit_number] then
            cave_worlds.set_owner(dest, moved_entity.force)
            cave_teams.set_home(moved_entity.force, dest)
            break
        end
    end
    queue_wire_restore(wire_snapshot, entity_map)
    clear_outpost_clear_ring(dest, dest_center, size_def)
    seal_outpost_ring(dest, dest_center, size_def)
    local pending_players = teleport_players(source, source_center, size_def, dest, dest_center)

    s.current_surface_name = dest.name
    prune_main_train_storage(dest.name)
    s.outpost_center = dest_center
    s.warp_number = next_warp_number
    s.surface_profiles[dest.name] = profile
    s.warned_minutes = {}
    s.manual_votes = {}
    s.manual_countdown_until = nil
    s.manual_cooldown_until = (game.tick or 0) + (time_def.cooldown * TICKS_PER_SECOND)
    s.next_auto_warp_tick = (game.tick or 0) + (time_def.minutes * TICKS_PER_MINUTE)
    s.safety_ring.active_units = {}
    s.safety_ring.pending_mini_waves = {}
    s.safety_ring.current_wave_number = nil
    s.safety_ring.current_wave_total = 0
    s.safety_ring.current_wave_started_tick = nil
    s.safety_ring.current_wave_boss = false
    s.safety_ring.rest_until = nil
    s.safety_ring.rest_wave_number = nil
    local ring_def, ring_level = safety_ring(force)
    s.safety_ring.last_level = ring_level
    s.safety_ring.cooldown_until = ring_level > 0 and ((game.tick or 0) + (tonumber(ring_def.cooldown_minutes) or 0) * TICKS_PER_MINUTE) or nil

    if source.name ~= "nauvis" and not source.name:find("^the%-cave%-train%-interior%-") then
        s.cleanup_queue[#s.cleanup_queue + 1] = { name = source.name, tick = (game.tick or 0) + 600, pending_players = pending_players, destination_surface_index = dest.index }
    else
        -- Do not delete Nauvis in this prototype. It is the default surface and
        -- some Factorio/scenario systems expect it to keep existing.
        s.cleanup_queue[#s.cleanup_queue + 1] = { name = source.name, tick = (game.tick or 0) + 600, skip_delete = true, pending_players = pending_players, destination_surface_index = dest.index }
    end

    maybe_announce_nightmare_unlock(next_warp_number)
    play_alarm()
    announce_profile(profile, next_warp_number, time_def)
    print_all("[The Cave] Warp complete.")
    refresh_gui()
    warp_outpost.check_main_train_defeat()
end

local function connected_player_count()
    local n = 0
    for _, player in pairs(game.connected_players or {}) do if player and player.valid then n = n + 1 end end
    return n
end

local function vote_count(votes)
    local n = 0
    for _ in pairs(votes or {}) do n = n + 1 end
    return n
end

function warp_outpost.request_manual_warp(player)
    if not cavetorio_enabled() then
        if player and player.valid then player.print("[The Cave] CAVETORIO is disabled in Mod Settings.") end
        return
    end
    if not (player and player.valid) then return end
    local s = state()
    local now = game.tick or 0
    if s.manual_countdown_until then
        player.print("[The Cave] Manual Warp countdown is already running.")
        return
    end
    if now < (s.manual_cooldown_until or 0) then
        player.print("[The Cave] Manual Warp is cooling down: " .. format_time((s.manual_cooldown_until or 0) - now) .. " remaining.")
        return
    end
    s.manual_votes[player.index] = true
    local required = math.floor(connected_player_count() / 2) + 1
    local votes = vote_count(s.manual_votes)
    print_all("[The Cave] Manual Warp vote: " .. votes .. "/" .. required .. " players agreed.")
    if votes >= required then
        local time_def = outpost_time(player_force())
        s.manual_countdown_until = now + time_def.countdown * TICKS_PER_SECOND
        print_all("[The Cave] Manual Warp initiated. Warp will happen in " .. tostring(time_def.countdown) .. " seconds. Anything outside the Warp Outpost will be lost.")
        play_alarm()
    end
    refresh_gui()
end

local function handle_warnings()
    local s = state()
    if not s.next_auto_warp_tick then return end
    local left_ticks = s.next_auto_warp_tick - (game.tick or 0)
    if left_ticks < 0 then return end
    local left_minutes = math.ceil(left_ticks / TICKS_PER_MINUTE)
    if left_minutes >= 1 and left_minutes <= 5 and not s.warned_minutes[left_minutes] then
        s.warned_minutes[left_minutes] = true
        play_alarm()
        if left_minutes >= 3 then
            print_all("[The Cave] Warp Warning: " .. tostring(left_minutes) .. " minutes remaining. Return to the Warp Outpost.")
        elseif left_minutes == 2 then
            print_all("[The Cave] Final Warning: 2 minutes remaining. Return to the Warp Outpost now. Players outside the Outpost will be left behind. Your body and inventory will be lost on this map.")
        else
            print_all("[The Cave] Final Warning: 1 minute remaining. Return to the Warp Outpost immediately. If you are outside the Outpost when warp happens, you will respawn on the next map with an empty inventory.")
        end
    end
end

local function process_cleanup_queue()
    local s = state()
    local now = game.tick or 0
    local keep = {}
    for _, item in pairs(s.cleanup_queue or {}) do
        if now >= (item.tick or 0) then
            local ready = true
            local destination = item.destination_surface_index and game.surfaces[item.destination_surface_index]
            if not (destination and destination.valid) then destination = current_surface() end
            for index, pending in pairs(item.pending_players or {}) do
                local player = game.get_player(index)
                if not (player and player.valid) then
                    item.pending_players[index] = nil
                elseif pending.origin_surface_index and (not physical.surface(player)
                    or physical.surface(player).index ~= pending.origin_surface_index) then
                    -- Another successful journey supersedes this failed transfer.
                    -- Do not pull the player back or apply an old inventory penalty.
                    item.pending_players[index] = nil
                elseif destination and destination.valid then
                    local target = pending.target
                    if destination.index ~= item.destination_surface_index then
                        local center = ensure_outpost_center(destination)
                        target = { x = center.x, y = center.y + 2 }
                    end
                    if recover_warp_player(player, destination, target, pending.clear_items) then
                        item.pending_players[index] = nil
                    else
                        ready = false
                    end
                else
                    ready = false
                end
            end
            local surface = item.name and game.surfaces[item.name]
            if ready and not item.skip_delete and surface and surface.valid then
                for _, player in pairs(game.players or {}) do
                    -- Retain the old map while any physical controller remains,
                    -- including an offline player awaiting the existing recovery.
                    if physical.on_surface(player, surface) then ready = false break end
                    if player.valid and player.surface == surface then
                        if not physical.move_view_off_surface(player, surface,
                            physical.surface(player), physical.position(player)) then ready = false break end
                    end
                end
            end
            if not ready then
                item.tick = now + 60
                keep[#keep + 1] = item
            elseif item.skip_delete then
                print_all("[The Cave] Previous map cleanup complete.")
            else
                local ok, queued = true, true
                if surface and surface.valid then
                    ok, queued = pcall(function() return game.delete_surface(surface) end)
                end
                if not ok or not queued then
                    item.tick = now + 60
                    keep[#keep + 1] = item
                else
                    print_all("[The Cave] Previous cave has collapsed and is no longer accessible.")
                end
            end
        else
            keep[#keep + 1] = item
        end
    end
    s.cleanup_queue = keep
end

local function process_offline_returns()
    local s = state()
    local now = game.tick or 0
    local keep = {}
    local surface = current_surface()
    local center = surface and ensure_outpost_center(surface)
    for _, item in pairs(s.offline_return_queue or {}) do
        if now >= (item.tick or 0) then
            local player = item.player_index and game.get_player(item.player_index)
            if player and player.valid and not player.connected and player.character and player.character.valid and surface and surface.valid then
                pcall(function() player.character.teleport({ x = center.x, y = center.y + 1 }, surface) end)
            end
        else
            keep[#keep + 1] = item
        end
    end
    s.offline_return_queue = keep
end

function warp_outpost.on_init()
    if not cavetorio_enabled() then
        destroy_all_gui()
        return
    end
    local s = state()
    local surface = current_surface()
    if surface then
        ensure_outpost_center(surface)
        apply_current_outpost_footprint("init")
    end
    local time_def = outpost_time(player_force())
    s.next_auto_warp_tick = s.next_auto_warp_tick or ((game.tick or 0) + time_def.minutes * TICKS_PER_MINUTE)
    s.manual_cooldown_until = s.manual_cooldown_until or ((game.tick or 0) + time_def.cooldown * TICKS_PER_SECOND)
    s.surface_profiles[s.current_surface_name] = s.surface_profiles[s.current_surface_name] or {
        zone = "Easy",
        region = "Normal Cave",
        lighting = LIGHTING_OPTIONS[((game.tick or 0) % #LIGHTING_OPTIONS) + 1] or "permanent-night",
        digging_mode = "disabled",
        resource_level = "level-2",
        cave_difficulty = "easy",
        research_level_difficulty = "medium",
        ore_patch_protection = "Disabled",
        ore_patch_missing = "Disabled",
        mixed_resource_patches = "Enabled",
    }
end

function warp_outpost.on_configuration_changed()
    local s = state()
    local force = player_force()
    if valid(force) and s.main_train_defeat_tick then
        s.main_train_defeats[force.index] = {
            ends_tick = s.main_train_defeat_tick,
            last_second = s.main_train_defeat_last_second,
            finished = s.main_train_defeat_finished,
        }
        s.main_train_registered_forces[force.index] = true
        if not main_train_defeat.is_active(force) then main_train_defeat.begin(force) end
    end
    if storage.the_cave_warp_outpost_defeated == true then
        storage.the_cave_warp_outpost_defeated = valid(force) and { [force.index] = true } or {}
    end
    s.main_train_defeat_tick = nil
    s.main_train_defeat_last_second = nil
    s.main_train_defeat_finished = nil
    s.main_train_registered_once = nil
    warp_outpost.on_init()
end

function warp_outpost.on_player_created(event)
    apply_current_outpost_footprint("player-created")
    local player = event and event.player_index and game.get_player(event.player_index)
    update_player_gui(player)
end

function warp_outpost.refresh_defeat_gui(player)
    if not valid(player) then return end
    local force = cave_teams.player_force(player)
    local s = storage.the_cave_warp_outpost
    local countdown = valid(force) and s and s.main_train_defeats and s.main_train_defeats[force.index]
    if countdown then
        warp_outpost._update_main_train_defeat_gui(
            math.max(0, math.ceil((countdown.ends_tick - game.tick) / TICKS_PER_SECOND)), force)
    else
        local frame = player.gui.screen[MAIN_TRAIN_DEFEAT_GUI]
        if frame and frame.valid then frame.destroy() end
    end
end

function warp_outpost.on_player_joined_game(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    update_player_gui(player)
    warp_outpost.refresh_defeat_gui(player)
end

function warp_outpost.on_player_left_game(event)
    if not cavetorio_enabled() then return end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local s = state()
    s.offline_return_queue[#s.offline_return_queue + 1] = {
        player_index = player.index,
        tick = (game.tick or 0) + 20 * TICKS_PER_SECOND,
    }
end

function warp_outpost.on_gui_click(event)
    if not cavetorio_enabled() then return end
    local element = event and event.element
    if not (element and element.valid) then return end
    local player = event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if element.name == GUI_BUTTON then
        warp_outpost.request_manual_warp(player)
        return
    end
    if element.name == GUI_CAVE_INFO_BUTTON or element.name == GUI_TRAIN_INFO_BUTTON then
        local s = state()
        local target = element.name == GUI_CAVE_INFO_BUTTON and "cave" or "train"
        if s.gui_mode[player.index] == target then
            s.gui_mode[player.index] = nil
        else
            s.gui_mode[player.index] = target
        end
        update_player_gui(player)
    end
end

function warp_outpost.on_research_finished(event)
    if not cavetorio_enabled() then return end
    local name = event and event.research and event.research.name or ""
    local s = state()
    if name:find(EXPANSION_PREFIX, 1, true) then
        apply_current_outpost_footprint("research")
        local size_def, size_level = outpost_size(player_force())
        print_all("[The Cave] Warp Outpost Expansion " .. tostring(size_level) .. " complete. Outpost size is now " .. tostring(size_def.label) .. ".")
    elseif name:find(TIME_PREFIX, 1, true) then
        local time_def, time_level = outpost_time(player_force())
        s.next_auto_warp_tick = (game.tick or 0) + time_def.minutes * TICKS_PER_MINUTE
        s.manual_cooldown_until = math.max(s.manual_cooldown_until or 0, (game.tick or 0) + time_def.cooldown * TICKS_PER_SECOND)
        print_all("[The Cave] Warp Outpost Time " .. tostring(time_level) .. " complete. Current cycle: " .. tostring(time_def.minutes) .. " minutes.")
    elseif name:find(SAFETY_RING_PREFIX, 1, true) then
        apply_current_outpost_footprint("research")
        local ring_def, ring_level = safety_ring(player_force())
        local sr = s.safety_ring
        sr.last_level = ring_level
        sr.cooldown_until = (game.tick or 0) + (tonumber(ring_def.cooldown_minutes) or 0) * TICKS_PER_MINUTE
        sr.pending_mini_waves = sr.pending_mini_waves or {}
        local msg = "[The Cave] Safety Ring Upgrade " .. tostring(ring_level) .. " complete. Safety Ring radius is now " .. tostring(ring_def.label) .. "."
        if ring_level == 1 then
            msg = msg .. " Enemy attack waves are now active. Next attack in 1 minute. Prepare your defenses."
        else
            msg = msg .. " Enemy attack waves are stronger. Next attack in 1 minute."
        end
        print_all(msg)
    end
    refresh_gui()
end
function warp_outpost.on_tick(event)
    if warp_outpost._process_main_train_defeat_countdown(event) then return end
    if cavetorio_enabled() then process_pending_wire_restores() end
    if not cavetorio_enabled() then
        if event.tick % 300 == 0 then destroy_all_gui() end
        return
    end
    local s = state()
    if event.tick % 30 == 0 then refresh_gui() end
    if event.tick % 60 == 0 then
        handle_warnings()
        process_cleanup_queue()
        process_offline_returns()
        process_safety_ring_waves()
    end
    if s.manual_countdown_until and event.tick >= s.manual_countdown_until then
        warp_outpost.perform_warp("manual")
        return
    end
    if s.next_auto_warp_tick and event.tick >= s.next_auto_warp_tick then
        print_all("[The Cave] Auto Warp initiated. Everything outside the Warp Outpost is lost. Players outside the Outpost will be recovered on the next map without their inventory.")
        warp_outpost.perform_warp("auto")
    end
end

function warp_outpost.debug_spawn_safety_ring_wave(player)
    if not cavetorio_enabled() then
        if player then player.print("[The Cave] CAVETORIO is disabled in Mod Settings.") end
        return
    end
    local _, level = safety_ring(player_force())
    if level <= 0 then level = 1 end
    local created = safety_ring_start_attack_cycle(level)
    if player then player.print("[The Cave] Debug Safety Ring wave spawned: " .. tostring(created) .. " enemies (level " .. tostring(level) .. ").") end
end

function warp_outpost.debug_force_warp(player)
    if not cavetorio_enabled() then
        if player then player.print("[The Cave] CAVETORIO is disabled in Mod Settings.") end
        return
    end
    if player then player.print("[The Cave] Debug force warp started.") end
    warp_outpost.perform_warp("debug")
end

function warp_outpost.debug_show_profile(player)
    if not cavetorio_enabled() then
        if player then player.print("[The Cave] CAVETORIO is disabled in Mod Settings.") end
        return
    end
    local s = state()
    local p = s.surface_profiles[s.current_surface_name] or {}
    if player then
        player.print("[The Cave] Current Warp #" .. tostring(s.warp_number) .. " Zone: " .. display_profile_value(p.zone) .. " Region: " .. display_profile_value(p.region) .. " Lighting: " .. display_profile_value(p.lighting))
    end
end

return warp_outpost
