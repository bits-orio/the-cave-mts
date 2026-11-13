local physical = require("scripts.player_physical")
local child_state = require("scripts.cave_child_state")
-- Fortified Underground Vault raid for The Cave.
-- New/unentered raids use the current Fortified room layout. Previously entered legacy raids
-- retain their original layout and deadline until closure.

local game_settings = require("scripts.game_settings")
local hash = require("scripts.lib.hash")
local depth_levels = require("scripts.depth_levels")
local advancing_zones = require("scripts.advancing_zones")
local cave_evolution = require("scripts.cave_evolution")
local region_features = require("scripts.region_features")
local reward_policy = require("scripts.reward_policy")
local cave_placement = require("scripts.cave_placement")
local world = require("scripts.world")

local group_rewards = require("scripts.fortified_vault_rewards")

local fortified_vaults = {}
local spiral = require("scripts.fortified_spiral")
local panel_text = require("scripts.fortified_panel_text")

-- Control new entrances only. Saved vaults keep their access and normal lifetime.
function fortified_vaults.enabled()
    return game_settings.enabled("the-cave-fortified-cave", true)
end

local SURFACE_PREFIX = "the-cave-fortified-vault-"
local ENTRANCE_NAMES = {
    ["the-cave-fortified-vault-entrance-1"] = true,
    ["the-cave-fortified-vault-entrance-2"] = true,
}
local EXIT_NAMES = {
    ["the-cave-fortified-vault-exit-1"] = true,
    ["the-cave-fortified-vault-exit-2"] = true,
}
local CACHE_NAMES = {
    ["the-cave-fortified-cache-standard"] = "standard",
    ["the-cave-fortified-cache-secure"] = "secure",
    ["the-cave-fortified-cache-high-security"] = "high",
}

local INFO_PANEL = "display-panel"
local POWER_POLE = "the-cave-fortified-vault-power-pole"
local LOWER_LAMP = "the-cave-fortified-vault-lamp"
local ENEMY_LASER = "the-cave-enemy-laser-turret"
local VAULT_ROCK = "the-cave-fortified-vault-rock"

local RAID_MINUTES = 30
local RAID_TICKS = RAID_MINUTES * 60 * 60
local TIMER_UPDATE_INTERVAL = 60
local PORTAL_LABEL_LAYOUT_VERSION = 1
local SAFE_HALF_EXTENT = 35 -- exact 70x70 combat-safe square
local ENEMY_SPAWN_BUFFER = 10 -- defenders begin at least ten tiles beyond the visible safe-zone edge
local SAFE_SPAWN_MARGIN = 0
local ARRIVAL_CLEAR_HALF_EXTENT = 8
local FLOOR_TILE_BATCH = 40000
local SAFE_ZONE_RENDER_VERSION = 1
local SAFE_ZONE_LINE_COLOR = { r = 0.20, g = 1, b = 0.32, a = 0.92 }

local STRONGHOLD_COUNT = 8
local CACHES_PER_STRONGHOLD = { standard = 8, secure = 6, high = 4 }
local GROUP_DEFENDERS = {
    medium = { biters = 15, spitters = 10, spawners = 2, worms = 1, guns = 2, lasers = 1 },
    hard = { biters = 20, spitters = 15, spawners = 3, worms = 2, guns = 3, lasers = 2 },
    nightmare = { biters = 25, spitters = 20, spawners = 4, worms = 3, guns = 4, lasers = 3 },
}
local TIER_LAYOUT = {}
for level, defence in pairs(GROUP_DEFENDERS) do
    TIER_LAYOUT[level] = {
        size = 350, standard = 64, secure = 48, high = 32, strongholds = STRONGHOLD_COUNT,
        units = (defence.biters + defence.spitters) * STRONGHOLD_COUNT,
        spawners = defence.spawners * STRONGHOLD_COUNT,
        worms = defence.worms * STRONGHOLD_COUNT,
        guns = defence.guns * STRONGHOLD_COUNT,
        lasers = defence.lasers * STRONGHOLD_COUNT,
    }
end

local function advancing_level_at(surface, position)
    if not (advancing_zones.is_active()
        and advancing_zones.is_main_surface(surface)
        and position) then
        return nil
    end
    local zone = advancing_zones.zone_index_at_y(position.y)
    if zone <= 9 then return "medium", zone end
    if zone <= 19 then return "hard", zone end
    return "nightmare", zone
end

function fortified_vaults.level_for_position(surface, position, fallback)
    local level = advancing_level_at(surface, position)
    return level or fallback or "medium"
end

local ALARM_UNITS = {
    standard = 3,
    secure = 4,
    high = 5,
}

local JACKPOT_CHANCE = { standard = 0.05, secure = 0.12, high = 0.24 }

-- Each selected item is inserted as one bundle. The previous 18/24/30 repeated
-- pick loop multiplied the same item several times and was the source of the
-- multi-thousand-item caches.
local CACHE_UNIQUE_TYPES = {
    standard = { min = 4, max = 6 },
    secure = { min = 5, max = 7 },
    high = { min = 6, max = 8 },
}
local JACKPOT_UNIQUE_TYPES = {
    standard = { min = 2, max = 3 },
    secure = { min = 3, max = 5 },
    high = { min = 4, max = 7 },
}
local CACHE_TIER_ID = { standard = 1, secure = 2, high = 3 }

-- Fortified Vault rewards are discovered dynamically from these four visible
-- item-tab groups. Selecting the group before the item prevents the much larger
-- intermediate-products group from drowning out Logistics, Production or Combat.
local REWARD_ITEM_GROUPS = {
    logistics = true,
    production = true,
    ["intermediate-products"] = true,
    combat = true,
}
local REWARD_ITEM_GROUP_ORDER = {
    "logistics", "production", "intermediate-products", "combat",
}
local REWARD_DIVERSITY_ATTEMPTS = 12

-- These are cursor/planning tools that happen to live in normal item-tab groups,
-- but are not physical loot. Rail planners are intentionally not excluded: the
-- user explicitly wants rails to remain a possible Logistics reward.
local NON_PHYSICAL_REWARD_ITEM_TYPES = {
    blueprint = true,
    ["blueprint-book"] = true,
    ["copy-paste-tool"] = true,
    ["deconstruction-item"] = true,
    ["selection-tool"] = true,
    ["upgrade-item"] = true,
}

-- Absolute deny-list for Fortified Vault rewards only. These prototypes remain
-- untouched everywhere else in The Cave and in Factorio.
local BLACKLISTED_ITEMS = {
    ["promethium-science-pack"] = true,
    ["cryogenic-science-pack"] = true,
    ["electromagnetic-science-pack"] = true,
    ["agricultural-science-pack"] = true,
    ["metallurgic-science-pack"] = true,
    ["space-science-pack"] = true,
    ["fusion-power-cell"] = true,
    ["lithium-plate"] = true,
    ["lithium"] = true,
    ["supercapacitor"] = true,
    ["superconductor"] = true,
    ["carbon-fiber"] = true,
    ["biter-egg"] = true,
    ["tungsten-plate"] = true,
    ["tungsten-carbide"] = true,
    ["quantum-processor"] = true,
    ["fusion-generator"] = true,
    ["fusion-reactor"] = true,
    ["biolab"] = true,
    ["spidertron"] = true,
    ["cryogenic-plant"] = true,
    ["mech-armor"] = true,
    ["capture-robot-rocket"] = true,
    ["railgun-turret"] = true,
    ["tesla-turret"] = true,
    ["fusion-reactor-equipment"] = true,
    ["teslagun"] = true,
    ["railgun"] = true,
}

local SCIENCE_PACKS = {
    ["automation-science-pack"] = true,
    ["logistic-science-pack"] = true,
    ["military-science-pack"] = true,
    ["chemical-science-pack"] = true,
    ["production-science-pack"] = true,
    ["utility-science-pack"] = true,
}
local SCIENCE_TOTAL_CAP = 400

-- Per-Vault hard ceilings. Normal rewards, jackpots, every cache and every
-- player all consume the same record-local budgets.
local ITEM_CAPS = {
    ["iron-plate"] = 1500,
    ["copper-plate"] = 1500,
    ["steel-plate"] = 500,
    ["stone-brick"] = 1000,
    ["pipe"] = 500,
    ["repair-pack"] = 200,
    ["electronic-circuit"] = 1000,
    ["advanced-circuit"] = 700,
    ["processing-unit"] = 500,
    ["electric-engine-unit"] = 200,
    ["flying-robot-frame"] = 100,
    ["low-density-structure"] = 100,
    ["rocket-fuel"] = 100,

    ["electric-mining-drill"] = 50,
    ["assembling-machine-2"] = 30,
    ["assembling-machine-3"] = 15,
    ["electric-furnace"] = 30,
    ["chemical-plant"] = 20,
    ["oil-refinery"] = 10,
    ["centrifuge"] = 5,
    ["roboport"] = 10,
    ["nuclear-reactor"] = 2,

    ["construction-robot"] = 100,
    ["logistic-robot"] = 100,
    ["bulk-inserter"] = 100,
    ["stack-inserter"] = 50,
    ["rail"] = 400,

    ["transport-belt"] = 500,
    ["fast-transport-belt"] = 400,
    ["express-transport-belt"] = 300,
    ["turbo-transport-belt"] = 100,
    ["underground-belt"] = 50,
    ["fast-underground-belt"] = 30,
    ["express-underground-belt"] = 10,
    ["turbo-underground-belt"] = 6,
    ["splitter"] = 40,
    ["fast-splitter"] = 30,
    ["express-splitter"] = 20,
    ["turbo-splitter"] = 10,

    ["gun-turret"] = 50,
    ["laser-turret"] = 20,
    ["firearm-magazine"] = 1000,
    ["piercing-rounds-magazine"] = 500,
    ["uranium-rounds-magazine"] = 100,
    ["explosive-rocket"] = 100,
    ["railgun-ammo"] = 20,

    ["speed-module"] = 50,
    ["efficiency-module"] = 50,
    ["productivity-module"] = 50,
    ["quality-module"] = 50,
    ["speed-module-2"] = 20,
    ["efficiency-module-2"] = 20,
    ["productivity-module-2"] = 20,
    ["quality-module-2"] = 20,
    ["speed-module-3"] = 5,
    ["efficiency-module-3"] = 5,
    ["productivity-module-3"] = 5,
    ["quality-module-3"] = 5,

    ["modular-armor"] = 1,
    ["power-armor"] = 1,
    ["power-armor-mk2"] = 1,
    ["fission-reactor-equipment"] = 1,
    ["battery-equipment"] = 4,
    ["battery-mk2-equipment"] = 2,
    ["energy-shield-equipment"] = 4,
    ["energy-shield-mk2-equipment"] = 2,
    ["personal-roboport-equipment"] = 2,
    ["personal-roboport-mk2-equipment"] = 1,
    ["exoskeleton-equipment"] = 2,
    ["personal-laser-defense-equipment"] = 2,
    ["solar-panel-equipment"] = 4,
    ["belt-immunity-equipment"] = 2,
    ["discharge-defense-equipment"] = 2,
    ["discharge-defense-remote"] = 1,

    ["flamethrower-turret"] = 10,
    ["artillery-turret"] = 2,
    ["rocket-turret"] = 10,
    ["land-mine"] = 100,
    ["defender-capsule"] = 50,
    ["distractor-capsule"] = 30,
    ["destroyer-capsule"] = 20,
    ["atomic-bomb"] = 2,
    ["artillery-shell"] = 20,
}

local ARMOR_ITEMS = {
    ["modular-armor"] = true,
    ["power-armor"] = true,
    ["power-armor-mk2"] = true,
}

local EQUIPMENT_ITEMS = {
    ["fission-reactor-equipment"] = true,
    ["battery-equipment"] = true,
    ["battery-mk2-equipment"] = true,
    ["energy-shield-equipment"] = true,
    ["energy-shield-mk2-equipment"] = true,
    ["personal-roboport-equipment"] = true,
    ["personal-roboport-mk2-equipment"] = true,
    ["exoskeleton-equipment"] = true,
    ["personal-laser-defense-equipment"] = true,
    ["solar-panel-equipment"] = true,
    ["belt-immunity-equipment"] = true,
    ["discharge-defense-equipment"] = true,
}

