# The Cave 3.2.27 - stage 2 interior maintenance test

Based only on the user-tested 3.2.26 package. Stage 1 cave modules are
byte-identical. This stage covers Train Interiors, Shelter Defense and one
duplicate global lighting pass. Their existing Startup defaults and mutual
exclusion are retained.

Baseline ZIP SHA-256:
`3ca6739e57e3ad749b91440714ff2ed4fc17a3672ec6b29f8d039cee85a5cd51`.

## Changes

- Clean legacy hidden Train radars once per interior surface, including on
  configuration migration. Map charting and the live outside camera continue.
- Remember successful fixed Train/Shelter Garden setup. Normal transfers reuse
  saved native entity/connector references. Cheap validity, location, owner,
  layout, render and wire checks detect stale or changed infrastructure. A
  changed room, missing fixture or removed wire still triggers repair. Failed
  setup is not marked successful. Pending legacy Garden contents still drain.
- Correct Train Garden copper verification: recognize both player and script
  wire origins, matching the existing script-created cross-surface connection.
- Reuse nearby exterior poles for a stationary battery bridge. Moving trains,
  changed bridge entities/force/surface and built or cloned poles refresh the
  local square. Existing connections are still checked/pruned on each power
  sync. A bounded local scan every 300 ticks catches poles silently created or
  moved by another mod without a build event. This is five seconds at 60 UPS;
  normal raised build events are handled on the next existing power sync.
- Skip slot/content enumeration for empty inventories using native is_empty().
  Nonempty inventory transfers retain their stack/quality and remainder rules.
- Skip power-interface teleport when its position is already correct. Exterior
  interfaces still follow a moving train. Valid Main Locomotive fixtures also
  skip repeated setup property writes.
- Remove the second global lighting call every 60 ticks. Retain the existing
  once-per-second enforcement, init/update/surface-created application and lamp
  maintenance. Solar-display synchronization remains live for day/night and
  moving Space Age platforms.

Live cargo/fluid transfer, Garden transfers, battery charge/discharge,
pollution, cameras, shield repair, train rebuilding and defense waves retain
their existing scheduling/rules. Enemy/Bob balance, rewards, cave closures,
resources, Stage 1 chart flags, Remote View guards and Vulcanus fix are retained.
Advancing Collapse gameplay/AI is outside this patch.

## Exact files changed relative to 3.2.26

- `scripts/train_interiors.lua`: radar/setup guards, script-wire verification,
  empty inventories, stationary power fixture/connection upkeep and migration.
- `scripts/shelter_core.lua`: fixed Garden readiness, empty inventories,
  stationary exterior pole cache and interface position guard, migration.
- `scripts/interior_maintenance.lua` (new): saved fixture snapshots and bounded
  nearby-pole cache shared by the two interior systems.
- `control.lua`: pole build/clone and surface deletion notifications, cache
  reset at init/configuration, removal of duplicate lighting call.
- `info.json`: version only, 3.2.27. Dependencies/other metadata retained.
- `changelog.txt`: release notes.
- `TESTING-3.2.27.md` (new): this guide.

No prototype, setting, locale, cave, enemy, collapse, resource, wave or
solar-display source files are changed. Private native fixtures, counters,
debug generators and commands are excluded from the ZIP.

## Official API checks

API use is checked against official documentation and executed with the
Factorio 2.0.77 engine. The current online documentation is newer; the native
2.0.77 checks establish compatibility with the user's engine version.

- `is_connected_to` defaults to player origin; script connections need an
  explicit script-origin check. Cross-surface connect_to uses reach_check=false:
  https://lua-api.factorio.com/latest/classes/LuaWireConnector.html
- Native `LuaInventory.is_empty()` tests whether an inventory contains items:
  https://lua-api.factorio.com/latest/classes/LuaInventory.html#is_empty
- Saved LuaObject references are permitted in storage. No cache writes occur
  in on_load, and cached entities/connectors are checked for validity:
  https://lua-api.factorio.com/latest/auxiliary/storage.html
