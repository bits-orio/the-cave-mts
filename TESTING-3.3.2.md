# The Cave 3.3.2 team compatibility — local server playtest build

Date: 2026-10-26. Scope: the five agreed compatibility areas; CAVETORIO multi-team support is excluded.

## Delivered components

- **The Cave 3.3.2**, based only on the supplied latest 3.3.1 archive.
- **Multi-Team Support 0.7.9**, a local patch of the supplied 0.7.8 archive, not an upstream release.
- **The Cave MTS Compatibility 0.1.0**, a separate companion. It requires the two local versions above.

No publication/deployment was performed. Original archives were not changed. No test mod, test-only constructor, or `the-cave-test` remote interface is included inside the delivered mod ZIPs.

The core recognizes copied worlds from engine clone events, sets up bases on actual arrival, stores force/world ownership, isolates defeat, and resolves player services to their team home. It does not name, detect or call MTS. The companion supplies staged-start readiness, pause state and effective spectator membership, and registers Cave-owned interiors/child surfaces with MTS. A generic MTS change excludes registered script-built floors from administrative chunk trimming and correctly transfers/clears their explicit ownership.

Train/shelter electricity formulas, battery capacities, transfer rates, resource rewards, existing terrain RNG and original startup defaults were not intentionally changed. One-force behavior is preserved with starter placement delayed two ticks; the old single-force server reset remains the last-team reset. Shared-origin second trains use a deterministic free nearby position to avoid overlap.

## Source provenance

| Input | SHA-256 |
|---|---|
| the-cave_3.3.1.zip | `23443a6c9c5c06fbae3ece4b6cbf407f3979aff2da5c079b49dc86ae0eda3c3c` |
| multi-team-support_0.7.8.zip | `f5c98a5cf641fdcc4afb4c9dc63ac667b3b3cc24a394c27bb56d53496983ab26` |
| Official Factorio 2.1.23 headless archive | `4633250f7747676279fb210a1717ba34caed6b9890c951fb3e469eefe43c46b9` |

Engine: Factorio 2.1.23 build 87750, Linux64 headless. Runtime API names were checked against the official 2.1.23 runtime API. Space Age runs enable the bundled official expansion dependencies. All runtime tests had **zero connected clients**.

## Test method and measured coverage

The temporary `cave-team-sim` creates real engine forces/surfaces and copies real chunks. `copy-a` is a script surface; with Space Age, `copy-b` is backed by a copied Nauvis planet prototype. A separate earlier-loaded copier tests cloning before The Cave's normal chunk handler. Snapshot-only exports call the production train/shelter constructors to create real entities without inventing a LuaPlayer. Real `entity.die()` then drives production loss handlers and countdowns. These fixtures prove entity/state behavior, not player-arrival execution.

Measured checks include:

- Copy registration and copy-of-copy; exact rock/void/resource counts in the tested spawn area; rejected split tile/entity moves, partial areas, shifted chunks and brush clones; unchanged destination map settings and stale-index rejection.
- Early copying repaired with fully built source chunks, including abandoned train-part metadata.
- 36,000 ticks of unchanged generated-template entity/tile counts, inside longer 40,601-tick runs.
- Real Main Train and Shelter destruction: only the losing force's truce/research reset, preserved other-team base, asymmetric diplomacy/share-chart restoration, one correctly scoped/reasoned defeat event, and deletion cleanup.
- Real neutral found wagon joins team-a's four-carriage Main Train, acquires team-a, gains the normal main/interior records and loses its unclaimed marker.
- Force reset preserving a live base, force merge, selective cleanup, single-team server reset, equal new seed on original/copies, retained registry rows and untouched unrelated lobby fixtures.
- Per-world Advancing Collapse initialization/map width and selective reset. Live countdown/wave advancement involving connected players is not inferred from an empty server.
- True original 3.3.1 save upgrades with default, countdown and already-active collapse state; private-server checkpoint/save/reload.
- Original MTS 0.7.8's real Base and Space Age chunk-copy handler with the new core and no companion. Tests lower its slot count where the simulator needs extra forces; untouched baseline smoke runs also use the default 60 Base / 20 Space Age slots.
- Companion/local MTS real-engine tests: staged/clock-zero readiness, pause/resume, interior ownership scanning, protected trim queues, preserved paused accumulator energies/solar factors, optional next-tick disband, merge, force-name reuse and deleted surface-name reuse.

