# The Cave 3.1.84 — large accumulator column effects

Built directly from the tested 3.1.83 package, SHA-256:
83aef8766b4bd39e9300a9ed730542678e01531e98be1bb60b175f1515938bc7

## Fix

The 10x10 and 20x20 charging/discharging animations previously repeated only
their static bodies and shadows. They now include the exact blue charging and
yellow discharging window animation from the approved 6x6 accumulator.

The 10x10 has nine visible battery windows; the 20x20 has eight. Each native
animation layer reads its 32 frames directly from the existing 6x6 atlas and is
positioned and scaled to its window. Partly hidden rear windows use clipped
regions so the effect does not cover the foreground body or fan decks.

The front red/yellow/green charge meter remains separate and continues to show
the actual stored-energy percentage. The column effects indicate charging or
discharging, using the engine's existing accumulator animation behaviour and
cooldowns. They are not another percentage meter.

All existing image files, body sizes, shadows, fans, footprints, runtime scripts,
recipes, capacities, power limits, research, entity names and saved-energy
handling are unchanged. No additional image atlas, runtime render object or
per-tick script is needed. Existing placed accumulators receive the graphics
when the updated mod loads; no rebuilding or migration is required.

## Verification

- All 322 Lua files pass Lua 5.2 syntax checks.
- Prototype comparison against 3.1.83 confirms that only the two large models'
  charge/discharge graphics changed. All other prototype fields match.
- Every frame crop is inside the original 3072x1536 atlas, with the correct
  frame order, visible colour and changing pixels. Rendered effect bounds stay
  within the existing body canvases.
- All existing PNG files are byte-identical to 3.1.83. Static inspection renders
  were composed from the actual prototype positions at both body sizes.
- Actual Factorio 2.0.72 headless runs passed with Space Age/Quality enabled and
  disabled: loading existing 3.1.83 saves, retaining placed entities and stored
  Joules, native charging and discharging of both models, and preservation of
  the front meters and 20x20 fan render objects.

Headless tests validate loading and electrical behaviour, but do not render
the game's final visual output. Check the following in your graphical client:

1. Load the same test save with 3.1.84 enabled.
2. While a 10x10 or 20x20 is receiving power, its battery windows should show
   moving blue light, matching the 6x6 style.
3. While it supplies power, those windows should show moving yellow light.
4. The front percentage gauge should still change independently, and all ten
   20x20 cooling fans should continue spinning.
5. At rest, column effects follow the existing native cooldown, then the
   unchanged idle artwork remains. Footprints and neighbouring machines
   should look exactly as before.
