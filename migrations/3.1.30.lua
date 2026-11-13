-- Rebase only the previously scheduled 60-to-4-minute expansion timestamp.
-- The runtime will schedule the new 10-to-2-minute interval on its next
-- five-second check while preserving sequence and pending settler migrations.
local expansion = storage and storage.the_cave_vanilla_enemy_expansion
for _, surface_state in pairs(expansion and expansion.surfaces or {}) do
    if type(surface_state) == "table" then surface_state.next_tick = nil end
end
