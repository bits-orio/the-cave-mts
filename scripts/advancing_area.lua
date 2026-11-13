-- Presentation and one-time supplies for the Advancing Collapse clearing.
local clearing = require("scripts.advancing_clearing")
local recovery = require("scripts.advancing_recovery")
local cave_teams = require("scripts.cave_teams")
local mirror = require("scripts.lib.mirror")
local area = {}
local start_api
local GREEN = { r = 0.15, g = 1, b = 0.28, a = 1 }
local RED = { r = 1, g = 0.08, b = 0.04, a = 1 }
local PANEL_TEXT = "PREPARATION ZONE\nGather resources, build power and prepare your train and rails.\nMove your train NORTH past the green boundary before the two-hour countdown ends.\nThe boundary turns red during combat. The full-width, five-chunk-deep area SOUTH of it spawns enemies while the collapse moves north.\nDuring Recovery Break the boundary turns green, the collapse pauses, and enemies inside are removed."

function area.configure_start_api(api) start_api = api end

local function object(id)
    if not id then return nil end
    local obj = rendering.get_object_by_id(id)
    return obj and obj.valid and obj or nil
end

function area.destroy_visuals(state)
    if not state then return end
    for _, key in ipairs { "area_outline_id", "area_label_id" } do
        local obj = object(state[key])
        if obj then obj.destroy() end
        state[key] = nil
    end
    state.area_visual_key = nil
end

local AREA_LABELS = {
    ["the-cave-advancing-collapse.area-preparation"] = true,
    ["the-cave-advancing-collapse.area-recovery"] = true,
    ["the-cave-advancing-collapse.area-combat"] = true,
}

local function force_key(obj)
    local indexes = {}
    for _, force in pairs(obj.forces or {}) do indexes[#indexes + 1] = force.index end
    table.sort(indexes)
    return table.concat(indexes, ",")
end

-- Position targets outlive surface.clear(false). Older soft resets erased
-- their saved IDs, so recover only this feature's labels and paired outlines.
-- This scan runs on configuration changes/reset, never in the tick loop.
function area.destroy_all_visuals(root)
    local objects = rendering.get_all_objects("the-cave")
    local labels = {}
    for _, obj in pairs(objects) do
        if obj.valid and obj.type == "text" then
            local text = obj.text
            if type(text) == "table" and AREA_LABELS[text[1]] then
                local target = obj.target
                labels[#labels + 1] = {
                    object = obj, position = target and not target.entity and target.position,
                    surface_index = obj.surface.index, forces = force_key(obj), color = obj.color,
                }
            end
        end
    end
    for _, obj in pairs(objects) do
        if obj.valid and (obj.type == "line" or (obj.type == "rectangle" and not obj.filled))
            and (obj.width == 4 or obj.width == 3)
            and obj.render_mode == "game" and not obj.draw_on_ground and not obj.only_in_alt_mode then
            local lt = obj.type == "line" and obj.from or obj.left_top
            local rb = obj.type == "line" and obj.to or obj.right_bottom
            local left = lt and not lt.entity and lt.position
            local right = rb and not rb.entity and rb.position
            local legacy = left and right and right.y-left.y==160
                and ((left.x==-64 and right.x==64) or (left.x==-48 and right.x==48))
            local boundary = left and right and obj.type=="line" and left.y==right.y
                and left.x==-clearing.WIDTH/2 and right.x==clearing.WIDTH/2
            if legacy or boundary then
                local color, forces = obj.color, force_key(obj)
                for _, label in ipairs(labels) do
                    local position, tint = label.position, label.color
                    if position and position.x == 0
                        and (position.y == left.y + 2 or position.y == left.y - 2)
                        and label.surface_index == obj.surface.index and label.forces == forces
                        and color.r == tint.r and color.g == tint.g and color.b == tint.b and color.a == tint.a then
                        obj.destroy()
                        break
                    end
                end
            end
        end
    end
    for _, label in ipairs(labels) do label.object.destroy() end
    for _, state in pairs(root and root.surfaces or {}) do area.destroy_visuals(state) end
end

local function clock(ticks)
    local seconds = math.max(0, math.ceil(ticks / 60))
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600),
        math.floor(seconds / 60) % 60, seconds % 60)
end

