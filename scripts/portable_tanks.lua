local portable_tanks = {}

local BASE_TANK_NAME = "storage-tank"
local ITEM_PREFIX = "portable-storage-tank-"
local PROXY_PREFIX = "portable-storage-tank-proxy-"
local TAG_VERSION = 1
local EPSILON = 0.001

-- The standalone implementations use the same item names and tags. When one
-- is active it remains the sole runtime owner, preventing two mods from
-- converting the same mining buffer or placement event.
local function external_owner_active()
  return script.active_mods["early-stack-size"] ~= nil
    or script.active_mods["portable-storage-tanks"] ~= nil
end

function portable_tanks.is_enabled()
  return not external_owner_active()
end

local function is_finite_number(value)
  return type(value) == "number"
    and value == value
    and value > -math.huge
    and value < math.huge
end

local function copy_basic(value)
  if type(value) ~= "table" then
    return value
  end

  local result = {}
  for key, child in pairs(value) do
    result[copy_basic(key)] = copy_basic(child)
  end
  return result
end

local function format_number(value, decimals)
  local rounded = math.floor(value + 0.5)
  if math.abs(value - rounded) < EPSILON then
    return tostring(rounded)
  end

  local formatted = string.format("%." .. tostring(decimals or 2) .. "f", value)
  formatted = string.gsub(formatted, "0+$", "")
  formatted = string.gsub(formatted, "%.$", "")
  return formatted
end

local function item_name_for_fluid(fluid_name)
  return ITEM_PREFIX .. fluid_name
end

local function proxy_name_for_fluid(fluid_name)
  return PROXY_PREFIX .. fluid_name
end

