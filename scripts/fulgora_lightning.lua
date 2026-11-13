local physical = require("scripts.player_physical")
-- The Cave: localized Fulgora lightning for Everything on Nauvis.
--
-- The planet-style regions all share a Nauvis/cave surface, so the engine
-- cannot use Fulgora's planet-wide lightning_properties without also striking
-- every other region. This runtime storm only executes lightning near players
-- who are physically inside The Cave's Fulgora wedge.
local hash = require("scripts.lib.hash")
local region_features = require("scripts.region_features")
local cave_worlds = require("scripts.cave_worlds")

local fulgora_lightning = {}

local LIGHTNING_NAME = "lightning"
local UPDATE_INTERVAL = 120       -- one visible storm attempt every 2 seconds
local STORM_CELL_SIZE = 128       -- nearby multiplayer players share one storm
local MIN_STRIKE_DISTANCE = 8
local MAX_STRIKE_DISTANCE = 36
local REGION_SAFETY_MARGIN = 12   -- Fulgora's vanilla target search radius is 10
local MAX_TILE_CANDIDATES = 384
local STREAM_BASE = 3210
local WARNING_SPRITE = "utility/lightning_warning_icon"
local WARNING_SCALE = 0.55
local WARNING_OFFSET = { 0, 0.65 }

-- Vanilla Space Age protection radii at normal quality. Quality increases
-- lightning-attractor reach by 30% per quality level; legendary quality uses
-- level 5, matching the vanilla 37.5-tile rod and 62.5-tile collector ranges.
local ATTRACTOR_BASE_RANGES = {
    ["lightning-rod"] = 15,
    ["lightning-collector"] = 25,
    ["fulgoran-ruin-attractor"] = 20
}
local MAX_ATTRACTOR_SEARCH_RADIUS = 64
local PROTECTION_EDGE_TOLERANCE = 0.25
local logged_surface_errors = {}

local function is_cave_world_surface(surface)
    return cave_worlds.is_cave_world(surface)
end

local function lightning_is_available()
    return script
        and script.active_mods
        and script.active_mods["space-age"] ~= nil
        and prototypes
        and prototypes.entity
        and prototypes.entity[LIGHTNING_NAME] ~= nil
end

local function safely_inside_fulgora(x, y)
    local r = region_features.region_at
    return r(x, y) == "fulgora"
        and r(x - REGION_SAFETY_MARGIN, y) == "fulgora"
        and r(x + REGION_SAFETY_MARGIN, y) == "fulgora"
        and r(x, y - REGION_SAFETY_MARGIN) == "fulgora"
        and r(x, y + REGION_SAFETY_MARGIN) == "fulgora"
end

