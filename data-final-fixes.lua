-- The Cave 2.1.52: optional integrated Train Interiors.
require("prototypes.weapon_digging")
-- When enabled, trains become exploration/progression objects instead of craft-spammable items.
local function the_cave_startup_enabled_data(name, fallback)
  if settings and settings.startup and settings.startup[name] then
    local value = settings.startup[name].value
    return value == "enabled" or value == true
  end
  return fallback ~= false
end

-- Advancing Collapse supplies rolling stock through its Main Train. A private
-- category also prevents an assembler saved with one of these recipes selected
-- from continuing to manufacture trains after this setting is enabled.
if the_cave_startup_enabled_data("the-cave-advancing-collapse", false) then
  local blocked = { ["locomotive"] = true, ["cargo-wagon"] = true,
    ["fluid-wagon"] = true, ["artillery-wagon"] = true }
  data:extend({ { type = "recipe-category", name = "the-cave-disabled-train-crafting" } })
  for name in pairs(blocked) do
    local recipe = data.raw.recipe[name]
    if recipe then
      recipe.enabled = false
      recipe.hidden = true
      recipe.allow_as_intermediate = false
      recipe.categories = {"the-cave-disabled-train-crafting"}
    end
  end
  for _, technology in pairs(data.raw.technology or {}) do
    for i = #(technology.effects or {}), 1, -1 do
      local effect = technology.effects[i]
      if effect.type == "unlock-recipe" and blocked[effect.recipe] then
        table.remove(technology.effects, i)
      end
    end
  end
end

-- Keep the complete Train prototype union available; force-local runtime gating
-- follows the independent Startup settings.
local the_cave_train_interiors_active = true
local the_cave_train_interiors_selected =
  the_cave_startup_enabled_data("the-cave-train-interiors", false)
  and not the_cave_startup_enabled_data("the-cave-shelter-defense", false)

