# Automation Delete Status

Last updated: 2026-04-30 (Asia/Hong_Kong)

## Current Status

Automation delete is using the production full-rewrite path.

Current result from manual testing:
- Online delete works.
- Repeated create/delete does not corrupt `presets.json`.
- Transition playlist and step presets are removed together.
- No WLED-side backup file remains on `/edit`.
- Delete while another delete is active is blocked/disabled.
- Create while delete is active is blocked.
- Offline delete no longer removes local automation metadata too early.
- Force-quit during pending delete is safe because delete intent is persisted and resumed.

## Current Delete Pipeline

1. User taps delete.
2. `AutomationStore.delete(id:)` checks global delete lock.
3. Automation ID is persisted in `aesdetic.pendingAutomationDeleteIds`.
4. Timer ownership is resolved by WLED timer signature.
5. Owned WLED timer slots are disabled directly.
6. Playlist and managed step presets are deleted with one full `presets.json` rewrite.
7. Rewritten file is read back and verified.
8. Local automation metadata is removed only after device cleanup succeeds.
9. Post-delete verification is read-only.

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
- No post-finalization write retries.
- No WLED-side backup file.
- Failed cleanup keeps the automation pending and retries automatically.

## Pass Signals In Logs

Expected success logs:
- `automation.delete.requested`
- `automation.delete.pipeline.begin`
- `automation.delete.timer.no_owned_slots` or timer direct cleanup logs
- `automation.delete.pipeline.preset_store_delete`
- `preset_store.full_rewrite_delete.success`
- `automation.delete.pipeline.full_rewrite_success`
- `automation.delete.pipeline.verify_postdelete_clean`
- `Deleted automation:`

Expected retry/offline logs:
- `automation.delete.device_unreachable`
- `automation.delete.retry_scheduled`
- `automation.delete.resume_persisted`
- `automation.delete.pipeline.defer_offline_timer`

Failure logs that need investigation:
- `preset_store.full_rewrite_delete.verify_failed`
- `preset_store.full_rewrite_delete.preflight_failed`
- `automation.delete.pipeline.full_rewrite_required`
- `automation.delete.timer.remaining_owned_slots_retry_required`
- `cleanup.queue_hard_stop_unreadable`

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
