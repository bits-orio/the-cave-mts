local settings = require("scripts.game_settings").proxy(settings)

-- Shared zone model for The Cave: Advancing Collapse.
--
-- New zones use a northbound 510 x 1024 layout and the existing
-- 132-slot repeating zone pool, but deliberately owns no train, factory, wave
-- defence, market, or RPG state. Planet families enter the weighted pool only
-- after their normal planet-discovery research has completed.
local hash = require("scripts.lib.hash")
local cave_worlds = require("scripts.cave_worlds")

local zones = {}

zones.ZONE_WIDTH = 510
zones.ZONE_DEPTH = 1024
zones.LEGACY_ZONE_DEPTH = 704
zones.ZONE_POOL_SIZE = 132
zones.COLLAPSE_START_Y = 130
zones.COLLAPSE_MAX_LINE_SIZE = 620
zones.SOUTH_GUARD_LINE_Y = 64
zones.SOUTH_VOID_Y = 120

local SETTING_NAME = "the-cave-advancing-collapse"
local NAUVIS_PICK_STREAM = 7701
local VARIANT_STREAM = 7702
local SPECIAL_PICK_STREAM = 7703
local NAUVIS_BUFFER_STREAM = 7704

local PLANET_TECHS = {
    ["planet-discovery-vulcanus"] = "vulcanus",
    ["planet-discovery-gleba"] = "gleba",
    ["planet-discovery-fulgora"] = "fulgora",
    ["planet-discovery-aquilo"] = "aquilo",
}

local BASE_VARIANTS = {
    { name = "zone_1", palette = "dirt", weight = 100 },
    { name = "zone_2", palette = "grass", weight = 100 },
    { name = "zone_3", palette = "red-desert", weight = 100 },
    { name = "zone_4", palette = "sand", weight = 100 },
    { name = "zone_5", palette = "dry", weight = 100 },
    { name = "zone_7_garden", palette = "garden", weight = 100 },
    { name = "zone_9", palette = "stone", weight = 100 },
    { name = "zone_11", palette = "dirt-dark", weight = 100 },
    { name = "zone_12", palette = "red-desert-dark", weight = 100 },
    { name = "zone_13", palette = "mixed", weight = 100 },
    { name = "zone_forest_1", palette = "forest", weight = 50 },
    { name = "zone_forest_2", palette = "forest-dark", weight = 50 },
    { name = "zone_10", palette = "forest", weight = 50 },
    { name = "zone_14", palette = "forest-dark", weight = 50 },
    { name = "zone_scrap_1", palette = "scrap", weight = 100 },
    { name = "zone_scrap_2", palette = "scrap-dark", weight = 100 },
}

local PLANET_VARIANTS = {
    gleba = {
        { name = "zone_gleba_1", palette = "gleba-wet", weight = 120 },
        { name = "zone_gleba_2", palette = "gleba-dry", weight = 120 },
        { name = "zone_gleba_forest_1", palette = "gleba-forest", weight = 120 },
        { name = "zone_gleba_forest_2", palette = "gleba-forest", weight = 120 },
    },
    vulcanus = {
        { name = "zone_vulcanus_1", palette = "vulcanus", weight = 120 },
    },
    fulgora = {
        { name = "zone_fulgora_tech_1", palette = "fulgora", weight = 120 },
    },
    aquilo = {
        { name = "zone_aquilo_1", palette = "aquilo", weight = 120 },
    },
}

local function startup_enabled()
    local setting = settings and settings.startup and settings.startup[SETTING_NAME]
    return setting and (setting.value == "enabled" or setting.value == true) or false
end

local function root()
    return storage and storage.the_cave_advancing_collapse or nil
end

local function zone_state()
    local state = root()
    return state and state.zones or nil
end

local function space_age_active()
    return script and script.active_mods and script.active_mods["space-age"] ~= nil
end

local function force_has_research(force, technology_name)
    if not (force and force.valid and force.technologies) then return false end
    local technology = force.technologies[technology_name]
    return technology and technology.researched or false
end

local function any_force_has_research(technology_name)
    if not game then return false end
    for _, force in pairs(game.forces) do
        if force_has_research(force, technology_name) then return true end
    end
    return false
end

local function seed()
    local surface = game and game.surfaces and game.surfaces["nauvis"]
    local settings_table = surface and surface.valid and surface.map_gen_settings
    return settings_table and settings_table.seed or 0
end

local function copy_entry(entry, family)
    return {
        name = entry.name,
        family = family,
        palette = entry.palette,
    }
end

local function choose_nauvis_variant(slot)
    local total = 0
    for _, entry in ipairs(BASE_VARIANTS) do
        total = total + entry.weight
    end
    local roll = hash.range(seed(), slot, total, NAUVIS_PICK_STREAM, 1, total)
    for _, entry in ipairs(BASE_VARIANTS) do
        roll = roll - entry.weight
        if roll <= 0 then
            return copy_entry(entry, "nauvis")
        end
    end
    return copy_entry(BASE_VARIANTS[1], "nauvis")
