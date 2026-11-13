-- Treasure sealed in the cover (CONTEXT.md "Treasure"): presence AND contents
-- are seed-keyed by tile (ADR 0005), so MTS team worlds hide identical chests
-- with identical loot in identical places. Contents scale with depth zone.
--
-- 1.8.24 Behrooz Treasure Balance Rework:
--   * Simple chunk-based square spacing: 2 empty chunks gap around each chest.
--   * All zones use 1-4 loot picks per chest.
--   * Loot quality comes from the depth zone, not from chest density.
--   * Coins are rare bonus loot, not the main treasure reward.
--   * Full stack size is not used as reward size.
local hash = require("scripts.lib.hash")
local reward_policy = require("scripts.reward_policy")
local market_policy = require("scripts.market_policy")

local treasure = {}

-- Hash stream ids (keep unique across all dig modules).
local S_PRESENCE, S_PICKS, S_ITEM, S_AMOUNT = 20, 21, 22, 23
local S_COIN_CHANCE, S_COIN_AMOUNT = 24, 25

local CHUNK_SIZE = 32
local TREASURE_GAP_CHUNKS = 2
local TREASURE_PICKS = { min = 1, max = 4 }
local TREASURE_COIN_CHANCE = 0.10 -- about 1 in 10 chests

-- The Cave treasure progression:
-- Easy      = survival supplies
-- Medium    = infrastructure and expansion
-- Hard      = heavy military and advanced tech
-- Nightmare = legendary endgame rewards
--
-- `weight` controls rarity inside a tier. Low weight = rare.
local LOOT_TIERS = {
    {
        max_depth = 300,
        chest = "wooden-chest",
        coin = { min = 5, max = 10 },
        loot = {
            { name = "stone-wall", min = 20, max = 60, weight = 18 },
            { name = "firearm-magazine", min = 20, max = 50, weight = 14 },
            { name = "piercing-rounds-magazine", min = 8, max = 24, weight = 8 },
            { name = "repair-pack", min = 5, max = 15, weight = 10 },
            { name = "iron-plate", min = 25, max = 60, weight = 12 },
            { name = "copper-plate", min = 25, max = 60, weight = 10 },
            { name = "steel-plate", min = 8, max = 25, weight = 7 },
            { name = "coal", min = 30, max = 80, weight = 8 },
            { name = "grenade", min = 4, max = 12, weight = 6 },
            { name = "gun-turret", min = 1, max = 2, weight = 4 },
            { name = "radar", min = 1, max = 1, weight = 2 },
            { name = "light-armor", min = 1, max = 1, weight = 2 },
            { name = "car", min = 1, max = 1, weight = 1 },
            { name = "solar-panel", min = 1, max = 2, weight = 1 },
            { name = "accumulator", min = 1, max = 2, weight = 1 },
            { name = "flamethrower-turret", min = 1, max = 1, weight = 1 },
            { name = "laser-turret", min = 1, max = 1, weight = 1 },
        },
    },
    {
        max_depth = 700,
        chest = "iron-chest",
        coin = { min = 10, max = 20 },
        loot = {
            { name = "solar-panel", min = 2, max = 6, weight = 12 },
            { name = "accumulator", min = 2, max = 6, weight = 12 },
            { name = "engine-unit", min = 5, max = 18, weight = 10 },
            { name = "electric-engine-unit", min = 3, max = 10, weight = 9 },
            { name = "battery", min = 12, max = 35, weight = 9 },
            { name = "electronic-circuit", min = 20, max = 50, weight = 10 },
            { name = "advanced-circuit", min = 8, max = 25, weight = 7 },
            { name = "steel-chest", min = 1, max = 3, weight = 6 },
            { name = "medium-electric-pole", min = 5, max = 15, weight = 7 },
            { name = "construction-robot", min = 2, max = 8, weight = 7 },
            { name = "logistic-robot", min = 2, max = 8, weight = 5 },
            { name = "roboport", min = 1, max = 1, weight = 4 },
            { name = "car", min = 1, max = 1, weight = 4 },
            { name = "modular-armor", min = 1, max = 1, weight = 3 },
            { name = "laser-turret", min = 1, max = 2, weight = 4 },
            { name = "flamethrower-turret", min = 1, max = 1, weight = 3 },
            { name = "personal-roboport-equipment", min = 1, max = 1, weight = 1 },
            { name = "exoskeleton-equipment", min = 1, max = 1, weight = 1 },
        },
    },
    {
        max_depth = 1400,
        chest = "steel-chest",
        coin = { min = 15, max = 30 },
        loot = {
            { name = "laser-turret", min = 2, max = 5, weight = 10 },
            { name = "flamethrower-turret", min = 1, max = 3, weight = 9 },
            { name = "rocket-launcher", min = 1, max = 1, weight = 6 },
            { name = "rocket", min = 5, max = 15, weight = 7 },
            { name = "explosive-rocket", min = 3, max = 10, weight = 6 },
            { name = "uranium-rounds-magazine", min = 10, max = 30, weight = 7 },
            { name = "tank", min = 1, max = 1, weight = 5 },
            { name = "power-armor", min = 1, max = 1, weight = 4 },
            { name = "substation", min = 2, max = 6, weight = 9 },
            { name = "processing-unit", min = 3, max = 10, weight = 5 },
            { name = "heat-pipe", min = 10, max = 30, weight = 10 },
            { name = "heat-exchanger", min = 1, max = 4, weight = 7 },
            { name = "steam-turbine", min = 1, max = 4, weight = 7 },
            { name = "uranium-fuel-cell", min = 2, max = 8, weight = 6 },
            { name = "nuclear-fuel", min = 1, max = 4, weight = 4 },
            { name = "nuclear-reactor", min = 1, max = 1, weight = 2 },
            { name = "battery-mk2-equipment", min = 1, max = 1, weight = 2 },
            { name = "personal-laser-defense-equipment", min = 1, max = 1, weight = 1 },
            -- Factorio 2.0 renamed portable fusion reactor equipment to fission reactor equipment.
            { name = "fission-reactor-equipment", min = 1, max = 1, weight = 1 },
        },
    },
    {
        max_depth = math.huge,
        chest = "steel-chest",
        coin = { min = 25, max = 50 },
        loot = {
            { name = "power-armor", min = 1, max = 1, weight = 8 },
            { name = "tank", min = 1, max = 1, weight = 6 },
            { name = "processing-unit", min = 5, max = 15, weight = 8 },
            { name = "uranium-235", min = 3, max = 10, weight = 7 },
            { name = "fission-reactor-equipment", min = 1, max = 1, weight = 6 },
            { name = "personal-roboport-mk2-equipment", min = 1, max = 1, weight = 6 },
            { name = "personal-laser-defense-equipment", min = 1, max = 1, weight = 6 },
            { name = "exoskeleton-equipment", min = 1, max = 1, weight = 6 },
            { name = "energy-shield-mk2-equipment", min = 1, max = 1, weight = 6 },
            { name = "battery-mk2-equipment", min = 1, max = 1, weight = 6 },
            { name = "productivity-module-3", min = 1, max = 2, weight = 4 },
            { name = "speed-module-3", min = 1, max = 2, weight = 4 },
            { name = "efficiency-module-3", min = 1, max = 2, weight = 4 },
            { name = "power-armor-mk2", min = 1, max = 1, weight = 1 }, -- very rare
            { name = "spidertron", min = 1, max = 1, weight = 1 }, -- extremely rare jackpot
        },
    },
}