Final run results are inserted below from the captured logs. Assertion counts are groups per run; repeated checks across configurations are not distinct gameplay features.

| Final test configuration | Engine ticks | Passed assertion groups | Result |
|---|---:|---:|---|
| base-default | 40,601 | 38 | PASS |
| sa-default | 40,601 | 38 | PASS |
| base-train | 40,601 | 47 | PASS |
| sa-train | 40,601 | 47 | PASS |
| base-shelter | 40,601 | 44 | PASS |
| sa-shelter | 40,601 | 44 | PASS |
| base-collapse | 40,601 | 41 | PASS |
| sa-collapse | 40,601 | 41 | PASS |
| base-mts-original | 4,661 | 39 | PASS |
| sa-mts-original | 4,661 | 39 | PASS |
| Companion + patched MTS, Base | 600 | 28 | PASS |
| Companion + patched MTS, Space Age | 600 | 28 | PASS |

Additional PASS results: three original-3.3.1 upgrade cases (default, countdown with 1,234 ticks remaining, already-active phase); shared original with two real train bases (9 groups each on Base and Space Age); actual private-server checkpoint then reload for 600 ticks on Base and Space Age; uninstrumented shipping-source load/reload for 600 ticks with original MTS defaults (60 Base / 20 Space Age slots).

Examples from the final engine logs:

```text
seed 12345 spawn area: nauvis 200 rocks / 15656 void / 71 resources
copy-a and copy-b: 200 rocks / 15656 void / 71 resources
neutral found wagon: valid=true force=team-a same_train=true
main_record=true wagon_record=true still_unclaimed=false carriages=4
template interval: 36000 ticks; entity/tile counts unchanged
server reset: original and registered copies reseeded together; lobby fixture retained
```

The same seed/count result occurs in these deliberately controlled fixtures; it does not assert that every arbitrary seed has those counts. Full logs and numbered assertions are in the QA archive.


### Isolated Lua checks

Ten test programs also pass under Lua 5.2 with API doubles. These include 19 arrival/home/scheduling cases, 23 player-service cases, 20 child-record/handle cleanup cases, 15 collapse cases, 6 shared-assault cases, and additional registry, train migration, truce, force cleanup and companion cases. They cover remote-controller return, two-tick arrival timing, readiness retry, 60-tick suppression, first-home persistence, shared-world activity, item-research isolation, and offline-return tickets. They are **not** additional Factorio-client gameplay runs.

All production Lua files parse under Lua 5.2. Whitespace checks pass. The final three-component engine snapshot covers 526 production Lua files; its aggregate manifest SHA-256 is `337b74a88c1091beaaef129241a174c894c022a186da9c27068d904926eb9449`.

## Remaining limits and deliberate choices

1. **Client validation remains required.** No real player was connected. Actual MTS claim/lobby timing, character displacement around the shelter, two-client GUI/message isolation, offline body return, remote-view transitions, automatic replacement base at tick +60, and player-gated wave/growth/collapse progression require the checklist in INSTALL-FA.txt. The build is suitable for a staging server, not certified live multiplayer deployment.
2. **CAVETORIO stays single-force and is excluded.** Leave it disabled on the multi-team server. The small warp ownership bookkeeping preserves the existing warp path; it does not implement multi-team outposts.
3. **Ambiguous old ownership is preserved.** A 3.3.1 save with legacy copied worlds and an actual existing base/character on original Nauvis retains that original owner and logs a conflict instead of deleting a potentially legitimate base. A synthesized migration-only default owner is provisional and becomes a template when a later qualifying copy proves the empty-original arrangement. Existing misplaced bases/contradictory old worlds should be reviewed on a save copy.
4. **Companion interface is intentionally broader than the pasted one-event-only proposal.** `the-cave-v1` exposes `get_event_id`, `register_adapter`, and `get_owned_surfaces` to implement the agreed staged-start/spectator/interior-statistics integration. It offers no world-registration or defeat-override function. `diggy-v1` is preserved. Independent Diggy still conflicts with that interface.
5. Optional disband is off by default. It acts next tick only for `scope="force"`; server defeat runs the staged server reset. This avoids deleting maps underneath an active staged reset.
6. MTS's existing loaded-burner-fuel pause behavior and broader native team-slot/planet merge semantics were not redesigned. The patch covers registered surface ownership, including merge and name reuse. Mods that disable MTS's chunk copying, arbitrary third-party warps, large multiplayer performance/desync behavior, and the user's complete mod pack are not certified by these tests.
7. The research-offer table in this actual source is empty. Buyer-force lookup and revalidation were corrected and isolated-test verified; no claim is made that a currently enabled research offer was observed in the engine.
8. The pre-existing Space Age spawner collision-mask warning also occurs with the original archives and did not fail these tests.