local HIGH_SECURITY_ONLY = {
    ["modular-armor"] = true,
    ["power-armor"] = true,
    ["power-armor-mk2"] = true,
    ["fission-reactor-equipment"] = true,
    ["battery-equipment"] = true,
    ["battery-mk2-equipment"] = true,
    ["energy-shield-equipment"] = true,
    ["energy-shield-mk2-equipment"] = true,
    ["personal-roboport-equipment"] = true,
    ["personal-roboport-mk2-equipment"] = true,
    ["exoskeleton-equipment"] = true,
    ["personal-laser-defense-equipment"] = true,
    ["solar-panel-equipment"] = true,
    ["belt-immunity-equipment"] = true,
    ["discharge-defense-equipment"] = true,
    ["speed-module-3"] = true,
    ["efficiency-module-3"] = true,
    ["productivity-module-3"] = true,
    ["quality-module-3"] = true,
    ["nuclear-reactor"] = true,
    ["railgun-ammo"] = true,
}

-- Space Age items that belong to a particular Cave coordinate region. Base-game
-- rewards remain universal, but a planetary reward cannot leak into another
-- planet's region merely because its recipe was researched elsewhere.
local PLANET_ITEM_REGION = {
    ["calcite"] = "vulcanus",
    ["tungsten-ore"] = "vulcanus",
    ["foundry"] = "vulcanus",
    ["big-mining-drill"] = "vulcanus",
    ["turbo-transport-belt"] = "vulcanus",
    ["turbo-underground-belt"] = "vulcanus",
    ["turbo-splitter"] = "vulcanus",
    ["speed-module-3"] = "vulcanus",
    ["artillery-turret"] = "vulcanus",
    ["artillery-wagon"] = "vulcanus",
    ["artillery-shell"] = "vulcanus",

    ["scrap"] = "fulgora",
    ["holmium-ore"] = "fulgora",
    ["holmium-plate"] = "fulgora",
    ["electromagnetic-plant"] = "fulgora",
    ["recycler"] = "fulgora",
    ["lightning-rod"] = "fulgora",
    ["lightning-collector"] = "fulgora",
    ["tesla-ammo"] = "fulgora",
    ["efficiency-module-3"] = "fulgora",
    ["quality-module-3"] = "fulgora",

    ["yumako"] = "gleba",
    ["jellynut"] = "gleba",
    ["yumako-seed"] = "gleba",
    ["jellynut-seed"] = "gleba",
    ["yumako-mash"] = "gleba",
    ["jelly"] = "gleba",
    ["bioflux"] = "gleba",
    ["nutrients"] = "gleba",
    ["spoilage"] = "gleba",
    ["pentapod-egg"] = "gleba",
    ["biochamber"] = "gleba",
    ["agricultural-tower"] = "gleba",
    ["heating-tower"] = "gleba",
    ["rocket-turret"] = "gleba",
    ["stack-inserter"] = "gleba",
    ["productivity-module-3"] = "gleba",

    ["ice"] = "aquilo",
    ["railgun-ammo"] = "aquilo",
}

local PLANET_DISCOVERY_TECH_REGION = {
    ["planet-discovery-vulcanus"] = "vulcanus",
    ["planet-discovery-fulgora"] = "fulgora",
    ["planet-discovery-gleba"] = "gleba",
    ["planet-discovery-aquilo"] = "aquilo",
}
local PLANET_SCIENCE_REGION = {
    ["metallurgic-science-pack"] = "vulcanus",
    ["electromagnetic-science-pack"] = "fulgora",
    ["agricultural-science-pack"] = "gleba",
    ["cryogenic-science-pack"] = "aquilo",
}

local function root()
    storage.the_cave_fortified_vaults = storage.the_cave_fortified_vaults or {}
    local r = storage.the_cave_fortified_vaults
    r.next_id = r.next_id or 1
    r.by_id = r.by_id or {}
    r.by_entity = r.by_entity or {}
    r.by_surface = r.by_surface or {}
    r.hacks = r.hacks or {}
    r.alarm_units = r.alarm_units or {}
    r.flashlight_state = r.flashlight_state or {}
    r.pending_respawns = r.pending_respawns or {}
    return r
end

local function copy_position(position)
    return { x = position.x, y = position.y }
end

local function valid_surface(index)
    local surface = index and game.surfaces[index]
    return surface and surface.valid and surface or nil
end

-- A sealed Vault keeps its child surface for save/reference safety, while the
-- force-local Remote View entry is hidden for every current (and future) force.
local function set_child_surface_hidden(record, hidden, only_force)
    local surface = record and valid_surface(record.child_surface_index)
    if not surface then return end

    local function apply(force)
        if force and force.valid then force.set_surface_hidden(surface, hidden) end
    end

    if only_force then
        apply(only_force)
    else
        for _, force in pairs(game.forces) do apply(force) end
    end
end

local function entity_exists(name)
    return prototypes and prototypes.entity and prototypes.entity[name] ~= nil
end

local function item_exists(name)
    return prototypes and prototypes.item and prototypes.item[name] ~= nil
end

local function item_group_name(name)
    local prototype = prototypes and prototypes.item and prototypes.item[name]
    local group = prototype and prototype.group
    return group and group.name or nil
end

local function item_is_in_space_group(name)
    return item_group_name(name) == "space"
end

local function item_is_in_reward_group(name)
    local group = item_group_name(name)
    return group and REWARD_ITEM_GROUPS[group] == true or false
end

local function item_is_blacklisted(name)
    return BLACKLISTED_ITEMS[name] == true or reward_policy.is_blocked(name)
end

local function item_is_armor(name)
    if ARMOR_ITEMS[name] then return true end
    local prototype = prototypes and prototypes.item and prototypes.item[name]
    return prototype and prototype.type == "armor" or false
end

local function item_is_equipment(name)
    if EQUIPMENT_ITEMS[name] then return true end
    local prototype = prototypes and prototypes.item and prototypes.item[name]
    return prototype and prototype.place_as_equipment_result ~= nil or false
end

local LOW_COUNT_ENTITY_TYPES = {
    ["assembling-machine"] = true,
    furnace = true,
    ["mining-drill"] = true,
    lab = true,
    beacon = true,
    roboport = true,
    reactor = true,
    generator = true,
    ["burner-generator"] = true,
    ["rocket-silo"] = true,
    ["ammo-turret"] = true,
    ["electric-turret"] = true,
    ["fluid-turret"] = true,
    ["artillery-turret"] = true,
}
local SINGLE_ENTITY_TYPES = {
    locomotive = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
    car = true,
    ["spider-vehicle"] = true,
}

local function item_cap(name)
    if SCIENCE_PACKS[name] then return SCIENCE_TOTAL_CAP end
    local explicit = ITEM_CAPS[name]
    if explicit then return explicit end

    -- Dynamic category entries use their runtime item/entity kind to receive a
    -- conservative hard ceiling even when another mod adds them to the pool.
    local prototype = prototypes and prototypes.item and prototypes.item[name]
    if not prototype then return 0 end
    local stack_size = math.max(1, tonumber(prototype.stack_size) or 1)
    if item_is_armor(name) or item_is_equipment(name) or prototype.type == "gun" then return 1 end
    if prototype.type == "capsule" then return math.min(50, stack_size) end
    if prototype.type == "ammo" then return math.min(100, stack_size * 2) end
    if prototype.type == "module" then return math.min(20, stack_size) end

    local placed = prototype.place_result
    local placed_type = placed and placed.type
    if placed_type and SINGLE_ENTITY_TYPES[placed_type] then return 1 end
    if placed_type and LOW_COUNT_ENTITY_TYPES[placed_type] then return math.min(10, stack_size) end
    if placed_type then return math.min(50, stack_size) end
    if stack_size <= 1 then return 1 end
    return math.min(100, stack_size * 2)
end

local function space_age_active()
    return script and script.active_mods and script.active_mods["space-age"] ~= nil
end

local function record_region(record)
    if record and record.region_id then return record.region_id end
    local position = record and record.entrance_position
    if not position then return "nauvis" end
    local region = region_features.region_at(position.x, position.y) or "nauvis"
    if record then record.region_id = region end
    return region
end

-- Infer the planet family of unlocked recipes from the official technology
-- graph. This supplements the explicit item map and keeps dynamically scanned
-- Production/Combat items from leaking across coordinate regions.
local recipe_region_cache = nil

local function direct_technology_region(technology)
    if not technology then return nil end
    local discovery = PLANET_DISCOVERY_TECH_REGION[technology.name]
    if discovery then return discovery end

    local found = {}
    local has_cryogenic = false
    for _, ingredient in ipairs(technology.research_unit_ingredients or {}) do
        if ingredient.name == "promethium-science-pack" then return "space" end
        local region = PLANET_SCIENCE_REGION[ingredient.name]
        if region == "aquilo" then has_cryogenic = true
        elseif region then found[region] = true end
    end
    if has_cryogenic then return "aquilo" end
    local only, count = nil, 0
    for region in pairs(found) do only, count = region, count + 1 end
    if count == 1 then return only end
    if count > 1 then return "space" end
    return nil
end

local function build_recipe_region_map()
    if recipe_region_cache then return recipe_region_cache end
    local technology_regions = {}
    local visiting = {}

    local function infer(technology)
        if not technology then return nil end
        local name = technology.name
        if technology_regions[name] ~= nil then
            return technology_regions[name] or nil
        end
        if visiting[name] then return nil end
        visiting[name] = true

        local region = direct_technology_region(technology)
        if not region then
            for _, prerequisite in pairs(technology.prerequisites or {}) do
                local inherited = infer(prerequisite)
                if inherited then
                    if region and region ~= inherited then region = "space" break end
                    region = inherited
                end
            end
        end
        visiting[name] = nil
        technology_regions[name] = region or false
        return region
    end

    local recipe_regions = {}
    for _, technology in pairs((prototypes and prototypes.technology) or {}) do
        local region = infer(technology)
        if region then
            for _, effect in ipairs(technology.effects or {}) do
                if effect.type == "unlock-recipe" and effect.recipe then
                    local previous = recipe_regions[effect.recipe]
                    if previous and previous ~= region then recipe_regions[effect.recipe] = "space"
                    else recipe_regions[effect.recipe] = region end
                end
            end
        end
    end
    recipe_region_cache = recipe_regions
    return recipe_region_cache
end

local function recipe_matches_region(record, recipe_name)
    if not space_age_active() then return true end
    local required = build_recipe_region_map()[recipe_name]
    return not required or required == record_region(record)
end

local function build_available_reward_items(force, record)
    local available = {}
    -- Fortified Vault loot is a prize table, not a research progression table.
    -- Prototype existence is the only availability gate, so unresearched items
    -- are valid and Space Age-only items disappear cleanly when that mod is absent.
    for name, prototype in pairs((prototypes and prototypes.item) or {}) do
        if not NON_PHYSICAL_REWARD_ITEM_TYPES[prototype.type] then
            available[name] = true
        end
    end
    return available
end

local function item_matches_region(record, name)
    if not space_age_active() then return true end
    local required = PLANET_ITEM_REGION[name]
    return not required or required == record_region(record)
end

local function reward_item_is_allowed(record, cache_tier, name, available_items)
    if not item_exists(name) or item_is_blacklisted(name) then return false end
    return available_items and available_items[name] == true or false
end

local function tile_exists(name)
    return prototypes and prototypes.tile and prototypes.tile[name] ~= nil
end

local function find_unit(surface_index, unit_number, names)
    if not unit_number then return nil end
    local surface = valid_surface(surface_index)
    if not surface then return nil end
    for _, entity in pairs(surface.find_entities_filtered { name = names }) do
        if entity.valid and entity.unit_number == unit_number then return entity end
    end
    return nil
end

local function record_for_entity(entity)
    if not (entity and entity.valid and entity.unit_number) then return nil end
    local r = root()
    local id = r.by_entity[entity.unit_number]
    return id and r.by_id[id] or nil
end

local function record_for_surface(surface)
    if not (surface and surface.valid) then return nil end
    local id = root().by_surface[surface.index]
    return id and root().by_id[id] or nil
end

