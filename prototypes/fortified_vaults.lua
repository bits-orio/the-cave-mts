-- Runtime-only entities for the Fortified Underground Vault raid.
-- These are script-created and intentionally have no item, recipe or blueprint result.

local function clone_portal(source_name, name, localised_name, localised_description, map_color)
    local source = data.raw.container and data.raw.container[source_name]
    if not source then return nil end
    local entity = table.deepcopy(source)
    entity.name = name
    entity.localised_name = localised_name
    entity.localised_description = localised_description
    entity.map_color = map_color
    entity.is_military_target = false
    return entity
end

local prototypes = {}

local function runtime_flags()
    return {
        "placeable-neutral",
        "not-deconstructable",
        "not-blueprintable",
        "not-flammable",
        "hide-alt-info",
    }
end

local pole_source = data.raw["electric-pole"] and data.raw["electric-pole"]["big-electric-pole"]
if pole_source then
    local pole = table.deepcopy(pole_source)
    pole.name = "the-cave-fortified-vault-power-pole"
    pole.localised_name = { "entity-name.the-cave-fortified-vault-power-pole" }
    pole.localised_description = { "entity-description.the-cave-fortified-vault-power-pole" }
    pole.flags = runtime_flags()
    pole.minable = nil
    pole.destructible = false
    pole.is_military_target = false
    pole.fast_replaceable_group = nil
    pole.next_upgrade = nil
    pole.allow_copy_paste = false
    pole.hidden_in_factoriopedia = true
    prototypes[#prototypes + 1] = pole
end

local lamp_source = data.raw.lamp and data.raw.lamp["small-lamp"]
if lamp_source then
    local lamp = table.deepcopy(lamp_source)
    lamp.name = "the-cave-fortified-vault-lamp"
    lamp.localised_name = { "entity-name.the-cave-fortified-vault-lamp" }
    lamp.localised_description = { "entity-description.the-cave-fortified-vault-lamp" }
    lamp.flags = runtime_flags()
    lamp.minable = nil
    lamp.destructible = false
    lamp.is_military_target = false
    lamp.fast_replaceable_group = nil
    lamp.next_upgrade = nil
    lamp.allow_copy_paste = false
    lamp.hidden_in_factoriopedia = true
    prototypes[#prototypes + 1] = lamp
end


local entrance_1 = clone_portal(
    "the-cave-uranium-cave-entrance-1",
    "the-cave-fortified-vault-entrance-1",
    { "entity-name.the-cave-fortified-vault-entrance" },
    { "entity-description.the-cave-fortified-vault-entrance" },
    { r = 0.30, g = 0.12, b = 0.06, a = 1 }
)
if entrance_1 then prototypes[#prototypes + 1] = entrance_1 end

local entrance_2 = clone_portal(
    "the-cave-uranium-cave-entrance-2",
    "the-cave-fortified-vault-entrance-2",
    { "entity-name.the-cave-fortified-vault-entrance" },
    { "entity-description.the-cave-fortified-vault-entrance" },
    { r = 0.30, g = 0.12, b = 0.06, a = 1 }
)
if entrance_2 then prototypes[#prototypes + 1] = entrance_2 end

local exit_1 = clone_portal(
    "the-cave-uranium-cave-exit-1",
    "the-cave-fortified-vault-exit-1",
    { "entity-name.the-cave-fortified-vault-exit" },
    { "entity-description.the-cave-fortified-vault-exit" },
    { r = 0.65, g = 0.22, b = 0.08, a = 1 }
)
if exit_1 then prototypes[#prototypes + 1] = exit_1 end

local exit_2 = clone_portal(
    "the-cave-uranium-cave-exit-2",
    "the-cave-fortified-vault-exit-2",
    { "entity-name.the-cave-fortified-vault-exit" },
    { "entity-description.the-cave-fortified-vault-exit" },
    { r = 0.65, g = 0.22, b = 0.08, a = 1 }
)
if exit_2 then prototypes[#prototypes + 1] = exit_2 end

local function make_cache(name, localised_name, localised_description, tint)
    local source = data.raw.container and data.raw.container["steel-chest"]
    if not source then return nil end
    local entity = table.deepcopy(source)
    entity.name = name
    entity.localised_name = localised_name
    entity.localised_description = localised_description
    entity.flags = {
        "placeable-neutral",
        "not-deconstructable",
        "not-blueprintable",
        "no-automated-item-insertion",
        "no-automated-item-removal",
        "hide-alt-info",
    }
    entity.minable = nil
    entity.destructible = false
    entity.max_health = 2000
    entity.inventory_size = 96
    entity.fast_replaceable_group = nil
    entity.next_upgrade = nil
    entity.allow_copy_paste = false
    entity.hidden_in_factoriopedia = true
    entity.map_color = tint
    entity.is_military_target = false
    if entity.picture and entity.picture.layers then
        for _, layer in pairs(entity.picture.layers) do
            if layer and layer.filename and not layer.draw_as_shadow then
                layer.tint = tint
            end
        end
    elseif entity.picture and entity.picture.filename then
        entity.picture.tint = tint
    end
    return entity
end

local standard = make_cache(
    "the-cave-fortified-cache-standard",
    { "entity-name.the-cave-fortified-cache-standard" },
    { "entity-description.the-cave-fortified-cache-standard" },
    { r = 0.70, g = 0.78, b = 0.90, a = 1 }
)
if standard then prototypes[#prototypes + 1] = standard end

local secure = make_cache(
    "the-cave-fortified-cache-secure",
    { "entity-name.the-cave-fortified-cache-secure" },
    { "entity-description.the-cave-fortified-cache-secure" },
    { r = 0.96, g = 0.68, b = 0.18, a = 1 }
)
if secure then prototypes[#prototypes + 1] = secure end

local high = make_cache(
    "the-cave-fortified-cache-high-security",
    { "entity-name.the-cave-fortified-cache-high-security" },
    { "entity-description.the-cave-fortified-cache-high-security" },
    { r = 0.95, g = 0.18, b = 0.14, a = 1 }
)
if high then prototypes[#prototypes + 1] = high end


local rock_source = data.raw["simple-entity"] and data.raw["simple-entity"]["big-rock"]
if rock_source then
    local rock = table.deepcopy(rock_source)
    rock.name = "the-cave-fortified-vault-rock"
    rock.localised_name = { "entity-name.big-rock" }
    rock.flags = {
        "placeable-neutral",
        "not-deconstructable",
        "not-blueprintable",
        "not-flammable",
    }
    rock.collision_box = { { -0.42, -0.42 }, { 0.42, 0.42 } }
    rock.selection_box = { { -0.48, -0.48 }, { 0.48, 0.48 } }
    rock.minable = {
        mining_time = 0.8,
        results = { { type = "item", name = "stone", amount_min = 1, amount_max = 3 } },
    }
    rock.autoplace = nil
    rock.max_health = 250
    rock.map_color = { r = 0.20, g = 0.16, b = 0.13 }
    rock.hidden_in_factoriopedia = true

    -- Keep the familiar big-rock artwork but shrink it to a one-tile obstacle,
    -- allowing thousands of rocks while leaving navigable gaps between them.
    if rock.pictures then
        for _, picture in pairs(rock.pictures) do
            local layers = picture.layers or { picture }
            for _, layer in pairs(layers) do
                layer.scale = (layer.scale or 1) * 0.55
                if layer.shift then
                    local sx = layer.shift[1] or layer.shift.x or 0
                    local sy = layer.shift[2] or layer.shift.y or 0
                    layer.shift = { sx * 0.55, sy * 0.55 }
                end
            end
        end
    end
    prototypes[#prototypes + 1] = rock
end

if #prototypes > 0 then data:extend(prototypes) end
