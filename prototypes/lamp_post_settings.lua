-- The Cave: integrated Lamp Post startup toggle.
-- Uses the project-wide explicit Enable/Disable dropdown rule.
data:extend({
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-lamp-post",
    default_value = "enabled",
    allowed_values = { "enabled", "disabled" },
    order = "a-b-3-5",
  }
})
