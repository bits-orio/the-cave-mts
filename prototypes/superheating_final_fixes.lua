-- The Cave: integrated Superheating liquid-fuel values.
local function setting_enabled(name, fallback)
  local setting = settings and settings.startup and settings.startup[name]
  if not setting then return fallback ~= false end
  return setting.value == "enabled" or setting.value == true
end

if not setting_enabled("the-cave-superheating", true) then return end
if not setting_enabled("the-cave-superheating-liquid-fuel", true) then return end

local override_values = setting_enabled("the-cave-superheating-override-liquid-values", false)
local fuels = require("prototypes.superheating_fuels")

for _, fuel in ipairs(fuels) do
  local fluid = data.raw.fluid and data.raw.fluid[fuel.name]
  if fluid and (override_values or not fluid.fuel_value) then
    local setting = settings.startup["the-cave-superheating-" .. fuel.name .. "-value"]
    local value = setting and setting.value or fuel.default_value
    fluid.fuel_value = tostring(value) .. "kJ"
    fluid.emissions_multiplier = fuel.emissions_multiplier
  end
end