## Per-file changes in The Cave

| File | Change |
|---|---|
| `control.lua` | Wires clone registration, delayed arrivals, physical/controller changes, force resets/merges, selective deletion, per-force defeat routing, and global-stop versus per-force countdown behavior. |
| `scripts/cave_worlds.lua` | New leaf registry with surface-name/index identity, original/copy/template distinctions, immutable first ownership, and provisional legacy ownership confirmation. |
| `scripts/cave_world_events.lua` | New whole-chunk clone recognition and source-before-build repair; legacy migration; late-copy migration repair and surface cleanup. |
| `scripts/cave_teams.lua` | New generic home/ownership/active-force coordinator; two-tick arrival queue, pause/readiness adapter, start marks and reset suppression. First home persists without base modes. |
| `scripts/cave_lifecycle.lua` | New orchestration of arrival, force-only reset, evacuation, diplomacy restoration, per-force cleanup, merge/deletion, deferred offline return, and custom defeat interface. |
| `scripts/cave_child_state.lua` | New shared child ownership validation, record transfer/cleanup and disposal of recorded render/chart/inventory handles; safe player-return helpers. |
| `scripts/world.lua` | Uses the registry for main-world features while retaining original/child-only construction. Exposes built-chunk inspection and construction for clone repair. |
| `scripts/advancing_zones.lua` | Main-world predicates use registry; collapse status reads the correct world phase. Shared seed layout is unchanged. |
| `scripts/advancing_collapse.lua` | Per-world phases, countdowns, map widths, migration, arrival start/reset, force-local displays, and selective cleanup. |
| `scripts/advancing_area.lua` | Uses generic ownership and the relevant surface phase. |
| `scripts/advancing_assault.lua` | Gates work by active world; shared originals aggregate eligible resident players/objectives without multiplying schedules. |
| `scripts/advancing_clearing.lua` | Uses world-specific phase and activity for clearing. |
| `scripts/advancing_recovery.lua` | Uses world-specific phase and activity for recovery. |
| `scripts/advancing_south_guard.lua` | Uses world-specific phase and activity for guard processing. |
| `scripts/cave_placement.lua` | Reads the applicable world phase for placement constraints. |
| `scripts/enemy_nest_growth.lua` | Registry/activity checks prevent timed growth on templates and inactive worlds. |
| `scripts/cave_enemy_expansion.lua` | Registry/activity checks scope expansion to running cave worlds. |
| `scripts/train_wave_defense.lua` | Uses force-index locomotive lookup, per-force defeat/world activity, and selective force cleanup. |
| `scripts/train_interiors.lua` | Arrival-only starter placement; force-index migration; precise base/interior/garden ownership and cleanup; no gardens for empty slots; clone metadata; neutral found-part claiming; shared-origin placement; home returns. |
| `scripts/shelter_core.lua` | Arrival-only layout placement; no initial lobby/template base; force-specific defeat/GUI/alarm and lifecycle helpers; skip interior rebuild during own reset. |
| `scripts/warp_outpost.lua` | Ordinary Main Train loss detection/countdown/GUI becomes per force; existing warp move records ownership. No multi-team CAVETORIO implementation. |
| `scripts/main_train_defeat.lua` | Per-force truce and character protection, independent countdown state, correct global-stop decision, asymmetric relation restoration, deferred offline return tickets. |
| `scripts/soft_reset.lua` | Uses registered worlds/participating forces, preserves registry and adapter, returns to own homes, reseeds copies, preserves unrelated lobbies, and exports common evacuation cleanup. |
| `scripts/offline_player_body.lua` | Uses effective force/home and physical world; no template fallback. AFK exempts forces with no Cave participation. |
| `scripts/ore_veins.lua` | Starter oil target keyed by force and home world; arrival initialization, legacy adoption and deletion cleanup. Existing digging-mode initial terrain patches remain unchanged. |
| `scripts/market_coin.lua` | Research display and purchase revalidation use the buyer force. Latent research-offer item count uses the item count rather than technology string; current RESEARCH_ITEMS is empty. |
| `scripts/darkness_infestation.lua` | Allows Cave worlds/children and planets; skips templates and unrelated script lobbies. |
| `scripts/charting.lua` | Exports per-force/world arrival charting instead of charting on player creation. |
| `scripts/game_settings.lua` | Extracts per-force setup so force.reset restores the same recipe/research setup. |
| `scripts/quality_everything.lua` | Exports per-force quality unlock synchronization. |
| `scripts/collapse.lua` | Uses generic owner/team labels and other active Cave forces for broadcasts. |
| `scripts/depth_levels.lua` | Migrates force-name depth maps to force indexes and selectively clears reused-force state. |
| `scripts/progression_rooms.lua` | Generic ownership inference and selective progression/region-counter cleanup. |
| `scripts/caverns.lua` | Selective force pity-state cleanup and additional deleted-surface cleanup without clearing other teams. |
| `scripts/information_gui.lua` | Uses generic force labels and index-keyed depth state. |
| `scripts/uranium_caves.lua` | Validated child owner/enumeration, force transfer/cleanup and safe home returns; queued deletion is treated as accepted. |
| `scripts/mineral_caves.lua` | Validated child owner/enumeration, force transfer/cleanup and safe home returns; queued deletion is treated as accepted. |
| `scripts/fortified_vaults.lua` | Validated child owner/enumeration, force transfer/cleanup and safe home returns; queued deletion is treated as accepted. |
| `scripts/lost_city.lua` | Validated child owner/enumeration, force transfer/cleanup, safe home returns and source-force progress retirement. |
| `scripts/bob_ore_layout.lua` | Uses registry main-world recognition. |
| `scripts/bob_ores_resources.lua` | Uses registry main-world recognition. |
| `scripts/mobile_factory_resources.lua` | Uses registry main-world recognition. |
| `scripts/fulgora_lightning.lua` | Uses registry cave-world recognition. |
| `scripts/teleport.lua` | Uses registry for valid saved cave destinations. |
| `scripts/mts.lua` | Removed: the Cave core no longer detects/calls MTS directly. |
| `info.json` | Version 3.3.2; preserves original optional expansion/mod dependencies and original authorship. |
| `changelog.txt` | Documents the local compatibility release and test limitations. |
| `TESTING-3.3.2.md` | This verification report. |

