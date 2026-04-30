# Automation System Overview

Last updated: 2026-04-30 (Asia/Hong_Kong)

## Production Status

Automation create and delete are currently production-ready for WLED-device-backed automations based on the latest manual tests and code review.

What is working now:
- Automation creation writes WLED preset-store records through one serialized full `presets.json` rewrite.
- Automation delete clears the owned WLED timer first, then deletes playlist and step preset records through one full `presets.json` rewrite.
- Deletes do not use WLED `pdel` mutation anymore.
- Delete intent persists across app force-quit and resumes automatically on next launch.
- Offline or unreachable devices keep the automation in a deleting/retry state instead of locally removing metadata too early.
- A single automation delete is allowed at a time so multiple delete bursts cannot overload WLED storage.
- Automation creation is blocked while automation delete is in progress.
- Preset tab color/effect/playlist deletes use the full rewrite path, not direct `pdel`.
- Device-side backup files are not left on WLED; backups are local app files only.

Important remaining product limitation:
- WLED timers run on WLED without the app open after sync is complete.
- App-side foreground timers still depend on the app process. The reliable production path for sold hardware is the WLED-device-side timer flow.

## Core Architecture

Main components:
- `AutomationStore`: owns automation persistence, create/update/delete, scheduling, WLED sync, timer ownership checks, and retry state.
- `DeviceCleanupManager`: owns deferred device cleanup queue, delete leases, retry backoff, and combined preset-store cleanup items.
- `WLEDAPIService`: owns serialized WLED API/file operations and full `presets.json` rewrite helpers.
- `DeviceControlViewModel`: creates transition playlist payloads, deletes user preset records, and refreshes device preset/playlist state.
- `AddAutomationDialog`: creates or edits automations and only dismisses after `AutomationStore.add` confirms save.

Persistence:
- App automations: `automations.json` in app documents.
- Pending device cleanup queue: `UserDefaults` key `aesdetic_device_cleanup_queue_v1`.
- Pending automation deletes: `UserDefaults` key `aesdetic.pendingAutomationDeleteIds`.
- Local preset-store backups: app support directory `PresetStoreBackups/<device-id>-presets.json`.

## Automation Creation Flow

User creates automation:
1. `AddAutomationDialog` validates the form and selected target devices.
2. `AutomationStore.add(_:)` rejects the save if an automation delete is currently active.
3. For device-side automations, `AutomationStore` checks local WLED timer capacity.
4. The automation is saved locally first so the user has durable app metadata.
5. `syncOnDeviceScheduleIfNeeded` builds the WLED-side assets.
6. For transition automations, `DeviceControlViewModel.createTransitionPlaylist(... persist: true)` builds the playlist and step preset payloads.
7. `WLEDAPIService.rewritePresetStoreUpsertingRecords` reads current `presets.json`, merges the new playlist/presets, validates the rewritten JSON, uploads the complete file, then reads it back for verification.
8. Timer config is written after preset-store assets exist.
9. Metadata is updated with WLED playlist/preset IDs, timer slot, signatures, and sync state.

Why this is the safe create path:
- WLED sees one complete `presets.json` rewrite instead of many small preset saves.
- The rewrite preserves unrelated user presets/playlists.
- Verification confirms the new IDs exist and preserved IDs were not dropped.
- Local backup exists before upload, but no WLED flash backup file is created.

## Automation Delete Flow

User deletes automation:
1. `AutomationStore.delete(id:)` blocks if another automation delete is in progress.
2. The automation ID is inserted into `deletingAutomationIds` and persisted to `aesdetic.pendingAutomationDeleteIds`.
3. UI shows delete progress and other create/delete actions are disabled.
4. `cleanupDeviceEntries(for:)` runs per target device.
5. If the device is offline and an owned timer may exist, local finalization is blocked and retry remains active.
6. If the device is online, `disableOwnedTimerSlotsForDeletion` scans WLED timers and disables only slots matching the automation signature.
7. After timer cleanup is verified, playlist ID and managed step preset IDs are deleted through `rewritePresetStoreDeletingRecords` in one full rewrite.
8. The rewritten `presets.json` is verified by readback.
9. Only after device cleanup is complete does the automation get removed locally.
10. A read-only post-delete verification checks for leftovers; it logs leftovers but does not issue repeated write retries.

