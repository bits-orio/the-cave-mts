local shared = {}

shared.ICON_PATH = "__the-cave__/graphics/icons/extra-storage-tanks/"
shared.TECHNOLOGY_ICON_PATH = "__the-cave__/graphics/technology/extra-storage-tanks/"
shared.GRAPHICS_PATH = "__the-cave__/graphics/entity/extra-storage-tanks/"
shared.STORAGE_TANK_NAME = {
  ["1x1"] = "the-cave-storage-tank-1x1",
  ["2x2"] = "the-cave-storage-tank-2x2",
  ["3x4"] = "the-cave-storage-tank-3x4",
  ["5x5"] = "the-cave-storage-tank-5x5"
}
shared.SPACE_AGE_PRESENT = mods["space-age"] ~= nil

return shared
