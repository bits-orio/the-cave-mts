local settings = require("scripts.game_settings").proxy(settings)

local advancing_zones = require("scripts.advancing_zones")
local cave_worlds = require("scripts.cave_worlds")
local cave_teams = require("scripts.cave_teams")

local function the_cave_startup_enabled(name, default_enabled)
    local setting = settings.startup[name]
    if not setting then return default_enabled ~= false end
    return setting.value == "enabled" or setting.value == true
end

local function the_cave_space_age_enabled()
    if advancing_zones.is_active() then return advancing_zones.space_age_available() end
    if not the_cave_startup_enabled("the-cave-everything-on-nauvis", true) then return false end
    return script and script.active_mods and script.active_mods["space-age"] ~= nil
end

local function tc_region_for_normal_resources(x, y)
    if advancing_zones.is_active() then return advancing_zones.region_at(x, y) end
    -- Without Space Age, normal resources remain available everywhere.
    if not the_cave_space_age_enabled() then return "nauvis" end

    local ax, ay = math.abs(x), math.abs(y)
    if x * x + y * y < 1000 * 1000 then return "nauvis" end
    -- Nauvis ends at the 1000-tile radius. Every position beyond that circle
    -- belongs to the dominant-axis Space Age region; no diagonal Nauvis gaps.
    if ay >= ax then
        return y >= 0 and "gleba" or "aquilo"
    end
    return x < 0 and "vulcanus" or "fulgora"
end

-- Ore veins materialize at dig time (ADR 0004): when a cover entity dies, the
-- tile's vein membership is computed from simplex noise seeded by the surface's
-- map seed — deterministic, so re-digging a collapsed area or comparing MTS
-- team worlds always yields identical veins. Veins never exist until dug.
local Simplex = require("scripts.lib.simplex")
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local ore_missing = require("scripts.ore_missing")
local bob_ore_layout = require("scripts.bob_ore_layout")

local ore_veins = {}

-- Hash stream ids (keep unique across all dig modules).
local S_OIL_WELL = 90
local S_PATCH_RESOURCE = 91
local S_PATCH_AMOUNT = 92
local S_PATCH_PRESET = 93
local S_OIL_AMOUNT = 95
local S_OIL_FIELD_CENTER_X = 96
local S_OIL_FIELD_CENTER_Y = 97
local S_OIL_WELL_COUNT = 98
local S_OIL_WELL_YIELD = 99
local S_OIL_FIELD_TRIGGER = 100
local S_STARTER_OIL_DIRECTION = 101
local S_STARTER_OIL_DISTANCE = 102

local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value
local TENDRIL_SCALE = 1 / 40
local CHUNK_SIZE = 32
local RESOURCE_GAP_CHUNKS = 3
local SPECIAL_GAP_CHUNKS = 5
local OIL_GAP_CHUNKS = 4 -- regular oil wells use practical 4-chunk spacing for playable exploration
local STARTER_OIL_MIN_DISTANCE = 80
local STARTER_OIL_MAX_DISTANCE = 100
local STARTER_OIL_TRIGGER_RADIUS = 6
local STARTER_OIL_EXISTING_RADIUS = 120

local function mixed_enabled()
    return the_cave_startup_enabled("the-cave-mixed-resource-patches", true)
end

local RESOURCE_SIZE_MULTIPLIERS = {
    ["level-1"] = 1,
    ["level-2"] = 2,
    ["level-3"] = 3,
    ["level-4"] = 4,
    ["level-5"] = 5,
    ["level-6"] = 6,
    ["level-7"] = 7,
    ["level-8"] = 8,

    -- Backward compatibility for saves/configs created before the 8-level system.
    small = 1,
    medium = 2,
    large = 4,
    huge = 8,
}

local function resource_patch_size_setting()
    local setting = settings.startup["the-cave-resource-patch-size"]
    return setting and setting.value or "level-2"
end

local function digging_mode_value()
    local setting = settings.startup["the-cave-digging-mode"]
    return setting and setting.value or "disabled"
end

local function digging_mode_enabled()
    return digging_mode_value() ~= "disabled"
end

