# The Cave 3.1.95 - Lamp research, accumulator crafting, resource pipette

Base: the user-tested `the-cave_3.1.94.zip`, SHA-256
`f054ad049c87c0ca789afe976084a4e6f902f6f4a586e8d02322da45c8edeb4b`.
This is the same branch; the existing Advancing Collapse and Queen files are unchanged.

## Changes

- Lamp post: base research cost 50 red + 50 green packs, no blue pack. The blue-science prerequisite is replaced with Plastics, which supplies an existing recipe ingredient. Research time per unit remains 30 seconds. Existing research-difficulty multipliers still apply (the displayed cost is 50 at Medium).
- Cave Accumulators: base crafting times 3x3 = 20s, 6x6 = 30s, 10x10 = 40s, 20x20 = 50s. Actual machine duration still depends on crafting speed. Ingredients, stored energy, flow limits and graphics are unchanged.
- Resource Q: if native pipetting selects a market Electric Mining Drill MK1-MK5 over a resource, replace that selection with an eligible standard drill. Prefer an owned Big Mining Drill, then Electric Mining Drill, then Burner Mining Drill, keeping the highest owned quality of that model. An owned lower-tier standard drill takes priority over a ghost of a higher tier. Fluid-requiring resources cannot select a burner drill.
- When native pipetting chose a ghost and no eligible standard drill is owned, use the best eligible standard drill whose recipe is enabled for that player's force. Do not unlock research or manufacture an item. If no standard option exists, clear the unwanted MK selection.
- Existing MK stacks are returned through the native clear-cursor action. A failed cursor return aborts correction instead of overwriting or losing an owned item. Manually selecting MKs and using Q on placed MKs, including filtered variants, remain native behavior.

The new handler uses only `on_player_pipette`. It has no per-tick work, world scans, persistent state, or migration. Existing saves pick up the prototype changes on loading; no research reset is performed.

## Exact files changed from 3.1.94

- `prototypes/lamp_post.lua`
- `prototypes/cave_accumulators.lua`
- `control.lua` (module import and one event registration)
- `scripts/mining_drill_pipette.lua` (new)
- `info.json` (version only)
- `changelog.txt` (new version entry)
- `TESTING-3.1.95.md` (new)

All other payload files are byte-identical to the 3.1.94 ZIP. Validation fixtures and downloaded API documentation remain outside the playable ZIP.

## Verification performed

- Compiled all 331 mod Lua files with Lua 5.4: no syntax errors. This is not Factorio's native loader.
- Executed the real new pipette module against mocked Factorio objects: 100 combinations of five MK tiers, five ore types, filter on/off and Base/Space Age prototype availability; 122 assertions plus inventory/quality conservation checks.
- Additional cases cover owned Big drills, owned Electric drills versus higher-tier ghosts, numeric quality 1000, per-force recipe unlocks, missing prototypes, fluid-required mining, returning real MK stacks, failed cursor clearing, cheat mode, duplicate/reentrant events, module reloads, invalid entities and missing players.
- Executed the actual old and new Lamp/Accumulator prototype modules with mocked engine dependencies and compared their complete outputs. Only the agreed research fields, prerequisite and four crafting times differ. Executed the existing difficulty-scaling block for all six settings.
- Checked used runtime API contracts against the official Factorio 2.0.72 runtime API: `on_player_pipette`, inventory contents, resource categories, cursor ghost prototype/quality pairs, `clear_cursor` and `pipette_entity`.
- Reviewed the exact diff, event wiring and package metadata; checked archive integrity and every payload file against the base ZIP.

## In-game checks still required

Factorio is not installed in the build environment. These checks are necessary before promoting the build to the live server:

1. Load a copy of the current save with 3.1.95. Check both researched and unresearched Lamp post states. At Medium research difficulty, confirm 50 red + 50 green, no blue prerequisite, and successful crafting after Lamp and Plastics.
2. Check the four accumulator recipe times above and confirm an existing placed accumulator retains its charge and connections.
3. In normal play with Electric Mining Drills in inventory and no MKs, press Q over iron, copper, coal and stone. The real Electric Mining Drill must be selected and placeable. Repeat with Filter Mining Drills enabled and disabled; also check uranium with a compatible drill.
4. Repeat while owning MK drills: resource Q must choose a standard drill, and MK counts/quality must remain intact. Select an MK manually and place it; Q on that placed MK must still select its model.
5. Check Big Mining Drill before/after unlock and with/without it in inventory. Check a non-normal quality Electric Mining Drill. With no standard items, verify the ghost fallback uses that team's unlocked standard drill.
6. Save/reload and try Q with two players/forces at different research stages. Check native cursor behavior in remote view as well as normal character view.

Existing MK ghosts/blueprints already placed or saved by players are not converted by this event-only correction.
