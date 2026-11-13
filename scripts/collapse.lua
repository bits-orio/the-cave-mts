local settings = require("scripts.game_settings").proxy(settings)

-- Cave collapse via STATELESS geometry stress (ADR 0008): a cell's stress is
-- a pure function of the current world —
--   stress = LOAD x (mask-weighted open-floor fraction)
--            - Σ support contributions (entities by live reach, flooring)
-- recomputed on demand for cells affected by each world-changing event.
-- No ledger, no history, no possibility of poisoned saves. Thresholds, mask
-- shape and support strengths preserve the tuned outcome: a fully open
-- unsupported cell reads exactly 4.0 against the 3.57 threshold, and a
-- stone-wall lattice with 3-tile gaps holds (~2.5-3.0). Wall strength 5 is
-- the deliberate deviation from the original's 3 (see ADR 0008 history).
--
-- Reads go through the world mirror (ADR 0009) — pure Lua, no API calls in
-- the hot path. Rock-grade cover folds into the same disc pass as the load.
local hash = require("scripts.lib.hash")
local mirror = require("scripts.lib.mirror")
local cave_teams = require("scripts.cave_teams")
local pop_text = require("scripts.pop_text")
local advancing_clearing = require("scripts.advancing_clearing")
local cave_policy = require("scripts.cave_policy")
local roof_support = require("scripts.roof_support")

local collapse = {}
collapse.is_surface_exempt = cave_policy.is_collapse_exempt

-- One startup switch controls the complete system. Enabled uses the original
-- balance; Disabled removes collapses, warnings, sounds and effects.
local function collapses_disabled()
    local collapse_setting = settings.startup["the-cave-collapse-mode"]
    return not (collapse_setting and collapse_setting.value == "enabled")
end

local STRESS_THRESHOLD = 3.57
local NEAR_THRESHOLD = 3.3
local COLLAPSE_DELAY_TICKS = 150 -- original: 2.5 seconds
local NORMAL_COLLAPSE_DENSITY = 1
local CAVERN_COLLAPSE_DENSITY = 0.55
local COLLAPSE_MASK_FACTOR = 16 -- original: collapse_threshold_total_strength
local LOAD = 4.0 -- a fully open, unsupported cell

-- fill_cell's spared-entity check (mirror folds rock-grade cover into tile
-- codes; walls/reactors live in its support lists).
local SUPPORTS = {
    ["diggy-rock"] = 2,
    ["diggy-rubble"] = 2,
    ["stone-wall"] = 5,
    ["nuclear-reactor"] = 6,
}

collapse.SUPPORT_NAMES = { "diggy-rock", "diggy-rubble", "stone-wall", "nuclear-reactor" }
local BASE_RADIUS = 4
local MAX_REACH = 14
local SUPPORT_WINDOW_RADIUS = MAX_REACH + 2
local SUPPORT_LUT_WIDTH = SUPPORT_WINDOW_RADIUS * 2 + 1

-- Disc mask (size 9 at base): rings 2/3/4 normalized. value_of(d²) gives the
-- per-point weight; supports with researched reach use wider masks, scaled
-- so per-cell strength stays constant.
local MASKS = {}

local function build_mask(radius)
    local radius_sq = (radius + 0.2) * (radius + 0.2)
    local center_sq = radius_sq / 9
    local disc_sq = radius_sq * 4 / 9
    local weights = { ring = 2, disc = 3, center = 4 }
    local sum, points = 0, 0
    for x = -radius, radius do
        for y = -radius, radius do
            local d = x * x + y * y
            local w
            if d <= center_sq then
                w = weights.center
            elseif d <= disc_sq then
                w = weights.disc
            elseif d <= radius_sq then
                w = weights.ring
            end
            if w then
                sum = sum + w
                points = points + 1
            end
        end
    end
    return {
        radius = radius,
        points = points,
        value_of = function(d_sq)
            if d_sq <= center_sq then return weights.center / sum end
            if d_sq <= disc_sq then return weights.disc / sum end
            if d_sq <= radius_sq then return weights.ring / sum end
            return 0
        end,
    }
end

local function mask_for(radius)
    radius = math.min(math.max(radius or BASE_RADIUS, BASE_RADIUS), MAX_REACH)
    if not MASKS[radius] then MASKS[radius] = build_mask(radius) end
    return MASKS[radius]
end
local BASE_MASK = mask_for(BASE_RADIUS)

