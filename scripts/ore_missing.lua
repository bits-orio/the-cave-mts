local settings = require("scripts.game_settings").proxy(settings)

-- The Cave Ore Patch Missing mode.
-- Optional startup challenge: one basic ore type has no natural patches in the cave.
-- The missing ore is still available from digging rocks, preserving progression while
-- making the cave's resource economy feel different per map seed.
local hash = require("scripts.lib.hash")

local ore_missing = {}

local S_ORE_PATCH_MISSING_PICK = 710

local BASIC_ORES = { "iron-ore", "copper-ore", "coal", "stone" }
local BASIC_ORE_SET = {
    ["iron-ore"] = true,
    ["copper-ore"] = true,
    ["coal"] = true,
    ["stone"] = true,
}

local function setting_enabled()
    local setting = settings and settings.startup and settings.startup["the-cave-ore-patch-missing"]
    return setting and (setting.value == "enabled" or setting.value == true)
end

local function state()
    storage.the_cave_ore_patch_missing = storage.the_cave_ore_patch_missing or {}
    return storage.the_cave_ore_patch_missing
end

local function map_seed()
    local surface = game and game.surfaces and game.surfaces["nauvis"]
    if surface and surface.valid and surface.map_gen_settings then
        return surface.map_gen_settings.seed or 0
    end
    return 0
end

function ore_missing.enabled()
    return setting_enabled()
end

function ore_missing.get_missing_resource()
    if not setting_enabled() then return nil end

    local s = state()
    if BASIC_ORE_SET[s.resource] then return s.resource end

    local seed = map_seed()
    s.resource = BASIC_ORES[hash.range(seed, 0, 0, S_ORE_PATCH_MISSING_PICK, 1, #BASIC_ORES)] or "iron-ore"
    return s.resource
end

function ore_missing.is_missing(resource_name)
    if not BASIC_ORE_SET[resource_name] then return false end
    return ore_missing.get_missing_resource() == resource_name
end

function ore_missing.filter_weighted(weighted)
    local missing = ore_missing.get_missing_resource()
    if not missing then return weighted end

    local filtered = {}
    for _, item in pairs(weighted or {}) do
        if item[1] ~= missing then
            filtered[#filtered + 1] = item
        end
    end
    return filtered
end

function ore_missing.filter_resource_names(names)
    local missing = ore_missing.get_missing_resource()
    if not missing then return names end

    local filtered = {}
    for _, name in pairs(names or {}) do
        if name ~= missing then
            filtered[#filtered + 1] = name
        end
    end
    return filtered
end

function ore_missing.on_init()
    if not setting_enabled() then
        storage.the_cave_ore_patch_missing = nil
        return
    end
    ore_missing.get_missing_resource()
end

function ore_missing.on_configuration_changed()
    if not setting_enabled() then
        storage.the_cave_ore_patch_missing = nil
        return
    end
    ore_missing.get_missing_resource()
end

local function announce_to_player(player)
    if not (player and player.valid) then return end
    if not setting_enabled() then return end

    -- Force the resource to be chosen/stored, but do not reveal which one.
    ore_missing.get_missing_resource()

    local s = state()
    s.announced_players = s.announced_players or {}
    if s.announced_players[player.index] then return end
    s.announced_players[player.index] = true

    player.print({ "the-cave-runtime.ore-missing-enabled" })
end

function ore_missing.on_player_created(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    announce_to_player(player)
end

function ore_missing.on_player_joined_game(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    announce_to_player(player)
end

return ore_missing
