-- The Cave: normal-Factorio fallback for the expansion belt-stacking engine.
--
-- The mod's info.json enables the Space Travel feature flag, so owners of the
-- Space Age expansion can use the real belt-stack engine even while the
-- "space-age" mod itself is disabled. When Space Age is active, its official
-- Stack Inserter and Transport Belt Capacity prototypes are used instead.
if mods["space-age"] then return end

local early_stack_size_setting = settings.startup["the-cave-early-stack-size"]
local early_stack_size_enabled = (not early_stack_size_setting)
    or early_stack_size_setting.value ~= "disabled"
if not early_stack_size_enabled then return end

if not (feature_flags and feature_flags.space_travel) then
    error("[The Cave] Normal-Factorio belt stacking requires the Space Travel feature flag.")
end

local bulk_entity = data.raw.inserter and data.raw.inserter["bulk-inserter"]
local bulk_item = data.raw.item and data.raw.item["bulk-inserter"]
local bulk_recipe = data.raw.recipe and data.raw.recipe["bulk-inserter"]
local capacity_7 = data.raw.technology and data.raw.technology["inserter-capacity-bonus-7"]

if not bulk_entity then error("[The Cave] Base prototype 'bulk-inserter' entity was not found.") end
if not bulk_item then error("[The Cave] Base prototype 'bulk-inserter' item was not found.") end
if not bulk_recipe then error("[The Cave] Base prototype 'bulk-inserter' recipe was not found.") end
if not capacity_7 then error("[The Cave] Base technology 'inserter-capacity-bonus-7' was not found.") end

local prototypes = {}

-- Clone the tested base Bulk Inserter architecture and sounds, then replace
-- its visible arm/platform/icon with the Space Age Stack Inserter artwork.
-- This keeps the normal-mode implementation small while making the two
-- inserters visually distinct.
if not data.raw.inserter["stack-inserter"] then
    local entity = table.deepcopy(bulk_entity)
    entity.name = "stack-inserter"
    entity.localised_name = {"entity-name.stack-inserter"}
    entity.localised_description = {"entity-description.the-cave-stack-inserter"}
    entity.icon = "__the-cave__/graphics/icons/stack-inserter.png"
    entity.icons = nil
    entity.icon_size = 64
    entity.hand_base_picture = {
        filename = "__the-cave__/graphics/entity/stack-inserter/stack-inserter-hand-base.png",
        priority = "extra-high",
        width = 32,
        height = 136,
        scale = 0.25,
    }
    entity.hand_closed_picture = {
        filename = "__the-cave__/graphics/entity/stack-inserter/stack-inserter-hand-closed.png",
        priority = "extra-high",
        width = 112,
        height = 164,
        scale = 0.25,
    }
    entity.hand_open_picture = {
        filename = "__the-cave__/graphics/entity/stack-inserter/stack-inserter-hand-open.png",
        priority = "extra-high",
        width = 134,
        height = 164,
        scale = 0.25,
    }
    entity.hand_closed_shadow = {
        filename = "__the-cave__/graphics/entity/stack-inserter/stack-inserter-hand-closed-shadow.png",
        priority = "extra-high",
        width = 112,
        height = 164,
        scale = 0.25,
    }
    entity.hand_open_shadow = {
        filename = "__the-cave__/graphics/entity/stack-inserter/stack-inserter-hand-open-shadow.png",
        priority = "extra-high",
        width = 134,
        height = 164,
        scale = 0.25,
    }
    entity.platform_picture = {
        sheet = {
            filename = "__the-cave__/graphics/entity/stack-inserter/stack-inserter-platform.png",
            priority = "extra-high",
            width = 105,
            height = 79,
            shift = util.by_pixel(1.5, 6.5),
            scale = 0.5,
        },
    }
    entity.minable = entity.minable or {mining_time = 0.1}
    entity.minable.result = "stack-inserter"
    entity.stack_size_bonus = 4
    entity.bulk = true
    entity.grab_less_to_match_belt_stack = true
    entity.wait_for_full_hand = true
    entity.enter_drop_mode_if_held_stack_spoiled = true
    entity.max_belt_stack_size = 20
    prototypes[#prototypes + 1] = entity
end

if not data.raw.item["stack-inserter"] then
    local item = table.deepcopy(bulk_item)
    item.name = "stack-inserter"
    item.localised_name = {"item-name.stack-inserter"}
    item.localised_description = {"item-description.the-cave-stack-inserter"}
    item.icon = "__the-cave__/graphics/icons/stack-inserter.png"
    item.icons = nil
    item.icon_size = 64
    item.place_result = "stack-inserter"
    item.order = "h[stack-inserter]"
    item.color_hint = {text = "S"}
    prototypes[#prototypes + 1] = item
end

if not data.raw.recipe["stack-inserter"] then
    local recipe = table.deepcopy(bulk_recipe)
    recipe.name = "stack-inserter"
    recipe.localised_name = {"recipe-name.stack-inserter"}
    recipe.enabled = false
    recipe.energy_required = 1
    recipe.ingredients = {
        {type = "item", name = "bulk-inserter", amount = 1},
        {type = "item", name = "processing-unit", amount = 3},
    }
    recipe.results = {{type = "item", name = "stack-inserter", amount = 1}}
    prototypes[#prototypes + 1] = recipe
end

if not data.raw.technology["stack-inserter"] then
    prototypes[#prototypes + 1] = {
        type = "technology",
        name = "stack-inserter",
        localised_name = {"technology-name.stack-inserter"},
        localised_description = {"technology-description.the-cave-stack-inserter"},
        icon = "__the-cave__/graphics/technology/stack-inserter.png",
        icon_size = 256,
        effects = {
            {type = "unlock-recipe", recipe = "stack-inserter"},
            {type = "belt-stack-size-bonus", modifier = 1},
        },
        prerequisites = {"inserter-capacity-bonus-7"},
        unit = {
            count = 1000,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"production-science-pack", 1},
                {"utility-science-pack", 1},
            },
            time = 60,
        },
        order = "a-f-c",
    }
end

-- Two seed technologies mirror the official Space Age prototype layout. The
-- shared final-fixes pass configures them and extends the chain through level 18.
local function capacity_seed(level, prerequisite)
    return {
        type = "technology",
        name = "transport-belt-capacity-" .. tostring(level),
        localised_name = {"technology-name.the-cave-transport-belt-capacity", tostring(level)},
        localised_description = {"technology-description.the-cave-transport-belt-capacity", tostring(level + 2)},
        icons = util.technology_icon_constant_stack_size("__the-cave__/graphics/technology/transport-belt-capacity.png"),
        effects = {{type = "belt-stack-size-bonus", modifier = 1}},
        prerequisites = {prerequisite},
        unit = {
            count = level == 1 and 1100 or 1150,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"production-science-pack", 1},
                {"utility-science-pack", 1},
            },
            time = 60,
        },
        upgrade = true,
        order = "a-f-d-" .. string.format("%02d", level),
    }
end

if not data.raw.technology["transport-belt-capacity-1"] then
    prototypes[#prototypes + 1] = capacity_seed(1, "stack-inserter")
end
if not data.raw.technology["transport-belt-capacity-2"] then
    prototypes[#prototypes + 1] = capacity_seed(2, "transport-belt-capacity-1")
end

if #prototypes > 0 then
    data:extend(prototypes)
end
