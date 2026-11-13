# The Cave 3.2.17 - test build

Based on the complete 3.2.16 archive, retaining all existing assets.

Included changes: separate shared team stats and online-player coin ranking;
quarter the existing direct-dig Worm chances (native and Bob), without replacing
rejected Worms or changing strength; fireproof the three requested poles;
apply the agreed market sell prices; add Landfill and Wood x 5 in Buy > Other.

Validation completed with a Lua 5.4 parser and mocked Factorio APIs:
- Syntax for all 347 Lua files.
- Reproduced the previous caption-limit error; rebuilt the new Caves tab with
  1, 8, 9, 30 and 128 online players. Checked coin ordering, name ties, offline
  exclusion and unchanged team statistics calculations.
- Native/Bob Worm acceptance at the 25% boundary, no replacement, unchanged
  other enemy selections and tiers.
- All three pole prototypes have 100% fire resistance and not-flammable;
  their health, other resistances and vanilla small pole are preserved.
- All ten market sell offers, bulk quantities, Sell All, insufficient stock,
  Wood/Landfill purchases and the Other category display.

Factorio engine and server tests were not available here. On the server, open
and refresh Caves; test the sell offers and Wood/Landfill purchases; expose old
and newly placed poles to flamethrower fire and biter attacks. Confirm direct-dig
Worms are rarer while room guardians and enemy strength retain their behavior.
