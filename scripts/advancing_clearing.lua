-- Sixteen native chunk columns by five rows, clipped to the 510-tile map.
-- Whole-chunk steps keep each saved nest's home stable until the front passes it.
local zones = require("scripts.advancing_zones")
local world = require("scripts.world")
local cave_teams = require("scripts.cave_teams")

local clearing = { WIDTH = zones.ZONE_WIDTH, DEPTH = 160, CELL_SIZE = 32,
    COLUMNS = 16, ROWS = 5, CELL_COUNT = 80, COMMIT_ROWS = 2 }
local MAX_UNCOMMITTED_ROWS = 8

function clearing.bounds(surface_state)
    -- The hidden southern guard uses Y=130 during preparation. The visible
    -- clearing already ends at Y=64, the actual collapse start line.
    local bottom = math.floor(math.min(surface_state.line_y or zones.SOUTH_GUARD_LINE_Y,
        zones.SOUTH_GUARD_LINE_Y) / clearing.CELL_SIZE) * clearing.CELL_SIZE
    return -clearing.WIDTH / 2, clearing.WIDTH / 2, bottom - clearing.DEPTH, bottom
end

-- Keep the native-chunk assault grid above unchanged. Terrain has its own
-- saved front: a complete southern row and one northern row commit together.
function clearing.completed_line(surface_state)
    local bottom = math.floor(math.min(surface_state.line_y or zones.SOUTH_GUARD_LINE_Y,
        zones.SOUTH_GUARD_LINE_Y))
    if surface_state.row_order
        and (surface_state.row_cursor or 1) > #surface_state.row_order then
        bottom = bottom - 1
    end
    return bottom
end

function clearing.initialize_follow(surface_state)
    local root = storage and storage.the_cave_advancing_collapse
    local state = surface_state and surface_state.clearing
    if not (root and surface_state.phase == "active" and state
        and type(state.next_y) == "number") then return end
    if type(state.follow_line_y) ~= "number" or type(state.follow_depth) ~= "number" then
        state.follow_line_y = clearing.completed_line(surface_state)
        -- Legacy clears can be up to 31 rows ahead. Retain that opened floor
        -- and follow from here, without refilling it or waiting to catch up.
        state.follow_depth = math.max(clearing.DEPTH,
            state.follow_line_y - state.next_y - 1)
        state.prepared_strip = nil
    end
end

function clearing.terrain_bounds(surface_state)
    local state = surface_state and surface_state.clearing
    local bottom = state and state.follow_line_y
        or math.floor(math.min(surface_state.line_y or zones.SOUTH_GUARD_LINE_Y,
            zones.SOUTH_GUARD_LINE_Y))
    local depth = state and state.follow_depth or clearing.DEPTH
    return -clearing.WIDTH / 2, clearing.WIDTH / 2, bottom - depth, bottom
end

function clearing.cell_bounds(surface_state, index)
    local min_x, max_x, top = clearing.bounds(surface_state)
    local column = (index - 1) % clearing.COLUMNS
    local row = math.floor((index - 1) / clearing.COLUMNS)
    local left = -clearing.COLUMNS * clearing.CELL_SIZE / 2 + column * clearing.CELL_SIZE
    top = top + row * clearing.CELL_SIZE
    return math.max(min_x, left), math.min(max_x, left + clearing.CELL_SIZE),
        top, top + clearing.CELL_SIZE
end

function clearing.is_ready(surface_state)
    local state = surface_state and surface_state.clearing
    if not (state and type(state.next_y) == "number" and state.width == clearing.WIDTH)
        or state.widening then return false end
    local _, _, top = clearing.terrain_bounds(surface_state)
    return state.next_y < top
end

-- Prepare only the chunks touched by the next two strips, one chunk per
-- controller pass. Do not force-generate sixteen columns in a commit tick.
local function prepare_next_strip(surface, state)
    local first_cx = math.floor(-clearing.WIDTH / 2 / clearing.CELL_SIZE)
    local last_cx = math.floor((clearing.WIDTH / 2 - 1) / clearing.CELL_SIZE)
    local first_cy = math.floor((state.next_y - 2 - clearing.COMMIT_ROWS + 1) / clearing.CELL_SIZE)
    local last_cy = math.floor(state.next_y / clearing.CELL_SIZE)
    local prepared = state.prepared_strip
    if not prepared or prepared.first_cy > first_cy or prepared.last_cy < last_cy then
        prepared = { first_cy = first_cy, last_cy = last_cy,
            cx = first_cx, cy = first_cy, ready = false }
        state.prepared_strip = prepared
    end
    if prepared.ready then return true end
    if game and prepared.work_tick == game.tick then return false end
    prepared.work_tick = game and game.tick or nil
    if not world.ensure_generated_radius(surface, {
        x = prepared.cx * clearing.CELL_SIZE + clearing.CELL_SIZE / 2,
        y = prepared.cy * clearing.CELL_SIZE + clearing.CELL_SIZE / 2,
    }, 0) then return false end
    prepared.cx = prepared.cx + 1
    if prepared.cx > last_cx then
        prepared.cx = first_cx
        prepared.cy = prepared.cy + 1
        prepared.ready = prepared.cy > prepared.last_cy
    end
    return prepared.ready
