local cave_teams = require("scripts.cave_teams")
local physical = require("scripts.player_physical")
-- Southern one-way boundary for The Cave: Advancing Collapse.
--
-- Mountain Fortress uses a visible electric boundary, a hostile strip and
-- then out-of-map terrain behind the starting area.  This self-contained
-- implementation keeps the same readability without importing its wave
-- defence: guard units visibly patrol at all times, attack only players who
-- cross the line, return to patrol after the player retreats, and remain
-- permanently leashed south of the electric boundary.
local hash = require("scripts.lib.hash")
local mirror = require("scripts.lib.mirror")
local zones = require("scripts.advancing_zones")

local guard = {}

local LINE_Y = zones.SOUTH_GUARD_LINE_Y
local VOID_Y = zones.SOUTH_VOID_Y
local MIN_X = -math.floor(zones.ZONE_WIDTH / 2)
local MAX_X = MIN_X + zones.ZONE_WIDTH - 1
local UNIT_STREAM = 7901
local FLOOR_STREAM = 7902
local PATROL_STREAM = 7903
local BUILD_DELAY = 120
local TICK_INTERVAL = 30
local ACTIVE_X_RADIUS = 84
local WARNING_COOLDOWN = 10 * 60
local PATROL_MIN_TICKS = 4 * 60
local PATROL_MAX_TICKS = 8 * 60

local UNIT_RAFFLE = {
    "small-biter", "small-biter", "small-biter", "small-spitter",
    "medium-biter", "medium-biter", "medium-spitter",
    "big-biter", "big-spitter",
    "behemoth-biter", "behemoth-spitter",
}

local FLOOR_RAFFLE = {
    "dirt-5", "dirt-6", "dirt-7",
    "red-desert-2", "red-desert-3",
}

local function root()
    return storage and storage.the_cave_advancing_collapse or nil
end

local function surface_state(surface)
    local state = root()
    return state and state.surfaces and surface and state.surfaces[surface.index] or nil
end

local function valid(object)
    return object and object.valid
end

local function destroy_objects(objects)
    for _, object in pairs(objects or {}) do
        if valid(object) then pcall(function() object.destroy() end) end
    end
end

local function clear_visuals(state)
    if not state then return end
    destroy_objects(state.south_guard_beams)
    destroy_objects(state.south_guard_renders)
    state.south_guard_beams = {}
    state.south_guard_renders = {}
end

local function generated_guard_chunks(surface)
    for chunk_x = math.floor(MIN_X / 32), math.floor(MAX_X / 32) do
        for chunk_y = math.floor(LINE_Y / 32), math.floor(zones.COLLAPSE_START_Y / 32) do
            surface.request_to_generate_chunks(
                { x = chunk_x * 32 + 16, y = chunk_y * 32 + 16 },
                0
            )
        end
    end
    surface.force_generate_chunk_requests()
end

local function has_player_presence(surface)
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { MIN_X, LINE_Y }, { MAX_X + 1, zones.COLLAPSE_START_Y + 1 } },
    }) do
        local force = entity.force
        if entity.type == "character"
            or (force and force.valid and force.name ~= "neutral" and force.name ~= "enemy") then
            return true
        end
    end
    return false
end

local function clear_generated_entities(surface)
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { MIN_X, LINE_Y }, { MAX_X + 1, zones.COLLAPSE_START_Y + 1 } },
    }) do
        if valid(entity) then
            if entity.name == "diggy-rock" or entity.name == "diggy-rubble" then
                mirror.set_rock(surface, entity.position, false)
            end
            pcall(function() entity.destroy() end)
        end
    end
end

