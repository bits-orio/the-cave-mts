local shared = require("prototypes.extra_storage_tanks.shared")
local names = shared.STORAGE_TANK_NAME

local function technology(name, icon_name, count, ingredients, time, prerequisites, order)
  return {
    type = "technology",
    name = name,
    icon = shared.TECHNOLOGY_ICON_PATH .. icon_name .. ".png",
    icon_size = 256,
    effects = {{type = "unlock-recipe", recipe = icon_name}},
    prerequisites = prerequisites,
    unit = {count = count, ingredients = ingredients, time = time},
    order = order
  }
end

local tech_1x1 = "the-cave-storage-tank-1x1-technology"
local tech_2x2 = "the-cave-storage-tank-2x2-technology"
local tech_3x4 = "the-cave-storage-tank-3x4-technology"
local tech_5x5 = "the-cave-storage-tank-5x5-technology"

local techs = {
  technology(
    tech_1x1, names["1x1"], 20,
    {{"automation-science-pack", 1}},
    10, {}, "d-a-a[storage-tank-1x1]"
  ),
  technology(
    tech_2x2, names["2x2"], 40,
    {{"automation-science-pack",1},{"logistic-science-pack",1}},
    15, {tech_1x1, "logistic-science-pack"}, "d-a-b[storage-tank-2x2]"
  ),
  technology(
    tech_3x4, names["3x4"], 150,
    {{"automation-science-pack",1},{"logistic-science-pack",1},{"chemical-science-pack",1}},
    30, {"fluid-handling", "chemical-science-pack"}, "d-a-d[storage-tank-3x4]"
  ),
  technology(
    tech_5x5, names["5x5"], 300,
    {
      {"automation-science-pack",1},
      {"logistic-science-pack",1},
      {"chemical-science-pack",1},
      {"production-science-pack",1},
      {"utility-science-pack",1}
    },
    30, {tech_3x4, "production-science-pack", "utility-science-pack"}, "d-a-e[storage-tank-5x5]"
  )
}

data:extend(techs)

local function add_unique(list, value)
  list = list or {}
  for _, existing in pairs(list) do
    if existing == value then return list end
  end
  list[#list + 1] = value
  return list
end

-- The vanilla 3x3 storage tank remains the progression gate for oil.
-- The small 1x1 and 2x2 tanks unlock only their own recipes.
local fluid_handling = data.raw.technology and data.raw.technology["fluid-handling"]
if fluid_handling then
  fluid_handling.prerequisites = add_unique(fluid_handling.prerequisites, tech_2x2)
  fluid_handling.order = "d-a-c[storage-tank-3x3]"
end

local vanilla_tank_item = data.raw.item and data.raw.item["storage-tank"]
if vanilla_tank_item then
  vanilla_tank_item.order = "b[fluid]-c[storage-tank-3x3]"
end
