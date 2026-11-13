# The Cave 3.1.96 - Approved futuristic Lamp post

Base: the delivered and user-tested 3.1.95 branch. Base ZIP SHA-256:
`c3dbe21c88ec5ac7fa5c537cbbc60d370c8d5bb22feb368d8d8a7c035a108bcb`.

## Changes

- Uses the user's approved tall futuristic lamp-post artwork for the world sprite. The compact UI icon and broken remnants are companion images of that same design.
- Replaces seven existing PNG files: body, powered lens mask, shadow, water reflection, remnants, item icon atlas and technology icon atlas.
- Preserves every sprite canvas size, scale, shift and filename; the entity remains the same Lamp post with its existing collision/selection boxes, circuit connections, light settings and powered protection logic.
- Removes the one Plastic Bar from the recipe and removes the Plastics prerequisite. The recipe now uses exactly five Small Lamps and one Steel Plate; its original four-second base crafting time remains. Research still uses 50 red plus 50 green science before the existing difficulty multiplier, with Lamp as its prerequisite.
- No runtime scripts, entity identifiers, recipe identifiers, settings or migrations are added or changed. Existing placed lamps retain their identity and receive the new appearance when the save loads.

## Exact changed files from 3.1.95

- `graphics/entity/lamp-post/lamp-post.png` - 59x178 RGBA.
- `graphics/entity/lamp-post/lamp-post-shadow.png` - 237x50 RGBA black shadow.
- `graphics/entity/lamp-post/lamp-light.png` - 90x78 grayscale/alpha tintable mask.
- `graphics/entity/lamp-post/lamp-post-reflection.png` - 12x24 RGBA red-channel reflection.
- `graphics/entity/lamp-post/remnants/lamp-post-remnants.png` - 102x96 RGBA.
- `graphics/icons/lamp-post.png` - 120x64 atlas containing 64, 32, 16 and 8 pixel icons.
- `graphics/technology/lamp-post.png` - 480x256 atlas containing 256, 128, 64 and 32 pixel icons.
- `prototypes/lamp_post.lua` - only the Plastic Bar ingredient and Plastics prerequisite are removed.
- `info.json` - version 3.1.96 only.
- `changelog.txt` - new release entry.
- `TESTING-3.1.96.md` - this report.

All other files are byte-identical to the base ZIP, including the Q correction, accumulator recipes, Advancing Collapse and Queen systems. Source artwork, image preparation commands and validation fixtures are kept outside the playable ZIP.

## Verification

- Loaded all seven PNGs and checked exact existing dimensions, eight-bit depth, transparency, single frames, all icon mipmap cells, the neutral powered mask and reflection/shadow channel requirements.
- Reviewed synthetic texture previews for body/light alignment, base/shadow placement, small icon readability and the damaged sprite. These are texture-layout checks, not Factorio screenshots.
- Executed the old and new actual Lamp prototype files with mocked base graphics dependencies. After accounting for the two approved removals, all resulting prototype fields are identical, including lighting, energy, geometry, signals, recipe output and research.
- Compiled all 331 Lua files; compared all files with the base ZIP, checked version/root naming and final ZIP integrity.
- No native Factorio executable is available in the build environment. Native loading and live rendering are not claimed as tested.

## In-game checks

1. Load a copy of the current save with 3.1.96 and inspect both existing and newly placed Lamp posts. Check the tall body, base position, inventory/research icons and shadow at normal zoom.
2. At night, connect and disconnect power. The powered lens and surrounding light must switch with the original lamp behavior; protection still requires power. Check a circuit-selected color and a circuit-controlled off state.
3. Confirm the recipe shows only five Small Lamps and one Steel Plate, costs four base crafting seconds, and is available after Lamp post research without Plastics. At Medium difficulty, research remains 50 red plus 50 green.
4. Destroy a test lamp to inspect its matching wreckage, and inspect the reflection near water if relevant to the map.
5. Save/reload the test save before promoting this build to the live server. Existing lamps, charge state of unrelated accumulators and all scenario systems should remain intact.

The reflection mask follows the existing red-channel convention documented in the official Factorio [Animated water article](https://www.factorio.com/blog/post/fff-323).
