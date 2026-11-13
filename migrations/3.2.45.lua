-- Scrap now uses ordinary solid-resource mining. Existing drills may retain
-- their old resource connections, especially burners that could not mine scrap
-- before this upgrade. Refresh only drills covering The Cave Scrap, once.
local scrap = "the-cave-scrap-resource"
for _, surface in pairs(game.surfaces) do
    if surface.find_entities_filtered { name = scrap, limit = 1 }[1] then
        for _, drill in pairs(surface.find_entities_filtered { type = "mining-drill" }) do
            if surface.find_entities_filtered { name = scrap, area = drill.mining_area, limit = 1 }[1] then
                drill.update_connections()
            end
        end
    end
end
