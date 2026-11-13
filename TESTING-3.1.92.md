# The Cave 3.1.92 — rolling clearing and four-family assault

Test build based exclusively on the supplied stable `the-cave_3.1.91(2).zip`.
Baseline SHA-256: `72e0ed3cc44f29ee1f556c82ae7f17a8805acd144047206bcc9c79e8f5ecc42f`.

## Behavior

- The original two-hour connected-gameplay countdown remains. Once Advancing Collapse is active, each main map receives a 96-wide by 160-deep open rectangle, centred at X=0. This is three horizontal chunk-sized columns and five vertical rows, or 15,360 tiles. It slides by individual tile rows, independent of engine chunk boundaries.
- For a collapse front at Y=L, the footprint is X from -48 inclusive to 48 exclusive, and Y from L-160 inclusive to L exclusive. The middle spawn column spans X=-16 to X=16, with extra collision and boundary margins. Every completed collapse row creates one replacement row at the north end.
- Initial clearance is limited to one 96-tile row per tick: 160 working ticks, about 2.7 seconds at 60 UPS, plus any chunk-generation wait. No repeated full-rectangle scan is used. The cursor is saved independently for each surface; upgrading an active save does not reset its wave number or deadlines.
- Natural Cave walls/rubble and trees are removed; void, water, ocean and lava are opened as regional floor. Existing floor resources, player walls/buildings, rails, trains, portals, enemies and nests are preserved by clearance. The original destructive collapse still removes anything its front consumes.
- Newly opened tiles materialize normal floor-resource deposits with existing region/depth/settings rules. Previously mined open floor is not replenished. Automatic opening does not invoke player-dig events, cave/room discovery, mineral/uranium entrances, random digging enemies, lakes or regional plants/ruins. Existing entrances are not erased. Digging Mode's existing resource-generation rules continue to apply.
- Player construction can occupy the area normally. Structural Cave Collapse cannot bury completed rows in the active rectangle. Other players or mods can still introduce obstacles; this is not a guarantee about every engine pathfinding situation.
- Scheduled assault spawning remains separate from terrain opening. Its waves, nests and reinforcements use the middle column. Existing actors move normally; moving the rectangle does not teleport them. The existing five-minute stationary-unit recovery remains.
- Wave units have target quotas of 40% Biter, 30% Spitter, 15% Armoured Biter and 15% Arachnid. Largest-remainder rounding preserves the existing wave total, rotating ties. Every wave budget of at least four reserves one unit from each family. Wave 1's 30-unit budget is 12/9/5/4. A full population cap or obstructed spawn location can prevent requested units from appearing.
- Evolution tiers are unchanged: small below 0.25, medium from 0.25, big from 0.55, behemoth from 0.85. Armoured tiers copy the integrated matching Armoured Biter. Arachnid tiers use Drone / Warrior / Tiger / Royal Warrior respectively. Source combat stats and art are retained; no Boss was added.
- Nest families rotate across waves. Each surviving nest produces its own family's reinforcement on the existing timer. Nests consumed by the collapse are removed; subsequent scheduled waves build replacements. Native population is disabled on private assault nests.
- Existing timing/count rules remain: first wave after five seconds, then every three minutes; 30 starting units, +2 per subsequent wave, +5 per additional connected owner-team player; batches of at most 25 units per second; caps of 300 units and 24 nests. Nests start at two requested per wave and increase by one per ten completed waves up to eight. Living attackers do not postpone waves. Initial terrain preparation can delay a due spawn.
- The two new private families use existing per-tier Biter coin/resource reward settings. Ordinary custom enemies and legacy Boss routing are unchanged.

## Verification performed

The real modified Lua modules were executed using the installed Lua 5.4 shared library with mocked Factorio objects. The mocks exercise script behavior and serialized table state; they do not reproduce native engine collision/pathfinding or an actual Factorio save reload.

