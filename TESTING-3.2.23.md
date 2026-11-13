# The Cave 3.2.23 - Remote View test build

This package is based exclusively on the supplied **the-cave_3.2.21(1).zip**.
The version number is 3.2.23 to distinguish this test build. No 3.2.22 source was merged.
Baseline ZIP SHA-256: `d67cca61fb58670f36362173ade5418497a935f57fc2e2037118553a4aedee46`.

## Expected behavior

- Opening a cave entrance/exit in Remote View closes that interaction without moving the character, creating the cave, or starting its timer. Normal travel requires the character on the entity's surface and `can_reach_entity`.
- Ctrl+Enter/entry shortcuts and automatic garden portals require normal character control. Train/Shelter entry keeps the original 10-tile distance. Garden portals keep the original rectangles and Force restrictions.
- Cave expiry, physical pickups, Advancing Collapse exploration/combat and Fulgora hazard calculations follow the physical character even when its camera is elsewhere.
- The paid waypoint Teleporter remains an intentional long-distance action, including in Remote View. Its return point comes from the body, and its original price, research and cooldown remain.
- Failed transfers do not commit successful travel state, clear Warp/Reset inventory, or permit an occupied child surface to be deleted. Camera-only observers are moved with the remote controller, leaving their body alone.
- Failed removed-wagon cleanup and Warp evacuation are retried in existing tick handlers. A later successful journey supersedes stale Warp recovery.

The patch introduces no migration or reset and does not change prototypes, graphics, sounds, locale files, settings, balance, timer durations, resource yields or the existing 3.2.21 digging layouts.

## Modified files

| File | Change |
| --- | --- |
| `scripts/player_physical.lua` (new) | Shared physical context, access checks, bounded landing lookup, synchronous travel guard, verified transfer and camera-only evacuation. |
| `scripts/mineral_caves.lua` | Physical access for Iron/Copper/Coal cave travel; physical deadline/lighting/cleanup checks and confirmed respawn state. |
| `scripts/uranium_caves.lua` | Equivalent Uranium cave access, deadline, lighting, cleanup and respawn checks. |
| `scripts/fortified_vaults.lua` | Guard cave/cache interactions; physical deadline, corpse, lighting, loot-spill and evacuation handling. |
| `scripts/lost_city.lua` | Guard entrance/exit; physical NPC/HUD/reward proximity and deadline/evacuation/respawn handling. |
| `scripts/train_interiors.lua` | Guard entry/garden actions, preserve range/Force checks, verify movement/state, follow bodies in forced relocations and retry removed-wagon cleanup. |
| `scripts/shelter_core.lua` | Guard entry/garden actions; preserve geometry/Force checks and commit movement state after success. |
| `scripts/market_coin.lua` | Scan body surface and position together for coin pickups. |
| `scripts/ore_blood.lua` | Scan body surface and position together for resource pickups. |
| `scripts/advancing_collapse.lua` | Physical character progression and safe respawn positions. |
| `scripts/advancing_south_guard.lua` | Physical boundary intrusion and distance checks. |
| `scripts/advancing_assault.lua` | Physical targets, clearance and surface context. |
| `scripts/fulgora_lightning.lua` | Physical region, protection, warning target and storm-cell context. |
| `scripts/teleport.lua` | Physical waypoint return history, safe landing and physical character inventory for payment. |
| `scripts/warp_outpost.lua` | Body-based Outpost membership; inventory penalty after confirmed transfer; pending recovery and occupied-surface cleanup protection. |
| `scripts/soft_reset.lua` | Physical evacuation/destructive-stage/return checks; inventory clearing after verified lobby arrival. |
| `info.json` / `changelog.txt` | Test-build version and release notes. |
| `TESTING-3.2.23.md` (new) | This report and in-game test checklist. |

## Official API references

Reviewed against the official Factorio **2.0** runtime documentation, rather than assuming the behavior of the newer 2.1 API:

