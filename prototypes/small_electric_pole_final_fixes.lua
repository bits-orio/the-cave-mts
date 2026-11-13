-- The Cave 2.5.37: improve the vanilla Small Electric Pole without creating
-- a replacement prototype. Keeping the original prototype name preserves
-- existing entities, ghosts, blueprints, upgrade planners and save files.
local poles = data.raw["electric-pole"]
local pole = poles and poles["small-electric-pole"]

if pole then
  pole.maximum_wire_distance = 9
  pole.supply_area_distance = 3.5 -- 7 x 7 supply area
end

-- Keep every one-tile player pole in the same native fast-replace family.
-- In particular, The Cave's Big Wooden Pole used to have no group at all, so
-- placing a Medium Electric Pole over it was rejected and players had to mine
-- it first (which also removed its red/green circuit wires).
if poles then
  local medium = poles["medium-electric-pole"]
  local fast_group = (medium and medium.fast_replaceable_group)
    or (pole and pole.fast_replaceable_group)
    or "electric-pole"

  local one_tile_poles = {
    "small-electric-pole",
    "the-cave-small-metal-electric-pole",
    "medium-electric-pole",
    "the-cave-big-wooden-pole",
  }
  for level = 1, 5 do
    one_tile_poles[#one_tile_poles + 1] = "the-cave-medium-electric-pole-mk" .. level
  end

  for _, name in pairs(one_tile_poles) do
    local candidate = poles[name]
    if candidate then
      candidate.fast_replaceable_group = fast_group
    end
  end

  -- Preserve Factorio's normal Upgrade Planner direction without forcing the
  -- long-reach Big Wooden Pole or market-only MK poles into an upgrade chain.
  if pole and medium then
    pole.next_upgrade = "medium-electric-pole"
  end

  -- Match The Cave's existing small-pole balance without replacing the
  -- original pole or changing its upgrade direction.
  local metal = poles["the-cave-small-metal-electric-pole"]
  if metal and pole then
    metal.maximum_wire_distance = pole.maximum_wire_distance
    metal.supply_area_distance = pole.supply_area_distance
    metal.next_upgrade = pole.next_upgrade
  end
end
