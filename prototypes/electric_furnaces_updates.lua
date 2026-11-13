-- The Cave: Electric Furnaces upgrade planner chain.
local setting = settings.startup["the-cave-electric-furnaces-advanced"]
if setting and setting.value == "enabled" then
  local base_furnace = data.raw.furnace and data.raw.furnace["electric-furnace"]
  local tier2 = data.raw.furnace and data.raw.furnace["electric-furnace-2"]
  if base_furnace and tier2 then
    base_furnace.next_upgrade = "electric-furnace-2"
  end
end
