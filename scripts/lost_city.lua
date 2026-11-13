local physical = require("scripts.player_physical")
local child_state = require("scripts.cave_child_state")
local cave_boxes = require("scripts.cave_item_boxes")
local cave_timing = require("scripts.cave_operation_time")
-- Procedural Lost City extraction operation.
--
-- Medium+ ordinary empty rooms can reveal a natural entrance. Each entrance
-- owns an unbounded, chunk-generated settlement surface. One contact offers
-- a repeatable stream of value-balanced trades shared by the whole Force. The first entrant
-- starts a 60-minute deadline; anyone still below
-- at 00:00 dies and the parent entrance seals permanently unless completed
-- trades have extended the shared deadline.

local depth_levels = require("scripts.depth_levels")
local reward_policy = require("scripts.reward_policy")
local cave_evolution = require("scripts.cave_evolution")
local cave_placement = require("scripts.cave_placement")
local world = require("scripts.world")
local cave_policy = require("scripts.cave_policy")

local lost_city = {}
lost_city.scheduled = require("scripts.advancing_caves")

local SURFACE_PREFIX = "the-cave-lost-city-"
local ENTRANCE_NAME = "the-cave-lost-city-entrance"
local EXIT_NAME = "the-cave-lost-city-exit"
local SUPPLY_CRATE_NAME = "the-cave-lost-city-supply-crate"
local REWARD_CRATE_NAME = "the-cave-lost-city-reward-crate"
local INFO_PANEL_NAME = "display-panel"
local ITEM_DOWN_INPUT = "the-cave-lost-city-item-down-input"
local ITEM_DOWN_OUTPUT = "the-cave-lost-city-item-down-output"
local ITEM_UP_INPUT = "the-cave-lost-city-item-up-input"
local ITEM_UP_OUTPUT = "the-cave-lost-city-item-up-output"
local HOUSE_PREFIX = "the-cave-lost-city-house"
local PARENT_MIN_DISTANCE = 400
local LEGACY_OPERATION_TICKS = 30 * 60 * 60
local OPERATION_TICKS = cave_timing.duration(LEGACY_OPERATION_TICKS)
local TIMER_INTERVAL = 60
local INITIAL_GENERATION_RADIUS = 4
local MISSION_HUB_RADIUS = 16
local NPC_APPROACH_TIMEOUT = 15 * 60
local NEXT_TRADE_DELAY_TICKS = 3 * 60
local GUI_DIALOG = "the_cave_lost_city_dialog"
local GUI_CLOSE = "the_cave_lost_city_dialog_close"
local GUI_HUD = "the_cave_lost_city_hud"
local GUI_REWARD = "the_cave_lost_city_reward_choice"
local GUI_REWARD_BUTTON_PREFIX = "the_cave_lost_city_reward_"

local function operation_duration_ticks(record)
    if record and (record.started_tick or record.suspended_remaining_ticks or record.status == "waiting") then
        return record.operation_duration_ticks or LEGACY_OPERATION_TICKS
    end
    return OPERATION_TICKS
end

local function enabled()
    return cave_policy.LOST_VILLAGE_GENERATION_ENABLED
end
local CONTRACT_MINUTES = 8
local CONTRACT_MAX_MINUTES = 12
local REWARD_MULTIPLIER_MIN = 0.55
local REWARD_MULTIPLIER_MAX = 0.70
local CONTRACT_VERSION = 7
local TRANSFER_LAYOUT_VERSION = 1
local UPPER_PORT_LAYOUT_VERSION = 2
local UPPER_TIMER_LAYOUT_VERSION = 3

local RUIN_TEMPLATES = { small = {}, medium = {}, large = {} }

