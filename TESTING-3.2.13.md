# The Cave 3.2.13 — optional Bob's Ores compatibility

## Source and scope

Built exclusively from the supplied `the-cave_3.2.12(3).zip`.
Source archive SHA-256: `e1822350c38903fd4f59b874c312879fe70e5f3f7acd53bb6f2305fdb709c9af`.
Reference inspected: `bobores_2.1.2.zip`.
Bob's Enemies was not changed or integrated in this release.
Bob's Ores and its required Bob's Functions Library remain separate mod installations.

## Files changed

- `scripts/bob_ores_resources.lua` — new optional runtime adapter.
- `control.lua` — connect digging, late room oil, configuration and surface cleanup hooks; supply the existing world API.
- `scripts/world.lua` — connect cavern tile opening and Advancing Collapse resource-strip opening.
- `info.json` — version 3.2.13 and optional dependency on Bob's Ores >= 2.1.2.
- `changelog.txt` — release entry.
- `TESTING-3.2.13.md` — this report.

All 1,137 other original files are byte-for-byte unchanged. This includes the complete existing oil generator, Mobile Factory adapter, settings, prototypes and enemy systems.

## Implemented behavior

The adapter is inert when Bob's Ores is absent. It checks actual resource prototypes and their final autoplace specifications, including resources enabled by Bob companion mods. A resource with no enabled natural generation is not spawned. No Bob startup settings are forced on.

Thirteen solid resources are recognized: tin, lead, quartz, silver, zinc, gold, bauxite, rutile, tungsten, thorium, nickel, cobalt and gemstones. Each enabled resource has a separate deterministic simplex vein, with the existing Cave resource-size multiplier and Mobile Factory-style ore amounts. Veins may cross and different solid resource entities may share a tile. Duplicate callbacks cannot stack another copy of the same resource or refill it. Original mining products, gem options and thorium mining-fluid requirements come from Bob's prototypes unchanged.

With Space Age active, the adapter excludes tungsten from the Nauvis route, matching Bob's own rule. Solid ores follow the same main/team/warp surface and Nauvis-region restrictions as the existing Mobile Factory integration. Resource-cave and train/factory interiors are excluded. Like Mobile Factory's optional veins, this adapter does not change the separate Digging Mode reward system.

Each discovered oil well gets at most one enabled Ground Water well and one enabled Lithia Water well. Default targets are on opposite sides of the oil, 15 tiles from its centre; the two companions are then 30 tiles apart. Alternate integer offsets on the 15-tile ring are tried when blocked, followed by a bounded 30-tile ring. Distances between oil/Bob well centres remain at least 15 tiles. No extra oil wells are created.

The placement check preserves resources, buildings, enemies, water, existing paving and unplayable/collapsed terrain. A clear 3x3 pump footprint is opened and charted for the discovering force. Mobile Factory's existing 10-tile companion rule is unchanged; physical fluid footprints cannot overlap. If no safe target is available, the missing companion is retried on a later nearby dig instead of overwriting obstacles.

Fluid yield is scaled from the associated oil well using each prototype's normal resource amount, so different internal amount scales do not produce accidentally tiny or huge yields. Existing completed companion records persist across module reloads and prevent replacement/refill after mining or removal. No per-tick task or full-surface scan is added. Existing oil wells receive companions when digging nearby; old ore patches are not regenerated on upgrade.

## Automated checks performed

- All 345 Lua files parsed successfully with the installed Lua 5.4 parser. This is a syntax check, not a Factorio engine load.
- Ten mocked-runtime scenarios passed, using the actual Cave simplex and hash modules: absent/disabled content; all 13 veins; Space Age/region/interior exclusions; deterministic team geology and independent toggles; single fluid companions/yields/reload/no refills; terrain and building obstacles; Mobile Factory coexistence; blocked/failed placement retry; per-fluid enable/lazy upgrade; separate surface state/late room wells; paving preservation.
- A 101x101 sample produced every enabled solid ore: individual counts ranged from 1,287 to 1,585 entities. Independent vein crossings were present.
- Checked 15-tile minimum well distances, two 3x3 clear footprints on hidden terrain, source oil count, prototype-normalized liquid amounts, duplicate callbacks, invalid surfaces and cleanup after surface removal.
- Checked all 15 recognized resource names against the supplied Bob's Ores source; checked local module references, JSON metadata and optional dependency.
- Compared every original archive member against the supplied baseline and checked that the existing oil, Mobile Factory, settings and data-stage files were unchanged.
- Final package checked for ZIP integrity, correct top-level folder and matching version metadata.

## In-game checks still required

No Factorio executable was run. Bob's Library was not among the supplied archives, so a complete engine load with all dependencies was not tested.

1. Load 3.2.13 with Bob's Ores 2.1.2 and Bob's Functions Library. Enable the wanted Bob resources. Dig unopened terrain and inspect the separate veins, including drilling where veins cross, gemstone outputs and acid-fed thorium mining.
2. Discover a new oil well. Confirm the two single liquid wells are nearby, their visible yield is sensible, and pumps can be placed and connected without overlap. Repeat with Mobile Factory active.
3. Save/reload, continue digging near the same oil and confirm no duplicated wells or restored resource amounts. For an existing oil well, mine ordinary Cave rock within six tiles to trigger local adoption.
4. Test the chosen gameplay mode, including TNT/cavern opening and Advancing Collapse's resource strip if used. Check a blocked location near water/buildings and near the collapse/map boundary.
5. Check optional-mod absence, selected resources disabled, and the Space Age tungsten restriction in the actual intended mod set. In multiplayer, check a save/reload and equivalent exploration on separate team surfaces.
