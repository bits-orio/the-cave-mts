local physical = require("scripts.player_physical")
-- The Cave: Advancing Collapse.
--
-- Self-contained northbound terrain deletion inspired by the GPLv3
-- ComfyFactorio Mountain Fortress collapse. This implementation depends only
-- on The Cave's own world mirror. Catch-up follows the live Main Locomotive;
-- without one, terrain deletion continues at its ordinary player-count rate.
local hash = require("scripts.lib.hash")
local mirror = require("scripts.lib.mirror")
local zones = require("scripts.advancing_zones")
local south_guard = require("scripts.advancing_south_guard")
local assault = require("scripts.advancing_assault")
local recovery = require("scripts.advancing_recovery")
local clearing = require("scripts.advancing_clearing")
local main_train_defeat = require("scripts.main_train_defeat")
local area = require("scripts.advancing_area")
local cave_worlds = require("scripts.cave_worlds")
local cave_teams = require("scripts.cave_teams")

local advancing = {}
local catch_up_api

local FRAME_NAME = "the_cave_advancing_collapse_timer"
local TITLE_NAME = "the_cave_advancing_collapse_title"
local TIME_NAME = "the_cave_advancing_collapse_time"
local HIGHEST_NAME = "the_cave_advancing_collapse_highest"
local WAVE_NAME = "the_cave_advancing_collapse_wave"
local NEXT_WAVE_NAME = "the_cave_advancing_collapse_next_wave"
local COUNTDOWN_TICKS = 2 * 60 * 60 * 60
local CATCH_UP_DISTANCE = 900
local CATCH_UP_CHECK_TICKS = 250
-- Frequent terrain edits can starve native path searches during an assault.
-- Keep the original erosion parameters and batch new floor changes every
-- 256 ticks (about 4.3 seconds). Paired terrain drains in bounded row steps;
-- unavailable northern chunks apply backpressure instead of growing a burst.
local TERRAIN_COMMIT_TICKS = 256
local ROW_STREAM = 7801
local GUI_WIDTH = 390
local RESPAWN_AHEAD_TILES = 40
local RESPAWN_SEARCH_STEP = 8
local RESPAWN_SEARCH_ROWS = 20

local function root()
    return storage and storage.the_cave_advancing_collapse or nil
end

local function world_for_player(player)
    local force = cave_teams.player_force(player)
    if not force then return nil end
    local surface = physical.surface(player)
    if surface and cave_worlds.owner_force(surface) == force then return surface end
    return cave_teams.home_surface(force)
end

local function connected_count(surface)
    local count = 0
    for _, player in pairs(game.connected_players) do
        if world_for_player(player) == surface then count = count + 1 end
    end
    return count
end

local function world_running(surface)
    return cave_teams.is_world_running(surface)
end

local function player_world_state(player)
    local state = root()
    if not (state and player and player.valid) then return nil end
    local surface = world_for_player(player)
    if not (surface and cave_teams.is_world_running(surface)) then return nil end
    return state.surfaces and state.surfaces[surface.index]
end

local function destroy_gui(player)
    if not (player and player.valid and player.gui and player.gui.screen) then return end
    local frame = player.gui.screen[FRAME_NAME]
    if frame and frame.valid then frame.destroy() end
end

local function destroy_all_guis()
    if not game then return end
    for _, player in pairs(game.players) do destroy_gui(player) end
end

local function logical_width(player)
    local resolution = player.display_resolution or { width = 1280, height = 720 }
    local scale = player.display_scale or 1
    if scale <= 0 then scale = 1 end
    return resolution.width / scale
end

local function timer_color(seconds)
    if seconds <= 60 then
        if seconds % 2 == 0 then return { r = 1, g = 0.08, b = 0.04 } end
        return { r = 1, g = 0.78, b = 0.18 }
    end
    if seconds <= 10 * 60 then return { r = 1, g = 0.08, b = 0.04 } end
    if seconds <= 30 * 60 then return { r = 1, g = 0.45, b = 0.08 } end
    return { r = 1, g = 0.82, b = 0.16 }
end

