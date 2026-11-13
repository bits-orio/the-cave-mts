local util = require("util")

local MOD_TAG = "[The Cave/FuelGlow] "
local DEFAULT_PEAK_ENERGY = "1.21GJ"
local DEFAULT_FLOOR_ENERGY = "2MJ"

-- The standalone mod owns this feature when both packages are installed.
-- Its setting names and light marker are deliberately independent from The
-- Cave, and this guard prevents duplicate colour or light processing.
if mods and mods["FuelGlow"] then
  log(MOD_TAG .. "Standalone FuelGlow detected; skipping the integrated copy.")
  return
end

local function startup_value(name, fallback)
  local startup = settings and settings.startup
  local setting = startup and startup[name]
  if setting and setting.value ~= nil then return setting.value end
  return fallback
end

local function startup_enabled(name, fallback)
  local value = startup_value(name, fallback and "enabled" or "disabled")
  return value == "enabled" or value == true
end

if not startup_enabled("the-cave-fuel-glow", true) then return end

-- Every concrete prototype type that inherits from ItemPrototype in Factorio
-- 2.x. Scanning all of them supports unusual fuels created by other mods.
local item_prototype_types = {
  "item",
  "ammo",
  "capsule",
  "gun",
  "item-with-entity-data",
  "item-with-label",
  "item-with-inventory",
  "blueprint-book",
  "item-with-tags",
  "selection-tool",
  "blueprint",
  "copy-paste-tool",
  "deconstruction-item",
  "spidertron-remote",
  "upgrade-item",
  "module",
  "rail-planner",
  "space-platform-starter-pack",
  "tool",
  "armor",
  "repair-tool"
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function parse_energy(energy_string)
  if type(energy_string) ~= "string" or energy_string:sub(-1) ~= "J" then
    return nil
  end

  local success, energy = pcall(util.parse_energy, energy_string)
  if not success or type(energy) ~= "number" or energy <= 0 or energy == math.huge then
    return nil
  end

  return energy
end

local function read_energy_setting(setting_name, fallback)
  local configured_value = startup_value(setting_name, fallback)
  local parsed_value = parse_energy(configured_value)

  if parsed_value then return parsed_value end

  log(
    MOD_TAG
      .. "Invalid startup setting '"
      .. setting_name
      .. "' ("
      .. tostring(configured_value)
      .. "). Using "
      .. fallback
      .. "."
  )

  return assert(parse_energy(fallback))
end

local function each_item_prototype(callback)
  for _, prototype_type in ipairs(item_prototype_types) do
    local prototypes = data.raw[prototype_type]
    if prototypes then
      for _, prototype in pairs(prototypes) do callback(prototype) end
    end
  end
end

local function find_item_prototype(name)
  for _, prototype_type in ipairs(item_prototype_types) do
    local prototypes = data.raw[prototype_type]
    if prototypes and prototypes[name] then return prototypes[name] end
  end
end

local peak_energy = read_energy_setting(
  "the-cave-fuel-glow-peak-fuel-value",
  DEFAULT_PEAK_ENERGY
)
local floor_energy = read_energy_setting(
  "the-cave-fuel-glow-floor-fuel-value",
  DEFAULT_FLOOR_ENERGY
)

if floor_energy >= peak_energy then
  log(
    MOD_TAG
      .. "The floor fuel value must be lower than the peak fuel value. "
      .. "Using the defaults instead."
  )
  peak_energy = assert(parse_energy(DEFAULT_PEAK_ENERGY))
  floor_energy = assert(parse_energy(DEFAULT_FLOOR_ENERGY))
end

local color_curve = startup_value("the-cave-fuel-glow-color-curve", 2)
local color_exponent = 1 / color_curve
local color_scale = peak_energy ^ color_exponent
local floor_ratio = (floor_energy ^ color_exponent) / color_scale
local floor_tweak = 0.1 / floor_ratio

local function automatic_glow_color(fuel_value)
  local color_value = (fuel_value ^ color_exponent) / color_scale

  -- Keep low-energy fuels visibly warm while retaining FuelGlow's
  -- red -> orange -> pale -> blue progression.
  color_value =
    color_value
    + (((color_value * floor_tweak) - color_value) * (1 - color_value))
  color_value = clamp(color_value, 0, 1)

  local red = 1
  local green = color_value * 2.5
  local blue = color_value

  if green > 1 then
    local excess = (green - 1) / 2
    green = 1
    blue = blue + excess

    if blue > 1 then
      excess = (blue - 1) / 9
      blue = 1
      green = green - (excess * 4)
      red = red - (excess * 5)
    end
  end

  return {
    r = clamp(red, 0, 1),
    g = clamp(green, 0, 1),
    b = clamp(blue, 0, 1),
    a = 1
  }
end

if startup_enabled("the-cave-fuel-glow-lock-vanilla-fuels", true) then
  local vanilla_colors = {
    wood = {r = 1, g = 0.25, b = 0.1, a = 0.2},
    coal = {r = 1, g = 0.5, b = 0.2, a = 0.4},
    ["solid-fuel"] = {r = 1, g = 0.75, b = 0.3, a = 0.6},
    ["rocket-fuel"] = {r = 1, g = 1, b = 0.4, a = 0.8},
    ["uranium-fuel-cell"] = {r = 51 / 255, g = 245 / 255, b = 35 / 255, a = 1},
    ["nuclear-fuel"] = {r = 0.75, g = 1, b = 0.5, a = 1}
  }

  for item_name, glow_color in pairs(vanilla_colors) do
    local item = find_item_prototype(item_name)
    if item then item.fuel_glow_color = glow_color end
  end
end

each_item_prototype(function(item)
  if item.fuel_value and not item.fuel_glow_color then
    local fuel_value = parse_energy(item.fuel_value)
    if fuel_value then
      item.fuel_glow_color = automatic_glow_color(fuel_value)
    else
      log(
        MOD_TAG
          .. "Could not parse fuel value for "
          .. item.type
          .. " prototype '"
          .. item.name
          .. "'. Its glow colour was left unchanged."
      )
    end
  end
end)

if startup_enabled("the-cave-fuel-glow-electric-furnace-light", true) then
  local electric_furnace =
    data.raw.furnace
    and data.raw.furnace["electric-furnace"]

  if electric_furnace and electric_furnace.graphics_set then
    local graphics_set = electric_furnace.graphics_set
    graphics_set.working_visualisations =
      graphics_set.working_visualisations
      or {}

    local light_already_added = false
    for _, visualisation in pairs(graphics_set.working_visualisations) do
      if visualisation.name == "fuel-glow-electric-furnace-light" then
        light_already_added = true
        break
      end
    end

    if not light_already_added then
      table.insert(graphics_set.working_visualisations, {
        name = "fuel-glow-electric-furnace-light",
        light = {
          intensity = 0.4,
          size = 9,
          color = {r = 1, g = 0.625, b = 0.25}
        }
      })
    end
  else
    log(
      MOD_TAG
        .. "Electric furnace graphics were replaced by another mod; "
        .. "the optional furnace light was skipped safely."
    )
  end
end
