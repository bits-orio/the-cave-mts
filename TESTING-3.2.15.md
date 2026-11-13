# The Cave 3.2.15 — separated Bob ore deposits

## Source and scope

Continued only from the delivered, user-tested `the-cave_3.2.14.zip`.
Before copying the working tree, all 1,144 files were checked byte-for-byte
against that release. No other branch or Bob mod code was merged or bundled.

Changed files relative to 3.2.14:

- Added `scripts/bob_ore_layout.lua`.
- Updated `scripts/bob_ores_resources.lua`.
- Updated `scripts/ore_veins.lua`.
- Updated `scripts/mobile_factory_resources.lua`.
- Updated `info.json` and `changelog.txt`.
- Added this report, `TESTING-3.2.15.md`.

## Behavior

- Each upper-surface Bob deposit contains exactly one resource. Overlapping
  independent Bob noise fields are replaced by broad, connected oval deposits
  with lightly irregular edges and deterministic positions/orientation.
- A 64-by-64-tile allocation cell holds one deposit. Each complete group of
  four by three cells assigns one slot to every one of the 12 supported upper
  ores, using a seed-dependent shuffle. Disabled ores leave their own slot
  unused without moving other ores. Final resource prototypes still decide
  enablement. Space Age tungsten stays excluded; thorium stays underground.
- Default deposit bounds are 30 by 20 tiles, rotated in some cells. The existing
  Resource Patch Size setting scales bounds from 27 by 18 at level 1 to 48 by
  32 at level 8. Rounded edges and obstacles reduce the filled tile count.
  Per-tile ore richness and mining requirements are unchanged.
- Core and Mobile Factory solid generation share the same prospective
  reservation. They leave at least five empty tiles around the Bob deposit
  bounds, even if the neighbouring terrain is dug later. Different Bob
  deposits also remain separated. This supports clean placement of ordinary
  drills; oversized mining areas from other mods can span a larger distance.
- With Bob active, core/Mobile Factory veins leave gaps at these reservations;
  their existing geometry, amounts and selection continue outside them.
  Simply rejecting Bob tiles wherever an existing vein crossed would nearly
  eliminate Bob resources in dense Classic mode, so exclusive reservations
  are necessary to keep both resource sets available.
- With Bob absent, or every upper Bob solid disabled, core and Mobile Factory
  ore output matches 3.2.14. Uranium/mineral caves and other private surfaces
  are outside this allocation. The arrival area and planetary boundaries are
  protected. Water, void, existing resources and custom resource categories
  remain respected.
- Bob solids also leave prospective regular oil centres and the registered
  starter-oil discovery area free. Oil placement, triggers and yield have not
  changed. Ground Water/Lithia Water companions still use the existing single
  wells, minimum 15-tile centre spacing and clear pump footprints.
- Geometry caches hold at most 256 cell descriptors and contain no entity
  references. No surface scan, tick task or old-save resource migration was
  added. This release changes generation of newly opened terrain.
- Uranium Cave code and locales are byte-for-byte unchanged: optional 60-minute
  expeditions, normal 30-minute expeditions, saved deadlines, abundant separate
  uranium/salvage scrap/thorium beds and depletion tracking remain as in 3.2.14.

## Verification

No Factorio executable was available. The checks below use a Lua 5.4 syntax
parser and mocked Factorio surfaces with actual Cave resource modules, simplex
noise and deterministic hash code. They are not an engine or in-game test.

- Syntax: all 346 Lua files parsed successfully.
- Separation integration suite: 17 scenarios, 1,559,635 assertions.
  - Resource levels 1, 2 and 8; Mixed and Classic modes; seeds 0 and 456;
    Mobile Factory present and absent.
  - Actual core, Mobile Factory and Bob callbacks generate a complete
    256-by-192-tile allocation group. Every enabled upper ore is present,
    every basic resource remains available, no Bob tile shares a resource,
    and no other solid lies within five tiles of a Bob tile.
  - Default-size groups had at least 278 Bob tiles per ore for seed 0 and
    346 per ore for seed 456. Maximum-size groups had at least 915 and 942,
    respectively. These are sampled results, not a promise for every terrain.
  - Reverse coordinate order, including revealing Bob before core/Mobile
    Factory, produces identical fields in matching team worlds.
  - Bob-absent and all-solids-disabled results match the actual 3.2.14 core
    and Mobile Factory modules for both Mixed and Classic modes.
  - Later regular-oil discovery, negative coordinates, group boundaries,
    cache eviction/reset and custom mining categories were checked.
- Boundary suite: 2 scenarios, 64,939 assertions. Circular Space Age and
  rectangular Advancing Collapse boundaries retain the five-tile clearance.
- Bob compatibility regression suite: 10 scenarios, 25,264 assertions.
  Optional enablement, all 12 deposits, excluded thorium/tungsten, amount
  ranges, duplicate callbacks, independent toggles, team determinism, well
  spacing/yield, obstacles, failed creation retries, no well refills and
  preservation of paving passed.
- Uranium Cave regression suite: 13 scenarios, 742,409 assertions.
  Resource beds, all amount/size ranges, depletion, save/reload state, team
  isolation, first-entry 30/60-minute durations, saved deadlines, five-minute
  warnings and collapse deadlines passed.
- Inspected a modeled default-layout image to confirm that the deposits form
  broad separate mining areas rather than a scattered per-tile mixture.
- Reviewed the release diff and checked archive integrity/content against
  the release working tree before delivery.

## Remaining in-game check

Start a fresh test map with the intended Bob ores enabled. Dig across several
allocation cells and place normal/Cave MK drills inside the pure Bob deposits;
confirm the mining areas contain the expected single solid. Check both normal
and maximum Resource Patch Size, with the user's usual Mobile Factory setup.
Confirm an oil discovery still reveals the two companion wells with room for
pumps, then enter a Uranium Cave and check its resources and countdown.
