# The Cave 3.2.26 - stage 1 cave maintenance test

Based only on the user-tested 3.2.25 package. This stage covers Uranium,
Iron, Copper, Coal, Fortified Vaults and existing Lost Villages.
Train Interiors, Shelter Defense and general performance changes are deferred.

Baseline 3.2.25 ZIP SHA-256:
`9b76217e4f076d47c1e160bd8c8e2792f9751d854ba261ac1bb7ba7c949d4b42`.

## Changed behavior

- Uranium Caves no longer create their four fixed fluid transfer endpoints.
  Their repeating Lua fluid shuttle is removed. An update removes the recorded
  legacy endpoints once, including any fluid in those endpoints. Ordinary
  player pipes and tanks are not removed. Bring sulfuric acid into the cave,
  for example as barrels, and unpack it there. Mining requirements are retained.
- Native linked belts and copper power connections are verified during setup.
  Successful setup is remembered in the saved cave record. Later successful
  entries and normal ticks do not repeat the connection repair or layout scan.
  Incomplete setup may retry on entry. Configuration changes verify existing
  infrastructure once. Existing Uranium item-belt layout identifiers are kept
  because removing fluid ports does not require moving or rebuilding belts.
- The cave modules apply fixed lighting when creating/updating their surfaces.
  Repeating cave lighting writes in their tick handlers and the global lighting
  pass are removed. Extraction caves/Fortified remain pitch black; Lost Village
  keeps its previous global twilight profile. Flashlight handling is retained.
- All six cave information panels have both Always Show in Alt Mode and Show
  Tag in Chart enabled. Existing panels are updated too.
- Lost Village looks up an entity once and reuses its valid reference. It checks
  surface/prototype validity and clears stale references on removal/update.
  Mission, trade and reward checks still read current inventories and state.

Expedition deadlines, closure/evacuation, resources, ore richness, loot,
rewards and enemy/Bob balance retain their existing rules. Remote View and
Vulcanus collapse fixes remain. New Lost Village generation remains disabled
by the existing release policy; existing villages receive these changes.
Fixed connections no longer have a periodic scripted repair loop.

## Factorio API compatibility

The implementation uses the Factorio 2.0.77 API, also exercised in the native
2.0.77 engine:

- Native linked-belt connections carry items without a Lua transfer loop:
  https://lua-api.factorio.com/2.0.77/classes/LuaEntity.html#connect_linked_belts
- Copper verification checks both player and script wire origins. Omitting
  the origin checks player wires by default, so it previously failed to
  recognize this mod's scripted connection:
  https://lua-api.factorio.com/2.0.77/classes/LuaWireConnector.html#is_connected_to
- Saved setup markers and entity caches use permitted LuaObject references
  in storage. They are not initialized or modified during on_load:
  https://lua-api.factorio.com/2.0.77/auxiliary/storage.html
- Cached entities are checked for validity before reading their properties:
  https://lua-api.factorio.com/2.0.77/classes/LuaEntity.html#valid
- The map-panel options are native read/write display-panel attributes:
  https://lua-api.factorio.com/2.0.77/classes/LuaEntity.html#display_panel_show_in_chart

## Exact files changed relative to 3.2.25

- `scripts/uranium_caves.lua`: remove fluid endpoints/shuttle, one-time setup,
  fixed lighting, chart flag and legacy endpoint cleanup.
- `scripts/mineral_caves.lua`: one-time Iron/Copper/Coal setup, lighting and
  chart flags.
- `scripts/fortified_vaults.lua`: one-time power setup, lighting and chart flag,
  including existing panels.
- `scripts/lost_city.lua`: one-time power/belt setup, fixed twilight, valid
  entity cache and chart flag.
- `control.lua`: skip repeated global lighting writes for these cave surfaces.
  Other surface lighting branches and the global tick schedule are retained.
- `prototypes/uranium_caves.lua`: explanatory comment only. Hidden legacy fluid
  prototypes remain so old saves load safely before endpoint cleanup; no
  runtime creation or fluid shuttle remains.
