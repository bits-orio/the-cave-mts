# The Cave 3.1.91 — Advancing Collapse assault test build

Base: the user-confirmed stable `the-cave_3.1.90(1).zip` (SHA-256 `ab994c9c41cc972002c7f2d93c930cfa70cf63abbb61269a64eb991dfbb23e31`). The extracted baseline matched every file in that ZIP before editing.

## Locked behavior

- The existing two-hour connected-gameplay countdown is unchanged. At zero, the electric southern boundary and its stranded guard retire and the northbound collapse continues.
- The first assault begins five seconds later. Wave 1 requests 30 attackers; every later wave adds two, and every additional connected player on the surface-owning team adds five.
- Waves use a fixed three-minute deadline. Living, trapped or ignored attackers never postpone the next wave.
- Units use the surface's current Evolution tier and a deterministic 70% Biter / 30% Spitter mix. They retain the existing Train Wave per-unit coin/resource settings; no Boss or wave-clear reward was added.
- Two scripted nests are requested per initial wave. The request gains one nest after every ten completed waves, up to eight in one wave and 24 active nests on a surface. Every active nest requests one reinforcement per minute.
- Units are created in batches of at most 25 per second. At most 300 assault units can be alive on a surface; later deadlines still advance the wave number when that cap is full.
- The spawn band follows the current southern front. At ordinary collapse speed it is about 30 tiles ahead; catch-up speed expands it to about 232 tiles so a newly staged wave has one full wave interval plus a 20-row safety margin.
- Commands refresh every 30 seconds. A stationary attacker directly attacks a nearby player building. Only a unit stationary for five minutes with no nearby player blocker may be relocated to the current front.
- With no connected player belonging to the surface owner, spawning pauses and missed intervals are not accumulated. On return, at most one overdue wave starts.
- Existing active saves migrate in place: southern guard actors/visuals are removed and wave 1 is scheduled for five seconds later. Late-created team surfaces start at the visible Y=64 front and never rebuild the retired guard strip.

## Verification performed

- Executed the real `scripts/advancing_assault.lua` in a deterministic Lua runtime harness with mocked Factorio runtime objects. Verified active-save guard retirement, five-second wave start, 25+5 batch creation, two nests, first reinforcement exactly 60 seconds after nest creation, and the fixed second-wave deadline while all wave-1 units remained alive.
- Verified owner-force multiplayer scaling: an unrelated force did not increase the wave, while a second player on the owner force added exactly five attackers.
- Verified the offline/no-relevant-player pause leaves one overdue deadline rather than replaying missed waves on reconnect.
- Verified ordinary/catch-up staging distances of 31/232 tiles for the current 4-per-8-tick and 10-per-1-tick collapse rates.
- Verified blocker handling: a nearby player wall received a direct attack and suppressed relocation; removing the blocker allowed a five-minute-stale unit to relocate.
- Simulated every one-second controller update through wave 30 without killing attackers. The measured maxima were exactly 300 active units and 24 active nests; neither cap was exceeded.
- Executed the private nest data-stage module with copied Biter/Spitter spawners. Both generated prototypes retained the source spawn definitions while disabling native population, defensive population, pollution absorption and autoplace; the source prototypes were unchanged.
- Exercised active late-team-surface creation and confirmed Y=64 initialization, immediate assault ownership and no guard scheduling. Separately exercised a pending guard migration at Y=64 and confirmed it exits before chunk generation or entity creation.
- All six added/modified Lua integration modules compile in the available Lua parser. Across the complete candidate tree (329 Lua files), the parser result exactly matches the stable 3.1.90 baseline: its only rejection is the unchanged integrated Damage Indicator cache's Factorio-Lua `const` construct, which this non-Factorio Lua runtime does not implement.
- Checked changed files for trailing whitespace and checked the new English/Russian Advancing Collapse locale keys in their exact sections.

Factorio headless is not installed in this workspace, so native prototype loading, save migration and multiplayer pathfinding still require the graphical/server test below. The local harness, its temporary files and logs are excluded from the release ZIP.

## In-game checks

1. Back up an existing save whose Advancing Collapse is already active, install 3.1.91, and load it. The old southern guard should disappear; wave 1 should be announced after about five seconds and the HUD should show 30 requested attackers and two nests as batches finish.
2. Leave at least one wave-1 attacker alive or enclose it with walls. At three minutes, wave 2 must start anyway. The enclosed unit should attack the wall rather than stop the schedule.
3. Leave one nest alive for at least one minute and verify it produces a reinforcement. Destroy other nests and confirm the HUD counts fall on the next one-second update.
4. Observe two consecutive waves while the collapse advances. Their spawn band should move north with the front. If catch-up activates, the next band should appear substantially farther ahead instead of being immediately erased.
5. Disconnect every player on that team for longer than three minutes, then reconnect. Only one overdue wave may start; missed waves must not burst-spawn.
6. Repeat on the multiplayer server and confirm each team surface receives only its owning force's player scaling and target objective.

## Exact files changed from 3.1.90

- `control.lua`
- `data.lua`
- `prototypes/advancing_assault.lua` (new)
- `scripts/advancing_assault.lua` (new)
- `scripts/advancing_collapse.lua`
- `scripts/advancing_south_guard.lua`
- `scripts/cave_enemy_expansion.lua`
- `locale/en/locale.cfg`
- `locale/en/settings.cfg`
- `locale/ru/locale.cfg`
- `locale/ru/settings.cfg`
- `info.json`
- `changelog.txt`
- `TESTING-3.1.91.md` (new)

This is a test build awaiting the user's live client/server confirmation.