local function tier_for(depth)
    for _, tier in pairs(LOOT_TIERS) do
        if depth <= tier.max_depth then return tier end
    end
end

local function item_exists(name)
    return prototypes and prototypes.item and prototypes.item[name] ~= nil
end

local function chunk_coord(v)
    return math.floor(v / CHUNK_SIZE)
end

local function surface_key(surface)
    return tostring(surface.index)
end

local function ensure_treasure_storage()
    storage.the_cave_treasure_chunks = storage.the_cave_treasure_chunks or {}
    return storage.the_cave_treasure_chunks
end

local function is_chunk_blocked(surface, cx, cy)
    local all = ensure_treasure_storage()
    local list = all[surface_key(surface)]
    if not list then return false end

    for _, pos in pairs(list) do
        if math.abs(cx - pos.x) <= TREASURE_GAP_CHUNKS and math.abs(cy - pos.y) <= TREASURE_GAP_CHUNKS then
            return true
        end
    end
    return false
end

local function remember_treasure_chunk(surface, cx, cy)
    local all = ensure_treasure_storage()
    local key = surface_key(surface)
    all[key] = all[key] or {}
    all[key][#all[key] + 1] = { x = cx, y = cy }
end

local function pick_weighted_item(tier, seed, x, y, stream)
    local total = 0
    for _, item in pairs(tier.loot) do
        if item_exists(item.name) and reward_policy.is_allowed(item.name) then
            total = total + (item.weight or 1)
        end
    end
    if total <= 0 then return nil end

    local roll = hash.roll(seed, x, y, stream) * total
    for _, item in pairs(tier.loot) do
        if item_exists(item.name) and reward_policy.is_allowed(item.name) then
            roll = roll - (item.weight or 1)
            if roll <= 0 then return item end
        end
    end
end

local function insert_random_loot(chest, item, seed, x, y, stream)
    if not item or not reward_policy.is_allowed(item.name) then return end
    chest.insert {
        name = item.name,
        count = hash.range(seed, x, y, stream, item.min, item.max),
    }
end

local function insert_coin_bonus(chest, tier, seed, x, y)
    if not item_exists("coin") or not tier.coin then return false end
    if hash.roll(seed, x, y, S_COIN_CHANCE) >= TREASURE_COIN_CHANCE then return false end

    if market_policy.enabled() then
        chest.insert {
            name = "coin",
            count = hash.range(seed, x, y, S_COIN_AMOUNT, tier.coin.min, tier.coin.max),
        }
    end
    -- Still reserve the original coin pick while disabled. Other loot keeps
    -- exactly the same seed, count and value; no replacement reward is added.
    return true
end

-- Place a loot chest near a tile, tiered by depth and seed-keyed by the tile.
-- Used by per-dig treasure rolls and by hoard rooms (caverns).
function treasure.spawn_chest(surface, x, y, depth)
    local seed = surface.map_gen_settings.seed
    local tier = tier_for(depth)
    if not tier then return end

    local source_cx = chunk_coord(x)
    local source_cy = chunk_coord(y)
    if is_chunk_blocked(surface, source_cx, source_cy) then return end

    local position = surface.find_non_colliding_position(tier.chest, { x + 0.5, y + 0.5 }, 2, 0.5)
    if not position then return end

    local final_cx = chunk_coord(position.x)
    local final_cy = chunk_coord(position.y)
    if is_chunk_blocked(surface, final_cx, final_cy) then return end

    local chest = surface.create_entity { name = tier.chest, position = position, force = "neutral" }
    if not chest then return end

    remember_treasure_chunk(surface, final_cx, final_cy)

    local picks = hash.range(seed, x, y, S_PICKS, TREASURE_PICKS.min, TREASURE_PICKS.max)
    local coin_inserted = insert_coin_bonus(chest, tier, seed, x, y)
    if coin_inserted then
        picks = math.max(0, picks - 1)
    end

    for i = 1, picks do
        local item = pick_weighted_item(tier, seed, x, y, S_ITEM + i * 100)
        insert_random_loot(chest, item, seed, x, y, S_AMOUNT + i * 100)
    end
end

function treasure.on_dig(dig)
    local surface = dig.surface
    local x = math.floor(dig.position.x)
    local y = math.floor(dig.position.y)

    -- Treasure density is intentionally the same in all depth zones and all global difficulty settings.
    -- Zone affects loot quality only.
    local chance = settings.global["diggy-treasure-chance"].value
    if hash.roll(surface.map_gen_settings.seed, x, y, S_PRESENCE) >= math.min(1, chance) then
        return
    end

    treasure.spawn_chest(surface, x, y, math.sqrt(x * x + y * y))
end

return treasure
