-- Shared runtime view of the independent Startup settings.
-- The proxy keeps every gameplay module on the established setting interface
-- while allowing compatible scenario features to be enabled together.

local game_settings = {}
local roof_support_variants = require("shared.roof_support")

function game_settings.value(name, fallback)
    local setting = settings and settings.startup and settings.startup[name]
    if setting ~= nil then return setting.value end
    return fallback
end

function game_settings.enabled(name, fallback)
    local value = game_settings.value(name, fallback ~= false and "enabled" or "disabled")
    return value == true or value == "enabled"
end

-- Wave Defense and Biter Expansion are independent systems. The combined
-- label is retained for diagnostics, while each gameplay predicate below
-- reads only its own Startup request.
function game_settings.enemy_attack_mode()
    local wave = game_settings.enabled("the-cave-allow-wave-defense", true)
    local expansion = game_settings.enabled("the-cave-allow-biter-expansion", false)
    if wave and expansion then return "combined" end
    if wave then return "wave-defense" end
    if expansion then return "biter-expansion" end
    return "disabled"
end

function game_settings.wave_defense_enabled()
    return game_settings.enabled("the-cave-allow-wave-defense", true)
end

function game_settings.biter_expansion_enabled()
    return game_settings.enabled("the-cave-allow-biter-expansion", false)
end

-- Temporarily disabled; retain the Queen implementation for a later redesign.
function game_settings.arachnid_queen_enabled()
    return false
end

function game_settings.enemy_attack_mode_conflict()
    -- Compatibility no-op for callers from older releases.
    return false
end

function game_settings.proxy(real_settings)
    local startup = setmetatable({}, {
        __index = function(_, name)
            local real = real_settings and real_settings.startup and real_settings.startup[name]
            local value = game_settings.value(name, real and real.value or nil)
            if value == nil then return real end
            return { value = value }
        end,
        __pairs = function()
            return pairs(real_settings and real_settings.startup or {})
        end,
    })
    return setmetatable({
        startup = startup,
        -- Capture the already-loaded function during control.lua parsing.
        -- Runtime event handlers can call it without invoking require again.
        wave_defense_enabled = game_settings.wave_defense_enabled,
    }, {
        __index = function(_, name)
            return real_settings and real_settings[name] or nil
        end,
    })
end

local TRAIN_PREFIXES = {
    "the-cave-train-battery-upgrade-",
    "the-cave-train-interior-expansion-",
    "the-cave-main-train-expansion-",
    "the-cave-locomotive-garden-",
    "the-cave-train-shield-upgrade-",
}
local CAVETORIO_PREFIXES = {
    "the-cave-warp-outpost-expansion-",
    "the-cave-warp-outpost-time-",
    "the-cave-safety-ring-upgrade-",
}
local SHELTER_PREFIXES = {
    "the-cave-shelter-interior-expansion-",
    "the-cave-shelter-battery-upgrade-",
    "the-cave-shelter-shield-upgrade-",
    "the-cave-shelter-garden-",
}
local SHELTER_ATTACK_DISTANCE_PREFIX = "the-cave-shelter-attack-distance-"

local function has_prefix(name, prefixes)
    for _, prefix in ipairs(prefixes) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

function game_settings.mode()
    local train = game_settings.enabled("the-cave-train-interiors", false)
    local shelter = game_settings.enabled("the-cave-shelter-defense", false)
    if train and shelter then return "conflict" end
    if game_settings.enabled("the-cave-cavetorio", false) then return "cavetorio" end
    if shelter then return "shelter" end
    if train then return "train" end
    if game_settings.enabled("the-cave-advancing-collapse", false) then return "advancing" end
    if game_settings.enabled("the-cave-collapse-mode", false) then return "collapse" end
    if game_settings.value("the-cave-digging-mode", "disabled") ~= "disabled" then return "digging" end
    return "normal"
end

local TRAIN_RECIPES = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" }

function game_settings.lock_advancing_train_recipes(force)
    if not game_settings.enabled("the-cave-advancing-collapse", false) then return end
    if not (force and force.valid) then return end
    storage.the_cave_advancing_train_locks = storage.the_cave_advancing_train_locks or {}
    storage.the_cave_advancing_train_locks[force.index] = true
    for _, name in ipairs(TRAIN_RECIPES) do
        local recipe = force.recipes[name]
        if recipe then recipe.enabled = false end
    end
end

local function restore_advancing_train_recipes()
    if game_settings.enabled("the-cave-advancing-collapse", false) then return end
    local locked = storage.the_cave_advancing_train_locks
    if not locked then return end
    local train = game_settings.enabled("the-cave-train-interiors", false)
        and not game_settings.enabled("the-cave-shelter-defense", false)
    if not train then
        for _, force in pairs(game.forces) do
            if locked[force.index] then
                local unlocked = {}
                for _, name in ipairs(TRAIN_RECIPES) do
                    local prototype = prototypes.recipe[name]
                    unlocked[name] = prototype and prototype.enabled == true or false
                end
                for _, technology in pairs(force.technologies) do
                    if technology.researched then
                        for _, effect in pairs(technology.prototype.effects or {}) do
                            if effect.type == "unlock-recipe" and unlocked[effect.recipe] ~= nil then
                                unlocked[effect.recipe] = true
                            end
                        end
                    end
                end
                for name, enabled in pairs(unlocked) do
                    if force.recipes[name] then force.recipes[name].enabled = enabled end
                end
            end
        end
    end
    storage.the_cave_advancing_train_locks = nil
