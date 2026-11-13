-- Keep the native blast and combat damage. Only report its start and protect
-- Cave terrain from native crater tiles; other surfaces replay the same tiles.
local projectile = data.raw.projectile and data.raw.projectile["atomic-rocket"]
if not projectile then return end

local serial = 0
local additions = {}
local function wrap_terrain_effects(value, prototype)
    if type(value) ~= "table" then return end
    for key, effect in pairs(value) do
        if type(effect) == "table" then
            if effect.type == "set-tile" then
                serial = serial + 1
                local original = table.deepcopy(prototype)
                original.name = "the-cave-atomic-terrain-" .. serial
                original.created_effect = {type = "direct", action_delivery = {
                    type = "instant", target_effects = table.deepcopy(effect)}}
                additions[#additions + 1] = original
                value[key] = {type = "script", effect_id = original.name}
            else
                wrap_terrain_effects(effect, prototype)
            end
        end
    end
end
for _, name in ipairs {"nuke-effects-nauvis", "nuke-effects-vulcanus", "nuke-effects-aquilo"} do
    local prototype = data.raw.explosion and data.raw.explosion[name]
    if prototype then wrap_terrain_effects(prototype.created_effect, prototype) end
end
if #additions > 0 then data:extend(additions) end

local function mark_impact(action)
    if type(action) ~= "table" then return end
    if action.type then
        local delivery = action.action_delivery
        if delivery and delivery.type == "instant" then
            local effects = delivery.target_effects or {}
            if effects.type then effects = {effects} end
            table.insert(effects, 1, {type = "script", effect_id = "the-cave-atomic-blast-start"})
            delivery.target_effects = effects
        end
    else
        for _, entry in ipairs(action) do mark_impact(entry) end
    end
end
mark_impact(projectile.action)

-- A script mark immediately before each atomic damage effect also handles
-- engine events where the optional direct projectile source is unavailable.
local function mark_damage(value)
    if type(value) ~= "table" then return end
    for key, child in pairs(value) do
        if type(child) == "table" then
            if child.type == "instant" and child.target_effects then
                local effects = child.target_effects
                if effects.type then effects = {effects} end
                for i = #effects, 1, -1 do
                    if effects[i].type == "damage" then
                        table.insert(effects, i, {type = "script", effect_id = "the-cave-atomic-rock-hit"})
                    end
                end
                child.target_effects = effects
            else mark_damage(child) end
        end
    end
end
for _, name in ipairs {"atomic-rocket", "atomic-bomb-wave", "atomic-bomb-ground-zero-projectile"} do
    local p = data.raw.projectile[name]
    if p then mark_damage({p.action}) end
end
