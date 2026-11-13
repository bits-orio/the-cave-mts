-- Keep The Cave's approved artwork visible instead of Factorio's rotating
-- base-game or Space Age menu simulations.
local utility_constants = data.raw["utility-constants"]
  and data.raw["utility-constants"]["default"]

if utility_constants then
  utility_constants.main_menu_simulations = nil
  utility_constants.main_menu_background_image_location =
    "__the-cave__/graphics/gui/the-cave-main-menu-background.png"
  utility_constants.main_menu_background_vignette_intensity = 0
  utility_constants.main_menu_background_vignette_sharpness = 0
end

-- A zero weight keeps an ambient-sound prototype available to the engine but
-- removes it from random menu-track selection. Runtime/gameplay music is not
-- touched because it uses a different track type.
if data.raw["ambient-sound"] then
  for _, track in pairs(data.raw["ambient-sound"]) do
    if track.track_type == "menu-track" then
      track.weight = 0
    end
  end
end

data:extend({
  {
    type = "ambient-sound",
    name = "the-cave-main-menu-stone-mining",
    track_type = "menu-track",
    weight = 1,
    sound = {
      filename = "__the-cave__/sounds/the-cave-main-menu-stone-mining.ogg",
      volume = 1.0,
    },
  },
})
