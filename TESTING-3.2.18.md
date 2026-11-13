# The Cave 3.2.18

Base: the supplied/delivered `the-cave_3.2.17.zip`. Only the two approved changes are included.

## Behavior

- Structural Cave Collapses cannot evaluate, schedule or execute on the underground Iron, Copper, Coal, Uranium, Lost Village and Fortified Vault surfaces. Iron/Copper/Coal use the existing mineral-cave namespace.
- On upgrade, remove these surfaces' saved pending roof collapses, room roof countdowns and associated/orphaned roof markers. Keep previously fallen rubble, map contents and every timed mission deadline. Preserve parent-map collapse behavior and the independent Advancing Collapse system.
- `scripts/cave_policy.lua` contains the internal `LOST_VILLAGE_GENERATION_ENABLED = false` switch. There is no player setting for it.
- Remove the Underground Village setting prototype and its English/Russian setting labels/descriptions. Do not register the Lost Village test command while the internal switch is off.
- Stop new ordinary entrances, new Advancing Collapse village plans, and queued retries for uncreated village entrances. Previously generated zone layouts are not rerolled.
- Previously discovered Lost Village entrances remain usable even if their underground surface has not yet been created. Their existing access, force ownership, contents, missions, trades, timer extensions and normal timeout/closure behavior remain in place. An already-started timer is not restarted; first entry to an already-discovered unused entrance still starts its normal timer. Closed entrances cannot reopen.
- Lost Village code, graphics and entity prototypes are retained for existing saves and future reconsideration. Its existing-operation tick handlers must continue until normal closure.
- Uranium fluid transfer, intervals, throughput and other performance code are unchanged.

## Exact changed files

Modified:

- `control.lua`
- `scripts/collapse.lua`
- `scripts/caverns.lua`
- `scripts/advancing_caves.lua`
- `scripts/lost_city.lua`
- `settings.lua`
- `locale/en/settings.cfg`
- `locale/en/locale.cfg`
- `locale/ru/settings.cfg`
- `locale/ru/locale.cfg`
- `info.json` (version only)
- `changelog.txt`

Added:

- `scripts/cave_policy.lua`
- `TESTING-3.2.18.md`

## Checks performed

- Compiled all 348 Lua files with Lua 5.4. This is a syntax/local-variable-limit check, not a Factorio engine launch.
- Executed Lua behavior checks with mocked Factorio APIs: six cave classifications; parent/invalid surface handling; suppression of structural evaluation, telegraphs, scheduling and sparse execution; selective and repeatable old-job cleanup; preservation of parent jobs, mission deadlines and contents; cancellation of stale exempt jobs before their due tick; main-map scheduling and disabled-collapse behavior.
- Checked room heartbeat cancellation, ordinary and AC generation gates, ignored legacy Enabled setting, omission of village from new AC plans, removal of old uncreated village retries, and retention of the other cave kinds.
- Checked that the Lost Village test command and setting prototype are absent. Checked existing-entrance access, unchanged started deadlines and contents, first-entry timer for a discovered unused entrance, continued old-operation processing, normal timeout dispatch and refusal to reopen a closed entrance. Engine construction/GUI helpers were mocked; this does not certify real engine migration or multiplayer execution.
- Reviewed the diff against 3.2.17. All other original files, including `scripts/uranium_caves.lua`, graphics and optional-mod code, match the base byte-for-byte. Dependencies and Factorio/Space Age metadata are unchanged except the mod version.
- Release packaging checks verify the archive CRCs, one correctly named root folder, matching metadata version, no duplicate entries, all original files retained, and only the listed changes/additions.

## Remaining in-game tests

No Factorio executable is available in the build environment; in-game and server tests remain.

1. Update a COPY of the existing 3.2.17 server save containing an active Lost Village and, if available, an already-discovered unused entrance. Check the original contents and remaining time, entry/exit, trades and movement of supplies out of the cave. Repeat after save/load and with players from two forces. Existing normal timer extensions remain allowed.
2. Confirm Underground Village is absent from Mod Settings and the read-only Information/Controls settings list, and the Lost Village test command is not registered. Discover new ordinary rooms and new AC zones: no new Lost Village entrance may appear, including an old queued/uncreated reservation. Other cave kinds must still generate normally.
3. With Cave Collapses enabled, dig/build/remove supports or use TNT inside each of the six cave types. No structural roof warning, falling rubble or collapse damage may occur. Load a save with pending roof jobs on these surfaces and confirm those warnings/jobs disappear while cave mission timers retain their remaining time.
4. Confirm ordinary unsupported parent-map areas still collapse, Cave Collapses disabled still suppresses them, and Advancing Collapse continues with its existing rules.
5. Let an old Lost Village reach normal closure. Its entrance must remain sealed and no replacement/new village may be discovered. Supplies must be retrieved before the existing mission deadline under the original rules.
