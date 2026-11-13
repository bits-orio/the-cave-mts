local cave_worlds = require("scripts.cave_worlds")
local world = require("scripts.world")
local mirror = require("scripts.lib.mirror")

local events = {}
local hooks = {}

function events.configure(callbacks)
    hooks = callbacks or {}
end

local function register_copy(surface)
    local row, added = cave_worlds.register_copy(surface)
    if not added then return row, false end
    -- A recycled index must not inherit generated chunks or old tile mirrors.
    world.forget_surface_chunks(surface)
    mirror.drop_surface(surface.index)
    if storage.train_wave_team_chunk_verification then
        storage.train_wave_team_chunk_verification[surface.index] = nil
    end
    if storage.the_cave_starter_oil then
        storage.the_cave_starter_oil[surface.index] = nil
    end
    if hooks.on_copy_registered then hooks.on_copy_registered(surface) end
    return row, true
end

local function whole_chunk_area(event)
    local source = event.source_area
    local destination = event.destination_area
    if not (source and destination) then return nil end
    local lt, rb = source.left_top, source.right_bottom
    local dlt, drb = destination.left_top, destination.right_bottom
    if not (lt and rb and dlt and drb) then return nil end
    if lt.x ~= dlt.x or lt.y ~= dlt.y or rb.x ~= drb.x or rb.y ~= drb.y then return nil end
    if rb.x <= lt.x or rb.y <= lt.y then return nil end
    if lt.x % 32 ~= 0 or lt.y % 32 ~= 0 or rb.x % 32 ~= 0 or rb.y % 32 ~= 0 then return nil end
    return lt, rb
end

function events.on_area_cloned(event)
    local source, destination = event.source_surface, event.destination_surface
    if not (source and source.valid and destination and destination.valid) then return end
    if source.index == destination.index or not cave_worlds.is_cave_world(source) then return end
    if destination.name == "nauvis" or destination.name:find("^the%-cave%-") then return end
    if event.clone_tiles ~= true or event.clone_entities ~= true then return end
    local lt, rb = whole_chunk_area(event)
    if not lt then return end

    if cave_worlds.is_original(source) then
        local row = cave_worlds.get(source)
        if source.name == "nauvis" and row and row.provisional_owner then
            -- Unknown-name copies in an old save are discovered on their next
            -- clone. Its migration fallback must not turn an empty template
            -- into a permanently owned world before that clone arrives.
            local actual_owner = hooks.resolve_owner and hooks.resolve_owner(source)
            if actual_owner then cave_worlds.set_owner(source, actual_owner)
            else row.owner_force_index = nil end
            row.provisional_owner = nil
        end
        local repaired = false
        for y = lt.y / 32, rb.y / 32 - 1 do
            for x = lt.x / 32, rb.x / 32 - 1 do
                local position = { x = x, y = y }
                if not world.is_chunk_built(source, position) then
                    local area = { left_top = { x = x * 32, y = y * 32 },
                        right_bottom = { x = (x + 1) * 32, y = (y + 1) * 32 } }
                    world.ensure_built_chunk(source, position, area)
                    -- A copier can run before our on_chunk_generated handler.
                    -- Build abandoned train parts too before copying the chunk again.
                    if hooks.on_source_chunk_generated then
                        hooks.on_source_chunk_generated {
                            surface = source, position = position, area = area,
                            tick = event.tick, name = defines.events.on_chunk_generated,
                        }
                    end
                    source.clone_area {
                        source_area = area, destination_area = area,
                        destination_surface = destination, destination_force = event.destination_force,
                        clone_tiles = event.clone_tiles, clone_entities = event.clone_entities,
                        clone_decoratives = event.clone_decoratives,
                        clear_destination_entities = event.clear_destination_entities,
                        clear_destination_decoratives = event.clear_destination_decoratives,
                    }
                    repaired = true
                end
            end
        end
        -- The corrective clone raises this event again after the source is built.
        if repaired then return end
        if not cave_worlds.owner_force(source) then cave_worlds.mark_template(source) end
    end

    local row, added = register_copy(destination)
    if added and row and source.map_gen_settings.seed ~= destination.map_gen_settings.seed then
        log("[The Cave] cave copy " .. destination.name .. " has a different seed from " .. source.name
            .. "; new digging uses the copy's seed")
    end
end

function events.on_init()
    cave_worlds.ensure_original(game.surfaces.nauvis)
end

function events.on_surface_deleted(event)
    -- The global deletion fan-out also checks for a live replacement surface.
    cave_worlds.drop_surface(event.surface_index)
    if not game.surfaces[event.surface_index] and storage.the_cave_starter_oil then
        storage.the_cave_starter_oil[event.surface_index] = nil
    end
end

function events.on_configuration_changed()
    if storage.the_cave_worlds_migration_version == 1 then return nil end
    local result = { legacy_copies = 0, owned_original_conflict = false }
    for _, surface in pairs(game.surfaces) do
        if cave_worlds.is_original(surface) then
            cave_worlds.ensure_original(surface)
        -- Legacy 3.3.1 recognition only; remove after its upgrade window.
        elseif surface.name:find("^team%-%d+%-nauvis$") then
            register_copy(surface)
            result.legacy_copies = result.legacy_copies + 1
        end
    end
    for _, surface in pairs(game.surfaces) do
        if cave_worlds.is_cave_world(surface) and hooks.resolve_owner then
            local owner = hooks.resolve_owner(surface)
            if owner then cave_worlds.set_owner(surface, owner) end
        end
    end
    local nauvis = game.surfaces.nauvis
    if nauvis then
        if result.legacy_copies > 0 then
            if cave_worlds.owner_force(nauvis) then
                result.owned_original_conflict = true
                log("[The Cave] legacy cave copies coexist with an owned nauvis; preserving its owner and base")
            else
                cave_worlds.mark_template(nauvis)
            end
        elseif not cave_worlds.is_template(nauvis) then
            if not cave_worlds.owner_force(nauvis) then
                local row = cave_worlds.set_owner(nauvis, game.forces.player)
                if row then row.provisional_owner = true end
            end
        end
    end
    storage.the_cave_worlds_migration_version = 1
    return result
end

return events
