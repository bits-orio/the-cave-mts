local settings = require("scripts.game_settings").proxy(settings)

-- Player-centred darkness threat system, adapted from the Cave Miner scenario.
-- The reference point is the player, not hidden map points: a powered lamp
-- near the player resets the threat. Cave interiors are dangerous from entry;
-- other surfaces retain their spawn safe zone.
local darkness = {}
local mobile_factory_resources = require("scripts.mobile_factory_resources")
local cave_evolution = require("scripts.cave_evolution")
local bob_enemies = require("scripts.bob_enemies")
local cave_worlds = require("scripts.cave_worlds")

local CHECK_INTERVAL = 240          -- 4 seconds
local GRACE_TICKS = 30 * 60         -- 30 seconds
local SMALL_LAMP_RANGE = 12         -- Cave Miner uses a 24x24 search box
local LAMP_POST_RANGE = 30          -- Large integrated Lamp Post protection range
local SAFE_CHUNK_RADIUS = 2         -- centre chunk +/- 2 = 5x5 chunks total
local MAX_WAVE_SIZE = 20            -- safety cap for a single player wave
local TRAIN_INTERIOR_SURFACE_PREFIX = "the-cave-train-interior-"
local SHELTER_INTERIOR_SURFACE_PREFIX = "the-cave-shelter-interior-"
local FORTIFIED_SURFACE_PREFIX = "the-cave-fortified-vault-"
local LOST_CITY_SURFACE_PREFIX = "the-cave-lost-city-"
local CAVE_SURFACE_PREFIXES = {
    "the-cave-mineral-cave-", "the-cave-uranium-cave-",
    FORTIFIED_SURFACE_PREFIX, LOST_CITY_SURFACE_PREFIX,
}

local function is_cave_surface(surface)
    if not (surface and surface.valid) then return false end
    for _, prefix in ipairs(CAVE_SURFACE_PREFIXES) do
        if surface.name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function supported_surface(surface)
    if not (surface and surface.valid) then return false end
    if cave_worlds.is_cave_world(surface) then
        return not cave_worlds.is_template(surface)
    end
    return is_cave_surface(surface) or surface.planet ~= nil
end

local FACTORISSIMO_INTERFACE = "factorissimo"
local FACTORISSIMO_SURFACE_MARKERS = {
    "factory-floor",
    "factory floor",
    "factorissimo",
}

local function enabled()
    local setting = settings.startup["the-cave-darkness-infestation"]
    return setting and setting.value == "enabled"
end

local function root()
    storage.the_cave_darkness = storage.the_cave_darkness or { players = {} }
    storage.the_cave_darkness.players = storage.the_cave_darkness.players or {}
    return storage.the_cave_darkness
end

local function reset_state(state)
    state.unlit_since = nil
    state.last_spawn_tick = nil
    state.threat = 0
end

local function chunk_coordinate(value)
    return math.floor(value / 32)
end

local function physical_context(player)
    local character = player.character
    if not (character and character.valid) then return nil, nil, nil end

    local surface = character.surface
    if not (surface and surface.valid) then return nil, nil, nil end

    return character, surface, character.position
end

local function in_safe_zone(player, surface, position)
    local spawn = player.force.get_spawn_position(surface)
    local px = chunk_coordinate(position.x)
    local py = chunk_coordinate(position.y)
    local sx = chunk_coordinate(spawn.x)
    local sy = chunk_coordinate(spawn.y)
    return math.abs(px - sx) <= SAFE_CHUNK_RADIUS
       and math.abs(py - sy) <= SAFE_CHUNK_RADIUS
end

