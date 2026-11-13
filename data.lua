require("prototypes.the_cave_feature_flags")

-- Main information-menu icon. The existing mod thumbnail is reused so the GUI
-- does not introduce or duplicate a separate artwork asset.
data:extend({
  {
    type = "sprite",
    name = "the-cave-gui-icon",
    filename = "__the-cave__/thumbnail.png",
    flags = { "gui-icon" },
    size = 1254,
    priority = "extra-high-no-scale"
  },
  {
    type = "sprite",
    name = "the-cave-locomotive-garden-portal",
    filename = "__the-cave__/graphics/train_interiors/locomotive-garden-portal.png",
    width = 256,
    height = 256,
    -- 256 pixels at 0.25 scale renders as exactly 64 pixels, or 2x2 tiles.
    scale = 0.25,
    priority = "extra-high"
  },
  {
    type = "sprite",
    name = "the-cave-shelter-garden-portal",
    filename = "__the-cave__/graphics/train_interiors/locomotive-garden-portal.png",
    width = 256,
    height = 256,
    -- The shared Cave portal artwork still renders as an exact 2x2 opening;
    -- only the prototype identity is Shelter-specific.
    scale = 0.25,
    priority = "extra-high"
  }
})

require("prototypes.drill_filter")
require("prototypes.resource_eraser")
require("prototypes.cave_belt_stacking")
require("prototypes.portable_power_interface")
require("prototypes.wind_turbine")
require("prototypes.cave_accumulators")
require("prototypes.big_wooden_pole")
require("prototypes.metal_electric_poles")
require("prototypes.train_hidden_radar")
require("prototypes.train_power_bridge")
require("prototypes.train_fluid_transfer_tank")
require("prototypes.shelter_core")
require("prototypes.train_garden_transfer")
require("prototypes.train_wave_defense")
require("prototypes.mk_market_items")
require("prototypes.coin_maker")
require("prototypes.equipment_grid_upgrades")
require("prototypes.rock")
do
  local function startup_enabled(name, default_enabled)
    local setting = settings.startup[name]
    if not setting then return default_enabled ~= false end
    return setting.value == "enabled" or setting.value == true
  end

  local tnt_enabled = startup_enabled("the-cave-tnt-boxes", true)
  if tnt_enabled then
    require("prototypes.tnt_boxes")
  end
end
require("prototypes.uranium_caves")
require("prototypes.mineral_caves")
require("prototypes.lost_city_houses")
require("prototypes.lost_city")
require("prototypes.lost_city_transfer")
require("prototypes.scrap_salvage")
require("prototypes.fortified_vaults")
require("prototypes.industrial_containers")
require("prototypes.industrial_loaders")
local extra_storage_tanks_setting = settings.startup["the-cave-extra-storage-tanks"]
local extra_storage_tanks_enabled = not extra_storage_tanks_setting or extra_storage_tanks_setting.value == "enabled"
if extra_storage_tanks_enabled then
  require("prototypes.extra_storage_tanks.init")
end
require("prototypes.armoured_biters.data")
require("prototypes.arachnids.init")
require("prototypes.advancing_assault")
require("prototypes.tree")
require("prototypes.map_gen")
require("prototypes.technology")
require("prototypes.roof_support")
require("prototypes.teleporter")
require("prototypes.character_reach_technology")
require("prototypes.turret_range_technology")
require("prototypes.underground_belt_reach_technology")
require("prototypes.underground_pipe_reach_technology")
require("prototypes.electric_furnaces")
require("prototypes.faster_start")
require("prototypes.superheating")
local lamp_post_setting = settings.startup["the-cave-lamp-post"]
local lamp_post_enabled = not lamp_post_setting or lamp_post_setting.value == "enabled"
if lamp_post_enabled then
  require("prototypes.lamp_post")
  require("prototypes.lamp_pole")
end
local chemical_rocket_setting = settings.startup["the-cave-chemical-rockets"]
local chemical_rockets_enabled = not chemical_rocket_setting or chemical_rocket_setting.value == "enabled"
if chemical_rockets_enabled then
  require("prototypes.chemical_rockets")
end
local inserter_config_setting = settings.startup["the-cave-inserter-configurable"]
local inserter_config_enabled = not inserter_config_setting or inserter_config_setting.value == "enabled"
if inserter_config_enabled then
  require("prototypes.inserter_config")
  require("prototypes.inserter_config_technology")
end

