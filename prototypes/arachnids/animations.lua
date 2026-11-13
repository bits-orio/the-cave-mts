-- Arachnids_enemy 1.2.0 animation definitions (MIT).
local path = "__the-cave__/arachnids_enemy/"

function arachnidsrunanimation(scale, tint1, tint2)
    return
    {
      layers=
      {
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-run-01.png",
              path .. "graphics/hr-Arachnids-run-02.png",
              path .. "graphics/hr-Arachnids-run-03.png",
              path .. "graphics/hr-Arachnids-run-04.png"
            },
            slice = 8,
            lines_per_file = 8,
            line_length = 8,
            width = 398,
            height = 350,
            frame_count = 16,
            --shift = util.mul_shift(util.by_pixel(-1, -5), scale),
            direction_count = 16,
            scale = 0.5 * scale
        },
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-run-mask1-01.png",
              path .. "graphics/hr-Arachnids-run-mask1-02.png",
              path .. "graphics/hr-Arachnids-run-mask1-03.png",
              path .. "graphics/hr-Arachnids-run-mask1-04.png"
            },
            slice = 8,
            lines_per_file = 8,
            line_length = 8,
            width = 398,
            height = 350,
            frame_count = 16,
            --shift = util.mul_shift(util.by_pixel(-1, -37), scale),
            direction_count = 16,
            scale = 0.5 * scale,
            tint = tint1
        },
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-run-mask2-01.png",
              path .. "graphics/hr-Arachnids-run-mask2-02.png",
              path .. "graphics/hr-Arachnids-run-mask2-03.png",
              path .. "graphics/hr-Arachnids-run-mask2-04.png"
            },
            slice = 8,
            lines_per_file = 8,
            line_length = 8,
            width = 398,
            height = 350,
            frame_count = 16,
            --shift = util.mul_shift(util.by_pixel(-1, -5), scale),
            direction_count = 16,
            scale = 0.5 * scale,
            tint = tint2
        },
        {
           filenames =
            {
              path .. "graphics/hr-Arachnids-run-shadow-01.png",
              path .. "graphics/hr-Arachnids-run-shadow-02.png",
              path .. "graphics/hr-Arachnids-run-shadow-03.png",
              path .. "graphics/hr-Arachnids-run-shadow-04.png"
            },
            slice = 8,
            lines_per_file = 8,
            line_length = 8,
            width = 398,
            height = 240,
            frame_count = 16,
            shift = util.mul_shift(util.by_pixel(18, 18), scale),
            direction_count = 16,
            scale = 0.62 * scale,
            draw_as_shadow = true
        }
      }
    }
  end


  function arachnidsattackanimation(scale, tint1, tint2)
    return
    {
      layers=
      {
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-attack-01.png",
              path .. "graphics/hr-Arachnids-attack-02.png",
              path .. "graphics/hr-Arachnids-attack-03.png",
              path .. "graphics/hr-Arachnids-attack-04.png"
            },
            slice = 11,
            lines_per_file = 4,
            line_length = 16,
            width = 398,
            height = 350,
            frame_count = 11,
            --shift = util.mul_shift(util.by_pixel(0, -25), scale),
            direction_count = 16,
            animation_speed = 0.4,
            scale = 0.5 * scale
        },
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-attack-mask1-01.png",
              path .. "graphics/hr-Arachnids-attack-mask1-02.png",
              path .. "graphics/hr-Arachnids-attack-mask1-03.png",
              path .. "graphics/hr-Arachnids-attack-mask1-04.png"
            },
            slice = 11,
            lines_per_file = 4,
            line_length = 16,
            width = 398,
            height = 350,
            frame_count = 11,
            --shift = util.mul_shift(util.by_pixel(-1, -41), scale),
            direction_count = 16,
            animation_speed = 0.4,
            scale = 0.5 * scale,
            tint = tint1
        },
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-attack-mask2-01.png",
              path .. "graphics/hr-Arachnids-attack-mask2-02.png",
              path .. "graphics/hr-Arachnids-attack-mask2-03.png",
              path .. "graphics/hr-Arachnids-attack-mask2-04.png"
            },
            slice = 11,
            lines_per_file = 4,
            line_length = 16,
            width = 398,
            height = 350,
            frame_count = 11,
            --shift = util.mul_shift(util.by_pixel(-1, -41), scale),
            direction_count = 16,
            animation_speed = 0.4,
            scale = 0.5 * scale,
            tint = tint2
        },
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-attack-shadow-01.png",
              path .. "graphics/hr-Arachnids-attack-shadow-02.png",
              path .. "graphics/hr-Arachnids-attack-shadow-03.png",
              path .. "graphics/hr-Arachnids-attack-shadow-04.png"
            },
            slice = 11,
            lines_per_file = 4,
            line_length = 16,
            width = 398,
            height = 240,
            frame_count = 11,
            shift = util.mul_shift(util.by_pixel(18, 18), scale),
            direction_count = 16,
            animation_speed = 0.4,
            scale = 0.62 * scale,
            draw_as_shadow = true
        }
      }
    }
  end


  function arachnidsdieanimation(scale, tint1, tint2)
    return
    {
      layers=
      {
        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-die-01.png",
              path .. "graphics/hr-Arachnids-die-02.png",
              path .. "graphics/hr-Arachnids-die-03.png",
              path .. "graphics/hr-Arachnids-die-04.png",
              path .. "graphics/hr-Arachnids-die-05.png",
              path .. "graphics/hr-Arachnids-die-06.png",
              path .. "graphics/hr-Arachnids-die-07.png",
              path .. "graphics/hr-Arachnids-die-08.png",
              path .. "graphics/hr-Arachnids-die-09.png",
              path .. "graphics/hr-Arachnids-die-10.png",
              path .. "graphics/hr-Arachnids-die-11.png",
              path .. "graphics/hr-Arachnids-die-12.png",
              path .. "graphics/hr-Arachnids-die-13.png",
              path .. "graphics/hr-Arachnids-die-14.png",
              path .. "graphics/hr-Arachnids-die-15.png",
              path .. "graphics/hr-Arachnids-die-16.png",
              path .. "graphics/hr-Arachnids-die-17.png"
            },
            slice = 4,
            lines_per_file = 4,
            line_length = 4,
            width = 398,
            height = 350,
            frame_count = 17,
            --shift = util.mul_shift(util.by_pixel(0, -4), scale),
            direction_count = 16,
            scale = 0.5 * scale
        },

        {
            filenames =
            {
              path .. "graphics/hr-Arachnids-die-shadow-01.png",
              path .. "graphics/hr-Arachnids-die-shadow-02.png",
              path .. "graphics/hr-Arachnids-die-shadow-03.png",
              path .. "graphics/hr-Arachnids-die-shadow-04.png",
              path .. "graphics/hr-Arachnids-die-shadow-05.png",
              path .. "graphics/hr-Arachnids-die-shadow-06.png",
              path .. "graphics/hr-Arachnids-die-shadow-07.png",
              path .. "graphics/hr-Arachnids-die-shadow-08.png",
              path .. "graphics/hr-Arachnids-die-shadow-09.png",
              path .. "graphics/hr-Arachnids-die-shadow-10.png",
              path .. "graphics/hr-Arachnids-die-shadow-11.png",
              path .. "graphics/hr-Arachnids-die-shadow-12.png",
              path .. "graphics/hr-Arachnids-die-shadow-13.png",
              path .. "graphics/hr-Arachnids-die-shadow-14.png",
              path .. "graphics/hr-Arachnids-die-shadow-15.png",
              path .. "graphics/hr-Arachnids-die-shadow-16.png",
              path .. "graphics/hr-Arachnids-die-shadow-17.png"
            },
            slice = 4,
            lines_per_file = 4,
            line_length = 4,
            width = 398,
            height = 240,
            frame_count = 17,
            shift = util.mul_shift(util.by_pixel(18, 18), scale),
            direction_count = 16,
            scale = 0.62 * scale,
            draw_as_shadow = true
        }
      }
    }
  end







