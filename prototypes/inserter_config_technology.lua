-- The Cave: four-stage research progression for Inserter Configuration.

local function has_technology(name)
  return data.raw.technology and data.raw.technology[name] ~= nil
end

local function add_existing(list, name)
  if name and has_technology(name) then
    list[#list + 1] = name
  end
end

local function science_ingredients(names)
  local result = {}
  for _, name in ipairs(names) do
    result[#result + 1] = { name, 1 }
  end
  return result
end

local technology_icons = {
  {
    icon = "__the-cave__/graphics/technology/inserter-configuration.png",
    icon_size = 256,
  },
}

local PREFIX = "the-cave-inserter-configuration-"

local definitions = {
  {
    count = 150,
    packs = { "automation-science-pack", "logistic-science-pack" },
    gates = { "logistic-science-pack" },
  },
  {
    count = 250,
    packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" },
    gates = { "chemical-science-pack" },
  },
  {
    count = 400,
    packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" },
    gates = { "production-science-pack" },
  },
  {
    count = 600,
    packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" },
    gates = { "utility-science-pack" },
  },
}

local technologies = {}
for level, definition in ipairs(definitions) do
  local prerequisites = {}
  if level > 1 then
    prerequisites[#prerequisites + 1] = PREFIX .. tostring(level - 1)
  end
  for _, gate in ipairs(definition.gates or {}) do
    add_existing(prerequisites, gate)
  end

  technologies[#technologies + 1] = {
    type = "technology",
    name = PREFIX .. tostring(level),
    localised_name = { "technology-name.the-cave-inserter-configuration", tostring(level) },
    localised_description = { "technology-description.the-cave-inserter-configuration-" .. tostring(level) },
    icons = table.deepcopy(technology_icons),
    effects = {
      {
        type = "nothing",
        effect_description = { "technology-effect.the-cave-inserter-configuration-" .. tostring(level) },
      },
    },
    prerequisites = prerequisites,
    unit = {
      count = definition.count,
      ingredients = science_ingredients(definition.packs),
      time = 30,
    },
    order = "the-cave-inserter-configuration-" .. string.format("%02d", level),
  }
end

data:extend(technologies)
