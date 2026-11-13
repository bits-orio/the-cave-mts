local physical = require("scripts.player_physical")
local market_coin = {}
local market_policy = require("scripts.market_policy")
local depth_levels = require("scripts.depth_levels")
local portable_tanks = require("scripts.portable_tanks")

local MARKET_POSITION = { x = 0, y = -8 }

local MARKET_PORTAL_BUTTON = "the_cave_market_portal_button"
local MARKET_FRAME = "the_cave_market_frame"

local function destroy_market_portal_button(player)
    if not player or not player.valid then return end

    -- Clean up old test versions that used player.gui.screen.
    if player.gui.screen then
        local old_screen_button = player.gui.screen[MARKET_PORTAL_BUTTON]
        if old_screen_button and old_screen_button.valid then old_screen_button.destroy() end
    end

    if player.gui.relative then
        local relative_button = player.gui.relative[MARKET_PORTAL_BUTTON]
        if relative_button and relative_button.valid then relative_button.destroy() end
    end
    local top_button = player.gui.top and player.gui.top[MARKET_PORTAL_BUTTON]
    if top_button and top_button.valid then top_button.destroy() end
end

local function style_market_portal_button(button)
    if not button or not button.valid then return end
    button.style.width = 64
    button.style.height = 64
    button.style.padding = 2
end

function market_coin.ensure_market_portal_button(player, visible)
    if not player or not player.valid then return end
    if not market_policy.enabled() then
        destroy_market_portal_button(player)
        return
    end

    -- Important: this must live in player.gui.relative and be anchored to the
    -- controller/inventory GUI. That makes Factorio show it only while the
    -- inventory opened with E is visible. It is not a permanent HUD button.
    if player.gui.screen then
        local old_screen_button = player.gui.screen[MARKET_PORTAL_BUTTON]
        if old_screen_button and old_screen_button.valid then old_screen_button.destroy() end
    end

    local button = player.gui.relative and player.gui.relative[MARKET_PORTAL_BUTTON]
    if not (button and button.valid) then
        local ok, created = pcall(function()
            return player.gui.relative.add {
                type = "sprite-button",
                name = MARKET_PORTAL_BUTTON,
                sprite = "item/coin",
                tooltip = "Open The Cave Market",
                anchor = {
                    gui = defines.relative_gui_type.controller_gui,
                    position = defines.relative_gui_position.right
                }
            }
        end)

        if ok and created and created.valid then
            button = created
        else
            -- Very defensive fallback: if relative GUI is unavailable for some
            -- reason, create a text button in top GUI so the feature still works.
            -- Normal gameplay should use the relative coin button above.
            button = player.gui.top[MARKET_PORTAL_BUTTON]
            if not (button and button.valid) then
                button = player.gui.top.add {
                    type = "button",
                    name = MARKET_PORTAL_BUTTON,
                    caption = "Market",
                    tooltip = "Open The Cave Market"
                }
            end
        end

        style_market_portal_button(button)
    end

    button.visible = visible ~= false
end

function market_coin.show_market_portal_button(player)
    market_coin.ensure_market_portal_button(player, true)
end

function market_coin.hide_market_portal_button(player)
    -- With relative GUI, hiding is normally handled by Factorio when the
    -- inventory closes. Do not destroy it every time; keep it ready for E.
    market_coin.ensure_market_portal_button(player, true)
end

function market_coin.update_market_portal_button_for_player(player)
    if not player or not player.valid then return end
    market_coin.ensure_market_portal_button(player, true)
end

function market_coin.refresh_market_portal_buttons()
    if not game or not game.players then return end
    for _, player in pairs(game.players) do
        market_coin.update_market_portal_button_for_player(player)
    end
end

local bob_enemies = require("scripts.bob_enemies")
local COIN_VALUES = {
    -- Nauvis biters
    ["small-biter"] = 1,
    ["medium-biter"] = 2,
    ["big-biter"] = 3,
    ["behemoth-biter"] = 5,

    -- Armoured Biters use the equivalent vanilla tier reward. Leviathan is the
    -- rare tier above Behemoth and consumes twice its coin value.
    ["small-armoured-biter"] = 1,
    ["medium-armoured-biter"] = 2,
    ["big-armoured-biter"] = 3,
    ["behemoth-armoured-biter"] = 5,
    ["leviathan-armoured-biter"] = 10,

    -- Nauvis spitters
    ["small-spitter"] = 1,
    ["medium-spitter"] = 2,
    ["big-spitter"] = 3,
    ["behemoth-spitter"] = 5,

    -- Nauvis worms
    ["small-worm-turret"] = 2,
    ["medium-worm-turret"] = 4,
    ["big-worm-turret"] = 8,
    ["behemoth-worm-turret"] = 16,

    -- Nauvis nests are handled by the finite Nest Coin Value system below.
    -- Destroying a nest does not directly refund its remaining value.

    -- Vulcanus demolishers
    ["small-demolisher"] = 100,
    ["medium-demolisher"] = 200,
    ["big-demolisher"] = 400,

    -- Gleba wrigglers
    ["small-wriggler-pentapod"] = 1,
    ["medium-wriggler-pentapod"] = 2,
    ["big-wriggler-pentapod"] = 3,
    ["small-wriggler-pentapod-premature"] = 1,
    ["medium-wriggler-pentapod-premature"] = 2,
    ["big-wriggler-pentapod-premature"] = 3,

    -- Gleba strafers
    ["small-strafer-pentapod"] = 10,
    ["medium-strafer-pentapod"] = 20,
    ["big-strafer-pentapod"] = 40,

    -- Gleba stompers
    ["small-stomper-pentapod"] = 20,
    ["medium-stomper-pentapod"] = 50,
    ["big-stomper-pentapod"] = 100,

    -- Gleba egg rafts / pentapod spawners are not part of the Nauvis nest budget system yet.
}

local TRAIN_WAVE_UNIT_PREFIX = "the-cave-train-wave-"
local TRAIN_WAVE_COIN_SETTINGS = {
    ["small-biter"] = { name = "the-cave-train-wave-small-coin-drop", default = 2 },
    ["small-spitter"] = { name = "the-cave-train-wave-small-coin-drop", default = 2 },
    ["medium-biter"] = { name = "the-cave-train-wave-medium-coin-drop", default = 3 },
    ["medium-spitter"] = { name = "the-cave-train-wave-medium-coin-drop", default = 3 },
    ["big-biter"] = { name = "the-cave-train-wave-big-coin-drop", default = 4 },
    ["big-spitter"] = { name = "the-cave-train-wave-big-coin-drop", default = 4 },
    ["behemoth-biter"] = { name = "the-cave-train-wave-behemoth-coin-drop", default = 6 },
    ["behemoth-spitter"] = { name = "the-cave-train-wave-behemoth-coin-drop", default = 6 },
}
local TRAIN_WAVE_BOSS_COIN_SETTING = "the-cave-train-wave-boss-coin-drop"
local TRAIN_WAVE_BOSS_COIN_DEFAULT = 6

local function runtime_global_amount(name, default)
    local setting = settings and settings.global and settings.global[name]
    local value = setting and tonumber(setting.value) or tonumber(default) or 0
    return math.max(0, math.floor(value))
end

