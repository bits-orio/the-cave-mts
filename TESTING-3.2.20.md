# The Cave 3.2.20 — test build

Base: the supplied `the-cave_3.2.19.zip`, SHA-256
`149d114afa9956e8c27304f6619bcf515d64954e52f4081db7d01eb07b52b4f6`.

This build implements the four agreed changes. Existing room layouts, already
owned coins/items/buildings, depleted nest balances and starter entitlements are
not reset. Market defaults to Enable. Existing Fortified Cave and Lost Village
switches, train safety and extraction-cave collapse exemptions remain in place.

## Behavior

- Ordinary new digging rooms in every region require one straight corridor:
  10 tiles long, 4 tiles wide. The whole room starts beyond its far end. Validate
  the corridor, room, entrance pad, map bounds and train clearance before carving.
  Try another direction with the same selected room identity; skip if none fits.
  Concave/double rooms receive an entrance connection within their own bounds.
  Existing scheduled Advancing Collapse caves, Train Wave extraction tunnels and
  the separate Demolisher exception retain their current layouts.
- Team tank collisions and weapons use the same full digging pipeline and
  force/surface enemy counter as manual mining. Existing probabilities, caps and
  safe zones remain. Rubble and other ordinary non-tank weapon causes are inert
  or geometry-only as before. Tank/explosion digging does not invent a mining
  inventory buffer, matching the existing TNT callback architecture.
- Startup > Market > Disable hides the shop and blocks trades, fresh coin
  drops/rewards, treasure coin bonuses, starter coins, market-only starter power,
  automatic coin pickup and nest coin displays. Offspring born while disabled
  have zero carry, without consuming/refilling the nest's saved budget. Existing
  stacks, equipment and prototypes remain. Re-enable restores future normal
  rewards without refilling nests, granting duplicate starter packs or backpay.
- Atomic rock deaths are recorded once. The native blast retains its combat
  damage and wave counts. Cave crater tile replacement is suppressed so native
  floor conversion cannot remove existing ores; non-Cave surfaces replay the
  original terrain effects. New resources, rooms, treasure and enemies resolve
  after all tracked damaging waves on that affected surface have finished.
  Completion checks scan only bounded areas, at most once per 15 ticks while
  active; up to eight pending full digs resolve per tick. Overlapping blasts
  extend the wait. Pending work survives save/load and is removed with a deleted
  or cleared surface. A world restart resets it.

## Completed checks

Performed with the real modified Lua modules/functions and mocked Factorio APIs:

- Syntax compilation of every Lua file with Lua 5.4, including the local-variable
  limit of the large caverns module.
- Tank, atomic source attribution, missing optional source markers, deferred
  queues, overlaps, force separation, save/load, duplicate exclusion and cleanup.
- Enabled/disabled coins, finite nest preservation, zero carry, stale shop GUI,
  starter inventory/overflow and other starter items; treasure coin gating keeps
  the existing non-coin loot picks unchanged.
- Real room planner/carver: all five regions, all nine Nauvis shapes, four
  directions, exact corridor dimensions and connected entrances; reject old
  floor, blocked corridors, unsafe train areas and boundary translation before
  carving. Direction retry does not reroll the identity.
- Actual control routing for manual mining, tanks, robots, ordinary weapons,
  rubble, Queen, TNT, Demolisher, room budgets and deferred atomic outcomes.
- Prototype changes against Wube's official Factorio 2.0.77 atomic definitions:
  native damage, projectile speeds and wave counts unchanged; original tile
  effects available for replay outside Cave surfaces.
- Final archive metadata, required module references, asset preservation and ZIP
  integrity checked before delivery.

These are offline checks, not an in-game multiplayer test. No Factorio runtime
was available in this workspace.

## Files changed or added

- `control.lua`, `scripts/caverns.lua`: full-dig routing, deferred integration,
  preflight and the universal room corridor.
- `scripts/weapon_digging.lua`, `prototypes/weapon_digging.lua`,
  `data-final-fixes.lua`: tank/atomic attribution, wave completion and terrain protection.
- `scripts/market_policy.lua`, `scripts/market_coin.lua`, `scripts/treasure.lua`,
  `scripts/starter_pack.lua`: the shop and all fresh currency/starter gates.
- `settings.lua`, `locale/en/market_setting.cfg`, `locale/ru/market_setting.cfg`:
  the default-enabled Startup switch and translations.
- `info.json`, `changelog.txt`, `TESTING-3.2.20.md`: version and test documentation.

## Required in-game tests

Use a copy of the existing save with the server's current mod list:

1. Leave Market at its default Enable. Verify inventory shop, buy/sell, normal
   coin drops and existing discovered cave access.
2. Set Market to Disable and restart/load. Check ordinary/Bob enemies, finite
   nests, waves/recovery and treasure: no new coins. Existing coins and placed
   MK5 remain. A new player's starter pack omits coin/MK5 but keeps other items.
3. Re-enable and reload. New rewards resume; depleted nests remain depleted,
   disabled-period nest offspring do not pay and starter packs are not repeated.
4. Drive a tank through fresh frontier rocks. Repeat with its machine gun,
   cannon and installed supported weapons. Verify resource/room discovery and
   normal enemy pressure, including Bob families when enabled. Compare ordinary
   on-foot weapons and rubble to confirm they retain their old behavior.
5. Mine fresh rocks in each of the five regions. When a room is found, verify
   its 10-by-4 corridor, whole room beyond the far end, traversable entry, and no
   overlap into old floor or train safety areas. Existing rooms remain unchanged.
6. Fire an atomic rocket into fresh Cave rocks. Verify outcomes wait until the
   damaging waves finish, exposed resources match normal digging, existing ore
   amounts are preserved, and enemies/room contents survive the original blast.
   Test overlapping rockets, save/load during a pending blast, multiple forces,
   and firing again into already opened/mined ground. Check UPS during blasts.

Official references used for offline compatibility checks:
- https://github.com/wube/factorio-data/blob/2.0.77/base/prototypes/entity/atomic-bomb.lua
- https://lua-api.factorio.com/2.0.77/runtime-api.json
