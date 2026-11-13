-- The Cave: Turret Range Upgrade runtime handling.
-- Uses hidden turret variants created at data-final-fixes stage.
-- Each research level adds +3 range to all supported turrets for that force.
--
-- 2.3.19 fix:
-- Target priority is not stored in normal control_behavior. It is stored directly
-- on the turret LuaEntity through priority_targets / get_priority_target /
-- set_priority_target plus ignore_unprioritised_targets.
-- We explicitly save and restore those fields before and after upgrading.

local turret_range = {}

local TECH_PREFIX = "the-cave-turret-range-upgrade-"
local LEVELS = 5

local BASE_TURRETS = {
    ["gun-turret"] = true,
    ["laser-turret"] = true,
    ["flamethrower-turret"] = true,
    ["rocket-turret"] = true,
    ["tesla-turret"] = true,
    ["railgun-turret"] = true,
}

local function variant_name(base_name, level)
    return "the-cave-range-" .. base_name .. "-" .. tostring(level)
end

local function base_from_name(name)
    if BASE_TURRETS[name] then return name end
    local base, level = name:match("^the%-cave%-range%-(.+)%-(%d+)$")
    if base and BASE_TURRETS[base] then
        return base, tonumber(level)
    end
    return nil
end

local function prototype_exists(name)
    return prototypes and prototypes.entity and prototypes.entity[name] ~= nil
end

local function get_force_level(force)
    if not (force and force.valid and force.technologies) then return 0 end
    local level = 0
    for i = 1, LEVELS do
        local tech = force.technologies[TECH_PREFIX .. i]
        if tech and tech.researched then
            level = i
        else
            break
        end
    end
    return level
end

local function desired_name(base_name, level)
    if level <= 0 then return base_name end
    local name = variant_name(base_name, level)
    if prototype_exists(name) then return name end
    return base_name
end

