local physical = require("scripts.player_physical")
local settings = require("scripts.game_settings").proxy(settings)

-- The Cave Ore Blood mode.
-- Optional startup reward layer: killed vanilla and Armoured Biters/Spitters drop
-- one random basic resource bundle. Coin drops are intentionally unchanged.
-- Train Wave units and Bosses use their own exact live Map-setting amounts.
-- A zero amount disables that tier without changing ordinary Ore Blood.
-- Worms, nests/spawners, pentapods, demolishers, turrets, and other enemies are
-- not affected.

local ore_blood = {}
local bob_enemies = require("scripts.bob_enemies")

local BASIC_RESOURCES = { "iron-ore", "copper-ore", "coal", "stone" }

local UNIT_DROPS = {
    -- Increased after player testing: the first pass was too tiny to feel useful.
    ["small-biter"] = { min = 10, max = 20 },
    ["small-spitter"] = { min = 10, max = 20 },

    ["medium-biter"] = { min = 20, max = 40 },
    ["medium-spitter"] = { min = 20, max = 40 },

    ["big-biter"] = { min = 40, max = 80 },
    ["big-spitter"] = { min = 40, max = 80 },

    ["behemoth-biter"] = { min = 80, max = 160 },
    ["behemoth-spitter"] = { min = 80, max = 160 },

    ["small-armoured-biter"] = { min = 10, max = 20 },
    ["medium-armoured-biter"] = { min = 20, max = 40 },
    ["big-armoured-biter"] = { min = 40, max = 80 },
    ["behemoth-armoured-biter"] = { min = 80, max = 160 },
    ["leviathan-armoured-biter"] = { min = 160, max = 320 },
}

for name,base in pairs(require("shared.fortified_combat").offspring_aliases) do
    UNIT_DROPS[name]=UNIT_DROPS[base]
end

local TRAIN_WAVE_UNIT_PREFIX = "the-cave-train-wave-"
local TRAIN_WAVE_RESOURCE_SETTINGS = {
    ["small-biter"] = "the-cave-train-wave-small-resource-drop",
    ["small-spitter"] = "the-cave-train-wave-small-resource-drop",
    ["medium-biter"] = "the-cave-train-wave-medium-resource-drop",
    ["medium-spitter"] = "the-cave-train-wave-medium-resource-drop",
    ["big-biter"] = "the-cave-train-wave-big-resource-drop",
    ["big-spitter"] = "the-cave-train-wave-big-resource-drop",
    ["behemoth-biter"] = "the-cave-train-wave-behemoth-resource-drop",
    ["behemoth-spitter"] = "the-cave-train-wave-behemoth-resource-drop",
}
local TRAIN_WAVE_BOSS_RESOURCE_SETTING = "the-cave-train-wave-boss-resource-drop"
local TRAIN_WAVE_RESOURCE_SETTING_NAMES = {
    "the-cave-train-wave-small-resource-drop",
    "the-cave-train-wave-medium-resource-drop",
    "the-cave-train-wave-big-resource-drop",
    "the-cave-train-wave-behemoth-resource-drop",
    TRAIN_WAVE_BOSS_RESOURCE_SETTING,
}

local function runtime_global_amount(name)
    local setting = settings and settings.global and settings.global[name]
    local value = setting and tonumber(setting.value) or 0
    return math.max(0, math.floor(value))
end

