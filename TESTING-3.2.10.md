# The Cave 3.2.10 test build

Based on the exact delivered 3.2.9 archive. Use this guide instead of the
historical 3.2.9 guide for the current Heating Tower requirements.

Heating Tower now requires Advanced Material Processing and costs 200 red
plus 200 green packs at the normal research cost multiplier. No blue packs,
Gleba discovery or Copper Stromatolite mining are required for this research.
Each unit still takes 30 seconds. The existing technology and its Heating
Tower, Heat Pipe, Heat Exchanger and Steam Turbine unlocks are retained.
This is core progression, independent of optional scenario settings.

## In-game checks

1. Complete Advanced Material Processing without researching blue science.
   Check Heating Tower is available and needs only the two listed packs.
2. Complete Heating Tower and verify all four recipes are available.
3. Load an existing save with Heating Tower unresearched, then one where it
   is completed. Check the new requirements and retained completed research.

## Checks completed here

- Both changed Lua files passed syntax loading under Lua 5.4.
- Loading the actual progression module with mocked prototype data produced
  the new prerequisite, 200 red/200 green cost, 30-second unit time and no
  mining trigger, while retaining the existing four unlock effects.
- Loading without a Heating Tower prototype completed safely.
- Diff review confirmed the five files below are the only changes.

Factorio itself and real save upgrades were not tested here.

## Exact files changed from 3.2.9

- `prototypes/heating_tower_progression_final_fixes.lua`: prerequisite and cost.
- `data-final-fixes.lua`: update the related comment only.
- `info.json`: version 3.2.10.
- `changelog.txt`: release entry.
- `TESTING-3.2.10.md`: this new guide.
