-- The Cave: integrated Electric Furnaces startup settings.
-- Uses explicit Enable/Disable dropdowns instead of startup checkboxes.
data:extend({
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-electric-furnaces-stone-steel",
    default_value = "enabled",
    allowed_values = {"enabled", "disabled"},
    order = "a-b-3-6-a"
  },
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-electric-furnaces-advanced",
    default_value = "enabled",
    allowed_values = {"enabled", "disabled"},
    order = "a-b-3-6-b"
  },
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-electric-furnaces-boiler",
    default_value = "enabled",
    allowed_values = {"enabled", "disabled"},
    order = "a-b-3-6-c"
  },
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-electric-furnaces-distinct-icons",
    default_value = "disabled",
    allowed_values = {"enabled", "disabled"},
    order = "a-b-3-6-d"
  }
})