function fortified_vaults.is_fortified_vault_surface(surface)
    return surface and surface.valid and surface.name:sub(1, #SURFACE_PREFIX) == SURFACE_PREFIX
end

local function draw_label(surface, position, text, color, scale)
    local obj = rendering.draw_text {
        text = text,
        surface = surface,
        target = position,
        color = color or { r = 1, g = 1, b = 1 },
        alignment = "center",
        vertical_alignment = "middle",
        scale = scale or 1.15,
        only_in_alt_mode = false,
        use_rich_text = true,
    }
    return obj and obj.id or nil
end

local function render_object(id)
    if not id then return nil end
    local ok, obj = pcall(rendering.get_object_by_id, id)
    return ok and obj or nil
end

local function destroy_render(id)
    local obj = render_object(id)
    if obj then pcall(function() obj.destroy() end) end
end

local function destroy_safe_zone_render(record)
    if not record then return end
    destroy_render(record.safe_zone_outline_id)
    destroy_render(record.safe_zone_label_id)
    record.safe_zone_outline_id = nil
    record.safe_zone_label_id = nil
end

local function ensure_safe_zone_render(record)
    if not record or record.status == "closed" then return end
    local surface = valid_surface(record.child_surface_index)
    local force = game.forces[record.owner_force_index]
    if not (surface and force and force.valid) then return end

    if record.safe_zone_render_version ~= SAFE_ZONE_RENDER_VERSION then
        destroy_safe_zone_render(record)
        record.safe_zone_render_version = SAFE_ZONE_RENDER_VERSION
    end
    if render_object(record.safe_zone_outline_id)
        and render_object(record.safe_zone_label_id) then return end
    destroy_safe_zone_render(record)

    local outline = nil
    local label = nil
    local ok = pcall(function()
        outline = rendering.draw_rectangle {
            surface = surface,
            left_top = { x = -SAFE_HALF_EXTENT, y = -SAFE_HALF_EXTENT },
            right_bottom = { x = SAFE_HALF_EXTENT, y = SAFE_HALF_EXTENT },
            color = SAFE_ZONE_LINE_COLOR,
            width = 2,
            filled = false,
            forces = { force },
            only_in_alt_mode = false,
            draw_on_ground = false,
            render_mode = "game",
        }
        label = rendering.draw_text {
            surface = surface,
            target = { x = 0, y = -SAFE_HALF_EXTENT - 1.5 },
            text = { "the-cave-fortified-vault.safe-zone-label", SAFE_HALF_EXTENT * 2 },
            color = SAFE_ZONE_LINE_COLOR,
            scale = 1.05,
            alignment = "center",
            vertical_alignment = "bottom",
            forces = { force },
            only_in_alt_mode = false,
            draw_on_ground = false,
            render_mode = "game",
        }
    end)
    if not ok or not (outline and outline.valid and label and label.valid) then
        if outline and outline.valid then pcall(function() outline.destroy() end) end
        if label and label.valid then pcall(function() label.destroy() end) end
        return
    end
    record.safe_zone_outline_id = outline.id
    record.safe_zone_label_id = label.id
end

local function cleanup_legacy_closed_labels()
    for _, object in pairs(rendering.get_all_objects("the-cave")) do
        if object.valid and object.type == "text" then
            local ok, text = pcall(function() return object.text end)
            if ok and type(text) == "table"
                and text[1] == "the-cave-fortified-vault.label-sealed" then
                pcall(function() object.destroy() end)
            end
        end
    end
end

local function apply_pitch_black(surface)
    if not (surface and surface.valid) then return end
    pcall(function() surface.always_day = false end)
    pcall(function() surface.freeze_daytime = true end)
    pcall(function() surface.daytime = 0.5 end)
    pcall(function() surface.dusk = 0.25 end)
    pcall(function() surface.evening = 0.45 end)
    pcall(function() surface.morning = 0.55 end)
    pcall(function() surface.dawn = 0.75 end)
    pcall(function() surface.show_clouds = false end)
    pcall(function() surface.brightness_visual_weights = { r = 1, g = 1, b = 1 } end)
    pcall(function() surface.min_brightness = 0 end)
    pcall(function() surface.solar_power_multiplier = 0 end)
end

local function clear_site(surface, position, radius, protected)
    radius = radius or 0.6
    for _, entity in pairs(surface.find_entities_filtered {
        area = {
            { position.x - radius, position.y - radius },
            { position.x + radius, position.y + radius },
        },
    }) do
        local keep = protected and entity.unit_number and protected[entity.unit_number]
        if entity.valid and not keep and entity.type ~= "character" and entity.name ~= "character" then
            entity.destroy()
        end
    end
end

local function create_fixed(surface, name, position, force, clear_radius)
    if not entity_exists(name) then return nil end
    if clear_radius then clear_site(surface, position, clear_radius) end
    local ok, entity = pcall(function()
        return surface.create_entity {
            name = name,
            position = position,
            force = force,
            create_build_effect_smoke = false,
        }
    end)
    if not ok or not (entity and entity.valid) then return nil end
    entity.destructible = false
    entity.minable_flag = false
    return entity
end

local function portal_variant(seed, position, upper)
    local second = hash.roll(seed, math.floor(position.x), math.floor(position.y), upper and 9101 or 9102) >= 0.5
    if upper then return second and "the-cave-fortified-vault-entrance-2" or "the-cave-fortified-vault-entrance-1" end
    return second and "the-cave-fortified-vault-exit-2" or "the-cave-fortified-vault-exit-1"
end

local function setup_panel(panel, record)
    if not (panel and panel.valid) then return end
    pcall(function() panel.operable = false end)
    pcall(function() panel.display_panel_icon = { type = "virtual", name = "signal-info" } end)
    -- Factorio 2.1 requires plain text here. The HUD keeps its localised rules.
    local text_key = record and not record.spiral_layout_version
        and "the-cave-fortified-vault.panel-text" or spiral.text_key(record, "rules")
    panel.display_panel_text = assert(panel_text[text_key], "Missing Fortified panel text: " .. text_key)
    pcall(function() panel.display_panel_always_show = true end)
    pcall(function() panel.display_panel_show_in_chart = true end)
end

local function get_copper_connector(entity)
    if not (entity and entity.valid and entity.get_wire_connector) then return nil end
    local ok, connector = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    end)
    if not ok or not (connector and connector.valid) then return nil end
    return connector
end

local function connect_cross_surface_power(upper_pole, lower_pole)
    local upper = get_copper_connector(upper_pole)
    local lower = get_copper_connector(lower_pole)
    if not (upper and lower) then return false end
    local ok_connected, connected = pcall(function() return upper.is_connected_to(lower, defines.wire_origin.player)
            or upper.is_connected_to(lower, defines.wire_origin.script) end)
    if ok_connected and connected then return true end
    local ok = pcall(function()
        upper.connect_to(lower, false, defines.wire_origin.script)
    end)
    if not ok then return false end
    local verify_ok, verify = pcall(function() return upper.is_connected_to(lower, defines.wire_origin.player)
            or upper.is_connected_to(lower, defines.wire_origin.script) end)
    return verify_ok and verify == true
end

local function ensure_upper_indicator_lamp(record)
    if not record then return nil end
    local surface = valid_surface(record.parent_surface_index)
    local pole = find_unit(record.parent_surface_index, record.upper_pole_unit, POWER_POLE)
    if not (surface and pole) then return nil end
    local lamp = find_unit(record.parent_surface_index, record.upper_lamp_unit, LOWER_LAMP)
    local target = { x = pole.position.x + 1, y = pole.position.y }
    if not lamp then
        clear_site(surface, target, 0.7, { [pole.unit_number] = true })
        local force = game.forces[record.owner_force_index] or game.forces.player
        lamp = create_fixed(surface, LOWER_LAMP, target, force, nil)
        record.upper_lamp_unit = lamp and lamp.unit_number or nil
    elseif math.abs(lamp.position.x - target.x) > 0.1 or math.abs(lamp.position.y - target.y) > 0.1 then
        pcall(function() lamp.teleport(target) end)
    end
    if lamp then
        pcall(function() lamp.operable = false end)
        pcall(function() lamp.always_on = true end)
    end
    return lamp
end

local function ensure_power_bridge(record)
    if not record then return false end
    local child = valid_surface(record.child_surface_index)
    if child and record.power_connections_surface == child then return true end
    local upper = find_unit(record.parent_surface_index, record.upper_pole_unit, POWER_POLE)
    if not upper then return false end
    ensure_upper_indicator_lamp(record)
    local lower = find_unit(record.child_surface_index, record.lower_pole_unit, POWER_POLE)
    if not lower then return false end
    local connected = connect_cross_surface_power(upper, lower)
    local upper_lamp = find_unit(record.parent_surface_index, record.upper_lamp_unit, LOWER_LAMP)
    if upper_lamp then
        pcall(function() upper_lamp.operable = false end)
        pcall(function() upper_lamp.always_on = true end)
    end
    local lamp = find_unit(record.child_surface_index, record.lower_lamp_unit, LOWER_LAMP)
    if lamp then
        pcall(function() lamp.operable = false end)
        pcall(function() lamp.always_on = true end)
    end
    if connected then record.power_connections_surface = child end
    return connected
end

local function format_timer(record, tick)
    local remaining = record.close_tick and math.max(0, record.close_tick - tick)
        or (record.spiral_layout_version and spiral.stage_minutes(1,record) * 3600 or RAID_TICKS)
    local seconds = math.ceil(remaining / 60)
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function timer_color(record, tick)
    if not record.timer_started_tick then return { r = 1, g = 0.85, b = 0.18 } end
    local remaining = math.max(0, (record.close_tick or tick) - tick)
    if remaining <= 60 * 60 then return { r = 1, g = 0.12, b = 0.05 } end
    if remaining <= 5 * 60 * 60 then return { r = 1, g = 0.48, b = 0.08 } end
    return { r = 0.30, g = 1, b = 0.40 }
end

local function update_timer_label(record, upper, tick)
    if record.status == "closed" then return end
    local surface = valid_surface(upper and record.parent_surface_index or record.child_surface_index)
    local position = upper and record.entrance_position or record.exit_position
    if not (surface and position) then return end
    local field = upper and "upper_timer_id" or "lower_timer_id"
    local obj = render_object(record[field])
    if not obj then
        record[field] = draw_label(surface, { x = position.x, y = position.y - 2.15 },
            format_timer(record, tick), timer_color(record, tick), 1.10)
        obj = render_object(record[field])
    end
    if obj then
        pcall(function() obj.text = format_timer(record, tick) end)
        pcall(function() obj.color = timer_color(record, tick) end)
    end
end

local function update_timer_labels(record, tick)
    update_timer_label(record, true, tick)
    if record.child_surface_index then update_timer_label(record, false, tick) end
end

local function ensure_portal_label(record, upper)
    if not record or record.status == "closed" then return nil end
    local surface = valid_surface(upper and record.parent_surface_index or record.child_surface_index)
    local position = upper and record.entrance_position or record.exit_position
    if not (surface and position) then return nil end
    local field = upper and "entrance_label_id" or "exit_label_id"
    local timer_field = upper and "upper_timer_id" or "lower_timer_id"
    local version_field = upper and "upper_portal_label_layout_version"
        or "lower_portal_label_layout_version"
    if record[version_field] ~= PORTAL_LABEL_LAYOUT_VERSION then
        destroy_render(record[field])
        destroy_render(record[timer_field])
        record[field] = nil
        record[timer_field] = nil
        record[version_field] = PORTAL_LABEL_LAYOUT_VERSION
    end
    if render_object(record[field]) then return record[field] end
    local text = { upper and "the-cave-fortified-vault.entrance-name"
        or "the-cave-fortified-vault.return-label" }
    local color = upper and { r = 1, g = 0.72, b = 0.12 } or { r = 0.25, g = 0.85, b = 1 }
    record[field] = draw_label(surface, { x = position.x, y = position.y - 3.4 },
        text, color, upper and 1.25 or 1.2)
    return record[field]
end

local function zone_layout(level, advancing_balance)
    return TIER_LAYOUT[level] or TIER_LAYOUT.medium
end