local function supported_entity_name_list()
    local names = {}
    for base_name in pairs(BASE_TURRETS) do
        if prototype_exists(base_name) then
            names[#names + 1] = base_name
        end
        for level = 1, LEVELS do
            local name = variant_name(base_name, level)
            if prototype_exists(name) then
                names[#names + 1] = name
            end
        end
    end
    return names
end

-- Hidden range variants have different prototype names from their vanilla
-- turrets. Factorio stores turret-attack research bonuses by exact turret
-- prototype name, so the variants would otherwise keep ammo-category bonuses
-- but lose the turret-specific damage bonus. Mirror the final modifier from
-- each base turret to all of its range variants for the force.
local function sync_force_attack_modifiers(force)
    if not (force and force.valid) then return end

    for base_name in pairs(BASE_TURRETS) do
        if prototype_exists(base_name) then
            local ok_get, modifier = pcall(function()
                return force.get_turret_attack_modifier(base_name)
            end)

            if ok_get and type(modifier) == "number" then
                for level = 1, LEVELS do
                    local name = variant_name(base_name, level)
                    if prototype_exists(name) then
                        pcall(function()
                            force.set_turret_attack_modifier(name, modifier)
                        end)
                    end
                end
            end
        end
    end
end

local function sync_all_force_attack_modifiers()
    for _, force in pairs(game.forces) do
        if force and force.valid and force.name ~= "neutral" and force.name ~= "enemy" then
            sync_force_attack_modifiers(force)
        end
    end
end

local function read_quality(entity)
    local ok, quality = pcall(function() return entity.quality end)
    if ok and quality then return quality end
    return nil
end

local function get_health_ratio(entity)
    local ok, max_health = pcall(function()
        return entity.max_health
    end)
    if ok and max_health and max_health > 0 and entity.health then
        return math.max(0, math.min(1, entity.health / max_health))
    end
    return nil
end

local function collect_inventory(entity, inventory_id)
    local stacks = {}
    local ok, inv = pcall(function() return entity.get_inventory(inventory_id) end)
    if not ok or not inv then return stacks end

    for i = 1, #inv do
        local stack = inv[i]
        if stack and stack.valid_for_read then
            local entry = { name = stack.name, count = stack.count }
            pcall(function()
                if stack.quality then entry.quality = stack.quality.name or stack.quality end
            end)
            stacks[#stacks + 1] = entry
        end
    end
    return stacks
end

local function restore_inventory(entity, inventory_id, stacks)
    if not (stacks and #stacks > 0) then return end
    local ok, inv = pcall(function() return entity.get_inventory(inventory_id) end)
    if not ok or not inv then return end

    for _, entry in pairs(stacks) do
        local remaining = entry.count or 1
        local insert_stack = { name = entry.name, count = remaining }
        if entry.quality then insert_stack.quality = entry.quality end
        local inserted = 0
        local ok_insert, result = pcall(function() return inv.insert(insert_stack) end)
        if ok_insert and type(result) == "number" then
            inserted = result
        end
        if inserted < remaining then
            pcall(function()
                entity.surface.spill_item_stack({
                    position = entity.position,
                    stack = { name = entry.name, count = remaining - inserted },
                    force = entity.force,
                    allow_belts = false,
                })
            end)
        end
    end
end

local function collect_fluidbox(entity)
    local fluids = {}
    local ok = pcall(function()
        for i = 1, entity.fluids_count do
            fluids[i] = entity.get_fluid(i)
        end
    end)
    if not ok then return {} end
    return fluids
end

local function restore_fluidbox(entity, fluids)
    if not fluids then return end
    pcall(function()
        for i, fluid in pairs(fluids) do
            entity.set_fluid(i, fluid)
        end
    end)
end

local function prototype_name_from_priority_target(target)
    if not target then return nil end
    if type(target) == "string" then return target end
    local ok, name = pcall(function() return target.name end)
    if ok and name then return name end
    return nil
end

local function collect_priority_targets(entity)
    local data = {
        targets = {},
        ignore_unprioritised_targets = nil,
    }

    pcall(function()
        data.ignore_unprioritised_targets = entity.ignore_unprioritised_targets
    end)

    -- Official runtime API exposes priority_targets as an array of LuaEntityPrototype.
    local ok_list, list = pcall(function() return entity.priority_targets end)
    if ok_list and list then
        for i, target in pairs(list) do
            local name = prototype_name_from_priority_target(target)
            if name then
                data.targets[i] = name
            end
        end
    end

    -- Also probe by index with get_priority_target. This helps preserve order even if
    -- the read-only priority_targets array behavior changes or omits sparse entries.
    for i = 1, 32 do
        local ok_target, target = pcall(function() return entity.get_priority_target(i) end)
        if ok_target then
            local name = prototype_name_from_priority_target(target)
            if name then
                data.targets[i] = name
            end
        end
    end

    return data
end

local function restore_priority_targets(entity, data)
    if not (entity and entity.valid and data) then return end

    pcall(function()
        if data.ignore_unprioritised_targets ~= nil then
            entity.ignore_unprioritised_targets = data.ignore_unprioritised_targets
        end
    end)

    -- Clear existing entries first so an upgraded entity cannot keep stale/default targets.
    for i = 1, 32 do
        pcall(function() entity.set_priority_target(i, nil) end)
    end

    for i, name in pairs(data.targets or {}) do
        if name then
            pcall(function() entity.set_priority_target(i, name) end)
        end
    end
end

local function collect_turret_control_behavior(entity)
    local data = {}
    local ok, cb = pcall(function() return entity.get_control_behavior() end)
    if not ok or not cb or not cb.valid then return data end

    -- Generic inherited circuit settings. Target priority itself is handled
    -- separately through collect_priority_targets().
    pcall(function() data.read_ammo = cb.read_ammo end)
    pcall(function() data.circuit_enable_disable = cb.circuit_enable_disable end)
    pcall(function() data.circuit_condition = cb.circuit_condition end)
    pcall(function() data.connect_to_logistic_network = cb.connect_to_logistic_network end)
    pcall(function() data.logistic_condition = cb.logistic_condition end)
    pcall(function() data.input_networks = cb.input_networks end)
    pcall(function() data.output_networks = cb.output_networks end)

    return data
end

local function restore_turret_control_behavior(entity, data)
    if not data then return end
    local ok, cb = pcall(function() return entity.get_or_create_control_behavior() end)
    if not ok or not cb or not cb.valid then return end

    pcall(function() if data.read_ammo ~= nil then cb.read_ammo = data.read_ammo end end)
    pcall(function() if data.circuit_enable_disable ~= nil then cb.circuit_enable_disable = data.circuit_enable_disable end end)
    pcall(function() if data.circuit_condition ~= nil then cb.circuit_condition = data.circuit_condition end end)
    pcall(function() if data.connect_to_logistic_network ~= nil then cb.connect_to_logistic_network = data.connect_to_logistic_network end end)
    pcall(function() if data.logistic_condition ~= nil then cb.logistic_condition = data.logistic_condition end end)
    pcall(function() if data.input_networks ~= nil then cb.input_networks = data.input_networks end end)
    pcall(function() if data.output_networks ~= nil then cb.output_networks = data.output_networks end end)
end

local function create_replacement(surface, params)
    local ok, entity = pcall(function() return surface.create_entity(params) end)
    if ok and entity then return entity end
    params.quality = nil
    ok, entity = pcall(function() return surface.create_entity(params) end)
    if ok and entity then return entity end
    return nil
end

local function try_builtin_upgrade(entity, target_name, priority_data, control_data)
    if not (entity and entity.valid and target_name and entity.name ~= target_name) then return nil end

    local target = target_name
    local quality = read_quality(entity)
    if quality then
        pcall(function()
            target = { name = target_name, quality = quality.name or quality }
        end)
    end

    local ok_mark, marked = pcall(function()
        return entity.order_upgrade({ target = target, force = entity.force })
    end)
    if not ok_mark or not marked then
        return nil
    end

    local ok_apply, new_entity = pcall(function()
        return entity.apply_upgrade()
    end)

    if ok_apply and new_entity and new_entity.valid then
        restore_turret_control_behavior(new_entity, control_data)
        restore_priority_targets(new_entity, priority_data)
        return new_entity
    end

    pcall(function()
        if entity and entity.valid and entity.cancel_upgrade then
            entity.cancel_upgrade(entity.force)
        end
    end)

    return nil
end

local function replace_turret_fallback(entity, target_name, priority_data, control_data)
    if not (entity and entity.valid and target_name and entity.name ~= target_name) then return nil end

    local surface = entity.surface
    local position = entity.position
    local force = entity.force
    local direction = entity.direction
    local health_ratio = get_health_ratio(entity)
    local quality = read_quality(entity)
    local disabled_by_script = entity.disabled_by_script

    local ammo = collect_inventory(entity, defines.inventory.turret_ammo)
    local fluids = collect_fluidbox(entity)

    local params = {
        name = target_name,
        position = position,
        force = force,
        direction = direction,
        create_build_effect_smoke = false,
        raise_built = false,
    }
    if quality then params.quality = quality end

    entity.destroy({ raise_destroy = false })

    local new_entity = create_replacement(surface, params)
    if not new_entity then return nil end

    if health_ratio then
        pcall(function()
            local max_health = new_entity.max_health
            if max_health and max_health > 0 then
                new_entity.health = math.max(1, math.floor(max_health * health_ratio))
            end
        end)
    end

    if disabled_by_script ~= nil then
        pcall(function() new_entity.disabled_by_script = disabled_by_script end)
    end

    restore_inventory(new_entity, defines.inventory.turret_ammo, ammo)
    restore_fluidbox(new_entity, fluids)
    restore_turret_control_behavior(new_entity, control_data)
    restore_priority_targets(new_entity, priority_data)

    return new_entity
end

local function replace_turret(entity, target_name)
    local priority_data = collect_priority_targets(entity)
    local control_data = collect_turret_control_behavior(entity)

    local upgraded = try_builtin_upgrade(entity, target_name, priority_data, control_data)
    if upgraded then return upgraded end
    return replace_turret_fallback(entity, target_name, priority_data, control_data)
end

function turret_range.apply_to_entity(entity)
    if not (entity and entity.valid and entity.force and entity.force.valid) then return end
    local base_name = base_from_name(entity.name)
    if not base_name then return end

    local level = get_force_level(entity.force)
    local target_name = desired_name(base_name, level)
    if target_name ~= entity.name and prototype_exists(target_name) then
        replace_turret(entity, target_name)
    end
end

function turret_range.apply_to_force(force)
    if not (force and force.valid) then return end
    local names = supported_entity_name_list()
    if #names == 0 then return end

    for _, surface in pairs(game.surfaces) do
        if surface and surface.valid then
            local entities = surface.find_entities_filtered({ name = names, force = force })
            for _, entity in pairs(entities) do
                turret_range.apply_to_entity(entity)
            end
        end
    end
end

function turret_range.apply_to_all_forces()
    for _, force in pairs(game.forces) do
        if force and force.valid and force.name ~= "neutral" and force.name ~= "enemy" then
            turret_range.apply_to_force(force)
        end
    end
end

function turret_range.on_init()
    -- Nothing persistent is required; derive everything from researched technologies.
    -- Synchronise modifiers immediately so newly created saves and forces use the
    -- same turret-specific damage bonus on every hidden range variant.
    sync_all_force_attack_modifiers()
end

function turret_range.on_configuration_changed()
    turret_range.apply_to_all_forces()
    -- Repairs existing saves immediately when updating from an older version.
    sync_all_force_attack_modifiers()
end

function turret_range.on_built(event)
    local entity = event.entity or event.created_entity
    turret_range.apply_to_entity(entity)
end

function turret_range.on_research_finished(event)
    if not (event and event.research and event.research.name and event.research.force) then return end

    -- Range research changes which hidden prototype is used. Any research can
    -- change a turret-attack modifier, so always re-sync after research finishes.
    if event.research.name:find(TECH_PREFIX, 1, true) then
        turret_range.apply_to_force(event.research.force)
    end
    sync_force_attack_modifiers(event.research.force)
end

function turret_range.on_research_reversed(event)
    if not (event and event.research and event.research.name and event.research.force) then return end

    if event.research.name:find(TECH_PREFIX, 1, true) then
        turret_range.apply_to_force(event.research.force)
    end
    sync_force_attack_modifiers(event.research.force)
end

return turret_range