- [LuaPlayer](https://lua-api.factorio.com/2.0.77/classes/LuaPlayer.html): `character`, `physical_surface`, `physical_position`, `controller_type`, `set_controller`.
- [LuaControl](https://lua-api.factorio.com/2.0.77/classes/LuaControl.html): `can_reach_entity` and the boolean result of `teleport`.
- [LuaSurface](https://lua-api.factorio.com/2.0.77/classes/LuaSurface.html): bounded `find_non_colliding_position` and queued surface deletion.
- [Runtime events](https://lua-api.factorio.com/2.0.77/events.html): a GUI-open event is not evidence that the physical character is present or can reach the entity; teleport can synchronously raise a position-change event.

The patch does not depend on `exit_remote_view` or `physical_controller_type`. Forced/intentional transfers use the documented 2.0 teleport path and verify the body's resulting surface and position. Observers are handled with a remote `set_controller` call.

## Completed offline checks

- **352 Lua files** passed syntax loading with the available Lua 5.4 library; zero syntax errors.
- **57 mocked scenarios** passed using the actual changed runtime modules. Covered remote cave/cache rejection before state creation, reach and surface checks, normal cave exits, failed respawn retention, paired body/camera coordinates, custom character landing prototype, teleport errors and recursion, camera-only observers, cleanup failures, train range/Force checks, failed train entry state, paid Teleporter costs/history/cooldown, coin/resource pickup, Warp membership/retries/stale requests, Reset inventory protection and physical progression/combat/hazards.
- Diff whitespace checks passed.
- The finished ZIP is checked against the supplied archive: unchanged entries retain identical contents; only the files listed above are changed/added. The archive CRCs, single mod-root layout, version metadata and unchanged dependencies are checked.

These are offline checks with mocked Factorio objects, **not a Factorio engine run**. Actual engine events, multiplayer, offline characters and save/load still require the following in-game tests.

## In-game tests

Install this ZIP as the active The Cave version and load a copy of the 3.2.21 test save with the same settings. Check Base and Space Age in separate configurations; Train Interiors and Shelter Defense stay mutually exclusive.

1. **Original reproduction:** stand far from an Iron/Copper/Coal/Uranium/Fortified/Lost City entrance; press M, pan to it and click. The character must remain at its physical location, and a previously unused cave must not start its timer. Repeat for exits and Fortified cache tiers.
2. Close Remote View, walk to a reachable entrance and enter/exit normally. Existing timers, ownership, transfer ports and discovered caves must remain intact. Check a second Force, out-of-reach entities, ghost/spectator/editor controllers and vehicle restrictions.
3. In Remote View, press Ctrl+Enter/use the entry shortcut while viewing a train or Shelter and pan across garden portals. No physical travel should occur. In normal view, verify entry within 10 tiles, refusal outside that range, normal exit and both garden portal rectangles. Test failed/blocked landings without a success cooldown/state change.
4. Keep the body inside a timed cave while viewing the parent/another surface until expiry: the original death/closure consequence must apply to the body. Keep a different player's body outside while their camera views the expiring cave: that body must survive. Check respawn and delayed child cleanup.
5. While the camera views a different surface, verify coin/resource pickups beside the body, physical exploration/highest-zone progress, south-guard intrusion, assault targeting/clearance and Fulgora storms/protection. Panning the camera alone must not change physical progress or hazards.
6. Use the paid waypoint Teleporter in Remote View, then Go Back. Verify the return point is the body's previous location, the cost is still 10 advanced circuits, the cooldown/research rules remain and failed transfers do not charge or overwrite history.
7. **Warp:** test body inside/camera outside and body outside/camera inside the Outpost. Inventory membership follows the body. Exercise a blocked landing: inventory stays until confirmed recovery; cleanup waits; a later journey must not be undone by a stale retry.
8. **Cleanup/Reset:** remove a train with a physical occupant and a separate camera-only observer. Check safe evacuation versus view-only relocation. Exercise reset/return failures and ensure destructive stages do not proceed with bodies still on an old surface.
9. In multiplayer, save/load during pending cleanup/Warp recovery, disconnect/rejoin a physical occupant, and check AFK/offline-body integration. A blocked/offline evacuation may intentionally retain the old surface until recovery is possible; confirm it clears after recovery.

Record any failure with Factorio version, Base/Space Age configuration, relevant settings, the action, body surface/position, viewed surface and the log/stack trace.
