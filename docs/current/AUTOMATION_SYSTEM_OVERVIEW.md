# Automation System Overview

Last updated: 2026-07-31 (Asia/Hong_Kong)

## Production Status

The long-term persistence architecture is implemented in code. The focused simulator matrix passed on 2026-07-31 (100 selected tests, zero failures), and the app target builds successfully. Release remains gated on the physical WLED v16 interruption matrix below; simulator success alone is not a production sign-off.

What is working now:
- Automation creation writes WLED preset-store records through one serialized full `presets.json` rewrite.
- Presets, segmented presets, playlists, routine records, transitions, renames, profiles, Alexa mirrors, and cleanup deletes all use the same per-device transaction coordinator.
- Each transaction journals its verified original and candidate locally before one upload, then requires two matching strict read-backs and a complete-file SHA-256 match before commit.
- Upload timeout or connection loss is an unknown outcome. It triggers read-only classification after the device settles, never an immediate rollback write.
- Confirmed corruption restores a verified snapshot, replays the interrupted edit once, and performs one final restore if the replay fails.
- Recovery resumes after relaunch or reconnect and stops in `Needs repair` after three confirmed-invalid restore attempts or when no verified backup exists.
- Generated automation transition step presets use compact WLED JSON API state records: only power, brightness, segment bounds, color/CCT, solid effect, and palette are stored.
- Automation delete clears the owned WLED timer first, then deletes playlist and step preset records through one full `presets.json` rewrite.
- Deletes do not use WLED `pdel` mutation anymore.
- Active native WLED timers are imported and shown when they point at an existing preset or playlist.
- Imported/native WLED timer rows are read-through rows; they do not self-resync back onto WLED if the timer is deleted.
- Orphan or duplicate native WLED timers are reported during import but never auto-cleared. Import and readiness are read-only.
- Delete intent persists across app force-quit and resumes automatically on next launch.
- Offline or unreachable devices keep the automation in a deleting/retry state instead of locally removing metadata too early.
- A single automation delete is allowed at a time so multiple delete bursts cannot overload WLED storage.
- Automation creation is blocked while automation delete is in progress.
- Preset tab color/effect/playlist deletes use the full rewrite path, not direct `pdel`.
- Rapid preset-store delete taps are coalesced before the full rewrite so color/effect/transition/preset deletes do not overload `presets.json`.
- Preset-store read/decode failures during active mutation or short settle windows are treated as busy/read-unstable before becoming user-facing degraded health.
- Final cleanup logs report clean per-device queue state when pending preset/timer work has settled.
- Device-side backup files are not left on WLED; backups are local app files only.

Important remaining product limitation:
- WLED timers run on WLED without the app open after sync is complete.
- App-side foreground timers still depend on the app process. The reliable production path for sold hardware is the WLED-device-side timer flow.

Timer correctness details, including sunrise/sunset slots, clock readiness, and verification commands, live in [Automation Timer Correctness](AUTOMATION_TIMER_CORRECTNESS.md).

## Core Architecture

Main components:
- `AutomationStore`: owns automation persistence, create/update/delete, scheduling, WLED sync, timer ownership checks, and retry state.
- `DeviceCleanupManager`: owns deferred device cleanup queue, delete leases, retry backoff, and combined preset-store cleanup items.
- `WLEDAPIService`: owns the per-device preset-store transaction coordinator, durable journal, verified snapshots, recovery, and serialized WLED API/file operations.
- `DeviceControlViewModel`: creates transition playlist payloads, deletes user preset records, and refreshes device preset/playlist state.
- `AddAutomationDialog`: creates or edits automations and only dismisses after `AutomationStore.add` confirms save.

Persistence:
- App automations: `automations.json` in app documents.
- Pending device cleanup queue and pending automation-delete IDs: versioned `CleanupJournal/cleanup-journal-v2.json` in Application Support, with an atomically written previous-generation backup. The former `UserDefaults` keys are one-time migration sources only.
- Pending preset-store transaction: app support directory `PresetStoreTransactions/<device-id>/journal.json`, plus its atomically written original and candidate files.
- Verified recovery snapshots: app support directory `PresetStoreBackups/<device-id>/`, retaining the newest three strictly parsed, device-read-back-verified files.

## Automation Creation Flow

