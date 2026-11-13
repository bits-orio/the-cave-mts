# The Cave 3.1.83 — accumulator test build

Built from the supplied the-cave_3.1.82(1).zip, SHA-256:
c7aab1c3992dd05780a5fa177022154a94a88d14610378898a02d4e88d0ad6f0

## Normal-quality values

| Footprint | Capacity | Battery | Steel plate | Electronic circuit | Advanced circuit | Processing unit |
|---|---:|---:|---:|---:|---:|---:|
| 3x3 | 50 MJ | 50 | 10 | 20 | 10 | 0 |
| 6x6 | 250 MJ | 200 | 40 | 80 | 40 | 0 |
| 10x10 | 1 GJ | 750 | 150 | 300 | 150 | 0 |
| 20x20 | 5 GJ | 3000 | 600 | 1200 | 0 | 250 |

| Footprint | Maximum input/output | Base recipe time |
|---|---:|---:|
| 3x3 | 3 MW | 100 seconds |
| 6x6 | 6 MW | 200 seconds |
| 10x10 | 60 MW | 1500 seconds |
| 20x20 | 300 MW | 6000 seconds |

Capacity and ingredients use the accepted proposal. The existing small models'
flow limits and crafting times are retained. For the newly added models, flow
follows the existing 3x3 power/capacity ratio, and recipe time follows its two
base crafting seconds per battery. Actual crafting speed depends on the
crafting machine and its bonuses.

All four recipes use the existing Electric Energy Accumulators research.
The 20x20 recipe requires processing units. Ordinary accumulators, market MK
accumulators, loaders, containers, wind turbines, the 3.1.82 cave entrances and
other systems retain their original files.

## Display and graphics

The accepted PNG artwork is reused. The 10x10 body is 640x640 source pixels;
the 20x20 body is 1280x1280 pixels. At sprite scale 0.5 these canvases occupy
exactly 10x10 and 20x20 tiles. Visible bodies remain inside those canvases.
Shadows are separate and can extend outside the footprint.

The seven-segment front meter reads each entity's energy divided by its actual
buffer size. Its displayed percentage is floored to an integer. It fills upward,
changing from red through yellow to green; at zero it shows a small red lamp.
It updates every ten ticks. Quality-adjusted buffer sizes are read from the
engine. Rendering is visible to the owning force.

The ten cooling fans continuously loop the approved rotation. They are cosmetic:
the graphics controller does not create, transfer or consume electricity.
Each 20x20 uses one layered animation object; no Lua work runs per rotor frame.
Existing 3x3 and 6x6 artwork and animations are unchanged.

## Checks performed

Actual Factorio 2.0.72 headless runs passed with Space Age/Quality enabled and
with those mods disabled:

- Full mod startup and new-map creation.
- Loading a test save made with the supplied 3.1.82 code; the existing 6x6 entity
  identity and stored Joules were preserved while its capacity increased.
- Recipe unlocking on a researched force while a second force remained locked.
- Real meter states at 0%, 25%, 50%, 75% and 100%, including live Quality capacity
  when Quality was available.
- Native charging/discharging of a 20x20 through an outside substation.
- Duplicate builds, cloning, ghost revival, force transfer, silent/scripted
  destruction, cross-surface cloning, missing-render recovery and surface deletion.
- Multiplayer-server saving followed by loading the saved map: render IDs were
  retained without duplicate gauges or fan animations.
- Complete ingredients for all four recipes accepted by an assembling-machine-3
  input inventory.

Also checked: all 321 Lua files parsed with Lua 5.2; 244 sprite references and
28 relevant PNG files; sprite atlas bounds; all ten moving fans; exact recipes;
graphics-to-footprint alignment; and a byte comparison against 3.1.82.

The graphical client, a multi-client lockstep session and your own save/mod pack
were not available for testing. The headless tests verify behavior and API usage;
the final in-game appearance still needs your visual test.

## In-game test

1. Load a copy of your 3.1.82 save. If accumulator research is complete, the two
   new recipes should be available immediately.
2. Check the four recipes and capacities. A previously full 100 MJ 6x6 can show
   40% after its capacity increases to 250 MJ: its stored energy is preserved
   rather than filled for free.
3. Place a 10x10 and 20x20 next to other buildings. Inspect selection outlines,
   body edges, shadows, front meters and the ten fan rotors.
4. Charge and discharge both large models. Compare their front indicators with
   the game's energy readout; check their appearance in light and darkness.
5. Save, reload, mine/rebuild and revive a blueprint of each model. If using
   Quality, check a higher-quality model too.

## Exact file changes

Modified:

- `changelog.txt`
- `control.lua`
- `info.json`
- `locale/en/cave_accumulators.cfg`
- `locale/ru/cave_accumulators.cfg`
- `prototypes/cave_accumulators.lua`

Added:

- `TESTING-3.1.83.md`
- `graphics/entity/cave-accumulators/10x10/body.png`
- `graphics/entity/cave-accumulators/10x10/gauge.png`
- `graphics/entity/cave-accumulators/10x10/reflection.png`
- `graphics/entity/cave-accumulators/10x10/shadow.png`
- `graphics/entity/cave-accumulators/20x20/body.png`
- `graphics/entity/cave-accumulators/20x20/fan-side-left-front.png`
- `graphics/entity/cave-accumulators/20x20/fan-side-left-middle.png`
- `graphics/entity/cave-accumulators/20x20/fan-side-left-rear.png`
- `graphics/entity/cave-accumulators/20x20/fan-side-right-front.png`
- `graphics/entity/cave-accumulators/20x20/fan-side-right-middle.png`
- `graphics/entity/cave-accumulators/20x20/fan-side-right-rear.png`
- `graphics/entity/cave-accumulators/20x20/fan-upper-left-front.png`
- `graphics/entity/cave-accumulators/20x20/fan-upper-left-rear.png`
- `graphics/entity/cave-accumulators/20x20/fan-upper-right-front.png`
- `graphics/entity/cave-accumulators/20x20/fan-upper-right-rear.png`
- `graphics/entity/cave-accumulators/20x20/gauge.png`
- `graphics/entity/cave-accumulators/20x20/reflection.png`
- `graphics/entity/cave-accumulators/20x20/shadow.png`
- `graphics/icons/cave-accumulators/10x10.png`
- `graphics/icons/cave-accumulators/20x20.png`
- `migrations/3.1.83.lua`
- `scripts/cave_accumulator_visuals.lua`
- `shared/cave_accumulator_graphics.lua`

No baseline files were removed. Local test tools, test mods, saved maps and
the headless Factorio executable are not included in the mod ZIP.
