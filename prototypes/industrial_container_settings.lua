-- Startup capacities for The Cave's independent industrial container families.
-- These settings never modify vanilla or third-party chest prototypes.
data:extend({
  {
    type = "int-setting",
    setting_type = "startup",
    name = "the-cave-industrial-container-1x1-capacity",
    default_value = 200,
    minimum_value = 100,
    maximum_value = 200,
    order = "z-industrial-containers-a"
  },
  {
    type = "int-setting",
    setting_type = "startup",
    name = "the-cave-industrial-container-2x2-capacity",
    default_value = 800,
    minimum_value = 400,
    maximum_value = 800,
    order = "z-industrial-containers-b"
  },
  {
    type = "int-setting",
    setting_type = "startup",
    name = "the-cave-industrial-container-4x4-capacity",
    default_value = 1600,
    minimum_value = 900,
    maximum_value = 1600,
    order = "z-industrial-containers-c"
  },
  {
    type = "int-setting",
    setting_type = "startup",
    name = "the-cave-industrial-container-6x6-capacity",
    default_value = 3000,
    minimum_value = 1800,
    maximum_value = 3000,
    order = "z-industrial-containers-d"
  }
})
