# Testing And Logs

Last updated: 2026-06-04 (Asia/Hong_Kong)

Use this file to verify the current automation, timer, save, preset-store, sync, setup, and support behavior.

## Latest Verified Behavior

Verified in recent real-device stress testing:

- Created many saves and automations.
- Deleted automations rapidly.
- Deleted color/effect/transition saves rapidly.
- Navigated across tabs/views while deletes continued.
- Quit and reopened the app during cleanup.
- Confirmed WLED timers returned to clean state.
- Confirmed `presets.json` stayed valid and app-managed deleted IDs were removed.
- Confirmed final cleanup logs reported clean state.

Latest pushed cleanup commit:

- `4d2f7b3 Coalesce preset-store delete cleanup`

## Build And Test Commands

Focused cleanup tests:

```bash
xcodebuild test \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -derivedDataPath /tmp/aesdetic-cleanup-tests-derived \
  -only-testing:Aesdetic-ControlTests/AutomationModelTests/testCleanupQueueCoalescesRapidPresetStoreDeletes \
  -only-testing:Aesdetic-ControlTests/AutomationModelTests/testPresetStoreReadableDegradeIsThresholded
```

Simulator build:

```bash
xcodebuild build \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -derivedDataPath /tmp/aesdetic-cleanup-build-derived
```

Whitespace check for staged docs/code:

```bash
git diff --check
```

## Manual Test Plan

### Automation Create

1. Create one time-of-day automation.
2. Wait until the row reaches ready state.
3. Check WLED `/json/cfg` timer rows.
4. Check `presets.json` contains the managed action target.
5. Confirm logs include `automation.sync.ready`.

### Automation Delete

1. Delete one ready automation.
2. Confirm timer cleanup logs include `timer.rows_delete.success`.
3. Confirm preset-store cleanup logs include `preset_store.full_rewrite_delete.success`.
4. Confirm local automation row disappears only after cleanup.
5. Confirm final logs include `cleanup.device.final_state`.

### Rapid Automation Delete

1. Create several automations.
2. Tap delete rapidly on multiple rows.
3. Confirm the first delete runs and the rest queue.
4. Confirm all rows eventually delete.
5. Confirm no `timer.rows_delete.verify_failed`.

### Rapid Save Delete

1. Create several color/effect/transition saves.
2. Delete several saves quickly.
3. Confirm logs show `cleanup.preset_store_delete.coalesced`.
4. Confirm local rows disappear only after device cleanup.
5. Confirm `presets.json` is valid and deleted IDs are gone.

### Navigation During Delete

1. Start an automation or save delete.
2. Move between Light, Saves, Automations, Sync, Dashboard, and device detail.
3. Confirm cleanup continues.
4. Confirm light controls remain usable.
5. Confirm mutation controls are blocked or queued where appropriate.

### Force-Quit During Delete

1. Start a delete while the device is online.
2. Force-quit the app.
3. Reopen the app.
4. Confirm pending delete resumes or verifies clean state.
5. Confirm local metadata is not removed before device cleanup is safe.

### Dashboard Scenes And Shortcuts

1. Create or apply a scene/scene group from Dashboard or device detail.
2. Apply a preset shortcut.
3. Apply an automation shortcut.
4. Confirm the target device state changes.
5. Confirm no cleanup/mutation lock is bypassed while deletes are active.

### Device Sync

1. Select a source device and one or more target devices.
2. Use Copy Now and confirm target state matches supported source state.
3. Change color/effect/transition state and confirm propagation to reachable targets.
4. Toggle WLED UDP send/receive and confirm settings persist after refresh.
5. Repeat with one target offline and confirm failures are scoped to that target.

### Product Setup

1. Start product setup for a supported product profile.
2. Apply LED recommendations and naming/WiFi steps.
3. Save Alexa setup on firmware that supports WLED Alexa.
4. Create the first wake automation with sunrise.
5. Repeat with specific time when location permission is unavailable.

### Smart Home And Integrations

1. Load Integrations settings for a device.
2. Confirm Alexa settings load or show unsupported firmware messaging.
3. Add Alexa favorites from color, transition, and effect saves.
4. Save Alexa setup and confirm favorites sync or conflict messaging is understandable.
5. Review Home Assistant guidance and advanced protocol controls without requiring those protocols for normal setup.

### Wellness

1. Create a Wellness entry with sleep/wake times and sunrise-lamp usage.
2. Confirm history and summary stats update.
3. Grant HealthKit sleep permission on a test device with sleep samples.
4. Import latest wake time.
5. Confirm the entry remains editable/locked according to the current Wellness UI state.

## Expected Success Logs

Automation:

- `automation.delete.requested`
- `automation.delete.queued`
- `automation.delete.queue_start`
- `automation.delete.pipeline.begin`
- `automation.delete.pipeline.preset_store_delete`
- `automation.delete.pipeline.full_rewrite_success`
- `automation.delete.pipeline.verify_postdelete_clean`
- `automation.delete.pipeline.summary`

Timer cleanup:

- `timer.rows_delete.write_plan`
- `timer.rows_delete.success`

Preset-store cleanup:

- `preset_store.full_rewrite_create.success`
- `preset_store.full_rewrite_delete.success`
- `cleanup.preset_store_delete.enqueued`
- `cleanup.preset_store_delete.coalesced`
- `cleanup.device.final_state ... pendingDeletes=0 pendingPresetStore=0 pendingTimers=0 ... health=healthy`

Expected transient logs:

- `timer.rows_delete.verify_error` on a non-final attempt is acceptable only if followed by `timer.rows_delete.success`.
- `timer.rows_delete.verify_remaining_mismatch` on a non-final attempt is acceptable only if followed by `timer.rows_delete.success`.
- `preset_store.health.degraded_readable_deferred` is acceptable during mutation/settle if it does not become recovery-required.
- `Skipping synced automation validation (preset store settling)` is expected during mutation/settle windows.

## Failure Logs To Investigate

- `preset_store.full_rewrite_delete.verify_failed`
- `preset_store.full_rewrite_delete.preflight_failed`
- `preset_store.full_rewrite_create.verify_failed`
- `automation.delete.pipeline.full_rewrite_required`
- `automation.delete.timer.remaining_owned_rows_retry_required`
- `cleanup.queue_hard_stop_unreadable`
- `cleanup.preset_store_delete.wait_timeout`
- `timer.rows_delete.verify_failed`
- `timer.rows_delete.ambiguous`
- `preset_store.health.recovery_required`

## How To Review An Xcode Result

User-provided `.xcresult` launch logs usually live under:

```text
/Users/ryan/Library/Developer/Xcode/DerivedData/Aesdetic-Control-hezboohypnztumfilnxtkthbsgwk/Logs/Launch/
```

High-signal searches:

```bash
rg -n "automation\\.delete|timer\\.rows_delete|preset_store\\.full_rewrite|cleanup\\.preset_store_delete|cleanup\\.device\\.final_state|preset_store\\.health|sync|Alexa|Wellness|ProductSetup" <exported-log.txt>
```

Negative scan:

```bash
rg -n "verify_failed|preflight_failed|wait_timeout|queue_hard_stop|recovery_required|ambiguous" <exported-log.txt>
```
