-- The Cave: integrated Superheating Startup settings.
-- Uses explicit Enable/Disable dropdowns per The Cave's Startup-setting rule.
local fuels = require("prototypes.superheating_fuels")

local function toggle(name, default_value, order)
  return {
    type = "string-setting",
    setting_type = "startup",
    name = name,
    default_value = default_value,
    allowed_values = {"enabled", "disabled"},
    order = order
  }
end

local prototypes = {
  toggle("the-cave-superheating", "enabled", "zz-superheating-a"),
  toggle("the-cave-superheating-superheaters", "enabled", "zz-superheating-b"),
  toggle("the-cave-superheating-single-stage", "disabled", "zz-superheating-c"),
  toggle("the-cave-superheating-liquid-fuel", "enabled", "zz-superheating-d"),
  toggle("the-cave-superheating-override-liquid-values", "disabled", "zz-superheating-e")
}

for _, fuel in ipairs(fuels) do
  prototypes[#prototypes + 1] = {
    type = "int-setting",
    setting_type = "startup",
    name = "the-cave-superheating-" .. fuel.name .. "-value",
    localised_name = {"mod-setting-name.the-cave-superheating-fuel-value", {"fluid-name." .. fuel.name}},
    localised_description = {"mod-setting-description.the-cave-superheating-fuel-value", {"fluid-name." .. fuel.name}},
    default_value = fuel.default_value,
    minimum_value = 1,
    order = "zz-superheating-f-" .. fuel.order
  }
end

data:extend(prototypes)
