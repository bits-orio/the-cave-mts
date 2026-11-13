local settings = require("scripts.game_settings").proxy(settings)

-- The Cave Minimal Wire
-- Event-driven copper-wire cleanup for player-placeable electric poles.
-- Red and green circuit connectors are never part of the MST calculation.

local M = {}

local SETTING_ENABLED = "the-cave-minimal-wire"
local SETTING_RADIUS = "the-cave-minimal-wire-radius"
local SETTING_MAX_POLES = "the-cave-minimal-wire-max-poles"
local SETTING_OPERATIONS = "the-cave-minimal-wire-operations-per-tick"
local REPLACEMENT_LIFETIME = 3
local CIRCUIT_RESTORE_ATTEMPTS = 4

local wire_distance_cache = {}

local function feature_enabled()
  local setting = settings and settings.startup and settings.startup[SETTING_ENABLED]
  return not setting or setting.value == "enabled" or setting.value == true
end

local function global_setting(name, fallback)
  local setting = settings and settings.global and settings.global[name]
  if setting and setting.value ~= nil then return setting.value end
  return fallback
end

local function state()
  storage.the_cave_minimal_wire = storage.the_cave_minimal_wire or {}
  local s = storage.the_cave_minimal_wire
  s.rebuild_requests = s.rebuild_requests or {}
  s.rebuild_keys = s.rebuild_keys or {}
  s.wire_operations = s.wire_operations or {}
  s.pending_replacements = s.pending_replacements or {}
  s.circuit_restores = s.circuit_restores or {}
  return s
end

local function valid(entity)
  return entity and entity.valid
end

local function position_key(surface_index, force_index, position)
  local x = math.floor((position.x or position[1] or 0) * 256 + 0.5)
  local y = math.floor((position.y or position[2] or 0) * 256 + 0.5)
  return table.concat({ surface_index or 0, force_index or 0, x, y }, ":")
end

