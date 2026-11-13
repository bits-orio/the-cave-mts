-- The Cave MK Market prototype series
-- Market-only upgrades. No recipes, no technologies, and no new graphics.
-- Each prototype is cloned from the closest vanilla prototype and only safe prototype values are changed.

local parse_energy = require("util").parse_energy

local function tc_copy(value)
  return value and table.deepcopy(value) or nil
end

local function literal(text)
  return {"", text}
end

local function set_names(proto, display_name, description)
  proto.localised_name = literal(display_name)
  proto.localised_description = literal(description)
end

local function set_item_common(item, name, display_name, description, place_result)
  item.name = name
  set_names(item, display_name, description)
  item.icons = tc_copy(item.icons)
  item.place_result = place_result
  item.place_as_tile = nil
  item.order = "z[the-cave-mk]-" .. name
  item.hidden = false
end

local function set_entity_common(entity, name, display_name, description)
  entity.name = name
  set_names(entity, display_name, description)
  entity.icons = tc_copy(entity.icons)
  entity.next_upgrade = nil
  entity.order = "z[the-cave-mk]-" .. name
  if entity.minable then
    entity.minable = tc_copy(entity.minable)
    entity.minable.result = name
    entity.minable.results = nil
  end
end

local function set_pollution(energy_source, pollution)
  if not energy_source then return end
  if type(energy_source.emissions_per_minute) == "table" then
    energy_source.emissions_per_minute = tc_copy(energy_source.emissions_per_minute)
    energy_source.emissions_per_minute.pollution = pollution
  else
    -- Factorio 2.0 uses the table form; this fallback keeps older/odd prototypes safe.
    energy_source.emissions_per_minute = { pollution = pollution }
  end
end

