# The Cave 3.2.29 — Advancing Collapse garrison test

Built only from the user-approved 3.2.27 archive, SHA-256:
`6830acbcc3c1bf799f5cb0f805570bfad2537af27799161b05927266286e1b6d`.
No 3.2.28 source changes are merged. Existing dependencies and Startup settings
are retained.

## Implemented behavior

- The assault clearing spans the 510-tile playable width and five native chunk
  rows: 80 chunk cells, with 31-tile outer columns. Its boundary advances in
  native chunk steps as the physical collapse continues moving.
- Ten groups reserve three separate nest chunks each. A spare chunk separates
  different groups. One group unlocks at combat minute 0, then at 4, 8, 12, 16,
  20, 24, 28, 32 and 36. The normal 20-wave combat round remains 40 minutes.
- The unlocked count determines capacity, not an unconditional living count.
  Placement blocked by a player, building, terrain or unavailable spacing waits
  and retries. The shared maximum is 30 living assault nests; Queen placement
  also respects the unlocked slots, homes and rebuilding deadlines.
- A destroyed nest waits two simulation minutes before rebuilding in its saved
  native chunk. Temporary obstruction never rerolls that home. A chunk that
  leaves the moving clearing can receive a new reservation when its nest needs
  replacement. A living nest keeps its home reserved until the physical front
  consumes it, even if the aligned boundary has stepped past its chunk.
  Collapse losses also use the delay, so the live total can be
  temporarily below the unlocked capacity.
- Recovery cancels all reservations/rebuild jobs and retires every owned
  assault nest, including a survivor between the chunk boundary and physical
  front. The following combat round starts with one group and a fresh clock.
  The global wave number continues increasing.
- Scripted nest offspring immediately get the same objective attack command
  as wave attackers. Prefer the owning force's train, or the configured Shelter
  objective; preserve the existing target fallback when no objective exists.
  Registered native-spawn events are handled once, without taking over ordinary
  map nests or other wave-defense units.
- The watchdog checks each tracked attacker every 30 simulation seconds.
  Renew idle or missing commands; preserve moving units and active attacks.
  Retain the previous five-minute safe reposition fallback for a stale unit.
- One line marks the entire northern boundary. It is red during combat and
  green during preparation/recovery. The old rectangle sides/bottom are removed.
- Preserve wave attacker formulas, the 25-unit spawn batches, 1,000-attacker
  cap, 20-second scripted nest-production cadence, enemy prototypes and stats.
  The existing special wave 60 remains ten minutes, followed by 30-minute
  recovery; ordinary recovery remains fifteen minutes.

## Exact files changed from 3.2.27

| File | Change |
| --- | --- |
| `scripts/advancing_nest_groups.lua` (new) | Persistent homes, group clock, bounded placement, rebuild delay and recovery reset. |
| `scripts/advancing_assault.lua` | Migration, shared nest placement, initial commands, selective watchdog, native spawn/death handlers and owned-nest cleanup. |
| `scripts/advancing_clearing.lua` | Full width, 80 native cells, chunk-aligned bounds and resumable widening. |
| `scripts/world.lua` | Clip this clearing's generation halo at the finite map edges so readiness cannot wait for an impossible chunk. |
| `scripts/advancing_schedule.lua` | Nest cap 15 to 30; existing clocks retained. |
| `scripts/advancing_area.lua` | Full-width top line and legacy visual cleanup. |
| `scripts/advancing_collapse.lua` | Forward the two assault event handlers. |
| `control.lua` | Connect nest deaths/native spawn events to those handlers. |
| `locale/en/locale.cfg`, `locale/ru/locale.cfg` | Update five messages for the boundary and shared nest capacity. |
| `info.json` | Version 3.2.29 only. |
| `changelog.txt` | Release entry. |
| `TESTING-3.2.29.md` (new) | This guide. |

## Verification