-- Ctrl+R is shared safely by Inserter Configuration and Gun Turret area reload.
-- When Inserter Configuration is disabled its existing input prototype is not
-- loaded, so define the same stable input name here as a fallback.
if not (
  data.raw["custom-input"]
  and data.raw["custom-input"]["inserter-config-pickup-rotate"]
) then
  data:extend({
    {
      type = "custom-input",
      name = "inserter-config-pickup-rotate",
      key_sequence = "CONTROL + R",
      consuming = "none",
      order = "the-cave-gun-turret-area-reload"
    }
  })
end

local train_interior_setting = settings.startup["the-cave-train-interiors"]
local shelter_defense_setting = settings.startup["the-cave-shelter-defense"]
local train_requested = train_interior_setting
  and (train_interior_setting.value == "enabled" or train_interior_setting.value == true)
local shelter_requested = shelter_defense_setting
  and (shelter_defense_setting.value == "enabled" or shelter_defense_setting.value == true)
local shelter_mode = shelter_requested and not train_requested
local train_mode = train_requested and not shelter_requested
local interior_shortcut_name = shelter_mode
  and {"shortcut-name.the-cave-enter-shelter-interior-shortcut"}
  or {"shortcut-name.the-cave-enter-train-interior-shortcut"}
local interior_shortcut_description = shelter_mode
  and {"shortcut-description.the-cave-enter-shelter-interior-shortcut"}
  or {"shortcut-description.the-cave-enter-train-interior-shortcut"}
local interior_shortcut_icon = shelter_mode
  and "__the-cave__/graphics/shelter/shelter.png"
  or "__base__/graphics/icons/locomotive.png"

-- The Cave: shared utility inputs and shortcut-bar buttons. The Gun Turret
-- shortcut directly runs area reload even when Ctrl+R is currently pointing
-- at an Inserter. Only the interior shortcut depends on the selected scenario.
local cave_inputs = {
  {
    type = "custom-input",
    name = "the-cave-clean-corpses",
    key_sequence = "BACKSPACE",
    consuming = "game-only",
    order = "the-cave-clean-corpses"
  },
  {
    type = "custom-input",
    name = "the-cave-enter-train-interior",
    key_sequence = "CONTROL + RETURN",
    consuming = "game-only",
    order = "the-cave-enter-train-interior"
  },
  {
    type = "shortcut",
    name = "the-cave-reload-gun-turrets-shortcut",
    action = "lua",
    associated_control_input = "inserter-config-pickup-rotate",
    order = "z[the-cave]-r[reload-gun-turrets]",
    localised_name = {"shortcut-name.the-cave-reload-gun-turrets-shortcut"},
    localised_description = {"shortcut-description.the-cave-reload-gun-turrets-shortcut"},
    icon = "__base__/graphics/icons/gun-turret.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/gun-turret.png",
    small_icon_size = 64
  },
  {
    type = "shortcut",
    name = "the-cave-clean-corpses-shortcut",
    action = "lua",
    associated_control_input = "the-cave-clean-corpses",
    order = "z[the-cave]-c[clean-corpses]",
    localised_name = {"shortcut-name.the-cave-clean-corpses-shortcut"},
    localised_description = {"shortcut-description.the-cave-clean-corpses-shortcut"},
    icon = "__base__/graphics/icons/behemoth-biter.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/behemoth-biter.png",
    small_icon_size = 64
  }
}
if train_mode or shelter_mode then
  cave_inputs[#cave_inputs + 1] = {
    type = "shortcut",
    name = "the-cave-enter-train-interior-shortcut",
    action = "lua",
    associated_control_input = "the-cave-enter-train-interior",
    order = "z[the-cave]-t[train-interior]",
    localised_name = interior_shortcut_name,
    localised_description = interior_shortcut_description,
    icon = interior_shortcut_icon,
    icon_size = 64,
    small_icon = interior_shortcut_icon,
    small_icon_size = 64
  }
end
data:extend(cave_inputs)



-- The Cave integrated Damage Indicator font prototype (Dummiez, GPLv3)
-- data.lua
-- Dummiez 2026/05/01

-- Font prototype is created at data stage; player-facing font settings are runtime-per-user.
-- Keep the built-in custom font stable here so startup settings are not required.
local font_family = "default-bold"
local font_size = 16

data:extend({
  {
    type = "font",
    name = "damage-indicator-font",
    from = font_family,
    size = font_size,
    border = true,
    border_color = {0, 0, 0, 1}
  }
})