local function fluid_name_from_proxy(entity_name)
  if string.sub(entity_name, 1, #PROXY_PREFIX) ~= PROXY_PREFIX then
    return nil
  end
  return string.sub(entity_name, #PROXY_PREFIX + 1)
end

local function entity_quality_name(entity)
  return entity.quality and entity.quality.name or "normal"
end

local function make_tags(fluid_name, amount, temperature, capacity)
  return {
    pst_version = TAG_VERSION,
    pst_fluid = fluid_name,
    pst_amount = amount,
    pst_temperature = temperature,
    pst_capacity = capacity
  }
end

local function validate_tags(raw_tags, expected_fluid)
  if type(raw_tags) ~= "table"
    or raw_tags.pst_version ~= TAG_VERSION
    or raw_tags.pst_fluid ~= expected_fluid
    or not is_finite_number(raw_tags.pst_amount)
    or not is_finite_number(raw_tags.pst_temperature)
    or not is_finite_number(raw_tags.pst_capacity)
    or raw_tags.pst_amount <= EPSILON
    or raw_tags.pst_capacity <= EPSILON
    or raw_tags.pst_amount > raw_tags.pst_capacity + EPSILON
  then
    return nil
  end

  if not prototypes.fluid[raw_tags.pst_fluid] then
    return nil
  end

  return make_tags(
    raw_tags.pst_fluid,
    raw_tags.pst_amount,
    raw_tags.pst_temperature,
    raw_tags.pst_capacity
  )
end

local function dynamic_description(tags)
  local fluid = prototypes.fluid[tags.pst_fluid]
  local fluid_name = fluid and fluid.localised_name or {"fluid-name." .. tags.pst_fluid}

  return {
    "portable-storage-tanks.dynamic-description",
    fluid_name,
    format_number(tags.pst_amount, 2),
    format_number(tags.pst_capacity, 2),
    format_number(tags.pst_temperature, 2)
  }
end

-- Uses the existing portable-item contract, including compatible standalone
-- owners. No entity or fluid is created until the purchased item is placed.
function portable_tanks.make_filled_item(fluid_name, amount, temperature)
  local fluid = prototypes.fluid[fluid_name]
  local item_name = item_name_for_fluid(fluid_name)
  local item = prototypes.item[item_name]
  local tank = prototypes.entity[BASE_TANK_NAME]
  if not fluid or not item or item.type ~= "item-with-tags" or not tank
    or not item.place_result or item.place_result.name ~= proxy_name_for_fluid(fluid_name)
  then
    return nil
  end

  local capacity = tank.get_fluid_capacity("normal")
  temperature = temperature or fluid.default_temperature
  local tags = validate_tags(make_tags(fluid_name, amount, temperature, capacity), fluid_name)
  if not tags or temperature < fluid.default_temperature or temperature > fluid.max_temperature then
    return nil
  end

  return {
    name = item_name,
    count = 1,
    quality = "normal",
    tags = tags,
    custom_description = dynamic_description(tags)
  }
end

local function find_mined_tank_stack(buffer, quality_name)
  if not buffer then
    return nil
  end

  for index = 1, #buffer do
    local stack = buffer[index]
    if stack.valid_for_read and stack.name == BASE_TANK_NAME then
      local stack_quality = stack.quality and stack.quality.name or "normal"
      if stack_quality == quality_name then
        return stack
      end
    end
  end

  return nil
end

local function restore_mined_tank(entity, result_stack, quality_name, fluid_name, amount, temperature)
  pcall(function()
    result_stack.set_stack({name = BASE_TANK_NAME, count = 1, quality = quality_name})
  end)

  local restored = entity.insert_fluid({
    name = fluid_name,
    amount = amount,
    temperature = temperature
  })

  if restored + EPSILON < amount then
    log("[The Cave] Portable tank rollback restored only " .. tostring(restored)
      .. " of " .. tostring(amount) .. " fluid after a mining conversion failure.")
  end
end

function portable_tanks.on_mined(event)
  if external_owner_active() then
    return false
  end

  local entity = event.entity
  if not entity or not entity.valid or entity.name ~= BASE_TANK_NAME then
    return false
  end

  local fluid = entity.get_fluid(1)
  if not fluid or not is_finite_number(fluid.amount) or fluid.amount <= EPSILON then
    return false
  end

  local portable_item_name = item_name_for_fluid(fluid.name)
  if not prototypes.item[portable_item_name] then
    log("[The Cave] No portable tank item prototype exists for fluid " .. fluid.name .. ".")
    return false
  end

  local quality_name = entity_quality_name(entity)
  local result_stack = find_mined_tank_stack(event.buffer, quality_name)
  if not result_stack or result_stack.count ~= 1 then
    log("[The Cave] Could not find the single storage-tank mining result; portable conversion skipped.")
    return false
  end

  local amount = fluid.amount
  local temperature = fluid.temperature
  local capacity = entity.get_fluid_capacity(1)
  local removed = entity.extract_fluid({name = fluid.name, amount = amount})

  if not is_finite_number(removed) or removed <= EPSILON then
    return false
  end

  local tags = make_tags(fluid.name, removed, temperature, capacity)
  local changed = false
  local ok, error_message = pcall(function()
    changed = result_stack.set_stack({
      name = portable_item_name,
      count = 1,
      quality = quality_name
    })

    if changed then
      result_stack.tags = tags
      result_stack.custom_description = dynamic_description(tags)
    end
  end)

  if not ok or not changed then
    restore_mined_tank(entity, result_stack, quality_name, fluid.name, removed, temperature)
    log("[The Cave] Portable tank mining conversion failed: "
      .. tostring(error_message or "set_stack returned false"))
    return false
  end

  return true
end

local function stack_source_from_inventory(inventory, expected_item_name)
  if not inventory then
    return nil
  end

  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read and stack.name == expected_item_name then
      return stack
    end
  end

  return nil
end

local function source_from_build_event(event, expected_item_name)
  local stack

  if event.stack and event.stack.valid_for_read and event.stack.name == expected_item_name then
    stack = event.stack
  else
    stack = stack_source_from_inventory(event.consumed_items, expected_item_name)
  end

  if stack then
    return {
      found = true,
      tags = copy_basic(stack.tags or event.tags),
      custom_description = copy_basic(stack.custom_description),
      quality = stack.quality and stack.quality.name or nil
    }
  end

  if event.tags then
    return {
      found = true,
      tags = copy_basic(event.tags),
      quality = nil
    }
  end

  return nil
end

local function actor_from_event(event)
  local robot = event.robot
  local player
  local platform = event.platform

  if event.player_index then
    player = game.get_player(event.player_index)
  elseif robot and robot.valid and robot.last_user then
    player = robot.last_user
  end

  if platform and not platform.valid then
    platform = nil
  end

  return player, robot, platform
end

local function refund_item(surface, position, force, player, robot, definition, platform)
  if platform and platform.valid then
    local hub = platform.hub
    local inventory = hub and hub.valid and hub.get_inventory(defines.inventory.hub_main) or nil
    if inventory and inventory.insert(definition) == 1 then
      return true
    end
  end

  if robot and robot.valid then
    local inventory = robot.get_inventory(defines.inventory.robot_cargo)
    if inventory and inventory.insert(definition) == 1 then
      return true
    end
  elseif player and player.valid and player.insert(definition) == 1 then
    return true
  end

  surface.spill_item_stack({
    position = position,
    stack = definition,
    enable_looted = true,
    force = force,
    allow_belts = false,
    use_start_position_on_failure = true,
    drop_full_stack = true
  })
  return false
end

local function notify_player(player, position, message)
  if not player or not player.valid then
    return
  end

  player.create_local_flying_text({text = message, position = position})
  player.print(message)
end

local function refund_definition(item_name, quality_name, source, valid_tags)
  local definition = {
    name = item_name,
    count = 1,
    quality = quality_name
  }

  if valid_tags then
    definition.tags = copy_basic(valid_tags)
    definition.custom_description = dynamic_description(valid_tags)
  elseif source then
    definition.tags = copy_basic(source.tags)
    definition.custom_description = copy_basic(source.custom_description)
  end

  return definition
end

local function cancel_placement(context, definition, message)
  if context.entity.valid then
    context.entity.destroy({raise_destroy = true})
  end

  if definition then
    refund_item(
      context.surface,
      context.position,
      context.force,
      context.player,
      context.robot,
      definition,
      context.platform
    )
  end

  notify_player(context.player, context.position, message)
end

function portable_tanks.on_built(event)
  if external_owner_active() then
    return false
  end

  local proxy = event.entity
  if not proxy or not proxy.valid then
    return false
  end

  local fluid_name = fluid_name_from_proxy(proxy.name)
  if not fluid_name then
    return false
  end

  local item_name = item_name_for_fluid(fluid_name)
  local quality_name = entity_quality_name(proxy)
  local source = source_from_build_event(event, item_name)
  local tags = source and validate_tags(source.tags, fluid_name) or nil
  local player, robot, platform = actor_from_event(event)
  local context = {
    entity = proxy,
    surface = proxy.surface,
    position = {x = proxy.position.x, y = proxy.position.y},
    direction = proxy.direction,
    force = proxy.force,
    quality = quality_name,
    player = player,
    robot = robot,
    platform = platform
  }

  if not source or not tags then
    local definition = source and refund_definition(item_name, quality_name, source, nil) or nil
    cancel_placement(context, definition, {"portable-storage-tanks.invalid-data"})
    return true
  end

  local definition = refund_definition(item_name, quality_name, source, tags)
  proxy.destroy({raise_destroy = true})

  local tank = context.surface.create_entity({
    name = BASE_TANK_NAME,
    position = context.position,
    direction = context.direction,
    quality = context.quality,
    force = context.force,
    player = context.player,
    fast_replace = false,
    spill = false,
    raise_built = true,
    create_build_effect_smoke = false
  })

  if not tank then
    refund_item(context.surface, context.position, context.force, player, robot, definition, platform)
    notify_player(player, context.position, {"portable-storage-tanks.create-failed"})
    return true
  end

  local current_capacity = tank.get_fluid_capacity(1)
  if tags.pst_amount > current_capacity + EPSILON then
    tank.destroy({raise_destroy = true})
    refund_item(context.surface, context.position, context.force, player, robot, definition, platform)
    notify_player(player, context.position, {"portable-storage-tanks.capacity-changed"})
    return true
  end

  local existing_fluid = tank.get_fluid(1)
  if existing_fluid and existing_fluid.name ~= fluid_name then
    tank.destroy({raise_destroy = true})
    refund_item(context.surface, context.position, context.force, player, robot, definition, platform)
    notify_player(player, context.position, {"portable-storage-tanks.incompatible-fluid"})
    return true
  end

  local inserted = tank.insert_fluid({
    name = fluid_name,
    amount = tags.pst_amount,
    temperature = tags.pst_temperature
  })

  if inserted + EPSILON < tags.pst_amount then
    if inserted > EPSILON then
      tank.extract_fluid({name = fluid_name, amount = inserted})
    end
    tank.destroy({raise_destroy = true})
    refund_item(context.surface, context.position, context.force, player, robot, definition, platform)
    notify_player(player, context.position, {"portable-storage-tanks.insert-failed"})
    return true
  end

  return true
end

local function replace_orphaned_proxy(proxy)
  local surface = proxy.surface
  local position = {x = proxy.position.x, y = proxy.position.y}
  local direction = proxy.direction
  local force = proxy.force
  local quality_name = entity_quality_name(proxy)
  local platform = surface.platform

  proxy.destroy({raise_destroy = true})

  local tank = surface.create_entity({
    name = BASE_TANK_NAME,
    position = position,
    direction = direction,
    quality = quality_name,
    force = force,
    fast_replace = false,
    spill = false,
    raise_built = true,
    create_build_effect_smoke = false
  })

  if tank then
    return true
  end

  refund_item(
    surface,
    position,
    force,
    nil,
    nil,
    {name = BASE_TANK_NAME, count = 1, quality = quality_name},
    platform
  )
  return false
end

function portable_tanks.on_configuration_changed()
  if external_owner_active() then
    return
  end

  local replaced = 0
  local refunded = 0
  local proxy_names = {}

  for fluid_name in pairs(prototypes.fluid) do
    proxy_names[#proxy_names + 1] = proxy_name_for_fluid(fluid_name)
  end

  if #proxy_names == 0 then
    return
  end

  for _, surface in pairs(game.surfaces) do
    if surface.valid then
      local tanks = surface.find_entities_filtered({name = proxy_names})
      for _, tank in pairs(tanks) do
        if tank.valid and fluid_name_from_proxy(tank.name) then
          if replace_orphaned_proxy(tank) then
            replaced = replaced + 1
          else
            refunded = refunded + 1
          end
        end
      end
    end
  end

  if replaced > 0 or refunded > 0 then
    log("[The Cave] Recovered " .. tostring(replaced)
      .. " orphaned portable-tank proxies as empty storage tanks; refunded "
      .. tostring(refunded) .. " empty storage-tank items after replacement failures.")
  end
end

portable_tanks.item_name_for_fluid = item_name_for_fluid
portable_tanks.proxy_name_for_fluid = proxy_name_for_fluid
portable_tanks.base_tank_name = BASE_TANK_NAME

return portable_tanks