function area.update_visuals(surface, state, root, tick)
    local mode = state.phase == "countdown" and "preparation"
        or recovery.is_resting(state) and "recovery" or "combat"
    local left, right, top, bottom = clearing.terrain_bounds(state)
    local remaining = mode == "preparation" and (state.remaining_ticks or 0)
        or mode == "recovery" and math.max(0, state.assault.break_until_tick - tick) or 0
    local key = "4:" .. mode .. ":" .. bottom .. ":" .. top .. ":" .. math.ceil(remaining / 60)
    local outline, label = object(state.area_outline_id), object(state.area_label_id)
    if outline and outline.type ~= "line" then
        outline.destroy(); state.area_outline_id=nil; outline=nil
    end
    if outline and label and state.area_visual_key == key then return end
    local color = mode == "combat" and RED or GREEN
    local force = cave_teams.surface_owner_force(surface)
    local text = { "the-cave-advancing-collapse.area-" .. mode, clock(remaining) }
    if not outline then
        outline = rendering.draw_line {
            surface = surface, from = {left, top}, to = {right, top},
            color = color, width = 4, forces = force and {force} or {},
            only_in_alt_mode = false, draw_on_ground = false, render_mode = "game",
        }
        state.area_outline_id = outline.id
    else
        outline.from, outline.to = {left, top}, {right, top}
        outline.color = color
        outline.width = 4
    end
    if not label then
        label = rendering.draw_text {
            surface = surface, target = {0, top + 2}, text = text, color = color,
            alignment = "center", vertical_alignment = "top", scale = 2,
            forces = {force}, only_in_alt_mode = false, draw_on_ground = false,
            render_mode = "game",
        }
        state.area_label_id = label.id
    else
        label.target = {0, top + 2}
        label.vertical_alignment = "top"
        label.scale = 2
        label.color, label.text = color, text
    end
    state.area_visual_key = key
end

local function dry(tile)
    if not (tile and tile.valid) then return false end
    local name = tile.name
    return name ~= "out-of-map" and not name:find("water", 1, true)
        and not name:find("ocean", 1, true) and not name:find("lava", 1, true)
end

-- Never erase or move anything to make supplies fit. The dry halo supplies
-- room for a pump, pipe, player access, and the pumpjack footprint.
local function empty_dry_square(surface, state, x, y, width, margin, anchor)
    local left, right, top, bottom = clearing.bounds(state)
    local x1, y1, x2, y2 = x - margin, y - margin, x + width + margin, y + width + margin
    if x1 < left + 2 or x2 > right - 2 or y1 < top + 2 or y2 > bottom - 2 then return false end
    -- Reserve the starter train pad and a northbound exit corridor.
    if x1 < anchor.x + 24 and x2 > anchor.x - 24
        and y1 < anchor.y + 14 and y2 > anchor.y - 14 then return false end
    if x1 < anchor.x + 12 and x2 > anchor.x - 12 then return false end
    if #surface.find_entities_filtered { area = {{x1, y1}, {x2, y2}}, limit = 1 } > 0 then return false end
    for ty = y1, y2 - 1 do
        for tx = x1, x2 - 1 do
            if not dry(surface.get_tile(tx, ty)) then return false end
        end
    end
    return true
end

