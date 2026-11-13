-- Server-wide, startup-only master switch. Fixed colours keep the feature
-- entirely in Factorio's native prototype renderer with no runtime polling.
data:extend({
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-production-status-indicators",
    default_value = "enabled",
    allowed_values = {"enabled", "disabled"},
    order = "z-production-status"
  }
})