-- Train interiors are private scripted surfaces and must always be safe.
-- The exterior locomotive position is intentionally irrelevant: once the
-- player's physical character is on a Train Interior surface, the Darkness
-- Infestation warning, grace timer, and enemy spawning are all suspended.
local function is_train_interior(surface)
    return surface
       and surface.valid
       and type(surface.name) == "string"
       and surface.name:sub(1, #TRAIN_INTERIOR_SURFACE_PREFIX) == TRAIN_INTERIOR_SURFACE_PREFIX
end

local function is_shelter_interior(surface)
    return surface
       and surface.valid
       and type(surface.name) == "string"
       and surface.name:sub(1, #SHELTER_INTERIOR_SURFACE_PREFIX) == SHELTER_INTERIOR_SURFACE_PREFIX
end

local function is_fortified_vault_surface(surface)
    return surface
       and surface.valid
       and type(surface.name) == "string"
       and surface.name:sub(1, #FORTIFIED_SURFACE_PREFIX) == FORTIFIED_SURFACE_PREFIX
end

local function is_lost_city_surface(surface)
    return surface
       and surface.valid
       and type(surface.name) == "string"
       and surface.name:sub(1, #LOST_CITY_SURFACE_PREFIX) == LOST_CITY_SURFACE_PREFIX
end

-- A powered vanilla Small Lamp protects within 12 tiles. The integrated
-- Lamp Post is deliberately stronger and protects within 30 tiles. Both use
-- the same power and circuit-condition checks, and neither prototype's visual
-- light, recipe, power network, or circuit behaviour is modified here.
local function has_powered_lamp_named(player, surface, position, name, range)
    local lamps = surface.find_entities_filtered {
        area = {
            { position.x - range, position.y - range },
            { position.x + range, position.y + range },
        },
        name = name,
        force = player.force,
    }

    for _, lamp in pairs(lamps) do
        -- A lamp only needs to be receiving some power to protect the player.
        -- Do not use a fixed Joule threshold: lamp sizes and supply levels
        -- differ, so a fixed cutoff becomes unreliable during brownouts.
        -- A completely unpowered lamp
        -- still has zero energy and starts the normal 30-second grace period.
        if lamp.valid and lamp.energy > 0 then
            local behavior = lamp.get_or_create_control_behavior()
            if not behavior or not behavior.disabled then
                return true
            end
        end
    end
    return false
end

local function has_powered_lamp(player, surface, position)
    if has_powered_lamp_named(
        player,
        surface,
        position,
        "small-lamp",
        SMALL_LAMP_RANGE
    ) then
        return true
    end

    -- The Lamp Post prototype is optional and may not exist when its Startup
    -- setting is disabled. Avoid querying an unavailable prototype.
    if prototypes and prototypes.entity and prototypes.entity["lamp-post"] then
        if has_powered_lamp_named(
            player,
            surface,
            position,
            "lamp-post",
            LAMP_POST_RANGE
        ) then return true end
    end
    if prototypes and prototypes.entity and prototypes.entity["the-cave-lamp-pole-light"] then
        return has_powered_lamp_named(player, surface, position, "the-cave-lamp-pole-light", LAMP_POST_RANGE)
    end

    return false
end


-- Factorissimo interiors are fully exempt from Darkness Infestation.
-- No research, lamp, grace-period, warning, or enemy-spawn check is required
-- while the player is on a detected factory-interior surface.
local function is_factorissimo_interior(surface, position)
    -- Prefer Factorissimo's runtime API when the installed build exposes it.
    local interfaces = remote.interfaces
    local interface = interfaces and interfaces[FACTORISSIMO_INTERFACE]
    if interface then
        if interface.find_surrounding_factory then
            local ok, factory = pcall(
                remote.call,
                FACTORISSIMO_INTERFACE,
                "find_surrounding_factory",
                surface,
                position
            )
            if ok and factory then return true end
        end

        if interface.is_factorissimo_surface then
            local ok, is_factory_surface = pcall(
                remote.call,
                FACTORISSIMO_INTERFACE,
                "is_factorissimo_surface",
                surface
            )
            if ok and is_factory_surface then return true end
        end
    end

    -- Behrooz Factorissimo, Factorissimo 2 ports, and Factorissimo 3 use
    -- factory-floor-style surface names. This fallback deliberately does not
    -- depend on Interior Lighting research: every factory interior is exempt.
    local name = surface.name:lower()
    for _, marker in ipairs(FACTORISSIMO_SURFACE_MARKERS) do
        if name:find(marker, 1, true) then return true end
    end

    return false
end

local function is_exempt_interior(surface, position)
    return is_train_interior(surface)
        or is_shelter_interior(surface)
        or is_factorissimo_interior(surface, position)
        or mobile_factory_resources.is_interior_surface(surface)
end

local function difficulty_bias()
    local setting = settings.startup["the-cave-global-difficulty"]
    local value = setting and setting.value or "medium"
    if value == "easy" then return -0.25 end
    if value == "hard" then return 0.25 end
    if value == "nightmare" then return 0.45 end
    return 0
end

local function enemy_names_for(surface, position)
    local evolution = cave_evolution.factor(surface)
    local adjusted = evolution
    -- Match dig ambushes: Bob mode selects Cave tiers from real evolution,
    -- without the separate depth and global-difficulty tier adjustments.
    if not bob_enemies.active() then
        local distance = math.sqrt(position.x * position.x + position.y * position.y)
        local depth_bonus = 0
        if distance >= 1000 then
            depth_bonus = 0.23
        elseif distance >= 700 then
            depth_bonus = 0.12
        elseif distance >= 300 then
            depth_bonus = 0.05
        end
        adjusted = math.max(0, math.min(1, evolution + depth_bonus + difficulty_bias()))
    end
    if adjusted >= 0.85 then return "behemoth-biter", "behemoth-spitter" end
    if adjusted >= 0.55 then return "big-biter", "big-spitter" end
    if adjusted >= 0.25 then return "medium-biter", "medium-spitter" end
    return "small-biter", "small-spitter"
end

local function spawn_enemy(character, surface, origin, index)
    if not (character and character.valid and surface and surface.valid) then return false end
    if character.surface_index ~= surface.index then return false end

    local biter_name, spitter_name = enemy_names_for(surface, origin)
    local name = math.random() < 0.70 and biter_name or spitter_name
    if is_fortified_vault_surface(surface) then
        name = "the-cave-darkness-" .. name
    end
    local angle = (index * 2.399963229728653) + math.random()
    local distance = 7 + math.random() * 5
    local candidate = {
        x = origin.x + math.cos(angle) * distance,
        y = origin.y + math.sin(angle) * distance,
    }
    local position = surface.find_non_colliding_position(name, candidate, 6, 0.5)
    if not position then return false end

    local unit = surface.create_entity {
        name = name,
        position = position,
        force = "enemy",
    }
    if not (unit and unit.valid) then return false end

    -- An attack command may only target an entity on the same surface. Keep
    -- this defensive check even though both entities were derived from the
    -- same physical player context, because third-party interior mods can
    -- move controllers between surfaces in unusual ways.
    if not character.valid or unit.surface_index ~= character.surface_index then
        unit.destroy()
        return false
    end

    local commandable = unit.commandable
    if not commandable then
        unit.destroy()
        return false
    end

    local ok = pcall(function()
        commandable.set_command {
            type = defines.command.attack,
            target = character,
            distraction = defines.distraction.none,
        }
    end)

    if not ok then
        if unit.valid then unit.destroy() end
        return false
    end

    return true
end

local function spawn_wave(character, surface, position, state, tick)
    local elapsed_checks = math.floor((tick - state.unlit_since) / CHECK_INTERVAL)
    state.threat = elapsed_checks
    local wanted = math.min(2 + elapsed_checks, MAX_WAVE_SIZE)
    local spawned = 0
    for i = 1, wanted do
        if spawn_enemy(character, surface, position, i) then spawned = spawned + 1 end
    end
    state.last_spawn_tick = tick
    return spawned
end

local function warn_entered(player)
    player.print({ "the-cave-darkness.entered-zone" })
    pcall(function()
        player.play_sound { path = "utility/console_message" }
    end)
end

function darkness.on_init()
    root()
end

function darkness.on_configuration_changed()
    if enabled() then
        local data = root()
        -- A player already inside Mobile Factory when this update is installed
        -- must become safe immediately instead of waiting for the next
        -- four-second Darkness Infestation check.
        for _, player in pairs(game.connected_players or {}) do
            local character, surface, position = physical_context(player)
            if character and (not supported_surface(surface) or is_exempt_interior(surface, position)) then
                local state = data.players[player.index] or { threat = 0 }
                data.players[player.index] = state
                state.surface_index = surface.index
                state.in_darkness_zone = false
                reset_state(state)
            end
        end
    else
        storage.the_cave_darkness = nil
    end
end

function darkness.on_player_removed(event)
    local data = storage.the_cave_darkness
    if data and data.players then data.players[event.player_index] = nil end
end

function darkness.on_player_changed_surface(event)
    if not enabled() then return end
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end

    local data = root()
    local state = data.players[player.index] or { threat = 0 }
    data.players[player.index] = state

    local character, surface, position = physical_context(player)
    state.surface_index = surface and surface.index or nil
    reset_state(state)
    state.in_darkness_zone = false

    if not (character and surface
        and is_cave_surface(surface)) then return end

    -- Warn immediately instead of waiting for the four-second periodic check.
    state.in_darkness_zone = true
    warn_entered(player)

    if not character.driving and not has_powered_lamp(player, surface, position) then
        state.unlit_since = game.tick
        state.last_spawn_tick = nil
        state.threat = 0
    end
end

function darkness.on_nth_tick(event)
    if not enabled() then return end
    local data = root()

    for _, player in pairs(game.connected_players) do
        local state = data.players[player.index]
        if not state then
            state = { threat = 0 }
            data.players[player.index] = state
        end

        local character, surface, position = physical_context(player)
        if not character then
            state.surface_index = nil
            reset_state(state)
            state.in_darkness_zone = false
        else
            if state.surface_index ~= surface.index then
                state.surface_index = surface.index
                state.in_darkness_zone = false
                reset_state(state)
            end

            local exempt_interior = is_exempt_interior(surface, position)
            local forced_darkness_zone = is_cave_surface(surface)
            -- Every cave interior is a Darkness Zone from entry; its spawn
            -- position does not grant a 5x5-chunk safe area.
            local safe = not supported_surface(surface) or exempt_interior
                or (not forced_darkness_zone and in_safe_zone(player, surface, position))
            if safe then
                if state.in_darkness_zone then state.in_darkness_zone = false end
                reset_state(state)
            else
                if not state.in_darkness_zone then
                    state.in_darkness_zone = true
                    warn_entered(player)
                end

                -- Match Cave Miner: driving is treated as temporary safety.
                if character.driving then
                    reset_state(state)
                elseif has_powered_lamp(player, surface, position) then
                    reset_state(state)
                else
                    if not state.unlit_since then
                        state.unlit_since = event.tick
                        state.last_spawn_tick = nil
                        state.threat = 0
                    end

                    if event.tick - state.unlit_since >= GRACE_TICKS then
                        if not state.last_spawn_tick
                            or event.tick - state.last_spawn_tick >= CHECK_INTERVAL then
                            spawn_wave(character, surface, position, state, event.tick)
                        end
                    end
                end
            end
        end
    end
end

return darkness