local function create_map_gen_settings(record, parent)
    local layout = zone_layout(record.level_id, record.advancing_balance)
    local size = math.max(64, layout.size)
    return {
        seed = record.seed,
        width = size,
        height = size,
        starting_area = 1,
        starting_points = { { x = 0, y = 0 } },
        peaceful_mode = parent.map_gen_settings and parent.map_gen_settings.peaceful_mode or false,
        default_enable_all_autoplace_controls = false,
        autoplace_controls = {},
    }
end

local function make_indestructible(entity)
    if entity and entity.valid then
        entity.destructible = false
        entity.minable_flag = false
    end
    return entity
end

local function create_wall(surface, x, y)
    if not entity_exists("stone-wall") then return nil end
    local entity = surface.create_entity { name = "stone-wall", position = { x = x + 0.5, y = y + 0.5 }, force = "enemy" }
    return make_indestructible(entity)
end

local function inside_safe_square(position, margin)
    margin = margin or 0
    return math.abs(position.x) <= SAFE_HALF_EXTENT + margin
        and math.abs(position.y) <= SAFE_HALF_EXTENT + margin
end

local function inside_arrival_clear_pad(position)
    return math.abs(position.x) <= ARRIVAL_CLEAR_HALF_EXTENT
        and math.abs(position.y) <= ARRIVAL_CLEAR_HALF_EXTENT
end

local function boundary_radius(half)
    -- Old 700-wide surfaces retain their original inset boundary. New Vaults
    -- have a true 350-tile diameter, with no extra eight-tile inset.
    if half == 175 then return half end
    return math.max(SAFE_HALF_EXTENT + 18, half - 8)
end

local function inside_round_boundary(position, half, margin)
    margin = margin or 0
    local radius = boundary_radius(half) - margin
    if radius <= 0 then return false end
    local nx = position.x / radius
    local ny = position.y / radius
    return (nx * nx + ny * ny) <= 1
end

local function choose_floor_tiles()
    local primary = tile_exists("stone-path") and "stone-path" or (tile_exists("refined-concrete") and "refined-concrete" or nil)
    local alt1 = tile_exists("dirt-7") and "dirt-7" or primary
    local alt2 = tile_exists("dirt-6") and "dirt-6" or primary
    return primary, alt1, alt2
end

local function floor_tile_name(record, x, y, half, primary, alt1, alt2)
    local radius = boundary_radius(half)
    local px, py = x + 0.5, y + 0.5
    local distance = math.sqrt(px * px + py * py)
    local edge_distance = radius - distance
    if edge_distance <= 0 then return "out-of-map" end

    local roll = hash.roll(record.seed, x, y, 9123)
    if edge_distance < 5 then
        return primary
    elseif roll < 0.08 then
        return alt1
    elseif roll < 0.16 then
        return alt2
    end
    return primary
end

local function set_vault_floor(record, surface, half)
    local primary, alt1, alt2 = choose_floor_tiles()
    if not primary then return end
    local tiles = {}
    local function flush()
        if #tiles > 0 then
            surface.set_tiles(tiles, true, false, false, false)
            tiles = {}
        end
    end
    for x = -half, half - 1 do
        for y = -half, half - 1 do
            local tile_name = floor_tile_name(record, x, y, half, primary, alt1, alt2)
            tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
            if #tiles >= FLOOR_TILE_BATCH then flush() end
        end
    end
    flush()
    pcall(function()
        surface.destroy_decoratives { area = { { -half, -half }, { half, half } } }
    end)
end

local function build_outer_walls(surface, half)
    -- Intentionally empty. The underground vault now uses a rounded finite edge
    -- and natural combat clusters instead of a boxed wall perimeter.
end
local function band_limits(half, tier)
    if tier == "standard" then
        return SAFE_HALF_EXTENT + ENEMY_SPAWN_BUFFER + 20,
            math.max(SAFE_HALF_EXTENT + ENEMY_SPAWN_BUFFER + 30, math.floor(half * 0.58))
    elseif tier == "secure" then
        return math.max(SAFE_HALF_EXTENT + ENEMY_SPAWN_BUFFER + 35,
            math.floor(half * 0.40)), math.floor(half * 0.79)
    end
    return math.max(SAFE_HALF_EXTENT + ENEMY_SPAWN_BUFFER + 55,
        math.floor(half * 0.67)), half - 22
end

local function random_position(record, half, stream, min_extent, max_extent)
    min_extent = math.max(min_extent or (SAFE_HALF_EXTENT + ENEMY_SPAWN_BUFFER + SAFE_SPAWN_MARGIN),
        SAFE_HALF_EXTENT + ENEMY_SPAWN_BUFFER + SAFE_SPAWN_MARGIN)
    max_extent = math.min(max_extent or (half - 5), half - 5)
    if max_extent < min_extent then max_extent = min_extent end
    for attempt = 1, 180 do
        local x = hash.range(record.seed, record.id, stream, attempt * 2, -max_extent, max_extent)
        local y = hash.range(record.seed, record.id, stream, attempt * 2 + 1, -max_extent, max_extent)
        local extent = math.max(math.abs(x), math.abs(y))
        local candidate = { x = x + 0.5, y = y + 0.5 }
        if extent >= min_extent and extent <= max_extent
            and not inside_safe_square(candidate, SAFE_SPAWN_MARGIN)
            and inside_round_boundary(candidate, half, 6) then
            return candidate
        end
    end
    local fallback = { x = max_extent + 0.5, y = 0.5 }
    if inside_round_boundary(fallback, half, 6) then return fallback end
    return { x = 0.5, y = max_extent + 0.5 }
end

