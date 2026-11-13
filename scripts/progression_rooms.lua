-- Campaign-wide starter-room quota shared by normal Cave regions and
-- Advancing Collapse. Only successful content placement commits a chance.
local game_settings = require("scripts.game_settings")
local zones = require("scripts.advancing_zones")
local cave_teams = require("scripts.cave_teams")
local cave_worlds = require("scripts.cave_worlds")

local progression = { limit = 3 }
local FAMILIES = { vulcanus = true, gleba = true, fulgora = true, aquilo = true }
local LEGACY_MIN_WIDTH = { vulcanus = 50, gleba = 32, fulgora = 38, aquilo = 34 }

local function playable_force(force)
    return force and force.valid and force.name ~= "enemy" and force.name ~= "neutral"
end

local function root()
    storage.the_cave_progression_rooms = storage.the_cave_progression_rooms
        or { by_force = {}, legacy_migrated = false }
    return storage.the_cave_progression_rooms
end

local function force_state(force)
    local state = root()
    state.by_force[force.index] = state.by_force[force.index] or { counts = {}, sites = {} }
    return state.by_force[force.index]
end

local function site_key(surface, plan)
    return tostring(surface.index) .. ":" .. tostring(plan.cx) .. ":" .. tostring(plan.cy)
end

function progression.enabled()
    if not (script and script.active_mods and script.active_mods["space-age"]) then return false end
    return zones.is_active() or game_settings.enabled("the-cave-everything-on-nauvis", true)
end

function progression.manages(surface)
    if not (surface and surface.valid and progression.enabled()) then return false end
    if zones.is_main_surface(surface) then return true end
    -- Normal Cave warp worlds share the same campaign; changing worlds cannot
    -- replenish a team's planetary quota. Timed caves/interiors stay excluded.
    return not zones.is_active() and type(surface.name) == "string"
        and surface.name:find("^the%-cave%-warp%-") ~= nil
end

function progression.count(force, family)
    if not (playable_force(force) and FAMILIES[family]) then return 0 end
    local state = root().by_force[force.index]
    return state and math.min(progression.limit, state.counts[family] or 0) or 0
end

function progression.can_create(surface, force, family)
    return progression.manages(surface) and playable_force(force) and FAMILIES[family] == true
        and progression.count(force, family) < progression.limit
end

function progression.allowed(surface, force, family)
    return not progression.manages(surface) or progression.can_create(surface, force, family)
end

function progression.complete(surface, force, family, plan)
    if not (plan and type(plan.cx) == "number" and type(plan.cy) == "number"
        and progression.can_create(surface, force, family)) then return nil end
    local state = force_state(force)
    local key = site_key(surface, plan)
    if state.sites[key] then return nil end
    local count = progression.count(force, family) + 1
    state.counts[family] = count
    state.sites[key] = family
    return count
end

function progression.on_init()
    root().legacy_migrated = true
end

local function legacy_family(record)
    if record.progression_failed then return nil end
    if FAMILIES[record.progression_family] then return record.progression_family end
    if record.progression_checked then return nil end
    local family = record.region
    local minimum = LEGACY_MIN_WIDTH[family]
    if not (minimum and record.shape == "square" and record.x1 and record.x2
        and record.y1 and record.y2 and record.cx and record.cy) then return nil end
    local width, height = record.x2 - record.x1, record.y2 - record.y1
    -- Legacy normal/special/entrance rooms top out below these family-specific
    -- starter sizes. The permanent registry survives mining their contents.
    if width == height and width >= minimum then return family end
    return nil
end

