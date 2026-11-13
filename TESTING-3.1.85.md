# The Cave 3.1.85 — portable Cave Accumulators

Based only on the previous 3.1.84 package, SHA-256:
84b2b69b5ff146c8185a4aa31d91acfda621add70ef64888b901a7dc450cfe08

## Behaviour

All four Cave Accumulators (3x3, 6x6, 10x10 and 20x20) retain their exact stored
Joules and item quality when mined and placed again. Partial charge is kept.
Energy is stored on the actual item, survives inventory/container transfers
and save/load, and does not decay while carried. Place the battery and connect
it to a power network to use its energy or recharge it.

A charged battery occupies one inventory slot and shows its stored energy,
capacity at pickup and charge percentage in its tooltip. Empty batteries keep
their original stackable items. Recipes, capacities, electrical flow limits,
research, graphics, animation, body sizes and existing entity IDs are unchanged.
Vanilla accumulators and the separate market/TI/Shelter energy systems are not
made portable by this feature. Destroying a battery does not return its energy.

For robot construction using a charged battery, make the construction ghost
from the charged item. That ghost requests a charged battery of the matching
size and quality. Ordinary copied blueprints still request the original empty
items; blueprint tags cannot create free energy. Once built, the machine is
the same original Cave Accumulator. Its front gauge reads the restored charge.

The four charged item prototypes use temporary placement prototypes so robots
request the right item. Native replacement preserves circuit wires/settings,
then the original entity receives the stored charge. Invalid metadata or a
capacity smaller than the stored energy cancels placement and returns the item.
Ore protection and existing TI/Shelter placement restrictions return the charged
item rather than substituting an empty one.

No new periodic handler, entity-energy cache, surface scan, setting, recipe or
research is added. Existing placed entities do not need a migration or rebuild.

## Checks performed

Actual Factorio 2.0.72 headless, with Space Age/Quality enabled and disabled:

- Loaded saves created with 3.1.84; all four existing entity IDs and stored
  fractional Joules remained unchanged.
- Exercised player-event payloads using native LuaEntity/LuaInventory objects
  for all four sizes: zero, fractional and full charge; repeated pickup/build;
  physical chest transfer; simulated consumption and recharge; and Normal plus
  Legendary quality where available. Duplicate callbacks do not refill energy.
- Tested item transfer between forces, preserving energy with the item.
- Tested ore-protection rejection and subsequent reuse of the refunded item.
  Also checked missing/invalid tags, reduced-capacity refunds and spilled items.
- Verified ordinary ghost/script revival does not restore fabricated energy.
- Ran real construction robots through mining, chest delivery and rebuilding
  from a charged-item ghost, preserving exact fractional energy.
- Wrote actual server saves with charged items in a chest, loaded them again,
  and restored the same exact energy when placing the saved item.

A separate native robot construction check verified that a red circuit wire
and a non-default output signal survive replacement of the placement entity.
All 324 Lua files pass Lua 5.2 syntax/local-variable checks. Package comparison
checks all existing image files and the original accumulator definitions.

The headless environment has no connected human player. Manual mouse placement
was exercised through matching event payloads, not through a graphical client.
The following checks remain for the player's test:

1. Partly charge a battery, note its MJ/GJ, pick it up by hand and inspect the
   charged item's tooltip. Put it in a chest and place it again.
2. Consume some energy, pick it up again, recharge it, and repeat for each size.
3. Shift-place a ghost from a charged item and let construction robots build it.
4. Check the front meter and blue/yellow column effects after placement.
5. Try a charged item near TI/Shelter restricted areas if those modes are used.
   Their refund hooks were inspected; those full scenarios and automatic space
   platform construction were not exercised in this test fixture.

## Exact file changes

Added:

- `prototypes/portable_cave_accumulators.lua` — four charged item prototypes and
  four temporary placement prototypes; original entity definitions unchanged.
- `scripts/portable_cave_accumulators.lua` — mining, tagged charge, placement,
  refund handling and per-item tooltip.
- `TESTING-3.1.85.md` — this report and test instructions.

Modified:

- `control.lua` — mining/build event routing, including platform event routing.
- `data-final-fixes.lua` — load the new prototypes after existing definitions.
- `scripts/ore_protection.lua` — optional callback for returning a charged item.
- `scripts/train_interiors.lua` — charged-item guard in the existing refund path.
- `scripts/shelter_core.lua` — charged-item guard in the existing refund path.
- `locale/en/cave_accumulators.cfg` — English charged-item text and messages.
- `locale/ru/cave_accumulators.cfg` — Russian charged-item text and messages.
- `info.json` — version 3.1.85.
- `changelog.txt` — this version's changes.

No existing files were removed. All other baseline files are byte-identical.