local function resource_patch_size_multiplier()
    local value = resource_patch_size_setting()
    return RESOURCE_SIZE_MULTIPLIERS[value] or RESOURCE_SIZE_MULTIPLIERS["level-2"]
end

local function cell_key(tile_x, tile_y, gap_chunks)
    local size = gap_chunks * CHUNK_SIZE
    return math.floor(tile_x / size), math.floor(tile_y / size)
end

local function discovery_store()
    storage.the_cave_discovered_resource_patches = storage.the_cave_discovered_resource_patches or {}
    return storage.the_cave_discovered_resource_patches
end

local function discovered_once(surface, key)
    local all = discovery_store()
    local by_surface = all[surface.index]
    if not by_surface then
        by_surface = {}
        all[surface.index] = by_surface
    end
    if by_surface[key] then return false end
    by_surface[key] = true
    return true
end

local function spawned_oil_store()
    storage.the_cave_spawned_oil_fields = storage.the_cave_spawned_oil_fields or {}
    return storage.the_cave_spawned_oil_fields
end

local function mark_oil_field_spawned(surface, key)
    local all = spawned_oil_store()
    local by_surface = all[surface.index]
    if not by_surface then
        by_surface = {}
        all[surface.index] = by_surface
    end
    if by_surface[key] then return false end
    by_surface[key] = true
    return true
end

local function player_prefix(player_index)
    if player_index then
        local player = game.get_player(player_index)
        if player and player.valid then return player.name end
    end
    return nil
end

local function announce(force, player_index, discovery_message)
    if not force then return end
    local name = player_prefix(player_index)
    if name then
        force.print({ "the-cave-runtime.resource-discovered-by-player", name, discovery_message })
    else
        force.print({ "the-cave-runtime.resource-discovered", discovery_message })
    end
end

local RESOURCE_LABELS = {
    ["iron-ore"] = { "the-cave-runtime.resource-iron-vein" },
    ["copper-ore"] = { "the-cave-runtime.resource-copper-vein" },
    ["coal"] = { "the-cave-runtime.resource-coal-vein" },
    ["stone"] = { "the-cave-runtime.resource-stone-deposit" },
}

local MIXED_PRESETS = {
    -- Stable long-run distribution for newly generated mixed patches.
    { { "iron-ore", 35 }, { "copper-ore", 27 }, { "coal", 25 }, { "stone", 13 } },
}

local MIXED_TILE_AMOUNTS = {
    easy = { min = 250, max = 625 },
    medium = { min = 625, max = 875 },
    hard = { min = 875, max = 1250 },
    nightmare = { min = 1250, max = 2000 },
}

local CLASSIC_TILE_AMOUNTS = {
    easy = { min = 125, max = 375 },
    medium = { min = 375, max = 625 },
    hard = { min = 625, max = 875 },
    nightmare = { min = 875, max = 1250 },
}

local OIL_YIELD = {
    regular_min_percent = 500,
    regular_max_percent = 1000,
}

local function oil_percent_to_amount(percent)
    -- Factorio crude-oil wells are displayed as yield %. Internally the
    -- resource amount maps to roughly 3000 internal amount per percent.
    -- Verified from Factorio editor values: 500% = 1,500,000,
    -- 700% = 2,100,000, 300% = 900,000.
    return percent * 3000
end

local function range_for_level(table_by_level, level_id)
    return table_by_level[level_id] or table_by_level.easy or table_by_level.medium or table_by_level.hard or table_by_level.nightmare
end

