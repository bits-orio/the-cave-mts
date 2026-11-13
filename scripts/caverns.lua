local settings = require("scripts.game_settings").proxy(settings)

-- Caverns (ADR 0006): a dig's seed-keyed roll can breach a tunnel that snakes
-- outward, sometimes ending in a room with a depth-gated personality. Carved
-- tiles materialize veins and chart, but per-tile spawn/treasure rolls are
-- skipped — the room's contents are the sole source of its danger and loot.
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local mirror = require("scripts.lib.mirror")
local world = require("scripts.world")
local region_features = require("scripts.region_features")
local treasure = require("scripts.treasure")
local dig_spawner = require("scripts.dig_spawner")
local collapse = require("scripts.collapse")
local pop_text = require("scripts.pop_text")
local fortified_vaults = require("scripts.fortified_vaults")
local reward_policy = require("scripts.reward_policy")
local cave_evolution = require("scripts.cave_evolution")
local enemy_nest_growth = require("scripts.enemy_nest_growth")

local caverns = {}
caverns.bob_enemies = require("scripts.bob_enemies")
caverns.placement = require("scripts.cave_placement")
caverns.scheduled = require("scripts.advancing_caves")
caverns.progression = require("scripts.progression_rooms")

-- Factorio stores required modules under engine-owned canonical keys, so
-- looking them up later through a guessed package.loaded key is not reliable.
-- control.lua injects the already-required APIs once during script loading;
-- every runtime spacing query then uses these direct references.
local uranium_caves_api
local mineral_caves_api
local lost_city_api

function caverns.configure_extraction_cave_apis(uranium_api, mineral_api, city_api)
    assert(type(uranium_api) == "table"
        and type(uranium_api.has_parent_entrance_within) == "function",
        "The Cave: Uranium Cave spacing API is unavailable")
    assert(type(mineral_api) == "table"
        and type(mineral_api.has_parent_entrance_within) == "function"
        and type(mineral_api.peek_placeable_resource_key) == "function",
        "The Cave: Mineral Cave spacing API is unavailable")
    assert(type(city_api) == "table"
        and type(city_api.has_parent_entrance_within) == "function",
        "The Cave: Lost City spacing API is unavailable")
    uranium_caves_api = uranium_api
    mineral_caves_api = mineral_api
    lost_city_api = city_api
end

function caverns.configure_train_safety_api(api)
    assert(type(api) == "table" and type(api.cave_area_is_safe) == "function",
        "The Cave: Train Interiors cave-safety API is unavailable")
    caverns.train_safety_api = api
    caverns.placement.configure_train_safety_api(api)
end

local ENEMY_LASER_TURRET = "the-cave-enemy-laser-turret"
local LEGACY_LASER_POWER = "the-cave-enemy-laser-power"
local LEGACY_LASER_POWER_POLE = "the-cave-enemy-laser-power-pole"
local ENEMY_LASER_MIGRATION_VERSION = 2510
local GLEBA_WILD_PLANT_MIGRATION_VERSION = 2731


function caverns.on_init()
    storage.the_cave_enemy_guard_turrets = storage.the_cave_enemy_guard_turrets or {}
    storage.cavern_rooms = storage.cavern_rooms or {}
    storage.cavern_worms = storage.cavern_worms or {}
    storage.cavern_countdowns = storage.cavern_countdowns or {}
    storage.next_cavern_id = storage.next_cavern_id or 1
    storage.fortified_vault_generation = storage.fortified_vault_generation or {}
    -- Exploration pacing is tracked per surface and planetary region so a fight
    -- in one quadrant cannot suppress native encounters in a distant quadrant.
    storage.cavern_combat_cooldowns = storage.cavern_combat_cooldowns or {}
    -- Timed Iron/Copper/Coal/Uranium caves use their own short nest drought
    -- counter. It is deliberately separate from main-surface room pacing.
    storage.cavern_extraction_nest_pacing = storage.cavern_extraction_nest_pacing or {}
    -- Counts successfully opened Medium+ rooms since each Force last found a
    -- Uranium Cave on a surface. It provides a deterministic anti-drought
    -- guarantee without permitting nearby Uranium entrances to cluster.
    storage.cavern_uranium_pity = storage.cavern_uranium_pity or {}
    -- Counts successfully opened eligible ordinary empty rooms since each Force
    -- last found a Mineral Cave on a surface. Spacing and Uranium priority still
    -- win, so the guarantee can never create a clustered extraction entrance.
    storage.cavern_mineral_pity = storage.cavern_mineral_pity or {}
    -- Lost City uses its own 10-room anti-drought counter. A candidate blocked
    -- by the permanent 400-tile spacing rule never consumes the guarantee.
    storage.cavern_lost_city_pity = storage.cavern_lost_city_pity or {}
    -- Permanent geometry registry for every successfully generated cavern room.
    -- Unlike storage.cavern_rooms (which only tracks live worm-protected rooms),
    -- these footprints remain for the lifetime of the surface so a later room
    -- can never be carved or populated on top of an earlier one.
    storage.cavern_room_footprints = storage.cavern_room_footprints or {}
end

-- No collapse can trigger inside a room while its worms live — and none
-- while its countdown runs: the countdown IS the grace period, and its
-- expiry (sparse_collapse, live re-checked) is the only judge of that
-- ceiling. Without this, placing one wall mid-countdown re-evaluated the
-- room straight into 2.5-second pendings, stealing the time.
collapse.protection_check = function(surface, x, y)
    for _, room in pairs(storage.cavern_rooms or {}) do
        if room.protected and room.surface_index == surface.index then
            local dx, dy = x - room.cx, y - room.cy
            if dx * dx + dy * dy <= (room.radius + 2) * (room.radius + 2) then
                return true
            end
        end
    end
    for _, cd in pairs(storage.cavern_countdowns or {}) do
        if cd.surface_index == surface.index then
            local r = cd.radius or 16
            local dx, dy = x - cd.cx, y - cd.cy
            if dx * dx + dy * dy <= r * r then
                return true
            end
        end
    end
    return false
end

-- Hash stream ids (keep unique across all dig modules).
local S_TRIGGER, S_DIR, S_LEN, S_TURN = 40, 41, 42, 43
local S_ROOM, S_RADIUS, S_TYPE, S_CONTENT = 44, 45, 46, 47
local S_SHAPE = 48
local S_SPECIAL, S_SPECIAL_CONTENT = 49, 50
local S_CORRIDOR_COUNT, S_CORRIDOR_LENGTH, S_CORRIDOR_TURN = 151, 152, 153
local S_MINERAL_CAVE = 154
local S_DEMOLISHER_SIDE, S_DEMOLISHER_CLEARANCE = 155, 156
local S_LOST_CITY = 157

local URANIUM_CAVE_MIN_DISTANCE = 192
local MINERAL_CAVE_MIN_DISTANCE = 192
local LOST_CITY_MIN_DISTANCE = 400
local URANIUM_PITY_ROOMS = 8
local MINERAL_PITY_ROOMS = 5
local LOST_CITY_PITY_ROOMS = 10
local MINERAL_CAVE_EMPTY_ROOM_CHANCE = 0.20
local LOST_CITY_EMPTY_ROOM_CHANCE = 0.10
local EXTRACTION_EMPTY_ROOM_WEIGHT = 40
local EXTRACTION_NEST_ROOM_WEIGHT = 60
local EXTRACTION_EMPTY_ROOM_GUARANTEE = 2
local EXTRACTION_LIVE_SPAWNER_CAP = 12
local EXTRACTION_NEST_ROOM_SPAWNER_COUNT = 3

local MIN_DEPTH = 30 -- never breach a cavern right at the carve-out
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Room personalities by minimum depth; weights picked per seed-keyed roll.
local ROOM_TYPES = {
    { kind = "empty", min_depth = 0, weight = 50 },
    { kind = "nest", min_depth = 75, weight = 60 },
    { kind = "arachnid", min_depth = 100, weight = 15 },
    { kind = "hoard", min_depth = 140, weight = 15 },
    { kind = "uranium-cave", min_depth = 300, weight = 12 },
}

local function mineral_caves_enabled()
    local startup = settings and settings.startup
    if not startup then return true end
    local iron = startup["the-cave-iron-cave"]
    local copper = startup["the-cave-copper-cave"]
    local coal = startup["the-cave-coal-cave"]
    return not iron or iron.value == "enabled" or iron.value == true
        or not copper or copper.value == "enabled" or copper.value == true
        or not coal or coal.value == "enabled" or coal.value == true
end

local function lost_city_enabled()
    return caverns.scheduled.enabled("village")
end

local function uranium_caves_enabled()
    local setting = settings and settings.startup and settings.startup["the-cave-uranium-caves"]
    return not setting or setting.value == "enabled"
end

local function entrance_near(module_api, surface, position, radius, resource_key)
    assert(module_api and type(module_api.has_parent_entrance_within) == "function",
        "The Cave: extraction-cave spacing APIs were not configured")
    return module_api.has_parent_entrance_within(surface, position, radius, resource_key) == true
end

local function uranium_pity_surface(surface_index)
    storage.cavern_uranium_pity = storage.cavern_uranium_pity or {}
    local state = storage.cavern_uranium_pity[surface_index]
    if not state then
        state = {}
        storage.cavern_uranium_pity[surface_index] = state
    end
    return state
end

local function uranium_pity_count(surface, force)
    if not (surface and surface.valid) then return 0 end
    local force_index = force and force.valid and force.index or 0
    return tonumber(uranium_pity_surface(surface.index)[force_index]) or 0
end

local function set_uranium_pity_count(surface, force, count)
    if not (surface and surface.valid) then return end
    local force_index = force and force.valid and force.index or 0
    uranium_pity_surface(surface.index)[force_index] = math.max(0, tonumber(count) or 0)
end

local function mineral_pity_surface(surface_index)
    storage.cavern_mineral_pity = storage.cavern_mineral_pity or {}
    local state = storage.cavern_mineral_pity[surface_index]
    if not state then
        state = {}
        storage.cavern_mineral_pity[surface_index] = state
    end
    return state
end

local function mineral_pity_count(surface, force)
    if not (surface and surface.valid) then return 0 end
    local force_index = force and force.valid and force.index or 0
    return tonumber(mineral_pity_surface(surface.index)[force_index]) or 0
end

local function set_mineral_pity_count(surface, force, count)
    if not (surface and surface.valid) then return end
    local force_index = force and force.valid and force.index or 0
    mineral_pity_surface(surface.index)[force_index] = math.max(0, tonumber(count) or 0)
end

local function lost_city_pity_surface(surface_index)
    storage.cavern_lost_city_pity = storage.cavern_lost_city_pity or {}
    local state = storage.cavern_lost_city_pity[surface_index]
    if not state then
        state = {}
        storage.cavern_lost_city_pity[surface_index] = state
    end
    return state
end

local function lost_city_pity_count(surface, force)
    if not (surface and surface.valid) then return 0 end
    local force_index = force and force.valid and force.index or 0
    return tonumber(lost_city_pity_surface(surface.index)[force_index]) or 0
end

local function set_lost_city_pity_count(surface, force, count)
    if not (surface and surface.valid) then return end
    local force_index = force and force.valid and force.index or 0
    lost_city_pity_surface(surface.index)[force_index] = math.max(0, tonumber(count) or 0)
end

