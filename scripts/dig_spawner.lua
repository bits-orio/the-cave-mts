local game_settings = require("scripts.game_settings")
local settings = game_settings.proxy(settings)

local function global_difficulty()
    local setting = settings.startup["the-cave-global-difficulty"]
    return setting and setting.value or "medium"
end

local function difficulty_tier_bias()
    local value = global_difficulty()

    if value == "easy" then return -0.25 end
    if value == "hard" then return 0.25 end
    if value == "nightmare" then return 0.45 end
    return 0
end

-- Direct-dig pressure is deliberately bounded. Main surfaces keep their single
-- enemy event; timed resource caves receive a small deterministic pack. Both
-- paths discard blocked cycles instead of saving a later enemy debt.
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local cave_evolution = require("scripts.cave_evolution")
local enemy_nest_growth = require("scripts.enemy_nest_growth")
local bob_enemies = require("scripts.bob_enemies")

local dig_spawner = {}

local PEACEFUL_DEPTH = 65
local MAIN_ACTIVE_UNIT_CAP = 6
local ACTIVE_UNIT_CAP_RADIUS = 80
local INTERVAL_STORAGE = "the_cave_dig_ambush_intervals"
local INTERVAL_SCHEMA_VERSION = 2

local DIG_INTERVALS = {
    easy = { min = 3, max = 4 },
    medium = { min = 3, max = 4 },
    hard = { min = 3, max = 4 },
    nightmare = { min = 3, max = 4 },
}

local EXTRACTION_PACK_SIZES = {
    easy = { min = 2, max = 3 },
    medium = { min = 3, max = 5 },
    hard = { min = 5, max = 8 },
    nightmare = { min = 8, max = 12 },
}

-- Hash stream ids (keep unique across all dig modules).
local S_INTERVAL, S_TYPE, S_COUNT, S_POSITION_X, S_POSITION_Y = 10, 11, 12, 13, 14
local S_ARACHNID_TYPE = 15
local S_BOB_KIND, S_BOB_TIER = 16, 17
local S_WORM_CHANCE = 18

local UNIT_LADDER = {
    {
        evolution = 0.00,
        biter = "small-biter",
        spitter = "small-spitter",
        snapper = "small-armoured-biter",
        arachnid_biter = "arachnid-biter-drone-unit",
        arachnid_spitter = "arachnid-spitter-smallspitter-unit",
        worm = "small-worm-turret",
    },
    {
        evolution = 0.25,
        biter = "medium-biter",
        spitter = "medium-spitter",
        snapper = "medium-armoured-biter",
        arachnid_biter = "arachnid-biter-warrior-unit",
        arachnid_spitter = "arachnid-spitter-mediumspitter-unit",
        worm = "medium-worm-turret",
    },
    {
        evolution = 0.55,
        biter = "big-biter",
        spitter = "big-spitter",
        snapper = "big-armoured-biter",
        arachnid_biter = "arachnid-biter-tiger-unit",
        arachnid_spitter = "arachnid-spitter-bigspitter-unit",
        worm = "big-worm-turret",
    },
    {
        evolution = 0.85,
        biter = "behemoth-biter",
        spitter = "behemoth-spitter",
        snapper = "behemoth-armoured-biter",
        arachnid_biter = "arachnid-biter-royalwarrior-unit",
        arachnid_spitter = "arachnid-spitter-behemothspitter-unit",
        worm = "behemoth-worm-turret",
    },
}

function dig_spawner.tier_for(evolution)
    local tier = UNIT_LADDER[1]
    for _, candidate in pairs(UNIT_LADDER) do
        if evolution >= candidate.evolution then tier = candidate end
    end
    return tier
end
local tier_for = dig_spawner.tier_for

local function interval_key(dig)
    return tostring(dig.surface.index) .. ":" .. tostring(dig.force.index)
end

local function interval_storage()
    storage[INTERVAL_STORAGE] = storage[INTERVAL_STORAGE] or {}
    return storage[INTERVAL_STORAGE]
