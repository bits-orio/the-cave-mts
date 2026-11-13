-- Fixed extraction-cave opportunities for NEW Advancing Collapse zones only.
-- Plan once from the map seed, discover by digging, and retain the reservation
-- after an entrance seals. No evolution roll, distance gate or resource deck.
local settings = require("scripts.game_settings").proxy(settings)
local zones = require("scripts.advancing_zones")
local hash = require("scripts.lib.hash")
local cave_policy = require("scripts.cave_policy")
local caves = {}

local SETTINGS = {
    fortress = "the-cave-fortified-cave",
    uranium = "the-cave-uranium-caves",
    iron = "the-cave-iron-cave", copper = "the-cave-copper-cave",
    coal = "the-cave-coal-cave",
}
local REGISTRIES = {
    "the_cave_uranium_caves", "the_cave_mineral_caves",
    "the_cave_lost_city", "the_cave_fortified_vaults",
}

local function initialize_schedule(r)
    if r.four_per_kind_from then return end
    -- Freeze the density boundary once on upgrade, after zone geometry has
    -- migrated. Retain generated terrain and every saved 3.2.7 reservation,
    -- including undiscovered/pending entries and plans ahead of generation.
    local highest = (zones.first_scheduled_zone() or 1) - 1
    local advancing = storage.the_cave_advancing_collapse
    for _, visited in pairs(advancing and advancing.highest_zone_by_force or {}) do
        highest = math.max(highest, tonumber(visited) or 0)
    end
    for _, state in pairs(r.surfaces) do
        highest = math.max(highest, (state.next_zone or 1) - 1)
    end
    -- MTS uses shared zone geometry. Inspect chunk metadata once across its
    -- main maps; never scan tiles/entities or repeat this work on ticks.
    for _, surface in pairs(game.surfaces) do
        if zones.is_main_surface(surface) then
            for chunk in surface.get_chunks() do
                if chunk.x >= -8 and chunk.x <= 7 then
                    highest = math.max(highest, zones.zone_index_at_y(chunk.y * 32))
                end
            end
        end
    end
    r.version = 2
    r.four_per_kind_from = highest + 1
end

local function root()
    storage.the_cave_advancing_caves = storage.the_cave_advancing_caves
        or { surfaces = {}, pending = {}, cursor = 1 }
    local r = storage.the_cave_advancing_caves
    initialize_schedule(r)
    return r
end

local function key(x, y) return tostring(x) .. ":" .. tostring(y) end

local function reserve(state, x, y)
    for dx = -1, 1 do
        for dy = -1, 1 do state.blocked[key(x + dx, y + dy)] = true end
    end
end

local function surface_state(surface)
    local r = root()
    local state = r.surfaces[surface.index]
    if state then return state end
    state = { next_zone = zones.first_scheduled_zone(), zones = {}, by_chunk = {}, blocked = {} }
    r.surfaces[surface.index] = state
    -- Preserve the exclusion ring of old entrances at the migration boundary.
    -- Use the existing registries once; do not scan the map for entities.
    for _, name in ipairs(REGISTRIES) do
        local registry = storage[name]
        for _, record in pairs(registry and registry.by_id or {}) do
            if record.parent_surface_index == surface.index and record.entrance_position then
                local p = record.entrance_position
                reserve(state, math.floor(p.x / 32), math.floor(p.y / 32))
            end
        end
    end
    return state
end

function caves.on_init()
    -- This runs before fresh-world zone initialization, also on soft reset.
    storage.the_cave_advancing_caves = {
        surfaces = {}, pending = {}, cursor = 1, version = 2, four_per_kind_from = 1,
    }
end

function caves.on_configuration_changed()
    if zones.is_active() then root() end
end

function caves.on_surface_deleted(event)
    local r = storage.the_cave_advancing_caves
    if r then r.surfaces[event.surface_index] = nil end
end

function caves.manages(surface, position)
    return zones.uses_scheduled_caves(surface, position)
end

function caves.enabled(kind)
    if kind == "village" then return cave_policy.LOST_VILLAGE_GENERATION_ENABLED end
    local name = SETTINGS[kind]
    if not name then return false end
    local setting = settings.startup[name]
    if not setting then return kind ~= "village" end
    return setting.value == "enabled" or setting.value == true
end