end

local function unlocked_special_families(state, previous_family)
    local all = {}
    for _, family in ipairs({ "vulcanus", "gleba", "fulgora", "aquilo" }) do
        if state.unlocked[family] then all[#all + 1] = family end
    end
    if #all <= 1 or not previous_family then return all end

    local alternatives = {}
    for _, family in ipairs(all) do
        if family ~= previous_family then alternatives[#alternatives + 1] = family end
    end
    return #alternatives > 0 and alternatives or all
end

local function remove_pending_family(state, allowed)
    local accepted = {}
    for _, family in ipairs(allowed) do accepted[family] = true end
    for index, family in ipairs(state.pending_unlocks) do
        if state.unlocked[family] and accepted[family] then
            table.remove(state.pending_unlocks, index)
            return family
        end
    end
    return nil
end

local function choose_special_family(state, slot, previous_family)
    local candidates = unlocked_special_families(state, previous_family)
    if #candidates == 0 then return nil end

    local pending = remove_pending_family(state, candidates)
    if pending then return pending end

    local index = hash.range(seed(), slot, #candidates, SPECIAL_PICK_STREAM, 1, #candidates)
    return candidates[index]
end

local function preceding_special(state, slot)
    for previous_slot = slot - 1, 1, -1 do
        local previous = state.slots[previous_slot]
        if previous and previous.family ~= "nauvis" then
            return previous_slot, previous.family, slot - previous_slot - 1
        end
    end
    return nil, nil, slot - 1
end

local function required_nauvis_buffer(previous_special_slot)
    if not previous_special_slot then return 1 end
    return hash.range(seed(), previous_special_slot, 2, NAUVIS_BUFFER_STREAM, 1, 2)
end

local choose_family_variant
local assign_slot

assign_slot = function(slot)
    local state = zone_state()
    if not state then return copy_entry(BASE_VARIANTS[1], "nauvis") end
    if state.slots[slot] then return state.slots[slot] end

    -- Northbound exploration normally discovers slots in order. Recursively
    -- assigning a missing predecessor also keeps the one/two-Nauvis buffer
    -- deterministic if a charting command requests a farther chunk first.
    if slot > 1 and not state.slots[slot - 1] then assign_slot(slot - 1) end

    local chosen
    if slot == 1 then
        chosen = choose_nauvis_variant(slot)
    else
        local previous_slot, previous_family, nauvis_count = preceding_special(state, slot)
        local required = required_nauvis_buffer(previous_slot)
        if nauvis_count < required then
            chosen = choose_nauvis_variant(slot)
        else
            local family = choose_special_family(state, slot, previous_family)
            chosen = family and choose_family_variant(family, slot) or choose_nauvis_variant(slot)
        end
    end
    state.slots[slot] = chosen
    return chosen
end

choose_family_variant = function(family, slot)
    local variants = PLANET_VARIANTS[family]
    if not variants or #variants == 0 then return copy_entry(BASE_VARIANTS[1], "nauvis") end
    local index = hash.range(seed(), slot, #variants, VARIANT_STREAM, 1, #variants)
    return copy_entry(variants[index], family)
end


local function refresh_unlocks(state)
    state.unlocked = state.unlocked or {}
    for technology_name, family in pairs(PLANET_TECHS) do
        state.unlocked[family] = space_age_active() and any_force_has_research(technology_name) or false
    end
end

-- The zone family pool is shared by copied worlds. Preserve the same geometry on
-- every main surface by freezing the furthest already-generated old zone once
-- per save. Only chunk metadata is visited, never tiles/entities or each tick.
local function initialize_layout(state, new_world)
    if state.zones.layout then return end
    local last_old = 0
    if not new_world then
        for _, highest in pairs(state.highest_zone_by_force or {}) do
            last_old = math.max(last_old, tonumber(highest) or 0)
        end
        for _, surface in pairs(game and game.surfaces or {}) do
            if zones.is_main_surface(surface) then
                for chunk in surface.get_chunks() do
                    if chunk.x >= -8 and chunk.x <= 7 then
                        local progress = math.max(0, -chunk.y * 32)
                        last_old = math.max(last_old,
                            math.floor(progress / zones.LEGACY_ZONE_DEPTH) + 1)
                    end
                end
            end
        end
    end
    state.zones.layout = { version = 1, legacy_zones = last_old }
end

function zones.initialize(state, new_world)
    if not state then return end
    state.zones = state.zones or {}
    state.zones.slots = state.zones.slots or {}
    state.zones.pending_unlocks = state.zones.pending_unlocks or {}
    state.zones.unlocked = state.zones.unlocked or {}
    initialize_layout(state, new_world == true)
    refresh_unlocks(state.zones)
    state.zones.slots[1] = state.zones.slots[1] or copy_entry(BASE_VARIANTS[1], "nauvis")
end

function zones.repair()
    local state = root()
    if not state then return end
    zones.initialize(state)
end

function zones.setting_enabled()
    return startup_enabled()
end

function zones.is_active()
    local state = root()
    return startup_enabled()
        and state ~= nil
        and state.initialized == true
        and state.blocked_mid_save ~= true
end

function zones.space_age_available()
    return zones.is_active() and space_age_active()
end

function zones.is_main_surface(surface)
    if not (surface and surface.valid and type(surface.name) == "string") then return false end
    return surface.name == "nauvis"
        or cave_worlds.is_copy(surface)
end

function zones.inside_width(x)
    x = math.floor(x)
    local half = zones.ZONE_WIDTH / 2
    return x >= -half and x < half
end

function zones.zone_index_at_y(y)
    local progress = math.max(0, -math.floor(y))
    local state = zone_state()
    local layout = state and state.layout
    -- Before upgrade migration runs, all existing coordinates remain legacy.
    if not layout then return math.floor(progress / zones.LEGACY_ZONE_DEPTH) + 1 end
    local old = layout.legacy_zones
    local boundary = old * zones.LEGACY_ZONE_DEPTH
    if progress < boundary then
        return math.floor(progress / zones.LEGACY_ZONE_DEPTH) + 1
    end
    return old + math.floor((progress - boundary) / zones.ZONE_DEPTH) + 1
end

function zones.zone_area(zone_index)
    zone_index = math.max(1, math.floor(tonumber(zone_index) or 1))
    local half = zones.ZONE_WIDTH / 2
    local state = zone_state()
    local layout = state and state.layout
    local old = layout and layout.legacy_zones or zone_index
    local depth = zone_index <= old and zones.LEGACY_ZONE_DEPTH or zones.ZONE_DEPTH
    local bottom = zone_index <= old and (zone_index - 1) * zones.LEGACY_ZONE_DEPTH
        or old * zones.LEGACY_ZONE_DEPTH + (zone_index - old - 1) * zones.ZONE_DEPTH
    return {
        left_top = {
            x = -half,
            y = -bottom - depth,
        },
        right_bottom = {
            x = half,
            y = -bottom,
        },
    }
end

function zones.first_scheduled_zone()
    local state = zone_state()
    return state and state.layout and (state.layout.legacy_zones + 1) or nil
end

function zones.uses_scheduled_caves(surface, position)
    if not (zones.is_active() and zones.is_main_surface(surface) and position) then return false end
    local first = zones.first_scheduled_zone()
    return first ~= nil and zones.zone_index_at_y(position.y) >= first
end

function zones.zone_at(x, y)
    if not zones.is_active() then return nil end
    local index = zones.zone_index_at_y(y)
    local slot = ((index - 1) % zones.ZONE_POOL_SIZE) + 1
    local assigned = assign_slot(slot)
    return {
        index = index,
        slot = slot,
        name = assigned.name,
        family = assigned.family,
        palette = assigned.palette,
    }
end

function zones.region_at(x, y)
    local zone = zones.zone_at(x, y)
    return zone and zone.family or "nauvis"
end

function zones.is_collapsed(surface, x, y)
    local state = root()
    if not (zones.is_active() and zones.is_main_surface(surface)) then
        return false
    end
    local surface_state = state.surfaces and state.surfaces[surface.index]
    if not surface_state or surface_state.phase ~= "active" then return false end
    local tile_y = math.floor(y)
    if tile_y > surface_state.line_y then return true end
    if tile_y < surface_state.line_y then return false end
    return surface_state.erased_x and surface_state.erased_x[math.floor(x)] == true or false
end

function zones.is_playable(surface, x, y)
    if not (zones.is_active() and zones.is_main_surface(surface)) then return true end
    -- Advancing Collapse is a one-way northbound expedition.  The southern
    -- guard strip ends at Y 120; world digging must never reopen terrain below
    -- that hard cap after the strip has been built.
    return zones.inside_width(x)
        and math.floor(y) < zones.SOUTH_VOID_Y
        and not zones.is_collapsed(surface, x, y)
end

function zones.on_research_finished(event)
    if not (zones.is_active() and space_age_active() and event and event.research) then return nil end
    local family = PLANET_TECHS[event.research.name]
    if not family then return nil end
    local state = zone_state()
    if not state then return nil end
    if not state.unlocked[family] then
        state.unlocked[family] = true
        state.pending_unlocks[#state.pending_unlocks + 1] = family
        return family
    end
    return nil
end

function zones.on_research_reversed(event)
    if not (zones.is_active() and event and event.research) then return end
    local family = PLANET_TECHS[event.research.name]
    if not family then return end
    local state = zone_state()
    if not state then return end
    if any_force_has_research(event.research.name) then return end
    state.unlocked[family] = false
    for index = #state.pending_unlocks, 1, -1 do
        if state.pending_unlocks[index] == family then table.remove(state.pending_unlocks, index) end
    end
end

return zones
