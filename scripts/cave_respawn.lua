local physical = require("scripts.player_physical")
local respawn = {}
local ROOTS = {
    { "the_cave_mineral_caves", "cave_id" },
    { "the_cave_uranium_caves", "cave_id" },
    { "the_cave_lost_city", "city_id" },
    { "the_cave_fortified_vaults", "cave_id" },
}

function respawn.capture(event)
    local player = event and event.player_index and game.get_player(event.player_index)
    local surface = player and player.valid and physical.surface(player)
    if not (surface and surface.valid) then return end
    for _, spec in ipairs(ROOTS) do
        local root = storage[spec[1]]
        local id = root and root.by_surface and root.by_surface[surface.index]
        local record = id and root.by_id[id]
        if record and record.parent_surface_index then
            for _, other in ipairs(ROOTS) do
                local data = storage[other[1]]
                if other ~= spec and data and data.pending_respawns then data.pending_respawns[player.index] = nil end
            end
            root.pending_respawns = root.pending_respawns or {}
            root.pending_respawns[player.index] = root.pending_respawns[player.index] or {
                parent_surface_index = record.parent_surface_index,
                [spec[2]] = id,
            }
            return
        end
    end
end

return respawn
