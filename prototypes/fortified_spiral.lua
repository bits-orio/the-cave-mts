-- Invisible, enemy-only boundaries. They exist only in new Fortified interiors.
local layer = "the_cave_fortified_enemy"
local hall_layer = "the_cave_fortified_hall_enemy"
for _, color in ipairs { "green", "yellow", "red" } do
    local tile = table.deepcopy(data.raw.tile[color .. "-refined-concrete"])
    tile.name = "the-cave-fortified-floor-" .. color
    tile.minable = nil
    tile.autoplace = nil
    data:extend({tile})
end
data:extend({
    { type = "collision-layer", name = layer },
    { type = "collision-layer", name = hall_layer },
    {
        type = "simple-entity-with-owner", name = "the-cave-fortified-enemy-boundary",
        flags = { "not-on-map", "not-blueprintable", "not-deconstructable", "not-flammable", "placeable-off-grid" },
        hidden = true, hidden_in_factoriopedia = true, selectable_in_game = false,
        max_health = 1, is_military_target = false,
        collision_box = {{-0.5, -0.5}, {0.5, 0.5}},
        collision_mask = { layers = { [layer] = true } },
        picture = { filename = "__core__/graphics/empty.png", width = 1, height = 1 },
    },
})
local masks = require("__core__/lualib/collision-mask-util")
local blue = table.deepcopy(data.raw.tile["blue-refined-concrete"])
blue.name = "the-cave-fortified-floor-blue"
blue.minable = nil
blue.autoplace = nil
blue.collision_mask = table.deepcopy(masks.get_mask(blue))
blue.collision_mask.layers[hall_layer] = true
data:extend({blue})
-- This extra layer exists only on the new hall floor. Include custom unit
-- families without changing their collisions on any pre-existing surface.
for _, unit in pairs(data.raw.unit) do
    unit.collision_mask = table.deepcopy(masks.get_mask(unit))
    unit.collision_mask.layers[hall_layer] = true
end
for _, size in ipairs { "small", "medium", "big", "behemoth" } do
    for _, kind in ipairs { "biter", "spitter" } do
        local unit = data.raw.unit[size .. "-" .. kind]
        if unit then
            unit.collision_mask = table.deepcopy(masks.get_mask(unit))
            unit.collision_mask.layers[layer] = true
        end
    end
end
