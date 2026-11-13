local variants = require("shared.roof_support")
local prototypes = {}
local graphics = "__the-cave__/graphics/entity/roof-support/"
local icon = "__the-cave__/graphics/technology/roof-support.png"
-- Keep the approved, equally tall artwork at one world scale. Only the
-- progressively reinforced footings change size; PNG originals stay intact.
local pixel_scale = 128 / 750
local frames = {
    {x = 268, right = 670, y = 10, height = 765, anchor_x = 470, anchor_y = 675,
        shadow_right = 1380, shadow_y = 440, shadow_height = 335, file = "small.png"},
    {x = 190, right = 780, y = 10, height = 775, anchor_x = 483, anchor_y = 660,
        shadow_right = 1410, shadow_y = 440, shadow_height = 345, file = "medium.png"},
    {x = 130, right = 910, y = 10, height = 775, anchor_x = 523, anchor_y = 658,
        shadow_right = 1410, shadow_y = 440, shadow_height = 345, file = "large.png"},
}

local function sprite_frame(frame, shadow)
    local x = shadow and frame.right or frame.x
    local y = shadow and frame.shadow_y or frame.y
    local width = shadow and (frame.shadow_right - x) or (frame.right - x)
    local height = shadow and frame.shadow_height or frame.height
    return {filename = graphics .. frame.file, x = x, y = y, width = width, height = height,
        scale = pixel_scale,
        shift = {(x + width / 2 - frame.anchor_x) * pixel_scale / 32,
            (y + height / 2 - frame.anchor_y) * pixel_scale / 32},
        draw_as_shadow = shadow, priority = "high"}
end

-- Generated body atlases keep their upright north/east bodies in the top
-- row. Short opaque shadows use a separate atlas below. Opposite views share
-- artwork; the engine changes frames rather than rotating the bitmap flat.
local atlas_frames = {
    [2] = {file = "medium-rotatable.png", cell = 627, scale = 0.224,
        north = {column = 0, anchor_x = 299, anchor_y = 545, shadow_x = 217, shadow_y = 450},
        east = {column = 1, anchor_x = 313, anchor_y = 545, shadow_x = 224, shadow_y = 450}},
    [3] = {file = "large-rotatable.png", scale = 0.224,
        north = {body = {x = 795, y = 80, width = 328, height = 585, anchor_x = 959, anchor_y = 590},
            shadow = {x = 799, y = 812, width = 360, height = 367, anchor_x = 941, anchor_y = 1100}},
        east = {body = {x = 64, y = 80, width = 578, height = 585, anchor_x = 353, anchor_y = 590},
            shadow = {x = 75, y = 812, width = 567, height = 367, anchor_x = 313, anchor_y = 1100}}},
}

-- Opaque masks let Factorio apply its normal surface shadow opacity once.
-- Repeating translucent shadow layers does not increase the engine mask.
local shadow_frames = {
    [1] = {north = {column = 0, row = 0, x = 210, y = 330, scale = 0.35}},
    [2] = {north = {column = 1, row = 0, x = 200, y = 330, scale = 0.35},
        east = {column = 2, row = 0, x = 220, y = 330, scale = 0.35}},
    [3] = {north = {column = 0, row = 1, x = 200, y = 304, scale = 0.35},
        east = {column = 1, row = 1, x = 240, y = 310, scale = 0.4}},
}

local function shadow_sprite(frame)
    return {filename = graphics .. "shadows-rotatable.png", x = frame.column * 512,
        y = frame.row * 512, width = 512, height = 512, scale = frame.scale,
        draw_as_shadow = true, priority = "high",
        shift = {(256 - frame.x) * frame.scale / 32, (256 - frame.y) * frame.scale / 32}}
end