end

local function rolled_interval(surface, sequence, difficulty)
    local bounds = DIG_INTERVALS[difficulty] or DIG_INTERVALS.medium
    local seed = surface.map_gen_settings.seed
    -- Force is intentionally absent from the roll. Separate Force state keeps
    -- counters independent, while teams following the same dig sequence receive
    -- the same deterministic intervals on the same surface.
    return hash.range(seed, sequence, surface.index, S_INTERVAL, bounds.min, bounds.max)
end

local function interval_state(dig)
    local list = interval_storage()
    local key = interval_key(dig)
    local difficulty = global_difficulty()
    local state = list[key]

    if not state
        or state.difficulty ~= difficulty
        or state.schema_version ~= INTERVAL_SCHEMA_VERSION then
        state = {
            digs = 0,
            sequence = state and tonumber(state.sequence) or 0,
            difficulty = difficulty,
            schema_version = INTERVAL_SCHEMA_VERSION,
        }
        state.target = rolled_interval(dig.surface, state.sequence, difficulty)
        list[key] = state
    end

    return state
end

-- Finish a cycle before any placement or nearby-enemy check. A blocked event is
-- discarded and starts a fresh interval, so the system can never save an enemy
-- debt and release it immediately after combat.
local function advance_cycle(dig, state)
    local event_sequence = state.sequence
    state.digs = 0
    state.sequence = event_sequence + 1
    state.target = rolled_interval(dig.surface, state.sequence, state.difficulty)
    return event_sequence
end

local function active_mobile_enemies_near(surface, position, limit)
    return surface.count_entities_filtered {
        type = "unit",
        force = "enemy",
        position = position,
        radius = ACTIVE_UNIT_CAP_RADIUS,
        limit = limit,
    }
end

local function spawn_one_unit(surface, position, tier, seed, x, y, sequence, member, spread, evolution)
    local member_key = (member or 1) - 1
    local roll_x = member_key == 0 and x or x + member_key * 7919
    local roll_y = member_key == 0 and y or y - member_key * 104729
    -- Keep the existing family and tier selection. Selected Worms receive a
    -- separate 25% acceptance roll below; rejected Worms have no replacement.
    local family_roll = hash.roll(seed, roll_x, roll_y, S_TYPE + sequence * 100)
    local name, family
    if bob_enemies.active() then
        name, family = bob_enemies.choose_dig(evolution, tier, family_roll,
            hash.roll(seed, roll_x, roll_y, S_BOB_KIND + sequence * 100),
            hash.roll(seed, roll_x, roll_y, S_BOB_TIER + sequence * 100))
        if not name then return nil, nil end
    elseif family_roll < 0.20 then
        name = tier.biter
        family = "biter"
    elseif family_roll < 0.40 then
        name = tier.spitter
        family = "spitter"
    elseif family_roll < 0.60 then
        name = tier.snapper
        family = "snapper"
    elseif family_roll < 0.80 then
        name = hash.roll(seed, roll_x, roll_y, S_ARACHNID_TYPE + sequence * 100) < 0.5
            and tier.arachnid_biter or tier.arachnid_spitter
        family = "arachnid"
    else
        name = tier.worm
        family = "worm"
    end
    local bob_info = bob_enemies.unit_info(name)
    if (family == "worm" or (bob_info and bob_info.kind == "worm-turret"))
        and hash.roll(seed, roll_x, roll_y, S_WORM_CHANCE + sequence * 100) >= 0.25 then
        return nil, nil
    end
    local target = position
    if spread then
        target = {
            x = position.x + hash.range(seed, roll_x, roll_y, S_POSITION_X, -4, 4),
            y = position.y + hash.range(seed, roll_x, roll_y, S_POSITION_Y, -4, 4),
        }
    end
    local spot = surface.find_non_colliding_position(name, target, 5, 0.5)
    if not spot then return nil, nil end

    local entity = surface.create_entity { name = name, position = spot, force = "enemy" }
    if not (entity and entity.valid) then return nil, nil end
    bob_enemies.protect_scripted_base_part(entity)
    return entity, family