function arachnids_spawner_idle_animation(scale, variation)
return
  {
    layers =
    {
      {
          filename = path .. "graphics/hr-Arachnids-spawner-idle.png",
          line_length = 1,
          width = 350,
          height = 362,
	    frame_count = 1,
	    shift = util.mul_shift(util.by_pixel(-10, -20), scale),
          --shift = util.by_pixel(-10, -20),
          y = variation * 362,
          scale = 0.5 * scale
      },
      {
          filename = path .. "graphics/hr-Arachnids-spawner-idle-shadow.png",
          draw_as_shadow = true,
          width = 370,
          height = 240,
	    frame_count = 1,
          shift = util.mul_shift(util.by_pixel(20, -2), scale),
          line_length = 1,
          y = variation * 240,
          scale = 0.59 * scale
      }
    }
  }
end

function arachnids_spawner_die_animation(scale,variation)
return
  {
    layers =
    {
      {
          filename = path .. "graphics/hr-Arachnids-spawner-die.png",
          line_length = 8,
          width = 350,
          height = 362,
          frame_count = 8,
          direction_count = 1,
          shift = util.mul_shift(util.by_pixel(-10, -20), scale),
          y = variation * 362,
          scale = 0.5 * scale
      },
      {
          filename = path .. "graphics/hr-Arachnids-spawner-die-shadow.png",
          draw_as_shadow = true,
          width = 370,
          height = 240,
          frame_count = 8,
          direction_count = 1,
          shift = util.mul_shift(util.by_pixel(20, -2), scale),
          line_length = 8,
          y = variation * 240,
          scale = 0.59 * scale
      }
    }
  }
end


local green_blood = {r = 60, g = 200, b = 20}
function get_arachnids_ground_patch(scale)
return
  {
    sheet ={
        filename = "__base__/graphics/entity/biter/blood-puddle-var-main.png",
        flags = { "low-object" },
        line_length = 4,
        variation_count = 4,
        frame_count = 1,
        width = 164,
        height = 134,
        shift = util.by_pixel(-0.5,-0.5),
        tint = green_blood,
        scale = 0.5 * scale
    }
  }
end
