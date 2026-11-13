local settings = require("scripts.game_settings").proxy(settings)

-- Train Wave Defense.
--
-- This module is shared by Train Interiors and Shelter Defense. Attackers
-- spawn on the live exterior surface of each force's registered Main
-- Locomotive or Shelter. No Cave Torio, Advancing Collapse, Darkness, mission
-- or general Cave wave system calls this module.

local world = require("scripts.world")
local ore_veins = require("scripts.ore_veins")
local mobile_factory_resources = require("scripts.mobile_factory_resources")
local mirror = require("scripts.lib.mirror")

local wave = {}
-- Keep imported helpers together: this large controller is at Lua's local limit.
wave._teams = { worlds = require("scripts.cave_worlds"),
    state = require("scripts.cave_teams"), defeat = require("scripts.main_train_defeat") }

local caverns_api
local uranium_caves_api
local mineral_caves_api

function wave.configure_extraction_cave_apis(cavern_api, uranium_api, mineral_api)
    assert(type(cavern_api) == "table"
        and type(cavern_api.on_train_wave_tunnel_dig) == "function",
        "The Cave: Train Wave cavern API is unavailable")
    assert(type(uranium_api) == "table"
        and type(uranium_api.on_cavern_opened) == "function",
        "The Cave: Train Wave Uranium Cave API is unavailable")
    assert(type(mineral_api) == "table"
        and type(mineral_api.on_cavern_opened) == "function",
        "The Cave: Train Wave Mineral Cave API is unavailable")
    caverns_api = cavern_api
    uranium_caves_api = uranium_api
    mineral_caves_api = mineral_api
end

local STORAGE_NAME = "the_cave_train_wave_defense"
local STORAGE_VERSION = 8
local UNIT_PREFIX = "the-cave-train-wave-"
local SURFACE_PREFIX = "the-cave-train-interior-"
local FORBIDDEN_SURFACE_PREFIXES = {
    SURFACE_PREFIX,
    "the-cave-shelter-interior-",
    "the-cave-uranium-cave-",
    "the-cave-mineral-cave-",
    "the-cave-fortified-vault-",
}

local GUI_NAME = "the_cave_train_wave_defense"
local GUI_HEADER_FLOW = "the_cave_train_wave_header_flow"
local GUI_TOGGLE = "the_cave_train_wave_toggle"
local GUI_HEADER = "the_cave_train_wave_header"
local GUI_TIMER = "the_cave_train_wave_timer"
local GUI_SCALE = "the_cave_train_wave_scale"
local GUI_INCOMING = "the_cave_train_wave_incoming"
local GUI_ACTIVE = "the_cave_train_wave_active"
local GUI_QUEUE = "the_cave_train_wave_queue"
local GUI_TUNNEL = "the_cave_train_wave_tunnel"
local GUI_BOSS = "the_cave_train_wave_boss"
local GUI_STYLE = {
    layout_version = 2,
    expanded_min_width = 430,
    expanded_min_height = 80,
    toggle_size = 28,
}

local SECOND = 60
local TUNNEL_UPDATE_TICKS = SECOND / 4
local PREPARATION_TICKS = 2 * 60 * 60 * SECOND
local LEGACY_WAVE_INTERVAL_TICKS = 5 * 60 * SECOND
local BREAK_INTERVAL_TICKS = 15 * 60 * SECOND
local MIN_ATTACK_GAP_TICKS = 15 * SECOND
local BATCH_INTERVAL_TICKS = SECOND
local ROUTE_RETRY_TICKS = 10 * SECOND
local SAFETY_CHECK_TICKS = 10 * SECOND
local STUCK_RETRY_TICKS = 30 * SECOND
local COMMAND_REFRESH_TICKS = 30 * SECOND
local PLAYER_AGGRO_RADIUS = 24
wave.max_active_enemy_cap = 1000
wave.active_enemy_buffer = 10
wave.military_target_scan_buckets = 4
wave.military_target_fallback_vision = 30
wave.tunnel_route_lookahead = 8
wave.tunnel_route_cautious_lookahead = 6
-- Route commands must be replaced before Factorio considers their current
-- destination complete.  The old 3-tile command radius combined with a
-- 3.5-tile route check let fast units finish the order between one-second
-- controller updates, producing the visible walk-stop-walk rhythm.
wave.tunnel_route_handoff_radius_squared = 4.5 * 4.5
wave.tunnel_route_command_radius = 0.25
wave.tunnel_rock_redirect_cooldown = 30
wave.tunnel_stall_timeout_ticks = 30 * SECOND
wave.forced_tunnel_angle_spread = math.pi * 0.05
wave.replacement_tunnel_angle_spread = math.pi * 0.25
wave.tunnel_mouth_separation_squared = 32 * 32
wave.train_generation_radius_chunks = 22
wave.train_generation_profile_version = 2
wave.train_cache_route_profile_version = 2
wave.persistent_tunnel_profile_version = 1
wave.tunnel_mouth_repair_version = 1
wave.attack_region_profile_version = 1
wave.tunnel_mouth_radius = 16
wave.tunnel_mouth_spawn_radius = 14
wave.tunnel_width_upgrade_steps_per_update = 4
wave.attack_region_radius_tiles = 5 * 32
wave.attack_region_radius_squared = wave.attack_region_radius_tiles * wave.attack_region_radius_tiles
wave.attack_region_activation_ticks = 5 * 60 * SECOND
wave.attack_region_stop_speed = 0.001

function wave._entity_max_health(entity)
    local maximum = nil
    pcall(function()
        maximum = entity.prototype.get_max_health(entity.quality)
    end)
    return math.max(1, tonumber(maximum) or tonumber(entity and entity.health) or 1)
end

local BOSS_RESERVED_SLOTS = 1
local MAX_ATOMIC_GROUP_SIZE = 150
local ATTACK_GROUP_SPAWN_RADIUS = 8
local MAX_TEST_WAVE = 10000
local SAFE_ZONE_HALF_SIZE = 70
local SPAWN_MIN_DISTANCE = 640
local SPAWN_MAX_DISTANCE = 672
local TUNNEL_MIN_DISTANCE = 640
local TUNNEL_MAX_DISTANCE = 672
local TUNNEL_MAX_STEPS = 900
local TUNNEL_WIDTH = 12
local TUNNEL_STEP_TICKS = TUNNEL_UPDATE_TICKS
local WATER_BRIDGE_SCAN_DISTANCE = 48
local RELOCATE_DISTANCE = 450
local BOSS_BAR_WIDTH = 8
local BOSS_BAR_Y_SCALE = 0.42
local BOSS_CONTROL = {
    blocker_timeout_ticks = 2 * 60 * SECOND,
    blocker_scan_distance = 12,
    blocker_clear_distance = 8,
    blocker_clear_grace_ticks = 3 * SECOND,
    free_stall_distance = 4,
    goal_attack_gap = 3,
    excluded_types = {
        ["character"] = true,
        ["unit"] = true,
        ["combat-robot"] = true,
        ["construction-robot"] = true,
        ["logistic-robot"] = true,
        ["entity-ghost"] = true,
        ["tile-ghost"] = true,
        ["locomotive"] = true,
        ["cargo-wagon"] = true,
        ["fluid-wagon"] = true,
        ["artillery-wagon"] = true,
    },
}
local SAFE_ZONE_LINE_WIDTH = 2
local SAFE_ZONE_LINE_COLOR = { r = 1, g = 0.78, b = 0.08, a = 0.92 }
local TRAIN_CACHE_HALF_WIDTH = 5
local TRAIN_CACHE_HALF_HEIGHT = 2
local TRAIN_SITE_SPAWN_MARGIN = 2
local TRAIN_SITE_TUNNEL_MARGIN = 4
local ROLLING_STOCK_PROTECTION_RADIUS = 10
local ROLLING_STOCK_TYPES = {
    "locomotive",
    "cargo-wagon",
    "fluid-wagon",
    "artillery-wagon",
}

local TIERS = { "small", "medium", "big", "behemoth" }
local SECTOR_ANGLES = {
    -math.pi * 0.5,
    -math.pi * 0.25,
    0,
    math.pi * 0.25,
    math.pi * 0.5,
    math.pi * 0.75,
    math.pi,
    math.pi * 1.25,
}
local SECTOR_NAMES = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function valid(object)
    return object and object.valid
end

function wave._active_cap(total)
    total = math.max(0, math.floor(tonumber(total) or 0))
    return math.min(wave.max_active_enemy_cap, total + wave.active_enemy_buffer)
end

function wave._current_active_cap(state)
    if state and tonumber(state.active_enemy_cap) then
        return math.max(wave.active_enemy_buffer,
            math.min(wave.max_active_enemy_cap, math.floor(state.active_enemy_cap)))
    end
    local plan = state and state.last_wave_plan
    return wave._active_cap(plan and plan.total or 0)
end

local function feature_enabled()
    local startup = settings and settings.startup
    local train_setting = startup and startup["the-cave-train-interiors"]
    local shelter_setting = startup and startup["the-cave-shelter-defense"]
    local train_requested = train_setting
        and (train_setting.value == "enabled" or train_setting.value == true)
    local shelter_requested = shelter_setting
        and (shelter_setting.value == "enabled" or shelter_setting.value == true)
    local enabled = train_requested and not shelter_requested
    local incompatible = script and script.active_mods and script.active_mods["immersive_locomotives_fork"] ~= nil
    return enabled and not incompatible
end

function wave._shelter_wave_mode_enabled()
    local startup = settings and settings.startup
    local train_setting = startup and startup["the-cave-train-interiors"]
    local shelter_setting = startup and startup["the-cave-shelter-defense"]
    local train_requested = train_setting
        and (train_setting.value == "enabled" or train_setting.value == true)
    local shelter_requested = shelter_setting
        and (shelter_setting.value == "enabled" or shelter_setting.value == true)
    local shelter = storage and storage.the_cave_shelter_core
    return settings.wave_defense_enabled()
        and shelter_requested and not train_requested
        and shelter and shelter.new_game_enabled == true
end

local function is_forbidden_surface(surface)
    if not (surface and surface.valid and type(surface.name) == "string") then return true end
    for _, prefix in ipairs(FORBIDDEN_SURFACE_PREFIXES) do
        if surface.name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function startup_mode_enabled(name)
    local setting = settings and settings.startup and settings.startup[name]
    return setting and (setting.value == "enabled" or setting.value == true) or false
end

local function normal_train_wave_mode_enabled()
    return settings.wave_defense_enabled()
        and (feature_enabled() or wave._shelter_wave_mode_enabled())
        and not startup_mode_enabled("the-cave-cavetorio")
        and not startup_mode_enabled("the-cave-advancing-collapse")
end

local function is_tunnel_surface(surface)
    if is_forbidden_surface(surface) then return false end
    -- This fallback belongs only to the normal Train Interiors experiment.
    -- CAVETORIO and Advancing Collapse keep their own terrain rules.
    if startup_mode_enabled("the-cave-cavetorio")
        or startup_mode_enabled("the-cave-advancing-collapse") then
        return false
    end
    return wave._teams.worlds.is_cave_world(surface)
end

local function new_force_state()
    return {
        phase = "preparation",
        remaining_ticks = PREPARATION_TICKS,
        wave = 0,
        units = {},
        queue = {},
        queue_cursor = 1,
        tunnels = {},
        canonical_tunnel_ids = {},
        tunnel_retry_profiles = {},
        attack_regions = {},
        active_attack_region_id = nil,
        next_attack_region_id = 1,
        attack_region_candidate_started_tick = nil,
        attack_region_candidate_ready = false,
        attack_region_profile_version = nil,
        next_tunnel_id = 1,
        tunnel_announced_waves = {},
        tunnel_breached_waves = {},
        spawn_wait_ticks = 0,
        safety_wait_ticks = SAFETY_CHECK_TICKS,
        command_wait_ticks = COMMAND_REFRESH_TICKS,
        tunnel_reserve_retry_tick = 0,
        warnings = {},
        attack_events = {},
        attack_event_cursor = 1,
        wave_elapsed_ticks = 0,
        wave_duration_ticks = 0,
        next_burst_id = 1,
        boss_wave_active = false,
        boss_total = 0,
        boss_spawned = 0,
        boss_killed = 0,
        boss_pending = false,
        boss_targets = {},
        boss_sectors = {},
        boss_next_delay_ticks = 0,
        boss_active = nil,
        waiting_for_locomotive = false,
        route_blocked = false,
        last_single_sectors = {},
        informed_players = {},
        player_aggro_groups = {},
        tunnel_profile_version = 4,
        persistent_tunnel_profile_version = wave.persistent_tunnel_profile_version,
        train_generation_profile_version = wave.train_generation_profile_version,
        train_generation_surface_index = nil,
        train_generation_chunk_x = nil,
        train_generation_chunk_y = nil,
        train_cache_route_profile_version = wave.train_cache_route_profile_version,
        tunnel_mouth_repair_version = wave.tunnel_mouth_repair_version,
        last_wave_plan = nil,
        test_player_count_override = nil,
        debug_player_index = nil,
        safe_zone_render = nil,
    }
end

local function root_state()
    storage[STORAGE_NAME] = storage[STORAGE_NAME] or {
        version = STORAGE_VERSION,
        forces = {},
    }
    local root = storage[STORAGE_NAME]
    root.forces = root.forces or {}
    return root
end

local function force_state(force)
    if not (force and force.valid) then return nil end
    local root = root_state()
    root.forces[force.index] = root.forces[force.index] or new_force_state()
    local state = root.forces[force.index]
    state.phase = state.phase == "preparation" and "preparation"
        or state.phase == "break" and "break"
        or state.phase == "boss" and "boss" or "countdown"
    state.remaining_ticks = tonumber(state.remaining_ticks) or PREPARATION_TICKS
    state.wave = math.max(0, math.floor(tonumber(state.wave) or 0))
    state.units = state.units or {}
    state.queue = state.queue or {}
    state.queue_cursor = math.max(1, math.floor(tonumber(state.queue_cursor) or 1))
    state.tunnels = state.tunnels or {}
    state.canonical_tunnel_ids = state.canonical_tunnel_ids or {}
    state.tunnel_retry_profiles = state.tunnel_retry_profiles or {}
    state.attack_regions = state.attack_regions or {}
    state.next_attack_region_id = math.max(1,
        math.floor(tonumber(state.next_attack_region_id) or 1))
    state.attack_region_candidate_ready = state.attack_region_candidate_ready == true
    state.next_tunnel_id = math.max(1, math.floor(tonumber(state.next_tunnel_id) or 1))
    state.tunnel_announced_waves = state.tunnel_announced_waves or {}
    state.tunnel_breached_waves = state.tunnel_breached_waves or {}
    state.spawn_wait_ticks = tonumber(state.spawn_wait_ticks) or 0
    state.safety_wait_ticks = tonumber(state.safety_wait_ticks) or SAFETY_CHECK_TICKS
    state.command_wait_ticks = tonumber(state.command_wait_ticks) or COMMAND_REFRESH_TICKS
    state.tunnel_reserve_retry_tick = tonumber(state.tunnel_reserve_retry_tick) or 0
    state.eight_tunnel_reserved_wave = tonumber(state.eight_tunnel_reserved_wave)
    state.warnings = state.warnings or {}
    state.attack_events = state.attack_events or {}
    state.attack_event_cursor = math.max(1, math.floor(tonumber(state.attack_event_cursor) or 1))
    state.wave_elapsed_ticks = math.max(0, tonumber(state.wave_elapsed_ticks) or 0)
    state.wave_duration_ticks = math.max(0, tonumber(state.wave_duration_ticks) or 0)
    state.next_burst_id = math.max(1, math.floor(tonumber(state.next_burst_id) or 1))
    state.boss_wave_active = state.boss_wave_active == true
    state.boss_total = math.max(0, math.floor(tonumber(state.boss_total) or 0))
    state.boss_spawned = math.max(0, math.floor(tonumber(state.boss_spawned) or 0))
    state.boss_killed = math.max(0, math.floor(tonumber(state.boss_killed) or 0))
    state.boss_pending = state.boss_pending == true
    state.active_enemy_cap = wave._current_active_cap(state)
    state.boss_targets = state.boss_targets or {}
    state.boss_sectors = state.boss_sectors or {}
    state.boss_next_delay_ticks = math.max(0, tonumber(state.boss_next_delay_ticks) or 0)
    if type(state.boss_active) ~= "table" then state.boss_active = nil end
    state.last_single_sectors = state.last_single_sectors or {}
    state.informed_players = state.informed_players or {}
    state.player_aggro_groups = state.player_aggro_groups or {}
    if state.tunnel_profile_version ~= 4 then
        for _, tunnel in pairs(state.tunnels or {}) do
            if tunnel then
                -- Every legacy regular and Boss route becomes the same exact
                -- twelve-tile passage without restarting its queued Wave. The
                -- existing route is widened incrementally by process_tunnels
                -- so an old long tunnel cannot freeze the server on upgrade.
                tunnel.width = TUNNEL_WIDTH
                tunnel.pending = nil
                tunnel.step_wait_ticks = math.min(
                    tonumber(tunnel.step_wait_ticks) or TUNNEL_STEP_TICKS,
                    TUNNEL_STEP_TICKS
                )
                local first_route = type(tunnel.route) == "table" and tunnel.route[1] or nil
                local mouth = tunnel.mouth_position or first_route or tunnel.deployment_position
                if mouth then
                    -- Use an integer grid intersection as the chamber centre.
                    -- With a radius of 16, tile centres then rasterise to an
                    -- exact 32-by-32 circular footprint rather than 33 tiles.
                    tunnel.mouth_position = {
                        x = math.floor(mouth.x) + 1,
                        y = math.floor(mouth.y) + 1,
                    }
                    tunnel.mouth_upgrade_pending = true
                end
                tunnel.width_upgrade_index = 1
            end
        end
        state.tunnel_profile_version = 4
    end
    return state
end