User creates automation:
1. `AddAutomationDialog` validates the form and selected target devices.
2. `AutomationStore.add(_:)` rejects the save if an automation delete is currently active.
3. For device-side automations, `AutomationStore` checks local WLED timer capacity.
4. The automation is saved locally first so the user has durable app metadata.
5. `syncOnDeviceScheduleIfNeeded` builds the WLED-side assets.
6. For transition automations, `DeviceControlViewModel.createTransitionPlaylist(... persist: true)` builds the playlist and step preset payloads.
7. Transition step presets are serialized as compact partial WLED JSON API state records, then `WLEDAPIService.rewritePresetStoreUpsertingRecords` strictly reads current `presets.json`, preserves unrelated records and unknown fields, journals the original and candidate, uploads once, and verifies the complete candidate by two stable reads and content hash.
8. Timer config is written after preset-store assets exist.
9. Metadata is updated with WLED playlist/preset IDs, timer slot, signatures, and sync state.

Why this is the safe create path:
- WLED sees one complete `presets.json` rewrite instead of many small preset saves.
- Compact step records avoid writing optional segment defaults such as speed, intensity, grouping, selected state, segment name, freeze state, and custom effect flags that are not needed for generated transition frames.
- The rewrite preserves unrelated user presets/playlists.
- Verification confirms the new IDs exist and preserved IDs were not dropped.
- A verified original and candidate journal exist before upload, but no WLED flash backup file is created.
- The uploaded candidate does not become last-known-good until the device returns the complete matching file.

## Native WLED Timer Import

The app imports active WLED timer rows so users can see device-side schedules that may have been created outside Aesdetic.

Import behavior:
- `AutomationStore.refreshDeviceAutomationState(for:reason:)` owns one complete per-device refresh: snapshot retrieval, import reconciliation, readiness evaluation, and one readiness publication.
- Launch, foreground, reconnect, committed-mutation, manual-retry, and periodic triggers coalesce onto the same in-flight refresh instead of repeating downstream import work.
- The refresh consumes one immutable generation-aware snapshot: one `/json/cfg` read and one strict `/presets.json` read.
- Timers are actionable when `macroId > 0`, the logical slot is `0...9`, and the row is not suppressed by an in-flight automation delete.
- The timer macro target is resolved against playlists first, then presets.
- If either strict snapshot read is unavailable, import stops without changing WLED or inventing a partial generation.
- If the macro target is missing, or a duplicate authored row is detected, the condition is logged for explicit repair; import performs no device write.
- Import does not invoke orphan cleanup. Ownership-checked orphan maintenance is scheduled separately through the cleanup coordinator.
- Imported timer rows use `templateId` values under `wled.timer.*` and are marked `runOnDevice`.

Ownership behavior:
- App-authored automations can resync/recreate their WLED timer and managed preset-store assets when validation detects drift.
- Imported/native timer rows are read-through and are excluded from `validateSyncedOnDeviceSchedulesIfNeeded`, so stale imported rows cannot recreate a timer after the user deletes it.
- When a WLED timer disappears, matching imported rows are removed locally. Cleanup recognizes both canonical device IDs and older `ip:<address>` import IDs.

## Automation Delete Flow

User deletes automation:
1. `AutomationStore.delete(id:)` blocks if another automation delete is in progress.
2. The automation ID is inserted into `deletingAutomationIds` and atomically persisted in the cleanup journal.
3. UI shows delete progress and other create/delete actions are disabled.
4. `cleanupDeviceEntries(for:)` runs per target device.
5. If the device is offline and an owned timer may exist, local finalization is blocked and retry remains active.
6. If the device is online, `deleteOwnedTimerRowsForDeletion` scans WLED timers and deletes only rows matching the automation signature.
7. After timer cleanup is verified, playlist ID and managed step preset IDs are deleted through `rewritePresetStoreConditionallyDeleting` in one full rewrite.
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
- New preset-store delete requests default to a short coalescing window before processing.
- Rapid `.presetStore` requests for the same device merge playlist and preset IDs and keep the coalescing window open for the latest rapid tap.
- Every deferred preset, playlist, preset-store, and verified timer cleanup schedules a per-device wake-up for the earliest eligible item.
- Persisted cleanup entries restore their per-device wake-up after app relaunch.
- Queue passes schedule the next remaining item or retry before returning, while offline devices continue to rely on the existing reconnect recovery path.
- Preset-store entries are processed one per queue pass.
- Save delete flows can wait for their journaled preset-store IDs to leave the active queue before removing local UI rows.
- Retry uses capped backoff.
- Preset-store unreadable hard stops move entries to dead-letter instead of repeatedly writing into a corrupted/unreadable store.
- Every queued preset/playlist target carries prior ownership evidence. The coordinator deletes it only when the current record still matches that evidence; an absent target completes safely, a changed target is preserved as superseded, and an ID-only legacy target moves to `needsReview`.
- Newly written automation and generated-step records include a short owner-scoped marker derived from the local routine or saved-transition UUID. Delayed cleanup must match that token (or an exact captured record hash/signature), so another routine reusing the same WLED ID is preserved.
- Older generic `[AD automation]` records do not gain ownership merely from their type marker. Unproven legacy cleanup is preserved for explicit review instead of guessing.
- Legacy automation timer queue entries are dropped on load because raw WLED timer slots require live ownership proof.
- Combined `.presetStore` entries participate in active-ID checks and queue pruning so newly-created IDs are not later deleted by stale queued work.
- When no active queue work remains, `cleanup.device.final_state` logs pending delete, preset-store, timer, dead-letter, and health state.