Why timer cleanup is first:
- A WLED timer can point at a playlist/preset ID.
- Deleting preset-store entries while a timer still points at them can leave WLED in a bad or confusing state.
- Timer rows in WLED config compact/shift when empty rows are omitted, so stored timer slot numbers are not treated as stable IDs.

Why delete does not finalize early:
- If preset-store rewrite fails, the automation remains in deleting state and retries later.
- If timer ownership cannot be proven, delete retries later instead of disabling a raw slot.
- Offline timer-owning deletes are not finalized locally because local metadata is the ownership proof needed for future cleanup.

## Deferred Cleanup Queue

`DeviceCleanupManager` handles cleanup that cannot complete immediately.

Queue item types:
- `.timer`: only for non-automation or already safe timer cleanup. Automation-owned raw timer queue entries are rejected.
- `.preset`: full-rewrite preset cleanup.
- `.playlist`: full-rewrite playlist cleanup.
- `.presetStore`: combined playlist plus preset full-rewrite cleanup.

Queue behavior:
- Per-device delete leases serialize queue processing and immediate deletes.
- Preset-store entries are processed one per queue pass.
- Retry uses capped backoff.
- Preset-store unreadable hard stops move entries to dead-letter instead of repeatedly writing into a corrupted/unreadable store.
- Legacy automation timer queue entries are dropped on load because raw WLED timer slots require live ownership proof.
- Combined `.presetStore` entries participate in active-ID checks and queue pruning so newly-created IDs are not later deleted by stale queued work.

## Preset Store Rewrite Design

Full rewrite delete:
1. Fetch raw `presets.json`.
2. Strict-parse the file into ID records.
3. Remove target playlist/preset IDs in memory.
4. Preflight that targets are gone and preserved IDs still exist.
5. Save local backup.
6. Upload complete `presets.json`.
7. Sleep briefly for WLED filesystem settle.
8. Fetch `presets.json` again.
9. Verify target IDs are gone and preserved IDs remain.
10. Cache verified records and report success.

Full rewrite create:
1. Fetch raw `presets.json`.
2. Strict-parse current records.
3. Merge app-generated playlist/preset records in memory.
4. Preflight upserts and preserved IDs.
5. Save local backup.
6. Upload complete `presets.json`.
7. Read back and verify.
8. Cache verified records and report success.

Backup policy:
- Local app backup is overwritten per device on each full rewrite.
- No `presets-aesdetic-backup.json` is kept on WLED.
- This avoids consuming WLED flash space with backup files.

## Paths That Did Not Work

Rejected path: repeated `pdel` deletes.
- Behavior observed: missed deletes, leftover automation step presets, invalid bytes/corruption in `presets.json` under delete bursts.
- Firmware reason: WLED preset mutations rewrite the same preset store file; repeated mutations under load increase the chance of partial/fragile file state.
- Current status: removed from production delete paths and removed from `WLEDAPIService` API surface.

Rejected path: post-delete write retries.
- Behavior observed: retry writes after finalization could amplify WLED filesystem load.
- Current status: post-delete verification is read-only. If cleanup fails before finalization, the automation remains pending and retries the main safe full-rewrite path.

Rejected path: raw queued automation timer slot deletes.
- Behavior observed: WLED timer rows can compact, so a stored slot can later refer to another automation's timer.
- Current status: automation timer cleanup must prove ownership by signature before disabling a slot.

Rejected path: finalizing locally after preset-store rewrite failure.
- Risk: app could remove metadata while WLED playlist/preset records remain on device.
- Current status: local finalization is blocked until cleanup is verified or proven unnecessary.

Rejected path: device-side WLED backup file.
- Behavior observed: `presets-aesdetic-backup.json` persists on `/edit` if cleanup fails and consumes flash.
- Current status: backup is local-only.

## Concurrency Rules

Automation delete:
- One automation delete at a time globally.
- Other automation delete buttons are disabled while one delete is active.
- Creation is blocked while delete is active.
- Preset/effect/color saves are blocked while automation delete is active.

