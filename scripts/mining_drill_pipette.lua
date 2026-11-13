-- Market drills remain usable by hand and by pipetting placed drills. Only
-- native resource pipetting is corrected; no tick handler or saved state.
local mining_drill_pipette = {}
local STANDARD_DRILLS = {"big-mining-drill", "electric-mining-drill", "burner-mining-drill"}

local function prototype_name(value)
    if type(value) == "string" then return value end
    return value and value.name
end

local function is_market_drill(name)
    return type(name) == "string" and name:match("^the%-cave%-electric%-mining%-drill%-mk[1-5]$") ~= nil
end

local function can_mine(drill, resource)
    if not (drill and drill.resource_categories and drill.resource_categories[resource.resource_category]) then
        return false
    end
    -- Filter Mining Drills changes categories to resource names. Inspect the
    -- loaded prototypes so this also works with that setting disabled.
    if resource.mineable_properties.required_fluid then
        for _, box in pairs(drill.fluidbox_prototypes) do
            if box.production_type == "input" or box.production_type == "input-output" then return true end
        end
        return false
    end
    return true
end

local function choose_drill(player, resource, allow_ghost, ghost_quality)
    local inventory = player.get_main_inventory()
    local contents = inventory and inventory.valid and inventory.get_contents() or {}
    local ghost_candidate
    for _, name in ipairs(STANDARD_DRILLS) do
        if prototypes.item[name] and can_mine(prototypes.entity[name], resource) then
            local best_quality, best_level
            for _, item in pairs(contents) do
                if item.name == name and item.count > 0 then
                    local quality_name = prototype_name(item.quality) or "normal"
                    local quality = prototypes.quality[quality_name]
                    if quality and (not best_level or quality.level > best_level
                        or (quality.level == best_level and quality_name < best_quality)) then
                        best_quality, best_level = quality_name, quality.level
                    end
                end
            end
            -- Prefer an owned standard drill to a ghost of a later-tier drill.
            if best_quality then return {name = name, quality = best_quality} end
            local recipe = player.force.recipes[name]
            if allow_ghost and not ghost_candidate and recipe and recipe.enabled then
                ghost_candidate = {name = name, quality = ghost_quality}
            end
        end
    end
    return ghost_candidate
end

function mining_drill_pipette.on_player_pipette(event)
    if not is_market_drill(event.item and event.item.name) then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local selected = player.selected
    if not (selected and selected.valid and selected.type == "resource") then return end

    local cursor = player.cursor_stack
    local has_stack = cursor and cursor.valid_for_read
    local ghost = player.cursor_ghost
    local current_name = has_stack and cursor.name or (ghost and prototype_name(ghost.name))
    -- A repeated event, another handler or manual selection may have changed it.
    if not is_market_drill(current_name) then return end

    local allow_ghost = not has_stack and ghost ~= nil
    local quality = prototype_name(event.quality) or "normal"
    local candidate = choose_drill(player, selected.prototype, allow_ghost or event.used_cheat_mode, quality)

    if has_stack and event.used_cheat_mode then
        -- This stack was created by native cheat pipetting, not taken from the
        -- inventory. Do not turn it into a free market purchase on clear_cursor.
        cursor.clear()
    end
    -- Return any owned MK stack through the engine, including its quality and
    -- hand slot. Never delete or overwrite it if the cursor cannot be cleared.
    if not player.clear_cursor() then return end
    if candidate then
        -- Using a named standard entity cannot select an MK resource variant.
        -- The recursive pipette event exits at the item-name guard above.
        player.pipette(prototypes.entity[candidate.name], candidate.quality, allow_ghost)
    end
end

return mining_drill_pipette
