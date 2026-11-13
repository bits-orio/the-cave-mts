# The Cave 3.2.24 - Bob evolution compatibility test build

Based on the previously delivered 3.2.23 test archive, which was built only
from the supplied 3.2.21 branch. Its Remote View fixes are retained. No
3.2.22 changes are merged.

Baseline 3.2.23 ZIP SHA-256:
`b27a896fd6fb263eab060843a0986829607351729af13563a95e63b9b28bb626`.

## Behavior

- With `bobenemies` active, ordinary and TNT/Queen dig ambushes select the
  original Cave-family tier from the real evolution of the owning surface.
  Timed mineral/uranium caves continue to read their entrance's parent surface.
  The Cave depth bonus and global-difficulty tier adjustment do not apply.
- Darkness Infestation uses the same raw-evolution rule with Bob active.
  Its existing biter/spitter families, tier thresholds and attack behavior stay.
- With Bob absent, both modules retain their original depth and difficulty
  adjustments. This includes Easy's negative adjustment.
- Bob-family picks keep using the existing adapter and loaded Bob spawn curves.
- No prototypes, HP, damage, resistances, quality, enemy-family shares, Queen
  rules, room generation, spawn counts, caps, intervals, resources or rewards
  are changed. This is not a full enemy-system handoff to Bob.
- No migration or reset is added. Existing enemy entities retain their type
  and health. The patch affects new encounters; it does not lower evolution.

At the supplied save's Nauvis evolution, `0.6782133864750246`, a Cave-family
arachnid-biter dig pick now selects Tiger rather than Royal Warrior, regardless
of local depth or the global Hard tier bias. Bob can still select its own Huge
units where its existing spawn curve allows them. Darkness selects the Big
biter/spitter tier. Cave-family Behemoth/Royal remains available from raw 0.85
under the existing four-tier ladder; this patch does not replace that ladder
with Bob's eight-tier ladder or native nest curves.

## Changed files relative to 3.2.23

- `scripts/dig_spawner.lua`: conditional raw-evolution tier selection.
- `scripts/darkness_infestation.lua`: Bob activation check and matching tier rule.
- `info.json`: version 3.2.24; dependencies and feature flags retained.
- `changelog.txt`: release notes.
- `TESTING-3.2.24.md`: this new test guide.

## Completed checks

- All 352 Lua source files passed syntax loading with the available Lua 5.4
  library. The Factorio engine checks below additionally parsed and initialized
  the actual mod with Factorio's own Lua environment.
- 3,136 mocked public-event scenarios passed using the actual runtime modules.
  Covered Bob-off equivalence with 3.2.23 across four global difficulties,
  depth and evolution boundaries; Bob-on raw-evolution tiers; unchanged
  Bob-adapter picks; child/parent evolution; existing dig progress; independent
  Force counters; blocked/capped encounters; darkness grace, physical target,
  lamps, driving, safe zones, absent/invalid characters and disabled settings.
  Factorio objects and small Bob result_units fixtures were mocked: these are
  not full Bob prototype or multiplayer gameplay tests.
- Factorio 2.0.77 headless successfully created maps with the complete mod
  in Base and, separately, Space Age + Quality + Elevated Rails. Bob was absent
  in both engine configurations. Space Age reported its existing Gleba-spawner
  collision-mask warning; creation finished successfully.
- The release archive is checked for CRC errors, a single correctly named mod
  root, matching version metadata, unchanged dependencies, and an exact content
  comparison against 3.2.23. Only the five files listed above differ.

The supplied save is not modified. A full engine/gameplay test with Bob 2.1.0
and the server's complete mod pack still needs the following user tests.

## In-game tests

Use this version as the active The Cave package and load a copy of the supplied
save with the same mod pack and Startup settings.

1. With Bob active and the saved Hard setting/evolution unchanged, mine ordinary
   rocks outside the 65-tile peaceful radius. Compare positions below 300,
   between 300-700 and 700-1000, and beyond 1000. Newly spawned original Cave
   enemies should keep the same evolution tier across these depth boundaries.
   A newly selected arachnid biter should be Tiger at approximately 67.82%,
   not Royal Warrior. Encounters remain subject to their original intervals,
   room exclusion, placement checks and nearby-unit cap.
2. Test newly spawned enemies in Iron/Copper/Coal/Uranium extraction caves.
   The entrance's parent evolution must govern the tier. The Hard extraction
   pack bounds and cap remain unchanged; a Nightmare entrance must not force
   a Royal tier at approximately 67.82% raw evolution.
3. Test Darkness Infestation outside its safe zone without a powered lamp.
   Keep the 30-second grace period; new darkness enemies at approximately
   67.82% should be Big biters/spitters. A powered lamp and exempt interiors
   must still protect the physical character, including while viewing remotely.
4. On a disposable test copy, compare raw evolution 30%, 67.82% and 95%.
   Cave-family arachnid-biter dig picks should be Warrior, Tiger and Royal
   respectively. Darkness should use Medium, Big and Behemoth respectively.
   Bob-family enemies still follow their own curves and should not be judged
   by the Cave four-tier names. Existing enemies do not downgrade when evolution
   is reduced.
5. Save/load and, in multiplayer, dig as a second Force. Check independent
   counters, normal encounter pacing, and absence of a delayed enemy burst.
6. In a separate test configuration with Bob disabled, confirm the original
   difficulty/depth progression. Keep Base and Space Age checks separate.

Record a failure with enemy prototype/name and quality, whether it was newly
spawned, raw parent-surface evolution, global difficulty, position, surface,
trigger (dig/room/nest/darkness), Factorio/mod versions and any log stack trace.
