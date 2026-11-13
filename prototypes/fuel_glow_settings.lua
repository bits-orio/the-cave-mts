-- The Cave: integrated FuelGlow startup settings.
-- Every prototype name is The Cave-prefixed so the standalone FuelGlow mod can
-- be installed at the same time without duplicate setting prototypes.
data:extend({
  {
    type = "string-setting",
    name = "the-cave-fuel-glow",
    setting_type = "startup",
    default_value = "enabled",
    allowed_values = {"enabled", "disabled"},
    order = "zz-fuel-glow-a"
  },
  {
    type = "string-setting",
    name = "the-cave-fuel-glow-peak-fuel-value",
    setting_type = "startup",
    default_value = "1.21GJ",
    allow_blank = false,
    auto_trim = true,
    order = "zz-fuel-glow-b"
  },
  {
    type = "string-setting",
    name = "the-cave-fuel-glow-floor-fuel-value",
    setting_type = "startup",
    default_value = "2MJ",
    allow_blank = false,
    auto_trim = true,
    order = "zz-fuel-glow-c"
  },
  {
    type = "double-setting",
    name = "the-cave-fuel-glow-color-curve",
    setting_type = "startup",
    default_value = 2,
    minimum_value = 1,
    maximum_value = 10,
    order = "zz-fuel-glow-d"
  },
  {
    type = "string-setting",
    name = "the-cave-fuel-glow-lock-vanilla-fuels",
    setting_type = "startup",
    default_value = "enabled",
    allowed_values = {"enabled", "disabled"},
    order = "zz-fuel-glow-e"
  },
  {
    type = "string-setting",
    name = "the-cave-fuel-glow-electric-furnace-light",
    setting_type = "startup",
    default_value = "enabled",
    allowed_values = {"enabled", "disabled"},
    order = "zz-fuel-glow-f"
  }
})
