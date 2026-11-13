local config = require("shared.solar_display")
data:extend({{
  type = "surface-property",
  name = config.property,
  default_value = 100,
  localised_name = {"surface-property-name.solar-power"},
  localised_unit_key = "surface-property-unit.percentage",
  hidden = true,
}})

-- Only change our six panels with the ordinary native day/night curve.
-- Other mods' generators and custom solar curves remain their owners'.
local names = {"solar-panel"}
for tier = 1, 5 do names[#names + 1] = "the-cave-solar-panel-mk" .. tier end
for _, name in ipairs(names) do
  local panel = data.raw["solar-panel"][name]
  if panel
    and (panel.performance_at_day == nil or panel.performance_at_day == 1)
    and (panel.performance_at_night == nil or panel.performance_at_night == 0)
    and (panel.solar_coefficient_property == nil or panel.solar_coefficient_property == "solar-power") then
    panel.performance_at_night = config.night_performance
    panel.solar_coefficient_property = config.property
  end
end