local function guard_floor(seed, x, y)
    if y == LINE_Y or y == LINE_Y + 1 then
        return (x + y) % 2 == 0 and "hazard-concrete-left" or "hazard-concrete-right"
    end
    return FLOOR_RAFFLE[hash.range(seed, x, y, FLOOR_STREAM, 1, #FLOOR_RAFFLE)]
end

local function build_tiles(surface)
    local seed = surface.map_gen_settings and surface.map_gen_settings.seed or 0
    local tiles = {}
    for x = MIN_X, MAX_X do
        for y = LINE_Y, VOID_Y - 1 do
            tiles[#tiles + 1] = {
                name = guard_floor(seed, x, y),
                position = { x = x, y = y },
            }
        end
        for y = VOID_Y, zones.COLLAPSE_START_Y do
            tiles[#tiles + 1] = {
                name = "out-of-map",
                position = { x = x, y = y },
            }
        end
    end
    surface.set_tiles(tiles, true, true)
    mirror.set_tiles(surface, tiles)
end

local function lock_entity(entity, active)
    if not valid(entity) then return end
    pcall(function() entity.destructible = false end)
    pcall(function() entity.protected = true end)
    pcall(function() entity.minable_flag = false end)
    pcall(function() entity.operable = false end)
    pcall(function() entity.disabled_by_script = not active end)
end

local function create_guard_entity(surface, parameters, active)
    if not surface.can_place_entity(parameters) then return nil end
    local entity = surface.create_entity(parameters)
    lock_entity(entity, active)
    return entity
end

local function build_units(surface, state)
    local seed = surface.map_gen_settings and surface.map_gen_settings.seed or 0
    state.south_guard_units = {}

    -- Four staggered ranks make the forbidden area visibly occupied. Patrol
    -- commands are staggered so the active guards do not all path on one tick.
    for row = 0, 3 do
        local y = LINE_Y + 8 + row * 10
        local first_x = MIN_X + 3 + (row % 2) * 3
        for x = first_x, MAX_X - 3, 6 do
            local name = UNIT_RAFFLE[hash.range(seed, x, y, UNIT_STREAM, 1, #UNIT_RAFFLE)]
            local unit = create_guard_entity(surface, {
                name = name,
                position = { x = x + 0.5, y = y + 0.5 },
                force = "enemy",
            }, true)
            if unit then
                local unit_index = #state.south_guard_units + 1
                state.south_guard_units[unit_index] = {
                    entity = unit,
                    home = { x = unit.position.x, y = unit.position.y },
                    mode = "waiting",
                    patrol_step = 0,
                    -- Spread the initial path requests over five seconds so a
                    -- new map never asks hundreds of units to path at once.
                    next_patrol_tick = (game and game.tick or 0)
                        + hash.range(seed, x, y, PATROL_STREAM, 0, 5 * 60),
                }
            end
        end
    end

    -- Inactive, indestructible nests make the strip look established but can
    -- never create an expansion party or an upward attack wave.
    local spawner_names = { "biter-spawner", "spitter-spawner" }
    for x = MIN_X + 16, MAX_X - 16, 32 do
        create_guard_entity(surface, {
            name = spawner_names[(math.floor((x - MIN_X) / 32) % 2) + 1],
            position = { x = x + 0.5, y = VOID_Y - 11.5 },
            force = "enemy",
        }, false)
    end

    -- Static worms sit far enough behind the line that even their maximum
    -- vanilla range cannot reach a player who remains on the northern side.
    local worm_names = {
        "medium-worm-turret",
        "big-worm-turret",
        "behemoth-worm-turret",
    }
    for x = MIN_X + 10, MAX_X - 10, 20 do
        create_guard_entity(surface, {
            name = worm_names[(math.floor((x - MIN_X) / 20) % #worm_names) + 1],
            position = { x = x + 0.5, y = VOID_Y - 1.5 },
            force = "enemy",
        }, true)
    end
end

local function build_visuals(surface, state)
    clear_visuals(state)
    state.south_guard_beams = {}
    state.south_guard_renders = {}

    -- Mountain Fortress draws the same electric beam three times to give the
    -- border a bright, unmistakable electric-barrier appearance.
    for _ = 1, 3 do
        local ok, beam = pcall(function()
            return surface.create_entity {
                name = "electric-beam",
                position = { x = MIN_X, y = LINE_Y + 0.5 },
                source = { x = MIN_X, y = LINE_Y + 0.5 },
                target = { x = MAX_X + 1, y = LINE_Y + 0.5 },
            }
        end)
        if ok and beam then state.south_guard_beams[#state.south_guard_beams + 1] = beam end
    end

    if rendering and rendering.draw_text then
        for _, x in ipairs({ -170, 0, 170 }) do
            local ok, object = pcall(function()
                return rendering.draw_text {
                    text = { "the-cave-advancing-collapse.south-warning" },
                    surface = surface,
                    target = { x = x, y = LINE_Y - 3 },
                    color = { r = 1, g = 0.32, b = 0.04 },
                    scale = 2.5,
                    font = "heading-1",
                    alignment = "center",
                    scale_with_zoom = false,
                }
            end)
            if ok and object then state.south_guard_renders[#state.south_guard_renders + 1] = object end
        end
    end
end

local function build_surface(surface, migrating)
    if not (zones.is_active() and zones.is_main_surface(surface) and cave_teams.is_world_running(surface)) then return false end
    local state = surface_state(surface)
    if not state or state.south_guard_ready or state.south_guard_skipped_existing_builds then return false end

    -- Once collapse has reached the starting barrier there is nothing left to
    -- build or repair.
    if state.line_y and state.line_y <= LINE_Y then
        clear_visuals(state)
        state.south_guard_ready = true
        state.south_guard_pending_tick = nil
        return false
    end

    generated_guard_chunks(surface)
    if migrating and has_player_presence(surface) then
        state.south_guard_skipped_existing_builds = true
        state.south_guard_pending_tick = nil
        log("[The Cave] Advancing Collapse south guard was not added to surface "
            .. surface.name .. " because player entities already occupy its boundary area.")
        return false
    end

    clear_generated_entities(surface)
    build_tiles(surface)
    build_units(surface, state)
    build_visuals(surface, state)
    state.south_guard_ready = true
    state.south_guard_pending_tick = nil
    state.south_guard_warned_players = {}
    return true
end

local function command_unit(unit, command)
    if not valid(unit) then return false end
    local commanded = false
    pcall(function()
        local commandable = unit.commandable
        if commandable and commandable.valid then
            commandable.set_command(command)
            commanded = true
        end
    end)
    -- Compatibility with Factorio runtime revisions where unit commands were
    -- exposed directly on LuaEntity.
    if not commanded then
        pcall(function()
            if unit.set_command then
                unit.set_command(command)
                commanded = true
            end
        end)
    end
    return commanded
end

local function activate_unit(unit)
    if not valid(unit) then return end
    pcall(function() unit.disabled_by_script = false end)
end

local function attack_player(unit, player)
    if not (valid(unit) and player and player.valid and valid(player.character)) then
        return false
    end
    activate_unit(unit)
    return command_unit(unit, {
        type = defines.command.attack,
        target = player.character,
        distraction = defines.distraction.none,
    })
end

local function normalise_record(value, tick)
    if type(value) == "table" and value.entity then
        value.home = value.home or {
            x = value.entity.position.x,
            y = value.entity.position.y,
        }
        value.mode = value.mode or "waiting"
        value.patrol_step = value.patrol_step or 0
        value.next_patrol_tick = value.next_patrol_tick or tick
        return value
    end
    if valid(value) then
        -- 2.7.7 stored bare LuaEntity references. Converting lazily keeps
        -- existing Advancing Collapse test saves compatible.
        return {
            entity = value,
            home = { x = value.position.x, y = value.position.y },
            mode = "waiting",
            patrol_step = 0,
            next_patrol_tick = tick,
        }
    end
    return nil
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function patrol_unit(surface, record, tick)
    local unit = record.entity
    if not valid(unit) then return false end
    activate_unit(unit)

    local seed = surface.map_gen_settings and surface.map_gen_settings.seed or 0
    record.patrol_step = (record.patrol_step or 0) + 1
    local home_x = math.floor(record.home.x)
    local home_y = math.floor(record.home.y)
    local stream = PATROL_STREAM + record.patrol_step * 11
    local target = {
        x = clamp(
            record.home.x + hash.range(seed, home_x, home_y, stream, -5, 5),
            MIN_X + 3,
            MAX_X - 2
        ),
        y = clamp(
            record.home.y + hash.range(seed, home_x, home_y, stream + 1, -5, 5),
            LINE_Y + 5,
            VOID_Y - 5
        ),
    }
    local commanded = command_unit(unit, {
        type = defines.command.go_to_location,
        destination = target,
        radius = 1.5,
        distraction = defines.distraction.none,
    })
    record.mode = "patrol"
    record.next_patrol_tick = tick
        + hash.range(
            seed,
            home_x,
            record.patrol_step,
            stream + 2,
            PATROL_MIN_TICKS,
            PATROL_MAX_TICKS
        )
    return commanded
end

local function nearest_intruder(unit, intruders)
    local nearest
    local best = ACTIVE_X_RADIUS * ACTIVE_X_RADIUS
    for _, player in ipairs(intruders) do
        if valid(player.character) then
            local dx = unit.position.x - physical.position(player).x
            local dy = unit.position.y - physical.position(player).y
            local distance = dx * dx + dy * dy
            if math.abs(dx) <= ACTIVE_X_RADIUS and distance <= best then
                nearest = player
                best = distance
            end
        end
    end
    return nearest
end

local function warn_intruder(state, player, tick)
    state.south_guard_warned_players = state.south_guard_warned_players or {}
    local last = state.south_guard_warned_players[player.index] or -WARNING_COOLDOWN
    if tick - last < WARNING_COOLDOWN then return end
    state.south_guard_warned_players[player.index] = tick
    player.print(
        { "the-cave-advancing-collapse.south-entered" },
        { r = 1, g = 0.08, b = 0.04 }
    )
    pcall(function()
        player.play_sound { path = "utility/cannot_build", volume_modifier = 1 }
    end)
end

local function control_surface(surface, state, tick)
    if state.line_y and state.line_y <= LINE_Y then
        clear_visuals(state)
        return
    end

    local intruders = {}
    for _, player in pairs(game.connected_players) do
        if valid(player.character) and physical.surface(player) == surface and physical.position(player).y > LINE_Y + 0.5 then
            intruders[#intruders + 1] = player
            warn_intruder(state, player, tick)
        end
    end

    local live_units = {}
    for _, value in pairs(state.south_guard_units or {}) do
        local record = normalise_record(value, tick)
        local unit = record and record.entity
        if valid(unit) then
            activate_unit(unit)
            -- A hard leash makes it impossible for a provoked guard to cross
            -- the electric line, leave either side of the strip, or continue
            -- fighting in the northern base after the player retreats.
            if unit.position.y < LINE_Y + 2
                or unit.position.y > VOID_Y - 2
                or unit.position.x < MIN_X + 1
                or unit.position.x > MAX_X then
                pcall(function()
                    unit.teleport {
                        x = clamp(record.home.x, MIN_X + 3, MAX_X - 2),
                        y = clamp(record.home.y, LINE_Y + 5, VOID_Y - 5),
                    }
                end)
                record.mode = "waiting"
                record.next_patrol_tick = tick
            end
            local target = nearest_intruder(unit, intruders)
            if target then
                attack_player(unit, target)
                record.mode = "attack"
            else
                if record.mode == "attack" then record.next_patrol_tick = tick end
                if tick >= (record.next_patrol_tick or 0) then
                    patrol_unit(surface, record, tick)
                end
            end
            live_units[#live_units + 1] = record
        end
    end
    state.south_guard_units = live_units
end

function guard.drop_surface(state)
    clear_visuals(state)
    for _, record in pairs(state and state.south_guard_units or {}) do
        if valid(record.entity) then record.entity.destroy { raise_destroy = true } end
    end
end

function guard.on_world_ready()
    if not zones.is_active() then return end
    for _, surface in pairs(game.surfaces) do
        if zones.is_main_surface(surface) then build_surface(surface, false) end
    end
end

function guard.schedule_surface(surface, migrating)
    if not (zones.is_active() and zones.is_main_surface(surface) and cave_teams.is_world_running(surface)) then return end
    local state = surface_state(surface)
    if not state or state.south_guard_ready or state.south_guard_skipped_existing_builds then return end
    state.south_guard_pending_tick = game.tick + BUILD_DELAY
    state.south_guard_migrating = migrating == true
end

function guard.on_configuration_changed()
    if not zones.is_active() then return end
    for _, surface in pairs(game.surfaces) do guard.schedule_surface(surface, true) end
end

function guard.on_tick(event)
    if not (zones.is_active() and event and event.tick % TICK_INTERVAL == 0) then return end
    local state = root()
    if not state then return end
    for surface_index, surface_data in pairs(state.surfaces or {}) do
        local surface = game.get_surface(surface_index)
        if surface and surface.valid and cave_teams.is_world_running(surface) then
            if surface_data.south_guard_pending_tick
                and event.tick >= surface_data.south_guard_pending_tick then
                build_surface(surface, surface_data.south_guard_migrating == true)
                surface_data.south_guard_migrating = nil
            end
            if surface_data.south_guard_ready then
                control_surface(surface, surface_data, event.tick)
            end
        end
    end
end

return guard
