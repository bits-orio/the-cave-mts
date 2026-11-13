-- Version 3.1.59 used one technology to unlock every TNT Box recipe. The same
-- technology name now represents the Small tier so its research state and any
-- in-progress research remain intact. Re-lock the two new higher tiers until
-- their own technologies have actually been researched.
for _, force in pairs(game.forces) do
    local tiers = {
        {
            recipe = "the-cave-tnt-box-small",
            technology = "the-cave-tnt-box",
        },
        {
            recipe = "the-cave-tnt-box-medium",
            technology = "the-cave-tnt-box-medium",
        },
        {
            recipe = "the-cave-tnt-box-large",
            technology = "the-cave-tnt-box-large",
        },
    }

    for _, tier in ipairs(tiers) do
        local recipe = force.recipes[tier.recipe]
        local technology = force.technologies[tier.technology]
        if recipe and technology then
            recipe.enabled = technology.researched
        end
    end
end
