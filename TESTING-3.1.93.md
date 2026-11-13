# The Cave 3.1.93 — faster Advancing Collapse and passive Queen

Test release based on the previously tested `the-cave_3.1.92.zip`.
Base SHA-256: `37f0bbfc9b830cdf10119ba21bd58cde03ff75958db792e0251bcaf6fb44c3ec`.

## Install and test command

Install version 3.1.93 in place of 3.1.92 and load your active Advancing Collapse save.
With administrator access, enter this exact command in chat/console:

```text
/the-cave-advancing-queen-test
```

The two-hour Advancing Collapse countdown must have ended and the open rectangle must be ready. The command also works from your team's train interior. It creates a Queen in the central spawn column and prints a clickable GPS position; it does not move the player, change wave numbers, skip the countdown, or clear existing nests. If a Queen is already alive, it prints her position instead of adding another test Queen. After killing her, run the command again for another test.

## Release behavior

| Rule | Value |
| --- | --- |
| Scheduled waves | Every 60 seconds; first wave retains its five-second delay |
| Nest production | One unit of the nest's family every five seconds while space/capacity permits |
| Living assault units | At most 1,000 per main surface, including Advancing Queens |
| Living assault nests | At most 24 per main surface, shared by waves and every Advancing Queen |
| Queen milestones | Waves 60, 120, 180, and subsequent multiples of 60 |
| Queen health | 50,000; no automatic regeneration |
| Queen nesting | Up to three immediately on spawn, then up to three every 30 seconds |
| Queen combat | No attacks, damage delivery, rock digging, or joining native attack groups |

At 22 living nests the Queen can add two. At 20 she can add three, then one at the next interval. At 24 she waits for a later interval with space. Destroying her stops her own future nesting; existing nests continue reinforcing, and scheduled waves keep their normal nest-building behavior. Nests and Queens consumed by the collapse are removed.

Queen nests rotate through all four families. Scheduled wave quotas remain 40% Biter, 30% Spitter, 15% Armoured Biter and 15% Arachnid with integer rounding, and all four families retain current Evolution scaling. Nest creation and reinforcement use the existing bounded, collision-aware central-column placement searches. A blocked location may reduce a batch; no buildings or terrain are destroyed to force a spawn.

A milestone Queen that cannot spawn because the 1,000 limit is full or the column is blocked waits in saved state and retries every five seconds. The next available population slot is reserved for her so ordinary reinforcements cannot continually take it. Each milestone requests one Queen, even if an earlier milestone's Queen survives. All share the same population and nest limits. The test command's repeat protection does not suppress natural milestones.

The Queen uses existing level-one Queen artwork/resistances through a separate private prototype. She moves between clear destinations in the central column with a margin ahead of the moving front. This does not guarantee passage through player-built enclosures; she never attacks obstructions or destroys construction. The ordinary Cave Queen's stats, regeneration, nesting and discovery behavior are unchanged.

The 96-by-160 rolling clearing, resource-only automatic opening, two-hour countdown, 30 starting attackers, +2 per later wave, +5 per additional connected team player, 25-unit-per-second wave batching, reward settings and other modes are unchanged. The 1,000-unit/24-nest limits cover this assault controller's entities, not unrelated enemies discovered elsewhere.

## Existing saves

The one-time controller upgrade retains the current wave, living units/nests and pending wave batches. It shortens the next wave deadline to at most 60 seconds from upgrade and the next reinforcement deadline to at most five seconds. It does not replay past Queen milestones or reset the collapse. Existing newer-state deadlines and Queen records survive subsequent configuration changes. If a team is offline, generation pauses; returning does not create a backlog burst of missed waves or nesting intervals.

## Verification completed

The modified Lua code was executed with the installed Lua 5.4 library and mocked Factorio objects. These tests exercise controller behavior and saved table state, not native engine pathfinding or an actual save file.

- Checked all four family quotas for totals 0–1,000, every Evolution tier, nest rotation, wave batching, five-second production, 60-second scheduling with survivors, team scaling, readiness, migration and pause/reconnect behavior.
- Simulated repeated waves reaching the 1,000-unit and 24-nest limits; checked consumed nests are removed and blocked searches stay bounded and inside the central column.
- Checked the private Queen's 50,000 health, zero healing, no attack effects, passive AI settings and unchanged original Queen prototype.
- Exercised the registered admin command, immediate three-nest batch, exact 30-second nesting boundary, four-family rotation, partial-cap cases 22→24 and 20→23→24, and continued reinforcement after Queen death.
- Confirmed the Queen remains outside the attack-unit registry and receives only move/stop commands with no combat distraction, including beside a player wall. Checked destinations follow a moving front and collapse removes a consumed Queen.
- Checked milestones at waves 60 and 120, surviving previous Queens, a full 1,000 population, reserved-slot priority with offset clocks, and pending Queen retry state across module reload/configuration change.
- Checked admin, enabled-mode, active-phase, own-team, readiness and blocked-position command gates; repeat-command location reporting and train-interior surface resolution; no wave/deadline changes from the test command.
- Re-ran the existing rolling-clearance tests: 15,360 tiles, exact three-row replacement, resource/building preservation, no discovery hooks, saved cursor, team sealing and collapse-rubble protection.
- Re-ran resource/reward tests for the regional profiles and all private families; the new Queen is not interpreted as a legacy reward Boss.
- Compiled all 330 mod Lua files, checked locale keys, compared every candidate file with the 3.1.92 ZIP, and validated the final ZIP's integrity, version and root folder.

## In-game checks still required

Factorio is not installed in the build environment. Native prototype loading, actual save loading, combat/pathfinding, multiplayer synchronization and UPS must be checked in the client/server.

1. Load the existing active save with 3.1.93. Confirm its wave number remains and the next wave is within one minute. Observe several living nests producing at five-second intervals while under the cap.
2. Run the command, use the printed GPS position, and check the Queen has 50,000 health. Approach, shoot her, and move a train nearby: she should never strike any target or dig rocks.
3. If all 24 nest slots are occupied, destroy several and wait for the next 30-second Queen interval. Scheduled waves may also fill slots; their continued nest building is intentional. Watch the partial batches and family rotation.
4. Kill the Queen. Her existing nests should remain active, with no later Queen-owned construction. Ordinary one-minute waves still continue.
5. Save/reload while a Queen is alive and again with the population near 1,000. Check timing resumes, units stay capped and no extra Queen appears from reload alone. Observe movement as the front advances and report any crowding, difficulty or UPS issues.

## Exact files changed from 3.1.92

| File | Purpose |
| --- | --- |
| `scripts/advancing_assault.lua` | Timing/cap changes, saved-state upgrade, independent Queen lifecycle and command |
| `prototypes/advancing_assault.lua` | Passive 50,000-health Queen copy |
| `scripts/advancing_collapse.lua` | Expose command registration |
| `control.lua` | Register the Queen test command |
| `locale/en/locale.cfg` | English Queen name and command messages |
| `locale/ru/locale.cfg` | Russian Queen name and command messages |
| `info.json` | Version 3.1.93 |
| `changelog.txt` | Release entry |
| `TESTING-3.1.93.md` (new) | This behavior and verification record |

All other base files are preserved byte for byte. Validation fixtures are excluded from the playable ZIP. Earlier TESTING files describe historical releases.
