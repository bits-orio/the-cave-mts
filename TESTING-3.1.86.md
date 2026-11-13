# The Cave 3.1.86 — test build

Based on the accepted `the-cave_3.1.85.zip` (SHA-256: `a5f8b66bce492c6930376a6bad5a536fccab2fe085d509859849af61ee9787df`).

## Changes

- Steam Engine MK1–MK5 now consume enough steam to reach their existing power ratings. Steam temperature, engine efficiency, prices and recipes are unchanged. The calculation uses the loaded steam heat capacity and engine temperature/efficiency.
- Vanilla and Market MK solar panels have English and Russian explanations of the low-light Productivity bonus and current versus full-light maximum power. The native bonus number remains visible. Solar output, lighting modes, percentages and defaults are unchanged.
- Existing entities adopt the prototype update without replacement. No runtime handlers, polling, migrations or graphics were added or changed.

| Normal-quality engine | Rated output | Steam needed at 165 °C |
|---|---:|---:|
| MK1 | 1.1 MW | 36.67 units/s |
| MK2 | 1.3 MW | 43.33 units/s |
| MK3 | 1.5 MW | 50 units/s |
| MK4 | 1.7 MW | 56.67 units/s |
| MK5 | 2 MW | 66.67 units/s |

One normal-quality boiler supplies 60 steam/s, equivalent to 1.8 MW. For continuous full MK5 output, provide additional steam supply; two normal-quality boilers can supply one normal-quality MK5. Actual generation also follows electrical demand. Higher-quality engines require more steam for their higher output.

## Verification performed

- Factorio 2.0.72 headless, with Base only and with Space Age/Quality enabled.
- Created a 3.1.85 save with 20 isolated electrical circuits per configuration. Measured each circuit under the old release, then loaded the same save with 3.1.86 and measured again. Existing unit numbers, quality and force ownership were retained.
- Reproduced the old 900 kW ceiling on all five normal-quality MK engines, even with ample 165 °C steam. After the change, all five produced their rated power under demand. Legendary engines produced 2.75/3.25/3.75/4.25/5 MW. A second force's MK5 also reached 2 MW.
- Direct-supply cases replenished steam in the test fixture and measured native electrical generation and steam consumption over ten seconds. MK5 consumed approximately 66.67 steam/s at 2 MW.
- Separate tests used actual coal-burning boilers and connected pipes. MK5 produced 1.8 MW with one normal-quality boiler and 2 MW with two; test water was replenished automatically.
- The ordinary steam engine remained at 900 kW. Native output of the ordinary solar panel and all five MK solar panels was identical before and after the change in Permanent Night; the surface time and multiplier also remained unchanged.
- Factorio's native locale dump resolved all twelve solar item/entity descriptions in both English and Russian.
- All 324 Lua files passed Lua 5.2 syntax checks. The file diff was restricted to the list below; runtime scripts, settings, migrations, recipes, prices and image files were preserved. ZIP CRC and version/root metadata are checked during packaging.

## Exact file list relative to 3.1.85

Modified:
- `prototypes/mk_market_items.lua`
- `info.json`
- `changelog.txt`

Added:
- `locale/en/power.cfg`
- `locale/ru/power.cfg`
- `TESTING-3.1.86.md`

## Player test remaining

The tests used the real headless engine, not a graphical client. Check the solar tooltip's readability in-game, including an MK panel. Confirm its familiar percentage and output have not changed. Then connect a normal-quality MK5 to two fueled boilers with sufficient water and a steam pipe connection, and provide at least 2 MW of electrical demand. Check that Available power reaches 2 MW and that full output is delivered when demanded. One normal-quality boiler alone should sustain approximately 1.8 MW. The player's complete third-party mod set was not available for testing.
