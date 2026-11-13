# The Cave 3.2.19

Base: the delivered `the-cave_3.2.18.zip`. This release adds only the approved Fortified Cave Startup option.

## Behavior

- `Settings > Mod Settings > Startup > Fortified Cave` (`the-cave-fortified-cave`) provides Enable/Disable and defaults to Enable. A missing value also defaults to enabled for compatibility.
- Disable prevents new Fortified entrances in ordinary exploration and Advancing Collapse. Direct creation and the existing admin test command cannot bypass it. No new surface/entrance is made or placement attempted through the entrance creation API while disabled.
- Previously discovered entrances stay usable, including entrances whose underground surface has never been created. Preserve their contents, ownership, entry/exit, cache interactions and normal timer/closure rules. Active timers do not restart, and first entry to an already-discovered unused entrance still starts its normal timer.
- Keep Fortified entity prototypes, code, graphics, saved records and existing-operation event handlers. This is a generation gate, not removal of existing caves.
- Preserve Advancing Collapse zone layouts and reservations across both setting values. Already queued, uncreated Fortified sites pause while disabled and can resume when enabled again; other cave types keep their existing behavior. No saved zone is rerolled.
- Changing this Startup option requires applying the setting and restarting the game/server, then loading the same save with the matching mod/settings configuration. A new world is not required.
- Retain both 3.2.18 changes: six underground cave types remain exempt from structural Cave Collapses; new Lost Village generation remains internally off with no visible setting.
- Loot, MK2 rewards, enemies, balance, timer duration, Uranium transfer/performance code, mod dependencies and optional Space Age support are unchanged.

## Exact changed files

Modified:

- `settings.lua`
- `scripts/fortified_vaults.lua`
- `scripts/caverns.lua`
- `scripts/advancing_caves.lua`
- `locale/en/settings.cfg`
- `locale/en/locale.cfg`
- `locale/ru/settings.cfg`
- `locale/ru/locale.cfg`
- `info.json` (version only)
- `changelog.txt`

Added:

- `TESTING-3.2.19.md`

## Checks performed

- Compile all 348 Lua files using Lua 5.4 to check syntax and the local-variable limit. This does not launch Factorio.
- Execute behavior checks against the real setting readers, Fortified module, ordinary selection and Advancing Collapse scheduler, with mocked Factorio construction/rendering helpers: missing/default Enabled values; Disable before any entrance placement/map/storage mutation; no test-command bypass; ordinary Medium/Hard/Nightmare Fortified selection disabled; scheduled opening rejected before room carving; re-enabling reaches placement.
- Check deterministic zone layouts on two main surfaces/forces across Enable/Disable, retained saved reservations, blocked planned Fortified discovery, unchanged Uranium eligibility, paused saved Fortified retries while Iron proceeds, and resumed Fortified retries after Enable.
- Check configuration handling with three saved Fortified records: records, owner forces, reward budgets and original active deadlines preserved; existing entry and exit allowed; a discovered unused entrance reaches underground-surface creation and starts its first-entry timer; wrong-force entry denied; active caves continue tick processing; normal expiry dispatch runs; a closed cave cannot reopen. Surface creation, graphics and physical closure helpers are mocked, so these checks do not certify actual engine/save migration or multiplayer execution.
- Run the 3.2.18 behavior regression checks for six collapse exemptions, selective pending-job cleanup, parent-map behavior, Lost Village shutdown and continued access/timer/normal closure of old Lost Village entrances.
- Check the single visible Startup prototype, exact Enable/Disable values, default Enable, complete English/Russian names/descriptions/value labels, and absence of the Lost Village setting.
- Compare all release payloads with 3.2.18: only the listed files change; all original files are retained. Loot/reward code, Uranium code, existing mission handlers, graphics, prototypes, `control.lua`, collapse policy and optional-mod files remain unchanged except the specific generation gates listed above.
- Verify archive CRCs, a single correctly versioned root directory, matching metadata version, no duplicate entries, no missing original files and only the listed addition.

## Remaining in-game/server tests

No Factorio executable is available in this build environment.

1. Install 3.2.19 and load a copy of the existing save. Confirm Fortified Cave appears under Startup with Enable selected by default. The other cave settings remain available; Lost Village remains absent.
2. Have the server admin set Fortified Cave to Disable, apply the Startup change, restart and load the same save with clients using matching mods/settings. Visit the three discovered Fortified entrances; verify contents, entry/exit, power, caches, force ownership and original remaining time. An unused discovered entrance must still work on its first visit.
3. Save/reload while disabled. Discover ordinary rooms and dig old/new scheduled Advancing Collapse sites: no new Fortified entrance may appear, including a previously queued uncreated site. The admin Fortified test command must not create a cave. Other enabled cave types must still generate.
4. Let an old Fortified cave reach its existing deadline. Confirm normal closure and evacuation/cleanup under the original rules; no replacement/new Fortified entrance may appear while disabled. Retrieve supplies before the deadline as before.
5. Re-enable, restart and continue the same save. Confirm new ordinary/scheduled Fortified discovery works, including a still-valid uncreated reservation, with no reroll of saved zone layouts. Check two forces and both Base/Space Age mod combinations where available.
