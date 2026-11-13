# The Cave 3.2.8 — four-band Advancing Collapse test

This build continues exclusively from the delivered 3.2.7 ZIP. The older
TESTING-3.2.7.md is retained as historical documentation; use this guide for
the new four-per-type schedule.

## Expected new-zone layout

Zone dimensions stay at 16 horizontal chunk columns by 32 chunk rows, within
the existing 510-tile-wide ribbon. A new zone is split along the northbound
direction of travel into rows 1–8, 9–16, 17–24 and 25–32.

Each band contains one randomly selected chunk for each cave type allowed in
that zone. This gives four of each eligible type, distributed along the zone.

| Zone | Fortress | Uranium | Lost Village | Iron | Copper | Coal | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2 | 4 | 0 | 0 | 4 | 4 | 4 | 16 |
| Odd, from 3 | 4 | 4 | 4 | 0 | 0 | 0 | 12 |
| Even, from 4 | 4 | 4 | 0 | 4 | 4 | 4 | 20 |

The table assumes all relevant cave switches are enabled. Underground Village
remains disabled by default. Disabling a type keeps its reserved positions but
prevents its entrances from being created; other types do not move.

Horizontal columns 1 and 16 remain excluded. Every entrance remains at its
chunk centre. The selected chunk and its eight neighbours exclude all other
scheduled caves, including across the four band boundaries and zone borders.
All existing entrance sizes, cave interiors, rewards and timing remain intact.

## Existing saves

On the first upgrade to 3.2.8, the mod preserves all generated/partly generated
zones and any zones with stored 3.2.7 cave plans. The first zone beyond this
retained range starts the four-band schedule. Saved centres, ownership,
created/closed entrances and pending discoveries are not rerolled or duplicated.

The boundary is shared across main/MTS maps, matching their shared zone
geometry, while cave state and ownership remain separate per surface. The
boundary is saved once and does not advance on subsequent reloads or changes
to settings. Previously planned zones can extend ahead of visible exploration.

For example, if zone 41 contains generated terrain and no later zone has a
saved cave plan, the new density starts at zone 42. Zone 42 has four each of
Fortress, Uranium, Iron, Copper and Coal, spread over its four bands. Retained
3.2.7 zones keep their one-per-eligible-type schedule. Existing 704-tile zones
from earlier saves still retain their old dimensions and discovery rules.

New games and soft resets use the four-band policy immediately; zone 1 still
has none of these six types. A fresh game is the clearest way to compare the
new distribution in zones 2–5.

## In-game checks still required

1. Enable Advancing Collapse and the desired cave types, including Underground
   Village if testing all six. Explore zones 2–5 and compare the table above.
   Check that every eight-row band has one of each eligible cave type.
2. Mine within candidate chunks. Entrances are revealed by digging in their
   selected chunk; charting the map or walking nearby alone does not reveal
   them. A narrow route can still miss caves elsewhere across the map width.
3. Check Fortress and the other entrances near both stationary and moving Main
   Trains. The existing 50-tile margin around every connected Main Train part
   remains in force. A blocked discovered site waits and retries at the same
   position when the obstruction leaves. Player buildings and characters can
   also block placement; no extra cave should be created as compensation.
4. Enter the cave types and check their original hardware, timers and return
   routes. Test unlocked Space Age regions and MTS team maps when applicable.
5. On a copy of a 3.2.7 save, verify existing entrances stay in place, then pass
   the retained-zone boundary. Save/load and check the new locations and counts
   again. Monitor gameplay performance with several caves active.

Increasing density addresses the number and distribution of potential finds.
It does not establish the cause of the earlier report of a missing Fortress.
Real engine collisions, graphics, actual save upgrades and multiplayer gameplay
were not available in this environment and must be checked in Factorio.

## Checks completed outside Factorio

- 158,400 planned entrances over 100 seeds and 100 zones per seed: exact counts,
  one of every eligible type in each band, centred placement, excluded columns,
  and shared exclusion rings across band and zone boundaries.
- Forced random collisions exercised the bounded fallback. It stayed within
  its eight-row band without losing quotas or relaxing spacing.
- Planner/migration suite: 2,290,078 assertions. Includes deterministic order,
  simulated save/load, feature switches, ownership, pending retries and cleanup.
- 3.2.7-to-3.2.8 density upgrade: 358 assertions, including actual old-planner
  state, partially generated zones, untouched V1 coordinates, pending aliases,
  plans ahead of generation, MTS boundaries, direct 3.2.6 upgrade and soft reset.
- Cavern integration: 4,211 assertions using mocked engine APIs, including all
  four bands of each eligible cave family, train/player blocks, failure/retry,
  duplicate prevention and ordinary-mode regression.
- Actual entrance-creator routing with mocked hardware/engine APIs: 63
  assertions, including retaining the other three copies after one is created.
- Production Lua syntax and release archive integrity checks are performed
  before packaging. The available validation host is Lua 5.4, not Factorio.

## Exact file changes from 3.2.7

| File | Change |
| --- | --- |
| `scripts/advancing_caves.lua` | Four-band allocation, bounded per-band fallback and saved density-upgrade boundary. |
| `control.lua` | Run cave-schedule migration after existing zone-geometry migration. |
| `info.json` | Version 3.2.8. |
| `changelog.txt` | Add release notes. |
| `TESTING-3.2.8.md` (new) | This guide. |

All other files are byte-identical to the delivered 3.2.7 ZIP. No prototype,
graphics, locale, dependency, train-safety, cave-content or zone-size changes
are included in this update.
