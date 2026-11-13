-- Reuse the approved 6x6 battery-window animation without changing any artwork.
-- Each stripe selects one window from one existing 384x384 frame. Positions
-- below are measured on the unchanged large body sprites (64 pixels per tile).
local windows = {
  [10] = {
    -- The rear pair is partly hidden by the centre column. Crop the effect at
    -- the same occlusion, rather than drawing light over the foreground metal.
    {center = {239, 116.5}, height = 15, crop = {x = 186, y = 97, width = 11, height = 15}},
    {center = {402, 117}, height = 12, crop = {x = 186, y = 97, width = 11, height = 12}},
    {center = {132.5, 154.5}, height = 37},
    {center = {507.5, 155}, height = 38},
    {center = {320.5, 219.5}, height = 57},
    {center = {129.5, 400}, height = 40},
    {center = {511, 400}, height = 38},
    {center = {212.5, 436}, height = 32},
    {center = {428.5, 436.5}, height = 33}
  },
  [20] = {
    -- Only the exposed lower windows under the rear fan decks are visible.
    {center = {248, 338.5}, height = 21, crop = {x = 185, y = 104, width = 13, height = 21}},
    {center = {1035.5, 338.5}, height = 21, crop = {x = 185, y = 104, width = 13, height = 21}},
    {center = {524.5, 494.5}, height = 99},
    {center = {758.5, 494.5}, height = 99},
    {center = {216.5, 748}, height = 46},
    {center = {320, 779}, height = 50},
    {center = {963, 778.5}, height = 49},
    {center = {1066, 747}, height = 48}
  }
}

return function(size, state)
  local layers = {}
  local filename = "__the-cave__/graphics/entity/cave-accumulators/6x6/" .. state .. ".png"
  for _, window in ipairs(windows[size]) do
    -- The source window's illuminated core is 30 pixels high. Include its
    -- original soft glow for exposed columns; clip hidden windows separately.
    local crop = window.crop or {x = 176, y = 87, width = 31, height = 50}
    local ratio = window.height / (window.crop and crop.height or 30)
    local stripes = {}
    for frame = 0, 31 do
      stripes[#stripes + 1] = {
        filename = filename, width_in_frames = 1, height_in_frames = 1,
        x = (frame % 8) * 384 + crop.x,
        y = math.floor(frame / 8) * 384 + crop.y
      }
    end
    layers[#layers + 1] = {
      stripes = stripes, width = crop.width, height = crop.height,
      frame_count = 32, animation_speed = 0.5,
      scale = 0.5 * ratio, priority = "high", draw_as_glow = true,
      shift = {(window.center[1] - size * 32) / 64,
               (window.center[2] - size * 32) / 64}
    }
  end
  return layers
end