local function train_wave_base_unit_name(name)
    if type(name) ~= "string"
        or name:sub(1, #TRAIN_WAVE_UNIT_PREFIX) ~= TRAIN_WAVE_UNIT_PREFIX then
        return nil
    end

    local suffix = name:sub(#TRAIN_WAVE_UNIT_PREFIX + 1)
    local tier, kind = suffix:match("^([a-z]+)%-([a-z]+)$")
    if tier and kind then
        -- The two additional scheduled families share the existing per-tier
        -- Wave settings. This does not add rewards to their ordinary variants.
        if kind == "armoured" or kind == "arachnid" then kind = "biter" end
        local base_name = tier .. "-" .. kind
        if TRAIN_WAVE_COIN_SETTINGS[base_name] then return base_name, false end
    end

    -- Current Bosses use Behemoth Biters; legacy saves can still contain older
    -- Big-Biter Boss prototypes. Every Train Wave Boss shares the dedicated
    -- live Boss reward setting regardless of its compatibility prototype tier.
    local boss_tier = suffix:match("^boss%-([a-z]+)%-biter%-l%d+$")
    local boss_base = boss_tier and (boss_tier .. "-biter") or nil
    if boss_base and COIN_VALUES[boss_base] then return boss_base, true end
    return nil, false
end

local SPECIAL_ITEMS = {
    -- Power / essential cave materials
    { "wood", 1, 5 },
    { "landfill", 20 },
    { "heat-pipe", 50 },
    { "solar-panel", 100 },
    { "accumulator", 100 },
    { "the-cave-portable-power-interface-mk1", 100 },
    { "the-cave-portable-power-interface-mk2", 200 },
    { "the-cave-portable-power-interface-mk3", 400 },
    { "the-cave-portable-power-interface-mk4", 600 },
    { "the-cave-portable-power-interface-mk5", 800 },

    -- MK Power upgrades
    { "the-cave-solar-panel-mk1", 220 },
    { "the-cave-solar-panel-mk2", 350 },
    { "the-cave-solar-panel-mk3", 520 },
    { "the-cave-solar-panel-mk4", 700 },
    { "the-cave-solar-panel-mk5", 900 },
    { "the-cave-accumulator-mk1", 150 },
    { "the-cave-accumulator-mk2", 300 },
    { "the-cave-accumulator-mk3", 600 },
    { "the-cave-accumulator-mk4", 1200 },
    { "the-cave-accumulator-mk5", 1600 },
    { "the-cave-steam-engine-mk1", 100 },
    { "the-cave-steam-engine-mk2", 120 },
    { "the-cave-steam-engine-mk3", 130 },
    { "the-cave-steam-engine-mk4", 140 },
    { "the-cave-steam-engine-mk5", 150 },
    { "the-cave-boiler-mk1", 200 },
    { "the-cave-boiler-mk2", 240 },
    { "the-cave-boiler-mk3", 260 },
    { "the-cave-boiler-mk4", 280 },
    { "the-cave-boiler-mk5", 300 },
    { "the-cave-medium-electric-pole-mk1", 20 },
    { "the-cave-medium-electric-pole-mk2", 25 },
    { "the-cave-medium-electric-pole-mk3", 30 },
    { "the-cave-medium-electric-pole-mk4", 35 },
    { "the-cave-medium-electric-pole-mk5", 40 },
    { "the-cave-large-electric-pole-mk1", 100 },
    { "the-cave-large-electric-pole-mk2", 130 },
    { "the-cave-large-electric-pole-mk3", 160 },
    { "the-cave-large-electric-pole-mk4", 220 },
    { "the-cave-large-electric-pole-mk5", 260 },
    { "the-cave-substation-mk1", 180 },
    { "the-cave-substation-mk2", 220 },
    { "the-cave-substation-mk3", 280 },
    { "the-cave-substation-mk4", 360 },
    { "the-cave-substation-mk5", 450 },
    { "electric-furnace", 200 },

    -- MK Production upgrades
    { "the-cave-electric-steel-furnace-mk1", 100 },
    { "the-cave-electric-steel-furnace-mk2", 140 },
    { "the-cave-electric-steel-furnace-mk3", 190 },
    { "the-cave-electric-steel-furnace-mk4", 250 },
    { "the-cave-electric-steel-furnace-mk5", 330 },
    { "the-cave-electric-furnace-mk1", 210 },
    { "the-cave-electric-furnace-mk2", 250 },
    { "the-cave-electric-furnace-mk3", 320 },
    { "the-cave-electric-furnace-mk4", 420 },
    { "the-cave-electric-furnace-mk5", 550 },
    { "the-cave-assembling-machine-4", 400 },
    { "the-cave-assembling-machine-5", 650 },
    { "the-cave-beacon-mk1", 450 },
    { "the-cave-beacon-mk2", 650 },
    { "the-cave-beacon-mk3", 900 },
    { "the-cave-beacon-mk4", 1250 },
    { "the-cave-beacon-mk5", 1700 },
    { "electric-mining-drill", 80 },
    { "the-cave-electric-mining-drill-mk1", 120 },
    { "the-cave-electric-mining-drill-mk2", 170 },
    { "the-cave-electric-mining-drill-mk3", 240 },
    { "the-cave-electric-mining-drill-mk4", 340 },
    { "the-cave-electric-mining-drill-mk5", 500 },
    { "heat-exchanger", 500 },
    { "steam-turbine", 500 },
    { "substation", 150 },
    { "beacon", 300 },
    { "heating-tower", 3000 },

    -- Logistics
    { "logistic-robot", 100 },
    { "construction-robot", 100 },
    { "storage-chest", 500 },
    { "passive-provider-chest", 500 },
    { "loader", 50 },
    { "fast-loader", 100 },
    { "express-loader", 150 },
    { "turbo-loader", 200 },
    { "roboport", 2000 },

    -- MK Logistics upgrades
    { "the-cave-roboport-mk1", 2200 },
    { "the-cave-roboport-mk2", 2600 },
    { "the-cave-roboport-mk3", 3200 },
    { "the-cave-roboport-mk4", 4000 },
    { "the-cave-roboport-mk5", 5000 },
    { "the-cave-storage-tank-mk1", 300 },
    { "the-cave-storage-tank-mk2", 350 },
    { "the-cave-storage-tank-mk3", 400 },
    { "the-cave-storage-tank-mk4", 450 },
    { "the-cave-storage-tank-mk5", 500 },
    { "the-cave-radar-mk1", 300 },
    { "the-cave-radar-mk2", 450 },
    { "the-cave-radar-mk3", 650 },
    { "the-cave-radar-mk4", 900 },
    { "the-cave-radar-mk5", 1200 },

    -- Fluids & Barrels. Each buy deal gives one full barrel stack (10 barrels).
    { "water-barrel", 5, 10 },
    { "crude-oil-barrel", 20, 10 },
    { "light-oil-barrel", 40, 10 },
    { "petroleum-gas-barrel", 50, 10 },
    { "heavy-oil-barrel", 60, 10 },
    { "lubricant-barrel", 60, 10 },
    { "sulfuric-acid-barrel", 60, 10 },

    -- Modules
    { "speed-module", 100 },
    { "efficiency-module", 100 },
    { "productivity-module", 100 },
    { "quality-module", 100 },
    { "speed-module-2", 750 },
    { "efficiency-module-2", 750 },
    { "productivity-module-2", 750 },
    { "quality-module-2", 750 },
    { "speed-module-3", 5000 },
    { "efficiency-module-3", 5000 },
    { "productivity-module-3", 5000 },
    { "quality-module-3", 5000 },

    -- Armor & Equipment
    { "solar-panel-equipment", 200 },
    { "battery-equipment", 200 },
    { "battery-mk2-equipment", 750 },
    { "energy-shield-equipment", 750 },
    { "modular-armor", 1000 },
    { "personal-roboport-equipment", 1500 },
    { "exoskeleton-equipment", 2000 },
    { "energy-shield-mk2-equipment", 3000 },
    { "personal-laser-defense-equipment", 3000 },
    { "power-armor", 6000 },
    { "fission-reactor-equipment", 10000 },
    { "fusion-reactor-equipment", 12000 },
    { "personal-roboport-mk2-equipment", 12000 },
    { "power-armor-mk2", 25000 },

    -- MK Military equipment upgrades
    { "the-cave-toolbelt-equipment-mk1", 2500 },
    { "the-cave-toolbelt-equipment-mk2", 3500 },
    { "the-cave-toolbelt-equipment-mk3", 5000 },
    { "the-cave-toolbelt-equipment-mk4", 7000 },
    { "the-cave-toolbelt-equipment-mk5", 10000 },

    -- Vehicles
    { "car", 2000 },
    { "tank", 12000 },
    { "spidertron", 120000 },

    -- Nuclear
    { "uranium-fuel-cell", 100 },
    { "nuclear-fuel", 500 },
    { "centrifuge", 8000 },
    { "nuclear-reactor", 20000 },

    -- Military
    { "rocket", 10 },
    { "artillery-shell", 25 },
    { "explosive-rocket", 20 },
    { "poison-capsule", 20 },
    { "slowdown-capsule", 20 },
    { "flamethrower-ammo", 30 },
    { "flamethrower", 100 },
    { "rocket-launcher", 150 },
    { "flamethrower-turret", 500 },
    { "laser-turret", 500 },
    { "rocket-turret", 500 },
    { "artillery-turret", 5000 },
    { "atomic-bomb", 10000 },

    -- Space Age / progression extras
    { "recycler", 400 },
    { "biochamber", 500 },
    { "pentapod-egg", 1000 },
    { "tree-seed", 20 },
    { "yumako-seed", 20 },
    { "jellynut-seed", 20 },

    -- Other: optional TNT Boxes, one box per deal.
    { "the-cave-tnt-box-small", 30 },
    { "the-cave-tnt-box-medium", 40 },
    { "the-cave-tnt-box-large", 50 },
}

local RESEARCH_ITEMS = {}

-- Fixed prices per 25,000-unit tank. Missing DLC fluids and incompatible
-- portable-item prototypes are omitted from the live offers.
local FILLED_TANK_AMOUNT = 25000
local FILLED_TANK_OFFERS = {
    { "water", 100 },
    { "steam", 200, 165 },
    { "crude-oil", 750 },
    { "heavy-oil", 1500 },
    { "light-oil", 1250 },
    { "petroleum-gas", 1750 },
    { "lubricant", 2000 },
    { "sulfuric-acid", 3000 },
    { "lava", 500 },
    { "molten-iron", 1500 },
    { "molten-copper", 1500 },
    { "holmium-solution", 4000 },
    { "electrolyte", 6000 },
    { "ammoniacal-solution", 500 },
    { "ammonia", 1000 },
    { "lithium-brine", 2000 },
    { "fluorine", 1500 },
    { "fluoroketone-hot", 10000, 180 },
    { "fluoroketone-cold", 11000, -150 },
    { "thruster-fuel", 750 },
    { "thruster-oxidizer", 750 },
}

local item_exists
local tech_done

-- Market Test GUI (v1.8.4-test)
-- Prices stay exactly the same as SPECIAL_ITEMS above. This GUI only changes presentation and adds multi-buy buttons.
local CATEGORY_ORDER = { "MK", "Power", "Production", "Logistics", "Fluids & Barrels", "Military", "Vehicles", "Modules", "Other" }
local MK_CATEGORY_ORDER = { "Power", "Production", "Logistics", "Military" }
local MK_CATEGORY_INDEX = {}
for i, name in ipairs(MK_CATEGORY_ORDER) do
    MK_CATEGORY_INDEX[name] = i
end
local CATEGORY_INDEX = {}
for i, name in ipairs(CATEGORY_ORDER) do
    CATEGORY_INDEX[name] = i
end

local CATEGORY_SUBCATEGORY_ORDER = {
    ["Fluids & Barrels"] = { "Barrels", "Storage Tank" },
    ["Power"] = { "Solar & Storage", "Electric Network", "Steam Power", "Thermal Power", "Nuclear" },
    ["Production"] = { "Furnaces", "Beacons", "Miners" },
    ["Logistics"] = { "Loader", "Box", "Robots & Roboports" },
    ["Military"] = { "Armor", "Ammo", "Weapons", "Turrets" },
}
local CATEGORY_SUBCATEGORY_INDEX = {}
for category, subcategories in pairs(CATEGORY_SUBCATEGORY_ORDER) do
    CATEGORY_SUBCATEGORY_INDEX[category] = {}
    for i, name in ipairs(subcategories) do
        CATEGORY_SUBCATEGORY_INDEX[category][name] = i
    end
end

local MK_ITEM_SORT_ORDER = {}
local function add_mk_sort_family(prefix, family_order, first_mk, last_mk)
    for mk = first_mk, last_mk do
        MK_ITEM_SORT_ORDER[prefix .. tostring(mk)] = family_order * 100 + mk
    end
end
add_mk_sort_family("the-cave-portable-power-interface-mk", 10, 1, 5)
add_mk_sort_family("the-cave-solar-panel-mk", 20, 1, 5)
add_mk_sort_family("the-cave-accumulator-mk", 30, 1, 5)
add_mk_sort_family("the-cave-steam-engine-mk", 40, 1, 5)
add_mk_sort_family("the-cave-boiler-mk", 45, 1, 5)
add_mk_sort_family("the-cave-medium-electric-pole-mk", 50, 1, 5)
add_mk_sort_family("the-cave-large-electric-pole-mk", 60, 1, 5)
add_mk_sort_family("the-cave-substation-mk", 70, 1, 5)
add_mk_sort_family("the-cave-electric-steel-furnace-mk", 10, 1, 5)
add_mk_sort_family("the-cave-electric-furnace-mk", 20, 1, 5)
MK_ITEM_SORT_ORDER["the-cave-assembling-machine-4"] = 30 * 100 + 4
MK_ITEM_SORT_ORDER["the-cave-assembling-machine-5"] = 30 * 100 + 5
add_mk_sort_family("the-cave-beacon-mk", 40, 1, 5)
add_mk_sort_family("the-cave-electric-mining-drill-mk", 50, 1, 5)
add_mk_sort_family("the-cave-roboport-mk", 10, 1, 5)
add_mk_sort_family("the-cave-storage-tank-mk", 20, 1, 5)
add_mk_sort_family("the-cave-radar-mk", 30, 1, 5)
add_mk_sort_family("the-cave-toolbelt-equipment-mk", 10, 1, 5)

local MULTI_BUY_COUNTS = { 1, 5, 10, 25, 50, 100 }

local MARKET_ICON_COLUMN_WIDTH = 36
local MARKET_ITEM_COLUMN_WIDTH = 220
local MARKET_PRICE_COLUMN_WIDTH = 120
local MARKET_DEAL_COLUMN_WIDTH = 160
local MARKET_AMOUNT_BUTTON_WIDTH = 58


-- Some placeable vehicles, buildings, equipment items, and Space Age items do not expose
-- their readable name through item-name.* locale keys. The market should never show raw
-- prototype IDs or "Unknown key" text, so market rows use this display-name helper.
local MARKET_ITEM_DISPLAY_NAMES = {
    ["the-cave-portable-power-interface-mk1"] = "MK1 50kW",
    ["the-cave-portable-power-interface-mk2"] = "MK2 80kW",
    ["the-cave-portable-power-interface-mk3"] = "MK3 100kW",
    ["the-cave-portable-power-interface-mk4"] = "MK4 150kW",
    ["the-cave-portable-power-interface-mk5"] = "MK5 250kW",


    -- MK market display names
    ["the-cave-solar-panel-mk1"] = "Solar Panel MK1",
    ["the-cave-solar-panel-mk2"] = "Solar Panel MK2",
    ["the-cave-solar-panel-mk3"] = "Solar Panel MK3",
    ["the-cave-solar-panel-mk4"] = "Solar Panel MK4",
    ["the-cave-solar-panel-mk5"] = "Solar Panel MK5",
    ["the-cave-accumulator-mk1"] = "Accumulator MK1",
    ["the-cave-accumulator-mk2"] = "Accumulator MK2",
    ["the-cave-accumulator-mk3"] = "Accumulator MK3",
    ["the-cave-accumulator-mk4"] = "Accumulator MK4",
    ["the-cave-accumulator-mk5"] = "Accumulator MK5",
    ["the-cave-steam-engine-mk1"] = "Steam Engine MK1",
    ["the-cave-steam-engine-mk2"] = "Steam Engine MK2",
    ["the-cave-steam-engine-mk3"] = "Steam Engine MK3",
    ["the-cave-steam-engine-mk4"] = "Steam Engine MK4",
    ["the-cave-steam-engine-mk5"] = "Steam Engine MK5",
    ["the-cave-boiler-mk1"] = "Boiler MK1",
    ["the-cave-boiler-mk2"] = "Boiler MK2",
    ["the-cave-boiler-mk3"] = "Boiler MK3",
    ["the-cave-boiler-mk4"] = "Boiler MK4",
    ["the-cave-boiler-mk5"] = "Boiler MK5",
    ["the-cave-medium-electric-pole-mk1"] = "Medium Electric Pole MK1",
    ["the-cave-medium-electric-pole-mk2"] = "Medium Electric Pole MK2",
    ["the-cave-medium-electric-pole-mk3"] = "Medium Electric Pole MK3",
    ["the-cave-medium-electric-pole-mk4"] = "Medium Electric Pole MK4",
    ["the-cave-medium-electric-pole-mk5"] = "Medium Electric Pole MK5",
    ["the-cave-large-electric-pole-mk1"] = "Large Electric Pole MK1",
    ["the-cave-large-electric-pole-mk2"] = "Large Electric Pole MK2",
    ["the-cave-large-electric-pole-mk3"] = "Large Electric Pole MK3",
    ["the-cave-large-electric-pole-mk4"] = "Large Electric Pole MK4",
    ["the-cave-large-electric-pole-mk5"] = "Large Electric Pole MK5",
    ["the-cave-substation-mk1"] = "Substation MK1",
    ["the-cave-substation-mk2"] = "Substation MK2",
    ["the-cave-substation-mk3"] = "Substation MK3",
    ["the-cave-substation-mk4"] = "Substation MK4",
    ["the-cave-substation-mk5"] = "Substation MK5",
    ["the-cave-storage-tank-mk1"] = "Storage Tank MK1",
    ["the-cave-storage-tank-mk2"] = "Storage Tank MK2",
    ["the-cave-storage-tank-mk3"] = "Storage Tank MK3",
    ["the-cave-storage-tank-mk4"] = "Storage Tank MK4",
    ["the-cave-storage-tank-mk5"] = "Storage Tank MK5",
    ["the-cave-electric-steel-furnace-mk1"] = "Electric Steel Furnace MK1",
    ["the-cave-electric-steel-furnace-mk2"] = "Electric Steel Furnace MK2",
    ["the-cave-electric-steel-furnace-mk3"] = "Electric Steel Furnace MK3",
    ["the-cave-electric-steel-furnace-mk4"] = "Electric Steel Furnace MK4",
    ["the-cave-electric-steel-furnace-mk5"] = "Electric Steel Furnace MK5",
    ["the-cave-electric-furnace-mk1"] = "Electric Furnace MK1",
    ["the-cave-electric-furnace-mk2"] = "Electric Furnace MK2",
    ["the-cave-electric-furnace-mk3"] = "Electric Furnace MK3",
    ["the-cave-electric-furnace-mk4"] = "Electric Furnace MK4",
    ["the-cave-electric-furnace-mk5"] = "Electric Furnace MK5",
    ["the-cave-assembling-machine-4"] = "Assembling Machine 4",
    ["the-cave-assembling-machine-5"] = "Assembling Machine 5",
    ["the-cave-beacon-mk1"] = "Beacon MK1",
    ["the-cave-beacon-mk2"] = "Beacon MK2",
    ["the-cave-beacon-mk3"] = "Beacon MK3",
    ["the-cave-beacon-mk4"] = "Beacon MK4",
    ["the-cave-beacon-mk5"] = "Beacon MK5",
    ["the-cave-electric-mining-drill-mk1"] = "Electric Mining Drill MK1",
    ["the-cave-electric-mining-drill-mk2"] = "Electric Mining Drill MK2",
    ["the-cave-electric-mining-drill-mk3"] = "Electric Mining Drill MK3",
    ["the-cave-electric-mining-drill-mk4"] = "Electric Mining Drill MK4",
    ["the-cave-electric-mining-drill-mk5"] = "Electric Mining Drill MK5",
    ["the-cave-roboport-mk1"] = "Roboport MK1",
    ["the-cave-roboport-mk2"] = "Roboport MK2",
    ["the-cave-roboport-mk3"] = "Roboport MK3",
    ["the-cave-roboport-mk4"] = "Roboport MK4",
    ["the-cave-roboport-mk5"] = "Roboport MK5",
    ["the-cave-radar-mk1"] = "Radar MK1",
    ["the-cave-radar-mk2"] = "Radar MK2",
    ["the-cave-radar-mk3"] = "Radar MK3",
    ["the-cave-radar-mk4"] = "Radar MK4",
    ["the-cave-radar-mk5"] = "Radar MK5",
    ["the-cave-toolbelt-equipment-mk1"] = "Toolbelt Equipment MK1",
    ["the-cave-toolbelt-equipment-mk2"] = "Toolbelt Equipment MK2",
    ["the-cave-toolbelt-equipment-mk3"] = "Toolbelt Equipment MK3",
    ["the-cave-toolbelt-equipment-mk4"] = "Toolbelt Equipment MK4",
    ["the-cave-toolbelt-equipment-mk5"] = "Toolbelt Equipment MK5",

    ["heat-pipe"] = "Heat pipe",
    ["heat-exchanger"] = "Heat exchanger",
    ["steam-turbine"] = "Steam turbine",
    ["electric-furnace"] = "Electric furnace",
    ["beacon"] = "Beacon",
    ["electric-mining-drill"] = "Electric mining drill",
    ["substation"] = "Substation",
    ["heating-tower"] = "Heating tower",
    ["accumulator"] = "Accumulator",

    ["barrel"] = "Empty barrel",
    ["water-barrel"] = "Water barrel",
    ["crude-oil-barrel"] = "Crude oil barrel",
    ["light-oil-barrel"] = "Light oil barrel",
    ["petroleum-gas-barrel"] = "Petroleum gas barrel",
    ["heavy-oil-barrel"] = "Heavy oil barrel",
    ["lubricant-barrel"] = "Lubricant barrel",
    ["sulfuric-acid-barrel"] = "Sulfuric acid barrel",

    ["roboport"] = "Roboport",
    ["logistic-robot"] = "Logistic robot",
    ["construction-robot"] = "Construction robot",
    ["storage-chest"] = "Storage chest",
    ["passive-provider-chest"] = "Passive provider chest",
    ["loader"] = "Loader",
    ["fast-loader"] = "Fast loader",
    ["express-loader"] = "Express loader",
    ["turbo-loader"] = "Turbo loader",
    ["the-cave-tnt-box-small"] = "Small TNT Box",
    ["the-cave-tnt-box-medium"] = "Medium TNT Box",
    ["the-cave-tnt-box-large"] = "Large TNT Box",

    ["car"] = "Car",
    ["tank"] = "Tank",
    ["spidertron"] = "Spidertron",

    ["centrifuge"] = "Centrifuge",
    ["nuclear-reactor"] = "Nuclear reactor",
    ["recycler"] = "Recycler",
    ["biochamber"] = "Biochamber",
    ["pentapod-egg"] = "Pentapod Egg",
    ["rocket-turret"] = "Rocket Turret",

    ["solar-panel-equipment"] = "Portable solar panel",
    ["fission-reactor-equipment"] = "Portable fission reactor",
    ["fusion-reactor-equipment"] = "Portable fusion reactor",
    ["battery-equipment"] = "Battery equipment",
    ["battery-mk2-equipment"] = "Battery MK2 equipment",
    ["exoskeleton-equipment"] = "Exoskeleton",
    ["personal-roboport-equipment"] = "Personal roboport",
    ["personal-roboport-mk2-equipment"] = "Personal roboport MK2",
    ["energy-shield-equipment"] = "Energy shield",
    ["energy-shield-mk2-equipment"] = "Energy shield MK2",
    ["personal-laser-defense-equipment"] = "Personal laser defense",
}

local function make_readable_item_name(item)
    local name = item:gsub("%-equipment$", "")
    name = name:gsub("%-mk2", " MK2")
    name = name:gsub("%-mk3", " MK3")
    name = name:gsub("%-", " ")
    return (name:gsub("^%l", string.upper))
end

local function get_market_item_display_name(item)
    return MARKET_ITEM_DISPLAY_NAMES[item] or make_readable_item_name(item)
end

-- Sell prices are intentionally separate from buy prices.
-- Format: { item_name, item_count_per_deal, coins_per_deal }
-- Bulk resources sell in 100-item packs; advanced items sell one at a time.
local SELL_ITEMS = require("shared.market_sell_offers")

local function get_sell_items_sorted()
    local items = {}
    for _, entry in pairs(SELL_ITEMS) do
        if item_exists(entry[1]) then
            items[#items + 1] = { item = entry[1], count = entry[2], price = entry[3] }
        end
    end

    table.sort(items, function(a, b)
        if a.price == b.price then
            if a.count == b.count then
                return a.item < b.item
            end
            return a.count < b.count
        end
        return a.price < b.price
    end)

    return items
end

-- Read-only maintainer hook: the same optional-prototype-filtered offers
-- used by the Sell GUI, so headless checks cannot drift from the real list.
function market_coin.debug_sell_items()
    return get_sell_items_sorted()
end

local MARKET_MODES = { "Buy", "Sell" }

local ITEM_CATEGORIES = {
    ["wood"] = "Other",
    ["landfill"] = "Other",
    ["substation"] = "Power/Electric Network",
    ["solar-panel"] = "Power/Solar & Storage",
    ["accumulator"] = "Power/Solar & Storage",
    ["the-cave-portable-power-interface-mk1"] = "MK/Power",
    ["the-cave-portable-power-interface-mk2"] = "MK/Power",
    ["the-cave-portable-power-interface-mk3"] = "MK/Power",
    ["the-cave-portable-power-interface-mk4"] = "MK/Power",
    ["the-cave-portable-power-interface-mk5"] = "MK/Power",

    -- MK market categories
    ["the-cave-solar-panel-mk1"] = "MK/Power",
    ["the-cave-solar-panel-mk2"] = "MK/Power",
    ["the-cave-solar-panel-mk3"] = "MK/Power",
    ["the-cave-solar-panel-mk4"] = "MK/Power",
    ["the-cave-solar-panel-mk5"] = "MK/Power",
    ["the-cave-accumulator-mk1"] = "MK/Power",
    ["the-cave-accumulator-mk2"] = "MK/Power",
    ["the-cave-accumulator-mk3"] = "MK/Power",
    ["the-cave-accumulator-mk4"] = "MK/Power",
    ["the-cave-accumulator-mk5"] = "MK/Power",
    ["the-cave-steam-engine-mk1"] = "MK/Power",
    ["the-cave-steam-engine-mk2"] = "MK/Power",
    ["the-cave-steam-engine-mk3"] = "MK/Power",
    ["the-cave-steam-engine-mk4"] = "MK/Power",
    ["the-cave-steam-engine-mk5"] = "MK/Power",
    ["the-cave-boiler-mk1"] = "MK/Power",
    ["the-cave-boiler-mk2"] = "MK/Power",
    ["the-cave-boiler-mk3"] = "MK/Power",
    ["the-cave-boiler-mk4"] = "MK/Power",
    ["the-cave-boiler-mk5"] = "MK/Power",
    ["the-cave-medium-electric-pole-mk1"] = "MK/Power",
    ["the-cave-medium-electric-pole-mk2"] = "MK/Power",
    ["the-cave-medium-electric-pole-mk3"] = "MK/Power",
    ["the-cave-medium-electric-pole-mk4"] = "MK/Power",
    ["the-cave-medium-electric-pole-mk5"] = "MK/Power",
    ["the-cave-large-electric-pole-mk1"] = "MK/Power",
    ["the-cave-large-electric-pole-mk2"] = "MK/Power",
    ["the-cave-large-electric-pole-mk3"] = "MK/Power",
    ["the-cave-large-electric-pole-mk4"] = "MK/Power",
    ["the-cave-large-electric-pole-mk5"] = "MK/Power",
    ["the-cave-substation-mk1"] = "MK/Power",
    ["the-cave-substation-mk2"] = "MK/Power",
    ["the-cave-substation-mk3"] = "MK/Power",
    ["the-cave-substation-mk4"] = "MK/Power",
    ["the-cave-substation-mk5"] = "MK/Power",
    ["the-cave-storage-tank-mk1"] = "MK/Logistics",
    ["the-cave-storage-tank-mk2"] = "MK/Logistics",
    ["the-cave-storage-tank-mk3"] = "MK/Logistics",
    ["the-cave-storage-tank-mk4"] = "MK/Logistics",
    ["the-cave-storage-tank-mk5"] = "MK/Logistics",
    ["the-cave-electric-steel-furnace-mk1"] = "MK/Production",
    ["the-cave-electric-steel-furnace-mk2"] = "MK/Production",
    ["the-cave-electric-steel-furnace-mk3"] = "MK/Production",
    ["the-cave-electric-steel-furnace-mk4"] = "MK/Production",
    ["the-cave-electric-steel-furnace-mk5"] = "MK/Production",
    ["the-cave-electric-furnace-mk1"] = "MK/Production",
    ["the-cave-electric-furnace-mk2"] = "MK/Production",
    ["the-cave-electric-furnace-mk3"] = "MK/Production",
    ["the-cave-electric-furnace-mk4"] = "MK/Production",
    ["the-cave-electric-furnace-mk5"] = "MK/Production",
    ["the-cave-assembling-machine-4"] = "MK/Production",
    ["the-cave-assembling-machine-5"] = "MK/Production",
    ["the-cave-beacon-mk1"] = "MK/Production",
    ["the-cave-beacon-mk2"] = "MK/Production",
    ["the-cave-beacon-mk3"] = "MK/Production",
    ["the-cave-beacon-mk4"] = "MK/Production",
    ["the-cave-beacon-mk5"] = "MK/Production",
    ["the-cave-electric-mining-drill-mk1"] = "MK/Production",
    ["the-cave-electric-mining-drill-mk2"] = "MK/Production",
    ["the-cave-electric-mining-drill-mk3"] = "MK/Production",
    ["the-cave-electric-mining-drill-mk4"] = "MK/Production",
    ["the-cave-electric-mining-drill-mk5"] = "MK/Production",
    ["the-cave-roboport-mk1"] = "MK/Logistics",
    ["the-cave-roboport-mk2"] = "MK/Logistics",
    ["the-cave-roboport-mk3"] = "MK/Logistics",
    ["the-cave-roboport-mk4"] = "MK/Logistics",
    ["the-cave-roboport-mk5"] = "MK/Logistics",
    ["the-cave-radar-mk1"] = "MK/Logistics",
    ["the-cave-radar-mk2"] = "MK/Logistics",
    ["the-cave-radar-mk3"] = "MK/Logistics",
    ["the-cave-radar-mk4"] = "MK/Logistics",
    ["the-cave-radar-mk5"] = "MK/Logistics",
    ["the-cave-toolbelt-equipment-mk1"] = "MK/Military",
    ["the-cave-toolbelt-equipment-mk2"] = "MK/Military",
    ["the-cave-toolbelt-equipment-mk3"] = "MK/Military",
    ["the-cave-toolbelt-equipment-mk4"] = "MK/Military",
    ["the-cave-toolbelt-equipment-mk5"] = "MK/Military",

    ["heating-tower"] = "Power/Thermal Power",
    ["heat-pipe"] = "Power/Thermal Power",
    ["heat-exchanger"] = "Power/Thermal Power",
    ["steam-turbine"] = "Power/Thermal Power",
    ["electric-furnace"] = "Production/Furnaces",
    ["beacon"] = "Production/Beacons",
    ["electric-mining-drill"] = "Production/Miners",

    ["water-barrel"] = "Fluids & Barrels",
    ["crude-oil-barrel"] = "Fluids & Barrels",
    ["light-oil-barrel"] = "Fluids & Barrels",
    ["petroleum-gas-barrel"] = "Fluids & Barrels",
    ["heavy-oil-barrel"] = "Fluids & Barrels",
    ["lubricant-barrel"] = "Fluids & Barrels",
    ["sulfuric-acid-barrel"] = "Fluids & Barrels",

    ["roboport"] = "Logistics/Robots & Roboports",
    ["logistic-robot"] = "Logistics/Robots & Roboports",
    ["construction-robot"] = "Logistics/Robots & Roboports",
    ["storage-chest"] = "Logistics/Box",
    ["passive-provider-chest"] = "Logistics/Box",
    ["loader"] = "Logistics/Loader",
    ["fast-loader"] = "Logistics/Loader",
    ["express-loader"] = "Logistics/Loader",
    ["turbo-loader"] = "Logistics/Loader",

    ["modular-armor"] = "Military/Armor",
    ["power-armor"] = "Military/Armor",
    ["power-armor-mk2"] = "Military/Armor",
    ["solar-panel-equipment"] = "Military/Armor",
    ["fusion-reactor-equipment"] = "Military/Armor",
    ["fission-reactor-equipment"] = "Military/Armor",
    ["battery-equipment"] = "Military/Armor",
    ["battery-mk2-equipment"] = "Military/Armor",
    ["exoskeleton-equipment"] = "Military/Armor",
    ["personal-roboport-equipment"] = "Military/Armor",
    ["personal-roboport-mk2-equipment"] = "Military/Armor",
    ["energy-shield-equipment"] = "Military/Armor",
    ["energy-shield-mk2-equipment"] = "Military/Armor",
    ["personal-laser-defense-equipment"] = "Military/Armor",

    ["artillery-turret"] = "Military/Turrets",
    ["artillery-shell"] = "Military/Ammo",
    ["rocket-launcher"] = "Military/Weapons",
    ["rocket"] = "Military/Ammo",
    ["explosive-rocket"] = "Military/Ammo",
    ["atomic-bomb"] = "Military/Ammo",
    ["flamethrower"] = "Military/Weapons",
    ["flamethrower-ammo"] = "Military/Ammo",
    ["poison-capsule"] = "Military/Ammo",
    ["slowdown-capsule"] = "Military/Ammo",
    ["laser-turret"] = "Military/Turrets",
    ["flamethrower-turret"] = "Military/Turrets",
    ["rocket-turret"] = "Military/Turrets",

    ["car"] = "Vehicles",
    ["tank"] = "Vehicles",
    ["spidertron"] = "Vehicles",

    ["centrifuge"] = "Power/Nuclear",
    ["nuclear-reactor"] = "Power/Nuclear",
    ["uranium-fuel-cell"] = "Power/Nuclear",
    ["nuclear-fuel"] = "Power/Nuclear",

    ["speed-module"] = "Modules",
    ["speed-module-2"] = "Modules",
    ["speed-module-3"] = "Modules",
    ["efficiency-module"] = "Modules",
    ["efficiency-module-2"] = "Modules",
    ["efficiency-module-3"] = "Modules",
    ["productivity-module"] = "Modules",
    ["productivity-module-2"] = "Modules",
    ["productivity-module-3"] = "Modules",
    ["quality-module"] = "Modules",
    ["quality-module-2"] = "Modules",
    ["quality-module-3"] = "Modules",

    ["recycler"] = "Other",
    ["biochamber"] = "Other",
    ["pentapod-egg"] = "Other",
    ["tree-seed"] = "Other",
    ["yumako-seed"] = "Other",
    ["jellynut-seed"] = "Other",
    ["the-cave-tnt-box-small"] = "Other",
    ["the-cave-tnt-box-medium"] = "Other",
    ["the-cave-tnt-box-large"] = "Other",
}

local function get_item_category(item)
    local category = ITEM_CATEGORIES[item] or "Other"
    if category == "Fluids & Barrels" then return category .. "/Barrels" end
    return category
end

local function get_player_coin_count(player)
    if not player or not player.valid or not item_exists("coin") then return 0 end
    local inv = player.get_main_inventory()
    if not inv or not inv.valid then return 0 end
    return inv.get_item_count("coin")
end


-- Nest Coin Value System (v1.8.22 experimental)
-- The two vanilla Nauvis nests and The Cave's Armoured nest share this finite
-- budget. Gleba pentapod/egg-raft prototypes remain intentionally separate.
local NEST_COIN_VALUE_RANGES = {
    easy = { min = 100, max = 500 },
    medium = { min = 250, max = 1000 },
    hard = { min = 500, max = 2500 },
    nightmare = { min = 1000, max = 5000 },
}

local NEST_COIN_ENTITY_NAMES = {
    ["biter-spawner"] = true,
    ["spitter-spawner"] = true,
    ["armoured-biter-spawner"] = true,
}
-- Fortified copies retain the finite coin budget of their original nest family.
for name,base in pairs(require("shared.fortified_combat").nest_aliases) do
    if NEST_COIN_ENTITY_NAMES[base] then NEST_COIN_ENTITY_NAMES[name]=true end
end

local SPAWNED_NAUVIS_UNITS = {
    ["small-biter"] = true,
    ["medium-biter"] = true,
    ["big-biter"] = true,
    ["behemoth-biter"] = true,
    ["small-spitter"] = true,
    ["medium-spitter"] = true,
    ["big-spitter"] = true,
    ["behemoth-spitter"] = true,
    ["small-armoured-biter"] = true,
    ["medium-armoured-biter"] = true,
    ["big-armoured-biter"] = true,
    ["behemoth-armoured-biter"] = true,
    ["leviathan-armoured-biter"] = true,
}

-- Dedicated hard-room offspring retain the original finite-budget rewards.
for name,base in pairs(require("shared.fortified_combat").offspring_aliases) do
    COIN_VALUES[name]=COIN_VALUES[base]
    SPAWNED_NAUVIS_UNITS[name]=SPAWNED_NAUVIS_UNITS[base]
end

local function ensure_nest_coin_storage()
    storage.the_cave_nest_coin_values = storage.the_cave_nest_coin_values or {}
    storage.the_cave_enemy_coin_carry = storage.the_cave_enemy_coin_carry or {}
    storage.the_cave_selected_nest_gui = storage.the_cave_selected_nest_gui or {}
    storage.the_cave_selected_nest_render = storage.the_cave_selected_nest_render or {}
end

local function is_coin_nest(entity)
    return entity and entity.valid and (NEST_COIN_ENTITY_NAMES[entity.name]
        or bob_enemies.nest_info(entity.name) ~= nil)
end

local function random_nest_coin_value(entity)
    local level = depth_levels.level_for_position(entity.position)
    local range = NEST_COIN_VALUE_RANGES[(level and level.id) or "easy"] or NEST_COIN_VALUE_RANGES.easy
    return math.random(range.min, range.max)
end

local function get_nest_coin_record(entity)
    if not is_coin_nest(entity) then return nil end
    local unit_number = entity.unit_number
    if not unit_number then return nil end

    ensure_nest_coin_storage()
    local record = storage.the_cave_nest_coin_values[unit_number]
    if not record then
        local initial = random_nest_coin_value(entity)
        local level = depth_levels.level_for_position(entity.position)
        record = {
            initial = initial,
            remaining = initial,
            level = (level and level.id) or "easy",
            name = entity.name,
            surface = entity.surface and entity.surface.name or nil,
            depleted_announced = false,
        }
        storage.the_cave_nest_coin_values[unit_number] = record
    end
    return record
end

local function remove_nest_coin_record(entity)
    if not entity or not entity.unit_number then return end
    ensure_nest_coin_storage()
    storage.the_cave_nest_coin_values[entity.unit_number] = nil
end

local function notify_nearby_players(surface, position, message)
    if not surface or not surface.valid then return end
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.surface == surface and player.position then
            local dx = player.position.x - position.x
            local dy = player.position.y - position.y
            if (dx * dx + dy * dy) <= (96 * 96) then
                player.print(message)
            end
        end
    end
end

local function destroy_player_nest_coin_gui(player)
    if not player or not player.valid then return end
    local gui_name = "the_cave_nest_coin_value_info"

    -- v1.8.22 test v2 used player.gui.left. Clean it up if a player upgrades
    -- while that temporary frame still exists.
    if player.gui.left and player.gui.left[gui_name] then
        player.gui.left[gui_name].destroy()
    end

    if player.gui.screen and player.gui.screen[gui_name] then
        player.gui.screen[gui_name].destroy()
    end

    if storage.the_cave_selected_nest_render then
        local render_id = storage.the_cave_selected_nest_render[player.index]
        if render_id then
            local obj = rendering.get_object_by_id(render_id)
            if obj then obj.destroy() end
            storage.the_cave_selected_nest_render[player.index] = nil
        end
    end

    if storage.the_cave_selected_nest_gui then
        storage.the_cave_selected_nest_gui[player.index] = nil
    end
end

local function update_player_nest_coin_gui(player)
    if not player or not player.valid then return end
    if not market_policy.enabled() then
        destroy_player_nest_coin_gui(player)
        return
    end
    ensure_nest_coin_storage()

    local gui_name = "the_cave_nest_coin_value_info"
    local selected = player.selected

    if not is_coin_nest(selected) then
        destroy_player_nest_coin_gui(player)
        return
    end

    local record = get_nest_coin_record(selected)
    if not record then return end

    local caption
    if (record.remaining or 0) <= 0 then
        caption = "Coin Value: Depleted"
    else
        caption = "Coin Value Remaining: " .. tostring(record.remaining)
    end

    -- Use screen GUI instead of gui.left. gui.left can be hidden or crowded by
    -- Factorio's entity info panel layout, while screen GUI is reliably visible
    -- when a nest is selected. This is informational only; it does not change the
    -- nest entity or Factorio's vanilla info panel.
    local existing = player.gui.screen[gui_name]
    if not existing then
        existing = player.gui.screen.add {
            type = "frame",
            name = gui_name,
            direction = "vertical",
            caption = "The Cave Nest"
        }
        existing.location = { x = 20, y = 120 }
        existing.style.minimal_width = 240
        existing.add { type = "label", name = "coin_value_label", caption = caption }
    elseif existing.coin_value_label then
        existing.coin_value_label.caption = caption
    end

    -- Extra reliable in-world display: Factorio's vanilla entity info panel cannot
    -- be extended directly, and screen GUI can be easy to miss on some layouts.
    -- This short text is tied to the selected nest and removed when selection changes.
    if storage.the_cave_selected_nest_render then
        local old_render_id = storage.the_cave_selected_nest_render[player.index]
        if old_render_id then
            local old_obj = rendering.get_object_by_id(old_render_id)
            if old_obj then old_obj.destroy() end
        end
    end

    local render_obj = rendering.draw_text {
        text = caption,
        surface = selected.surface,
        target = selected,
        target_offset = { 0, -2.25 },
        color = { r = 1, g = 0.86, b = 0.15, a = 1 },
        scale = 1.25,
        font = "default-large-bold",
        alignment = "center",
        scale_with_zoom = true,
        forces = player.force and { player.force } or nil,
        time_to_live = 60 * 60,
    }
    if render_obj then
        storage.the_cave_selected_nest_render[player.index] = render_obj.id
    end

    storage.the_cave_selected_nest_gui[player.index] = selected.unit_number
end

local function refresh_selected_nest_guis_for(entity)
    if not is_coin_nest(entity) then return end
    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.selected == entity then
            update_player_nest_coin_gui(player)
        end
    end
end

function market_coin.on_selected_entity_changed(event)
    local player = event.player_index and game.get_player(event.player_index)
    update_player_nest_coin_gui(player)
end

function market_coin.on_entity_spawned(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    local bob_unit = bob_enemies.unit_info(entity.name)
    if not SPAWNED_NAUVIS_UNITS[entity.name]
        and not (bob_unit and bob_unit.kind ~= "worm-turret") then return end

    local spawner = event.spawner or event.source or event.parent
    if not is_coin_nest(spawner) then return end

    local unit_number = entity.unit_number
    if not unit_number then return end

    ensure_nest_coin_storage()
    if not market_policy.enabled() then
        -- Mark disabled-period offspring as unpaid, without touching the nest's
        -- finite budget. They must not gain a fallback reward after re-enabling.
        storage.the_cave_enemy_coin_carry[unit_number] = 0
        return
    end
    local record = get_nest_coin_record(spawner)
    if not record then return end

    local value = COIN_VALUES[entity.name] or bob_enemies.coin_value(entity.name) or 0
    local carry = 0

    if value > 0 and (record.remaining or 0) > 0 then
        carry = math.min(value, record.remaining)
        record.remaining = record.remaining - carry
        if record.remaining < 0 then record.remaining = 0 end
    end

    -- Store even zero. A depleted nest should create tracked enemies that drop no coins,
    -- rather than falling back to the normal untracked enemy coin value.
    storage.the_cave_enemy_coin_carry[unit_number] = carry

    if (record.remaining or 0) <= 0 and not record.depleted_announced then
        record.depleted_announced = true
        notify_nearby_players(spawner.surface, spawner.position, "[The Cave] Nest depleted. No more coins from this nest.")
    end

    refresh_selected_nest_guis_for(spawner)
end

local function get_available_offers(force)
    local available_offers = {}

    for _, entry in pairs(SPECIAL_ITEMS) do
        if item_exists(entry[1]) then
            available_offers[#available_offers + 1] = {
                item = entry[1],
                price = entry[2],
                count = entry[3] or 1,
                category = get_item_category(entry[1])
            }
        end
    end

    for _, entry in ipairs(FILLED_TANK_OFFERS) do
        local stack = portable_tanks.make_filled_item(entry[1], FILLED_TANK_AMOUNT, entry[3])
        if stack then
            available_offers[#available_offers + 1] = {
                item = stack.name,
                price = entry[2],
                count = 1,
                category = "Fluids & Barrels/Storage Tank",
                stack = stack,
                display_name = { "the-cave-market.filled-tank-name", prototypes.fluid[entry[1]].localised_name }
            }
        end
    end

    for _, entry in pairs(RESEARCH_ITEMS) do
        if tech_done(force, entry[3]) and item_exists(entry[1]) then
            available_offers[#available_offers + 1] = {
                item = entry[1],
                price = entry[2],
                count = entry[4] or 1,
                category = get_item_category(entry[1])
            }
        end
    end

    table.sort(available_offers, function(a, b)
        local function category_sort_key(category)
            if category:match("^MK/") then
                local sub = category:match("^MK/(.+)$") or "Power"
                return (CATEGORY_INDEX["MK"] or 1) * 100 + (MK_CATEGORY_INDEX[sub] or 99)
            end
            local parent, sub = category:match("^(.-)/(.+)$")
            if parent then
                return (CATEGORY_INDEX[parent] or 999) * 100 + ((CATEGORY_SUBCATEGORY_INDEX[parent] and CATEGORY_SUBCATEGORY_INDEX[parent][sub]) or 99)
            end
            return (CATEGORY_INDEX[category] or 999) * 100
        end

        if a.category == b.category then
            local a_mk_sort = MK_ITEM_SORT_ORDER[a.item]
            local b_mk_sort = MK_ITEM_SORT_ORDER[b.item]
            if a_mk_sort or b_mk_sort then
                if a_mk_sort == b_mk_sort then return a.item < b.item end
                return (a_mk_sort or 99999) < (b_mk_sort or 99999)
            end
            if a.price == b.price then
                return a.item < b.item
            end
            return a.price < b.price
        end
        return category_sort_key(a.category) < category_sort_key(b.category)
    end)

    return available_offers
end

local function selected_category_for_player(player)
    storage.the_cave_market_gui_category = storage.the_cave_market_gui_category or {}
    local selected = storage.the_cave_market_gui_category[player.index] or "Power"
    if not CATEGORY_INDEX[selected] then selected = "Power" end
    return selected
end

local function set_selected_category_for_player(player, category)
    storage.the_cave_market_gui_category = storage.the_cave_market_gui_category or {}
    if CATEGORY_INDEX[category] then
        storage.the_cave_market_gui_category[player.index] = category
    else
        storage.the_cave_market_gui_category[player.index] = "Power"
    end
end

local function selected_mk_category_for_player(player)
    storage.the_cave_market_gui_mk_category = storage.the_cave_market_gui_mk_category or {}
    local selected = storage.the_cave_market_gui_mk_category[player.index] or "Power"
    if not MK_CATEGORY_INDEX[selected] then selected = "Power" end
    return selected
end

local function set_selected_mk_category_for_player(player, category)
    storage.the_cave_market_gui_mk_category = storage.the_cave_market_gui_mk_category or {}
    if MK_CATEGORY_INDEX[category] then
        storage.the_cave_market_gui_mk_category[player.index] = category
    else
        storage.the_cave_market_gui_mk_category[player.index] = "Power"
    end
end

local function selected_subcategory_for_player(player, category)
    storage.the_cave_market_gui_subcategory = storage.the_cave_market_gui_subcategory or {}
    storage.the_cave_market_gui_subcategory[player.index] = storage.the_cave_market_gui_subcategory[player.index] or {}
    local order = CATEGORY_SUBCATEGORY_ORDER[category]
    if not order then return category end
    local selected = storage.the_cave_market_gui_subcategory[player.index][category] or order[1]
    if not (CATEGORY_SUBCATEGORY_INDEX[category] and CATEGORY_SUBCATEGORY_INDEX[category][selected]) then
        selected = order[1]
    end
    return selected
end

local function set_selected_subcategory_for_player(player, category, subcategory)
    storage.the_cave_market_gui_subcategory = storage.the_cave_market_gui_subcategory or {}
    storage.the_cave_market_gui_subcategory[player.index] = storage.the_cave_market_gui_subcategory[player.index] or {}
    if CATEGORY_SUBCATEGORY_INDEX[category] and CATEGORY_SUBCATEGORY_INDEX[category][subcategory] then
        storage.the_cave_market_gui_subcategory[player.index][category] = subcategory
    end
end

local function subcategory_path(category, subcategory)
    if subcategory == category then return category end
    return category .. "/" .. subcategory
end

local function offer_matches_selected_category(player, offer)
    local selected = selected_category_for_player(player)
    if selected == "MK" then
        return offer.category == ("MK/" .. selected_mk_category_for_player(player))
    end
    if CATEGORY_SUBCATEGORY_ORDER[selected] then
        return offer.category == subcategory_path(selected, selected_subcategory_for_player(player, selected))
    end
    return offer.category == selected
end

local function selected_mode_for_player(player)
    storage.the_cave_market_gui_mode = storage.the_cave_market_gui_mode or {}
    local selected = storage.the_cave_market_gui_mode[player.index] or "Buy"
    if selected ~= "Buy" and selected ~= "Sell" then selected = "Buy" end
    return selected
end

local function set_selected_mode_for_player(player, mode)
    storage.the_cave_market_gui_mode = storage.the_cave_market_gui_mode or {}
    if mode == "Sell" then
        storage.the_cave_market_gui_mode[player.index] = "Sell"
    else
        storage.the_cave_market_gui_mode[player.index] = "Buy"
    end
end

local function add_market_label(parent, caption, width, bold)
    local label = parent.add { type = "label", caption = caption }
    if bold then label.style.font = "default-bold" end
    if width then label.style.minimal_width = width end
    return label
end

local function add_small_button(parent, name, caption, tooltip, enabled)
    local button = parent.add {
        type = "button",
        name = name,
        caption = caption,
        tooltip = tooltip
    }
    button.enabled = enabled
    button.style.width = MARKET_AMOUNT_BUTTON_WIDTH
    button.style.height = 28
    return button
end

local function destroy_market_gui(player)
    if not player or not player.valid then return end
    local frame = player.gui.screen[MARKET_FRAME]
    if frame and player.opened == frame then
        pcall(function() player.opened = nil end)
    end
    if frame then frame.destroy() end
end

local function build_buy_rows(player, container)
    local selected = selected_category_for_player(player)
    local coins = get_player_coin_count(player)
    local inv = player.get_main_inventory()
    local offers = get_available_offers(player.force)

    local table_gui = container.add { type = "table", name = "the_cave_market_table", column_count = 9 }
    table_gui.style.horizontally_stretchable = true
    table_gui.style.horizontal_spacing = 10
    table_gui.style.vertical_spacing = 4

    add_market_label(table_gui, "", MARKET_ICON_COLUMN_WIDTH, false)
    add_market_label(table_gui, "Item", MARKET_ITEM_COLUMN_WIDTH, true)
    add_market_label(table_gui, "Price", MARKET_PRICE_COLUMN_WIDTH, true)
    add_market_label(table_gui, "1", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "5", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "10", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "25", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "50", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "100", MARKET_AMOUNT_BUTTON_WIDTH, true)

    local shown = 0
    for _, offer in pairs(offers) do
        if offer_matches_selected_category(player, offer) then
            shown = shown + 1
            local display_name = offer.display_name or get_market_item_display_name(offer.item)
            local sprite = table_gui.add { type = "sprite", sprite = "item/" .. offer.item, tooltip = offer.stack and offer.stack.custom_description or { "", "[item=", offer.item, "] ", display_name } }
            sprite.style.width = 30
            sprite.style.height = 30

            local deal_count = offer.count or 1
            if offer.item == "wood" then
                display_name = { "", display_name, " × ", deal_count }
            end
            add_market_label(table_gui, display_name, MARKET_ITEM_COLUMN_WIDTH, false)
            if deal_count > 1 and offer.item ~= "wood" then
                add_market_label(table_gui, tostring(deal_count) .. " for " .. tostring(offer.price) .. " coins", MARKET_PRICE_COLUMN_WIDTH, false)
            else
                add_market_label(table_gui, tostring(offer.price) .. " coins", MARKET_PRICE_COLUMN_WIDTH, false)
            end

            for _, amount in pairs(MULTI_BUY_COUNTS) do
                local total_price = offer.price * amount
                local items_to_insert = deal_count * amount
                local can_afford = coins >= total_price
                local can_insert = inv and inv.valid and inv.can_insert({ name = offer.item, count = items_to_insert })
                if offer.stack then
                    can_insert = inv and inv.valid and inv.get_insertable_count({name = offer.item, quality = "normal"}) >= items_to_insert
                end
                add_small_button(
                    table_gui,
                    "the_cave_market_buy__" .. offer.item .. "__" .. amount,
                    tostring(amount),
                    "Buy " .. items_to_insert .. " for " .. total_price .. " coins",
                    can_afford and can_insert
                )
            end
        end
    end

    if shown == 0 then
        container.add { type = "label", caption = "No items in this category for the currently loaded mods." }
    end
end

local function build_sell_rows(player, container)
    local inv = player.get_main_inventory()
    local table_gui = container.add { type = "table", name = "the_cave_market_sell_table", column_count = 10 }
    table_gui.style.horizontally_stretchable = true
    table_gui.style.horizontal_spacing = 10
    table_gui.style.vertical_spacing = 4

    add_market_label(table_gui, "", MARKET_ICON_COLUMN_WIDTH, false)
    add_market_label(table_gui, "Item", MARKET_ITEM_COLUMN_WIDTH, true)
    add_market_label(table_gui, "Deal", MARKET_DEAL_COLUMN_WIDTH, true)
    add_market_label(table_gui, "1", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "5", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "10", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "25", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "50", MARKET_AMOUNT_BUTTON_WIDTH, true)
    add_market_label(table_gui, "100", MARKET_AMOUNT_BUTTON_WIDTH, true)

    add_market_label(table_gui, {"the-cave-market.all"}, MARKET_AMOUNT_BUTTON_WIDTH, true)

    local shown = 0
    for _, entry in pairs(get_sell_items_sorted()) do
        local item = entry.item
        local item_count_per_deal = entry.count
        local coins_per_deal = entry.price
        shown = shown + 1
        local inventory_count = inv and inv.valid and inv.get_item_count(item) or 0
        local display_name = get_market_item_display_name(item)
        local sprite = table_gui.add { type = "sprite", sprite = "item/" .. item, tooltip = { "", "[item=", item, "] ", display_name } }
        sprite.style.width = 30
        sprite.style.height = 30

        add_market_label(table_gui, display_name .. " (" .. tostring(inventory_count) .. ")", MARKET_ITEM_COLUMN_WIDTH, false)
        add_market_label(table_gui, tostring(item_count_per_deal) .. " -> " .. tostring(coins_per_deal) .. " coins", MARKET_DEAL_COLUMN_WIDTH, false)

        for _, deal_count in pairs(MULTI_BUY_COUNTS) do
            local items_to_remove = item_count_per_deal * deal_count
            local coins_to_add = coins_per_deal * deal_count
            add_small_button(
                table_gui,
                "the_cave_market_sell__" .. item .. "__" .. deal_count,
                tostring(deal_count),
                "Sell " .. items_to_remove .. " for " .. coins_to_add .. " coins",
                inventory_count >= items_to_remove
            )
        end
        add_small_button(
            table_gui,
            "the_cave_market_sell__" .. item .. "__all",
            {"the-cave-market.all"},
            {"the-cave-market.sell-all-tooltip"},
            inventory_count >= item_count_per_deal
        )
    end

    if shown == 0 then
        container.add { type = "label", caption = "No sellable items are available with the currently loaded mods." }
    end
end

local function refresh_market_gui(player)
    if not player or not player.valid then return end
    if not market_policy.enabled() then
        destroy_market_gui(player)
        return
    end
    local frame = player.gui.screen[MARKET_FRAME]
    if not frame then return end

    local body = frame["the_cave_market_body"]
    if body then body.destroy() end

    local body_new = frame.add { type = "flow", name = "the_cave_market_body", direction = "vertical" }
    body_new.style.vertically_stretchable = true

    local coins = get_player_coin_count(player)
    body_new.add { type = "label", caption = "Coins in inventory: " .. coins }.style.font = "default-bold"

    local mode = selected_mode_for_player(player)
    local mode_flow = body_new.add { type = "flow", name = "the_cave_market_mode_flow", direction = "horizontal" }
    mode_flow.add { type = "button", name = "the_cave_market_mode_buy", caption = mode == "Buy" and "[ Buy ]" or "Buy" }
    mode_flow.add { type = "button", name = "the_cave_market_mode_sell", caption = mode == "Sell" and "[ Sell ]" or "Sell" }

    if mode == "Buy" then
        local selected = selected_category_for_player(player)
        local category_flow = body_new.add { type = "flow", name = "the_cave_market_category_flow", direction = "horizontal" }
        for _, category in ipairs(CATEGORY_ORDER) do
            local button = category_flow.add {
                type = "button",
                name = "the_cave_market_category__" .. category,
                caption = category == selected and "[ " .. category .. " ]" or category
            }
            button.style.height = 28
        end

        if selected == "MK" then
            local mk_selected = selected_mk_category_for_player(player)
            local mk_category_flow = body_new.add { type = "flow", name = "the_cave_market_mk_category_flow", direction = "horizontal" }
            mk_category_flow.add { type = "label", caption = "MK:" }.style.font = "default-bold"
            for _, category in ipairs(MK_CATEGORY_ORDER) do
                local button = mk_category_flow.add {
                    type = "button",
                    name = "the_cave_market_mk_category__" .. category,
                    caption = category == mk_selected and "[ " .. category .. " ]" or category
                }
                button.style.height = 28
            end
        elseif CATEGORY_SUBCATEGORY_ORDER[selected] then
            local sub_selected = selected_subcategory_for_player(player, selected)
            local subcategory_flow = body_new.add { type = "flow", name = "the_cave_market_subcategory_flow", direction = "horizontal" }
            subcategory_flow.add { type = "label", caption = selected .. ":" }.style.font = "default-bold"
            for _, subcategory in ipairs(CATEGORY_SUBCATEGORY_ORDER[selected]) do
                local caption = subcategory
                if selected == "Fluids & Barrels" then
                    caption = {"the-cave-market." .. (subcategory == "Storage Tank" and "storage-tank" or "barrels")}
                end
                local button = subcategory_flow.add {
                    type = "button",
                    name = "the_cave_market_subcategory__" .. selected .. "__" .. subcategory,
                    caption = subcategory == sub_selected and {"", "[ ", caption, " ]"} or caption
                }
                button.style.height = 28
            end
        end
    else
        body_new.add { type = "label", caption = "Sell items from your inventory for coins. Buy prices are unchanged." }
    end

    local scroll = body_new.add { type = "scroll-pane", name = "the_cave_market_scroll" }
    scroll.style.maximal_height = 620
    scroll.style.minimal_width = 820
    if mode == "Sell" then
        build_sell_rows(player, scroll)
    else
        build_buy_rows(player, scroll)
    end
end

function market_coin.open_test_market_gui(player)
    if not player or not player.valid then return end
    destroy_market_gui(player)
    if not market_policy.enabled() then return end

    local frame = player.gui.screen.add { type = "frame", name = MARKET_FRAME, direction = "vertical", caption = "The Cave Market" }
    frame.auto_center = true
    frame.style.minimal_width = 900

    local header = frame.add { type = "flow", name = "the_cave_market_header", direction = "horizontal" }
    header.drag_target = frame
    header.add { type = "label", caption = "Buy and sell with coins." }
    local spacer = header.add { type = "empty-widget" }
    spacer.style.horizontally_stretchable = true
    local close_button = header.add { type = "button", name = "the_cave_market_close", caption = "Close" }
    close_button.style.width = 70
    close_button.style.height = 28

    refresh_market_gui(player)
    player.opened = frame
end

function market_coin.close_test_market_gui(player)
    destroy_market_gui(player)
end

function market_coin.on_gui_opened(event)
    if not event then return end
    local player = game.get_player(event.player_index)
    if not player then return end

    if not market_policy.enabled() then
        destroy_market_portal_button(player)
        if event.entity and event.entity.valid and event.entity.name == "market" then
            player.opened = nil
        end
        return
    end

    if event.gui_type == defines.gui_type.controller then
        market_coin.show_market_portal_button(player)
        return
    end

    if not event.entity or not event.entity.valid then return end
    if event.entity.name ~= "market" then return end

    -- Replace the vanilla market window with our test shop UI.
    pcall(function() player.opened = nil end)
    market_coin.open_test_market_gui(player)
end

function market_coin.on_gui_closed(event)
    if not event then return end
    local player = game.get_player(event.player_index)
    if not player then return end

    if event.element and event.element.valid and event.element.name == MARKET_FRAME then
        destroy_market_gui(player)
        return
    end

    -- The portal belongs to the inventory experience. When the inventory/editor
    -- inventory closes, the button disappears again.
    market_coin.update_market_portal_button_for_player(player)
end

function market_coin.on_player_created(event)
    local player = game.get_player(event.player_index)
    if player then market_coin.ensure_market_portal_button(player, false) end
end

function market_coin.on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    if player then market_coin.update_market_portal_button_for_player(player) end
end

function market_coin.on_player_display_changed(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local button = player.gui.screen[MARKET_PORTAL_BUTTON]
    if button and button.valid then
        position_market_portal_button(player, button)
    end
end

function market_coin.on_gui_selection_state_changed(event)
    if not market_policy.enabled() then return end
    local element = event.element
    if not element or not element.valid or element.name ~= "the_cave_market_category_dropdown" then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local category = CATEGORY_ORDER[element.selected_index] or "Power"
    set_selected_category_for_player(player, category)
    refresh_market_gui(player)
end

-- Player-triggered transactions only. Copy actual stacks so a failed exchange
-- restores the exact original slots, quality, tags and other stack metadata.
-- This also protects existing partially filled tanks during bulk purchases.
local function inventory_transaction(inventory, exchange)
    local backup = game.create_inventory(#inventory)
    for index = 1, #inventory do
        if inventory[index].valid_for_read and not backup[index].set_stack(inventory[index]) then
            backup.destroy()
            return false
        end
    end

    local ok, completed = pcall(exchange)
    if not ok or not completed then
        for index = 1, #inventory do
            if backup[index].valid_for_read then
                inventory[index].set_stack(backup[index])
            else
                inventory[index].clear()
            end
        end
    end
    backup.destroy()
    if not ok then log("[The Cave Market] Exchange rolled back: " .. tostring(completed)) end
    return ok and completed == true
end

function market_coin.on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    if not market_policy.enabled() then
        destroy_market_gui(player)
        destroy_market_portal_button(player)
        return
    end

    if element.name == MARKET_PORTAL_BUTTON then
        market_coin.open_test_market_gui(player)
        return
    end

    if element.name == "the_cave_market_close" then
        destroy_market_gui(player)
        return
    end

    if element.name == "the_cave_market_mode_buy" then
        set_selected_mode_for_player(player, "Buy")
        refresh_market_gui(player)
        return
    end

    if element.name == "the_cave_market_mode_sell" then
        set_selected_mode_for_player(player, "Sell")
        refresh_market_gui(player)
        return
    end

    local category = element.name:match("^the_cave_market_category__(.+)$")
    if category then
        set_selected_category_for_player(player, category)
        refresh_market_gui(player)
        return
    end

    local mk_category = element.name:match("^the_cave_market_mk_category__(.+)$")
    if mk_category then
        set_selected_mk_category_for_player(player, mk_category)
        refresh_market_gui(player)
        return
    end

    local subcategory_parent, subcategory = element.name:match("^the_cave_market_subcategory__(.-)__(.+)$")
    if subcategory_parent and subcategory then
        set_selected_subcategory_for_player(player, subcategory_parent, subcategory)
        refresh_market_gui(player)
        return
    end

    local sell_item, sell_deal_count_text = element.name:match("^the_cave_market_sell__(.+)__(%d+)$")
    if not sell_item then
        sell_item, sell_deal_count_text = element.name:match("^the_cave_market_sell__(.+)__(all)$")
    end
    if sell_item then
        if not item_exists(sell_item) or not item_exists("coin") then return end

        local item_count_per_deal
        local coins_per_deal
        for _, entry in pairs(SELL_ITEMS) do
            if entry[1] == sell_item then
                item_count_per_deal = entry[2]
                coins_per_deal = entry[3]
                break
            end
        end
        if not item_count_per_deal or not coins_per_deal then return end

        local inv = player.get_main_inventory()
        if not inv or not inv.valid then return end
        local inventory_count = inv.get_item_count({name = sell_item, quality = "normal"})
        local deal_count = sell_deal_count_text == "all"
            and math.floor(inventory_count / item_count_per_deal)
            or tonumber(sell_deal_count_text)
        if not deal_count or deal_count <= 0 then
            refresh_market_gui(player)
            return
        end
        local amount = item_count_per_deal * deal_count
        local coins_to_add = coins_per_deal * deal_count

        if inventory_count < amount then
            player.print("[The Cave Market] You do not have enough " .. sell_item .. " to sell.")
            refresh_market_gui(player)
            return
        end

        local completed = inventory_transaction(inv, function()
            if inv.remove({ name = sell_item, count = amount, quality = "normal" }) ~= amount then return false end
            -- Check after removal: selling can free the space needed for coins.
            if inv.get_insertable_count({name = "coin", quality = "normal"}) < coins_to_add then return false end
            return inv.insert({ name = "coin", count = coins_to_add, quality = "normal" }) == coins_to_add
        end)
        if not completed then
            player.print("[The Cave Market] Not enough inventory space for coins.")
            refresh_market_gui(player)
            return
        end

        player.print("[The Cave Market] Sold " .. amount .. " x " .. sell_item .. " for " .. coins_to_add .. " coins.")
        refresh_market_gui(player)
        return
    end

    local item, amount_text = element.name:match("^the_cave_market_buy__(.+)__(%d+)$")
    if not item then return end

    local amount = tonumber(amount_text) or 1
    if amount <= 0 then return end
    if not item_exists(item) or not item_exists("coin") then return end

    local price
    local count_per_deal = 1
    local filled_stack
    for _, offer in pairs(get_available_offers(player.force)) do
        if offer.item == item then
            price = offer.price
            count_per_deal = offer.count or 1
            filled_stack = offer.stack
            break
        end
    end
    if not price then return end

    local item_amount = count_per_deal * amount
    local total_price = price * amount
    if get_player_coin_count(player) < total_price then
        player.print("[The Cave Market] Not enough coins.")
        refresh_market_gui(player)
        return
    end

    local inv = player.get_main_inventory()
    if filled_stack then
        if not inv or not inv.valid
            or inv.get_insertable_count({name = item, quality = "normal"}) < item_amount then
            player.print("[The Cave Market] Not enough inventory space.")
            refresh_market_gui(player)
            return
        end

        filled_stack.count = item_amount
        local completed = inventory_transaction(inv, function()
            if inv.remove({name = "coin", count = total_price, quality = "normal"}) ~= total_price then return false end
            return inv.insert(filled_stack) == item_amount
        end)
        if completed then
            player.print({"the-cave-market.purchased-tanks", item_amount, total_price})
        else
            player.print({"the-cave-market.purchase-rolled-back"})
        end
        refresh_market_gui(player)
        return
    end

    if not inv or not inv.valid or not inv.can_insert({ name = item, count = item_amount }) then
        player.print("[The Cave Market] Not enough inventory space.")
        refresh_market_gui(player)
        return
    end

    local removed = player.remove_item({ name = "coin", count = total_price })
    if removed < total_price then
        if removed > 0 then player.insert({ name = "coin", count = removed }) end
        player.print("[The Cave Market] Not enough coins.")
        refresh_market_gui(player)
        return
    end

    local inserted = player.insert({ name = item, count = item_amount })
    if inserted < item_amount then
        if inserted > 0 then player.remove_item({ name = item, count = inserted }) end
        player.insert({ name = "coin", count = total_price })
        player.print("[The Cave Market] Not enough inventory space.")
        refresh_market_gui(player)
        return
    end

    player.print("[The Cave Market] Purchased " .. item_amount .. " x " .. item .. " for " .. total_price .. " coins.")
    refresh_market_gui(player)
end

function item_exists(name)
    if prototypes and prototypes.item and prototypes.item[name] then
        return true
    end

    local ok, items = pcall(function()
        return game.item_prototypes
    end)

    return ok and items and items[name] ~= nil
end

function tech_done(force, tech_name)
    local tech = force and force.technologies and force.technologies[tech_name]
    return tech and tech.researched
end

local function add_offer(market, item, price, count)
    if not market or not market.valid then return end
    if not item_exists(item) or not item_exists("coin") then return end
    pcall(function()
        market.add_market_item {
            price = { { name = "coin", count = price } },
            offer = { type = "give-item", item = item, count = count or 1 }
        }
    end)
end


local function cleanup_physical_markets()
    if not (game and game.surfaces) then return end
    for _, surface in pairs(game.surfaces) do
        if surface and surface.valid then
            for _, e in pairs(surface.find_entities_filtered { name = "market", area = { { -128, -128 }, { 128, 128 } } }) do
                if e and e.valid then pcall(function() e.destroy { raise_destroy = false } end) end
            end
        end
    end
    storage.the_cave_market_unit_number = nil
end

function market_coin.refresh_market()
    -- Physical market entity removed. The Cave Market is opened through the inventory coin portal.
end

function market_coin.get_market()
    return nil
end

function market_coin.ensure_market()
    cleanup_physical_markets()
    return nil
end

function market_coin.on_init()
    storage.the_cave_market_unit_number = storage.the_cave_market_unit_number or nil
    market_coin.ensure_market()
    market_coin.refresh_market_portal_buttons()
end

function market_coin.on_configuration_changed()
    market_coin.ensure_market()
    market_coin.refresh_market_portal_buttons()
    for _, player in pairs(game.players) do
        refresh_market_gui(player)
        if not market_policy.enabled() then destroy_player_nest_coin_gui(player) end
    end
end

function market_coin.on_research_finished(event)
    market_coin.refresh_market()
end


local function get_pickup_position(player)
    return physical.position(player)
end

local function try_pickup_coin(player, coin_entity)
    if not player or not player.valid or not coin_entity or not coin_entity.valid then return end
    local stack = coin_entity.stack
    if not stack or not stack.valid_for_read or stack.name ~= "coin" then return end

    local count = stack.count
    if count <= 0 then
        coin_entity.destroy()
        return
    end

    local inserted = player.insert { name = "coin", count = count }
    if inserted <= 0 then return end

    if inserted >= count then
        coin_entity.destroy()
    else
        stack.count = count - inserted
    end
end

function market_coin.auto_pickup_coins()
    if not market_policy.enabled() then return end
    if not item_exists("coin") then return end

    for _, player in pairs(game.connected_players) do
        if player and player.valid and player.controller_type ~= defines.controllers.spectator then
            local surface = physical.surface(player)
            local position = get_pickup_position(player)
            if surface and surface.valid and position then
                local radius = 1.15
                local coins = surface.find_entities_filtered {
                    name = "item-on-ground",
                    area = {
                        { position.x - radius, position.y - radius },
                        { position.x + radius, position.y + radius }
                    }
                }

                for _, coin_entity in pairs(coins) do
                    try_pickup_coin(player, coin_entity)
                end
            end
        end
    end
end

function market_coin.on_entity_died(event, suppress_rewards)
    local entity = event.entity
    if not entity or not entity.valid then return end

    -- Destroying a nest burns any remaining Coin Value. No refund, no bonus.
    if is_coin_nest(entity) then
        remove_nest_coin_record(entity)
        return
    end

    local count
    local unit_number = entity.unit_number

    ensure_nest_coin_storage()
    if suppress_rewards or not market_policy.enabled() then
        -- Released brood units never pay a second reward. Clear any unexpected
        -- spawner carry record as well so no stale Coin state survives.
        if unit_number then
            storage.the_cave_enemy_coin_carry[unit_number] = nil
        end
        return
    end

    if unit_number and storage.the_cave_enemy_coin_carry[unit_number] ~= nil then
        count = storage.the_cave_enemy_coin_carry[unit_number]
        storage.the_cave_enemy_coin_carry[unit_number] = nil
    else
        local base_name, is_train_wave_boss = train_wave_base_unit_name(entity.name)
        if is_train_wave_boss then
            count = runtime_global_amount(
                TRAIN_WAVE_BOSS_COIN_SETTING,
                TRAIN_WAVE_BOSS_COIN_DEFAULT
            )
        elseif base_name then
            local reward = TRAIN_WAVE_COIN_SETTINGS[base_name]
            count = runtime_global_amount(reward.name, reward.default)
        else
            count = COIN_VALUES[entity.name] or bob_enemies.coin_value(entity.name)
        end
    end

    if not count or count <= 0 then return end
    if not item_exists("coin") then return end

    local surface = entity.surface
    if not surface or not surface.valid then return end

    -- Do NOT use spill_item_stack with looted markers.
    -- It can display the ugly red X overlay on dropped coins.
    -- Plain item-on-ground keeps coins clean and still collectible/tradable.
    pcall(function()
        surface.create_entity {
            name = "item-on-ground",
            position = entity.position,
            stack = { name = "coin", count = count }
        }
    end)
end

return market_coin
