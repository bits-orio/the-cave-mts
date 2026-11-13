# The Cave 3.1.87 — boiler test build

Built exclusively from the accepted `the-cave_3.1.86.zip` (SHA-256 `af4f792970662df575a8ebbda14cd611743ea104677a77ba4890e85a394b2175`).

## Included changes

Five market-only boilers are available under **MK → Power**, immediately after the Steam Engine series. Prices are per boiler. Existing engine prices remain 100/120/130/140/150 coins.

| Tier | Each engine | Matching boiler heat | Engine steam/s | Boiler steam/s | Boiler price |
|---|---:|---:|---:|---:|---:|
| MK1 | 1.8 MW | 3.6 MW | 60 | 120 | 200 coins |
| MK2 | 2.7 MW | 5.4 MW | 90 | 180 | 240 coins |
| MK3 | 3.6 MW | 7.2 MW | 120 | 240 | 260 coins |
| MK4 | 4.5 MW | 9 MW | 150 | 300 | 280 coins |
| MK5 | 5.4 MW | 10.8 MW | 180 | 360 | 300 coins |

Values above are for Normal quality and 165 °C steam. One boiler supplies two engines of the same MK tier and quality. Steam rates follow the native steam heat capacity. Fuel use increases with heat production; efficiency remains vanilla. Higher-quality boilers and engines retain native scaling.

Boilers reuse vanilla artwork, animations, 3×2 footprint, pipe connections, fuel types, inventories and pollution settings. Mining returns the corresponding MK boiler item with its quality. English and Russian descriptions explain the two-engine pairing. No new recipes or technologies were added.

Existing Steam Engine MK1–MK5 entities adopt the new ratings without replacement. Market offers are built when the shop opens, so the new boilers also appear in existing saves. No new event handlers, periodic work, surface scans or migrations were added. Vanilla boilers/engines, solar output and explanations, accumulators, loaders, graphics and unrelated settings remain unchanged.

## Verification performed

- Factorio **2.0.72, build 84292**, actual headless engine. Tested Base with Space Age, Quality and Elevated Rails explicitly disabled, and separately with all three enabled.
- Created saves under 3.1.86 and loaded them under 3.1.87. Existing engine unit numbers, force ownership and quality were retained. Before/after runs covered 52 circuit measurements: 13 baseline and 39 updated cases.
- Each of the five updated Normal-quality engines produced its specified power with sufficient 165 °C steam and demand.
- Actual coal-burning boilers, connected by pipes to two engines, sustained **3.6/5.4/7.2/9/10.8 MW** in both configurations. Only fuel and input water were replenished by the test fixture; paired-engine tests did not inject steam. Measurements covered ten seconds after a sixty-second warm-up from empty pipes and engines.
- All five Legendary pairs also passed: **9/13.5/18/22.5/27 MW**. MK5 pairs passed at Uncommon, Rare and Epic quality, and on a second force.
- Measured fuel energy consumption matched output. Separate MK5 cases without fuel, water or electrical demand produced zero sustained power. The vanilla boiler/engine pair retained its previous output.
- Native mining checks returned one matching MK boiler item, preserving Normal quality in Base and Legendary quality with Space Age.
- A Lua 5.2 harness executed the actual market module with simulated players and inventories: verified five new offers, category, names, tier ordering, thirty purchases across two player/force inventories, insufficient coins, full inventory and a missing item prototype. All 156 existing catalog entries were unchanged in that fixture. This was not a graphical market test.
- Factorio's data dump confirmed ratings, steam consumption, native boiler geometry/graphics/efficiency and the absence of MK boiler recipes. Native locale dumps resolved all ten boiler item/entity descriptions in both English and Russian.
- All 324 Lua files passed Lua 5.2 syntax checks. File diff, ZIP CRC, member paths, archive contents, version and root-directory metadata were checked. Test fixtures are not shipped.

## Exact files changed relative to 3.1.86

Modified:
- `prototypes/mk_market_items.lua`
- `scripts/market_coin.lua`
- `locale/en/power.cfg`
- `locale/ru/power.cfg`
- `info.json`
- `changelog.txt`

Added:
- `TESTING-3.1.87.md`

All 1,085 other baseline files are byte-identical. No files were removed.

## Player test remaining

Load your existing save, open **Market → MK → Power**, and check/buy Boiler MK1–MK5 at 200/240/260/280/300 coins. The market layout and mouse interaction still require a graphical-client check.

For the MK5 test, connect one Normal-quality Boiler MK5 to two Normal-quality Steam Engine MK5 units. Supply water and enough fuel, allow the steam circuit to fill, and provide at least **10.8 MW** of electrical demand. Each engine should supply **5.4 MW** under full demand. Actual output will be lower if demand or steam supply is lower.

The player's complete third-party mod set and multiplayer clients were not available. Save-upgrade tests used generated 3.1.86 fixtures, not the user's live save.