function progression.on_configuration_changed()
    local state = root()
    if state.legacy_migrated or not progression.enabled() then return end

    -- Preserve quotas if a save passed through the earlier AC-only trial.
    local old = storage.the_cave_advancing_progression
    for force_index, saved in pairs(old and old.by_force or {}) do
        local force = game.forces[force_index]
        if playable_force(force) then
            local current = force_state(force)
            for family in pairs(FAMILIES) do
                current.counts[family] = math.max(current.counts[family] or 0,
                    math.min(progression.limit, (saved.counts or {})[family] or 0))
            end
            for key, family in pairs(saved.sites or {}) do current.sites[key] = family end
        end
    end

    local recovered = {}
    local explicit_fulgora = {}
    local function credit(force, surface, family, record)
        if not playable_force(force) then return end
        recovered[force.index] = recovered[force.index] or { counts = {}, sites = {} }
        local result = recovered[force.index]
        local key = site_key(surface, record)
        if result.sites[key] or (result.counts[family] or 0) >= progression.limit then return end
        result.sites[key] = family
        result.counts[family] = math.min(progression.limit, (result.counts[family] or 0) + 1)
    end

    -- Read saved footprints, never scan a whole surface or require unmined
    -- trigger entities. Legacy ownership is inferred only from charted rooms.
    for surface_index, records in pairs(storage.cavern_room_footprints or {}) do
        local surface = game.surfaces[surface_index]
        if progression.manages(surface) then
            local owner = cave_worlds.is_active(surface) and cave_teams.owner_force(surface) or nil
            for _, record in ipairs(records) do
                if record.region == "fulgora" and (record.progression_checked
                    or record.progression_failed or record.progression_family == "fulgora") then
                    explicit_fulgora[surface_index] = true
                end
                local family = legacy_family(record)
                if family then
                    local known_force = record.progression_force_index or record.force_index
                    if known_force then
                        credit(game.forces[known_force], surface, family, record)
                    else
                        local chunk = { math.floor(record.cx / 32), math.floor(record.cy / 32) }
                        for _, force in pairs(game.forces) do
                            if playable_force(force) and (not owner or owner.index == force.index)
                                and force.is_chunk_charted(surface, chunk) then
                                credit(force, surface, family, record)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Legacy Fulgora has its own authoritative per-force counter, even before
    -- queued chart requests finish. Prefer it over geometry without ownership;
    -- explicit newer success/failure records must retain their exact counts.
    for key, saved in pairs(storage.the_cave_fulgora_ruin_rooms or {}) do
        local surface_index, force_index = tostring(key):match("^(%d+):(%d+)$")
        surface_index, force_index = tonumber(surface_index), tonumber(force_index)
        local surface = surface_index and game.surfaces[surface_index] or nil
        local force = force_index and game.forces[force_index] or nil
        if progression.manages(surface) and playable_force(force) and not explicit_fulgora[surface_index] then
            local current = force_state(force)
            current.counts.fulgora = math.max(current.counts.fulgora or 0,
                math.min(progression.limit, saved.rooms or 0))
        end
    end

    for force_index, recovered_state in pairs(recovered) do
        local current = force_state(game.forces[force_index])
        for family, count in pairs(recovered_state.counts) do
            current.counts[family] = math.max(current.counts[family] or 0, count)
        end
        for key, family in pairs(recovered_state.sites) do current.sites[key] = family end
    end
    state.legacy_migrated = true
end

function progression.clear_force(force_index)
    root().by_force[force_index] = nil
    if storage.the_cave_fulgora_recycling_recovery then
        storage.the_cave_fulgora_recycling_recovery[force_index] = nil
    end
    local legacy = storage.the_cave_advancing_progression
    if legacy and legacy.by_force then legacy.by_force[force_index] = nil end
    for key in pairs(storage.the_cave_fulgora_ruin_rooms or {}) do
        local owner = tonumber(tostring(key):match("^%d+:(%d+)$"))
        if owner == force_index then storage.the_cave_fulgora_ruin_rooms[key] = nil end
    end
end

function progression.on_forces_merged(event)
    local destination = event and event.destination
    if not (event and event.source_index and playable_force(destination)) then return end
    if event.source_index == destination.index then return end
    local state = root()
    local source = state.by_force[event.source_index]
    if not source then return end
    local target = force_state(destination)
    for family in pairs(FAMILIES) do
        target.counts[family] = math.min(progression.limit,
            (target.counts[family] or 0) + (source.counts[family] or 0))
    end
    for key, family in pairs(source.sites) do target.sites[key] = family end
    state.by_force[event.source_index] = nil
end

return progression
