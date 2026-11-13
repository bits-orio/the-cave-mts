local M = {}

local STORAGE_KEY = "the_cave_belt_stack_sync_2_5_5"

local REGULAR_NAMES = {
    "burner-inserter",
    "inserter",
    "long-handed-inserter",
    "fast-inserter",
}

local HEAVY_NAMES = {
    "bulk-inserter",
    "stack-inserter",
}

local LEGACY_REGULAR_OVERRIDES = {
    ["burner-inserter"] = 3,
    ["inserter"] = 3,
    ["long-handed-inserter"] = 3,
    ["fast-inserter"] = 3,
}

local LEGACY_HEAVY_OVERRIDES = {
    ["bulk-inserter"] = 12,
    ["stack-inserter"] = 16,
}

local function researched_capacity_level(force)
    if not (force and force.valid) then return 0 end
    for level = 18, 1, -1 do
        local technology = force.technologies["transport-belt-capacity-" .. level]
        if technology and technology.researched then
            return level
        end
    end
    return 0
end

local function ensure_progressive_regular_bonus(force, level)
    if not (force and force.valid) then return false end
    if level < 1 then return false end

    -- A regular inserter has base hand size 1. Inserter Capacity Bonus 7 leaves
    -- the force at bonus 2 (hand size 3). Capacity levels 2-18 add +1 each, so
    -- the intended minimum force bonus is level + 1: level 12 => bonus 13 =>
    -- hand size 14, and level 18 => bonus 19 => hand size 20.
    local intended_minimum = level + 1
    if force.inserter_stack_size_bonus < intended_minimum then
        force.inserter_stack_size_bonus = intended_minimum
        return true
    end
    return false
end

local function reset_exact_overrides(force, names, legacy_values)
    if not (force and force.valid) then return 0 end

    local changed = 0
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local inserters = surface.find_entities_filtered {
                name = names,
                force = force,
            }
            for _, inserter in pairs(inserters) do
                if inserter.valid then
                    local legacy = legacy_values[inserter.name]
                    if legacy and inserter.inserter_stack_size_override == legacy then
                        -- Zero means no per-entity limit: follow the current force research.
                        inserter.inserter_stack_size_override = 0
                        changed = changed + 1
                    end
                end
            end
        end
    end

    return changed
end

local function state()
    storage[STORAGE_KEY] = storage[STORAGE_KEY] or {
        regular_forces = {},
        heavy_forces = {},
    }
    storage[STORAGE_KEY].regular_forces = storage[STORAGE_KEY].regular_forces or {}
    storage[STORAGE_KEY].heavy_forces = storage[STORAGE_KEY].heavy_forces or {}
    return storage[STORAGE_KEY]
end

local function reconcile_force(force)
    if not (force and force.valid) then return end

    local level = researched_capacity_level(force)
    local s = state()

    -- Reconcile only this feature's regular-inserter force bonus. Using a
    -- minimum preserves any larger bonus supplied intentionally by another mod
    -- and avoids resetting unrelated technology effects on a live server save.
    if level >= 1 then
        ensure_progressive_regular_bonus(force, level)
    end

    -- Level 2 is the first level that raises regular inserters above their
    -- vanilla researched hand capacity of 3. Clear only the exact old automatic
    -- value; player-selected custom limits such as 1, 2, 5 or 10 are preserved.
    if level >= 2 and not s.regular_forces[force.index] then
        local changed = reset_exact_overrides(force, REGULAR_NAMES, LEGACY_REGULAR_OVERRIDES)
        s.regular_forces[force.index] = true
        if changed > 0 then
            log("[The Cave] Reset " .. changed .. " legacy regular-inserter stack-size overrides for force '" .. force.name .. "'.")
        end
    end

    -- Bulk and Stack begin their final progression at Capacity 15. Clear the
    -- exact legacy 12/16 per-entity limits at that point so already placed
    -- inserters immediately follow the force bonus: 17, 18, 19, then 20.
    if level >= 15 and not s.heavy_forces[force.index] then
        local changed = reset_exact_overrides(force, HEAVY_NAMES, LEGACY_HEAVY_OVERRIDES)
        s.heavy_forces[force.index] = true
        if changed > 0 then
            log("[The Cave] Reset " .. changed .. " legacy Bulk/Stack Inserter stack-size overrides for force '" .. force.name .. "'.")
        end
    end
end

function M.on_configuration_changed()
    for _, force in pairs(game.forces) do
        reconcile_force(force)
    end
end

function M.on_research_finished(event)
    local research = event and event.research
    if not (research and research.valid) then return end

    local level = tonumber(string.match(research.name, "^transport%-belt%-capacity%-(%d+)$"))
    if not level then return end

    reconcile_force(research.force)
end

return M