- Cleared all 15,360 tiles; advanced the front by three rows and verified exactly 288 new resource-hook calls. Confirmed idle updates performed no terrain/entity scans and did not refill mined ore.
- Preserved pre-existing ore amounts, walls, rails, locomotive, portal, floor paving, enemy and nest. Confirmed water/lava/ocean became dry floor; player-dig/ordinary regional discovery hooks were not called; the mineable outer frontier stayed outside the rectangle.
- Re-required the controller midway through a three-row update and resumed its saved cursor. Checked countdown and disabled-mode inactivity, collapsed-ground exclusion and independent team state.
- Simulated a newly generated team chunk with a late cloned actor. The row waited for the existing second sealing pass before opening.
- Executed the real structural-collapse tile filler and confirmed it added no rubble inside protected rows.
- Checked exact quota totals for every requested count from 0 through 300 across four tie rotations. Verified 25+5 wave batching, first-wave 12/9/5/4 composition, all four evolution tiers, nest-family rotation and timed reinforcement.
- Verified the next wave started while previous units survived, owner-team player scaling, no-owner pause, one overdue wave on reconnect, initial-readiness gating, and migration of an old pending batch without resetting wave state.
- Rejected mocked spawn results outside the column or rectangle and checked fully blocked searches used bounded retries. Simulated 24 scheduled waves with survivors and enforced the 300-unit/24-nest caps; advancing the line removed a consumed nest.
- Executed the private-prototype module with source fixtures: four nest copies and eight additional unit copies, correct Arachnid name mapping, no source mutation, no autoplace and no native nest population.
- Exercised the actual resource-only regional helper for Nauvis, Vulcanus, Fulgora, Gleba and Aquilo. Only resource entities were created; duplicate resources, invalid-floor resources and colliding natural resource objects were suppressed. Both reward modules correctly mapped all four private families and preserved ordinary-enemy/Boss interpretation.
- Compiled every Lua file in both the supplied baseline and candidate with Lua 5.4. Reviewed the complete changed-file diff and checked the ZIP against the baseline for unrelated modifications, version/root consistency and archive integrity.

The harness and temporary analysis files are excluded from the mod ZIP.

## In-game checks still required

Factorio is not installed in this workspace. Native prototype loading, actual save migration, multiplayer synchronization, pathfinding, UPS and combat difficulty require the user's client/server test.

1. Load a copy of an already-active 3.1.91 save with 3.1.92. Expect clearance around the current front without resetting wave number. Save/reload during initial clearance and confirm it finishes.
2. Observe the next full wave: all four families should appear in the central column, using the current Evolution tier. Check two consecutive early waves for all four nest families. Leave one attacker alive to confirm the next deadline remains independent.
3. Follow several completed collapse rows. The open footprint should remain 96 wide and 160 deep while new rows appear above. Existing nests should remain stationary until destroyed or consumed.
4. Observe newly exposed deposits: resources may remain on the floor, but automatic clearance should not announce or create new cave entrances or random discovery enemies. Player digging outside the clearing should retain its normal outcomes.
5. With Cave Collapse also enabled, verify the active rectangle stays free of falling rubble. Keep construction and a train ahead of the consuming front and confirm clearance preserves them.
6. Check a multiplayer team surface, including newly generated northern terrain and reconnecting after a pause. Watch UPS during initial preparation and wave placement. Report the wave/Evolution and any crowding or difficulty imbalance.

## Exact files changed from the supplied 3.1.91 ZIP

| File | Purpose |
| --- | --- |
| `scripts/advancing_clearing.lua` (new) | Rectangle bounds, saved incremental cursor, readiness and collapse protection |
| `scripts/advancing_collapse.lua` | Run clearance after moving the front and before assault processing |
| `scripts/world.lua` | Resource-only row carving, preserved existing entities, frontier and team-generation guard |
| `scripts/region_features.lua` | Resource-only regional entry point |
| `scripts/advancing_assault.lua` | Central-column placement, four-family quotas/nests, readiness and saved-state compatibility |
| `prototypes/advancing_assault.lua` | Private Armoured/Arachnid units and nest copies |
| `data.lua` | Load private copies after integrated source families |
| `scripts/collapse.lua` | Keep structural rubble out of completed active clearing rows |
| `scripts/market_coin.lua` | Existing per-tier coin settings for new private families |
| `scripts/ore_blood.lua` | Existing per-tier resource rewards for new private families |
| `info.json` | Version 3.1.92 |
| `changelog.txt` | Release entry |
| `TESTING-3.1.92.md` (new) | This behavior and verification record |

All other supplied files, including assets, settings, locale, Train Interiors and unrelated cave systems, are preserved byte for byte. Earlier TESTING files describe historical releases; this file describes 3.1.92.