-- Carving delegates to world.carve_tile (entity removal + void→floor + vein),
-- records each tile for frontier advance, and separately records tiles that
-- actually OPENED (void→floor) — only those owe ceiling debt; overlap with
-- already-open space must never double-charge (it once stacked cells to 9+,
-- beyond any pillar's reach).
local suppress_room_region_features = false

local function carve_tile(surface, x, y, force, carved, skip_vein, opened)
    if world.carve_tile(surface, x, y, force, skip_vein, suppress_room_region_features) and opened then
        opened[#opened + 1] = { x, y }
    end
    carved[#carved + 1] = { x, y }
end

local function carve_disc(surface, cx, cy, radius, force, carved, skip_vein, opened)
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= radius * radius then
                carve_tile(surface, x, y, force, carved, skip_vein, opened)
            end
        end
    end
end

-- The Cave 2.1.5: visual variety for cavern rooms.
-- Every normal shape uses the same radius budget as the old circular room.  The goal is
-- different silhouettes, not bigger rewards or giant accidental map openings.
-- Double-room is the only intentional exception: slightly larger for readability,
-- but still hard-capped by conservative radius-based dimensions.
local ROOM_SHAPES = { "circle", "square", "rectangle", "line", "l", "cross", "t", "u", "double" }

-- Shared Space Age room protection. These four regions use the corridor-chain
-- layout and permanent room-footprint overlap validation. Every region still
-- records opened rooms so the Queen controller can select real destinations.
local SPACED_ROOM_REGIONS = {
    fulgora = true,
    gleba = true,
    vulcanus = true,
    aquilo = true,
}
local ROOM_SAFETY_BUFFER = 12

local function room_shape_plan(seed, cx, cy, radius, forced_shape)
    local shape = forced_shape or ROOM_SHAPES[hash.range(seed, cx, cy, S_SHAPE, 1, #ROOM_SHAPES)] or "circle"
    local plan = { shape = shape, cx = cx, cy = cy, radius = radius }

    if shape == "circle" then
        plan.x1, plan.y1, plan.x2, plan.y2 = cx - radius, cy - radius, cx + radius, cy + radius
    elseif shape == "square" then
        plan.half = math.max(4, math.floor(radius * 0.78 + 0.5))
        plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.half, cy - plan.half, cx + plan.half, cy + plan.half
    elseif shape == "rectangle" then
        plan.long = math.max(6, math.floor(radius * 1.15 + 0.5))
        plan.short = math.max(3, math.floor(radius * 0.50 + 0.5))
        plan.horizontal = hash.roll(seed, cx, cy, S_SHAPE + 101) < 0.5
        if plan.horizontal then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.long, cy - plan.short, cx + plan.long, cy + plan.short
        else
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.short, cy - plan.long, cx + plan.short, cy + plan.long
        end
    elseif shape == "line" then
        plan.long = math.max(8, math.floor(radius * 1.35 + 0.5))
        plan.short = math.max(2, math.floor(radius * 0.28 + 0.5))
        plan.horizontal = hash.roll(seed, cx, cy, S_SHAPE + 102) < 0.5
        if plan.horizontal then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.long, cy - plan.short, cx + plan.long, cy + plan.short
        else
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.short, cy - plan.long, cx + plan.short, cy + plan.long
        end
    elseif shape == "l" then
        plan.arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        plan.width = math.max(3, math.floor(radius * 0.38 + 0.5))
        plan.sx = hash.roll(seed, cx, cy, S_SHAPE + 103) < 0.5 and -1 or 1
        plan.sy = hash.roll(seed, cx, cy, S_SHAPE + 104) < 0.5 and -1 or 1
        plan.x1 = cx + math.min(-plan.width, plan.sx * plan.arm)
        plan.x2 = cx + math.max(plan.width, plan.sx * plan.arm)
        plan.y1 = cy + math.min(-plan.width, plan.sy * plan.arm)
        plan.y2 = cy + math.max(plan.width, plan.sy * plan.arm)
    elseif shape == "cross" then
        plan.arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        plan.width = math.max(2, math.floor(radius * 0.30 + 0.5))
        plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.arm, cy - plan.arm, cx + plan.arm, cy + plan.arm
    elseif shape == "t" then
        plan.arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        plan.width = math.max(2, math.floor(radius * 0.30 + 0.5))
        plan.stem = math.max(6, math.floor(radius * 0.95 + 0.5))
        plan.dir = hash.range(seed, cx, cy, S_SHAPE + 105, 1, 4)
        if plan.dir == 1 then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.arm, cy - plan.width, cx + plan.arm, cy + plan.stem
        elseif plan.dir == 2 then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.arm, cy - plan.stem, cx + plan.arm, cy + plan.width
        elseif plan.dir == 3 then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.width, cy - plan.arm, cx + plan.stem, cy + plan.arm
        else
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.stem, cy - plan.arm, cx + plan.width, cy + plan.arm
        end
    elseif shape == "u" then
        plan.arm = math.max(7, math.floor(radius * 0.95 + 0.5))
        plan.width = math.max(2, math.floor(radius * 0.28 + 0.5))
        plan.gap = math.max(4, math.floor(radius * 0.55 + 0.5))
        plan.dir = hash.range(seed, cx, cy, S_SHAPE + 106, 1, 4)
        if plan.dir == 1 then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.gap - plan.width, cy - plan.arm, cx + plan.gap + plan.width, cy + plan.width
        elseif plan.dir == 2 then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.gap - plan.width, cy - plan.width, cx + plan.gap + plan.width, cy + plan.arm
        elseif plan.dir == 3 then
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.arm, cy - plan.gap - plan.width, cx + plan.width, cy + plan.gap + plan.width
        else
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.width, cy - plan.gap - plan.width, cx + plan.arm, cy + plan.gap + plan.width
        end
    elseif shape == "double" then
        plan.lobe = math.max(4, math.floor(radius * 0.58 + 0.5))
        plan.gap = math.max(5, math.floor(radius * 0.78 + 0.5))
        plan.corridor = math.max(1, math.floor(radius * 0.18 + 0.5))
        plan.horizontal = hash.roll(seed, cx, cy, S_SHAPE + 107) < 0.5
        if plan.horizontal then
            local extent = plan.gap + plan.lobe
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - extent, cy - plan.lobe, cx + extent, cy + plan.lobe
        else
            local extent = plan.gap + plan.lobe
            plan.x1, plan.y1, plan.x2, plan.y2 = cx - plan.lobe, cy - extent, cx + plan.lobe, cy + extent
        end
    else
        plan.shape = "circle"
        plan.x1, plan.y1, plan.x2, plan.y2 = cx - radius, cy - radius, cx + radius, cy + radius
    end
    return plan
end

-- The corridor endpoint is the room entrance, not the room centre. Translate
-- the complete precomputed plan forward so its nearest edge begins immediately
-- after the final corridor tile. This preserves the requested 10–20 tile gap
-- even for large progression rooms and fortresses.
local function anchor_room_plan_after_corridor(plan, anchor_x, anchor_y, dir)
    if not (plan and dir) then return plan end

    local shift_x, shift_y = 0, 0
    if dir[1] > 0 then
        shift_x = (plan.cx - plan.x1) + 1
    elseif dir[1] < 0 then
        shift_x = -((plan.x2 - plan.cx) + 1)
    elseif dir[2] > 0 then
        shift_y = (plan.cy - plan.y1) + 1
    elseif dir[2] < 0 then
        shift_y = -((plan.y2 - plan.cy) + 1)
    end

    shift_x = shift_x + anchor_x - plan.cx
    shift_y = shift_y + anchor_y - plan.cy
    plan.cx = plan.cx + shift_x
    plan.cy = plan.cy + shift_y
    plan.x1 = plan.x1 + shift_x
    plan.x2 = plan.x2 + shift_x
    plan.y1 = plan.y1 + shift_y
    plan.y2 = plan.y2 + shift_y
    return plan
end

local function room_plan_contains(plan, x, y)
    local entry = plan.entry_connection
    if entry and x >= entry.x1 and x <= entry.x2 and y >= entry.y1 and y <= entry.y2 then return true end
    local dx, dy = x - plan.cx, y - plan.cy
    local shape = plan.shape
    if shape == "circle" then return dx * dx + dy * dy <= plan.radius * plan.radius end
    if shape == "square" then return math.abs(dx) <= plan.half and math.abs(dy) <= plan.half end
    if shape == "rectangle" or shape == "line" then
        if plan.horizontal then return math.abs(dx) <= plan.long and math.abs(dy) <= plan.short end
        return math.abs(dx) <= plan.short and math.abs(dy) <= plan.long
    end
    if shape == "l" then
        local horizontal = math.abs(dy) <= plan.width
            and dx >= math.min(-plan.width, plan.sx * plan.arm)
            and dx <= math.max(plan.width, plan.sx * plan.arm)
        local vertical = math.abs(dx) <= plan.width
            and dy >= math.min(-plan.width, plan.sy * plan.arm)
            and dy <= math.max(plan.width, plan.sy * plan.arm)
        return horizontal or vertical
    end
    if shape == "cross" then
        return (math.abs(dx) <= plan.arm and math.abs(dy) <= plan.width)
            or (math.abs(dx) <= plan.width and math.abs(dy) <= plan.arm)
    end
    if shape == "t" then
        if plan.dir == 1 then
            return (math.abs(dx) <= plan.arm and math.abs(dy) <= plan.width)
                or (math.abs(dx) <= plan.width and dy >= 0 and dy <= plan.stem)
        elseif plan.dir == 2 then
            return (math.abs(dx) <= plan.arm and math.abs(dy) <= plan.width)
                or (math.abs(dx) <= plan.width and dy <= 0 and dy >= -plan.stem)
        elseif plan.dir == 3 then
            return (math.abs(dx) <= plan.width and math.abs(dy) <= plan.arm)
                or (math.abs(dy) <= plan.width and dx >= 0 and dx <= plan.stem)
        end
        return (math.abs(dx) <= plan.width and math.abs(dy) <= plan.arm)
            or (math.abs(dy) <= plan.width and dx <= 0 and dx >= -plan.stem)
    end
    if shape == "u" then
        if plan.dir == 1 then
            return (math.abs(dx) <= plan.gap + plan.width and math.abs(dy) <= plan.width)
                or (math.abs(dx + plan.gap) <= plan.width and dy >= -plan.arm and dy <= plan.width)
                or (math.abs(dx - plan.gap) <= plan.width and dy >= -plan.arm and dy <= plan.width)
        elseif plan.dir == 2 then
            return (math.abs(dx) <= plan.gap + plan.width and math.abs(dy) <= plan.width)
                or (math.abs(dx + plan.gap) <= plan.width and dy >= -plan.width and dy <= plan.arm)
                or (math.abs(dx - plan.gap) <= plan.width and dy >= -plan.width and dy <= plan.arm)
        elseif plan.dir == 3 then
            return (math.abs(dy) <= plan.gap + plan.width and math.abs(dx) <= plan.width)
                or (math.abs(dy + plan.gap) <= plan.width and dx >= -plan.arm and dx <= plan.width)
                or (math.abs(dy - plan.gap) <= plan.width and dx >= -plan.arm and dx <= plan.width)
        end
        return (math.abs(dy) <= plan.gap + plan.width and math.abs(dx) <= plan.width)
            or (math.abs(dy + plan.gap) <= plan.width and dx >= -plan.width and dx <= plan.arm)
            or (math.abs(dy - plan.gap) <= plan.width and dx >= -plan.width and dx <= plan.arm)
    end
    if shape == "double" then
        if plan.horizontal then
            local left = (dx + plan.gap) * (dx + plan.gap) + dy * dy <= plan.lobe * plan.lobe
            local right = (dx - plan.gap) * (dx - plan.gap) + dy * dy <= plan.lobe * plan.lobe
            local hall = dx >= -plan.gap and dx <= plan.gap and math.abs(dy) <= plan.corridor
            return left or right or hall
        end
        local top = dx * dx + (dy + plan.gap) * (dy + plan.gap) <= plan.lobe * plan.lobe
        local bottom = dx * dx + (dy - plan.gap) * (dy - plan.gap) <= plan.lobe * plan.lobe
        local hall = dy >= -plan.gap and dy <= plan.gap and math.abs(dx) <= plan.corridor
        return top or bottom or hall
    end
    return false
end

local function room_footprints_for_surface(surface_index)
    storage.cavern_room_footprints = storage.cavern_room_footprints or {}
    local list = storage.cavern_room_footprints[surface_index]
    if not list then
        list = {}
        storage.cavern_room_footprints[surface_index] = list
    end
    return list
end

local function room_plan_overlaps_registered(surface_index, plan)
    for _, existing in ipairs(room_footprints_for_surface(surface_index)) do
        if not (
            plan.x2 + ROOM_SAFETY_BUFFER < existing.x1
            or plan.x1 - ROOM_SAFETY_BUFFER > existing.x2
            or plan.y2 + ROOM_SAFETY_BUFFER < existing.y1
            or plan.y1 - ROOM_SAFETY_BUFFER > existing.y2
        ) then
            return true
        end
    end
    return false
end

local function key_xy(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

local function room_plan_has_old_open_terrain(surface, plan, fresh_open)
    -- Existing saves did not register historical room footprints. Detect those
    -- rooms from their already-open floor while ignoring the fresh corridor
    -- created by this same dig event and ignoring still-closed frontier rocks.
    local covered = {}
    local covers = surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-tree" },
        area = { { plan.x1, plan.y1 }, { plan.x2 + 1, plan.y2 + 1 } },
    }
    for _, entity in pairs(covers or {}) do
        if entity.valid then
            covered[key_xy(math.floor(entity.position.x), math.floor(entity.position.y))] = true
        end
    end

    local total, old_open = 0, 0
    for x = plan.x1, plan.x2 do
        for y = plan.y1, plan.y2 do
            if room_plan_contains(plan, x, y) then
                total = total + 1
                local key = key_xy(x, y)
                if not (fresh_open and fresh_open[key]) and not covered[key] then
                    local chunk = { math.floor(x / 32), math.floor(y / 32) }
                    if surface.is_chunk_generated(chunk) then
                        local tile = surface.get_tile(x, y)
                        if tile and tile.valid and tile.name ~= "out-of-map" then
                            old_open = old_open + 1
                        end
                    end
                end
            end
        end
    end

    -- A few already-open cells can exist at a tunnel mouth. A true old room or
    -- substantial hall overlap is much larger and is rejected before any room
    -- tiles or contents are created.
    local allowance = math.max(20, math.floor(total * 0.08))
    return old_open > allowance
end

local function room_plan_has_player_entities(surface, plan)
    local entities = surface.find_entities_filtered {
        area = { { plan.x1, plan.y1 }, { plan.x2 + 1, plan.y2 + 1 } },
    }
    for _, entity in pairs(entities or {}) do
        if entity.valid and (not plan.shape or room_plan_contains(plan, math.floor(entity.position.x), math.floor(entity.position.y))) then
            local force_name = entity.force and entity.force.name or "neutral"
            if force_name ~= "neutral" and force_name ~= "enemy" then return true end
            if entity.type == "character" or entity.type == "car" or entity.type == "spider-vehicle"
                or entity.type == "locomotive" or entity.type == "cargo-wagon"
                or entity.type == "fluid-wagon" or entity.type == "artillery-wagon" then
                return true
            end
        end
    end
    return false
end

function caverns._room_plan_is_clear_of_main_train(surface, plan)
    local x1, y1, x2, y2 = caverns.placement.plan_bounds(plan, plan.has_entrance)
    if not caverns.placement.area_is_playable(surface, x1, y1, x2, y2) then return false end
    local api = caverns.train_safety_api
    assert(api and type(api.cave_area_is_safe) == "function",
        "The Cave: Train Interiors cave-safety API was not configured")
    return api.cave_area_is_safe(surface, {
        { x1, y1 },
        { x2 + 1, y2 + 1 },
    }) == true
end

local function register_room_plan(surface_index, plan, region)
    local list = room_footprints_for_surface(surface_index)
    local x1, y1, x2, y2 = caverns.placement.plan_bounds(plan, plan.has_entrance)
    list[#list + 1] = {
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        cx = plan.cx,
        cy = plan.cy,
        shape = plan.shape,
        region = region,
        created_tick = game and game.tick or 0,
    }
    return list[#list]
end

local function carve_rect(surface, x1, y1, x2, y2, force, carved, skip_vein, opened)
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end
    for x = x1, x2 do
        for y = y1, y2 do
            carve_tile(surface, x, y, force, carved, skip_vein, opened)
        end
    end
end

local function carve_room_shape(surface, cx, cy, radius, seed, force, carved, skip_vein, opened, forced_shape, exact_plan)
    if exact_plan then
        for x = exact_plan.x1, exact_plan.x2 do
            for y = exact_plan.y1, exact_plan.y2 do
                if room_plan_contains(exact_plan, x, y) then
                    carve_tile(surface, x, y, force, carved, skip_vein, opened)
                end
            end
        end
        return exact_plan.shape
    end

    local shape = forced_shape or ROOM_SHAPES[hash.range(seed, cx, cy, S_SHAPE, 1, #ROOM_SHAPES)] or "circle"

    if shape == "circle" then
        carve_disc(surface, cx, cy, radius, force, carved, skip_vein, opened)
        return shape
    end

    if shape == "square" then
        -- Square area is kept close to the old disc area.
        local half = math.max(4, math.floor(radius * 0.78 + 0.5))
        carve_rect(surface, cx - half, cy - half, cx + half, cy + half, force, carved, skip_vein, opened)
        return shape
    end

    if shape == "rectangle" then
        -- Long enough to feel different, capped by radius so it cannot explode in size.
        local long = math.max(6, math.floor(radius * 1.15 + 0.5))
        local short = math.max(3, math.floor(radius * 0.50 + 0.5))
        if hash.roll(seed, cx, cy, S_SHAPE + 101) < 0.5 then
            carve_rect(surface, cx - long, cy - short, cx + long, cy + short, force, carved, skip_vein, opened)
        else
            carve_rect(surface, cx - short, cy - long, cx + short, cy + long, force, carved, skip_vein, opened)
        end
        return shape
    end

    if shape == "line" then
        -- Tunnel-like room: narrow but not map-long.
        local long = math.max(8, math.floor(radius * 1.35 + 0.5))
        local short = math.max(2, math.floor(radius * 0.28 + 0.5))
        if hash.roll(seed, cx, cy, S_SHAPE + 102) < 0.5 then
            carve_rect(surface, cx - long, cy - short, cx + long, cy + short, force, carved, skip_vein, opened)
        else
            carve_rect(surface, cx - short, cy - long, cx + short, cy + long, force, carved, skip_vein, opened)
        end
        return shape
    end

    if shape == "l" then
        -- Two capped arms sharing a corner.  This gives an L silhouette without doubling room size.
        local arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        local width = math.max(3, math.floor(radius * 0.38 + 0.5))
        local sx = hash.roll(seed, cx, cy, S_SHAPE + 103) < 0.5 and -1 or 1
        local sy = hash.roll(seed, cx, cy, S_SHAPE + 104) < 0.5 and -1 or 1
        carve_rect(surface, cx - width, cy - width, cx + sx * arm, cy + width, force, carved, skip_vein, opened)
        carve_rect(surface, cx - width, cy - width, cx + width, cy + sy * arm, force, carved, skip_vein, opened)
        return shape
    end

    if shape == "cross" then
        -- Plus-shaped room: two narrow bars crossing at the center.
        local arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        local width = math.max(2, math.floor(radius * 0.30 + 0.5))
        carve_rect(surface, cx - arm, cy - width, cx + arm, cy + width, force, carved, skip_vein, opened)
        carve_rect(surface, cx - width, cy - arm, cx + width, cy + arm, force, carved, skip_vein, opened)
        return shape
    end

    if shape == "t" then
        -- T-shaped room: one capped top bar plus a centered stem.
        -- The stem is shorter than a full second rectangle, keeping the area near
        -- the normal room budget while giving a very different silhouette.
        local arm = math.max(7, math.floor(radius * 1.05 + 0.5))
        local width = math.max(2, math.floor(radius * 0.30 + 0.5))
        local stem = math.max(6, math.floor(radius * 0.95 + 0.5))
        local dir = hash.range(seed, cx, cy, S_SHAPE + 105, 1, 4)
        if dir == 1 then
            carve_rect(surface, cx - arm, cy - width, cx + arm, cy + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - width, cy, cx + width, cy + stem, force, carved, skip_vein, opened)
        elseif dir == 2 then
            carve_rect(surface, cx - arm, cy - width, cx + arm, cy + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - width, cy - stem, cx + width, cy, force, carved, skip_vein, opened)
        elseif dir == 3 then
            carve_rect(surface, cx - width, cy - arm, cx + width, cy + arm, force, carved, skip_vein, opened)
            carve_rect(surface, cx, cy - width, cx + stem, cy + width, force, carved, skip_vein, opened)
        else
            carve_rect(surface, cx - width, cy - arm, cx + width, cy + arm, force, carved, skip_vein, opened)
            carve_rect(surface, cx - stem, cy - width, cx, cy + width, force, carved, skip_vein, opened)
        end
        return shape
    end

    if shape == "u" then
        -- U-shaped room: two short legs joined by one capped bar.
        -- Leg width/gap are radius-based so the U reads clearly without becoming
        -- a huge hollow rectangle.
        local arm = math.max(7, math.floor(radius * 0.95 + 0.5))
        local width = math.max(2, math.floor(radius * 0.28 + 0.5))
        local gap = math.max(4, math.floor(radius * 0.55 + 0.5))
        local dir = hash.range(seed, cx, cy, S_SHAPE + 106, 1, 4)
        if dir == 1 then
            carve_rect(surface, cx - gap - width, cy - width, cx + gap + width, cy + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - gap - width, cy - arm, cx - gap + width, cy + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx + gap - width, cy - arm, cx + gap + width, cy + width, force, carved, skip_vein, opened)
        elseif dir == 2 then
            carve_rect(surface, cx - gap - width, cy - width, cx + gap + width, cy + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - gap - width, cy - width, cx - gap + width, cy + arm, force, carved, skip_vein, opened)
            carve_rect(surface, cx + gap - width, cy - width, cx + gap + width, cy + arm, force, carved, skip_vein, opened)
        elseif dir == 3 then
            carve_rect(surface, cx - width, cy - gap - width, cx + width, cy + gap + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - arm, cy - gap - width, cx + width, cy - gap + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - arm, cy + gap - width, cx + width, cy + gap + width, force, carved, skip_vein, opened)
        else
            carve_rect(surface, cx - width, cy - gap - width, cx + width, cy + gap + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - width, cy - gap - width, cx + arm, cy - gap + width, force, carved, skip_vein, opened)
            carve_rect(surface, cx - width, cy + gap - width, cx + arm, cy + gap + width, force, carved, skip_vein, opened)
        end
        return shape
    end

    if shape == "double" then
        -- Double room: two smaller lobes with a short connector.
        -- This is intentionally a little larger than normal shapes for readability,
        -- but the two lobe radius and spacing are capped so it cannot become a
        -- giant two-room cavern.
        local lobe = math.max(4, math.floor(radius * 0.58 + 0.5))
        local gap = math.max(5, math.floor(radius * 0.78 + 0.5))
        local corridor = math.max(1, math.floor(radius * 0.18 + 0.5))
        if hash.roll(seed, cx, cy, S_SHAPE + 107) < 0.5 then
            carve_disc(surface, cx - gap, cy, lobe, force, carved, skip_vein, opened)
            carve_disc(surface, cx + gap, cy, lobe, force, carved, skip_vein, opened)
            carve_rect(surface, cx - gap, cy - corridor, cx + gap, cy + corridor, force, carved, skip_vein, opened)
        else
            carve_disc(surface, cx, cy - gap, lobe, force, carved, skip_vein, opened)
            carve_disc(surface, cx, cy + gap, lobe, force, carved, skip_vein, opened)
            carve_rect(surface, cx - corridor, cy - gap, cx + corridor, cy + gap, force, carved, skip_vein, opened)
        end
        return shape
    end

    carve_disc(surface, cx, cy, radius, force, carved, skip_vein, opened)
    return "circle"
end

-- Spawn `count` worms scattered across the room; returns their unit_numbers.
-- Every non-Uranium-Cave room keeps at least one guardian — its death is what
-- arms the ceiling, so an unguarded pre-collapse can never greet a breach.
local function spawn_worms(surface, cx, cy, radius, seed, count, bob_family)
    local evolution = cave_evolution.factor(surface)
    local tier = dig_spawner.tier_for(evolution)
    local center = { cx + 0.5, cy + 0.5 }
    local worm_ids = {}
    for i = 1, count do
        local worm_name = bob_family and caverns.bob_enemies.pick_worm(bob_family, evolution,
            hash.roll(seed, cx, cy, caverns.bob_enemies.worm_stream + i * 100)) or tier.worm
        local target = {
            cx + 0.5 + hash.range(seed, cx, cy, S_CONTENT + 50 + i, -radius + 2, radius - 2),
            cy + 0.5 + hash.range(seed, cx, cy, S_CONTENT + 60 + i, -radius + 2, radius - 2),
        }
        local spot = surface.find_non_colliding_position(worm_name, target, 4, 0.5)
            or surface.find_non_colliding_position(worm_name, center, radius, 0.5)
        if spot then
            local worm = surface.create_entity { name = worm_name, position = spot, force = "enemy" }
            if worm then
                caverns.bob_enemies.protect_scripted_base_part(worm)
                worm_ids[#worm_ids + 1] = worm.unit_number
            end
        end
    end
    return worm_ids
end

-- Fixed zone threat budgets replace the old runaway room scaling. In 2.5.53
-- the global The Cave Difficulty scales only mobile defenders and then clamps
-- them to CPU-safe caps (10/18/28/35). Static nests and worms are unchanged.
local ROOM_THREAT_BUDGETS = {
    easy =      { nest = 9,  infested = 12, treasure = 6,  nuclear = 6,  boss = 12, hoard = 6  },
    medium =    { nest = 12, infested = 15, treasure = 8,  nuclear = 8,  boss = 16, hoard = 8  },
    hard =      { nest = 18, infested = 24, treasure = 12, nuclear = 12, boss = 24, hoard = 12 },
    nightmare = { nest = 24, infested = 30, treasure = 16, nuclear = 16, boss = 32, hoard = 16 },
}

local ROOM_STATIC_DEFENCES = {
    easy =      { nest_spawners = 3, nest_worms = 2, infested_worms = 1, boss_worms = 1 },
    medium =    { nest_spawners = 3, nest_worms = 3, infested_worms = 1, boss_worms = 1 },
    hard =      { nest_spawners = 3, nest_worms = 4, infested_worms = 1, boss_worms = 2 },
    nightmare = { nest_spawners = 3, nest_worms = 5, infested_worms = 2, boss_worms = 2 },
}

local function room_budget(profile, kind)
    local row = ROOM_THREAT_BUDGETS[profile.level_id or "easy"] or ROOM_THREAT_BUDGETS.easy
    return depth_levels.scale_mobile_enemy_count(row[kind] or 0)
end

local function room_defences(profile)
    return ROOM_STATIC_DEFENCES[profile.level_id or "easy"] or ROOM_STATIC_DEFENCES.easy
end

local REWARD_ZONE_MULTIPLIER = { easy = 1, medium = 2, hard = 3, nightmare = 4 }
local function reward_zone_multiplier(profile)
    return REWARD_ZONE_MULTIPLIER[profile.level_id or "easy"] or 1
end

-- The Cave 2.0.11: room contents are now identity-driven.
-- The old normal/dangerous worm tables made almost every early room a worm room.
-- Keep the existing depth/zone detection, but let each room type define its own core.
local RADIUS_BONUS = {
    easy = 0,
    medium = 1,
    hard = 2,
    nightmare = 3,
}

local function cavern_profile(surface, seed, cx, cy)
    local level = depth_levels.level_for_surface_position(surface, { x = cx, y = cy })
    return {
        level = level,
        level_id = level.id or "easy",
        dangerous = false,
    }
end

local function radius_bonus_for(profile)
    return RADIUS_BONUS[profile.level_id] or 0
end

-- The Cave v1.5.0: Special Caverns.
-- These do not replace the normal cave system; they add personality to some
-- freshly opened rooms so cave exploration feels less repetitive.
local SPECIAL_CAVERN_CHANCE = {
    easy = 0.10,
    medium = 0.18,
    hard = 0.28,
    nightmare = 0.40,
}

local SPECIAL_CAVERN_WEIGHTS = {
    easy = {
        { kind = "resource", weight = 70 },
        { kind = "treasure", weight = 30 },
    },
    medium = {
        { kind = "resource", weight = 25 },
        { kind = "treasure", weight = 25 },
        { kind = "infested", weight = 20 },
        { kind = "nuclear", weight = 20 },
        { kind = "none", weight = 10 },
    },
    hard = {
        { kind = "treasure", weight = 20 },
        { kind = "infested", weight = 25 },
        { kind = "nuclear", weight = 20 },
        { kind = "boss", weight = 10 },
        { kind = "none", weight = 25 }, -- preserves pre-vault special-room balance
    },
    nightmare = {
        { kind = "treasure", weight = 15 },
        { kind = "infested", weight = 20 },
        { kind = "nuclear", weight = 20 },
        { kind = "boss", weight = 20 },
        { kind = "none", weight = 25 }, -- preserves pre-vault special-room balance
    },
}

-- Nuclear Caverns stay in the ordinary repeatable Special Cavern roll, but
-- their fixed reward and defence package now scales with the depth zone. The
-- mobile ranges below are the Medium global-difficulty baseline; the shared
-- mobile-enemy multiplier/cap still honours the selected global difficulty.
local NUCLEAR_CAVERN_LEVELS = {
    medium = {
        uranium_235 = 5,
        uranium_238 = 50,
        uranium_fuel_cells = 20,
        gun_turrets = 4,
        laser_turrets = 4,
        worms = 2,
        mobile_min = 8,
        mobile_max = 10,
    },
    hard = {
        uranium_235 = 10,
        uranium_238 = 75,
        uranium_fuel_cells = 35,
        gun_turrets = 6,
        laser_turrets = 6,
        worms = 4,
        mobile_min = 14,
        mobile_max = 18,
    },
    nightmare = {
        uranium_235 = 15,
        uranium_238 = 100,
        uranium_fuel_cells = 40,
        gun_turrets = 8,
        laser_turrets = 8,
        worms = 6,
        mobile_min = 22,
        mobile_max = 28,
    },
}

-- Fortified Research Vault discovery rate. The independent roll is now close
-- to Uranium Cave frequency so normal exploration can reliably discover the
-- raid, while a completed-room cooldown and spatial separation still prevent
-- back-to-back vaults on the same surface.
local FORTRESS_CAVERN_CHANCE = {
    medium = 0.10,
    hard = 0.15,
    nightmare = 0.20,
}
local FORTRESS_MIN_COMPLETED_ROOMS = 6
local FORTRESS_MIN_DISTANCE = 160
local FORTRESS_MIN_DISTANCE_SQUARED = FORTRESS_MIN_DISTANCE * FORTRESS_MIN_DISTANCE
local S_FORTRESS = 4951

local COMBAT_ROOM_COOLDOWNS = {
    default = 1,
    gleba = 2,
    vulcanus = 2,
}
local COMBAT_BASE_ROOMS = { nest = true, arachnid = true, hoard = true }
local COMBAT_SPECIAL_ROOMS = { treasure = true, infested = true, nuclear = true, boss = true, fortress = true }

local function combat_cooldown_key(surface_index, region)
    return tostring(surface_index) .. ":" .. tostring(region or "nauvis")
end

local function combat_cooldown_state(surface_index, region)
    storage.cavern_combat_cooldowns = storage.cavern_combat_cooldowns or {}
    local remaining = tonumber(storage.cavern_combat_cooldowns[combat_cooldown_key(surface_index, region)]) or 0
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function room_selection_is_combat(picked, special)
    if special then return COMBAT_SPECIAL_ROOMS[special] == true end
    return picked and COMBAT_BASE_ROOMS[picked.kind] == true or false
end

local function apply_combat_room_cooldown(surface_index, region, picked, special)
    if combat_cooldown_state(surface_index, region) > 0 and room_selection_is_combat(picked, special) then
        return { kind = "empty", min_depth = 0, weight = 0 }, nil, false
    end
    return picked, special, room_selection_is_combat(picked, special)
end

local function record_room_combat_result(surface_index, region, is_combat)
    storage.cavern_combat_cooldowns = storage.cavern_combat_cooldowns or {}
    local key = combat_cooldown_key(surface_index, region)
    local remaining = combat_cooldown_state(surface_index, region)
    if is_combat then
        storage.cavern_combat_cooldowns[key] = COMBAT_ROOM_COOLDOWNS[region] or COMBAT_ROOM_COOLDOWNS.default
    elseif remaining > 1 then
        storage.cavern_combat_cooldowns[key] = remaining - 1
    else
        storage.cavern_combat_cooldowns[key] = nil
    end
end

local function extraction_nest_pacing(surface_index)
    storage.cavern_extraction_nest_pacing = storage.cavern_extraction_nest_pacing or {}
    local state = storage.cavern_extraction_nest_pacing[surface_index]
    if not state then
        state = { empty_streak = 0 }
        storage.cavern_extraction_nest_pacing[surface_index] = state
    end
    state.empty_streak = math.max(0, math.min(EXTRACTION_EMPTY_ROOM_GUARANTEE,
        tonumber(state.empty_streak) or 0))
    return state
end

local function extraction_nest_has_capacity(surface)
    local live = surface.count_entities_filtered {
        type = "unit-spawner",
        force = "enemy",
        limit = EXTRACTION_LIVE_SPAWNER_CAP,
    }
    return live + EXTRACTION_NEST_ROOM_SPAWNER_COUNT <= EXTRACTION_LIVE_SPAWNER_CAP
end

local function record_extraction_room_result(surface_index, is_nest)
    local state = extraction_nest_pacing(surface_index)
    if is_nest then
        state.empty_streak = 0
    else
        state.empty_streak = math.min(EXTRACTION_EMPTY_ROOM_GUARANTEE,
            state.empty_streak + 1)
    end
end

local function fortress_generation_state(surface_index)
    storage.fortified_vault_generation = storage.fortified_vault_generation or {}
    local state = storage.fortified_vault_generation[surface_index]
    if not state then
        state = { completed_rooms = 0, last_fortress_room = nil, positions = {} }
        storage.fortified_vault_generation[surface_index] = state
    end
    state.completed_rooms = tonumber(state.completed_rooms) or 0
    state.positions = state.positions or {}
    return state
end

local function fortress_spacing_allows(surface_index, cx, cy)
    local state = fortress_generation_state(surface_index)
    local next_room = state.completed_rooms + 1
    if state.last_fortress_room
        and next_room - state.last_fortress_room <= FORTRESS_MIN_COMPLETED_ROOMS then
        return false
    end

    for _, position in pairs(state.positions) do
        local dx = cx - position.x
        local dy = cy - position.y
        if dx * dx + dy * dy < FORTRESS_MIN_DISTANCE_SQUARED then
            return false
        end
    end
    return true
end

local function record_completed_cavern(surface_index, cx, cy, special)
    local state = fortress_generation_state(surface_index)
    state.completed_rooms = state.completed_rooms + 1
    if special == "fortress" then
        state.last_fortress_room = state.completed_rooms
        state.positions[#state.positions + 1] = { x = cx, y = cy }
    end
end

local function pick_weighted_special(seed, cx, cy, profile, surface_index, scheduled_zone)
    local fortress_chance = not scheduled_zone and FORTRESS_CAVERN_CHANCE[profile.level_id] or 0
    if fortress_chance > 0
        and fortified_vaults.enabled()
        and fortress_spacing_allows(surface_index, cx, cy)
        and hash.roll(seed, cx, cy, S_FORTRESS) < fortress_chance then
        return "fortress"
    end

    local chance = SPECIAL_CAVERN_CHANCE[profile.level_id] or 0
    if hash.roll(seed, cx, cy, S_SPECIAL) >= chance then return nil end

    local pool = SPECIAL_CAVERN_WEIGHTS[profile.level_id] or SPECIAL_CAVERN_WEIGHTS.easy
    local total = 0
    for _, spec in ipairs(pool) do total = total + spec.weight end

    local roll = hash.roll(seed, cx, cy, S_SPECIAL_CONTENT) * total
    for _, spec in ipairs(pool) do
        roll = roll - spec.weight
        if roll <= 0 then
            return spec.kind == "none" and nil or spec.kind
        end
    end
    local fallback = pool[#pool].kind
    return fallback == "none" and nil or fallback
end

local function spawn_special_ore_patch(surface, cx, cy, radius, seed, ore_name, count, amount_min, amount_max)
    for i = 1, count do
        local x = cx + hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 100 + i, -radius + 2, radius - 2)
        local y = cy + hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 200 + i, -radius + 2, radius - 2)
        local tile = surface.get_tile(x, y)
        if tile and tile.valid and not tile.name:find("water", 1, true) then
            surface.create_entity {
                name = ore_name,
                position = { x + 0.5, y + 0.5 },
                amount = hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 300 + i, amount_min, amount_max),
            }
        end
    end
end

local function spawn_special_chests(surface, cx, cy, radius, seed, depth, count)
    for i = 1, count do
        local x = cx + hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 400 + i, -radius + 2, radius - 2)
        local y = cy + hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 500 + i, -radius + 2, radius - 2)
        treasure.spawn_chest(surface, x, y, depth)
    end
end

local function spawn_special_spawners(surface, cx, cy, radius, seed, count)
    local center = { cx + 0.5, cy + 0.5 }
    for i = 1, count do
        local kind = hash.roll(seed, cx, cy, S_SPECIAL_CONTENT + 600 + i) < 0.5 and "biter-spawner" or "spitter-spawner"
        local target = {
            cx + 0.5 + hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 700 + i, -radius + 2, radius - 2),
            cy + 0.5 + hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 800 + i, -radius + 2, radius - 2),
        }
        local spot = surface.find_non_colliding_position(kind, target, 6, 0.5)
            or surface.find_non_colliding_position(kind, center, radius, 0.5)
        if spot then
            caverns.bob_enemies.protect_scripted_base_part(
                surface.create_entity { name = kind, position = spot, force = "enemy" }
            )
        end
    end
end

local function item_exists(name)
    return prototypes and prototypes.item and prototypes.item[name] ~= nil
end

local function entity_exists(name)
    return prototypes and prototypes.entity and prototypes.entity[name] ~= nil
end

local function stack_size(name)
    if item_exists(name) then return prototypes.item[name].stack_size or 50 end
    return 50
end

local function insert_stacks(chest, name, slots)
    if not chest or not chest.valid or slots <= 0 or not item_exists(name)
        or not reward_policy.is_allowed(name) then return end
    chest.insert { name = name, count = stack_size(name) * slots }
end

local function insert_count(chest, name, count)
    if not chest or not chest.valid or count <= 0 or not item_exists(name)
        or not reward_policy.is_allowed(name) then return end
    chest.insert { name = name, count = count }
end

local function random_point(seed, cx, cy, radius, stream, i)
    return {
        cx + 0.5 + hash.range(seed, cx, cy, stream + i * 2, -radius + 2, radius - 2),
        cy + 0.5 + hash.range(seed, cx, cy, stream + i * 2 + 1, -radius + 2, radius - 2),
    }
end

local function spawn_units_of_kind(surface, cx, cy, radius, seed, kind, count, stream)
    if count <= 0 then return end
    local tier = dig_spawner.tier_for(cave_evolution.factor(surface))
    local name = kind == "spitter" and tier.spitter or tier.biter
    local center = { cx + 0.5, cy + 0.5 }
    for i = 1, count do
        local target = random_point(seed, cx, cy, radius, stream, i)
        local spot = surface.find_non_colliding_position(name, target, 4, 0.5)
            or surface.find_non_colliding_position(name, center, radius, 0.5)
        if spot then surface.create_entity { name = name, position = spot, force = "enemy" } end
    end
end

local function spawn_mixed_units(surface, cx, cy, radius, seed, total, stream)
    if total <= 0 then return end
    local biters = math.ceil(total * 0.70)
    local spitters = total - biters
    spawn_units_of_kind(surface, cx, cy, radius, seed, "biter", biters, stream)
    spawn_units_of_kind(surface, cx, cy, radius, seed, "spitter", spitters, stream + 500)
end

local function regional_biter_share(region)
    if region == "gleba" then return 0.60 end
    if region == "vulcanus" then return 0.72 end
    return 1.00
end

local function spawn_region_balanced_units(surface, cx, cy, radius, seed, total, stream, region)
    if total <= 0 then return end
    local biter_total = math.max(1, math.floor(total * regional_biter_share(region) + 0.5))
    spawn_mixed_units(surface, cx, cy, radius, seed, biter_total, stream)
    if region == "gleba" then
        region_features.spawn_gleba_room_pack(surface, cx, cy, radius, seed, stream + 900)
    end
end

local ARMOURED_NEST = "armoured-biter-spawner"

-- Enemy Nest Rooms always contain exactly one nest for each of The Cave's
-- three Nauvis enemy families. Armoured first ensures its larger footprint is
-- reserved before the two vanilla nests are placed.
local NEST_ROOM_SPAWNERS = {
    ARMOURED_NEST,
    "biter-spawner",
    "spitter-spawner",
}

local NEST_ROOM_OFFSETS = {
    { x = 0,  y = -5 },
    { x = -5, y = 4 },
    { x = 5,  y = 4 },
}

local function spawn_room_spawners(surface, cx, cy, radius, names)
    local center = { cx + 0.5, cy + 0.5 }
    local spawned = 0
    for i, kind in ipairs(names or NEST_ROOM_SPAWNERS) do
        local offset = NEST_ROOM_OFFSETS[i]
        local target = { cx + 0.5 + offset.x, cy + 0.5 + offset.y }
        local spot = surface.find_non_colliding_position(kind, target, 3, 0.25)
            or surface.find_non_colliding_position(kind, center, math.max(3, radius - 2), 0.25)
        if spot then
            local spawner = surface.create_entity { name = kind, position = spot, force = "enemy" }
            if spawner and spawner.valid then
                caverns.bob_enemies.protect_scripted_base_part(spawner)
                spawned = spawned + 1
            end
        end
    end
    return spawned
end

local ARACHNID_SPAWNER = "arachnid-spawner-unitspawner"

-- A dedicated Arachnid Nest never mixes in vanilla, Armoured or regional
-- enemies. Its three spawners double as collapse guardians. Like an ordinary
-- Nest Room, it is eligible to release the zone's one living Arachnid Queen.
local function populate_arachnid_nest(surface, cx, cy, radius, seed, profile)
    local center = { cx + 0.5, cy + 0.5 }
    local guardian_ids = {}
    for i, offset in ipairs(NEST_ROOM_OFFSETS) do
        local target = { cx + 0.5 + offset.x, cy + 0.5 + offset.y }
        local spot = surface.find_non_colliding_position(ARACHNID_SPAWNER, target, 3, 0.25)
            or surface.find_non_colliding_position(
                ARACHNID_SPAWNER, center, math.max(3, radius - 2), 0.25
            )
        if spot then
            local spawner = surface.create_entity {
                name = ARACHNID_SPAWNER,
                position = spot,
                force = "enemy",
            }
            if spawner and spawner.valid and spawner.unit_number then
                caverns.bob_enemies.protect_scripted_base_part(spawner)
                guardian_ids[#guardian_ids + 1] = spawner.unit_number
            end
        end
    end

    if #guardian_ids == 3 then
        enemy_nest_growth.try_spawn_queen(
            surface, center, radius, profile.level_id or "easy"
        )
    end

    return guardian_ids
end

local function register_enemy_guard(entity)
    if not (storage and entity and entity.valid) then return end
    storage.the_cave_enemy_guard_turrets = storage.the_cave_enemy_guard_turrets or {}
    storage.the_cave_enemy_guard_turrets[#storage.the_cave_enemy_guard_turrets + 1] = {
        turret = entity,
        name = entity.name,
    }
end

local function refill_enemy_gun_turret(turret)
    if not (turret and turret.valid and turret.name == "gun-turret" and turret.force and turret.force.name == "enemy") then return end
    local inv = turret.get_inventory(defines.inventory.turret_ammo)
    if not inv then return end

    -- Keep generated enemy guard turrets effectively unlimited without changing
    -- vanilla prototypes. The inventory is topped up often enough that the
    -- turret should never enter the empty-ammo state during combat.
    local ammo = inv.get_item_count("firearm-magazine")
    if ammo < 100 then
        inv.insert { name = "firearm-magazine", count = 200 - ammo }
    end
end

local function spawn_enemy_turrets(surface, cx, cy, radius, seed, gun_count, laser_count, stream)
    local center = { cx + 0.5, cy + 0.5 }
    for i = 1, gun_count do
        local name = "gun-turret"
        local target = random_point(seed, cx, cy, radius, stream, i)
        local spot = surface.find_non_colliding_position(name, target, 5, 0.5)
            or surface.find_non_colliding_position(name, center, radius, 0.5)
        if spot then
            local turret = surface.create_entity { name = name, position = spot, force = "enemy" }
            if turret and turret.valid then
                turret.insert { name = "firearm-magazine", count = 1000 }
                register_enemy_guard(turret)
            end
        end
    end
    for i = 1, laser_count do
        local name = ENEMY_LASER_TURRET
        if entity_exists(name) then
            local target = random_point(seed, cx, cy, radius, stream + 500, i)
            local spot = surface.find_non_colliding_position(name, target, 5, 0.5)
                or surface.find_non_colliding_position(name, center, radius, 0.5)
            if spot then
                -- The dedicated enemy laser uses a void energy source. It fires
                -- normally but never creates or joins an electric network.
                surface.create_entity { name = name, position = spot, force = "enemy" }
            end
        end
    end
end

local function spawn_steel_chest(surface, cx, cy, radius, seed, stream, i)
    local name = "steel-chest"
    local center = { cx + 0.5, cy + 0.5 }
    local target = random_point(seed, cx, cy, radius, stream, i)
    local spot = surface.find_non_colliding_position(name, target, 5, 0.5)
        or surface.find_non_colliding_position(name, center, radius, 0.5)
    if not spot then return nil end
    return surface.create_entity { name = name, position = spot, force = "neutral" }
end

local function fill_sanctuary_chest(chest, seed, cx, cy, i)
    local pool = {
        { name = "firearm-magazine", min = 20, max = 50 },
        { name = "grenade", min = 4, max = 10 },
        { name = "repair-pack", min = 4, max = 10 },
        { name = "raw-fish", min = 5, max = 15 },
        { name = "coal", min = 30, max = 60 },
    }
    for pick = 1, 3 do
        local item = pool[hash.range(seed, cx, cy, S_CONTENT + 1000 + i * 10 + pick, 1, #pool)]
        insert_count(chest, item.name, hash.range(seed, cx, cy, S_CONTENT + 1100 + i * 10 + pick, item.min, item.max))
    end
end

local function fill_hoard_chest(chest, seed, cx, cy, i)
    local pool = {
        { name = "iron-plate", min = 10, max = 30 },
        { name = "copper-plate", min = 10, max = 30 },
        { name = "steel-plate", min = 5, max = 15 },
        { name = "repair-pack", min = 3, max = 8 },
        { name = "firearm-magazine", min = 20, max = 50 },
        { name = "piercing-rounds-magazine", min = 8, max = 20 },
        { name = "grenade", min = 3, max = 8 },
        { name = "coal", min = 20, max = 50 },
        { name = "solid-fuel", min = 5, max = 15 },
    }
    for pick = 1, 8 do
        local item = pool[hash.range(seed, cx, cy, S_CONTENT + 1300 + i * 10 + pick, 1, #pool)]
        insert_count(chest, item.name,
            2 * hash.range(seed, cx, cy, S_CONTENT + 1400 + i * 10 + pick, item.min, item.max))
    end
end

-- These are guaranteed room-wide bundles, not per-chest rolls. The original
-- basic Hoard loot above remains intact, while the stronger progression loot
-- scales in small controlled steps across the four depth zones.
local HOARD_REWARD_PROFILES = {
    easy = {
        module_level = 1, module_min = 2, module_max = 3,
        belts = {
            { "transport-belt", 20, 30 }, { "fast-transport-belt", 20, 30 },
            { "underground-belt", 4, 5 }, { "fast-underground-belt", 4, 5 },
            { "splitter", 4, 5 }, { "fast-splitter", 4, 5 },
        },
        inserter_min = 3, inserter_max = 4,
        science_min = 20, science_max = 30,
        reward_turret_min = 1, reward_turret_max = 2,
    },
    medium = {
        module_level = 2, module_min = 4, module_max = 5,
        belts = {
            { "transport-belt", 30, 40 }, { "fast-transport-belt", 30, 40 },
            { "underground-belt", 5, 6 }, { "fast-underground-belt", 5, 6 },
            { "splitter", 5, 6 }, { "fast-splitter", 5, 6 },
        },
        inserter_min = 4, inserter_max = 5,
        uranium = {
            { "uranium-235", 1, 1 }, { "uranium-238", 1, 1 }, { "uranium-fuel-cell", 1, 1 },
        },
        science_min = 35, science_max = 50,
        reward_turret_min = 3, reward_turret_max = 4,
    },
    hard = {
        module_level = 2, module_min = 6, module_max = 7,
        belts = {
            { "transport-belt", 40, 50 }, { "fast-transport-belt", 40, 50 },
            { "express-transport-belt", 20, 30 },
            { "underground-belt", 6, 8 }, { "fast-underground-belt", 6, 8 },
            { "express-underground-belt", 3, 5 },
            { "splitter", 6, 8 }, { "fast-splitter", 6, 8 }, { "express-splitter", 3, 5 },
        },
        inserter_min = 5, inserter_max = 7,
        uranium = {
            { "uranium-235", 2, 3 }, { "uranium-238", 2, 3 }, { "uranium-fuel-cell", 2, 3 },
        },
        science_min = 55, science_max = 75,
        reward_turret_min = 5, reward_turret_max = 7,
    },
    nightmare = {
        module_level = 3, module_min = 8, module_max = 10,
        belts = {
            { "transport-belt", 50, 60 }, { "fast-transport-belt", 50, 60 },
            { "express-transport-belt", 30, 40 },
            { "underground-belt", 8, 10 }, { "fast-underground-belt", 8, 10 },
            { "express-underground-belt", 5, 7 },
            { "splitter", 8, 10 }, { "fast-splitter", 8, 10 }, { "express-splitter", 5, 7 },
            -- Space Age turbo items are prototype-gated and disappear cleanly
            -- from this bundle when only base Factorio is loaded.
            { "turbo-transport-belt", 15, 20 }, { "turbo-underground-belt", 2, 4 },
            { "turbo-splitter", 2, 4 },
        },
        inserter_min = 7, inserter_max = 9,
        uranium = {
            { "uranium-235", 4, 5 }, { "uranium-238", 4, 5 }, { "uranium-fuel-cell", 5, 6 },
        },
        science_min = 80, science_max = 100,
        reward_turret_min = 6, reward_turret_max = 10,
    },
}

local HOARD_MODULE_BASES = { "speed-module", "productivity-module", "efficiency-module", "quality-module" }
local HOARD_INSERTERS = {
    "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter", "stack-inserter",
}
local HOARD_SCIENCE_PACKS = {
    { item = "automation-science-pack", starting = true },
    { item = "logistic-science-pack", technologies = { "logistic-science-pack" } },
    { item = "military-science-pack", technologies = { "military-science-pack" } },
    { item = "chemical-science-pack", technologies = { "chemical-science-pack" } },
    { item = "production-science-pack", technologies = { "production-science-pack" } },
    { item = "utility-science-pack", technologies = { "utility-science-pack" } },
    { item = "space-science-pack", technologies = { "space-science-pack", "rocket-silo" } },
    { item = "metallurgic-science-pack", technologies = { "metallurgic-science-pack" } },
    { item = "agricultural-science-pack", technologies = { "agricultural-science-pack" } },
    { item = "electromagnetic-science-pack", technologies = { "electromagnetic-science-pack" } },
    { item = "cryogenic-science-pack", technologies = { "cryogenic-science-pack" } },
    { item = "promethium-science-pack", technologies = { "promethium-science-pack" } },
}

local function module_item_name(base, level)
    if level <= 1 then return base end
    return base .. "-" .. tostring(level)
end

local function science_pack_unlocked(force, spec)
    if not (force and force.valid and spec and item_exists(spec.item)) then return false end
    if spec.starting then return true end

    -- Recipe enablement is the most direct Force-aware unlock signal and also
    -- respects compatibility mods. Technology markers cover packs such as base
    -- Space Science that can be obtained without a conventional enabled recipe.
    local recipe = force.recipes and force.recipes[spec.item]
    if recipe and recipe.enabled then return true end
    for _, technology_name in ipairs(spec.technologies or {}) do
        local technology = force.technologies and force.technologies[technology_name]
        if technology and technology.researched then return true end
    end
    return false
end

local function add_hoard_bundle(bundles, seed, cx, cy, stream, name, minimum, maximum)
    if not item_exists(name) or not reward_policy.is_allowed(name) then return end
    bundles[#bundles + 1] = {
        name = name,
        count = 2 * hash.range(seed, cx, cy, stream, minimum, maximum),
    }
end

local function build_hoard_bundles(seed, cx, cy, profile, force)
    local level_id = profile.level_id or "easy"
    local spec = HOARD_REWARD_PROFILES[level_id] or HOARD_REWARD_PROFILES.easy
    local bundles = {}

    for i, base in ipairs(HOARD_MODULE_BASES) do
        add_hoard_bundle(bundles, seed, cx, cy, S_CONTENT + 4000 + i,
            module_item_name(base, spec.module_level), spec.module_min, spec.module_max)
    end
    for i, reward in ipairs(spec.belts) do
        add_hoard_bundle(bundles, seed, cx, cy, S_CONTENT + 4200 + i,
            reward[1], reward[2], reward[3])
    end
    for i, name in ipairs(HOARD_INSERTERS) do
        add_hoard_bundle(bundles, seed, cx, cy, S_CONTENT + 4400 + i,
            name, spec.inserter_min, spec.inserter_max)
    end
    for i, reward in ipairs(spec.uranium or {}) do
        add_hoard_bundle(bundles, seed, cx, cy, S_CONTENT + 4600 + i,
            reward[1], reward[2], reward[3])
    end
    for i, science in ipairs(HOARD_SCIENCE_PACKS) do
        if science_pack_unlocked(force, science) then
            add_hoard_bundle(bundles, seed, cx, cy, S_CONTENT + 4800 + i,
                science.item, spec.science_min, math.min(100, spec.science_max))
        end
    end

    local turret_total = 2 * hash.range(seed, cx, cy, S_CONTENT + 5000,
        spec.reward_turret_min, spec.reward_turret_max)
    local laser_available = item_exists("laser-turret")
    local flame_available = item_exists("flamethrower-turret")
    if laser_available and flame_available and turret_total >= 2 then
        local laser_count = hash.range(seed, cx, cy, S_CONTENT + 5001, 1, turret_total - 1)
        bundles[#bundles + 1] = { name = "laser-turret", count = laser_count }
        bundles[#bundles + 1] = { name = "flamethrower-turret", count = turret_total - laser_count }
    elseif laser_available and flame_available then
        local name = hash.roll(seed, cx, cy, S_CONTENT + 5001) < 0.5
            and "laser-turret" or "flamethrower-turret"
        bundles[#bundles + 1] = { name = name, count = turret_total }
    elseif laser_available or flame_available then
        bundles[#bundles + 1] = {
            name = laser_available and "laser-turret" or "flamethrower-turret",
            count = turret_total,
        }
    end

    return bundles
end

local function distribute_hoard_bundles(chests, bundles, seed, cx, cy)
    if #chests <= 0 then return end
    for i, bundle in ipairs(bundles) do
        local remaining = bundle.count
        local start = hash.range(seed, cx, cy, S_CONTENT + 5200 + i, 1, #chests)
        for offset = 0, #chests - 1 do
            if remaining <= 0 then break end
            local chest = chests[((start + offset - 1) % #chests) + 1]
            if chest and chest.valid then
                -- Omitting quality deliberately creates normal-quality rewards.
                local inserted = chest.insert { name = bundle.name, count = remaining }
                remaining = remaining - (tonumber(inserted) or 0)
            end
        end
    end
end

local BOSS_REWARD_POOL = {
    -- Common/utility
    { name = "transport-belt", base = 50, weight = 18 },
    { name = "fast-transport-belt", base = 25, weight = 10 },
    { name = "express-transport-belt", base = 10, weight = 3 },
    { name = "underground-belt", base = 10, weight = 12 },
    { name = "fast-underground-belt", base = 6, weight = 7 },
    { name = "express-underground-belt", base = 4, weight = 2 },
    { name = "splitter", base = 5, weight = 10 },
    { name = "fast-splitter", base = 4, weight = 6 },
    { name = "express-splitter", base = 2, weight = 2 },
    { name = "fast-inserter", base = 10, weight = 12 },
    { name = "bulk-inserter", base = 10, weight = 5 },
    { name = "electric-mining-drill", base = 5, weight = 10 },
    { name = "steel-furnace", base = 5, weight = 10 },
    { name = "electric-furnace", base = 5, weight = 5 },
    { name = "assembling-machine-2", base = 5, weight = 10 },
    { name = "assembling-machine-3", base = 2, weight = 3 },
    { name = "medium-electric-pole", base = 20, weight = 8 },
    { name = "substation", base = 10, weight = 4 },
    { name = "construction-robot", base = 10, weight = 6 },
    { name = "logistic-robot", base = 10, weight = 4 },
    { name = "roboport", base = 1, weight = 4 },
    { name = "gun-turret", base = 2, weight = 7 },
    { name = "laser-turret", base = 1, weight = 4 },
    { name = "processing-unit", base = 10, weight = 4 },
    { name = "low-density-structure", base = 5, weight = 3 },
}

local function pick_weighted_from_pool(pool, seed, cx, cy, stream)
    local total = 0
    for _, item in pairs(pool) do
        if item_exists(item.name) and reward_policy.is_allowed(item.name) then
            total = total + (item.weight or 1)
        end
    end
    if total <= 0 then return nil end
    local roll = hash.roll(seed, cx, cy, stream) * total
    for _, item in pairs(pool) do
        if item_exists(item.name) and reward_policy.is_allowed(item.name) then
            roll = roll - (item.weight or 1)
            if roll <= 0 then return item end
        end
    end
    return nil
end

local function fill_boss_chest(chest, seed, cx, cy, profile)
    -- Boss reward scales with zone. One reward theme per chest keeps it exciting but controlled.
    local item = pick_weighted_from_pool(BOSS_REWARD_POOL, seed, cx, cy, S_SPECIAL_CONTENT + 1500)
    if not item then return end
    insert_count(chest, item.name, item.base * reward_zone_multiplier(profile))
end

local function fill_resource_chest(chest, seed, cx, cy, i)
    local ores = { "iron-ore", "copper-ore", "coal", "stone" }
    local ore = ores[((i - 1) % #ores) + 1]
    local slots = hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 1600 + i, 5, 6)
    insert_stacks(chest, ore, slots)
end

local function fill_nuclear_reward_chest(chest, item_name, count)
    -- Nuclear Caverns award processed nuclear materials only. Raw uranium ore
    -- remains exclusive to the timed Uranium Salvage Cavern expedition.
    insert_count(chest, item_name, count)
end


-- Fortified Research Vault.
-- The upper fortress is now a smaller guarded gateway. Its old six central
-- reward caches moved into a separate timed underground raid surface.
-- FortressRuins remains reference-only and is not a dependency.
local FORTRESS_LAYOUT = {
    -- Compact upper gateway only; the real battle and all rewards are below.
    medium = { radius = 15, size = 20, laser_turrets = 2, gun_turrets = 2, biters = 0, spitters = 0, worms = 0 },
    hard = { radius = 16, size = 22, laser_turrets = 4, gun_turrets = 4, biters = 2, spitters = 2, worms = 0 },
    nightmare = { radius = 17, size = 24, laser_turrets = 6, gun_turrets = 6, biters = 4, spitters = 4, worms = 0 },
}

-- Six themed pools. Each cache takes a deterministic random sample from its
-- own pool, with a room-wide duplicate guard. Hard and Nightmare select more
-- entries and use stronger quantities than Medium.
local FORTRESS_REWARD_POOLS = {
    medium = {
        {
            { "transport-belt", 100, 250 }, { "underground-belt", 20, 50 }, { "splitter", 10, 25 },
            { "fast-transport-belt", 50, 150 }, { "fast-underground-belt", 10, 30 }, { "fast-splitter", 5, 15 },
            { "inserter", 25, 75 }, { "fast-inserter", 15, 40 }, { "long-handed-inserter", 10, 25 },
        },
        {
            { "medium-electric-pole", 20, 50 }, { "big-electric-pole", 10, 25 }, { "substation", 2, 6 },
            { "solar-panel", 10, 30 }, { "accumulator", 10, 30 }, { "steam-engine", 4, 12 },
            { "battery", 25, 75 },
        },
        {
            { "electric-mining-drill", 5, 15 }, { "assembling-machine-1", 5, 15 },
            { "assembling-machine-2", 3, 10 }, { "electric-furnace", 3, 10 },
            { "chemical-plant", 2, 6 }, { "oil-refinery", 1, 3 }, { "pumpjack", 2, 6 },
        },
        {
            { "pipe", 100, 300 }, { "pipe-to-ground", 20, 60 }, { "pump", 2, 8 },
            { "storage-tank", 2, 6 }, { "iron-chest", 20, 50 }, { "steel-chest", 10, 30 },
            { "repair-pack", 25, 75 },
        },
        {
            { "gun-turret", 2, 8 }, { "laser-turret", 1, 4 }, { "firearm-magazine", 100, 300 },
            { "piercing-rounds-magazine", 50, 150 }, { "rocket", 10, 40 },
            { "solid-fuel", 50, 150 }, { "rocket-fuel", 5, 15 },
        },
        {
            { "automation-science-pack", 40, 100 }, { "logistic-science-pack", 40, 100 },
            { "military-science-pack", 25, 75 }, { "chemical-science-pack", 25, 75 },
            { "speed-module", 1, 4 }, { "efficiency-module", 1, 4 }, { "productivity-module", 1, 4 },
            { "processing-unit", 10, 30 }, { "modular-armor", 1, 1 },
            { "battery-equipment", 1, 1 }, { "energy-shield-equipment", 1, 1 },
        },
    },
    hard = {
        {
            { "fast-transport-belt", 150, 350 }, { "fast-underground-belt", 30, 80 }, { "fast-splitter", 15, 35 },
            { "express-transport-belt", 75, 200 }, { "express-underground-belt", 15, 45 },
            { "express-splitter", 8, 20 }, { "fast-inserter", 30, 80 }, { "bulk-inserter", 10, 30 },
            { "stack-inserter", 5, 15 },
        },
        {
            { "substation", 5, 12 }, { "solar-panel", 25, 70 }, { "accumulator", 25, 70 },
            { "roboport", 1, 4 }, { "steam-turbine", 2, 6 }, { "heat-exchanger", 2, 6 },
            { "electric-engine-unit", 20, 60 }, { "battery", 50, 150 },
        },
        {
            { "electric-mining-drill", 10, 30 }, { "assembling-machine-2", 8, 20 },
            { "assembling-machine-3", 2, 8 }, { "electric-furnace", 8, 20 },
            { "chemical-plant", 4, 12 }, { "oil-refinery", 2, 6 }, { "centrifuge", 1, 4 },
            { "pumpjack", 4, 12 },
        },
        {
            { "pipe", 200, 500 }, { "pipe-to-ground", 40, 100 }, { "pump", 5, 15 },
            { "storage-tank", 4, 12 }, { "steel-chest", 20, 60 }, { "passive-provider-chest", 5, 15 },
            { "storage-chest", 5, 15 }, { "logistic-robot", 10, 30 }, { "construction-robot", 10, 30 },
        },
        {
            { "gun-turret", 6, 16 }, { "laser-turret", 3, 8 }, { "flamethrower-turret", 1, 4 },
            { "uranium-rounds-magazine", 50, 150 }, { "explosive-rocket", 20, 60 },
            { "rocket-fuel", 15, 40 }, { "uranium-fuel-cell", 5, 15 }, { "uranium-238", 10, 30 },
        },
        {
            { "chemical-science-pack", 60, 150 }, { "production-science-pack", 50, 120 },
            { "utility-science-pack", 50, 120 }, { "speed-module-2", 2, 6 },
            { "efficiency-module-2", 2, 6 }, { "productivity-module-2", 2, 6 },
            { "processing-unit", 30, 80 }, { "low-density-structure", 25, 70 },
            { "power-armor", 1, 1 }, { "exoskeleton-equipment", 1, 1 },
            { "personal-roboport-equipment", 1, 1 }, { "energy-shield-mk2-equipment", 1, 1 },
        },
    },
    nightmare = {
        {
            { "express-transport-belt", 200, 500 }, { "express-underground-belt", 40, 120 },
            { "express-splitter", 20, 50 }, { "bulk-inserter", 20, 60 }, { "stack-inserter", 10, 30 },
            { "fast-inserter", 60, 150 }, { "transport-belt", 300, 700 },
        },
        {
            { "substation", 8, 20 }, { "solar-panel", 50, 120 }, { "accumulator", 50, 120 },
            { "roboport", 3, 8 }, { "steam-turbine", 4, 12 }, { "heat-exchanger", 4, 12 },
            { "centrifuge", 2, 6 }, { "electric-engine-unit", 50, 120 },
        },
        {
            { "electric-mining-drill", 20, 50 }, { "assembling-machine-3", 5, 15 },
            { "electric-furnace", 15, 40 }, { "chemical-plant", 8, 20 },
            { "oil-refinery", 4, 10 }, { "pumpjack", 8, 20 }, { "centrifuge", 3, 8 },
            { "low-density-structure", 50, 120 },
        },
        {
            { "pipe", 300, 800 }, { "pipe-to-ground", 60, 160 }, { "pump", 8, 20 },
            { "storage-tank", 8, 20 }, { "steel-chest", 30, 80 }, { "passive-provider-chest", 10, 30 },
            { "storage-chest", 10, 30 }, { "logistic-robot", 25, 70 }, { "construction-robot", 25, 70 },
        },
        {
            { "gun-turret", 10, 25 }, { "laser-turret", 5, 15 }, { "flamethrower-turret", 2, 6 },
            { "uranium-rounds-magazine", 100, 300 }, { "explosive-rocket", 50, 150 },
            { "rocket-fuel", 30, 80 }, { "nuclear-fuel", 1, 4 }, { "uranium-fuel-cell", 10, 30 },
            { "uranium-235", 1, 5 }, { "uranium-238", 20, 60 },
        },
        {
            { "production-science-pack", 100, 250 }, { "utility-science-pack", 100, 250 },
            { "space-science-pack", 75, 200 }, { "speed-module-3", 1, 4 },
            { "efficiency-module-3", 1, 4 }, { "productivity-module-3", 1, 4 },
            { "processing-unit", 75, 180 }, { "low-density-structure", 75, 180 },
            { "battery-mk2-equipment", 1, 1 }, { "energy-shield-mk2-equipment", 1, 1 },
            { "personal-roboport-mk2-equipment", 1, 1 }, { "exoskeleton-equipment", 1, 2 },
        },
    },
}

local FORTRESS_REWARD_PICKS = {
    medium = 3,
    hard = 4,
    nightmare = 5,
}

local FORTRESS_CHEST_OFFSETS = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1, 0 }, { 0, 0 }, { 1, 0 },
}

local function safe_create_entity(surface, name, position, force, search_radius)
    if not entity_exists(name) then return nil end
    local target = { x = position.x, y = position.y }
    local spot = target
    if search_radius and search_radius > 0 then
        spot = surface.find_non_colliding_position(name, target, search_radius, 0.5) or target
    end
    local ok, entity = pcall(function()
        return surface.create_entity { name = name, position = spot, force = force }
    end)
    if ok and entity and entity.valid then return entity end
    return nil
end

local function fortress_offsets(layout)
    local size = math.max(7, layout.size or (((layout.half or 1) * 2) + 1))
    local min_offset = -math.floor(size / 2)
    local max_offset = min_offset + size - 1
    return min_offset, max_offset
end

local function create_fortress_walls(surface, cx, cy, layout)
    local min_offset, max_offset = fortress_offsets(layout)
    local min_x, max_x = cx + min_offset, cx + max_offset
    local min_y, max_y = cy + min_offset, cy + max_offset

    local function is_opening(x, y)
        if (y == min_y or y == max_y) and math.abs(x - cx) <= 1 then return true end
        if (x == min_x or x == max_x) and math.abs(y - cy) <= 1 then return true end
        return false
    end

    for x = min_x, max_x do
        for _, y in pairs({ min_y, max_y }) do
            if not is_opening(x, y) then
                safe_create_entity(surface, "stone-wall", { x = x + 0.5, y = y + 0.5 }, "enemy", 0)
            end
        end
    end
    for y = min_y + 1, max_y - 1 do
        for _, x in pairs({ min_x, max_x }) do
            if not is_opening(x, y) then
                safe_create_entity(surface, "stone-wall", { x = x + 0.5, y = y + 0.5 }, "enemy", 0)
            end
        end
    end
end

local function create_enemy_guard_turret(surface, name, x, y)
    local turret = safe_create_entity(surface, name, { x = x + 0.5, y = y + 0.5 }, "enemy", 0)
    if turret and turret.valid and turret.name == "gun-turret" then
        turret.insert { name = "firearm-magazine", count = 1000 }
        register_enemy_guard(turret)
    end
    return turret
end

local function fortress_position_allowed(x, y, cx, cy, layout, placed)
    local dx, dy = x - cx, y - cy
    local min_offset, max_offset = fortress_offsets(layout)
    if dx < min_offset + 2 or dx > max_offset - 2 then return false end
    if dy < min_offset + 2 or dy > max_offset - 2 then return false end

    -- Keep the entrance itself and the pole/panel strip at y=-5 clear while
    -- still leaving enough perimeter room in the compact 20-24 tile boxes.
    if math.abs(dx) <= 3 and dy >= -7 and dy <= 3 then return false end

    -- Do not hard-block any of the four three-tile entrances.
    if math.abs(dx) <= 2 and (dy <= min_offset + 5 or dy >= max_offset - 5) then return false end
    if math.abs(dy) <= 2 and (dx <= min_offset + 5 or dx >= max_offset - 5) then return false end

    for _, pos in ipairs(placed) do
        local px, py = x - pos.x, y - pos.y
        if px * px + py * py < 6 then return false end
    end
    return true
end

local function quadrant_signs(quadrant)
    if quadrant == 1 then return -1, -1 end
    if quadrant == 2 then return 1, -1 end
    if quadrant == 3 then return -1, 1 end
    return 1, 1
end

local function find_random_fortress_position(seed, cx, cy, layout, quadrant, slot, placed)
    local sx, sy = quadrant_signs(quadrant)
    local min_offset, max_offset = fortress_offsets(layout)
    local x_min, x_max = (sx < 0) and (min_offset + 2) or 1, (sx < 0) and -1 or (max_offset - 2)
    local y_min, y_max = (sy < 0) and (min_offset + 2) or 1, (sy < 0) and -1 or (max_offset - 2)

    for attempt = 1, 100 do
        local stream = S_SPECIAL_CONTENT + 4100 + quadrant * 1000 + slot * 120 + attempt * 2
        local x = cx + hash.range(seed, cx, cy, stream, x_min, x_max)
        local y = cy + hash.range(seed, cx, cy, stream + 1, y_min, y_max)
        if fortress_position_allowed(x, y, cx, cy, layout, placed) then
            return { x = x, y = y }
        end
    end

    -- Deterministic fallback scan; normally unreachable, but guarantees the
    -- room still fills if another mod changes collision boxes.
    for dx = x_min, x_max do
        for dy = y_min, y_max do
            local x, y = cx + dx, cy + dy
            if fortress_position_allowed(x, y, cx, cy, layout, placed) then
                return { x = x, y = y }
            end
        end
    end
    return nil
end

local function spawn_fortress_defences(surface, cx, cy, seed, layout)
    local placed = {}
    local types = {}
    for i = 1, layout.laser_turrets do
        types[#types + 1] = { name = ENEMY_LASER_TURRET, key = i }
    end
    for i = 1, layout.gun_turrets do
        types[#types + 1] = { name = "gun-turret", key = 100 + i }
    end
    table.sort(types, function(a, b)
        local sa = hash.roll(seed, cx, cy, S_SPECIAL_CONTENT + 5200 + a.key)
        local sb = hash.roll(seed, cx, cy, S_SPECIAL_CONTENT + 5200 + b.key)
        if sa == sb then return a.key < b.key end
        return sa < sb
    end)

    for index, turret_type in ipairs(types) do
        local quadrant = ((index - 1) % 4) + 1
        local slot = math.floor((index - 1) / 4) + 1
        local pos = find_random_fortress_position(seed, cx, cy, layout, quadrant, slot, placed)
        if pos then
            local turret = create_enemy_guard_turret(surface, turret_type.name, pos.x, pos.y)
            if turret then placed[#placed + 1] = pos end
        end
    end
end

local function spawn_fortress_chest(surface, x, y)
    return safe_create_entity(surface, "steel-chest", { x = x + 0.5, y = y + 0.5 }, "neutral", 0)
end

local function insert_random_pool_rewards(chest, pool, picks, used_items, seed, cx, cy, stream)
    if not (chest and chest.valid) then return end
    local ranked = {}
    for i, reward in ipairs(pool or {}) do
        local name = reward[1]
        if item_exists(name) and reward_policy.is_allowed(name) and not used_items[name] then
            ranked[#ranked + 1] = {
                reward = reward,
                index = i,
                score = hash.roll(seed, cx, cy, stream + i * 17),
            }
        end
    end
    table.sort(ranked, function(a, b)
        if a.score == b.score then return a.index < b.index end
        return a.score < b.score
    end)

    local inserted = 0
    for _, entry in ipairs(ranked) do
        if inserted >= picks then break end
        local reward = entry.reward
        local count = hash.range(seed, cx, cy, stream + 500 + entry.index * 13, reward[2], reward[3])
        insert_count(chest, reward[1], count)
        used_items[reward[1]] = true
        inserted = inserted + 1
    end
end

local function add_fortress_premium_reward(chests, level, used_items, seed, cx, cy)
    local roll = hash.roll(seed, cx, cy, S_SPECIAL_CONTENT + 6900)
    local name = nil

    if level == "hard" and roll < 0.35 then
        local pool = {
            "power-armor", "exoskeleton-equipment", "personal-roboport-equipment", "energy-shield-mk2-equipment",
        }
        name = pool[hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 6901, 1, #pool)]
    elseif level == "nightmare" then
        if roll < 0.08 then
            name = "power-armor-mk2"
        elseif roll < 0.11 then
            name = "nuclear-reactor"
        elseif roll < 0.55 then
            local pool = {
                "personal-laser-defense-equipment", "fission-reactor-equipment", "battery-mk2-equipment",
                "energy-shield-mk2-equipment", "personal-roboport-mk2-equipment", "exoskeleton-equipment",
            }
            name = pool[hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 6902, 1, #pool)]
        end
    end

    -- Spidertron is intentionally never present in any fortress reward pool.
    if not name or used_items[name] or not item_exists(name)
        or not reward_policy.is_allowed(name) then return end
    local chest_index = hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 6903, 1, 6)
    insert_count(chests[chest_index], name, 1)
    used_items[name] = true
end

local function fill_unique_fortress_chests(chests, profile, seed, cx, cy)
    local level = profile.level_id
    local pools = FORTRESS_REWARD_POOLS[level] or FORTRESS_REWARD_POOLS.medium
    local picks = FORTRESS_REWARD_PICKS[level] or FORTRESS_REWARD_PICKS.medium
    local used_items = {}

    for chest_index = 1, 6 do
        insert_random_pool_rewards(
            chests[chest_index],
            pools[chest_index] or {},
            picks,
            used_items,
            seed,
            cx,
            cy,
            S_SPECIAL_CONTENT + 6100 + chest_index * 100
        )
    end
    add_fortress_premium_reward(chests, level, used_items, seed, cx, cy)
end

local function spawn_fortress_enemy(surface, name, cx, cy, layout, seed, stream, index)
    if not entity_exists(name) then return nil end
    local min_offset, max_offset = fortress_offsets(layout)
    local min_inner, max_inner = min_offset + 3, max_offset - 3
    for attempt = 1, 40 do
        local base = stream + index * 100 + attempt * 2
        local dx = hash.range(seed, cx, cy, base, min_inner, max_inner)
        local dy = hash.range(seed, cx, cy, base + 1, min_inner, max_inner)
        if not (math.abs(dx) <= 3 and math.abs(dy) <= 3) then
            local target = { x = cx + 0.5 + dx, y = cy + 0.5 + dy }
            local spot = surface.find_non_colliding_position(name, target, 3, 0.5)
            if spot then
                local spot_dx = spot.x - (cx + 0.5)
                local spot_dy = spot.y - (cy + 0.5)
                if spot_dx >= min_offset + 2 and spot_dx <= max_offset - 2
                    and spot_dy >= min_offset + 2 and spot_dy <= max_offset - 2 then
                    return safe_create_entity(surface, name, spot, "enemy", 0)
                end
            end
        end
    end
    return nil
end

local function spawn_fortress_creatures(surface, cx, cy, seed, layout, level_id)
    local biter, spitter, worm = cave_evolution.tier_names(surface)
    local names = { biter, spitter, worm }
    for i = 1, layout.biters do
        spawn_fortress_enemy(surface, names[1], cx, cy, layout, seed, S_SPECIAL_CONTENT + 7200, i)
    end
    for i = 1, layout.spitters do
        spawn_fortress_enemy(surface, names[2], cx, cy, layout, seed, S_SPECIAL_CONTENT + 7400, i)
    end
    for i = 1, layout.worms do
        -- Fortress worms are combat defenders only; they do not arm the cavern
        -- collapse system, so the player still has time to claim the loot.
        spawn_fortress_enemy(surface, names[3], cx, cy, layout, seed, S_SPECIAL_CONTENT + 7600, i)
    end
end

local function populate_research_fortress(surface, cx, cy, radius, seed, profile, force)
    local level_id = fortified_vaults.level_for_position(
        surface, { x = cx + 0.5, y = cy + 0.5 }, profile.level_id
    )
    local layout = FORTRESS_LAYOUT[level_id] or FORTRESS_LAYOUT.medium
    local vault_profile = {
        level = profile.level,
        level_id = level_id,
        dangerous = profile.dangerous,
        entrance_position = profile.entrance_position,
    }
    -- The six old central reward chests were removed. Their exact centre is now
    -- the entrance to the timed underground raid, together with the upper power
    -- connection and information display. All meaningful loot moved downstairs.
    local entrance = fortified_vaults.create_upper_entrance(surface, cx, cy, seed, vault_profile, force, layout)
    if not entrance then return end
    create_fortress_walls(surface, cx, cy, layout)

    spawn_fortress_defences(surface, cx, cy, seed, layout)
    spawn_fortress_creatures(surface, cx, cy, seed, layout, level_id)
    return entrance
end

local function actor_prefix(actor_name)
    if actor_name and actor_name ~= "" then
        return "[The Cave] " .. actor_name .. " discovered "
    end
    return "[The Cave] "
end

local function apply_special_cavern(surface, cx, cy, radius, seed, depth, profile, force, actor_name, special, room_region)
    if not special then return {}, nil end

    local worm_ids = {}
    local defence = room_defences(profile)

    if special == "resource" then
        for i = 1, 10 do
            local chest = spawn_steel_chest(surface, cx, cy, radius, seed, S_SPECIAL_CONTENT + 2000, i)
            fill_resource_chest(chest, seed, cx, cy, i)
        end
        return worm_ids, { "the-cave-runtime.room-resource-cavern" }

    elseif special == "treasure" then
        local total = room_budget(profile, "treasure")
        spawn_region_balanced_units(surface, cx, cy, radius, seed, total, S_SPECIAL_CONTENT + 2200, room_region)
        return worm_ids, { "the-cave-runtime.room-treasure-cavern" }

    elseif special == "infested" or special == "nest" then
        -- "nest" is accepted as a legacy alias, but the room identity is Infested Cavern.
        worm_ids = spawn_worms(surface, cx, cy, radius, seed, defence.infested_worms)
        spawn_region_balanced_units(surface, cx, cy, radius, seed, room_budget(profile, "infested"), S_SPECIAL_CONTENT + 2400, room_region)
        return worm_ids, { "the-cave-runtime.room-infested-cavern" }

    elseif special == "fortress" then
        -- The explicitly designed Fortified Research Vault keeps its own fixed
        -- defender table; it is already rare and independently spaced.
        local entrance = populate_research_fortress(surface, cx, cy, radius, seed, profile, force)
        return worm_ids, { "the-cave-runtime.room-fortified-research-vault" }, entrance

    elseif special == "nuclear" then
        local level = NUCLEAR_CAVERN_LEVELS[profile.level_id] or NUCLEAR_CAVERN_LEVELS.medium
        spawn_enemy_turrets(surface, cx, cy, radius, seed,
            level.gun_turrets, level.laser_turrets, S_SPECIAL_CONTENT + 2600)
        worm_ids = spawn_worms(surface, cx, cy, radius, seed, level.worms)

        local mobile_base = hash.range(seed, cx, cy, S_SPECIAL_CONTENT + 2699,
            level.mobile_min, level.mobile_max)
        local mobile_total = depth_levels.scale_mobile_enemy_count(mobile_base)
        spawn_region_balanced_units(surface, cx, cy, radius, seed, mobile_total,
            S_SPECIAL_CONTENT + 2700, room_region)

        local rewards = {
            { "uranium-235", level.uranium_235 },
            { "uranium-238", level.uranium_238 },
            { "uranium-fuel-cell", level.uranium_fuel_cells },
        }
        for i, reward in ipairs(rewards) do
            local chest = spawn_steel_chest(surface, cx, cy, radius, seed,
                S_SPECIAL_CONTENT + 2900, i)
            fill_nuclear_reward_chest(chest, reward[1], reward[2])
        end
        return worm_ids, { "the-cave-runtime.room-nuclear-cavern" }

    elseif special == "boss" then
        local gun_count = 1
        local laser_count = (profile.level_id == "hard" or profile.level_id == "nightmare") and 1 or 0
        spawn_enemy_turrets(surface, cx, cy, radius, seed, gun_count, laser_count, S_SPECIAL_CONTENT + 3000)
        worm_ids = spawn_worms(surface, cx, cy, radius, seed, defence.boss_worms)
        spawn_region_balanced_units(surface, cx, cy, radius, seed, room_budget(profile, "boss"), S_SPECIAL_CONTENT + 3100, room_region)
        local chest = spawn_steel_chest(surface, cx, cy, radius, seed, S_SPECIAL_CONTENT + 3300, 1)
        fill_boss_chest(chest, seed, cx, cy, profile)
        return worm_ids, { "the-cave-runtime.room-boss-cavern" }
    end

    return worm_ids, nil
end


local function populate_nest(surface, cx, cy, radius, seed, profile, room_region, bob_family)
    local defence = room_defences(profile)
    if bob_family and caverns.bob_enemies.active() then
        local names = caverns.bob_enemies.room_nests(bob_family, cave_evolution.factor(surface),
            hash.roll(seed, cx, cy, caverns.bob_enemies.super_stream))
        if not names then return {}, nil end
        spawn_room_spawners(surface, cx, cy, radius, names)
        return spawn_worms(surface, cx, cy, radius, seed, defence.nest_worms, bob_family), nil
    end
    local nest_count = spawn_room_spawners(surface, cx, cy, radius)
    if nest_count == #NEST_ROOM_SPAWNERS then
        enemy_nest_growth.try_spawn_queen(
            surface, { x = cx + 0.5, y = cy + 0.5 }, radius, profile.level_id or "easy"
        )
    end
    local worm_ids = spawn_worms(surface, cx, cy, radius, seed, defence.nest_worms)
    -- Do not pre-spawn a manual defender pack here. Native spawner ownership,
    -- nearby-friend limits and cooldowns now control the complete nest population.
    return worm_ids, nil
end

local HOARD_STATIC_DEFENCES = {
    easy = { gun_turrets = 2, laser_turrets = 1, worms = 1 },
    medium = { gun_turrets = 3, laser_turrets = 2, worms = 2 },
    hard = { gun_turrets = 4, laser_turrets = 3, worms = 3 },
    nightmare = { gun_turrets = 6, laser_turrets = 4, worms = 4 },
}

local function populate_hoard(surface, cx, cy, radius, seed, depth, profile, room_region, force)
    local chest_count = 14
    local chests = {}
    local attempt = 0
    while #chests < chest_count and attempt < chest_count * 10 do
        attempt = attempt + 1
        local chest = spawn_steel_chest(surface, cx, cy, radius, seed, S_CONTENT + 2400, attempt)
        if chest and chest.valid then
            local chest_index = #chests + 1
            fill_hoard_chest(chest, seed, cx, cy, chest_index)
            chests[chest_index] = chest
        end
    end
    distribute_hoard_bundles(chests, build_hoard_bundles(seed, cx, cy, profile, force), seed, cx, cy)

    -- Static defenders use the exact fixed zone table. The existing mobile
    -- defender budget remains independently difficulty-scaled and unchanged.
    local defence = HOARD_STATIC_DEFENCES[profile.level_id or "easy"] or HOARD_STATIC_DEFENCES.easy
    spawn_enemy_turrets(surface, cx, cy, radius, seed,
        defence.gun_turrets, defence.laser_turrets, S_CONTENT + 2600)
    local worm_ids = spawn_worms(surface, cx, cy, radius, seed, defence.worms)
    spawn_region_balanced_units(surface, cx, cy, radius, seed, room_budget(profile, "hoard"), S_CONTENT + 2900, room_region)
    return worm_ids, nil
end

function caverns.spawn_hoard_test(player, requested_level)
    if not (player and player.valid) then return end
    if not player.admin then
        player.print({ "the-cave-hoard-test.admin-only" })
        return
    end

    local requested = requested_level and requested_level:lower():match("^%s*(.-)%s*$") or ""
    local level = depth_levels.level_by_id(requested)
        or depth_levels.level_for_surface_position(player.surface, player.position)
    local level_id = level and level.id or "easy"
    local profile = { level = level, level_id = level_id, dangerous = false }
    local radius = 14 + radius_bonus_for(profile)
    local cx = math.floor(player.position.x + radius + 20)
    local cy = math.floor(player.position.y)
    local seed = (player.surface.map_gen_settings.seed or 0) + game.tick
    local carved, opened = {}, {}

    if not caverns.placement.area_is_playable(player.surface, cx - radius, cy - radius, cx + radius, cy + radius) then
        return
    end
    local previous_suppression = suppress_room_region_features
    suppress_room_region_features = true
    carve_disc(player.surface, cx, cy, radius, player.force, carved, true, opened)
    suppress_room_region_features = previous_suppression

    local room_region = region_features.region_at(cx, cy)
    populate_hoard(player.surface, cx, cy, radius, seed,
        math.sqrt(cx * cx + cy * cy), profile, room_region, player.force)
    player.force.chart(player.surface, {
        { cx - radius - 2, cy - radius - 2 },
        { cx + radius + 2, cy + radius + 2 },
    })
    player.print({ "the-cave-hoard-test.created", { "the-cave-runtime.depth-" .. level_id } })
end

function caverns.register_commands()
    if not commands then return end
    commands.add_command("the-cave-hoard-test", { "the-cave-hoard-test.command-help" }, function(command)
        local player = command.player_index and game.get_player(command.player_index)
        if player then caverns.spawn_hoard_test(player, command.parameter) end
    end)
end

local function populate_sanctuary(surface, cx, cy, radius, seed)
    local tiles = {}
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local dx, dy = x - cx, y - cy
            local d2 = dx * dx + dy * dy
            if d2 <= radius * radius then
                local name
                if d2 <= 9 then
                    name = "water"
                else
                    name = "grass-" .. hash.range(seed, x, y, S_CONTENT, 1, 4)
                end
                tiles[#tiles + 1] = { name = name, position = { x, y } }
            end
        end
    end
    surface.set_tiles(tiles)
    mirror.set_tiles(surface, tiles)
    for _, offset in pairs({ { 0.5, 0.5 }, { -0.5, -0.5 }, { 1.5, -0.5 } }) do
        surface.create_entity { name = "fish", position = { cx + offset[1], cy + offset[2] } }
    end
    for i = 1, hash.range(seed, cx, cy, S_CONTENT + 3100, 1, 2) do
        local chest = spawn_steel_chest(surface, cx, cy, radius, seed, S_CONTENT + 3200, i)
        fill_sanctuary_chest(chest, seed, cx, cy, i)
    end
end


-- Arm a room: its ceiling debt was already loaded at breach (suppressed by
-- the worms' protection), so arming just EVALUATES the live stress map —
-- pillars placed any time since the breach have been subtracting honestly,
-- and a pre-pillared room simply holds. No stress dump happens here.
local function arm_room(room)
    local surface = game.surfaces[room.surface_index]
    if not surface or not surface.valid then return end
    room.protected = false

    local force = game.forces[room.force_index] or game.forces.player
    -- Disabled never arms rooms; Enabled uses the original collapse rules.
    if collapse.is_surface_exempt(surface) or not collapse.available_for(force) then return end

    local hot = collapse.hot_cells(surface, room.cx, room.cy, room.radius + 2)
    if #hot == 0 then return end

    local at_tick = game.tick + settings.global["diggy-cavern-countdown"].value * 60
    -- Every failing cell gets the standard telegraph (box + live countdown),
    -- the same UX as 2.5s collapse pendings.
    for _, cell in pairs(hot) do
        cell.telegraph = collapse.telegraph(surface, cell.x, cell.y, at_tick)
    end
    storage.cavern_countdowns[#storage.cavern_countdowns + 1] = {
        surface_index = room.surface_index,
        cells = hot,
        at_tick = at_tick,
        force_index = force.index,
        cx = room.cx,
        cy = room.cy,
        radius = room.radius + 2, -- protection covers the same disc that armed
    }
    force.print({ "diggy.cavern-armed" })
end

local function room_weight_for_region(room, region)
    if room.kind == "nest" and (region == "gleba" or region == "vulcanus") then
        -- Native enemies supplement these regions, so vanilla nests remain common
        -- without crowding out Pentapods or Demolisher territory rooms.
        return 45
    end
    return room.weight
end

-- Keep room identity selection in one deterministic path. Direct player digs
-- use the full result below, while Demolisher digs inspect the same result and
-- are allowed to materialize extraction entrances only.
local function select_room_identity(surface, key_x, key_y, seed, force)
    local depth = math.sqrt(key_x * key_x + key_y * key_y)
    local profile = cavern_profile(surface, seed, key_x, key_y)
    local scheduled_zone = caverns.scheduled.manages(surface, { x = key_x, y = key_y })
    local radius = math.min(22,
        hash.range(seed, key_x, key_y, S_RADIUS, 6, 14) + radius_bonus_for(profile))

    local uranium_surface = surface.name:find("^the%-cave%-uranium%-cave%-") ~= nil
    local mineral_surface = surface.name:find("^the%-cave%-mineral%-cave%-") ~= nil
    local lost_city_surface = surface.name:find("^the%-cave%-lost%-city%-") ~= nil
    local extraction_cave_surface = uranium_surface or mineral_surface
    local mission_cave_surface = uranium_surface or mineral_surface or lost_city_surface
    local room_region = mission_cave_surface and "nauvis" or region_features.region_at(key_x, key_y)
    -- Discovery stays independent from operation. Several entrances may wait
    -- on the parent surface; uranium_caves.lua serialises only first-time entry
    -- so an unused entrance can never suppress all future discoveries.
    local uranium_available = not scheduled_zone and uranium_caves_enabled()
    local pool, total = {}, 0
    for _, room in pairs(ROOM_TYPES) do
        local allowed = depth >= room.min_depth
        if room.kind == "uranium-cave" and not uranium_available then
            allowed = false
        end
        if mission_cave_surface then
            -- Timed extraction cave interiors have only exploration rooms and
            -- zone-matched enemy nests. No nested entrances, hoards or specials.
            allowed = room.kind == "empty" or room.kind == "nest"
        end
        if allowed then
            local weighted = {
                kind = room.kind,
                min_depth = room.min_depth,
                weight = extraction_cave_surface
                    and (room.kind == "nest" and EXTRACTION_NEST_ROOM_WEIGHT
                        or EXTRACTION_EMPTY_ROOM_WEIGHT)
                    or room_weight_for_region(room, room_region),
            }
            pool[#pool + 1] = weighted
            total = total + weighted.weight
        end
    end
    local roll = hash.roll(seed, key_x, key_y, S_TYPE) * total
    local picked = pool[#pool]
    for _, room in pairs(pool) do
        roll = roll - room.weight
        if roll <= 0 then
            picked = room
            break
        end
    end

    local room_position = { x = key_x + 0.5, y = key_y + 0.5 }
    local uranium_eligible = uranium_available
        and not mission_cave_surface
        and profile.level_id ~= "easy"
    local uranium_pity_before = uranium_eligible and uranium_pity_count(surface, force) or 0
    local uranium_near = uranium_eligible and entrance_near(
        uranium_caves_api, surface, room_position, URANIUM_CAVE_MIN_DISTANCE
    ) or false
    local uranium_spacing_rejected = false

    -- Uranium always resolves before specials and Mineral Caves. A normal
    -- Uranium roll inside the 192-tile exclusion radius becomes an ordinary
    -- empty room and cannot be recycled into another extraction-cave type.
    if picked.kind == "uranium-cave" then
        if uranium_near then
            picked = { kind = "empty", min_depth = 0, weight = 0 }
            uranium_spacing_rejected = true
        end
    elseif uranium_eligible and uranium_pity_before >= URANIUM_PITY_ROOMS and not uranium_near then
        -- After eight successfully opened eligible rooms without Uranium, the
        -- next room outside the exclusion radius is guaranteed to be Uranium.
        picked = { kind = "uranium-cave", min_depth = 300, weight = 12 }
    end

    local special = nil
    if not mission_cave_surface
        and picked.kind ~= "uranium-cave"
        and picked.kind ~= "arachnid"
        and not uranium_spacing_rejected then
        special = pick_weighted_special(seed, key_x, key_y, profile, surface.index, scheduled_zone)
    end

    if extraction_cave_surface then
        local nest_has_capacity = extraction_nest_has_capacity(surface)
        if picked.kind == "nest" and not nest_has_capacity then
            picked = { kind = "empty", min_depth = 0, weight = 0 }
        elseif picked.kind == "empty"
            and nest_has_capacity
            and extraction_nest_pacing(surface.index).empty_streak >= EXTRACTION_EMPTY_ROOM_GUARANTEE
            and combat_cooldown_state(surface.index, room_region) == 0 then
            picked = { kind = "nest", min_depth = 0, weight = EXTRACTION_NEST_ROOM_WEIGHT }
        end
    end
    local room_is_combat
    picked, special, room_is_combat = apply_combat_room_cooldown(
        surface.index, room_region, picked, special
    )

    -- Preserve the existing combined combat-room frequency. Only distribute a
    -- resolved, non-special Nauvis nest encounter equally among its eligible
    -- original/Arachnid/Bob identities; extra families do not add extra fights.
    if caverns.bob_enemies.active() and room_region == "nauvis" and not special
        and (picked.kind == "nest" or picked.kind == "arachnid") then
        local identity = caverns.bob_enemies.choose_room(cave_evolution.factor(surface),
            not mission_cave_surface and depth >= 100,
            hash.roll(seed, key_x, key_y, caverns.bob_enemies.room_stream))
        if identity then picked = identity end
    end

    -- Lost City resolves after Uranium/specials but before ordinary Mineral
    -- Caves. Only successfully opened, ordinary Medium+ empty rooms count.
    local lost_city_opportunity = not scheduled_zone and lost_city_enabled()
        and not mission_cave_surface
        and profile.level_id ~= "easy"
        and not special
        and picked.kind == "empty"
        and not uranium_spacing_rejected
    local lost_city_pity_before = lost_city_opportunity
        and lost_city_pity_count(surface, force) or 0
    if lost_city_opportunity
        and (lost_city_pity_before >= LOST_CITY_PITY_ROOMS
            or hash.roll(seed, key_x, key_y, S_LOST_CITY) < LOST_CITY_EMPTY_ROOM_CHANCE) then
        picked = { kind = "lost-city", min_depth = 0, weight = 0 }
    end

    -- Mineral Caves can appear in every main-surface region. Uranium and
    -- specials resolve first; the per-Force resource deck is only consumed by
    -- the entrance creator after successful placement.
    local mineral_opportunity = not scheduled_zone and mineral_caves_enabled()
        and not mission_cave_surface
        and profile.level_id ~= "easy"
        and not special
        and picked.kind == "empty"
    local mineral_pity_before = mineral_opportunity and mineral_pity_count(surface, force) or 0
    if mineral_opportunity
        and not uranium_spacing_rejected
        and (mineral_pity_before >= MINERAL_PITY_ROOMS
            or hash.roll(seed, key_x, key_y, S_MINERAL_CAVE) < MINERAL_CAVE_EMPTY_ROOM_CHANCE) then
        picked = { kind = "mineral-cave", min_depth = 0, weight = 0 }
    end

    -- Prefer the three starter opportunities early in a family's exploration.
    -- Resolved specials and extraction/city entrances retain their priority.
    if not special and picked.kind ~= "uranium-cave"
        and picked.kind ~= "mineral-cave" and picked.kind ~= "lost-city"
        and caverns.progression.can_create(surface, force, room_region) then
        picked = { kind = "empty", min_depth = 0, weight = 0 }
        room_is_combat = false
    end

    return {
        depth = depth,
        profile = profile,
        radius = radius,
        extraction_cave_surface = extraction_cave_surface,
        mission_cave_surface = mission_cave_surface,
        room_region = room_region,
        picked = picked,
        special = special,
        room_is_combat = room_is_combat,
        uranium_eligible = uranium_eligible,
        uranium_pity_before = uranium_pity_before,
        uranium_spacing_rejected = uranium_spacing_rejected,
        mineral_opportunity = mineral_opportunity,
        mineral_pity_before = mineral_pity_before,
        lost_city_opportunity = lost_city_opportunity,
        lost_city_pity_before = lost_city_pity_before,
    }
end

-- Returns radius, opened_count. A "room" that overlaps mostly already-open
-- space (re-trigger over a hall, old cavern) opens nothing — skip contents,
-- registration and debt entirely; there is no new room there.
-- Strict preflight for new digging rooms. Frontier cover counts as closed,
-- even though its supporting floor tile is already present. Old floor never
-- receives an allowance; scheduled caves keep their separate layout rules.
function caverns._digging_footprint_is_closed(surface, plan)
    -- A registered room stays reserved even if collapse/another script later
    -- covered its floor again. Corridor checks use the actual old bounds.
    for _, old in ipairs(room_footprints_for_surface(surface.index)) do
        if plan.x1 <= old.x2 and plan.x2 >= old.x1
            and plan.y1 <= old.y2 and plan.y2 >= old.y1 then return false end
    end
    local covered = {}
    for _, entity in pairs(surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-tree" },
        area = {{plan.x1, plan.y1}, {plan.x2 + 1, plan.y2 + 1}},
    }) do
        if entity.valid then
            covered[key_xy(math.floor(entity.position.x), math.floor(entity.position.y))] = true
        end
    end
    for x = plan.x1, plan.x2 do
        for y = plan.y1, plan.y2 do
            if (not plan.shape or room_plan_contains(plan, x, y))
                and not covered[key_xy(x, y)]
                and surface.is_chunk_generated({math.floor(x / 32), math.floor(y / 32)}) then
                local tile = surface.get_tile(x, y)
                if tile and tile.valid and tile.name ~= "out-of-map" then return false end
            end
        end
    end
    return not room_plan_has_player_entities(surface, plan)
end

function caverns._digging_corridor_plan(x, y, dir)
    local px, py = dir[2], -dir[1]
    local ax, ay = x + dir[1] - px * 2, y + dir[2] - py * 2
    local bx, by = x + dir[1] * 20 + px * 3, y + dir[2] * 20 + py * 3
    return {x1 = math.min(ax, bx), y1 = math.min(ay, by),
        x2 = math.max(ax, bx), y2 = math.max(ay, by)}
end

local function make_room(surface, cx, cy, seed, force, carved, actor_name, fresh_open, entry_dir, scheduled, corridor_start, fixed_selection)
    -- Keep all deterministic room rolls keyed to the corridor endpoint. The
    -- actual room centre may be translated forward after its shape is known.
    local key_x, key_y = cx, cy
    local selection = fixed_selection or (scheduled and caverns.scheduled_selection(surface, scheduled, seed))
        or select_room_identity(surface, key_x, key_y, seed, force)
    local depth = selection.depth
    local profile = selection.profile
    local radius = selection.radius
    local extraction_cave_surface = selection.extraction_cave_surface
    local mission_cave_surface = selection.mission_cave_surface
    local room_region = selection.room_region
    local picked = selection.picked
    local special = selection.special
    local room_is_combat = selection.room_is_combat
    local uranium_eligible = selection.uranium_eligible
    local uranium_pity_before = selection.uranium_pity_before
    local uranium_spacing_rejected = selection.uranium_spacing_rejected
    local mineral_opportunity = selection.mineral_opportunity
    local mineral_pity_before = selection.mineral_pity_before
    local lost_city_opportunity = selection.lost_city_opportunity
    local lost_city_pity_before = selection.lost_city_pity_before
    if not special and (picked.kind == "nest" or picked.kind == "arachnid") then
        -- All three fixed nests need a reliable collision-free footprint. This
        -- also prevents the old Armoured-to-vanilla placement fallback and
        -- leaves enough room for the dedicated Arachnid boss.
        radius = math.max(radius, 12)
    end
    if special == "fortress" then
        local layout_level = scheduled and fortified_vaults.level_for_position(surface, scheduled.position, profile.level_id)
            or profile.level_id
        local layout = FORTRESS_LAYOUT[layout_level] or FORTRESS_LAYOUT.medium
        radius = math.max(radius, layout.radius)
    end

    -- The first three successful empty-room opportunities per Force/family
    -- become starter districts. After the cap, keep ordinary room geometry.
    local progression_allowed = caverns.progression.allowed(surface, force, room_region)
    local fulgora_ruin_room = not special
        and picked.kind == "empty"
        and room_region == "fulgora"
        and progression_allowed
    local gleba_progression_room = not special
        and picked.kind == "empty"
        and room_region == "gleba"
        and progression_allowed
    local vulcanus_progression_room = not special
        and picked.kind == "empty"
        and room_region == "vulcanus"
        and progression_allowed
    local aquilo_progression_room = not special
        and picked.kind == "empty"
        and room_region == "aquilo"
        and progression_allowed
    if fulgora_ruin_room then
        -- Large enough for the real vanilla Vault ruin plus a surrounding ruined
        -- district. All other surfaces keep their original room sizing.
        radius = math.max(radius, region_features.fulgora_ruin_room_radius())
    elseif gleba_progression_room then
        -- A Gleba starter needs both crop plots and all research triggers.
        radius = math.max(radius, region_features.gleba_progression_room_radius())
    elseif vulcanus_progression_room then
        -- A Vulcanus starter guarantees the native mining triggers and
        -- raw materials needed for the metallurgy progression chain.
        radius = math.max(radius, region_features.vulcanus_progression_room_radius())
    elseif aquilo_progression_room then
        -- An Aquilo starter guarantees the native mining trigger and the
        -- three fluid resources needed to start cryogenic progression.
        radius = math.max(radius, region_features.aquilo_progression_room_radius())
    end

    -- Timed extraction cave entrance rooms own their centre and must not receive normal veins.
    -- Fortresses and progression rooms force a square layout so their fixed
    -- resource districts fit reliably. Regional per-tile rolls are suppressed
    -- and the room content is placed only after carving finishes.
    local room_tiles, opened = {}, {}
    local progression_room = fulgora_ruin_room or gleba_progression_room
        or vulcanus_progression_room or aquilo_progression_room
    local forced_shape = scheduled and "square" or (not special
        and (picked.kind == "nest" or picked.kind == "arachnid")) and "circle"
        or ((special == "fortress" or progression_room) and "square" or nil)
    local skip_room_veins = mission_cave_surface or picked.kind == "uranium-cave"
        or picked.kind == "mineral-cave" or picked.kind == "lost-city"
        or special == "fortress" or progression_room

    local plan = room_shape_plan(seed, key_x, key_y, radius, forced_shape)
    if scheduled then
        plan.scheduled_cave = true
        plan.entrance_position = scheduled.position
        profile.entrance_position = scheduled.position
    end
    if entry_dir and (corridor_start or SPACED_ROOM_REGIONS[room_region]) then
        anchor_room_plan_after_corridor(plan, key_x, key_y, entry_dir)
        cx, cy = plan.cx, plan.cy
        -- A corridor may run along a quadrant boundary. Never carry a room's
        -- identity or progression contents into a different planetary region.
        if region_features.region_at(cx, cy) ~= room_region then
            return radius, 0, nil, nil
        end
    end

    plan.has_entrance = special == "fortress" or picked.kind == "uranium-cave"
        or picked.kind == "mineral-cave" or picked.kind == "lost-city"
    plan = caverns.placement.fit_plan(surface, plan, plan.has_entrance)
    if not plan then return radius, 0, nil, nil end
    if scheduled and (plan.cx ~= key_x or plan.cy ~= key_y) then return radius, 0, nil, nil end
    cx, cy = plan.cx, plan.cy
    if not mission_cave_surface and region_features.region_at(cx, cy) ~= room_region then
        return radius, 0, nil, nil
    end

    -- Apply Lost City's 400-tile permanent spacing at the final planned centre.
    -- A rejected guaranteed candidate stays guaranteed for the next legal room.
    if not scheduled and picked.kind == "lost-city" and entrance_near(
        lost_city_api,
        surface,
        { x = plan.cx + 0.5, y = plan.cy + 0.5 },
        LOST_CITY_MIN_DISTANCE
    ) then
        picked = { kind = "empty", min_depth = 0, weight = 0 }
        fulgora_ruin_room = room_region == "fulgora" and progression_allowed
        gleba_progression_room = room_region == "gleba" and progression_allowed
        vulcanus_progression_room = room_region == "vulcanus" and progression_allowed
        aquilo_progression_room = room_region == "aquilo" and progression_allowed
        progression_room = fulgora_ruin_room or gleba_progression_room
            or vulcanus_progression_room or aquilo_progression_room
        if progression_room then
            if fulgora_ruin_room then
                radius = math.max(radius, region_features.fulgora_ruin_room_radius())
            elseif gleba_progression_room then
                radius = math.max(radius, region_features.gleba_progression_room_radius())
            elseif vulcanus_progression_room then
                radius = math.max(radius, region_features.vulcanus_progression_room_radius())
            elseif aquilo_progression_room then
                radius = math.max(radius, region_features.aquilo_progression_room_radius())
            end
            forced_shape = "square"
            plan = room_shape_plan(seed, key_x, key_y, radius, forced_shape)
            if entry_dir and (corridor_start or SPACED_ROOM_REGIONS[room_region]) then
                anchor_room_plan_after_corridor(plan, key_x, key_y, entry_dir)
                cx, cy = plan.cx, plan.cy
                if region_features.region_at(cx, cy) ~= room_region then
                    return radius, 0, nil, nil
                end
            end
        end
        skip_room_veins = mission_cave_surface or special == "fortress" or progression_room
    end

    -- Apply the sole Mineral spacing rule at the final planned entrance centre:
    -- 192 tiles from the same resource only. Iron, Copper, Coal and Uranium may
    -- sit beside different types. If a Space Age candidate is rejected, rebuild
    -- its ordinary progression-room layout instead of silently losing the room.
    local mineral_resource_key = picked.kind == "mineral-cave"
        and (scheduled and scheduled.kind or mineral_caves_api.peek_placeable_resource_key(
            surface,
            force,
            { x = plan.cx + 0.5, y = plan.cy + 0.5 },
            MINERAL_CAVE_MIN_DISTANCE
        )) or nil
    if picked.kind == "mineral-cave" and not mineral_resource_key then
        picked = { kind = "empty", min_depth = 0, weight = 0 }
        fulgora_ruin_room = room_region == "fulgora" and progression_allowed
        gleba_progression_room = room_region == "gleba" and progression_allowed
        vulcanus_progression_room = room_region == "vulcanus" and progression_allowed
        aquilo_progression_room = room_region == "aquilo" and progression_allowed
        progression_room = fulgora_ruin_room or gleba_progression_room
            or vulcanus_progression_room or aquilo_progression_room

        if progression_room then
            if fulgora_ruin_room then
                radius = math.max(radius, region_features.fulgora_ruin_room_radius())
            elseif gleba_progression_room then
                radius = math.max(radius, region_features.gleba_progression_room_radius())
            elseif vulcanus_progression_room then
                radius = math.max(radius, region_features.vulcanus_progression_room_radius())
            elseif aquilo_progression_room then
                radius = math.max(radius, region_features.aquilo_progression_room_radius())
            end
            forced_shape = "square"
            plan = room_shape_plan(seed, key_x, key_y, radius, forced_shape)
            if entry_dir and (corridor_start or SPACED_ROOM_REGIONS[room_region]) then
                anchor_room_plan_after_corridor(plan, key_x, key_y, entry_dir)
                cx, cy = plan.cx, plan.cy
                if region_features.region_at(cx, cy) ~= room_region then
                    return radius, 0, nil, nil
                end
            end
        end
        skip_room_veins = mission_cave_surface or special == "fortress" or progression_room
    elseif picked.kind == "mineral-cave" then
        plan.mineral_resource_key = mineral_resource_key
    end

    plan.has_entrance = special == "fortress" or picked.kind == "uranium-cave"
        or picked.kind == "mineral-cave" or picked.kind == "lost-city"
    plan = caverns.placement.fit_plan(surface, plan, plan.has_entrance)
    if not plan then return radius, 0, nil, nil end
    if scheduled then
        -- Keep all fixed upper structures in the selected chunk; never translate
        -- or resize an entrance to make a different site appear successful.
        local x1, y1, x2, y2 = caverns.placement.plan_bounds(plan, true)
        local left, top = scheduled.chunk_x * 32, scheduled.chunk_y * 32
        if plan.cx ~= key_x or plan.cy ~= key_y or x1 < left or y1 < top
            or x2 >= left + 32 or y2 >= top + 32 then return radius, 0, nil, nil end
    elseif (plan.has_entrance and caverns.scheduled.manages(surface, { x = plan.cx, y = plan.cy }))
        or caverns.scheduled.intersects_reserved(surface, plan.x1, plan.y1, plan.x2, plan.y2) then
        return radius, 0, nil, nil
    end
    cx, cy = plan.cx, plan.cy
    if not mission_cave_surface and region_features.region_at(cx, cy) ~= room_region then
        return radius, 0, nil, nil
    end
    -- A translated room gets a short, three-wide connection to its original
    -- legal corridor endpoint. Validate the entire connection before digging.
    if corridor_start and plan.boundary_adjusted then return radius, 0, nil, nil end
    if corridor_start then
        -- Concave/double shapes can leave a hole at their nearest bounding
        -- edge. Keep the twenty-tile traversal gap, then connect its far end to
        -- the room centre entirely INSIDE the already validated room bounds.
        local px, py = entry_dir[2], -entry_dir[1]
        local ax, ay = key_x + entry_dir[1] - px * 2, key_y + entry_dir[2] - py * 2
        local bx, by = cx + px * 3, cy + py * 3
        plan.entry_connection = {x1 = math.max(plan.x1, math.min(ax, bx)),
            y1 = math.max(plan.y1, math.min(ay, by)),
            x2 = math.min(plan.x2, math.max(ax, bx)),
            y2 = math.min(plan.y2, math.max(ay, by))}
    end
    if plan.boundary_adjusted then
        local x1, y1 = math.min(key_x, cx) - 1, math.min(key_y, cy) - 1
        local x2, y2 = math.max(key_x, cx) + 1, math.max(key_y, cy) + 1
        if not caverns.placement.area_is_playable(surface, x1, y1, x2, y2)
            or not caverns.placement.area_is_clear(surface, x1, y1, x2, y2)
            or not caverns.train_safety_api.cave_area_is_safe(surface, {{x1, y1}, {x2 + 1, y2 + 1}}) then
            return radius, 0, nil, nil
        end
    end

    -- Check the final footprint immediately before carving. A moving long train
    -- is protected by the 50-tile margin contributed by every connected part.
    if not caverns._room_plan_is_clear_of_main_train(surface, plan) then
        return radius, 0, nil, nil
    end

    local corridor
    if corridor_start then
        corridor = caverns._digging_corridor_plan(corridor_start.x, corridor_start.y, entry_dir)
        local x1, y1, x2, y2 = caverns.placement.plan_bounds(plan, plan.has_entrance)
        local entrance_pad = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
        if room_plan_overlaps_registered(surface.index, plan)
            or not caverns._digging_footprint_is_closed(surface, plan)
            or (plan.has_entrance and not caverns._digging_footprint_is_closed(surface, entrance_pad))
            or not caverns.placement.area_is_playable(surface, corridor.x1, corridor.y1, corridor.x2, corridor.y2)
            or not caverns._digging_footprint_is_closed(surface, corridor)
            or caverns.scheduled.intersects_reserved(surface, corridor.x1, corridor.y1, corridor.x2, corridor.y2)
            or not caverns.train_safety_api.cave_area_is_safe(surface,
                {{corridor.x1, corridor.y1}, {corridor.x2 + 1, corridor.y2 + 1}}) then
            return radius, 0, nil, nil
        end
    elseif scheduled then
        if room_plan_has_player_entities(surface, plan) then return radius, 0, nil, nil end
    elseif SPACED_ROOM_REGIONS[room_region] or plan.boundary_adjusted then
        if room_plan_overlaps_registered(surface.index, plan)
            or room_plan_has_old_open_terrain(surface, plan, fresh_open)
            or room_plan_has_player_entities(surface, plan) then
            -- Keep the corridor that led here, but never carve/populate a room
            -- that would overlap an existing room, old open hall or player base.
            return radius, 0, nil, nil
        end
    end

    local previous_suppression = suppress_room_region_features
    -- A room's explicit content table is its sole source of danger. Suppress
    -- per-tile regional enemy/nest rolls while carving every room so a large
    -- room cannot silently add dozens of extra creatures on top of its budget.
    suppress_room_region_features = true
    if corridor then
        local px, py = entry_dir[2], -entry_dir[1]
        for step = 1, 20 do
            for offset = -2, 3 do
                carve_tile(surface,
                    corridor_start.x + entry_dir[1] * step + px * offset,
                    corridor_start.y + entry_dir[2] * step + py * offset,
                    force, carved, true, opened)
            end
        end
    end
    if plan.boundary_adjusted then
        local tx, ty = key_x, key_y
        while true do
            for dx = -1, 1 do
                for dy = -1, 1 do
                    carve_tile(surface, tx + dx, ty + dy, force, room_tiles, true, opened)
                end
            end
            if tx == cx and ty == cy then break end
            if tx ~= cx then tx = tx + (tx < cx and 1 or -1)
            else ty = ty + (ty < cy and 1 or -1) end
        end
    end
    local shape = carve_room_shape(
        surface, cx, cy, radius, seed, force, room_tiles, skip_room_veins, opened, plan.shape, plan
    )
    suppress_room_region_features = previous_suppression
    for _, t in pairs(room_tiles) do carved[#carved + 1] = t end
    if #opened < 10 and not scheduled then
        return radius, #opened, nil, nil
    end

    -- Ordinary empty rooms after the cap reveal native resource strata without
    -- starter-room clearing or per-tile enemies. Only newly opened room floor
    -- is eligible: exclude old terrain and the approach corridor.
    if not special and picked.kind == "empty" and not progression_room
        and SPACED_ROOM_REGIONS[room_region] and caverns.progression.manages(surface) then
        for _, tile in ipairs(opened) do
            if room_plan_contains(plan, tile[1], tile[2]) then
                region_features.on_dig { surface = surface, force = force,
                    position = { x = tile[1], y = tile[2] } }
            end
        end
    end

    -- Commit anti-drought pacing only after a real room has successfully
    -- opened. Failed/overlapping room attempts never consume the counter.
    if uranium_eligible then
        if picked.kind == "uranium-cave" then
            set_uranium_pity_count(surface, force, 0)
        else
            set_uranium_pity_count(surface, force, uranium_pity_before + 1)
        end
    end
    if mineral_opportunity then
        if picked.kind == "mineral-cave" then
            -- Reset only after mineral_caves confirms that the actual entrance
            -- entity was created. A rare placement failure must preserve the
            -- guarantee for the next legal room.
            plan.mineral_pity_pending = true
            plan.mineral_pity_before = mineral_pity_before
        else
            set_mineral_pity_count(surface, force,
                math.min(MINERAL_PITY_ROOMS, mineral_pity_before + 1))
        end
    end
    if lost_city_opportunity then
        if picked.kind == "lost-city" then
            plan.lost_city_pity_pending = true
            plan.lost_city_pity_before = lost_city_pity_before
        else
            set_lost_city_pity_count(surface, force,
                math.min(LOST_CITY_PITY_ROOMS, lost_city_pity_before + 1))
        end
    end

    -- Register the carved geometry even if a later optional content placement
    -- fails. The floor now exists and must remain protected from future rooms.
    local footprint
    if not scheduled or not scheduled.carved then
        footprint = register_room_plan(surface.index, plan, room_region)
        footprint.force_index = force and force.valid and force.index or nil
        footprint.progression_checked = caverns.progression.manages(surface)
    end


    local worm_ids = {}
    local room_label = nil

    -- The Cave 2.0.11: if a Special Cavern rolls, it owns the room identity.
    -- This prevents the old double-stacking problem where a base room spawned worms
    -- and then the special overlay spawned even more enemies on top.
    if special then
        worm_ids, room_label, plan.created_fortress = apply_special_cavern(surface, cx, cy, radius, seed, depth, profile, force, actor_name, special, room_region)
    elseif picked.kind == "nest" then
        worm_ids = populate_nest(surface, cx, cy, radius, seed, profile, room_region, picked.bob_family)
        room_label = picked.bob_family
            and { "the-cave-runtime.room-bob-enemy-nest", { "entity-name.bob-" .. picked.bob_family .. "-enemy" } }
            or { "the-cave-runtime.room-enemy-nest" }
    elseif picked.kind == "arachnid" then
        worm_ids = populate_arachnid_nest(surface, cx, cy, radius, seed, profile)
        room_label = { "the-cave-runtime.room-arachnid-nest" }
    elseif picked.kind == "hoard" then
        worm_ids = populate_hoard(surface, cx, cy, radius, seed, depth, profile, room_region, force)
        room_label = { "the-cave-runtime.room-hoard-room" }
    elseif picked.kind == "uranium-cave" then
        -- Dry, empty centre: uranium_caves.on_cavern_opened places the entrance here.
        room_label = { "the-cave-runtime.room-uranium-cave" }
    elseif picked.kind == "mineral-cave" then
        -- Dry, empty centre: mineral_caves.on_cavern_opened places the entrance here.
        room_label = { "the-cave-runtime.room-mineral-cave" }
    elseif picked.kind == "lost-city" then
        -- Dry centre: lost_city.on_cavern_opened places the persistent entrance.
        room_label = { "entity-name.the-cave-lost-city-entrance" }
    elseif fulgora_ruin_room then
        worm_ids = {}
        local require_vault = caverns.progression.manages(surface)
        local ruins_placed, progression_ready = region_features.populate_fulgora_ruin_room(
            surface, cx, cy, radius, seed, force, require_vault)
        if ruins_placed and ruins_placed > 0 and (not require_vault or progression_ready) then
            room_label = { "the-cave-runtime.room-fulgora-ruins" }
        else
            -- Never claim a ruin was discovered when entity placement failed.
            room_label = { "the-cave-runtime.room-empty-room" }
        end
    elseif gleba_progression_room then
        worm_ids = {}
        local resources_placed, progression_ready = region_features.populate_gleba_progression_room(
            surface, cx, cy, radius, seed, force
        )
        if progression_ready and resources_placed and resources_placed > 0 then
            room_label = { "the-cave-runtime.room-gleba-progression" }
        else
            -- Do not announce a progression room unless all mandatory trigger
            -- categories were actually placed successfully.
            room_label = { "the-cave-runtime.room-empty-room" }
        end
    elseif vulcanus_progression_room then
        worm_ids = {}
        local resources_placed, progression_ready = region_features.populate_vulcanus_progression_room(
            surface, cx, cy, radius, seed, force
        )
        if progression_ready and resources_placed and resources_placed > 0 then
            room_label = { "the-cave-runtime.room-vulcanus-progression" }
        else
            room_label = { "the-cave-runtime.room-empty-room" }
        end
    elseif aquilo_progression_room then
        worm_ids = {}
        local resources_placed, progression_ready = region_features.populate_aquilo_progression_room(
            surface, cx, cy, radius, seed, force
        )
        if progression_ready and resources_placed and resources_placed > 0 then
            room_label = { "the-cave-runtime.room-aquilo-progression" }
        else
            room_label = { "the-cave-runtime.room-empty-room" }
        end
    else
        -- Empty means empty outside the four progression regions: no worms, no biters, no spawners, no traps.
        worm_ids = {}
        room_label = { "the-cave-runtime.room-empty-room" }
    end

    if progression_room and caverns.progression.manages(surface) then
        if room_label[1] ~= "the-cave-runtime.room-empty-room" then
            local count = caverns.progression.complete(surface, force, room_region, plan)
            if count then
                room_label = { "the-cave-runtime.room-progression-quota", room_label,
                    count, caverns.progression.limit }
                if footprint then
                    footprint.progression_family = room_region
                    footprint.progression_force_index = force.index
                end
            end
        elseif footprint then
            footprint.progression_failed = true
        end
    end

    -- Count only successfully opened cavern rooms. This drives both the stable
    -- fortress rarity and the region-aware exploration combat cooldown.
    if extraction_cave_surface then
        record_extraction_room_result(surface.index, picked.kind == "nest")
    end
    if not scheduled or not scheduled.carved then
        record_room_combat_result(surface.index, room_region, room_is_combat)
        record_completed_cavern(surface.index, cx, cy, special)
    end
    if scheduled then scheduled.carved = true end

    -- Rooms with no registered guardians are stable safe/reward spaces. Worms
    -- guard ordinary combat rooms; Arachnid spawners guard Arachnid Nests. The
    -- ceiling arms only after the final registered guardian dies.
    if #worm_ids > 0 then
        local id = storage.next_cavern_id
        storage.next_cavern_id = id + 1
        local room = {
            id = id,
            surface_index = surface.index,
            cx = cx,
            cy = cy,
            radius = radius,
            shape = shape,
            force_index = force and force.index or game.forces.player.index,
            worms = #worm_ids,
            threat_level = profile.level_id,
            dangerous = profile.dangerous,
            protected = true,
        }
        storage.cavern_rooms[id] = room
        for _, unit in pairs(worm_ids) do
            storage.cavern_worms[unit] = id
        end
    end
    return radius, #opened, room_label, plan
end


-- Scheduled entrance rooms use the existing structures and content generators.
-- A compact square is an existing cavern shape; no building/sprite is scaled.
function caverns.scheduled_selection(surface, entry, seed)
    local cx, cy = entry.position.x, entry.position.y
    entry.profile = entry.profile or cavern_profile(surface, seed, cx, cy)
    local profile = entry.profile
    entry.radius = entry.radius or math.min(22,
        hash.range(seed, cx, cy, S_RADIUS, 6, 14) + radius_bonus_for(profile))
    local kind = entry.kind == "uranium" and "uranium-cave"
        or (entry.kind == "village" and "lost-city")
        or (entry.kind == "fortress" and "empty") or "mineral-cave"
    return {
        depth = math.sqrt(cx * cx + cy * cy), profile = profile,
        radius = entry.radius, picked = { kind = kind },
        special = entry.kind == "fortress" and "fortress" or nil,
        room_region = region_features.region_at(cx, cy),
        room_is_combat = entry.kind == "fortress",
    }
end

function caverns.open_scheduled_cave(surface, entry, force)
    if entry.status == "created" or not caverns.scheduled.enabled(entry.kind) then return false end
    force = entry.force_index and game.forces[entry.force_index] or force
    if not (surface and surface.valid and force and force.valid) then return false end
    local carved = {}
    local _, _, label, plan = make_room(surface, entry.position.x, entry.position.y,
        surface.map_gen_settings.seed or 0, force, carved, nil, nil, nil, entry)
    if #carved > 0 then world.advance_frontier(surface, carved) end
    if not plan then return false end
    local dig = { surface = surface, force = force, position = entry.position }
    local created = plan.created_fortress ~= nil
    if entry.kind == "uranium" then
        created = uranium_caves_api.on_cavern_opened(dig, plan, label) == true
    elseif entry.kind == "village" then
        created = lost_city_api.on_cavern_opened(dig, plan, label) == true
    elseif entry.kind ~= "fortress" then
        created = mineral_caves_api.on_cavern_opened(dig, plan, label) == true
    end
    if not created then return false end
    caverns.scheduled.complete(entry)
    force.chart(surface, {{plan.x1 - 2, plan.y1 - 2}, {plan.x2 + 3, plan.y2 + 3}})
    force.print({ "the-cave-runtime.cavern-discovered", label })
    return true
end

function caverns.retry_scheduled_caves()
    caverns.scheduled.retry_pending(caverns.open_scheduled_cave)
end

-- A registered cavern guardian died: when the last one falls, the room arms.
-- The legacy function name is retained for existing saves and callers.
function caverns.on_worm_died(entity)
    local id = storage.cavern_worms and storage.cavern_worms[entity.unit_number]
    if not id then return end
    storage.cavern_worms[entity.unit_number] = nil
    local room = storage.cavern_rooms[id]
    if not room or not room.protected then return end
    room.worms = room.worms - 1
    if room.worms <= 0 then
        arm_room(room)
        storage.cavern_rooms[id] = nil
    end
end

-- Countdown display: a rip-style pop text (rise + wobble) at the failing
-- cavern on every number, shifting orange to red as zero approaches.
function caverns.on_heartbeat()
    local countdowns = storage.cavern_countdowns
    if not countdowns or #countdowns == 0 then return end
    if collapse.is_disabled() then
        for i = #countdowns, 1, -1 do
            for _, cell in pairs(countdowns[i].cells or {}) do
                collapse.untelegraph(cell.telegraph)
            end
            table.remove(countdowns, i)
        end
        return
    end
    local now = game.tick
    for i = #countdowns, 1, -1 do
        local cd = countdowns[i]
        local surface = game.surfaces[cd.surface_index]
        if not surface or not surface.valid or collapse.is_surface_exempt(surface) then
            for _, cell in pairs(cd.cells) do collapse.untelegraph(cell.telegraph) end
            table.remove(countdowns, i)
        elseif cd.at_tick <= now then
            for _, cell in pairs(cd.cells) do collapse.untelegraph(cell.telegraph) end
            table.remove(countdowns, i)
            local force = game.forces[cd.force_index]
            local rocks = collapse.sparse_collapse(surface, cd.cells, force, surface.map_gen_settings.seed)
            if rocks > 0 then
                pop_text.spawn(surface, { x = cd.cx + 0.5, y = cd.cy + 0.5 },
                    { "diggy.cavern-collapse-pop" }, { r = 1, g = 0.1, b = 0.1 }, force)
            else
                -- The players shored it up in time.
                pop_text.spawn(surface, { x = cd.cx + 0.5, y = cd.cy + 0.5 },
                    { "diggy.cavern-held-pop" }, { r = 0.3, g = 1, b = 0.3 }, force)
                if force then force.print({ "diggy.cavern-held" }) end
            end
        else
            -- floor, not ceil: the announced number must match the integer
            -- part the per-cell telegraph timers display all second long
            -- (ceil ran a visible second ahead of them).
            local secs = math.floor((cd.at_tick - now) / 60)
            if secs >= 1 and secs ~= cd.last_secs then
                cd.last_secs = secs
                local force = game.forces[cd.force_index]
                local heat = 1 - math.min(secs, 15) / 15
                pop_text.spawn(surface, { x = cd.cx + 0.5, y = cd.cy + 0.5 },
                    { "diggy.cavern-countdown-pop", secs },
                    { r = 1, g = 0.65 * (1 - heat), b = 0.05 }, force)
            end
        end
    end
end

local function carve_four_wide_corridor_segment(surface, cx, cy, dir, length, force, carved, opened)
    local min_x, min_y, max_x, max_y = cx, cy, cx, cy
    local px, py = dir[2], -dir[1]
    for _ = 1, length do
        local nx, ny = cx + dir[1], cy + dir[2]
        if not caverns.placement.area_is_playable(surface, nx - 2, ny - 2, nx + 2, ny + 2) then break end
        cx, cy = nx, ny
        -- Four-tile-wide corridor. An even width has no single centre tile, so
        -- the path line sits between the two middle tiles (offsets 0 and 1).
        for offset = -1, 2 do
            local tx, ty = cx + px * offset, cy + py * offset
            carve_tile(surface, tx, ty, force, carved, true, opened)
            min_x, min_y = math.min(min_x, tx), math.min(min_y, ty)
            max_x, max_y = math.max(max_x, tx), math.max(max_y, ty)
        end
    end
    return cx, cy, min_x, min_y, max_x, max_y
end

local function carve_space_age_room_corridors(surface, seed, x, y, dir, force, carved, opened)
    local cx, cy = x, y
    local min_x, min_y, max_x, max_y = x, y, x, y
    local count = hash.range(seed, x, y, S_CORRIDOR_COUNT, 1, 3)

    -- These are clean traversal gaps between rooms, not resource halls. Suppress
    -- both regional feature placement and ore veins while carving them.
    local previous_suppression = suppress_room_region_features
    suppress_room_region_features = true
    for segment = 1, count do
        local length = hash.range(seed, cx, cy, S_CORRIDOR_LENGTH + segment, 10, 20)
        local sx1, sy1, sx2, sy2
        cx, cy, sx1, sy1, sx2, sy2 = carve_four_wide_corridor_segment(
            surface, cx, cy, dir, length, force, carved, opened
        )
        min_x, min_y = math.min(min_x, sx1), math.min(min_y, sy1)
        max_x, max_y = math.max(max_x, sx2), math.max(max_y, sy2)

        if segment < count then
            local turn = hash.roll(seed, cx, cy, S_CORRIDOR_TURN + segment)
            if turn < 0.30 then
                dir = { -dir[2], dir[1] } -- left
            elseif turn < 0.60 then
                dir = { dir[2], -dir[1] } -- right
            end -- otherwise continue straight
        end
    end
    suppress_room_region_features = previous_suppression

    return cx, cy, min_x, min_y, max_x, max_y, dir
end

local function name_is_demolisher(name)
    return type(name) == "string" and name:find("demolisher", 1, true) ~= nil
end

local function demolisher_corridor_is_safe(surface, x, y, dir, length)
    local px, py = dir[2], -dir[1]
    local end_x, end_y = x + dir[1] * length, y + dir[2] * length
    local x1 = math.min(x, end_x) - math.abs(px) * 2
    local y1 = math.min(y, end_y) - math.abs(py) * 2
    local x2 = math.max(x, end_x) + math.abs(px) * 2 + 1
    local y2 = math.max(y, end_y) + math.abs(py) * 2 + 1
    if not caverns.placement.area_is_playable(surface, x1, y1, x2 - 1, y2 - 1) then return false end
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { x1, y1 }, { x2, y2 } },
    }) do
        if entity.valid then
            local force_name = entity.force and entity.force.name or "neutral"
            -- The first corridor cells necessarily begin beneath the triggering
            -- Demolisher. Only player assets block the side route; the chamber
            -- itself independently rejects every Demolisher entity.
            if (force_name ~= "neutral" and force_name ~= "enemy")
                or entity.type == "character"
                or entity.type == "car"
                or entity.type == "spider-vehicle"
                or entity.type == "locomotive"
                or entity.type == "cargo-wagon"
                or entity.type == "fluid-wagon"
                or entity.type == "artillery-wagon" then
                return false
            end
        end
    end
    return true
end

local function demolisher_room_is_safe(surface, plan, room_region)
    if region_features.region_at(plan.cx, plan.cy) ~= room_region then return false end
    if not caverns._room_plan_is_clear_of_main_train(surface, plan) then return false end
    if room_plan_overlaps_registered(surface.index, plan)
        or room_plan_has_old_open_terrain(surface, plan, nil)
        or room_plan_has_player_entities(surface, plan) then
        return false
    end
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { plan.x1, plan.y1 }, { plan.x2 + 1, plan.y2 + 1 } },
    }) do
        if entity.valid and name_is_demolisher(entity.name) then return false end
    end
    return true
end

local function advance_demolisher_virtual_pity(surface, force, selection)
    if selection.uranium_eligible then
        set_uranium_pity_count(surface, force, selection.uranium_pity_before + 1)
    end
    if selection.mineral_opportunity then
        set_mineral_pity_count(surface, force,
            math.min(MINERAL_PITY_ROOMS, selection.mineral_pity_before + 1))
    end
end

local function preserve_demolisher_extraction_pity(surface, force, selection)
    if selection.picked.kind == "uranium-cave" then
        set_uranium_pity_count(surface, force,
            math.max(URANIUM_PITY_ROOMS, selection.uranium_pity_before))
    elseif selection.picked.kind == "mineral-cave" then
        set_mineral_pity_count(surface, force,
            math.max(MINERAL_PITY_ROOMS, selection.mineral_pity_before))
    end
end

-- Demolisher-only cavern resolution. It evaluates the same trigger, room,
-- Uranium-first, special-priority, Mineral-deck and pity decisions as player
-- excavation, but suppressed room kinds never carve geometry or spawn content.
-- A selected extraction entrance is moved into a dry side chamber so the
-- segmented body cannot immediately run over or obstruct it.
function caverns.on_demolisher_dig(dig)
    if not (dig and dig.is_demolisher and dig.surface and dig.surface.valid and dig.position) then
        return false
    end

    local surface = dig.surface
    local position = dig.position
    local x, y = math.floor(position.x), math.floor(position.y)
    if x * x + y * y < MIN_DEPTH * MIN_DEPTH then return false end

    local seed = surface.map_gen_settings.seed
    if hash.roll(seed, x, y, S_TRIGGER) >= settings.global["diggy-cavern-chance"].value
        or hash.roll(seed, x, y, S_ROOM) >= 0.4 then
        return false
    end

    local travel = dig.demolisher_direction or DIRS[hash.range(seed, x, y, S_DIR, 1, 4)]
    local left = { -travel[2], travel[1] }
    local primary = hash.roll(seed, x, y, S_DEMOLISHER_SIDE) < 0.5
        and left or { -left[1], -left[2] }
    local directions = { primary, { -primary[1], -primary[2] } }
    local minimum_clearance = math.max(32, tonumber(dig.demolisher_clearance) or 0)
    local corridor_length = hash.range(seed, x, y, S_DEMOLISHER_CLEARANCE,
        minimum_clearance, minimum_clearance + 12)

    -- The deterministic identity key belongs to the preferred side. If that
    -- placement is obstructed, the opposite side retains this exact identity,
    -- so a blocked room cannot reroll into a different reward.
    local key_x = x + primary[1] * corridor_length
    local key_y = y + primary[2] * corridor_length
    local selection = select_room_identity(surface, key_x, key_y, seed, dig.force)
    local picked = selection.picked
    if picked.kind ~= "uranium-cave" and picked.kind ~= "mineral-cave" then
        advance_demolisher_virtual_pity(surface, dig.force, selection)
        return false
    end

    local chosen_dir, chosen_plan, mineral_resource_key
    for _, dir in ipairs(directions) do
        local endpoint_x = x + dir[1] * corridor_length
        local endpoint_y = y + dir[2] * corridor_length
        local plan = room_shape_plan(seed, key_x, key_y, selection.radius, "circle")
        anchor_room_plan_after_corridor(plan, endpoint_x, endpoint_y, dir)
        plan.has_entrance = true

        local spacing_ok = true
        if picked.kind == "uranium-cave" then
            spacing_ok = not entrance_near(uranium_caves_api, surface,
                { x = plan.cx + 0.5, y = plan.cy + 0.5 }, URANIUM_CAVE_MIN_DISTANCE)
        else
            mineral_resource_key = mineral_caves_api.peek_placeable_resource_key(
                surface,
                dig.force,
                { x = plan.cx + 0.5, y = plan.cy + 0.5 },
                MINERAL_CAVE_MIN_DISTANCE
            )
            spacing_ok = mineral_resource_key ~= nil
        end

        if spacing_ok
            and demolisher_corridor_is_safe(surface, x, y, dir, corridor_length)
            and demolisher_room_is_safe(surface, plan, selection.room_region) then
            chosen_dir, chosen_plan = dir, plan
            break
        end
        mineral_resource_key = nil
    end

    if not chosen_plan then
        -- No deck entry is consumed and the next legal side-room opportunity is
        -- guaranteed to retry the selected extraction type.
        preserve_demolisher_extraction_pity(surface, dig.force, selection)
        return false
    end

    local carved, corridor_opened, room_tiles, room_opened = {}, {}, {}, {}
    local previous_suppression = suppress_room_region_features
    suppress_room_region_features = true
    carve_four_wide_corridor_segment(
        surface, x, y, chosen_dir, corridor_length, dig.force, carved, corridor_opened
    )
    carve_room_shape(
        surface,
        chosen_plan.cx,
        chosen_plan.cy,
        chosen_plan.radius,
        seed,
        dig.force,
        room_tiles,
        true,
        room_opened,
        "circle",
        chosen_plan
    )
    suppress_room_region_features = previous_suppression
    for _, tile in ipairs(room_tiles) do carved[#carved + 1] = tile end
    local frontier, seen = {}, {}
    for _, tile in ipairs(carved) do
        local key = key_xy(tile[1], tile[2])
        if not seen[key] then
            seen[key] = true
            frontier[#frontier + 1] = tile
        end
    end
    world.advance_frontier(surface, frontier)

    if #room_opened < 10 then
        preserve_demolisher_extraction_pity(surface, dig.force, selection)
        return false
    end

    chosen_plan.demolisher_extraction = true
    if picked.kind == "uranium-cave" then
        chosen_plan.uranium_pity_pending = true
        chosen_plan.uranium_pity_before = selection.uranium_pity_before
    else
        chosen_plan.mineral_resource_key = mineral_resource_key
        chosen_plan.mineral_pity_pending = true
        chosen_plan.mineral_pity_before = selection.mineral_pity_before
    end
    register_room_plan(surface.index, chosen_plan, selection.room_region)

    local room_label = picked.kind == "uranium-cave"
        and { "the-cave-runtime.room-uranium-cave" }
        or { "the-cave-runtime.room-mineral-cave" }
    return true, chosen_plan, room_label
end

-- A Train Wave tunnel may expose only real extraction Qs. The main six-wide
-- attack lane remains straight; a separate six-wide side branch gives the
-- entrance its native room and keeps the portal out of the Biter traffic line.
-- Normal cavern rooms, combat, treasure and regional progression content are
-- deliberately suppressed here.
local function carve_train_wave_side_corridor(surface, cx, cy, dir, length, force, carved, opened)
    local min_x, min_y, max_x, max_y = cx, cy, cx, cy
    for _ = 1, length do
        cx, cy = cx + dir[1], cy + dir[2]
        -- A square brush keeps the passage continuously six tiles wide even
        -- when the main Train Wave tunnel is travelling diagonally.
        for dx = -2, 3 do
            for dy = -2, 3 do
                local tx, ty = cx + dx, cy + dy
                carve_tile(surface, tx, ty, force, carved, true, opened)
                min_x, min_y = math.min(min_x, tx), math.min(min_y, ty)
                max_x, max_y = math.max(max_x, tx), math.max(max_y, ty)
            end
        end
    end
    return cx, cy, min_x, min_y, max_x, max_y
end

local function train_wave_side_corridor_is_safe(surface, x, y, dir, length)
    local end_x, end_y = x + dir[1] * length, y + dir[2] * length
    local x1, y1 = math.min(x, end_x) - 3, math.min(y, end_y) - 3
    local x2, y2 = math.max(x, end_x) + 4, math.max(y, end_y) + 4
    if not caverns.placement.area_is_playable(surface, x1, y1, x2 - 1, y2 - 1) then return false end
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { x1, y1 }, { x2, y2 } },
    }) do
        if entity.valid then
            local force_name = entity.force and entity.force.name or "neutral"
            if (force_name ~= "neutral" and force_name ~= "enemy")
                or entity.type == "character"
                or entity.type == "car"
                or entity.type == "spider-vehicle"
                or entity.type == "locomotive"
                or entity.type == "cargo-wagon"
                or entity.type == "fluid-wagon"
                or entity.type == "artillery-wagon" then
                return false
            end
        end
    end
    return true
end

function caverns.on_train_wave_tunnel_dig(dig)
    if not (dig and dig.is_train_wave_tunnel and dig.surface and dig.surface.valid and dig.position) then
        return false
    end

    local surface = dig.surface
    local x, y = math.floor(dig.position.x), math.floor(dig.position.y)
    if x * x + y * y < MIN_DEPTH * MIN_DEPTH then return false end

    local seed = surface.map_gen_settings.seed
    if hash.roll(seed, x, y, S_TRIGGER) >= settings.global["diggy-cavern-chance"].value
        or hash.roll(seed, x, y, S_ROOM) >= 0.4 then
        return false
    end

    local source_dir = dig.train_wave_direction or { 1, 0 }
    local travel = {
        source_dir[1] == 0 and 0 or (source_dir[1] < 0 and -1 or 1),
        source_dir[2] == 0 and 0 or (source_dir[2] < 0 and -1 or 1),
    }
    if travel[1] == 0 and travel[2] == 0 then return false end
    local left = { -travel[2], travel[1] }
    local primary = hash.roll(seed, x, y, S_DEMOLISHER_SIDE) < 0.5
        and left or { -left[1], -left[2] }
    local directions = { primary, { -primary[1], -primary[2] } }
    local minimum_clearance = math.max(32, tonumber(dig.train_wave_clearance) or 0)
    local corridor_length = hash.range(seed, x, y, S_DEMOLISHER_CLEARANCE,
        minimum_clearance, minimum_clearance + 12)

    -- The preferred side owns the deterministic identity. Trying the opposite
    -- side after a collision cannot reroll Uranium into a different reward.
    local key_x = x + primary[1] * corridor_length
    local key_y = y + primary[2] * corridor_length
    local selection = select_room_identity(surface, key_x, key_y, seed, dig.force)
    local picked = selection.picked
    if picked.kind ~= "uranium-cave" and picked.kind ~= "mineral-cave" then
        advance_demolisher_virtual_pity(surface, dig.force, selection)
        return false
    end

    local chosen_dir, chosen_plan, mineral_resource_key
    for _, dir in ipairs(directions) do
        local endpoint_x = x + dir[1] * corridor_length
        local endpoint_y = y + dir[2] * corridor_length
        local plan = room_shape_plan(seed, key_x, key_y, selection.radius, "circle")
        anchor_room_plan_after_corridor(plan, endpoint_x, endpoint_y, dir)
        plan.has_entrance = true

        local spacing_ok = true
        if picked.kind == "uranium-cave" then
            spacing_ok = not entrance_near(uranium_caves_api, surface,
                { x = plan.cx + 0.5, y = plan.cy + 0.5 }, URANIUM_CAVE_MIN_DISTANCE)
        else
            mineral_resource_key = mineral_caves_api.peek_placeable_resource_key(
                surface,
                dig.force,
                { x = plan.cx + 0.5, y = plan.cy + 0.5 },
                MINERAL_CAVE_MIN_DISTANCE
            )
            spacing_ok = mineral_resource_key ~= nil
        end

        if spacing_ok
            and train_wave_side_corridor_is_safe(surface, x, y, dir, corridor_length)
            and demolisher_room_is_safe(surface, plan, selection.room_region) then
            chosen_dir, chosen_plan = dir, plan
            break
        end
        mineral_resource_key = nil
    end

    if not chosen_plan then
        preserve_demolisher_extraction_pity(surface, dig.force, selection)
        return false
    end

    local carved, corridor_opened, room_tiles, room_opened = {}, {}, {}, {}
    local previous_suppression = suppress_room_region_features
    suppress_room_region_features = true
    carve_train_wave_side_corridor(
        surface, x, y, chosen_dir, corridor_length, dig.force, carved, corridor_opened
    )
    carve_room_shape(
        surface,
        chosen_plan.cx,
        chosen_plan.cy,
        chosen_plan.radius,
        seed,
        dig.force,
        room_tiles,
        true,
        room_opened,
        "circle",
        chosen_plan
    )
    suppress_room_region_features = previous_suppression
    for _, tile in ipairs(room_tiles) do carved[#carved + 1] = tile end
    local frontier, seen = {}, {}
    for _, tile in ipairs(carved) do
        local key = key_xy(tile[1], tile[2])
        if not seen[key] then
            seen[key] = true
            frontier[#frontier + 1] = tile
        end
    end
    world.advance_frontier(surface, frontier)

    if #room_opened < 10 then
        preserve_demolisher_extraction_pity(surface, dig.force, selection)
        return false
    end

    -- Reuse the automated-extraction retry semantics: a failed portal never
    -- consumes its pity guarantee or a Mineral resource-deck entry.
    chosen_plan.demolisher_extraction = true
    chosen_plan.train_wave_extraction = true
    if picked.kind == "uranium-cave" then
        chosen_plan.uranium_pity_pending = true
        chosen_plan.uranium_pity_before = selection.uranium_pity_before
    else
        chosen_plan.mineral_resource_key = mineral_resource_key
        chosen_plan.mineral_pity_pending = true
        chosen_plan.mineral_pity_before = selection.mineral_pity_before
    end
    register_room_plan(surface.index, chosen_plan, selection.room_region)

    local room_label = picked.kind == "uranium-cave"
        and { "the-cave-runtime.room-uranium-cave" }
        or { "the-cave-runtime.room-mineral-cave" }
    return true, chosen_plan, room_label
end

function caverns.on_dig(dig)
    -- Full rooms belong exclusively to direct player excavation. The narrowly
    -- filtered Demolisher extraction exception is resolved by the separate
    -- on_demolisher_dig entry point above.
    if not (dig and dig.allow_room_generation) then return end
    local scheduled = caverns.scheduled.at_position(dig.surface, dig.position)
    if scheduled and scheduled.status ~= "created" and caverns.scheduled.enabled(scheduled.kind) then
        caverns.scheduled.queue(scheduled, dig.force)
        if caverns.open_scheduled_cave(dig.surface, scheduled, dig.force) then
            -- Entrance creation was committed here; the generic callbacks in
            -- control.lua receive no plan and cannot create a duplicate.
            return true
        end
    end

    local actor_name = nil
    if dig.player_index then
        local player = game.get_player(dig.player_index)
        if player and player.valid then actor_name = player.name end
    end
    local position = dig.position
    local x, y = math.floor(position.x), math.floor(position.y)
    local surface = dig.surface
    local timed_cave_surface = surface and surface.valid and type(surface.name) == "string"
        and (surface.name:find("^the%-cave%-uranium%-cave%-") ~= nil
            or surface.name:find("^the%-cave%-mineral%-cave%-") ~= nil)
    if not timed_cave_surface and x * x + y * y < MIN_DEPTH * MIN_DEPTH then return end

    local seed = surface.map_gen_settings.seed
    if hash.roll(seed, x, y, S_TRIGGER) >= settings.global["diggy-cavern-chance"].value then
        return
    end

    local force = dig.force
    local dir = DIRS[hash.range(seed, x, y, S_DIR, 1, 4)]
    local cx, cy = x, y
    local min_x, min_y, max_x, max_y = x, y, x, y
    local carved = {}
    local opened = {}

    local wants_room = caverns.progression.can_create(surface, force, region_features.region_at(x, y))
        or hash.roll(seed, x, y, S_ROOM) < 0.4
    local room_entry_dir = nil
    if not wants_room then
        local length = hash.range(seed, x, y, S_LEN, 12, 40 + depth_levels.cavern_length_bonus(position, surface))
        for step = 1, length do
            local nx, ny = cx + dir[1], cy + dir[2]
            if not caverns.placement.area_is_playable(surface, nx - 1, ny - 1, nx + 1, ny + 1) then break end
            cx, cy = nx, ny
            -- Non-room tunnel breaches retain their established shape.
            carve_tile(surface, cx, cy, force, carved, nil, opened)
            carve_tile(surface, cx + dir[2], cy + dir[1], force, carved, nil, opened)
            carve_tile(surface, cx - dir[2], cy - dir[1], force, carved, nil, opened)
            min_x, min_y = math.min(min_x, cx), math.min(min_y, cy)
            max_x, max_y = math.max(max_x, cx), math.max(max_y, cy)
            -- Snake: reconsider heading every few steps.
            if step % 3 == 0 then
                local turn = hash.roll(seed, cx, cy, S_TURN)
                if turn < 0.25 then
                    dir = { dir[2], dir[1] }
                elseif turn < 0.5 then
                    dir = { -dir[2], -dir[1] }
                end
            end
        end
    end

    local radius, room_opened = 0, 0
    local room_label = nil
    local room_plan = nil
    if wants_room then
        -- Pick the identity once. Trying another closed direction never rerolls
        -- an extraction cave, threat budget, reward or pacing opportunity.
        local selection = select_room_identity(surface, x, y, seed, force)
        local first = hash.range(seed, x, y, S_DIR, 1, 4)
        for attempt = 0, 3 do
            room_entry_dir = DIRS[(first + attempt - 1) % 4 + 1]
            cx, cy = x + room_entry_dir[1] * 20, y + room_entry_dir[2] * 20
            radius, room_opened, room_label, room_plan = make_room(
                surface, cx, cy, seed, force, carved, actor_name, nil,
                room_entry_dir, nil, {x = x, y = y}, selection)
            if room_plan then break end
        end
        if room_plan then
            min_x, min_y = math.min(min_x, room_plan.x1), math.min(min_y, room_plan.y1)
            max_x, max_y = math.max(max_x, room_plan.x2), math.max(max_y, room_plan.y2)
        end
    end

    -- Wall off every void tile touching the carved space — the cavern gets
    -- its own frontier instead of bleeding into blackness.
    world.advance_frontier(surface, carved)

    -- Announce only when something actually opened: a tunnel that snaked
    -- entirely through already-open space exposed nothing and says nothing.
    local total_opened = #opened + room_opened
    if force and total_opened >= 6 then
        force.chart(surface, { { min_x - 2, min_y - 2 }, { max_x + 2, max_y + 2 } })
        if actor_name then
            if room_opened >= 10 and room_label then
                force.print({ "the-cave-runtime.cavern-discovered-by-player", actor_name, room_label })
            elseif room_opened >= 10 then
                force.print({ "the-cave-runtime.cavern-breached-by-player", actor_name })
            else
                force.print({ "the-cave-runtime.tunnel-opened-by-player", actor_name })
            end
        else
            if room_opened >= 10 and room_label then
                force.print({ "the-cave-runtime.cavern-discovered", room_label })
            else
                force.print({ room_opened >= 10 and "diggy.cavern-room-breached" or "diggy.cavern-breached" })
            end
        end
    end
    return room_opened >= 10, room_plan, room_label
end

function caverns.on_mineral_entrance_result(dig, room_plan, created)
    if not (dig and dig.surface and room_plan and room_plan.mineral_pity_pending) then return end
    if created then
        set_mineral_pity_count(dig.surface, dig.force, 0)
    elseif room_plan.demolisher_extraction then
        -- A Demolisher-selected cave whose safe entrance placement failed stays
        -- pending: the next legal virtual room retries Mineral immediately.
        set_mineral_pity_count(dig.surface, dig.force, MINERAL_PITY_ROOMS)
    else
        set_mineral_pity_count(dig.surface, dig.force,
            math.min(MINERAL_PITY_ROOMS, (tonumber(room_plan.mineral_pity_before) or 0) + 1))
    end
end

function caverns.on_lost_city_entrance_result(dig, room_plan, created)
    if not (dig and dig.surface and room_plan and room_plan.lost_city_pity_pending) then return end
    if created then
        set_lost_city_pity_count(dig.surface, dig.force, 0)
    else
        -- Placement failure cannot consume a roll or a ten-room guarantee.
        set_lost_city_pity_count(dig.surface, dig.force,
            math.min(LOST_CITY_PITY_ROOMS,
                (tonumber(room_plan.lost_city_pity_before) or 0) + 1))
    end
end

function caverns.on_uranium_entrance_result(dig, room_plan, created)
    if not (dig and dig.surface and room_plan and room_plan.uranium_pity_pending) then return end
    if created then
        set_uranium_pity_count(dig.surface, dig.force, 0)
    else
        -- No entrance means no consumed opportunity. Preserve a guaranteed
        -- Uranium retry at the next location that passes the 192-tile rule.
        set_uranium_pity_count(dig.surface, dig.force, URANIUM_PITY_ROOMS)
    end
end


local function destroy_legacy_support(support)
    if not support then return 0 end

    local removed = 0
    local function destroy_entity(entity)
        if entity and entity.valid then
            entity.destroy()
            removed = removed + 1
        end
    end

    if support.valid ~= nil then
        destroy_entity(support)
    else
        destroy_entity(support.power)
        destroy_entity(support.pole)
    end

    return removed
end

local function add_legacy_laser_candidate(candidates, turret)
    if not (turret and turret.valid and turret.name == "laser-turret") then return end
    if not (turret.force and turret.force.name == "enemy") then return end

    local key = turret.unit_number
        or (tostring(turret.surface.index) .. ":" .. tostring(turret.position.x) .. ":" .. tostring(turret.position.y))
    candidates[key] = turret
end

local function replace_legacy_laser_turret(turret)
    if not (turret and turret.valid and turret.name == "laser-turret") then return false end
    if not entity_exists(ENEMY_LASER_TURRET) then return false end

    local surface = turret.surface
    local position = { x = turret.position.x, y = turret.position.y }
    local force = turret.force
    local direction = turret.direction
    local old_max_health = tonumber(turret.max_health) or tonumber(turret.health) or 1
    local health_ratio = math.max(0, math.min(1, (turret.health or old_max_health) / old_max_health))
    local disabled_by_script = turret.disabled_by_script
    local destructible = turret.destructible
    local minable = turret.minable_flag
    local operable = turret.operable
    local quality = turret.quality and turret.quality.name or nil

    turret.destroy()

    local create_parameters = {
        name = ENEMY_LASER_TURRET,
        position = position,
        force = force,
        direction = direction,
    }
    if quality then create_parameters.quality = quality end

    local ok_create, replacement = pcall(function()
        return surface.create_entity(create_parameters)
    end)
    if not ok_create then replacement = nil end

    if not (replacement and replacement.valid) and quality then
        -- Quality should be accepted in Factorio 2.0, but retry without it so
        -- an unusual compatibility layer cannot abort the whole save migration.
        create_parameters.quality = nil
        ok_create, replacement = pcall(function()
            return surface.create_entity(create_parameters)
        end)
        if not ok_create then replacement = nil end
    end

    if not (replacement and replacement.valid) then
        -- Defensive fallback: never delete a live guard if another mod has
        -- unexpectedly made the dedicated prototype unbuildable at this spot.
        create_parameters.name = "laser-turret"
        local ok_fallback
        ok_fallback, replacement = pcall(function()
            return surface.create_entity(create_parameters)
        end)
        if not ok_fallback then replacement = nil end
    end
    if not (replacement and replacement.valid) then return false end

    local new_max_health = tonumber(replacement.max_health) or old_max_health
    replacement.health = math.max(1, new_max_health * health_ratio)
    pcall(function() replacement.disabled_by_script = disabled_by_script end)
    pcall(function() replacement.destructible = destructible end)
    pcall(function() replacement.minable_flag = minable end)
    pcall(function() replacement.operable = operable end)

    return replacement.name == ENEMY_LASER_TURRET
end

function caverns.on_configuration_changed()
    caverns.on_init()
    if collapse.is_disabled() then
        for _, cd in pairs(storage.cavern_countdowns or {}) do
            for _, cell in pairs(cd.cells or {}) do collapse.untelegraph(cell.telegraph) end
        end
        storage.cavern_countdowns = {}
    end
    -- 2.5.75 moved combat pacing from one surface-wide number to independent
    -- surface:region keys. Numeric legacy keys are obsolete and safe to remove.
    for key in pairs(storage.cavern_combat_cooldowns or {}) do
        if type(key) == "number" then storage.cavern_combat_cooldowns[key] = nil end
    end

    -- 2.7.31: historical room footprints retain their centre and planetary
    -- region. Upgrade only footprints whose exact Yumako/Jellynut soil layout
    -- proves that they are one of The Cave's generated Gleba Progression Rooms.
    if storage.gleba_wild_plant_migration_version ~= GLEBA_WILD_PLANT_MIGRATION_VERSION then
        for surface_index, footprints in pairs(storage.cavern_room_footprints or {}) do
            local surface = game.surfaces[surface_index]
            if surface and surface.valid then
                for _, footprint in ipairs(footprints or {}) do
                    if footprint.region == "gleba" and footprint.cx and footprint.cy then
                        local cx, cy = footprint.cx, footprint.cy
                        local left = surface.get_tile(cx - 8, cy)
                        local right = surface.get_tile(cx + 8, cy)
                        if left and left.valid and left.name == "natural-yumako-soil"
                            and right and right.valid and right.name == "natural-jellynut-soil" then
                            pcall(function()
                                region_features.populate_gleba_progression_wild_plants(
                                    surface, cx, cy, 20
                                )
                            end)
                        end
                    end
                end
            end
        end
        storage.gleba_wild_plant_migration_version = GLEBA_WILD_PLANT_MIGRATION_VERSION
    end

    if storage.the_cave_enemy_laser_migration_version == ENEMY_LASER_MIGRATION_VERSION then return end

    local candidates = {}
    local removed_support = 0

    -- Preserve only the gun-turret maintenance records. Old laser records are
    -- converted below and all of their helper entities are destroyed.
    local guards = storage.the_cave_enemy_guard_turrets or {}
    local gun_guards = {}
    for _, rec in pairs(guards) do
        local turret = rec and rec.turret
        if turret and turret.valid and turret.name == "gun-turret" then
            gun_guards[#gun_guards + 1] = { turret = turret, name = turret.name }
        else
            add_legacy_laser_candidate(candidates, turret)
        end
        if rec then removed_support = removed_support + destroy_legacy_support(rec.support) end
    end
    storage.the_cave_enemy_guard_turrets = gun_guards

    -- Find orphaned helper entities that lost their storage record when the
    -- original laser turret died. Any adjacent enemy vanilla laser is also an
    -- old cavern guard and is migrated before the helper is removed.
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local helpers = surface.find_entities_filtered {
                name = { LEGACY_LASER_POWER, LEGACY_LASER_POWER_POLE },
            }
            for _, helper in pairs(helpers) do
                if helper.valid then
                    local p = helper.position
                    for _, turret in pairs(surface.find_entities_filtered {
                        name = "laser-turret",
                        force = "enemy",
                        area = { { p.x - 1.5, p.y - 1.5 }, { p.x + 1.5, p.y + 1.5 } },
                    }) do
                        add_legacy_laser_candidate(candidates, turret)
                    end
                    helper.destroy()
                    removed_support = removed_support + 1
                end
            end
        end
    end

    local migrated = 0
    for _, turret in pairs(candidates) do
        if replace_legacy_laser_turret(turret) then migrated = migrated + 1 end
    end

    storage.the_cave_enemy_laser_migration_version = ENEMY_LASER_MIGRATION_VERSION
    if migrated > 0 or removed_support > 0 then
        log("[The Cave] enemy laser migration: replaced " .. migrated
            .. " legacy laser turret(s) and removed " .. removed_support .. " hidden power helper(s)")
    end
end

function caverns.clear_force(force_index)
    for _, key in ipairs({ "cavern_uranium_pity", "cavern_mineral_pity", "cavern_lost_city_pity" }) do
        for _, by_force in pairs(storage[key] or {}) do by_force[force_index] = nil end
    end
end

function caverns.on_surface_deleted(event)
    caverns.scheduled.on_surface_deleted(event)
    local surface_index = event and event.surface_index
    if not surface_index then return end
    for _, key in ipairs({ "cavern_extraction_nest_pacing", "cavern_uranium_pity",
        "cavern_mineral_pity", "cavern_lost_city_pity", "cavern_room_footprints",
        "fortified_vault_generation" }) do
        if storage[key] then storage[key][surface_index] = nil end
    end
    for key in pairs(storage.cavern_combat_cooldowns or {}) do
        if tostring(key):match("^(%d+):") == tostring(surface_index) then
            storage.cavern_combat_cooldowns[key] = nil
        end
    end
    local removed = {}
    for id, room in pairs(storage.cavern_rooms or {}) do
        if room.surface_index == surface_index then
            removed[id] = true
            storage.cavern_rooms[id] = nil
        end
    end
    for unit, id in pairs(storage.cavern_worms or {}) do
        if removed[id] then storage.cavern_worms[unit] = nil end
    end
    for id, countdown in pairs(storage.cavern_countdowns or {}) do
        if countdown.surface_index == surface_index then
            for _, cell in pairs(countdown.cells or {}) do collapse.untelegraph(cell.telegraph) end
            storage.cavern_countdowns[id] = nil
        end
    end
end

function caverns.tick_enemy_guards(tick)
    -- Light-weight maintenance for generated enemy gun turrets only. Enemy
    -- laser turrets use their own void energy source and need no runtime work.
    if (tick or game.tick) % 10 ~= 0 then return end
    local guards = storage.the_cave_enemy_guard_turrets
    if not guards then return end
    for i = #guards, 1, -1 do
        local rec = guards[i]
        local turret = rec.turret
        if not (turret and turret.valid and turret.name == "gun-turret") then
            if rec then destroy_legacy_support(rec.support) end
            table.remove(guards, i)
        else
            refill_enemy_gun_turret(turret)
        end
    end
end


return caverns
