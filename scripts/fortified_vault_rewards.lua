-- 3.2.5 group budgets, transcribed from the edited loot workbook.
-- Every retained item is rolled once per stronghold, then shared among its
-- colour's chests. No per-chest rerolls, research gates or global loot caps.
local hash = require("scripts.lib.hash")
local rewards = {}
rewards.pools = {
    standard = {
        { name = "repair-pack", min = 50, max = 100 }, -- R-B-04
        { name = "electronic-circuit", min = 200, max = 400 }, -- R-B-05
        { name = "electric-mining-drill", min = 10, max = 15 }, -- R-B-07
        { name = "assembling-machine-2", min = 10, max = 20 }, -- R-B-08
        { name = "steel-furnace", min = 20, max = 40 }, -- R-B-09
        { name = "piercing-rounds-magazine", min = 200, max = 300 }, -- R-B-10
        { name = "grenade", min = 20, max = 50 }, -- R-B-11
        { name = "car", min = 1, max = 1 }, -- R-B-12
        { name = "construction-robot", min = 10, max = 20 }, -- R-B-13
        { name = "logistic-robot", min = 10, max = 20 }, -- R-B-14
        { name = "accumulator", min = 25, max = 50 }, -- R-B-15
        { name = "transport-belt", min = 100, max = 200 }, -- R-B-16-1
        { name = "underground-belt", min = 20, max = 20 }, -- R-B-16-2
        { name = "splitter", min = 10, max = 10 }, -- R-B-16-3
        { name = "fast-transport-belt", min = 100, max = 200 }, -- R-B-17-1
        { name = "fast-underground-belt", min = 20, max = 20 }, -- R-B-17-2
        { name = "fast-splitter", min = 10, max = 10 }, -- R-B-17-3
    },
    secure = {
        { name = "advanced-circuit", min = 200, max = 400 }, -- R-Y-02
        { name = "electric-engine-unit", min = 100, max = 200 }, -- R-Y-04
        { name = "flying-robot-frame", min = 5, max = 10 }, -- R-Y-05
        { name = "electric-furnace", min = 10, max = 20 }, -- R-Y-06
        { name = "assembling-machine-3", min = 10, max = 20 }, -- R-Y-07
        { name = "roboport", min = 2, max = 4 }, -- R-Y-08
        { name = "tank", min = 1, max = 1 }, -- R-Y-09
        { name = "rocket-launcher", min = 1, max = 1 }, -- R-Y-10
        { name = "explosive-rocket", min = 100, max = 200 }, -- R-Y-11
        { name = "substation", min = 10, max = 20 }, -- R-Y-14
        { name = "uranium-238", min = 50, max = 100 }, -- R-Y-15
        { name = "express-transport-belt", min = 100, max = 100 }, -- R-Y-17-1
        { name = "express-underground-belt", min = 20, max = 20 }, -- R-Y-17-2
        { name = "express-splitter", min = 10, max = 10 }, -- R-Y-17-3
    },
    high = {
        { name = "processing-unit", min = 100, max = 200 }, -- R-R-01
        { name = "low-density-structure", min = 100, max = 200 }, -- R-R-02
        { name = "rocket-fuel", min = 100, max = 200 }, -- R-R-03
        { name = "uranium-ore", min = 200, max = 500 }, -- R-R-04
        { name = "uranium-235", min = 20, max = 50 }, -- R-R-05
        { name = "uranium-238", min = 100, max = 300 }, -- R-R-06
        { name = "uranium-fuel-cell", min = 2, max = 5 }, -- R-R-07
        { name = "nuclear-fuel", min = 10, max = 20 }, -- R-R-09
        { name = "centrifuge", min = 1, max = 1 }, -- R-R-10
        { name = "heat-pipe", min = 20, max = 40 }, -- R-R-11
        { name = "heat-exchanger", min = 5, max = 10 }, -- R-R-12
        { name = "steam-turbine", min = 10, max = 20 }, -- R-R-13
        { name = "tank", min = 1, max = 1 }, -- R-R-14
        { name = "uranium-cannon-shell", min = 50, max = 100 }, -- R-R-15
        { name = "explosive-uranium-cannon-shell", min = 50, max = 100 }, -- R-R-16
        { name = "explosive-rocket", min = 200, max = 400 }, -- R-R-17
        { name = "fission-reactor-equipment", min = 1, max = 1 }, -- R-R-18
        { name = "battery-mk2-equipment", min = 1, max = 2 }, -- R-R-19
        { name = "energy-shield-mk2-equipment", min = 1, max = 2 }, -- R-R-20
        { name = "personal-roboport-mk2-equipment", min = 1, max = 1 }, -- R-R-21
        { name = "artillery-turret", min = 1, max = 2 }, -- R-R-22
        { name = "artillery-shell", min = 5, max = 10 }, -- R-R-23
        { name = "atomic-bomb", min = 1, max = 1 }, -- R-R-24
        { name = "express-transport-belt", min = 100, max = 100 }, -- R-R-25-1
        { name = "express-underground-belt", min = 20, max = 20 }, -- R-R-25-2
        { name = "express-splitter", min = 10, max = 10 }, -- R-R-25-3
        { name = "turbo-transport-belt", min = 100, max = 100 }, -- R-R-26-1
        { name = "turbo-underground-belt", min = 20, max = 20 }, -- R-R-26-2
        { name = "turbo-splitter", min = 10, max = 10 }, -- R-R-26-3
    },
}
rewards.guarantees = {
    standard = {
        { "modular-armor", 1 }, { "gun-turret", 50 }, { "firearm-magazine", 1000 },
        { "the-cave-tnt-box-small", 10 }, { "defender-capsule", 100 },
        { "inserter", 100 }, { "long-handed-inserter", 100 },
    },
    secure = {
        { "power-armor", 1 }, { "laser-turret", 20 }, { "the-cave-tnt-box-medium", 10 },
        { "distractor-capsule", 100 }, { "chemical-rocket", 100 },
        { "the-cave-accumulator-6x6", 2 }, { "fast-inserter", 100 }, { "bulk-inserter", 50 },
    },
    high = {
        { "power-armor-mk2", 1 }, { "nuclear-reactor", 1 }, { "uranium-rounds-magazine", 300 },
        { "the-cave-tnt-box-large", 10 }, { "destroyer-capsule", 20 },
        { "incendiary-rocket", 100 }, { "the-cave-accumulator-10x10", 1 },
    },
}

