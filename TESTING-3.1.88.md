# The Cave 3.1.88 — solar display test build

Based on the user-approved `the-cave_3.1.87.zip`. Tested with Factorio 2.0.72, build 84292.

## Changes

- Removed the explanatory solar paragraph added in 3.1.86, restoring the vanilla item description and the short market-only MK descriptions.
- The ordinary panel and Solar Panel MK1–MK5 now use native night performance and a private surface coefficient. On a standard Permanent Night surface, the coefficient is 100%, instead of the old tenfold panel bonus.
- Production ratings, quality scaling, recipes, prices, graphics, footprints, lighting settings, and existing entity names remain unchanged. Other mods' solar prototypes retain their original solar coefficient.
- Existing Cave lighting multipliers remain available to external mods; only the six supported panels read the new coefficient. No panels are replaced, scanned, or recreated.

## Actual power, normal quality and standard surface

| Mode | Ordinary solar panel | New panel coefficient |
|---|---:|---:|
| Permanent Day | 60 kW | 100% |
| Permanent Night | 30 kW | 100% |
| Pitch Black | 15 kW | 50% |
| Normal cycle, full night | 0 kW | 0% |

These preserve 3.1.87's actual output. The same ratios apply to MK1–MK5. In Pitch Black, the native tooltip may show a negative surface modifier; the old +400% compensation is no longer needed for these panels. Normal-cycle surface coefficients vary with daylight so the original generation curve is retained.

## Verification completed

- Native engine loading and fresh-map creation passed in Base, with all expansions explicitly disabled, and in Space Age.
- Loaded 3.1.87 test saves into 3.1.88. The existing panel unit numbers, prototype identities, and quality were preserved.
- Compared 66 Base and 78 Space Age circuits against unchanged reference panels in the same engine run for 12,600 simulation ticks. Coverage includes all six panel tiers, normal and legendary quality, two forces, day/night/pitch-black/zero-solar conditions, a complete normal cycle, custom twilight boundaries, and 400%/20%/1%/125% solar surfaces.
- Space Age checks include Nauvis and Vulcanus orbit and three positions along their connection. Ground-panel differences were below 0.305 W, including a 1.35 MW quality/planet case. Moving-platform differences peaked at 1.036 W in the tested trajectory; total energy differed by 0.000124%, reflecting the per-tick update of the moving platform coefficient. This is numerical equivalence, not bit-for-bit equality.
- Native prototype dumps differ only in descriptions and the two new solar fields for the six supported panel types. All unrelated prototypes, including boilers, engines, loaders, turbines and accumulators, match the approved baseline.
- All 327 Lua files parse under Lua 5.2. English and Russian prototype locale dumps contain no missing solar translation keys.

## In-game check still needed

Headless Factorio cannot render the hover panel. The expected ordinary-panel display on standard Permanent Night, under sufficient electrical demand, is approximately **30 kW / 60 kW**, without the old **+900%** compensation. Actual power, coefficient values, descriptions, save loading and identity were verified; the final graphical tooltip needs the user's client test.

Load an existing test save with 3.1.88, hover an ordinary panel and an MK panel, and compare the tooltip and the electric network output. No panel replacement is required. The QA mod and reference generators are not included in this release.
