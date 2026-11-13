# The Cave 3.1.97 - Basic Big Pole

Base: the previously delivered 3.1.96 archive from this same The Cave branch.
Base SHA-256: `d2bda7b2a54938aa3d843e5ec43191b6dfffab999154b82d77e881de26355c22`.
This is a test release; native Factorio loading/rendering has not been run here.

## Changes

- The English item/entity display name is now **Basic Big Pole**. Russian names and both languages' material descriptions are updated consistently.
- One pole now costs **2 Iron Plates + 4 Copper Cables**, available from the start as before. Only the two Wood are replaced with two Iron Plates.
- The world sprite uses the approved riveted iron design, fitted to the existing pole's geometry. The item icon uses the same head and foot with a shorter shaft so the fittings remain readable at 32 pixels.
- The old ground shadow is retained. All original black shadow pixels outside the new foreground remain unchanged.
- The internal item, entity and recipe identifier stays `the-cave-big-wooden-pole`. Existing poles, items, ghosts and blueprints therefore retain their prototype identity; no replacement script or migration is introduced.

## Geometry and asset specification

| Property | Value |
| --- | --- |
| World image | 180 x 180 pixels, 8-bit RGBA PNG, transparent, one direction |
| Inventory icon | 32 x 32 pixels, 8-bit RGBA PNG, transparent |
| Sprite scale | Original default 1 |
| Sprite shift | (2.2, -2.5) tiles, unchanged |
| Entity origin in image | (19.6, 170) pixels |
| Opaque foreground bounds | x = 10..45, y = 4..177 |
| Collision box before existing settings | (-0.3, -0.3) to (0.3, 0.3) tiles |
| Selection box | (-0.5, -0.5) to (0.5, 0.5) tiles |
| Base wire reach | 24 tiles |
| Base supply area | 4 x 4 tiles |

All wire positions stay unchanged in the prototype. The visible metal fittings are aligned to those existing positions, including the circuit-wire anchors that previously fell outside the old painted fittings.

| Wire | Existing world offset | Image attachment point | Existing shadow attachment point |
| --- | --- | --- | --- |
| Copper | (0.68, -4.25) | (41.36, 34.00) px | (124.56, 173.20) px |
| Green | (0.58, -3.90) | (38.16, 45.20) px | (118.80, 176.40) px |
| Red | (0.35, -3.70) | (30.80, 51.60) px | (112.40, 171.60) px |

The image conversion uses `pixel = (90, 90) + 32 * (world_offset - sprite_shift)`.
The [official SpriteParameters documentation](https://lua-api.factorio.com/latest/types/SpriteParameters.html) describes the tile-based shift and normal-resolution pixel convention. Source artwork is transformed and composited before downsampling; the mod's numerical wire positions are not moved to fit the artwork.

The accompanying alignment preview is a synthetic texture check, not a Factorio screenshot. Cyan boxes show selection, yellow boxes show collision, white marks show the entity origin, and colored guide lines show the three wire anchors.

## Exact changed files from 3.1.96

1. `graphics/entity/big-wooden-pole.png` - fitted iron pole, same canvas and shadow coordinates.
2. `graphics/icons/big-wooden-pole.png` - matching 32-pixel icon.
3. `prototypes/big_wooden_pole.lua` - recipe input `wood` becomes `iron-plate`; quantity remains two.
4. `locale/en/locale.cfg` - item/entity names, descriptions and the early-machine guide sentence.
5. `locale/ru/locale.cfg` - corresponding Russian text.
6. `info.json` - version 3.1.97 only.
7. `changelog.txt` - new release entry.
8. `TESTING-3.1.97.md` - this report.

Every other file remains byte-identical to 3.1.96, including the new Lamp post, accumulator and Q changes, Train Interiors, Shelter, Advancing Collapse, Queen and Squeak Through systems. There are no new events, runtime scans, state, settings or migrations. Existing quality, force and fast-replacement behavior continues through the same prototype and untouched runtime code.

The prior 20 MJ fuel value and chemical fuel category are retained: their removal was suggested but was not part of the confirmed name/recipe/geometry change. No other item balance is changed.

## Checks performed

- Compiled all 331 Lua files with Lua 5.4 for syntax checking.
- Executed the actual old and new pole prototype modules in a small Lua data-stage harness. After allowing only the requested Wood-to-Iron recipe change, all resulting fields match, including collision, selection, drawing bounds, wire/shadow points, flags, health, sprite parameters, recipe output and item identifiers.
- Ran the existing pole fast-replacement final-fix module against both versions with minimal vanilla dependency fixtures; results match and the pole keeps its original replacement group.
- Loaded both PNGs, verified their exact dimensions, transparency, 8-bit depth, and single-frame layout. Checked visible opaque metal at all three connection points, foreground placement, the base position, and identical shadow bytes outside the foreground.
- Reviewed the aligned sprite and 32-pixel icon at enlarged and native texture sizes. This is asset verification, not a native engine render test.
- Compared every file against the base archive. Verified that only the eight files above differ, that no files are removed, and that all dependency metadata is unchanged except the mod version.
- Verified final ZIP integrity, root directory, unique entries and byte-for-byte agreement with the validated build.

## Remaining in-game checks

1. Load a copy of the current save with 3.1.97. Inspect an existing pole and place a new one. Confirm the base, height and selection footprint line up as before.
2. Connect copper, red and green wires from different sides, and inspect their visible endpoints at normal and enlarged zoom. Confirm both electricity and circuit signals still pass. Check a quality pole too if Space Age/Quality is enabled.
3. Verify the recipe consumes exactly two Iron Plates and four Copper Cables, without Wood, and that the new name/icon appears in inventory, crafting, ghosts and the entity tooltip.
4. Walk past the pole using the current Squeak Through setting, and check replacement with a Medium Electric Pole. Existing collision settings and fast-replacement rules should still apply.
5. Save/reload the test save and inspect an existing wired pole/blueprint before using this version on the server.

No native Factorio executable is installed in this environment, so these live loading/rendering/save checks are not claimed as completed.