## Preset Store Transaction Design

Every persistent preset-store mutation follows the same flow:
1. Enter the per-device coordinator. Only one save, edit, rename, delete, cleanup, verification, or recovery transaction runs at a time.
2. Strictly fetch and parse the complete current `presets.json`.
3. Merge the requested change in memory while preserving unrelated records and unknown WLED fields.
4. Validate the candidate and its affected/preserved IDs locally.
5. Atomically persist the transaction journal, verified original, and candidate in Application Support.
6. Upload the candidate once through the dedicated 60-second request / 180-second resource session.
7. Wait for WLED filesystem settling.
8. Strictly read the complete file twice. Both observations must be identical before classification.
9. Commit only when the returned file hash exactly matches the candidate hash.
10. Retain the returned candidate as last-known-good, clear the journal, refresh read-only routine readiness, and publish `idle`.

Unknown upload outcome:
- Timeout, connection loss, HTTP failure, or a failed verification read does not prove corruption.
- The transaction remains durable and publishes `Verification needed`.
- No immediate rollback or second upload is issued.
- After a stable read, a matching candidate commits, a matching original retries the requested edit once, and a different valid file is preserved while the edit is rebased once.
- Transport failures remain pending and resume after reconnect or relaunch.

Confirmed corruption and recovery:
- Corruption is confirmed only when the same malformed complete file is returned twice.
- An active transaction restores its verified original. Corruption discovered before a new mutation restores the newest verified last-known-good snapshot.
- After a verified restore, the exact interrupted candidate is replayed once.
- If replay also corrupts the file, the verified original is restored once more, the outcome is `recoveredWithoutCommit`, and the edit is reported unsaved.
- Confirmed-invalid restore attempts stop at three. The coordinator then publishes `Needs repair` and performs no more automatic writes.
- If no verified snapshot exists, writes pause and the app enters `Needs repair`; it never fabricates a replacement file.

Snapshot policy:
- The newest three strictly parsed, device-read-back-verified snapshots are retained per device.
- The candidate is never promoted on upload acknowledgement alone.
- Transaction files and snapshots are atomically written in Application Support, not `UserDefaults`.
- No backup file is kept on WLED, avoiding extra flash use.

Read-only validation rule:
- Preset/playlist and routine readiness checks may update health/readiness state but must never directly trigger another write.
- All synced routines for one device are evaluated from one immutable timer-plus-preset generation and published as one batch. Readiness never mixes timer rows from one generation with target records from another.
- A successful batch stores one atomic app-local verification receipt per routine/device pair. The receipt records the exact saved routine revision, timer signature and slot, timer-plus-store generation, exact target-record hash, and verification time. It is last-known evidence only; it does not replace the next live read.
- Receipts are promoted only after the device returns the complete matching timer and target evidence. A routine edit, explicit repair, confirmed mismatch, or deletion invalidates its receipt. Unrelated preset-store edits do not erase another routine's receipt.
- A timer edit or slot clear reads `/json/cfg` once for both its merge base and decoded rows, writes once, then reports `committed`, `notCommitted`, or `verificationNeeded` after read-only verification.
- Validation runs after a committed mutation, on foregrounding, and after reconnect.
- Cached `isOnline` state never blocks an explicit foreground, reconnect, or manual read attempt.
- HTTP 503 receives read-only retries after 2, 5, and 15 seconds. Exhaustion leaves `Verification needed` and waits for the next lifecycle/manual trigger; it performs zero repair or resync writes.
- Device unreachability produces `Verification needed`; it is not classified as corruption.
- A temporary read failure changes verification freshness, not the last confirmed operational state. It never rewrites the timer or preset store and never claims confirmed drift.
- Transport/generation uncertainty is tracked separately from confirmed preset-store content health; a timeout alone never labels the file corrupt.