end

function dig_spawner.on_dig(dig)
    if not (dig and dig.surface and dig.surface.valid and dig.position) then return false end
    if not (dig.force and dig.force.valid) then return false end
    if dig.room_opened then return false end

    local position = dig.position
    local surface = dig.surface
    local timed_cave_surface = type(surface.name) == "string"
        and (surface.name:find("^the%-cave%-uranium%-cave%-") ~= nil
            or surface.name:find("^the%-cave%-mineral%-cave%-") ~= nil)
    if not timed_cave_surface and position.x * position.x + position.y * position.y < PEACEFUL_DEPTH * PEACEFUL_DEPTH then
        return false
    end

    -- control.lua calls this handler only for an ordinary rock directly mined
    -- by a player, deliberately excavated by a registered Queen, or resolved
    -- by a player-placed TNT Box. Robot, unrelated explosion and Demolisher
    -- destruction never advances this counter, and a dig that opened a room
    -- was rejected above.
    local state = interval_state(dig)
    state.digs = state.digs + 1
    if state.digs < state.target then return false end

    local sequence = advance_cycle(dig, state)

    -- The count runs only once per completed interval, not on every dig. Count
    -- all mobile enemy units so regional enemies and Brood Split children also
    -- protect an already-busy battlefield from another direct-dig spawn.
    local active_cap = timed_cave_surface
        and depth_levels.mobile_enemy_count_cap() or MAIN_ACTIVE_UNIT_CAP
    local active_count = active_mobile_enemies_near(surface, position, active_cap)
    if active_count >= active_cap then return false end

    local seed = surface.map_gen_settings.seed
    local x = math.floor(position.x)
    local y = math.floor(position.y)
    local evolution = cave_evolution.factor(surface)
    local tier_evolution = evolution
    -- Bob's spawn curves use the real parent-surface evolution. Keep the
    -- original Cave families on that same value while Bob is active.
    if not bob_enemies.active() then
        local profile = depth_levels.level_for_surface_position(surface, position)
        tier_evolution = math.max(0, math.min(1,
            evolution + (profile.enemy_mult - 1) * 0.35 + difficulty_tier_bias()
        ))
    end
    local tier = tier_for(tier_evolution)

    local spawn_count = 1
    if timed_cave_surface then
        local bounds = EXTRACTION_PACK_SIZES[state.difficulty] or EXTRACTION_PACK_SIZES.medium
        spawn_count = math.min(active_cap - active_count,
            hash.range(seed, sequence, surface.index, S_COUNT, bounds.min, bounds.max))
    end

    local spawned = 0
    for member = 1, spawn_count do
        local entity, family = spawn_one_unit(surface, position, tier, seed, x, y, sequence,
            member, timed_cave_surface, evolution)
        if entity then
            spawned = spawned + 1
            enemy_nest_growth.register_direct_dig_spawn(entity, family)
        end
    end
    return spawned > 0
end

function dig_spawner.on_configuration_changed()
    interval_storage()
    -- Retire the pre-2.7.52 thirty-dig cooldown state. It is never converted
    -- into interval progress, so updating cannot trigger an immediate ambush.
    storage.the_cave_dig_ambush_cooldowns = nil
end

-- Removed in 2.5.51: killing a nest no longer releases a second army. Keeping
-- the public function as a no-op preserves control.lua and save compatibility.
function dig_spawner.on_nest_died(_entity)
end

function dig_spawner.apply_expansion_setting()
    -- The Cave owns expansion through an explicitly filtered settler group.
    -- Keep Factorio's unfiltered planner disabled so it can never recruit
    -- private Wave Defense units when both independent systems are enabled.
    game.map_settings.enemy_expansion.enabled = false
end

return dig_spawner
