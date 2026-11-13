# The Cave 3.2.44: server playtest

Based on the supplied and tested 3.2.42 branch. This is a playtest package.

## Included changes

- Death inside any of the six cave types returns the player to their force spawn on the parent surface.
- Darkness begins at cave entry. After 30 seconds without powered-lamp coverage, the four-second threat check can create the first wave between 30 and 34 seconds.
- Fortified darkness attackers can enter the blue hall. Ordinary room defenders keep their barriers and room objectives.
- Iron, Copper, Coal, Uranium and existing Lost Village caves have two upper and two lower Industrial Store Boxes. Right is Input; left is Output. There are two clear tiles between each box footprint and its portal footprint.
- Upper Input sends to lower Input. Lower Output sends to upper Output. Inserters and loaders are not supplied or placed. Players build their own attachments.
- In Core (Cave Collapse and Advancing Collapse both disabled), Iron/Copper/Coal/Uranium timers are 60 minutes from the first successful entry. Re-entry does not restart them. Still-open legacy 30-minute Core operations extend from their original first entry; closed caves stay closed.
- Core uranium without Bob's Ores uses broad, rich beds split equally between uranium and scrap. Existing revealed resources are retained; new opened tiles use the new layout. Bob's enabled thorium support is retained.

Lost Village remains disabled for new generation by its existing master switch; existing caves remain supported. Fortified receives no new transfer boxes. Existing power poles, lamps and panels remain.

## Headless checks already completed

Factorio 2.0.77 native tests covered entry, actual darkness attacks/damage, death/respawn in six caves, Core durations and deadline boundaries, re-entry, item directions, full/invalid destinations, quality and stack metadata, force/cave isolation, player-built inserter/loader connections, powered lamps, resource coverage and mined-bed refill prevention.

Compatibility profiles covered Base, Space Age, Bob's Ores, Collapse, Advancing Collapse and disabled Darkness. Real local-server saves covered old belt conversion and repeat save/load without lost/duplicated items or restarted timers. No graphical client or simultaneous live-player session was tested.

## In-game checklist

1. Enter each cave; remain unlit for at least 34 seconds, and verify that the darkness enemies can reach you. Repeat with a powered lamp.
2. Die inside each cave and confirm the respawn surface and force spawn.
3. Confirm the five transfer-equipped caves spawn only their four transfer boxes, with Input on the right and Output on the left.
4. Put supplies in upper Input and mined items in lower Output. Attach your own inserters/loaders and test a full destination.
5. In Core, confirm a new mining cave shows 60:00 and that re-entry does not reset it. Check newly opened uranium tiles with Bob's Ores disabled.
6. On the server, test simultaneous players, force separation, existing cave conversion, reconnect and save/load. Report any error with the save and Factorio log.

## Changed runtime files relative to 3.2.42

- control.lua
- data-final-fixes.lua
- prototypes/darkness_enemies.lua
- scripts/cave_respawn.lua
- scripts/darkness_infestation.lua
- scripts/fortified_spiral.lua
- scripts/cave_item_boxes.lua
- scripts/cave_operation_time.lua
- scripts/mineral_caves.lua
- scripts/uranium_caves.lua
- scripts/lost_city.lua

Release metadata: info.json, changelog.txt and this playtest note. Test drivers and test saves are excluded from the release archive.
