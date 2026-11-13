# The Cave 3.1.94 — Queen prototype load hotfix

This is a narrow correction to the 3.1.93 test build from the same 3.1.92 / user-supplied stable branch. It retains all agreed Advancing Collapse behavior.

## Reported failure and correction

The user reported a native prototype-load error for `the-cave-train-wave-advancing-queen`: key `type` was missing in `attack_parameters.ammo_type.action`.

Version 3.1.93 used `action = {}`. Factorio interpreted this as a Trigger definition with no required type. The earlier Lua fixture checked that this table had no effects but did not validate it as a Factorio Trigger, so that fixture missed the loading error.

The correction omits the optional `AmmoType.action` property entirely. The Queen has no attack action or damage delivery. Her passive movement commands, AI, 50,000 health, 30-second nest timer, the 1,000-unit/24-nest limits and the one-minute wave interval are unchanged. No save migration is needed for this data-stage-only correction.

Official API reference: [AmmoType.action](https://lua-api.factorio.com/latest/types/AmmoType.html#action), documented as optional.

## Files changed from 3.1.93

- `prototypes/advancing_assault.lua`: omit the invalid empty action and explain why.
- `info.json`: version 3.1.94.
- `changelog.txt`: hotfix entry.
- `TESTING-3.1.94.md`: this report (new).

All other mod files are identical to the delivered 3.1.93 ZIP. Test fixtures remain outside the playable mod ZIP.

## Verification and remaining checks

- Added a focused Trigger contract regression check that rejects the original empty action and accepts omission of the optional field. This check is not the full native Factorio prototype loader.
- Executed the actual private-prototype module and the existing Queen behavior harness using Lua 5.4 with mocked Factorio objects, checking passive commands, health, nesting, caps, death, milestones, saved state and command access.
- Compiled all mod Lua files, reviewed the exact hotfix diff, checked version/root naming, compared every file with the delivered 3.1.93 ZIP and checked final ZIP integrity.

Factorio is not installed in this environment. Native loading and in-game behavior still require client/server verification:

1. Replace 3.1.93 with 3.1.94, keep The Cave enabled and restart. Confirm the mod loads without the reported prototype error.
2. Load the active Advancing Collapse save and run the existing admin command:

```text
/the-cave-advancing-queen-test
```

3. Follow the printed GPS location. Confirm 50,000 health, no attacks when approached or shot, and up to three nests immediately and every 30 seconds while slots remain below the shared 24-nest cap.

The command still requires the two-hour countdown to have finished. The detailed intended behavior remains documented in `TESTING-3.1.93.md`; that earlier report did not establish native engine compatibility, as this reported error demonstrates.
