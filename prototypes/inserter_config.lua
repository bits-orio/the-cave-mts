-- The Cave: standalone Inserter Configuration prototypes.
-- Runtime behaviour is implemented independently in scripts/inserter_config.lua.

data:extend({
  -- Legacy sprite names are retained for one migration cycle so a persisted
  -- 2.5.11 relative GUI can load safely before on_configuration_changed removes it.
  {
    type = "sprite",
    name = "pickup",
    filename = "__the-cave__/graphics/icons/inserter_config/pickup.png",
    flags = { "gui-icon" },
    width = 40,
    height = 40,
    scale = 0.5,
    priority = "extra-high-no-scale",
  },
  {
    type = "sprite",
    name = "drop",
    filename = "__the-cave__/graphics/icons/inserter_config/drop.png",
    flags = { "gui-icon" },
    width = 40,
    height = 40,
    scale = 0.5,
    priority = "extra-high-no-scale",
  },
  {
    type = "sprite",
    name = "the-cave-inserter-config-pickup",
    filename = "__the-cave__/graphics/icons/inserter_config/pickup.png",
    flags = { "gui-icon" },
    width = 40,
    height = 40,
    scale = 0.5,
    priority = "extra-high-no-scale",
  },
  {
    type = "sprite",
    name = "the-cave-inserter-config-drop",
    filename = "__the-cave__/graphics/icons/inserter_config/drop.png",
    flags = { "gui-icon" },
    width = 40,
    height = 40,
    scale = 0.5,
    priority = "extra-high-no-scale",
  },
})

data:extend({
  {
    type = "custom-input",
    name = "inserter-config-drop-rotate",
    key_sequence = "",
    consuming = "none",
    order = "0",
  },
  {
    type = "custom-input",
    name = "inserter-config-drop-rotate-reverse",
    key_sequence = "",
    consuming = "none",
    order = "1",
  },
  {
    type = "custom-input",
    name = "inserter-config-pickup-rotate",
    key_sequence = "CONTROL + R",
    consuming = "none",
    order = "2",
  },
  {
    type = "custom-input",
    name = "inserter-config-pickup-rotate-reverse",
    key_sequence = "CONTROL + SHIFT + R",
    consuming = "none",
    order = "3",
  },
  {
    type = "custom-input",
    name = "inserter-config-drop-distance-adjust",
    key_sequence = "F",
    consuming = "none",
    order = "4",
  },
  {
    type = "custom-input",
    name = "inserter-config-pickup-distance-adjust",
    key_sequence = "CONTROL + F",
    consuming = "none",
    order = "5",
  },
  {
    type = "custom-input",
    name = "inserter-config-drop-offset-adjust-lateral",
    key_sequence = "",
    consuming = "none",
    order = "6",
  },
  {
    type = "custom-input",
    name = "inserter-config-drop-offset-adjust-distance",
    key_sequence = "",
    consuming = "none",
    order = "7",
  },
})
