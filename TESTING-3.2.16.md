# The Cave 3.2.16 — optional Bob's Enemies support

## Source and scope

Continued only from the delivered `the-cave_3.2.15.zip`. All 1,146 baseline
files were checked byte-for-byte against that archive before implementation.
Enemy names, startup settings, spawner construction and progression were
checked against the supplied `bobenemies_2.1.0(1).zip`, version 2.1.0.
Bob's Enemies and its Bob's Library dependency remain separate installations;
neither mod is included in this archive.

Exact changes relative to 3.2.15:

- Added `scripts/bob_enemies.lua`.
- Updated `scripts/caverns.lua`, `scripts/dig_spawner.lua`,
  `scripts/enemy_nest_growth.lua` and `scripts/cave_enemy_expansion.lua`.
- Updated `scripts/market_coin.lua` and `scripts/ore_blood.lua`.
- Updated `control.lua`, `info.json` and `changelog.txt`.
- Updated `locale/en/locale.cfg` and `locale/ru/locale.cfg`.
- Added this report, `TESTING-3.2.16.md`.

All other baseline files are unchanged. In particular, the Bob Ores layout,
Mobile Factory integration, Uranium Cave resource beds and 30/60-minute
expedition logic are byte-for-byte unchanged.

## Behavior

- The compatibility branch runs only when `script.active_mods.bobenemies`
  exists. With Bob disabled, the original Cave room selection, contents,
  direct-dig intervals, progression and reward paths remain active.
- Eligible ordinary Nauvis nest encounters are distributed equally among the
  original mixed Cave nest room, the existing Arachnid room, and each unlocked
  Bob family: Basic, Piercing, Electric, Acid, Explosive, Poison and Fire.
  Once all are eligible, there are nine equally selected identities. Their
  combined encounter frequency, combat cooldowns, minimum depth, room shape,
  radius and extraction-cave spawner cap are preserved. Other regional rooms,
  specials, hoards and scheduled entrances keep their existing selection.
  Mission interiors retain their exploration/nest encounter pool, with Bob
  identities selected within the nest share and Arachnid rooms still excluded.
- A Bob room uses three same-family nests: two biter nests and one spitter
  nest. Easy/Medium/Hard/Nightmare retain 2/3/4/5 same-family worms. No unrelated
  Queen or manually spawned defender pack is inserted; native Bob spawner
  population limits and cooldowns create the mobile enemies.
- If Bob's Super Spawners startup setting is enabled and raw Cave Evolution
  is at least 0.8, each Bob room has a 10% chance to replace one biter nest
  with its own family's super nest. The other biter nest and spitter nest
  remain. There is at most one super nest, and always three total nests.
  Its native result_units and geometry are unchanged: all supplied ordinary
  and super nests have 4.4-by-4.4 collision boxes and 5-by-5 selection boxes.
- Direct digging keeps the existing events, intervals, count caps and timed
  cave pack sizes. Its five original encounter groups and currently eligible
  Bob family groups have equal group selection chances. A Bob group's biter,
  spitter or worm is then selected within that family.
- Bob biter/spitter tier weights are read directly from the loaded spawner's
  runtime `result_units` at raw Cave Evolution. This respects native prototype
  changes, Bigger Enemies Sooner and Leviathan Frequency. No new eight-tier
  progression curve is introduced. Worms use Bob's adjacent-tier selection.
  The native tier order is Small, Medium, Big, Huge, Giant, Titan, Behemoth,
  Leviathan. Original groups retain their original Cave tier/difficulty bias.
- Family availability follows Bob's configured faction list and three unlock
  groups. Defaults unlock the six elemental families in pairs at Evolution
  0.5, 0.6 and 0.7. Removed/incomplete families are excluded. Basic remains
  eligible throughout.
- **Randomize Enemies limitation:** Bob keeps its shuffled faction order in
  private mod storage and exposes no runtime getter for it. With that optional
  setting enabled, Cave uses the same one-time Fisher-Yates algorithm with an
  independently seeded, saved room unlock order. Its order can differ from
  Bob's open-world order. With the default setting disabled, the configured
  family order and thresholds match Bob. Unit tier weights always come from
  Bob's actual loaded prototypes, regardless of this setting.
- Direct-dig Bob survivors can establish a same-family nest through the
  existing settler controller. Bob direct-dig worms mature into a nest of
  their own breed. The original direct-dig worm group retains its existing
  weighted-family maturation rule. Existing expansion settings still apply.
- Native expansion from a Bob nest retains its source family, including
  super nests. A bounded destination reconciliation handles Bob replacing
  the event entity before Cave sees it. It preserves quality, existing
  neighbouring nests, and newly scripted room/Queen/settler/dig base parts.
  Only active Cave migrations are inspected; no new surface-wide scan or
  tick task is added.