local function atlas_view(atlas, view, shadow_frame)
    local function layer(shadow)
        if not atlas.cell then
            local frame = shadow and view.shadow or view.body
            return {filename = graphics .. atlas.file, x = frame.x, y = frame.y,
                width = frame.width, height = frame.height, scale = atlas.scale,
                priority = "high", draw_as_shadow = shadow,
                shift = {(frame.x + frame.width / 2 - frame.anchor_x) * atlas.scale / 32,
                    (frame.y + frame.height / 2 - frame.anchor_y) * atlas.scale / 32}}
        end
        local anchor_x = shadow and view.shadow_x or view.anchor_x
        local anchor_y = shadow and view.shadow_y or view.anchor_y
        return {filename = graphics .. atlas.file, x = view.column * atlas.cell,
            y = shadow and atlas.cell or 0, width = atlas.cell, height = atlas.cell,
            scale = atlas.scale, priority = "high", draw_as_shadow = shadow,
            shift = {(atlas.cell / 2 - anchor_x) * atlas.scale / 32,
                (atlas.cell / 2 - anchor_y) * atlas.scale / 32}}
    end
    return {layers = {layer(false), shadow_sprite(shadow_frame)}}
end

for i, variant in ipairs(variants) do
    local half_width, half_height = variant.width / 2, variant.height / 2
    local description = {"entity-description.the-cave-roof-support", tostring(variant.area), tostring(variant.area)}
    local picture = {layers = {sprite_frame(frames[1], false), shadow_sprite(shadow_frames[1].north)}}
    local flags = {"placeable-neutral", "player-creation"}
    if variant.rotatable then
        local atlas = atlas_frames[i]
        local north = atlas_view(atlas, atlas.north, shadow_frames[i].north)
        local east = atlas_view(atlas, atlas.east, shadow_frames[i].east)
        picture = {north = north, east = east, south = table.deepcopy(north), west = table.deepcopy(east)}
    else
        flags[#flags + 1] = "not-rotatable"
    end
    prototypes[#prototypes + 1] = {
        type = "simple-entity-with-owner", name = variant.name,
        icon = icon, icon_size = 1254,
        localised_description = description,
        flags = flags,
        -- scripts.roof_support_mining fixes effective character speed at 0.5.
        -- A tiny epsilon avoids an extra tick from floating-point accumulation.
        minable = {mining_time = 2.5 - 0.000001, result = variant.name},
        max_health = 200, impact_category = "metal",
        tile_width = variant.width, tile_height = variant.height,
        collision_box = {{-half_width + 0.2, -half_height + 0.2}, {half_width - 0.2, half_height - 0.2}},
        selection_box = {{-half_width, -half_height}, {half_width, half_height}},
        drawing_box_vertical_extension = 4,
        render_layer = "object", picture = picture,
        radius_visualisation_specification = {
            -- The same native blue square used by vanilla substations, without
            -- changing the entity into a pole or adding electricity or wires.
            sprite = table.deepcopy(data.raw["electric-pole"].substation.radius_visualisation_picture),
            distance = variant.area / 2,
            offset = {variant.width % 2 == 1 and -0.5 or 0, variant.height % 2 == 1 and -0.5 or 0},
            draw_in_cursor = true, draw_on_selection = false,
        },
    }
    prototypes[#prototypes + 1] = {
        type = "item", name = variant.name,
        icon = icon, icon_size = 1254,
        subgroup = "defensive-structure", order = "z[roof-support]-" .. i,
        place_result = variant.name, stack_size = 50,
        localised_description = description,
    }
    prototypes[#prototypes + 1] = {
        type = "recipe", name = variant.name, enabled = false, categories = {"crafting"},
        energy_required = variant.seconds,
        ingredients = {
            {type = "item", name = "steel-plate", amount = variant.plates},
            {type = "item", name = "iron-plate", amount = variant.plates},
        },
        results = {{type = "item", name = variant.name, amount = 1}},
    }
end

local collapse = settings.startup["the-cave-collapse-mode"].value == "enabled"
for i, variant in ipairs(variants) do
    local ingredients = {}
    for _, science in ipairs(variant.science) do ingredients[#ingredients + 1] = {science, 1} end
    prototypes[#prototypes + 1] = {
        type = "technology", name = variant.technology,
        localised_name = {"technology-name." .. variant.technology},
        localised_description = {"technology-description." .. variant.technology},
        -- Retain the approved transparent research icon for all three stages.
        icon = icon, icon_size = 1254,
        enabled = collapse, visible_when_disabled = false,
        prerequisites = {i == 1 and "steel-processing" or variants[i - 1].technology},
        effects = {{type = "unlock-recipe", recipe = variant.name}},
        unit = {count = variant.research_count, time = 30, ingredients = ingredients},
        order = "a-f-b[roof-support]-" .. i,
    }
end
data:extend(prototypes)