if the_cave_train_interiors_active then
  local blocked_train_recipes = {
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
  }
  -- Crafting restrictions are force-local and applied from the Startup settings.
  -- Never globally hide vanilla recipes here.
  if false then
  if data.raw.recipe then
    for recipe_name in pairs(blocked_train_recipes) do
      local recipe = data.raw.recipe[recipe_name]
      if recipe then
        recipe.enabled = false
        recipe.hidden = true
      end
    end
  end
  if data.raw.technology then
    for _, tech in pairs(data.raw.technology) do
      if tech.effects then
        for i = #tech.effects, 1, -1 do
          local effect = tech.effects[i]
          if effect and effect.type == "unlock-recipe" and blocked_train_recipes[effect.recipe] then
            table.remove(tech.effects, i)
          end
        end
      end
    end

    -- Fluid Wagon technology has no remaining effect in Train Interiors after
    -- its only vanilla recipe unlock is removed. Hide the now-empty research
    -- instead of charging players 200 science for no reward. Railway remains
    -- visible for rails/signals/stops, and Artillery remains visible for its
    -- turret, ammunition and non-wagon effects.
    local fluid_wagon_technology = data.raw.technology["fluid-wagon"]
    if fluid_wagon_technology then
      fluid_wagon_technology.enabled = false
      fluid_wagon_technology.hidden = true
      fluid_wagon_technology.visible_when_disabled = false
      fluid_wagon_technology.hidden_in_factoriopedia = true
    end
  end
  local function lock_train_group(group)
    if not data.raw[group] then return end
    for _, proto in pairs(data.raw[group]) do
      proto.minable = nil
    end
  end
  lock_train_group("locomotive")
  lock_train_group("cargo-wagon")
  lock_train_group("fluid-wagon")
  lock_train_group("artillery-wagon")
  end

  -- The vanilla Fluid Wagon technology must remain globally available for
  -- non-Train configurations. Runtime force logic disables it only in active
  -- Train Interiors/CAVETORIO configurations; this prototype
  -- flag makes that disabled technology disappear from the research graph
  -- instead of remaining as a grey, selectable 200-science dead end.
  local runtime_fluid_wagon_technology = data.raw.technology and data.raw.technology["fluid-wagon"]
  if runtime_fluid_wagon_technology then
    runtime_fluid_wagon_technology.visible_when_disabled = false
  end

  -- Train Shield: keep the real train physically intact.
  -- Every compatible rolling-stock prototype uses one fixed physical ceiling.
  -- Runtime script stores the researched 5,000-35,000 HP as one shared pool per
  -- connected train and maps its ratio onto that ceiling. Research must never
  -- replace a live locomotive/wagon just to change prototype max_health.
  -- Extra wagons do not add free max HP. Repair packs are disabled; script
  -- handles slow self-repair.
  local shield_base_health = 5000
  local shield_health_per_level = 3000
  local shield_levels = 10
  local shield_physical_health_ceiling = shield_base_health + (shield_health_per_level * shield_levels)
  local shield_base_names = {
    locomotive = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
  }
  local shield_prototypes = {}
  local function shield_variant_name(base_name, level)
    return "the-cave-train-shield-" .. base_name .. "-" .. tostring(level)
  end
  local function add_not_repairable_flag(prototype)
    prototype.flags = prototype.flags or {}
    for _, flag in pairs(prototype.flags) do
      if flag == "not-repairable" then return end
    end
    prototype.flags[#prototype.flags + 1] = "not-repairable"
  end
  for group_name in pairs(blocked_train_recipes) do
    local group = data.raw[group_name]
    if group then
      for base_name in pairs(shield_base_names) do
        local base = group[base_name]
        if base then
          -- The physical entity always stays alive and keeps the same prototype,
          -- unit_number, direction and couplings. The script-controlled shared
          -- pool remains the authoritative researched health.
          if the_cave_train_interiors_selected then
            base.max_health = shield_physical_health_ceiling
            base.repair_speed_modifier = 0
            base.healing_per_tick = 0
            add_not_repairable_flag(base)
          end
          for level = 0, shield_levels do
            local variant = table.deepcopy(base)
            variant.name = shield_variant_name(base_name, level)
            variant.hidden = true
            variant.hidden_in_factoriopedia = true
            variant.localised_name = base.localised_name or { "entity-name." .. base_name }
            variant.localised_description = { "", "The Cave Train Shield shared-pool compatible rolling stock." }
            variant.minable = nil
            -- Legacy variants must remain loadable for existing saves, but all
            -- use the same physical ceiling. They are never swapped at runtime.
            variant.max_health = shield_physical_health_ceiling
            if the_cave_train_interiors_selected then
              variant.repair_speed_modifier = 0
              variant.healing_per_tick = 0
              add_not_repairable_flag(variant)
            end
            shield_prototypes[#shield_prototypes + 1] = variant
          end
        end
      end
    end
  end
  if #shield_prototypes > 0 then data:extend(shield_prototypes) end
end


-- The Cave 2.1.26: early pollution control and broader assembler productivity support.
-- Keep this data-stage only: no runtime scripts, no new systems.
if data.raw["assembling-machine"] and data.raw["assembling-machine"]["assembling-machine-1"] then
  data.raw["assembling-machine"]["assembling-machine-1"].module_slots = 1
end

local the_cave_assembler_crafting_categories = {}
for _, assembler_name in pairs({
  "assembling-machine-1",
  "assembling-machine-2",
  "assembling-machine-3",
  "the-cave-assembling-machine-4",
  "the-cave-assembling-machine-5"
}) do
  local assembler = data.raw["assembling-machine"] and data.raw["assembling-machine"][assembler_name]
  if assembler and assembler.crafting_categories then
    for _, category in pairs(assembler.crafting_categories) do
      the_cave_assembler_crafting_categories[category] = true
    end
  end
end
the_cave_assembler_crafting_categories["crafting"] = true

local function the_cave_recipe_has_item_result(recipe)
  if recipe.result then return true end
  if recipe.results then
    for _, result in pairs(recipe.results) do
      if type(result) == "table" and (result.type == nil or result.type == "item") then
        return true
      end
    end
  end
  return false
end

if data.raw.recipe then
  for recipe_name, recipe in pairs(data.raw.recipe) do
    local assembler_recipe = false
    for _, category in ipairs(recipe.categories or {"crafting"}) do
      if the_cave_assembler_crafting_categories[category] then
        assembler_recipe = true
        break
      end
    end
    local lower_name = string.lower(recipe_name or "")
    if assembler_recipe
        and not recipe.hidden
        and not string.find(lower_name, "recycl", 1, true)
        and the_cave_recipe_has_item_result(recipe) then
      recipe.allow_productivity = true
    end
  end
end


-- The Cave: automatic cleanup fade times.
-- 0 means leave vanilla/mod default unchanged.
local function tc_setting(name, fallback)
  if settings and settings.startup and settings.startup[name] then
    return settings.startup[name].value or fallback
  end
  -- These settings are now runtime-per-user for UI cleanup. Data-stage prototype
  -- cleanup keeps the previous default value because per-player values are not
  -- available during data-final-fixes.
  return fallback
end

local tree_stump_time = tc_setting("the-cave-tree-stump-fade-time", 54000)
local enemy_corpse_time = tc_setting("the-cave-enemy-corpse-fade-time", 54000)
local building_remnant_time = tc_setting("the-cave-building-remnant-fade-time", 54000)
local rail_remnant_time = tc_setting("the-cave-rail-remnant-fade-time", 54000)

local function set_corpse_fade(name, value)
  if value and value > 0 and data.raw.corpse and data.raw.corpse[name] then
    data.raw.corpse[name].time_before_removed = value
  end
end

local function set_remnant_fade(name, value)
  if value and value > 0 and data.raw["corpse"] and data.raw["corpse"][name] then
    data.raw["corpse"][name].time_before_removed = value
  end
end

if data.raw.corpse then
  for name, corpse in pairs(data.raw.corpse) do
    if corpse then
      local lower = string.lower(name)

      -- Tree stumps.
      if tree_stump_time > 0 and (string.find(lower, "stump", 1, true) or string.find(lower, "tree%-stump")) then
        corpse.time_before_removed = tree_stump_time
      end

      -- Enemy corpses: biters, spitters, worms, spawners, nests.
      if enemy_corpse_time > 0 and (
        string.find(lower, "biter", 1, true) or
        string.find(lower, "spitter", 1, true) or
        string.find(lower, "worm", 1, true) or
        string.find(lower, "spawner", 1, true) or
        string.find(lower, "nest", 1, true)
      ) then
        corpse.time_before_removed = enemy_corpse_time
      end

      -- Building remnants. Avoid character-corpse so player corpses/items are safe.
      if building_remnant_time > 0 and string.find(lower, "remnants", 1, true) and not string.find(lower, "rail", 1, true) and not string.find(lower, "character", 1, true) then
        corpse.time_before_removed = building_remnant_time
      end

      -- Rail remnants.
      if rail_remnant_time > 0 and string.find(lower, "rail", 1, true) and string.find(lower, "remnants", 1, true) then
        corpse.time_before_removed = rail_remnant_time
      end
    end
  end
end




-- The Cave: configurable chest capacities
local function tcv(name, fallback)
  if settings.startup[name] then return settings.startup[name].value end
  return fallback
end

local wooden = tcv("the-cave-wooden-chest-capacity",16)
local iron = tcv("the-cave-iron-chest-capacity",32)
local steel = tcv("the-cave-steel-chest-capacity",48)
local logistic = tcv("the-cave-logistic-chest-capacity",48)

if data.raw.container and data.raw.container["wooden-chest"] then
  data.raw.container["wooden-chest"].inventory_size = wooden
end
if data.raw.container and data.raw.container["iron-chest"] then
  data.raw.container["iron-chest"].inventory_size = iron
end
if data.raw.container and data.raw.container["steel-chest"] then
  data.raw.container["steel-chest"].inventory_size = steel
end

-- Logistic chest prototype names in Factorio are:
-- active-provider-chest, passive-provider-chest, storage-chest, buffer-chest, requester-chest
for _,n in pairs({"active-provider-chest","passive-provider-chest","storage-chest","buffer-chest","requester-chest"}) do
  if data.raw["logistic-container"] and data.raw["logistic-container"][n] then
    data.raw["logistic-container"][n].inventory_size = logistic
  end
end



-- The Cave 2.1.12 / 3.1.10: configurable selected resource and crop stack sizes.
-- The Cave Scrap and Fulgora Scrap deliberately remain separate prototypes
-- with separate Startup settings; neither setting is allowed to control the other.
-- Does not alter plates, crafted items, coins, loot, recipes, furnace output, oil, market, or economy.
local function tc_stack_setting(name, fallback)
  if settings and settings.startup and settings.startup[name] then
    local value = settings.startup[name].value
    if type(value) == "number" then return value end
  end
  return fallback
end

local configured_stack_sizes = {
  ["iron-ore"] = tc_stack_setting("the-cave-iron-ore-stack-size", 200),
  ["copper-ore"] = tc_stack_setting("the-cave-copper-ore-stack-size", 200),
  ["coal"] = tc_stack_setting("the-cave-coal-stack-size", 200),
  ["stone"] = tc_stack_setting("the-cave-stone-stack-size", 200),
  ["uranium-ore"] = tc_stack_setting("the-cave-uranium-ore-stack-size", 200),
  ["the-cave-scrap"] = tc_stack_setting("the-cave-scrap-stack-size", 200),
  ["calcite"] = tc_stack_setting("the-cave-calcite-stack-size", 200),
  ["tungsten-ore"] = tc_stack_setting("the-cave-tungsten-ore-stack-size", 200),
  ["scrap"] = tc_stack_setting("the-cave-fulgora-scrap-stack-size", 200),
  ["yumako"] = tc_stack_setting("the-cave-yumako-stack-size", 200),
  ["jellynut"] = tc_stack_setting("the-cave-jellynut-stack-size", 200)
}

for item_name, stack_size in pairs(configured_stack_sizes) do
  if data.raw.item and data.raw.item[item_name] then
    data.raw.item[item_name].stack_size = stack_size
  end
end

-- The Cave 2.4.18: keep the two primary vanilla ores visible in item-selection GUIs.
-- A player report found Iron Ore and Copper Ore missing from the manual splitter
-- filter picker while circuit-network assignment still worked. Restore only their
-- vanilla item grouping/visibility fields; mining, recipes and stack settings stay unchanged.
local the_cave_primary_ore_item_defaults = {
  ["iron-ore"] = { subgroup = "raw-resource", order = "e[iron-ore]" },
  ["copper-ore"] = { subgroup = "raw-resource", order = "f[copper-ore]" },
}

for item_name, defaults in pairs(the_cave_primary_ore_item_defaults) do
  local item = data.raw.item and data.raw.item[item_name]
  if item then
    item.subgroup = defaults.subgroup
    item.order = defaults.order
    item.hidden = false
    item.hidden_in_factoriopedia = false
  end
end



-- The Cave 2.1.11: native chest filtering support
-- Goal: let normal chests/boxes use Factorio's built-in filtered inventory UI.
-- Scope is intentionally small: chests only. No wagons, cars, tanks, spidertrons, player inventory, or new chest items.
-- This does not create new entities and does not change market/loot/coin systems.
local function the_cave_enable_chest_filters(prototype)
  if not prototype then return end

  -- Factorio containers usually use nil/"with_bar" inventory type.
  -- "with_filters_and_bar" keeps the normal chest limit bar and adds native item filters.
  if prototype.inventory_type == nil or prototype.inventory_type == "with_bar" then
    prototype.inventory_type = "with_filters_and_bar"
  end
end

local the_cave_chest_filter_blacklist = {
  -- Avoid special modded containers that should not behave like normal chests.
  ["se-rocket-landing-pad"] = true,
  ["se-delivery-cannon-chest"] = true,
}

if the_cave_startup_enabled_data("the-cave-chest-filtering", true) then
  if data.raw.container then
    for name, prototype in pairs(data.raw.container) do
      if not the_cave_chest_filter_blacklist[name] then
        the_cave_enable_chest_filters(prototype)
      end
    end
  end

  if data.raw["logistic-container"] then
    for name, prototype in pairs(data.raw["logistic-container"]) do
      if not the_cave_chest_filter_blacklist[name] then
        the_cave_enable_chest_filters(prototype)
      end
    end
  end
end


-- The Cave 2.6.4: the multiplayer-safe Damage Indicator uses local flying text.
-- Projectile script-trigger markers are no longer injected into combat prototypes.

-- The Cave: protect underground darkness progression.
-- Night Vision is a one-time equipment bypass for pitch-black/deep cave play,
-- so only the technology is disabled/hidden. The item, recipe and ingredients
-- are intentionally left untouched to avoid affecting unrelated prototype chains.
do
  local tech = data.raw.technology and data.raw.technology["night-vision-equipment"]
  if tech then
    tech.enabled = false
    tech.hidden = true
    tech.visible_when_disabled = false
  end
end

-- The Cave 2.5.7: Optional expansion belt-stacking path, belt-stack output and final inserter capacity.
-- Works for Space Age owners both with the Space Age mod active and in normal Factorio mode.
-- Goals:
--   1) Use the official Stack Inserter route when Space Age is active.
--   2) In normal Factorio, use The Cave's base-graphics Stack Inserter fallback.
--   3) Extend Transport Belt Capacity from 4 levels to 18 levels:
--        Stack Inserter -> stack size 2
--        Transport Belt Capacity 1 -> stack size 3
--        ...
--        Transport Belt Capacity 18 -> stack size 20
--   4) Bulk Inserter and Inserter Capacity use Automation and Logistic science;
--      Stack Inserter and every capacity level also use Chemical science.
--   5) At Transport Belt Capacity 18, all standard inserter hand capacities reach 20.
--   6) Keep the capacity progression prototype-driven; normal mode adds only the required fallback prototypes.
--   7) The whole path remains controlled by Startup setting "Early Stack Size".
do
  local early_stack_size_setting = settings.startup["the-cave-early-stack-size"]
  local early_stack_size_enabled = (not early_stack_size_setting) or early_stack_size_setting.value ~= "disabled"

  if early_stack_size_enabled and feature_flags and feature_flags.space_travel and data.raw.technology then
    local removed_science_packs = {
      ["space-science-pack"] = true,
      ["agricultural-science-pack"] = true,
    }

    local removed_prerequisites = {
      -- Science-pack gates intentionally removed from this belt-capacity path.
      ["space-science-pack"] = true,
      ["agricultural-science-pack"] = true,

      -- Space/Gleba route gates that can enter through the official Space Age tree.
      ["rocket-silo"] = true,
      ["space-platform"] = true,
      ["space-platform-thruster"] = true,
      ["space-platform-foundation"] = true,
      ["planet-discovery-gleba"] = true,
      ["agriculture"] = true,
      ["carbon-fiber"] = true,
      ["bioflux"] = true,
      ["jellynut"] = true,
      ["jellynut-processing"] = true,
      ["yumako-processing"] = true,
      ["landfill"] = true,
    }

    local red_green_science_ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
    }

    local red_green_blue_science_ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
    }

    local function remove_named_entries(list, remove_names)
      if type(list) ~= "table" then return list end
      local cleaned = {}
      for _, entry in pairs(list) do
        local name = nil
        if type(entry) == "string" then
          name = entry
        elseif type(entry) == "table" then
          name = entry[1] or entry.name
        end
        if not (name and remove_names[name]) then
          cleaned[#cleaned + 1] = entry
        end
      end
      return cleaned
    end

    local function clean_space_age_gates(tech)
      if not tech then return end
      tech.prerequisites = remove_named_entries(tech.prerequisites, removed_prerequisites)
      if tech.unit and tech.unit.ingredients then
        tech.unit.ingredients = remove_named_entries(tech.unit.ingredients, removed_science_packs)
      end
    end

    local function configure_finite_research(tech, count, ingredients, time)
      tech.research_trigger = nil
      tech.unit = tech.unit or {}
      tech.unit.count_formula = nil
      tech.unit.count = count
      tech.unit.ingredients = table.deepcopy(ingredients)
      tech.unit.time = time
    end

    -- Keep the early inserter-capacity section on Automation and Logistic
    -- science only. The seven bonuses form one uninterrupted chain.
    local bulk_inserter_technology = data.raw.technology["bulk-inserter"]
    if not bulk_inserter_technology then
      error("[The Cave] Required technology 'bulk-inserter' was not found.")
    end
    configure_finite_research(
      bulk_inserter_technology,
      100,
      red_green_science_ingredients,
      30
    )

    for level = 1, 7 do
      local name = "inserter-capacity-bonus-" .. tostring(level)
      local technology = data.raw.technology[name]
      if not technology then
        error("[The Cave] Required technology '" .. name .. "' was not found.")
      end

      clean_space_age_gates(technology)
      technology.prerequisites = {
        level == 1 and "bulk-inserter" or
          ("inserter-capacity-bonus-" .. tostring(level - 1))
      }
      configure_finite_research(
        technology,
        250,
        red_green_science_ingredients,
        30
      )
    end

    -- Stack Inserter is the capacity-2 step and costs 300 Automation,
    -- Logistic and Chemical science packs.
    -- This is the official prototype in Space Age mode and The Cave's fallback in normal mode.
    local stack_inserter = data.raw.technology["stack-inserter"]
    if not stack_inserter then
      error("[The Cave] Required technology 'stack-inserter' was not found.")
    end
    clean_space_age_gates(stack_inserter)
    stack_inserter.prerequisites = { "inserter-capacity-bonus-7" }
    configure_finite_research(
      stack_inserter,
      300,
      red_green_blue_science_ingredients,
      60
    )

    local capacity_1 = data.raw.technology["transport-belt-capacity-1"]
    local capacity_2 = data.raw.technology["transport-belt-capacity-2"]
    local capacity_template = capacity_2 or capacity_1

    if not capacity_template then
      error("[The Cave] Required Transport Belt Capacity technology was not found.")
    end

    -- Configure one level after it exists in data.raw. New levels are registered one-by-one.
    local function configure_capacity_level(tech, level)
      clean_space_age_gates(tech)
      tech.prerequisites = {
        level == 1 and "stack-inserter" or ("transport-belt-capacity-" .. tostring(level - 1))
      }
      configure_finite_research(
        tech,
        300,
        red_green_blue_science_ingredients,
        60
      )
      tech.effects = {{ type = "belt-stack-size-bonus", modifier = 1 }}

      -- Regular inserters already end at hand capacity 3 after Inserter Capacity
      -- Bonus 7. From Transport Belt Capacity 2 onward, add exactly +1 per level
      -- so Burner, standard, Long-handed and Fast Inserters progress smoothly:
      -- 3 at level 1, 4 at level 2, ... and 20 at level 18.
      if level >= 2 then
        tech.effects[#tech.effects + 1] = {
          type = "inserter-stack-size-bonus",
          modifier = 1,
        }
      end

      -- Bulk and Stack Inserters share the bulk force bonus. Their built-in
      -- bonuses are aligned below at 16, then levels 15-18 add +1 each so both
      -- progress smoothly: 16 at level 14, 17 at level 15, ... and 20 at level 18.
      if level >= 15 then
        tech.effects[#tech.effects + 1] = {
          type = "bulk-inserter-capacity-bonus",
          modifier = 1,
        }
      end

      tech.localised_name = {
        "technology-name.the-cave-transport-belt-capacity",
        tostring(level),
      }
      if level == 18 then
        tech.localised_description = {
          "technology-description.the-cave-transport-belt-capacity-final",
          tostring(level + 2),
        }
      else
        tech.localised_description = {
          "technology-description.the-cave-transport-belt-capacity",
          tostring(level + 2),
        }
      end
      tech.upgrade = true
      tech.order = "a-f-d-" .. string.format("%02d", level)
    end

    local template_copy = table.deepcopy(capacity_template)
    for level = 1, 18 do
      local name = "transport-belt-capacity-" .. tostring(level)
      local tech = data.raw.technology[name]

      if not tech then
        local clone = table.deepcopy(template_copy)
        clone.name = name
        data:extend({ clone })
        tech = data.raw.technology[name]
      end

      if not tech then
        error("[The Cave] Failed to create technology '" .. name .. "'.")
      end

      configure_capacity_level(tech, level)
    end

    -- Fail loudly instead of silently shipping a partial 4-level chain.
    for level = 1, 18 do
      local name = "transport-belt-capacity-" .. tostring(level)
      if not data.raw.technology[name] then
        error("[The Cave] Belt-capacity validation failed; missing technology '" .. name .. "'.")
      end
    end

    -- Permit the final researched stack size of 20.
    if data.raw["utility-constants"] and data.raw["utility-constants"].default then
      local constants = data.raw["utility-constants"].default
      constants.max_belt_stack_size = math.max(constants.max_belt_stack_size or 4, 20)
    end

    -- Bulk and Stack Inserters use the same force-wide bulk capacity bonus.
    -- Align their built-in bonuses at 16 so Capacity levels 15-18 can raise
    -- both smoothly by +1 per level to the shared final hand capacity of 20.
    if data.raw.inserter then
      local bulk_inserter = data.raw.inserter["bulk-inserter"]
      local stack_inserter_entity = data.raw.inserter["stack-inserter"]
      if bulk_inserter and stack_inserter_entity then
        local shared_builtin_bonus = math.max(
          bulk_inserter.stack_size_bonus or 0,
          stack_inserter_entity.stack_size_bonus or 0
        )
        bulk_inserter.stack_size_bonus = shared_builtin_bonus
        stack_inserter_entity.stack_size_bonus = shared_builtin_bonus
      end

      -- Let eligible inserters create the researched belt stacks.
      -- Preserve each prototype's native full-hand policy: ordinary inserters
      -- may use their researched hand capacity without waiting indefinitely for
      -- a full hand, while the dedicated Stack Inserter keeps its intended
      -- wait-for-full-hand behaviour.
      for _, inserter in pairs(data.raw.inserter) do
        if not inserter.hidden then
          inserter.max_belt_stack_size = math.max(inserter.max_belt_stack_size or 1, 20)
          inserter.grab_less_to_match_belt_stack = true
          inserter.enter_drop_mode_if_held_stack_spoiled = true
        end
      end
    end

    -- Let every Loader and 1x1 Loader follow the force-wide researched belt
    -- stack size, up to the same final cap of 20. This is prototype-only, so
    -- loaders already placed in a save update automatically after the mod reloads.
    -- Keep runtime adjustment disabled unless another mod explicitly enables it;
    -- this avoids per-loader overrides that could become stuck on an old value.
    for _, loader_type in pairs({ "loader", "loader-1x1" }) do
      if data.raw[loader_type] then
        for _, loader in pairs(data.raw[loader_type]) do
          loader.max_belt_stack_size = math.max(loader.max_belt_stack_size or 1, 20)
        end
      end
    end

    -- Let item-output mining drills use full belt stacks too.
    -- Pumpjacks/fluid-only mining drills are skipped because they do not output items onto belts.
    local function is_fluid_only_mining_drill(drill)
      if not drill then return false end
      if drill.name == "pumpjack" then return true end

      local categories = drill.resource_categories
      if type(categories) ~= "table" then return false end

      local has_fluid_category = false
      local has_item_category = false

      for _, category in pairs(categories) do
        local name = tostring(category or "")
        if name == "basic-fluid" or string.find(name, "fluid", 1, true) then
          has_fluid_category = true
        else
          has_item_category = true
        end
      end

      return has_fluid_category and not has_item_category
    end

    if data.raw["mining-drill"] then
      for _, drill in pairs(data.raw["mining-drill"]) do
        if not drill.hidden and not is_fluid_only_mining_drill(drill) then
          drill.max_belt_stack_size = math.max(drill.max_belt_stack_size or 1, 20)
          drill.drops_full_belt_stacks = true
        end
      end
    end
  end
end

-- The Cave 2.7.29: MTN-style discovery plus Warptorio-style ground Space
-- Science for Everything on Nauvis. This runs before the global research
-- difficulty pass so its 100-unit laboratory cost follows the selected
-- Research Level Difficulty multiplier.
require("prototypes.everything_on_nauvis_progression_final_fixes")

-- The Cave: Research Level Difficulty startup setting.
-- When The Cave is active, this scales all finite technology research costs in the loaded game.
-- This is still scoped to The Cave as a mod: disabling The Cave removes this prototype patch entirely.
-- The multiplier is direct from each technology's base cost, not cumulative between difficulty levels.
-- Keep this after The Cave technology edits so new/changed research counts are scaled too.
do
  local multipliers = {
    ["very-easy"] = 0.25,
    ["easy"] = 0.5,
    ["medium"] = 1,
    ["hard"] = 2,
    ["very-hard"] = 3,
    ["marathon"] = 6,
  }

  local setting = settings.startup["the-cave-research-level-difficulty"]
  local difficulty = setting and setting.value or "medium"
  local multiplier = multipliers[difficulty] or 1

  local function scaled_count(count)
    if type(count) ~= "number" then return count end
    return math.max(1, math.floor((count * multiplier) + 0.5))
  end

  if multiplier ~= 1 then
    for _, tech in pairs(data.raw.technology or {}) do
      if tech.unit and tech.unit.count then
        tech.unit.count = scaled_count(tech.unit.count)
      end
    end
  end
end


-- The Cave 2.1.46: optional mining drill resource filters.
-- Inspired by the Cursed Filter Mining Drill gameplay idea, but implemented as a small
-- self-contained The Cave system. Enabled only by startup setting because it changes
-- resource categories and creates hidden filtered mining-drill variants.
do
  local setting = settings and settings.startup and settings.startup["the-cave-filter-mining-drills"]
  if setting and setting.value == "enabled" and data.raw["resource"] and data.raw["mining-drill"] then
    local connector = "__tcdf__"

    local function as_category_array(value, fallback)
      local result = {}
      local seen = {}
      local function add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
          seen[name] = true
          result[#result + 1] = name
        end
      end
      if type(value) == "string" then
        add(value)
      elseif type(value) == "table" then
        for key, val in pairs(value) do
          if type(key) == "number" then
            add(val)
          elseif val then
            add(key)
          end
        end
      end
      if #result == 0 and fallback then add(fallback) end
      return result
    end

    local function has_category(categories, wanted)
      for _, category in pairs(categories or {}) do
        if category == wanted then return true end
      end
      return false
    end

    local function add_category(categories, wanted)
      if not has_category(categories, wanted) then
        categories[#categories + 1] = wanted
      end
    end

    local function can_drill_reach_resource(drill_old_categories, old_resource_category, resource_name, resource_needs_input_fluid, drill_handles_input_fluid)
      if resource_needs_input_fluid and not drill_handles_input_fluid then
        return false
      end
      return has_category(drill_old_categories, old_resource_category)
    end

    local old_resource_category = {}
    local resource_needs_input_fluid = {}
    local resource_localised_name = {}

    for resource_name, resource in pairs(data.raw["resource"] or {}) do
      old_resource_category[resource_name] = resource.category or "basic-solid"
      resource_needs_input_fluid[resource_name] = resource.minable and resource.minable.required_fluid ~= nil or false
      resource_localised_name[resource_name] = resource.localised_name or {"entity-name." .. resource_name}

      resource.category = resource_name
      if not data.raw["resource-category"] then data.raw["resource-category"] = {} end
      if not data.raw["resource-category"][resource_name] then
        data.raw["resource-category"][resource_name] = {
          type = "resource-category",
          name = resource_name,
        }
      end
    end

    -- Keep hand-mining compatible with the resource-category split.
    for _, character in pairs(data.raw["character"] or {}) do
      local old_categories = as_category_array(character.mining_categories, "basic-solid")
      local new_categories = {}
      for resource_name, category in pairs(old_resource_category) do
        if not resource_needs_input_fluid[resource_name] and has_category(old_categories, category) then
          add_category(new_categories, resource_name)
        end
      end
      if #new_categories > 0 then character.mining_categories = new_categories end
    end

    local placeable_by = {}
    for item_name, item in pairs(data.raw["item"] or {}) do
      if item.place_result and data.raw["mining-drill"][item.place_result] then
        placeable_by[item.place_result] = {item = item_name, count = 1}
      end
    end

    local base_drills = {}
    local base_drill_categories = {}
    for drill_name, drill in pairs(data.raw["mining-drill"] or {}) do
      if not string.find(drill_name, connector, 1, true) and drill.resource_categories then
        local old_categories = as_category_array(drill.resource_categories)
        if #old_categories > 0 then
          base_drill_categories[drill_name] = old_categories
          base_drills[#base_drills + 1] = {name = drill_name, prototype = drill}
        end
      end
    end

    -- Convert normal drills to the split categories so unfiltered drills still mine
    -- every resource they could mine before.
    for _, entry in pairs(base_drills) do
      local drill = entry.prototype
      local old_categories = base_drill_categories[entry.name]
      local new_categories = {}
      local drill_handles_input_fluid = drill.input_fluid_box ~= nil
      for resource_name, category in pairs(old_resource_category) do
        if can_drill_reach_resource(old_categories, category, resource_name, resource_needs_input_fluid[resource_name], drill_handles_input_fluid) then
          add_category(new_categories, resource_name)
        end
      end
      if #new_categories > 0 then drill.resource_categories = new_categories end
      if not drill.fast_replaceable_group then drill.fast_replaceable_group = entry.name end
    end

    -- Create one hidden filtered entity variant per drill/resource pair.
    for _, entry in pairs(base_drills) do
      local drill_name = entry.name
      local drill = data.raw["mining-drill"][drill_name]
      local old_categories = base_drill_categories[drill_name]
      local drill_handles_input_fluid = drill and drill.input_fluid_box ~= nil
      if drill and old_categories then
        for resource_name, category in pairs(old_resource_category) do
          if can_drill_reach_resource(old_categories, category, resource_name, resource_needs_input_fluid[resource_name], drill_handles_input_fluid) then
            local filtered_name = drill_name .. connector .. resource_name
            if not data.raw["mining-drill"][filtered_name] then
              local filtered = table.deepcopy(drill)
              filtered.name = filtered_name
              filtered.resource_categories = {resource_name}
              filtered.localised_name = {"", drill.localised_name or {"entity-name." .. drill_name}, " {", resource_localised_name[resource_name], "}"}
              filtered.localised_description = drill.localised_description or {"entity-description." .. drill_name}
              filtered.order = (drill.order or drill_name) .. "-" .. resource_name
              filtered.placeable_by = table.deepcopy(drill.placeable_by or placeable_by[drill_name])
              filtered.flags = table.deepcopy(drill.flags or {})
              local has_not_in_made_in = false
              for _, flag in pairs(filtered.flags) do
                if flag == "not-in-made-in" then has_not_in_made_in = true end
              end
              if not has_not_in_made_in then filtered.flags[#filtered.flags + 1] = "not-in-made-in" end
              data.raw["mining-drill"][filtered_name] = filtered
            end
          end
        end
      end
    end
  end
end

-- The Cave 2.2.36: Keep Coal Liquefaction on the vanilla/base progression path with The Cave balance cost.
-- Space Age normally makes the technology more expensive and adds a planet science
-- requirement; The Cave keeps the normal coal-to-oil route available at Purple
-- Science so scarce cave oil does not turn plastic into an excessive grind.
local function the_cave_restore_vanilla_coal_liquefaction()
  local tech = data.raw.technology and data.raw.technology["coal-liquefaction"]
  if not tech then return end

  local function has_technology(name)
    return data.raw.technology and data.raw.technology[name] ~= nil
  end

  tech.prerequisites = {}
  if has_technology("advanced-oil-processing") then
    tech.prerequisites[#tech.prerequisites + 1] = "advanced-oil-processing"
  end
  if has_technology("production-science-pack") then
    tech.prerequisites[#tech.prerequisites + 1] = "production-science-pack"
  end

  tech.unit = tech.unit or {}
  tech.unit.count = 800
  tech.unit.time = 30
  tech.unit.ingredients = {
    { "automation-science-pack", 1 },
    { "logistic-science-pack", 1 },
    { "chemical-science-pack", 1 },
    { "production-science-pack", 1 },
  }

  tech.effects = {
    { type = "unlock-recipe", recipe = "coal-liquefaction" },
  }
end

the_cave_restore_vanilla_coal_liquefaction()

-- The Cave 2.3.14: Beacon-only module compatibility.
-- Scope intentionally limited to:
--   - vanilla beacon
--   - The Cave Beacon MK1-MK5
-- No modules, recipes, technologies, market prices, loot, furnaces,
-- assemblers, miners, labs, or other machines are changed here.
local function the_cave_has_quality_modules()
  return data.raw.module
    and (
      data.raw.module["quality-module"]
      or data.raw.module["quality-module-2"]
      or data.raw.module["quality-module-3"]
    )
end

local function the_cave_set_beacon_allowed_effects(beacon)
  if not beacon then return end

  local effects = {
    "speed",
    "consumption",
    "pollution",
    "productivity",
  }

  if the_cave_has_quality_modules() then
    effects[#effects + 1] = "quality"
  end

  beacon.allowed_effects = effects
end

local the_cave_beacon_module_targets = {
  "beacon",
  "the-cave-beacon-mk1",
  "the-cave-beacon-mk2",
  "the-cave-beacon-mk3",
  "the-cave-beacon-mk4",
  "the-cave-beacon-mk5",
}

if data.raw.beacon then
  for _, beacon_name in pairs(the_cave_beacon_module_targets) do
    the_cave_set_beacon_allowed_effects(data.raw.beacon[beacon_name])
  end
end

-- The Cave 2.3.17: Turret range upgrade hidden variants.
-- Scope:
--   - Gun Turret
--   - Laser Turret
--   - Flamethrower Turret
--   - Space Age only when present: Rocket Turret, Tesla Turret, Railgun Turret
-- Artillery Turret is intentionally excluded.
local THE_CAVE_TURRET_RANGE_BONUS = 3
local THE_CAVE_TURRET_RANGE_LEVELS = 5

local the_cave_turret_range_targets = {
  { type = "ammo-turret", name = "gun-turret" },
  { type = "electric-turret", name = "laser-turret" },
  { type = "fluid-turret", name = "flamethrower-turret" },
  { type = "ammo-turret", name = "rocket-turret" },
  { type = "electric-turret", name = "tesla-turret" },
  { type = "ammo-turret", name = "railgun-turret" },
}

local function the_cave_range_variant_name(base_name, level)
  return "the-cave-range-" .. base_name .. "-" .. tostring(level)
end

local function the_cave_add_attack_range(attack_parameters, bonus)
  if not attack_parameters then return false end
  if attack_parameters.range then
    attack_parameters.range = attack_parameters.range + bonus
    return true
  end
  return false
end

local function the_cave_add_not_in_made_in_flag(flags)
  flags = table.deepcopy(flags or {})
  for _, flag in pairs(flags) do
    if flag == "not-in-made-in" then return flags end
  end
  flags[#flags + 1] = "not-in-made-in"
  return flags
end

-- Hidden range variants are not the direct place_result of the normal turret
-- item. Give every variant an explicit placeable_by mapping so Factorio's
-- smart pipette (Q), blueprints and ghost revival all resolve back to the
-- original turret item.
local function the_cave_items_that_place_entity(entity_name)
  local result = {}
  local seen = {}

  -- Respect an explicit mapping already supplied by the base entity.
  for _, target in pairs(the_cave_turret_range_targets) do
    if target.name == entity_name then
      local group = data.raw[target.type]
      local entity = group and group[entity_name]
      local explicit = entity and entity.placeable_by
      if explicit then
        local entries = explicit.item and { explicit } or explicit
        for _, entry in pairs(entries) do
          if entry and entry.item and not seen[entry.item] then
            result[#result + 1] = table.deepcopy(entry)
            seen[entry.item] = true
          end
        end
      end
      break
    end
  end

  -- Otherwise derive it from every item-like prototype whose place_result is
  -- the original turret. Scanning all data.raw groups also keeps compatibility
  -- with mods that use a non-standard item prototype type or item name.
  for _, prototype_group in pairs(data.raw) do
    if type(prototype_group) == "table" then
      for _, prototype in pairs(prototype_group) do
        if type(prototype) == "table"
          and prototype.name
          and prototype.place_result == entity_name
          and not seen[prototype.name]
        then
          result[#result + 1] = { item = prototype.name, count = 1 }
          seen[prototype.name] = true
        end
      end
    end
  end

  -- Vanilla and Space Age turret item names match their entity names. Keep a
  -- final safe fallback for unusual load orders where place_result was removed.
  if #result == 0 and data.raw.item and data.raw.item[entity_name] then
    result[1] = { item = entity_name, count = 1 }
  end

  if #result == 0 then return nil end
  if #result == 1 then return result[1] end
  return result
end

for _, target in pairs(the_cave_turret_range_targets) do
  local raw_group = data.raw[target.type]
  local base = raw_group and raw_group[target.name]
  if base and base.attack_parameters and base.attack_parameters.range then
    if not base.fast_replaceable_group then
      base.fast_replaceable_group = target.name
    end

    for level = 1, THE_CAVE_TURRET_RANGE_LEVELS do
      local variant_name = the_cave_range_variant_name(target.name, level)
      if not raw_group[variant_name] then
        local variant = table.deepcopy(base)
        variant.name = variant_name
        variant.localised_name = base.localised_name or { "entity-name." .. target.name }
        variant.localised_description = base.localised_description or { "entity-description." .. target.name }
        variant.order = (base.order or target.name) .. "-the-cave-range-" .. string.format("%02d", level)
        variant.fast_replaceable_group = base.fast_replaceable_group or target.name
        variant.placeable_by = the_cave_items_that_place_entity(target.name)
        variant.minable = table.deepcopy(base.minable)
        variant.next_upgrade = nil
        variant.flags = the_cave_add_not_in_made_in_flag(base.flags)

        the_cave_add_attack_range(variant.attack_parameters, level * THE_CAVE_TURRET_RANGE_BONUS)

        raw_group[variant_name] = variant
      end
    end
  end
end

-- The Cave 2.3.22: if the standalone Big Wooden Pole mod is enabled too,
-- keep only The Cave's integrated recipe visible in the crafting menu.
do
  local original_recipe = data.raw.recipe and data.raw.recipe["big-wooden-pole"]
  if original_recipe then
    original_recipe.enabled = false
    original_recipe.hidden = true
    original_recipe.hidden_in_factoriopedia = true
  end
end

-- The Cave 2.4.9: hidden Underground Belt Reach variants.
-- This must run in final fixes so every variant copies the final official belt
-- prototype after base/Space Age/other-mod data changes.
require("prototypes.underground_belt_reach_variants")

-- The Cave 2.4.15: hidden Underground Pipe Reach variants.
-- Runs in final fixes so variants copy the final pipe-to-ground prototype after
-- base/Space Age/other-mod data changes.
require("prototypes.underground_pipe_reach_variants")

-- The Cave 2.5.10: enemy cavern Laser Turret with isolated void power.
-- Runs in final fixes so it copies the final loaded vanilla Laser Turret after
-- base, Space Age and ordered compatibility-mod prototype changes.
require("prototypes.enemy_laser_power")

-- The Cave Inserter Configuration prototype support.
require("prototypes.inserter_config_final_fixes")

-- The Cave 2.4.16: integrated Squeak Through collision-box configuration.
-- Must run last so hidden variants and prototypes from other mods are included.
require("prototypes.faster_start_final_fixes")

-- The Cave 2.5.36: integrated Superheating liquid-fuel values.
require("prototypes.superheating_final_fixes")

require("prototypes.squeak_through_final_fixes")



-- The Cave 2.5.46: Everything on Nauvis must support the complete Gleba
-- production chain on the shared Nauvis cave surface. Official Gleba recipes
-- are locked to pressure 2000, while Nauvis pressure is 1000. Remove only the
-- exact Gleba pressure condition from the official progression recipes when
-- Everything on Nauvis is enabled; preserve every other surface condition and
-- leave normal planet-travel mode untouched.
do
  local setting = settings and settings.startup and settings.startup["the-cave-everything-on-nauvis"]
  local enabled = not setting or (setting.value ~= "disabled" and setting.value ~= false)
  if enabled and mods and mods["space-age"] and data.raw.recipe then
    local gleba_pressure_recipes = {
      "copper-bacteria",
      "copper-bacteria-cultivation",
      "iron-bacteria",
      "iron-bacteria-cultivation",
      "artificial-yumako-soil",
      "overgrowth-yumako-soil",
      "artificial-jellynut-soil",
      "overgrowth-jellynut-soil",
      "pentapod-egg",
      "agricultural-science-pack",
      "biochamber",
    }

    local function remove_exact_gleba_pressure(conditions)
      if type(conditions) ~= "table" then return conditions end
      local kept = {}
      for _, condition in pairs(conditions) do
        local is_gleba_pressure = type(condition) == "table"
          and condition.property == "pressure"
          and condition.min == 2000
          and condition.max == 2000
        if not is_gleba_pressure then
          kept[#kept + 1] = condition
        end
      end
      return #kept > 0 and kept or nil
    end

    for _, recipe_name in ipairs(gleba_pressure_recipes) do
      local recipe = data.raw.recipe[recipe_name]
      if recipe then
        recipe.surface_conditions = remove_exact_gleba_pressure(recipe.surface_conditions)
      end
    end
  end
end

-- The Cave 2.5.48: Everything on Nauvis must support the complete Vulcanus
-- production chain on the shared Nauvis cave surface. Official Vulcanus recipes
-- are locked to pressure 4000, while Nauvis pressure is 1000. Remove only the
-- exact Vulcanus pressure condition from the seven official recipes when the
-- shared-surface mode is enabled; preserve every other condition and normal
-- planet-travel behaviour.
do
  local setting = settings and settings.startup and settings.startup["the-cave-everything-on-nauvis"]
  local enabled = not setting or (setting.value ~= "disabled" and setting.value ~= false)
  if enabled and mods and mods["space-age"] and data.raw.recipe then
    local vulcanus_pressure_recipes = {
      "acid-neutralisation",
      "foundry",
      "metallurgic-science-pack",
      "turbo-transport-belt",
      "turbo-underground-belt",
      "turbo-splitter",
      "big-mining-drill",
    }

    local function remove_exact_vulcanus_pressure(conditions)
      if type(conditions) ~= "table" then return conditions end
      local kept = {}
      for _, condition in pairs(conditions) do
        local is_vulcanus_pressure = type(condition) == "table"
          and condition.property == "pressure"
          and condition.min == 4000
          and condition.max == 4000
        if not is_vulcanus_pressure then
          kept[#kept + 1] = condition
        end
      end
      return #kept > 0 and kept or nil
    end

    for _, recipe_name in ipairs(vulcanus_pressure_recipes) do
      local recipe = data.raw.recipe[recipe_name]
      if recipe then
        recipe.surface_conditions = remove_exact_vulcanus_pressure(recipe.surface_conditions)
      end
    end
  end
end

-- The Cave 2.5.73: complete shared-surface Aquilo progression. Aquilo recipes
-- use pressure conditions that the shared Nauvis cave surface cannot satisfy.
-- Remove only the pressure condition from the five official Aquilo progression
-- recipes while Everything on Nauvis is enabled. Preserve every other surface
-- condition and leave normal planet-travel mode completely vanilla.
do
  local setting = settings and settings.startup and settings.startup["the-cave-everything-on-nauvis"]
  local enabled = not setting or (setting.value ~= "disabled" and setting.value ~= false)
  if enabled and mods and mods["space-age"] and data.raw.recipe then
    local aquilo_pressure_recipes = {
      "cryogenic-science-pack",
      "cryogenic-plant",
      "fusion-reactor",
      "fusion-generator",
      "quantum-processor",
    }

    local function remove_aquilo_pressure(conditions)
      if type(conditions) ~= "table" then return conditions end
      local kept = {}
      for _, condition in pairs(conditions) do
        local is_aquilo_pressure = type(condition) == "table"
          and condition.property == "pressure"
        if not is_aquilo_pressure then kept[#kept + 1] = condition end
      end
      return #kept > 0 and kept or nil
    end

    for _, recipe_name in ipairs(aquilo_pressure_recipes) do
      local recipe = data.raw.recipe[recipe_name]
      if recipe then
        recipe.surface_conditions = remove_aquilo_pressure(recipe.surface_conditions)
      end
    end
  end
end

-- The Cave 2.5.73: complete shared-surface Fulgora compatibility. Fulgora
-- recipes require a magnetic field that the shared Nauvis cave surface cannot
-- provide. Remove only the magnetic-field condition from all five official
-- Fulgora progression recipes while Everything on Nauvis is enabled. Preserve
-- every other surface condition and leave normal planet-travel mode vanilla.
do
  local setting = settings and settings.startup and settings.startup["the-cave-everything-on-nauvis"]
  local enabled = not setting or (setting.value ~= "disabled" and setting.value ~= false)
  if enabled and mods and mods["space-age"] and data.raw.recipe then
    local fulgora_magnetic_recipes = {
      "electromagnetic-science-pack",
      "lightning-rod",
      "lightning-collector",
      "electromagnetic-plant",
      "recycler",
    }

    local function remove_fulgora_magnetic_field(conditions)
      if type(conditions) ~= "table" then return conditions end
      local kept = {}
      for _, condition in pairs(conditions) do
        local is_fulgora_magnetic = type(condition) == "table"
          and condition.property == "magnetic-field"
        if not is_fulgora_magnetic then kept[#kept + 1] = condition end
      end
      return #kept > 0 and kept or nil
    end

    for _, recipe_name in ipairs(fulgora_magnetic_recipes) do
      local recipe = data.raw.recipe[recipe_name]
      if recipe then
        recipe.surface_conditions = remove_fulgora_magnetic_field(recipe.surface_conditions)
      end
    end
  end
end

-- The Cave 2.5.23: enable the engine lightning generator on Nauvis only when
-- Everything on Nauvis is active. LuaSurface::execute_lightning requires the
-- surface's planet prototype to have lightning_properties; without this the
-- engine rejects every scripted strike with "surface does not have a lightning
-- generator". Copy Fulgora's target/priority rules so rods and collectors keep
-- vanilla behaviour, but set both time-of-day multipliers to zero so the engine
-- never creates automatic planet-wide strikes. Runtime code remains solely
-- responsible for striking inside The Cave's Fulgora region.
local function the_cave_enable_localised_fulgora_lightning_generator()
  local setting = settings and settings.startup and settings.startup["the-cave-everything-on-nauvis"]
  if setting and (setting.value == "disabled" or setting.value == false) then return end
  if not (mods and mods["space-age"]) then return end

  local planets = data.raw.planet
  local nauvis = planets and planets.nauvis
  local fulgora = planets and planets.fulgora
  local source = fulgora and fulgora.lightning_properties
  if not (nauvis and source) then return end

  local properties = table.deepcopy(source)
  properties.lightning_multiplier_at_day = 0
  properties.lightning_multiplier_at_night = 0

  -- The lightning generator belongs to the whole Nauvis surface, while The
  -- Cave's Fulgora is only one coordinate region on that surface. The engine
  -- warning icon therefore cannot be spatially limited and would follow
  -- endangered entities into Nauvis/Gleba/Vulcanus/Aquilo. Hide that global
  -- icon here; scripts/fulgora_lightning.lua draws the vanilla utility warning
  -- only for players who are currently inside the Fulgora region.
  properties.lightning_warning_icon = {
    filename = "__core__/graphics/empty.png",
    width = 1,
    height = 1
  }

  nauvis.lightning_properties = properties
end

the_cave_enable_localised_fulgora_lightning_generator()

-- The Cave 2.5.37: expand the original vanilla Small Electric Pole.
-- Applied in final fixes so it uses the final loaded vanilla prototype and
-- does not create a new entity or change blueprint/entity names.
require("prototypes.small_electric_pole_final_fixes")

-- The Cave 2.6.16: append native status-tinted indicators after other mods
-- have finished defining compatible crafting machines and mining drills.
require("prototypes.production_status_indicators")

-- The Cave 2.7.23: integrated FuelGlow colour and electric-furnace lighting.
-- The module safely yields to the standalone FuelGlow mod when both are loaded.
require("prototypes.fuel_glow_final_fixes")

-- Shelter Mode owns one fixed, scripted core. If the optional shelter-k2 mod
-- is also installed, keep its artwork available but remove its independent
-- craftable Shelter progression so a second movable/free-power Shelter cannot
-- bypass the Cave objective.
do
  local train_setting = settings.startup["the-cave-train-interiors"]
  local shelter_setting = settings.startup["the-cave-shelter-defense"]
  local train_requested = train_setting
    and (train_setting.value == "enabled" or train_setting.value == true)
  local shelter_requested = shelter_setting
    and (shelter_setting.value == "enabled" or shelter_setting.value == true)
  local shelter_mode = shelter_requested and not train_requested
  if shelter_mode then
    local technology = data.raw.technology and data.raw.technology["kr-shelter"]
    if technology then
      technology.enabled = false
      technology.hidden = true
      technology.hidden_in_factoriopedia = true
      technology.effects = {}
    end
    local recipe = data.raw.recipe and data.raw.recipe["kr-shelter"]
    if recipe then
      recipe.enabled = false
      recipe.hidden = true
      recipe.hidden_in_factoriopedia = true
    end
    local item = data.raw.item and data.raw.item["kr-shelter"]
    if item then
      item.hidden = true
      item.hidden_in_factoriopedia = true
    end
  end
end

-- The Cave 2.6.3: the cave world is fully script-generated. Keep every engine
-- entity autoplace entry disabled after all of The Cave's Space Age prototype
-- integration work has run. This prevents isolated high-richness planetary
-- resources (most visibly one-tile Scrap) from appearing in Nauvis chunks.
do
  local nauvis = data.raw.planet and data.raw.planet["nauvis"]
  local map_gen = nauvis and nauvis.map_gen_settings
  if map_gen then
    map_gen.autoplace_settings = map_gen.autoplace_settings or {}
    map_gen.autoplace_settings.entity = {
      settings = {},
      treat_missing_as_default = false,
    }
  end
end

-- The Cave 2.7.71: locked storage-capacity overrides.
-- Apply these at the end of final-fixes so vanilla Cargo Wagons, optional
-- modded Cargo Wagons and every hidden Train Shield compatibility variant use
-- the same eighty-slot inventory. Existing wagon entities adopt the prototype
-- increase without replacement or inventory migration.
if data.raw["cargo-wagon"] then
  for _, wagon in pairs(data.raw["cargo-wagon"]) do
    wagon.inventory_size = 80
  end
end

-- Scope is intentionally limited to the four player-approved processed items.
-- Raw resources and every unrelated crafted item retain their existing stack
-- settings and compatibility behaviour.
for _, item_name in ipairs({ "iron-plate", "copper-plate", "steel-plate", "stone-brick" }) do
  local item = data.raw.item and data.raw.item[item_name]
  if item then item.stack_size = 200 end
end

-- The Cave 3.0.42: apply the custom static menu after every dependency has
-- finished defining menu simulations and music tracks.
require("prototypes.main_menu")

-- The Cave 3.1.23: optional integrated Everything Has Quality behaviour.
-- Runs at the very end so it also covers compatible machines and modules
-- supplied or changed by other mods.
require("prototypes.quality_everything_final_fixes")

require("prototypes.locked_stack_sizes")

-- The Cave 3.1.35: Cave worlds are dominated by the engine's out-of-map tile,
-- whose vanilla industrial-pollution absorption is much stronger than normal
-- ground. Retain a very small leak instead of removing absorption entirely:
-- 0.000001 per tile per second is one percent of the vanilla out-of-map value,
-- or 0.06144 pollution per minute for a completely void-filled 32x32 chunk.
-- Change only standard industrial pollution; spores and every other airborne
-- pollutant keep their loaded prototype values.
do
  local void_tile = data.raw.tile and data.raw.tile["out-of-map"]
  if void_tile then
    void_tile.absorptions_per_second = void_tile.absorptions_per_second or {}
    void_tile.absorptions_per_second.pollution = 0.000001
  end
end

-- The Cave 3.1.39: dense, zero-spacing enemy bases can place many independent
-- spawners inside the same pollution front. Each vanilla-style nest otherwise
-- removes an absolute 20 pollution plus one percent of its chunk pollution per
-- absorption cycle, so a cluster becomes a near-solid wall even though attack
-- units themselves are inexpensive. Scale the direct industrial-pollution
-- intake of every loaded spawner to one percent while retaining a finite rate.
-- Iterating prototypes also covers compatible modded nests without changing
-- spores or any other airborne pollutant.
if the_cave_startup_enabled_data("the-cave-allow-biter-expansion", false) then
  local spawner_pollution_absorption_multiplier = 0.01

  for _, spawner in pairs(data.raw["unit-spawner"] or {}) do
    local absorptions = spawner.absorptions_per_second
    local pollution_absorption = absorptions and absorptions.pollution

    if type(pollution_absorption) == "table" then
      local absolute = tonumber(pollution_absorption.absolute)
      local proportional = tonumber(pollution_absorption.proportional)

      if absolute then
        pollution_absorption.absolute = absolute * spawner_pollution_absorption_multiplier
      end
      if proportional then
        pollution_absorption.proportional = proportional * spawner_pollution_absorption_multiplier
      end
    end
  end
end

-- Portable non-empty vanilla storage tanks. Generate one tagged item/proxy
-- pair for every loaded fluid after all prototype changes. A compatible
-- standalone implementation remains the sole owner when it is installed.
if not (mods["early-stack-size"] or mods["portable-storage-tanks"]) then
  require("prototypes.portable_storage_tanks")
end

require("prototypes.portable_cave_accumulators")
require("prototypes.solar_display")

-- Engine units can be made by hand as well as in assembling machines.
-- Keep their existing ingredients, time, results and research unlock.
local engine_unit_recipe = data.raw.recipe and data.raw.recipe["engine-unit"]
if engine_unit_recipe then
  engine_unit_recipe.categories = {"crafting"}
end

-- Thermal power follows Concrete in every mode.
require("prototypes.heating_tower_progression_final_fixes")

require("prototypes.fortified_spiral")
require("prototypes.fortified_combat")
require("prototypes.darkness_enemies")

require("prototypes.mech_armor_recipe")
require("prototypes.underground_cursor_return")

require("prototypes.coin_maker_final_fixes")
