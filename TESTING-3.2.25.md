# The Cave 3.2.25 - Vulcanus progression-room collapse test build

Based only on the delivered 3.2.24 archive that the user tested successfully
for Bob evolution balance. Its Remote View and Bob compatibility fixes remain.
No 3.2.22 branch changes are merged.

Baseline 3.2.24 ZIP SHA-256:
`2326f3fdcece51584a25faaa899b21e7c4d0921501d6d285c7978a049fca2405`.

## Problem and corrected behavior

Opening a Vulcanus progression room previously ran a private guardian roll
that could create a small, medium or big Demolisher. That room is now populated
with its progression materials and props without running a Demolisher spawn.
The guardian-only helper, selection table and random stream are removed.
Calcite, coal, tungsten ore, sulfuric-acid geyser, lava, volcanic rocks, trees,
room radius, research prerequisites and resource amounts keep their existing
placement rules. Other regional content and the Advancing Collapse Demolisher
profile/rebalance code are retained.

The reported crash was in `collapse.lua`, accessing `entity.name` after the
entity became invalid. A collapse tile query can return multiple segments of
one Demolisher. Killing one of them invalidates other references already in
that query's result. The loop now checks each entity's current `valid` value
before accessing its name, type or health. This follows Factorio's LuaEntity
validity guidance and covers both timed roof collapses and sparse collapses:
https://lua-api.factorio.com/latest/classes/LuaEntity.html#valid

No migration or world-wide removal is added. Existing Demolishers remain;
the collapse guard also protects the invalid-reference path for those units.
Roof stability, warning timers, rubble density, crush/remains rules and enemy
health/balance are unchanged. There is no new recurring scan or tick handler.

## Exact changed files relative to 3.2.24

- `scripts/region_features.lua`: remove progression-room Demolisher spawning.
- `scripts/collapse.lua`: recheck live entity validity inside the crush loop.
- `info.json`: version 3.2.25; other metadata/dependencies remain.
- `changelog.txt`: release notes.
- `TESTING-3.2.25.md`: this new guide. Earlier test guides remain in the archive.

## Completed checks

- All 352 Lua files passed syntax loading with the available Lua 5.4 library.
- Forty focused mocked collapse scenarios used the actual runtime module and
  its public `sparse_collapse`/`on_heartbeat` entry points. The 3.2.24 baseline
  reproduced the invalid-entity error in both paths, with crushed-remains on
  and off; 3.2.25 passed. Ordinary deaths/rubble/query behavior matched the
  baseline for live supports, resources/corpses, water, cleared terrain,
  supported geometry, disabled/exempt surfaces and sparse density outcomes.
- Factorio 2.0.77 headless created maps with the unmodified release source in
  Base and Space Age + Quality + Elevated Rails. Startup defaults were used
  for these load checks. Bob and the full server mod pack were absent.
- Native regression fixtures used temporary copies of the control script,
  with Cave Collapses enabled. Sixteen progression rooms across four planet
  difficulty distances and four seeds were generated with real Space Age
  prototypes. The old version spawned three guardians; the fixed version
  spawned zero. All sixteen rooms retained `progression_ready=true`, four
  calcite/coal/tungsten entities each, one acid geyser, twenty Big volcanic
  rocks and twenty Huge volcanic rocks. Other total content differed only
  by the removed guardians.
- Real 42-segment Demolishers were collapsed through both public paths.
  A folded-body fixture placed multiple real segments in a tile query:
  3.2.24 returned the same invalid-LuaEntity error in both paths; 3.2.25
  killed the unit and continued placing rubble without that error. A straight
  body also passed. Stress was fixed at the normal unsupported value, 4.0,
  to isolate the real entity-query/death loop; this is not a replay of the
  user's save or a full natural-timer/movement gameplay test.
- Archive CRC, root/version metadata, unchanged dependencies and byte-level
  comparison with the exact 3.2.24 ZIP are checked. Only the five files above
  differ. The Bob balance modules and Remote View changes are byte-identical
  to 3.2.24. Diagnostic commands and test fixtures are excluded from release.

The original supplied save is not modified. Space Age's existing Gleba
spawner collision-mask warning is outside this change; map creation succeeds.

## User test

1. Activate 3.2.25 as the The Cave package and load a copy of the save with
   the same server mod pack and Cave Collapses enabled.
2. Open four NEW Vulcanus progression rooms at different locations. Opening
   the room must not create a Demolisher. Check that calcite, coal, tungsten,
   acid, lava and the volcanic rocks are available as before.
3. Allow an unsupported room's roof countdown to finish. Its existing roof
   rules still apply; a collapse should continue without the reported
   invalid-LuaEntity error. Adding supports should retain the old behavior.
4. On a disposable save copy, also check collapse near an already-existing
   Demolisher. Existing units are not automatically deleted by upgrading.
5. Save/load and repeat with another Force in multiplayer. The complete
   server pack, natural movement/timing and multiplayer still need this
   gameplay verification. Keep the Bob balance that already tested correctly.

For a failure, record Factorio/mod versions, Startup scenario settings,
surface/position, whether the room/unit was new or already saved, and the
complete error text or screenshot.
