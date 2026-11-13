-- Armoured Biters 2.0.2 integration for The Cave.
-- Fixed prototype values and Cave-controlled placement deliberately replace the
-- source mod's startup settings and map autoplace. There is no runtime script.
require("prototypes.armoured_biters.animation")
local sounds = require("__base__.prototypes.entity.sounds")
-- The shared base file was removed in 2.1. Keep the integrated AI flags.
local biter_ai_settings = { destroy_when_commands_fail = true, allow_try_return_to_spawner = true }

local small_armoured_scale = 0.5
local small_armoured_tint1 = { r = 0.93, g = 0.94, b = 0.72, a = 0.6 }
local small_armoured_tint2 = { r = 0.90, g = 0.83, b = 0.54, a = 1.0 }

local medium_armoured_scale = 0.65
local medium_armoured_tint1 = { r = 0.49, g = 0.46, b = 0.51, a = 0.8 }
local medium_armoured_tint2 = { r = 0.93, g = 0.72, b = 0.72, a = 1.0 }

local big_armoured_scale = 0.8
local big_armoured_tint1 = { r = 0.53, g = 0.65, b = 0.90, a = 0.8 }
local big_armoured_tint2 = { r = 0.56, g = 0.54, b = 0.98, a = 1.0 }

local behemoth_armoured_scale = 1
local behemoth_armoured_tint1 = { r = 0.41, g = 0.63, b = 0.40, a = 1.0 }
local behemoth_armoured_tint2 = { r = 0.44, g = 1.00, b = 0.29, a = 1.0 }

local make_unit_melee_ammo_type = function(damage_value)
    return {
        target_type = "entity",
        action = {
            type = "direct",
            action_delivery = {
                type = "instant",
                target_effects = {
                    type = "damage",
                    damage = {amount = damage_value, type = "physical"}
                }
            }
        }
    }
end

local function make_biter_area_damage(damage, radius)
    return {
        type = "area",
        radius = radius,
        force = "enemy",
        ignore_collision_condition = true,
        action_delivery = {
            type = "instant",
            target_effects = {
                {
                    type = "damage",
                    damage = {
                        amount = damage,
                        type = "physical"
                    }
                },
                {
                    type = "create-particle",
                    repeat_count = 5,
                    particle_name = "explosion-remnants-particle",
                    initial_height = 0.5,
                    speed_from_center = 0.08,
                    speed_from_center_deviation = 0.15,
                    initial_vertical_speed = 0.08,
                    initial_vertical_speed_deviation = 0.15,
                    offset_deviation = {
                        {
                            -0.2,
                            -0.2
                        },
                        {
                            0.2,
                            0.2
                        }
                    }
                }
            }
        }
    }
end

local function setresistancevalue(initres)
    return math.floor(-100 / (1.25 ^ (initres / 20)) + 100)
end