- Syntax loading for all 354 Lua files, plus 1,424 assertions against the actual
  geometry, scheduler and reservation modules: unlock boundaries, home
  uniqueness, group buffers, rebuild delay, blocked-home retention and reset.
- Factorio 2.0.77 loads the supplied save with the new code. The existing wave
  39 clock is retained; its normal transition to wave 40 still occurs. All 15
  existing nest entity IDs survive migration to separate reserved chunks, and
  the already-unlocked cycle fills to 30 nests after widening is ready.
- Actual engine placement at all ten unlock boundaries gives 3, 6, ... 30
  nests with separate native chunks and the intended inter-group gap. These
  checks advance the cycle clock explicitly; they are not a full uninterrupted
  40-minute playthrough.
- An actual nest death leaves 29 nests at 119 seconds. Saving/reloading retains
  its deadline; it rebuilds after 120 seconds in the original native chunk with
  a new entity ID.
- A deliberately stopped attacker starts moving by the 31-second observation
  after watchdog renewal. A moving attacker keeps its initial command; an
  attacker fighting a wall keeps its attack. A synthetic native-spawn event
  through the actual control handler registers/commands once, even when raised
  twice. Normal nest births use the existing script-controlled production.
- In the widened area, a 650-unit wave and 600 observed nest offspring all get
  initial commands and move. The heavy run covers six simulation minutes at
  accelerated game speed. Maximum observed first-movement latency is 62 seconds
  for wave units and 53 seconds for nest offspring; no live observed unit remains
  without moving at the end. This does not establish that every obstruction
  clears within 30 seconds, or reproduce the original 600-unit mass freeze.
- Explicit front advances exercise home expiry/replacement. Recovery cancels
  pending rebuilds and removes owned nests, including the physical-front gap;
  its green line returns to red and the next round starts at three nests.
- The final uninstrumented package is checked for valid ZIP entries, version,
  exact source bytes and the expected changed-file list. Native Base-only map
  creation and Space Age save loading are also checked.

Engine fixtures run on independent save copies with a diagnostic offline-player
override and a fixed physical front except during explicit advance checks.
Diagnostic hooks, private commands and test fixtures are excluded from the ZIP.
Original source/save files remain unchanged. Full multiplayer pathfinding,
client appearance, normal continuously moving-collapse behavior and server UPS
still need the user's playtest. The watchdog reduces command-related stalls;
it cannot guarantee a path through a physically blocked route.

## تست شما

1. فایل ZIP را داخل پوشهٔ `mods` بگذارید و نسخهٔ 3.2.29 را فعال کنید.
   یک کپی از سیو فعلی را با همان مدها و تنظیمات باز کنید.
2. خروجیِ لانه‌ها را جدا از دشمنانِ خود موج نگاه کنید: باید بلافاصله فرمان
   حمله بگیرند. اگر تجمع دیدید، حدود ۳۰ تا ۶۰ ثانیه هم حرکتشان را بررسی کنید.
3. بعد از شروع یک دور تازه، گروه‌ها در دقیقهٔ صفر و سپس هر چهار دقیقه اضافه
   می‌شوند؛ دقیقهٔ ۳۶ ظرفیت ده گروه و ۳۰ لانه باز می‌شود.
4. یک لانه را بکشید: زودتر از دو دقیقه برنگردد و اگر چانک هنوز قابل استفاده
   است، در همان چانک برگردد. ساخت‌وسازِ مسدودکننده می‌تواند بازسازی را عقب بیندازد.
5. موقع ریکاوری، لانه‌های این دور پاک شوند و خط سبز شود؛ دور بعد از یک گروه
   شروع شود. بعد از ذخیره و بارگذاری هم زمان‌ها و چانک‌های لانه حفظ شوند.

اگر دوباره توقف طولانی دیدید، مدت توقف، شمارهٔ موج، شمار دشمنان، موقعیت
چانک و یک کپی از سیو همان لحظه را نگه دارید تا مورد واقعی قابل تکرار باشد.