-- Random positive weights vary quantities between boxes; low counts select
-- only a few boxes. Integer remainders and overflow retries preserve totals.
function rewards.spread(chests, name, total, seed, stream, insert)
    if #chests == 0 then return 0 end
    local weights, weight_total = {}, 0
    for i = 1, #chests do
        weights[i] = hash.range(seed, stream, i, 21400, 1, 8)
        weight_total = weight_total + weights[i]
    end
    local shares, assigned = {}, 0
    for i = 1, #chests do
        shares[i] = math.floor(total * weights[i] / weight_total)
        assigned = assigned + shares[i]
    end
    local start = hash.range(seed, stream, #chests, 21401, 1, #chests)
    for offset = 0, total - assigned - 1 do
        local i = ((start + offset - 1) % #chests) + 1
        shares[i] = shares[i] + 1
    end
    local inserted = 0
    for i, chest in ipairs(chests) do
        if shares[i] > 0 then inserted = inserted + insert(chest, name, shares[i]) end
    end
    for offset = 0, #chests - 1 do
        if inserted >= total then break end
        inserted = inserted + insert(chests[((start + offset - 1) % #chests) + 1], name, total - inserted)
    end
    return inserted
end

function rewards.fill(chests, seed, group_index, available, insert)
    local totals, delivered = {}, {}
    local stream = group_index * 1000
    for tier_index, tier in ipairs { "standard", "secure", "high" } do
        totals[tier], delivered[tier] = {}, {}
        local function give(name, total)
            stream = stream + 1
            if not available(name) then return end
            totals[tier][name] = (totals[tier][name] or 0) + total
            local count = rewards.spread(chests[tier], name, total, seed, stream, insert)
            delivered[tier][name] = (delivered[tier][name] or 0) + count
        end
        for index, entry in ipairs(rewards.pools[tier]) do
            give(entry.name, hash.range(seed, group_index, index, 23000 + tier_index, entry.min, entry.max))
        end
        for _, entry in ipairs(rewards.guarantees[tier]) do give(entry[1], entry[2]) end
        local modules = {}
        for _, base in ipairs { "speed-module", "productivity-module", "efficiency-module", "quality-module" } do
            local name = tier_index == 1 and base or (base .. "-" .. tier_index)
            if available(name) then modules[#modules + 1] = name end
        end
        local module_total = ({100, 50, 30})[tier_index]
        for i, name in ipairs(modules) do
            give(name, math.floor(module_total / #modules) + (i <= module_total % #modules and 1 or 0))
        end
    end
    return totals, delivered
end
return rewards
