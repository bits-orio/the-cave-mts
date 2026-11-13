-- Integrated FasterStart final compatibility pass.
local setting = settings.startup["the-cave-faster-start"]
if setting and setting.value == "disabled" then return end

local function contains(list, value)
  if not list then return false end
  for _, entry in pairs(list) do
    if entry == value then return true end
  end
  return false
end

local robot = data.raw["construction-robot"] and data.raw["construction-robot"]["fission-construction-robot"]
if robot then
  local resistances = {}
  for _, damage_type in pairs(data.raw["damage-type"] or {}) do
    resistances[#resistances + 1] = {type = damage_type.name, percent = 100}
  end
  robot.resistances = resistances
end

for prototype_type, prototype_name in pairs({
  ["roboport-equipment"] = "personal-roboport-equipment",
  ["battery-equipment"] = "battery-equipment"
}) do
  local prototype = data.raw[prototype_type] and data.raw[prototype_type][prototype_name]
  if prototype then
    prototype.categories = prototype.categories or {}
    if not contains(prototype.categories, "simple-armor") then
      table.insert(prototype.categories, "simple-armor")
    end
  end
end
