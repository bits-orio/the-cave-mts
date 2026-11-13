function the_cave_add_biter_armoured_die_animation(scale, tint1, tint2, corpse)
    corpse.animation = the_cave_biterarmoureddieanimation(scale, tint1, tint2)
    corpse.decay_frame_transition_duration = 6 * 60
    corpse.use_decay_layer = true
    corpse.dying_speed = (1 / 25) * (0.25 + 0.1 / scale)
    corpse.time_before_removed = 5 * 60 * 60
    corpse.direction_shuffle = {{1, 2, 3, 16}, {4, 5, 6, 7}, {8, 9, 10, 11}, {12, 13, 14, 15}}
    corpse.shuffle_directions_at_frame = 0
    corpse.final_render_layer = "lower-object-above-shadow"

    corpse.ground_patch_render_layer = "decals" -- "transport-belt-integration"
    corpse.ground_patch_fade_in_delay = 1 / 0.02 -- in ticks; 1/dying_speed to delay the animation until dying animation finishes
    corpse.ground_patch_fade_in_speed = 0.002
    corpse.ground_patch_fade_out_start = 1 * 60
    corpse.ground_patch_fade_out_duration = 60 * 60

    local a = 1
    local d = 0.9
    corpse.ground_patch = {
        sheet = {
            filename = "__base__/graphics/entity/biter/blood-puddle-var-main.png",
            flags = {"low-object"},
            line_length = 4,
            variation_count = 4,
            frame_count = 1,
            width = 164,
            height = 134,
            shift = util.by_pixel(-0.5, -0.5),
            tint = {r = 0.6 * d * a, g = 0.1 * d * a, b = 0.6 * d * a, a = a},
            scale = 0.5 * scale
        }
    }
    return corpse
end

function the_cave_biterarmoureddieanimation(scale, tint1, tint2)
    return {
        layers = {
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-04.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-05.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-06.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-07.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-08.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-09.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-10.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-11.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-12.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-13.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-14.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-15.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-16.png"
                },
                slice = 4,
                lines_per_file = 4,
                line_length = 4,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-04.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-05.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-06.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-07.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-08.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-09.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-10.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-11.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-12.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-13.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-14.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-15.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask1-16.png"
                },
                slice = 4,
                lines_per_file = 4,
                line_length = 4,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale,
                tint = tint1
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-04.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-05.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-06.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-07.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-08.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-09.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-10.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-11.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-12.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-13.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-14.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-15.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-mask2-16.png"
                },
                slice = 4,
                lines_per_file = 4,
                line_length = 4,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale,
                tint = tint2
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-04.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-05.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-06.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-07.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-08.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-09.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-10.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-11.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-12.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-13.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-14.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-15.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-die-shadow-16.png"
                },
                slice = 4,
                lines_per_file = 4,
                line_length = 4,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale,
                draw_as_shadow = true
            }
        }
    }
end

function the_cave_armored_attack_biter(scale, tint1, tint2)
    return {
        layers = {
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-04.png"
                },
                slice = 11,
                lines_per_file = 4,
                line_length = 16,
                width = 476,
                height = 340,
                frame_count = 11,
                shift = {0, 0},
                direction_count = 16,
                animation_speed = 0.4,
                scale = 0.5 * scale
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask1-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask1-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask1-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask1-04.png"
                },
                slice = 11,
                lines_per_file = 4,
                line_length = 16,
                width = 476,
                height = 340,
                frame_count = 11,
                shift = {0, 0},
                direction_count = 16,
                animation_speed = 0.4,
                scale = 0.5 * scale,
                tint = tint1
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask2-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask2-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask2-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-mask2-04.png"
                },
                slice = 11,
                lines_per_file = 4,
                line_length = 16,
                width = 476,
                height = 340,
                frame_count = 11,
                shift = {0, 0},
                direction_count = 16,
                animation_speed = 0.4,
                scale = 0.5 * scale,
                tint = tint2
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-shadow-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-shadow-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-shadow-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-attack-shadow-04.png"
                },
                slice = 11,
                lines_per_file = 4,
                line_length = 16,
                width = 476,
                height = 340,
                frame_count = 11,
                shift = {0, 0},
                direction_count = 16,
                animation_speed = 0.4,
                scale = 0.5 * scale,
                draw_as_shadow = true
            }
        }
    }
end

function the_cave_armored_run_biter(scale, tint1, tint2)
    return {
        layers = {
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-04.png"
                },
                slice = 8,
                lines_per_file = 8,
                line_length = 8,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask1-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask1-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask1-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask1-04.png"
                },
                slice = 8,
                lines_per_file = 8,
                line_length = 8,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale,
                tint = tint1
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask2-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask2-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask2-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-mask2-04.png"
                },
                slice = 8,
                lines_per_file = 8,
                line_length = 8,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale,
                tint = tint2
            },
            {
                filenames = {
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-shadow-01.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-shadow-02.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-shadow-03.png",
                    "__the-cave__/graphics/armoured-biters/armoured-biter/armoured-biter-run-shadow-04.png"
                },
                slice = 8,
                lines_per_file = 8,
                line_length = 8,
                width = 476,
                height = 340,
                frame_count = 16,
                shift = {0, 0},
                direction_count = 16,
                scale = 0.5 * scale,
                draw_as_shadow = true
            }
        }
    }
end

function the_cave_armoured_spawner_idle_animation(variation, tint)
    return {
        layers = {
            {
                filename = "__the-cave__/graphics/armoured-biters/armoured-spawner/spawner-armoured-idle.png",
                line_length = 4,
                width = 490,
                height = 354,
                frame_count = 8,
                animation_speed = 0.18,
                run_mode = "forward-then-backward",
                scale = 0.5
            },
            {
                filename = "__the-cave__/graphics/armoured-biters/armoured-spawner/spawner-armoured-idle-mask.png",
                flags = {"mask"},
                width = 276,
                height = 235,
                frame_count = 8,
                animation_speed = 0.18,
                run_mode = "forward-then-backward",
                shift = util.by_pixel(-3, -12),
                line_length = 4,
                tint = tint,
                scale = 0.5
            },
            {
                filename = "__the-cave__/graphics/armoured-biters/armoured-spawner/spawner-armoured-idle-shadow.png",
                draw_as_shadow = true,
                width = 464,
                height = 406,
                frame_count = 8,
                animation_speed = 0.18,
                run_mode = "forward-then-backward",
                shift = util.by_pixel(36, 13),
                line_length = 4,
                scale = 0.5
            }
        }
    }
end

function the_cave_spawner_armoured_integration()
    return {
        filename = "__the-cave__/graphics/armoured-biters/armoured-spawner/spawner-armoured-idle-integration.png",
        variation_count = 1,
        width = 522,
        height = 380,
        shift = util.by_pixel(2, -2),
        frame_count = 1,
        line_length = 1
    }
end
