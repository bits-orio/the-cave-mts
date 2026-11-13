-- Hidden train-interior radar.
-- This is never craftable/placeable by players. It exists only so Factorio's
-- normal map view has live radar coverage on the hidden train-interior surface.
local base = data.raw["radar"] and data.raw["radar"]["radar"]
if base and not data.raw["radar"]["the-cave-train-hidden-radar"] then
  local radar = table.deepcopy(base)
  radar.name = "the-cave-train-hidden-radar"
  radar.localised_name = {"", "The Cave Train Interior Map View"}
  radar.localised_description = {"", "Hidden radar used by The Cave train interiors."}
  radar.hidden = true
  radar.selectable_in_game = false
  radar.collision_box = nil
  radar.selection_box = nil
  radar.collision_mask = { layers = {} }
  radar.flags = {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "not-flammable",
    "hide-alt-info"
  }

  -- Void energy source keeps it active without poles, fuel, or visible power setup.
  radar.energy_source = { type = "void" }
  radar.energy_usage = "1W"
  radar.energy_per_sector = "1J"
  radar.energy_per_nearby_scan = "1J"

  -- Nearby scan gives the live, zoomed-in map view. Sector scanning is kept tiny;
  -- regular script charting already handles the static explored chunks.
  radar.max_distance_of_sector_revealed = 1
  radar.max_distance_of_nearby_sector_revealed = 5

  local empty_sprite = {
    filename = "__core__/graphics/empty.png",
    priority = "low",
    width = 1,
    height = 1,
    direction_count = 1,
    frame_count = 1,
    line_length = 1,
    shift = {0, 0}
  }
  radar.pictures = { layers = { empty_sprite } }
  radar.integration_patch = nil
  radar.working_sound = nil
  radar.water_reflection = nil

  data:extend({ radar })
end