## Companion and MTS local patch files

| Component/file | Change |
|---|---|
| Companion `info.json` | Separate 0.1.0 mod; requires The Cave >=3.3.2 and bundled MTS >=0.7.9. |
| Companion `control.lua` | Generic adapter callbacks; actual MTS event subscription; 300-tick child/interior registration plus immediate registration on pause; guarded optional deferred disband. |
| Companion `settings.lua` and locale | Runtime optional disband setting, default false. |
| Companion `README.txt` | Installation, surface policy and pause/disband boundaries. |
| MTS `scripts/team_surfaces.lua` | Optional `allow_chunk_trim` policy; safely freezes a newly registered surface on an already paused team; transfers registered ownership on merge and clears ownership/policy on deletion. |
| MTS `scripts/chunk_trim.lua` | Excludes explicitly protected surfaces both when queuing and when executing an already queued trim. |
| MTS `events/ticks.lua` | Hooks generic registered-surface merge/deletion cleanup, preserving reaper banking order. |
| MTS `info.json` and changelog | Clearly labels local 0.7.9 compatibility build. |

## Reproduction and release integrity

The separate QA archive contains fixture sources, machine-readable summaries, final engine logs and source manifests; it is for development only and must not be placed in the server mods directory. Temporary `the-cave-test` exports were appended only to disposable test snapshots. The final release ZIPs are rebuilt from the production working directories, exclude Git/test snapshots, and are checked for internal version/root-folder agreement and ZIP CRC integrity. Package SHA-256 values are in SHA256SUMS.txt.

Representative commands used:

```text
factorio --config <private-config> --mod-directory <test-mods> --create <suite.zip> --map-gen-seed 12345
factorio --config <private-config> --mod-directory <test-mods> --benchmark <suite.zip> --benchmark-ticks 40601 --benchmark-runs 1
factorio --config <private-config> --mod-directory <test-mods> --start-server <suite.zip> --server-settings <private-settings>
```

The private server was bound to local test use; no user server or external repository was deployed or modified.
