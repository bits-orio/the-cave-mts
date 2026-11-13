# The Cave 3.2.47 - synchronized Advancing Collapse terrain

This server playtest build uses only `the-cave_3.2.46-test.zip` as its baseline.
It has not been declared a new stable release.

## Behavior

The northern clearing follows complete southern rows at the actual floor
commit. One complete row erased below opens one row above in that same tick.
Two complete rows erased below open two above. At most two complete row pairs
are committed per tick. Partial-row erosion retains the original behavior.

New southern batches retain the 256-tick pathfinding interval. A catch-up
batch drains through small paired steps rather than a 32-row northern burst.
Only the chunks touched by the next strips are prefetched, with one chunk
preparation attempt per controller tick. Unavailable terrain waits; its queue
is bounded. Preparation and recovery retain their original clocks.

The native 16-by-5 assault grid, nest home coordinates, nest group schedule,
Queen implementation, commands, enemy statistics and erosion parameters are
unchanged. The northern line now follows the terrain instead of chunk steps.

Legacy already-open floor is retained. The supplied save starts with the
southern line at -386 and its clearing cursor at -577. Its 190-row distance is
preserved, then both ends advance together. New prepared maps use 160 rows.
Saved pending tiles, row order and cursors remain valid. No opened strip is
repopulated on upgrade or reload.

## Verification performed

- All 371 Lua files parse. Native Factorio 2.0.77 loads the mod in Base-only
  and Space Age environments.
- Production controller checks with mocked native operations cover player
  counts 1, 9, 21 and 36, ordinary and catch-up speeds, native chunk crossings,
  unavailable generation, failed carving, recovery, no-player pauses and
  independent surface state. Every completed lower row has a matching upper
  row in the same tick; no step exceeds two pairs.
- Native Base catch-up observation reaches 36 paired rows in 2,062 updates,
  with a maximum of two pairs per update and an unchanged native chunk grid.
- A native observation on a copy of the supplied save runs 40,000 updates.
  It reaches 36 paired rows by update 36,612, with a maximum of one pair per
  update at ordinary speed. The observed existing resource remains unchanged.
- A native checkpoint retains 120 queued southern tiles, the original commit
  state and the 190-row follow distance. A fresh load runs another 2,400
  updates with independent checks of physical lower floor and upper opening.
- Archive membership, version, source bytes and the changed-file list are
  checked before delivery. Diagnostic hooks and observer mods are excluded.

Native terrain observations use a temporary offline-player controller override
on separate test copies. Test settings match the supplied save. Space Age
tests include the official Space Age, quality and elevated rails mods; the
server's other utility/content mods are not installed in the test environment.
These checks establish paired terrain and serialization. They do not establish
zero frame hitches or a full multiplayer pathfinding regression result.

## Exact files changed from 3.2.46

- `scripts/advancing_clearing.lua`
- `scripts/advancing_collapse.lua`
- `scripts/advancing_area.lua`
- `info.json`
- `changelog.txt`
- Added `TESTING-3.2.47.md`

## Server playtest

1. Load a copy of the current save with 3.2.47 and the same server mods and
   Startup settings.
2. Observe complete lower rows and the northern opening across a chunk
   boundary. The upper edge should advance by the same number of rows, with
   no 32-row burst. Also check the red boundary line.
3. Check normal travel, train catch-up, a recovery break, save/reload and
   disconnect/reconnect. Existing floor and mined resources should stay intact.
4. Confirm wave attackers and nest offspring continue attacking while the
   terrain moves. Live multiplayer attacker movement still needs this check.
5. If a hitch remains, record its position and whether it coincides with
   terrain opening, a wave, a room or another controller.
