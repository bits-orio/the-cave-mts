# The Cave 3.2.45: scrap mining playtest

Based on the delivered 3.2.44 package. All five previously agreed cave changes are retained. This is a server playtest build.

## Scrap mining

The Cave Scrap resource is now based on ordinary iron ore mining. It is available without research or acid, by hand or with normal burner/electric mining drills. Mining time is 1 second at mining speed 1, matching iron, copper, coal and stone. The yield remains 10 The Cave Scrap per completed mining cycle.

The existing scrap item, Scrap Sorting recipe, sorting probabilities, resource amounts and separate Core uranium/scrap beds are unchanged. This affects The Cave Scrap, not Space Age Fulgora Scrap. Existing placed scrap resources acquire the new prototype when the mod is upgraded; no ore replacement or resource reset is needed.

Uranium is unchanged. Factorio's Uranium mining research still enables manual placement of drills on uranium, and uranium still needs sulphuric acid. Uranium processing remains unchanged. Native script-created drills bypass the placement check, as they did before this change; the tests check the research gate using Factorio's manual build rules.

## Validation for this change

Factorio 2.0.77 Headless tests use a native character, real mining drills, native electric power and real resource depletion. Test forces begin with zero completed technologies and fluid mining locked. Tests covered manual, burner and electric scrap extraction without acid, 10-scrap yield, Scrap Sorting availability, uranium drill placement before/after research, and uranium extraction with/without acid. Uranium's native mining prototype, research effects and prerequisites match 3.2.44.

Profiles: Base only, Space Age, Bob's Ores with Base, Bob's Ores with Space Age, and the mining-drill filter setting disabled. The normal filter-enabled setting was exercised in the other profiles. Bob's Ores 2.1.2 and Bob's Library 2.1.0 were used.

A real local-server save created under 3.2.44 was loaded in 3.2.45 with both Base and Space Age. Existing resource/drill/output references, amounts and contents survived the upgrade, and the saved scrap resources then mined without research or acid. The upgrade refreshes connections only for drills covering The Cave Scrap, once; it does not replace resources or machines. Previously blocked active burner drills resumed without being rebuilt or toggled. Old-save tests cover real drills; manual extraction was tested separately with connected native players in the five profiles above. All source saves remain unchanged. Test maps, drivers, debug hooks and automatic inserters/loaders are excluded from the package.

The six-cave behavioral matrix in TESTING-3.2.44.md belongs to the preceding build. Its gameplay implementation is byte-preserved here except for Uranium Cave information-panel wording. No graphical client or simultaneous live-player session was tested for 3.2.45.

## Changed files relative to 3.2.44

- prototypes/scrap_salvage.lua
- migrations/3.2.45.lua
- scripts/uranium_caves.lua (information text only)
- locale/en/locale.cfg
- locale/en/settings.cfg
- locale/ru/locale.cfg
- locale/ru/settings.cfg
- info.json
- changelog.txt
- TESTING-3.2.45.md

## In-game checks

1. With Uranium mining not researched, enter a Uranium Cave and mine a scrap bed by hand and with your own burner/electric drills. Supply fuel/power normally; no acid is required for scrap.
2. Check that uranium keeps its normal research and acid rules, including on an existing save.
3. Keep a drill confined to the scrap bed. A drill covering uranium as well may encounter uranium's normal acid requirement.
4. Reconnect, save/load and test with multiple players on the server. Report any error with the save and Factorio log.