data:extend(
    {
        {
            type = "unit",
            name = "small-armoured-biter",
            order = "a-a-a",
            icon = "__the-cave__/graphics/armoured-biters/icons/small-armoured-biter.png",
            icon_size = 64,
            flags = {
                "placeable-player",
                "placeable-enemy",
                "placeable-off-grid",
                "breaths-air",
                "not-repairable"
            },
            max_health = 50 * 1,
            subgroup = "enemies",
            resistances = {
                {
                    type = "physical",
                    decrease = 1 * 1,
                    percent = setresistancevalue(10 * 1)
                },
                {
                    type = "explosion",
                    decrease = 2 * 1,
                    percent = setresistancevalue(10 * 1)
                },
                {
                    type = "fire",
                    decrease = 2 * 1,
                    percent = setresistancevalue(10 * 1)
                },
                {
                    type = "laser",
                    decrease = 2 * 1,
                    percent = setresistancevalue(10 * 1)
                }
            },
            healing_per_tick = 0,
            collision_box = {
                {
                    -0.3,
                    -0.3
                },
                {
                    0.3,
                    0.3
                }
            },
            selection_box = {
                {
                    -0.5,
                    -0.8
                },
                {
                    0.5,
                    0.2
                }
            },
            sticker_box = {
                {
                    -0.6,
                    -0.8
                },
                {0.6, 0}
            },
            distraction_cooldown = 300,
            min_pursue_time = 20 * 60,
            max_pursue_distance = 80,
            attack_parameters = {
                type = "projectile",
                range = 1.2,
                cooldown = 80,
                ammo_category = "melee",
                ammo_type = make_unit_melee_ammo_type(20),
                sound = sounds.biter_roars(0.4),
                animation = the_cave_armored_attack_biter(small_armoured_scale, small_armoured_tint1, small_armoured_tint2)
            },
            vision_distance = 30,
            movement_speed = 0.14,
            distance_per_frame = 0.105,
            -- in pu
            absorptions_to_join_attack = {pollution = 10},
            corpse = "small_armoured-corpse",
            dying_explosion = "blood-explosion-big",
            working_sound = sounds.biter_calls(0.4),
            dying_sound = sounds.biter_dying(0.9),
            run_animation = the_cave_armored_run_biter(small_armoured_scale, small_armoured_tint1, small_armoured_tint2),
            ai_settings = biter_ai_settings,
            walking_sound = sounds.biter_walk_big(0.2),
            running_sound_animation_positions = {
                2
            },
            damaged_trigger_effect = table.deepcopy(data.raw["unit"]["small-biter"].damaged_trigger_effect)
        },
        the_cave_add_biter_armoured_die_animation(
            small_armoured_scale,
            small_armoured_tint1,
            small_armoured_tint2,
            {
                type = "corpse",
                name = "small_armoured-corpse",
                icon = "__the-cave__/graphics/armoured-biters/icons/small-armoured-biter.png",
                icon_size = 64,
                selection_box = {
                    {
                        -0.8,
                        -0.8
                    },
                    {
                        0.8,
                        0.8
                    }
                },
                selectable_in_game = false,
                subgroup = "corpses",
                order = "c[corpse]-a[biter]-a[small]",
                flags = {
                    "placeable-neutral",
                    "placeable-off-grid",
                    "building-direction-8-way",
                    "not-repairable",
                    "not-on-map"
                }
            }
        ),
        {
            type = "unit",
            name = "medium-armoured-biter",
            order = "a-a-b",
            icon = "__the-cave__/graphics/armoured-biters/icons/medium-armoured-biter.png",
            icon_size = 64,
            flags = {
                "placeable-player",
                "placeable-enemy",
                "placeable-off-grid",
                "breaths-air",
                "not-repairable"
            },
            max_health = 200 * 1,
            subgroup = "enemies",
            resistances = {
                {
                    type = "physical",
                    decrease = 4 * 1,
                    percent = setresistancevalue(20 * 1)
                },
                {
                    type = "explosion",
                    decrease = 1 * 1,
                    percent = setresistancevalue(10 * 1)
                },
                {
                    type = "fire",
                    decrease = 1 * 1,
                    percent = setresistancevalue(10 * 1)
                },
                {
                    type = "laser",
                    decrease = 4 * 1,
                    percent = setresistancevalue(10 * 1)
                }
            },
            healing_per_tick = 0,
            collision_box = {
                {
                    -0.3,
                    -0.3
                },
                {
                    0.3,
                    0.3
                }
            },
            selection_box = {
                {
                    -0.7,
                    -1.2
                },
                {
                    0.7,
                    0.3
                }
            },
            sticker_box = {
                {
                    -0.6,
                    -0.8
                },
                {0.6, 0}
            },
            distraction_cooldown = 300,
            min_pursue_time = 25 * 60,
            max_pursue_distance = 80,
            attack_parameters = {
                type = "projectile",
                range = 1.5,
                cooldown = 80,
                ammo_category = "melee",
                ammo_type = make_unit_melee_ammo_type(40),
                sound = sounds.biter_roars_mid(0.4),
                animation = the_cave_armored_attack_biter(medium_armoured_scale, medium_armoured_tint1, medium_armoured_tint2)
            },
            vision_distance = 30,
            movement_speed = 0.16,
            distance_per_frame = 0.119,
            -- in pu
            absorptions_to_join_attack = {pollution = 50},
            corpse = "medium-armoured-corpse",
            dying_explosion = "blood-explosion-big",
            working_sound = sounds.biter_calls(0.4),
            dying_sound = sounds.biter_dying(0.9),
            run_animation = the_cave_armored_run_biter(medium_armoured_scale, medium_armoured_tint1, medium_armoured_tint2),
            ai_settings = biter_ai_settings,
            walking_sound = sounds.biter_walk_big(0.4),
            running_sound_animation_positions = {
                2
            },
            damaged_trigger_effect = table.deepcopy(data.raw["unit"]["medium-biter"].damaged_trigger_effect)
        },
        the_cave_add_biter_armoured_die_animation(
            medium_armoured_scale,
            medium_armoured_tint1,
            medium_armoured_tint2,
            {
                type = "corpse",
                name = "medium-armoured-corpse",
                icon = "__the-cave__/graphics/armoured-biters/icons/medium-armoured-biter.png",
                icon_size = 64,
                selection_box = {
                    {
                        -0.8,
                        -0.8
                    },
                    {
                        0.8,
                        0.8
                    }
                },
                selectable_in_game = false,
                subgroup = "corpses",
                order = "c[corpse]-a[biter]-a[small]",
                flags = {
                    "placeable-neutral",
                    "placeable-off-grid",
                    "building-direction-8-way",
                    "not-repairable",
                    "not-on-map"
                }
            }
        ),
        {
            type = "unit",
            name = "big-armoured-biter",
            order = "a-a-c",
            icon = "__the-cave__/graphics/armoured-biters/icons/big-armoured-biter.png",
            icon_size = 64,
            flags = {
                "placeable-player",
                "placeable-enemy",
                "placeable-off-grid",
                "breaths-air",
                "not-repairable"
            },
            max_health = 800 * 1,
            subgroup = "enemies",
            resistances = {
                {
                    type = "physical",
                    decrease = 8 * 1,
                    percent = setresistancevalue(20 * 1)
                },
                {
                    type = "explosion",
                    decrease = 3 * 1,
                    percent = setresistancevalue(15 * 1)
                },
                {
                    type = "fire",
                    decrease = 2 * 1,
                    percent = setresistancevalue(20 * 1)
                },
                {
                    type = "laser",
                    decrease = 6 * 1,
                    percent = setresistancevalue(30 * 1)
                },
                {
                    type = "impact",
                    percent = setresistancevalue(15 * 1)
                }
            },
            spawning_time_modifier = 3,
            healing_per_tick = 0,
            collision_box = {
                {
                    -0.3,
                    -0.3
                },
                {
                    0.3,
                    0.3
                }
            },
            selection_box = {
                {
                    -0.8,
                    -1.4
                },
                {
                    0.8,
                    1
                }
            },
            drawing_box_vertical_extension = 0.3,
            sticker_box = {
                {
                    -0.6,
                    -0.8
                },
                {0.6, 0}
            },
            distraction_cooldown = 300,
            min_pursue_time = 30 * 60,
            max_pursue_distance = 80,
            attack_parameters = {
                type = "projectile",
                range = 1.8,
                cooldown = 80,
                ammo_category = "melee",
                ammo_type = make_unit_melee_ammo_type(80),
                sound = sounds.biter_roars_big(0.4),
                animation = the_cave_armored_attack_biter(big_armoured_scale, big_armoured_tint1, big_armoured_tint2)
            },
            vision_distance = 30,
            movement_speed = 0.18,
            distance_per_frame = 0.136,
            -- in pu
            absorptions_to_join_attack = {pollution = 200},
            corpse = "big-armoured-corpse",
            dying_explosion = "blood-explosion-big",
            working_sound = sounds.biter_calls_big(0.4),
            dying_sound = sounds.biter_dying_big(0.9),
            run_animation = the_cave_armored_run_biter(big_armoured_scale, big_armoured_tint1, big_armoured_tint2),
            ai_settings = biter_ai_settings,
            walking_sound = sounds.biter_walk_big(0.4),
            running_sound_animation_positions = {
                2
            },
            damaged_trigger_effect = table.deepcopy(data.raw["unit"]["big-biter"].damaged_trigger_effect)
        },
        the_cave_add_biter_armoured_die_animation(
            big_armoured_scale,
            big_armoured_tint1,
            big_armoured_tint2,
            {
                type = "corpse",
                name = "big-armoured-corpse",
                icon = "__the-cave__/graphics/armoured-biters/icons/big-armoured-biter.png",
                icon_size = 64,
                selection_box = {
                    {
                        -0.8,
                        -0.8
                    },
                    {
                        0.8,
                        0.8
                    }
                },
                selectable_in_game = false,
                subgroup = "corpses",
                order = "c[corpse]-a[biter]-a[small]",
                flags = {
                    "placeable-neutral",
                    "placeable-off-grid",
                    "building-direction-8-way",
                    "not-repairable",
                    "not-on-map"
                }
            }
        ),
        {
            type = "unit",
            name = "behemoth-armoured-biter",
            order = "a-a-d",
            icon = "__the-cave__/graphics/armoured-biters/icons/behemoth-armoured-biter.png",
            icon_size = 64,
            flags = {
                "placeable-player",
                "placeable-enemy",
                "placeable-off-grid",
                "breaths-air",
                "not-repairable"
            },
            max_health = 6000 * 1,
            subgroup = "enemies",
            resistances = {
                {
                    type = "physical",
                    decrease = 12 * 1,
                    percent = setresistancevalue(30 * 1)
                },
                {
                    type = "explosion",
                    decrease = 12 * 1,
                    percent = setresistancevalue(35 * 1)
                },
                {
                    type = "fire",
                    decrease = 4 * 1,
                    percent = setresistancevalue(35 * 1)
                },
                {
                    type = "laser",
                    decrease = 13 * 1,
                    percent = setresistancevalue(40 * 1)
                },
                {
                    type = "impact",
                    percent = setresistancevalue(35 * 1)
                }
            },
            spawning_time_modifier = 12,
            healing_per_tick = 0,
            collision_box = {
                {
                    -0.4,
                    -0.4
                },
                {
                    0.4,
                    0.4
                }
            },
            selection_box = {
                {
                    -1,
                    -1.6
                },
                {
                    1,
                    1
                }
            },
            drawing_box_vertical_extension = 0.5,
            sticker_box = {
                {
                    -0.6,
                    -0.8
                },
                {0.6, 0}
            },
            distraction_cooldown = 300,
            min_pursue_time = 30 * 60,
            max_pursue_distance = 80,
            attack_parameters = {
                type = "projectile",
                range = 2.2,
                cooldown = 80,
                sound = sounds.biter_roars_behemoth(0.4),
                animation = the_cave_armored_attack_biter(
                    behemoth_armoured_scale,
                    behemoth_armoured_tint1,
                    behemoth_armoured_tint2
                ),
                ammo_category = "melee",
                ammo_type = {
                    target_type = "entity",
                    action = {
                        {
                            action_delivery = {
                                target_effects = {
                                    damage = {
                                        amount = (200),
                                        type = "physical"
                                    },
                                    type = "damage",
                                    show_in_tooltip = true
                                },
                                type = "instant"
                            },
                            type = "direct"
                        },
                        make_biter_area_damage(50, 1)
                    }
                }
            },
            vision_distance = 30,
            movement_speed = 0.2,
            distance_per_frame = 0.17,
            -- in pu
            absorptions_to_join_attack = {pollution = 1000},
            corpse = "behemoth-armoured-corpse",
            dying_explosion = "blood-explosion-big",
            working_sound = sounds.biter_calls_big(0.4),
            dying_sound = sounds.biter_dying_big(0.9),
            run_animation = the_cave_armored_run_biter(behemoth_armoured_scale, behemoth_armoured_tint1, behemoth_armoured_tint2),
            ai_settings = biter_ai_settings,
            walking_sound = sounds.biter_walk_big(0.5),
            running_sound_animation_positions = {
                2
            },
            damaged_trigger_effect = table.deepcopy(data.raw["unit"]["behemoth-biter"].damaged_trigger_effect)
        },
        the_cave_add_biter_armoured_die_animation(
            behemoth_armoured_scale,
            behemoth_armoured_tint1,
            behemoth_armoured_tint2,
            {
                type = "corpse",
                name = "behemoth-armoured-corpse",
                icon = "__the-cave__/graphics/armoured-biters/icons/behemoth-armoured-biter.png",
                icon_size = 64,
                selection_box = {
                    {
                        -0.8,
                        -0.8
                    },
                    {
                        0.8,
                        0.8
                    }
                },
                selectable_in_game = false,
                subgroup = "corpses",
                order = "c[corpse]-a[biter]-a[small]",
                flags = {
                    "placeable-neutral",
                    "placeable-off-grid",
                    "building-direction-8-way",
                    "not-repairable",
                    "not-on-map"
                }
            }
        )
    }
)

