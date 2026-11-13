local config = require("shared.solar_display")
local solar_display = {}

local function daylight(surface)
  if surface.always_day then return 1 end
  local time = surface.daytime
  -- on_tick runs after native electricity. Prepare the coefficient for the
  -- next simulation tick, avoiding a one-tick delay at sunrise/sunset.
  if not surface.freeze_daytime then time = (time + 1 / surface.ticks_per_day) % 1 end
  local dusk, evening = surface.dusk, surface.evening
  local morning, dawn = surface.morning, surface.dawn
  if time < dusk or time >= dawn then return 1 end
  if time < evening then return (evening - time) / (evening - dusk) end
  if time < morning then return 0 end
  return (time - morning) / (dawn - morning)
end

local function space_multiplier(surface)
  local platform = surface.platform
  if not platform then return 1 end
  local location = platform.space_location
  if location then return location.solar_power_in_space / 100 end
  local connection = platform.space_connection
  if connection then
    local distance = platform.distance or 0
    return (connection.from.solar_power_in_space * (1 - distance)
      + connection.to.solar_power_in_space * distance) / 100
  end
  return 1
end

function solar_display.sync(surface)
  if not (surface and surface.valid) then return end
  local light = math.max(0, math.min(1, daylight(surface)))
  local performance = light + config.night_performance * (1 - light)
  local coefficient = surface.get_property("solar-power")
    * surface.solar_power_multiplier * space_multiplier(surface)
    * light / performance
  -- Avoid displaying a spurious +/-0% from floating-point round-off.
  local integer = math.floor(coefficient + 0.5)
  if math.abs(coefficient - integer) < 0.000001 then coefficient = integer end
  if math.abs(surface.get_property(config.property) - coefficient) > 0.00000001 then
    surface.set_property(config.property, coefficient)
  end
end

function solar_display.on_tick()
  -- One calculation per surface, never per panel. Updating with the native
  -- day/night cycle also preserves mixed CAVETORIO maps and moving platforms.
  -- The original solar multiplier, lighting, and external interiors are not
  -- written here; third-party panels continue using their native properties.
  for _, surface in pairs(game.surfaces) do solar_display.sync(surface) end
end

return solar_display