local function train_wave_base_unit_name(name)
    if type(name) ~= "string"
        or name:sub(1, #TRAIN_WAVE_UNIT_PREFIX) ~= TRAIN_WAVE_UNIT_PREFIX then
        return nil
    end

    local suffix = name:sub(#TRAIN_WAVE_UNIT_PREFIX + 1)
    local tier, kind = suffix:match("^([a-z]+)%-([a-z]+)$")
    if tier and kind then
        if kind == "armoured" or kind == "arachnid" then kind = "biter" end
        local base_name = tier .. "-" .. kind
        if TRAIN_WAVE_RESOURCE_SETTINGS[base_name] then return base_name, false end
    end

    local boss_tier = suffix:match("^boss%-([a-z]+)%-biter%-l%d+$")
    local boss_base = boss_tier and (boss_tier .. "-biter") or nil
    if boss_base and UNIT_DROPS[boss_base] then return boss_base, true end
    return nil, false
end

local BASIC_RESOURCE_SET = {}
for _, resource_name in pairs(BASIC_RESOURCES) do
    BASIC_RESOURCE_SET[resource_name] = true
end

local function setting_enabled()
    local setting = settings and settings.startup and settings.startup["the-cave-ore-blood"]
    return not setting or setting.value == "enabled" or setting.value == true
end

local function train_wave_resource_rewards_enabled()
    for _, setting_name in ipairs(TRAIN_WAVE_RESOURCE_SETTING_NAMES) do
        if runtime_global_amount(setting_name) > 0 then return true end
    end
    return false
end

local function item_exists(name)
    if prototypes and prototypes.item and prototypes.item[name] then return true end

    local ok, items = pcall(function()
        return game.item_prototypes
    end)
    return ok and items and items[name] ~= nil
end

local function random_basic_resource()
    return BASIC_RESOURCES[math.random(1, #BASIC_RESOURCES)] or "iron-ore"
end

function ore_blood.enabled()
    return setting_enabled()
end

local function get_pickup_position(player)
    return physical.position(player)
end

local function try_pickup_resource(player, item_entity)
    if not player or not player.valid or not item_entity or not item_entity.valid then return end
    local stack = item_entity.stack
    if not stack or not stack.valid_for_read or not BASIC_RESOURCE_SET[stack.name] then return end

    local name = stack.name
    local count = stack.count
    if count <= 0 then
        item_entity.destroy()
        return
    end

    local inserted = player.insert { name = name, count = count }
    if inserted <= 0 then return end

    if inserted >= count then
        item_entity.destroy()
    else
        stack.count = count - inserted
    end
end

function ore_blood.auto_pickup_resources()
    if not setting_enabled() and not train_wave_resource_rewards_enabled() then return end

    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.controller_type ~= defines.controllers.spectator then
            local surface = physical.surface(player)
            local position = get_pickup_position(player)
            if surface and surface.valid and position then
                local radius = 1.15
                local items = surface.find_entities_filtered {
                    name = "item-on-ground",
                    area = {
                        { position.x - radius, position.y - radius },
                        { position.x + radius, position.y + radius }
                    }
                }

                for _, item_entity in pairs(items) do
                    try_pickup_resource(player, item_entity)
                end
            end
        end
    end
end

function ore_blood.on_entity_died(event, suppress_rewards)
    local entity = event and event.entity
    if not entity or not entity.valid then return end
    if suppress_rewards then return end

    local wave_base_name, is_train_wave_boss = train_wave_base_unit_name(entity.name)
    local count = nil
    if wave_base_name then
        local setting_name = is_train_wave_boss
            and TRAIN_WAVE_BOSS_RESOURCE_SETTING
            or TRAIN_WAVE_RESOURCE_SETTINGS[wave_base_name]
        count = runtime_global_amount(setting_name)
        if count <= 0 then return end
    else
        if not setting_enabled() then return end
        local range = UNIT_DROPS[entity.name] or bob_enemies.ore_range(entity.name)
        if not range then return end
        count = math.random(range.min, range.max)
    end

    local surface = entity.surface
    if not surface or not surface.valid then return end
    if type(surface.name) == "string"
        and (surface.name:find("^the%-cave%-uranium%-cave%-")
            or surface.name:find("^the%-cave%-mineral%-cave%-")) then
        -- Timed extraction caves own their resource identity. Enemy kills must
        -- not leak unrelated resources into them through Ore Blood.
        return
    end

    local resource = random_basic_resource()
    if not item_exists(resource) then return end
    if not count or count <= 0 then return end

    -- Exact configured amounts can exceed the selected resource's current
    -- stack size. Split them into clean ground stacks so no reward is silently
    -- capped or lost when raw-resource stack-size settings are changed.
    local prototype = prototypes and prototypes.item and prototypes.item[resource]
    local stack_size = math.max(1, math.floor(tonumber(prototype and prototype.stack_size) or count))
    local remaining = count
    while remaining > 0 do
        local stack_count = math.min(remaining, stack_size)
        local created = nil
        local ok = pcall(function()
            created = surface.create_entity {
                name = "item-on-ground",
                position = entity.position,
                stack = { name = resource, count = stack_count }
            }
        end)
        if not ok or not created then break end
        remaining = remaining - stack_count
    end
end

return ore_blood
