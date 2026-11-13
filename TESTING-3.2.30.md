# The Cave 3.2.30 — moving-collapse pathfinding regression

Based on the released 3.2.29 archive (SHA-256
`17c1c5c93b36258c13cb209f5e40b52d8c0188e12d2b49e6d4da8fe179c352e8`).
The 3.2.29 garrison design remains intact; this build changes collapse terrain
commits and the top-level defeat flush only.

## Diagnosis and fix

The new supplied save, `the cave 07-10-2026 2.zip`, SHA-256
`da8c5844df4fbe071f95d773a15a282e0e403dac5aded9d02937ecfc6384b5b8`,
contains attackers that already have attack commands. At the first observation,
233 of 242 are in the native `stale` movement state. Command presence alone is
therefore insufficient evidence that an attacker is following a path.

With the physical collapse moving normally, a controlled four-minute replay of
3.2.29 leaves all 494 surviving attackers stale; 480 have been stationary for
at least 30 seconds. Disabling only command refresh does not clear the mass
stall. Enabling the global path cache also does not clear it. Stopping only
physical front processing lets attackers resume, while the wave, production
and command controllers keep running.

Batching the physical tile writes every 256 ticks (about 4.3 simulation seconds)
resolves that reproduced stall. Logical erosion, entity removal, row order,
player-count speed and train catch-up remain at their original cadence. A
consumed tile can remain visually present until the next batch. Placement and
respawn checks still use the logical collapse state. Pending tile edits and
commit deadlines are saved with the surface state; batches also flush on
recovery, configuration changes, no-player pauses and the defeat guard.

The interventions establish that frequent terrain mutation triggers the stall
in this fixture. Native path-search invalidation/starvation is the explanation
consistent with the measurements; no internal engine queue is exposed here.
Changing the attack command or increasing enemy counts is not part of this fix.

## Verification

All tests use independent copies; the original supplied save is unchanged.

- Factorio 2.0.77, Space Age, quality, elevated rails, even-distribution 2.0.2
  and The Cave. The supplied save references additional utility mods unavailable
  in the test environment; this is not a full replay of the user's mod pack.
- A/B replay: same save, same front progression to Y=-241 and wave 44.
  Original: 494 survivors, all stale. Experimental 256-tick batching: 163
  survivors, all observed moving, only one stationary for 30 seconds. Lower
  survival is not a lowered spawn budget; wave and nest production counts are
  unchanged.
- Production implementation: 15 simulation minutes with the front continuously
  moving, wave 42 to 49, front Y=-227 to -280, and 15 live nests unlocked.
  No mass stall recurs. From minute one onward, at most nine attackers per
  sample are stationary for 30 seconds. At the final observation, the six
  never-yet-moving survivors are only seven seconds old.
- A native save taken with 56 queued tile edits retains all 56 and the original
  deadline after reload. An already-logically-eroded sample tile stays dirt
  while waiting, then becomes out-of-map on the scheduled commit.
- No-player pause and recovery flush queued edits. Recovery removes the owned
  nests and restarts the normal round with one group. Killing the Main Train
  on a test copy exercises the actual top-level defeat guard: pending edits
  flush before the ordinary controllers stop.

The diagnostic offline-player override stands in for one connected player and
keeps the normal collapse/wave controllers running. Observer hooks, artificial
stress/phase triggers, private commands and test saves are excluded from the
released ZIP. The original 3.2.29 tests with a fixed front did not reproduce this
regression and should not be treated as proof of continuously moving behavior.

- Six-minute stress replay with the physical front moving: artificially unlock
  all ten nest groups and trigger ordinary wave 311 (650 requested attackers).
  The peak sample has 963 live attackers. The end has 584 survivors, with 546
  moving/adapting and nine stationary for 30 seconds. Every surviving attacker
  older than 30 seconds has been observed moving; the never-yet-moving units
  are newborns aged zero or seven seconds. Native attacks produce 5,575 damage
  events. No locomotive hit is observed: the fixture's train remains defended.
  Large simultaneous bursts can still queue paths; this test does not establish
  a 30-second upper bound on movement (the peak stationary-30s sample is 430).

## Exact changes from 3.2.29

- `scripts/advancing_collapse.lua`: persistent terrain batching and flushes.
- `control.lua`: flush before the existing defeat guard returns.
- `info.json`, `changelog.txt`: version and release entry.
- `TESTING-3.2.30.md`: this guide.

The 16-by-5 chunk arena, ten groups of three nests, minute 0/4/8/.../36
unlocks, same-home two-minute rebuilding, immediate objective commands,
30-second selective watchdog, 20-second nest production, 1,000-attacker cap,
wave formulas and full-width red/green northern line remain as in 3.2.29.

## تست شما

نسخهٔ ۳.۲.۳۰ را فعال کنید و یک کپی از همان سیو فریز‌شده را با مدهای خودتان
باز کنید. خروجی لانه‌ها و دشمن‌های موج باید شروع به حرکت کنند و حمله ادامه
پیدا کند. تغییرات ظاهری زمینِ کولاپس اکنون در دسته‌های حدود چهارثانیه‌ای
ثبت می‌شوند؛ سرعت کلی پیشروی همان است. بعد از ذخیره و بارگذاری هم حرکت
دشمن‌ها و زمان‌بندی لانه‌ها را بررسی کنید. این تست رفع توقفِ بازتولیدشده را
تأیید می‌کند؛ تضمین مسیر برای هر چانکِ کاملاً مسدود نیست.
