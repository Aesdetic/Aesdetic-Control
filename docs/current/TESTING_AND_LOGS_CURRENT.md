# Testing And Logs

Last updated: 2026-08-01 (Asia/Hong_Kong)

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

### Consolidated Routine Refresh

1. Install the build and launch with at least two synced WLED routines. The first launch after introducing verification receipts may show `Checking` once; allow both rows to reach `Ready` so their verified receipts are created.
2. Close and relaunch the app. Confirm both rows immediately show `Ready · Checking`, then silently settle to `Ready` from one refresh generation. They must not briefly show `Verification needed`, expose Retry, or play the Ready celebration.
3. Background and foreground the app while reconnect/device-list signals also fire. Existing Ready rows should remain `Ready · Checking` until current evidence arrives.
4. Confirm one `automation.refresh.started`, any number of `automation.refresh.coalesced`, one `automation.refresh.snapshot`, and one `automation.refresh.completed` per device generation.
5. Confirm the refresh emits no POST, cleanup, restore, or timer-resync logs.
6. Create another routine on the same device. Only the new routine should show `Preparing` and play the one-shot Ready celebration. Existing verified routines may show `Ready · Checking`, but must not change to `Preparing` or celebrate again.
7. Simulate or capture HTTP 503 and confirm read-only retries at 2, 5, and 15 seconds. A previously verified routine should end at `Ready · Check needed`; a never-verified routine should end at `Verification needed`.
8. Tap Retry and confirm another read-only refresh, not `automation.retry.explicit_resync`.
9. For a confirmed-drift test, deliberately remove or alter the owned timer/target outside the app, then refresh. Only a complete readable mismatch may change the row to `Not ready`; repairing that routine may celebrate once when it returns to verified Ready.

### Interactive Brightness

1. With the lamp already on, drag brightness continuously for at least five seconds.
2. Confirm visible response starts within 250 ms and previews are not sent more frequently than about 140 ms.
3. Release on a distinctive value and confirm the device and UI settle on the exact value.
4. Confirm Core Data/propagation occurs once at release and `presets.json` is unchanged.
5. Repeat while a transition is running and confirm the run is cancelled once at drag start.
6. Repeat from lamp-off and at zero; confirm preview is withheld and the existing atomic gradient/power restoration runs on release.

### Release Memory Check

1. Profile a Release build on the physical device with SwiftUI Instruments, Time Profiler, and Allocations.
2. Complete ten background/foreground cycles, then leave the app idle for two minutes.
3. Confirm resident memory does not grow monotonically, returns to within 20% of the post-warm-up level, and no automation-refresh or brightness-preview tasks remain retained.

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

### WLED Advanced LED And Hardware

1. Open `Settings > Advanced > LED & Hardware`.
2. Change `Global brightness factor`, save, verify the WLED LED setup page reflects the value, then restore the original value.
3. Toggle `Enable automatic brightness limiter` on, save, leave/re-enter, verify it stays on, and compare with WLED.
4. Toggle `Enable automatic brightness limiter` off, save, leave/re-enter, verify it stays off, and compare with WLED.
5. If safe for the device, change LED output `Length`, save, confirm the app shows `Restart Required`, verify WLED shows the new value, restart from the app, and re-enter to confirm persistence.
6. For length reductions, send black/off first or power-cycle LED power before judging whether upper pixels are still actively controlled; addressable LEDs can keep their last color after WLED stops sending data.
7. Add a color order override, save, verify in WLED, delete it, save, restart if requested, and confirm it does not duplicate or reappear.
8. Use `< Settings` to return from LED & Hardware to Advanced categories; confirm the transition swipes horizontally and does not fade.
9. Type quickly in numeric fields and confirm field editing remains responsive while the top-right action becomes `Save` after the buffered commit.

### WLED Advanced WiFi And Network

1. Open `Settings > Advanced > WiFi & Network`.
2. Change only the mDNS address/name, save, confirm the app reports a reconnect-required state, then re-enter and compare the WLED WiFi page.
3. Toggle `Disable WiFi sleep`, save, leave/re-enter, and confirm the toggle persists with the WLED page showing the matching value.
4. Change TX power only if safe for the device, save, leave/re-enter, and compare with WLED.
5. Confirm station WiFi passwords and AP password never display real stored values; they should remain configured/write-only unless intentionally replaced.
6. Avoid changing real SSID/password, static IP, gateway, subnet, DNS, or Ethernet fields on a primary device until reconnect/recovery UI is hardened.
7. If the device changes IP or temporarily disappears, wait for rediscovery before judging the save as failed.

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

## WLED Advanced Settings Focused Tests

Use these after changing the Advanced settings service, LED output editor, color override editor, or WLED manifest mappings:

```bash
xcodebuild test \
  -derivedDataPath /tmp/AesdeticControlAdvancedSettingsTests \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -only-testing:Aesdetic-ControlTests/WLEDAdvancedSettingsServiceTests
```

High-signal cases:

- `brightnessLimiterUsesWLEDLEDSettingsFormAndDoesNotSnapBack`
- `ledOutputDraftSavesNativeBusConfiguration`
- `ledOutputSaveRetriesUntilWLEDReflectsDelayedReinit`
- `ledOutputSaveClearsColorOverridesWithWLEDSettingsFormFallback`
- `ledOutputDraftMutatesDynamicRowsByStableIDAfterRemoval`
- `ledOutputSaveDeduplicatesExactColorOverrides`