local function candidates(state, preferred_x, preferred_y)
    local left, right, top, bottom = clearing.bounds(state)
    local list = { {x=preferred_x, y=preferred_y} }
    for y = top + 10, bottom - 10, 4 do
        for x = left + 10, right - 10, 4 do list[#list + 1] = {x=x, y=y} end
    end
    table.sort(list, function(a, b)
        local da = (a.x-preferred_x)^2 + (a.y-preferred_y)^2
        local db = (b.x-preferred_x)^2 + (b.y-preferred_y)^2
        if da ~= db then return da < db end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    return list
end

local function pump_position(surface, force, x, y)
    if not prototypes.entity["offshore-pump"] then return nil end
    for _, direction in ipairs { defines.direction.north, defines.direction.east,
        defines.direction.south, defines.direction.west } do
        -- Both whole-tile and half-tile centres cover rotated pump footprints.
        for ty = y - 2, y + 5, 0.5 do
            for tx = x - 2, x + 5, 0.5 do
                local position = {x=tx, y=ty}
                if surface.can_place_entity { name="offshore-pump", position=position,
                    direction=direction, force=force } then
                    return {position=position, direction=direction}
                end
            end
        end
    end
end

local function place_pond(surface, state, force, anchor)
    if not prototypes.tile["water"] then return end
    for _, p in ipairs(candidates(state, math.floor(anchor.x) - 36, math.floor(anchor.y) - 38)) do
        if empty_dry_square(surface, state, p.x, p.y, 4, 3, anchor) then
            local water, previous = {}, {}
            for y = p.y, p.y + 3 do
                for x = p.x, p.x + 3 do
                    water[#water + 1] = {name="water", position={x,y}}
                    previous[#previous + 1] = {name=surface.get_tile(x,y).name, position={x,y}}
                end
            end
            surface.set_tiles(water, false, false, false, false)
            local pump = pump_position(surface, force, p.x, p.y)
            if pump then
                mirror.set_tiles(surface, water)
                return {x=p.x, y=p.y, width=4, pump=pump}
            end
            -- Restore the empty ground if another mod's pump cannot use it.
            surface.set_tiles(previous, false, false, false, false)
        end
    end
end

local function place_oil(surface, state, force, anchor)
    if not (prototypes.entity["crude-oil"] and prototypes.entity["pumpjack"]) then return end
    for _, p in ipairs(candidates(state, math.floor(anchor.x) + 32, math.floor(anchor.y) - 36)) do
        if empty_dry_square(surface, state, p.x - 1, p.y - 1, 3, 2, anchor) then
            local position = {x=p.x + 0.5, y=p.y + 0.5}
            if surface.can_place_entity {name="crude-oil", position=position} then
                local oil = surface.create_entity {name="crude-oil", position=position, amount=300000}
                if oil and oil.valid then
                    if surface.can_place_entity {name="pumpjack", position=position, force=force} then
                        return position
                    end
                    -- Remove only the well just created by this attempt; all
                    -- existing resources and player entities remain untouched.
                    oil.destroy()
                end
            end
        end
    end
end

local function place_panel(surface, state, force, anchor)
    if not prototypes.entity["display-panel"] then return end
    for _, p in ipairs(candidates(state, math.floor(anchor.x) - 28, math.floor(anchor.y) - 18)) do
        if empty_dry_square(surface, state, p.x, p.y, 1, 2, anchor) then
            local position = {x=p.x + 0.5, y=p.y + 0.5}
            if surface.can_place_entity {name="display-panel", position=position, force=force} then
                local panel = surface.create_entity {name="display-panel", position=position, force=force}
                if panel and panel.valid then
                    panel.destructible = false
                    panel.minable_flag = false
                    panel.operable = false
                    panel.display_panel_icon = {type="virtual", name="signal-info"}
                    -- 2.0 accepts LocalisedString; newer APIs require a string.
                    local localized = pcall(function()
                        panel.display_panel_text = {"the-cave-advancing-collapse.start-panel"}
                    end)
                    if not localized then panel.display_panel_text = PANEL_TEXT end
                    panel.display_panel_always_show = true
                    panel.display_panel_show_in_chart = false
                    return panel
                end
            end
        end
    end
end

function area.prepare_supplies(surface, state, root, tick)
    if state.phase ~= "countdown" or not clearing.is_ready(state) then return end
    local supplies = state.start_supplies
    if not supplies then supplies = {}; state.start_supplies = supplies end
    if supplies.complete or tick < (supplies.next_attempt_tick or 0) then return end
    local force = cave_teams.surface_owner_force(surface)
    if not (force and force.valid) then return end
    -- Wait until this team's train has been placed so its pad cannot cover the
    -- pond. Standalone Advancing Collapse uses the force's spawn as its anchor.
    local anchor = start_api and start_api.get_train_center(surface, force)
    if not anchor and start_api and start_api.train_enabled() then return end
    anchor = anchor or force.get_spawn_position(surface)
    supplies.next_attempt_tick = tick + 300
    if not supplies.pond then supplies.pond = place_pond(surface, state, force, anchor) end
    if not supplies.oil then supplies.oil = place_oil(surface, state, force, anchor) end
    -- Place the panel last, after both resource footprints are known.
    if supplies.pond and supplies.oil and not supplies.panel_placed then
        local panel = place_panel(surface, state, force, anchor)
        if panel then
            supplies.panel_placed = true
            supplies.panel_position = {x=panel.position.x, y=panel.position.y}
        end
    end
    supplies.complete = supplies.pond ~= nil and supplies.oil ~= nil and supplies.panel_placed == true
end

return area