- create_entity does not raise a build event by default, explaining the limited
  fallback for other mods' silent pole creation:
  https://lua-api.factorio.com/latest/classes/LuaSurface.html#create_entity

## Native checks

Disposable fixtures use separate Base and Space Age + Quality + Elevated Rails
runs, independently for Train and Shelter modes. Each combination checks fresh
3.2.27 state and a 3.2.26 save upgraded to 3.2.27: eight runs, two independent
test forces per run. The tests cover:

- Garden item transfer in both directions, Normal/Rare quality, and native
  Train Garden fluid transfer in both directions.
- Native cross-surface copper, generator-to-battery charging and output energy
  settlement. Fixed Garden/upper-substation unit numbers survive the tested
  version upgrade and same-version save/load.
- Destroyed transfer chest recovery, missing wire recovery, new-pole events,
  foreign-force exclusion, empty/blocked/full inventory transfer and tail slots.
- Actual train motion on rails, output following the anchor, removal of old
  out-of-range connections and reconnection in the new square. The stationary
  Shelter bridge is also exercised after a native scripted anchor move.
- Garden research refresh where its technologies exist (Space Age). Base mode
  retains its existing Garden stage zero and does not gain new technologies.
- Additional four mode/edition runs cover actual clone events, destroyed cached
  poles, and a silent pole created after all raised events: it stays undiscovered
  initially and is connected by the 300-tick fallback. Native uncoupling and
  recoupling refresh the Train Garden link; the private debug generator is
  reattached for a separate charge check after room reassembly. Live Cargo
  Wagon/Shelter import and export after empty snapshots preserve Normal/Rare
  quality and do not immediately re-import exported goods.

All 353 Lua files pass syntax loading. The final uninstrumented ZIP is checked
for root/version, CRC, exact source bytes and native Base/Space Age map creation.

Focused measured calls over 120 native ticks, with two test forces:

| Measured call | 3.2.26 | 3.2.27 |
| --- | ---: | ---: |
| Train Garden fixed fixture helpers | 144 | 0 |
| Train exterior pole queries, stationary | 48 | 0 |
| Shelter Garden fixed storebox helper calls, including default player Shelter | 96 | 0 |
| Shelter exterior pole queries, two researched batteries | 16 | 0 |
| Global lighting passes | 4 | 2 |
| Train radar queries, 20 repeated cleanup calls after setup | 20 | 0 |

These windows follow setup/migration; local fallback scans still occur outside
the windows. These are call counts, not milliseconds or a server UPS benchmark.
The full user/server Bob mod pack and supplied multiplayer save were not
replayed. Client camera/map appearance and full-server UPS need the user test.

## تست پیشنهادی شما

1. نسخهٔ 3.2.27 را جایگزین 3.2.26 کنید و یک کپی از سیو تأییدشده را با همان
   مدها و تنظیمات باز کنید. برای تست قطار، Train Interiors باید فعال باشد.
2. داخل قطار و Garden رفت‌وبرگشت کنید؛ آیتم و مایع را در هر دو جهت منتقل
   کنید و باتری را هنگام شارژ و مصرف بررسی کنید.
3. قطار را حرکت دهید، متوقف کنید و واگن را جدا و دوباره وصل کنید. تیر برق
   تازه کنار قطار بسازید و اتصال برق بیرون و داخل را بررسی کنید.
4. با چند بازیکن وارد قطار شوید، مپ/Remote View و دوربین بیرون را ببینید.
   سپس ذخیره و بارگذاری مجدد کنید و انتقال‌ها و باتری را دوباره چک کنید.
5. UPS و F4 show-time-usage را با فعالیت مشابه با 3.2.26 مقایسه کنید.
   برای تست Shelter، سیو جداگانهٔ حالت Shelter را استفاده کنید؛ این دو
   حالت طبق تنظیمات فعلی هم‌زمان فعال نمی‌شوند.

برای گزارش مشکل: متن کامل خطا، نسخهٔ فکتوریو، وضعیت قطار (متحرک/متوقف)،
قدیمی یا تازه بودن سیو، تعداد بازیکنان و تصویر time-usage را نگه دارید.
