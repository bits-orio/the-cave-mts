-- The previous shared research already awarded all three recipes. Preserve
-- those earned unlocks once during upgrade; new and unresearched forces still
-- progress through the three independent stages.
for _, force in pairs(game.forces) do
    local previous = force.technologies["the-cave-roof-support"]
    if previous and previous.researched then
        for _, name in ipairs({"the-cave-roof-support-2", "the-cave-roof-support-3"}) do
            local technology = force.technologies[name]
            if technology then technology.researched = true end
        end
    end
end
