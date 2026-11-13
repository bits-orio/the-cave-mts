-- The Cave: research-gated Underground Belt Reach prototypes.
--
-- Level 0 uses Factorio's official underground-belt prototypes. Levels 1-7
-- use a distinct entity prototype for every official belt tier. Each level has
-- its own complete native Upgrade Planner row:
--
--   yellow Ln -> red Ln -> blue Ln -> Turbo Ln
--
-- The entity variants are deliberately NOT prototype-hidden: Factorio excludes
-- hidden entity prototypes from normal Upgrade Planner selection. Their cursor
-- items remain hidden, and Factoriopedia redirects to the
-- official entity, so players still craft and handle only the official items.

local LEVEL_BONUS = { 2, 4, 5, 6, 7, 8, 9 }
local OFFICIAL = {
    "underground-belt",
    "fast-underground-belt",
    "express-underground-belt",
    "turbo-underground-belt",
}
local OFFICIAL_SET = {}
for _, name in ipairs(OFFICIAL) do OFFICIAL_SET[name] = true end

local function entity_variant_name(base_name, level)
    return "the-cave-ubr-" .. base_name .. "-" .. tostring(level)
end

local function item_variant_name(base_name, level)
    return "the-cave-ubr-item-" .. base_name .. "-" .. tostring(level)
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
    if not has_flag(flags, wanted) then flags[#flags + 1] = wanted end
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
    local entity = data.raw["underground-belt"] and data.raw["underground-belt"][entity_name]
    local explicit = entity and entity.placeable_by
    if explicit then
        local placement = explicit.item and explicit or explicit[1]
        if placement and placement.item then
            for prototype_type, group in pairs(data.raw) do
                local item = type(group) == "table" and group[placement.item] or nil
                if item and item.stack_size then
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

local raw_entities = data.raw["underground-belt"]
if not raw_entities then return end

-- First create every level/tier entity and its hidden placement item.
for _, base_name in ipairs(OFFICIAL) do
    local base_entity = raw_entities[base_name]
    if base_entity and base_entity.max_distance then
        local item_type, base_item, placer = item_that_places(base_name)
        if item_type and base_item and placer then
            local fast_replaceable_group = base_entity.fast_replaceable_group or base_name

            for level, bonus in ipairs(LEVEL_BONUS) do
                local entity_name = entity_variant_name(base_name, level)
                local cursor_item_name = item_variant_name(base_name, level)

                local variant = table.deepcopy(base_entity)
                variant.name = entity_name
                variant.localised_name = base_entity.localised_name or { "entity-name." .. base_name }
                variant.localised_description = base_entity.localised_description
                variant.order = (base_entity.order or base_name)
                    .. "-the-cave-ubr-" .. string.format("%02d", level)
                variant.max_distance = base_entity.max_distance + bonus
                variant.fast_replaceable_group = fast_replaceable_group
                variant.placeable_by = table.deepcopy(placer)
                variant.next_upgrade = nil -- assigned in the second pass below

                -- Native Upgrade Planner requires the source entity prototype to
                -- be visible/upgradable. Keep only Factoriopedia/internal UI hidden.
                variant.hidden = false
                variant.hidden_in_factoriopedia = true
                variant.factoriopedia_alternative = base_name
                variant.deconstruction_alternative = base_name
                variant.flags = add_flag(base_entity.flags, "not-in-made-in")

                local mining_time = 0.1
                if base_entity.minable and base_entity.minable.mining_time then
                    mining_time = base_entity.minable.mining_time
                end
                variant.minable = {
                    mining_time = mining_time,
                    result = placer.item,
                }

                raw_entities[entity_name] = variant

                local raw_items = data.raw[item_type]
                if raw_items then
                    local cursor_item = table.deepcopy(base_item)
                    cursor_item.name = cursor_item_name
                    cursor_item.place_result = entity_name
                    cursor_item.localised_name = base_item.localised_name or { "item-name." .. placer.item }
                    cursor_item.localised_description = base_item.localised_description
                    cursor_item.order = (base_item.order or placer.item)
                        .. "-the-cave-ubr-cursor-" .. string.format("%02d", level)
                    cursor_item.hidden = true
                    cursor_item.hidden_in_factoriopedia = true
                    cursor_item.flags = remove_flag(base_item.flags, "primary-place-result")
                    cursor_item.flags = remove_flag(cursor_item.flags, "only-in-cursor")
                    raw_items[cursor_item_name] = cursor_item
                end
            end
        end
    end
end

-- Then connect each reach level to its own complete native tier upgrade row.
-- The target variant uses the normal visible item of its official tier through
-- placeable_by, satisfying Factorio's next_upgrade validation and robot request.
for _, base_name in ipairs(OFFICIAL) do
    local base_entity = raw_entities[base_name]
    local next_base = base_entity and base_entity.next_upgrade
    if type(next_base) == "string" and OFFICIAL_SET[next_base] and raw_entities[next_base] then
        for level = 1, #LEVEL_BONUS do
            local source = raw_entities[entity_variant_name(base_name, level)]
            local target_name = entity_variant_name(next_base, level)
            if source and raw_entities[target_name] then
                source.next_upgrade = target_name
            end
        end
    end
end