Request and UI performance budget:
- One readiness/import pass costs two device reads per device (`/json/cfg` plus `/presets.json`), independent of the number of routines on that device.
- Timer and preset matching is local linear work over the captured snapshot. Readiness and reconciled slot metadata are published once per device batch instead of once per row.
- Concurrent lifecycle requests for the same device share the complete in-flight refresh, including import and readiness publication. A mutation that overlaps the read settles and receives one fresh read rather than publishing mixed generations.
- Preset-store idle waits and per-device routine-sync locks are continuation-driven. They wake when the owning operation releases the device instead of polling the main actor on a fixed interval.
- The existing `ObservableObject` boundary remains in place. A broad Swift Observation migration is profile-gated and should only proceed if an ETTrace or Instruments run identifies observation invalidation as a measured bottleneck.

## Paths That Did Not Work

Rejected path: repeated `pdel` deletes.
- Behavior observed: missed deletes, leftover automation step presets, invalid bytes/corruption in `presets.json` under delete bursts.
- Firmware reason: WLED preset mutations rewrite the same preset store file; repeated mutations under load increase the chance of partial/fragile file state.
- Current status: removed from production delete paths and removed from `WLEDAPIService` API surface.

Rejected path: native `psave` persistence.
- Risk: it mutates the same WLED preset store outside the app's journal, merge, hash verification, and recovery boundary.
- Current status: all preset, playlist, segmented preset, rename, profile, Alexa mirror, routine, and transition persistence uses coordinated full-file transactions. `bootps` is updated only after commit and verified separately.

Rejected path: immediate rollback after timeout or failed verification.
- Risk: an upload timeout does not reveal whether WLED stored the candidate. A blind rollback can overwrite a valid candidate or another valid external change and adds a second destructive upload while the device may still be unstable.
- Current status: timeout and connection loss are `outcomeUnknown`; classification is read-only until two stable observations agree.

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
- New user preset/effect/color save and delete mutations are blocked while conflicting preset/timer mutation work is active; only background orphan/cleanup work remains queued.
- Live light controls remain usable during preset/timer mutation work.

Preset-store operations:
- `WLEDAPIService` serializes preset-store operations by device key.
- User persistence controls are disabled while a transaction or queued cleanup owns that device. New user saves/renames/deletes are not queued.
- Background orphan and cleanup work remains durably queued and coalesced.
- Preset and playlist activation is temporarily blocked because it reads the mutating store.
- Direct power, brightness, color, and effect controls remain available.
- `DeviceCleanupManager` also uses a per-device delete lease.
- Queue helpers track combined `.presetStore` entries so stale queued cleanup cannot silently delete newly-created IDs.
- Rapid background preset-store cleanup deletes are merged by `DeviceCleanupManager.enqueuePresetStoreDelete(...)`.
- Background preset/playlist validation pauses during mutation and settle windows.

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
- `Preparing` means routine assets or the transaction are still being saved.
- `Checking` means a routine without durable verified evidence is undergoing a consolidated read-only device refresh. Retry is disabled until it completes.
- `Verifying` means read-only store/timer confirmation is active.
- `Ready` means the current live snapshot verifies both the timer and target record against one healthy preset-store generation.
- `Ready · Checking` means the routine has a durable last-known verified receipt and the app is refreshing its live evidence. It remains operationally Ready while freshness is checked.
- `Ready · Check needed` means the last-known verified receipt remains valid as historical evidence but the latest read could not complete. Retry performs a read-only refresh.
- `Verification needed` is reserved for a routine that has no verified receipt and whose current generation could not be checked.
- `Not ready` appears only after a complete live snapshot confirms missing or mismatched timer/target evidence, or after the routine is explicitly changed into an unsynced state.
- `Recovering` means automatic verified-snapshot restoration is active.
- `Needs repair` means recovery is exhausted or no verified backup exists.
- Foreground/reconnect validation never auto-resyncs. Retry is state-aware: a synced routine with `Verification needed` performs another read-only refresh, while confirmed drift or unsynced metadata can explicitly resync.
- Ready feedback is driven by an explicit one-shot event for a newly created routine or a confirmed-drift repair. A routine does not animate merely because a shared device refresh republishes Ready, and an unrelated routine save does not put existing verified rows into Preparing.

