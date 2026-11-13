# The Cave 3.2.11 test build

Based on the exact delivered 3.2.10 archive. Heating Tower now has Concrete
as its only prerequisite. It remains a separate research costing 200 red
and 200 green packs at the normal cost multiplier, with 30 seconds per unit.
Completing it unlocks Heating Tower, Heat Pipe, Heat Exchanger and Steam
Turbine. No blue science or Gleba research/mining trigger is required.

## In-game checks

1. With Heating Tower unresearched, verify Concrete is required. Complete
   Concrete, then research Heating Tower using red and green packs.
2. Confirm all four recipes become available after Heating Tower research.
3. Check existing saves with Heating Tower both unresearched and completed;
   completed research should remain completed.

## Validation and file changes

Both changed Lua files passed syntax loading under Lua 5.4. Loading the actual
progression module with mocked data confirmed Concrete, the two-pack cost,
30-second unit time, no trigger and retention of the four existing effects.
Diff review confirmed only these five files changed:

- `prototypes/heating_tower_progression_final_fixes.lua`: prerequisite only.
- `data-final-fixes.lua`: related comment only.
- `info.json`: version 3.2.11.
- `changelog.txt`: release entry.
- `TESTING-3.2.11.md`: this guide, superseding earlier research test guides.

Factorio itself and real save upgrades were not tested here.
