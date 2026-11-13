-- The Cave: integrated Inserter Configuration startup toggle.
-- Startup options use explicit Enable/Disable dropdowns instead of checkboxes.
data:extend({
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-inserter-configurable",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-3-1",
    }
})