local function distance_squared(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return dx * dx + dy * dy
end

local function max_wire_distance(pole)
  if not valid(pole) then return 0 end
  local prototype = pole.prototype
  if not (prototype and prototype.get_max_wire_distance) then return 0 end

  local quality_name = "normal"
  pcall(function()
    if pole.quality and pole.quality.name then quality_name = pole.quality.name end
  end)
  local cache_key = prototype.name .. ":" .. quality_name
  if wire_distance_cache[cache_key] then
    return wire_distance_cache[cache_key]
  end

  local ok, distance = pcall(function()
    return prototype.get_max_wire_distance(pole.quality)
  end)
  if not ok or type(distance) ~= "number" or distance <= 0 then return 0 end
  wire_distance_cache[cache_key] = distance
  return distance
end

local function eligible_pole(entity)
  if not (valid(entity) and entity.type == "electric-pole" and entity.unit_number) then
    return false
  end

  -- Internal Cave bridge/vault/enemy poles are deliberately unminable. They
  -- must retain their script-owned topology and never enter the player MST.
  local ok, minable = pcall(function() return entity.minable end)
  if not ok or not minable then return false end
  return max_wire_distance(entity) > 0
end

local function get_connector(entity, connector_id, create)
  if not (valid(entity) and entity.get_wire_connector) then return nil end
  local ok, connector = pcall(function()
    return entity.get_wire_connector(connector_id, create == true)
  end)
  if ok and connector and connector.valid then return connector end
  return nil
end

local function entity_descriptor(entity)
  return {
    entity = entity,
    surface_index = entity.surface.index,
    force_index = entity.force.index,
    position = { x = entity.position.x, y = entity.position.y },
    type = entity.type,
  }
end

local function resolve_descriptor(descriptor)
  if descriptor and valid(descriptor.entity) then return descriptor.entity end
  if not (descriptor and game) then return nil end
  local surface = game.surfaces[descriptor.surface_index]
  local force = game.forces[descriptor.force_index]
  if not (surface and surface.valid and force and force.valid) then return nil end

  local entities = surface.find_entities_filtered {
    position = descriptor.position,
    radius = 0.05,
    force = force,
  }
  for _, entity in pairs(entities) do
    if valid(entity) and (not descriptor.type or entity.type == descriptor.type) then
      return entity
    end
  end
  return nil
end

local CIRCUIT_CONNECTOR_IDS = {
  defines.wire_connector_id.circuit_red,
  defines.wire_connector_id.circuit_green,
}

local function snapshot_circuit_connections(pole)
  local links = {}
  for _, connector_id in pairs(CIRCUIT_CONNECTOR_IDS) do
    local connector = get_connector(pole, connector_id, false)
    if connector then
      local ok, connections = pcall(function() return connector.real_connections end)
      if ok and type(connections) == "table" then
        for _, connection in pairs(connections) do
          local target_connector = connection and connection.target
          local target_entity
          local target_connector_id
          pcall(function() target_entity = target_connector and target_connector.owner end)
          pcall(function() target_connector_id = target_connector and target_connector.wire_connector_id end)
          if valid(target_entity) and target_connector_id ~= nil then
            links[#links + 1] = {
              source_connector_id = connector_id,
              target = entity_descriptor(target_entity),
              target_connector_id = target_connector_id,
              origin = connection.origin,
            }
          end
        end
      end
    end
  end
  return links
end

local function queue_circuit_restore(pole, snapshot)
  if not (snapshot and snapshot.links and #snapshot.links > 0) then return end
  local s = state()
  s.circuit_restores[#s.circuit_restores + 1] = {
    due_tick = (game.tick or 0) + 1,
    attempts = 0,
    source = entity_descriptor(pole),
    links = snapshot.links,
  }
end

local function process_circuit_restores(tick)
  local s = state()
  local keep = {}
  for _, task in pairs(s.circuit_restores) do
    if task.due_tick > tick then
      keep[#keep + 1] = task
    else
      local source = resolve_descriptor(task.source)
      local unresolved = false
      if valid(source) then
        for _, link in pairs(task.links or {}) do
          local target = resolve_descriptor(link.target)
          if valid(target) then
            local source_connector = get_connector(source, link.source_connector_id, true)
            local target_connector = get_connector(target, link.target_connector_id, true)
            if source_connector and target_connector then
              pcall(function()
                source_connector.connect_to(target_connector, false, link.origin)
              end)
            else
              unresolved = true
            end
          else
            unresolved = true
          end
        end
      else
        unresolved = true
      end

      task.attempts = (task.attempts or 0) + 1
      if unresolved and task.attempts < CIRCUIT_RESTORE_ATTEMPTS then
        task.due_tick = tick + 1
        keep[#keep + 1] = task
      end
    end
  end
  s.circuit_restores = keep
end

local function queue_rebuild(surface, position, force)
  if not (feature_enabled() and surface and surface.valid and force and force.valid) then return end
  local s = state()
  local key = position_key(surface.index, force.index, position)
  if s.rebuild_keys[key] then return end
  s.rebuild_keys[key] = true
  s.rebuild_requests[#s.rebuild_requests + 1] = {
    key = key,
    due_tick = (game.tick or 0) + 1,
    surface_index = surface.index,
    force_index = force.index,
    position = { x = position.x, y = position.y },
  }
end

local function gather_local_poles(request)
  local surface = game.surfaces[request.surface_index]
  local force = game.forces[request.force_index]
  if not (surface and surface.valid and force and force.valid) then return {} end

  local radius = global_setting(SETTING_RADIUS, 42)
  local radius_squared = radius * radius
  local candidates = surface.find_entities_filtered {
    area = {
      { request.position.x - radius, request.position.y - radius },
      { request.position.x + radius, request.position.y + radius },
    },
    type = "electric-pole",
    force = force,
  }

  local poles = {}
  for _, pole in pairs(candidates) do
    if eligible_pole(pole) and distance_squared(pole.position, request.position) <= radius_squared then
      poles[#poles + 1] = pole
    end
  end
  table.sort(poles, function(a, b)
    local da = distance_squared(a.position, request.position)
    local db = distance_squared(b.position, request.position)
    if da == db then return a.unit_number < b.unit_number end
    return da < db
  end)

  local max_poles = global_setting(SETTING_MAX_POLES, 30)
  while #poles > max_poles do
    poles[#poles] = nil
  end
  return poles
end

local function edge_key(a_unit, b_unit)
  if a_unit > b_unit then a_unit, b_unit = b_unit, a_unit end
  return tostring(a_unit) .. ":" .. tostring(b_unit)
end

local function calculate_mst(poles)
  local parent = {}
  local rank = {}
  local edges = {}

  for i = 1, #poles do
    parent[i] = i
    rank[i] = 0
    local distance_a = max_wire_distance(poles[i])
    for j = i + 1, #poles do
      local limit = math.min(distance_a, max_wire_distance(poles[j]))
      local distance = distance_squared(poles[i].position, poles[j].position)
      if limit > 0 and distance <= limit * limit then
        edges[#edges + 1] = { from = i, to = j, distance = distance }
      end
    end
  end

  local function find_root(index)
    while parent[index] ~= index do
      parent[index] = parent[parent[index]]
      index = parent[index]
    end
    return index
  end

  local function unite(a, b)
    local root_a = find_root(a)
    local root_b = find_root(b)
    if root_a == root_b then return false end
    if rank[root_a] < rank[root_b] then
      parent[root_a] = root_b
    elseif rank[root_a] > rank[root_b] then
      parent[root_b] = root_a
    else
      parent[root_b] = root_a
      rank[root_a] = rank[root_a] + 1
    end
    return true
  end

  table.sort(edges, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    local a1, a2 = poles[a.from].unit_number, poles[a.to].unit_number
    local b1, b2 = poles[b.from].unit_number, poles[b.to].unit_number
    if math.min(a1, a2) ~= math.min(b1, b2) then
      return math.min(a1, a2) < math.min(b1, b2)
    end
    return math.max(a1, a2) < math.max(b1, b2)
  end)

  local desired = {}
  for _, edge in pairs(edges) do
    if unite(edge.from, edge.to) then
      local a = poles[edge.from]
      local b = poles[edge.to]
      desired[edge_key(a.unit_number, b.unit_number)] = { a = a, b = b }
    end
  end
  return desired
end

local function current_copper_edges(poles)
  local included = {}
  local current = {}
  for _, pole in pairs(poles) do included[pole.unit_number] = true end

  for _, pole in pairs(poles) do
    local connector = get_connector(pole, defines.wire_connector_id.pole_copper, false)
    if connector then
      local ok, connections = pcall(function() return connector.real_connections end)
      if ok and type(connections) == "table" then
        for _, connection in pairs(connections) do
          local target_connector = connection and connection.target
          local target
          pcall(function() target = target_connector and target_connector.owner end)
          if eligible_pole(target)
            and included[target.unit_number]
            and pole.unit_number < target.unit_number
          then
            current[edge_key(pole.unit_number, target.unit_number)] = { a = pole, b = target }
          end
        end
      end
    end
  end
  return current
end

local function queue_wire_operation(kind, a, b)
  state().wire_operations[#state().wire_operations + 1] = {
    kind = kind,
    a = a,
    b = b,
  }
end

local function rebuild(request)
  local poles = gather_local_poles(request)
  if #poles < 2 then return end

  local desired = calculate_mst(poles)
  local current = current_copper_edges(poles)

  -- Connect the replacement tree first so cleanup cannot briefly split power.
  for key, edge in pairs(desired) do
    if not current[key] then queue_wire_operation("connect", edge.a, edge.b) end
  end
  for key, edge in pairs(current) do
    if not desired[key] then queue_wire_operation("disconnect", edge.a, edge.b) end
  end
end

local function connection_is_in_range(a, b)
  if not (eligible_pole(a) and eligible_pole(b)) then return false end
  if a.surface.index ~= b.surface.index or a.force.index ~= b.force.index then return false end
  local limit = math.min(max_wire_distance(a), max_wire_distance(b))
  return limit > 0 and distance_squared(a.position, b.position) <= limit * limit
end

local function process_wire_operations()
  local s = state()
  local limit = global_setting(SETTING_OPERATIONS, 10)
  local processed = 0
  while processed < limit and #s.wire_operations > 0 do
    local operation = table.remove(s.wire_operations, 1)
    local a, b = operation.a, operation.b
    if valid(a) and valid(b) then
      local connector_a = get_connector(a, defines.wire_connector_id.pole_copper, true)
      local connector_b = get_connector(b, defines.wire_connector_id.pole_copper, true)
      if connector_a and connector_b then
        if operation.kind == "connect" then
          if connection_is_in_range(a, b) then
            pcall(function()
              connector_a.connect_to(connector_b, false, defines.wire_origin.player)
            end)
          end
        else
          pcall(function() connector_a.disconnect_from(connector_b) end)
        end
      end
    end
    processed = processed + 1
  end
end

local function process_next_rebuild(tick)
  local s = state()
  if #s.wire_operations > 0 then return end
  local request = s.rebuild_requests[1]
  if not request or request.due_tick > tick then return end
  table.remove(s.rebuild_requests, 1)
  s.rebuild_keys[request.key] = nil
  rebuild(request)
end

local function cleanup_replacement_snapshots(tick)
  local pending = state().pending_replacements
  for key, snapshot in pairs(pending) do
    if not snapshot or snapshot.expires_tick < tick then pending[key] = nil end
  end
end

function M.on_init()
  storage.the_cave_minimal_wire = nil
  state()
end

function M.on_configuration_changed()
  wire_distance_cache = {}
  state()
  if not feature_enabled() then
    storage.the_cave_minimal_wire = nil
    state()
  end
end

function M.on_runtime_mod_setting_changed(event)
  if not (event and event.setting) then return end
  if event.setting == SETTING_RADIUS
    or event.setting == SETTING_MAX_POLES
    or event.setting == SETTING_OPERATIONS
  then
    wire_distance_cache = {}
  end
end

function M.on_pre_removed(entity)
  if not eligible_pole(entity) then return end
  local s = state()
  local key = position_key(entity.surface.index, entity.force.index, entity.position)
  s.pending_replacements[key] = {
    expires_tick = (game.tick or 0) + REPLACEMENT_LIFETIME,
    links = snapshot_circuit_connections(entity),
  }
  if feature_enabled() then
    queue_rebuild(entity.surface, entity.position, entity.force)
  end
end

function M.on_removed(entity)
  if not (feature_enabled() and eligible_pole(entity)) then return end
  queue_rebuild(entity.surface, entity.position, entity.force)
end

function M.on_built(entity)
  if not eligible_pole(entity) then return end
  local s = state()
  local key = position_key(entity.surface.index, entity.force.index, entity.position)
  local snapshot = s.pending_replacements[key]
  if snapshot then
    s.pending_replacements[key] = nil
    queue_circuit_restore(entity, snapshot)
  end
  if feature_enabled() then
    queue_rebuild(entity.surface, entity.position, entity.force)
  end
end

function M.on_tick(event)
  local tick = event and event.tick or game.tick
  cleanup_replacement_snapshots(tick)
  process_circuit_restores(tick)
  if not feature_enabled() then return end
  process_next_rebuild(tick)
  process_wire_operations()
end

return M