local s_r = 1
local m_r = 1
local b_r = 1
local bb_r = 1
-- Keep the source mod's default Leviathan rarity (50%).
local l_r = 0.5

local result_units = {
    {
        "small-armoured-biter",
        {
            {
                0.0,
                0.3 * s_r
            },
            {
                0.6,
                0.0
            }
        }
    },
    {
        "medium-armoured-biter",
        {
            {
                0.2,
                0.0
            },
            {
                0.6,
                0.3 * m_r
            },
            {
                0.7,
                0.1 * m_r
            }
        }
    },
    {
        "big-armoured-biter",
        {
            {
                0.5,
                0.0
            },
            {
                1.0,
                0.4 * b_r
            }
        }
    },
    {
        "behemoth-armoured-biter",
        {
            {
                0.9,
                0.0
            },
            {
                1.0,
                0.3 * bb_r
            }
        }
    }
}

local res_mp = 1
local leviathan_resists = {
    {
        type = "physical",
        decrease = 16 * res_mp,
        percent = setresistancevalue(40 * res_mp)
    },
    {
        type = "explosion",
        decrease = 25 * res_mp,
        percent = setresistancevalue(45 * res_mp)
    },
    {
        type = "fire",
        decrease = 12 * res_mp,
        percent = setresistancevalue(50 * res_mp)
    },
    {
        type = "laser",
        decrease = 16 * res_mp,
        percent = setresistancevalue(60 * res_mp)
    },
    {
        type = "impact",
        percent = setresistancevalue(65 * res_mp)
    }
}

