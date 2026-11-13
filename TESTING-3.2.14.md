# The Cave 3.2.14 — optional Bob's Ores mining caves

## Source and scope

Continued exclusively from the delivered `the-cave_3.2.13.zip`, whose source
was the user's `the-cave_3.2.12(3).zip`. Before editing, all 1,143 files in the
3.2.13 working copy were compared byte-for-byte with the delivered archive.
No other Cave branch or Bob mod code was merged or bundled.

Changed files relative to 3.2.13:

- `scripts/bob_ores_resources.lua`
- `scripts/uranium_caves.lua`
- `locale/en/locale.cfg`
- `locale/ru/locale.cfg`
- `info.json`
- `changelog.txt`
- Added this report, `TESTING-3.2.14.md`.

Bob's Ores and Bob's Library remain optional, separate installations. Bob's
Enemies is outside this change. Resource prototypes, acid requirements,
drill speeds, mining productivity, scrap sorting, oil/water placement,
Mobile Factory, cave entrance rules and transfer infrastructure are unchanged.

## Agreed behavior

- At the first successful entry, an expedition gets 60 minutes if `bobores`
  is active; otherwise it gets the original 30 minutes. The thorium checkbox
  does not control the timer. No new setting is added.
- Already-started expeditions retain their saved deadline when upgrading,
  adding or removing Bob's Ores, saving/loading or re-entering. Discovered
  entrances that have not been entered use the mod state at first entry.
- Old saves with a start tick but no deadline/duration retain a 30-minute
  interpretation. The five-minute warning and permanent-collapse behavior
  remain unchanged. Each force still has its own expedition lock.
- With Bob's Ores active, newly opened Uranium Cave tiles reveal separate,
  dense beds of uranium, The Cave salvage scrap and enabled Bob's thorium.
  Default bed size is 32 x 32 tiles, with four-tile gaps. Existing patch-size
  settings scale bed width from 28 tiles at level 1 to 56 at level 8.
  Resource types cycle between whole beds so every adjacent run of three
  bed columns/rows includes all three. The existing arrival exclusion remains.
- Each resource's per-tile amount is 10 times the previous Uranium Cave range:

| Depth | Amount per resource tile with Bob's Ores |
| --- | ---: |
| Medium | 5,000–8,000 |
| Hard | 7,000–11,000 |
| Nightmare | 9,000–14,000 |

- Thorium requires both the active Bob's Ores mod and its final enabled
  resource prototype. A disabled/missing thorium prototype leaves its bed
  locations empty; it does not move uranium or scrap beds.
- Without Bob's Ores, newly generated uranium/scrap retain exactly the old
  deterministic tendril geometry, amount ranges and 50/50 selection.
- New upper-surface Bob veins exclude thorium. The stable indices of the
  other 12 solids are retained, so their fields do not move.
- This is a generation change, not a destructive map migration. Previously
  exposed resources, including old upper-surface thorium, are not removed,
  relocated, increased or regenerated. Dig new areas to see the new beds.
- Bed depletion is remembered per cave in compact numeric chunk-row masks.
  Duplicate callbacks, reloads and optional-mod toggles do not refill those
  tiles. Masks are discarded when the child surface is deleted or cleared.
- English/Russian guidance and the information panel explain the optional
  behavior. Entry messages show the actual remaining countdown.

## Verification performed

No Factorio executable was available. These are syntax and mocked-runtime
checks, not an engine startup, multiplayer server run or in-game mining test.

- Parsed all 345 Lua files successfully with the available Lua 5.4 parser.
  Production edits use syntax already supported by the project's Lua code.
- Passed 13 mining-cave scenarios using the actual Cave modules, hash and
  simplex noise with mocked Factorio surfaces/entities/forces/storage:
  - Exact no-Bob resource-field comparison with 3.2.13 over three seeds.
  - Nearby complete 32 x 32 beds of every resource, service gaps, arrival
    exclusion and richness ranges. Each complete Medium bed holds at least
    5,120,000 resource units before productivity.
  - Thorium disabled/absent and unchanged uranium/scrap locations.
  - Duplicate calls, partial/depleted mining, positive/negative chunk-row
    boundaries, copied save state, module reload and Bob off/on transitions.
  - Invalid/unregistered/wrong surfaces, blocked/void/water tiles, existing
    resources, closing caves and retry after entity-creation failure.
  - Hard/Nightmare ranges and minimum/maximum/legacy patch-size settings.
  - Independent cave/force state and deterministic matching fields.
  - Existing child cleanup preserves partially mined thorium. No new
    generated-tile or resource sweep was introduced; the existing legacy
    cleanup pass is unchanged except that it now accepts thorium.
  - Deleted, cleared and reused surface state.
  - First-entry 30/60 clocks, previews, remaining-time strings, no reentry
    reset, legacy missing deadlines, start tick zero and optional-mod changes.
  - The public tick handler's five-minute warning and exact 30/60 closure.
  - Force locks, administrative evacuation and closed-cave guards.
- Passed the 10 previous Bob-adapter regression scenarios, updated to require
  12 upper-surface solids and zero new upper-surface thorium. These cover
  per-resource enablement, Space Age tungsten/regions, team surfaces,
  oil companions, minimum 15-tile spacing, yield, persistence, obstacles,
  Mobile Factory coexistence, failed placement retries and paving preservation.
- Reviewed the runtime diff, all changed callers, saved fields and lifecycle
  cleanup. No new event registration, per-tick scan or whole-surface migration
  was added.
- Checked version/folder consistency, EN/RU keys and placeholders, unchanged
  file contents, ZIP entry uniqueness, CRC integrity and archive contents.

## In-game verification still required

1. Install 3.2.14 with Bob's Ores 2.1.2 and its required Bob's Library. Enable
   thorium and Uranium Caves. Use a discovered cave that has never been entered:
   confirm 60:00, then dig enough new space to expose several complete beds.
2. Place multiple normal and Cave Filter/MK mining drills on each resource.
   Supply sulphuric acid and power. Confirm their real footprint, recipe
   selection and output, and move the output through the existing linked belts.
   Per-drill speed itself has not been increased; the extra floor coverage
   permits more drills to work in parallel.
3. Save and reload during the expedition. Re-enter and confirm the remaining
   time is preserved. Confirm the warning begins at 05:00 and the expedition
   closes at 00:00.
4. On copies of a save, test adding/removing Bob's Ores with an expedition in
   progress: the started cave keeps its deadline and the next unstarted cave
   adopts the new 30/60 duration. Previously revealed resource amounts stay
   unchanged; removing a mod may remove that mod's entities through Factorio.
5. Check the normal no-Bob 30-minute cave, the thorium-disabled Bob cave,
   multiplayer force isolation and relevant Base/Space Age configurations.

Keep a copy of the save before testing. Normal cave collapse is lethal and
permanent, as in the existing Cave design.