local function is_open_strike_tile(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not (tile and tile.valid) then return false end
    if tile.name == "out-of-map" then return false end

    -- Never let a random storm directly remove the entity used as The Cave's mineable frontier. Player structures and lightning attractors are
    -- intentionally left eligible, matching the danger/reward of Fulgora.
    local frontier = surface.find_entities_filtered {
        area = { { x - 1, y - 1 }, { x + 2, y + 2 } },
        name = "diggy-rock"
    }
    return not frontier or #frontier == 0
end


local function warning_store()
    storage.the_cave_fulgora_lightning_warning_renders =
        storage.the_cave_fulgora_lightning_warning_renders or {}
    return storage.the_cave_fulgora_lightning_warning_renders
end

local function destroy_warning(player_index)
    local store = warning_store()
    local id = store[player_index]
    if id then
        local object = rendering.get_object_by_id(id)
        if object then object.destroy() end
        store[player_index] = nil
    end
end

local function player_is_in_fulgora(player)
    if not (player and player.valid and player.connected and physical.character_context(player)) then return false end
    local surface = physical.surface(player)
    local position = physical.position(player)
    return is_cave_world_surface(surface)
        and region_features.region_at(math.floor(position.x), math.floor(position.y)) == "fulgora"
end

local function quality_range_multiplier(entity)
    local quality = entity and entity.quality
    local level = quality and quality.level or 0
    return 1 + (0.3 * level)
end

-- The engine's planet-wide warning icon cannot be used on The Cave's shared
-- Nauvis surface, so mirror the relevant vanilla safety rule here: a player is
-- safe while inside the quality-scaled protection radius of a Lightning Rod,
-- Lightning Collector, or the natural Fulgoran ruin attractor.
local function player_is_under_lightning_protection(player)
    local surface = physical.surface(player)
    local position = physical.position(player)
    local attractors = surface.find_entities_filtered {
        position = position,
        radius = MAX_ATTRACTOR_SEARCH_RADIUS,
        type = "lightning-attractor"
    }

    for _, attractor in ipairs(attractors) do
        if attractor.valid then
            local base_range = ATTRACTOR_BASE_RANGES[attractor.name]
            if base_range then
                local radius = base_range * quality_range_multiplier(attractor)
                    + PROTECTION_EDGE_TOLERANCE
                local dx = position.x - attractor.position.x
                local dy = position.y - attractor.position.y
                if (dx * dx + dy * dy) <= (radius * radius) then
                    return true
                end
            end
        end
    end

    return false
end

-- The engine lightning warning belongs to the entire planet prototype and
-- cannot distinguish The Cave's coordinate-based regions on one shared Nauvis
-- surface. data-final-fixes.lua hides that global icon; this replaces it with
-- the same vanilla utility sprite only while each player is inside Fulgora.
function fulgora_lightning.sync_warning_icons()
    local store = warning_store()
    local connected = {}

    for _, player in ipairs(game.connected_players) do
        connected[player.index] = true
        local target = player.character
        local should_show = lightning_is_available()
            and player_is_in_fulgora(player)
            and not player_is_under_lightning_protection(player)
            and target
            and target.valid

        local id = store[player.index]
        local object = id and rendering.get_object_by_id(id) or nil

        if should_show then
            if not object then
                local created = rendering.draw_sprite {
                    sprite = WARNING_SPRITE,
                    surface = physical.surface(player),
                    target = {
                        type = "entity",
                        entity = target,
                        offset = WARNING_OFFSET
                    },
                    x_scale = WARNING_SCALE,
                    y_scale = WARNING_SCALE,
                    blink_interval = 30,
                    render_layer = "arrow"
                }
                if created then store[player.index] = created.id end
            end
        elseif id then
            destroy_warning(player.index)
        end
    end

    -- Disconnected players do not need a persistent world marker. This also
    -- removes stale IDs after character death, surface changes or old saves.
    local stale_players = {}
    for player_index in pairs(store) do
        if not connected[player_index] then
            stale_players[#stale_players + 1] = player_index
        end
    end
    for _, player_index in ipairs(stale_players) do
        destroy_warning(player_index)
    end
end

local function execute_one_strike(surface, anchor, cell_x, cell_y, tick)
    local seed = (surface.map_gen_settings and surface.map_gen_settings.seed) or 0
    local cycle = math.floor(tick / UPDATE_INTERVAL)

    -- The Cave is mostly narrow tunnels and carved rooms. Random coordinates
    -- inside a large circle would usually land on out-of-map cave void, so ask
    -- the engine for a bounded set of real open tiles first and then choose a
    -- deterministic starting point inside that set.
    local candidates = surface.find_tiles_filtered {
        position = anchor,
        radius = MAX_STRIKE_DISTANCE,
        name = "out-of-map",
        invert = true,
        limit = MAX_TILE_CANDIDATES
    }
    if not candidates or #candidates == 0 then return false end

    local start_index = hash.range(
        seed,
        cell_x + cycle * 31,
        cell_y - cycle * 17,
        STREAM_BASE,
        1,
        #candidates
    )

    for offset = 0, #candidates - 1 do
        local tile = candidates[((start_index + offset - 1) % #candidates) + 1]
        local x = math.floor(tile.position.x)
        local y = math.floor(tile.position.y)
        local dx = (x + 0.5) - anchor.x
        local dy = (y + 0.5) - anchor.y
        local distance_squared = dx * dx + dy * dy

        if distance_squared >= MIN_STRIKE_DISTANCE * MIN_STRIKE_DISTANCE
            and safely_inside_fulgora(x, y)
            and is_open_strike_tile(surface, x, y)
        then
            local ok, err = pcall(function()
                surface.execute_lightning {
                    name = LIGHTNING_NAME,
                    position = { x + 0.5, y + 0.5 }
                }
            end)
            if not ok and not logged_surface_errors[surface.index] then
                logged_surface_errors[surface.index] = true
                log("[The Cave] Fulgora lightning could not execute on surface '"
                    .. tostring(surface.name) .. "': " .. tostring(err))
            end
            return ok
        end
    end

    return false
end

function fulgora_lightning.on_nth_tick(event)
    if not lightning_is_available() then return end

    local occupied_cells = {}
    local ordered_cells = {}

    for _, player in ipairs(game.connected_players) do
        if player.valid and player.connected then
            local surface = physical.surface(player)
            local position = physical.position(player)
            if player_is_in_fulgora(player) then
                local cell_x = math.floor(position.x / STORM_CELL_SIZE)
                local cell_y = math.floor(position.y / STORM_CELL_SIZE)
                local key = surface.index .. ":" .. cell_x .. ":" .. cell_y

                if not occupied_cells[key] then
                    local cell = {
                        surface = surface,
                        anchor = { x = position.x, y = position.y },
                        cell_x = cell_x,
                        cell_y = cell_y
                    }
                    occupied_cells[key] = cell
                    ordered_cells[#ordered_cells + 1] = cell
                end
            end
        end
    end

    for _, cell in ipairs(ordered_cells) do
        execute_one_strike(
            cell.surface,
            cell.anchor,
            cell.cell_x,
            cell.cell_y,
            event.tick
        )
    end
end

return fulgora_lightning
