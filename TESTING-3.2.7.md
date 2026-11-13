# The Cave 3.2.7 — Advancing Collapse test build

Built exclusively from the supplied `the-cave_3.2.6(2).zip`.

## Expected schedule

Enable Advancing Collapse when creating a new game. Enable Uranium Caves,
Iron Cave, Copper Cave, Coal Cave and Underground Village to test all six types.
Underground Village is disabled by default in the original mod; that default
and all existing feature switches are preserved.

| Zone | Fortress | Uranium | Lost Village | Iron | Copper | Coal |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2 | 1 | 0 | 0 | 1 | 1 | 1 |
| Odd, from 3 | 1 | 1 | 1 | 0 | 0 | 0 |
| Even, from 4 | 1 | 1 | 0 | 1 | 1 | 1 |

New zones are 1024 tiles deep (32 chunk rows). The existing 510-tile map width
still spans 16 horizontal chunk columns. Only columns 2–15 can receive caves.
Each entrance is centred at `(chunk_x * 32 + 16, chunk_y * 32 + 16)`.
All six cave types share one exclusion rule: the selected chunk and its eight
neighbours cannot contain another scheduled cave. This also applies between
successive zones. Cave structures and interiors retain their existing sizes.

Locations are deterministic, stored in the save and revealed when digging in
the selected chunk. Generating or charting a zone alone does not create all its
entrances. Disabled types retain their reserved locations; enabling a type
allows discovery at the same location, without moving the other caves.

## Existing saves

Test using a copy of an existing Advancing Collapse save. All zones containing
generated terrain, including a partly generated next zone, retain their old
704-tile dimensions and original cave discovery rules. Only the first fully
ungenerated zone and subsequent zones use the new dimensions and schedule.

For example, if any terrain in zone 41 was already generated, zones 1–41 stay
as they were and zone 42 begins the new 1024-tile layout. Zone 42 is even and
therefore has Fortress, Uranium, Iron, Copper and Coal. The transition is saved
once; loading or changing configuration again does not move it. Generation
ahead of the player can make this boundary later than the displayed zone.

MTS team maps share the existing zone geometry and biome pool. The furthest
generated zone across the main maps sets the saved transition for all of them;
each surface stores its own entrance schedule and ownership.

## Gameplay checks to run

1. In a new game, explore the first five zones and check the table above. Check
   that low evolution and ordinary cavern chance do not prevent scheduled caves.
2. Check cave centres, excluded edge columns and the one-chunk ring in all
   eight directions, including caves on opposite sides of a zone boundary.
3. Save/load after discovering some caves. Confirm locations do not change and
   completed entrances do not appear twice. Closed entrances do not respawn.
4. Discover a planned site near the Main Train or a player building. Placement
   waits without clearing player assets. Moving the obstruction allows retry
   at the same centre. The player's character can also block a site; step away.
5. Enter each cave and check the original transfer equipment, timer, return
   route and contents. Test Fortress at zones 2, 10 and 20, and caves in unlocked
   Space Age regions. These require the actual Factorio engine.
6. Load the old-save copy, check existing terrain and zone labels, then explore
   past the saved transition. Save/load once more and confirm the transition.
7. Check a game with Advancing Collapse disabled: ordinary cave discovery should
   retain its previous behaviour. Existing generated Advancing zones also keep
   the original discovery rules.

## Automated validation performed

- Every production Lua file parsed successfully with the available Lua 5.4
  host. Factorio itself was unavailable; this is not engine validation.
- Planner and migration: 586,613 assertions, including 39,600 placements over
  100 map seeds, exact quotas, chunk centres, border exclusions, neighbouring
  zones, partial-zone migration, reload persistence and per-surface state.
- Cavern integration: 4,058 assertions with mocked Factorio APIs, including
  zero-evolution discovery, train/player blocking, failed-placement retries,
  one-time registration, all cave families and legacy-selection regression.
- Actual entrance-creator routing: 43 assertions with mocked hardware/engine
  APIs, covering legacy-gate bypass, exact centres, fixed mineral types,
  unchanged legacy mineral deck, rollback and duplicate prevention.

These tests exercise Lua logic. Collision behaviour, visuals, real save
migration, MTS cloning and gameplay performance still need in-game testing.

## Exact changes from 3.2.6

| File | Change |
| --- | --- |
| `scripts/advancing_caves.lua` (new) | Persistent chunk schedule, shared exclusion rings and pending-site retries. |
| `scripts/advancing_zones.lua` | New depth and saved legacy/new layout boundary. |
| `scripts/advancing_collapse.lua` | Mark new-world zone initialization explicitly. |
| `scripts/caverns.lua` | Scheduled discovery, fixed centres, quota enforcement and existing creator integration. |
| `scripts/cave_placement.lua` | Include explicit entrance centre in footprint bounds. |
| `scripts/uranium_caves.lua` | Accept scheduled sites; retain legacy gates elsewhere. |
| `scripts/mineral_caves.lua` | Accept fixed scheduled types without consuming the legacy resource deck. |
| `scripts/lost_city.lua` | Accept scheduled Village sites with exact centres. |
| `scripts/fortified_vaults.lua` | Honour the scheduled entrance centre. |
| `control.lua` | Initialize scheduler on new worlds and run bounded retries. |
| `locale/en/locale.cfg` | Update Advancing Collapse dimensions and migration explanation. |
| `locale/en/settings.cfg` | Update Advancing Collapse setting description. |
| `locale/ru/locale.cfg` | Update Advancing Collapse dimensions and migration explanation. |
| `locale/ru/settings.cfg` | Update Advancing Collapse setting description. |
| `info.json` | Version 3.2.7. |
| `changelog.txt` | Add release notes. |
| `TESTING-3.2.7.md` (new) | This test guide. |

All other files are byte-identical to the supplied 3.2.6 archive.