function caves.kinds_for_zone(index)
    -- Keep zone reservations stable across Startup toggles. enabled() gates
    -- discovery and retries, including previously saved uncreated sites.
    local kinds = {}
    if index >= 2 then kinds[#kinds + 1] = "fortress" end
    if index >= 3 then kinds[#kinds + 1] = "uranium" end
    if cave_policy.LOST_VILLAGE_GENERATION_ENABLED and index >= 3 and index % 2 == 1 then
        kinds[#kinds + 1] = "village"
    end
    if index >= 2 and index % 2 == 0 then
        kinds[#kinds + 1] = "iron"
        kinds[#kinds + 1] = "copper"
        kinds[#kinds + 1] = "coal"
    end
    return kinds
end

local function choose_chunk(state, seed, index, ordinal, bottom, first_row, last_row)
    -- Columns 1 and 16 are never candidates. Keep each new entrance inside
    -- its eight-row band, including when random attempts need the fallback.
    for attempt = 1, 64 do
        local x = hash.range(seed, index, ordinal, 7811 + attempt * 2, -7, 6)
        local y = bottom - hash.range(seed, index, ordinal, 7812 + attempt * 2, first_row, last_row)
        if not state.blocked[key(x, y)] then return x, y end
    end
    -- A bounded deterministic fallback cannot lose a quota to repeated rolls.
    local cells = 14 * (last_row - first_row + 1)
    local start = hash.range(seed, index, ordinal, 7943, 0, cells - 1)
    for offset = 0, cells - 1 do
        local cell = (start + offset) % cells
        local x, y = -7 + cell % 14, bottom - first_row - math.floor(cell / 14)
        if not state.blocked[key(x, y)] then return x, y end
    end
    error("The Cave: no legal chunk remains for an Advancing Collapse cave")
end

function caves.ensure_zone(surface, index)
    local first = zones.first_scheduled_zone()
    if not (zones.is_active() and zones.is_main_surface(surface) and first and index >= first) then
        return nil
    end
    local state = surface_state(surface)
    local four_per_kind_from = root().four_per_kind_from
    local seed = surface.map_gen_settings.seed or 0
    -- Ascending allocation makes cross-zone rings independent of exploration
    -- order. The cursor is saved; completed zones are never rolled again.
    while state.next_zone <= index do
        local number = state.next_zone
        local area = zones.zone_area(number)
        local bottom = math.floor(area.right_bottom.y / 32)
        local entries = {}
        local kinds = caves.kinds_for_zone(number)
        local bands = number >= four_per_kind_from and 4 or 1
        for band = 1, bands do
            local first_row = bands == 4 and (band - 1) * 8 + 1 or 1
            local last_row = bands == 4 and band * 8 or 32
            for ordinal, kind in ipairs(kinds) do
                local slot = (band - 1) * #kinds + ordinal
                local x, y = choose_chunk(state, seed, number, slot, bottom, first_row, last_row)
                local entry = {
                    zone = number, kind = kind, chunk_x = x, chunk_y = y,
                    position = { x = x * 32 + 16, y = y * 32 + 16 },
                    surface_index = surface.index, status = "undiscovered",
                    band = bands == 4 and band or nil,
                }
                entries[#entries + 1] = entry
                state.by_chunk[key(x, y)] = entry
                -- One shared ring across all kinds, bands and zone borders.
                reserve(state, x, y)
            end
        end
        state.zones[number] = entries
        state.next_zone = number + 1
    end
    return state.zones[index]
end

function caves.at_position(surface, position)
    if not caves.manages(surface, position) then return nil end
    caves.ensure_zone(surface, zones.zone_index_at_y(position.y))
    return surface_state(surface).by_chunk[key(math.floor(position.x / 32), math.floor(position.y / 32))]
end

function caves.is_planned_entrance(surface, position, kind)
    local entry = caves.at_position(surface, position)
    return entry and entry.kind == kind and entry.status ~= "created"
        and entry.position.x == position.x and entry.position.y == position.y
        and caves.enabled(kind) or false
end

function caves.queue(entry, force)
    if not (entry and entry.status ~= "created" and force and force.valid) then return end
    if entry.kind == "village" and not caves.enabled("village") then return end
    entry.force_index = entry.force_index or force.index
    if entry.queued then return end
    entry.queued = true
    entry.status = "pending"
    local pending = root().pending
    pending[#pending + 1] = entry
end

function caves.complete(entry)
    entry.status = "created"
end

function caves.retry_pending(callback)
    local r = storage.the_cave_advancing_caves
    if not (r and zones.is_active()) or #r.pending == 0 then return end
    -- Retry only already-discovered blocked sites, four per two-second pass.
    -- No active-player/surface/chunk scan and no random relocation.
    for _ = 1, math.min(4, #r.pending) do
        if r.cursor > #r.pending then r.cursor = 1 end
        local entry = r.pending[r.cursor]
        local surface = game.surfaces[entry.surface_index]
        local remove = entry.status == "created" or not (surface and surface.valid)
            or (entry.kind == "village" and not caves.enabled("village"))
        if not remove and not zones.is_playable(surface, entry.position.x, entry.position.y) then
            entry.status = "collapsed"
            remove = true
        end
        if not remove and caves.enabled(entry.kind) then
            local force = game.forces[entry.force_index]
            if force and force.valid then callback(surface, entry, force) end
            remove = entry.status == "created"
        end
        if remove then
            entry.queued = nil
            table.remove(r.pending, r.cursor)
        else
            r.cursor = r.cursor + 1
        end
        if #r.pending == 0 then r.cursor = 1; break end
    end
end

-- Ordinary cavern rooms must not occupy a scheduled entrance's future site.
-- Only its selected chunk is reserved against room carving; the eight-neighbour
-- rule above applies to selection of the six scheduled cave types.
function caves.intersects_reserved(surface, x1, y1, x2, y2)
    if not (zones.is_active() and zones.is_main_surface(surface)) then return false end
    local first = zones.first_scheduled_zone()
    local last = zones.zone_index_at_y(y1)
    if not first or last < first then return false end
    caves.ensure_zone(surface, last)
    local state = surface_state(surface)
    for x = math.floor(x1 / 32), math.floor(x2 / 32) do
        for y = math.floor(y1 / 32), math.floor(y2 / 32) do
            if state.by_chunk[key(x, y)] then return true end
        end
    end
    return false
end

return caves
