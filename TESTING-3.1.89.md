# The Cave 3.1.89 — market test build

Base: the user-confirmed stable `the-cave_3.1.88.zip` (SHA-256 `45b07dbe5fe8b985741d55e858c7cf38505c7296c74b020d31580513ff013035`). The extracted baseline matched every file in that ZIP before editing.

## Changes

- Sell: an All button follows 100 on every available row. It reads the current main inventory, sells complete deals at Normal quality and leaves the remainder. Numeric buttons still count deals.
- Rocket silo is absent from Sell. Its prototype and other uses are retained.
- Nuclear fuel sells for 200 coins per item. Its 500-coin buy price is retained.
- Buy > Fluids & Barrels > Storage Tank contains eight filled-tank offers in Base and 21 with Space Age. Every purchase supplies a Normal-quality tank containing 25,000 units. Plasma and technical placeholder fluids are not offered.
- The existing seven barrel offers remain under the Barrels subcategory with their original prices and quantities.
- New purchases use the existing portable-tank item/proxy/tag contract. Steam is supplied at 165 C; other fluids use the temperatures below. No new entity prototypes or recipes were added.
- Failed sales or filled-tank purchases restore the exact original main-inventory stacks, including quality and metadata. Work runs only when a player clicks; there is no new periodic task.

## Approved prices

All prices include the tank and 25,000 units of contents.

| Fluid | Coins | Temperature (C) |
|---|---:|---:|
| Water | 100 | 15 |
| Steam | 200 | 165 |
| Crude oil | 750 | 25 |
| Heavy oil | 1,500 | 25 |
| Light oil | 1,250 | 25 |
| Petroleum gas | 1,750 | 25 |
| Lubricant | 2,000 | 25 |
| Sulfuric acid | 3,000 | 25 |
| Lava | 500 | 1,500 |
| Molten iron | 1,500 | 1,500 |
| Molten copper | 1,500 | 1,100 |
| Holmium solution | 4,000 | 15 |
| Electrolyte | 6,000 | 15 |
| Ammoniacal solution | 500 | -50 |
| Ammonia | 1,000 | -35 |
| Lithium brine | 2,000 | 15 |
| Fluorine | 1,500 | 25 |
| Fluoroketone (hot) | 10,000 | 180 |
| Fluoroketone (cold) | 11,000 | -150 |
| Thruster fuel | 750 | 25 |
| Thruster oxidizer | 750 | 25 |

## Verification performed

- All 327 Lua files passed Lua 5.2 syntax compilation. Diff whitespace checks passed.
- The prior buy-price table was byte-for-byte unchanged. The sell-price table differs only in the two approved edits.
- The full mod loaded and created fresh maps using Factorio headless 2.0.72, both Base and Space Age.
- Native character inventories and item stacks exercised All with 10,050 copper plates (1,000 coins, 50 plates remain), inventory changes after GUI construction, repeated clicks, numeric deal counts, nuclear-fuel payouts and rejection of stale rocket-silo sale requests.
- A full-inventory failure restored every slot, including an existing partially filled tank's custom tags and description. Selling a complete stack correctly freed space for the resulting coins.
- Space Age cases verified that higher-quality nuclear fuel and coins were untouched.
- All 8/21 filled-tank prices and temperatures were checked. Each purchased tank was passed through the portable placement and mining handlers with real Factorio storage-tank entities and fluid boxes. Fluid type, 25,000-unit amount, temperature, force and quality were retained.
- Purchases of 5 and 100 tanks retained the tags on every individual item. Insufficient money and capacity for only part of an order caused no changes.
- Two simulated players used real native inventories belonging to different forces; a transaction did not change the other inventory.
- Fresh saves containing purchased tanks were reloaded successfully. Test saves created with 3.1.88 were upgraded to 3.1.89 in both modes; existing inventory contents were preserved and the exchange checks passed again.
- New English and Russian market locale references were checked against their definitions.

Headless tests used simulated player/GUI dispatch because the engine has no API to create a LuaPlayer. Inventories, items, entities, fluids, prototype loading and save/load were native. These checks do not replace a graphical-client or live multiplayer session. Third-party portable-tank owners were not installed in the tests; matching existing item/proxy prototypes are required for their offers to appear.

## In-game checks

1. Open Sell and verify the All column appears after 100. Check a bulk resource with a remainder and sell one Nuclear fuel for 200 coins.
2. Open Buy > Fluids & Barrels > Storage Tank. Buy a tank, place it, connect a pipe, then pick it up and place it again. For Steam verify 25,000 units at 165 C.
3. Check the menu at your display/UI scale, and repeat a transaction on your multiplayer server.

## Exact files changed from 3.1.88

- `scripts/market_coin.lua`
- `scripts/portable_tanks.lua`
- `locale/en/market.cfg` (new)
- `locale/ru/market.cfg` (new)
- `info.json`
- `changelog.txt`
- `TESTING-3.1.89.md` (new)

The QA mod, temporary saves, test scripts and logs are excluded from the release ZIP. This is a test build awaiting the user's in-game confirmation.