end

-- A valid LuaPlayer can have no manual crafter (for example while dead).
-- Catch that API condition at the call site, without hiding unrelated errors.
local function try_manual_crafting(call)
    local ok, result = pcall(call)
    if not ok then
        if type(result) == "string" and result:find("No manual crafter", 1, true) then
            return false
        end
        error(result, 0)
    end
    return true, result
end

-- Existing hand-crafting queues predate the prototype restriction. Cancel only
-- the four blocked recipes, returning their ingredients through Factorio.
function game_settings.cancel_advancing_train_crafting()
    if not game_settings.enabled("the-cave-advancing-collapse", false) then return end
    local blocked = {}
    for _, name in ipairs(TRAIN_RECIPES) do blocked[name] = true end
    for _, player in pairs(game.players) do
        local previous_remaining
        while player.valid do
            local readable, queue = try_manual_crafting(function() return player.crafting_queue end)
            if not readable or not queue then break end
            local index, remaining = nil, 0
            for i = #queue, 1, -1 do
                if blocked[queue[i].recipe] then
                    index = index or i
                    remaining = remaining + queue[i].count
                end
            end
            if not index then break end
            -- cancel_crafting has no return value. Observe actual progress so
            -- an unchanged queue cannot stall configuration loading.
            if previous_remaining and remaining >= previous_remaining then break end
            previous_remaining = remaining
            local cancelled = try_manual_crafting(function()
                player.cancel_crafting { index = index, count = queue[index].count }
            end)
            if not cancelled then break end
            -- Cancelling an item can also remove intermediate crafts. Always
            -- read the new queue before using another index.
        end
    end
end

-- Reapply saved per-force flags after configuration changes and force lifecycle
-- events. Research progress stays intact; recipes follow their own stage only.
function game_settings.apply_roof_support_research(force)
    if not (force and force.valid) then return end
    local collapse = game_settings.enabled("the-cave-collapse-mode", false)
    for _, variant in ipairs(roof_support_variants) do
        local technology = force.technologies[variant.technology]
        if technology then
            technology.enabled = collapse
            technology.visible_when_disabled = false
        end
        local recipe = force.recipes[variant.name]
        if recipe then recipe.enabled = collapse and technology ~= nil and technology.researched end
    end
end

function game_settings.on_roof_support_research(event)
    local technology = event.research
    if not technology then return end
    for _, variant in ipairs(roof_support_variants) do
        if technology.name == variant.technology then
            game_settings.apply_roof_support_research(technology.force)
            return
        end
    end
end

function game_settings.apply_to_force(force)
    if not (force and force.valid) then return end
    local train_requested = game_settings.enabled("the-cave-train-interiors", false)
    local shelter_requested = game_settings.enabled("the-cave-shelter-defense", false)
    local interior_conflict = train_requested and shelter_requested
    local train = train_requested and not interior_conflict
    local shelter = shelter_requested and not interior_conflict
    local shelter_wave = shelter and game_settings.wave_defense_enabled()
    local cavetorio = game_settings.enabled("the-cave-cavetorio", false) and train
    local collapse = game_settings.enabled("the-cave-collapse-mode", false)
    for name, technology in pairs(force.technologies or {}) do
        if has_prefix(name, TRAIN_PREFIXES) then technology.enabled = train
        elseif has_prefix(name, CAVETORIO_PREFIXES) then technology.enabled = cavetorio
        elseif has_prefix(name, SHELTER_PREFIXES) then technology.enabled = shelter
        elseif name:sub(1, #SHELTER_ATTACK_DISTANCE_PREFIX) == SHELTER_ATTACK_DISTANCE_PREFIX then
            -- Attack Distance changes only Wave Defense tunnel spawns. Keep
            -- completed progress in the save, but remove this dead research
            -- branch completely whenever Shelter Wave Defense is disabled.
            technology.enabled = shelter_wave
            technology.visible_when_disabled = false
        elseif name:sub(1, #"diggy-support-reach-") == "diggy-support-reach-" then technology.enabled = collapse end
    end
    game_settings.apply_roof_support_research(force)

    -- Fluid Wagon has no usable research reward in Train modes because its
    -- recipe is intentionally supplied through exploration instead of
    -- crafting. Keep the vanilla technology untouched in every other mode.
    -- This also repairs existing saves which already completed the research:
    -- their progress is preserved, but the technology is hidden and the
    -- recipe below is force-disabled again as soon as the update loads.
    if train then
        local fluid_wagon_technology = force.technologies and force.technologies["fluid-wagon"]
        if fluid_wagon_technology then
            fluid_wagon_technology.enabled = false
            -- Factorio saves this per-Force flag inside existing saves, so
            -- set it at runtime as well as in the data-stage prototype.
            fluid_wagon_technology.visible_when_disabled = false
        end
    end

    for _, name in ipairs(TRAIN_RECIPES) do
        local recipe = force.recipes and force.recipes[name]
        if recipe and train then recipe.enabled = false end
    end
    game_settings.lock_advancing_train_recipes(force)
end

function game_settings.apply_to_forces()
    if not game then return end
    restore_advancing_train_recipes()
    for _, force in pairs(game.forces or {}) do
        game_settings.apply_to_force(force)
    end
end

return game_settings
