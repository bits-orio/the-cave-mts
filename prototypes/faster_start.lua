-- Integrated FasterStart 2.0.3 prototypes.
-- Original mod by magu5026. Names are retained for save/blueprint compatibility.
local util = require("util")

local setting = settings.startup["the-cave-faster-start"]
if setting and setting.value == "disabled" then return end

if not data.raw["equipment-category"]["simple-armor"] then
  data:extend({{
    type = "equipment-category",
    name = "simple-armor"
  }})
end

if not data.raw["equipment-grid"]["simple-equipment-grid"] then
  data:extend({{
    type = "equipment-grid",
    name = "simple-equipment-grid",
    width = 6,
    height = 6,
    equipment_categories = {"simple-armor"}
  }})
end

local prototypes = {}

if not data.raw.armor["simple-modular-armor"] then
  local armor = util.table.deepcopy(data.raw.armor["modular-armor"])
  armor.name = "simple-modular-armor"
  armor.icon = "__the-cave__/graphics/faster_start/icons/simple-power-armor.png"
  armor.resistances = nil
  armor.order = "c[faster-start]"
  armor.equipment_grid = "simple-equipment-grid"
  armor.hidden_in_factoriopedia = true
  prototypes[#prototypes + 1] = armor
end

if not data.raw["generator-equipment"]["simple-fission-reactor-equipment"] then
  local reactor = util.table.deepcopy(data.raw["generator-equipment"]["fission-reactor-equipment"])
  reactor.name = "simple-fission-reactor-equipment"
  reactor.power = "250kW"
  reactor.categories = {"simple-armor"}
  prototypes[#prototypes + 1] = reactor
end

if not data.raw.item["simple-fission-reactor-equipment"] then
  local item = util.table.deepcopy(data.raw.item["fission-reactor-equipment"])
  item.name = "simple-fission-reactor-equipment"
  item.place_as_equipment_result = "simple-fission-reactor-equipment"
  item.order = "a[energy-source]-b[faster-start]"
  item.hidden_in_factoriopedia = true
  prototypes[#prototypes + 1] = item
end

if not data.raw["movement-bonus-equipment"]["simple-exoskeleton-equipment"] then
  local exo = util.table.deepcopy(data.raw["movement-bonus-equipment"]["exoskeleton-equipment"])
  exo.name = "simple-exoskeleton-equipment"
  exo.shape.height = 6
  exo.energy_consumption = "100kW"
  exo.movement_bonus = 0.30
  exo.categories = {"simple-armor"}
  prototypes[#prototypes + 1] = exo
end

if not data.raw.item["simple-exoskeleton-equipment"] then
  local item = util.table.deepcopy(data.raw.item["exoskeleton-equipment"])
  item.name = "simple-exoskeleton-equipment"
  item.place_as_equipment_result = "simple-exoskeleton-equipment"
  item.order = "d[exoskeleton]-a[faster-start]"
  item.hidden_in_factoriopedia = true
  prototypes[#prototypes + 1] = item
end

if not data.raw["construction-robot"]["fission-construction-robot"] then
  local robot = util.table.deepcopy(data.raw["construction-robot"]["construction-robot"])
  robot.name = "fission-construction-robot"
  robot.icon = "__the-cave__/graphics/faster_start/icons/fission-construction-robot.png"
  robot.minable.result = "fission-construction-robot"
  robot.healing_per_tick = 10
  robot.max_health = 1000
  robot.energy_per_tick = "0kJ"
  robot.energy_per_move = "0kJ"
  robot.idle.filename = "__the-cave__/graphics/faster_start/entity/fission-construction-robot.png"
  robot.in_motion.filename = "__the-cave__/graphics/faster_start/entity/fission-construction-robot.png"
  robot.working.filename = "__the-cave__/graphics/faster_start/entity/fission-construction-robot-working.png"
  robot.hide_resistances = true
  prototypes[#prototypes + 1] = robot
end

if not data.raw.item["fission-construction-robot"] then
  prototypes[#prototypes + 1] = {
    type = "item",
    name = "fission-construction-robot",
    icon = "__the-cave__/graphics/faster_start/icons/fission-construction-robot.png",
    icon_size = 64,
    icon_mipmaps = 4,
    subgroup = "logistic-network",
    order = "a[robot]-b[construction-robot]-a[fission-construction-robot]",
    place_result = "fission-construction-robot",
    stack_size = 50,
    hidden_in_factoriopedia = true
  }
end

if #prototypes > 0 then data:extend(prototypes) end
