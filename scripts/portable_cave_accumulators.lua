-- Event-only energy transfer. No surface scans, tick handler, or energy cache.
-- The actual consumed item is the authority; blueprint/event tags are not.
local portable = {entity_names = {}}
local supported = {}
local placement_names = {}
for _, size in ipairs({3, 6, 10, 20}) do
  local name = "the-cave-accumulator-" .. size .. "x" .. size
  supported[name] = name .. "-charged"
  placement_names[name .. "-portable-placement"] = name
  portable.entity_names[#portable.entity_names + 1] = name
end

function portable.is_placement(entity)
  return entity and entity.valid and placement_names[entity.name] ~= nil
end

function portable.is_supported(entity)
  return entity and entity.valid and supported[entity.name] ~= nil
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function quality_name(object)
  return object.quality and object.quality.name or "normal"
end

local function energy_text(joules)
  for _, unit in ipairs({{1e12, "TJ"}, {1e9, "GJ"}, {1e6, "MJ"}, {1e3, "kJ"}, {0, "J"}}) do
    if joules >= unit[1] then
      local value = string.format("%.3f", joules / math.max(1, unit[1]))
      value = value:gsub("0+$", ""):gsub("%.$", "")
      return value .. " " .. unit[2]
    end
  end
end

local function description(tags)
  return {"cave-portable-accumulators.stored-charge", energy_text(tags.energy),
    energy_text(tags.capacity), string.format("%.1f", math.floor(tags.energy / tags.capacity * 1000) / 10)}
end

function portable.on_mined(event)
  local entity = event.entity
  if not portable.is_supported(entity) then return false end
  local energy, capacity = entity.energy, entity.electric_buffer_size
  if not finite(energy) or energy <= 0 or not finite(capacity) or capacity <= 0 then return false end
  local buffer = event.buffer
  if not (buffer and buffer.valid) then return false end
  local quality = quality_name(entity)
  for index = 1, #buffer do
    local stack = buffer[index]
    if stack.valid_for_read and stack.name == entity.name and stack.count == 1
        and quality_name(stack) == quality then
      local tags = {version = 1, entity = entity.name, energy = energy, capacity = capacity}
      local ok, err = pcall(function()
        assert(stack.set_stack({name = supported[entity.name], count = 1, quality = quality}))
        stack.tags = {cave_accumulator = tags}
        stack.custom_description = description(tags)
      end)
      if not ok then
        stack.set_stack({name = entity.name, count = 1, quality = quality})
        log("[The Cave] Could not preserve accumulator charge: " .. tostring(err))
        return false
      end
      -- The mined entity is about to disappear. Clearing it also prevents a
      -- duplicate mining callback from crediting these same Joules twice.
      entity.energy = 0
      return true
    end
  end
  return false
end

local function source_stack(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return nil end
  local base_name = placement_names[entity.name] or entity.name
  local expected = supported[base_name]
  if not expected then return nil end
  local stack = event.stack
  if stack and stack.valid_for_read and stack.name == expected then return stack end
  local consumed = event.consumed_items
  if consumed and consumed.valid then
    for index = 1, #consumed do
      stack = consumed[index]
      if stack.valid_for_read and stack.name == expected then return stack end
    end
  end
end

local function player_from_event(event)
  if event.player_index then return game.get_player(event.player_index) end
  local robot = event.robot
  return robot and robot.valid and robot.last_user or nil
end

local function refund(event, stack)
  local entity = event.entity or event.created_entity
  local definition = {name = stack.name, count = 1, quality = quality_name(stack),
    tags = stack.tags, custom_description = stack.custom_description}
  local platform, robot = event.platform, event.robot
  local inventory
  if platform and platform.valid then
    local hub = platform.hub
    inventory = hub and hub.valid and hub.get_inventory(defines.inventory.hub_main)
  elseif robot and robot.valid then
    inventory = robot.get_inventory(defines.inventory.robot_cargo)
  end
  if inventory and inventory.insert(definition) == 1 then return end
  if not robot and not platform then
    local player = player_from_event(event)
    if player and player.valid and player.insert(definition) == 1 then return end
  end
  entity.surface.spill_item_stack({position = entity.position, stack = definition,
    force = entity.force, enable_looted = true, allow_belts = false,
    use_start_position_on_failure = true, drop_full_stack = true})
end

-- Used only when the existing ore-protection rule rejects this placement.
-- Return the actual charged item, not the entity's default empty build item.
function portable.refund_placement(event)
  local stack = source_stack(event)
  if not stack then return false end
  if not stack.get_tag("cave_accumulator_consumed") then
    refund(event, stack)
    stack.set_tag("cave_accumulator_consumed", true)
  end
  return true
end

local function cancel(event, stack, reason)
  local player = player_from_event(event)
  portable.refund_placement(event)
  local entity = event.entity or event.created_entity
  entity.destroy({raise_destroy = true})
  if player and player.valid then player.print({"cave-portable-accumulators." .. reason}) end
  return true
end

function portable.on_built(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return false end
  local base_name = placement_names[entity.name]
  local stack = source_stack(event)
  if not stack then
    -- A script/ghost without a consumed charged item cannot create a charge.
    if base_name then entity.destroy({raise_destroy = true}); return true end
    return false
  end
  -- This marker is on the temporary consumed stack, never on the placed entity
  -- or in a global cache. Repeating this same event cannot refill the battery.
  if stack.get_tag("cave_accumulator_consumed") then return false end
  local tags = stack.get_tag("cave_accumulator")
  if stack.count ~= 1 or type(tags) ~= "table" or tags.version ~= 1
      or tags.entity ~= (base_name or entity.name) or quality_name(stack) ~= quality_name(entity)
      or not finite(tags.energy) or tags.energy <= 0
      or not finite(tags.capacity) or tags.capacity <= 0 or tags.energy > tags.capacity then
    return cancel(event, stack, "invalid-charge")
  end
  local capacity = entity.electric_buffer_size
  if not finite(capacity) or tags.energy > capacity then
    return cancel(event, stack, "capacity-changed")
  end
  if base_name then
    -- Native fast replacement preserves circuit wires and entity settings.
    local replacement = entity.surface.create_entity({name = base_name,
      position = entity.position, direction = entity.direction,
      quality = entity.quality, force = entity.force, fast_replace = true,
      spill = false, raise_built = false, create_build_effect_smoke = false})
    if not replacement then return cancel(event, stack, "restore-failed") end
    entity = replacement
  end
  entity.energy = tags.energy
  if math.abs(entity.energy - tags.energy) > math.max(1e-6, tags.energy * 1e-12) then
    -- Replacement can change the event entity, so cancellation needs the
    -- final entity while retaining the original consumed inventory/actor.
    local failed = {}
    for key, value in pairs(event) do failed[key] = value end
    failed.entity = entity
    return cancel(failed, stack, "restore-failed")
  end
  stack.set_tag("cave_accumulator_consumed", true)
  if base_name then script.raise_script_built({entity = entity}); return true end
  return false
end

return portable
