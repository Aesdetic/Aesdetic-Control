# Automation Delete Status

Last updated: 2026-06-02 (Asia/Hong_Kong)

## Current Status

Automation delete is using the production full-rewrite path and the latest manual stress run passed.

Latest verified run:
- Xcode result: `Run-Aesdetic-Control-2026.06.02_13-04-59-+0800.xcresult`.
- Build action succeeded and run action succeeded on Ryan's iPhone.
- Created 3 color presets: IDs `10`, `11`, and `12`; each uploaded through full `presets.json` rewrite and verified.
- Created 5 automations; all saved locally, synced to WLED, and reported `On-device schedule updated+verified`.
- WLED timer rows increased to `cfgInsCount=5`, then returned to `cfgInsCount=0` after delete.
- Automation delete pipeline summaries succeeded for all 5 automations.
- Full preset-store delete rewrites succeeded for all automation assets and all 3 color presets.
- Final live WLED check after the run: `/json/cfg` timers were `[]`, and `presets.json` numeric keys were `[0]`.

Current result from manual testing:
- Online automation create/delete works.
- Repeated create/delete does not corrupt `presets.json`.
- Transition automation playlist and step presets are removed together.
- Direct preset automations remove their app-managed preset record.
- No WLED-side backup file remains on `/edit`; backups are local app files only.
- Rapid automation delete taps are serialized: one delete runs, later delete taps queue and run afterward.
- Create/edit and preset/timer mutation actions are blocked or deferred while conflicting mutation work is active.
- Light controls remain usable during preset/timer mutation work.
- Offline delete no longer removes local automation metadata too early.
- Force-quit during pending delete is safe because delete intent is persisted and resumed.
- Color preset delete now waits for verified WLED preset-store deletion before removing the local app row.
- Transition and effect preset deletes use verified full-rewrite delete paths rather than enqueue-only cleanup.

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
- Preset/playlist validation pauses while preset-store writes are in flight or settling.

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

Failure logs that need investigation:
- `preset_store.full_rewrite_delete.verify_failed`
- `preset_store.full_rewrite_delete.preflight_failed`
- `automation.delete.pipeline.full_rewrite_required`
- `automation.delete.timer.remaining_owned_rows_retry_required`
- `cleanup.queue_hard_stop_unreadable`
- `timer.rows_delete.verify_failed`
- `timer.rows_delete.ambiguous`

Latest run observations:
- `full_rewrite_create.success`: 8
- `full_rewrite_delete.success`: 8
- `timer.rows_delete.success`: 5
- `automation.delete.pipeline.summary`: 5
- `automation.delete.pipeline.full_rewrite_success`: 5
- `automation.delete.pipeline.verify_postdelete_clean`: 5
- `timer.rows_delete.verify_remaining_mismatch`: 1, recovered on retry.
- `timer.rows_delete.verify_error`: 1, recovered on retry.
- No `preset_store.mutation.error`, no `degraded`, no `corrupt`, and no leftover WLED automation assets.

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
- Debug memory diagnostics are noisy in launch logs and should be cleaned up or gated before release.

## Commit Readiness Notes

The automation delete behavior is ready based on the latest manual run and live device verification.

Before commit/push:
- Commit from a feature branch, not directly from `main`.
- Keep the commit scope clear because the current working tree includes automation delete hardening, preset delete behavior, UI/editor changes, model changes, and tests.
- Convert newly-added plain `print(...)` diagnostics to structured logger calls or keep them debug-gated.
- Run a final build after cleanup. If focused simulator tests hang, record that as a test-environment issue rather than a delete-path failure.
