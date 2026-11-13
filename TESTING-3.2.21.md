# The Cave 3.2.21 — test build

Base: the delivered and user-tested `the-cave_3.2.20.zip`, SHA-256
`27a9ec9c23ac6f541723642b1314c7b7f7d04afaaceeaef591d36a252f1d1369`.

## Change

New ordinary digging rooms use a straight corridor exactly 20 tiles long and
6 tiles wide. The entire room starts beyond the far end, at tile 21 measured
from the triggering dig tile. The six-wide connection continues inside the
room, clipped to its existing bounds for narrower shapes.

This applies to the shared full-dig pipeline: manual mining, team tanks and
their weapons, TNT boxes and deferred atomic digging, in Nauvis, Gleba,
Vulcanus, Fulgora and Aquilo regions. The complete 20-by-6 corridor and room
are checked before carving, using the existing closed-ground, reserved-area,
map-boundary and train-clearance rules. Another direction may be tried with
the same selected identity; a room is skipped if no direction fits.

Existing discovered layouts are preserved. Separate scheduled Advancing
Collapse caves, Train Wave extraction corridors and Demolisher exceptions
retain their prior layouts. Room chances, rewards, counters, Market settings
and atomic timing are unchanged from 3.2.20. No save migration is needed for
this geometry change.

## Exact files changed from 3.2.20

- `scripts/caverns.lua`: corridor validation footprint, carving, endpoint and
  internal entrance connection dimensions.
- `info.json`: version 3.2.21.
- `changelog.txt`: new version entry; older entries preserved.
- `TESTING-3.2.21.md`: this test guide, added.

## Offline verification

- Lua syntax compilation and JSON metadata validation.
- Actual room planner/carver with mocked Factorio APIs: all five regions,
  all nine Nauvis room shapes and all four directions; exactly 120 distinct
  corridor cells, length 20, width 6, room edge at tile 21, connected entry
  and internal connection contained within the original room bounds.
- Reject uncovered ground at the widened sides and far end, player assets,
  train exclusions, reserved areas and map boundaries before carving.
  Frontier cover remains eligible; direction retry preserves room identity.
- Existing full-dig control-routing checks: manual mining, team tank,
  TNT and deferred atomic outcomes.
- Archive integrity, root/version and byte comparison against the base:
  only the four files above may differ or be added.

These checks run outside the game. No Factorio runtime is available here.

## In-game test

Use a copy of the tested save and the same mod list. Find new rooms in each
region using manual mining, tank digging/weapons, TNT and an atomic rocket.
Count 20 corridor tiles before the room and six tiles across, then walk through
the entrance. Test near opened ground, map edges and the train safety area.
Confirm previously discovered rooms keep their original geometry.
