-- Train Wave Defense units.
--
-- Private prototype names keep scheduled attackers isolated from The Cave's
-- direct-dig enemies and Brood Split tables. Bosses reuse vanilla artwork but
-- are deliberately much larger, slower and tougher than ordinary enemies.

local PREFIX = "the-cave-train-wave-"
local BOSS_ATTACK_DAMAGE = 200
local prototypes_to_add = {}

local function scale_vector(vector, factor)
    if type(vector) ~= "table" then return vector end
    if vector.x ~= nil or vector.y ~= nil then
        return {
            x = (tonumber(vector.x) or tonumber(vector[1]) or 0) * factor,
            y = (tonumber(vector.y) or tonumber(vector[2]) or 0) * factor,
        }
    end
    return {
        (tonumber(vector[1]) or 0) * factor,
        (tonumber(vector[2]) or 0) * factor,
    }
end

local function scale_box(box, factor)
    if type(box) ~= "table" or type(box[1]) ~= "table" or type(box[2]) ~= "table" then return box end
    return { scale_vector(box[1], factor), scale_vector(box[2], factor) }
end

local DIRECTION_KEYS = {
    "north", "north_east", "east", "south_east",
    "south", "south_west", "west", "north_west",
}

-- Rotated animations can be a leaf sprite, layers, an array of variations or
-- an eight-way direction table. Scale only leaf sprites so nested layers are
-- never multiplied twice.
local function scale_animation(animation, factor)
    if type(animation) ~= "table" then return end

    if animation.filename or animation.filenames or animation.stripes then
        animation.scale = (tonumber(animation.scale) or 1) * factor
        if animation.shift then animation.shift = scale_vector(animation.shift, factor) end
        return
    end

    if type(animation.layers) == "table" then
        for _, layer in pairs(animation.layers) do scale_animation(layer, factor) end
    end

    local found_direction = false
    for _, key in ipairs(DIRECTION_KEYS) do
        if type(animation[key]) == "table" then
            found_direction = true
            scale_animation(animation[key], factor)
        end
    end

    if not found_direction and #animation > 0 then
        for _, variation in ipairs(animation) do scale_animation(variation, factor) end
    end
end

-- Bosses keep the copied Biter attack category, range, animation and damage
-- type. Only the physical amount is replaced, so every explicit blocker and
-- final Train/Shelter attack uses the same locked 200-damage strike.
local function set_attack_damage(node)
    if type(node) ~= "table" then return end
    if node.type == "damage" and type(node.damage) == "table" then
        node.damage.amount = BOSS_ATTACK_DAMAGE
    end
    for _, child in pairs(node) do
        if type(child) == "table" then set_attack_damage(child) end
    end
end

local function copy_unit(base_name, new_name, localised_name)
    local source = data.raw.unit and data.raw.unit[base_name]
    if not source then return nil end

    local unit = table.deepcopy(source)
    unit.name = new_name
    unit.localised_name = localised_name or { "entity-name." .. base_name }
    unit.autoplace = nil
    unit.hidden_in_factoriopedia = true
    unit.order = "z[the-cave-train-wave]-" .. new_name
    prototypes_to_add[#prototypes_to_add + 1] = unit
    return unit
end

for _, tier in ipairs({ "small", "medium", "big", "behemoth" }) do
    copy_unit(tier .. "-biter", PREFIX .. tier .. "-biter")
    copy_unit(tier .. "-spitter", PREFIX .. tier .. "-spitter")
end

local boss_corpses = {}

local function boss_corpse_for(source_unit, tier)
    local source_name = source_unit and source_unit.corpse
    if type(source_name) ~= "string" then return source_name end
    if boss_corpses[source_name] then return boss_corpses[source_name] end

    local source = data.raw.corpse and data.raw.corpse[source_name]
    if not source then return source_name end

    local corpse = table.deepcopy(source)
    corpse.name = PREFIX .. "boss-" .. tier .. "-biter-corpse"
    corpse.localised_name = { "the-cave-train-wave.boss-name" }
    corpse.hidden_in_factoriopedia = true
    scale_animation(corpse.animation, 2)
    scale_animation(corpse.animation_overlay, 2)
    scale_animation(corpse.decay_animation, 2)
    prototypes_to_add[#prototypes_to_add + 1] = corpse
    boss_corpses[source_name] = corpse.name
    return corpse.name
end

-- Eleven evolution-driven Boss levels: 3x health at level 1, +0.5x per
-- level, capped at 8x. The visual is 2x vanilla size, while collision grows
-- only 1.35x so the Boss can still path through carved cave corridors.
-- Legacy big-Biter Boss names are retained for save compatibility; all newly
-- spawned Bosses use the Behemoth visual family.
for _, tier in ipairs({ "big", "behemoth" }) do
    local source = data.raw.unit and data.raw.unit[tier .. "-biter"]
    if source then
        local corpse_name = boss_corpse_for(source, tier)
        for level = 1, 11 do
            local multiplier = math.min(8, 3 + (level - 1) * 0.5)
            local name = PREFIX .. "boss-" .. tier .. "-biter-l" .. level
            local boss = copy_unit(tier .. "-biter", name, { "the-cave-train-wave.boss-name" })
            if boss then
                boss.max_health = math.max(1, math.floor((source.max_health or 1) * multiplier + 0.5))
                boss.movement_speed = (source.movement_speed or boss.movement_speed or 0.1) * 0.65
                if boss.attack_parameters and boss.attack_parameters.cooldown then
                    boss.attack_parameters.cooldown = math.max(1, math.ceil(boss.attack_parameters.cooldown / 0.80))
                end
                if boss.attack_parameters then
                    set_attack_damage(boss.attack_parameters.ammo_type)
                end

                scale_animation(boss.run_animation, 2)
                if boss.attack_parameters then scale_animation(boss.attack_parameters.animation, 2) end
                boss.collision_box = scale_box(source.collision_box, 1.35)
                boss.selection_box = scale_box(source.selection_box, 1.75)
                boss.sticker_box = scale_box(source.sticker_box or source.collision_box, 1.50)
                boss.hit_visualization_box = scale_box(source.hit_visualization_box or source.selection_box, 1.75)
                boss.drawing_box_vertical_extension = (tonumber(source.drawing_box_vertical_extension) or 0) + 3
                boss.shooting_cursor_size = (tonumber(source.shooting_cursor_size) or 1) * 1.75
                boss.corpse = corpse_name
            end
        end
    end
end

if #prototypes_to_add > 0 then data:extend(prototypes_to_add) end