Preset-store operations:
- `WLEDAPIService` serializes preset-store operations by device key.
- `DeviceCleanupManager` also uses a per-device delete lease.
- Queue helpers track combined `.presetStore` entries so stale queued cleanup cannot silently delete newly-created IDs.

On-device sync:
- Creation is blocked only when target device IDs overlap an in-flight on-device sync.
- This avoids blocking unrelated devices indefinitely.

## Offline And Retry Behavior

If WLED is unplugged:
- The app cannot know instantly from WLED itself; offline is inferred from WebSocket disconnects, HTTP failures/timeouts, mDNS/health checks, and explicit unreachable markers.
- Automation delete now marks the device unreachable faster when cleanup HTTP operations fail.
- The automation remains visible as deleting/retrying instead of being removed locally.
- On app relaunch, persisted pending delete IDs resume automatically.

Retry behavior:
- Automation delete retry starts at 3 seconds and caps at 30 seconds.
- Queue retry uses a longer backoff schedule for deferred cleanup.
- Timer cleanup retries only through ownership scan, never raw slot queueing.

## UI Behavior

Create/edit sheet:
- Save is disabled during active automation delete.
- Save does not dismiss unless `AutomationStore.add` returns true.
- On-device sync conflicts are shown as validation/status text.

Automation rows:
- Deleting row shows progress.
- Other delete buttons are disabled during active delete.
- Offline/unreachable retry state is surfaced to the user.

Preset tab:
- Transition preset delete enqueues one combined playlist plus step preset full-rewrite cleanup.
- Color/effect preset delete enqueues full-rewrite preset cleanup.
- Direct playlist delete uses `DeviceControlViewModel.deletePlaylist`, which calls full rewrite.

## Test Checklist

Core happy path:
1. Create one transition automation and wait until it is ready.
2. Confirm it appears in WLED `presets.json` as one playlist plus step presets.
3. Confirm the WLED timer exists and points to the playlist/macro ID.
4. Close the app and let the WLED timer run.
5. Delete the automation online.
6. Confirm `presets.json` is valid JSON and the playlist/step presets are gone.
7. Confirm no `presets-aesdetic-backup.json` exists on WLED `/edit`.

Concurrency:
1. Start deleting automation A.
2. Try deleting automation B; it should be disabled or blocked.
3. Try creating automation C; save should be blocked.
4. After A finishes, B/C actions should be available again.

Offline/retry:
1. Create automation and wait until ready.
2. Unplug WLED.
3. Press delete.
4. Force close the app.
5. Reopen app.
6. Plug WLED back in.
7. Delete should resume automatically or remain clearly retrying until reachable.

Preset tab:
1. Delete a transition preset.
2. Verify playlist and step preset IDs are gone from `presets.json`.
3. Delete a normal preset.
4. Verify `presets.json` remains valid.

Stress:
1. Create/delete/create several automations back-to-back.
2. Verify no invalid bytes in `presets.json`.
3. Verify no stale automation preset IDs remain.
4. Verify WLED `/edit` has no app backup file.

## Current Code Anchors

Primary files:
- `Aesdetic-Control/Services/AutomationStore.swift`
- `Aesdetic-Control/Services/DeviceCleanupManager.swift`
- `Aesdetic-Control/Services/WLEDAPIService.swift`
- `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
- `Aesdetic-Control/Views/Components/AddAutomationDialog.swift`
- `Aesdetic-Control/Views/Scenes/PresetsListView.swift`

Important functions:
- `AutomationStore.add(_:)`
- `AutomationStore.delete(id:)`
- `AutomationStore.disableOwnedTimerSlotsForDeletion(...)`
- `AutomationStore.cleanupDeviceEntriesOnOnlineDevice(...)`
- `AutomationStore.resumePersistedAutomationDeletes()`
- `DeviceCleanupManager.enqueuePresetStoreDelete(...)`
- `DeviceCleanupManager.activeDeleteIds(...)`
- `DeviceCleanupManager.removeIds(...)`
- `WLEDAPIService.rewritePresetStoreUpsertingRecords(...)`
- `WLEDAPIService.rewritePresetStoreDeletingRecords(...)`
- `DeviceControlViewModel.createTransitionPlaylist(... persist: true)`