local function format_time(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function position_gui(player, frame)
    if not (player and player.valid and frame and frame.valid) then return end
    local x = math.max(0, math.floor((logical_width(player) - GUI_WIDTH) / 2))
    pcall(function() frame.location = { x = x, y = 8 } end)
end

local function show_gui(player, seconds)
    if not (player and player.valid and player.connected) then return end
    local state = player_world_state(player)
    if not (zones.is_active() and state and state.phase == "countdown" and seconds > 0) then
        destroy_gui(player)
        return
    end

    local frame = player.gui.screen[FRAME_NAME]
    if not (frame and frame.valid) then
        frame = player.gui.screen.add {
            type = "frame",
            name = FRAME_NAME,
            direction = "vertical",
        }
        frame.style.width = GUI_WIDTH
        frame.style.horizontal_align = "center"
        frame.style.padding = 8

        local title = frame.add {
            type = "label",
            name = TITLE_NAME,
            caption = { "the-cave-advancing-collapse.timer-title" },
        }
        title.style.font = "default-large-bold"
        title.style.horizontal_align = "center"
        title.style.horizontally_stretchable = true
        title.style.bottom_margin = 2

        local timer = frame.add {
            type = "label",
            name = TIME_NAME,
            caption = format_time(seconds),
        }
        timer.style.font = "default-large-bold"
        timer.style.horizontal_align = "center"
        timer.style.horizontally_stretchable = true
        position_gui(player, frame)
    end

    local color = timer_color(seconds)
    local title = frame[TITLE_NAME]
    local timer = frame[TIME_NAME]
    if title and title.valid then title.style.font_color = color end
    if timer and timer.valid then
        timer.caption = format_time(seconds)
        timer.style.font_color = color
    end
end

local function update_player_zone(state, player)
    state.player_current_zones = state.player_current_zones or {}
    state.highest_zone_by_force = state.highest_zone_by_force or {}
    if physical.character_context(player) and zones.is_main_surface(physical.surface(player)) then
        local current = zones.zone_index_at_y(physical.position(player).y)
        state.player_current_zones[player.index] = current
        local force_index = player.force and player.force.index or 1
        state.highest_zone_by_force[force_index] = math.max(
            state.highest_zone_by_force[force_index] or 1,
            current
        )
    end
    return state.player_current_zones[player.index] or 1
end

local function show_zone_gui(player)
    if not (player and player.valid and player.connected) then return end
    local state = root()
    local surface_state = player_world_state(player)
    if not (zones.is_active() and state and surface_state and surface_state.phase == "active") then
        destroy_gui(player)
        return
    end

    local current = update_player_zone(state, player)
    local force_index = player.force and player.force.index or 1
    local highest = state.highest_zone_by_force[force_index] or current
    local frame = player.gui.screen[FRAME_NAME]
    if frame and frame.valid and not frame[HIGHEST_NAME] then
        frame.destroy()
        frame = nil
    end
    if not (frame and frame.valid) then
        frame = player.gui.screen.add {
            type = "frame",
            name = FRAME_NAME,
            direction = "vertical",
        }
        frame.style.width = GUI_WIDTH
        frame.style.horizontal_align = "center"
        frame.style.padding = 8

        local current_label = frame.add {
            type = "label",
            name = TITLE_NAME,
            caption = { "the-cave-advancing-collapse.current-zone", current },
        }
        current_label.style.font = "default-large-bold"
        current_label.style.font_color = { r = 0.25, g = 0.9, b = 1 }
        current_label.style.horizontal_align = "center"
        current_label.style.horizontally_stretchable = true
        current_label.style.bottom_margin = 2

        local highest_label = frame.add {
            type = "label",
            name = HIGHEST_NAME,
            caption = { "the-cave-advancing-collapse.highest-zone", highest },
        }
        highest_label.style.font = "default-large-bold"
        highest_label.style.font_color = { r = 1, g = 0.82, b = 0.16 }
        highest_label.style.horizontal_align = "center"
        highest_label.style.horizontally_stretchable = true
        position_gui(player, frame)
    end

    local assault_status = assault.status_for_player(player)
    if not frame[WAVE_NAME] then
        local wave_label = frame.add {
            type = "label",
            name = WAVE_NAME,
            caption = "",
        }
        wave_label.style.font = "default-bold"
        wave_label.style.font_color = { r = 1, g = 0.32, b = 0.08 }
        wave_label.style.horizontal_align = "center"
        wave_label.style.horizontally_stretchable = true
        wave_label.style.top_margin = 4
    end
    if not frame[NEXT_WAVE_NAME] then
        local next_label = frame.add {
            type = "label",
            name = NEXT_WAVE_NAME,
            caption = "",
        }
        next_label.style.font_color = { r = 1, g = 0.82, b = 0.16 }
        next_label.style.horizontal_align = "center"
        next_label.style.horizontally_stretchable = true
    end

    local current_label = frame[TITLE_NAME]
    local highest_label = frame[HIGHEST_NAME]
    if current_label and current_label.valid then
        current_label.caption = { "the-cave-advancing-collapse.current-zone", current }
    end
    if highest_label and highest_label.valid then
        highest_label.caption = { "the-cave-advancing-collapse.highest-zone", highest }
    end
    local wave_label = frame[WAVE_NAME]
    local next_label = frame[NEXT_WAVE_NAME]
    if wave_label and wave_label.valid then
        wave_label.caption = assault_status and {
            "the-cave-advancing-collapse.wave-status",
            assault_status.wave,
            assault_status.units,
            assault_status.nests,
        } or { "the-cave-advancing-collapse.wave-status", 0, 0, 0 }
    end
    if next_label and next_label.valid then
        next_label.caption = {
            assault_status and assault_status.resting
                and "the-cave-advancing-collapse.recovery-remaining"
                or (assault_status and assault_status.recovery_due
                    and "the-cave-advancing-collapse.recovery-in"
                    or "the-cave-advancing-collapse.next-wave"),
            format_time(assault_status and assault_status.next_seconds or 0),
        }
    end
end

local function refresh_all_guis(force)
    local state = root()
    if not (zones.is_active() and state) then destroy_all_guis(); return end
    -- First collect every connected player's progress so the force-wide maximum
    -- is identical on every teammate's panel during this update.
    for _, player in pairs(game.connected_players) do update_player_zone(state, player) end
    for _, player in pairs(game.connected_players) do
        local surface_state = player_world_state(player)
        if surface_state and surface_state.phase == "active" then show_zone_gui(player)
        else
            local seconds = surface_state and math.ceil(math.max(0, surface_state.remaining_ticks or 0) / 60) or 0
            show_gui(player, seconds)
        end
    end
end

local function add_surface(surface)
    local state = root()
    if not (state and zones.is_main_surface(surface) and cave_teams.is_world_running(surface)) then return nil end
    state.surfaces = state.surfaces or {}
    local surface_state = state.surfaces[surface.index]
    if not surface_state then
        surface_state = {
            phase = "countdown",
            remaining_ticks = COUNTDOWN_TICKS,
            line_y = zones.COLLAPSE_START_Y,
            row_order = nil,
            row_cursor = 1,
            erased_x = {},
            progress_y = 0,
        }
        state.surfaces[surface.index] = surface_state
    end
    return surface_state
end

local function tile_is_walkable(surface, position)
    if not (surface and surface.valid and surface.get_tile) then return true end
    local ok, tile = pcall(function() return surface.get_tile(position) end)
    if not (ok and tile and tile.valid) then return false end
    local name = tile.name or ""
    if name == "out-of-map"
        or name:find("water", 1, true)
        or name:find("ocean", 1, true)
        or name:find("lava", 1, true) then
        return false
    end
    if tile.collides_with then
        local collision_ok, collides = pcall(function() return tile.collides_with("player") end)
        if collision_ok and collides then return false end
    end
    return true
end

local function safe_respawn_limit(surface_state)
    return math.floor(surface_state.line_y or zones.COLLAPSE_START_Y) - RESPAWN_AHEAD_TILES
end

local function position_is_respawn_safe(surface, surface_state, position)
    if not (surface_state and position) then return false end
    if not zones.inside_width(position.x) then return false end
    if math.floor(position.y) > safe_respawn_limit(surface_state) then return false end
    if zones.is_collapsed(surface, position.x, position.y) then return false end
    return tile_is_walkable(surface, position)
end

local function safe_respawn_table(state, surface, force_index)
    state.safe_respawns = state.safe_respawns or {}
    state.safe_respawns[surface.index] = state.safe_respawns[surface.index] or {}
    return state.safe_respawns[surface.index], force_index
end

local function remember_safe_position(player, surface_state)
    if not (player and player.valid and physical.surface(player) and player.force and physical.position(player)) then return end
    if not zones.is_main_surface(physical.surface(player)) then return end
    if not position_is_respawn_safe(physical.surface(player), surface_state, physical.position(player)) then return end

    local state = root()
    if not state then return end
    local by_force, force_index = safe_respawn_table(state, physical.surface(player), player.force.index)
    by_force[force_index] = {
        x = physical.position(player).x,
        y = physical.position(player).y,
        tick = game and game.tick or 0,
    }
end

local function find_walkable_near(surface, surface_state, entity_name, anchor, radius)
    if not (surface and surface.valid and surface.find_non_colliding_position) then return nil end
    local ok, found = pcall(function()
        return surface.find_non_colliding_position(
            entity_name or "character",
            anchor,
            radius or 6,
            0.5,
            true
        )
    end)
    if ok and found and position_is_respawn_safe(surface, surface_state, found) then
        return found
    end
    return nil
end

local function find_safe_respawn(player, surface_state)
    local state = root()
    local surface = physical.surface(player)
    local entity_name = player.character and player.character.valid and player.character.name or "character"
    local force_index = player.force and player.force.index or 1
    local stored = state
        and state.safe_respawns
        and state.safe_respawns[surface.index]
        and state.safe_respawns[surface.index][force_index]
    if stored and position_is_respawn_safe(surface, surface_state, stored) then
        local near_stored = find_walkable_near(
            surface,
            surface_state,
            entity_name,
            { x = stored.x, y = stored.y },
            8
        )
        if near_stored then return near_stored end
    end

    local half = math.floor(zones.ZONE_WIDTH / 2)
    local base_x = math.max(-half + 4, math.min(half - 5, physical.position(player).x or 0))
    local safe_y = safe_respawn_limit(surface_state) + 0.5
    local x_offsets = { 0 }
    for offset = 16, half - 8, 16 do
        x_offsets[#x_offsets + 1] = offset
        x_offsets[#x_offsets + 1] = -offset
    end

    -- Search the requested 40-tile safety line first, then progressively
    -- farther north. Every accepted result is rechecked against the current
    -- partially erased row, ribbon bounds and non-walkable terrain.
    for row = 0, RESPAWN_SEARCH_ROWS do
        local y = safe_y - row * RESPAWN_SEARCH_STEP
        for _, offset in ipairs(x_offsets) do
            local x = math.max(-half + 4, math.min(half - 5, base_x + offset))
            local found = find_walkable_near(
                surface,
                surface_state,
                entity_name,
                { x = x, y = y },
                6
            )
            if found then return found end
        end
    end
    return nil
end

local function row_order(surface, line_y)
    local first_x = -math.floor(zones.ZONE_WIDTH / 2)
    local order = {}
    for offset = 0, zones.ZONE_WIDTH - 1 do order[#order + 1] = first_x + offset end
    local surface_seed = surface.map_gen_settings and surface.map_gen_settings.seed or 0
    for index = #order, 2, -1 do
        local swap = hash.range(surface_seed, line_y, index, ROW_STREAM, 1, index)
        order[index], order[swap] = order[swap], order[index]
    end
    return order
end

local function kill_entity(entity)
    if not (entity and entity.valid) then return end
    -- Characters must die normally so their owners receive the standard death
    -- and respawn flow. Cave cover and resources are erased without mining or
    -- death rewards: collapsing a diggy-rock must not reopen terrain or yield
    -- ore. Other damageable entities die normally so optional mods can retire
    -- their vehicle/factory state through the standard on_entity_died event.
    if assault.is_owned_entity(entity) then
        pcall(function() entity.destroy { raise_destroy = true } end)
    elseif entity.type == "character" then
        pcall(function() entity.die() end)
    elseif entity.name == "diggy-rock" or entity.name == "diggy-rubble"
        or entity.name == "diggy-tree" or entity.type == "resource" then
        pcall(function() entity.destroy { raise_destroy = true } end)
    elseif entity.health then
        pcall(function() entity.die() end)
    else
        pcall(function() entity.destroy { raise_destroy = true } end)
    end
    if entity.valid then pcall(function() entity.destroy { raise_destroy = true } end) end
end

local function erase_tile(surface, surface_state, x)
    local y = surface_state.line_y
    local position = { x = x, y = y }
    local center = { x = x + 0.5, y = y + 0.5 }
    for _, entity in pairs(surface.find_entities_filtered {
        area = {
            { center.x - 4, center.y - 2 },
            { center.x + 4, center.y + 2 },
        },
    }) do
        if not world_running(surface) then return nil end
        kill_entity(entity)
    end
    if not world_running(surface) then return nil end
    surface_state.erased_x[x] = true
    return { name = "out-of-map", position = position }
end

local function update_train_catch_up(surface, surface_state)
    surface_state.catch_up = false
    if not catch_up_api then return end
    local force = catch_up_api.get_owner_force(surface)
    if not (force and force.valid and cave_teams.force_is_running(force)) then return end
    local locomotive = catch_up_api.get_main_locomotive(force)
    if not (locomotive and locomotive.valid and locomotive.force == force
        and locomotive.surface == surface) then return end

    -- Compare the live front with the train's current absolute coordinates.
    -- Never retain a player or train's furthest point.
    local distance = math.abs(math.abs(surface_state.line_y) - math.abs(locomotive.position.y))
    surface_state.catch_up = distance > CATCH_UP_DISTANCE
end

local function collapse_parameters(surface, surface_state)
    local players = connected_count(surface)
    local amount = math.floor(players * 0.25 + 2)
    amount = math.max(4, math.min(10, amount))

    local speed = 8
    if players > 35 then
        speed = 5
    elseif players > 20 then
        speed = 6
    elseif players > 8 then
        speed = 7
    end

    if surface_state.catch_up then
        amount = 10
        speed = 1
    end
    return amount, speed
end

local function update_progress_anchors()
    local state = root()
    if not (state and state.surfaces) then return end
    for _, player in pairs(game.connected_players) do
        local surface = physical.surface(player)
        if physical.character_context(player) and zones.is_main_surface(surface) then
            local surface_state = add_surface(surface)
            if surface_state then
                local y = physical.position(player) and physical.position(player).y or 0
                -- Retained for the assault's existing fallback target only;
                -- player exploration never controls terrain deletion speed.
                surface_state.progress_y = math.min(surface_state.progress_y or y, y)
                remember_safe_position(player, surface_state)
            end
        end
    end
end

local function commit_terrain(surface, surface_state, tick, force)
    local tiles = surface_state.pending_collapse_tiles
    if not (tiles and #tiles > 0) then return end
    local due = tonumber(surface_state.next_tile_commit_tick) or tick
    if not force and tick < due then return end
    local deferred
    local follow = surface_state.clearing
    if zones.is_active() and world_running(surface)
        and follow and type(follow.follow_line_y) == "number" then
        if force then clearing.prepare_commit(surface, surface_state) end
        local completed = clearing.completed_line(surface_state)
        for _ = 1, clearing.COMMIT_ROWS do
            if follow.follow_line_y <= completed then break end
            if not clearing.advance_row(surface, surface_state) then break end
        end
        -- Finish a southern row only after its matching northern strip is
        -- ready in this tick. Partial-row erosion keeps the original cadence.
        local ready = {}
        local waiting = follow.follow_line_y > completed
        for _, tile in ipairs(tiles) do
            local y = tile.position.y or tile.position[2]
            if y > follow.follow_line_y or (not waiting and y == follow.follow_line_y) then
                ready[#ready + 1] = tile
            else
                deferred = deferred or {}
                deferred[#deferred + 1] = tile
            end
        end
        tiles = ready
    end
    -- Preserve native collision cleanup for rails, trains and newly built
    -- entities on already-eroded cells, then update the Cave mirror once.
    if #tiles > 0 then
        surface.set_tiles(tiles, true, true)
        mirror.set_tiles(surface, tiles)
    end
    surface_state.pending_collapse_tiles = deferred
    -- A large catch-up batch drains in paired steps of at most two rows;
    -- new batches retain the pathfinding-safe 256-tick interval.
    surface_state.next_tile_commit_tick = deferred and (tick + 1)
        or (not force and (tick + TERRAIN_COMMIT_TICKS) or nil)
end

local function commit_all_terrain(state, tick)
    for index, surface_state in pairs(state and state.surfaces or {}) do
        local surface = game.get_surface(index)
        if surface and surface.valid then commit_terrain(surface, surface_state, tick, true) end
    end
end

local function process_surface(surface, surface_state, tick, amount, speed)
    if not (surface and surface.valid and surface_state) then return end
    if not amount or not speed then amount, speed = collapse_parameters(surface, surface_state) end
    if tick % speed ~= 0 then return end

    if not surface_state.row_order then
        surface_state.row_order = row_order(surface, surface_state.line_y)
        surface_state.row_cursor = 1
        surface_state.erased_x = {}
    end

    local tiles = {}
    for _ = 1, amount do
        local x = surface_state.row_order[surface_state.row_cursor]
        if x == nil then
            surface_state.line_y = surface_state.line_y - 1
            surface_state.row_order = nil
            surface_state.row_cursor = 1
            surface_state.erased_x = {}
            break
        end
        surface_state.row_cursor = surface_state.row_cursor + 1
        tiles[#tiles + 1] = erase_tile(surface, surface_state, x)
        if not world_running(surface) then return end
    end

    if #tiles > 0 then
        local pending = surface_state.pending_collapse_tiles or {}
        surface_state.pending_collapse_tiles = pending
        surface_state.next_tile_commit_tick = surface_state.next_tile_commit_tick
            or (tick + TERRAIN_COMMIT_TICKS)
        for _, tile in ipairs(tiles) do pending[#pending + 1] = tile end
    end
end

local function move_hidden_line_to_guard_boundary(surface_state)
    if not surface_state then return end
    if (surface_state.line_y or zones.COLLAPSE_START_Y) <= zones.SOUTH_GUARD_LINE_Y then
        return
    end
    surface_state.line_y = zones.SOUTH_GUARD_LINE_Y
    surface_state.row_order = nil
    surface_state.row_cursor = 1
    surface_state.erased_x = {}
end

local function start_collapse(surface, surface_state)
    if not surface_state or surface_state.phase == "active" then return end
    move_hidden_line_to_guard_boundary(surface_state)
    surface_state.phase = "active"
    surface_state.remaining_ticks = 0
    surface_state.started_tick = game.tick
    local owner = cave_worlds.owner_force(surface)
    for _, player in pairs(game.connected_players) do
        local force = cave_teams.player_force(player)
        if force == owner or (force and cave_teams.home_surface(force) == surface) then
            destroy_gui(player)
            player.print({ "the-cave-advancing-collapse.started" }, { color = { r = 1, g = 0.08, b = 0.04 } })
            player.play_sound { path = "utility/new_objective", volume_modifier = 1 }
        end
    end
    assault.begin_surface(surface, surface_state, game.tick)
end

-- Arrival owns the clock. A freshly copied world remains inert until then.
function advancing.start_world(surface)
    if not zones.is_active() then return end
    local existing = root().surfaces and root().surfaces[surface.index]
    local surface_state = add_surface(surface)
    if not surface_state then return end
    local map_gen = surface.map_gen_settings
    if map_gen.width ~= zones.ZONE_WIDTH then
        map_gen.width = zones.ZONE_WIDTH
        surface.map_gen_settings = map_gen
    end
    if not existing then
        south_guard.schedule_surface(surface, false)
        clearing.prepare(surface, surface_state)
        recovery.enforce_surface(surface)
        area.update_visuals(surface, surface_state, surface_state, game.tick)
    end
    refresh_all_guis(true)
end

function advancing.reset_world(surface)
    local state = root()
    if not (state and surface) then return end
    local surface_state = state.surfaces and state.surfaces[surface.index]
    if surface_state then
        area.destroy_visuals(surface_state)
        south_guard.drop_surface(surface_state)
        assault.drop_surface(surface_state)
    end
    state.surfaces[surface.index] = nil
    if state.safe_respawns then state.safe_respawns[surface.index] = nil end
end

function advancing.clear_force(force_index)
    local state = root()
    if not state then return end
    for _, by_force in pairs(state.safe_respawns or {}) do by_force[force_index] = nil end
    if state.highest_zone_by_force then state.highest_zone_by_force[force_index] = nil end
    for _, player in pairs(game.players) do
        if player.force.index == force_index and state.player_current_zones then
            state.player_current_zones[player.index] = nil
            destroy_gui(player)
        end
    end
end

function advancing.destroy_visuals()
    area.destroy_all_visuals(root())
end

function advancing.on_init()
    advancing.destroy_visuals()
    destroy_all_guis()
    if not zones.setting_enabled() then
        storage.the_cave_advancing_collapse = nil
        return
    end

    if storage.mid_save_install then
        storage.the_cave_advancing_collapse = {
            initialized = false,
            blocked_mid_save = true,
        }
        return
    end

    storage.the_cave_advancing_collapse = {
        initialized = true,
        surfaces = {},
        safe_respawns = {},
        player_current_zones = {},
        highest_zone_by_force = {},
    }
    zones.initialize(storage.the_cave_advancing_collapse, true)
    refresh_all_guis(true)
end

function advancing.on_configuration_changed()
    local state = root()
    commit_all_terrain(state, game.tick)
    advancing.destroy_visuals()
    if not zones.setting_enabled() or not (state and state.initialized) then
        destroy_all_guis()
        return
    end
    state.surfaces = state.surfaces or {}
    state.safe_respawns = state.safe_respawns or {}
    state.player_current_zones = state.player_current_zones or {}
    state.highest_zone_by_force = state.highest_zone_by_force or {}
    -- Only worlds already present inherit the running 3.3.1 clock.
    -- New copies always receive their own full countdown on arrival.
    for _, surface_state in pairs(state.surfaces) do
        if not surface_state.phase then
            surface_state.phase = state.phase or "countdown"
            surface_state.remaining_ticks = state.remaining_ticks or COUNTDOWN_TICKS
            surface_state.started_tick = state.started_tick
        end
        if surface_state.phase == "active" then move_hidden_line_to_guard_boundary(surface_state) end
    end
    state.phase, state.remaining_ticks, state.started_tick, state.last_gui_second = nil, nil, nil, nil
    for _, by_force in pairs(state.safe_respawns) do
        local names = {}
        for key in pairs(by_force) do
            if type(key) == "string" then names[#names + 1] = key end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local force = game.forces[name]
            if force then by_force[force.index] = by_force[force.index] or by_force[name] end
            by_force[name] = nil
        end
    end
    zones.repair()
    for _, surface_state in pairs(state.surfaces) do
        -- Re-evaluate after all runtime modules finish configuration migration.
        surface_state.catch_up = nil
        clearing.initialize_follow(surface_state)
        if surface_state.clearing then surface_state.clearing.prepared_strip = nil end
    end
    update_progress_anchors()
    south_guard.on_configuration_changed()
    assault.on_configuration_changed()
    for index, surface_state in pairs(state.surfaces) do
        local surface = game.get_surface(index)
        if surface and surface.valid and world_running(surface) then
            recovery.enforce_surface(surface)
            area.update_visuals(surface, surface_state, surface_state, game.tick)
        end
    end
    refresh_all_guis(true)
end

-- The top-level defeat guard stops ordinary controllers before on_tick.
function advancing.flush_pending_terrain()
    commit_all_terrain(root(), game.tick)
end

function advancing.on_world_ready()
    local state = root()
    if not (zones.is_active() and state) then return end
    south_guard.on_world_ready()
    for index, surface_state in pairs(state.surfaces or {}) do
        local surface = game.get_surface(index)
        if surface and world_running(surface) and surface_state.phase == "countdown" then
            clearing.prepare(surface, surface_state)
            recovery.enforce_surface(surface)
            area.update_visuals(surface, surface_state, surface_state, game.tick)
        end
    end
end

function advancing.on_tick(event)
    local state = root()
    if not (zones.is_active() and state) then return end
    if main_train_defeat.blocks_all() then
        commit_all_terrain(state, event.tick)
        return
    end
    south_guard.on_tick(event)
    if event.tick % 60 == 0 then update_progress_anchors() end
    for surface_index, surface_state in pairs(state.surfaces or {}) do
        local surface = game.get_surface(surface_index)
        if surface and surface.valid and world_running(surface) and connected_count(surface) > 0 then
            clearing.on_tick(surface, surface_state)
            if surface_state.phase == "countdown" then
                area.prepare_supplies(surface, surface_state, surface_state, event.tick)
                surface_state.remaining_ticks = math.max(0, (surface_state.remaining_ticks or COUNTDOWN_TICKS) - 1)
                if surface_state.remaining_ticks == 0 then start_collapse(surface, surface_state) end
            elseif surface_state.phase == "active" then
                if surface_state.catch_up == nil or event.tick % CATCH_UP_CHECK_TICKS == 0 then
                    update_train_catch_up(surface, surface_state)
                end
                local amount, speed = collapse_parameters(surface, surface_state)
                assault.on_tick(surface, surface_state, event.tick, amount, speed)
                local resting = recovery.is_resting(surface_state)
                if not resting and clearing.can_erode(surface_state) then
                    process_surface(surface, surface_state, event.tick, amount, speed)
                end
                commit_terrain(surface, surface_state, event.tick, resting)
            end
            area.update_visuals(surface, surface_state, surface_state, event.tick)
        elseif surface and surface.valid then
            commit_terrain(surface, surface_state, event.tick, true)
        end
    end
    if event.tick % 60 == 0 then refresh_all_guis(false) end
end

function advancing.on_player_created(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    local state = player_world_state(player)
    local seconds = state and math.ceil(math.max(0, state.remaining_ticks or 0) / 60) or 0
    if state and state.phase == "active" then show_zone_gui(player)
    else show_gui(player, seconds) end
end

function advancing.on_player_joined_game(event)
    advancing.on_player_created(event)
end

function advancing.on_player_respawned(event)
    local state = root()
    if not (zones.is_active() and state) then return end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid and physical.surface(player) and zones.is_main_surface(physical.surface(player))) then return end

    local surface_state = add_surface(physical.surface(player))
    if not surface_state or surface_state.phase ~= "active" then return end
    if position_is_respawn_safe(physical.surface(player), surface_state, physical.position(player)) then
        remember_safe_position(player, surface_state)
        show_zone_gui(player)
        return
    end

    local destination = find_safe_respawn(player, surface_state)
    if not destination then return end
    local ok, teleported = pcall(function()
        return physical.teleport(player, destination, physical.surface(player))
    end)
    if ok and teleported ~= false then
        remember_safe_position(player, surface_state)
        show_zone_gui(player)
    end
end

function advancing.on_display_changed(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    local state = player_world_state(player)
    if not (player and state) then return end
    if state.phase == "active" then
        show_zone_gui(player)
        local active_frame = player.gui.screen[FRAME_NAME]
        position_gui(player, active_frame)
        return
    end
    if state.phase ~= "countdown" then return end
    local seconds = math.ceil(math.max(0, state.remaining_ticks or 0) / 60)
    show_gui(player, seconds)
    local frame = player.gui.screen[FRAME_NAME]
    position_gui(player, frame)
end

function advancing.on_surface_created(event)
    -- Registration and the first character arrival run after surface creation.
end

function advancing.on_surface_deleted(event)
    local state = root()
    if state and state.surfaces and event and event.surface_index then
        area.destroy_visuals(state.surfaces[event.surface_index])
        state.surfaces[event.surface_index] = nil
        if state.safe_respawns then state.safe_respawns[event.surface_index] = nil end
    end
end

function advancing.on_research_finished(event)
    local family = zones.on_research_finished(event)
    if family then
        game.print(
            { "the-cave-advancing-collapse.zone-unlocked", { "the-cave-advancing-collapse.family-" .. family } },
            { r = 0.25, g = 0.9, b = 1 }
        )
    end
end

function advancing.on_research_reversed(event)
    zones.on_research_reversed(event)
end

function advancing.configure_assault_objective_api(api)
    assault.configure_objective_api(api)
end

function advancing.on_entity_spawned(event) assault.on_entity_spawned(event) end
function advancing.on_entity_died(event) assault.on_entity_died(event) end

function advancing.configure_start_area_api(api)
    area.configure_start_api(api)
end

function advancing.configure_catch_up_api(api)
    assert(type(api) == "table" and type(api.get_owner_force) == "function"
        and type(api.get_main_locomotive) == "function",
        "advancing collapse catch-up API requires owner force and Main Locomotive lookups")
    catch_up_api = api
end

function advancing.register_commands()
    assault.register_commands()
end

return advancing
