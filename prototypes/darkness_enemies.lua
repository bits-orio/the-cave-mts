-- Infestation units must reach the player in Fortified's hall. Room defenders
-- keep their native hall and doorway collision layers.
local variants = {}
for _, size in ipairs { "small", "medium", "big", "behemoth" } do
    for _, kind in ipairs { "biter", "spitter" } do
        local name = size .. "-" .. kind
        local original = data.raw.unit[name]
        if original then
            local unit = table.deepcopy(original)
            unit.name = "the-cave-darkness-" .. name
            unit.localised_name = original.localised_name or { "entity-name." .. name }
            unit.hidden_in_factoriopedia = true
            unit.collision_mask.layers.the_cave_fortified_hall_enemy = nil
            unit.collision_mask.layers.the_cave_fortified_enemy = nil
            variants[#variants + 1] = unit
        end
    end
end
data:extend(variants)