local function connected_players(force)
    local players = {}
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid and player.force == force then
            players[#players + 1] = player
        end
    end
    return players
end

local function announce(force, message, sound)
    if not (force and force.valid) then return end
    force.print(message)
    if not sound then return end
    for _, player in ipairs(connected_players(force)) do
        pcall(function()
            player.play_sound { path = sound, volume_modifier = 1 }
        end)
    end
end

local function format_time(ticks)
    local seconds = math.max(0, math.ceil((tonumber(ticks) or 0) / SECOND))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function position_distance_squared(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

local function position_inside_safe_zone(locomotive, position)
    if not (valid(locomotive) and position) then return true end
    return math.abs(position.x - locomotive.position.x) <= SAFE_ZONE_HALF_SIZE
        and math.abs(position.y - locomotive.position.y) <= SAFE_ZONE_HALF_SIZE
end

local function position_outside_safe_zone(locomotive, position)
    return not position_inside_safe_zone(locomotive, position)
end

function wave._shelter_attack_chunks(force)
    local level = 0
    if force and force.valid and force.technologies then
        for index = 1, 8 do
            local technology = force.technologies["the-cave-shelter-attack-distance-" .. index]
            if technology and technology.researched then level = index end
        end
    end
    return 10 + level * 2
end

function wave._spawn_distance_bounds(locomotive)
    if valid(locomotive) and locomotive.name == "the-cave-shelter" then
        local chunks = wave._shelter_attack_chunks(locomotive.force)
        return chunks * 32, (chunks + 1) * 32
    end
    return SPAWN_MIN_DISTANCE, SPAWN_MAX_DISTANCE
end

function wave._generation_radius_chunks(locomotive)
    if valid(locomotive) and locomotive.name == "the-cave-shelter" then
        return wave._shelter_attack_chunks(locomotive.force) + 2
    end
    return wave.train_generation_radius_chunks
end

local function position_inside_spawn_ring(locomotive, position)
    if not (valid(locomotive) and position and position_outside_safe_zone(locomotive, position)) then
        return false
    end
    local minimum, maximum = wave._spawn_distance_bounds(locomotive)
    local distance_squared = position_distance_squared(position, locomotive.position)
    return distance_squared >= minimum * minimum
        and distance_squared <= maximum * maximum
end

local function train_cache_chunk_key(x, y)
    return tostring(math.floor(x / 32)) .. ":" .. tostring(math.floor(y / 32))
end

local function refresh_train_cache_site_index()
    local interiors = storage.the_cave_train_interiors
    local source = interiors and interiors.cache_centers or {}
    local root = root_state()
    local index = root.train_cache_site_index
    if not index or (tonumber(index.source_count) or 0) > #source then
        index = { source_count = 0, by_surface = {} }
        root.train_cache_site_index = index
    end
    index.by_surface = index.by_surface or {}
    for source_index = (tonumber(index.source_count) or 0) + 1, #source do
        local cache = source[source_index]
        if cache and cache.surface_index and cache.x and cache.y then
            local surface_sites = index.by_surface[cache.surface_index]
            if not surface_sites then
                surface_sites = {}
                index.by_surface[cache.surface_index] = surface_sites
            end
            local key = train_cache_chunk_key(cache.x, cache.y)
            surface_sites[key] = surface_sites[key] or {}
            surface_sites[key][#surface_sites[key] + 1] = {
                x = cache.x,
                y = cache.y,
            }
        end
    end
    index.source_count = #source
    return index.by_surface
end

local function position_inside_known_train_cache(surface, position, margin)
    if not (surface and surface.valid and position) then return false end
    margin = math.max(0, tonumber(margin) or 0)
    local sites = refresh_train_cache_site_index()[surface.index]
    if not sites then return false end
    local chunk_x = math.floor(position.x / 32)
    local chunk_y = math.floor(position.y / 32)
    for offset_x = -1, 1 do
        for offset_y = -1, 1 do
            local bucket = sites[tostring(chunk_x + offset_x) .. ":" .. tostring(chunk_y + offset_y)]
            for _, cache in ipairs(bucket or {}) do
                if math.abs(position.x - cache.x) <= TRAIN_CACHE_HALF_WIDTH + margin
                    and math.abs(position.y - cache.y) <= TRAIN_CACHE_HALF_HEIGHT + margin then
                    return true
                end
            end
        end
    end
    return false
end

local function position_inside_protected_train_site(surface, position, margin)
    if not (surface and surface.valid and position) then return true end
    margin = math.max(0, tonumber(margin) or 0)

    -- This catches live rolling stock even on old saves whose abandoned cache
    -- centre predates the persistent cache registry.
    local radius = ROLLING_STOCK_PROTECTION_RADIUS + margin
    local rolling_stock = surface.find_entities_filtered {
        area = {
            { position.x - radius, position.y - radius },
            { position.x + radius, position.y + radius },
        },
        type = ROLLING_STOCK_TYPES,
        limit = 1,
    }
    if rolling_stock and rolling_stock[1] and valid(rolling_stock[1]) then return true end

    -- Cache centres remain protected after a part is moved, coupled or
    -- destroyed. The chunk index avoids scanning every discovered cache for
    -- every member of a large Wave.
    return position_inside_known_train_cache(surface, position, margin)
end

-- Return the centre that caused a local Train-site collision. This is used
-- only when the digging face actually reaches a cache; tunnel creation itself
-- is never rejected by a distant or hidden cache elsewhere on the route.
function wave._nearest_train_cache_center(surface, position, margin)
    if not (surface and surface.valid and position) then return nil end
    margin = math.max(0, tonumber(margin) or 0)
    local nearest = nil
    local nearest_distance = math.huge
    local radius = ROLLING_STOCK_PROTECTION_RADIUS + margin
    local rolling_stock = surface.find_entities_filtered {
        area = {
            { position.x - radius, position.y - radius },
            { position.x + radius, position.y + radius },
        },
        type = ROLLING_STOCK_TYPES,
    }
    for _, entity in pairs(rolling_stock or {}) do
        if valid(entity) then
            local distance = position_distance_squared(position, entity.position)
            if distance < nearest_distance then
                nearest = { x = entity.position.x, y = entity.position.y }
                nearest_distance = distance
            end
        end
    end

    local sites = refresh_train_cache_site_index()[surface.index]
    if sites then
        local chunk_x = math.floor(position.x / 32)
        local chunk_y = math.floor(position.y / 32)
        for offset_x = -1, 1 do
            for offset_y = -1, 1 do
                local bucket = sites[tostring(chunk_x + offset_x) .. ":" .. tostring(chunk_y + offset_y)]
                for _, cache in ipairs(bucket or {}) do
                    if math.abs(position.x - cache.x) <= TRAIN_CACHE_HALF_WIDTH + margin
                        and math.abs(position.y - cache.y) <= TRAIN_CACHE_HALF_HEIGHT + margin then
                        local distance = position_distance_squared(position, cache)
                        if distance < nearest_distance then
                            nearest = { x = cache.x, y = cache.y }
                            nearest_distance = distance
                        end
                    end
                end
            end
        end
    end
    return nearest
end

local function main_locomotive(force)
    if not (force and force.valid) then return nil end
    if wave._shelter_wave_mode_enabled() then
        local shelter = storage.the_cave_shelter_core
        local record = shelter and shelter.forces and shelter.forces[force.index]
        local entity = record and record.entity
        if valid(entity) and entity.name == "the-cave-shelter"
            and entity.force == force and not is_forbidden_surface(entity.surface) then
            return entity
        end
    end
    local interiors = storage.the_cave_train_interiors
    if not interiors then return nil end

    local selected_unit = interiors.main_battery_locomotive_units
        and interiors.main_battery_locomotive_units[force.index]
    if selected_unit then
        local wagon = interiors.wagons and interiors.wagons[selected_unit]
        local entity = wagon and wagon.entity
        if valid(entity) and entity.type == "locomotive" and entity.force == force
            and not is_forbidden_surface(entity.surface) then
            return entity
        end
    end

    local candidates = {}
    for unit in pairs(interiors.main_train_units or {}) do
        local wagon = interiors.wagons and interiors.wagons[unit]
        local entity = wagon and wagon.entity
        if valid(entity) and entity.type == "locomotive" and entity.force == force
            and not is_forbidden_surface(entity.surface) then
            candidates[#candidates + 1] = entity
        end
    end
    table.sort(candidates, function(a, b)
        return (a.unit_number or math.huge) < (b.unit_number or math.huge)
    end)
    return candidates[1]
end

local function enemy_evolution(surface)
    local evolution = 0
    if surface and surface.valid then
        pcall(function()
            evolution = game.forces.enemy.get_evolution_factor(surface)
        end)
    end
    return math.max(0, math.min(1, tonumber(evolution) or 0))
end

local function evolution_tier(surface)
    local evolution = enemy_evolution(surface)
    if evolution >= 0.85 then return 4 end
    if evolution >= 0.50 then return 3 end
    if evolution >= 0.20 then return 2 end
    return 1
end

local function boss_level_for_surface(surface)
    return math.max(1, math.min(11, math.floor(enemy_evolution(surface) * 10) + 1))
end

local function regular_unit_name(kind, surface)
    local highest = evolution_tier(surface)
    local tier_index = highest
    local roll = math.random()
    if highest > 1 and roll >= 0.65 then tier_index = highest - 1 end
    if highest > 2 and roll >= 0.90 then tier_index = highest - 2 end
    return UNIT_PREFIX .. (TIERS[tier_index] or "small") .. "-" .. kind
end

local function boss_unit_name(level)
    return UNIT_PREFIX .. "boss-behemoth-biter-l" .. math.max(1, math.min(11, level))
end

local function boss_count_for_wave(number)
    number = math.max(1, math.floor(tonumber(number) or 1))
    if number % 100 ~= 0 then return 0 end
    return math.min(4, math.floor(number / 100))
end

local function wave_bracket(number)
    number = math.max(1, math.floor(tonumber(number) or 1))
    return math.max(1, math.ceil(number / 50))
end

local function wave_interval_ticks(number)
    -- Wave 1-50 lasts one minute. Every following 50-Wave bracket adds
    -- another thirty seconds, with no upper time ceiling.
    return (wave_bracket(number) + 1) * 30 * SECOND
end

local function wave_growth_total(number)
    number = math.max(1, math.floor(tonumber(number) or 1))
    local bracket = wave_bracket(number)
    local offset = (number - 1) % 50
    local start_total = bracket == 1 and 20 or (bracket - 1) * 100
    local growth = bracket == 1 and 79 or 99
    return math.floor(start_total + growth * offset / 49)
end

local function population_hash(force, number, surface, salt)
    local seed = 0
    pcall(function()
        local settings = surface and surface.valid and surface.map_gen_settings or nil
        seed = math.floor(tonumber(settings and settings.seed) or 0)
    end)
    local force_index = force and force.valid and force.index or 0
    local modulus = 2147483647
    local value = (seed % modulus
        + (math.max(1, math.floor(tonumber(number) or 1)) * 48271) % modulus
        + (force_index * 69621) % modulus
        + (math.floor(tonumber(salt) or 0) * 104729) % modulus) % modulus
    return (value * 16807 + 11) % modulus
end

local function population_roll(force, number, surface, salt, low, high)
    return low + population_hash(force, number, surface, salt) % (high - low + 1)
end

local function raw_population_mode(force, number, surface)
    local roll = population_roll(force, number, surface, 1, 1, 100)
    if roll <= 12 then return "brake" end
    if roll <= 20 then return "surge" end
    return "normal"
end

local function scheduled_wave_population(force, number, surface)
    local baseline = wave_growth_total(number)
    local offset = (number - 1) % 50
    if offset == 0 or offset == 49 then return baseline, baseline, "anchor" end

    local mode = raw_population_mode(force, number, surface)
    -- Random relief never lasts more than two Waves. Pressure-driven relief
    -- may continue when the live/queued workload genuinely remains unsafe.
    if mode == "brake"
        and raw_population_mode(force, number - 1, surface) == "brake"
        and raw_population_mode(force, number - 2, surface) == "brake" then
        mode = "normal"
    end

    local percent = 100
    if mode == "brake" then
        percent = population_roll(force, number, surface, 2, 40, 60)
    elseif mode == "surge" then
        percent = population_roll(force, number, surface, 3, 110, 125)
    else
        percent = population_roll(force, number, surface, 4, 92, 108)
    end

    local bracket_ceiling = wave_bracket(number) * 100 - 1
    local total = math.floor(baseline * percent / 100 + 0.5)
    return math.max(10, math.min(bracket_ceiling, total)), baseline, mode
end

local function set_plan_population(plan, normal_total, mode)
    normal_total = math.max(0, math.floor(tonumber(normal_total) or 0))
    plan.normal_total = normal_total
    plan.total = normal_total + plan.bosses
    plan.base = math.ceil(normal_total / math.max(1, plan.fronts))
    plan.biters = math.max(0, math.min(normal_total, math.floor(normal_total * 0.70 + 0.5)))
    plan.spitters = normal_total - plan.biters
    plan.population_mode = mode or plan.population_mode
end

local function current_wave_pressure(state)
    local active = 0
    for _, record in pairs(state.units or {}) do
        if record and valid(record.entity) then active = active + 1 end
    end
    local queued = 0
    for _, group in ipairs(state.queue or {}) do
        queued = queued
            + math.max(0, tonumber(group.biters) or 0)
            + math.max(0, tonumber(group.spitters) or 0)
            + math.max(0, tonumber(group.bosses) or 0)
    end
    return active, queued
end

local function next_boss_wave(completed_wave)
    local completed = math.max(0, math.floor(tonumber(completed_wave) or 0))
    return (math.floor(completed / 100) + 1) * 100
end

local function attack_front_count(number)
    number = math.max(1, math.floor(tonumber(number) or 1))
    local bracket = wave_bracket(number)
    if bracket >= 4 then return 8 end
    if bracket == 3 then return 6 end
    if bracket == 2 then return 4 end
    return 2
end

local function wave_numbers(force, number, surface, player_override)
    local player_count = 0
    local fronts = attack_front_count(number)
    local normal_total, baseline_total, population_mode = scheduled_wave_population(
        force, number, surface)
    local bosses = boss_count_for_wave(number)
    local total = normal_total + bosses
    local biters = math.max(0, math.min(normal_total, math.floor(normal_total * 0.70 + 0.5)))
    local spitters = normal_total - biters

    return {
        wave = number,
        base = math.ceil(normal_total / math.max(1, fronts)),
        baseline_total = baseline_total,
        population_mode = population_mode,
        players = player_count,
        total = total,
        normal_total = normal_total,
        biters = biters,
        spitters = spitters,
        bosses = bosses,
        boss_level = boss_level_for_surface(surface),
        fronts = fronts,
        interval_ticks = wave_interval_ticks(number),
    }
end

local function shuffled_sectors()
    local sectors = { 1, 2, 3, 4, 5, 6, 7, 8 }
    for index = #sectors, 2, -1 do
        local other = math.random(1, index)
        sectors[index], sectors[other] = sectors[other], sectors[index]
    end
    return sectors
end

local function choose_normal_sectors(state, count)
    if count <= 1 then
        local blocked = {}
        for _, sector in ipairs(state.last_single_sectors or {}) do blocked[sector] = true end
        local candidates = {}
        for sector = 1, 8 do
            if not blocked[sector] then candidates[#candidates + 1] = sector end
        end
        if #candidates == 0 then candidates = shuffled_sectors() end
        local chosen = candidates[math.random(1, #candidates)]
        state.last_single_sectors[#state.last_single_sectors + 1] = chosen
        while #state.last_single_sectors > 2 do table.remove(state.last_single_sectors, 1) end
        return { chosen }
    end

    local sectors = shuffled_sectors()
    local result = {}
    for index = 1, math.min(8, count) do result[#result + 1] = sectors[index] end
    return result
end

local function choose_boss_sectors(count)
    if count <= 0 then return {} end
    local start = math.random(1, 8)
    if count == 1 then return { start } end
    if count == 2 then return { start, ((start + 3) % 8) + 1 } end
    if count == 3 then return { start, ((start + 2) % 8) + 1, ((start + 5) % 8) + 1 } end
    return { 1, 3, 5, 7 }
end

local function make_wave_plan(force, state, number, surface, player_override)
    local plan = wave_numbers(force, number, surface, player_override)
    local offset = (number - 1) % 50
    if offset ~= 0 and offset ~= 49 then
        local active, queued = current_wave_pressure(state)
        local pressure = active + queued
        local pressure_cap = wave._active_cap(plan.total)
        local severe = active >= math.floor(pressure_cap * 0.90)
            or queued >= pressure_cap * 2
            or pressure >= math.floor(pressure_cap * 2.50)
        local moderate = active >= math.floor(pressure_cap * 0.73)
            or queued >= math.floor(pressure_cap * 0.83)
            or pressure >= math.floor(pressure_cap * 1.33)
        if severe or moderate then
            local percent = severe
                and population_roll(force, number, surface, 5, 30, 45)
                or population_roll(force, number, surface, 6, 45, 60)
            local relief_total = math.floor(plan.baseline_total * percent / 100 + 0.5)
            local relief_cap = severe and math.floor(pressure_cap / 3)
                or math.floor(pressure_cap * 2 / 3)
            if active >= math.floor(pressure_cap * 0.83) then
                relief_cap = math.min(relief_cap,
                    math.max(20, pressure_cap - active + 25))
            end
            set_plan_population(plan,
                math.min(plan.normal_total, relief_total, relief_cap),
                severe and "emergency-brake" or "pressure-brake")
        end
    end
    plan.normal_sectors = choose_normal_sectors(state, plan.fronts)
    plan.boss_sectors = choose_boss_sectors(plan.bosses)
    return plan
end

local function queue_group_total(group)
    if not group then return 0 end
    return math.max(0, tonumber(group.biters) or 0)
        + math.max(0, tonumber(group.spitters) or 0)
        + math.max(0, tonumber(group.bosses) or 0)
end

local function queue_counts(state)
    local counts = { total = 0, biters = 0, spitters = 0, bosses = 0 }
    for _, group in ipairs(state.queue or {}) do
        counts.biters = counts.biters + math.max(0, tonumber(group.biters) or 0)
        counts.spitters = counts.spitters + math.max(0, tonumber(group.spitters) or 0)
        counts.bosses = counts.bosses + math.max(0, tonumber(group.bosses) or 0)
    end
    counts.total = counts.biters + counts.spitters + counts.bosses
    return counts
end

local function append_group(state, group)
    if queue_group_total(group) > 0 then state.queue[#state.queue + 1] = group end
end

local destroy_healthbar

-- One-time upgrade recovery: attackers created on raw, disconnected chunks in
-- older saves are returned to the exact Wave queue without death credit or
-- loot. Fresh tunnels can then deploy them from the generated train area.
function wave._requeue_generation_upgrade_units(state)
    if not state then return 0 end
    local normal = {}
    local order = {}
    local bosses = {}
    local recovered = 0

    for unit_number, record in pairs(state.units or {}) do
        if record and valid(record.entity) then
            if record.boss then
                bosses[#bosses + 1] = {
                    wave = record.wave or state.wave,
                    sector = record.sector or 1,
                    biters = 0,
                    spitters = 0,
                    bosses = 1,
                    boss_level = record.boss_level,
                    boss_sequence = record.boss_sequence,
                    next_kind = "biter",
                    failures = 3,
                    force_tunnel = true,
                }
            else
                local key = tostring(record.wave or state.wave or 0)
                    .. ":" .. tostring(record.sector or 1)
                local group = normal[key]
                if not group then
                    group = {
                        wave = record.wave or state.wave,
                        sector = record.sector or 1,
                        biters = 0,
                        spitters = 0,
                        bosses = 0,
                        next_kind = "biter",
                        failures = 3,
                        force_tunnel = true,
                    }
                    normal[key] = group
                    order[#order + 1] = key
                end
                if record.kind == "spitter" then
                    group.spitters = group.spitters + 1
                else
                    group.biters = group.biters + 1
                end
            end
            destroy_healthbar(record)
            pcall(function() record.entity.destroy { raise_destroy = false } end)
            state.units[unit_number] = nil
            recovered = recovered + 1
        else
            destroy_healthbar(record)
            -- Keep an invalid current-Boss record until the once-per-second
            -- controller has copied its logical identity and remaining-health
            -- snapshot back into the queue. Ordinary invalid units and stale
            -- Boss records can still be discarded immediately.
            local recoverable_boss = record and record.boss
                and not record.boss_finished and state.phase == "boss"
                and state.boss_wave_active and record.wave == state.wave
            if not recoverable_boss then state.units[unit_number] = nil end
        end
    end

    for _, key in ipairs(order) do
        local source = normal[key]
        while source.biters + source.spitters > 0 do
            local capacity = MAX_ATOMIC_GROUP_SIZE
            local biters = math.min(source.biters, capacity)
            source.biters = source.biters - biters
            capacity = capacity - biters
            local spitters = math.min(source.spitters, capacity)
            source.spitters = source.spitters - spitters
            append_group(state, {
                wave = source.wave,
                sector = source.sector,
                biters = biters,
                spitters = spitters,
                bosses = 0,
                next_kind = "biter",
                failures = 3,
                force_tunnel = true,
            })
        end
    end
    for _, group in ipairs(bosses) do append_group(state, group) end

    state.tunnels = {}
    state.next_tunnel_id = 1
    state.eight_tunnel_reserved_wave = nil
    state.tunnel_reserve_retry_tick = 0
    state.route_blocked = false
    state.spawn_wait_ticks = 0
    state.player_aggro_groups = {}
    return recovered
end

-- Generate and chart a 45 x 45 chunk square around the Main Locomotive. The
-- cache follows the train by chunk, so a moving train generates only the new
-- outer strip rather than rebuilding the full square every tick.
function wave._ensure_train_generated_area(state, force, locomotive)
    if not (state and force and force.valid and valid(locomotive)) then return false end
    local surface = locomotive.surface
    local chunk_x = math.floor(locomotive.position.x / 32)
    local chunk_y = math.floor(locomotive.position.y / 32)
    local radius = wave._generation_radius_chunks(locomotive)

    if state.train_generation_profile_version ~= wave.train_generation_profile_version
        and not state.train_generation_migration_started then
        wave._requeue_generation_upgrade_units(state)
        state.train_generation_surface_index = nil
        state.train_generation_chunk_x = nil
        state.train_generation_chunk_y = nil
        state.train_generation_migration_started = true
    end

    if state.train_generation_profile_version == wave.train_generation_profile_version
        and state.train_generation_surface_index == surface.index
        and state.train_generation_chunk_x == chunk_x
        and state.train_generation_chunk_y == chunk_y
        and state.train_generation_radius_chunks == radius then
        return true
    end

    if not world.ensure_generated_radius(
        surface, locomotive.position, radius) then
        return false
    end

    pcall(function()
        force.chart(surface, {
            { (chunk_x - radius) * 32, (chunk_y - radius) * 32 },
            { (chunk_x + radius + 1) * 32, (chunk_y + radius + 1) * 32 },
        })
    end)
    state.train_generation_profile_version = wave.train_generation_profile_version
    state.train_generation_surface_index = surface.index
    state.train_generation_chunk_x = chunk_x
    state.train_generation_chunk_y = chunk_y
    state.train_generation_radius_chunks = radius
    state.train_generation_migration_started = nil
    return true
end

local function normal_groups_for_plan(plan)
    local groups = {}
    local sector_count = math.max(1, #plan.normal_sectors)
    local remaining_total = plan.normal_total
    local remaining_biters = plan.biters
    for index, sector in ipairs(plan.normal_sectors) do
        local groups_left = sector_count - index + 1
        local group_total = index == sector_count and remaining_total
            or math.floor(remaining_total / groups_left + 0.5)
        group_total = math.max(0, math.min(remaining_total, group_total))

        local group_biters = 0
        if group_total > 0 and remaining_total > 0 then
            group_biters = index == sector_count and remaining_biters
                or math.floor(group_total * remaining_biters / remaining_total + 0.5)
            group_biters = math.max(0, math.min(group_total, remaining_biters, group_biters))
        end
        local group_spitters = group_total - group_biters

        local sector_total = group_total
        local sector_biters = group_biters
        local chunks = math.max(1, math.ceil(sector_total / MAX_ATOMIC_GROUP_SIZE))
        for chunk_index = 1, chunks do
            local chunks_left = chunks - chunk_index + 1
            local chunk_total = chunk_index == chunks and sector_total
                or math.floor(sector_total / chunks_left + 0.5)
            chunk_total = math.max(0, math.min(sector_total, chunk_total))
            local chunk_biters = 0
            if chunk_total > 0 and sector_total > 0 then
                chunk_biters = chunk_index == chunks and sector_biters
                    or math.floor(chunk_total * sector_biters / sector_total + 0.5)
                chunk_biters = math.max(0, math.min(chunk_total, sector_biters, chunk_biters))
            end
            groups[#groups + 1] = {
                wave = plan.wave,
                sector = sector,
                biters = chunk_biters,
                spitters = chunk_total - chunk_biters,
                bosses = 0,
                boss_level = plan.boss_level,
                next_kind = "biter",
                failures = 0,
                force_tunnel = sector_count == 8,
            }
            sector_total = sector_total - chunk_total
            sector_biters = sector_biters - chunk_biters
        end
        remaining_total = remaining_total - group_total
        remaining_biters = remaining_biters - group_biters
    end
    return groups
end

local function choose_attack_width(groups_left)
    if groups_left <= 1 then return 1 end
    local roll = math.random(1, 100)
    local width = roll <= 50 and 1 or roll <= 85 and 2 or 3
    return math.min(groups_left, width)
end

local function build_attack_events(plan, duration_ticks)
    local groups = normal_groups_for_plan(plan)
    local events = {}
    local cursor = 1
    while cursor <= #groups do
        local width = choose_attack_width(#groups - cursor + 1)
        while width > 1 do
            local burst_total = 0
            for offset = 0, width - 1 do
                burst_total = burst_total + queue_group_total(groups[cursor + offset])
            end
            if burst_total <= wave._active_cap(plan.total) - BOSS_RESERVED_SLOTS then break end
            width = width - 1
        end
        local event = { groups = {} }
        for _ = 1, width do
            event.groups[#event.groups + 1] = groups[cursor]
            cursor = cursor + 1
        end
        events[#events + 1] = event
    end

    if #events == 0 then return events end
    local active_percent = math.random(65, 85)
    local active_end = math.max(MIN_ATTACK_GAP_TICKS * (#events + 1),
        math.floor(duration_ticks * active_percent / 100))
    active_end = math.min(duration_ticks - MIN_ATTACK_GAP_TICKS, active_end)
    local segment = math.max(MIN_ATTACK_GAP_TICKS, math.floor(active_end / (#events + 1)))
    local previous = 0
    for index, event in ipairs(events) do
        local jitter = math.floor(segment * math.random(-25, 25) / 100)
        local latest = active_end - (#events - index) * MIN_ATTACK_GAP_TICKS
        event.at_ticks = math.max(previous + MIN_ATTACK_GAP_TICKS,
            math.min(latest, index * segment + jitter))
        previous = event.at_ticks
    end
    return events
end

local function build_boss_targets(count, duration_ticks)
    local targets = {}
    for index = 1, count do
        local center = duration_ticks * index / (count + 1)
        local jitter = duration_ticks * math.random(-7, 7) / 100
        targets[index] = math.max(MIN_ATTACK_GAP_TICKS,
            math.floor(center + jitter))
        if index > 1 then
            targets[index] = math.max(targets[index], targets[index - 1] + MIN_ATTACK_GAP_TICKS)
        end
    end
    return targets
end

local function safe_destroy_render(object)
    pcall(function()
        if object and object.valid then object.destroy() end
    end)
end

local function destroy_safe_zone_render(state)
    if not (state and state.safe_zone_render) then return end
    safe_destroy_render(state.safe_zone_render.outline)
    safe_destroy_render(state.safe_zone_render.label)
    state.safe_zone_render = nil
end

local function update_safe_zone_render(force, state, locomotive)
    if not (state and force and force.valid and valid(locomotive)) then
        destroy_safe_zone_render(state)
        return
    end

    local label_key = locomotive.name == "the-cave-shelter"
        and "the-cave-train-wave.shelter-safe-zone-label"
        or "the-cave-train-wave.safe-zone-label"
    local existing = state.safe_zone_render
    if existing
        and existing.locomotive_unit_number == locomotive.unit_number
        and existing.surface_index == locomotive.surface.index
        and existing.label_key == label_key
        and existing.outline and existing.outline.valid
        and existing.label and existing.label.valid then
        return
    end
    destroy_safe_zone_render(state)

    local outline = nil
    local label = nil
    local ok = pcall(function()
        outline = rendering.draw_rectangle {
            surface = locomotive.surface,
            left_top = {
                type = "entity",
                entity = locomotive,
                offset = { -SAFE_ZONE_HALF_SIZE, -SAFE_ZONE_HALF_SIZE },
            },
            right_bottom = {
                type = "entity",
                entity = locomotive,
                offset = { SAFE_ZONE_HALF_SIZE, SAFE_ZONE_HALF_SIZE },
            },
            color = SAFE_ZONE_LINE_COLOR,
            width = SAFE_ZONE_LINE_WIDTH,
            filled = false,
            forces = { force },
            only_in_alt_mode = false,
            -- Keep the thin boundary readable even when walls, rails or other
            -- defence sprites are built directly on top of it.
            draw_on_ground = false,
            render_mode = "game",
        }
        label = rendering.draw_text {
            surface = locomotive.surface,
            target = {
                type = "entity",
                entity = locomotive,
                offset = { 0, -SAFE_ZONE_HALF_SIZE - 1.5 },
            },
            text = {
                label_key,
                SAFE_ZONE_HALF_SIZE,
            },
            color = SAFE_ZONE_LINE_COLOR,
            scale = 1.05,
            alignment = "center",
            vertical_alignment = "bottom",
            forces = { force },
            only_in_alt_mode = false,
            draw_on_ground = false,
            render_mode = "game",
        }
    end)
    if not ok or not (outline and outline.valid and label and label.valid) then
        safe_destroy_render(outline)
        safe_destroy_render(label)
        return
    end
    state.safe_zone_render = {
        outline = outline,
        label = label,
        locomotive_unit_number = locomotive.unit_number,
        surface_index = locomotive.surface.index,
        label_key = label_key,
    }
end

destroy_healthbar = function(record)
    if not record or not record.healthbar then return end
    safe_destroy_render(record.healthbar.fill)
    safe_destroy_render(record.healthbar.background)
    record.healthbar = nil
end

local function create_boss_healthbar(unit)
    if not valid(unit) then return nil end
    local background = nil
    local fill = nil
    local ok = pcall(function()
        background = rendering.draw_sprite {
            sprite = "virtual-signal/signal-white",
            tint = { r = 0.03, g = 0.03, b = 0.03, a = 0.90 },
            x_scale = BOSS_BAR_WIDTH + 0.5,
            y_scale = BOSS_BAR_Y_SCALE + 0.18,
            render_layer = "light-effect",
            target = { entity = unit, offset = { 0, -5.0 } },
            surface = unit.surface,
        }
        fill = rendering.draw_sprite {
            sprite = "virtual-signal/signal-white",
            tint = { r = 0, g = 0.78, b = 0, a = 1 },
            x_scale = BOSS_BAR_WIDTH,
            y_scale = BOSS_BAR_Y_SCALE,
            render_layer = "light-effect",
            target = { entity = unit, offset = { 0, -5.0 } },
            surface = unit.surface,
        }
    end)
    if not ok then
        safe_destroy_render(fill)
        safe_destroy_render(background)
        return nil
    end
    return { fill = fill, background = background }
end

local function update_boss_healthbar(record)
    if not (record and record.boss and valid(record.entity)) then return end
    local bar = record.healthbar
    if not (bar and bar.fill and bar.fill.valid and bar.background and bar.background.valid) then
        destroy_healthbar(record)
        record.healthbar = create_boss_healthbar(record.entity)
        bar = record.healthbar
    end
    if not (bar and bar.fill and bar.fill.valid) then return end

    local max_health = tonumber(record.max_health)
    if not max_health or max_health <= 0 then
        max_health = wave._entity_max_health(record.entity)
        record.max_health = max_health
    end
    max_health = math.max(1, tonumber(max_health) or 1)
    local ratio = math.max(0, math.min(1, (tonumber(record.entity.health) or 0) / max_health))
    pcall(function()
        bar.fill.x_scale = math.max(0.001, BOSS_BAR_WIDTH * ratio)
        bar.fill.color = { r = 1 - ratio, g = 0.80 * ratio, b = 0, a = 1 }
    end)
end

local function active_counts(state, refresh_bars)
    local counts = { total = 0, biters = 0, spitters = 0, bosses = 0 }
    for unit_number, record in pairs(state.units or {}) do
        if record and valid(record.entity) then
            counts.total = counts.total + 1
            if record.boss then
                counts.bosses = counts.bosses + 1
                if refresh_bars then update_boss_healthbar(record) end
            elseif record.kind == "spitter" then
                counts.spitters = counts.spitters + 1
            else
                counts.biters = counts.biters + 1
            end
        else
            destroy_healthbar(record)
            state.units[unit_number] = nil
        end
    end
    return counts
end

local function global_active_count()
    local count = 0
    for _, state in pairs(root_state().forces or {}) do
        count = count + active_counts(state, false).total
    end
    return count
end

local function destroy_wave_units(state, preserve_tunnels)
    for unit_number, record in pairs(state.units or {}) do
        destroy_healthbar(record)
        if record and valid(record.entity) then
            pcall(function() record.entity.destroy { raise_destroy = false } end)
        end
        state.units[unit_number] = nil
    end
    state.queue = {}
    state.queue_cursor = 1
    if not preserve_tunnels then
        state.tunnels = {}
        state.canonical_tunnel_ids = {}
        state.tunnel_retry_profiles = {}
        state.attack_regions = {}
        state.active_attack_region_id = nil
        state.next_attack_region_id = 1
        state.attack_region_candidate_started_tick = nil
        state.attack_region_candidate_ready = false
        state.attack_region_profile_version = nil
        state.next_tunnel_id = 1
        state.tunnel_announced_waves = {}
        state.tunnel_breached_waves = {}
        state.tunnel_reserve_retry_tick = 0
        state.eight_tunnel_reserved_wave = nil
    end
    state.route_blocked = false
    state.spawn_wait_ticks = 0
    state.attack_events = {}
    state.attack_event_cursor = 1
    state.wave_elapsed_ticks = 0
    state.wave_duration_ticks = 0
    state.boss_wave_active = false
    state.boss_total = 0
    state.boss_spawned = 0
    state.boss_killed = 0
    state.boss_pending = false
    state.boss_targets = {}
    state.boss_sectors = {}
    state.boss_next_delay_ticks = 0
    state.boss_active = nil
    state.player_aggro_groups = {}
end

local function command_unit(unit, target, distraction)
    if not (valid(unit) and valid(target) and unit.surface == target.surface) then return false end
    local command = {
        type = defines.command.attack,
        target = target,
        distraction = distraction or defines.distraction.by_enemy,
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

local function command_record(record, target, role, distraction)
    if not (record and valid(record.entity)) then return false end
    local ok = command_unit(record.entity, target, distraction)
    if ok then
        record.wave_command_role = role
        record.wave_command_target_unit_number = target.unit_number
    end
    return ok
end

local function command_locomotive(record, locomotive)
    if record then record.military_target = nil end
    if record and record.boss then
        return command_record(record, locomotive, "boss-locomotive", defines.distraction.none)
    end
    -- Discoverable rolling stock must never steal the Main Locomotive order.
    return command_record(record, locomotive, "locomotive", defines.distraction.none)
end

function wave._command_tunnel_position(record, tunnel, force_reissue)
    if not (record and record.tunnel_route_active and valid(record.entity)
        and tunnel and tunnel.status == "open" and type(tunnel.route) == "table"
        and #tunnel.route > 1) then
        return false
    end

    local unit = record.entity
    local index = math.max(2, math.min(#tunnel.route,
        math.floor(tonumber(record.tunnel_route_index) or 2)))
    local target = tunnel.route[index]
    local lookahead = record.tunnel_route_cautious
        and wave.tunnel_route_cautious_lookahead or wave.tunnel_route_lookahead

    while index < #tunnel.route
        and position_distance_squared(unit.position, target)
            <= wave.tunnel_route_handoff_radius_squared do
        index = math.min(#tunnel.route, index + lookahead)
        target = tunnel.route[index]
    end

    if index >= #tunnel.route
        and position_distance_squared(unit.position, target)
            <= wave.tunnel_route_handoff_radius_squared then
        record.tunnel_route_active = nil
        record.tunnel_route_index = nil
        record.tunnel_route_command_index = nil
        record.tunnel_route_cautious = nil
        record.tunnel_id = nil
        return false
    end

    record.tunnel_route_index = index
    local role = "tunnel-route:" .. tostring(tunnel.id) .. ":" .. tostring(index)
    if not force_reissue and record.wave_command_role == role
        and record.tunnel_route_command_index == index then
        return true
    end

    local command = {
        type = defines.command.go_to_location,
        destination = { x = target.x, y = target.y },
        radius = wave.tunnel_route_command_radius,
        distraction = defines.distraction.none,
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
    if ok then
        record.wave_command_role = role
        record.wave_command_target_unit_number = nil
        record.tunnel_route_command_index = index
    end
    return ok
end

local function tile_key(x, y)
    return tostring(math.floor(x)) .. ":" .. tostring(math.floor(y))
end

local function tunnel_square_cells(center, width)
    local cells = {}
    width = math.max(1, math.floor(tonumber(width) or TUNNEL_WIDTH))
    local low = -math.floor((width - 1) / 2)
    local high = low + width - 1
    for dx = low, high do
        for dy = low, high do
            cells[#cells + 1] = { x = center.x + dx, y = center.y + dy }
        end
    end
    return cells
end

function wave._tunnel_circle_cells(center, radius)
    if not center then return {} end
    radius = math.max(1, tonumber(radius) or wave.tunnel_mouth_radius)
    local cells = {}
    local minimum_x = math.floor(center.x - radius)
    local maximum_x = math.ceil(center.x + radius) - 1
    local minimum_y = math.floor(center.y - radius)
    local maximum_y = math.ceil(center.y + radius) - 1
    local radius_squared = radius * radius
    for x = minimum_x, maximum_x do
        for y = minimum_y, maximum_y do
            local dx = x + 0.5 - center.x
            local dy = y + 0.5 - center.y
            if dx * dx + dy * dy <= radius_squared then
                cells[#cells + 1] = { x = x, y = y }
            end
        end
    end
    return cells
end

local function tunnel_position_inside_mouth(tunnel, position)
    if not (tunnel and position and tunnel.mouth_position) then return false end
    local radius = math.max(1, tonumber(wave.tunnel_mouth_radius) or 1)
    return position_distance_squared(position, tunnel.mouth_position)
        <= radius * radius
end

local function tunnel_face_inside_mouth(tunnel)
    return tunnel_position_inside_mouth(tunnel, tunnel and tunnel.current)
end

local function is_cover_name(name)
    return name == "diggy-rock" or name == "diggy-rubble" or name == "diggy-tree"
end

local function pocket_is_clear(surface, cells)
    for _, cell in ipairs(cells) do
        local entities = surface.find_entities_filtered {
            area = { { cell.x + 0.02, cell.y + 0.02 }, { cell.x + 0.98, cell.y + 0.98 } },
        }
        for _, entity in pairs(entities or {}) do
            if valid(entity) and not is_cover_name(entity.name) then return false end
        end
    end
    return true
end

local function cells_touch_player_structure(surface, cells, force, locomotive)
    if not (force and force.valid) then return false end
    for _, cell in ipairs(cells) do
        local entities = surface.find_entities_filtered {
            area = { { cell.x + 0.02, cell.y + 0.02 }, { cell.x + 0.98, cell.y + 0.98 } },
            force = force,
        }
        for _, entity in pairs(entities or {}) do
            if valid(entity) and type(entity.name) == "string"
                and entity.name:sub(1, #UNIT_PREFIX) ~= UNIT_PREFIX
                and (not valid(locomotive)
                    or entity.type ~= "locomotive" and entity.type ~= "cargo-wagon"
                    and entity.type ~= "fluid-wagon" and entity.type ~= "artillery-wagon"
                    or valid(locomotive) and entity.unit_number == locomotive.unit_number) then
                return true
            end
        end
    end
    return false
end

local function is_water_tile(tile)
    return tile and tile.valid and type(tile.name) == "string"
        and tile.name:find("water", 1, true) ~= nil
end

local function landfill_water_cells(surface, cells, force)
    if not (surface and surface.valid and cells and #cells > 0) then return 0 end
    local positions = {}
    local tiles = {}
    local seen = {}
    for _, cell in ipairs(cells) do
        local x, y = math.floor(cell.x), math.floor(cell.y)
        local key = tile_key(x, y)
        if not seen[key] and is_water_tile(surface.get_tile(x, y)) then
            seen[key] = true
            positions[#positions + 1] = { x = x, y = y }
            tiles[#tiles + 1] = { name = "landfill", position = { x = x, y = y } }
        end
    end
    if #tiles == 0 or cells_touch_player_structure(surface, positions, force) then return 0 end

    local changed = false
    local ok = pcall(function()
        -- Never remove colliding entities or decoratives and never raise a
        -- player tile event. This is a narrow Wave route, not player landfill.
        surface.set_tiles(tiles, true, false, false, false)
        changed = true
    end)
    if not ok or not changed then return 0 end
    mirror.set_tiles(surface, tiles)
    return #tiles, positions
end

local function reveal_frontier_resource(surface, x, y, force)
    -- Ordinary veins remain visible in the controlled passage. Extraction Qs
    -- are resolved once per forward step by the dedicated side-room path.
    ore_veins.materialize(surface, x, y, force, nil)
    mobile_factory_resources.on_open_tile(surface, x, y, force)
end

local function open_tunnel_extraction(tunnel, surface, force, center, step_x, step_y)
    if not (caverns_api and uranium_caves_api and mineral_caves_api) then return false end
    tunnel.extraction_checked = tunnel.extraction_checked or {}
    local key = tile_key(center.x, center.y)
    if tunnel.extraction_checked[key] then return false end
    tunnel.extraction_checked[key] = true

    local dig = {
        surface = surface,
        position = { x = center.x, y = center.y },
        force = force,
        allow_room_generation = true,
        is_train_wave_tunnel = true,
        train_wave_direction = { step_x, step_y },
        train_wave_clearance = 32,
    }
    local opened, room_plan, room_label = caverns_api.on_train_wave_tunnel_dig(dig)
    if not opened then return false end

    local uranium_created = uranium_caves_api.on_cavern_opened(dig, room_plan, room_label) == true
    local mineral_created = mineral_caves_api.on_cavern_opened(dig, room_plan, room_label) == true
    caverns_api.on_uranium_entrance_result(dig, room_plan, uranium_created)
    caverns_api.on_mineral_entrance_result(dig, room_plan, mineral_created)
    if (uranium_created or mineral_created) and force and force.valid then
        force.chart(surface, {
            { room_plan.x1 - 2, room_plan.y1 - 2 },
            { room_plan.x2 + 2, room_plan.y2 + 2 },
        })
    end
    return uranium_created or mineral_created
end

function wave._chart_tunnel_cells(tunnel, surface, cells, force)
    if not (tunnel and surface and surface.valid and force and force.valid
        and type(cells) == "table") then
        return 0
    end
    tunnel.charted_chunks = tunnel.charted_chunks or {}
    local chunks = {}
    for _, cell in ipairs(cells) do
        local cx = math.floor((tonumber(cell.x or cell[1]) or 0) / 32)
        local cy = math.floor((tonumber(cell.y or cell[2]) or 0) / 32)
        local key = tostring(cx) .. ":" .. tostring(cy)
        if not tunnel.charted_chunks[key] then
            chunks[key] = { x = cx, y = cy }
        end
    end
    local charted = 0
    for key, chunk in pairs(chunks) do
        local ok = pcall(function()
            force.chart(surface, {
                { chunk.x * 32, chunk.y * 32 },
                { chunk.x * 32 + 32, chunk.y * 32 + 32 },
            })
        end)
        if ok then
            tunnel.charted_chunks[key] = true
            charted = charted + 1
        end
    end
    return charted
end

local function carve_tunnel_cells(tunnel, surface, cells, force)
    if not world.ensure_generated_area(surface, cells) then return false end
    local frontier = {}
    local frontier_keys = {}
    local changed = false
    local inspected_new = false
    tunnel.carved = tunnel.carved or {}

    for _, cell in ipairs(cells) do
        local x, y = math.floor(cell.x), math.floor(cell.y)
        local key = tile_key(x, y)
        if not tunnel.carved[key] then
            inspected_new = true
            local had_rock = false
            local had_rubble = false
            local covers = surface.find_entities_filtered {
                name = { "diggy-rock", "diggy-rubble" },
                area = { { x + 0.02, y + 0.02 }, { x + 0.98, y + 0.98 } },
            }
            for _, cover in pairs(covers or {}) do
                if valid(cover) then
                    if cover.name == "diggy-rubble" then
                        had_rubble = true
                        mirror.set_rock(surface, { x = x, y = y }, false)
                        cover.destroy()
                    else
                        had_rock = true
                    end
                end
            end

            local opened = world.carve_tile(surface, x, y, force, false, true)
            if had_rock and not opened then reveal_frontier_resource(surface, x, y, force) end
            if opened or had_rock or had_rubble then
                frontier[#frontier + 1] = { x, y }
                frontier_keys[key] = true
                changed = true
            end
            tunnel.carved[key] = true
        end
    end

    -- Water generated by cave carving is allowed to flood normally outside
    -- the corridor. Only the current twelve-tile-wide tunnel slice is bridged.
    local filled, positions = landfill_water_cells(surface, cells, force)
    if filled > 0 then
        for _, position in ipairs(positions) do
            local key = tile_key(position.x, position.y)
            if not frontier_keys[key] then
                frontier[#frontier + 1] = { position.x, position.y }
                frontier_keys[key] = true
            end
        end
        changed = true
    end

    if #frontier > 0 then world.advance_frontier(surface, frontier) end
    wave._chart_tunnel_cells(tunnel, surface, cells, force)
    return changed, inspected_new
end

function wave._process_tunnel_width_upgrade(force, tunnel)
    if not (tunnel and (tunnel.mouth_upgrade_pending or tunnel.width_upgrade_index)) then return end
    local surface = tunnel.surface_index and game.get_surface(tunnel.surface_index) or nil
    if not (surface and surface.valid) then return end

    if tunnel.mouth_upgrade_pending and tunnel.mouth_position then
        local mouth_cells = wave._tunnel_circle_cells(
            tunnel.mouth_position,
            wave.tunnel_mouth_radius)
        if not world.ensure_generated_area(surface, mouth_cells) then return end
        carve_tunnel_cells(tunnel, surface, mouth_cells, force)
        tunnel.mouth_upgrade_pending = nil
    end

    local route = type(tunnel.route) == "table" and tunnel.route or nil
    local index = math.max(1, math.floor(tonumber(tunnel.width_upgrade_index) or 1))
    if not route or index > #route then
        tunnel.width_upgrade_index = nil
        return
    end

    local last_index = math.min(
        #route,
        index + wave.tunnel_width_upgrade_steps_per_update - 1)
    local cells = {}
    for route_index = index, last_index do
        local position = route[route_index]
        if position then
            local square = tunnel_square_cells({
                x = math.floor(position.x),
                y = math.floor(position.y),
            }, TUNNEL_WIDTH)
            for _, cell in ipairs(square) do cells[#cells + 1] = cell end
        end
    end
    if #cells > 0 then
        if not world.ensure_generated_area(surface, cells) then return end
        carve_tunnel_cells(tunnel, surface, cells, force)
    end
    tunnel.width_upgrade_index = last_index < #route and last_index + 1 or nil
end

local function tunnel_step_toward(from, target)
    local dx = target.x - from.x
    local dy = target.y - from.y
    local ax, ay = math.abs(dx), math.abs(dy)
    if ax > ay * 1.6 then return dx < 0 and -1 or 1, 0 end
    if ay > ax * 1.6 then return 0, dy < 0 and -1 or 1 end
    local sx = dx == 0 and 0 or (dx < 0 and -1 or 1)
    local sy = dy == 0 and 0 or (dy < 0 and -1 or 1)
    return sx, sy
end

-- Build a two-leg local bypass only after the digging face reaches an
-- abandoned Train. The first leg moves sideways away from the cache and the
-- second moves beyond it; normal direct digging then resumes toward the Main
-- Locomotive. Repeated collisions widen the bypass and alternate its side.
function wave._begin_train_cache_detour(tunnel, surface, locomotive, blocked_center)
    if not (tunnel and tunnel.current and surface and surface.valid and valid(locomotive)) then
        return false
    end
    local attempt = (tonumber(tunnel.cache_detour_attempts) or 0) + 1
    if attempt > 6 then return false end

    local obstacle = wave._nearest_train_cache_center(
        surface, blocked_center,
        TRAIN_SITE_TUNNEL_MARGIN + math.ceil(TUNNEL_WIDTH / 2)) or blocked_center
    local dx = locomotive.position.x - tunnel.current.x
    local dy = locomotive.position.y - tunnel.current.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 1 then return false end
    local forward_x, forward_y = dx / distance, dy / distance
    local left_x, left_y = -forward_y, forward_x
    local obstacle_cross = forward_x * (obstacle.y - tunnel.current.y)
        - forward_y * (obstacle.x - tunnel.current.x)
    local side = obstacle_cross > 0.1 and -1
        or obstacle_cross < -0.1 and 1
        or ((tonumber(tunnel.id) or 0) + attempt) % 2 == 0 and 1 or -1
    if tunnel.cache_detour_waypoints then
        side = -(tonumber(tunnel.cache_detour_side) or side)
    end

    local clearance = 24 + math.min(3, attempt - 1) * 8
    local function rounded(value) return math.floor(value + 0.5) end
    tunnel.cache_detour_waypoints = {
        {
            x = rounded(tunnel.current.x + left_x * side * clearance),
            y = rounded(tunnel.current.y + left_y * side * clearance),
        },
        {
            x = rounded(obstacle.x + forward_x * (clearance + 8)
                + left_x * side * clearance),
            y = rounded(obstacle.y + forward_y * (clearance + 8)
                + left_y * side * clearance),
        },
    }
    tunnel.cache_detour_index = 1
    tunnel.cache_detour_side = side
    tunnel.cache_detour_attempts = attempt
    tunnel.pending = nil
    return true
end

function wave._tunnel_dig_destination(tunnel, locomotive)
    local waypoints = tunnel and tunnel.cache_detour_waypoints
    while waypoints do
        local index = math.max(1, math.floor(tonumber(tunnel.cache_detour_index) or 1))
        local waypoint = waypoints[index]
        if waypoint and (tunnel.current.x ~= waypoint.x or tunnel.current.y ~= waypoint.y) then
            tunnel.cache_detour_index = index
            return waypoint
        end
        index = index + 1
        if waypoints[index] then
            tunnel.cache_detour_index = index
        else
            tunnel.cache_detour_waypoints = nil
            tunnel.cache_detour_index = nil
            tunnel.cache_detour_side = nil
            tunnel.cache_detour_attempts = 0
            waypoints = nil
        end
    end
    return tunnel and tunnel.target_position or locomotive.position
end

local function existing_tunnel(state, wave_number, sector)
    local id = state and state.canonical_tunnel_ids
        and state.canonical_tunnel_ids[sector] or nil
    local tunnel = id and state.tunnels and state.tunnels[id] or nil
    if tunnel and tunnel.sector == sector and tunnel.status ~= "failed" then
        tunnel.persistent = true
        return tunnel
    end
    if state and state.canonical_tunnel_ids then state.canonical_tunnel_ids[sector] = nil end
    return nil
end

function wave._tunnel_mouth_is_separate(state, group, center)
    if not (state and group and center) then return false end
    for _, position in ipairs(group.avoid_positions or {}) do
        if position_distance_squared(center, position)
            < wave.tunnel_mouth_separation_squared then
            return false
        end
    end
    for _, other in pairs(state.tunnels or {}) do
        if other and other.status ~= "failed"
            and other.deployment_position
            and position_distance_squared(center, other.deployment_position)
                < wave.tunnel_mouth_separation_squared then
            return false
        end
    end
    return true
end

local function create_tunnel(state, force, locomotive, group, prototype_name, kind)
    if not (valid(locomotive) and is_tunnel_surface(locomotive.surface)) then return nil end
    local shared = existing_tunnel(state, group.wave, group.sector)
    if shared then
        shared.width = TUNNEL_WIDTH
        return shared
    end

    state.canonical_tunnel_ids = state.canonical_tunnel_ids or {}
    state.tunnel_retry_profiles = state.tunnel_retry_profiles or {}
    local retry_profile = state.tunnel_retry_profiles[group.sector] or {}
    group.tunnel_rebuilds = math.max(
        tonumber(group.tunnel_rebuilds) or 0,
        tonumber(retry_profile.rebuilds) or 0)
    if retry_profile.avoid_positions and #retry_profile.avoid_positions > 0 then
        group.avoid_positions = retry_profile.avoid_positions
    end

    local surface = locomotive.surface
    local base_angle = SECTOR_ANGLES[group.sector] or 0
    local width = TUNNEL_WIDTH
    local minimum_distance, maximum_distance = wave._spawn_distance_bounds(locomotive)
    for _ = 1, 8 do
        local angle_spread = (tonumber(group.tunnel_rebuilds) or 0) > 0
            and wave.replacement_tunnel_angle_spread
            or group.force_tunnel and wave.forced_tunnel_angle_spread
            or math.pi * 0.24
        local angle = base_angle + (math.random() - 0.5) * angle_spread
        local distance = minimum_distance
            + math.random() * (maximum_distance - minimum_distance)
        local center = {
            x = math.floor(locomotive.position.x + math.cos(angle) * distance),
            y = math.floor(locomotive.position.y + math.sin(angle) * distance),
        }
        local tunnel = {
            id = state.next_tunnel_id,
            wave = group.wave,
            sector = group.sector,
            surface_index = surface.index,
            status = "digging",
            width = width,
            current = center,
            exit_position = { x = center.x + 0.5, y = center.y + 0.5 },
            deployment_position = nil,
            mouth_position = { x = center.x + 1, y = center.y + 1 },
            steps = 0,
            step_wait_ticks = TUNNEL_STEP_TICKS,
            pending = nil,
            carved = {},
            route = {{ x = center.x + 0.5, y = center.y + 0.5 }},
            target_position = {
                x = locomotive.position.x,
                y = locomotive.position.y,
            },
            region_id = state.active_attack_region_id,
            persistent = true,
            forced = group.force_tunnel == true,
            rebuilds = math.max(0, tonumber(group.tunnel_rebuilds) or 0),
            avoid_positions = group.avoid_positions,
            attack_chunks = locomotive.name == "the-cave-shelter"
                and wave._shelter_attack_chunks(force) or nil,
        }
        local pocket = wave._tunnel_circle_cells(
            tunnel.mouth_position,
            wave.tunnel_mouth_radius)
        if world.ensure_generated_area(surface, pocket)
            and not position_inside_protected_train_site(surface, center, TRAIN_SITE_TUNNEL_MARGIN)
            and wave._tunnel_mouth_is_separate(state, group, center)
            and pocket_is_clear(surface, pocket) then
            local step_x, step_y = tunnel_step_toward(center, locomotive.position)
            if step_x ~= 0 or step_y ~= 0 then
                open_tunnel_extraction(tunnel, surface, force, center, step_x, step_y)
            end
            carve_tunnel_cells(tunnel, surface, pocket, force)
            local position = surface.find_non_colliding_position(
                prototype_name,
                tunnel.mouth_position,
                wave.tunnel_mouth_spawn_radius,
                0.5,
                true
            )
            if position then
                -- The tunnel mouth is the permanent deployment point. Keep it
                -- inside the strict moving 640-672-tile spawn ring even when
                -- the tunnel itself later carves toward the safe square.
                if position_inside_spawn_ring(locomotive, position)
                    and not position_inside_protected_train_site(
                        surface, position, TRAIN_SITE_SPAWN_MARGIN) then
                    tunnel.exit_position = position
                    tunnel.deployment_position = { x = position.x, y = position.y }
                    state.tunnels[tunnel.id] = tunnel
                    state.canonical_tunnel_ids[group.sector] = tunnel.id
                    state.next_tunnel_id = state.next_tunnel_id + 1
                    if not state.tunnel_announced_waves[group.wave] then
                        state.tunnel_announced_waves[group.wave] = true
                        announce(force, { "the-cave-train-wave.tunnel-started", group.wave }, "utility/console_message")
                    end
                    return tunnel
                end
            end
        end
    end
    return nil
end

-- Shelter research moves each of the eight canonical mouths outward without
-- re-carving the already-open route. The short new segment digs back to the
-- previous mouth, then inherits that route. If the new mouth cannot be placed
-- safely, the canonical slot is released and the normal proven full-tunnel
-- fallback is used by the next queued attack.
function wave._create_shelter_tunnel_extension(state, force, shelter, parent, desired_chunks)
    if not (parent and parent.status == "open" and parent.deployment_position
        and valid(shelter) and shelter.name == "the-cave-shelter") then return nil end
    local surface = shelter.surface
    local dx = parent.deployment_position.x - shelter.position.x
    local dy = parent.deployment_position.y - shelter.position.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then return nil end
    local distance = desired_chunks * 32 + 16
    local center = {
        x = math.floor(shelter.position.x + dx / length * distance),
        y = math.floor(shelter.position.y + dy / length * distance),
    }
    local mouth_position = { x = center.x + 1, y = center.y + 1 }
    local cells = wave._tunnel_circle_cells(mouth_position, wave.tunnel_mouth_radius)
    if not world.ensure_generated_area(surface, cells)
        or not pocket_is_clear(surface, cells)
        or position_inside_protected_train_site(surface, center, TRAIN_SITE_TUNNEL_MARGIN) then
        return nil
    end

    local initial_carve = { carved = {}, charted_chunks = {} }
    carve_tunnel_cells(initial_carve, surface, cells, force)
    local prototype_name = regular_unit_name("biter", surface)
    local deployment = surface.find_non_colliding_position(prototype_name,
        mouth_position, wave.tunnel_mouth_spawn_radius, 0.5, true)
    if not deployment or not position_inside_spawn_ring(shelter, deployment) then return nil end

    local tunnel = {
        id = state.next_tunnel_id,
        wave = math.max(1, tonumber(state.wave) or 1),
        sector = parent.sector,
        surface_index = surface.index,
        status = "digging",
        width = TUNNEL_WIDTH,
        current = center,
        exit_position = { x = deployment.x, y = deployment.y },
        deployment_position = { x = deployment.x, y = deployment.y },
        mouth_position = mouth_position,
        steps = 0,
        step_wait_ticks = TUNNEL_STEP_TICKS,
        carved = initial_carve.carved,
        charted_chunks = initial_carve.charted_chunks,
        route = { { x = deployment.x, y = deployment.y } },
        target_position = {
            x = parent.deployment_position.x,
            y = parent.deployment_position.y,
        },
        region_id = state.active_attack_region_id,
        persistent = true,
        forced = true,
        rebuilds = 0,
        extension_parent_id = parent.id,
        attack_chunks = desired_chunks,
    }
    local step_x, step_y = tunnel_step_toward(center, parent.deployment_position)
    if step_x ~= 0 or step_y ~= 0 then
        -- An extension is deliberately plain corridor work: do not roll a new
        -- extraction cavern merely because research moved an existing mouth.
        tunnel.extraction_checked = { [tile_key(center.x, center.y)] = true }
    end
    state.tunnels[tunnel.id] = tunnel
    state.canonical_tunnel_ids[parent.sector] = tunnel.id
    state.next_tunnel_id = state.next_tunnel_id + 1
    parent.extension_child_id = tunnel.id
    return tunnel
end

function wave._ensure_shelter_tunnel_distance(state, force, shelter)
    if not (wave._shelter_wave_mode_enabled() and valid(shelter)
        and shelter.name == "the-cave-shelter") then return end
    local desired = wave._shelter_attack_chunks(force)
    state.shelter_target_attack_chunks = desired
    state.canonical_tunnel_ids = state.canonical_tunnel_ids or {}
    for sector = 1, 8 do
        local id = state.canonical_tunnel_ids[sector]
        local tunnel = id and state.tunnels[id] or nil
        if tunnel and tunnel.status ~= "failed"
            and (tonumber(tunnel.attack_chunks) or 10) < desired then
            if tunnel.status == "open" then
                local extension = wave._create_shelter_tunnel_extension(
                    state, force, shelter, tunnel, desired)
                if not extension then
                    -- Keep the old route usable for attackers already assigned
                    -- to it, but let future groups build one safe final route.
                    state.canonical_tunnel_ids[sector] = nil
                    tunnel.legacy_extra = true
                end
            elseif tunnel.status == "digging" and tunnel.extension_parent_id then
                local parent = state.tunnels[tunnel.extension_parent_id]
                if parent and parent.status == "open" then
                    tunnel.status = "failed"
                    tunnel.persistent = false
                    tunnel.pending = nil
                    parent.extension_child_id = nil
                    state.canonical_tunnel_ids[sector] = parent.id
                    if not wave._create_shelter_tunnel_extension(
                        state, force, shelter, parent, desired) then
                        state.canonical_tunnel_ids[sector] = nil
                        parent.legacy_extra = true
                    end
                end
            end
            -- A still-digging route finishes first; the next update extends it
            -- directly to the latest level, coalescing rapid research levels.
        end
    end
end

local function find_spawn_position(locomotive, prototype_name, sector)
    if not (valid(locomotive) and locomotive.surface and locomotive.surface.valid) then return nil end
    local surface = locomotive.surface
    if is_forbidden_surface(surface) then return nil end
    local base_angle = SECTOR_ANGLES[sector] or 0
    local minimum_distance, maximum_distance = wave._spawn_distance_bounds(locomotive)

    for _ = 1, 16 do
        local angle = base_angle + (math.random() - 0.5) * (math.pi * 0.40)
        local distance = minimum_distance + math.random() * (maximum_distance - minimum_distance)
        local candidate = {
            x = locomotive.position.x + math.cos(angle) * distance,
            y = locomotive.position.y + math.sin(angle) * distance,
        }
        local position = surface.find_non_colliding_position(prototype_name, candidate, 10, 0.5, true)
        if position and position_inside_spawn_ring(locomotive, position)
            and not position_inside_protected_train_site(
                surface, position, TRAIN_SITE_SPAWN_MARGIN) then
            return position
        end
    end
    return nil
end

local function wave_unit_name(group, kind, surface)
    return kind == "boss" and boss_unit_name(group.boss_level)
        or regular_unit_name(kind, surface)
end

local function create_wave_unit(state, locomotive, group, kind, name, position, tunnel)
    if not (valid(locomotive) and locomotive.surface and locomotive.surface.valid and position) then return nil end
    -- Normal deployment follows the moving 640-672-tile ring. A saved active
    -- region may continue using an older mouth during travel, but never while
    -- that mouth lies inside the Main Train safe zone or a managed Train site.
    local persistent_mouth = tunnel and tunnel.persistent == true
        and tunnel.status == "open"
    if position_inside_safe_zone(locomotive, position)
        or not persistent_mouth and not position_inside_spawn_ring(locomotive, position)
        or position_inside_protected_train_site(
            locomotive.surface, position, TRAIN_SITE_SPAWN_MARGIN) then
        return nil
    end
    if not (prototypes and prototypes.entity and prototypes.entity[name]) then return nil end
    local boss = kind == "boss"
    local unit = nil
    local ok = pcall(function()
        unit = locomotive.surface.create_entity {
            name = name,
            position = position,
            force = game.forces.enemy,
            create_build_effect_smoke = false,
        }
    end)
    if not ok or not valid(unit) or not unit.unit_number then return nil end

    pcall(function()
        if unit.ai_settings then unit.ai_settings.allow_destroy_when_commands_fail = false end
    end)

    local max_health = wave._entity_max_health(unit)
    if boss and tonumber(group.boss_health) then
        local recovered_health = math.max(1,
            math.min(max_health, tonumber(group.boss_health) or max_health))
        pcall(function() unit.health = recovered_health end)
    end
    local initial_health = tonumber(unit.health) or max_health
    local record = {
        entity = unit,
        unit_number = unit.unit_number,
        kind = boss and "boss" or kind,
        boss = boss,
        boss_level = boss and group.boss_level or nil,
        boss_sequence = boss and group.boss_sequence or nil,
        wave = group.wave,
        sector = group.sector,
        max_health = tonumber(max_health) or tonumber(unit.health) or 1,
        last_position = { x = unit.position.x, y = unit.position.y },
        last_health = initial_health,
        stuck_ticks = 0,
        rescue_attempts = 0,
        tunnel_id = tunnel and tunnel.id or nil,
        tunneling = false,
        tunnel_route_active = tunnel and tunnel.status == "open"
            and type(tunnel.route) == "table" and #tunnel.route > 1 or nil,
        tunnel_route_index = tunnel and tunnel.status == "open"
            and type(tunnel.route) == "table"
            and math.min(#tunnel.route, 1 + wave.tunnel_route_lookahead) or nil,
        boss_free_progress_tick = boss and game.tick or nil,
        boss_free_progress_position = boss and {
            x = unit.position.x,
            y = unit.position.y,
        } or nil,
    }
    if boss then
        record.healthbar = create_boss_healthbar(unit)
        state.boss_active = {
            wave = group.wave,
            sequence = group.boss_sequence,
            level = group.boss_level,
            sector = group.sector,
            unit_number = unit.unit_number,
            health = initial_health,
            max_health = max_health,
            relocations = math.max(0, math.floor(tonumber(group.boss_relocations) or 0)),
        }
    end
    state.units[unit.unit_number] = record
    if boss then state.boss_pending = false end
    if not wave._command_tunnel_position(record, tunnel, true) then
        command_locomotive(record, locomotive)
    end
    update_boss_healthbar(record)
    return record
end

local function spawn_queued_unit(state, force, locomotive, group, kind)
    if not (valid(locomotive) and locomotive.surface and locomotive.surface.valid) then return false end
    local name = wave_unit_name(group, kind, locomotive.surface)
    local position = nil
    if group.spawn_anchor then
        position = locomotive.surface.find_non_colliding_position(
            name,
            group.spawn_anchor,
            ATTACK_GROUP_SPAWN_RADIUS,
            0.5,
            true
        )
        if position and (not position_inside_spawn_ring(locomotive, position)
            or position_inside_protected_train_site(
                locomotive.surface, position, TRAIN_SITE_SPAWN_MARGIN)) then
            position = nil
        end
    end
    if not position then
        position = find_spawn_position(locomotive, name, group.sector)
        if position then group.spawn_anchor = { x = position.x, y = position.y } end
    end
    if not position then return false end
    return create_wave_unit(state, locomotive, group, kind, name, position, nil) ~= nil
end

local function find_tunnel_spawn_position(locomotive, prototype_name, tunnel)
    if not (valid(locomotive) and tunnel and tunnel.surface_index == locomotive.surface.index) then return nil end
    local anchor = tunnel.deployment_position
    if not anchor or position_inside_safe_zone(locomotive, anchor)
        or not tunnel.persistent
        and not position_inside_spawn_ring(locomotive, anchor) then return nil end
    -- Spread each burst across a deterministic golden-angle spiral inside the
    -- round mouth chamber. Each candidate receives only a short local collision
    -- search, so a player wall cannot be crossed and a full chamber leaves the
    -- remaining attackers queued instead of stacking them on one coordinate.
    local mouth = tunnel.mouth_position or anchor
    local allowed_radius = wave.tunnel_mouth_radius - 0.5
    local allowed_radius_squared = allowed_radius * allowed_radius
    for _ = 1, 16 do
        tunnel.spawn_cursor = math.floor(tonumber(tunnel.spawn_cursor) or 0) % 128 + 1
        local cursor = tunnel.spawn_cursor
        local distance = wave.tunnel_mouth_spawn_radius
            * math.sqrt((cursor - 0.5) / 128)
        local angle = cursor * 2.399963229728653
        local candidate = {
            x = mouth.x + math.cos(angle) * distance,
            y = mouth.y + math.sin(angle) * distance,
        }
        local position = locomotive.surface.find_non_colliding_position(
            prototype_name, candidate, 1.25, 0.5, true)
        if position
            and position_distance_squared(position, mouth) <= allowed_radius_squared
            and not position_inside_safe_zone(locomotive, position)
            and (tunnel.persistent or position_inside_spawn_ring(locomotive, position))
            and not position_inside_protected_train_site(
                locomotive.surface, position, TRAIN_SITE_SPAWN_MARGIN) then
            return position
        end
    end
    return nil
end

local function spawn_from_tunnel(state, locomotive, group, kind, tunnel)
    if not (tunnel and tunnel.status ~= "failed") then return false end
    -- Autonomous tunnels keep every attacker safely queued until the route is
    -- open. No vulnerable unit or Boss is required to drive terrain carving.
    if tunnel.status == "digging" or tunnel_face_inside_mouth(tunnel) then return false end

    local name = wave_unit_name(group, kind, locomotive.surface)
    local position = find_tunnel_spawn_position(locomotive, name, tunnel)
    if not position then return false end
    return create_wave_unit(state, locomotive, group, kind, name, position, tunnel) ~= nil
end

function wave._ensure_eight_front_tunnels(state, force, locomotive, immediate)
    local plan = state and state.last_wave_plan or nil
    if not (plan and plan.wave == state.wave and #plan.normal_sectors == 8
        and valid(locomotive) and force and force.valid) then
        return 0
    end

    local selected = {}
    local needed = {}
    for _, sector in ipairs(plan.normal_sectors) do selected[sector] = true end
    for _, group in ipairs(state.queue or {}) do
        if group.wave == plan.wave and selected[group.sector] then
            group.force_tunnel = true
            needed[group.sector] = true
        end
    end
    for index = state.attack_event_cursor, #state.attack_events do
        for _, group in ipairs(state.attack_events[index].groups or {}) do
            if group.wave == plan.wave and selected[group.sector] then
                group.force_tunnel = true
                needed[group.sector] = true
            end
        end
    end

    if state.eight_tunnel_reserved_wave ~= plan.wave then
        for _, sector in ipairs(plan.normal_sectors) do needed[sector] = true end
    end

    if not immediate and game.tick < state.tunnel_reserve_retry_tick then return 0 end
    state.tunnel_reserve_retry_tick = game.tick + ROUTE_RETRY_TICKS
    local created = 0
    for _, sector in ipairs(plan.normal_sectors) do
        if needed[sector] and not existing_tunnel(state, plan.wave, sector) then
            local group = {
                wave = plan.wave,
                sector = sector,
                force_tunnel = true,
                failures = 3,
            }
            local prototype_name = regular_unit_name("biter", locomotive.surface)
            if create_tunnel(state, force, locomotive, group, prototype_name, "biter") then
                created = created + 1
            end
        end
    end
    local reserved = 0
    for _, sector in ipairs(plan.normal_sectors) do
        if existing_tunnel(state, plan.wave, sector) then reserved = reserved + 1 end
    end
    if reserved == 8 then state.eight_tunnel_reserved_wave = plan.wave end
    return created
end

local function compact_queue(state)
    for index = #state.queue, 1, -1 do
        if queue_group_total(state.queue[index]) <= 0 then table.remove(state.queue, index) end
    end
    if #state.queue == 0 then
        state.queue_cursor = 1
    elseif state.queue_cursor > #state.queue then
        state.queue_cursor = 1
    end
end

local function next_group_kind(group)
    if (tonumber(group.bosses) or 0) > 0 then return "boss" end
    local biters = tonumber(group.biters) or 0
    local spitters = tonumber(group.spitters) or 0
    if biters > 0 and spitters > 0 then return group.next_kind == "spitter" and "spitter" or "biter" end
    if biters > 0 then return "biter" end
    if spitters > 0 then return "spitter" end
    return nil
end

local function decrement_group(group, kind)
    if kind == "boss" then
        group.bosses = math.max(0, (tonumber(group.bosses) or 0) - 1)
    elseif kind == "spitter" then
        group.spitters = math.max(0, (tonumber(group.spitters) or 0) - 1)
        group.next_kind = "biter"
    else
        group.biters = math.max(0, (tonumber(group.biters) or 0) - 1)
        group.next_kind = "spitter"
    end
end

local fail_tunnel

local function spawn_one_from_queue(state, force, locomotive, locked_group)
    compact_queue(state)
    local group_count = #state.queue
    if group_count == 0 then return false end

    if locked_group then
        local locked_index = nil
        for index, group in ipairs(state.queue) do
            if group == locked_group then
                locked_index = index
                break
            end
        end
        if not locked_index then return false end
        state.queue_cursor = locked_index
        group_count = 1
    end

    for _ = 1, group_count do
        if state.queue_cursor > #state.queue then state.queue_cursor = 1 end
        local index = state.queue_cursor
        local group = state.queue[index]
        local kind = next_group_kind(group)
        local spawned = false
        local tunnel = group.tunnel_id and state.tunnels[group.tunnel_id] or nil
        if tunnel and tunnel.status == "failed" then
            group.tunnel_id = nil
            tunnel = nil
        end
        if tunnel and (tunnel.surface_index ~= locomotive.surface.index
            or not tunnel.deployment_position
            or not tunnel.persistent
                and not position_inside_spawn_ring(locomotive, tunnel.deployment_position)) then
            -- A moving train can carry its strict spawn ring away from an old mouth.
            -- Retire that route without consuming the queued attackers; the
            -- normal fallback will choose a new mouth inside the current ring.
            fail_tunnel(state, tunnel, locomotive)
            group.tunnel_id = nil
            tunnel = nil
        end

        if kind and tunnel then
            spawned = spawn_from_tunnel(state, locomotive, group, kind, tunnel)
        elseif kind and not group.force_tunnel then
            spawned = spawn_queued_unit(state, force, locomotive, group, kind)
        end

        if kind and spawned then
            decrement_group(group, kind)
            group.failures = 0
            if queue_group_total(group) <= 0 then
                table.remove(state.queue, index)
                state.queue_cursor = index
            else
                state.queue_cursor = locked_group and index or index + 1
            end
            if state.queue_cursor > #state.queue and #state.queue > 0 then state.queue_cursor = 1 end
            return true
        end

        if not tunnel then
            group.failures = group.force_tunnel and 3
                or (tonumber(group.failures) or 0) + 1
            if group.failures >= 3 and kind then
                local prototype_name = wave_unit_name(group, kind, locomotive.surface)
                tunnel = create_tunnel(state, force, locomotive, group, prototype_name, kind)
                if tunnel then
                    group.tunnel_id = tunnel.id
                    group.failures = 0
                    if spawn_from_tunnel(state, locomotive, group, kind, tunnel) then
                        decrement_group(group, kind)
                        if queue_group_total(group) <= 0 then
                            table.remove(state.queue, index)
                            state.queue_cursor = index
                        else
                            state.queue_cursor = index + 1
                        end
                        if state.queue_cursor > #state.queue and #state.queue > 0 then state.queue_cursor = 1 end
                        return true
                    end
                elseif group.failures >= 6 then
                    -- Tunnelling is unavailable on this surface or no safe
                    -- pocket exists. Rotate only after both normal placement
                    -- and the controlled fallback have failed repeatedly.
                    if not group.force_tunnel then
                        group.sector = ((group.sector + math.random(1, 7) - 1) % 8) + 1
                        group.failures = 0
                    else
                        group.failures = 3
                    end
                end
            end
        end
        state.queue_cursor = locked_group and index or index + 1
    end
    return false
end

local function tunnel_counts(state)
    local counts = { active = 0, waiting = 0 }
    local active_ids = {}
    for id, tunnel in pairs(state.tunnels or {}) do
        if tunnel and tunnel.status == "digging" then
            counts.active = counts.active + 1
            active_ids[id] = true
        end
    end
    for _, group in ipairs(state.queue or {}) do
        if group.tunnel_id and active_ids[group.tunnel_id] then
            counts.waiting = counts.waiting + queue_group_total(group)
        end
    end
    return counts
end

local function spawn_batch(force, state, locomotive)
    local queued = queue_counts(state).total
    if queued <= 0 then
        state.route_blocked = false
        return 0
    end

    compact_queue(state)
    if #state.queue == 0 then return 0 end
    if state.queue_cursor > #state.queue then state.queue_cursor = 1 end

    -- A due Boss owns the reserved live slot and must not be trapped behind an
    -- ordinary group that is correctly waiting for a full atomic capacity.
    if state.phase == "boss" and state.boss_pending then
        for index, group in ipairs(state.queue) do
            if (tonumber(group.bosses) or 0) > 0 then
                state.queue_cursor = index
                break
            end
        end
    end

    local selected = state.queue[state.queue_cursor]
    local selected_burst = selected.burst_id
    local groups = { selected }
    if selected_burst then
        for _, group in ipairs(state.queue) do
            if group ~= selected and group.burst_id == selected_burst then groups[#groups + 1] = group end
        end
    end

    local required = 0
    local has_boss = false
    for _, group in ipairs(groups) do
        required = required + queue_group_total(group)
        has_boss = has_boss or (tonumber(group.bosses) or 0) > 0
    end

    local active = active_counts(state, false).total
    local active_cap = wave._current_active_cap(state)
    local reserved = state.phase == "boss" and not has_boss and BOSS_RESERVED_SLOTS or 0

    -- A later pressure-braked Wave can have a smaller live cap than an atomic
    -- burst already committed by an earlier Wave. Raise only the current cap
    -- enough to honour that queued burst instead of leaving it blocked forever.
    local minimum_atomic_cap = math.min(wave.max_active_enemy_cap, required + reserved)
    if active_cap < minimum_atomic_cap then
        active_cap = minimum_atomic_cap
        state.active_enemy_cap = active_cap
    end

    local limit = active_cap - reserved
    local capacity = math.max(0, limit - active)
    if capacity < required then
        state.route_blocked = false
        return 0, false
    end

    local spawned = 0
    for _, group in ipairs(groups) do
        group.spawn_anchor = nil
        local wanted = queue_group_total(group)
        for _ = 1, wanted do
            if not spawn_one_from_queue(state, force, locomotive, group) then break end
            spawned = spawned + 1
        end
        group.spawn_anchor = nil
        if queue_group_total(group) > 0 then break end
    end
    compact_queue(state)
    local tunnels = tunnel_counts(state)
    local still_queued = queue_counts(state).total > 0

    -- A group assigned to a still-digging tunnel must not monopolise the queue
    -- cursor. Rotate to the next queued group without deleting or splitting it.
    local rotated = false
    if spawned == 0 and still_queued and #state.queue > 1 then
        for index, group in ipairs(state.queue) do
            if group == selected then
                state.queue_cursor = index % #state.queue + 1
                rotated = true
                break
            end
        end
    end
    state.route_blocked = spawned == 0 and still_queued
        and tunnels.active == 0 and not rotated
    return spawned, rotated
end

local function breach_tunnel(force, state, tunnel, locomotive)
    if not (tunnel and tunnel.status == "digging") then return end
    if tunnel.extension_parent_id then
        local parent = state.tunnels and state.tunnels[tunnel.extension_parent_id]
        if parent and type(parent.route) == "table" then
            tunnel.route = tunnel.route or {}
            for _, point in ipairs(parent.route) do
                local last = tunnel.route[#tunnel.route]
                if not last or last.x ~= point.x or last.y ~= point.y then
                    tunnel.route[#tunnel.route + 1] = { x = point.x, y = point.y }
                end
            end
            tunnel.target_position = parent.target_position or locomotive.position
            parent.extension_child_id = nil
            parent.legacy_extra = true
        end
        tunnel.extension_parent_id = nil
    end
    tunnel.status = "open"
    tunnel.pending = nil
    tunnel.persistent = true
    state.canonical_tunnel_ids = state.canonical_tunnel_ids or {}
    state.canonical_tunnel_ids[tunnel.sector] = tunnel.id
    state.tunnel_retry_profiles = state.tunnel_retry_profiles or {}
    state.tunnel_retry_profiles[tunnel.sector] = nil
    if tunnel.current then
        tunnel.exit_position = { x = tunnel.current.x + 0.5, y = tunnel.current.y + 0.5 }
    end
    -- The current one-second force update can deploy the first accumulated
    -- batch immediately instead of waiting for a route-retry cooldown.
    state.spawn_wait_ticks = 0

    -- Release any legacy 2.7.56 leader that was already present when the save
    -- upgraded. Newly created autonomous tunnels have no active unit here.
    for _, record in pairs(state.units or {}) do
        if record and record.tunnel_id == tunnel.id and valid(record.entity) then
            record.tunneling = false
            command_locomotive(record, locomotive)
        end
    end
    if not state.tunnel_breached_waves[tunnel.wave] then
        state.tunnel_breached_waves[tunnel.wave] = true
        announce(force, { "the-cave-train-wave.tunnel-breached", tunnel.wave }, "utility/new_objective")
    end
end

fail_tunnel = function(state, tunnel, locomotive, rebuild_away_from_route)
    if not tunnel then return end
    tunnel.status = "failed"
    tunnel.pending = nil
    state.canonical_tunnel_ids = state.canonical_tunnel_ids or {}
    if state.canonical_tunnel_ids[tunnel.sector] == tunnel.id then
        state.canonical_tunnel_ids[tunnel.sector] = nil
    end
    local retry_profile = nil
    if rebuild_away_from_route then
        state.tunnel_retry_profiles = state.tunnel_retry_profiles or {}
        retry_profile = state.tunnel_retry_profiles[tunnel.sector] or {
            rebuilds = 0,
            avoid_positions = {},
        }
        retry_profile.rebuilds = math.max(
            tonumber(retry_profile.rebuilds) or 0,
            (tonumber(tunnel.rebuilds) or 0) + 1)
        retry_profile.avoid_positions = retry_profile.avoid_positions or {}
        if tunnel.deployment_position then
            retry_profile.avoid_positions[#retry_profile.avoid_positions + 1] = {
                x = tunnel.deployment_position.x,
                y = tunnel.deployment_position.y,
            }
        end
        state.tunnel_retry_profiles[tunnel.sector] = retry_profile
    end
    for _, group in ipairs(state.queue or {}) do
        if group.tunnel_id == tunnel.id then
            group.tunnel_id = nil
            if rebuild_away_from_route then
                group.force_tunnel = true
                group.failures = 3
                group.tunnel_rebuilds = retry_profile.rebuilds
                group.avoid_positions = retry_profile.avoid_positions
            else
                group.failures = 0
            end
        end
    end
    for _, record in pairs(state.units or {}) do
        if record and record.tunnel_id == tunnel.id and valid(record.entity) then
            record.tunneling = false
            command_locomotive(record, locomotive)
        end
    end
end

local function process_tunnel(force, state, tunnel, locomotive)
    wave._process_tunnel_width_upgrade(force, tunnel)
    if not (tunnel and tunnel.status == "digging") then return end
    if tunnel.surface_index ~= locomotive.surface.index then
        fail_tunnel(state, tunnel, locomotive, true)
        return
    end
    if not tunnel.deployment_position
        or not tunnel.persistent
            and not position_inside_spawn_ring(locomotive, tunnel.deployment_position) then
        fail_tunnel(state, tunnel, locomotive, true)
        return
    end

    local surface = locomotive.surface
    if (tonumber(tunnel.steps) or 0) >= TUNNEL_MAX_STEPS then
        -- Never declare a sealed route open merely because a distance or step
        -- limit was reached. Requeue the group and seek another outside mouth.
        fail_tunnel(state, tunnel, locomotive, true)
        return
    end

    tunnel.step_wait_ticks = math.max(0,
        (tonumber(tunnel.step_wait_ticks) or TUNNEL_STEP_TICKS) - TUNNEL_UPDATE_TICKS)
    if tunnel.step_wait_ticks > 0 then return end
    tunnel.step_wait_ticks = TUNNEL_STEP_TICKS

    local center = nil
    local cells = nil
    local step_x, step_y = 0, 0
    -- Preserve a prepared 2.7.56 step when upgrading an in-progress save.
    if tunnel.pending and tunnel.pending.center and tunnel.pending.cells then
        center = tunnel.pending.center
        cells = tunnel.pending.cells
        tunnel.pending = nil
        step_x = center.x - tunnel.current.x
        step_y = center.y - tunnel.current.y
    else
        local destination = wave._tunnel_dig_destination(tunnel, locomotive)
        local sx, sy = tunnel_step_toward(tunnel.current, destination)
        if sx == 0 and sy == 0 then
            breach_tunnel(force, state, tunnel, locomotive)
            return
        end
        step_x, step_y = sx, sy
        center = { x = tunnel.current.x + sx, y = tunnel.current.y + sy }
        cells = tunnel_square_cells(center, TUNNEL_WIDTH)
    end

    if not world.ensure_generated_area(surface, cells) then
        tunnel.pending = { center = center, cells = cells }
        return
    end

    local at_discovered_train_site = position_outside_safe_zone(locomotive, center)
        and position_inside_protected_train_site(
            surface, center,
            TRAIN_SITE_TUNNEL_MARGIN + math.ceil(TUNNEL_WIDTH / 2))

    -- Do not reject the whole tunnel because a cache exists somewhere ahead.
    -- Only the digging face reacts, creating a persistent left/right bypass
    -- before continuing toward the Main Locomotive.
    if at_discovered_train_site then
        if not wave._begin_train_cache_detour(tunnel, surface, locomotive, center) then
            fail_tunnel(state, tunnel, locomotive, true)
        end
        return
    end

    if not tunnel_position_inside_mouth(tunnel, center)
        and cells_touch_player_structure(surface, cells, force, locomotive) then
        breach_tunnel(force, state, tunnel, locomotive)
        return
    end

    open_tunnel_extraction(tunnel, surface, force, center, step_x, step_y)
    local changed, inspected_new = carve_tunnel_cells(tunnel, surface, cells, force)
    if changed then tunnel.frontier_carved = true end
    tunnel.current = center
    tunnel.exit_position = { x = center.x + 0.5, y = center.y + 0.5 }
    tunnel.route = tunnel.route or {}
    local last_route = tunnel.route[#tunnel.route]
    if not last_route or last_route.x ~= tunnel.exit_position.x
        or last_route.y ~= tunnel.exit_position.y then
        tunnel.route[#tunnel.route + 1] = {
            x = tunnel.exit_position.x,
            y = tunnel.exit_position.y,
        }
    end
    tunnel.steps = (tonumber(tunnel.steps) or 0) + 1

    -- Slices still inside the already-carved round mouth contain no new cells.
    -- They must advance silently instead of being mistaken for a completed
    -- route. Only a new, unchanged slice reached after real frontier carving
    -- proves that the controlled corridor has met already-open cave terrain.
    if not changed and inspected_new and tunnel.frontier_carved
        and not tunnel.cache_detour_waypoints then
        breach_tunnel(force, state, tunnel, locomotive)
    elseif tunnel.steps >= TUNNEL_MAX_STEPS then
        fail_tunnel(state, tunnel, locomotive, true)
    end
end

local function compact_tunnels(state)
    local referenced = {}
    local pending_forced = {}
    for index = state.attack_event_cursor, #state.attack_events do
        for _, group in ipairs(state.attack_events[index].groups or {}) do
            if group.force_tunnel then
                pending_forced[tostring(group.wave or 0) .. ":" .. tostring(group.sector or 0)] = true
            end
        end
    end
    -- A digging tunnel is its own controller and remains valid even when no
    -- attacker is currently alive or queued for it.
    for id, tunnel in pairs(state.tunnels or {}) do
        if tunnel and tunnel.status ~= "failed" and tunnel.persistent then
            referenced[id] = true
        elseif tunnel and (tunnel.status == "digging"
            or tunnel.forced and pending_forced[
                tostring(tunnel.wave or 0) .. ":" .. tostring(tunnel.sector or 0)]) then
            referenced[id] = true
        end
    end
    for _, group in ipairs(state.queue or {}) do
        if group.tunnel_id then referenced[group.tunnel_id] = true end
    end
    for _, record in pairs(state.units or {}) do
        if record and record.tunnel_id and valid(record.entity) then referenced[record.tunnel_id] = true end
    end
    for id, tunnel in pairs(state.tunnels or {}) do
        if not referenced[id] then state.tunnels[id] = nil end
    end
end

local function process_tunnels(force, state, locomotive)
    for _, tunnel in pairs(state.tunnels or {}) do process_tunnel(force, state, tunnel, locomotive) end
    compact_tunnels(state)
end

local function sectors_text(sectors)
    local names = {}
    for _, sector in ipairs(sectors or {}) do names[#names + 1] = SECTOR_NAMES[sector] or "?" end
    return #names > 0 and table.concat(names, ", ") or "-"
end

local function release_due_attack_events(state)
    while state.attack_event_cursor <= #state.attack_events do
        local event = state.attack_events[state.attack_event_cursor]
        if state.wave_elapsed_ticks < (tonumber(event.at_ticks) or 0) then break end
        local burst_id = state.next_burst_id
        state.next_burst_id = state.next_burst_id + 1
        for _, group in ipairs(event.groups or {}) do
            group.burst_id = burst_id
            append_group(state, group)
        end
        state.attack_event_cursor = state.attack_event_cursor + 1
        state.spawn_wait_ticks = 0
    end
end

local function normal_queue_waiting_for_wave(state, number)
    for _, group in ipairs(state.queue or {}) do
        if group.wave == number and (tonumber(group.bosses) or 0) <= 0
            and queue_group_total(group) > 0 then
            return true
        end
    end
    return false
end

local function boss_alive(state)
    for _, record in pairs(state.units or {}) do
        if record and record.boss and record.wave == state.wave and valid(record.entity) then return true end
    end
    return false
end

local function enter_boss_break(force, state)
    local completed_wave = state.wave
    destroy_wave_units(state, true)
    state.wave = completed_wave
    state.phase = "break"
    state.remaining_ticks = BREAK_INTERVAL_TICKS
    state.warnings = {}
    announce(force, {
        "the-cave-train-wave.boss-cleared-break",
        completed_wave,
        format_time(BREAK_INTERVAL_TICKS),
        completed_wave + 1,
    }, "utility/new_objective")
end

local function mark_boss_finished(state, record)
    if not (state and record and record.boss and record.wave == state.wave
        and state.boss_wave_active and not record.boss_finished) then
        return false
    end
    record.boss_finished = true
    state.boss_killed = math.min(state.boss_total, state.boss_killed + 1)
    state.boss_pending = false
    state.boss_next_delay_ticks = math.random(30, 75) * SECOND
    state.boss_active = nil
    return true
end

local function maybe_release_next_boss(force, state)
    if not state.boss_wave_active or state.phase ~= "boss" then return end
    if state.boss_killed >= state.boss_total then
        enter_boss_break(force, state)
        return
    end
    if state.boss_pending or boss_alive(state) or state.boss_spawned > state.boss_killed then return end
    if state.boss_next_delay_ticks > 0 then return end

    local next_index = state.boss_spawned + 1
    local target = tonumber(state.boss_targets[next_index]) or 0
    if state.wave_elapsed_ticks < target then return end

    -- The final Boss is the closing encounter. Every ordinary attack event
    -- must already have been released, and every ordinary group from this Boss
    -- Wave must already have left the entity queue before it can appear.
    if next_index == state.boss_total then
        if state.attack_event_cursor <= #state.attack_events then return end
        if normal_queue_waiting_for_wave(state, state.wave) then return end
    end

    local burst_id = state.next_burst_id
    state.next_burst_id = state.next_burst_id + 1
    append_group(state, {
        wave = state.wave,
        sector = state.boss_sectors[next_index] or math.random(1, 8),
        biters = 0,
        spitters = 0,
        bosses = 1,
        boss_level = state.last_wave_plan and state.last_wave_plan.boss_level or 1,
        boss_sequence = next_index,
        next_kind = "biter",
        failures = 0,
        burst_id = burst_id,
    })
    state.boss_spawned = next_index
    state.boss_pending = true
    state.spawn_wait_ticks = 0
    announce(force, { "the-cave-train-wave.boss-arrived", state.wave }, "utility/new_objective")
end

local function begin_wave(force, state, locomotive)
    local number = state.wave + 1
    local override = state.test_player_count_override
    local plan = make_wave_plan(force, state, number, locomotive.surface, override)
    state.wave = number
    state.last_wave_plan = plan
    state.active_enemy_cap = wave._active_cap(plan.total)
    state.boss_wave_active = plan.bosses > 0
    state.phase = state.boss_wave_active and "boss" or "countdown"
    state.wave_duration_ticks = state.boss_wave_active
        and plan.bosses * 2 * 60 * SECOND or plan.interval_ticks
    state.remaining_ticks = state.wave_duration_ticks
    state.wave_elapsed_ticks = 0
    state.attack_events = build_attack_events(plan, state.wave_duration_ticks)
    state.attack_event_cursor = 1
    state.boss_total = plan.bosses
    state.boss_spawned = 0
    state.boss_killed = 0
    state.boss_pending = false
    state.boss_targets = build_boss_targets(plan.bosses, state.wave_duration_ticks)
    state.boss_sectors = plan.boss_sectors
    state.boss_next_delay_ticks = 0
    state.boss_active = nil
    state.warnings = {}
    state.route_blocked = false
    state.spawn_wait_ticks = 0
    state.tunnel_reserve_retry_tick = 0
    wave._ensure_eight_front_tunnels(state, force, locomotive, true)

    if plan.bosses > 0 then
        announce(force, {
            "the-cave-train-wave.boss-started-hidden",
            plan.wave,
            plan.normal_total,
            plan.biters,
            plan.spitters,
        }, "utility/new_objective")
    else
        announce(force, {
            "the-cave-train-wave.wave-started",
            plan.wave,
            plan.total,
            plan.biters,
            plan.spitters,
            plan.wave + 1,
            format_time(plan.interval_ticks),
        }, "utility/new_objective")
    end

    if state.debug_player_index then
        local player = game.get_player(state.debug_player_index)
        if player and player.valid then
            player.print({
                "the-cave-train-wave.test-directions",
                plan.wave,
                sectors_text(plan.normal_sectors),
                sectors_text(plan.boss_sectors),
            })
        end
    end
    state.test_player_count_override = nil
    state.debug_player_index = nil
end

local function crossed(before, after, threshold)
    return before > threshold and after <= threshold
end

local function check_preparation_warnings(force, state, before, after)
    local thresholds = {
        { 60 * 60 * SECOND, 60 },
        { 30 * 60 * SECOND, 30 },
        { 10 * 60 * SECOND, 10 },
        { 5 * 60 * SECOND, 5 },
        { 1 * 60 * SECOND, 1 },
    }
    for _, threshold in ipairs(thresholds) do
        local key = "prep-" .. threshold[2]
        if crossed(before, after, threshold[1]) and not state.warnings[key] then
            state.warnings[key] = true
            announce(force, { "the-cave-train-wave.preparation-warning", threshold[2] }, "utility/console_message")
        end
    end
end

local function check_wave_warnings(force, state, locomotive, before, after)
    local next_number = state.wave + 1
    local preview = wave_numbers(force, next_number, locomotive.surface, state.test_player_count_override)
    local thresholds = { 1 * 60 * SECOND, 10 * SECOND }

    for _, threshold in ipairs(thresholds) do
        local key = "wave-" .. next_number .. "-" .. threshold
        if crossed(before, after, threshold) and not state.warnings[key] then
            state.warnings[key] = true
            announce(force, {
                "the-cave-train-wave.wave-warning",
                next_number,
                format_time(threshold),
                preview.normal_total,
                preview.biters,
                preview.spitters,
            }, threshold <= 10 * SECOND and "utility/new_objective" or "utility/console_message")
        end
    end
end

local function check_break_warnings(force, state, before, after)
    for _, minutes in ipairs({ 10, 5, 1 }) do
        local threshold = minutes * 60 * SECOND
        local key = "break-" .. state.wave .. "-" .. minutes
        if crossed(before, after, threshold) and not state.warnings[key] then
            state.warnings[key] = true
            announce(force, {
                "the-cave-train-wave.break-warning",
                state.wave,
                state.wave + 1,
                minutes,
            }, minutes == 1 and "utility/new_objective" or "utility/console_message")
        end
    end
end

local function update_scheduler(force, state, locomotive)
    local before = state.remaining_ticks

    if state.phase == "preparation" then
        state.remaining_ticks = math.max(0, before - SECOND)
        check_preparation_warnings(force, state, before, state.remaining_ticks)
        if state.remaining_ticks <= 0 then
            state.phase = "countdown"
            state.remaining_ticks = wave_interval_ticks(1)
            state.warnings = {}
            announce(force, { "the-cave-train-wave.activated" }, "utility/new_objective")
        end
        return
    end

    if state.phase == "break" then
        state.remaining_ticks = math.max(0, before - SECOND)
        check_break_warnings(force, state, before, state.remaining_ticks)
        if state.remaining_ticks <= 0 then begin_wave(force, state, locomotive) end
        return
    end

    state.wave_elapsed_ticks = state.wave_elapsed_ticks + SECOND
    release_due_attack_events(state)

    if state.phase == "boss" then
        state.remaining_ticks = math.max(0, before - SECOND)
        state.boss_next_delay_ticks = math.max(0, state.boss_next_delay_ticks - SECOND)
        maybe_release_next_boss(force, state)
        return
    end

    state.remaining_ticks = math.max(0, before - SECOND)
    check_wave_warnings(force, state, locomotive, before, state.remaining_ticks)
    if state.remaining_ticks <= 0 then begin_wave(force, state, locomotive) end
end

function wave._queued_boss_group(state, sequence)
    for _, group in ipairs(state.queue or {}) do
        if (tonumber(group.bosses) or 0) > 0 and group.wave == state.wave
            and tonumber(group.boss_sequence) == tonumber(sequence) then
            return group
        end
    end
    return nil
end

function wave._different_boss_sector(previous)
    previous = math.max(1, math.min(8, math.floor(tonumber(previous) or 1)))
    return ((previous + math.random(1, 7) - 1) % 8) + 1
end

function wave._discard_active_record(state, record, unit_number)
    destroy_healthbar(record)
    if valid(record.entity) then
        pcall(function() record.entity.destroy { raise_destroy = false } end)
    end
    local key = unit_number or record.unit_number
    if state.units and key then state.units[key] = nil end
end

-- Replace an entity, never the logical Boss. The Wave/sequence counters stay
-- untouched, death rewards are impossible, and the next entity must use a
-- different directional tunnel while retaining its last observed health.
function wave._queue_boss_recovery(state, record, unit_number)
    if not (state and state.phase == "boss" and state.boss_wave_active
        and state.boss_spawned > state.boss_killed) then
        return false
    end

    local snapshot = state.boss_active or {}
    local sequence = math.floor(tonumber(record and record.boss_sequence)
        or tonumber(snapshot.sequence) or tonumber(state.boss_spawned) or 0)
    if sequence <= state.boss_killed or sequence < 1 then return false end

    local health = nil
    if record and valid(record.entity) then health = tonumber(record.entity.health) end
    health = health or tonumber(record and record.last_health) or tonumber(snapshot.health)
    if health then health = math.max(1, health) end
    local maximum = tonumber(record and record.max_health) or tonumber(snapshot.max_health)
    local level = math.max(1, math.min(11, math.floor(
        tonumber(record and record.boss_level) or tonumber(snapshot.level)
            or tonumber(state.last_wave_plan and state.last_wave_plan.boss_level) or 1)))
    local previous_sector = tonumber(record and record.sector) or tonumber(snapshot.sector)
        or tonumber(state.boss_sectors and state.boss_sectors[sequence]) or 1
    local next_sector = wave._different_boss_sector(previous_sector)
    local relocations = math.max(0, math.floor(tonumber(snapshot.relocations) or 0)) + 1

    local pending = wave._queued_boss_group(state, sequence)
    if pending then
        if health then pending.boss_health = health end
        pending.boss_relocations = math.max(
            tonumber(pending.boss_relocations) or 0, relocations)
        next_sector = tonumber(pending.sector) or next_sector
    else
        local burst_id = state.next_burst_id
        state.next_burst_id = state.next_burst_id + 1
        append_group(state, {
            wave = state.wave,
            sector = next_sector,
            biters = 0,
            spitters = 0,
            bosses = 1,
            boss_level = level,
            boss_sequence = sequence,
            boss_health = health,
            boss_relocations = relocations,
            next_kind = "biter",
            failures = 3,
            force_tunnel = true,
            burst_id = burst_id,
        })
    end

    state.boss_active = {
        wave = state.wave,
        sequence = sequence,
        level = level,
        sector = next_sector,
        health = health,
        max_health = maximum,
        relocations = relocations,
        pending = true,
    }
    state.boss_pending = true
    state.boss_next_delay_ticks = 0
    state.spawn_wait_ticks = 0
    state.route_blocked = false
    if record then wave._discard_active_record(state, record, unit_number) end
    return true
end

local function remove_active_record(state, unit_number)
    local record = state.units and state.units[unit_number]
    if not record then return end
    if record.boss and wave._queue_boss_recovery(state, record, unit_number) then return end
    wave._discard_active_record(state, record, unit_number)
end

local function relocate_record(state, record, locomotive)
    if not (record and valid(record.entity) and valid(locomotive)) then return false end
    local name = record.entity.name
    local position = find_spawn_position(locomotive, name, record.sector)
    if not position and record.tunnel_id then
        local tunnel = state.tunnels and state.tunnels[record.tunnel_id]
        if tunnel and tunnel.status == "open" then
            position = find_tunnel_spawn_position(locomotive, name, tunnel)
        end
    end
    if not position or not position_inside_spawn_ring(locomotive, position)
        or position_inside_protected_train_site(
            locomotive.surface, position, TRAIN_SITE_SPAWN_MARGIN) then
        return false
    end

    local moved = false
    local surface_changed = record.entity.surface ~= locomotive.surface
    if surface_changed then destroy_healthbar(record) end
    pcall(function()
        moved = record.entity.teleport(position, locomotive.surface)
    end)
    if not moved then return false end

    if record.boss then record.healthbar = create_boss_healthbar(record.entity) end
    record.last_position = { x = record.entity.position.x, y = record.entity.position.y }
    record.last_health = tonumber(record.entity.health) or record.last_health
    record.stuck_ticks = 0
    record.rescue_attempts = 0
    record.tunnel_route_active = nil
    record.tunnel_route_index = nil
    record.tunnel_route_command_index = nil
    record.tunnel_route_cautious = nil
    record.tunnel_id = nil
    command_locomotive(record, locomotive)
    update_boss_healthbar(record)
    return true
end

local function build_water_bridge(record, locomotive)
    local unit = record and record.entity
    if not (valid(unit) and valid(locomotive) and unit.surface == locomotive.surface
        and is_tunnel_surface(unit.surface)) then
        return 0
    end

    local dx = locomotive.position.x - unit.position.x
    local dy = locomotive.position.y - unit.position.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 2 then return 0 end

    local steps = math.min(WATER_BRIDGE_SCAN_DISTANCE, math.floor(distance))
    local centers = {}
    local center_keys = {}
    local found_water = false
    local reached_far_bank = false
    for step = 1, steps do
        local x = math.floor(unit.position.x + dx * step / distance)
        local y = math.floor(unit.position.y + dy * step / distance)
        local water = is_water_tile(unit.surface.get_tile(x, y))
        if water then
            found_water = true
            local key = tile_key(x, y)
            if not center_keys[key] then
                center_keys[key] = true
                centers[#centers + 1] = { x = x, y = y }
            end
        elseif found_water then
            reached_far_bank = true
            break
        end
    end
    if not found_water or not reached_far_bank then return 0 end

    local width = TUNNEL_WIDTH
    local cells = {}
    for _, center in ipairs(centers) do
        local square = tunnel_square_cells(center, width)
        for _, cell in ipairs(square) do cells[#cells + 1] = cell end
    end
    return landfill_water_cells(unit.surface, cells, locomotive.force)
end

local function rescue_units_from_train_cache_sites(state, locomotive)
    local normal_groups = {}
    local normal_order = {}
    local boss_groups = {}
    local rescued = 0
    local rescued_boss = false

    for unit_number, record in pairs(state.units or {}) do
        local unit = record and record.entity
        if valid(unit) and unit.surface == locomotive.surface
            and position_outside_safe_zone(locomotive, unit.position)
            and position_inside_protected_train_site(
                unit.surface, unit.position, TRAIN_SITE_TUNNEL_MARGIN) then
            if record.boss then
                rescued_boss = true
                boss_groups[#boss_groups + 1] = {
                    wave = record.wave,
                    sector = record.sector,
                    biters = 0,
                    spitters = 0,
                    bosses = 1,
                    boss_level = record.boss_level,
                    boss_sequence = record.boss_sequence,
                    next_kind = "biter",
                    failures = 3,
                    force_tunnel = true,
                }
            else
                local key = tostring(record.wave or 0) .. ":" .. tostring(record.sector or 0)
                local group = normal_groups[key]
                if not group then
                    group = {
                        wave = record.wave,
                        sector = record.sector,
                        biters = 0,
                        spitters = 0,
                        boss_level = record.boss_level,
                        force_tunnel = true,
                        failures = 3,
                    }
                    normal_groups[key] = group
                    normal_order[#normal_order + 1] = key
                end
                if record.kind == "spitter" then
                    group.spitters = group.spitters + 1
                else
                    group.biters = group.biters + 1
                end
            end

            -- Return the attacker to its script queue without a death event,
            -- loot, Boss completion or Wave-count loss.
            destroy_healthbar(record)
            pcall(function() unit.destroy { raise_destroy = false } end)
            state.units[unit_number] = nil
            rescued = rescued + 1
        end
    end

    for _, key in ipairs(normal_order) do
        local source = normal_groups[key]
        while source.biters + source.spitters > 0 do
            local capacity = MAX_ATOMIC_GROUP_SIZE
            local biters = math.min(source.biters, capacity)
            source.biters = source.biters - biters
            capacity = capacity - biters
            local spitters = math.min(source.spitters, capacity)
            source.spitters = source.spitters - spitters
            append_group(state, {
                wave = source.wave,
                sector = source.sector,
                biters = biters,
                spitters = spitters,
                bosses = 0,
                boss_level = source.boss_level,
                next_kind = "biter",
                failures = 3,
                force_tunnel = true,
            })
        end
    end
    for _, group in ipairs(boss_groups) do append_group(state, group) end
    if rescued > 0 then
        if rescued_boss then state.boss_pending = true end
        state.spawn_wait_ticks = 0
        state.route_blocked = false
    end
    return rescued
end

-- Repair an upgraded save once: rescue attackers already trapped at a cache
-- and retire old straight routes so every replacement can use local bypasses.
function wave._migrate_train_cache_routes(state, locomotive)
    if not (state and valid(locomotive)) then return 0 end
    if state.train_cache_route_profile_version == wave.train_cache_route_profile_version then
        return 0
    end

    local rescued = rescue_units_from_train_cache_sites(state, locomotive)
    for _, tunnel in pairs(state.tunnels or {}) do
        if tunnel and tunnel.status == "digging" then
            fail_tunnel(state, tunnel, locomotive, true)
        elseif tunnel and tunnel.status == "open" then
            wave._retire_stalled_tunnel(state, tunnel, locomotive)
        end
    end
    state.train_cache_route_profile_version = wave.train_cache_route_profile_version
    state.spawn_wait_ticks = 0
    return rescued
end

function wave._retire_stalled_tunnel(state, tunnel, locomotive)
    if not (state and tunnel and tunnel.status == "open" and valid(locomotive)) then return 0 end
    -- A canonical mouth is permanent. Stalled units may have their commands
    -- refreshed, but they must never cause another scar to be carved.
    if tunnel.persistent then return 0 end
    tunnel.status = "failed"
    tunnel.pending = nil

    local avoid_positions = {}
    for _, position in ipairs(tunnel.avoid_positions or {}) do
        avoid_positions[#avoid_positions + 1] = { x = position.x, y = position.y }
    end
    if tunnel.deployment_position then
        avoid_positions[#avoid_positions + 1] = {
            x = tunnel.deployment_position.x,
            y = tunnel.deployment_position.y,
        }
    end

    local function prepare_group(group)
        group.tunnel_id = nil
        group.force_tunnel = true
        group.failures = 3
        group.tunnel_rebuilds = math.max(
            tonumber(group.tunnel_rebuilds) or 0,
            (tonumber(tunnel.rebuilds) or 0) + 1)
        group.avoid_positions = {}
        for _, position in ipairs(avoid_positions) do
            group.avoid_positions[#group.avoid_positions + 1] = {
                x = position.x,
                y = position.y,
            }
        end
        return group
    end

    for _, group in ipairs(state.queue or {}) do
        if group.tunnel_id == tunnel.id then prepare_group(group) end
    end

    local normal = {}
    local order = {}
    local bosses = {}
    local rescued = 0
    local rescued_boss = false
    for unit_number, record in pairs(state.units or {}) do
        local unit = record and record.entity
        if record and record.tunnel_id == tunnel.id and valid(unit) then
            local player_engaged = not record.boss
                and type(record.wave_command_role) == "string"
                and record.wave_command_role:sub(1, 7) == "player:"
            local military_engaged = wave._military_target_is_live(record, locomotive)
            local recover = unit.surface == locomotive.surface
                and position_outside_safe_zone(locomotive, unit.position)
                and not player_engaged and not military_engaged
            if recover then
                if record.boss then
                    rescued_boss = true
                    bosses[#bosses + 1] = prepare_group {
                        wave = record.wave,
                        sector = record.sector,
                        biters = 0,
                        spitters = 0,
                        bosses = 1,
                        boss_level = record.boss_level,
                        boss_sequence = record.boss_sequence,
                        next_kind = "biter",
                    }
                else
                    local key = tostring(record.wave or 0) .. ":" .. tostring(record.sector or 0)
                    local group = normal[key]
                    if not group then
                        group = prepare_group {
                            wave = record.wave,
                            sector = record.sector,
                            biters = 0,
                            spitters = 0,
                            bosses = 0,
                            boss_level = record.boss_level,
                            next_kind = "biter",
                        }
                        normal[key] = group
                        order[#order + 1] = key
                    end
                    if record.kind == "spitter" then
                        group.spitters = group.spitters + 1
                    else
                        group.biters = group.biters + 1
                    end
                end
                destroy_healthbar(record)
                pcall(function() unit.destroy { raise_destroy = false } end)
                state.units[unit_number] = nil
                rescued = rescued + 1
            else
                record.tunnel_route_active = nil
                record.tunnel_route_index = nil
                record.tunnel_route_command_index = nil
                record.tunnel_route_cautious = nil
                record.tunnel_id = nil
                if not military_engaged then command_locomotive(record, locomotive) end
            end
        end
    end

    for _, key in ipairs(order) do
        local source = normal[key]
        while source.biters + source.spitters > 0 do
            local capacity = MAX_ATOMIC_GROUP_SIZE
            local biters = math.min(source.biters, capacity)
            source.biters = source.biters - biters
            capacity = capacity - biters
            local spitters = math.min(source.spitters, capacity)
            source.spitters = source.spitters - spitters
            local group = prepare_group {
                wave = source.wave,
                sector = source.sector,
                biters = biters,
                spitters = spitters,
                bosses = 0,
                boss_level = source.boss_level,
                next_kind = "biter",
            }
            append_group(state, group)
        end
    end
    for _, group in ipairs(bosses) do append_group(state, group) end
    if rescued > 0 then
        if rescued_boss then state.boss_pending = true end
        state.spawn_wait_ticks = 0
        state.route_blocked = false
    end
    return rescued
end

-- Upgrade an existing save without carving another forest of radial tunnels.
-- Keep the best existing route in each of the eight sectors and prevent every
-- later Wave from claiming one of the old surplus routes.
function wave._migrate_persistent_tunnels(state, locomotive)
    if not (state and valid(locomotive)) then return end
    if state.persistent_tunnel_profile_version == wave.persistent_tunnel_profile_version then
        return
    end

    state.canonical_tunnel_ids = {}
    state.tunnel_retry_profiles = {}
    local chosen = {}
    for id, tunnel in pairs(state.tunnels or {}) do
        local sector = tunnel and math.floor(tonumber(tunnel.sector) or 0) or 0
        if tunnel and tunnel.status ~= "failed"
            and tunnel.surface_index == locomotive.surface.index
            and sector >= 1 and sector <= 8 then
            tunnel.sector = sector
            local rank = tunnel.status == "open" and 2 or 1
            local current = chosen[sector]
            if not current or rank > current.rank
                or rank == current.rank
                    and (tonumber(id) or math.huge) < (tonumber(current.id) or math.huge) then
                chosen[sector] = { id = id, tunnel = tunnel, rank = rank }
            end
        end
    end

    for sector = 1, 8 do
        local selected = chosen[sector]
        if selected then
            selected.tunnel.persistent = true
            selected.tunnel.legacy_extra = nil
            state.canonical_tunnel_ids[sector] = selected.id
        end
    end

    for id, tunnel in pairs(state.tunnels or {}) do
        if tunnel and tunnel.status ~= "failed"
            and tunnel.surface_index == locomotive.surface.index
            and state.canonical_tunnel_ids[tunnel.sector] ~= id then
            tunnel.persistent = false
            if tunnel.status == "digging" then
                tunnel.status = "failed"
                tunnel.pending = nil
            else
                tunnel.legacy_extra = true
            end
        end
    end

    for _, group in ipairs(state.queue or {}) do
        local old = group.tunnel_id and state.tunnels[group.tunnel_id] or nil
        if old and (old.status == "failed" or old.legacy_extra) then
            group.tunnel_id = state.canonical_tunnel_ids[group.sector]
            group.force_tunnel = true
            group.failures = 3
        elseif group.tunnel_id and not old then
            group.tunnel_id = state.canonical_tunnel_ids[group.sector]
        end
    end

    state.persistent_tunnel_profile_version = wave.persistent_tunnel_profile_version
    state.spawn_wait_ticks = 0
end

function wave._find_attack_region(state, surface_index, position)
    if not (state and surface_index and position) then return nil end
    local best = nil
    local best_distance = math.huge
    for _, region in pairs(state.attack_regions or {}) do
        if region and region.surface_index == surface_index and region.anchor_position then
            local distance = position_distance_squared(position, region.anchor_position)
            if distance <= wave.attack_region_radius_squared and distance < best_distance then
                best = region
                best_distance = distance
            end
        end
    end
    return best
end

-- Convert the single permanent tunnel set from 1.2.11/2.7.102 into the first
-- saved attack region. The route ends provide the old Main Train centre even
-- when the player installs this upgrade after already driving away.
function wave._migrate_attack_regions(state, locomotive)
    if not (state and valid(locomotive)) then return nil end
    if state.attack_region_profile_version ~= wave.attack_region_profile_version then
        local x, y, count = 0, 0, 0
        for _, id in pairs(state.canonical_tunnel_ids or {}) do
            local tunnel = state.tunnels and state.tunnels[id] or nil
            if tunnel and tunnel.surface_index == locomotive.surface.index then
                local route = type(tunnel.route) == "table" and tunnel.route or nil
                local position = route and route[#route]
                    or tunnel.target_position or tunnel.current or tunnel.deployment_position
                if position then
                    x = x + position.x
                    y = y + position.y
                    count = count + 1
                end
            end
        end
        local anchor = count > 0 and { x = x / count, y = y / count }
            or { x = locomotive.position.x, y = locomotive.position.y }
        local id = 1
        local region = {
            id = id,
            surface_index = locomotive.surface.index,
            anchor_position = anchor,
            canonical_tunnel_ids = state.canonical_tunnel_ids or {},
            tunnel_retry_profiles = state.tunnel_retry_profiles or {},
        }
        state.attack_regions = { [id] = region }
        state.active_attack_region_id = id
        state.next_attack_region_id = 2
        state.attack_region_candidate_started_tick = nil
        state.attack_region_candidate_ready = false
        state.attack_region_profile_version = wave.attack_region_profile_version
        for _, tunnel_id in pairs(region.canonical_tunnel_ids) do
            local tunnel = state.tunnels and state.tunnels[tunnel_id] or nil
            if tunnel then
                tunnel.region_id = id
                tunnel.persistent = true
                tunnel.target_position = tunnel.target_position or {
                    x = anchor.x,
                    y = anchor.y,
                }
            end
        end
    end

    state.attack_regions = state.attack_regions or {}
    local active = state.attack_regions[state.active_attack_region_id]
    if not active then
        local id = math.max(1, math.floor(tonumber(state.next_attack_region_id) or 1))
        active = {
            id = id,
            surface_index = locomotive.surface.index,
            anchor_position = {
                x = locomotive.position.x,
                y = locomotive.position.y,
            },
            canonical_tunnel_ids = {},
            tunnel_retry_profiles = {},
        }
        state.attack_regions[id] = active
        state.active_attack_region_id = id
        state.next_attack_region_id = id + 1
    end
    active.canonical_tunnel_ids = active.canonical_tunnel_ids or {}
    active.tunnel_retry_profiles = active.tunnel_retry_profiles or {}
    state.canonical_tunnel_ids = active.canonical_tunnel_ids
    state.tunnel_retry_profiles = active.tunnel_retry_profiles
    return active
end

local function requeue_mouth_only_tunnel_units(state, tunnel)
    local normal = {}
    local order = {}
    local bosses = {}
    local recovered = 0
    local recovered_boss = false

    for unit_number, record in pairs(state.units or {}) do
        if record and record.tunnel_id == tunnel.id then
            if valid(record.entity) then
                if record.boss then
                    recovered_boss = true
                    bosses[#bosses + 1] = {
                        wave = record.wave or state.wave,
                        sector = record.sector or tunnel.sector or 1,
                        biters = 0,
                        spitters = 0,
                        bosses = 1,
                        boss_level = record.boss_level,
                        boss_sequence = record.boss_sequence,
                        next_kind = "biter",
                        failures = 0,
                        force_tunnel = true,
                        tunnel_id = tunnel.id,
                    }
                else
                    local wave_number = record.wave or state.wave or 0
                    local sector = record.sector or tunnel.sector or 1
                    local key = tostring(wave_number) .. ":" .. tostring(sector)
                    local group = normal[key]
                    if not group then
                        group = {
                            wave = wave_number,
                            sector = sector,
                            biters = 0,
                            spitters = 0,
                            bosses = 0,
                            next_kind = "biter",
                            failures = 0,
                            force_tunnel = true,
                            tunnel_id = tunnel.id,
                        }
                        normal[key] = group
                        order[#order + 1] = key
                    end
                    if record.kind == "spitter" then
                        group.spitters = group.spitters + 1
                    else
                        group.biters = group.biters + 1
                    end
                end
                recovered = recovered + 1
                destroy_healthbar(record)
                pcall(function() record.entity.destroy { raise_destroy = false } end)
            else
                destroy_healthbar(record)
            end
            state.units[unit_number] = nil
        end
    end

    for _, key in ipairs(order) do
        local source = normal[key]
        while source.biters + source.spitters > 0 do
            local capacity = MAX_ATOMIC_GROUP_SIZE
            local biters = math.min(source.biters, capacity)
            source.biters = source.biters - biters
            capacity = capacity - biters
            local spitters = math.min(source.spitters, capacity)
            source.spitters = source.spitters - spitters
            append_group(state, {
                wave = source.wave,
                sector = source.sector,
                biters = biters,
                spitters = spitters,
                bosses = 0,
                next_kind = "biter",
                failures = 0,
                force_tunnel = true,
                tunnel_id = tunnel.id,
            })
        end
    end
    for _, group in ipairs(bosses) do append_group(state, group) end
    if recovered_boss then state.boss_pending = true end
    return recovered
end

-- 3.0.62 save repair: the old controller could declare a route open after its
-- first one-tile step because that entire slice still overlapped the round
-- mouth chamber. Restore only those unmistakable mouth-only routes in place,
-- preserving the chamber and queued Wave while returning already deployed
-- attackers to their exact tunnel queue without death credit or loot.
function wave._repair_mouth_only_tunnels(state, locomotive)
    if not (state and valid(locomotive)) then return 0, 0 end
    if state.tunnel_mouth_repair_version == wave.tunnel_mouth_repair_version then
        return 0, 0
    end

    local repaired = 0
    local recovered = 0
    for id, tunnel in pairs(state.tunnels or {}) do
        if tunnel and tunnel.status == "open"
            and tunnel.surface_index == locomotive.surface.index
            and tunnel_face_inside_mouth(tunnel) then
            tunnel.id = tunnel.id or id
            recovered = recovered + requeue_mouth_only_tunnel_units(state, tunnel)
            tunnel.status = "digging"
            tunnel.width = TUNNEL_WIDTH
            tunnel.steps = 0
            tunnel.step_wait_ticks = TUNNEL_STEP_TICKS
            tunnel.pending = nil
            tunnel.persistent = true
            tunnel.frontier_carved = nil
            tunnel.cache_detour_waypoints = nil
            tunnel.cache_detour_index = nil
            tunnel.cache_detour_side = nil
            tunnel.cache_detour_attempts = 0
            tunnel.stall_last_count = nil
            tunnel.stall_last_route_index = nil
            tunnel.stall_last_nearest = nil
            tunnel.stall_last_progress_tick = nil
            tunnel.route = {
                { x = tunnel.current.x + 0.5, y = tunnel.current.y + 0.5 },
            }
            tunnel.exit_position = {
                x = tunnel.current.x + 0.5,
                y = tunnel.current.y + 0.5,
            }
            if state.tunnel_breached_waves then
                state.tunnel_breached_waves[tunnel.wave] = nil
            end
            repaired = repaired + 1
        end
    end

    state.tunnel_mouth_repair_version = wave.tunnel_mouth_repair_version
    if repaired > 0 then
        state.spawn_wait_ticks = 0
        state.route_blocked = false
        state.player_aggro_groups = {}
    end
    return repaired, recovered
end

function wave._activate_attack_region(state, force, locomotive, region)
    if not (state and force and force.valid and valid(locomotive) and region) then return false end
    local previous = state.attack_regions and state.attack_regions[state.active_attack_region_id] or nil
    if previous and previous.id ~= region.id then
        for sector, id in pairs(previous.canonical_tunnel_ids or {}) do
            local tunnel = state.tunnels and state.tunnels[id] or nil
            if tunnel and tunnel.status == "digging" then
                tunnel.status = "failed"
                tunnel.pending = nil
                previous.canonical_tunnel_ids[sector] = nil
            end
        end
    end

    region.canonical_tunnel_ids = region.canonical_tunnel_ids or {}
    region.tunnel_retry_profiles = region.tunnel_retry_profiles or {}
    state.active_attack_region_id = region.id
    state.canonical_tunnel_ids = region.canonical_tunnel_ids
    state.tunnel_retry_profiles = region.tunnel_retry_profiles
    for _, id in pairs(region.canonical_tunnel_ids) do
        local tunnel = state.tunnels and state.tunnels[id] or nil
        if tunnel and tunnel.status ~= "failed" then
            tunnel.region_id = region.id
            tunnel.persistent = true
            tunnel.target_position = tunnel.target_position or {
                x = region.anchor_position.x,
                y = region.anchor_position.y,
            }
        end
    end
    for _, group in ipairs(state.queue or {}) do
        local id = region.canonical_tunnel_ids[group.sector]
        local tunnel = id and state.tunnels and state.tunnels[id] or nil
        group.tunnel_id = tunnel and tunnel.status ~= "failed" and id or nil
        group.force_tunnel = true
        group.failures = 3
    end
    state.attack_region_candidate_started_tick = nil
    state.attack_region_candidate_ready = false
    state.eight_tunnel_reserved_wave = nil
    state.tunnel_reserve_retry_tick = 0
    state.spawn_wait_ticks = 0
    state.route_blocked = false
    announce(force, { "the-cave-train-wave.attack-region-activated" }, "utility/new_objective")
    return true
end

-- Leaving the active five-chunk area starts the timer but does not pause any
-- Wave, tunnel or living attacker. Returning cancels it. Once five minutes
-- have elapsed, the next stopped position becomes (or reuses) a saved region.
function wave._update_attack_region(state, force, locomotive)
    local active = wave._migrate_attack_regions(state, locomotive)
    if not active then return false end
    local inside_active = active.surface_index == locomotive.surface.index
        and position_distance_squared(locomotive.position, active.anchor_position)
            <= wave.attack_region_radius_squared
    if inside_active then
        state.attack_region_candidate_started_tick = nil
        state.attack_region_candidate_ready = false
        return false
    end

    if not state.attack_region_candidate_started_tick then
        state.attack_region_candidate_started_tick = game.tick
        state.attack_region_candidate_ready = false
    end
    if game.tick - state.attack_region_candidate_started_tick
        >= wave.attack_region_activation_ticks then
        state.attack_region_candidate_ready = true
    end
    if not state.attack_region_candidate_ready
        or math.abs(tonumber(locomotive.speed) or 0) > wave.attack_region_stop_speed then
        return false
    end

    local region = wave._find_attack_region(
        state, locomotive.surface.index, locomotive.position)
    if not region then
        local id = math.max(1, math.floor(tonumber(state.next_attack_region_id) or 1))
        region = {
            id = id,
            surface_index = locomotive.surface.index,
            anchor_position = {
                x = locomotive.position.x,
                y = locomotive.position.y,
            },
            canonical_tunnel_ids = {},
            tunnel_retry_profiles = {},
        }
        state.attack_regions[id] = region
        state.next_attack_region_id = id + 1
    end
    return wave._activate_attack_region(state, force, locomotive, region)
end

function wave._military_target_is_live(record, locomotive)
    local unit = record and record.entity
    local target = record and record.military_target
    if not (valid(unit) and valid(target) and target ~= locomotive
        and unit.surface == target.surface and valid(unit.force) and valid(target.force)
        and unit.force ~= target.force) then
        return false
    end

    local friendly = false
    local cease_fire = false
    pcall(function()
        friendly = unit.force.get_friend(target.force)
        cease_fire = unit.force.get_cease_fire(target.force)
    end)
    if friendly or cease_fire then return false end

    local vision = wave.military_target_fallback_vision
    pcall(function()
        vision = tonumber(unit.prototype.vision_distance) or vision
    end)
    vision = math.max(1, tonumber(vision) or wave.military_target_fallback_vision)
    return position_distance_squared(unit.position, target.position) <= vision * vision
end

function wave._recover_stalled_tunnels(state, locomotive)
    local observations = {}
    for _, record in pairs(state.units or {}) do
        local unit = record and record.entity
        local tunnel = record and record.tunnel_id and state.tunnels[record.tunnel_id] or nil
        local player_engaged = record and not record.boss
            and type(record.wave_command_role) == "string"
            and record.wave_command_role:sub(1, 7) == "player:"
        local military_engaged = wave._military_target_is_live(record, locomotive)
        -- Boss obstruction/recovery is owned exclusively by its continuous
        -- 120-second controller; the generic 30-second tunnel watchdog must
        -- neither overwrite its attack order nor retire its route early.
        if valid(unit) and not record.boss and tunnel and tunnel.status == "open"
            and unit.surface == locomotive.surface
            and position_outside_safe_zone(locomotive, unit.position)
            and not player_engaged and not military_engaged then
            local observation = observations[tunnel.id]
            if not observation then
                observation = { count = 0, nearest = math.huge, route_index = 0 }
                observations[tunnel.id] = observation
            end
            observation.count = observation.count + 1
            observation.nearest = math.min(observation.nearest,
                math.sqrt(position_distance_squared(unit.position, locomotive.position)))
            observation.route_index = math.max(observation.route_index,
                tonumber(record.tunnel_route_index) or 0)
        end
    end

    for id, tunnel in pairs(state.tunnels or {}) do
        local observation = observations[id]
        if tunnel and tunnel.status == "open" and observation and observation.count > 0 then
            local progressed = tunnel.stall_last_count == nil
                or observation.count < tunnel.stall_last_count
                or observation.route_index > (tonumber(tunnel.stall_last_route_index) or 0)
                or observation.nearest <= (tonumber(tunnel.stall_last_nearest) or math.huge) - 2
            if progressed then tunnel.stall_last_progress_tick = game.tick end
            tunnel.stall_last_count = observation.count
            tunnel.stall_last_route_index = observation.route_index
            tunnel.stall_last_nearest = observation.nearest
            if game.tick - (tonumber(tunnel.stall_last_progress_tick) or game.tick)
                >= wave.tunnel_stall_timeout_ticks then
                if tunnel.persistent then
                    for _, record in pairs(state.units or {}) do
                        if record and record.tunnel_id == tunnel.id and valid(record.entity)
                            and not wave._military_target_is_live(record, locomotive) then
                            record.tunnel_route_command_index = nil
                            wave._command_tunnel_position(record, tunnel, true)
                        end
                    end
                    tunnel.stall_last_progress_tick = game.tick
                else
                    wave._retire_stalled_tunnel(state, tunnel, locomotive)
                end
            end
        elseif tunnel then
            tunnel.stall_last_count = nil
            tunnel.stall_last_route_index = nil
            tunnel.stall_last_nearest = nil
            tunnel.stall_last_progress_tick = nil
        end
    end
end

function wave._boss_point_coordinate(point, key, index)
    return point and (tonumber(point[key]) or tonumber(point[index])) or nil
end

function wave._boss_entity_box(entity)
    if not valid(entity) then return nil end
    local box = nil
    pcall(function() box = entity.bounding_box end)
    if not box then return nil end
    local left = box.left_top or box[1]
    local right = box.right_bottom or box[2]
    local left_x = wave._boss_point_coordinate(left, "x", 1)
    local left_y = wave._boss_point_coordinate(left, "y", 2)
    local right_x = wave._boss_point_coordinate(right, "x", 1)
    local right_y = wave._boss_point_coordinate(right, "y", 2)
    if not (left_x and left_y and right_x and right_y) then return nil end
    return {
        left = math.min(left_x, right_x),
        top = math.min(left_y, right_y),
        right = math.max(left_x, right_x),
        bottom = math.max(left_y, right_y),
    }
end

function wave._boss_same_collision_layers(first, second)
    for layer in pairs(first or {}) do
        if not (second and second[layer]) then return false end
    end
    for layer in pairs(second or {}) do
        if not (first and first[layer]) then return false end
    end
    return true
end

function wave._boss_entities_collide(first_entity, second_entity)
    if not (valid(first_entity) and valid(second_entity)) then return false end
    local first = nil
    local second = nil
    pcall(function() first = first_entity.prototype.collision_mask end)
    pcall(function() second = second_entity.prototype.collision_mask end)
    local first_layers = first and first.layers
    local second_layers = second and second.layers
    if type(first_layers) ~= "table" or type(second_layers) ~= "table"
        or first.colliding_with_tiles_only or second.colliding_with_tiles_only then
        return false
    end
    local overlaps = false
    for layer in pairs(first_layers) do
        if second_layers[layer] then
            overlaps = true
            break
        end
    end
    if not overlaps then return false end
    if first.not_colliding_with_itself and second.not_colliding_with_itself
        and wave._boss_same_collision_layers(first_layers, second_layers) then
        return false
    end
    return true
end

function wave._boss_entity_gap_squared(first, second)
    local a = wave._boss_entity_box(first)
    local b = wave._boss_entity_box(second)
    if not (a and b) then
        return position_distance_squared(first.position, second.position)
    end
    local dx = 0
    if a.right < b.left then
        dx = b.left - a.right
    elseif b.right < a.left then
        dx = a.left - b.right
    end
    local dy = 0
    if a.bottom < b.top then
        dy = b.top - a.bottom
    elseif b.bottom < a.top then
        dy = a.top - b.bottom
    end
    return dx * dx + dy * dy
end

function wave._boss_blocker_role(entity)
    if not valid(entity) then return nil end
    if entity.unit_number then return "boss-blocker:" .. tostring(entity.unit_number) end
    return "boss-blocker:" .. tostring(entity.name) .. ":"
        .. tostring(math.floor(entity.position.x * 2)) .. ":"
        .. tostring(math.floor(entity.position.y * 2))
end

-- Scan only the swept collision corridor between the Boss and its current
-- route destination. A nearby belt or building that the Boss can physically
-- cross is not a blocker, and entities beside the corridor are not selected.
function wave._find_boss_blocker(record, locomotive, destination)
    local unit = record and record.entity
    if not (valid(unit) and valid(locomotive) and destination
        and unit.surface == locomotive.surface) then return nil end

    local dx = destination.x - unit.position.x
    local dy = destination.y - unit.position.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.01 then return nil end
    local direction_x = dx / distance
    local direction_y = dy / distance
    local scan_distance = math.min(BOSS_CONTROL.blocker_scan_distance, distance)
    local end_x = unit.position.x + direction_x * scan_distance
    local end_y = unit.position.y + direction_y * scan_distance
    local unit_bounds = wave._boss_entity_box(unit)
    local unit_half_width = unit_bounds and (unit_bounds.right - unit_bounds.left) * 0.5 or 1
    local unit_half_height = unit_bounds and (unit_bounds.bottom - unit_bounds.top) * 0.5 or 1
    local unit_perpendicular_radius = math.abs(direction_y) * unit_half_width
        + math.abs(direction_x) * unit_half_height
    local padding = unit_perpendicular_radius + 4
    local candidates = unit.surface.find_entities_filtered {
        area = {
            { math.min(unit.position.x, end_x) - padding,
                math.min(unit.position.y, end_y) - padding },
            { math.max(unit.position.x, end_x) + padding,
                math.max(unit.position.y, end_y) + padding },
        },
        force = locomotive.force,
    }

    local best = nil
    local best_score = nil
    for _, candidate in pairs(candidates or {}) do
        local health = nil
        pcall(function() health = tonumber(candidate.health) end)
        if valid(candidate) and candidate ~= locomotive and health and health > 0
            and not BOSS_CONTROL.excluded_types[candidate.type]
            and wave._boss_entities_collide(unit, candidate) then
            local bounds = wave._boss_entity_box(candidate)
            if bounds then
                local center_x = (bounds.left + bounds.right) * 0.5
                local center_y = (bounds.top + bounds.bottom) * 0.5
                local half_width = (bounds.right - bounds.left) * 0.5
                local half_height = (bounds.bottom - bounds.top) * 0.5
                local offset_x = center_x - unit.position.x
                local offset_y = center_y - unit.position.y
                local projection = offset_x * direction_x + offset_y * direction_y
                local perpendicular = math.abs(offset_x * direction_y - offset_y * direction_x)
                local projection_radius = math.abs(direction_x) * half_width
                    + math.abs(direction_y) * half_height
                local perpendicular_radius = math.abs(direction_y) * half_width
                    + math.abs(direction_x) * half_height
                local near_edge = projection - projection_radius
                local far_edge = projection + projection_radius
                local side_gap = perpendicular - perpendicular_radius
                    - unit_perpendicular_radius
                if far_edge >= -0.25 and near_edge <= scan_distance
                    and side_gap <= 0.35 then
                    local score = math.max(0, near_edge) * 100
                        + math.max(0, side_gap)
                    if not best_score or score < best_score then
                        best = candidate
                        best_score = score
                    end
                end
            end
        end
    end
    return best
end

function wave._clear_boss_obstruction(record)
    record.boss_blocker = nil
    record.boss_obstruction_started_tick = nil
    record.boss_last_blocker_tick = nil
    record.boss_last_blocker_position = nil
    record.boss_last_blocker_direction = nil
end

function wave._update_boss_snapshot(state, record)
    if not (state and record and record.boss and valid(record.entity)) then return end
    local current = state.boss_active or {}
    current.wave = record.wave
    current.sequence = record.boss_sequence
    current.level = record.boss_level
    current.sector = record.sector
    current.unit_number = record.entity.unit_number
    current.health = tonumber(record.entity.health) or tonumber(record.last_health)
    current.max_health = tonumber(record.max_health) or current.max_health
    current.relocations = math.max(0, math.floor(tonumber(current.relocations) or 0))
    current.pending = nil
    state.boss_active = current
    record.last_health = current.health or record.last_health
end

function wave._boss_route_destination(state, record, locomotive)
    local tunnel = record.tunnel_id and state.tunnels[record.tunnel_id] or nil
    if record.tunneling == true and tunnel and tunnel.status == "digging" then
        return nil, true
    end
    if record.tunnel_route_active and tunnel and tunnel.status == "open"
        and type(tunnel.route) == "table" and #tunnel.route > 1 then
        local index = math.max(2, math.min(#tunnel.route,
            math.floor(tonumber(record.tunnel_route_index) or 2)))
        return tunnel.route[index], true
    end
    return locomotive.position, false
end

function wave._resume_boss_route(state, record, locomotive)
    if record.tunnel_route_active then
        local tunnel = record.tunnel_id and state.tunnels[record.tunnel_id] or nil
        if wave._command_tunnel_position(record, tunnel, true) then return true end
    end
    return command_locomotive(record, locomotive)
end

function wave._update_one_boss(state, record, unit_number, locomotive)
    local unit = record and record.entity
    if not valid(unit) then
        wave._queue_boss_recovery(state, record, unit_number)
        return false
    end
    if unit.surface ~= locomotive.surface then
        wave._update_boss_snapshot(state, record)
        wave._queue_boss_recovery(state, record, unit_number)
        return false
    end

    wave._update_boss_snapshot(state, record)
    local destination, waiting_for_tunnel = wave._boss_route_destination(
        state, record, locomotive)
    if not destination then
        wave._clear_boss_obstruction(record)
        record.boss_free_progress_tick = game.tick
        record.boss_free_progress_position = {
            x = unit.position.x,
            y = unit.position.y,
        }
        return true
    end

    local blocker = wave._find_boss_blocker(record, locomotive, destination)
    if blocker then
        if not record.boss_obstruction_started_tick then
            record.boss_obstruction_started_tick = game.tick
        end
        record.boss_last_blocker_tick = game.tick
        record.boss_last_blocker_position = {
            x = unit.position.x,
            y = unit.position.y,
        }
        local dx = destination.x - unit.position.x
        local dy = destination.y - unit.position.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0 then
            record.boss_last_blocker_direction = {
                x = dx / length,
                y = dy / length,
            }
        end
        record.boss_blocker = blocker
        local role = wave._boss_blocker_role(blocker)
        if record.wave_command_role ~= role
            or record.wave_command_target_unit_number ~= blocker.unit_number then
            command_record(record, blocker, role, defines.distraction.none)
        end
    elseif record.boss_obstruction_started_tick then
        record.boss_blocker = nil
        if type(record.wave_command_role) == "string"
            and record.wave_command_role:sub(1, 13) == "boss-blocker:" then
            wave._resume_boss_route(state, record, locomotive)
        end
        local origin = record.boss_last_blocker_position or unit.position
        local direction = record.boss_last_blocker_direction
        local moved_x = unit.position.x - origin.x
        local moved_y = unit.position.y - origin.y
        local forward = direction and (moved_x * direction.x + moved_y * direction.y)
            or math.sqrt(moved_x * moved_x + moved_y * moved_y)
        local clear_long_enough = game.tick
            - math.max(0, tonumber(record.boss_last_blocker_tick) or game.tick)
            >= BOSS_CONTROL.blocker_clear_grace_ticks
        if clear_long_enough and forward >= BOSS_CONTROL.blocker_clear_distance then
            wave._clear_boss_obstruction(record)
            record.boss_free_progress_tick = game.tick
            record.boss_free_progress_position = {
                x = unit.position.x,
                y = unit.position.y,
            }
        end
    end

    if record.boss_obstruction_started_tick
        and game.tick - record.boss_obstruction_started_tick
            >= BOSS_CONTROL.blocker_timeout_ticks then
        wave._update_boss_snapshot(state, record)
        wave._queue_boss_recovery(state, record, unit_number)
        return false
    end
    if record.boss_obstruction_started_tick or blocker then return true end

    if waiting_for_tunnel then
        record.boss_free_progress_tick = game.tick
        record.boss_free_progress_position = {
            x = unit.position.x,
            y = unit.position.y,
        }
        return true
    end

    if wave._boss_entity_gap_squared(unit, locomotive)
        <= BOSS_CONTROL.goal_attack_gap * BOSS_CONTROL.goal_attack_gap then
        record.boss_free_progress_tick = game.tick
        record.boss_free_progress_position = {
            x = unit.position.x,
            y = unit.position.y,
        }
        if record.wave_command_role ~= "boss-locomotive"
            or record.wave_command_target_unit_number ~= locomotive.unit_number then
            command_locomotive(record, locomotive)
        end
        return true
    end

    local progress_position = record.boss_free_progress_position
    if not progress_position
        or position_distance_squared(unit.position, progress_position)
            >= BOSS_CONTROL.free_stall_distance * BOSS_CONTROL.free_stall_distance then
        record.boss_free_progress_tick = game.tick
        record.boss_free_progress_position = {
            x = unit.position.x,
            y = unit.position.y,
        }
    elseif game.tick - math.max(0,
        tonumber(record.boss_free_progress_tick) or game.tick)
            >= BOSS_CONTROL.blocker_timeout_ticks then
        wave._update_boss_snapshot(state, record)
        wave._queue_boss_recovery(state, record, unit_number)
        return false
    end

    if record.wave_command_role ~= "boss-locomotive"
        or record.wave_command_target_unit_number ~= locomotive.unit_number then
        command_locomotive(record, locomotive)
    end
    return true
end

function wave._update_boss_control(state, locomotive)
    if not (state and state.phase == "boss" and state.boss_wave_active
        and valid(locomotive)) then return end
    local live_boss = false
    for unit_number, record in pairs(state.units or {}) do
        if record and record.boss and record.wave == state.wave and not record.boss_finished then
            if valid(record.entity) then
                if wave._update_one_boss(state, record, unit_number, locomotive) then
                    live_boss = true
                end
            else
                wave._queue_boss_recovery(state, record, unit_number)
            end
        end
    end

    if live_boss or state.boss_spawned <= state.boss_killed then return end
    local sequence = state.boss_spawned
    local pending = wave._queued_boss_group(state, sequence)
    if pending then
        state.boss_pending = true
    else
        -- Repair both a freshly removed entity and an older save already
        -- stranded at Boss Status: Unknown.
        state.boss_pending = false
        wave._queue_boss_recovery(state, nil, nil)
    end
end

local function update_unit_safety(state, locomotive)
    -- Attackers may pass discovered Train caches. Do not destroy and requeue
    -- them merely for entering a cache site.
    for unit_number, record in pairs(state.units or {}) do
        local unit = record and record.entity
        if not valid(unit) then
            if not (record and record.boss
                and wave._queue_boss_recovery(state, record, unit_number)) then
                destroy_healthbar(record)
                state.units[unit_number] = nil
            end
        else
            update_boss_healthbar(record)
            if record.boss then
                -- The dedicated Boss controller owns its blocker timer and
                -- tunnel replacement. The generic 30-second unit rescue must
                -- never teleport it early or convert a cleanup into kill credit.
                wave._update_boss_snapshot(state, record)
                record.last_position = { x = unit.position.x, y = unit.position.y }
                record.last_health = tonumber(unit.health) or record.last_health
            else
                local tunnel = record.tunnel_id and state.tunnels[record.tunnel_id] or nil
                local waiting_for_legacy_tunnel = record.tunneling == true and tunnel
                    and tunnel.status == "digging"
                local tunnel_managed = tunnel and tunnel.status == "open"
                    and unit.surface == locomotive.surface
                    and position_outside_safe_zone(locomotive, unit.position)

                if waiting_for_legacy_tunnel then
                    -- A leader carried over from 2.7.56 waits safely at the old
                    -- mouth while the autonomous controller completes the route.
                    record.stuck_ticks = 0
                    record.rescue_attempts = 0
                    record.last_position = { x = unit.position.x, y = unit.position.y }
                    record.last_health = tonumber(unit.health) or record.last_health
                else
                    local wrong_surface = unit.surface ~= locomotive.surface
                    local player_engaged = type(record.wave_command_role) == "string"
                        and record.wave_command_role:sub(1, 7) == "player:"
                    local military_engaged = wave._military_target_is_live(record, locomotive)
                    local too_far = not wrong_surface and not player_engaged
                        and not military_engaged and not tunnel_managed
                        and position_distance_squared(unit.position, locomotive.position)
                            > RELOCATE_DISTANCE * RELOCATE_DISTANCE

                    if wrong_surface or too_far then
                        record.rescue_attempts = (tonumber(record.rescue_attempts) or 0) + 1
                        if not relocate_record(state, record, locomotive)
                            and record.rescue_attempts >= 4 then
                            remove_active_record(state, unit_number)
                        end
                    else
                        local moved = record.last_position
                            and position_distance_squared(unit.position, record.last_position) >= 4
                        local health = tonumber(unit.health) or 0
                        local damaged = record.last_health and health < record.last_health
                        local close_to_target = position_distance_squared(
                            unit.position, locomotive.position) <= 32 * 32

                        -- A unit near the train used to be exempt from stuck
                        -- recovery. Check for a water barrier first so an islanded
                        -- attacker cannot remain harmless forever.
                        local nearby_bridge = 0
                        if close_to_target and not moved and not damaged then
                            nearby_bridge = build_water_bridge(record, locomotive)
                            if nearby_bridge > 0 then command_locomotive(record, locomotive) end
                        end

                        if moved or damaged or close_to_target then
                            record.stuck_ticks = 0
                            record.rescue_attempts = 0
                        else
                            record.stuck_ticks = (tonumber(record.stuck_ticks) or 0)
                                + SAFETY_CHECK_TICKS
                        end

                        if record.stuck_ticks >= STUCK_RETRY_TICKS
                            and not tunnel_managed and not military_engaged then
                            record.stuck_ticks = 0
                            local bridge = build_water_bridge(record, locomotive)
                            if bridge > 0 then
                                record.rescue_attempts = 0
                                command_locomotive(record, locomotive)
                            else
                                record.rescue_attempts = (tonumber(record.rescue_attempts) or 0) + 1
                                if record.rescue_attempts == 1 then
                                    command_locomotive(record, locomotive)
                                elseif not relocate_record(state, record, locomotive)
                                    and record.rescue_attempts >= 4 then
                                    remove_active_record(state, unit_number)
                                end
                            end
                        end

                        if valid(unit) then
                            record.last_position = { x = unit.position.x, y = unit.position.y }
                            record.last_health = tonumber(unit.health) or health
                        end
                    end
                end
            end
        end
    end
    wave._recover_stalled_tunnels(state, locomotive)
end

local function attackable_player_entry(player, force, surface)
    if not (player and player.valid and player.connected and player.force == force) then return nil end
    local character = player.character
    if not (valid(character) and character.surface == surface) then return nil end
    local target = valid(player.vehicle) and player.vehicle.surface == surface and player.vehicle or character
    return {
        player = player,
        target = target,
        position = character.position,
    }
end

local function player_aggro_group_key(wave_number, sector)
    return tostring(math.max(0, math.floor(tonumber(wave_number) or 0)))
        .. ":" .. tostring(math.max(0, math.floor(tonumber(sector) or 0)))
end

local function group_still_pending(state, key)
    for _, group in ipairs(state.queue or {}) do
        local regular = math.max(0, tonumber(group.biters) or 0)
            + math.max(0, tonumber(group.spitters) or 0)
        if regular > 0 and player_aggro_group_key(group.wave, group.sector) == key then return true end
    end
    for event_index = state.attack_event_cursor or 1, #(state.attack_events or {}) do
        local event = state.attack_events[event_index]
        for _, group in ipairs(event and event.groups or {}) do
            if player_aggro_group_key(group.wave, group.sector) == key then return true end
        end
    end
    return false
end

local function group_member_is_digging(state, record)
    local tunnel = record and record.tunnel_id and state.tunnels[record.tunnel_id] or nil
    return record and (record.tunnel_route_active == true
        or record.tunneling == true and tunnel and tunnel.status == "digging")
end

function wave._resume_after_military_target(state, record, locomotive)
    if not record then return false end
    record.military_target = nil
    if not valid(record.entity) then return false end

    local tunnel = record.tunnel_id and state.tunnels[record.tunnel_id] or nil
    if record.tunnel_route_active then
        if wave._command_tunnel_position(record, tunnel, true) then return true end
        record.tunnel_route_active = nil
        record.tunnel_route_index = nil
        record.tunnel_route_command_index = nil
        record.tunnel_route_cautious = nil
    end
    return command_locomotive(record, locomotive)
end

function wave._update_tunnel_route_units(state, locomotive)
    for _, record in pairs(state.units or {}) do
        if record and record.tunnel_route_active and valid(record.entity) then
            local boss_blocked = record.boss and valid(record.boss_blocker)
            local military_engaged = wave._military_target_is_live(record, locomotive)
            if record.military_target and not military_engaged then
                record.military_target = nil
            end
            if not military_engaged and not boss_blocked then
                local tunnel = record.tunnel_id and state.tunnels[record.tunnel_id] or nil
                if not wave._command_tunnel_position(record, tunnel, false) then
                    record.tunnel_route_active = nil
                    record.tunnel_route_index = nil
                    record.tunnel_route_command_index = nil
                    command_locomotive(record, locomotive)
                end
            end
        end
    end
end

local function command_group_to_player(state, group, entry)
    local role = "player:" .. tostring(entry.player.index)
    local target_unit_number = entry.target.unit_number
    for _, record in ipairs(group.members) do
        record.military_target = nil
        if valid(record.entity) and not group_member_is_digging(state, record)
            and (record.wave_command_role ~= role
                or record.wave_command_target_unit_number ~= target_unit_number) then
            command_record(record, entry.target, role, defines.distraction.none)
        end
    end
end

local function command_group_to_locomotive(state, group, locomotive)
    for _, record in ipairs(group.members) do
        local military_engaged = wave._military_target_is_live(record, locomotive)
        if record.military_target and not military_engaged then
            record.military_target = nil
        end
        if valid(record.entity) and not group_member_is_digging(state, record)
            and not military_engaged
            and record.wave_command_role ~= "locomotive" then
            command_locomotive(record, locomotive)
        end
    end
end

local function update_player_aggro(force, state, locomotive)
    local surface = locomotive.surface
    local players = {}
    for _, player in ipairs(connected_players(force)) do
        local entry = attackable_player_entry(player, force, surface)
        if entry then players[player.index] = entry end
    end

    -- A directional contingent is one Wave/sector pair. Atomic queue chunks
    -- keep deployment safe, but they remain one gameplay group for aggro.
    local groups = {}
    for _, record in pairs(state.units or {}) do
        if record then
            -- Remove the temporary per-unit leash fields written by 2.7.79.
            record.player_target_index = nil
            record.player_aggro_origin = nil
            record.player_aggro_returning = nil
            record.player_aggro_cooldown_index = nil
            record.player_aggro_cooldown_until = nil
        end
        if record and not record.boss and valid(record.entity) and record.entity.surface == surface then
            local key = player_aggro_group_key(record.wave, record.sector)
            groups[key] = groups[key] or {
                key = key,
                wave = record.wave,
                sector = record.sector,
                members = {},
            }
            groups[key].members[#groups[key].members + 1] = record
        end
    end

    -- Keep a group's first detected player locked until that player dies,
    -- disconnects or leaves the exterior surface. No chase distance or unit
    -- count limit is applied.
    local released = {}
    for key, engagement in pairs(state.player_aggro_groups or {}) do
        local group = groups[key]
        local entry = engagement and players[engagement.player_index] or nil
        if entry then
            if group then command_group_to_player(state, group, entry) end
            if not group and not group_still_pending(state, key) then
                state.player_aggro_groups[key] = nil
            end
        else
            state.player_aggro_groups[key] = nil
            released[key] = true
            if group then command_group_to_locomotive(state, group, locomotive) end
        end
    end

    -- A single member seeing a player pulls every living member of that
    -- directional group, including far-away chunks, onto the same target.
    for key, group in pairs(groups) do
        if not state.player_aggro_groups[key] and not released[key] then
            local nearest_entry = nil
            local nearest_distance = nil
            for _, record in ipairs(group.members) do
                if not group_member_is_digging(state, record) then
                    for _, entry in pairs(players) do
                        local distance = position_distance_squared(record.entity.position, entry.position)
                        if distance <= PLAYER_AGGRO_RADIUS * PLAYER_AGGRO_RADIUS
                            and (not nearest_distance or distance < nearest_distance) then
                            nearest_entry = entry
                            nearest_distance = distance
                        end
                    end
                end
            end
            if nearest_entry then
                state.player_aggro_groups[key] = { player_index = nearest_entry.player.index }
                command_group_to_player(state, group, nearest_entry)
            else
                command_group_to_locomotive(state, group, locomotive)
            end
        end
    end
end

local function refresh_commands(force, state, locomotive)
    for _, record in pairs(state.units or {}) do
        if record and valid(record.entity) and not group_member_is_digging(state, record) then
            if record.boss and valid(record.boss_blocker) then
                local blocker = record.boss_blocker
                local role = wave._boss_blocker_role(blocker)
                if record.wave_command_role ~= role
                    or record.wave_command_target_unit_number ~= blocker.unit_number then
                    command_record(record, blocker, role, defines.distraction.none)
                end
            else
                local engagement = not record.boss
                    and state.player_aggro_groups[
                        player_aggro_group_key(record.wave, record.sector)] or nil
                local player = engagement and game.get_player(engagement.player_index) or nil
                local entry = attackable_player_entry(player, force, locomotive.surface)
                if entry then
                    record.military_target = nil
                    local role = "player:" .. tostring(player.index)
                    if record.wave_command_role ~= role
                        or record.wave_command_target_unit_number ~= entry.target.unit_number then
                        command_record(record, entry.target, role, defines.distraction.none)
                    end
                elseif wave._military_target_is_live(record, locomotive) then
                    local target = record.military_target
                    local role = "military:" .. tostring(target.unit_number or target.name)
                    if record.wave_command_role ~= role
                        or record.wave_command_target_unit_number ~= target.unit_number then
                        command_record(record, target, role, defines.distraction.none)
                    end
                else
                    record.military_target = nil
                    local destination_role = record.boss and "boss-locomotive" or "locomotive"
                    if record.wave_command_role ~= destination_role
                        or record.wave_command_target_unit_number ~= locomotive.unit_number then
                        command_locomotive(record, locomotive)
                    end
                end
            end
        end
    end
end

function wave._update_military_targeting(force, state, locomotive, tick)
    local bucket_count = math.max(1,
        math.floor(tonumber(wave.military_target_scan_buckets) or 4))
    local bucket = math.floor((tonumber(tick) or 0) / TUNNEL_UPDATE_TICKS) % bucket_count

    for unit_number, record in pairs(state.units or {}) do
        local unit = record and record.entity
        local unit_bucket = math.floor(tonumber(unit_number)
            or tonumber(unit and unit.unit_number) or 0) % bucket_count
        if record and not record.boss and valid(unit)
            and unit.surface == locomotive.surface and unit_bucket == bucket then
            local tunnel = record.tunnel_id and state.tunnels[record.tunnel_id] or nil
            local actually_digging = record.tunneling == true
                and tunnel and tunnel.status == "digging"
            local engagement = state.player_aggro_groups[
                player_aggro_group_key(record.wave, record.sector)]
            local player = engagement and game.get_player(engagement.player_index) or nil
            local player_entry = attackable_player_entry(player, force, locomotive.surface)

            if actually_digging or player_entry then
                record.military_target = nil
            else
                local vision = wave.military_target_fallback_vision
                pcall(function()
                    vision = tonumber(unit.prototype.vision_distance) or vision
                end)
                vision = math.max(1,
                    tonumber(vision) or wave.military_target_fallback_vision)

                local target = nil
                pcall(function()
                    target = unit.surface.find_nearest_enemy {
                        position = unit.position,
                        max_distance = vision,
                        force = unit.force,
                    }
                end)
                if target == locomotive then target = nil end

                if valid(target) then
                    local previous_target = record.military_target
                    local role = "military:" .. tostring(target.unit_number or target.name)
                    if previous_target ~= target or record.wave_command_role ~= role
                        or record.wave_command_target_unit_number ~= target.unit_number then
                        if command_record(record, target, role, defines.distraction.none) then
                            record.military_target = target
                        else
                            record.military_target = nil
                            record.wave_command_role = nil
                            record.wave_command_target_unit_number = nil
                        end
                    else
                        record.military_target = target
                    end
                elseif record.military_target
                    or type(record.wave_command_role) == "string"
                        and record.wave_command_role:sub(1, 9) == "military:" then
                    wave._resume_after_military_target(state, record, locomotive)
                end
            end
        end
    end
end

local function update_force(force, state)
    if #connected_players(force) == 0 then return end
    if state.paused or wave._teams.defeat.is_active(force) then return end

    local locomotive = main_locomotive(force)
    if not valid(locomotive) then
        destroy_safe_zone_render(state)
        if not state.waiting_for_locomotive then
            announce(force, { "the-cave-train-wave.locomotive-wait" }, "utility/console_message")
            state.waiting_for_locomotive = true
        end
        return
    end
    if not wave._teams.state.is_world_running(locomotive.surface) then return end
    state.waiting_for_locomotive = false
    update_safe_zone_render(force, state, locomotive)
    if not wave._ensure_train_generated_area(state, force, locomotive) then return end
    wave._ensure_shelter_tunnel_distance(state, force, locomotive)
    wave._migrate_train_cache_routes(state, locomotive)
    wave._migrate_persistent_tunnels(state, locomotive)
    wave._update_attack_region(state, force, locomotive)
    wave._ensure_eight_front_tunnels(state, force, locomotive, false)

    update_scheduler(force, state, locomotive)
    wave._update_boss_control(state, locomotive)

    state.spawn_wait_ticks = math.max(0, state.spawn_wait_ticks - SECOND)
    if state.spawn_wait_ticks <= 0 and queue_counts(state).total > 0 then
        local spawned, retry_next_group = spawn_batch(force, state, locomotive)
        state.spawn_wait_ticks = (spawned > 0 or retry_next_group)
            and BATCH_INTERVAL_TICKS or ROUTE_RETRY_TICKS
    end

    update_player_aggro(force, state, locomotive)

    state.safety_wait_ticks = math.max(0, state.safety_wait_ticks - SECOND)
    if state.safety_wait_ticks <= 0 then
        update_unit_safety(state, locomotive)
        state.safety_wait_ticks = SAFETY_CHECK_TICKS
    end

    state.command_wait_ticks = math.max(0, state.command_wait_ticks - SECOND)
    if state.command_wait_ticks <= 0 then
        refresh_commands(force, state, locomotive)
        state.command_wait_ticks = COMMAND_REFRESH_TICKS
    end
end

local function update_force_tunnels(force, state)
    if #connected_players(force) == 0 then return end
    if state.paused or wave._teams.defeat.is_active(force) then return end
    local locomotive = main_locomotive(force)
    if valid(locomotive) and wave._teams.state.is_world_running(locomotive.surface)
        and wave._ensure_train_generated_area(state, force, locomotive) then
        wave._ensure_shelter_tunnel_distance(state, force, locomotive)
        wave._migrate_train_cache_routes(state, locomotive)
        wave._migrate_persistent_tunnels(state, locomotive)
        wave._migrate_attack_regions(state, locomotive)
        wave._repair_mouth_only_tunnels(state, locomotive)
        process_tunnels(force, state, locomotive)
        -- Tunnel digging already runs four times per second.  Hand route
        -- destinations off on that same cadence so the next order is active
        -- well before the current go-to command can finish and idle the unit.
        wave._update_tunnel_route_units(state, locomotive)
        wave._update_military_targeting(force, state, locomotive, game.tick)
    end
end

local function add_gui_label(frame, name)
    local label = frame.add { type = "label", name = name, caption = "" }
    label.style.left_padding = 6
    label.style.right_padding = 6
    return label
end

local function apply_gui_dimensions(frame)
    if not (frame and frame.valid) then return end
    local collapsed = (frame.tags or {}).collapsed == true
    frame.style.minimal_width = collapsed and 0 or GUI_STYLE.expanded_min_width
    frame.style.minimal_height = collapsed and 0 or GUI_STYLE.expanded_min_height

    local header_flow = frame[GUI_HEADER_FLOW]
    if not (header_flow and header_flow.valid) then return end
    header_flow.style.vertically_stretchable = not collapsed
    header_flow.style.vertical_align = "center"

    local toggle = header_flow[GUI_TOGGLE]
    if toggle and toggle.valid then
        toggle.style.width = GUI_STYLE.toggle_size
        toggle.style.height = GUI_STYLE.toggle_size
    end
end

local function ensure_gui(player)
    if not (player and player.valid and player.gui and player.gui.top) then return nil end
    local shelter_mode = wave._shelter_wave_mode_enabled()
    local frame = player.gui.top[GUI_NAME]
    if frame and frame.valid and (not frame[GUI_HEADER_FLOW] or not frame[GUI_TUNNEL]) then
        frame.destroy()
        frame = nil
    end
    if frame and frame.valid then
        local tags = frame.tags or {}
        if tags.layout_version ~= GUI_STYLE.layout_version then
            tags.layout_version = GUI_STYLE.layout_version
            tags.collapsed = true
            frame.tags = tags
        end
        frame.tooltip = {
            shelter_mode and "the-cave-train-wave.gui-shelter-tooltip"
                or "the-cave-train-wave.gui-tooltip",
        }
        apply_gui_dimensions(frame)
        return frame
    end

    frame = player.gui.top.add {
        type = "frame",
        name = GUI_NAME,
        direction = "vertical",
        tooltip = {
            shelter_mode and "the-cave-train-wave.gui-shelter-tooltip"
                or "the-cave-train-wave.gui-tooltip",
        },
    }
    frame.tags = { collapsed = true, layout_version = GUI_STYLE.layout_version }

    local header_flow = frame.add { type = "flow", name = GUI_HEADER_FLOW, direction = "horizontal" }
    local toggle = header_flow.add { type = "button", name = GUI_TOGGLE, caption = "+" }
    local header = header_flow.add { type = "label", name = GUI_HEADER, caption = "" }
    header.style.font = "default-bold"
    header.style.left_padding = 4

    add_gui_label(frame, GUI_TIMER)
    add_gui_label(frame, GUI_SCALE)
    add_gui_label(frame, GUI_INCOMING)
    add_gui_label(frame, GUI_ACTIVE)
    add_gui_label(frame, GUI_QUEUE)
    add_gui_label(frame, GUI_TUNNEL)
    add_gui_label(frame, GUI_BOSS)
    apply_gui_dimensions(frame)
    return frame
end

local function set_detail_visibility(frame, visible)
    for _, name in ipairs({ GUI_TIMER, GUI_SCALE, GUI_INCOMING, GUI_ACTIVE, GUI_QUEUE, GUI_TUNNEL, GUI_BOSS }) do
        if frame[name] and frame[name].valid then frame[name].visible = visible end
    end
    local toggle = frame[GUI_HEADER_FLOW] and frame[GUI_HEADER_FLOW][GUI_TOGGLE]
    if toggle and toggle.valid then toggle.caption = visible and "-" or "+" end
    apply_gui_dimensions(frame)
end

local function active_boss_summary(state)
    local bosses = {}
    for _, record in pairs(state.units or {}) do
        if record and record.boss and valid(record.entity) then
            local max_health = math.max(1, tonumber(record.max_health) or 1)
            local percent = math.max(0, math.min(100, math.floor((tonumber(record.entity.health) or 0) * 100 / max_health + 0.5)))
            bosses[#bosses + 1] = tostring(percent) .. "%"
        end
    end
    table.sort(bosses)
    return table.concat(bosses, " | ")
end

local function gui_color(state, next_preview, active)
    if state.waiting_for_locomotive then return { r = 0.65, g = 0.65, b = 0.65 } end
    if state.phase == "preparation" then return { r = 0.35, g = 1, b = 0.35 } end
    if state.phase == "break" then return { r = 0.30, g = 0.85, b = 1 } end
    if state.phase == "boss" or active.bosses > 0 then return { r = 0.82, g = 0.45, b = 1 } end
    if state.remaining_ticks <= 10 * SECOND then return { r = 1, g = 0.25, b = 0.20 } end
    if state.remaining_ticks <= 60 * SECOND then return { r = 1, g = 0.62, b = 0.15 } end
    return { r = 1, g = 0.88, b = 0.25 }
end

local function update_player_gui(player)
    local state = force_state(player.force)
    local frame = ensure_gui(player)
    if not (state and frame and frame.valid) then return end

    local locomotive = main_locomotive(player.force)
    local surface = valid(locomotive) and locomotive.surface or nil
    local active = active_counts(state, true)
    local queued = queue_counts(state)
    local active_cap = wave._current_active_cap(state)
    local tunnels = tunnel_counts(state)
    local next_number = state.wave + 1
    local preview = wave_numbers(player.force, next_number, surface, state.test_player_count_override)
    local header = frame[GUI_HEADER_FLOW][GUI_HEADER]
    local tags = frame.tags or {}
    local collapsed = tags.collapsed == true
    local shelter_mode = wave._shelter_wave_mode_enabled()

    if state.waiting_for_locomotive then
        header.caption = {
            shelter_mode and "the-cave-train-wave.gui-shelter-header-paused"
                or "the-cave-train-wave.gui-header-paused",
            next_number,
        }
    elseif collapsed and state.phase == "boss" then
        header.caption = {
            shelter_mode and "the-cave-train-wave.gui-shelter-header-compact-boss"
                or "the-cave-train-wave.gui-header-compact-boss",
            state.wave,
            active.total,
            active_cap,
        }
    elseif collapsed then
        header.caption = {
            shelter_mode
                and (state.phase == "break"
                    and "the-cave-train-wave.gui-shelter-header-compact-break"
                    or "the-cave-train-wave.gui-shelter-header-compact")
                or (state.phase == "break"
                    and "the-cave-train-wave.gui-header-compact-break"
                    or "the-cave-train-wave.gui-header-compact"),
            state.wave,
            next_number,
            format_time(state.remaining_ticks),
            active.total,
            active_cap,
        }
    elseif state.phase == "preparation" then
        header.caption = {
            shelter_mode and "the-cave-train-wave.gui-shelter-header-preparation"
                or "the-cave-train-wave.gui-header-preparation",
        }
    elseif state.phase == "break" then
        header.caption = {
            shelter_mode and "the-cave-train-wave.gui-shelter-header-break"
                or "the-cave-train-wave.gui-header-break",
            state.wave,
        }
    elseif state.phase == "boss" then
        header.caption = {
            shelter_mode and "the-cave-train-wave.gui-shelter-header-boss"
                or "the-cave-train-wave.gui-header-boss",
            state.wave,
        }
    else
        header.caption = {
            shelter_mode and "the-cave-train-wave.gui-shelter-header-wave"
                or "the-cave-train-wave.gui-header-wave",
            state.wave,
        }
    end
    header.style.font_color = gui_color(state, preview, active)
    set_detail_visibility(frame, not collapsed)
    if collapsed then return end

    if state.phase == "preparation" then
        frame[GUI_TIMER].caption = {
            "the-cave-train-wave.gui-preparation-timer",
            format_time(state.remaining_ticks),
        }
    elseif state.phase == "break" then
        frame[GUI_TIMER].caption = {
            "the-cave-train-wave.gui-break-timer",
            state.wave,
            next_number,
            format_time(state.remaining_ticks),
        }
    elseif state.phase == "boss" then
        frame[GUI_TIMER].caption = { "the-cave-train-wave.gui-boss-timer-hidden" }
    else
        frame[GUI_TIMER].caption = {
            "the-cave-train-wave.gui-next-timer",
            next_number,
            format_time(state.remaining_ticks),
        }
    end
    frame[GUI_SCALE].caption = {
        "the-cave-train-wave.gui-scale",
        preview.base,
        preview.players,
        preview.fronts,
    }
    frame[GUI_INCOMING].caption = {
        "the-cave-train-wave.gui-incoming",
        preview.total,
        preview.biters,
        preview.spitters,
        preview.bosses,
    }
    frame[GUI_ACTIVE].caption = {
        "the-cave-train-wave.gui-active",
        active.total,
        active_cap,
        active.biters,
        active.spitters,
        active.bosses,
    }
    frame[GUI_ACTIVE].style.font_color = active.total > 0
        and { r = 1, g = 0.35, b = 0.25 } or { r = 0.55, g = 1, b = 0.55 }

    local queue_key = state.route_blocked and "the-cave-train-wave.gui-queue-blocked"
        or "the-cave-train-wave.gui-queue"
    frame[GUI_QUEUE].caption = {
        queue_key,
        queued.total,
        queued.biters,
        queued.spitters,
        queued.bosses,
    }
    frame[GUI_QUEUE].style.font_color = queued.total > 0
        and { r = 1, g = 0.65, b = 0.20 } or { r = 0.70, g = 0.70, b = 0.70 }

    if tunnels.active > 0 then
        frame[GUI_TUNNEL].caption = {
            "the-cave-train-wave.gui-tunneling",
            tunnels.active,
            tunnels.waiting,
        }
        frame[GUI_TUNNEL].style.font_color = { r = 1, g = 0.48, b = 0.16 }
    else
        frame[GUI_TUNNEL].caption = { "the-cave-train-wave.gui-tunneling-none" }
        frame[GUI_TUNNEL].style.font_color = { r = 0.70, g = 0.70, b = 0.70 }
    end

    local boss_summary = active_boss_summary(state)
    if boss_summary ~= "" then
        frame[GUI_BOSS].caption = { "the-cave-train-wave.gui-active-bosses", boss_summary }
    elseif state.phase == "boss" then
        frame[GUI_BOSS].caption = { "the-cave-train-wave.gui-boss-hidden" }
    else
        frame[GUI_BOSS].caption = { "the-cave-train-wave.gui-next-boss-hidden" }
    end
    frame[GUI_BOSS].style.font_color = { r = 0.82, g = 0.45, b = 1 }

    if not state.informed_players[player.index] then
        state.informed_players[player.index] = true
        if state.phase == "boss" then
            player.print({ "the-cave-train-wave.join-status-boss", state.wave, active.total, active_cap })
        else
            player.print({
                "the-cave-train-wave.join-status",
                state.wave,
                next_number,
                format_time(state.remaining_ticks),
                active.total,
                active_cap,
            })
        end
    end
end

local function update_guis()
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid and player.force and player.force.valid then update_player_gui(player) end
    end
end

local function destroy_all_guis()
    if not game then return end
    for _, player in pairs(game.players or {}) do
        if player and player.valid and player.gui and player.gui.top then
            local frame = player.gui.top[GUI_NAME]
            if frame and frame.valid then frame.destroy() end
        end
    end
end

function wave.on_gui_click(event)
    local element = event and event.element
    if not (element and element.valid and element.name == GUI_TOGGLE) then return false end
    local player = game.get_player(event.player_index)
    if not (player and player.valid and player.gui and player.gui.top) then return true end
    local frame = player.gui.top[GUI_NAME]
    if not (frame and frame.valid) then return true end
    local tags = frame.tags or {}
    tags.collapsed = not (tags.collapsed == true)
    frame.tags = tags
    update_player_gui(player)
    return true
end

function wave.on_entity_damaged(event)
    if not normal_train_wave_mode_enabled() then return false end
    local entity = event and event.entity
    local cause = event and event.cause
    if entity and entity.valid and cause and cause.valid and cause.unit_number
        and (entity.name == "diggy-rock" or entity.name == "diggy-rubble")
        and type(cause.name) == "string" and cause.name:sub(1, #UNIT_PREFIX) == UNIT_PREFIX then
        for _, state in pairs(root_state().forces or {}) do
            local record = state.units and state.units[cause.unit_number]
            local tunnel = record and record.tunnel_id and state.tunnels[record.tunnel_id] or nil
            if record and record.tunnel_route_active and tunnel
                and tunnel.status == "open" and type(tunnel.route) == "table"
                and #tunnel.route > 1 then
                -- A Wave attacker crossing its own carved corridor must never
                -- widen that corridor by attacking the natural Cave cover.
                local damage = math.max(0, tonumber(event.final_damage_amount)
                    or tonumber(event.original_damage_amount) or 0)
                local final_health = tonumber(event.final_health)
                    or tonumber(entity.health) or 0
                if damage > 0 then
                    -- final_health + final_damage_amount is the exact health
                    -- immediately before this hit. Avoid max_health here:
                    -- LuaEntityPrototype exposes no such key in Factorio 2.0.
                    pcall(function()
                        entity.health = math.max(1, final_health + damage)
                    end)
                end

                -- The first corner collision switches only this unit to closer
                -- six-step centreline waypoints.  The route controller hands
                -- them off early, so cautious cornering no longer degrades to
                -- one-tile walk-stop-walk orders. Reissue at most twice per
                -- second; damage restoration remains event-driven and exact.
                record.tunnel_route_cautious = true
                if game.tick >= math.max(0, tonumber(record.tunnel_rock_redirect_tick) or 0) then
                    local nearest_index = 1
                    local nearest_distance = nil
                    for index, position in ipairs(tunnel.route) do
                        local distance = position_distance_squared(cause.position, position)
                        if not nearest_distance or distance < nearest_distance then
                            nearest_index = index
                            nearest_distance = distance
                        end
                    end
                    record.tunnel_route_index = math.min(
                        #tunnel.route,
                        nearest_index + wave.tunnel_route_cautious_lookahead)
                    record.tunnel_route_command_index = nil
                    record.tunnel_rock_redirect_tick = game.tick + wave.tunnel_rock_redirect_cooldown
                    wave._command_tunnel_position(record, tunnel, true)
                end
                return true
            end
        end
    end
    if entity and entity.valid and cause and cause.valid
        and type(cause.name) == "string" and cause.name:sub(1, #UNIT_PREFIX) == UNIT_PREFIX
        and (entity.type == "locomotive" or entity.type == "cargo-wagon"
            or entity.type == "fluid-wagon" or entity.type == "artillery-wagon") then
        local target = main_locomotive(entity.force)
        if not (valid(target) and entity.unit_number == target.unit_number) then
            local damage = math.max(0, tonumber(event.final_damage_amount)
                or tonumber(event.original_damage_amount) or 0)
            local final_health = tonumber(event.final_health)
                or tonumber(entity.health) or 0
            if damage > 0 then
                pcall(function()
                    entity.health = math.max(1, final_health + damage)
                end)
            end
            return true
        end
    end
    if not (entity and entity.valid and entity.unit_number) then return false end
    if type(entity.name) ~= "string" or entity.name:sub(1, #UNIT_PREFIX) ~= UNIT_PREFIX then return false end
    for _, state in pairs(root_state().forces or {}) do
        local record = state.units and state.units[entity.unit_number]
        if record then
            update_boss_healthbar(record)
            if record.boss then wave._update_boss_snapshot(state, record) end
            -- The hit was observed for Wave/Boss bookkeeping, but it was not
            -- cancelled. Returning true here tells control.lua that the damage
            -- was restored and suppresses the integrated Damage Indicator for
            -- every registered Wave attacker, including ordinary biters.
            return false
        end
    end
    return false
end

function wave.on_entity_died(event)
    if not normal_train_wave_mode_enabled() then return false end
    local entity = event and event.entity
    if not (entity and entity.valid and entity.unit_number) then return false end
    if type(entity.name) ~= "string" or entity.name:sub(1, #UNIT_PREFIX) ~= UNIT_PREFIX then return false end
    for force_index, state in pairs(root_state().forces or {}) do
        local record = state.units and state.units[entity.unit_number]
        if record then
            local boss_finished = mark_boss_finished(state, record)
            destroy_healthbar(record)
            state.units[entity.unit_number] = nil
            if boss_finished and state.boss_killed >= state.boss_total then
                local force = game.forces[force_index]
                if force and force.valid then enter_boss_break(force, state) end
            end
            return true
        end
    end
    return false
end

function wave.on_init(enabled)
    enabled = enabled and normal_train_wave_mode_enabled()
    local old = storage[STORAGE_NAME]
    if old and old.forces then
        for _, state in pairs(old.forces) do
            destroy_wave_units(state)
            destroy_safe_zone_render(state)
        end
    end
    storage[STORAGE_NAME] = { version = STORAGE_VERSION, forces = {} }
    if not enabled then destroy_all_guis() end
end

function wave.on_shelter_init(enabled)
    wave.on_init(enabled == true)
end

function wave.on_shelter_configuration_changed(enabled)
    wave.on_configuration_changed(enabled == true)
end

function wave.clear_force(force_index)
    local root = root_state()
    local state = root.forces[force_index]
    if state then
        destroy_wave_units(state)
        destroy_safe_zone_render(state)
        root.forces[force_index] = nil
    end
    for _, player in pairs(game.players) do
        if player.force.index == force_index then
            local frame = player.gui.top[GUI_NAME]
            if frame and frame.valid then frame.destroy() end
        end
    end
end

function wave.set_force_paused(force, paused)
    local state = force_state(force)
    if state then state.paused = paused == true end
end

function wave.on_shelter_distance_researched(force)
    if not (force and force.valid and wave._shelter_wave_mode_enabled()) then return end
    local state = force_state(force)
    state.shelter_target_attack_chunks = wave._shelter_attack_chunks(force)
    state.train_generation_radius_chunks = nil
    local shelter = main_locomotive(force)
    if valid(shelter) then wave._ensure_shelter_tunnel_distance(state, force, shelter) end
end

local function migrate_milestone_break(state)
    if not state or state.phase == "preparation" then return end
    local completed = math.max(0, math.floor(tonumber(state.wave) or 0))
    local remaining = math.max(0, tonumber(state.remaining_ticks) or 0)
    if completed > 0 and completed % 50 == 0 and state.phase ~= "break"
        and remaining <= LEGACY_WAVE_INTERVAL_TICKS then
        -- Preserve elapsed time since the milestone Wave began: an old
        -- five-minute countdown becomes the corresponding point inside the
        -- new thirty-minute break rather than restarting either timer.
        state.phase = "break"
        state.remaining_ticks = math.min(BREAK_INTERVAL_TICKS,
            remaining + BREAK_INTERVAL_TICKS - LEGACY_WAVE_INTERVAL_TICKS)
        state.warnings = {}
    end
end

local function migrate_three_minute_countdown(state)
    if not state or state.phase ~= "countdown" then return end
    local remaining = math.max(0, tonumber(state.remaining_ticks) or LEGACY_WAVE_INTERVAL_TICKS)
    local elapsed = math.max(0,
        LEGACY_WAVE_INTERVAL_TICKS - math.min(remaining, LEGACY_WAVE_INTERVAL_TICKS))
    state.remaining_ticks = math.max(0, wave_interval_ticks((state.wave or 0) + 1) - elapsed)
    state.warnings = {}
end

function wave.on_configuration_changed(enabled)
    enabled = (enabled or wave._shelter_wave_mode_enabled()) and normal_train_wave_mode_enabled()
    local old = storage[STORAGE_NAME]
    if old and old.version == 2 and old.forces then
        -- 2.7.54 already owns exact live units, queues and timers. Add the
        -- autonomous-tunnel fields without restarting preparation or deleting
        -- an in-progress Wave.
        old.version = STORAGE_VERSION
        for _, state in pairs(old.forces) do
            destroy_safe_zone_render(state)
            state.tunnels = {}
            state.next_tunnel_id = 1
            state.tunnel_announced_waves = {}
            state.tunnel_breached_waves = {}
            migrate_milestone_break(state)
            migrate_three_minute_countdown(state)
        end
    elseif old and old.version == 3 and old.forces then
        -- Preserve every 2.7.56 Wave, queue and partially carved tunnel. The
        -- former leader may wait at the existing mouth, but terrain progress
        -- no longer stores or depends on that unit.
        old.version = STORAGE_VERSION
        for _, state in pairs(old.forces) do
            destroy_safe_zone_render(state)
            state.tunnels = state.tunnels or {}
            for _, tunnel in pairs(state.tunnels) do
                if tunnel and tunnel.status == "digging" then
                    tunnel.step_wait_ticks = TUNNEL_STEP_TICKS
                    tunnel.leader_unit_number = nil
                end
            end
            migrate_milestone_break(state)
            migrate_three_minute_countdown(state)
        end
    elseif old and old.version == 4 and old.forces then
        -- 2.7.57 already owns autonomous tunnels. Preserve all live units,
        -- queues, tunnels and timers while enabling the locked stable balance.
        old.version = STORAGE_VERSION
        for _, state in pairs(old.forces) do
            destroy_safe_zone_render(state)
            migrate_milestone_break(state)
            migrate_three_minute_countdown(state)
        end
    elseif old and old.version == 5 and old.forces then
        -- Preserve the complete stable Wave schedule, active attackers, queue,
        -- timer and autonomous tunnel progress. Existing tunnels that do not
        -- yet own a safe outside deployment mouth are retired lazily and their
        -- queued attackers are assigned a new compliant route.
        old.version = STORAGE_VERSION
        for _, state in pairs(old.forces) do
            destroy_safe_zone_render(state)
            state.safe_zone_render = nil
            migrate_three_minute_countdown(state)
        end
    elseif old and old.version == 6 and old.forces then
        -- 2.7.71 already owns the complete live Wave state. Shorten only a
        -- normal five-minute countdown by preserving how much time has already
        -- elapsed; preparation, milestone breaks, units, queues and tunnels are
        -- left untouched.
        old.version = STORAGE_VERSION
        for _, state in pairs(old.forces) do
            migrate_three_minute_countdown(state)
        end
    elseif old and old.version == 7 and old.forces then
        -- Preserve the complete 2.7.72 Wave already in progress. Its live
        -- units, queue, tunnels and current timer finish under their saved
        -- state; the new table-driven scheduler takes ownership at the next
        -- Wave boundary.
        old.version = STORAGE_VERSION
        for _, state in pairs(old.forces) do
            state.attack_events = {}
            state.attack_event_cursor = 1
            state.wave_elapsed_ticks = 0
            state.wave_duration_ticks = 0
            state.boss_wave_active = false
            state.boss_total = 0
            state.boss_spawned = 0
            state.boss_killed = 0
            state.boss_pending = false
            state.boss_targets = {}
            state.boss_sectors = {}
            state.boss_next_delay_ticks = 0
        end
    elseif not old or old.version ~= STORAGE_VERSION then
        if old and old.forces then
            for _, state in pairs(old.forces) do
                destroy_wave_units(state)
                destroy_safe_zone_render(state)
            end
        end
        storage[STORAGE_NAME] = { version = STORAGE_VERSION, forces = {} }
    end

    if not enabled then
        local root = root_state()
        for _, state in pairs(root.forces or {}) do
            destroy_wave_units(state)
            destroy_safe_zone_render(state)
        end
        destroy_all_guis()
    end
end

function wave.on_tick(event)
    if not (event and event.tick) then return end
    local tunnel_update = event.tick % TUNNEL_UPDATE_TICKS == 0
    local second_update = event.tick % SECOND == 0
    if not tunnel_update and not second_update then return end
    if not normal_train_wave_mode_enabled() then return end
    local forces_seen = {}
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid and player.force and player.force.valid then
            if wave._teams.state.force_is_active(player.force) then forces_seen[player.force.index] = player.force end
        end
    end
    for _, force in pairs(forces_seen) do
        local state = force_state(force)
        if tunnel_update then update_force_tunnels(force, state) end
        if second_update then update_force(force, state) end
    end
    if second_update then update_guis() end
end

function wave._parse_positive_integer(value, maximum)
    local number = tonumber(value)
    if not number or number ~= math.floor(number) or number < 1 or number > maximum then return nil end
    return number
end

function wave._print_preview(player, number, player_override)
    local locomotive = main_locomotive(player.force)
    local surface = valid(locomotive) and locomotive.surface or nil
    local plan = wave_numbers(player.force, number, surface, player_override)
    player.print({
        "the-cave-train-wave.test-preview",
        plan.wave,
        plan.players,
        plan.total,
        plan.biters,
        plan.spitters,
        plan.bosses,
        plan.boss_level,
        plan.fronts,
    })
end

function wave._command_force_state(player, tokens)
    local action = string.lower(tokens[1] or "status")
    local state = force_state(player.force)

    if action == "status" or action == "" then
        local active = active_counts(state, true)
        local queued = queue_counts(state)
        local tunnels = tunnel_counts(state)
        player.print({
            "the-cave-train-wave.test-status",
            tostring(state.phase),
            state.wave,
            format_time(state.remaining_ticks),
            active.total,
            wave._current_active_cap(state),
            queued.total,
            tunnels.active,
        })
        return
    end

    if action == "preview" then
        local number = wave._parse_positive_integer(tokens[2], MAX_TEST_WAVE)
        local player_override = tokens[3] and wave._parse_positive_integer(tokens[3], 1000) or nil
        if not number or (tokens[3] and not player_override) then
            player.print({ "the-cave-train-wave.command-help" })
            return
        end
        wave._print_preview(player, number, player_override)
        return
    end

    if action == "wave" or action == "start" or action == "boss" then
        local number = nil
        if action == "wave" then
            number = wave._parse_positive_integer(tokens[2], MAX_TEST_WAVE)
        elseif action == "boss" then
            number = next_boss_wave(state.wave)
        else
            number = state.wave + 1
        end
        local player_override = action == "wave" and tokens[3]
            and wave._parse_positive_integer(tokens[3], 1000) or nil
        if not number or (action == "wave" and tokens[3] and not player_override) then
            player.print({ "the-cave-train-wave.command-help" })
            return
        end

        destroy_wave_units(state, true)
        state.phase = "countdown"
        state.wave = number - 1
        state.remaining_ticks = 10 * SECOND
        state.warnings = {}
        state.waiting_for_locomotive = false
        state.route_blocked = false
        state.test_player_count_override = player_override
        state.debug_player_index = player.index
        player.print({
            "the-cave-train-wave.test-scheduled",
            number,
            player_override or #connected_players(player.force),
        })
        wave._print_preview(player, number, player_override)
        return
    end

    if action == "clear" then
        destroy_wave_units(state, true)
        player.print({ "the-cave-train-wave.test-cleared" })
        return
    end

    if action == "reset" then
        destroy_wave_units(state)
        destroy_safe_zone_render(state)
        root_state().forces[player.force.index] = new_force_state()
        player.print({ "the-cave-train-wave.test-reset" })
        return
    end

    player.print({ "the-cave-train-wave.command-help" })
end

function wave.register_commands()
    local function test_command(event)
        local player = event.player_index and game.get_player(event.player_index) or nil
        if not (player and player.valid) then return end
        if not player.admin then
            player.print({ "the-cave-train-wave.admin-only" })
            return
        end
        if not normal_train_wave_mode_enabled() then
            player.print({ "the-cave-train-wave.inactive" })
            return
        end

        local tokens = {}
        for token in string.gmatch(event.parameter or "status", "%S+") do tokens[#tokens + 1] = token end
        wave._command_force_state(player, tokens)
    end
    commands.add_command("the-cave-train-wave-test", { "the-cave-train-wave.command-help" }, test_command)
    commands.add_command("the-cave-shelter-wave-test", { "the-cave-shelter.wave-command-help" }, test_command)
end

return wave
