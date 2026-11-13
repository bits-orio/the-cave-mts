-- The Cave self-contained Space Travel feature flag support.
-- Minimal fallback used only when Space Age is not active.
-- Do NOT create the Space tile-effect shader here; that requires expansion-shader.
if mods["space-age"] then return end

local tile_pollution = require("__base__/prototypes/tile/tile-pollution-values")

if not data.raw.tile["empty-space"] then
    data:extend({{
        name = "empty-space",
        type = "tile",
        order = "z[other]-b[empty-space]",
        subgroup = "special-tiles",
        collision_mask = {
            layers = {
                ground_tile = true,
                water_tile = true,
                empty_space = true,
                resource = true,
                floor = true,
                item = true,
                object = true,
                player = true,
                doodad = true
            },
        },
        layer_group = "zero",
        layer = 0,
        variants = {
            main = {{
                picture = "__the-cave__/graphics/terrain/empty-space.png",
                count = 1,
                size = 1
            }},
            empty_transitions = true
        },
        map_color = {0, 0, 0},
        absorptions_per_second = tile_pollution.out_of_map,
        autoplace = {probability_expression = 1},
        default_cover_tile = data.raw.tile["space-platform-foundation"] and "space-platform-foundation" or nil
    }})
end