local function stronghold_centres(record, half)
    if record.stronghold_centres then return record.stronghold_centres end
    local centres = { all = {} }
    local limit = half - 40
    -- Seeded rejection sampling scatters groups without concentric rings.
    -- Leave room for each group's thirty-tile defence footprint and searches.
    for attempt = 1, 6000 do
        if #centres.all == STRONGHOLD_COUNT then break end
        local p = {
            x = hash.range(record.seed, record.id, attempt, 9200, -limit, limit),
            y = hash.range(record.seed, record.id, attempt, 9201, -limit, limit),
        }
        local fits = math.max(math.abs(p.x), math.abs(p.y)) >= 81
            and p.x * p.x + p.y * p.y <= limit * limit
        for _, other in ipairs(centres.all) do
            if (p.x - other.x)^2 + (p.y - other.y)^2 < 64^2 then fits = false; break end
        end
        if fits then centres.all[#centres.all + 1] = p end
    end
    if #centres.all < STRONGHOLD_COUNT then
        -- A bounded irregular fallback avoids missing groups on crowded seeds.
        centres.all = {
            {x=-98,y=-91}, {x=3,y=-124}, {x=102,y=-80}, {x=-125,y=-6},
            {x=117,y=8}, {x=-93,y=94}, {x=-7,y=124}, {x=91,y=90},
        }
    end
    record.stronghold_centres = centres
    record.stronghold_layout_version = 3
    return centres
end

local function build_compound(surface, centre, radius, door_side)
    local cx, cy = math.floor(centre.x), math.floor(centre.y)
    for dx = -radius, radius do
        local top_open = door_side == 1 and math.abs(dx) <= 1
        local bottom_open = door_side == 2 and math.abs(dx) <= 1
        if not top_open then create_wall(surface, cx + dx, cy - radius) end
        if not bottom_open then create_wall(surface, cx + dx, cy + radius) end
    end
    for dy = -radius + 1, radius - 1 do
        local left_open = door_side == 3 and math.abs(dy) <= 1
        local right_open = door_side == 4 and math.abs(dy) <= 1
        if not left_open then create_wall(surface, cx - radius, cy + dy) end
        if not right_open then create_wall(surface, cx + radius, cy + dy) end
    end
end

local function build_internal_maze(record, surface, half)
    -- Intentionally disabled. The vault should feel open, natural and less boxy.
end

local VAULT_ROCK_COUNT = 10000

local function place_natural_rocks(record, surface, half)
    if not entity_exists(VAULT_ROCK) then return end

    local placed = 0
    local attempt = 0
    local max_attempts = VAULT_ROCK_COUNT * 35
    local max_extent = half - 7

    local function try_place(target)
        if inside_arrival_clear_pad(target) or not inside_round_boundary(target, half, 4) then return false end
        if not surface.can_place_entity {
            name = VAULT_ROCK,
            position = target,
            force = "neutral",
        } then return false end
        local rock = surface.create_entity {
            name = VAULT_ROCK,
            position = target,
            force = "neutral",
            create_build_effect_smoke = false,
        }
        if rock and rock.valid then
            placed = placed + 1
            return true
        end
        return false
    end

    -- Dense random coverage across the entire circular floor, including the
    -- 70x70 combat-safe zone. Only the small arrival pad stays clear.
    while placed < VAULT_ROCK_COUNT and attempt < max_attempts do
        attempt = attempt + 1
        local x = hash.range(record.seed, record.id, attempt, 15001, -max_extent, max_extent)
        local y = hash.range(record.seed, record.id, attempt, 15002, -max_extent, max_extent)
        try_place({ x = x + 0.5, y = y + 0.5 })
    end

    -- Deterministic fallback scan guarantees the requested count whenever the
    -- remaining open floor physically allows it.
    if placed < VAULT_ROCK_COUNT then
        local offset_x = hash.range(record.seed, record.id, 15003, 1, 0, max_extent * 2)
        local offset_y = hash.range(record.seed, record.id, 15004, 1, 0, max_extent * 2)
        local span = max_extent * 2 + 1
        for scan_y = 0, span - 1 do
            if placed >= VAULT_ROCK_COUNT then break end
            local y = -max_extent + ((scan_y + offset_y) % span)
            for scan_x = 0, span - 1 do
                if placed >= VAULT_ROCK_COUNT then break end
                local x = -max_extent + ((scan_x + offset_x) % span)
                try_place({ x = x + 0.5, y = y + 0.5 })
            end
        end
    end

    record.placed_rock_count = placed
end

local function enemy_target_outside_spawn_buffer(target, radius)
    if not inside_safe_square(target, ENEMY_SPAWN_BUFFER) then return target end
    local clearance = SAFE_HALF_EXTENT + ENEMY_SPAWN_BUFFER + (radius or 5) + 1
    local x, y = target.x or 0, target.y or 0
    if math.abs(x) >= math.abs(y) then
        x = x < 0 and -clearance or clearance
    else
        y = y < 0 and -clearance or clearance
    end
    return { x = x, y = y }
end

local function safe_enemy(surface, name, target, radius, ammo_name)
    local record = record_for_surface(surface)
    local half = record and record.half_size or nil
    if not entity_exists(name) then return nil end
    radius = radius or 5
    target = enemy_target_outside_spawn_buffer(target, radius)
    if half and not inside_round_boundary(target, half, 6) then return nil end
    local spot = surface.find_non_colliding_position(name, target, radius, 0.5)
    if spot and inside_safe_square(spot, ENEMY_SPAWN_BUFFER) then
        target = enemy_target_outside_spawn_buffer(spot, radius)
        spot = surface.find_non_colliding_position(name, target, radius, 0.5)
    end
    if not spot or inside_safe_square(spot, ENEMY_SPAWN_BUFFER)
        or (half and not inside_round_boundary(spot, half, 4)) then return nil end
    local ok, entity = pcall(function() return surface.create_entity { name = name, position = spot, force = "enemy" } end)
    if not ok or not (entity and entity.valid) then return nil end
    if entity.name == "gun-turret" then
        local ammo = item_exists(ammo_name or "piercing-rounds-magazine")
            and (ammo_name or "piercing-rounds-magazine")
            or "firearm-magazine"
        entity.insert { name = ammo, count = 1000 }
    end
    return entity
end

local function unit_names(level)
    if level == "medium" then
        return "medium-biter", "medium-spitter", "medium-worm-turret"
    elseif level == "hard" then
        return "big-biter", "big-spitter", "big-worm-turret"
    end
    return "behemoth-biter", "behemoth-spitter", "behemoth-worm-turret"
end

local function live_unit_names(record, surface)
    local parent = record and valid_surface(record.parent_surface_index) or nil
    return cave_evolution.tier_names(parent or surface)
end

local function clustered_target(record, centres, index, stream, spread)
    local centre = centres[((index - 1) % #centres) + 1]
    spread = spread or 11
    local dx = hash.range(record.seed, record.id, index, stream, -spread, spread)
    local dy = hash.range(record.seed, record.id, index, stream + 1, -spread, spread)
    local target = { x = centre.x + dx, y = centre.y + dy }
    if inside_safe_square(target, SAFE_SPAWN_MARGIN) then return centre end
    return target
end

local function spawn_static_defenders(record, surface, half)
    local biter, spitter, worm = live_unit_names(record, surface)
    local centres = stronghold_centres(record, half).all
    local defence = GROUP_DEFENDERS[record.level_id] or GROUP_DEFENDERS.medium
    local gun_ammo = record.level_id == "medium" and "piercing-rounds-magazine" or "uranium-rounds-magazine"

    local function place_group_count(centre, group_index, wanted, stream, radius_min, radius_max, name_for)
        local placed, attempt = 0, 0
        while placed < wanted and attempt < wanted * 12 do
            attempt = attempt + 1
            local angle = hash.roll(record.seed, group_index, attempt, stream) * math.pi * 2
            local radius = hash.range(record.seed, group_index, attempt, stream + 1, radius_min, radius_max)
            local target = {
                x = centre.x + math.cos(angle) * radius,
                y = centre.y + math.sin(angle) * radius,
            }
            local name, ammo = name_for(placed + 1)
            if safe_enemy(surface, name, target, 5, ammo) then placed = placed + 1 end
        end
        return placed
    end

    record.placed_group_defenders = {}
    for group_index, centre in ipairs(centres) do
        local placed = {}
        placed.lasers = place_group_count(centre, group_index, defence.lasers, 9400, 20, 27,
            function() return ENEMY_LASER end)
        placed.guns = place_group_count(centre, group_index, defence.guns, 9500, 20, 27,
            function() return "gun-turret", gun_ammo end)
        placed.biters = place_group_count(centre, group_index, defence.biters, 9600, 18, 30,
            function() return biter end)
        placed.spitters = place_group_count(centre, group_index, defence.spitters, 9650, 18, 30,
            function() return spitter end)
        placed.units = placed.biters + placed.spitters
        placed.spawners = place_group_count(centre, group_index, defence.spawners, 9700, 22, 30,
            function(i) return i % 2 == 0 and "spitter-spawner" or "biter-spawner" end)
        placed.worms = place_group_count(centre, group_index, defence.worms, 9800, 19, 28,
            function() return worm end)
        record.placed_group_defenders[group_index] = placed
    end
end

local function insert_item(chest, name, count)
    if item_is_blacklisted(name) or not (chest and chest.valid and item_exists(name)) then return 0 end
    local requested = math.max(0, math.floor(tonumber(count) or 0))
    if requested <= 0 then return 0 end
    local ok, inserted = pcall(function()
        return chest.insert { name = name, count = requested }
    end)
    return ok and (tonumber(inserted) or 0) or 0
end

local function cache_reward_seed(record, chest, cache_tier, cache_index)
    local tier_id = CACHE_TIER_ID[cache_tier] or 0
    local position = chest and chest.valid and chest.position or { x = 0, y = 0 }
    local px = math.floor((position.x or 0) * 2 + 0.5)
    local py = math.floor((position.y or 0) * 2 + 0.5)
    local unit_number = (chest and chest.valid and chest.unit_number or 0) % 65536

    -- Fold Vault identity, cache index, tier, final position and unit identity
    -- into one deterministic per-cache seed. Separate streams below then keep
    -- item selection, quantities and jackpot outcomes independent.
    local seed_a = hash.range(record.seed, record.id or 0, cache_index or 0,
        20000 + tier_id, 1, 2147483646)
    local seed_b = hash.range(seed_a, unit_number, px,
        20100 + tier_id, 1, 2147483646)
    return hash.range(seed_b, py, cache_index or 0,
        20200 + tier_id, 1, 2147483646)
end

local function create_cache(record, surface, cache_tier, index, tier_local_index,
        stronghold_index, position)
    local name = cache_tier == "high" and "the-cave-fortified-cache-high-security"
        or cache_tier == "secure" and "the-cave-fortified-cache-secure"
        or "the-cave-fortified-cache-standard"
    local half = record and record.half_size
        or math.floor(zone_layout(record.level_id, record.advancing_balance).size / 2)
    local spot
    if record.spiral_layout_version then
        if not spiral.inside(stronghold_index, position, 1, record) or not surface.can_place_entity{name=name, position=position, force="neutral"} then return nil end
        spot = position
    else
        if inside_safe_square(position, SAFE_SPAWN_MARGIN) or not inside_round_boundary(position, half, 6) then return nil end
        spot = surface.find_non_colliding_position(name, position, 10, 0.5)
        if not spot or inside_safe_square(spot, 0) or not inside_round_boundary(spot, half, 4) then return nil end
    end
    local chest = surface.create_entity { name = name, position = spot, force = "neutral" }
    if not (chest and chest.valid and chest.unit_number) then return nil end
    chest.destructible = false
    chest.minable_flag = false
    local reward_seed = cache_reward_seed(record, chest, cache_tier, index)
    root().by_entity[chest.unit_number] = record.id
    record.caches[chest.unit_number] = {
        tier = cache_tier,
        opened = false,
        alarm_triggered = false,
        index = index,
        tier_local_index = tier_local_index,
        stronghold_index = stronghold_index,
        reward_seed = reward_seed,
        reward_signature = "group-budget-v5",
    }
    return chest
end

local function spawn_caches(record, surface, half)
    local centres = stronghold_centres(record, half).all
    local index = 0
    local tier_radius = { standard = 16, secure = 10, high = 5 }
    local tier_angle_offset = { standard = 0, secure = math.pi / 12, high = math.pi / 6 }
    record.placed_cache_counts = { standard = 0, secure = 0, high = 0 }

    for stronghold_index, centre in ipairs(centres) do
        local group_chests = { standard = {}, secure = {}, high = {} }
        for _, tier in ipairs { "standard", "secure", "high" } do
            local wanted = CACHES_PER_STRONGHOLD[tier]
            for local_index = 1, wanted do
                index = index + 1
                local angle = (local_index - 1) * math.pi * 2 / wanted
                    + tier_angle_offset[tier]
                local radius = tier_radius[tier]
                local target = {
                    x = centre.x + math.cos(angle) * radius,
                    y = centre.y + math.sin(angle) * radius,
                }
                local tier_local_index = (stronghold_index - 1) * wanted + local_index
                local chest = create_cache(record, surface, tier, index, tier_local_index,
                    stronghold_index, target)
                if chest then
                    group_chests[tier][#group_chests[tier] + 1] = chest
                    record.placed_cache_counts[tier] = record.placed_cache_counts[tier] + 1
                end
            end
        end
        local totals, delivered = group_rewards.fill(group_chests, record.seed, stronghold_index,
            function(name) return item_exists(name) and not item_is_blacklisted(name) end, insert_item)
        record.group_reward_totals = record.group_reward_totals or {}
        record.group_reward_totals[stronghold_index] = totals
        for tier, items in pairs(totals) do
            for name, count in pairs(items) do
                assert(delivered[tier][name] == count, "Fortified Vault group loot did not fit: " .. name)
            end
        end
    end
end

-- Keep the exact eight legacy loot budgets, distributed across future chest slots.
-- Only plain item counts are planned here; unopened corridor entities do not exist.
local spiral_api = {}
function spiral_api.prepare_rewards(record)
    local slots = {standard={}, secure={}, high={}}
    for group=1,STRONGHOLD_COUNT do
        local chests={standard={}, secure={}, high={}}
        for _,tier in ipairs {"standard","secure","high"} do
            for _=1,CACHES_PER_STRONGHOLD[tier] do
                local slot={}
                chests[tier][#chests[tier]+1]=slot
                slots[tier][#slots[tier]+1]=slot
            end
        end
        group_rewards.fill(chests,record.seed,group,
            function(name) return item_exists(name) and not item_is_blacklisted(name) end,
            function(slot,name,count) slot[name]=(slot[name] or 0)+count;return count end)
    end
    if record.spiral_layout_version>=2 then
        -- Only container counts changed. Keep every original item total and
        -- redistribute those rewards across this layout's chest slots.
        local reduced={standard={},secure={},high={}}
        for tier_index,tier in ipairs {"standard","secure","high"} do
            local totals,names={},{}
            for _,slot in ipairs(slots[tier]) do
                for name,count in pairs(slot) do totals[name]=(totals[name] or 0)+count end
            end
            for name in pairs(totals) do names[#names+1]=name end
            table.sort(names)
            for _=1,spiral.layout(record).totals[tier] do reduced[tier][#reduced[tier]+1]={} end
            for index,name in ipairs(names) do
                local inserted=group_rewards.spread(reduced[tier],name,totals[name],record.seed,26000+tier_index*1000+index,
                    function(slot,item,count) slot[item]=(slot[item] or 0)+count;return count end)
                assert(inserted==totals[name],"Fortified reward redistribution failed: "..name)
            end
        end
        slots=reduced
    end
    record.spiral.reward_slots=slots
end
function spiral_api.create_cache(record,surface,tier,ordinal,stage,position)
    local offset=spiral.layout(record).offsets[tier]
    local chest=create_cache(record,surface,tier,offset+ordinal,ordinal,stage,position)
    if not chest then return nil end
    for name,count in pairs(record.spiral.reward_slots[tier][ordinal]) do
        assert(insert_item(chest,name,count)==count,"Fortified spiral reward did not fit: "..name)
    end
    return chest
end
function spiral_api.register_surface(record,surface)
    root().by_surface[surface.index]=record.id
    apply_pitch_black(surface)
end
function spiral_api.register_exit(record,entity,stage)
    root().by_entity[entity.unit_number]=record.id
    record.spiral.exit_units[entity.unit_number]=stage
end
function spiral_api.finish_station(record,surface)
    local force=game.forces[record.owner_force_index]
    local station=spiral.layout(record).station
    local pole=create_fixed(surface,POWER_POLE,station,force,nil)
    local lamp=create_fixed(surface,LOWER_LAMP,{x=station.x+1,y=station.y},force,nil)
    record.lower_pole_unit=pole and pole.unit_number
    record.lower_lamp_unit=lamp and lamp.unit_number
    if lamp then lamp.operable=false;lamp.always_on=true end
    ensure_power_bridge(record)
    ensure_portal_label(record,false)
end

local function create_lower_station(record, surface)
    local force = game.forces[record.owner_force_index] or game.forces.player
    local exit_name = portal_variant(record.seed, { x = 0, y = 0 }, false)
    local exit = create_fixed(surface, exit_name, { x = 0, y = 0 }, "neutral", 2.4)
    if not (exit and exit.unit_number) then return false end
    record.exit_unit_number = exit.unit_number
    record.exit_position = copy_position(exit.position)
    root().by_entity[exit.unit_number] = record.id

    local pole = create_fixed(surface, POWER_POLE, { x = 0, y = -5 }, force, 1.2)
    if not (pole and pole.unit_number) then return false end
    record.lower_pole_unit = pole.unit_number

    clear_site(surface, { x = 1, y = -5 }, 0.7, { [pole.unit_number] = true })
    local lamp = create_fixed(surface, LOWER_LAMP, { x = 1, y = -5 }, force, nil)
    if not (lamp and lamp.unit_number) then return false end
    record.lower_lamp_unit = lamp.unit_number
    pcall(function() lamp.operable = false end)
    pcall(function() lamp.always_on = true end)

    ensure_portal_label(record, false)
    update_timer_label(record, false, game.tick)
    return ensure_power_bridge(record)
end

local function ensure_child_surface(record)
    if record.spiral_layout_version then
        local parent=valid_surface(record.parent_surface_index)
        if not parent then return nil,"missing-parent" end
        local surface,reason=spiral.ensure(record,parent,spiral_api)
        if surface then apply_pitch_black(surface);ensure_power_bridge(record) end
        return surface,reason
    end
    local existing = valid_surface(record.child_surface_index)
    if existing then
        if record.power_connections_surface ~= existing then
            apply_pitch_black(existing)
            if not ensure_power_bridge(record) then return nil, "station-failed" end
        end
        if record.safe_zone_half_extent == SAFE_HALF_EXTENT then ensure_safe_zone_render(record) end
        return existing
    end
    local parent = valid_surface(record.parent_surface_index)
    if not parent then return nil, "missing-parent" end
    local name = SURFACE_PREFIX .. tostring(record.parent_surface_index) .. "-" .. tostring(record.id)
    local surface = game.surfaces[name]
    local created = not (surface and surface.valid)
    if created then
        surface = game.create_surface(name, create_map_gen_settings(record, parent))
    end
    if not (surface and surface.valid) then return nil, "surface-failed" end

    record.child_surface_index = surface.index
    root().by_surface[surface.index] = record.id
    if created then child_state.surface_created(record, surface) end
    apply_pitch_black(surface)
    local half = math.floor(zone_layout(record.level_id, record.advancing_balance).size / 2)
    local chunk_radius = math.ceil((half + 16) / 32)
    surface.request_to_generate_chunks({ x = 0, y = 0 }, chunk_radius)
    surface.force_generate_chunk_requests()

    record.half_size = half
    record.reward_catalog_version = 5
    -- Every tile on the finite child surface is rewritten: circular stone floor
    -- inside, out-of-map outside. No default-terrain square ring remains.
    set_vault_floor(record, surface, half)

    for _, entity in pairs(surface.find_entities_filtered {
        area = { { -half, -half }, { half, half } },
    }) do
        if entity.valid and entity.type ~= "character" and entity.name ~= "character" then entity.destroy() end
    end

    build_outer_walls(surface, half)
    build_internal_maze(record, surface, half)
    if not create_lower_station(record, surface) then return nil, "station-failed" end
    spawn_caches(record, surface, half)
    spawn_static_defenders(record, surface, half)
    place_natural_rocks(record, surface, half)

    -- Hard guarantee: the 70x70 combat-safe square remains free of combat entities after every
    -- placement pass. Rocks are allowed there; only the arrival pad around the exit, pole and lamp stays clear.
    local protected = {}
    for _, unit in pairs { record.exit_unit_number, record.lower_pole_unit, record.lower_lamp_unit } do
        if unit then protected[unit] = true end
    end
    for _, entity in pairs(surface.find_entities_filtered {
        area = { { -SAFE_HALF_EXTENT, -SAFE_HALF_EXTENT }, { SAFE_HALF_EXTENT + 1, SAFE_HALF_EXTENT + 1 } },
    }) do
        local keep = entity.unit_number and protected[entity.unit_number]
        local keep_rock = entity.name == VAULT_ROCK
        if entity.valid and not keep and not keep_rock
            and entity.type ~= "character" and entity.name ~= "character" then
            entity.destroy()
        end
    end

    record.safe_zone_half_extent = SAFE_HALF_EXTENT
    record.enemy_spawn_buffer = ENEMY_SPAWN_BUFFER
    ensure_safe_zone_render(record)

    local force = game.forces[record.owner_force_index] or game.forces.player
    force.chart(surface, { { -12, -12 }, { 12, 12 } })
    return surface
end

local function upper_area_clear(record)
    if record.test_bypass then return true end
    local surface = valid_surface(record.parent_surface_index)
    if not surface then return false end
    local half = math.floor((record.upper_size or 32) / 2)
    local area = {
        { record.entrance_position.x - half, record.entrance_position.y - half },
        { record.entrance_position.x + half, record.entrance_position.y + half },
    }
    local defender_types = {
        ["unit"] = true,
        ["unit-spawner"] = true,
        ["turret"] = true,
        ["ammo-turret"] = true,
        ["electric-turret"] = true,
        ["fluid-turret"] = true,
        ["artillery-turret"] = true,
    }
    for _, entity in pairs(surface.find_entities_filtered { area = area, force = "enemy" }) do
        if entity.valid and defender_types[entity.type] and entity.health and entity.health > 0 then return false end
    end
    return true
end

local function character_name(player)
    return player.character and player.character.valid and player.character.name or "character"
end

local function find_player_position(player, surface, preferred, radius)
    return surface.find_non_colliding_position(character_name(player), preferred, radius or 12, 0.5)
end

local function enable_flashlight(player)
    local r = root()
    if r.flashlight_state[player.index] == nil then
        local ok, state = pcall(function() return player.is_flashlight_enabled() end)
        r.flashlight_state[player.index] = ok and state or true
    end
    pcall(function() player.enable_flashlight() end)
end

local function restore_flashlight(player)
    local r = root()
    local state = r.flashlight_state[player.index]
    if state == nil then return end
    r.flashlight_state[player.index] = nil
    if state == false then pcall(function() player.disable_flashlight() end)
    else pcall(function() player.enable_flashlight() end) end
end

local function start_timer(record)
    if record.spiral_layout_version then spiral.start_timer(record);update_timer_labels(record,game.tick);return end
    if record.timer_started_tick then return end
    record.timer_started_tick = game.tick
    record.raid_duration_ticks = RAID_TICKS
    record.close_tick = game.tick + RAID_TICKS
    update_timer_labels(record, game.tick)
    local force = game.forces[record.owner_force_index]
    if force then force.print({ "the-cave-fortified-vault.timer-started", RAID_MINUTES }) end
end

local function migrate_raid_duration(record)
    if not record or record.raid_duration_ticks == RAID_TICKS then return end
    local old_close_tick = record.close_tick
    record.raid_duration_ticks = RAID_TICKS
    if record.timer_started_tick then
        record.close_tick = record.timer_started_tick + RAID_TICKS
        if not old_close_tick or record.close_tick > old_close_tick then
            record.warned_five = false
            record.warned_one = false
        end
    end
end

local function enter_vault(player, record)
    if not physical.can_travel(player) then return false end
    if record.status == "closed" then player.print({ "the-cave-fortified-vault.sealed" }) return false end
    if player.vehicle then player.print({ "the-cave-fortified-vault.leave-vehicle" }) return false end
    if record.owner_force_index and player.force.index ~= record.owner_force_index then
        player.print({ "the-cave-fortified-vault.wrong-force" })
        return false
    end
    if not upper_area_clear(record) then
        player.print({ "the-cave-fortified-vault.clear-upper-first" })
        return false
    end

    local surface, reason = ensure_child_surface(record)
    if not surface then
        player.print({ "the-cave-fortified-vault.travel-failed", reason or "unknown" })
        return false
    end
    local arrival=record.spiral_layout_version and spiral.layout(record).arrival or {x=0,y=3.5}
    local position = find_player_position(player, surface, arrival, record.spiral_layout_version and 4 or 12)
    if physical.teleport(player, position, surface) then
        record.entered_players[player.index]=true
        start_timer(record)
        enable_flashlight(player)
        if record.spiral then
            record.spiral.positions[player.index]=nil
            spiral.player_position(record,player)
            spiral.update_scaling(record)
            player.force.chart(surface,spiral.layout(record).chart)
            player.print({spiral.text_key(record,"rules")})
            spiral.update_hud(player,record,game.tick)
        else
            player.force.chart(surface, { { -14, -14 }, { 14, 14 } })
            player.print({ "the-cave-fortified-vault.entered", { "the-cave-runtime.depth-" .. record.level_id } })
        end
        return true
    end
    player.print({ "the-cave-fortified-vault.travel-failed", "teleport" })
    return false
end

local function leave_vault(player, record)
    if not physical.can_travel(player) then return false end
    if player.vehicle then player.print({ "the-cave-fortified-vault.leave-vehicle" }) return false end
    local parent = child_state.return_surface(player, record.parent_surface_index)
    if not parent then player.print({ "the-cave-fortified-vault.travel-failed", "missing-parent" }) return false end
    local preferred = parent.index == record.parent_surface_index
        and { x = record.entrance_position.x, y = record.entrance_position.y + 3.5 }
        or child_state.spawn_position(player, parent)
    local position = find_player_position(player, parent, preferred, 14)
    if physical.teleport(player, position, parent) then
        restore_flashlight(player)
        if record.spiral then record.spiral.positions[player.index]=nil end
        spiral.update_hud(player,nil,game.tick)
        player.print({ record.spiral and spiral.text_key(record,"left") or "the-cave-fortified-vault.left" })
        return true
    end
    return false
end

local function cache_record(record, entity)
    return record and record.caches and entity.unit_number and record.caches[entity.unit_number] or nil
end

local function remaining_alarm_count(cache)
    local remaining = 0
    for unit_number, entity in pairs(cache.alarm_units or {}) do
        if entity and entity.valid then
            remaining = remaining + 1
        else
            cache.alarm_units[unit_number] = nil
            root().alarm_units[unit_number] = nil
        end
    end
    if cache.alarm_triggered and remaining == 0 then cache.alarm_cleared = true end
    return remaining
end

local function spawn_alarm(record, cache, chest)
    if cache.alarm_triggered then return remaining_alarm_count(cache) end
    cache.alarm_triggered = true
    cache.alarm_cleared = false
    cache.alarm_units = {}
    local surface = chest.surface
    local biter, spitter = live_unit_names(record, surface)
    local amount = ALARM_UNITS[cache.tier] or 2
    for i = 1, amount do
        local angle = (i / amount) * math.pi * 2
        local target = {
            x = chest.position.x + math.cos(angle) * 5,
            y = chest.position.y + math.sin(angle) * 5,
        }
        local unit = safe_enemy(surface, i % 3 == 0 and spitter or biter, target, 5)
        if unit and unit.valid and unit.unit_number then
            cache.alarm_units[unit.unit_number] = unit
            root().alarm_units[unit.unit_number] = {
                record_id = record.id,
                chest_unit = chest.unit_number,
            }
        end
    end
    return remaining_alarm_count(cache)
end

local claim_cache

local function begin_cache_hack(player, record, chest)
    local cache = cache_record(record, chest)
    if not cache or cache.opened then return end
    if record.spiral_layout_version then claim_cache(player,record,chest,cache);return end
    if not cache.alarm_triggered then
        local spawned = spawn_alarm(record, cache, chest)
        player.print({ "the-cave-fortified-vault.alarm-started", spawned })
        if spawned == 0 then player.print({ "the-cave-fortified-vault.cache-cleared" }) end
        return
    end
    local remaining = remaining_alarm_count(cache)
    if remaining > 0 then
        player.print({ "the-cave-fortified-vault.alarm-remaining", remaining })
        return
    end
    claim_cache(player, record, chest, cache)
end

local function stack_definition(stack)
    local def = { name = stack.name, count = stack.count }
    local ok, quality = pcall(function() return stack.quality end)
    if ok and quality then def.quality = quality.name or quality end
    return def
end

local function transfer_cache_to_player(player, chest)
    local inventory = chest.get_inventory(defines.inventory.chest)
    if not inventory then return 0, 0, 0 end
    local stack_count = 0
    local item_count = 0
    local spilled_count = 0
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack and stack.valid_for_read then
            if reward_policy.is_blocked(stack.name) then
                -- Final reward-boundary guard for legacy or externally edited
                -- managed caches. Normal generation already rerolls these.
                stack.clear()
                goto continue
            end
            local def = stack_definition(stack)
            stack_count = stack_count + 1
            item_count = item_count + def.count
            local inserted = player.insert(def)
            local remaining = def.count - inserted
            if remaining > 0 then
                spilled_count = spilled_count + remaining
                def.count = remaining
                chest.surface.spill_item_stack {
                    position = physical.position(player),
                    stack = def,
                    enable_looted = true,
                    force = player.force,
                }
            end
            stack.clear()
        end
        ::continue::
    end
    return stack_count, item_count, spilled_count
end

claim_cache = function(player, record, chest, cache)
    if not (player and player.valid and record and record.status ~= "closed"
        and chest and chest.valid and cache and not cache.opened) then return end
    local stack_count, item_count, spilled_count = transfer_cache_to_player(player, chest)
    cache.opened = true
    record.player_loot[player.index] = (record.player_loot[player.index] or 0) + 1
    record.opened_count = record.opened_count + 1
    root().by_entity[chest.unit_number] = nil
    record.caches[chest.unit_number] = nil
    chest.destroy()
    player.print({ "the-cave-fortified-vault.cache-opened", record.player_loot[player.index], record.opened_count })
    player.print({ "the-cave-fortified-vault.loot-delivered", stack_count, item_count, spilled_count })
end

local function destroy_tracked_entity(surface_index, unit_number, names)
    local entity = find_unit(surface_index, unit_number, names)
    if entity then pcall(function() entity.destroy() end) end
end

local function clear_upper_fortress_remnants(record)
    local surface = valid_surface(record.parent_surface_index)
    local position = record.entrance_position
    if not (surface and position) then return end

    destroy_tracked_entity(record.parent_surface_index, record.entrance_unit_number, {
        "the-cave-fortified-vault-entrance-1", "the-cave-fortified-vault-entrance-2",
    })
    destroy_tracked_entity(record.parent_surface_index, record.upper_pole_unit, POWER_POLE)
    destroy_tracked_entity(record.parent_surface_index, record.upper_lamp_unit, LOWER_LAMP)
    destroy_tracked_entity(record.parent_surface_index, record.info_panel_unit, INFO_PANEL)

    -- The gateway perimeter belongs to the Vault encounter. Clear only enemy
    -- walls and defenders inside its recorded square; player-built entities on
    -- the reclaimed floor are deliberately preserved.
    local half = math.ceil((record.upper_size or 20) / 2) + 1
    local removable_types = {
        ["unit"] = true,
        ["unit-spawner"] = true,
        ["turret"] = true,
        ["ammo-turret"] = true,
        ["electric-turret"] = true,
        ["fluid-turret"] = true,
        ["artillery-turret"] = true,
    }
    for _, entity in pairs(surface.find_entities_filtered {
        area = {
            { position.x - half, position.y - half },
            { position.x + half, position.y + half },
        },
        force = "enemy",
    }) do
        if entity.valid and (entity.name == "stone-wall" or removable_types[entity.type]) then
            entity.destroy()
        end
    end
end

local function cleanup_closed_vault(record)
    if not record then return true end
    local r = root()

    clear_upper_fortress_remnants(record)
    for _, field in ipairs {
        "entrance_label_id", "exit_label_id", "upper_timer_id", "lower_timer_id", "sealed_label_id",
        "safe_zone_outline_id", "safe_zone_label_id",
    } do
        destroy_render(record[field])
        record[field] = nil
    end

    local child = valid_surface(record.child_surface_index)
    if child then
        for _, player in pairs(game.players) do
            local inside = physical.on_surface(player, child)
            if player.valid and (inside or player.surface == child) then
                local parent = child_state.return_surface(player, record.parent_surface_index)
                if not parent then return false end
                local preferred = child_state.spawn_position(player, parent)
                local position = preferred
                if inside then position = physical.find_position(player, parent, preferred, 32) end
                if inside and not position then return false end
                if not physical.evacuate(player, child, parent, position) then return false end
                if inside then restore_flashlight(player) end
            end
        end
        if child.valid then
            -- A spiral's surface name carries a layout suffix, so get_owned_surfaces never lists it.
            local owned = not record.spiral and record or nil
            local ok, queued = pcall(function() return child_state.delete_surface(owned, child) end)
            if not ok or not queued then
                set_child_surface_hidden(record, true)
                return false
            end
        end
    end

    if record.entrance_unit_number then r.by_entity[record.entrance_unit_number] = nil end
    if record.exit_unit_number then r.by_entity[record.exit_unit_number] = nil end
    if record.spiral then
        for unit_number in pairs(record.spiral.exit_units or {}) do r.by_entity[unit_number]=nil end
    end
    for unit_number, cache in pairs(record.caches or {}) do
        r.by_entity[unit_number] = nil
        for alarm_unit in pairs(cache.alarm_units or {}) do r.alarm_units[alarm_unit] = nil end
    end
    if record.child_surface_index then r.by_surface[record.child_surface_index] = nil end
    r.by_id[record.id] = nil
    return true
end

local function close_vault(record)
    if not record or record.status == "closed" then return end
    record.status = "closed"
    record.closed_tick = game.tick

    local child = valid_surface(record.child_surface_index)
    if child then
        for _, player in pairs(game.players) do
            if player.valid and physical.surface(player).index == child.index then
                root().pending_respawns[player.index] = {
                    parent_surface_index = record.parent_surface_index,
                    record_id = record.id,
                }
                if player.character and player.character.valid then
                    pcall(function() player.character.die() end)
                else
                    local parent = child_state.return_surface(player, record.parent_surface_index)
                    if parent and physical.teleport(player,
                        physical.find_position(player, parent, child_state.spawn_position(player, parent), 24), parent) then
                        root().pending_respawns[player.index] = nil
                        restore_flashlight(player)
                    end
                end
            end
        end
    end

    local force = game.forces[record.owner_force_index]
    if force then force.print({ "the-cave-fortified-vault.vault-sealed" }) end
    cleanup_closed_vault(record)
end

function fortified_vaults.create_upper_entrance(surface, cx, cy, seed, profile, force, upper_layout)
    if not fortified_vaults.enabled() then return nil end
    if not (surface and surface.valid and force and force.valid) then return nil end
    local position = profile and profile.entrance_position or { x = cx + 0.5, y = cy + 0.5 }
    if not cave_placement.prepare_entrance(surface, position, world) then return nil end
    local r = root()
    local id = r.next_id
    r.next_id = id + 1
    local entrance_name = portal_variant(seed, position, true)
    clear_site(surface, position, 2.5)
    local entrance = create_fixed(surface, entrance_name, position, "neutral", nil)
    if not (entrance and entrance.unit_number) then return nil end

    local pole = create_fixed(surface, POWER_POLE, { x = position.x, y = position.y - 5 }, force, 1.2)
    if not (pole and pole.unit_number) then entrance.destroy() return nil end

    clear_site(surface, { x = position.x + 1, y = position.y - 5 }, 0.7, { [pole.unit_number] = true })
    local upper_lamp = create_fixed(surface, LOWER_LAMP, { x = position.x + 1, y = position.y - 5 }, force, nil)
    if upper_lamp then
        pcall(function() upper_lamp.operable = false end)
        pcall(function() upper_lamp.always_on = true end)
    end

    local panel = nil
    if entity_exists(INFO_PANEL) then
        clear_site(surface, { x = position.x - 2, y = position.y - 5 }, 0.7, { [pole.unit_number] = true })
        panel = create_fixed(surface, INFO_PANEL, { x = position.x - 2, y = position.y - 5 }, "neutral", nil)
        setup_panel(panel)
    end

    local advancing_level, advancing_zone = advancing_level_at(surface, position)
    local level = advancing_level or (profile and profile.level_id) or "medium"
    if not TIER_LAYOUT[level] then level = "medium" end
    local record = {
        id = id,
        parent_surface_index = surface.index,
        entrance_position = copy_position(entrance.position),
        entrance_unit_number = entrance.unit_number,
        upper_pole_unit = pole.unit_number,
        upper_lamp_unit = upper_lamp and upper_lamp.unit_number or nil,
        info_panel_unit = panel and panel.unit_number or nil,
        owner_force_index = force.index,
        seed = hash.range(seed or 0, cx, cy, 9001 + id, 1, 2147483646),
        level_id = level,
        advancing_balance = advancing_level ~= nil,
        advancing_zone = advancing_zone,
        region_id = region_features.region_at(position.x, position.y) or "nauvis",
        upper_size = upper_layout and upper_layout.size or 32,
        status = "active",
        spiral_layout_version = spiral.VERSION,
        created_tick = game.tick,
        entered_players = {},
        player_loot = {},
        opened_count = 0,
        reward_spent = {},
        science_spent = 0,
        armor_spent = 0,
        equipment_spent = 0,
        reward_budget_version = 2,
        reward_catalog_version = 5,
        stronghold_layout_version = 3,
        raid_duration_ticks = RAID_TICKS,
        caches = {},
    }
    r.by_id[id] = record
    r.by_entity[entrance.unit_number] = id
    ensure_portal_label(record, true)
    update_timer_label(record, true, game.tick)
    return record
end

function fortified_vaults.on_gui_opened(event)
    local entity = event and event.entity
    if not (entity and entity.valid) then return false end
    local is_entrance = ENTRANCE_NAMES[entity.name]
    local is_exit = EXIT_NAMES[entity.name]
    local cache_tier = CACHE_NAMES[entity.name]
    if not is_entrance and not is_exit and not cache_tier then return false end

    local player = event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return true end
    player.opened = nil
    if not physical.can_use_entity(player, entity) then return true end
    local record = record_for_entity(entity)
    if not record then
        player.print({ "the-cave-fortified-vault.unlinked" })
        return true
    end
    if not is_exit and player.force.index~=record.owner_force_index then player.print({"the-cave-fortified-vault.wrong-force"});return true end
    if record.close_tick and game.tick>=record.close_tick then close_vault(record);return true end
    if is_entrance then enter_vault(player, record)
    elseif is_exit then leave_vault(player, record)
    else begin_cache_hack(player, record, entity) end
    return true
end

function fortified_vaults.on_tick(event)
    local tick = event and event.tick or game.tick
    local closing = {}
    local cleanup_pending = {}
    local r = root()
    -- Also repair saves made with the first 3.3.0 package, where a same-version
    -- replacement need not raise on_configuration_changed. Scan only once.
    local repair_panels = r.panel_text_format_version ~= 1
    for _, record in pairs(r.by_id) do
        if record.status ~= "closed" then
            if repair_panels then
                setup_panel(find_unit(record.parent_surface_index, record.info_panel_unit, INFO_PANEL), record)
            end
            if record.spiral and spiral.tick(record,tick,spiral_api) then update_timer_labels(record,tick) end
            local child = valid_surface(record.child_surface_index)
            if child then
                if tick % 60 == 0 then
                    for _, player in pairs(game.connected_players) do
                        if player.valid and physical.surface(player).index == child.index then enable_flashlight(player) end
                    end
                end
            end
            if tick % TIMER_UPDATE_INTERVAL == 0 then update_timer_labels(record, tick) end
            if record.close_tick then
                local remaining = record.close_tick - tick
                if remaining <= 5 * 60 * 60 and not record.warned_five then
                    record.warned_five = true
                    local force = game.forces[record.owner_force_index]
                    if force then force.print({ "the-cave-fortified-vault.time-warning", 5 }) end
                end
                if remaining <= 60 * 60 and not record.warned_one then
                    record.warned_one = true
                    local force = game.forces[record.owner_force_index]
                    if force then force.print({ "the-cave-fortified-vault.time-warning", 1 }) end
                end
                if remaining <= 0 then closing[#closing + 1] = record end
            end
        else
            cleanup_pending[#cleanup_pending + 1] = record
        end
    end
    r.panel_text_format_version = 1
    for _, record in ipairs(closing) do close_vault(record) end
    for _, record in ipairs(cleanup_pending) do cleanup_closed_vault(record) end
    if tick%60==0 then
        for _,player in pairs(game.connected_players) do
            spiral.update_hud(player,record_for_surface(physical.surface(player)),tick)
        end
    end
end

function fortified_vaults.on_player_changed_surface(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if fortified_vaults.is_fortified_vault_surface(physical.surface(player)) then enable_flashlight(player)
    else restore_flashlight(player) end
    local record=record_for_surface(physical.surface(player))
    if record and record.spiral then record.spiral.positions[player.index]=nil end
    spiral.update_hud(player,record,game.tick)
end

function fortified_vaults.on_player_died(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid and record_for_surface(physical.surface(player))) then return end
    for _, corpse in pairs(physical.surface(player).find_entities_filtered {
        name = "character-corpse",
        position = physical.position(player),
        radius = 4,
    }) do
        if corpse.valid then pcall(function() corpse.corpse_expires = false end) end
    end
end

function fortified_vaults.on_player_respawned(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local pending = root().pending_respawns[player.index]
    local record = record_for_surface(physical.surface(player))
    if not pending and not record then return end
    local parent_index = pending and pending.parent_surface_index or record.parent_surface_index
    local parent = child_state.return_surface(player, parent_index)
    if parent and physical.teleport(player,
        physical.find_position(player, parent, child_state.spawn_position(player, parent), 24), parent) then
        root().pending_respawns[player.index] = nil
        restore_flashlight(player)
    end
end

local function rebuild_indexes()
    local r = root()
    r.by_entity = {}
    r.by_surface = {}
    r.alarm_units = {}
    -- Timed cache hacks from 3.1.64 cannot continue under the defender-gated
    -- interaction. Their caches remain unopened and can be clicked normally.
    r.hacks = {}
    for id, record in pairs(r.by_id) do
        record.id = record.id or id
        record.entered_players = record.entered_players or {}
        record.player_loot = record.player_loot or {}
        record.caches = record.caches or {}
        record.opened_count = record.opened_count or 0
        record.reward_spent = record.reward_spent or {}
        record.science_spent = record.science_spent or 0
        record.armor_spent = record.armor_spent or 0
        record.equipment_spent = record.equipment_spent or 0
        record.reward_budget_version = record.reward_budget_version or 1
        record.reward_catalog_version = record.reward_catalog_version or 2
        record_region(record)
        record.status = record.status or "active"
        if record.entrance_unit_number then r.by_entity[record.entrance_unit_number] = id end
        if record.exit_unit_number then r.by_entity[record.exit_unit_number] = id end
        if record.spiral then
            for unit_number in pairs(record.spiral.exit_units or {}) do r.by_entity[unit_number]=id end
        end
        for unit_number, cache in pairs(record.caches) do
            r.by_entity[unit_number] = id
            cache.hacker_player_index = nil
            for alarm_unit, entity in pairs(cache.alarm_units or {}) do
                if entity and entity.valid then
                    r.alarm_units[alarm_unit] = { record_id = id, chest_unit = unit_number }
                else
                    cache.alarm_units[alarm_unit] = nil
                end
            end
            remaining_alarm_count(cache)
        end
        if record.child_surface_index and valid_surface(record.child_surface_index) then
            r.by_surface[record.child_surface_index] = id
        end
    end
end

local BITER_TIERS = {
    ["small-biter"] = true, ["medium-biter"] = true,
    ["big-biter"] = true, ["behemoth-biter"] = true,
}
local SPITTER_TIERS = {
    ["small-spitter"] = true, ["medium-spitter"] = true,
    ["big-spitter"] = true, ["behemoth-spitter"] = true,
}
local WORM_TIERS = {
    ["small-worm-turret"] = true, ["medium-worm-turret"] = true,
    ["big-worm-turret"] = true, ["behemoth-worm-turret"] = true,
}

local function replace_enemy_tier(entity, desired_name)
    if not (entity and entity.valid and desired_name) then return nil end
    if entity.name == desired_name then return entity end
    local surface = entity.surface
    local position = copy_position(entity.position)
    local direction = entity.direction
    local force = entity.force
    entity.destroy()
    local ok, replacement = pcall(function()
        return surface.create_entity {
            name = desired_name,
            position = position,
            direction = direction,
            force = force,
        }
    end)
    if ok and replacement and replacement.valid then return replacement end
    return nil
end

local function refresh_unentered_vault_level(record)
    if record.child_surface_index or record.raid_started_tick
        or (record.opened_count or 0) > 0 then return end
    local parent = valid_surface(record.parent_surface_index)
    local level, zone = advancing_level_at(parent, record.entrance_position)
    if level then
        record.level_id = level
        record.advancing_balance = true
        record.advancing_zone = zone
    end
end

function fortified_vaults.on_init()
    root()
end

function fortified_vaults.on_force_created(event)
    local force = event and event.force
    if not (force and force.valid) then return end
    for _, record in pairs(root().by_id) do
        if record.status == "closed" then set_child_surface_hidden(record, true, force) end
    end
end

-- A first-entry timer is authoritative even in versions which did not fill
-- entered_players. Never convert an empty-but-previously-visited vault.
local function migrate_spiral_layout(record)
    if record.spiral_layout_version==spiral.VERSION or record.status=="closed" then return end
    local child=valid_surface(record.child_surface_index)
    local used=record.timer_started_tick~=nil or record.raid_started_tick~=nil or record.close_tick~=nil
        or next(record.entered_players or {})~=nil or (record.opened_count or 0)>0
    if child then
        for _,player in pairs(game.players) do
            if physical.on_surface(player,child) then used=true;break end
        end
        if child.count_entities_filtered{type="character",limit=1}>0
            or child.count_entities_filtered{name="character-corpse",limit=1}>0 then used=true end
    end
    if used then
        if not record.spiral_layout_version then record.legacy_layout=true end
        return
    end
    if child then
        -- Remote observers are moved off the unvisited surface; no body is moved.
        for _,player in pairs(game.players) do
            local parent=child_state.return_surface(player,record.parent_surface_index)
            local position=parent and (parent.index==record.parent_surface_index and record.entrance_position or child_state.spawn_position(player,parent))
            if player.surface==child and (not parent or not physical.move_view_off_surface(player,child,parent,position)) then return end
        end
        if not child_state.delete_surface(not record.spiral and record or nil, child) then return end
    end
    for _,field in ipairs {"exit_label_id","lower_timer_id","safe_zone_outline_id","safe_zone_label_id"} do
        destroy_render(record[field]);record[field]=nil
    end
    record.child_surface_index=nil;record.exit_unit_number=nil;record.exit_position=nil
    record.lower_pole_unit=nil;record.lower_lamp_unit=nil;record.power_connections_surface=nil
    record.safe_zone_half_extent=nil;record.enemy_spawn_buffer=nil
    record.caches={};record.placed_cache_counts=nil;record.group_reward_totals=nil
    record.spiral=nil
    record.spiral_layout_version=spiral.VERSION
end

function fortified_vaults.on_configuration_changed()
    root()
    for _,record in pairs(root().by_id) do migrate_spiral_layout(record) end
    rebuild_indexes()
    cleanup_legacy_closed_labels()
    local closed = {}
    for _, record in pairs(root().by_id) do
        if record.status == "closed" then closed[#closed + 1] = record end
    end
    for _, record in ipairs(closed) do cleanup_closed_vault(record) end
    for _, record in pairs(root().by_id) do
        record.power_connections_surface = nil
        -- Preserve the exact legacy deadline; spiral timers reset only on unlock.
        cave_placement.repair_entrance(record, root(), world, {
            "upper_pole_unit", "upper_lamp_unit", "info_panel_unit",
        }, 0)
        refresh_unentered_vault_level(record)
        setup_panel(find_unit(record.parent_surface_index, record.info_panel_unit, INFO_PANEL), record)
        ensure_upper_indicator_lamp(record)
        local child = valid_surface(record.child_surface_index)
        if child then
            apply_pitch_black(child)
            ensure_power_bridge(record)
            if record.spiral then spiral.refresh_labels(record) end
            if record.safe_zone_half_extent == SAFE_HALF_EXTENT then ensure_safe_zone_render(record) end
        end
        ensure_portal_label(record, true)
        if child and record.exit_position then ensure_portal_label(record, false) end
        update_timer_labels(record, game.tick)
    end
end

function fortified_vaults.on_entity_spawned(event)
    local entity = event and event.entity
    if not (entity and entity.valid and entity.type == "unit") then return end
    local record = record_for_surface(entity.surface)
    if not record then return end
    if record.spiral then spiral.on_spawn(record,entity);return end
    local biter, spitter = live_unit_names(record, entity.surface)
    if BITER_TIERS[entity.name] then replace_enemy_tier(entity, biter)
    elseif SPITTER_TIERS[entity.name] then replace_enemy_tier(entity, spitter) end
end

function fortified_vaults.on_entity_died(event)
    local entity = event and event.entity
    if entity and entity.valid then
        local record=record_for_surface(entity.surface)
        if record and record.spiral then spiral.death(record,event) end
    end
    local unit_number = entity and entity.unit_number
    if not unit_number then return end
    local r = root()
    local link = r.alarm_units[unit_number]
    if not link then return end
    r.alarm_units[unit_number] = nil

    local record = r.by_id[link.record_id]
    local cache = record and record.caches and record.caches[link.chest_unit]
    if not cache then return end
    cache.alarm_units = cache.alarm_units or {}
    cache.alarm_units[unit_number] = nil
    if remaining_alarm_count(cache) == 0 and not cache.alarm_clear_announced then
        cache.alarm_clear_announced = true
        local force = game.forces[record.owner_force_index]
        if force and force.valid then force.print({ "the-cave-fortified-vault.cache-cleared" }) end
    end
end

function fortified_vaults.on_chunk_generated(event)
    local record=record_for_surface(event.surface)
    if record and record.spiral_layout_version then spiral.on_chunk_generated(record,event) end
end
function fortified_vaults.on_player_changed_position(event)
    local player=game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local record=record_for_surface(physical.surface(player))
    if record and record.spiral then spiral.player_position(record,player) end
end
function fortified_vaults.on_biter_base_built(event)
    local e=event.entity
    local record=e and e.valid and record_for_surface(e.surface)
    if record and record.spiral then
        -- Expansion is never allowed to repopulate a cleared stage.
        if spiral.stage_at(e.position,record)~=record.spiral.active or record.spiral.complete then e.destroy() end
        return true
    end
    return false
end
function fortified_vaults.on_tiles_changed(surface,tiles)
    local record=record_for_surface(surface)
    if record and record.spiral then spiral.restore_tiles(record,{tiles=tiles});return true end
    return false
end

function fortified_vaults.on_surface_deleted(event)
    local index = event and event.surface_index
    if not index then return end
    local r = root()
    local id = r.by_surface[index]
    if id and r.by_id[id] then
        r.by_id[id].child_surface_index = nil
        r.by_surface[index] = nil
    end
end

function fortified_vaults.spawn_test_entrance(player, level)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "the-cave-fortified-vault.admin-only" }) return end
    level = tostring(level or "medium"):lower()
    if not TIER_LAYOUT[level] then level = "medium" end
    local target = { x = math.floor(player.position.x), y = math.floor(player.position.y) }
    local record = fortified_vaults.create_upper_entrance(
        player.surface, target.x, target.y,
        player.surface.map_gen_settings.seed or 0,
        { level_id = level }, player.force, { size = level == "medium" and 20 or (level == "hard" and 22 or 24) }
    )
    if record then
        record.test_bypass = true
        player.print({ "the-cave-fortified-vault.test-created", level })
    else
        player.print({ "the-cave-fortified-vault.test-failed" })
    end
end


function fortified_vaults.start_close_test(player)
    if not (player and player.valid) then return end
    if not player.admin then player.print({ "the-cave-fortified-vault.admin-only" }) return end
    local record = record_for_surface(player.surface)
    if not record then
        player.print({ "the-cave-fortified-vault.close-test-inside" })
        return
    end
    if record.status == "closed" then
        player.print({ "the-cave-fortified-vault.sealed" })
        return
    end
    record.timer_started_tick = record.timer_started_tick or game.tick
    record.close_tick = game.tick + 60 * 60
    record.warned_five = true
    record.warned_one = false
    update_timer_labels(record, game.tick)
    player.print({ "the-cave-fortified-vault.close-test-started" })
end

function fortified_vaults.register_commands()
    if not commands then return end
    commands.add_command("the-cave-fortified-vault-test", { "the-cave-fortified-vault.command-help" }, function(command)
        local player = command.player_index and game.get_player(command.player_index)
        if player then fortified_vaults.spawn_test_entrance(player, command.parameter) end
    end)
    commands.add_command("the-cave-fortified-vault-close-test", { "the-cave-fortified-vault.command-close-help" }, function(command)
        local player = command.player_index and game.get_player(command.player_index)
        if player then fortified_vaults.start_close_test(player) end
    end)
end

function fortified_vaults.owned_surfaces(force)
    return child_state.owned_surfaces(root(), force, "child_surface_index", SURFACE_PREFIX, true)
end

function fortified_vaults.owner_force(surface)
    return child_state.owner_force(root(), surface, "child_surface_index", SURFACE_PREFIX, true)
end

function fortified_vaults.clear_force(force_index)
    child_state.clear_force(root(), force_index)
end

function fortified_vaults.transfer_force(source_index, destination_index)
    child_state.transfer_force(root(), source_index, destination_index)
end

return fortified_vaults