Brightness interaction:
- Slider drags use transient latest-value previews at no more than one dispatch every 140 ms.
- Preview uses WebSocket only after a confirmed connection and otherwise falls back to HTTP.
- Preview does not write Core Data, update canonical device state, propagate to other devices, or touch `presets.json`.
- Slider release cancels pending preview work and uses the existing authoritative brightness path once for exact final state, persistence, and propagation.
- Power-off, zero brightness, and off-to-on gradient restoration remain release-only atomic operations.

Preset tab:
- Transition preset delete enqueues one combined playlist plus step preset full-rewrite cleanup and waits for verified device cleanup before removing the local row.
- Color/effect preset delete enqueues full-rewrite preset cleanup and waits for verified device cleanup before removing the local row.
- Direct playlist delete uses `DeviceControlViewModel.deletePlaylist`, which calls full rewrite.
- If the preset store is busy, user-facing errors should explain that device saves are still finishing. Technical reasons belong in logs or advanced diagnostics.

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
5. While delete is running, confirm light controls still work.

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
5. Rapid-delete multiple color/effect/transition saves within the short coalescing window.
6. Confirm logs show `cleanup.preset_store_delete.coalesced` and local rows disappear only after device cleanup.

Stress:
1. Create/delete/create several automations back-to-back.
2. Verify no invalid bytes in `presets.json`.
3. Verify no stale automation preset IDs remain.
4. Verify WLED `/edit` has no app backup file.
5. Confirm `cleanup.device.final_state` appears with pending counts at `0` and `health=healthy`.

## Current Code Anchors

Primary files:
- `Aesdetic-Control/Services/AutomationStore.swift`
- `Aesdetic-Control/Services/CleanupJournalStore.swift`
- `Aesdetic-Control/Services/DeviceCleanupManager.swift`
- `Aesdetic-Control/Services/RoutineReadinessEvaluator.swift`
- `Aesdetic-Control/Services/RoutineVerificationReceiptStore.swift`
- `Aesdetic-Control/Services/WLEDAPIService.swift`
- `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
- `Aesdetic-Control/Views/Components/AddAutomationDialog.swift`
- `Aesdetic-Control/Views/Scenes/PresetsListView.swift`

Important functions:
- `AutomationStore.add(_:)`
- `AutomationStore.delete(id:)`
- `AutomationStore.importOnDeviceAutomations(for:)`
- `AutomationStore.refreshDeviceAutomationState(for:reason:)`
- `AutomationStore.retryRoutine(id:)`
- `AutomationStore.validateSyncedOnDeviceSchedulesIfNeeded()`
- `AutomationStore.deleteOwnedTimerRowsForDeletion(...)`
- `AutomationStore.cleanupDeviceEntriesOnOnlineDevice(...)`
- `AutomationStore.resumePersistedAutomationDeletes()`
- `DeviceControlViewModel.segmentedPresetState(...)`
- `DeviceCleanupManager.enqueuePresetStoreDelete(...)`
- `DeviceCleanupManager.waitForPresetStoreDeleteCompletion(...)`
- `DeviceCleanupManager.activeDeleteIds(...)`
- `DeviceCleanupManager.removeIds(...)`
- `WLEDAPIService.rewritePresetStoreUpsertingRecords(...)`
- `WLEDAPIService.capturePresetStoreCleanupTargets(...)`
- `WLEDAPIService.rewritePresetStoreConditionallyDeleting(...)`
- `WLEDAPIService.fetchDeviceAutomationSnapshot(...)`
- `DeviceControlViewModel.createTransitionPlaylist(... persist: true)`
- `DeviceControlViewModel.deleteColorPreset(...)`
- `DeviceControlViewModel.deleteTransitionPreset(...)`
- `DeviceControlViewModel.deleteEffectPreset(...)`
