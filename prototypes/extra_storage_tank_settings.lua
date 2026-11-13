-- The Cave: integrated Extra Storage Tanks startup toggle.
-- Capacities are intentionally fixed for consistent multiplayer balance.
data:extend({
  {
    type = "string-setting",
    name = "the-cave-extra-storage-tanks",
    setting_type = "startup",
    default_value = "enabled",
    allowed_values = { "enabled", "disabled" },
    order = "zz-extra-storage-tanks"
  }
})
