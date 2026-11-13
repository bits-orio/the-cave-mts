# The Cave 3.2.12 - Recovery Break rendering fix

Base: the confirmed original `the-cave_3.2.11.zip` only.

## Fix

Soft reset previously wiped the saved rendering IDs while position-based area
renderings survived the surface clear. Those old green markers then stayed
visible even though the new run's waves and collapse front advanced normally.

The configuration-change hook removes this mod's exact area labels and their
matching outlines, then rebuilds the current indicator from the existing saved
state. A pre-wipe soft-reset callback destroys area renderings while their IDs
are still available. The cleanup also recovers already orphaned markers.

The supplied save contains orphaned green IDs 4/5 at rectangle corners
(-64, -546) and (64, -386), with the label at (0, -544) showing 00:17:41.
Its current saved state is active wave 50, front Y=-286, no recovery deadline,
and current rendering IDs 1203305/1203306. Cleanup targets the old objects and
rebuilds the current combat marker; it does not reset the map or wave state.

## Exact changed files

- `scripts/advancing_area.lua`: scoped rendering cleanup; existing drawing and supplies logic unchanged.
- `scripts/advancing_collapse.lua`: cleanup at initialization/configuration change and public reset hook.
- `scripts/soft_reset.lua`: invoke cleanup before clearing storage.
- `control.lua`: wire the existing soft-reset callback configuration.
- `info.json`: version 3.2.12 only.
- `changelog.txt`: 3.2.12 entry.
- `TESTING-3.2.12.md`: this new validation note.

All other archive files, including gameplay scheduling, prototypes, dependencies,
locale, graphics and audio, are byte-for-byte identical to 3.2.11.

## Automated checks

- All 344 Lua files parsed with a Lua 5.4 host. Added code uses Lua 5.2-compatible syntax.
- Seven focused regression checks executed the actual modified Lua modules with mocked Factorio APIs:
  1. The supplied save's stale/current rendering IDs and wave/front values: stale markers removed, current combat marker rebuilt, wave deadlines and terrain cursor preserved.
  2. Unrelated text/sprites/rectangles, another mod's objects, other surfaces and force-specific renderings preserved.
  3. Existing recovery deadline preserved; countdown advances; expiry returns to combat. Ordinary/special break durations remain 15/30 minutes.
  4. Disabled Advancing Collapse cleans stale markers without starting waves.
  5. Preparation/combat markers on multiple surfaces clean correctly; repeated cleanup is safe.
  6. Actual soft-reset wipe stage calls cleanup before losing saved IDs and then advances normally.
  7. Fresh initialization removes untracked leftovers and keeps the original two-hour countdown.
- ZIP CRC, single root folder, metadata version and byte comparison against 3.2.11 checked before delivery.

## Required in-game test

Factorio is not installed in the build environment; these are not engine or
multiplayer gameplay test results.

1. Install 3.2.12 and open a copy of the supplied existing save. No console command or map reset is required.
2. Confirm the frozen green 00:17:41 Recovery Break text and its old outline disappear. The current combat outline remains at the saved front and the wave number continues from the save.
3. Save/reload and confirm the old marker stays gone.
4. At the next real Recovery Break, confirm the green countdown decreases and returns to red when it expires.
5. On a disposable test save, perform the normal soft reset and confirm only the new run's preparation marker remains.