- `info.json`: version 3.2.26 only; dependencies and other metadata retained.
- `changelog.txt`: release notes.
- `TESTING-3.2.26.md`: this guide. Earlier guides remain in the package.

All other files are byte-identical to 3.2.25, including Train Interiors,
Shelter, solar display, Bob balance, resources and collapse modules.
No private diagnostic commands or native fixtures are included in this ZIP.

## Completed checks

- All 352 Lua files pass syntax loading with the available Lua 5.4 library.
- Native Factorio 2.0.77 fixtures pass in Base and in Space Age + Quality +
  Elevated Rails, for both fresh 3.2.26 caves and 3.2.25 caves saved then
  upgraded. Each of the four runs contains all six cave types: 24 cave
  instances total. Instrumentation is confined to disposable mod copies.
- Both native item directions transfer plates, with Normal quality in Base
  and Rare quality with Quality enabled. Native copper wires remain connected
  and electricity reaches the child lamps. The fixed panel/pole/belt/lamp
  unit numbers are preserved during the tested update and save/load.
- All four old Uranium endpoints disappear on upgrade; fresh caves contain
  zero endpoints. Both native panel flags are true after creation/update.
- Synthetic running expedition start/deadline values survive the version
  update and save/load. Forced expiry still closes each cave. Successful
  subsequent child-entry setup calls do not rerun the measured searches or
  lighting setup. Fresh-build reloads retain their saved LuaSurface markers.
- Native Lost Village cache tests cover repeated lookup, allowed-name lists,
  live inventory changes, wrong prototype/surface, destroyed entities and
  cleanup after the native surface-deletion event.
- Release ZIP root/version, CRC, source bytes, baseline integrity and unchanged
  dependencies are verified before delivery. The ZIP itself also passes native
  map creation in Base and Space Age without private instrumentation.

Focused native-call comparison over 120 dispatched ticks, after setup:

| Measured helper | 3.2.25 | 3.2.26 |
| --- | ---: | ---: |
| Uranium whole-surface entity lookups, one cave | 123 | 0 |
| Mineral whole-surface entity lookups, three caves | 57 | 0 |
| Fortified whole-surface entity lookups, one cave | 6 | 0 |
| Lost Village whole-surface entity lookups, one fixture | 13 | 0 |
| Extraction/Fortified lighting setup calls, five caves | 600 | 0 |
| Cave lighting profiles written by two global passes, six caves | 12 | 0 |

These are focused call counts, not measured milliseconds or a server UPS
benchmark. Timers and dynamic gameplay still run. The original supplied save
was not modified or replayed with its full Bob/server mod pack.

## First user test

1. Install 3.2.26 and load a copy of your 3.2.25 save with the same server mods
   and settings. Check a previously opened Uranium Cave before opening a new
   one: its four fixed fluid ports should be gone, while item belts and poles
   remain usable. Bring acid inside through your item/supply logistics.
2. Open Uranium, Iron, Copper, Coal and Fortified caves. Test entry/return,
   both item directions where present, exterior-to-interior electricity and
   the existing countdown. Also test an existing Lost Village if your save
   has one; this release does not re-enable new Village generation.
3. Check the information-panel icon on the chart/Remote View map in the
   discovered area. Both panel options should be enabled. Remote View must
   retain the previous protection against physical cave teleporting.
4. Leave the cave, save/reload and re-enter. Connections and remaining time
   should persist. Check closure on a disposable test copy using the existing
   cave exhaustion/deadline test facilities where appropriate.
5. Compare UPS and the F4 show-time-usage display before opening a cave and
   while that cave remains open, with similar player activity. Record whether
   opening Uranium still starts the sustained lag. Repeat with the normal
   multiplayer/server pack; gameplay, chart appearance and full-pack
   performance still need this test.

For a failure, record cave type, whether it was old or newly opened,
Factorio/mod versions, full error text and the before/after time-usage values.
Proceed to stage 2 only after this cave test succeeds.