-- The base mask flattened for the hot loop (oy outer, ox inner).
local BASE_W = {}
for oy = -BASE_RADIUS, BASE_RADIUS do
    for ox = -BASE_RADIUS, BASE_RADIUS do
        BASE_W[#BASE_W + 1] = BASE_MASK.value_of(ox * ox + oy * oy)
    end
end

-- Per-reach contribution LUTs for walls/reactors, replacing a closure call
-- per wall per cell. The window includes two tiles beyond maximum researched
-- reach because surrounding-cell re-evaluation uses the same bound.
local REACH_LUT = {}
local function lut_for(reach)
    local lut = REACH_LUT[reach]
    if not lut then
        local mask = mask_for(reach)
        -- A wider mask covers ~quadratically more points; scaling by the
        -- full points ratio would make each Support Struts tier multiply
        -- every wall's total mass (~5.9x at max reach) on top of the reach
        -- itself. Instead the mass multiplier runs from 1 at base reach to
        -- the host-tunable "strength at max research", interpolated by
        -- area growth.
        local max_ratio = mask_for(MAX_REACH).points / BASE_MASK.points
        local strut_max = settings.global["diggy-strut-strength-max"].value
        local ratio = mask.points / BASE_MASK.points
        local scale = (1 + (ratio - 1) * (strut_max - 1) / (max_ratio - 1)) * 4
        lut = {}
        for dx = -SUPPORT_WINDOW_RADIUS, SUPPORT_WINDOW_RADIUS do
            for dy = -SUPPORT_WINDOW_RADIUS, SUPPORT_WINDOW_RADIUS do
                lut[(dx + SUPPORT_WINDOW_RADIUS) * SUPPORT_LUT_WIDTH
                    + dy + SUPPORT_WINDOW_RADIUS + 1] = scale * mask.value_of(dx * dx + dy * dy)
            end
        end
        REACH_LUT[reach] = lut
    end
    return lut
end

local FLOOR_SUPPORT = mirror.FLOOR_SUPPORT

function collapse.on_init()
    storage.pending_collapses = {}
    storage.collapse_count = {}
    storage.collapse_log = {}
    storage.warn_renders = {}
    storage.collapse_warning_sprite_cleanup_done = false
    storage.telegraphs = {}
end

local function cell_key(x, y)
    return x .. "," .. y
end

local function clear_warning_markers()
    storage.warn_renders = storage.warn_renders or {}
    for key, id in pairs(storage.warn_renders) do
        local obj = rendering.get_object_by_id(id)
        if obj then obj.destroy() end
        storage.warn_renders[key] = nil
    end

    -- Some test saves lost the warn_renders registry before the old permanent
    -- ALT-mode warning sprites were destroyed. The render objects themselves
    -- therefore survived as orphans. Scan this mod's objects by identity and
    -- remove only that exact legacy sprite; rectangles/text used by the real
    -- collapse countdown, and every other The Cave rendering, stay intact.
    for _, obj in pairs(rendering.get_all_objects("the-cave")) do
        if obj.valid and obj.type == "sprite" and obj.sprite == "utility/warning_icon" then
            obj.destroy()
        end
    end
    storage.collapse_warning_sprite_cleanup_done = true
end

-- Public migration/cleanup hook. Stress is intentionally hidden during
-- normal play; only an actually scheduled collapse gets a world telegraph.
function collapse.clear_warning_markers()
    clear_warning_markers()
end

-- Injected by caverns.lua: true while a worm-guarded room covers the cell.
collapse.protection_check = nil

-- Live Support Struts reach per force: research benefits ALL walls at once.
local reach_cache, reach_cache_tick = {}, -1
local function reach_for(force_index)
    if reach_cache_tick ~= game.tick then
        reach_cache, reach_cache_tick = {}, game.tick
    end
    local reach = reach_cache[force_index]
    if not reach then
        local force = game.forces[force_index]
        reach = BASE_RADIUS
        for i = 1, 10 do
            local tech = force.technologies["diggy-support-reach-" .. i]
            if tech and tech.researched then reach = reach + 1 end
        end
        reach_cache[force_index] = reach
    end
    return reach
end

-- Evaluation radius covering everything a force's supports influence.
function collapse.reach_radius(force)
    return reach_for(force.index) + 2
end

-- The pillar spacing that holds calmly at the current wall strength: the
-- original every-4th-tile grid above ~4.5 support, every 3rd tile below.
-- The spawn lattice and the benchmark sim both build to this.
function collapse.recommended_pillar_spacing()
    return settings.global["diggy-wall-support"].value >= 4.5 and 4 or 3
end

function collapse.is_disabled()
    return collapses_disabled()
end

local function force_for(surface, player_index, force_index)
    if force_index then
        local force = game.forces[force_index]
        if force then return force end
    end
    if player_index then
        local player = game.get_player(player_index)
        if player and player.valid then return player.force end
    end
    return cave_teams.owner_force(surface)
end

-- Enabled always uses the original scheduling; Disabled never arms anything.
function collapse.available_for(force)
    return not collapses_disabled()
end

-- Crowding penalty (host lever): touching walls share the load path, so a
-- wall's support divides by (1 + K x neighbours). Isolated pillars (n = 0)
-- are untouched; solid lines stop multiplying support.
local crowding_value, crowding_tick = 0, -1
local function crowding()
    if crowding_tick ~= game.tick then
        crowding_value = settings.global["diggy-wall-crowding"].value
        crowding_tick = game.tick
    end
    return crowding_value
end

local function effective_strength(record, k)
    local n = record.n
    if n and n > 0 and k > 0 then
        return record.s / (1 + k * n)
    end
    return record.s
end

-- ── The function (cell coords are even; a cell spans 2x2 tiles) ──────────

local wall_scratch = {}
local window = {}
-- Window indices of the cell's own 2x2 tiles (ox, oy in {0, 1}).
local OWN = { 41, 42, 50, 51 }

function collapse.compute_cell(surface, cx, cy)
    -- One pass over the base mask via the mirror window: open-floor load and
    -- rock-grade support (strength 2, base reach — same disc, so it folds in).
    mirror.fill_window(surface, cx, cy, window)
    local load_w, rock_w = 0, 0
    for i = 1, 81 do
        local w = BASE_W[i]
        if w > 0 then
            local v = window[i]
            if v >= 8 then
                load_w = load_w + w
                rock_w = rock_w + w
            elseif v >= 2 then
                load_w = load_w + w
            end
        end
    end
    -- Fully open ⇒ LOAD; a rock tile nets -(2 x 4 x w) against its own +4w.
    local value = LOAD * load_w - 8 * rock_w
    for k = 1, 4 do
        local fs = FLOOR_SUPPORT[window[OWN[k]] % 8]
        if fs then value = value - fs end
    end

    -- Walls and reactors, by their force's live researched reach and
    -- crowding-discounted strength.
    local k = crowding()
    local n = mirror.walls_near(surface, cx, cy, wall_scratch)
    for i = 1, n do
        local e = wall_scratch[i]
        local dx, dy = cx - e.x, cy - e.y
        if dx >= -SUPPORT_WINDOW_RADIUS and dx <= SUPPORT_WINDOW_RADIUS
            and dy >= -SUPPORT_WINDOW_RADIUS and dy <= SUPPORT_WINDOW_RADIUS then
            local c = lut_for(reach_for(e.f))[(dx + SUPPORT_WINDOW_RADIUS) * SUPPORT_LUT_WIDTH
                + dy + SUPPORT_WINDOW_RADIUS + 1]
            if c > 0 then value = value - effective_strength(e, k) * c end
        end
    end
    return value
end

-- ── Markers, triggers, evaluation ────────────────────────────────────────

-- A cell is evaluable only if its anchor tile is real ground: void cells
-- beyond the frontier see open neighbors and read high, but nothing there
-- can fall. Every evaluator must apply this — values at void cells are
-- measurement artifacts, not hazards.
local function cell_exists(surface, cx, cy)
    return mirror.tile_value(surface, cx, cy) ~= 0
end

-- Severity gradient across the warning band: yellow at 3.3, red at 3.57 —
-- and faint to solid the same way, so a tile-squeezed base reads as a
-- quiet haze with only the genuinely hot cells popping.
local function warn_tint(value)
    local t = math.min(math.max((value - NEAR_THRESHOLD) / (STRESS_THRESHOLD - NEAR_THRESHOLD), 0), 1)
    local a = 0.2 + 0.8 * t
    -- Premultiplied alpha: the engine treats unmultiplied RGB at low
    -- alpha as a bright additive glow, not a fade.
    return { r = a, g = (0.9 - 0.82 * t) * a, b = 0.05 * a, a = a }
end

-- ── Telegraph: a thin box around a cell awaiting judgment with a live
-- countdown inside — one UX shared by 2.5s collapse pendings and cavern
-- countdowns. Entries live in storage.telegraphs; tick() keeps the timer
-- text and the severity tint current.

function collapse.telegraph(surface, cx, cy, at_tick, value)
    if collapses_disabled() or collapse.is_surface_exempt(surface) then return nil end
    storage.telegraphs = storage.telegraphs or {}
    local box = rendering.draw_rectangle {
        surface = surface,
        left_top = { cx, cy },
        right_bottom = { cx + 2, cy + 2 },
        color = warn_tint(value or STRESS_THRESHOLD + 1),
        width = 1,
    }
    local timer = rendering.draw_text {
        surface = surface,
        target = { cx + 1, cy + 1 },
        text = string.format("%.1f", (at_tick - game.tick) / 60),
        color = { r = 1, g = 0.45, b = 0.1 },
        scale = 1.3,
        alignment = "center",
        vertical_alignment = "middle",
    }
    local entry = {
        surface_index = surface.index,
        x = cx,
        y = cy,
        at_tick = at_tick,
        box_id = box and box.id or nil,
        timer_id = timer and timer.id or nil,
    }
    storage.telegraphs[#storage.telegraphs + 1] = entry
    return entry
end

function collapse.untelegraph(entry)
    if not entry then return end
    for _, id in pairs({ entry.box_id, entry.timer_id }) do
        local obj = rendering.get_object_by_id(id)
        if obj then obj.destroy() end
    end
    local list = storage.telegraphs or {}
    for i = #list, 1, -1 do
        if list[i] == entry then
            list[i] = list[#list]
            list[#list] = nil
        end
    end
end

local function trigger(surface, cx, cy, player_index, value)
    if collapses_disabled() or collapse.is_surface_exempt(surface) then return end
    if collapse.is_protected(surface, cx, cy) then return end
    local force = force_for(surface, player_index)
    if not collapse.available_for(force) then return end
    for _, p in pairs(storage.pending_collapses) do
        if p.surface_index == surface.index and p.x == cx and p.y == cy then return end
    end

    -- Unmissable telegraph at the failure point (it can be tiles away from
    -- the dig that caused it): CRACKING! pop, a box around the exact failing
    -- 2x2 cell, and a live countdown inside it.
    pop_text.spawn(surface, { x = cx + 1, y = cy + 1 },
        { "diggy.collapse-imminent-pop" }, { r = 1, g = 0.25, b = 0.05 }, force)
    for _, player in pairs(force.connected_players) do
        player.create_local_flying_text {
            text = { "diggy.cracking-sound-" .. hash.range(surface.map_gen_settings.seed, cx, cy, 60, 1, 2) },
            position = { cx, cy },
            color = { r = 1, g = 0.3, b = 0 },
        }
    end
    storage.pending_collapses[#storage.pending_collapses + 1] = {
        surface_index = surface.index,
        x = cx,
        y = cy,
        player_index = player_index,
        force_index = force.index,
        at_tick = game.tick + COLLAPSE_DELAY_TICKS,
        telegraph = collapse.telegraph(surface, cx, cy, game.tick + COLLAPSE_DELAY_TICKS, value),
    }
end


-- ── Layer-2 stress cache (ADR 0009): incrementally maintained from mirror
-- deltas, never trusted at the moment of action. Lives in locals: wiped on
-- player join (lockstep), on Support Struts research (reach changes every
-- wall's contribution), and follows mirror chunk evictions via bulk drops.
local stress_cache = {} -- [surface_index][cx][cy] = value

local function cache_col(surface_index, cx)
    local sx = stress_cache[surface_index]
    if not sx then
        sx = {}
        stress_cache[surface_index] = sx
    end
    local col = sx[cx]
    if not col then
        col = {}
        sx[cx] = col
    end
    return col
end

function collapse.wipe_cache()
    stress_cache = {}
    reach_cache, reach_cache_tick = {}, -1
end

-- A strength setting moved: the LUTs bake it in, and every cached value
-- (and wall record — control wipes the mirror) is built on it.
function collapse.stress_basis_changed()
    REACH_LUT = {}
    stress_cache = {}
end

function collapse.drop_surface_cache(surface_index)
    stress_cache[surface_index] = nil
end

-- Surface indices can be reused. A removed/cleared surface must not leave
-- countdowns that later act on a different world with that same index.
function collapse.drop_surface_jobs(surface_index)
    local pending = storage.pending_collapses or {}
    for i = #pending, 1, -1 do
        if pending[i].surface_index == surface_index then
            collapse.untelegraph(pending[i].telegraph)
            table.remove(pending, i)
        end
    end
    local telegraphs = storage.telegraphs or {}
    for i = #telegraphs, 1, -1 do
        if telegraphs[i].surface_index == surface_index then collapse.untelegraph(telegraphs[i]) end
    end
end

-- Deltas are the ± of the exact terms compute_cell uses — symmetric by
-- construction, applied only to cells already cached.
mirror.on_tile_change(function(surface_index, x, y, old, new)
    local sx = stress_cache[surface_index]
    if not sx then return end
    local ob, nb = old % 8, new % 8
    local d_open = (nb >= 2 and 1 or 0) - (ob >= 2 and 1 or 0)
    local d_rock = (new >= 8 and 1 or 0) - (old >= 8 and 1 or 0)
    if d_open ~= 0 or d_rock ~= 0 then
        local amount = LOAD * d_open - 8 * d_rock
        -- First EVEN anchor at or inside the mask bound (never outside: the
        -- LUT has no entries past it).
        for cx = (x - 4) + ((x - 4) % 2), x + 4, 2 do
            local col = sx[cx]
            if col then
                local oxi = (x - cx) + 5 -- BASE_W is (oy+4)*9 + ox + 5
                for cy = (y - 4) + ((y - 4) % 2), y + 4, 2 do
                    local v = col[cy]
                    if v then
                        local w = BASE_W[(y - cy + 4) * 9 + oxi]
                        if w > 0 then col[cy] = v + amount * w end
                    end
                end
            end
        end
    end
    local d_fs = (FLOOR_SUPPORT[nb] or 0) - (FLOOR_SUPPORT[ob] or 0)
    if d_fs ~= 0 then
        local col = sx[2 * math.floor(x * 0.5)]
        local cy = 2 * math.floor(y * 0.5)
        if col and col[cy] then col[cy] = col[cy] - d_fs end
    end
end)

mirror.on_wall_change(function(surface_index, record, sign)
    local sx = stress_cache[surface_index]
    if not sx then return end
    local lut = lut_for(reach_for(record.f))
    local amount = sign * effective_strength(record, crowding())
    for cx = (record.x - SUPPORT_WINDOW_RADIUS)
            + ((record.x - SUPPORT_WINDOW_RADIUS) % 2),
        record.x + SUPPORT_WINDOW_RADIUS, 2 do
        local col = sx[cx]
        if col then
            local dxi = (cx - record.x + SUPPORT_WINDOW_RADIUS) * SUPPORT_LUT_WIDTH
                + SUPPORT_WINDOW_RADIUS + 1
            for cy = (record.y - SUPPORT_WINDOW_RADIUS)
                    + ((record.y - SUPPORT_WINDOW_RADIUS) % 2),
                record.y + SUPPORT_WINDOW_RADIUS, 2 do
                local v = col[cy]
                if v then
                    local c = lut[dxi + (cy - record.y)]
                    if c > 0 then col[cy] = v - amount * c end
                end
            end
        end
    end
end)

-- A chunk rebuilt or evicted from the mirror can no longer feed deltas:
-- forget every cell whose computation could have read into it.
mirror.on_bulk_change(function(surface_index, x1, y1, x2, y2)
    local sx = stress_cache[surface_index]
    if not sx then return end
    for cx = 2 * math.floor((x1 - SUPPORT_WINDOW_RADIUS) * 0.5),
        x2 + SUPPORT_WINDOW_RADIUS, 2 do
        local col = sx[cx]
        if col then
            for cy = 2 * math.floor((y1 - SUPPORT_WINDOW_RADIUS) * 0.5),
                y2 + SUPPORT_WINDOW_RADIUS, 2 do
                col[cy] = nil
            end
        end
    end
end)

-- Re-derive a cell from facts before acting on its cached value. Drift means
-- a delta-coverage bug: correct it and say so loudly.
local function verified(surface, col, cx, cy, value)
    local truth = collapse.compute_cell(surface, cx, cy)
    if math.abs(truth - value) > 0.005 then
        log(string.format("[DIGGY] stress cache drift at %d,%d on %s: cached=%.3f truth=%.3f",
            cx, cy, surface.name, value, truth))
        col[cy] = truth
    end
    return truth
end

local audit_counter = 0

-- THE entry point after any world-changing event: judge every cell within
-- `radius` tiles against its cached value; recompute on miss; verify any
-- cached value before it changes a marker or triggers a collapse.
function collapse.evaluate_around(surface, position, radius, player_index)
    if collapse.is_surface_exempt(surface) then return end
    if surface and surface.valid and type(surface.name) == "string"
        and surface.name:sub(1, #"the-cave-shelter-interior-") == "the-cave-shelter-interior-" then
        return
    end
    if collapses_disabled() then
        clear_warning_markers()
        return
    end
    radius = radius or (BASE_RADIUS + 2)
    local si = surface.index
    local x0, y0 = math.floor(position.x), math.floor(position.y)
    for cx = 2 * math.floor((x0 - radius) * 0.5), x0 + radius, 2 do
        local col = cache_col(si, cx)
        for cy = 2 * math.floor((y0 - radius) * 0.5), y0 + radius, 2 do
            if cell_exists(surface, cx, cy) then
                local value = col[cy]
                local fresh = false
                if value == nil then
                    value = collapse.compute_cell(surface, cx, cy)
                    col[cy] = value
                    fresh = true
                end
                if value > STRESS_THRESHOLD then
                    if not fresh then
                        value = verified(surface, col, cx, cy, value)
                    end
                    if value > STRESS_THRESHOLD then
                        trigger(surface, cx, cy, player_index, value)
                    end
                end
            end
        end
    end
    -- Rolling audit: every 16th evaluation re-derives its center cell, so a
    -- systematic delta bug surfaces (and self-corrects) within seconds.
    audit_counter = audit_counter + 1
    if audit_counter % 16 == 0 then
        local cx, cy = 2 * math.floor(x0 * 0.5), 2 * math.floor(y0 * 0.5)
        local col = cache_col(si, cx)
        if col[cy] and cell_exists(surface, cx, cy) then
            verified(surface, col, cx, cy, col[cy])
        end
    end
end

-- Cache health probe (debug remote): cached cells re-derived over an area.
function collapse.cache_check(surface, x1, y1, x2, y2)
    local cached, max_delta = 0, 0
    local sx = stress_cache[surface.index]
    for cx = 2 * math.floor(x1 * 0.5), x2, 2 do
        local col = sx and sx[cx]
        for cy = 2 * math.floor(y1 * 0.5), y2, 2 do
            local v = col and col[cy]
            if v then
                cached = cached + 1
                local d = math.abs(v - collapse.compute_cell(surface, cx, cy))
                if d > max_delta then max_delta = d end
            end
        end
    end
    return { cached = cached, max_delta = max_delta }
end

-- Cells over threshold within a disc (cavern arming, diagnostics).
function collapse.hot_cells(surface, cx, cy, radius)
    if collapses_disabled() or collapse.is_surface_exempt(surface) then return {} end
    local hot = {}
    for x = 2 * math.floor((cx - radius) * 0.5), cx + radius, 2 do
        for y = 2 * math.floor((cy - radius) * 0.5), cy + radius, 2 do
            if cell_exists(surface, x, y) and collapse.compute_cell(surface, x, y) > STRESS_THRESHOLD then
                hot[#hot + 1] = { x = x, y = y }
            end
        end
    end
    return hot
end

-- Cavern grace state (worms alive or countdown running), for diagnostics
-- and the benchmark: protected cells legitimately sit over threshold.
function collapse.is_protected(surface, x, y)
    return collapse.is_surface_exempt(surface)
        or advancing_clearing.contains(surface, x, y)
        or roof_support.is_cell_protected(surface, x, y)
        or (collapse.protection_check ~= nil and collapse.protection_check(surface, x, y))
end

-- A newly placed support also retires already queued jobs and their labels.
-- Partly covered cells remain queued: fill_cell spares only protected tiles.
function collapse.cancel_roof_jobs()
    local pending = storage.pending_collapses or {}
    for i = #pending, 1, -1 do
        local p = pending[i]
        if roof_support.is_cell_protected(game.surfaces[p.surface_index], p.x, p.y) then
            collapse.untelegraph(p.telegraph)
            table.remove(pending, i)
        end
    end
end

function collapse.max_in_area(surface, x1, y1, x2, y2, ignore_protected)
    local maxv = 0
    for x = 2 * math.floor(x1 * 0.5), x2, 2 do
        for y = 2 * math.floor(y1 * 0.5), y2, 2 do
            if cell_exists(surface, x, y)
                and not (ignore_protected and collapse.is_protected(surface, x, y)) then
                local v = collapse.compute_cell(surface, x, y)
                if v > maxv then maxv = v end
            end
        end
    end
    return maxv
end

-- Debug overlay (/diggy-stress): computed live, painted for 10 seconds.
function collapse.debug_overlay(player)
    local surface = player.surface
    local px, py = math.floor(player.position.x), math.floor(player.position.y)
    local shown = 0
    for x = px - 40, px + 40, 2 do
        for y = py - 40, py + 40, 2 do
            local cx, cy = 2 * math.floor(x * 0.5), 2 * math.floor(y * 0.5)
            if cell_exists(surface, cx, cy) then
                local value = collapse.compute_cell(surface, cx, cy)
                if value > 0.05 or value < -0.05 then
                    local t = math.min(math.max(value / STRESS_THRESHOLD, 0), 1)
                    rendering.draw_text {
                        text = string.format("%.1f", value),
                        surface = surface,
                        target = { cx + 1, cy + 1 },
                        color = value < 0 and { r = 0.4, g = 0.7, b = 1 }
                            or { r = t, g = 1 - t, b = 0 },
                        scale = 0.8,
                        alignment = "center",
                        time_to_live = 600,
                        players = { player.index },
                    }
                    shown = shown + 1
                end
            end
        end
    end
    player.print({ "diggy.stress-overlay", shown })
end

-- ── Collapse execution ────────────────────────────────────────────────────

-- Crush an entity: with crushed-remains recovery enabled (off by default),
-- inventories go into a buried character-corpse; otherwise destroyed.
local function crush(surface, entity)
    if entity.type == "character" then
        entity.die()
        return
    end
    if not settings.global["diggy-crushed-remains"].value then
        entity.die()
        return
    end
    local stacks = {}
    for i = 1, 10 do
        local ok, inventory = pcall(entity.get_inventory, i)
        if ok and inventory and inventory.valid then
            for j = 1, #inventory do
                local stack = inventory[j]
                if stack.valid_for_read then
                    stacks[#stacks + 1] = { name = stack.name, count = stack.count, quality = stack.quality }
                end
            end
        end
    end
    if #stacks > 0 then
        local corpse = surface.create_entity {
            name = "character-corpse",
            position = entity.position,
            inventory_size = #stacks,
        }
        if corpse then
            local inv = corpse.get_inventory(defines.inventory.character_corpse)
            for _, s in pairs(stacks) do
                inv.insert(s)
            end
        end
    end
    entity.die()
end

local function log_collapse(surface_index, x, y)
    storage.collapse_count[surface_index] = (storage.collapse_count[surface_index] or 0) + 1
    storage.collapse_log = storage.collapse_log or {}
    storage.collapse_log[#storage.collapse_log + 1] =
        { surface_index = surface_index, x = x, y = y, tick = game.tick }
    if #storage.collapse_log > 60 then table.remove(storage.collapse_log, 1) end
end

-- Fill one cell's tiles with rubble where unsupported; crush what stands.
local function fill_cell(surface, cellx, celly, density, seed)
    local rocks = 0
    for dx = 0, 1 do
        for dy = 0, 1 do
            local tx, ty = cellx + dx, celly + dy
            if not advancing_clearing.contains(surface, tx, ty)
                and not roof_support.is_tile_protected(surface, tx, ty) then
                local falls = density >= 1 or hash.roll(seed, tx, ty, 80) < density
                local supported = false
                for _, entity in pairs(surface.find_entities_filtered {
                    area = { { tx + 0.05, ty + 0.05 }, { tx + 0.95, ty + 0.95 } },
                }) do
                    -- Killing a segmented unit invalidates its other segments,
                    -- including references already returned by this query.
                    if entity.valid then
                        if SUPPORTS[entity.name] then
                            supported = true
                        elseif entity.name == "character-corpse" or entity.type == "resource" then
                            -- buried, not crushed
                        elseif entity.type == "character" or entity.health then
                            crush(surface, entity)
                        end
                    end
                end
                local tile = surface.get_tile(tx, ty)
                if falls and not supported and tile.valid and tile.name ~= "out-of-map"
                    and not tile.name:find("water", 1, true) then
                    surface.create_entity { name = "diggy-rubble", position = { tx + 0.5, ty + 0.5 }, force = "neutral" }
                    mirror.set_rock(surface, { x = tx, y = ty }, true)
                    rocks = rocks + 1
                end
            end
        end
    end
    return rocks
end

local function execute(pending)
    local surface = game.surfaces[pending.surface_index]
    if not surface or not surface.valid then return end
    if collapse.is_surface_exempt(surface) then return end

    if roof_support.is_cell_protected(surface, pending.x, pending.y) then return end

    -- Live re-judgment at execution, against the FULL threshold: a pillar
    -- placed during the 2.5s warning saves its spot.
    local epicenter = cell_exists(surface, pending.x, pending.y)
        and collapse.compute_cell(surface, pending.x, pending.y) or 0
    if epicenter <= STRESS_THRESHOLD then
        local force = force_for(surface, pending.player_index, pending.force_index)
        pop_text.spawn(surface, { x = pending.x + 1, y = pending.y + 1 },
            { "diggy.cavern-held-pop" }, { r = 0.3, g = 0.9, b = 0.3 }, force)
        return
    end

    -- The epicenter fails for real: spread to near-threshold neighbors.
    local positions = {}
    for ox = -BASE_RADIUS, BASE_RADIUS do
        for oy = -BASE_RADIUS, BASE_RADIUS do
            local w = BASE_MASK.value_of(ox * ox + oy * oy)
            if w > 0 then
                local cx = 2 * math.floor((pending.x + ox) * 0.5)
                local cy = 2 * math.floor((pending.y + oy) * 0.5)
                local key = cell_key(cx, cy)
                if positions[key] == nil then
                    local value = cell_exists(surface, cx, cy)
                        and collapse.compute_cell(surface, cx, cy) or 0
                    positions[key] = not roof_support.is_cell_protected(surface, cx, cy)
                        and value >= STRESS_THRESHOLD - w * COLLAPSE_MASK_FACTOR
                        and { x = cx, y = cy } or false
                end
            end
        end
    end

    local any = false
    for _, v in pairs(positions) do
        if v then any = true end
    end
    if not any then return end

    surface.create_entity { name = "big-explosion", position = { pending.x, pending.y } }

    local rocks = 0
    local seed = surface.map_gen_settings.seed
    for _, cell in pairs(positions) do
        if cell then
            rocks = rocks + fill_cell(surface, cell.x, cell.y, NORMAL_COLLAPSE_DENSITY, seed)
        end
    end

    -- Sibling pendings whose cell this collapse just filled are part of it:
    -- consume them so they never claim to have held.
    for _, p in pairs(storage.pending_collapses) do
        if p.surface_index == pending.surface_index and positions[cell_key(p.x, p.y)] then
            p.consumed = true
        end
    end

    if rocks > 0 then
        log_collapse(pending.surface_index, pending.x, pending.y)
        local force = force_for(surface, pending.player_index, pending.force_index)
        pop_text.spawn(surface, { x = pending.x + 1, y = pending.y + 1 },
            { "diggy.cavern-collapse-pop" }, { r = 1, g = 0.15, b = 0.05 }, force)
        force.print({ "diggy.cave-collapse" })
        if settings.global["diggy-collapse-broadcast"].value then
            local label = cave_teams.team_label(force)
            for _, other in pairs(cave_teams.other_team_forces(force)) do
                other.print({ "diggy.cave-collapse-other", label })
            end
        end
        local target = surface.create_entity {
            name = "diggy-rubble",
            position = { pending.x + 0.5, pending.y + 0.5 },
            force = "neutral",
        }
        if target then
            for _, player in pairs(force.connected_players) do
                player.add_custom_alert(target, { type = "item", name = "stone" }, { "diggy.cave-collapse" }, true)
            end
            target.destroy()
        end
        -- New rubble changed the geometry: refresh markers around the site.
        collapse.evaluate_around(surface, { x = pending.x, y = pending.y }, BASE_RADIUS * 2)
    end
end

-- Cavern collapse: sparse (~55%) over the given cells, live re-checked —
-- cells pillared back under threshold during the countdown are spared.
function collapse.sparse_collapse(surface, cells, force, seed)
    if collapse.is_surface_exempt(surface) then return 0 end
    if surface and surface.valid and type(surface.name) == "string"
        and surface.name:sub(1, #"the-cave-shelter-interior-") == "the-cave-shelter-interior-" then
        return 0
    end
    if not collapse.available_for(force) then return 0 end
    local live = {}
    for _, cell in pairs(cells) do
        if not roof_support.is_cell_protected(surface, cell.x, cell.y)
            and collapse.compute_cell(surface, cell.x, cell.y) > STRESS_THRESHOLD then
            live[#live + 1] = cell
        end
    end
    if #live == 0 then return 0 end

    local rocks = 0
    for _, cell in pairs(live) do
        rocks = rocks + fill_cell(surface, cell.x, cell.y, CAVERN_COLLAPSE_DENSITY, seed)
    end
    if rocks > 0 then
        log_collapse(surface.index, live[1].x, live[1].y)
        if force then force.print({ "diggy.cavern-collapsed" }) end
        collapse.evaluate_around(surface, { x = live[1].x, y = live[1].y }, BASE_RADIUS * 3)
    end
    return rocks
end

-- Per-tick telegraph refresh; a single length check when nothing pends.
-- Each box tracks its cell's live severity tint — supports placed against
-- the clock visibly cool it from red toward yellow.
function collapse.tick()
    if collapses_disabled() then return end
    local telegraphs = storage.telegraphs
    if not telegraphs or #telegraphs == 0 then return end
    local now = game.tick
    for i = 1, #telegraphs do
        local t = telegraphs[i]
        if t.timer_id then
            local obj = rendering.get_object_by_id(t.timer_id)
            if obj then
                obj.text = string.format("%.1f", math.max(0, t.at_tick - now) / 60)
            end
        end
        local sx = stress_cache[t.surface_index]
        local col = sx and sx[t.x]
        local value = col and col[t.y]
        if value and t.box_id then
            local box = rendering.get_object_by_id(t.box_id)
            if box then box.color = warn_tint(value) end
        end
    end
end

-- The only timer in the mod: a 0.5s heartbeat that fires pending collapses.
-- Consumed entries (buried by a sibling collapse) leave silently: their
-- spot already fell as part of that collapse — it did not "hold".
function collapse.cleanup_disabled_state()
    if not collapses_disabled() then return end
    if not storage.collapse_warning_sprite_cleanup_done
        or (storage.warn_renders and next(storage.warn_renders)) then
        clear_warning_markers()
    end
    local pending = storage.pending_collapses or {}
    for i = #pending, 1, -1 do
        collapse.untelegraph(pending[i].telegraph)
        table.remove(pending, i)
    end
    local telegraphs = storage.telegraphs or {}
    for i = #telegraphs, 1, -1 do
        collapse.untelegraph(telegraphs[i])
    end
end

-- Retire only structural roof jobs on exempt underground surfaces. Mission
-- deadlines, map contents, previous rubble and parent-map jobs are untouched.
function collapse.cleanup_exempt_state()
    local pending = storage.pending_collapses or {}
    for i = #pending, 1, -1 do
        if collapse.is_surface_exempt(game.surfaces[pending[i].surface_index]) then
            collapse.untelegraph(pending[i].telegraph)
            table.remove(pending, i)
        end
    end
    local countdowns = storage.cavern_countdowns or {}
    for i = #countdowns, 1, -1 do
        if collapse.is_surface_exempt(game.surfaces[countdowns[i].surface_index]) then
            for _, cell in pairs(countdowns[i].cells or {}) do
                collapse.untelegraph(cell.telegraph)
            end
            table.remove(countdowns, i)
        end
    end
    -- Also clear orphaned roof markers from old saves, without touching any
    -- countdown labels belonging to the timed cave missions themselves.
    local telegraphs = storage.telegraphs or {}
    for i = #telegraphs, 1, -1 do
        if collapse.is_surface_exempt(game.surfaces[telegraphs[i].surface_index]) then
            collapse.untelegraph(telegraphs[i])
        end
    end
end

function collapse.on_heartbeat()
    if collapses_disabled() then
        collapse.cleanup_disabled_state()
        return
    end
    -- Same-version test builds may not raise on_configuration_changed. Retire
    -- both registered and orphaned advisory triangles on the first heartbeat.
    if not storage.collapse_warning_sprite_cleanup_done
        or (storage.warn_renders and next(storage.warn_renders)) then
        clear_warning_markers()
    end
    local pending = storage.pending_collapses
    if not pending or #pending == 0 then return end
    local now = game.tick
    for i = #pending, 1, -1 do
        local p = pending[i]
        if p.consumed or collapse.is_surface_exempt(game.surfaces[p.surface_index])
            or roof_support.is_cell_protected(game.surfaces[p.surface_index], p.x, p.y) then
            collapse.untelegraph(p.telegraph)
            table.remove(pending, i)
        elseif p.at_tick <= now then
            local job = table.remove(pending, i)
            collapse.untelegraph(job.telegraph)
            execute(job)
        end
    end
end

return collapse
