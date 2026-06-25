# Automation Delete Status

Last updated: 2026-06-04 (Asia/Hong_Kong)

## Current Status

Automation delete is using the production full-rewrite path, rapid preset-store deletes are coalesced, and the latest manual stress runs passed.

Latest verified run:
- Xcode result: `Run-Aesdetic-Control-2026.06.03_12-52-55-+0800.xcresult`.
- Build action succeeded and run action succeeded on Ryan's iPhone.
- Rapid color preset, transition, animation/effect, and automation create/delete testing completed successfully.
- Preset-store delete queue coalesced rapid delete taps into fewer full rewrites.
- Timer rows were deleted and verified; non-final timer verify errors recovered on retry.
- Final cleanup logs reported no pending deletes, no pending preset-store work, no pending timers, no dead letters, and healthy preset-store state.

Current result from manual testing:
- Online automation create/delete works.
- Repeated create/delete does not corrupt `presets.json`.
- Transition automation playlist and step presets are removed together.
- Direct preset automations remove their app-managed preset record.
- No WLED-side backup file remains on `/edit`; backups are local app files only.
- Rapid automation delete taps are serialized: one delete runs, later delete taps queue and run afterward.
- Rapid preset-store delete taps within the coalescing window are merged into one combined `.presetStore` cleanup item.
- Create/edit and preset/timer mutation actions are blocked or deferred while conflicting mutation work is active.
- Light controls remain usable during preset/timer mutation work.
- Offline delete no longer removes local automation metadata too early.
- Force-quit during pending delete is safe because delete intent and cleanup queue state are persisted and resumed.
- Color preset delete now waits for verified WLED preset-store deletion before removing the local app row.
- Transition and effect preset deletes use verified full-rewrite delete paths rather than enqueue-only cleanup.
- Preset-store decode/read failures during active mutation or settle windows are treated as busy/read-unstable first, not immediately as real degraded health.
- A final all-clear log is emitted when a device queue is clean.

## Current Delete Pipeline

1. User taps delete.
2. `AutomationStore.delete(id:)` marks the automation as deleting.
3. If another automation delete is active, the new automation ID is queued and persisted.
4. When the automation becomes active, its ID is persisted in `aesdetic.pendingAutomationDeleteIds`.
5. Timer ownership is resolved by WLED timer signature, not by trusting a stale stored slot alone.
6. Owned WLED timer rows are deleted through `/json/cfg` row rewrite and readback verification.
7. Playlist and managed step presets are deleted with one full `presets.json` rewrite.
8. Rewritten file is read back and verified.
9. Local automation metadata is removed only after device cleanup succeeds.
10. Post-delete verification is read-only.
11. The next queued automation delete starts after the active delete finalizes.

Preset and save delete path:
1. User deletes a color, effect, transition, or playlist save.
2. The app blocks or queues the preset-store mutation if another conflicting preset/timer mutation is active.
3. The delete is journaled into `DeviceCleanupManager`.
4. Rapid save deletes for the same device are coalesced for a short window.
5. `DeviceCleanupManager` processes the merged playlist/preset IDs through the verified full-rewrite delete path.
6. The local save row is removed only after the queued cleanup no longer contains the target IDs.

## What Changed From The Old Delete Path

Old path:
- Delete playlist with `pdel`.
- Delete each step preset with `pdel`.
- Retry leftover writes after finalization.
- Queue raw timer slot deletes when ownership was uncertain.

Problems observed:
- Some step preset deletes were missed.
- Repeated delete bursts caused invalid bytes/corruption in `presets.json`.
- Raw WLED timer slots could compact and point at the wrong row later.
- Device-side backup files could persist and consume WLED flash.

New path:
- No production `pdel` deletes.
- One full rewrite for playlist plus step presets.
- Timer cleanup requires ownership proof.
- Timer row delete forces cleared rows into the write payload when needed so WLED compaction does not leave stale rows behind.
- No post-finalization write retries.
- No WLED-side backup file.
- Failed cleanup keeps the automation pending and retries automatically.
- Rapid delete taps are queued instead of dropped.
- Rapid preset-store delete taps are coalesced before rewrite.
- Preset/playlist validation pauses while preset-store writes are in flight or settling.
- Final all-clear logs make it obvious when cleanup is done and healthy.

## Pass Signals In Logs