local function ensure_effect_allowed(prototype, effect_name)
  if not prototype then return end
  if not prototype.allowed_effects then
    prototype.allowed_effects = { effect_name }
    return
  end
  for _, effect in pairs(prototype.allowed_effects) do
    if effect == effect_name then return end
  end
  prototype.allowed_effects[#prototype.allowed_effects + 1] = effect_name
end

local function clone_placeable_item(item_name, entity_type, entity_name, display_name, description)
  local base_item = data.raw.item and data.raw.item[item_name]
  local base_entity = data.raw[entity_type] and data.raw[entity_type][entity_name]
  if not (base_item and base_entity) then return nil, nil end

  local item = table.deepcopy(base_item)
  local entity = table.deepcopy(base_entity)
  set_item_common(item, display_name.internal_name, display_name.text, description, display_name.internal_name)
  set_entity_common(entity, display_name.internal_name, display_name.text, description)
  return item, entity
end

local function add_placeable_series(base_item_name, entity_type, base_entity_name, prefix, display_base, variants, mutator)
  local prototypes = {}
  for _, v in pairs(variants) do
    local name = prefix .. "-" .. v.suffix
    local display = display_base .. " " .. v.label
    local description = v.description or ("Market-only " .. display .. ".")
    local item, entity = clone_placeable_item(base_item_name, entity_type, base_entity_name, {
      internal_name = name,
      text = display
    }, description)
    if item and entity then
      if mutator then mutator(item, entity, v) end
      prototypes[#prototypes + 1] = item
      prototypes[#prototypes + 1] = entity
    end
  end
  if #prototypes > 0 then data:extend(prototypes) end
end

local mk = {
  { suffix = "mk1", label = "MK1" },
  { suffix = "mk2", label = "MK2" },
  { suffix = "mk3", label = "MK3" },
  { suffix = "mk4", label = "MK4" },
  { suffix = "mk5", label = "MK5" },
}

-- 1. Solar Panel MK1-MK5
local solar = {
  { suffix = "mk1", label = "MK1", output = "120kW" },
  { suffix = "mk2", label = "MK2", output = "180kW" },
  { suffix = "mk3", label = "MK3", output = "220kW" },
  { suffix = "mk4", label = "MK4", output = "250kW" },
  { suffix = "mk5", label = "MK5", output = "270kW" },
}
add_placeable_series("solar-panel", "solar-panel", "solar-panel", "the-cave-solar-panel", "Solar Panel", solar, function(item, entity, v)
  entity.production = v.output
  item.subgroup = "energy"
end)

-- 2. Medium Electric Pole MK1-MK5
local medium_poles = {
  { suffix = "mk1", label = "MK1", wire = 9,  area = 4 },
  { suffix = "mk2", label = "MK2", wire = 10, area = 4.5 },
  { suffix = "mk3", label = "MK3", wire = 11, area = 5 },
  { suffix = "mk4", label = "MK4", wire = 12, area = 5.5 },
  { suffix = "mk5", label = "MK5", wire = 13, area = 6 },
}
add_placeable_series("medium-electric-pole", "electric-pole", "medium-electric-pole", "the-cave-medium-electric-pole", "Medium Electric Pole", medium_poles, function(item, entity, v)
  entity.maximum_wire_distance = v.wire
  entity.supply_area_distance = v.area
  item.subgroup = "energy-pipe-distribution"
end)

-- 3. Large Electric Pole MK1-MK5
local large_poles = {
  { suffix = "mk1", label = "MK1", wire = 34, area = 2.5 },
  { suffix = "mk2", label = "MK2", wire = 38, area = 3 },
  { suffix = "mk3", label = "MK3", wire = 42, area = 3.5 },
  { suffix = "mk4", label = "MK4", wire = 46, area = 4 },
  { suffix = "mk5", label = "MK5", wire = 50, area = 4.5 },
}
add_placeable_series("big-electric-pole", "electric-pole", "big-electric-pole", "the-cave-large-electric-pole", "Large Electric Pole", large_poles, function(item, entity, v)
  entity.maximum_wire_distance = v.wire
  entity.supply_area_distance = v.area
  item.subgroup = "energy-pipe-distribution"
end)

-- 4. Storage Tank MK1-MK5
local storage_tanks = {
  { suffix = "mk1", label = "MK1", capacity = 40000 },
  { suffix = "mk2", label = "MK2", capacity = 50000 },
  { suffix = "mk3", label = "MK3", capacity = 70000 },
  { suffix = "mk4", label = "MK4", capacity = 90000 },
  { suffix = "mk5", label = "MK5", capacity = 120000 },
}
add_placeable_series("storage-tank", "storage-tank", "storage-tank", "the-cave-storage-tank", "Storage Tank", storage_tanks, function(item, entity, v)
  if entity.fluid_box then
    entity.fluid_box = tc_copy(entity.fluid_box)
    entity.fluid_box.volume = v.capacity
    -- Compatibility for any older/modded tank clone that still uses base_area.
    if entity.fluid_box.base_area then
      entity.fluid_box.base_area = v.capacity / 100
    end
  end
  item.subgroup = "storage"
end)

-- 5. Accumulator MK1-MK5
local accumulators = {
  { suffix = "mk1", label = "MK1", capacity = "10MJ" },
  { suffix = "mk2", label = "MK2", capacity = "20MJ" },
  { suffix = "mk3", label = "MK3", capacity = "40MJ" },
  { suffix = "mk4", label = "MK4", capacity = "80MJ" },
  { suffix = "mk5", label = "MK5", capacity = "150MJ" },
}
add_placeable_series("accumulator", "accumulator", "accumulator", "the-cave-accumulator", "Accumulator", accumulators, function(item, entity, v)
  if entity.energy_source then
    entity.energy_source = tc_copy(entity.energy_source)
    entity.energy_source.buffer_capacity = v.capacity
  end
  item.subgroup = "energy"
end)

-- 6. Steam Engine MK1-MK5
local steam_engines = {
  { suffix = "mk1", label = "MK1", output = "1.8MW", boiler_power = "3.6MW" },
  { suffix = "mk2", label = "MK2", output = "2.7MW", boiler_power = "5.4MW" },
  { suffix = "mk3", label = "MK3", output = "3.6MW", boiler_power = "7.2MW" },
  { suffix = "mk4", label = "MK4", output = "4.5MW", boiler_power = "9MW" },
  { suffix = "mk5", label = "MK5", output = "5.4MW", boiler_power = "10.8MW" },
}
add_placeable_series("steam-engine", "generator", "steam-engine", "the-cave-steam-engine", "Steam Engine", steam_engines, function(item, entity, v)
  entity.max_power_output = v.output
  -- A power cap alone leaves every MK at the vanilla 30 steam/s (900 kW).
  -- W values parse to joules/tick; heat capacity parses to joules/unit/degree.
  -- Retain the loaded steam temperature and engine efficiency, and consume
  -- enough steam to reach this tier's power rating.
  local steam = data.raw.fluid[entity.fluid_box.filter]
  local energy_per_steam = parse_energy(steam.heat_capacity)
    * (math.min(entity.maximum_temperature, steam.max_temperature) - steam.default_temperature)
    * (entity.effectivity or 1)
  entity.fluid_usage_per_tick = parse_energy(v.output) / energy_per_steam
  item.subgroup = "energy"
end)

-- 6b. Boiler MK1-MK5: one boiler supplies two matching engines.
-- Retain the vanilla fuel efficiency, 165 C steam, footprint and graphics.
add_placeable_series("boiler", "boiler", "boiler", "the-cave-boiler", "Boiler", steam_engines, function(item, entity, v)
  entity.energy_consumption = v.boiler_power
  entity.localised_description = {"the-cave-power.boiler-description", v.label}
  item.localised_description = {"the-cave-power.boiler-description", v.label}
  item.subgroup = "energy"
end)

-- 7. Electric Steel Furnace MK1-MK5
local electric_furnace_base = data.raw.furnace and data.raw.furnace["electric-furnace"]
local esf = {
  { suffix = "mk1", label = "MK1", usage = "180kW", drain = "6.0kW", speed = 2.0, pollution = 2.0 },
  { suffix = "mk2", label = "MK2", usage = "200kW", drain = "6.0kW", speed = 2.5, pollution = 1.8 },
  { suffix = "mk3", label = "MK3", usage = "220kW", drain = "6.0kW", speed = 3.0, pollution = 1.5 },
  { suffix = "mk4", label = "MK4", usage = "250kW", drain = "6.0kW", speed = 3.5, pollution = 1.2 },
  { suffix = "mk5", label = "MK5", usage = "280kW", drain = "6.0kW", speed = 4.0, pollution = 1.0 },
}
add_placeable_series("steel-furnace", "furnace", "steel-furnace", "the-cave-electric-steel-furnace", "Electric Steel Furnace", esf, function(item, entity, v)
  entity.energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    drain = v.drain,
    emissions_per_minute = { pollution = v.pollution }
  }
  entity.energy_usage = v.usage
  entity.crafting_speed = v.speed
  entity.module_slots = 2
  if electric_furnace_base then
    entity.allowed_effects = tc_copy(electric_furnace_base.allowed_effects)
  else
    entity.allowed_effects = { "consumption", "speed", "productivity", "pollution", "quality" }
  end
  item.subgroup = "smelting-machine"
end)

-- 8. Electric Furnace MK1-MK5
local electric_furnaces = {
  { suffix = "mk1", label = "MK1", usage = "200kW", drain = "6.0kW", speed = 2.5, pollution = 1.0, modules = 3 },
  { suffix = "mk2", label = "MK2", usage = "220kW", drain = "6.0kW", speed = 3.0, pollution = 0.9, modules = 4 },
  { suffix = "mk3", label = "MK3", usage = "240kW", drain = "6.0kW", speed = 3.5, pollution = 0.8, modules = 5 },
  { suffix = "mk4", label = "MK4", usage = "270kW", drain = "6.0kW", speed = 4.0, pollution = 0.7, modules = 6 },
  { suffix = "mk5", label = "MK5", usage = "300kW", drain = "6.0kW", speed = 4.5, pollution = 0.6, modules = 7 },
}
add_placeable_series("electric-furnace", "furnace", "electric-furnace", "the-cave-electric-furnace", "Electric Furnace", electric_furnaces, function(item, entity, v)
  if entity.energy_source then
    entity.energy_source = tc_copy(entity.energy_source)
    entity.energy_source.drain = v.drain
    set_pollution(entity.energy_source, v.pollution)
  end
  entity.energy_usage = v.usage
  entity.crafting_speed = v.speed
  entity.module_slots = v.modules
  item.subgroup = "smelting-machine"
end)

-- 9-10. Assembling Machine 4 and 5
local assemblers = {
  { suffix = "4", label = "4", usage = "450kW", drain = "12.5kW", speed = 1.75, pollution = 1.8, modules = 6 },
  { suffix = "5", label = "5", usage = "550kW", drain = "12.5kW", speed = 2.25, pollution = 1.5, modules = 8 },
}
local assembler_prototypes = {}
local base_assembler_item = data.raw.item and data.raw.item["assembling-machine-3"]
local base_assembler = data.raw["assembling-machine"] and data.raw["assembling-machine"]["assembling-machine-3"]
if base_assembler_item and base_assembler then
  for _, v in pairs(assemblers) do
    local name = "the-cave-assembling-machine-" .. v.suffix
    local display = "Assembling Machine " .. v.label
    local description = "Market-only " .. display .. "."
    local item = table.deepcopy(base_assembler_item)
    local entity = table.deepcopy(base_assembler)
    set_item_common(item, name, display, description, name)
    set_entity_common(entity, name, display, description)
    if entity.energy_source then
      entity.energy_source = tc_copy(entity.energy_source)
      entity.energy_source.drain = v.drain
      set_pollution(entity.energy_source, v.pollution)
    end
    entity.energy_usage = v.usage
    entity.crafting_speed = v.speed
    entity.module_slots = v.modules
    item.subgroup = "production-machine"
    assembler_prototypes[#assembler_prototypes + 1] = item
    assembler_prototypes[#assembler_prototypes + 1] = entity
  end
end
if #assembler_prototypes > 0 then data:extend(assembler_prototypes) end

-- 11. Roboport MK1-MK5
local roboports = {
  { suffix = "mk1", label = "MK1", logistics = 55, construction = 120, charge = "600kW",  max = "2.3MW", min = "50kW" },
  { suffix = "mk2", label = "MK2", logistics = 60, construction = 130, charge = "700kW",  max = "2.5MW", min = "50kW" },
  { suffix = "mk3", label = "MK3", logistics = 65, construction = 140, charge = "800kW",  max = "2.8MW", min = "50kW" },
  { suffix = "mk4", label = "MK4", logistics = 70, construction = 150, charge = "900kW",  max = "3.1MW", min = "50kW" },
  { suffix = "mk5", label = "MK5", logistics = 75, construction = 160, charge = "1000kW", max = "3.5MW", min = "50kW" },
}
add_placeable_series("roboport", "roboport", "roboport", "the-cave-roboport", "Roboport", roboports, function(item, entity, v)
  entity.logistics_radius = v.logistics
  entity.construction_radius = v.construction
  entity.charging_energy = v.charge
  entity.energy_usage = v.min
  if entity.energy_source then
    entity.energy_source = tc_copy(entity.energy_source)
    entity.energy_source.input_flow_limit = v.max
  end
  item.subgroup = "logistic-network"
end)

-- 12. Toolbelt Equipment MK1-MK5
local toolbelt_equipment = data.raw["inventory-bonus-equipment"] and data.raw["inventory-bonus-equipment"]["toolbelt-equipment"]
local toolbelt_item = data.raw.item and data.raw.item["toolbelt-equipment"]
if toolbelt_equipment and toolbelt_item then
  local toolbelt_variants = {
    { suffix = "mk1", label = "MK1", bonus = 15 },
    { suffix = "mk2", label = "MK2", bonus = 20 },
    { suffix = "mk3", label = "MK3", bonus = 30 },
    { suffix = "mk4", label = "MK4", bonus = 40 },
    { suffix = "mk5", label = "MK5", bonus = 50 },
  }
  local prototypes = {}
  for _, v in pairs(toolbelt_variants) do
    local name = "the-cave-toolbelt-equipment-" .. v.suffix
    local display = "Toolbelt Equipment " .. v.label
    local description = "Market-only " .. display .. ". Adds " .. v.bonus .. " inventory slots."
    local item = table.deepcopy(toolbelt_item)
    local equipment = table.deepcopy(toolbelt_equipment)
    item.name = name
    set_names(item, display, description)
    item.place_as_equipment_result = name
    item.order = "z[the-cave-mk]-" .. name
    item.hidden = false
    equipment.name = name
    set_names(equipment, display, description)
    equipment.inventory_size_bonus = v.bonus
    equipment.shape = { width = 3, height = 1, type = "full" }
    equipment.order = "z[the-cave-mk]-" .. name
    prototypes[#prototypes + 1] = item
    prototypes[#prototypes + 1] = equipment
  end
  data:extend(prototypes)
end

-- 13. Radar MK1-MK5
local radars = {
  { suffix = "mk1", label = "MK1", continuous = 4, exploration = 18, usage = "350kW" },
  { suffix = "mk2", label = "MK2", continuous = 5, exploration = 22, usage = "400kW" },
  { suffix = "mk3", label = "MK3", continuous = 6, exploration = 28, usage = "450kW" },
  { suffix = "mk4", label = "MK4", continuous = 7, exploration = 35, usage = "500kW" },
  { suffix = "mk5", label = "MK5", continuous = 8, exploration = 45, usage = "600kW" },
}
add_placeable_series("radar", "radar", "radar", "the-cave-radar", "Radar", radars, function(item, entity, v)
  entity.max_distance_of_nearby_sector_revealed = v.continuous
  entity.max_distance_of_sector_revealed = v.exploration
  entity.energy_usage = v.usage
  item.subgroup = "defensive-structure"
end)

-- 14. Substation MK1-MK5
local substations = {
  { suffix = "mk1", label = "MK1", wire = 20, area = 10 },
  { suffix = "mk2", label = "MK2", wire = 22, area = 11 },
  { suffix = "mk3", label = "MK3", wire = 24, area = 12 },
  { suffix = "mk4", label = "MK4", wire = 26, area = 13 },
  { suffix = "mk5", label = "MK5", wire = 28, area = 14 },
}
add_placeable_series("substation", "electric-pole", "substation", "the-cave-substation", "Substation", substations, function(item, entity, v)
  entity.maximum_wire_distance = v.wire
  entity.supply_area_distance = v.area
  item.subgroup = "energy-pipe-distribution"
end)

-- 15. Beacon MK1-MK5
-- Market-only beacons. These intentionally allow productivity modules as a The Cave upgrade.
local beacons = {
  { suffix = "mk1", label = "MK1", modules = 3, supply = 4, effectivity = 1.6, usage = "600kW" },
  { suffix = "mk2", label = "MK2", modules = 3, supply = 5, effectivity = 1.7, usage = "800kW" },
  { suffix = "mk3", label = "MK3", modules = 4, supply = 6, effectivity = 1.8, usage = "1.0MW" },
  { suffix = "mk4", label = "MK4", modules = 5, supply = 7, effectivity = 1.9, usage = "1.3MW" },
  { suffix = "mk5", label = "MK5", modules = 6, supply = 8, effectivity = 2.0, usage = "1.7MW" },
}
add_placeable_series("beacon", "beacon", "beacon", "the-cave-beacon", "Beacon", beacons, function(item, entity, v)
  entity.module_slots = v.modules
  entity.supply_area_distance = v.supply
  entity.distribution_effectivity = v.effectivity
  entity.energy_usage = v.usage
  ensure_effect_allowed(entity, "productivity")
  item.subgroup = "module"
end)

-- 16. Electric Mining Drill MK1-MK5
-- Market-only miner upgrades. Mining area and uranium/fluid behavior stay vanilla for stability.
local electric_mining_drills = {
  { suffix = "mk1", label = "MK1", modules = 4, speed = 0.60, usage = "110kW", pollution = 9 },
  { suffix = "mk2", label = "MK2", modules = 5, speed = 0.70, usage = "130kW", pollution = 8 },
  { suffix = "mk3", label = "MK3", modules = 6, speed = 0.85, usage = "160kW", pollution = 7 },
  { suffix = "mk4", label = "MK4", modules = 7, speed = 1.00, usage = "200kW", pollution = 6 },
  { suffix = "mk5", label = "MK5", modules = 8, speed = 1.20, usage = "250kW", pollution = 5 },
}
add_placeable_series("electric-mining-drill", "mining-drill", "electric-mining-drill", "the-cave-electric-mining-drill", "Electric Mining Drill", electric_mining_drills, function(item, entity, v)
  entity.module_slots = v.modules
  entity.mining_speed = v.speed
  entity.energy_usage = v.usage
  if entity.energy_source then
    entity.energy_source = tc_copy(entity.energy_source)
    set_pollution(entity.energy_source, v.pollution)
  end
  item.subgroup = "extraction-machine"
end)
