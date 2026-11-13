-- Native assembler inventories, modules, beacons and electrical drain; only
-- independent Market sales and their work/energy accounting are scripted.
-- No item is held in script storage: mining/removal uses native inventories.
local M = {}
local NAME = "the-cave-coin-maker"
local OFFERS = require("shared.market_sell_offers")
local INTERVAL = 6
local WORK_PER_DEAL = 120 -- ticks at normal quality, without modules/beacons
local BASE_SPEED = 1.25
local WORK_JOULES_PER_TICK = 1500000 / 60

local function state()
    storage.coin_maker = storage.coin_maker or {machines = {}}
    return storage.coin_maker
end

local function status(record, key, item)
    if record.status == key and record.status_item == item then return end
    record.status, record.status_item = key, item
    record.entity.custom_status = {
        diode = key == "working" and defines.entity_status_diode.green or defines.entity_status_diode.yellow,
        label = {"coin-maker-status." .. key, item and prototypes.item[item].localised_name or ""}
    }
end

function M.on_built(event)
    local entity = event.entity or event.created_entity or event.destination
    if not (entity and entity.valid and entity.name == NAME and entity.unit_number) then return end
    local machines = state().machines
    -- Disabling native crafting is mandatory: the fixed recipe is an input
    -- filter/catalogue, not a recipe requiring every sale item at once.
    entity.disabled_by_script = true
    if not machines[entity.unit_number] then
        machines[entity.unit_number] = {entity = entity, progress = 0, next_offer = 1}
        entity.crafting_progress = 0
        status(machines[entity.unit_number], "waiting")
    end
end

function M.on_configuration_changed()
    local s = state()
    for id, record in pairs(s.machines) do
        if not (record.entity and record.entity.valid) then s.machines[id] = nil end
    end
    -- Once on init/configuration only, and filtered to this prototype. Ordinary
    -- play registers builds/clones and never searches surfaces on a tick.
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{name = NAME}) do
            M.on_built{entity = entity}
        end
    end
    for _, force in pairs(game.forces) do
        local recipe, tech = force.recipes[NAME], force.technologies[NAME]
        if recipe and tech then recipe.enabled = tech.researched end
    end
end
M.on_init = M.on_configuration_changed

local function choose_offer(record, input, output)
    local contents = input.get_contents()
    local counts = {}
    for _, stack in pairs(contents) do
        if stack.quality == "normal" then counts[stack.name] = (counts[stack.name] or 0) + stack.count end
    end
    local space = output.get_insertable_count{name = "coin", quality = "normal"}
    local blocked = false
    for offset = 0, #OFFERS - 1 do
        local index = (record.next_offer - 1 + offset) % #OFFERS + 1
        local offer = OFFERS[index]
        if (counts[offer[1]] or 0) >= offer[2] then
            if space >= offer[3] then return index end
            blocked = true
        end
    end
    return nil, blocked
end

local function process(record)
    local entity = record.entity
    -- Respect circuit stops, freezing and deconstruction despite using a script
    -- disable to prevent native all-ingredient crafting.
    if entity.disabled_by_control_behavior or entity.frozen or entity.to_be_deconstructed() then
        status(record, "stopped"); return
    end
    local input = entity.get_inventory(defines.inventory.crafter_input)
    local output = entity.get_output_inventory()
    if not (input and input.valid and output and output.valid) then return end
    local budget = INTERVAL
    while budget > 0.000001 do
        local offer = record.offer and OFFERS[record.offer]
        if offer and (not prototypes.item[offer[1]] or input.get_item_count{name = offer[1], quality = "normal"} < offer[2]) then
            record.offer, record.progress, offer = nil, 0, nil
            entity.crafting_progress = 0
        end
        if not offer then
            local blocked
            record.offer, blocked = choose_offer(record, input, output)
            if not record.offer then status(record, blocked and "output-full" or "waiting"); return end
            offer = OFFERS[record.offer]
        end
        if output.get_insertable_count{name = "coin", quality = "normal"} < offer[3] then
            status(record, "output-full"); return
        end
        -- Read native final bonuses, including quality, beacon profiles and
        -- efficiency's native floor. No module coefficients are duplicated.
        local speed = entity.crafting_speed / BASE_SPEED
        local cost_per_tick = WORK_JOULES_PER_TICK * (1 + entity.consumption_bonus)
        local remaining_ticks = (WORK_PER_DEAL - record.progress) / speed
        local work_ticks = math.min(budget, remaining_ticks, entity.energy / cost_per_tick)
        if work_ticks <= 0 then status(record, "no-power"); return end
        local energy = work_ticks * cost_per_tick
        entity.energy = math.max(0, entity.energy - energy)
        record.progress = math.min(WORK_PER_DEAL, record.progress + work_ticks * speed)
        entity.crafting_progress = math.min(0.999999, record.progress / WORK_PER_DEAL)
        status(record, "working", offer[1])
        local pollutant = entity.surface.pollutant_type
        local coefficient = pollutant and (entity.electric_emissions_per_joule or {})[pollutant.name] or 0
        if coefficient > 0 then
            entity.surface.pollute(entity.position, energy * coefficient * (1 + entity.pollution_bonus), NAME)
        end
        budget = budget - work_ticks
        if record.progress + 0.000001 < WORK_PER_DEAL then return end
        -- One synchronous transaction. Never consume goods without room for
        -- their exact payment. Inputs remain in native inventory until here.
        local removed = input.remove{name = offer[1], count = offer[2], quality = "normal"}
        local inserted = 0
        if removed == offer[2] then inserted = output.insert{name = "coin", count = offer[3], quality = "normal"} end
        if removed ~= offer[2] or inserted ~= offer[3] then
            if inserted > 0 then output.remove{name = "coin", count = inserted, quality = "normal"} end
            if removed > 0 then assert(input.insert{name = offer[1], count = removed, quality = "normal"} == removed) end
            status(record, "output-full"); return
        end
        local stats = entity.force.get_item_production_statistics(entity.surface)
        stats.on_flow({name = offer[1], quality = "normal"}, -removed)
        stats.on_flow({name = "coin", quality = "normal"}, inserted)
        entity.products_finished = entity.products_finished + 1
        record.next_offer = record.offer % #OFFERS + 1
        record.offer, record.progress = nil, 0
        entity.crafting_progress = 0
    end
end

function M.on_nth_tick()
    local s = storage.coin_maker
    if not s then return end
    for id, record in pairs(s.machines) do
        if not (record.entity and record.entity.valid) then
            s.machines[id] = nil
        else
            process(record)
        end
    end
end
return M
