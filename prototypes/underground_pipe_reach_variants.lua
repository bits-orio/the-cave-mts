-- The Cave: research-gated Underground Pipe Reach prototypes.
--
-- The official pipe-to-ground prototype is never modified. Level 0 therefore
-- keeps Factorio's native 10-tile reach and native placement guide. Each
-- researched level uses a hidden copy of both the item and entity with its own
-- real max_underground_distance.
--
-- Hidden placement stacks are normalised at inventory/UI boundaries. Inventories, mining, smart pipette, blueprints
-- and construction robots continue to use the original Factorio item.

local LEVEL_BONUS = { 5, 10, 15, 20, 25, 30, 35 }
local BASE_NAME = "pipe-to-ground"

local function entity_variant_name(level)
    return "the-cave-upr-" .. BASE_NAME .. "-" .. tostring(level)
end

local function item_variant_name(level)
    return "the-cave-upr-item-" .. BASE_NAME .. "-" .. tostring(level)
end

local function copy_flags(flags)
    return table.deepcopy(flags or {})
end

local function has_flag(flags, wanted)
    for _, flag in pairs(flags or {}) do
        if flag == wanted then return true end
    end
    return false
end

local function add_flag(flags, wanted)
    flags = copy_flags(flags)
    if not has_flag(flags, wanted) then
        flags[#flags + 1] = wanted
    end
    return flags
end

local function remove_flag(flags, unwanted)
    local result = {}
    for _, flag in pairs(flags or {}) do
        if flag ~= unwanted then result[#result + 1] = flag end
    end
    return result
end

local function item_that_places(entity_name)
    local entity = data.raw["pipe-to-ground"] and data.raw["pipe-to-ground"][entity_name]
    local explicit = entity and entity.placeable_by
    if explicit then
        local placement = explicit.item and explicit or explicit[1]
        if placement and placement.item then
            for prototype_type, group in pairs(data.raw) do
                local item = type(group) == "table" and group[placement.item] or nil
                if item and item.stack_size and item.place_result == entity_name then
                    return prototype_type, item, {
                        item = placement.item,
                        count = placement.count or 1,
                    }
                end
            end
        end
    end

    for prototype_type, group in pairs(data.raw) do
        if type(group) == "table" then
            for _, prototype in pairs(group) do
                if type(prototype) == "table"
                    and prototype.name
                    and prototype.stack_size
                    and prototype.place_result == entity_name
                then
                    return prototype_type, prototype, { item = prototype.name, count = 1 }
                end
            end
        end
    end

    return nil, nil, nil
end

local function add_reach_bonus(fluid_box, bonus)
    if not (fluid_box and fluid_box.pipe_connections) then return false, nil end

    local changed = false
    local maximum = nil
    for _, connection in pairs(fluid_box.pipe_connections) do
        if type(connection) == "table" and type(connection.max_underground_distance) == "number" then
            connection.max_underground_distance = connection.max_underground_distance + bonus
            maximum = math.max(maximum or 0, connection.max_underground_distance)
            changed = true
        end
    end
    return changed, maximum
end

local raw_entities = data.raw["pipe-to-ground"]
local base_entity = raw_entities and raw_entities[BASE_NAME]
if not (base_entity and base_entity.fluid_box) then return end

local item_type, base_item, placer = item_that_places(BASE_NAME)
if not (item_type and base_item and placer) then return end

for level, bonus in ipairs(LEVEL_BONUS) do
    local entity_name = entity_variant_name(level)
    local cursor_item_name = item_variant_name(level)

    if not raw_entities[entity_name] then
        local variant = table.deepcopy(base_entity)
        variant.name = entity_name
        variant.localised_name = base_entity.localised_name or { "entity-name." .. BASE_NAME }
        variant.localised_description = base_entity.localised_description
        variant.order = (base_entity.order or BASE_NAME)
            .. "-the-cave-upr-" .. string.format("%02d", level)
        variant.placeable_by = table.deepcopy(placer)
        variant.next_upgrade = base_entity.next_upgrade
        variant.hidden = true
        variant.hidden_in_factoriopedia = true
        variant.factoriopedia_alternative = BASE_NAME
        variant.flags = add_flag(base_entity.flags, "not-in-made-in")

        variant.fluid_box = table.deepcopy(base_entity.fluid_box)
        local changed, maximum = add_reach_bonus(variant.fluid_box, bonus)
        if changed then
            local mining_time = 0.1
            if base_entity.minable and base_entity.minable.mining_time then
                mining_time = base_entity.minable.mining_time
            end
            variant.minable = {
                mining_time = mining_time,
                result = placer.item,
            }

            -- Preserve any range marker supplied by another mod, but move it to
            -- the real researched endpoint when it uses a simple vector offset.
            local visual = variant.radius_visualisation_specification
            if visual and visual.offset and maximum then
                local x = visual.offset[1] or visual.offset.x or 0
                local y = visual.offset[2] or visual.offset.y or 0
                if math.abs(y) >= math.abs(x) then
                    visual.offset = { x, y < 0 and -maximum or maximum }
                elseif math.abs(x) > 0 then
                    visual.offset = { x < 0 and -maximum or maximum, y }
                end
            end

            raw_entities[entity_name] = variant
        end
    end

    local raw_items = data.raw[item_type]
    if raw_entities[entity_name] and raw_items and not raw_items[cursor_item_name] then
        local cursor_item = table.deepcopy(base_item)
        cursor_item.name = cursor_item_name
        cursor_item.place_result = entity_name
        cursor_item.localised_name = base_item.localised_name or { "item-name." .. placer.item }
        cursor_item.localised_description = base_item.localised_description
        cursor_item.order = (base_item.order or placer.item)
            .. "-the-cave-upr-cursor-" .. string.format("%02d", level)
        cursor_item.hidden = true
        cursor_item.hidden_in_factoriopedia = true
        cursor_item.flags = remove_flag(base_item.flags, "primary-place-result")
        cursor_item.flags = remove_flag(cursor_item.flags, "only-in-cursor")
        raw_items[cursor_item_name] = cursor_item
    end
end