end

function clearing.prepare_commit(surface, surface_state)
    if not (surface and surface.valid and clearing.is_ready(surface_state)) then return end
    local state = surface_state.clearing
    if state.follow_line_y then prepare_next_strip(surface, state) end
end

function clearing.can_erode(surface_state)
    local state = surface_state and surface_state.clearing
    return clearing.is_ready(surface_state) and state.follow_line_y
        and state.follow_line_y - clearing.completed_line(surface_state) < MAX_UNCOMMITTED_ROWS
end

function clearing.advance_row(surface, surface_state)
    if not (surface and surface.valid and clearing.is_ready(surface_state)) then return false end
    local state = surface_state.clearing
    local prepared = state.prepared_strip
    local first_cy = math.floor((state.next_y - 2) / clearing.CELL_SIZE)
    local last_cy = math.floor(state.next_y / clearing.CELL_SIZE)
    if not (state.follow_line_y and prepared and prepared.ready
        and prepared.first_cy <= first_cy and prepared.last_cy >= last_cy) then return false end
    -- A different mod can delete a prefetched chunk. Wait for bounded
    -- preparation again rather than falling into the synchronous generator.
    for cx = math.floor(-clearing.WIDTH / 2 / clearing.CELL_SIZE),
        math.floor((clearing.WIDTH / 2 - 1) / clearing.CELL_SIZE) do
        for cy = first_cy, last_cy do
            if not surface.is_chunk_generated({cx, cy}) then
                state.prepared_strip = nil
                return false
            end
        end
    end
    if not world.carve_resource_strip(surface, -clearing.WIDTH / 2,
        clearing.WIDTH / 2, state.next_y, cave_teams.surface_owner_force(surface)) then
        state.prepared_strip = nil
        return false
    end
    state.next_y = state.next_y - 1
    state.follow_line_y = state.follow_line_y - 1
    return true
end

-- Structural Cave Collapse must not refill opened rows with falling rubble.
function clearing.contains(surface, x, y)
    if not (surface and surface.valid and zones.is_active() and zones.is_main_surface(surface)) then return false end
    local root = storage and storage.the_cave_advancing_collapse
    local surface_state = root and root.surfaces and root.surfaces[surface.index]
    local state = surface_state and surface_state.clearing
    if not (state and type(state.next_y) == "number") then return false end
    local min_x, max_x, top, bottom = clearing.terrain_bounds(surface_state)
    y = math.floor(y)
    return x >= min_x and x < max_x and y >= top and y < bottom and y > state.next_y
end

function clearing.on_tick(surface, surface_state)
    if not (surface and surface.valid and surface_state and cave_teams.is_world_running(surface) and zones.is_active()
        and zones.is_main_surface(surface)) then return end
    local root = storage.the_cave_advancing_collapse
    if not (root and (surface_state.phase == "active" or surface_state.phase == "countdown")) then return end
    local min_x, max_x, top, bottom = clearing.terrain_bounds(surface_state)
    local state = surface_state.clearing
    if type(state) ~= "table" then
        state = { next_y = bottom - 1, width = clearing.WIDTH }
        surface_state.clearing = state
    end
    clearing.initialize_follow(surface_state)
    min_x, max_x, top, bottom = clearing.terrain_bounds(surface_state)
    if state.width ~= clearing.WIDTH then
        -- Upgrade only the new sides, preserving mined resources and water in
        -- the old centre. Cursors resume unchanged after saves and rest periods.
        local old_half=state.widening and state.widening.old_half or (state.width or 96)/2
        state.widening = { next_y = bottom - 1,
            stop_y = math.max(top, (tonumber(state.next_y) or bottom - 1) + 1),
            old_half = old_half }
        state.width = clearing.WIDTH
    end
    local force = cave_teams.surface_owner_force(surface)
    local widening = state.widening
    if widening then
        widening.next_y = math.min(widening.next_y, bottom - 1)
        if widening.next_y >= math.max(widening.stop_y, top) then
            if not widening.left_done then
                widening.left_done = world.carve_resource_strip(surface,
                    min_x, -widening.old_half, widening.next_y, force)
            end
            if widening.left_done and world.carve_resource_strip(surface,
                widening.old_half, max_x, widening.next_y, force) then
                widening.next_y = widening.next_y - 1
                widening.left_done = nil
            end
            return
        end
        state.widening = nil
    end
    state.next_y = math.min(tonumber(state.next_y) or (bottom - 1), bottom - 1)
    if state.next_y < top then
        if surface_state.phase == "active" then prepare_next_strip(surface, state) end
        return
    end
    if world.carve_resource_strip(surface, min_x, max_x, state.next_y, force) then
        state.next_y = state.next_y - 1
    end
end

-- Complete initial generation before play when possible. Asynchronous team
-- generation resumes via the bounded tick path without blocking the server.
function clearing.prepare(surface, surface_state)
    for _ = 1, clearing.DEPTH do
        local previous = surface_state.clearing and surface_state.clearing.next_y
        clearing.on_tick(surface, surface_state)
        if clearing.is_ready(surface_state) then return end
        if surface_state.clearing and surface_state.clearing.next_y == previous then return end
    end
end
return clearing
