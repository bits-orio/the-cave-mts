

-- The Cave 1.5.7: Region Autoplace Test
-- Safe subset inspired by NauvisWithEverything.
-- Goal: make Space Age tile/resource/enemy/plant prototypes available on Nauvis map gen,
-- then The Cave runtime regions can use those prototype names.

local function tc_safe(fn)
    local ok, err = pcall(fn)
    if not ok then log("[The Cave Region Autoplace Test] " .. tostring(err)) end
end

tc_safe(function()
    local everything_on_nauvis = settings.startup["the-cave-everything-on-nauvis"]
    if everything_on_nauvis and (everything_on_nauvis.value == "disabled" or everything_on_nauvis.value == false) then
        log("[The Cave] Everything On Nauvis is OFF; leaving Space Age planet progression unchanged.")
        return
    end
    if not (data.raw.planet and data.raw.planet.nauvis and data.raw.planet.nauvis.map_gen_settings) then return end

    local mg = data.raw.planet.nauvis.map_gen_settings
    mg.autoplace_controls = mg.autoplace_controls or {}
    mg.autoplace_settings = mg.autoplace_settings or {}
    -- The Cave builds every resource by script. Keep entity autoplace completely
    -- disabled even while exposing Space Age controls/tiles for the regional
    -- systems below. Re-enabling resource entries here caused isolated vanilla
    -- Scrap/geysers/ores to survive inside the scripted cave.
    mg.autoplace_settings.entity = { settings = {}, treat_missing_as_default = false }
    mg.autoplace_settings.tile = mg.autoplace_settings.tile or {settings = {}}
    mg.autoplace_settings.tile.settings = mg.autoplace_settings.tile.settings or {}
    mg.property_expression_names = mg.property_expression_names or {}

    local controls = {
        "gleba_enemy_base",
        "gleba_plants",
        "vulcanus_volcanism",
        "sulfuric_acid_geyser",
        "calcite",
        "tungsten_ore",
        "scrap",
        "oil_ocean",
        "lithium_brine",
        "fluorine_vent",
        "ammoniacal_ocean",
        "coal",
        "stone",
        "crude-oil"
    }

    for _, c in pairs(controls) do
        if data.raw["autoplace-control"] and data.raw["autoplace-control"][c] then
            mg.autoplace_controls[c] = mg.autoplace_controls[c] or {}
        end
    end

    -- Do not add resource prototypes to Nauvis entity autoplace. Runtime
    -- region_features.lua creates Calcite, Tungsten, Scrap, Brine, Fluorine and
    -- Geysers only in their intended cave regions.

    local tiles = {
        -- Gleba
        "natural-yumako-soil", "natural-jellynut-soil",
        "wetland-yumako", "wetland-jellynut",
        "lowland-red-infection", "lowland-red-vein", "lowland-red-vein-2", "lowland-red-vein-3",
        "lowland-olive-blubber", "lowland-olive-blubber-2", "lowland-brown-blubber", "lowland-cream-red",

        -- Vulcanus
        "volcanic-soil-dark", "volcanic-soil-light",
        "volcanic-ash-dark", "volcanic-ash-light",
        "volcanic-cracks", "volcanic-cracks-hot",
        "volcanic-folds", "volcanic-folds-flat",
        "volcanic-pumice-stones", "volcanic-smooth-stone",
        "lava",

        -- Fulgora
        "fulgoran-dunes", "fulgoran-dust", "fulgoran-rock", "fulgoran-sand",
        "fulgoran-machinery", "fulgoran-paving",
        "oil-ocean-shallow", "oil-ocean-deep",

        -- Aquilo
        "snow-flat", "snow-crests", "snow-lumpy", "snow-patchy",
        "ice-rough", "ice-smooth", "brash-ice",
        "ammoniacal-ocean", "ammoniacal-ocean-2"
    }

    for _, t in pairs(tiles) do
        if data.raw.tile and data.raw.tile[t] then
            mg.autoplace_settings.tile.settings[t] = mg.autoplace_settings.tile.settings[t] or {}
        end
    end

    -- Allow Gleba overgrowth soils to be placed on normal cave floor tiles too.
    local base_tiles = {"dirt-1","dirt-2","dirt-3","dirt-4","dirt-5","dirt-6","dirt-7","grass-1","grass-2","grass-3","grass-4","dry-dirt","sand-1","sand-2","sand-3"}
    local function allow_soil_item(item_name)
        local item = data.raw.item and data.raw.item[item_name]
        if not (item and item.place_as_tile and item.place_as_tile.tile_condition) then return end
        local seen = {}
        for _, t in pairs(item.place_as_tile.tile_condition) do seen[t] = true end
        for _, t in pairs(base_tiles) do
            if data.raw.tile[t] and not seen[t] then
                table.insert(item.place_as_tile.tile_condition, t)
                seen[t] = true
            end
        end
    end
    allow_soil_item("overgrowth-yumako-soil")
    allow_soil_item("overgrowth-jellynut-soil")
end)



-- The Cave: Auto Inventory Repair sound.
-- Adapted from Inventory Repair by calcwizard (MIT).
local the_cave_default_repair_sound_variations = {
    {
        filename = "__core__/sound/manual-repair-advanced-1.ogg",
        volume = 1,
    },
    {
        filename = "__core__/sound/manual-repair-advanced-2.ogg",
        volume = 1,
    },
}

if not (data.raw.sound and data.raw.sound["the-cave-inventory-repair"]) then
    data:extend({
        {
            name = "the-cave-inventory-repair",
            type = "sound",
            category = "game-effect",
            aggregation = {
                max_count = 1,
                count_already_playing = true,
                remove = true,
            },
            variations = data.raw["utility-sounds"]
                and data.raw["utility-sounds"]["default"]
                and data.raw["utility-sounds"]["default"]["default_manual_repair"]
                and data.raw["utility-sounds"]["default"]["default_manual_repair"].variations
                or the_cave_default_repair_sound_variations
        }
    })
end


-- The Cave 2.5.29: allow vanilla lamps to upgrade directly into the integrated Lamp Post.
local lamp_post_setting = settings.startup["the-cave-lamp-post"]
local lamp_post_enabled = not lamp_post_setting or lamp_post_setting.value == "enabled"
if lamp_post_enabled and data.raw.lamp["small-lamp"] and data.raw.lamp["lamp-post"] then
  data.raw.lamp["small-lamp"].next_upgrade = "lamp-post"
end


-- The Cave 2.5.31: integrated Electric Furnaces upgrade chain.
require("prototypes.electric_furnaces_updates")

local chemical_rocket_setting = settings.startup["the-cave-chemical-rockets"]
if not chemical_rocket_setting or chemical_rocket_setting.value == "enabled" then
  require("prototypes.chemical_rockets_updates")
end