Expected success logs:
- `automation.delete.requested`
- `automation.delete.queued` when a delete is tapped while another delete is active
- `automation.delete.queue_start`
- `automation.delete.pipeline.begin`
- `automation.delete.timer.no_owned_slots` or timer direct cleanup logs
- `timer.rows_delete.write_plan`
- `timer.rows_delete.success`
- `automation.delete.pipeline.preset_store_delete`
- `preset_store.full_rewrite_delete.success`
- `automation.delete.pipeline.full_rewrite_success`
- `automation.delete.pipeline.verify_postdelete_clean`
- `cleanup.preset_store_delete.enqueued`
- `cleanup.preset_store_delete.coalesced` when rapid save/preset deletes are merged
- `cleanup.device.final_state ... pendingDeletes=0 pendingPresetStore=0 pendingTimers=0 ... health=healthy`
- `Deleted automation:`
- `Saved 0 automations` after the final automation in a delete burst

Expected retry/offline logs:
- `automation.delete.device_unreachable`
- `automation.delete.retry_scheduled`
- `automation.delete.resume_persisted`
- `automation.delete.pipeline.defer_offline_timer`
- `timer.rows_delete.verify_remaining_mismatch` on a non-final retry attempt can be transient if followed by `timer.rows_delete.success`
- `timer.rows_delete.verify_error` on a non-final retry attempt can be transient if followed by `timer.rows_delete.success`
- `Skipping synced automation validation (preset store settling)` is expected during preset-store mutation/settle windows
- `preset_store.health.degraded_readable_deferred` is expected when a single transient read/decode issue happens during mutation/settle and has not crossed the health threshold

Failure logs that need investigation:
- `preset_store.full_rewrite_delete.verify_failed`
- `preset_store.full_rewrite_delete.preflight_failed`
- `automation.delete.pipeline.full_rewrite_required`
- `automation.delete.timer.remaining_owned_rows_retry_required`
- `cleanup.queue_hard_stop_unreadable`
- `cleanup.preset_store_delete.wait_timeout`
- `timer.rows_delete.verify_failed`
- `timer.rows_delete.ambiguous`

Latest run observations:
- `cleanup.preset_store_delete.enqueued`: 7
- `cleanup.preset_store_delete.coalesced`: 6
- `preset_store.full_rewrite_delete.success`: 14
- `timer.rows_delete.success`: 7
- `timer.rows_delete.verify_error`: 2 first-attempt/non-final events, both recovered on retry.
- `automation.delete.pipeline.summary`: 7
- `automation.delete.pipeline.verify_postdelete_clean`: 5
- `cleanup.device.final_state`: emitted repeatedly with pending counts at `0`, dead letters at `0`, and `health=healthy`.
- No `preset_store.full_rewrite_delete.verify_failed`, `preset_store.full_rewrite_delete.error`, `timer.rows_delete.verify_failed`, `cleanup.preset_store_delete.wait_timeout`, `cleanup.queue_hard_stop_unreadable`, or `preset_store.health.recovery_required`.

## WLED Firmware Notes

Relevant WLED behavior:
- `presets.json` stores presets and playlists in one file.
- WLED `pdel` mutates that file.
- Repeated mutations during large delete bursts are fragile on constrained flash/filesystems.
- WLED timer rows are not stable app-owned IDs; empty rows can be omitted/compacted in config serialization.
- WLED cannot notify the app instantly when unplugged; the app infers offline from connection failures and health checks.

Relevant WLED errors previously seen:
- `ERR_FS_QUOTA` / `11`: filesystem full or quota-related issue.
- `ERR_FS_PLOAD` / `12`: attempted to load a missing preset. This can appear transiently after deletes.

## Remaining Watch Items

These are not blockers, but should be watched in future testing:
- Very full WLED filesystems can still fail writes.
- If `presets.json` is already unreadable before our operation, full rewrite must abort rather than guess.
- Large automations should be tested near WLED preset-slot limits.
- App-side foreground timers are not the reliable sold-product path; WLED-side synced timers are.
- A non-final timer verification mismatch/decode error is acceptable only when followed by a successful retry.
- If the app is killed mid-upload, the in-flight HTTP request cannot be guaranteed to complete, but the persisted delete intent/cleanup queue resumes on next launch and verifies before local finalization.
- Debug memory diagnostics are noisy in launch logs and should be cleaned up or gated before release.

## Commit Readiness Notes

The automation delete and preset-store cleanup behavior is ready based on the latest manual run, live device verification, focused simulator tests, and commit `4d2f7b3`.

Already pushed:
- `4d2f7b3 Coalesce preset-store delete cleanup`

Verification used:
- Focused tests for rapid preset-store delete coalescing and readable-degrade health thresholding.
- Simulator build passed.
- Real-device stress test passed with clean final-state logs.
