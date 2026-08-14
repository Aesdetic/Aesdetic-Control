# Automation Timer Correctness

Last updated: 2026-08-10 (Asia/Hong_Kong)

This file is the current source of truth for Aesdetic automation timers that run on WLED while the app is closed.

## Production Rule

The reliable production path is WLED-device-side timers. After an automation is saved and synced, WLED owns execution through `/json/cfg` timer rows. App-side foreground timers are fallback behavior and should not be treated as the sold-product reliability path.

## WLED Timer Mapping

WLED stores timers in `timers.ins` under `/json/cfg`. Aesdetic decodes WLED's compact timer vector into logical slots so empty rows do not shift app meaning.

Current logical mapping:
- Specific time automations use regular WLED timer slots `0...7`.
- Sunrise automations use logical slot `8` and WLED hour marker `255`.
- Sunset automations use logical slot `9` and WLED hour marker `254`.
- Older firmware/config shapes where a second `hour=255` row represents sunset are decoded as sunset for compatibility.
- Macro-zero solar placeholder rows do not occupy app timer slots.

Solar offsets:
- WLED firmware stores timer minute as signed `int8_t`.
- Aesdetic clamps sunrise/sunset offsets to `-59...59` minutes for compatibility across supported WLED timer implementations.
- WLED v16 accepts a wider `-120...120` range, which can be enabled later after the app confirms the connected firmware capability.
- WLED applies solar timers as `sunrise + offset * 60` or `sunset + offset * 60`.

Weekdays:
- App UI stores weekdays Sunday-first.
- WLED `dow` is Monday-first, with Sunday at bit 6.
- Empty weekday selections are normalized to all days for WLED safety.
- Specific-time conversion uses one shared clock converter for both timer programming and read-only readiness evaluation, including prior/next-day weekday shifts across timezone boundaries.

## Clock And Solar Readiness

All WLED timer triggers depend on the lamp's local clock. This includes specific-time, sunrise, and sunset automations.

Before an on-device automation is considered ready:
- WLED timer capacity is checked.
- Sunrise/sunset automations require a WLED solar reference with valid latitude/longitude.
- Specific-time, sunrise, and sunset automations validate WLED clock/timezone readiness.
- If clock/timezone is missing or suspicious, the app writes phone-derived WLED time settings and posts current epoch time to `/json/state`.

Correct WLED timezone shape:
- For a known WLED timezone table index, write `if.ntp.tz=<index>` and `if.ntp.offset=0`.
- For unsupported zones, write `if.ntp.tz=0` plus `if.ntp.offset=<secondsFromGMT>`.

Rejected readiness shape:
- `if.ntp.tz=9` plus `if.ntp.offset=28800` is not ready. WLED applies both the timezone table and offset, which can shift local time.

## Write And Verify Flow

Automation creation:
1. Save local automation metadata.
2. Create any required preset or playlist records first.
3. Validate solar location and clock/timezone.
4. Resolve the WLED timer config.
5. Select a legal timer slot.
6. Write the timer through `/json/cfg`.
7. Read back and verify.
8. Mark sync ready only after verification.

Automation delete:
1. Prove timer ownership by signature.
2. Clear the owned timer row first.
3. Verify timer cleanup by readback.
4. Delete managed preset-store records after timer cleanup.
5. Remove local automation only after device cleanup is complete or proven unnecessary.

Timer rows can compact in WLED config, so stored slot numbers are metadata hints, not permanent ownership proof.

## User-Facing Behavior

Expected app behavior:
- A ready automation should run from WLED with the app closed.
- If WLED clock/timezone cannot be verified, the app should show a user-focused clock sync message rather than marking the schedule ready.
- If sunrise/sunset location is unavailable, the app should ask for location access or tell the user to sync Time & Schedules.
- Native WLED timer rows imported into the app are read-through rows and do not self-resync after the user deletes them from WLED.

## Useful Logs

Healthy create/sync logs:
- `automation.clock.auto_configured`
- `automation.sync.ready`
- `On-device schedule updated+verified`
- `timer.verify.match`
- `automation.timer.programmed` with `intendedLocal`, `intendedTimeZone`, `decodedWLEDHour`, `decodedWLEDMinute`, and `decodedWLEDDow`

Healthy delete logs:
- `timer.rows_delete.success`
- `automation.delete.pipeline.summary`
- `preset_store.full_rewrite_delete.success`

Investigate these:
- `automation.sync.not_ready ... reason=wled_clock_not_ready`
- `automation.clock.verify_failed`
- `timer.verify.mismatch` if it is final and not followed by success
- `timer.delete.verify_failed`

## Regression Coverage

Current focused coverage:
- Exact `00:00` remains `00:00` when app and WLED timezones match.
- Midnight and late-night timezone conversion shift the WLED weekday mask to the prior/next day when required.
- WLED timezone writes use table index with `offset=0` for supported zones.
- Clock-only WLED time sync preserves existing solar latitude/longitude in the app cache.
- WLED time settings parser treats `tz=9, offset=0` as ready.
- WLED time settings parser rejects `tz=9, offset=28800` as not ready.
- Solar timer decode maps `hour=255` to sunrise and `hour=254` to sunset.
- Swapped WLED solar row ordering does not drop either solar slot.
- Timer encode preserves positional slots through the highest used timer.

Useful command:

```sh
xcodebuild test -project Aesdetic-Control.xcodeproj -scheme Aesdetic-Control -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:Aesdetic-ControlTests/WLEDAPIServiceTests/testUpdateDeviceTimeSettingsWritesWLEDTimezoneIndex -only-testing:Aesdetic-ControlTests/WLEDAPIServiceTests/testUpdateDeviceTimeSettingsPreservesSolarReferenceCacheWhenCoordinateIsNil -only-testing:Aesdetic-ControlTests/WLEDAPIServiceTests/testFetchDeviceTimeSettingsReportsClockReadiness -only-testing:Aesdetic-ControlTests/WLEDAPIServiceTests/testFetchDeviceTimeSettingsRejectsTimezoneIndexWithExtraOffset -only-testing:Aesdetic-ControlTests/WLEDAPIServiceTests/testDecodeRemapsSolarSlots -only-testing:Aesdetic-ControlTests/WLEDAPIServiceTests/testDecodeHandlesSwappedSolarOrdering -only-testing:Aesdetic-ControlTests/WLEDAPIServiceTests/testEncodePreservesPositionalSlotsThroughHighestUsed
```
