-- Enemy Brood Split.
-- Killed vanilla Biters and Spitters release exactly one unit from the next
-- smaller vanilla tier. Released units continue the chain but never award
-- Coins or Ore Blood, so one original enemy still grants only one reward.

local brood = {}

local CHILD_BY_PARENT = {
    ["behemoth-biter"] = "big-biter",
    ["big-biter"] = "medium-biter",
    ["medium-biter"] = "small-biter",

    ["behemoth-spitter"] = "big-spitter",
    ["big-spitter"] = "medium-spitter",
    ["medium-spitter"] = "small-spitter",
}

for name,base in pairs(require("shared.fortified_combat").offspring_aliases) do
    CHILD_BY_PARENT[name]=CHILD_BY_PARENT[base]
end

local NO_REWARD_STORAGE = "the_cave_enemy_brood_no_reward"
local DESTROY_REGISTRATION_STORAGE = "the_cave_enemy_brood_destroy_registrations"

local function ensure_storage()
    storage[NO_REWARD_STORAGE] = storage[NO_REWARD_STORAGE] or {}
    storage[DESTROY_REGISTRATION_STORAGE] = storage[DESTROY_REGISTRATION_STORAGE] or {}
    return storage[NO_REWARD_STORAGE], storage[DESTROY_REGISTRATION_STORAGE]
end

local function mark_released_unit(entity)
    if not (entity and entity.valid and entity.unit_number) then return end

    local no_reward, destroy_registrations = ensure_storage()
    no_reward[entity.unit_number] = true

    local registration_number = script.register_on_object_destroyed(entity)
    if registration_number then
        destroy_registrations[registration_number] = entity.unit_number
    end
end

local function safe_spawn_child(parent, child_name)
    local surface = parent.surface
    if not (surface and surface.valid) then return nil end

    local force = parent.force
    if not (force and force.valid) then return nil end

    -- Use the same proven unit-spawn path as The Cave's other enemy systems.
    -- find_non_colliding_position already checks the unit's collision box, so a
    -- second building-style can_place_entity check can incorrectly reject a
    -- valid runtime unit position and silently cancel every brood spawn.
    local ok_position, position = pcall(function()
        return surface.find_non_colliding_position(
            child_name,
            parent.position,
            6,
            0.5,
            true
        )
    end)
    if not ok_position or not position then return nil end

    local ok_create, child = pcall(function()
        return surface.create_entity {
            name = child_name,
            position = position,
            force = force,
        }
    end)
    if not ok_create then return nil end

    if child and child.valid then
        mark_released_unit(child)
        return child
    end
    return nil
end

function brood.on_init()
    ensure_storage()
end

function brood.on_configuration_changed()
    ensure_storage()
end

-- Returns true only when the killed entity was itself released by this system.
-- control.lua passes the result to the existing Coin and Ore Blood handlers.
function brood.on_entity_died(event)
    local entity = event and event.entity
    if not (entity and entity.valid) then return false end

    local no_reward = ensure_storage()
    local unit_number = entity.unit_number
    local suppress_rewards = unit_number and no_reward[unit_number] == true or false
    if unit_number then
        no_reward[unit_number] = nil
    end

    local child_name = CHILD_BY_PARENT[entity.name]
    if child_name then
        safe_spawn_child(entity, child_name)
    end

    return suppress_rewards
end

-- Covers script removal, surface deletion and every other non-death removal.
-- It prevents stale unit-number records from accumulating in long-running saves.
function brood.on_object_destroyed(event)
    if not (event and event.registration_number) then return end

    local no_reward, destroy_registrations = ensure_storage()
    local unit_number = destroy_registrations[event.registration_number]
    if not unit_number then return end

    destroy_registrations[event.registration_number] = nil
    no_reward[unit_number] = nil
end

return brood
