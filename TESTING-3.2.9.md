# The Cave 3.2.9 test build

Continues from the delivered 3.2.8 build.

## Changes

- Heating Tower is a core research in every mode where that technology exists.
  Its only prerequisite is Chemical Science Pack. It costs 200 red, 200 green
  and 200 blue packs at the normal research cost multiplier, with 30 seconds
  per unit. Gleba discovery and the Copper Stromatolite mining trigger are
  removed from this research.
- The same technology retains its four recipe unlocks: Heating Tower, Heat
  Pipe, Heat Exchanger and Steam Turbine. Recipes and other research paths,
  including the existing optional Superheating turbine unlock, are unchanged.
- The setting name is now just **Advancing Collapse** in English, with the
  original short Russian translation restored. Tooltip descriptions remain.

## In-game checks

1. Restart Factorio with 3.2.9 and check the short startup setting title.
2. Before researching Gleba, complete Chemical Science Pack and check that
   Heating Tower can be researched with the three listed packs. Complete it
   and confirm the four recipes are available.
3. Check the same research with Advancing Collapse, Everything on Nauvis and
   Superheating disabled; the new research path is independent of these options.
4. Load a copy of an existing save. Check an unresearched Heating Tower uses
   the new cost and prerequisite, and an already completed Heating Tower stays
   completed with its recipes available.

## Validation

All 344 Lua files passed syntax loading under Lua 5.4. A mocked data-stage
check verified cost, trigger removal, existing unlocks, option independence,
unrelated technologies and safe handling when Heating Tower is absent.
Locale checks confirmed only the four setting-name entries changed, preserving
descriptions and line endings. Runtime scripts are byte-identical to 3.2.8.
Factorio itself and actual save upgrades were not run here.

## Files changed from 3.2.8

- `prototypes/heating_tower_progression_final_fixes.lua` (new)
- `data-final-fixes.lua`
- `locale/en/settings.cfg`, `locale/en/locale.cfg`
- `locale/ru/settings.cfg`, `locale/ru/locale.cfg`
- `info.json`, `changelog.txt`
- `TESTING-3.2.9.md` (new)