for i = 1, 16 do
    RUIN_TEMPLATES.small[#RUIN_TEMPLATES.small + 1] =
        require("scripts.lost_city_ruins.small.sabset" .. i)
end
for i = 1, 68 do
    RUIN_TEMPLATES.medium[#RUIN_TEMPLATES.medium + 1] =
        require("scripts.lost_city_ruins.medium.mabset" .. i)
end
for i = 1, 28 do
    RUIN_TEMPLATES.large[#RUIN_TEMPLATES.large + 1] =
        require("scripts.lost_city_ruins.large.abset" .. i)
end

local ROLE_ORDER = {
    "doctor",
    "soldier",
    "engineer",
    "electrician",
    "plumber",
    "gas",
    "miner",
}

local ROLE_COLORS = {
    doctor = { r = 0.45, g = 0.95, b = 0.65 },
    soldier = { r = 0.35, g = 0.75, b = 0.30 },
    engineer = { r = 0.95, g = 0.62, b = 0.15 },
    electrician = { r = 1.00, g = 0.88, b = 0.15 },
    plumber = { r = 0.25, g = 0.70, b = 1.00 },
    gas = { r = 0.70, g = 0.35, b = 0.95 },
    miner = { r = 0.72, g = 0.50, b = 0.25 },
}

-- Factorio 2.0 chart-tag text is a plain string, not a LocalisedString.
-- Dialogue and HUD text remain fully localised; only the small map labels use
-- these stable English names.
local ROLE_TAG_TEXT = {
    doctor = "Villager",
    soldier = "Villager",
    engineer = "Villager",
    electrician = "Villager",
    plumber = "Villager",
    gas = "Villager",
    miner = "Villager",
}

-- Every visible contact is a Villager, but internal request families keep the
-- dialogue and supply theme coherent. Later trades rotate away from the two
-- most recent families, so a Miner can no longer ask for ore forever and a
-- differently shuffled plate contract does not count as meaningful variety.
local ROLE_REQUIREMENTS = {
    doctor = {
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack", "utility-science-pack",
        "space-science-pack", "electronic-circuit", "advanced-circuit",
        "processing-unit", "battery", "low-density-structure", "lab",
    },
    soldier = {
        "firearm-magazine", "piercing-rounds-magazine", "uranium-rounds-magazine",
        "shotgun-shell", "piercing-shotgun-shell", "grenade", "cluster-grenade",
        "rocket", "explosive-rocket", "cannon-shell", "explosive-cannon-shell",
        "submachine-gun", "combat-shotgun", "rocket-launcher", "flamethrower",
        "gun-turret", "laser-turret", "flamethrower-turret", "radar", "stone-wall",
        "land-mine", "defender-capsule", "distractor-capsule", "destroyer-capsule",
    },
    engineer = {
        "electronic-circuit", "advanced-circuit", "processing-unit",
        "transport-belt", "underground-belt", "splitter", "fast-transport-belt",
        "fast-underground-belt", "fast-splitter", "inserter", "fast-inserter",
        "bulk-inserter", "electric-mining-drill", "assembling-machine-1",
        "assembling-machine-2", "assembling-machine-3", "electric-furnace",
        "electric-engine-unit", "flying-robot-frame", "construction-robot",
        "logistic-robot", "roboport", "productivity-module-2", "speed-module-2",
        "efficiency-module-2",
    },
    electrician = {
        "small-electric-pole", "medium-electric-pole", "big-electric-pole",
        "accumulator", "substation", "solar-panel", "power-switch", "steam-engine",
        "beacon", "heat-pipe", "heat-exchanger", "steam-turbine", "nuclear-reactor",
    },
    plumber = {
        "pipe", "pipe-to-ground", "pump", "storage-tank", "offshore-pump",
        "chemical-plant", "oil-refinery", "pumpjack", "heat-exchanger",
    },
    gas = {
        "chemical-plant", "oil-refinery", "pumpjack", "solid-fuel",
        "rocket-fuel", "sulfur", "plastic-bar", "explosives", "low-density-structure",
        "space-platform-foundation", "cargo-bay", "asteroid-collector", "crusher", "thruster",
    },
    miner = {
        "iron-plate", "copper-plate", "steel-plate", "iron-gear-wheel",
        "copper-cable", "stone-brick", "concrete", "refined-concrete", "rail",
    },
}

-- Expensive equipment must remain a serious contract without becoming an
-- absurd multi-stack tax. These are hard per-contract ceilings after the
-- production-rate calculation, and intentionally include the two cases that
-- made the previous build unfair: uranium magazines and module 2s.
local REQUEST_ITEM_CAPS = {
    ["iron-plate"] = 3000,
    ["copper-plate"] = 3000,
    ["steel-plate"] = 1500,
    ["iron-gear-wheel"] = 1500,
    ["copper-cable"] = 3000,
    ["stone-brick"] = 2000,
    ["concrete"] = 2000,
    ["refined-concrete"] = 1000,
    ["rail"] = 1000,
    ["automation-science-pack"] = 1000,
    ["logistic-science-pack"] = 1000,
    ["military-science-pack"] = 750,
    ["chemical-science-pack"] = 200,
    ["production-science-pack"] = 150,
    ["utility-science-pack"] = 150,
    ["space-science-pack"] = 300,
    ["electronic-circuit"] = 2000,
    ["advanced-circuit"] = 1000,
    ["processing-unit"] = 300,
    ["battery"] = 200,
    ["low-density-structure"] = 100,
    ["lab"] = 20,
    ["firearm-magazine"] = 1000,
    ["piercing-rounds-magazine"] = 200,
    ["uranium-rounds-magazine"] = 80,
    ["shotgun-shell"] = 500,
    ["piercing-shotgun-shell"] = 300,
    ["grenade"] = 300,
    ["cluster-grenade"] = 100,
    ["rocket"] = 300,
    ["explosive-rocket"] = 100,
    ["cannon-shell"] = 200,
    ["explosive-cannon-shell"] = 150,
    ["submachine-gun"] = 20,
    ["combat-shotgun"] = 15,
    ["rocket-launcher"] = 15,
    ["flamethrower"] = 10,
    ["gun-turret"] = 150,
    ["laser-turret"] = 20,
    ["flamethrower-turret"] = 30,
    ["radar"] = 150,
    ["stone-wall"] = 2000,
    ["land-mine"] = 200,
    ["defender-capsule"] = 50,
    ["distractor-capsule"] = 30,
    ["destroyer-capsule"] = 20,
    ["transport-belt"] = 2000,
    ["underground-belt"] = 500,
    ["splitter"] = 200,
    ["fast-transport-belt"] = 1500,
    ["fast-underground-belt"] = 400,
    ["fast-splitter"] = 150,
    ["inserter"] = 500,
    ["fast-inserter"] = 400,
    ["bulk-inserter"] = 200,
    ["electric-mining-drill"] = 100,
    ["assembling-machine-1"] = 100,
    ["assembling-machine-2"] = 80,
    ["assembling-machine-3"] = 40,
    ["electric-furnace"] = 80,
    ["electric-engine-unit"] = 100,
    ["flying-robot-frame"] = 80,
    ["construction-robot"] = 50,
    ["logistic-robot"] = 50,
    ["roboport"] = 10,
    ["productivity-module-2"] = 10,
    ["speed-module-2"] = 12,
    ["efficiency-module-2"] = 12,
    ["small-electric-pole"] = 1000,
    ["medium-electric-pole"] = 500,
    ["big-electric-pole"] = 200,
    ["accumulator"] = 100,
    ["substation"] = 30,
    ["solar-panel"] = 100,
    ["power-switch"] = 20,
    ["steam-engine"] = 100,
    ["beacon"] = 12,
    ["heat-pipe"] = 200,
    ["heat-exchanger"] = 20,
    ["steam-turbine"] = 30,
    ["nuclear-reactor"] = 2,
    ["pipe"] = 1000,
    ["pipe-to-ground"] = 400,
    ["pump"] = 40,
    ["storage-tank"] = 30,
    ["offshore-pump"] = 20,
    ["chemical-plant"] = 20,
    ["oil-refinery"] = 10,
    ["pumpjack"] = 20,
    ["solid-fuel"] = 400,
    ["rocket-fuel"] = 100,
    ["sulfur"] = 400,
    ["plastic-bar"] = 400,
    ["explosives"] = 300,
    ["space-platform-foundation"] = 500,
    ["cargo-bay"] = 20,
    ["asteroid-collector"] = 20,
    ["crusher"] = 20,
    ["thruster"] = 20,
}

-- Production history may raise a request, but it may never turn an advanced
-- Village trade into a token five-item delivery. Floors and caps are applied
-- before the per-trade growth multiplier is finalized.
local REQUEST_ITEM_FLOORS = {
    ["iron-plate"] = 1000,
    ["copper-plate"] = 1000,
    ["steel-plate"] = 500,
    ["iron-gear-wheel"] = 500,
    ["copper-cable"] = 1000,
    ["stone-brick"] = 750,
    ["concrete"] = 750,
    ["refined-concrete"] = 300,
    ["rail"] = 400,
    ["automation-science-pack"] = 400,
    ["logistic-science-pack"] = 400,
    ["military-science-pack"] = 300,
    ["chemical-science-pack"] = 50,
    ["production-science-pack"] = 50,
    ["utility-science-pack"] = 50,
    ["space-science-pack"] = 100,
    ["electronic-circuit"] = 750,
    ["advanced-circuit"] = 300,
    ["processing-unit"] = 100,
    ["battery"] = 100,
    ["low-density-structure"] = 50,
    ["lab"] = 20,
    ["firearm-magazine"] = 500,
    ["piercing-rounds-magazine"] = 100,
    ["uranium-rounds-magazine"] = 20,
    ["shotgun-shell"] = 200,
    ["piercing-shotgun-shell"] = 100,
    ["grenade"] = 100,
    ["cluster-grenade"] = 30,
    ["rocket"] = 100,
    ["explosive-rocket"] = 50,
    ["cannon-shell"] = 50,
    ["explosive-cannon-shell"] = 50,
    ["submachine-gun"] = 5,
    ["combat-shotgun"] = 5,
    ["rocket-launcher"] = 5,
    ["flamethrower"] = 4,
    ["gun-turret"] = 50,
    ["laser-turret"] = 10,
    ["flamethrower-turret"] = 10,
    ["radar"] = 50,
    ["stone-wall"] = 750,
    ["land-mine"] = 100,
    ["defender-capsule"] = 20,
    ["distractor-capsule"] = 10,
    ["destroyer-capsule"] = 5,
    ["transport-belt"] = 750,
    ["underground-belt"] = 150,
    ["splitter"] = 75,
    ["fast-transport-belt"] = 500,
    ["fast-underground-belt"] = 100,
    ["fast-splitter"] = 50,
    ["inserter"] = 200,
    ["fast-inserter"] = 150,
    ["bulk-inserter"] = 75,
    ["electric-mining-drill"] = 40,
    ["assembling-machine-1"] = 40,
    ["assembling-machine-2"] = 30,
    ["assembling-machine-3"] = 15,
    ["electric-furnace"] = 30,
    ["electric-engine-unit"] = 50,
    ["flying-robot-frame"] = 30,
    ["construction-robot"] = 20,
    ["logistic-robot"] = 20,
    ["roboport"] = 4,
    ["productivity-module-2"] = 4,
    ["speed-module-2"] = 4,
    ["efficiency-module-2"] = 4,
    ["small-electric-pole"] = 400,
    ["medium-electric-pole"] = 200,
    ["big-electric-pole"] = 75,
    ["accumulator"] = 50,
    ["substation"] = 10,
    ["solar-panel"] = 50,
    ["power-switch"] = 10,
    ["steam-engine"] = 40,
    ["beacon"] = 4,
    ["heat-pipe"] = 50,
    ["heat-exchanger"] = 8,
    ["steam-turbine"] = 10,
    ["nuclear-reactor"] = 1,
    ["pipe"] = 400,
    ["pipe-to-ground"] = 150,
    ["pump"] = 20,
    ["storage-tank"] = 10,
    ["offshore-pump"] = 10,
    ["chemical-plant"] = 10,
    ["oil-refinery"] = 5,
    ["pumpjack"] = 10,
    ["solid-fuel"] = 200,
    ["rocket-fuel"] = 50,
    ["sulfur"] = 200,
    ["plastic-bar"] = 200,
    ["explosives"] = 100,
    ["space-platform-foundation"] = 200,
    ["cargo-bay"] = 5,
    ["asteroid-collector"] = 5,
    ["crusher"] = 5,
    ["thruster"] = 5,
}

local REWARD_POOLS = {
    infrastructure = {
        "steel-furnace", "assembling-machine-1", "electric-mining-drill",
        "assembling-machine-2", "assembling-machine-3",
        "accumulator", "substation", "solar-panel", "construction-robot",
        "logistic-robot", "roboport", "beacon",
    },
    combat = {
        "gun-turret", "grenade", "piercing-rounds-magazine", "uranium-rounds-magazine",
        "explosive-rocket", "laser-turret", "land-mine", "defender-capsule", "destroyer-capsule",
        "energy-shield-equipment", "personal-roboport-equipment",
    },
    advanced = {
        "advanced-circuit", "battery", "electric-engine-unit", "processing-unit",
        "low-density-structure", "rocket-fuel",
        "productivity-module-2", "speed-module-2", "efficiency-module-2",
        "heat-pipe", "heat-exchanger", "steam-turbine", "nuclear-reactor",
        "uranium-fuel-cell",
    },
}

local REWARD_POOL_ORDER = { "infrastructure", "combat", "advanced" }

-- Reward quantities use gameplay caps, never a generic number of stacks.
-- These limits prevent a fallback valuation from turning one contract into
-- hundreds of expensive machines while still allowing useful team packages.
local REWARD_ITEM_CAPS = {
    ["steel-furnace"] = 50,
    ["assembling-machine-1"] = 20,
    ["electric-mining-drill"] = 20,
    ["assembling-machine-2"] = 12,
    ["assembling-machine-3"] = 8,
    ["accumulator"] = 50,
    ["substation"] = 12,
    ["solar-panel"] = 50,
    ["construction-robot"] = 50,
    ["logistic-robot"] = 50,
    ["roboport"] = 4,
    ["beacon"] = 4,
    ["gun-turret"] = 50,
    ["grenade"] = 100,
    ["piercing-rounds-magazine"] = 200,
    ["uranium-rounds-magazine"] = 80,
    ["explosive-rocket"] = 100,
    ["laser-turret"] = 20,
    ["land-mine"] = 200,
    ["defender-capsule"] = 50,
    ["destroyer-capsule"] = 20,
    ["energy-shield-equipment"] = 2,
    ["personal-roboport-equipment"] = 2,
    ["advanced-circuit"] = 200,
    ["battery"] = 200,
    ["electric-engine-unit"] = 100,
    ["processing-unit"] = 120,
    ["low-density-structure"] = 100,
    ["rocket-fuel"] = 50,
    ["productivity-module-2"] = 6,
    ["speed-module-2"] = 6,
    ["efficiency-module-2"] = 6,
    ["heat-pipe"] = 100,
    ["heat-exchanger"] = 10,
    ["steam-turbine"] = 20,
    ["nuclear-reactor"] = 1,
    ["uranium-fuel-cell"] = 50,
}

local NPC_POSITIONS = {
    { x = -56, y = 0 },
    { x = 56, y = 0 },
    { x = 0, y = -56 },
    { x = 0, y = 56 },
    { x = -48, y = -48 },
    { x = 48, y = -48 },
    { x = -48, y = 48 },
    { x = 48, y = 48 },
}

local RUIN_HALF_SIZE = { small = 4, medium = 8, large = 16 }

-- Engine autoplace on an unassociated custom surface can see prototypes from
-- every installed planet. Lost City is deliberately a Nauvis-only world, even
-- when Space Age or The Cave's Everything on Nauvis mode is enabled.
local NAUVIS_TILES = {
    "water", "deepwater",
    "grass-1", "grass-2", "grass-3", "grass-4",
    "dirt-1", "dirt-2", "dirt-3", "dirt-4", "dirt-5", "dirt-6", "dirt-7",
    "dry-dirt", "sand-1", "sand-2", "sand-3",
    "red-desert-0", "red-desert-1", "red-desert-2", "red-desert-3",
}

local NAUVIS_ENTITIES = {
    "iron-ore", "copper-ore", "coal", "stone", "uranium-ore", "crude-oil",
    "fish", "big-rock", "huge-rock", "big-sand-rock",
    "biter-spawner", "spitter-spawner",
    "small-worm-turret", "medium-worm-turret", "big-worm-turret", "behemoth-worm-turret",
    "dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree",
}

local NAUVIS_DECORATIVES = {
    "brown-asterisk", "brown-asterisk-mini", "brown-carpet-grass",
    "green-asterisk", "green-asterisk-mini", "green-bush-mini", "green-carpet-grass",
    "green-croton", "green-desert-bush", "green-hairy-grass", "green-pita", "green-pita-mini",
    "red-asterisk", "red-croton", "red-desert-bush", "white-desert-bush",
    "cracked-mud-decal", "dark-mud-decal", "light-mud-decal", "red-desert-decal",
    "sand-decal", "sand-dune-decal", "small-rock", "small-sand-rock",
    "sand-rock-big", "sand-rock-medium", "sand-rock-small",
}

local function root()
    storage.the_cave_lost_city = storage.the_cave_lost_city or {}
    local r = storage.the_cave_lost_city
    r.next_id = r.next_id or 1
    r.by_id = r.by_id or {}
    r.by_surface = r.by_surface or {}
    r.by_entity = r.by_entity or {}
    r.active_by_force = r.active_by_force or {}
    r.completed_by_force = r.completed_by_force or {}
    r.entrances_by_parent = r.entrances_by_parent or {}
    r.pending_respawns = r.pending_respawns or {}
    return r
end

local function valid_surface(index)
    local surface = index and game.get_surface(index)
    return surface and surface.valid and surface or nil
end

local function valid_player(index)
    local player = index and game.get_player(index)
    return player and player.valid and player or nil
end

local function surface_has_prefix(surface)
    return surface and surface.valid and type(surface.name) == "string"
        and surface.name:sub(1, #SURFACE_PREFIX) == SURFACE_PREFIX
end

function lost_city.is_lost_city_surface(surface)
    return surface_has_prefix(surface)
end

local function copy_position(position)
    return { x = position.x, y = position.y }
end

local function record_for_surface(surface)
    if not (surface and surface.valid) then return nil end
    local id = root().by_surface[surface.index]
    return id and root().by_id[id] or nil
end

local function find_unit(surface_index, unit_number, names)
    local surface = valid_surface(surface_index)
    if not (surface and unit_number) then return nil end
    local r = root()
    r.entity_cache = r.entity_cache or {}
    local cached = r.entity_cache[unit_number]
    if cached and cached.valid and cached.surface == surface then
        local matches = cached.name == names
        if type(names) == "table" then
            for _, name in pairs(names) do if cached.name == name then matches = true break end end
        end
        if matches then return cached end
    end
    r.entity_cache[unit_number] = nil
    for _, entity in pairs(surface.find_entities_filtered { name = names }) do
        if entity.valid and entity.unit_number == unit_number then
            r.entity_cache[unit_number] = entity
            return entity
        end
    end
    return nil
end

local function record_for_entity(entity)
    if not (entity and entity.valid and entity.unit_number) then return nil end
    local r = root()
    local id = r.by_entity[entity.unit_number]
    return id and r.by_id[id] or nil
end

local function add_parent_record(parent_surface_index, city_id)
    local r = root()
    local list = r.entrances_by_parent[parent_surface_index]
    if not list then
        list = {}
        r.entrances_by_parent[parent_surface_index] = list
    end
    list[#list + 1] = city_id
end

local function remove_parent_record(parent_surface_index, city_id)
    local list = root().entrances_by_parent[parent_surface_index]
    if not list then return end
    for index = #list, 1, -1 do
        if list[index] == city_id then table.remove(list, index) end
    end
end

-- Closed/sealed entrances deliberately remain in this registry, so their
-- location continues to reserve the full 400-tile same-type spacing forever.
function lost_city.has_parent_entrance_within(surface, position, radius)
    if not (surface and surface.valid and position) then return false end
    local radius_squared = (tonumber(radius) or PARENT_MIN_DISTANCE) ^ 2
    for _, id in ipairs(root().entrances_by_parent[surface.index] or {}) do
        local record = root().by_id[id]
        local entrance = record and record.entrance_position
        if entrance then
            local dx, dy = entrance.x - position.x, entrance.y - position.y
            if dx * dx + dy * dy < radius_squared then return true end
        end
    end
    return false
end

local function zone_for_position(position)
    local level = depth_levels.level_for_position(position)
    return level and level.id or "easy"
end

local function direction_value(value)
    if type(value) == "number" then return value end
    if type(value) == "string" and defines.direction[value] then return defines.direction[value] end
    return nil
end

local function sorted_keys(t)
    local keys = {}
    for key in pairs(t or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local RUIN_LOOT_TYPES = {
    small = { 1, 2 },
    medium = { 2, 4 },
    large = { 4, 7 },
}

local function populate_template_inventory(entity, item_plan, generator, ruin_size)
    if not (entity and entity.valid and item_plan) then return end
    local inventory = entity.get_inventory(defines.inventory.chest)
    if not inventory then return end
    local candidates = {}
    for _, item_name in ipairs(sorted_keys(item_plan)) do
        local specification = item_plan[item_name]
        if prototypes.item[item_name] and reward_policy.is_allowed(item_name)
            and type(specification) == "table" then
            local minimum = math.max(0, math.floor(tonumber(specification.min) or 0))
            local maximum = math.max(minimum, math.floor(tonumber(specification.max) or minimum))
            -- Source templates assumed containers with hundreds of slots.
            -- Lost City keeps the variety but scales the haul to 48-slot ruins.
            local rolled = generator(minimum, maximum)
            if rolled > 0 then
                local stack_size = prototypes.item[item_name].stack_size or 100
                candidates[#candidates + 1] = {
                    name = item_name,
                    count = math.min(stack_size * 2, math.max(1, math.floor(rolled * 0.20 + 0.5))),
                }
            end
        end
    end
    for i = #candidates, 2, -1 do
        local j = generator(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end
    local limits = RUIN_LOOT_TYPES[ruin_size] or RUIN_LOOT_TYPES.small
    local wanted = math.min(#candidates, generator(limits[1], limits[2]))
    for index = 1, wanted do
        local item = candidates[index]
        inventory.insert { name = item.name, count = item.count }
    end
end

local function place_ruin_template(surface, template, center, generator, owner_force, ruin_size)
    if not (surface and surface.valid and template and center) then return end
    local tiles = {}
    for _, tile in ipairs(template.tiles or {}) do
        if tile[1] and prototypes.tile[tile[1]] and tile[2] then
            tiles[#tiles + 1] = {
                name = tile[1],
                position = { x = center.x + tile[2].x, y = center.y + tile[2].y },
            }
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles, true, true) end

    for _, definition in ipairs(template.entities or {}) do
        local name, offset, options = definition[1], definition[2], definition[3] or {}
        if name and offset and prototypes.entity[name] then
            local parameters = {
                name = name,
                position = { x = center.x + offset.x, y = center.y + offset.y },
                create_build_effect_smoke = false,
            }
            local direction = direction_value(options.dir)
            if direction then parameters.direction = direction end
            local is_house = name:sub(1, #HOUSE_PREFIX) == HOUSE_PREFIX
            -- Ruin buildings belong to the expedition Force. A
            -- simple-entity-with-owner otherwise defaults to a hostile Force,
            -- which produces Factorio's "Enemy structures cannot be mined"
            -- message even when the prototype itself is minable.
            if is_house and owner_force and owner_force.valid then
                parameters.force = owner_force
            elseif options.force and game.forces[options.force] then
                -- Keep intentional hazards such as biter spawners hostile.
                parameters.force = options.force
            end
            local ok, entity = pcall(function() return surface.create_entity(parameters) end)
            if ok and entity and entity.valid then
                populate_template_inventory(entity, options.items, generator, ruin_size)
                if is_house then
                    entity.destructible = true
                    entity.minable_flag = true
                end
            end
        end
    end
end

local function clear_area_entities(surface, area, protected)
    for _, entity in pairs(surface.find_entities_filtered { area = area }) do
        local keep = protected and entity.unit_number and protected[entity.unit_number]
        if entity.valid and not keep and entity.type ~= "character" then entity.destroy() end
    end
end

local function chunk_key(chunk_position)
    return tostring(chunk_position.x) .. ":" .. tostring(chunk_position.y)
end

local function chunk_seed(record, chunk_position)
    local value = (record.seed or 1)
        + chunk_position.x * 73856093
        + chunk_position.y * 19349663
    return math.abs(value % 2147483646) + 1
end

local function deterministic_roll(record, chunk_position, salt)
    -- Factorio's seeded generator removes the diagonal correlations produced
    -- by a raw linear coordinate hash while remaining multiplayer-safe.
    local value = (record.seed or 1)
        + chunk_position.x * 73856093
        + chunk_position.y * 19349663
        + salt * 83492791
    local seed = math.abs(value % 2147483646) + 1
    return game.create_random_generator(seed)()
end

local function ruin_size_for_chunk(record, chunk_position)
    local district = {
        x = math.floor(chunk_position.x / 4),
        y = math.floor(chunk_position.y / 4),
    }
    -- Four-by-four-chunk districts produce broad dense and sparse regions,
    -- while the independent local roll prevents visible district borders.
    local district_density = deterministic_roll(record, district, 11)
    local spawn_chance = 0.28 + district_density * 0.42
    if math.abs(chunk_position.x) <= 4 and math.abs(chunk_position.y) <= 4 then
        spawn_chance = math.min(0.78, spawn_chance + 0.10)
    end
    if deterministic_roll(record, chunk_position, 17) >= spawn_chance then return nil end

    local size_roll = deterministic_roll(record, chunk_position, 23)
    if size_roll < 0.10 then return "large" end
    if size_roll < 0.42 then return "medium" end
    return "small"
end

local function ruin_center_for_chunk(chunk_position, half_size, generator)
    local left, top = chunk_position.x * 32, chunk_position.y * 32
    if half_size == 16 then return { x = left + 16, y = top + 16 } end
    return {
        x = left + generator(half_size, 32 - half_size),
        y = top + generator(half_size, 32 - half_size),
    }
end

local function ruin_area(center, half_size)
    return {
        { center.x - half_size, center.y - half_size },
        { center.x + half_size, center.y + half_size },
    }
end

local function site_has_blocked_tiles(surface, area)
    local ok, count = pcall(function()
        return surface.count_tiles_filtered {
            area = area,
            limit = 1,
            collision_mask = { item = true, object = true, water_tile = true },
        }
    end)
    return not ok or count > 0
end

local function clear_natural_site(surface, area, half_size, generator)
    for _, entity in pairs(surface.find_entities_filtered { area = area }) do
        if entity.valid and entity.type ~= "resource" and entity.type ~= "character" then
            local remove = entity.type ~= "tree" or generator() < (half_size / 14)
            if remove then
                pcall(function()
                    entity.destroy { do_cliff_correction = true, raise_destroy = true }
                end)
            end
        end
    end
end

-- Generate only visited chunks. Each chunk is an independent candidate for a
-- jittered 8x8, 16x16 or 32x32 ruin. Natural terrain is never paved globally:
-- water rejects the site, resources survive and some trees remain around it.
local function generate_city_chunk(record, surface, chunk_position)
    if not (record and surface and surface.valid and chunk_position) then return end
    record.generated_chunks = record.generated_chunks or {}
    local key = chunk_key(chunk_position)
    if record.generated_chunks[key] then return end
    record.generated_chunks[key] = true

    -- Reserve only the entrance chunk, not a giant rectangular mission zone.
    if chunk_position.x == 0 and chunk_position.y == 0 then return end

    local size = ruin_size_for_chunk(record, chunk_position)
    if not size then return end
    local generator = game.create_random_generator(chunk_seed(record, chunk_position))
    local half_size = RUIN_HALF_SIZE[size]
    local center = ruin_center_for_chunk(chunk_position, half_size, generator)
    local area = ruin_area(center, half_size)
    if site_has_blocked_tiles(surface, area) then return end

    clear_natural_site(surface, area, half_size, generator)
    local templates = RUIN_TEMPLATES[size]
    local template = templates[generator(1, #templates)]
    local force = game.forces[record.owner_force_index] or game.forces.player
    place_ruin_template(surface, template, center, generator, force, size)
end

local function prepare_mission_hub(record, surface)
    local tiles = {}
    for x = -MISSION_HUB_RADIUS, MISSION_HUB_RADIUS do
        for y = -MISSION_HUB_RADIUS, MISSION_HUB_RADIUS do
            local edge_noise = deterministic_roll(record, { x = x, y = y }, 41) * 3
            if x * x + y * y <= (MISSION_HUB_RADIUS - edge_noise) ^ 2 then
                local tile_roll = deterministic_roll(record, { x = x, y = y }, 47)
                local name = tile_roll < 0.34 and "dirt-6"
                    or (tile_roll < 0.68 and "dirt-7" or "red-desert-3")
                tiles[#tiles + 1] = { name = name, position = { x = x, y = y } }
            end
        end
    end
    surface.set_tiles(tiles, true, true)
    clear_area_entities(surface, {
        { -MISSION_HUB_RADIUS, -MISSION_HUB_RADIUS },
        { MISSION_HUB_RADIUS, MISSION_HUB_RADIUS },
    })
end

local function create_fixed_entity(surface, name, position, force, direction)
    local ok, entity = pcall(function()
        local definition = {
            name = name,
            position = position,
            force = force,
            create_build_effect_smoke = false,
        }
        if direction ~= nil then definition.direction = direction end
        return surface.create_entity(definition)
    end)
    if not ok or not (entity and entity.valid) then return nil end
    entity.destructible = false
    entity.minable_flag = false
    return entity
end

local function configure_indicator_lamp(lamp)
    if not (lamp and lamp.valid) then return nil end
    pcall(function() lamp.operable = false end)
    pcall(function() lamp.always_on = true end)
    return lamp
end

local function copper_connector(entity)
    if not (entity and entity.valid and entity.get_wire_connector) then return nil end
    local ok, connector = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    end)
    return ok and connector and connector.valid and connector or nil
end

local function connect_power_poles(upper, lower)
    local upper_connector = copper_connector(upper)
    local lower_connector = copper_connector(lower)
    if not (upper_connector and lower_connector) then return false end
    local ok, connected = pcall(function()
        return upper_connector.is_connected_to(lower_connector, defines.wire_origin.player)
            or upper_connector.is_connected_to(lower_connector, defines.wire_origin.script)
    end)
    if ok and connected then return true end
    local linked = pcall(function()
        upper_connector.connect_to(lower_connector, false, defines.wire_origin.script)
    end)
    if not linked then return false end
    local verified, result = pcall(function()
        return upper_connector.is_connected_to(lower_connector, defines.wire_origin.player)
            or upper_connector.is_connected_to(lower_connector, defines.wire_origin.script)
    end)
    return verified and result == true
end

local function lost_city_info_panel_text(record)
    return table.concat({
        "UNDERGROUND VILLAGE",
        "",
        "ENTER: Click the passage to enter the underground village.",
        "POWER: Connect your cave grid to this large electric pole before entering.",
        "The linked pole below powers the entry lamp and accepts your village lighting network.",
        "ITEM INPUT: Sends supplies from this surface down into the Underground Village.",
        "SALVAGE OUTPUT: Returns ore, mined buildings and loot from the Underground Village.",
        "",
        "MISSION: One Villager approaches the first entrant and offers repeated shared trades.",
        "SUPPLIES: Deliver requested items to the Mission Supply Crate near the village entrance.",
        "REWARD: Every trade offers Infrastructure, Combat, Advanced Technology or Extra Time.",
        "NEXT OFFER: Item rewards must be collected first; Extra Time starts the next offer immediately.",
        "",
        "DANGER: The village is dark. After 30 seconds without powered lamp coverage, biters attack.",
        "TIME: The first entry starts one shared " .. (operation_duration_ticks(record) / (60 * 60)) .. "-minute timer for the whole team.",
        "DEADLINE: At 00:00 every player still inside dies and the passage seals permanently.",
        "WORLD: The village is an unbounded Nauvis settlement; explore, mine abandoned buildings and salvage loot.",
    }, "\n")
end

local function setup_upper_info_panel(panel, record)
    if not (panel and panel.valid) then return end
    pcall(function() panel.operable = false end)
    pcall(function() panel.display_panel_icon = { type = "virtual", name = "signal-info" } end)
    -- Factorio 2.0 stores this runtime property as a plain string, so the panel
    -- uses the mod's common English server text while all GUI text stays localised.
    pcall(function() panel.display_panel_text = lost_city_info_panel_text(record) end)
    pcall(function() panel.display_panel_always_show = true end)
    pcall(function() panel.display_panel_show_in_chart = true end)
end

local function stored_transfer_direction(record, side, field, fallback)
    record.transfer_directions = record.transfer_directions or { upper = {}, lower = {} }
    record.transfer_directions.upper = record.transfer_directions.upper or {}
    record.transfer_directions.lower = record.transfer_directions.lower or {}
    local store = record.transfer_directions[side]
    if store[field] == nil then store[field] = fallback end
    return store[field]
end

local function create_or_find_port(record, side, field, name, surface, preferred, fallback_direction)
    local unit_field = side .. "_" .. field .. "_unit_number"
    local entity = find_unit(surface.index, record[unit_field], name)
    if entity then
        local direction = stored_transfer_direction(record, side, field, fallback_direction)
        pcall(function() entity.direction = direction end)
        return entity, false
    end
    local position = side == "upper"
        and cave_placement.find_upper_position(surface, name, preferred, 6, record.entrance_position)
        or nil
    if side ~= "upper" then position = surface.find_non_colliding_position(name, preferred, 6, 0.5) end
    if not position then return nil, false end
    local direction = stored_transfer_direction(record, side, field, fallback_direction)
    entity = create_fixed_entity(surface, name, position,
        game.forces[record.owner_force_index] or game.forces.player, direction)
    if not (entity and entity.unit_number) then return nil, false end
    record[unit_field] = entity.unit_number
    return entity, true
end

local function render_object(id)
    if not id then return nil end
    local ok, object = pcall(rendering.get_object_by_id, id)
    return ok and object or nil
end

local function ensure_port_label(record, field, entity, text, color)
    if not (record and entity and entity.valid) then return nil end
    local object = render_object(record[field])
    if object and record[field .. "_unit"] == entity.unit_number then return record[field] end
    if object then object.destroy() end
    object = rendering.draw_text {
        text = text,
        surface = entity.surface,
        target = entity,
        target_offset = { 0, -1.55 },
        color = color,
        alignment = "center",
        vertical_alignment = "middle",
        scale = 0.9,
        only_in_alt_mode = false,
        use_rich_text = true,
    }
    record[field] = object and object.id or nil
    record[field .. "_unit"] = entity.unit_number
    return record[field]
end

local function destroy_transfer_labels(record)
    for _, field in ipairs({
        "upper_item_down_label_id", "upper_item_up_label_id",
        "lower_item_down_label_id", "lower_item_up_label_id",
    }) do
        local object = render_object(record[field])
        if object then pcall(function() object.destroy() end) end
        record[field] = nil
    end
end

local function ensure_upper_item_ports(record, parent)
    local force = game.forces[record.owner_force_index]
    local down = cave_boxes.ensure(record, "upper_input", parent, record.entrance_position,
        ENTRANCE_NAME, true, force, record.upper_item_down_input_unit_number)
    local up = cave_boxes.ensure(record, "upper_output", parent, record.entrance_position,
        ENTRANCE_NAME, false, force, record.upper_item_up_output_unit_number)
    if not (down and up) then return nil, nil end
    record.upper_item_down_input_unit_number, record.upper_item_up_output_unit_number = down.unit_number, up.unit_number
    ensure_port_label(record, "upper_item_down_label_id", down,
        { "the-cave-lost-city.port-upper-input" }, { r = 0.25, g = 0.85, b = 1 })
    ensure_port_label(record, "upper_item_up_label_id", up,
        { "the-cave-lost-city.port-upper-output" }, { r = 0.35, g = 1, b = 0.45 })
    return down, up
end

local function ensure_lower_item_ports(record, surface)
    local force = game.forces[record.owner_force_index]
    local center = record.exit_position or { x = 0, y = -7 }
    local down = cave_boxes.ensure(record, "lower_input", surface, center,
        EXIT_NAME, true, force, record.lower_item_down_output_unit_number)
    local up = cave_boxes.ensure(record, "lower_output", surface, center,
        EXIT_NAME, false, force, record.lower_item_up_input_unit_number)
    if not (down and up) then return false end
    record.lower_item_down_output_unit_number, record.lower_item_up_input_unit_number = down.unit_number, up.unit_number
    ensure_port_label(record, "lower_item_down_label_id", down,
        { "the-cave-lost-city.port-upper-input" }, { r = 0.25, g = 0.85, b = 1 })
    ensure_port_label(record, "lower_item_up_label_id", up,
        { "the-cave-lost-city.port-upper-output" }, { r = 0.35, g = 1, b = 0.45 })
    return true
end

local function connect_item_ports(record)
    local ready = cave_boxes.ready(record)
    if ready then record.item_connections_surface = valid_surface(record.surface_index) end
    return ready
end

-- This part is independent of the child surface. It must succeed at discovery
-- time so players can wire the city before the first person starts the timer.
local function ensure_upper_entrance_infrastructure(record)
    if not record then return nil, nil end
    local parent = valid_surface(record.parent_surface_index)
    local force = game.forces[record.owner_force_index] or game.forces.player
    if not (parent and force and record.entrance_position) then return nil, nil end
    if not cave_placement.entrance_is_playable(parent, record.entrance_position) then return nil, nil end

    local upper = find_unit(record.parent_surface_index,
        record.upper_power_unit_number, "big-electric-pole")
    local created_upper = false
    if not upper then
        local preferred = { x = record.entrance_position.x, y = record.entrance_position.y - 5 }
        local position = cave_placement.find_upper_position(parent, "big-electric-pole", preferred, 12, record.entrance_position)
        upper = position and create_fixed_entity(parent, "big-electric-pole", position, force) or nil
        if not upper then return nil, nil end
        created_upper = true
        record.upper_power_unit_number = upper.unit_number
    end

    local upper_lamp = find_unit(record.parent_surface_index,
        record.upper_indicator_lamp_unit_number, "small-lamp")
    local lamp_position = { x = upper.position.x + 1, y = upper.position.y }
    if not upper_lamp then
        clear_area_entities(parent, {
            { lamp_position.x - 0.35, lamp_position.y - 0.35 },
            { lamp_position.x + 0.35, lamp_position.y + 0.35 },
        }, { [upper.unit_number] = true })
        upper_lamp = create_fixed_entity(parent, "small-lamp", lamp_position, force)
        record.upper_indicator_lamp_unit_number = upper_lamp and upper_lamp.unit_number or nil
    elseif math.abs(upper_lamp.position.x - lamp_position.x) > 0.1
        or math.abs(upper_lamp.position.y - lamp_position.y) > 0.1 then
        clear_area_entities(parent, {
            { lamp_position.x - 0.35, lamp_position.y - 0.35 },
            { lamp_position.x + 0.35, lamp_position.y + 0.35 },
        }, { [upper.unit_number] = true, [upper_lamp.unit_number] = true })
        pcall(function() upper_lamp.teleport(lamp_position) end)
    end
    configure_indicator_lamp(upper_lamp)

    local panel = find_unit(record.parent_surface_index,
        record.upper_info_panel_unit_number, INFO_PANEL_NAME)
    local created_panel = false
    if not panel then
        local preferred = { x = upper.position.x - 2, y = upper.position.y }
        local position = cave_placement.find_upper_position(parent, INFO_PANEL_NAME, preferred, 6, record.entrance_position)
        panel = position and create_fixed_entity(parent, INFO_PANEL_NAME, position, force) or nil
        if not panel then
            if created_upper and upper.valid then upper.destroy() end
            if created_upper then record.upper_power_unit_number = nil end
            return nil, nil
        end
        created_panel = true
        record.upper_info_panel_unit_number = panel.unit_number
    end
    setup_upper_info_panel(panel, record)
    local down, up = ensure_upper_item_ports(record, parent)
    if not (down and up) then
        if created_panel and panel.valid then panel.destroy() end
        if created_panel then record.upper_info_panel_unit_number = nil end
        if created_upper and upper.valid then upper.destroy() end
        if created_upper then record.upper_power_unit_number = nil end
        return nil, nil, nil, nil
    end
    return upper, panel, down, up, upper_lamp
end

local function ensure_power_bridge(record)
    if not record then return false end
    local child = valid_surface(record.surface_index)
    if child and record.power_connections_surface == child then return true end
    local parent = valid_surface(record.parent_surface_index)
    local force = game.forces[record.owner_force_index] or game.forces.player
    if not (parent and force) then return false end

    local upper = ensure_upper_entrance_infrastructure(record)
    if not (upper and child) then return false end

    local lower = find_unit(record.surface_index, record.lower_power_unit_number, "big-electric-pole")
    if not lower then
        lower = create_fixed_entity(child, "big-electric-pole", { x = 0, y = -12 }, force)
        record.lower_power_unit_number = lower and lower.unit_number or nil
    end

    local lamp_position = { x = 1, y = -12 }
    local lamp = find_unit(record.surface_index, record.entry_lamp_unit_number, "small-lamp")
    if not lamp then
        lamp = create_fixed_entity(child, "small-lamp", lamp_position, force)
        record.entry_lamp_unit_number = lamp and lamp.unit_number or nil
        configure_indicator_lamp(lamp)
    elseif math.abs(lamp.position.x - lamp_position.x) > 0.1
        or math.abs(lamp.position.y - lamp_position.y) > 0.1 then
        pcall(function() lamp.teleport(lamp_position) end)
    end
    configure_indicator_lamp(lamp)

    if not (upper and lower) then return false end
    local connected = connect_power_poles(upper, lower)
    if connected then record.power_connections_surface = child end
    return connected
end

local function render_text(surface, target, text, color, scale, target_offset)
    local object = rendering.draw_text {
        text = text,
        surface = surface,
        target = target,
        target_offset = target_offset,
        color = color or { r = 1, g = 1, b = 1 },
        alignment = "center",
        vertical_alignment = "middle",
        scale = scale or 1.05,
        only_in_alt_mode = false,
        use_rich_text = true,
    }
    return object and object.id or nil
end

local function destroy_render(id)
    if not id then return end
    local ok, object = pcall(rendering.get_object_by_id, id)
    if ok and object then pcall(function() object.destroy() end) end
end

-- Versions through 2.7.119 drew a permanent failure/sealed caption after the
-- Village entrance infrastructure was removed, but did not retain its render
-- ID. Remove those orphan render objects by their exact locale identity during
-- migration; no other world text is affected.
local function cleanup_legacy_closed_passage_labels()
    local legacy_keys = {
        ["the-cave-lost-city.label-failed"] = true,
        ["the-cave-lost-city.label-sealed"] = true,
    }
    for _, object in pairs(rendering.get_all_objects("the-cave")) do
        if object.valid and object.type == "text" then
            local ok, text = pcall(function() return object.text end)
            if ok and type(text) == "table" and legacy_keys[text[1]] then
                pcall(function() object.destroy() end)
            end
        end
    end
end

local function item_is_available(force, item_name)
    if not (force and force.valid and prototypes.item[item_name]) then return false end
    local recipe = force.recipes[item_name]
    if recipe and recipe.enabled == true then return true end
    for _, candidate in pairs(force.recipes) do
        if candidate.enabled and not candidate.hidden then
            for _, product in ipairs(candidate.products or {}) do
                if product.type == "item" and product.name == item_name then return true end
            end
        end
    end
    return false
end

local function shuffled_copy(source, generator)
    local result = {}
    for i, value in ipairs(source or {}) do result[i] = value end
    for i = #result, 2, -1 do
        local j = generator(1, i)
        result[i], result[j] = result[j], result[i]
    end
    return result
end

local function expected_amount(component)
    if not component then return 0 end
    local amount = tonumber(component.amount)
    if not amount then
        local minimum = tonumber(component.amount_min) or 0
        local maximum = tonumber(component.amount_max) or minimum
        amount = (minimum + maximum) * 0.5
    end
    return math.max(0, amount * (tonumber(component.probability) or 1))
end

local function value_key(component_type, name)
    return tostring(component_type or "item") .. ":" .. tostring(name)
end

-- Black-market style recipe valuation: raw resources start with a stable base
-- value, then every enabled crafting step adds energy and a transformation
-- margin. Repeated relaxation handles long recipe chains without storing any
-- Lua prototype objects in global state.
local function build_value_table(force)
    local values = {
        [value_key("item", "iron-ore")] = 100,
        [value_key("item", "copper-ore")] = 100,
        [value_key("item", "coal")] = 100,
        [value_key("item", "stone")] = 100,
        [value_key("item", "uranium-ore")] = 450,
        [value_key("item", "wood")] = 100,
        [value_key("item", "raw-fish")] = 250,
        [value_key("fluid", "water")] = 0.5,
        [value_key("fluid", "crude-oil")] = 2.5,
        [value_key("fluid", "steam")] = 0.75,
    }
    local anchored = {}
    for key in pairs(values) do anchored[key] = true end
    for _ = 1, 24 do
        local changed = false
        for _, recipe in pairs(force.recipes) do
            local recipe_name = tostring(recipe.name or "")
            local is_recycling = recipe_name:find("recycling", 1, true) ~= nil
            -- Valuation must include locked recipes as well as researched ones.
            -- Reward selection still uses item_is_available separately, but an
            -- unresearched luxury item must never fall back to a cheap stack price.
            if not recipe.hidden and not is_recycling then
                local ingredient_cost, complete = 0, true
                for _, ingredient in ipairs(recipe.ingredients or {}) do
                    local value = values[value_key(ingredient.type, ingredient.name)]
                    if not value then complete = false break end
                    ingredient_cost = ingredient_cost + value * expected_amount(ingredient)
                end
                if complete and ingredient_cost > 0 then
                    local total_output = 0
                    for _, product in ipairs(recipe.products or {}) do
                        total_output = total_output + expected_amount(product)
                    end
                    if total_output > 0 then
                        local transformation_cost = math.max(1, tonumber(recipe.energy) or 0.5) * 10
                        local unit_value = math.max(1,
                            (ingredient_cost + transformation_cost) * 1.12 / total_output)
                        for _, product in ipairs(recipe.products or {}) do
                            local key = value_key(product.type, product.name)
                            local previous = values[key]
                            if not anchored[key] and (not previous or unit_value < previous) then
                                values[key] = unit_value
                                changed = true
                            end
                        end
                    end
                end
            end
        end
        if not changed then break end
    end
    return values
end

local function item_value(values, item_name)
    local value = values[value_key("item", item_name)]
    if value then return math.max(1, value) end
    local prototype = prototypes.item[item_name]
    local stack_size = prototype and prototype.stack_size or 100
    -- Unknown modded or unreachable recipe chains receive a conservative
    -- one-full-stack value instead of the old cheap four-stack fallback.
    return math.max(1000, 100000 / math.max(1, stack_size))
end

local function item_production(force, item_name)
    local recent_per_minute, total = 0, 0
    for _, surface in pairs(game.surfaces) do
        if not surface_has_prefix(surface) then
            local ok, statistics = pcall(function()
                return force.get_item_production_statistics(surface)
            end)
            if ok and statistics and statistics.valid then
                local flow_ok, flow = pcall(function()
                    return statistics.get_flow_count {
                        name = item_name,
                        category = "input",
                        precision_index = defines.flow_precision_index.one_hour,
                    }
                end)
                if flow_ok then recent_per_minute = recent_per_minute + math.max(0, tonumber(flow) or 0) end
                local total_ok, produced = pcall(function()
                    return statistics.get_input_count(item_name)
                end)
                if total_ok then total = total + math.max(0, tonumber(produced) or 0) end
            end
        end
    end
    return recent_per_minute, total
end

local function make_reward_bundle(pool_name, budget, values, force, generator, requested)
    local candidates, fallback = {}, {}
    for _, item_name in ipairs(REWARD_POOLS[pool_name] or {}) do
        if not requested[item_name] and prototypes.item[item_name]
            and reward_policy.is_allowed(item_name) then
            local candidate = {
                name = item_name,
                value = item_value(values, item_name),
            }
            if item_is_available(force, item_name) then
                candidates[#candidates + 1] = candidate
            else
                fallback[#fallback + 1] = candidate
            end
        end
    end
    candidates = shuffled_copy(candidates, generator)
    fallback = shuffled_copy(fallback, generator)
    -- Loot may contain a technology the Force has not crafted yet. Filling to
    -- three candidates prevents researched-mod combinations from producing a
    -- blank Infrastructure or Combat frame.
    local fallback_index = 1
    while #candidates < 3 and fallback[fallback_index] do
        candidates[#candidates + 1] = fallback[fallback_index]
        fallback_index = fallback_index + 1
    end
    local affordable = {}
    for _, candidate in ipairs(candidates) do
        if candidate.value <= budget * 0.80 then affordable[#affordable + 1] = candidate end
    end
    if #affordable >= math.min(3, #candidates) then candidates = affordable end

    local wanted = math.min(3, #candidates)
    local bundle, spent = {}, 0
    for index = 1, wanted do
        local candidate = candidates[index]
        local remaining_slots = wanted - index + 1
        local share = math.max(0, budget - spent) / remaining_slots
        local count = math.floor(share / candidate.value)
        if count < 1 and candidate.value <= math.max(share, budget - spent) * 1.10 then count = 1 end
        local hard_cap = REWARD_ITEM_CAPS[candidate.name] or 10
        count = math.min(count, hard_cap)
        if count > 0 then
            bundle[#bundle + 1] = { name = candidate.name, count = count }
            spent = spent + count * candidate.value
        end
    end
    if #bundle == 0 and candidates[1] then
        bundle[1] = { name = candidates[1].name, count = 1 }
        spent = candidates[1].value
    end
    return {
        pool = pool_name,
        items = bundle,
        estimated_value = math.floor(spent + 0.5),
        target_value = math.floor(budget + 0.5),
    }
end

local function attach_reward_options(mission, force, generator, values)
    local requested = {}
    for _, requirement in ipairs(mission.requirements or {}) do requested[requirement.name] = true end
    local multiplier = math.min(REWARD_MULTIPLIER_MAX,
        REWARD_MULTIPLIER_MIN + math.max(0, (mission.trade_number or 1) - 1) * 0.02)
    mission.reward_multiplier = multiplier
    mission.reward_budget = math.max(1, (mission.estimated_value or 1) * multiplier)
    mission.reward_options = {}
    for _, pool_name in ipairs(REWARD_POOL_ORDER) do
        mission.reward_options[#mission.reward_options + 1] =
            make_reward_bundle(pool_name, mission.reward_budget, values, force, generator, requested)
    end

    -- Time is an alternative reward, not an automatic difficulty multiplier.
    -- Every offer independently rolls one of the three clear fixed choices.
    local time_choices = { 5, 10, 15 }
    local minutes = time_choices[generator(1, #time_choices)]
    mission.extra_time_minutes = minutes
    mission.reward_options[#mission.reward_options + 1] = {
        pool = "time",
        minutes = minutes,
        estimated_value = 0,
        target_value = math.floor(mission.reward_budget + 0.5),
    }
end

local function revalue_existing_mission(mission, values)
    if not mission then return end
    local total = 0
    if mission.kind == "mining" then
        total = item_value(values, mission.resource) * math.max(0, mission.target or 0)
    else
        for _, requirement in ipairs(mission.requirements or {}) do
            total = total + item_value(values, requirement.name) * math.max(0, requirement.count or 0)
        end
    end
    mission.estimated_value = math.max(1, math.floor(total + 0.5))
end

local function apply_request_floors_to_existing_mission(mission)
    if not mission or mission.kind ~= "supply" or mission.completed then return end
    local trade_multiplier = math.min(2,
        1 + math.max(0, (mission.trade_number or 1) - 1) * 0.10)
    for _, requirement in ipairs(mission.requirements or {}) do
        local floor = REQUEST_ITEM_FLOORS[requirement.name] or 1
        local prototype = prototypes.item[requirement.name]
        local stack_size = prototype and prototype.stack_size or 100
        local cap = REQUEST_ITEM_CAPS[requirement.name] or stack_size
        local minimum = math.min(cap, math.ceil(floor * trade_multiplier))
        requirement.count = math.max(requirement.count or 0, minimum)
    end
end

local mining_mission

local function requirement_mission(role, force, generator, level, trade_number)
    local values = build_value_table(force)
    local eligible = {}
    local enabled = {}
    for _, item_name in ipairs(ROLE_REQUIREMENTS[role] or {}) do
        if item_is_available(force, item_name) then
            local rate, total = item_production(force, item_name)
            local candidate = {
                name = item_name,
                rate = rate,
                total = total,
                value = item_value(values, item_name),
            }
            enabled[#enabled + 1] = candidate
            if total > 0 or rate > 0 then eligible[#eligible + 1] = candidate end
        end
    end
    if #eligible < 2 then eligible = enabled end
    if #eligible < 2 then return mining_mission(force, generator, level, trade_number) end
    eligible = shuffled_copy(eligible, generator)
    local minimum_wanted = math.min(2, #eligible)
    local maximum_wanted = math.min(4, #eligible)
    local wanted = generator(minimum_wanted, maximum_wanted)
    local challenge_minutes = math.min(CONTRACT_MAX_MINUTES,
        CONTRACT_MINUTES + math.max(0, level - 1))
    local requirements, estimated_value = {}, 0
    for i = 1, wanted do
        local candidate = eligible[i]
        local rate = candidate.rate
        if rate <= 0 and candidate.total > 0 then
            local elapsed_minutes = math.max(1, game.tick / 3600)
            rate = math.min(candidate.total / elapsed_minutes, candidate.total)
        end
        local count
        if rate > 0 then
            count = math.ceil(rate * challenge_minutes)
        else
            count = math.max(1, math.floor((20000 * math.max(1, level)) / candidate.value + 0.5))
        end
        local trade_multiplier = math.min(2, 1 + math.max(0, (trade_number or 1) - 1) * 0.10)
        count = math.max(count, REQUEST_ITEM_FLOORS[candidate.name] or 1)
        count = math.ceil(count * trade_multiplier)
        local stack_size = prototypes.item[candidate.name].stack_size or 100
        local hard_cap = REQUEST_ITEM_CAPS[candidate.name] or stack_size
        count = math.max(1, math.min(count, hard_cap))
        requirements[#requirements + 1] = {
            name = candidate.name,
            count = count,
        }
        estimated_value = estimated_value + candidate.value * count
    end
    local mission = {
        kind = "supply",
        role = role,
        story_variant = generator(1, 2),
        requirements = requirements,
        challenge_minutes = challenge_minutes,
        estimated_value = math.floor(estimated_value + 0.5),
        level = level,
        trade_number = trade_number or 1,
    }
    attach_reward_options(mission, force, generator, values)
    return mission
end

mining_mission = function(force, generator, level, trade_number)
    local values = build_value_table(force)
    local resources = { "iron-ore", "copper-ore", "coal", "stone" }
    local uranium = force.technologies["uranium-processing"]
    if uranium and uranium.researched and prototypes.entity["uranium-ore"] then
        resources[#resources + 1] = "uranium-ore"
    end
    local resource = resources[generator(1, #resources)]
    local rate = item_production(force, resource)
    local challenge_minutes = math.min(CONTRACT_MAX_MINUTES,
        CONTRACT_MINUTES + math.max(0, level - 1))
    local target = rate > 0 and math.floor(rate * challenge_minutes + 0.5)
        or (750 + math.max(0, level - 1) * 250)
    local trade_multiplier = math.min(2, 1 + math.max(0, (trade_number or 1) - 1) * 0.10)
    target = math.max(500, math.min(5000, math.ceil(target * trade_multiplier)))
    local mission = {
        kind = "mining",
        role = "miner",
        story_variant = generator(1, 2),
        resource = resource,
        target = target,
        progress = 0,
        challenge_minutes = challenge_minutes,
        estimated_value = math.floor(item_value(values, resource) * target + 0.5),
        level = level,
        trade_number = trade_number or 1,
    }
    attach_reward_options(mission, force, generator, values)
    return mission
end

local function generate_mission(role, force, seed, level, trade_number)
    local generator = game.create_random_generator(seed)
    if role == "miner" and generator(1, 2) == 1 then
        return mining_mission(force, generator, level, trade_number)
    end
    return requirement_mission(role, force, generator, level, trade_number)
end

local function choose_roles(generator, forced_role)
    local pool = shuffled_copy(ROLE_ORDER, generator)
    local roles = {}
    if forced_role then
        roles[#roles + 1] = forced_role
        for i = #pool, 1, -1 do
            if pool[i] == forced_role then table.remove(pool, i) end
        end
    end
    while #roles < 1 and #pool > 0 do
        roles[#roles + 1] = table.remove(pool, 1)
    end
    return roles
end

local function create_npc(surface, role, position, force)
    local preferred = surface.find_non_colliding_position("character", position, 12, 0.5) or position
    local ok, npc = pcall(function()
        return surface.create_entity { name = "character", position = preferred, force = force }
    end)
    if not ok or not (npc and npc.valid) then return nil, nil end
    npc.destructible = false
    npc.minable_flag = false
    pcall(function() npc.color = ROLE_COLORS[role] end)
    local label = render_text(surface, npc,
        { "the-cave-lost-city.role-" .. role }, ROLE_COLORS[role], 1.05, { 0, -2.2 })
    return npc, label
end

local function place_npcs(record, surface, force, generator)
    record.npcs = {}
    local positions = shuffled_copy(NPC_POSITIONS, generator)
    for index, role in ipairs(record.roles) do
        local position = index == 1 and { x = 0, y = 12 } or positions[index]
        local npc, label_id = create_npc(surface, role, position, force)
        record.npcs[index] = {
            role = role,
            entity = npc,
            label_id = label_id,
            introduced = false,
        }
    end
end

local function ensure_city_house_ownership(record, surface)
    local force = record and game.forces[record.owner_force_index] or game.forces.player
    if not (surface and surface.valid and force and force.valid) then return end
    for _, entity in pairs(surface.find_entities_filtered { type = "container" }) do
        if entity.valid and lost_city.is_house_name(entity.name) then
            entity.force = force
            entity.destructible = true
            entity.minable_flag = true
        end
    end
end

local function copy_plain(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[copy_plain(key)] = copy_plain(child) end
    return result
end

local function default_control(defaults, name, fallback)
    local controls = defaults and defaults.autoplace_controls
    if controls and controls[name] then return copy_plain(controls[name]) end
    return copy_plain(fallback)
end

local function add_existing(settings, prototype_table, names)
    for _, name in ipairs(names) do
        if prototype_table and prototype_table[name] then settings[name] = {} end
    end
end

local function create_nauvis_map_gen_settings(record)
    local defaults = game.default_map_gen_settings or {}
    local tile_settings, entity_settings, decorative_settings = {}, {}, {}
    add_existing(tile_settings, prototypes.tile, NAUVIS_TILES)
    add_existing(entity_settings, prototypes.entity, NAUVIS_ENTITIES)
    local decorative_prototypes = {}
    if prototypes.get_decorative_filtered then
        local ok, filtered = pcall(function()
            return prototypes.get_decorative_filtered { { filter = "autoplace" } }
        end)
        if ok and filtered then decorative_prototypes = filtered end
    end
    add_existing(decorative_settings, decorative_prototypes, NAUVIS_DECORATIVES)

    -- Vanilla Nauvis living-tree variants share this stable prefix. Planetary
    -- trees and plants use separate names and therefore stay excluded.
    for name, prototype in pairs(prototypes.entity or {}) do
        if prototype.type == "tree" and name:find("^tree%-") then entity_settings[name] = {} end
    end

    local unit = { frequency = 1, size = 1, richness = 1 }
    return {
        seed = record.seed,
        width = 0,
        height = 0,
        starting_area = 1,
        starting_points = { { x = 0, y = 0 } },
        peaceful_mode = false,
        no_enemies_mode = false,
        default_enable_all_autoplace_controls = false,
        autoplace_controls = {
            water = default_control(defaults, "water", unit),
            trees = default_control(defaults, "trees", unit),
            ["enemy-base"] = default_control(defaults, "enemy-base", unit),
            ["iron-ore"] = default_control(defaults, "iron-ore", unit),
            ["copper-ore"] = default_control(defaults, "copper-ore", unit),
            coal = default_control(defaults, "coal", unit),
            stone = default_control(defaults, "stone", unit),
            ["uranium-ore"] = default_control(defaults, "uranium-ore", unit),
            ["crude-oil"] = default_control(defaults, "crude-oil", unit),
        },
        autoplace_settings = {
            tile = { settings = tile_settings, treat_missing_as_default = false },
            entity = { settings = entity_settings, treat_missing_as_default = false },
            decorative = { settings = decorative_settings, treat_missing_as_default = false },
        },
        -- Omitting elevation selects normal Nauvis terrain. Only the four
        -- ordinary Nauvis climate controls are retained; no planetary noise
        -- expression is inherited from the cave's modified Nauvis prototype.
        property_expression_names = {
            ["control:moisture:frequency"] = "1",
            ["control:moisture:bias"] = "0",
            ["control:aux:frequency"] = "1",
            ["control:aux:bias"] = "0",
        },
        cliff_settings = { name = "cliff", cliff_elevation_interval = 0, cliff_elevation_0 = 0 },
    }
end

local function enforce_nauvis_map_gen(record, surface)
    if not (record and surface and surface.valid) then return false end
    local ok = pcall(function()
        surface.map_gen_settings = create_nauvis_map_gen_settings(record)
    end)
    if ok then record.city_generation_version = 3 end
    return ok
end

local function apply_city_lighting(surface)
    if not (surface and surface.valid) then return end
    surface.always_day = false
    surface.freeze_daytime = true
    surface.daytime = 0.42
    surface.dusk = 0.25
    surface.evening = 0.45
    surface.morning = 0.55
    surface.dawn = 0.75
    surface.show_clouds = false
    surface.brightness_visual_weights = { r = 1, g = 1, b = 1 }
    surface.min_brightness = 0.12
    surface.solar_power_multiplier = 0
end

local function create_city_surface(record)
    local existing = record.surface_index and valid_surface(record.surface_index)
    if existing then
        if record.power_connections_surface == existing
            and record.item_connections_surface == existing then return existing end
        enforce_nauvis_map_gen(record, existing)
        ensure_city_house_ownership(record, existing)
        if not ensure_lower_item_ports(record, existing) then return nil, "item-transfer-failed" end
        if not connect_item_ports(record) or not ensure_power_bridge(record) then
            return nil, "item-transfer-failed"
        end
        return existing
    end
    local name = SURFACE_PREFIX .. record.id
    local surface = game.get_surface(name)
    local created = not surface
    if not surface then
        surface = game.create_surface(name, create_nauvis_map_gen_settings(record))
    end
    if not (surface and surface.valid) then return nil, "surface-create-failed" end
    record.surface_index = surface.index
    root().by_surface[surface.index] = record.id
    if created then child_state.surface_created(record, surface) end
    record.city_generation_version = 3
    surface.request_to_generate_chunks({ 0, 0 }, INITIAL_GENERATION_RADIUS)
    surface.force_generate_chunk_requests()
    for chunk in surface.get_chunks() do
        generate_city_chunk(record, surface, { x = chunk.x, y = chunk.y })
    end
    local generator = game.create_random_generator(record.seed)
    prepare_mission_hub(record, surface)

    surface.no_enemies_mode = false
    apply_city_lighting(surface)

    local force = game.forces[record.owner_force_index] or game.forces.player
    local exit = create_fixed_entity(surface, EXIT_NAME, { x = 0, y = -7 }, force)
    local crate = create_fixed_entity(surface, SUPPLY_CRATE_NAME, { x = 4, y = 7 }, force)
    if not (exit and exit.unit_number and crate and crate.unit_number) then
        pcall(function() child_state.delete_surface(record, surface) end)
        return nil, "mission-entities-failed"
    end
    record.exit_unit_number = exit.unit_number
    record.supply_crate_unit_number = crate.unit_number
    root().by_entity[exit.unit_number] = record.id
    render_text(surface, { x = 0, y = -10.5 }, { "the-cave-lost-city.exit-label" },
        { r = 0.25, g = 0.85, b = 1 }, 1.2)
    render_text(surface, { x = 4, y = 4.8 }, { "the-cave-lost-city.supply-label" },
        { r = 1, g = 0.72, b = 0.12 }, 1.05)
    place_npcs(record, surface, force, generator)
    if not ensure_lower_item_ports(record, surface) then
        root().by_surface[surface.index] = nil
        pcall(function() child_state.delete_surface(record, surface) end)
        record.surface_index = nil
        return nil, "item-transfer-failed"
    end
    if not connect_item_ports(record) or not ensure_power_bridge(record) then
        return nil, "item-transfer-failed"
    end
    return surface
end

local function format_time(ticks)
    local seconds = math.max(0, math.ceil((ticks or 0) / 60))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function upper_countdown_color(record, tick)
    local remaining = math.max(0, (record.deadline_tick or tick) - tick)
    if remaining <= 5 * 60 * 60 then return { r = 1, g = 0.18, b = 0.08 } end
    return { r = 0.35, g = 1, b = 0.45 }
end

local function ensure_upper_countdown_label(record, tick)
    if not record then return nil end
    tick = tick or game.tick
    -- Keep the Village entrance pixel-aligned with every Resource Cave:
    -- title at -3.4, independent 1.10-scale countdown at -2.15.  The 2.7.123
    -- rich-text newline was rendered inline by Factorio and pushed the timer
    -- sideways over the indicator lamp.
    if record.upper_timer_layout_version ~= UPPER_TIMER_LAYOUT_VERSION then
        destroy_render(record.upper_timer_id)
        record.upper_timer_id = nil
        record.upper_timer_layout_version = UPPER_TIMER_LAYOUT_VERSION
    end
    local surface = valid_surface(record.parent_surface_index)
    local center = record.entrance_position
    if not (surface and center) then return nil end

    local title = render_object(record.entrance_label_id)
    if not title then
        record.entrance_label_id = render_text(surface, { x = center.x, y = center.y - 3.4 },
            { "the-cave-lost-city.entrance-label" }, { r = 0.72, g = 0.35, b = 1 }, 1.25)
        title = render_object(record.entrance_label_id)
    end
    if title then
        pcall(function() title.text = { "the-cave-lost-city.entrance-label" } end)
        pcall(function() title.color = { r = 0.72, g = 0.35, b = 1 } end)
    end

    if record.status == "closed" or not record.started_tick or not record.deadline_tick then
        destroy_render(record.upper_timer_id)
        record.upper_timer_id = nil
        return nil
    end

    local text = format_time(record.deadline_tick - tick)
    local color = upper_countdown_color(record, tick)
    local object = render_object(record.upper_timer_id)
    if not object then
        record.upper_timer_id = render_text(surface,
            { x = center.x, y = center.y - 2.15 }, text, color, 1.10)
        object = render_object(record.upper_timer_id)
    end
    if object then
        pcall(function() object.text = text end)
        pcall(function() object.color = color end)
    end
    return record.upper_timer_id
end

local function current_mission(record)
    return record and record.missions and record.missions[record.task_index or 1] or nil
end

local function item_count_in_crate(record, item_name)
    local crate = find_unit(record.surface_index, record.supply_crate_unit_number, SUPPLY_CRATE_NAME)
    local inventory = crate and crate.valid and crate.get_inventory(defines.inventory.chest)
    return inventory and inventory.get_item_count(item_name) or 0
end

local function requirement_progress_text(record, mission)
    local parts = {}
    for _, requirement in ipairs(mission.requirements or {}) do
        parts[#parts + 1] = string.format("[item=%s] %d/%d", requirement.name,
            math.min(requirement.count, item_count_in_crate(record, requirement.name)), requirement.count)
    end
    return table.concat(parts, "   ")
end

local function mission_progress_text(record, mission)
    if not mission then return "" end
    if record.status == "awaiting-reward" then
        return { "the-cave-lost-city.hud-choose-reward" }
    elseif record.status == "reward-collection" then
        return { "the-cave-lost-city.hud-collect-reward" }
    elseif record.status == "between-trades" then
        local remaining = math.max(0, (record.next_offer_tick or game.tick) - game.tick)
        return { "the-cave-lost-city.hud-next-offer", format_time(remaining) }
    end
    if mission.kind == "mining" then
        return string.format("[item=%s] %d/%d", mission.resource,
            math.min(mission.target, item_count_in_crate(record, mission.resource)), mission.target)
    end
    return requirement_progress_text(record, mission)
end

local function destroy_player_gui(player)
    if not (player and player.valid) then return end
    if player.gui.screen[GUI_DIALOG] then player.gui.screen[GUI_DIALOG].destroy() end
    if player.gui.screen[GUI_REWARD] then player.gui.screen[GUI_REWARD].destroy() end
    if player.gui.top[GUI_HUD] then player.gui.top[GUI_HUD].destroy() end
end

local function player_can_see_hud(player, record)
    if not (player and player.valid and record and record.status ~= "closed"
        and record.started_tick and player.force.index == record.owner_force_index) then
        return false
    end
    local surface_index = physical.surface(player).index
    return surface_index == record.surface_index
        or surface_index == record.parent_surface_index
end

local function update_player_hud(player, record)
    if not player_can_see_hud(player, record) then
        if player and player.valid and player.gui.top[GUI_HUD] then player.gui.top[GUI_HUD].destroy() end
        return
    end
    local mission = current_mission(record)
    local remaining = record.deadline_tick and (record.deadline_tick - game.tick) or operation_duration_ticks(record)
    local trade_number = (record.status == "active" or record.status == "awaiting-reward")
        and ((record.trade_count or 0) + 1) or math.max(1, record.trade_count or 0)
    local caption = { "the-cave-lost-city.hud", trade_number,
        { "the-cave-lost-city.role-" .. tostring(mission and mission.role or "engineer") },
        format_time(remaining), mission_progress_text(record, mission) }
    local frame = player.gui.top[GUI_HUD]
    if not frame then
        frame = player.gui.top.add { type = "frame", name = GUI_HUD, direction = "horizontal", caption = caption }
    else
        frame.caption = caption
    end
end

local function update_all_huds(record)
    for _, player in pairs(game.connected_players) do
        if player.force.index == record.owner_force_index then update_player_hud(player, record) end
    end
end

local function show_dialogue(player, record)
    if not (player and player.valid and record and physical.surface(player).index == record.surface_index) then return end
    local mission = current_mission(record)
    if not mission then return end
    if player.gui.screen[GUI_DIALOG] then player.gui.screen[GUI_DIALOG].destroy() end
    local frame = player.gui.screen.add {
        type = "frame",
        name = GUI_DIALOG,
        direction = "vertical",
        caption = { "the-cave-lost-city.dialog-title", { "the-cave-lost-city.role-" .. mission.role } },
    }
    frame.style.width = 520
    frame.auto_center = true
    local story = frame.add {
        type = "label",
        caption = { "the-cave-lost-city.story-" .. mission.role .. "-" .. mission.story_variant },
    }
    story.style.single_line = false
    story.style.maximal_width = 480
    frame.add { type = "line" }
    if mission.kind == "mining" then
        frame.add { type = "label", caption = { "the-cave-lost-city.mining-request",
            mission.target, prototypes.item[mission.resource].localised_name } }
    else
        frame.add { type = "label", caption = { "the-cave-lost-city.supply-request" } }
        for _, requirement in ipairs(mission.requirements) do
            frame.add { type = "label", caption = { "the-cave-lost-city.requirement-line",
                requirement.count, prototypes.item[requirement.name].localised_name, requirement.name } }
        end
    end
    frame.add { type = "line" }
    frame.add { type = "label", caption = { "the-cave-lost-city.contract-value",
        math.floor(mission.estimated_value or 0) } }
    frame.add { type = "label", caption = { "the-cave-lost-city.reward-preview" } }
    for option_index, option in ipairs(mission.reward_options or {}) do
        local option_frame = frame.add {
            type = "frame",
            direction = "vertical",
            caption = { "the-cave-lost-city.reward-option-title", option_index,
                { "the-cave-lost-city.reward-pool-" .. tostring(option.pool) } },
        }
        if option.pool == "time" then
            option_frame.add { type = "label", caption = { "the-cave-lost-city.time-reward-preview",
                option.minutes or 10 } }
        else
            for _, item in ipairs(option.items or {}) do
                option_frame.add { type = "label", caption = { "the-cave-lost-city.requirement-line",
                    item.count, prototypes.item[item.name].localised_name, item.name } }
            end
            option_frame.add { type = "label", caption = { "the-cave-lost-city.reward-option-value",
                math.floor(option.estimated_value or 0), math.floor(option.target_value or mission.reward_budget or 0) } }
        end
    end
    frame.add { type = "button", name = GUI_CLOSE, caption = { "the-cave-lost-city.close" } }
end

local function show_reward_choice(player, record)
    if not (player and player.valid and record and record.status == "awaiting-reward"
        and physical.surface(player).index == record.surface_index) then return end
    if player.gui.screen[GUI_REWARD] then player.gui.screen[GUI_REWARD].destroy() end
    local mission = current_mission(record)
    if not mission or mission.reward_selection then return end
    local frame = player.gui.screen.add {
        type = "frame",
        name = GUI_REWARD,
        direction = "vertical",
        caption = { "the-cave-lost-city.reward-choice-title" },
    }
    frame.style.width = 560
    frame.auto_center = true
    frame.add { type = "label", caption = { "the-cave-lost-city.reward-choice-shared" } }
    for option_index, option in ipairs(mission.reward_options or {}) do
        local option_frame = frame.add {
            type = "frame",
            direction = "vertical",
            caption = { "the-cave-lost-city.reward-option-title", option_index,
                { "the-cave-lost-city.reward-pool-" .. tostring(option.pool) } },
        }
        if option.pool == "time" then
            local remaining_ticks = math.max(0, (record.deadline_tick or game.tick) - game.tick)
            local added_ticks = (option.minutes or 10) * 60 * 60
            option_frame.add { type = "label", caption = { "the-cave-lost-city.time-reward-choice",
                option.minutes or 10, format_time(remaining_ticks), format_time(remaining_ticks + added_ticks) } }
        else
            for _, item in ipairs(option.items or {}) do
                option_frame.add { type = "label", caption = { "the-cave-lost-city.requirement-line",
                    item.count, prototypes.item[item.name].localised_name, item.name } }
            end
            option_frame.add { type = "label", caption = { "the-cave-lost-city.reward-option-value",
                math.floor(option.estimated_value or 0), math.floor(option.target_value or mission.reward_budget or 0) } }
        end
        option_frame.add {
            type = "button",
            name = GUI_REWARD_BUTTON_PREFIX .. option_index,
            caption = { "the-cave-lost-city.choose-reward", option_index },
            tags = { city_id = record.id, option_index = option_index },
        }
    end
end

local function nearest_city_player(record, position)
    local surface = valid_surface(record.surface_index)
    if not surface then return nil end
    local best, best_distance
    for _, player in pairs(game.connected_players) do
        if physical.surface(player) == surface and player.force.index == record.owner_force_index and player.character and player.character.valid then
            local dx, dy = physical.position(player).x - position.x, physical.position(player).y - position.y
            local distance = dx * dx + dy * dy
            if not best_distance or distance < best_distance then best, best_distance = player, distance end
        end
    end
    return best, best_distance
end

local function active_npc(record)
    return record and record.npcs and record.npcs[record.task_index or 1] or nil
end

local function add_chart_tag_safe(force, surface, position, icon, text)
    if not (force and force.valid and surface and surface.valid and position) then return nil end
    local ok, tag = pcall(function()
        return force.add_chart_tag(surface, {
            position = copy_position(position),
            icon = icon,
            text = tostring(text or ""),
        })
    end)
    return ok and tag or nil
end

local function add_active_npc_tag(record)
    if record.active_tag and record.active_tag.valid then record.active_tag.destroy() end
    record.active_tag = nil
    local npc = active_npc(record)
    local force = game.forces[record.owner_force_index]
    if npc and npc.entity and npc.entity.valid and force and force.valid then
        record.active_tag = add_chart_tag_safe(force, npc.entity.surface, npc.entity.position,
            { type = "virtual", name = "signal-info" }, ROLE_TAG_TEXT[npc.role] or npc.role)
    end
end

local function build_mining_site(record, mission)
    if mission.mining_site_ready then return end
    local surface = valid_surface(record.surface_index)
    if not surface then return end
    local center = { x = 70, y = 70 }
    clear_area_entities(surface, { { center.x - 12, center.y - 12 }, { center.x + 12, center.y + 12 } })
    local tiles = {}
    for x = center.x - 11, center.x + 11 do
        for y = center.y - 11, center.y + 11 do
            tiles[#tiles + 1] = { name = "dirt-4", position = { x, y } }
        end
    end
    surface.set_tiles(tiles, true, true)
    for x = center.x - 11, center.x + 11 do
        for y = center.y - 11, center.y + 11 do
            local dx, dy = x - center.x, y - center.y
            if dx * dx + dy * dy <= 95 then
                surface.create_entity {
                    name = mission.resource,
                    position = { x = x + 0.5, y = y + 0.5 },
                    amount = 1000,
                }
            end
        end
    end
    mission.mining_center = center
    mission.mining_radius = 12
    mission.initial_amount = 0
    for _, resource in pairs(surface.find_entities_filtered {
        type = "resource", name = mission.resource,
        area = { { center.x - 12, center.y - 12 }, { center.x + 12, center.y + 12 } },
    }) do
        mission.initial_amount = mission.initial_amount + (resource.amount or 0)
    end
    mission.mining_site_ready = true
    local force = game.forces[record.owner_force_index]
    if force and force.valid then
        mission.mining_tag = add_chart_tag_safe(force, surface, center,
            { type = "item", name = mission.resource }, "Village mining site")
        force.chart(surface, { { center.x - 16, center.y - 16 }, { center.x + 16, center.y + 16 } })
    end
end

local function activate_task(record)
    local mission = current_mission(record)
    if not mission then return end
    if mission.kind == "mining" then build_mining_site(record, mission) end
    add_active_npc_tag(record)
    local force = game.forces[record.owner_force_index]
    if force and force.valid then
        force.print({ "the-cave-lost-city.trade-started", (record.trade_count or 0) + 1,
            { "the-cave-lost-city.role-" .. mission.role } })
    end
    if (record.trade_count or 0) > 0 then
        local npc = active_npc(record)
        if npc then npc.introduced = true end
        for _, player in pairs(game.connected_players) do
            if physical.surface(player).index == record.surface_index
                and player.force.index == record.owner_force_index then
                show_dialogue(player, record)
            end
        end
    end
    update_all_huds(record)
end

local function remove_supply_items(record, mission)
    local crate = find_unit(record.surface_index, record.supply_crate_unit_number, SUPPLY_CRATE_NAME)
    local inventory = crate and crate.valid and crate.get_inventory(defines.inventory.chest)
    if not inventory then return false end
    for _, requirement in ipairs(mission.requirements or {}) do
        if inventory.get_item_count(requirement.name) < requirement.count then return false end
    end
    for _, requirement in ipairs(mission.requirements or {}) do
        inventory.remove { name = requirement.name, count = requirement.count }
    end
    return true
end

local function remove_mining_delivery(record, mission)
    local crate = find_unit(record.surface_index, record.supply_crate_unit_number, SUPPLY_CRATE_NAME)
    local inventory = crate and crate.valid and crate.get_inventory(defines.inventory.chest)
    if not inventory then return false end
    local target = math.max(1, mission.target or 1)
    if inventory.get_item_count(mission.resource) < target then return false end
    inventory.remove { name = mission.resource, count = target }
    mission.progress = target
    return true
end

local function insert_reward(inventory, item_name, count)
    if not (inventory and prototypes.item[item_name] and count > 0
        and reward_policy.is_allowed(item_name)) then return end
    inventory.insert { name = item_name, count = count }
end

local function mission_signature(mission)
    if not mission then return "" end
    if mission.kind == "mining" then return "mining:" .. tostring(mission.resource) end
    local names = {}
    for _, requirement in ipairs(mission.requirements or {}) do names[#names + 1] = requirement.name end
    table.sort(names)
    return table.concat(names, "|")
end

local function count_selected_trade(record, mission)
    if mission.trade_counted then return end
    mission.trade_counted = true
    record.trade_count = (record.trade_count or 0) + 1
end

local function schedule_next_trade(record)
    record.status = "between-trades"
    record.next_offer_tick = game.tick + NEXT_TRADE_DELAY_TICKS
    update_all_huds(record)
end

local function unregister_entity(unit_number)
    if unit_number then
        local r = root()
        r.by_entity[unit_number] = nil
        if r.entity_cache then r.entity_cache[unit_number] = nil end
    end
end

local function destroy_empty_reward_crate(record)
    local crate = find_unit(record.surface_index, record.reward_crate_unit_number, REWARD_CRATE_NAME)
    if crate and crate.valid then crate.destroy() end
    unregister_entity(record.reward_crate_unit_number)
    record.reward_crate_unit_number = nil
    destroy_render(record.reward_label_id)
    record.reward_label_id = nil
end

local function begin_next_trade(record)
    if not record or record.status == "closed" then return false end
    local force = game.forces[record.owner_force_index]
    if not (force and force.valid) then return false end
    local trade_number = (record.trade_count or 0) + 1
    local previous_signature = record.last_mission_signature or mission_signature(current_mission(record))
    local excluded_roles = {}
    for _, recent_role in ipairs(record.recent_request_roles or {}) do
        excluded_roles[recent_role] = true
    end
    local previous_mission = current_mission(record)
    if previous_mission and previous_mission.role then excluded_roles[previous_mission.role] = true end
    local available_roles = {}
    for _, candidate_role in ipairs(ROLE_ORDER) do
        if not excluded_roles[candidate_role] then available_roles[#available_roles + 1] = candidate_role end
    end
    if #available_roles == 0 then available_roles = shuffled_copy(ROLE_ORDER,
        game.create_random_generator((record.seed or 1) + trade_number * 65537)) end
    local role_order = shuffled_copy(available_roles,
        game.create_random_generator((record.seed or 1) + trade_number * 65537 + 4099))
    local mission
    for attempt = 1, math.max(12, #role_order * 2) do
        local seed = (record.seed or 1) + trade_number * 104729 + attempt * 8191
        local role = role_order[((attempt - 1) % #role_order) + 1]
        local candidate = generate_mission(role, force, seed, record.level or 1, trade_number)
        mission = candidate
        if mission_signature(candidate) ~= previous_signature
            and not excluded_roles[candidate.role] then break end
    end
    if not mission then return false end
    record.missions = { mission }
    record.task_index = 1
    record.last_mission_signature = mission_signature(mission)
    record.recent_request_roles = record.recent_request_roles or {}
    record.recent_request_roles[#record.recent_request_roles + 1] = mission.role
    while #record.recent_request_roles > 2 do table.remove(record.recent_request_roles, 1) end
    record.reward_selection = nil
    record.reward_actual_value = nil
    record.next_offer_tick = nil
    record.status = "active"
    local npc = active_npc(record)
    if npc then npc.introduced = true end
    activate_task(record)
    return true
end

local function create_final_reward(record, option_index)
    local surface = valid_surface(record.surface_index)
    if not surface then return end
    local mission = current_mission(record)
    local option = mission and mission.reward_options and mission.reward_options[option_index] or nil
    if not option or mission.reward_selection then return end
    local force = game.forces[record.owner_force_index] or game.forces.player
    mission.reward_selection = option_index
    record.reward_selection = option_index
    count_selected_trade(record, mission)

    for _, player in pairs(game.players) do
        if player.valid and player.gui.screen[GUI_REWARD] then
            player.gui.screen[GUI_REWARD].destroy()
        end
    end

    if option.pool == "time" then
        local minutes = math.max(1, tonumber(option.minutes) or 10)
        record.deadline_tick = math.max(game.tick, record.deadline_tick or game.tick) + minutes * 60 * 60
        record.total_bonus_minutes = (record.total_bonus_minutes or 0) + minutes
        if force and force.valid then
            force.print({ "the-cave-lost-city.time-added", minutes,
                format_time(math.max(0, record.deadline_tick - game.tick)) })
        end
        schedule_next_trade(record)
        return
    end

    local reward = create_fixed_entity(surface, REWARD_CRATE_NAME, { x = 8, y = 7 }, force)
    if not reward then
        mission.reward_selection = nil
        record.reward_selection = nil
        if mission.trade_counted then
            mission.trade_counted = nil
            record.trade_count = math.max(0, (record.trade_count or 1) - 1)
        end
        for _, player in pairs(game.connected_players) do
            if physical.surface(player).index == record.surface_index
                and player.force.index == record.owner_force_index then
                show_reward_choice(player, record)
            end
        end
        return
    end
    record.reward_crate_unit_number = reward.unit_number
    root().by_entity[reward.unit_number] = record.id
    local inventory = reward.get_inventory(defines.inventory.chest)
    for _, item in ipairs(option.items or {}) do
        insert_reward(inventory, item.name, item.count)
    end
    record.reward_actual_value = option.estimated_value
    record.status = "reward-collection"
    record.reward_label_id = render_text(surface, { x = 8, y = 4.8 },
        { "the-cave-lost-city.reward-label" }, { r = 0.25, g = 1, b = 0.38 }, 1.15)
    if force and force.valid then
        force.print({ "the-cave-lost-city.reward-selected", option_index,
            { "the-cave-lost-city.reward-pool-" .. tostring(option.pool) } })
    end
end

local function complete_task(record)
    local mission = current_mission(record)
    if not mission or mission.completed then return end
    mission.completed = true
    if mission.mining_tag and mission.mining_tag.valid then mission.mining_tag.destroy() end
    if record.active_tag and record.active_tag.valid then record.active_tag.destroy() end
    record.active_tag = nil
    local force = game.forces[record.owner_force_index]
    if force and force.valid then
        force.print({ "the-cave-lost-city.trade-completed", (record.trade_count or 0) + 1,
            { "the-cave-lost-city.role-" .. mission.role } })
    end
    record.status = "awaiting-reward"
    record.completed_tick = game.tick
    if not record.city_completion_counted then
        record.city_completion_counted = true
        root().completed_by_force[record.owner_force_index] =
            (root().completed_by_force[record.owner_force_index] or 0) + 1
    end
    if force and force.valid then force.print({ "the-cave-lost-city.city-completed" }) end
    for _, player in pairs(game.connected_players) do
        if physical.surface(player).index == record.surface_index
            and player.force.index == record.owner_force_index then
            show_reward_choice(player, record)
        end
    end
    update_all_huds(record)
end

local function task_is_complete(record, mission)
    if mission.kind == "mining" then return remove_mining_delivery(record, mission) end
    return remove_supply_items(record, mission)
end

local function role_direction(dx, dy)
    if math.abs(dx) > math.abs(dy) then
        return dx >= 0 and defines.direction.east or defines.direction.west
    end
    return dy >= 0 and defines.direction.south or defines.direction.north
end

local function approach_player(record, tick)
    if (record.task_index or 1) ~= 1 then return end
    local npc = active_npc(record)
    if not (npc and npc.entity and npc.entity.valid) or npc.introduced then return end
    local player, distance_squared = nearest_city_player(record, npc.entity.position)
    if not player then return end
    record.approach_started_tick = record.approach_started_tick or tick
    if distance_squared and distance_squared <= 25 then
        pcall(function() npc.entity.walking_state = { walking = false, direction = defines.direction.south } end)
        npc.introduced = true
        show_dialogue(player, record)
        return
    end
    if tick - record.approach_started_tick >= NPC_APPROACH_TIMEOUT then
        local target = physical.surface(player).find_non_colliding_position("character",
            { x = physical.position(player).x + 3, y = physical.position(player).y }, 8, 0.5)
        if target then npc.entity.teleport(target) end
        npc.introduced = true
        show_dialogue(player, record)
        return
    end
    local dx, dy = physical.position(player).x - npc.entity.position.x, physical.position(player).y - npc.entity.position.y
    pcall(function()
        npc.entity.walking_state = { walking = true, direction = role_direction(dx, dy) }
    end)
end

local function reward_is_empty(record)
    if not record.reward_crate_unit_number then return true end
    local crate = find_unit(record.surface_index, record.reward_crate_unit_number, REWARD_CRATE_NAME)
    local inventory = crate and crate.valid and crate.get_inventory(defines.inventory.chest)
    return not inventory or inventory.is_empty()
end

local function city_has_players(record)
    local surface = valid_surface(record.surface_index)
    if not surface then return false end
    for _, player in pairs(game.players) do
        if physical.surface(player) == surface then return true end
    end
    return false
end

local function parent_position_for_player(player, record)
    local parent = child_state.return_surface(player, record.parent_surface_index)
    if not parent then return nil, nil end
    local preferred = parent.index == record.parent_surface_index
        and { x = record.entrance_position.x, y = record.entrance_position.y + 4 }
        or child_state.spawn_position(player, parent)
    return parent.find_non_colliding_position(player.character and player.character.name or "character",
        preferred, 16, 0.5), parent
end

local function evacuate_players(record)
    local surface = valid_surface(record.surface_index)
    if not surface then return true end
    local all_moved = true
    for _, player in pairs(game.players) do
        local inside = physical.on_surface(player, surface)
        if player.valid and (inside or player.surface == surface) then
            local position, parent = parent_position_for_player(player, record)
            if not inside and parent then
                position = parent.index == record.parent_surface_index and record.entrance_position
                    or child_state.spawn_position(player, parent)
            end
            if not (parent and position and physical.evacuate(player, surface, parent, position)) then
                all_moved = false
            elseif inside then
                destroy_player_gui(player)
            end
        end
    end
    return all_moved
end

local function return_extra_supplies(record)
    local crate = find_unit(record.surface_index, record.supply_crate_unit_number, SUPPLY_CRATE_NAME)
    local inventory = crate and crate.valid and crate.get_inventory(defines.inventory.chest)
    local parent = valid_surface(record.parent_surface_index)
    if not (inventory and parent) then return end
    for slot = 1, #inventory do
        local stack = inventory[slot]
        if stack and stack.valid_for_read then
            local item = { name = stack.name, count = stack.count }
            pcall(function()
                if stack.quality then item.quality = stack.quality.name end
            end)
            parent.spill_item_stack {
                position = record.entrance_position,
                stack = item,
                enable_looted = true,
                force = game.forces[record.owner_force_index],
                allow_belts = false,
            }
        end
    end
    inventory.clear()
end

local function return_transfer_items(record)
    cave_boxes.spill(record)
    local parent = valid_surface(record.parent_surface_index)
    if not (record and parent) then return end
    local entities = {
        find_unit(record.parent_surface_index, record.upper_item_down_input_unit_number, ITEM_DOWN_INPUT),
        find_unit(record.parent_surface_index, record.upper_item_up_output_unit_number, ITEM_UP_OUTPUT),
        find_unit(record.surface_index, record.lower_item_down_output_unit_number, ITEM_DOWN_OUTPUT),
        find_unit(record.surface_index, record.lower_item_up_input_unit_number, ITEM_UP_INPUT),
    }
    local seen_lines = {}
    local function already_seen(line)
        for _, seen in ipairs(seen_lines) do
            local ok, equal = pcall(function() return line.line_equals(seen) end)
            if ok and equal then return true end
        end
        seen_lines[#seen_lines + 1] = line
        return false
    end
    for _, entity in pairs(entities) do
        if entity and entity.valid and entity.get_transport_line then
            local maximum = 2
            pcall(function() maximum = entity.get_max_transport_line_index() end)
            for index = 1, maximum do
                local ok, line = pcall(function() return entity.get_transport_line(index) end)
                if ok and line and line.valid and not already_seen(line) then
                    local contents_ok, contents = pcall(function() return line.get_contents() end)
                    if contents_ok then
                        for _, item in ipairs(contents or {}) do
                            if item.name and (item.count or 0) > 0 then
                                local stack = { name = item.name, count = item.count }
                                if item.quality then stack.quality = item.quality end
                                parent.spill_item_stack {
                                    position = record.entrance_position,
                                    stack = stack,
                                    enable_looted = true,
                                    force = game.forces[record.owner_force_index],
                                    allow_belts = false,
                                }
                            end
                        end
                    end
                    pcall(function() line.clear() end)
                end
            end
        end
    end
end

local function destroy_transfer_ports(record)
    cave_boxes.destroy(record)
    local definitions = {
        { record.parent_surface_index, "upper_item_down_input_unit_number", ITEM_DOWN_INPUT },
        { record.parent_surface_index, "upper_item_up_output_unit_number", ITEM_UP_OUTPUT },
        { record.surface_index, "lower_item_down_output_unit_number", ITEM_DOWN_OUTPUT },
        { record.surface_index, "lower_item_up_input_unit_number", ITEM_UP_INPUT },
    }
    for _, definition in ipairs(definitions) do
        local entity = find_unit(definition[1], record[definition[2]], definition[3])
        if entity and entity.valid then entity.destroy() end
        record[definition[2]] = nil
    end
    destroy_transfer_labels(record)
end

local function kill_city_players(record)
    local child = valid_surface(record.surface_index)
    if not child then return end
    for _, player in pairs(game.players) do
        if player.valid and physical.surface(player) == child then
            root().pending_respawns[player.index] = {
                city_id = record.id,
                parent_surface_index = record.parent_surface_index,
            }
            destroy_player_gui(player)
            if player.character and player.character.valid then
                pcall(function() player.character.die() end)
            else
                local position, parent = parent_position_for_player(player, record)
                if position and parent and physical.teleport(player, position, parent) then
                    root().pending_respawns[player.index] = nil
                end
            end
        end
    end
end

local function delete_child_if_empty(record)
    local child = valid_surface(record.surface_index)
    if not child or city_has_players(record) then return false end
    for _, player in pairs(game.players) do
        if player.valid and player.surface == child then
            local parent = child_state.return_surface(player, record.parent_surface_index)
            local position = parent and child_state.spawn_position(player, parent)
            if not physical.move_view_off_surface(player, child, parent, position) then return false end
        end
    end
    local ok, queued = pcall(function() return child_state.delete_surface(record, child) end)
    if not ok or not queued then return false end
    root().by_surface[child.index] = nil
    record.surface_index = nil
    return true
end

local function close_city(record, failed)
    if not record or record.status == "closed" then return end
    if failed then kill_city_players(record) else evacuate_players(record) end
    return_extra_supplies(record)
    return_transfer_items(record)
    destroy_transfer_ports(record)
    if record.active_tag and record.active_tag.valid then record.active_tag.destroy() end
    for _, npc in ipairs(record.npcs or {}) do destroy_render(npc.label_id) end
    destroy_render(record.reward_label_id)
    local child = valid_surface(record.surface_index)
    if child and not failed then delete_child_if_empty(record) end
    local entrance = find_unit(record.parent_surface_index, record.entrance_unit_number, ENTRANCE_NAME)
    if entrance and entrance.valid then entrance.destroy() end
    local upper_power = find_unit(record.parent_surface_index,
        record.upper_power_unit_number, "big-electric-pole")
    if upper_power then upper_power.destroy() end
    local upper_panel = find_unit(record.parent_surface_index,
        record.upper_info_panel_unit_number, INFO_PANEL_NAME)
    if upper_panel then upper_panel.destroy() end
    local upper_lamp = find_unit(record.parent_surface_index,
        record.upper_indicator_lamp_unit_number, "small-lamp")
    if upper_lamp then upper_lamp.destroy() end
    destroy_render(record.entrance_label_id)
    destroy_render(record.upper_timer_id)
    record.upper_timer_id = nil
    unregister_entity(record.entrance_unit_number)
    unregister_entity(record.exit_unit_number)
    unregister_entity(record.supply_crate_unit_number)
    unregister_entity(record.reward_crate_unit_number)
    record.status = "closed"
    record.failed = failed == true
    record.closed_tick = game.tick
    local r = root()
    if r.active_by_force[record.owner_force_index] == record.id then
        r.active_by_force[record.owner_force_index] = nil
    end
    update_all_huds(record)
    local force = game.forces[record.owner_force_index]
    if force and force.valid then
        force.print({ failed and "the-cave-lost-city.city-failed" or "the-cave-lost-city.city-sealed" })
    end
end

local function active_record_for_force(force_index)
    local r = root()
    local active_id = r.active_by_force[force_index]
    local record = active_id and r.by_id[active_id] or nil
    if not (record and record.status ~= "closed" and record.started_tick) then
        r.active_by_force[force_index] = nil
        return nil
    end
    return record
end

local function start_timer(record)
    if record.started_tick then
        root().active_by_force[record.owner_force_index] = record.id
        ensure_upper_countdown_label(record, game.tick)
        return
    end
    if record.status == "waiting" then
        local restored_status = record.suspended_status
        if not restored_status or restored_status == "prepared" or restored_status == "waiting" then
            restored_status = "active"
        end
        record.status = restored_status
        record.started_tick = game.tick
        record.deadline_tick = game.tick + math.max(1,
            tonumber(record.suspended_remaining_ticks) or operation_duration_ticks(record))
        if record.suspended_next_offer_ticks then
            record.next_offer_tick = game.tick + math.max(1, record.suspended_next_offer_ticks)
        end
        record.suspended_status = nil
        record.suspended_remaining_ticks = nil
        record.suspended_next_offer_ticks = nil
        root().active_by_force[record.owner_force_index] = record.id
        ensure_upper_countdown_label(record, game.tick)
        if record.status == "active" then activate_task(record) else update_all_huds(record) end
        return
    end
    record.operation_duration_ticks = OPERATION_TICKS
    record.started_tick = game.tick
    record.deadline_tick = game.tick + record.operation_duration_ticks
    record.status = "active"
    root().active_by_force[record.owner_force_index] = record.id
    ensure_upper_countdown_label(record, game.tick)
    activate_task(record)
    local force = game.forces[record.owner_force_index]
    if force and force.valid then force.print({ "the-cave-lost-city.timer-started", OPERATION_TICKS / (60 * 60) }) end
end

local function enter_city(player, record)
    if not physical.can_travel(player) then return false end
    if record.status == "closed" then player.print({ "the-cave-lost-city.closed" }) return false end
    if player.vehicle then player.print({ "the-cave-lost-city.leave-vehicle" }) return false end
    if player.force.index ~= record.owner_force_index then
        player.print({ "the-cave-lost-city.wrong-force" })
        return false
    end
    local active = active_record_for_force(player.force.index)
    if active and active.id ~= record.id then
        player.print({ "the-cave-lost-city.already-active", active.id })
        return false
    end
    local surface, reason = create_city_surface(record)
    if not surface then player.print({ "the-cave-lost-city.create-failed", reason or "unknown" }) return false end
    local preferred = { x = 0, y = -2 }
    local position = surface.find_non_colliding_position(player.character and player.character.name or "character",
        preferred, 14, 0.5)
    if physical.teleport(player, position, surface) then
        start_timer(record)
        player.force.chart(surface, { { -20, -20 }, { 20, 20 } })
        update_player_hud(player, record)
        local mission = current_mission(record)
        if record.status == "awaiting-reward" and mission and not mission.reward_selection then
            show_reward_choice(player, record)
        end
        return true
    end
    return false
end

local function leave_city(player, record)
    if not physical.can_travel(player) then return false end
    if player.vehicle then player.print({ "the-cave-lost-city.leave-vehicle" }) return false end
    local position, parent = parent_position_for_player(player, record)
    if not (position and parent) then return false end
    if physical.teleport(player, position, parent) then
        destroy_player_gui(player)
        update_player_hud(player, record)
        return true
    end
    return false
end

function lost_city.is_house_name(name)
    return type(name) == "string" and name:sub(1, #HOUSE_PREFIX) == HOUSE_PREFIX
end

function lost_city.on_chunk_generated(event)
    local surface = event and event.surface
    if not lost_city.is_lost_city_surface(surface) then return end
    local record = record_for_surface(surface)
    if record then generate_city_chunk(record, surface, event.position) end
end

local function ambush_unit_name(surface, position)
    local evolution = cave_evolution.factor(surface)
    local prefix = evolution >= 0.90 and "behemoth"
        or (evolution >= 0.60 and "big")
        or (evolution >= 0.30 and "medium")
        or "small"
    return prefix .. ((math.floor(position.x + position.y) % 3 == 0) and "-spitter" or "-biter")
end

function lost_city.on_house_mined(event)
    local entity = event and event.entity
    if not (entity and entity.valid and lost_city.is_house_name(entity.name)) then return false end
    local record = record_for_surface(entity.surface)
    if not record or record.status == "closed" then return true end
    record.houses_mined = (record.houses_mined or 0) + 1

    -- Per-city counter and unit number make the ambush decision stable without
    -- the old mod's global cross-player mining counter.
    local roll_key = (entity.unit_number or 0) + record.houses_mined * 37 + record.seed
    if roll_key % 100 >= 32 then return true end

    local player = event.player_index and valid_player(event.player_index) or nil
    local target = player and player.character and player.character.valid and player.character or nil
    local surface, origin = entity.surface, copy_position(entity.position)
    local wave_size = math.min(8, 2 + math.floor(record.houses_mined / 6))
    for i = 1, wave_size do
        local angle = (i * 2.3999632297) + (roll_key % 17) * 0.1
        local candidate = {
            x = origin.x + math.cos(angle) * (9 + i % 4),
            y = origin.y + math.sin(angle) * (9 + i % 4),
        }
        local name = ambush_unit_name(surface, candidate)
        local position = surface.find_non_colliding_position(name, candidate, 8, 0.5)
        local unit = position and surface.create_entity {
            name = name,
            position = position,
            force = "enemy",
        } or nil
        if unit and unit.valid and unit.commandable then
            pcall(function()
                if target and target.surface == surface then
                    unit.commandable.set_command {
                        type = defines.command.attack,
                        target = target,
                        distraction = defines.distraction.none,
                    }
                else
                    unit.commandable.set_command {
                        type = defines.command.attack_area,
                        destination = origin,
                        radius = 12,
                        distraction = defines.distraction.by_enemy,
                    }
                end
            end)
        end
    end
    return true
end

function lost_city.on_gui_opened(event)
    local entity = event and event.entity
    if not (entity and entity.valid) then return false end
    if entity.name ~= ENTRANCE_NAME and entity.name ~= EXIT_NAME then return false end
    local player = valid_player(event.player_index)
    if not player then return true end
    player.opened = nil
    if not physical.can_use_entity(player, entity) then return true end
    local record = record_for_entity(entity)
    if not record then player.print({ "the-cave-lost-city.unlinked" }) return true end
    if entity.name == ENTRANCE_NAME then enter_city(player, record) else leave_city(player, record) end
    return true
end

function lost_city.on_player_rotated_entity(event)
    local entity = event and event.entity
    if not (entity and entity.valid and entity.unit_number) then return end
    local fields = {
        { side = "upper", field = "item_down_input", unit = "upper_item_down_input_unit_number" },
        { side = "upper", field = "item_up_output", unit = "upper_item_up_output_unit_number" },
        { side = "lower", field = "item_down_output", unit = "lower_item_down_output_unit_number" },
        { side = "lower", field = "item_up_input", unit = "lower_item_up_input_unit_number" },
    }
    for _, record in pairs(root().by_id) do
        for _, definition in ipairs(fields) do
            if record[definition.unit] == entity.unit_number then
                stored_transfer_direction(record, definition.side, definition.field, entity.direction)
                record.transfer_directions[definition.side][definition.field] = entity.direction
                return
            end
        end
    end
end

function lost_city.on_gui_click(event)
    if not (event and event.element and event.element.valid) then return end
    local player = valid_player(event.player_index)
    if not player then return end
    if event.element.name == GUI_CLOSE then
        if player.gui.screen[GUI_DIALOG] then player.gui.screen[GUI_DIALOG].destroy() end
        return
    end
    if event.element.name:sub(1, #GUI_REWARD_BUTTON_PREFIX) == GUI_REWARD_BUTTON_PREFIX then
        local tags = event.element.tags or {}
        local record = root().by_id[tonumber(tags.city_id)]
        local option_index = tonumber(tags.option_index)
        local mission = record and current_mission(record) or nil
        if record and mission and option_index and record.status == "awaiting-reward"
            and not mission.reward_selection and player.force.index == record.owner_force_index then
            create_final_reward(record, option_index)
        end
    end
end

function lost_city.on_player_changed_surface(event)
    local player = valid_player(event.player_index)
    if not player then return end
    local record = record_for_surface(physical.surface(player))
    if record then
        update_player_hud(player, record)
        local mission = current_mission(record)
        if record.status == "awaiting-reward" and mission and not mission.reward_selection then
            show_reward_choice(player, record)
        else
            local npc = active_npc(record)
            if npc and npc.introduced then show_dialogue(player, record) end
        end
    else
        destroy_player_gui(player)
        local active_record = active_record_for_force(player.force.index)
        if active_record then update_player_hud(player, active_record) end
    end
end

function lost_city.on_tick(event)
    if event.tick % 15 == 0 then
        for _, record in pairs(root().by_id) do
            if record.status ~= "closed" then cave_boxes.sync(record) end
        end
    end
    local tick = event.tick
    for _, record in pairs(root().by_id) do
        if record.status ~= "closed" then
            if record.started_tick and tick >= (record.deadline_tick or math.huge) then
                close_city(record, true)
            elseif record.status == "active" then
                if tick % 10 == 0 then approach_player(record, tick) end
                if tick % TIMER_INTERVAL == 0 then
                    local mission = current_mission(record)
                    if mission and task_is_complete(record, mission) then complete_task(record) end
                    update_all_huds(record)
                end
            elseif record.status == "reward-collection" and tick % TIMER_INTERVAL == 0 then
                update_all_huds(record)
                if reward_is_empty(record) then
                    destroy_empty_reward_crate(record)
                    schedule_next_trade(record)
                end
            elseif record.status == "between-trades" and tick >= (record.next_offer_tick or math.huge) then
                begin_next_trade(record)
            elseif record.started_tick and tick % TIMER_INTERVAL == 0 then
                update_all_huds(record)
            end
            if tick % TIMER_INTERVAL == 0 then ensure_upper_countdown_label(record, tick) end
        elseif record.failed and record.surface_index
            and tick % TIMER_INTERVAL == 0 then
            delete_child_if_empty(record)
        end
    end
end

local function create_entrance(surface, target, force, bypass_zone, bypass_spacing, forced_role)
    if not enabled() then return nil, "disabled" end
    if not (surface and surface.valid and target and force and force.valid) then
        return nil, "invalid"
    end
    local surface_name = type(surface.name) == "string" and surface.name or ""
    if surface_has_prefix(surface)
        or surface_name:find("^the%-cave%-uranium%-cave%-")
        or surface_name:find("^the%-cave%-mineral%-cave%-") then
        return nil, "nested"
    end
    local scheduled = lost_city.scheduled.is_planned_entrance(surface, target, "village")
    if not scheduled and not bypass_zone and lost_city.scheduled.manages(surface, target) then
        return nil, "scheduled-zone"
    end
    if zone_for_position(target) == "easy" and not bypass_zone and not scheduled then
        return nil, "easy-zone"
    end
    if not bypass_spacing and not scheduled
        and lost_city.has_parent_entrance_within(surface, target, PARENT_MIN_DISTANCE) then
        return nil, "too-close"
    end

    if not cave_placement.prepare_entrance(surface, target, world) then return nil, "outside-or-blocked" end
    local r = root()
    local id = r.next_id
    r.next_id = id + 1
    local entrance = create_fixed_entity(surface, ENTRANCE_NAME, target, force)
    if not (entrance and entrance.unit_number) then
        return nil, "entrance-create-failed"
    end
    local parent_seed = surface.map_gen_settings and surface.map_gen_settings.seed or 1
    local seed = math.abs((parent_seed * 1103515245 + math.floor(target.x) * 97
        + math.floor(target.y) * 193 + id * 7919) % 2147483646) + 1
    local generator = game.create_random_generator(seed)
    local roles = choose_roles(generator, forced_role)
    local level = (r.completed_by_force[force.index] or 0) + 1
    local record = {
        id = id,
        parent_surface_index = surface.index,
        entrance_position = copy_position(entrance.position),
        entrance_unit_number = entrance.unit_number,
        owner_force_index = force.index,
        seed = seed,
        zone_id = zone_for_position(target),
        level = level,
        roles = roles,
        missions = {},
        task_index = 1,
        status = "prepared",
        contract_version = CONTRACT_VERSION,
        trade_count = 0,
        created_tick = game.tick,
        upper_port_layout_version = UPPER_PORT_LAYOUT_VERSION,
    }
    for index, role in ipairs(roles) do
        record.missions[index] = generate_mission(role, force, seed + index * 104729, level, 1)
        record.roles[index] = record.missions[index].role
    end
    record.last_mission_signature = mission_signature(record.missions[1])
    record.recent_request_roles = { record.missions[1].role }
    r.by_id[id] = record
    r.by_entity[entrance.unit_number] = id
    add_parent_record(surface.index, id)
    record.entrance_label_id = render_text(surface, { x = target.x, y = target.y - 3.4 },
        { "the-cave-lost-city.entrance-label" }, { r = 0.72, g = 0.35, b = 1 }, 1.25)
    local upper, panel = ensure_upper_entrance_infrastructure(record)
    if not (upper and panel) then
        destroy_render(record.entrance_label_id)
        r.by_entity[entrance.unit_number] = nil
        r.by_id[id] = nil
        remove_parent_record(surface.index, id)
        if entrance.valid then entrance.destroy() end
        if r.next_id == id + 1 then r.next_id = id end
        return nil, "upper-infrastructure-failed"
    end
    force.chart(surface, { { target.x - 8, target.y - 8 }, { target.x + 8, target.y + 8 } })
    return record
end

function lost_city.on_cavern_opened(dig, room_plan, room_label)
    if not enabled() then return false end
    if not (dig and dig.surface and dig.surface.valid and room_plan and dig.force) then return false end
    if not (type(room_label) == "table"
        and room_label[1] == "entity-name.the-cave-lost-city-entrance") then
        return false
    end
    local target = room_plan.entrance_position or { x = room_plan.cx + 0.5, y = room_plan.cy + 0.5 }
    local record = create_entrance(dig.surface, target, dig.force, false, false, nil)
    if record then
        dig.force.print({ "the-cave-lost-city.test-created", record.id })
    end
    return record ~= nil
end

local function create_test_entrance(player, forced_role)
    if surface_has_prefix(player.surface) then player.print({ "the-cave-lost-city.no-nesting" }) return end
    local preferred = { x = player.position.x + 8, y = player.position.y }
    local target = player.surface.find_non_colliding_position(ENTRANCE_NAME, preferred, 48, 0.5)
    if not target then
        player.print({ "the-cave-lost-city.test-failed", "no-clear-portal-position" })
        return
    end
    local record, reason = create_entrance(player.surface, target, player.force, true, true, forced_role)
    if not record then
        player.print({ "the-cave-lost-city.test-failed", reason or "unknown" })
        return
    end
    player.print({ "the-cave-lost-city.test-created", record.id })
end

function lost_city.register_commands()
    if not enabled() then return end
    commands.add_command("the-cave-lost-city-test", { "the-cave-lost-city.command-help" }, function(event)
        local player = valid_player(event.player_index)
        if not player then return end
        if not player.admin then player.print({ "the-cave-lost-city.admin-only" }) return end
        if not enabled() then player.print({ "the-cave-lost-city.disabled" }) return end
        local parameter = string.lower((event.parameter or "random"):match("^%s*(.-)%s*$"))
        local forced_role
        if parameter ~= "" and parameter ~= "random" then
            for _, role in ipairs(ROLE_ORDER) do
                if parameter == role then forced_role = role break end
            end
            if not forced_role then player.print({ "the-cave-lost-city.command-usage" }) return end
        end
        create_test_entrance(player, forced_role)
    end)
end

function lost_city.on_init()
    root()
end

local function upgrade_contract_record(record)
    local previous_version = record and (tonumber(record.contract_version) or 0) or 0
    if not record or previous_version >= CONTRACT_VERSION then return end
    if record.status == "closed" then
        record.contract_version = CONTRACT_VERSION
        return
    end
    local force = game.forces[record.owner_force_index]
    if not (force and force.valid) then return end
    local old_mission = current_mission(record)
    record.recent_request_roles = record.recent_request_roles or {}
    if old_mission and old_mission.role and #record.recent_request_roles == 0 then
        record.recent_request_roles[1] = old_mission.role
    end
    if previous_version >= 4 then
        if old_mission and not old_mission.reward_selection then
            local values = build_value_table(force)
            apply_request_floors_to_existing_mission(old_mission)
            revalue_existing_mission(old_mission, values)
            attach_reward_options(old_mission, force,
                game.create_random_generator((record.seed or 1)
                    + math.max(1, old_mission.trade_number or 1) * 104729), values)
            record.last_mission_signature = mission_signature(old_mission)
            -- Any reward/briefing window saved open contains the old package
            -- captions. The normal join/surface handler rebuilds it from the
            -- corrected offer without changing the request or timer.
            for _, player in pairs(game.players) do
                if player.gui.screen[GUI_DIALOG] then player.gui.screen[GUI_DIALOG].destroy() end
                if player.gui.screen[GUI_REWARD] then player.gui.screen[GUI_REWARD].destroy() end
            end
        end
        record.contract_version = CONTRACT_VERSION
        return
    end
    local role = old_mission and old_mission.role or (record.roles and record.roles[1]) or "engineer"
    if record.status == "completed" and old_mission then
        old_mission.trade_number = old_mission.trade_number or 1
        attach_reward_options(old_mission, force,
            game.create_random_generator((record.seed or 1) + 104729), build_value_table(force))
        old_mission.reward_selection = record.reward_selection
        record.trade_count = record.reward_selection and 1 or 0
        record.city_completion_counted = true
        record.last_mission_signature = mission_signature(old_mission)
        record.status = record.reward_selection and "reward-collection" or "awaiting-reward"
        record.contract_version = CONTRACT_VERSION
        return
    end
    if record.active_tag and record.active_tag.valid then record.active_tag.destroy() end
    record.active_tag = nil
    for _, npc in ipairs(record.npcs or {}) do
        destroy_render(npc.label_id)
        if npc.entity and npc.entity.valid then npc.entity.destroy() end
    end
    local mission = generate_mission(role, force, (record.seed or 1) + 104729,
        record.level or 1, 1)
    record.roles = { mission.role }
    record.missions = { mission }
    record.task_index = 1
    record.npcs = {}
    record.approach_started_tick = nil
    record.trade_count = 0
    record.last_mission_signature = mission_signature(mission)
    record.recent_request_roles = { mission.role }
    record.contract_version = CONTRACT_VERSION
    local surface = valid_surface(record.surface_index)
    if surface then
        place_npcs(record, surface, force, game.create_random_generator((record.seed or 1) + 17))
        if record.status == "active" then activate_task(record) end
    end
end

local function suspend_duplicate_village(record)
    if not (record and record.status ~= "closed" and record.started_tick) then return end
    evacuate_players(record)
    record.suspended_status = record.status
    record.suspended_remaining_ticks = math.max(1,
        (record.deadline_tick or (game.tick + operation_duration_ticks(record))) - game.tick)
    if record.next_offer_tick then
        record.suspended_next_offer_ticks = math.max(1, record.next_offer_tick - game.tick)
    else
        record.suspended_next_offer_ticks = nil
    end
    record.started_tick = nil
    record.deadline_tick = nil
    record.next_offer_tick = nil
    record.status = "waiting"
    ensure_upper_countdown_label(record, game.tick)
end

function lost_city.on_configuration_changed()
    local r = root()
    r.entity_cache = nil
    cleanup_legacy_closed_passage_labels()
    local chosen_by_force = {}
    for id, record in pairs(r.by_id) do
        record.power_connections_surface = nil
        record.item_connections_surface = nil
        record.id = record.id or id
        upgrade_contract_record(record)
        record.generated_chunks = record.generated_chunks or {}
        if record.started_tick and not record.deadline_tick then
            record.deadline_tick = record.started_tick + operation_duration_ticks(record)
        end
        if record.status ~= "closed" and record.started_tick then
            local force_index = record.owner_force_index
            local chosen = chosen_by_force[force_index]
            if not chosen or record.started_tick < chosen.started_tick
                or (record.started_tick == chosen.started_tick and record.id < chosen.id) then
                chosen_by_force[force_index] = record
            end
        end
    end
    for _, record in pairs(r.by_id) do
        local chosen = chosen_by_force[record.owner_force_index]
        if record.status ~= "closed" and record.started_tick
            and chosen and chosen.id ~= record.id then
            suspend_duplicate_village(record)
        end
    end
    r.by_surface = {}
    r.by_entity = {}
    r.active_by_force = {}
    r.entrances_by_parent = {}
    for id, record in pairs(r.by_id) do
        if record.parent_surface_index then add_parent_record(record.parent_surface_index, id) end
        if record.status ~= "closed" then
            cave_placement.repair_entrance(record, r, world, {
                "upper_power_unit_number", "upper_indicator_lamp_unit_number", "upper_info_panel_unit_number",
                "upper_item_down_input_unit_number", "upper_item_up_output_unit_number",
            }, PARENT_MIN_DISTANCE)
            if record.surface_index and valid_surface(record.surface_index) then
                r.by_surface[record.surface_index] = id
            end
            if record.entrance_unit_number then r.by_entity[record.entrance_unit_number] = id end
            if record.exit_unit_number then r.by_entity[record.exit_unit_number] = id end
            if record.reward_crate_unit_number then r.by_entity[record.reward_crate_unit_number] = id end
            if record.started_tick then r.active_by_force[record.owner_force_index] = id end
            ensure_upper_entrance_infrastructure(record)
        end
        if record.surface_index and valid_surface(record.surface_index) then
            r.by_surface[record.surface_index] = id
            local city_surface = valid_surface(record.surface_index)
            apply_city_lighting(city_surface)
            enforce_nauvis_map_gen(record, city_surface)
            ensure_city_house_ownership(record, city_surface)
            if record.status ~= "closed" then
                ensure_lower_item_ports(record, city_surface)
                connect_item_ports(record)
                ensure_power_bridge(record)
            end
        end
        ensure_upper_countdown_label(record, game.tick)
        if record.started_tick then update_all_huds(record) end
    end
end

function lost_city.on_surface_deleted(event)
    if not (event and event.surface_index) then return end
    local cache = root().entity_cache
    if cache then
        for unit, entity in pairs(cache) do
            if not entity.valid or entity.surface.index == event.surface_index then cache[unit] = nil end
        end
    end
    local id = root().by_surface[event.surface_index]
    if not id then return end
    local record = root().by_id[id]
    root().by_surface[event.surface_index] = nil
    if record then
        record.surface_index = nil
    end
    if record and record.status ~= "closed" then
        close_city(record, true)
    end
end

function lost_city.on_player_respawned(event)
    local player = valid_player(event.player_index)
    if not player then return end
    local pending = root().pending_respawns[player.index]
    local current = record_for_surface(physical.surface(player))
    if pending or current then
        local record = pending and root().by_id[pending.city_id] or current
        local parent = child_state.return_surface(player, pending and pending.parent_surface_index or current.parent_surface_index)
        if not parent then return end
        local preferred = child_state.spawn_position(player, parent)
        local position = physical.find_position(player, parent, preferred, 16)
        if not physical.teleport(player, position, parent) then return end
        root().pending_respawns[player.index] = nil
        if record then delete_child_if_empty(record) end
        destroy_player_gui(player)
        return
    end
    local record = record_for_surface(physical.surface(player))
    if record then update_player_hud(player, record) end
end

function lost_city.owned_surfaces(force)
    return child_state.owned_surfaces(root(), force, "surface_index", SURFACE_PREFIX, false)
end

function lost_city.owner_force(surface)
    return child_state.owner_force(root(), surface, "surface_index", SURFACE_PREFIX, false)
end

function lost_city.clear_force(force_index)
    child_state.clear_force(root(), force_index)
end

function lost_city.transfer_force(source_index, destination_index)
    child_state.transfer_force(root(), source_index, destination_index)
end

return lost_city
