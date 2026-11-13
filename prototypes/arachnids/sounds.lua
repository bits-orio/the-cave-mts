-- Arachnids_enemy 1.2.0 sound definitions (MIT).
local path = "__the-cave__/arachnids_enemy/"

arachnid_roars = function(volume)
  return
  {
    {
      filename = path .. "sound/creatures/warrior/warrior-roar-1.ogg",
      volume = volume
    },
    {
      filename = path .. "sound/creatures/warrior/warrior-roar-2.ogg",
      volume = volume
    },
    {
      filename = path .. "sound/creatures/warrior/warrior-roar-3.ogg",
      volume = volume
    }
  }
end

arachnid_calls = function(volume)
  return
  {
    sound =
    {
      {
        filename = path .. "sound/creatures/warrior/warrior-call-1.ogg",
        volume = volume
      },
      {
        filename = path .. "sound/creatures/warrior/warrior-call-2.ogg",
        volume =volume
      }
    },
    probability = 1 / (12 * 60), -- average pause between the sound is 12 seconds
    max_sounds_per_type = 2
  }
end

arachnid_dying = function(volume)
  return
  {
    {
      filename = path .. "sound/creatures/warrior/warrior-die-1.ogg",
      volume = volume
    },
    {
      filename = path .. "sound/creatures/warrior/warrior-die-2.ogg",
      volume = volume
    },
    {
      filename = path .. "sound/creatures/warrior/warrior-die-3.ogg",
      volume = volume
    },
    {
      filename = path .. "sound/creatures/warrior/warrior-die-4.ogg",
      volume = volume
    },
    {
      filename = path .. "sound/creatures/warrior/warrior-die-5.ogg",
      volume = volume
    }
  }
end