local leviathan_scale = 1.25
local leviathan_tint1 = { r = 0.90, g = 0.23, b = 0.23, a = 0.95 }
local leviathan_tint2 = { r = 0.78, g = 0.84, b = 0.00, a = 0.90 }

if l_r > 0 then
    table.insert(
        result_units,
        {
            "leviathan-armoured-biter",
            {
                {
                    0.965,
                    0.0
                },
                {
                    1.0,
                    0.06 * l_r
                }
            }
        }
    )

    data:extend(
        {
            {
                type = "unit",
                name = "leviathan-armoured-biter",
                order = "a-a-e",
                icon = "__the-cave__/graphics/armoured-biters/icons/leviathan-armoured-biter.png",
                icon_size = 64,
                flags = {
                    "placeable-player",
                    "placeable-enemy",
                    "placeable-off-grid",
                    "breaths-air",
                    "not-repairable"
                },
                max_health = 18000 * 1,
                subgroup = "enemies",
                resistances = leviathan_resists,
                spawning_time_modifier = 12,
                healing_per_tick = 0,
                collision_box = {
                    {
                        -0.4,
                        -0.4
                    },
                    {
                        0.4,
                        0.4
                    }
                },
                selection_box = {
                    {
                        -1,
                        -1.8
                    },
                    {
                        1,
                        1
                    }
                },
                drawing_box_vertical_extension = 0.7,
                sticker_box = {
                    {
                        -0.6,
                        -0.8
                    },
                    {
                        0.6,
                        0
                    }
                },
                distraction_cooldown = 300,
                min_pursue_time = 30 * 60,
                max_pursue_distance = 100,
                attack_parameters = {
                    type = "projectile",
                    range = 2.2,
                    cooldown = 60,
                    sound = sounds.biter_roars_behemoth(1),
                    animation = the_cave_armored_attack_biter(leviathan_scale, leviathan_tint1, leviathan_tint2),
                    ammo_category = "melee",
                    ammo_type = {
                        target_type = "entity",
                        action = {
                            {
                                action_delivery = {
                                    target_effects = {
                                        damage = {
                                            amount = (350),
                                            type = "physical"
                                        },
                                        type = "damage",
                                        show_in_tooltip = true
                                    },
                                    type = "instant"
                                },
                                type = "direct"
                            },
                            make_biter_area_damage(100, 2)
                        }
                    }
                },
                vision_distance = 40,
                movement_speed = 0.3,
                distance_per_frame = 0.17,
                -- in pu
                absorptions_to_join_attack = {pollution = 2000},
                corpse = "leviathan-armoured-corpse",
                dying_explosion = "blood-explosion-big",
                working_sound = sounds.biter_calls_big(1.0),
                dying_sound = sounds.biter_dying_big(1),
                walking_sound = sounds.biter_walk_big(0.8),
                running_sound_animation_positions = {
                    2
                },
                damaged_trigger_effect = table.deepcopy(data.raw["unit"]["behemoth-biter"].damaged_trigger_effect),
                run_animation = the_cave_armored_run_biter(leviathan_scale, leviathan_tint1, leviathan_tint2),
                ai_settings = biter_ai_settings
            },
            the_cave_add_biter_armoured_die_animation(
                leviathan_scale,
                leviathan_tint1,
                leviathan_tint2,
                {
                    type = "corpse",
                    name = "leviathan-armoured-corpse",
                    icon = "__the-cave__/graphics/armoured-biters/icons/leviathan-armoured-biter.png",
                    icon_size = 64,
                    selection_box = {
                        {
                            -2.5,
                            -1.8
                        },
                        {
                            2.5,
                            1.8
                        }
                    },
                    selectable_in_game = false,
                    subgroup = "corpses",
                    order = "c[corpse]-a[biter]-a[small]",
                    flags = {
                        "placeable-neutral",
                        "placeable-off-grid",
                        "building-direction-8-way",
                        "not-repairable",
                        "not-on-map"
                    }
                }
            )
        }
    )
