-- Standalone Lost City building prototypes adapted from Old Abandoned
-- Settlements by SacredAnarchy. The original source names are prefixed and the
-- prototypes are restricted to scripted Lost City placement so they cannot
-- collide with, or leak into, another ruin mod's normal gameplay.

for i = 1, 18 do
    require("prototypes.lost_city_houses.house" .. i)
end

local HOUSE_PREFIX = "the-cave-lost-city-house"

for name, entity in pairs(data.raw.container or {}) do
    if name:sub(1, #HOUSE_PREFIX) == HOUSE_PREFIX then
        entity.localised_name = { "the-cave-lost-city.abandoned-building" }
        entity.localised_description = { "the-cave-lost-city.abandoned-building-description" }
        entity.flags = {
            "placeable-neutral",
            "placeable-off-grid",
            "not-blueprintable",
            "hide-alt-info",
        }
        entity.minable = { mining_time = 4 }
        entity.destructible = true
        entity.inventory_size = 48
        entity.hidden_in_factoriopedia = true
        entity.fast_replaceable_group = nil
        entity.next_upgrade = nil
    end
end