local function pick_from_weighted(seed, tile_x, tile_y, stream, weighted)
    local total = 0
    for _, item in pairs(weighted) do total = total + item[2] end
    local roll = hash.roll(seed, tile_x, tile_y, stream) * total
    for _, item in pairs(weighted) do
        roll = roll - item[2]
        if roll <= 0 then return item[1] end
    end
    return weighted[#weighted][1]
end

local function pick_mixed_resource(seed, tile_x, tile_y, cell_x, cell_y)
    local preset_index = hash.range(seed, cell_x, cell_y, S_PATCH_PRESET, 1, #MIXED_PRESETS)
    local preset = ore_missing.filter_weighted(MIXED_PRESETS[preset_index])
    return pick_from_weighted(seed, tile_x, tile_y, S_PATCH_RESOURCE, preset)
end

-- The Cave 2.0.10 Oil Fields.
-- Regular oil is generated only when discovered by player digging. In addition,
-- one deterministic starter target is reserved 80-100 tiles from the initial
-- spawn and materializes only when a player digs close to it. This guarantees
-- early oil progression without revealing a resource icon through unexplored
-- cave rock or changing the regular exploration oil system.
-- Every discovered well uses the same 500%-1000% yield range.
local OIL = {
    min_depth = 0,
    grid_chunks = OIL_GAP_CHUNKS,
    trigger_radius = 4, -- must be close to the hidden field center before wells are created
}


local function oil_grid_key(tile_x, tile_y)
    local size = OIL.grid_chunks * CHUNK_SIZE
    return math.floor(tile_x / size), math.floor(tile_y / size)
end

local function oil_field_center(seed, gx, gy)
    local size = OIL.grid_chunks * CHUNK_SIZE
    local base_x = gx * size + math.floor(size / 2)
    local base_y = gy * size + math.floor(size / 2)
    -- Jitter by up to one chunk so fields do not land on perfectly predictable centers.
    local jitter_x = hash.range(seed, gx, gy, S_OIL_FIELD_CENTER_X, -CHUNK_SIZE, CHUNK_SIZE)
    local jitter_y = hash.range(seed, gx, gy, S_OIL_FIELD_CENTER_Y, -CHUNK_SIZE, CHUNK_SIZE)
    return base_x + jitter_x, base_y + jitter_y
end


local function regular_oil_field_near(seed, tile_x, tile_y)
    local gx, gy = oil_grid_key(tile_x, tile_y)
    local cx, cy = oil_field_center(seed, gx, gy)
    local dx, dy = tile_x - cx, tile_y - cy
    if dx * dx + dy * dy <= OIL.trigger_radius * OIL.trigger_radius then
        return gx, gy, cx, cy
    end
    return nil, nil, nil, nil
end

-- Read-only reservation for Bob solids. A regular well can appear at its
-- hidden centre after neighbouring tiles were opened; leave its footprint and
-- mining clearance free without changing any oil trigger, position or yield.
function ore_veins.is_oil_reserved(surface, tile_x, tile_y)
    local gx, gy = oil_grid_key(tile_x, tile_y)
    local cx, cy = oil_field_center(surface.map_gen_settings.seed or 0, gx, gy)
    if math.abs(tile_x - cx) <= 6 and math.abs(tile_y - cy) <= 6 then return true end
    local starts = storage.the_cave_starter_oil
    local row = starts and starts[surface.index]
    if row and (not row.name or row.name == surface.name) then
        -- The starter well is placed on the discovery tile within six tiles
        -- of its target, rather than necessarily at the target itself. Keep
        -- every force's target reserved when several forces share the cave.
        local targets = row.by_force or { row }
        for _, starter in pairs(targets) do
            if starter.target_x and starter.target_y
                and math.abs(tile_x - starter.target_x) <= 12
                and math.abs(tile_y - starter.target_y) <= 12 then return true end
        end
    end
    return false
end

-- Original shape/noise style retained. The old richness growth is removed.
local CLASSIC_ORES = {
    { name = "iron-ore", seed = 1100, width = 0.055, min_depth = CARVE_RADIUS + 4 },
    { name = "copper-ore", seed = 1200, width = 0.050, min_depth = 40 },
    { name = "coal", seed = 1300, width = 0.050, min_depth = CARVE_RADIUS + 4 },
    { name = "stone", seed = 1400, width = 0.040, min_depth = 40 },
}

local MIXED_SHAPE = { seed = 1100, width = 0.058, min_depth = CARVE_RADIUS + 4 }

local function patch_width()
    -- Resource Level is the sole controller of vein geometry. Depth/zone may
    -- still change the ore amount per tile, but must never widen a patch and
    -- silently turn a low Resource Level into a high one.
    return resource_patch_size_multiplier()
end

local function create_resource(surface, name, x, y, amount)
    if ore_missing.is_missing(name) then return nil end
    return surface.create_entity {
        name = name,
        position = { x, y },
        amount = amount,
    }
end

local function create_oil(surface, x, y, amount)
    local tile = surface.get_tile(math.floor(x), math.floor(y))
    if not tile.valid or tile.name:find("water", 1, true) then return nil end
    local existing = surface.find_entities_filtered {
        area = {{x - 0.1, y - 0.1}, {x + 0.1, y + 0.1}},
        name = "crude-oil"
    }
    if existing and #existing > 0 then return existing[1] end
    return surface.create_entity {
        name = "crude-oil",
        position = { x, y },
        amount = amount,
    }
end


local function create_regular_oil(surface, x, y, seed)
    local percent = hash.range(seed, math.floor(x), math.floor(y), S_OIL_WELL_YIELD,
        OIL_YIELD.regular_min_percent, OIL_YIELD.regular_max_percent)
    return create_oil(surface, x, y, oil_percent_to_amount(percent))
end

local function create_regular_oil_field(surface, seed, gx, gy, cx, cy)
    -- Final oil simplification: each regular discovery creates exactly one
    -- high-yield pumpjack-friendly well. This avoids overlap/spacing issues
    -- and keeps exploration clear and predictable.
    local x, y = cx + 0.5, cy + 0.5
    return create_regular_oil(surface, x, y, seed) ~= nil
end

local STARTER_OIL_DIRECTIONS = {
    { x = 1, y = 0 },
    { x = 0, y = 1 },
    { x = -1, y = 0 },
    { x = 0, y = -1 },
}

local function starter_oil_store()
    storage.the_cave_starter_oil = storage.the_cave_starter_oil or {}
    return storage.the_cave_starter_oil
end

local function starter_oil_targets(surface)
    local store = starter_oil_store()
    local row = store[surface.index]
    if row and not row.by_force then
        -- 3.3.1 only created a target on nauvis for the default player force.
        local legacy = row
        row = { name = surface.name, by_force = {} }
        local force = game.forces.player
        if surface.name == "nauvis" and force then row.by_force[force.index] = legacy end
    elseif not row or row.name ~= surface.name then
        row = { name = surface.name, by_force = {} }
    end
    store[surface.index] = row
    return row.by_force
end

local function starter_oil_candidate_is_hidden(surface, x, y)
    local tile = surface.get_tile(x, y)
    if not tile or not tile.valid then return false end
    if tile.name == "out-of-map" then return true end

    local covers = surface.find_entities_filtered {
        position = { x = x + 0.5, y = y + 0.5 },
        radius = 2,
        name = { "diggy-rock", "diggy-rubble" },
    }
    return covers and #covers > 0
end

local function nearby_crude_oil(surface, position, radius)
    local wells = surface.find_entities_filtered {
        position = position,
        radius = radius,
        name = "crude-oil",
    }
    return wells and wells[1] or nil
end

local function ensure_starter_oil_target(surface, force)
    if not (surface and surface.valid and force and force.valid
        and cave_worlds.is_cave_world(surface) and not cave_worlds.is_template(surface)
        and (surface.name == "nauvis" or cave_worlds.is_copy(surface))
        and cave_teams.is_world_running(surface)) then return nil end
    local home = cave_teams.home_surface(force)
    if not (home and home.index == surface.index) then return nil end

    local targets = starter_oil_targets(surface)
    local record = targets[force.index]
    if record then return record end

    local spawn = force.get_spawn_position(surface)
    local spawn_x = math.floor((spawn.x or 0) + 0.5)
    local spawn_y = math.floor((spawn.y or 0) + 0.5)

    -- Existing saves that already have a nearby well do not receive a duplicate.
    local existing = nearby_crude_oil(surface, { x = spawn_x, y = spawn_y }, STARTER_OIL_EXISTING_RADIUS)
    if existing and existing.valid then
        record = {
            target_x = math.floor(existing.position.x),
            target_y = math.floor(existing.position.y),
            spawned = true,
            position = { x = existing.position.x, y = existing.position.y },
        }
        targets[force.index] = record
        return record
    end

    local seed = surface.map_gen_settings.seed or 0
    local first_direction = hash.range(seed, spawn_x, spawn_y, S_STARTER_OIL_DIRECTION, 1, #STARTER_OIL_DIRECTIONS)
    local first_distance = hash.range(seed, spawn_x, spawn_y, S_STARTER_OIL_DISTANCE,
        STARTER_OIL_MIN_DISTANCE, STARTER_OIL_MAX_DISTANCE)

    local selected_x, selected_y, selected_distance
    local distance_offsets = { 0, 5, -5, 10, -10, 15, -15, 20, -20 }
    for direction_offset = 0, #STARTER_OIL_DIRECTIONS - 1 do
        local direction_index = ((first_direction - 1 + direction_offset) % #STARTER_OIL_DIRECTIONS) + 1
        local direction = STARTER_OIL_DIRECTIONS[direction_index]
        for _, offset in ipairs(distance_offsets) do
            local distance = first_distance + offset
            if distance >= STARTER_OIL_MIN_DISTANCE and distance <= STARTER_OIL_MAX_DISTANCE then
                local x = spawn_x + direction.x * distance
                local y = spawn_y + direction.y * distance
                if starter_oil_candidate_is_hidden(surface, x, y) then
                    selected_x, selected_y, selected_distance = x, y, distance
                    break
                end
            end
        end
        if selected_x then break end
    end

    -- New maps normally select an out-of-map/frontier tile above. This fallback
    -- keeps the target deterministic if another scenario has already opened the
    -- whole 80-100 tile ring before The Cave is installed.
    if not selected_x then
        local direction = STARTER_OIL_DIRECTIONS[first_direction]
        selected_distance = first_distance
        selected_x = spawn_x + direction.x * selected_distance
        selected_y = spawn_y + direction.y * selected_distance
    end

    record = {
        target_x = selected_x,
        target_y = selected_y,
        spawned = false,
        distance = selected_distance,
        spawn_x = spawn_x,
        spawn_y = spawn_y,
    }
    targets[force.index] = record
    return record
end

local function try_spawn_starter_oil(surface, tile_x, tile_y, force, player_index, seed, suppress_discovery)
    local record = ensure_starter_oil_target(surface, force)
    if not record or record.spawned then return false end

    local dx = tile_x - record.target_x
    local dy = tile_y - record.target_y
    if dx * dx + dy * dy > STARTER_OIL_TRIGGER_RADIUS * STARTER_OIL_TRIGGER_RADIUS then
        return false
    end

    -- The trigger is deliberately wider than the final placement ring so a
    -- nearby tunnel can discover the target. The actual well still appears
    -- only on a dug tile whose distance from spawn remains inside 80-100.
    local spawn_dx = tile_x - (record.spawn_x or 0)
    local spawn_dy = tile_y - (record.spawn_y or 0)
    local spawn_distance_sq = spawn_dx * spawn_dx + spawn_dy * spawn_dy
    if spawn_distance_sq < STARTER_OIL_MIN_DISTANCE * STARTER_OIL_MIN_DISTANCE
        or spawn_distance_sq > STARTER_OIL_MAX_DISTANCE * STARTER_OIL_MAX_DISTANCE then
        return false
    end

    -- If a normal field happened to appear in the same small area first, count
    -- it as the guaranteed starter supply instead of creating a duplicate.
    local existing = nearby_crude_oil(surface, { x = tile_x + 0.5, y = tile_y + 0.5 }, 12)
    if existing and existing.valid then
        record.spawned = true
        record.position = { x = existing.position.x, y = existing.position.y }
        return true
    end

    local created = create_regular_oil(surface, tile_x + 0.5, tile_y + 0.5, seed)
    if not (created and created.valid) then return false end

    record.spawned = true
    record.position = { x = created.position.x, y = created.position.y }

    -- Reserve the regular oil grid cell too, preventing two wells from being
    -- created by the same discovery dig.
    local gx, gy = oil_grid_key(tile_x, tile_y)
    mark_oil_field_spawned(surface, "oil:" .. gx .. ":" .. gy)
    if not suppress_discovery then
        announce(force, player_index, { "the-cave-runtime.resource-oil-field" })
    end
    return true
end

-- Materialize the vein (if any) at a tile — used for manual digs and for
-- cavern-carved tiles alike. `force` (optional) receives the discovery notice.
function ore_veins.materialize(surface, tile_x, tile_y, force, player_index, suppress_discovery)
    if surface and surface.valid and type(surface.name) == "string"
        and (surface.name:find("^the%-cave%-uranium%-cave%-")
            or surface.name:find("^the%-cave%-mineral%-cave%-")) then
        -- Timed extraction-cave resources are owned exclusively by their
        -- dedicated runtime modules.
        return
    end
    -- Central region gate: no caller (manual dig, cavern, frontier or future
    -- feature) may leak Nauvis resources beyond the 1000-tile Nauvis region.
    if tc_region_for_normal_resources(tile_x, tile_y) ~= "nauvis" then return end

    local x, y = tile_x + 0.5, tile_y + 0.5

    local tile = surface.get_tile(tile_x, tile_y)
    if not tile.valid or tile.name:find("water", 1, true) then
        return
    end

    local distance = math.sqrt(x * x + y * y)
    local level = depth_levels.level_for_distance(distance)
    local level_id = level.id
    local seed = surface.map_gen_settings.seed

    -- Oil is independent from Mixed/Classic ore mode. It is enabled in all
    -- zones because oil is required for research progression. There is no
    -- separate starter oil path anymore; every oil discovery uses the same
    -- single-well 500%-1000% regular oil logic.
    -- IMPORTANT: Oil entities are created only from player-triggered digging
    -- (force is present). Cavern/autocarve materialization must not spawn oil
    -- ahead of the player, otherwise smoke/resource icons can leak through the
    -- black unexplored cave.
    if force then
        local starter_created = try_spawn_starter_oil(
            surface, tile_x, tile_y, force, player_index, seed, suppress_discovery
        )
        if not starter_created then
            local oil_cell_x, oil_cell_y, oil_center_x, oil_center_y = regular_oil_field_near(seed, tile_x, tile_y)
            if oil_cell_x then
                local key = "oil:" .. oil_cell_x .. ":" .. oil_cell_y
                if mark_oil_field_spawned(surface, key) then
                    local created = create_regular_oil_field(surface, seed, oil_cell_x, oil_cell_y, oil_center_x, oil_center_y)
                    if created then
                        if discovered_once(surface, key) and not suppress_discovery then
                            announce(force, player_index, { "the-cave-runtime.resource-oil-field" })
                        end
                    end
                end
                -- Oil is independent from ore. Do not return here: oil discovery
                -- must never block iron/copper/coal/stone vein materialization.
            end
        end
    end

    -- Digging Mode: no generated ore, uranium, mixed, or classic resource patches.
    -- Oil remains active above, and rock digging rewards are controlled by the
    -- Digging Mode setting in scripts/dig_yield.lua. Tiny starter patches are
    -- created near spawn by on_init only to protect progression unlocks.
    if digging_mode_enabled() then
        return
    end

    -- Reserve pure Bob deposits and their five-tile empty border before either
    -- side is dug. Oil above remains independent; Bob absent/disabled is inert.
    if bob_ore_layout.is_reserved(surface, tile_x, tile_y) then return end

    -- Surface uranium generation is intentionally disabled. Existing patches in
    -- old saves remain untouched; all future uranium is generated only inside
    -- finite Uranium Caves.

    local resource_cell_x, resource_cell_y = cell_key(tile_x, tile_y, RESOURCE_GAP_CHUNKS)

    if mixed_enabled() then
        local noise = Simplex.d2(x * TENDRIL_SCALE, y * TENDRIL_SCALE, seed + MIXED_SHAPE.seed)
        if distance > MIXED_SHAPE.min_depth and math.abs(noise) < MIXED_SHAPE.width * patch_width() then
            local ore_name = pick_mixed_resource(seed, tile_x, tile_y, resource_cell_x, resource_cell_y)
            local range = range_for_level(MIXED_TILE_AMOUNTS, level_id)
            local amount = hash.range(seed, tile_x, tile_y, S_PATCH_AMOUNT, range.min, range.max)
            local created = create_resource(surface, ore_name, x, y, amount)
            if created and force then
                local key = "mixed:" .. resource_cell_x .. ":" .. resource_cell_y
                if discovered_once(surface, key) and not suppress_discovery then
                    announce(force, player_index, { "the-cave-runtime.resource-mixed-patch" })
                end
            end
            return
        end
    else
        for _, ore in pairs(CLASSIC_ORES) do
            if not ore_missing.is_missing(ore.name) and distance > ore.min_depth then
                local noise = Simplex.d2(x * TENDRIL_SCALE, y * TENDRIL_SCALE, seed + ore.seed)
                if math.abs(noise) < ore.width * patch_width() then
                    local range = range_for_level(CLASSIC_TILE_AMOUNTS, level_id)
                    local amount = hash.range(seed, tile_x, tile_y, S_PATCH_AMOUNT, range.min, range.max)
                    local created = create_resource(surface, ore.name, x, y, amount)
                    if created and force then
                        local key = "classic:" .. ore.name .. ":" .. resource_cell_x .. ":" .. resource_cell_y
                        if discovered_once(surface, key) and not suppress_discovery then
                            announce(force, player_index, RESOURCE_LABELS[ore.name] or { "the-cave-runtime.resource-generic-vein" })
                        end
                    end
                    return
                end
            end
        end
    end
end


local STARTER_PATCHES = {
    { name = "iron-ore", center = { x = -8, y = 0 }, amount = 1200 },
    { name = "copper-ore", center = { x = 8, y = 0 }, amount = 1200 },
    { name = "coal", center = { x = 0, y = -8 }, amount = 1200 },
    { name = "stone", center = { x = 0, y = 8 }, amount = 1200 },
}

local function can_place_starter_resource(surface, name, x, y)
    if not surface or not surface.valid then return false end

    -- Factorio 2.0 does not expose a generic "water-tile" collision layer for LuaTile:collides_with().
    -- Keep this check simple and stable: avoid placing starter ore on obvious fluid/unsafe tiles.
    local tile = surface.get_tile(x, y)
    if not tile or not tile.valid then return false end

    local tile_name = tile.name or ""
    if string.find(tile_name, "water", 1, true) or string.find(tile_name, "lava", 1, true) then
        return false
    end

    if surface.find_entity(name, { x, y }) then return false end
    return true
end

local function create_starter_patch(surface, patch)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local x = patch.center.x + dx
            local y = patch.center.y + dy
            if can_place_starter_resource(surface, patch.name, x, y) then
                surface.create_entity {
                    name = patch.name,
                    position = { x = x, y = y },
                    amount = patch.amount,
                }
            end
        end
    end
end

function ore_veins.on_init()
    local surface = game.surfaces["nauvis"]
    if not surface then return end

    if not digging_mode_enabled() then return end
    storage.the_cave_digging_mode_starter_patches = storage.the_cave_digging_mode_starter_patches or {}
    if storage.the_cave_digging_mode_starter_patches.created then return end
    for _, patch in pairs(STARTER_PATCHES) do
        if not ore_missing.is_missing(patch.name) then
            create_starter_patch(surface, patch)
        end
    end
    storage.the_cave_digging_mode_starter_patches.created = true
end

function ore_veins.on_arrival(player)
    if not (player and player.valid) then return end
    local force = player.force
    local surface = cave_teams.home_surface(force)
    if surface then ensure_starter_oil_target(surface, force) end
end

function ore_veins.clear_force(force_index)
    for _, row in pairs(storage.the_cave_starter_oil or {}) do
        if row.by_force then row.by_force[force_index] = nil end
    end
end

function ore_veins.on_surface_deleted(event)
    if storage.the_cave_starter_oil then
        storage.the_cave_starter_oil[event.surface_index] = nil
    end
    if storage.the_cave_discovered_resource_patches then
        storage.the_cave_discovered_resource_patches[event.surface_index] = nil
    end
    if storage.the_cave_spawned_oil_fields then
        storage.the_cave_spawned_oil_fields[event.surface_index] = nil
    end
end

function ore_veins.on_dig(dig)
    -- The Cave 1.5.7: normal Nauvis ore_veins only in center region.
    if dig and dig.position and tc_region_for_normal_resources(dig.position.x, dig.position.y) ~= "nauvis" then return end
    ore_veins.materialize(
        dig.surface,
        math.floor(dig.position.x),
        math.floor(dig.position.y),
        dig.force,
        dig.player_index,
        dig.suppress_discovery_messages == true
    )
end

return ore_veins