end

local biterSpawner = data.raw["unit-spawner"]["biter-spawner"]

-- Always define the nest prototype, but never give it map autoplace. The Cave
-- places it deterministically only inside suitable Nest Cavern rooms.
do
    local ab_enemy_autoplace = nil

    local nest_tint = {
        r = 0.36,
        g = 0.98,
        b = 0.38,
        a = 1
    }

    data:extend(
        {
            {
                type = "unit-spawner",
                name = "armoured-biter-spawner",
                icon = "__base__/graphics/icons/biter-spawner.png",
                icon_size = 64,
                flags = {
                    "placeable-player",
                    "placeable-enemy",
                    "not-repairable"
                },
                max_health = 650,
                order = "b-b-g",
                subgroup = "enemies",
                resistances = {
                    {
                        type = "explosion",
                        decrease = 5,
                        percent = 25
                    },
                    {
                        type = "fire",
                        decrease = 3,
                        percent = 60
                    },
                    {
                        type = "laser",
                        decrease = 10,
                        percent = 20
                    },
                    {
                        type = "physical",
                        decrease = 4,
                        percent = 20
                    }
                },
                working_sound = {
                    sound = {
                        {
                            filename = "__base__/sound/creatures/spawner.ogg",
                            volume = 1.0
                        }
                    },
                    apparent_volume = 2
                },
                dying_sound = {
                    {
                        filename = "__base__/sound/creatures/spawner-death-1.ogg",
                        volume = 1.0
                    },
                    {
                        filename = "__base__/sound/creatures/spawner-death-2.ogg",
                        volume = 1.0
                    }
                },
                healing_per_tick = 0.02,
                collision_box = {
                    {
                        -3.2,
                        -2.2
                    },
                    {
                        2.2,
                        2.2
                    }
                },
                map_generator_bounding_box = {
                    {
                        -4.2,
                        -3.2
                    },
                    {
                        3.2,
                        3.2
                    }
                },
                selection_box = {
                    {
                        -3.5,
                        -2.5
                    },
                    {
                        2.5,
                        2.5
                    }
                },
                -- in ticks per 1 pu
                absorptions_per_second = {pollution = {absolute = 20, proportional = 0.01}},
                corpse = "armoured-biter-spawner-corpse",
                dying_explosion = "blood-explosion-huge",
                max_count_of_owned_units = 10,
                max_friends_around_to_spawn = 7,
                graphics_set = {
                    animations = {
                        the_cave_armoured_spawner_idle_animation(0, nest_tint)
                    }
                },
                integration = {
                    sheet = the_cave_spawner_armoured_integration()
                },
                result_units = result_units,
                -- With zero evolution the spawn rate is 6 seconds, with max evolution it is 2.5 seconds
                spawning_cooldown = {
                    360,
                    150
                },
                spawning_radius = 10,
                spawning_spacing = 3,
                max_spawn_shift = 0,
                max_richness_for_spawn_shift = 100,
                autoplace = ab_enemy_autoplace,
                damaged_trigger_effect = table.deepcopy(
                    data.raw["unit-spawner"]["biter-spawner"].damaged_trigger_effect
                ),
                call_for_help_radius = 50
            },
            {
                type = "corpse",
                name = "armoured-biter-spawner-corpse",
                flags = {
                    "placeable-neutral",
                    "placeable-off-grid",
                    "not-on-map"
                },
                icon = "__base__/graphics/icons/biter-spawner-corpse.png",
                icon_size = 64,
                collision_box = {
                    {
                        -2,
                        -2
                    },
                    {
                        2,
                        2
                    }
                },
                selection_box = {
                    {
                        -2,
                        -2
                    },
                    {
                        2,
                        2
                    }
                },
                selectable_in_game = false,
                dying_speed = 0.04,
                time_before_removed = 15 * 60 * 60,
                subgroup = "corpses",
                order = "c[corpse]-b[biter-spawner]",
                final_render_layer = "remnants",
                animation = {
                    spawner_die_animation(1, nest_tint)
                },
                decay_animation = spawner_decay_animation(1, nest_tint),
                decay_frame_transition_duration = 6 * 60,
                --[[ ground_patch = {
                    sheet = the_cave_spawner_armoured_integration()
                } ]]
            }
        }
    )
    local armoured_spawner = data.raw["unit-spawner"]["armoured-biter-spawner"]
    armoured_spawner.integration = biterSpawner.integration
    -- Replacing one vanilla nest must not raise the room's autonomous enemy cap.
    armoured_spawner.max_count_of_owned_units = biterSpawner.max_count_of_owned_units
    armoured_spawner.max_friends_around_to_spawn = biterSpawner.max_friends_around_to_spawn
    armoured_spawner.spawning_cooldown = table.deepcopy(biterSpawner.spawning_cooldown)
    armoured_spawner.spawning_radius = biterSpawner.spawning_radius
    armoured_spawner.spawning_spacing = biterSpawner.spawning_spacing
        
    local capture_rocket = mods["space-age"] and data.raw.ammo and data.raw.ammo["capture-robot-rocket"]
    local target_filter = capture_rocket and capture_rocket.ammo_type and capture_rocket.ammo_type.target_filter
    if target_filter then
        table.insert(target_filter, "armoured-biter-spawner")
        armoured_spawner.captured_spawner_entity = "captive-biter-spawner"
    end
end

-- In 2.1, build_base requires an explicit list on every settler prototype.
-- Keep the native tier's worm choices; cave_enemy_expansion already restores
-- each dispatched group's original nest family in on_biter_base_built.
for _, size in ipairs({"small", "medium", "big", "behemoth", "leviathan"}) do
    local unit = data.raw.unit[size .. "-armoured-biter"]
    local base = data.raw.unit[(size == "leviathan" and "behemoth" or size) .. "-biter"]
    if unit and base then
        unit.buildable_entities = table.deepcopy(base.buildable_entities)
    end
end