- Coins and Ore Blood use the approved table below for all seven breeds.
  Bob nests join the existing finite Coin Value budget with unchanged zone
  ranges: Easy 100–500, Medium 250–1,000, Hard 500–2,500, Nightmare 1,000–5,000.
  Native spawned units reserve coins from that budget, including partial or
  zero carry when depleted. Nest destruction does not refund remaining coins.
  Brood suppression remains respected. Ore Blood is a random basic resource
  bundle for biters/spitters only, respecting its existing feature switch,
  stack sizes and timed extraction-cave exclusion.

| Size | Biter/spitter coins | Worm coins | Biter/spitter Ore Blood |
|---|---:|---:|---:|
| Small | 1 | 2 | 10–20 |
| Medium | 2 | 4 | 20–40 |
| Big | 3 | 8 | 40–80 |
| Huge | 4 | 10 | 50–100 |
| Giant | 4 | 12 | 60–120 |
| Titan | 5 | 14 | 70–140 |
| Behemoth | 5 | 16 | 80–160 |
| Leviathan | 10 | 32 | 160–320 |

## Verification

No Factorio executable was available. These are Lua 5.4 parser checks and
mocked Factorio API tests using the actual Cave runtime modules and native
Bob source-derived prototypes; they are not an engine or in-game test.

- Syntax: all 347 Lua files parsed successfully, including the large cavern
  module's local-variable limit.
- Bob Enemies suite: 12 scenarios, 429,344 assertions passed.
  - Seven families, eight sizes, 16 Evolution samples, Bigger Enemies Sooner
    on/off and Leviathan frequencies 0, 0.05 and 1. Selected biter/spitter
    units stay within the source-derived native spawn curves.
  - Family gates, missing prototypes, removed factions and saved shuffle;
    equal room/dig identity selection; native worm windows.
  - Three nests, at most one super, exact 10% roll coverage, Evolution and
    startup gates, and matching native nest footprints.
  - Production coin handlers: finite budget, partial and zero carry, no
    depleted-budget fallback, no nest refund and no duplicate brood reward.
    Production Ore Blood checks cover bundles, stack splitting and exclusions.
  - Production growth controller completes same-breed worm maturation and
    mobile settler nesting; original worm family selection is retained.
  - Production expansion event handles an already-invalid native event
    entity, maintains breed and quality, protects old neighbours and newly
    scripted nearby base parts, and does not repeat replacements.
  - Actual room selector matches 3.2.15 with Bob disabled for 20,480 seeded
    selections across four zones, five regions, main/mission surfaces and
    combat cooldown states. Original nest contents and Queen calls match.
  - Actual Bob room population tested for all seven families, four zone
    levels and 64 seeds: three nests plus exactly 2/3/4/5 same-family worms.
    Actual room selection preserves the old combined combat frequency and
    special/unrelated room results across 4,000 seeds.
  - Actual direct-dig pipeline compared with 3.2.15 at all four difficulties
    on main and timed cave surfaces. Bob-off output, state and registrations
    match. Bob-on event counts/pack sizes remain unchanged, with all families
    represented. Absent-Bob helpers require no prototype access or scan.
- Bob Ores regression suites rerun against 3.2.16:
  - Optional compatibility: 10 scenarios, 25,264 assertions.
  - Separated deposit/core/Mobile Factory integration: 17 scenarios,
    1,559,635 assertions.
  - Planetary/Advancing Collapse boundaries: 2 scenarios, 64,939 assertions.
  - Uranium Cave resources, depletion and 30/60-minute operation: 13 scenarios,
    742,409 assertions.
- Release diff reviewed; optional dependencies and locale keys checked;
  archive content, CRCs and every packaged file checked against the release
  working tree before delivery.

## Remaining in-game check

1. Enable The Cave 3.2.16, the supplied Bob's Enemies 2.1.0 and its required
   Bob's Library separately. Start a fresh test map using the intended Cave
   startup settings. Keep Bob's Randomize Enemies off for the native default
   family unlock order.
2. Dig below the existing encounter depths and across each Evolution unlock
   threshold. Verify each Bob room has three nests of one breed, ordinary
   native population appears, and worm counts follow the existing zone.
   The default elemental families do not all appear at low Evolution.
3. At Evolution 0.8 or higher with Super Spawners enabled, inspect several Bob
   rooms: occasional rooms should have one super plus two ordinary nests.
   Switch Super Spawners off and verify new rooms have no super nests.
4. Check digging encounters at low/high Evolution; enable the existing Biter
   Expansion feature and leave Bob survivors/nests alive long enough to
   establish new nests. Confirm same-breed expansion and no alteration of
   neighbouring newly opened rooms. Check late-tier units and native super
   population in the actual Factorio engine.
5. Kill Bob units/worms, check approved coins and unit Ore Blood, then deplete
   a nest's Coin Value and confirm no coin replenishment. Verify Ore Blood
   switches and extraction-cave exclusions.
6. With Bob's Enemies disabled, start a fresh map and verify original Cave
   encounters only. Recheck Bob Ores deposits, separated companion fluids and
   the existing 30/60-minute Uranium Cave behavior with Bob Ores off/on.
