# Aesdetic Control Handoff (2026-03-31)

## 1) Current Repo Snapshot

- Primary repo path: `/Users/ryan/Documents/Aesdetic-Control`
- Active branch (primary path): `codex/clean-main-push`
- Latest stable commit in active flow: `d8dcb60`
- `origin/main` commit: `d8dcb60`
- `codex/core` commit: `d8dcb60`
- `codex/clean-main-push` commit: `d8dcb60`

This means `codex/core`, `codex/clean-main-push`, and `origin/main` currently point to the same code.

## 2) Branch / Worktree Strategy (Decision)

### Adopted flow
1. Develop on `codex/core` (or `codex/clean-main-push`, but use one stable branch at a time).
2. Use `experiment/*` branches/worktrees only for risky trials.
3. Merge proven changes back into stable branch.
4. Promote stable branch -> `main` -> `origin/main` when release-ready.

### Important Git constraint
- A branch can only be checked out in one worktree at a time.
- If `codex/clean-main-push` is checked out in `/Users/ryan/Documents/Aesdetic-Control`, it cannot be checked out simultaneously in another worktree folder.

## 3) What Was Implemented (Conceptual + Code Areas)

## 3.1 Presets / Playlists / Transition Replay

### Goal
- Make saved transition replay closer to WLED behavior (fast replay path, avoid unnecessary rebuilds).

### Implemented direction
- Added/kept fast replay path for synced transition presets (start stored playlist directly when valid).
- Added pending-sync handling and rebuild fallback logic for degraded cases.
- Transition apply path has explicit replay-vs-rebuild behavior and state tracking.

### Main code areas
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
  - `applyTransitionPreset(...)`
  - `createTransitionPlaylist(...)`
  - preset/playlist save + replay + fallback routines
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/WLEDAPIService.swift`
  - playlist/preset API operations and retry/error handling

### Current expected behavior
- Saved transition preset replays immediately if playlist metadata is valid and synced.
- If stale/missing/invalid on device, fallback rebuild path is used.

## 3.2 Temporary Transition Runtime Path

### Goal
- Keep temporary transition playback reliable while avoiding destructive races.

### Implemented direction
- Segmented/native runtime paths for temporary transitions are supported.
- Temporary playlist creation path still exists in code with guarded cleanup and fallback behavior.
- Fallback to segmented/native when playlist path fails.

### Main code areas
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
  - transition path selection
  - temporary lease IDs, cleanup hints, and fallback controls
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/TemporaryTransitionCleanupService.swift`

### Current expected behavior
- Long/complex transitions can run through segmented stepper/native routes.
- Temporary playlist path may still be attempted in some flows; if it fails, fallback should continue transition execution.

## 3.3 Automation Scheduling (Strict WLED Timer Semantics)

### Goal
- Align timer-slot behavior with WLED constraints and avoid slot drift/ghost behavior.

### Implemented direction
- Strict slot policy:
  - time-of-day uses slots `0...7`
  - sunrise uses slot `8`
  - sunset uses slot `9`
- Sparse timer decode/encode handling with logical 10-slot model.
- Timer slot selection + reclaim + reservation logic instrumented.

### Main code areas
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/AutomationStore.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/WLEDAPIService.swift`
  - timer codec functions:
    - `decodeWLEDTimers(from:)`
    - `encodeWLEDTimersForConfig(_:)`
    - strict/legacy codec gate

### Current expected behavior
- App should not allow 9th time-of-day automation creation.
- Sunrise/sunset require proper WLED solar configuration.
- Imported WLED timers are mapped into app automations when catalogs/timers are reachable.

## 3.4 Automation Delete Pipeline + Managed Asset Cleanup

### Goal
- Ensure automation deletion removes owned timer + managed assets without deleting user-owned preset/playlist content.

### Implemented direction
- Deletion pipeline determines ownership before clearing timer slots.
- Queue + immediate delete strategy via `DeviceCleanupManager`.
- Post-check and requeue behavior for unresolved/deferred delete cases.
- Managed step-preset cleanup path for transition-generated automation assets.

### Main code areas
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/AutomationStore.swift`
  - `cleanupDeviceEntries(for:)`
  - ownership checks and post-delete verification
  - `shouldDeleteManagedPlaylistAsset(...)`
  - `shouldDeleteManagedPresetAsset(...)`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/DeviceCleanupManager.swift`

### Current expected behavior
- Deleting an automation queues/removes timer slot if slot is owned and not claimed by another automation.
- Managed assets should be deleted for generated automation actions.
- User-selected preset/playlist actions should not delete user-owned source assets.

## 3.5 Automation UI Locking During Sync/Delete

### Goal
- Prevent user interaction while automation row is in fragile states (creating/syncing/deleting).

### Implemented
- Row blur + overlay + hit-test lock during:
  - device sync-in-progress
  - deletion in progress
- Overlay messaging:
  - `Getting ready...`
  - `Deleting on device...`
  - `Keep app open` during delete

### Main code areas
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AutomationRow.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/AutomationView.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/DeviceDetailView.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/AutomationStore.swift`

### Commit reference
- `d8dcb60` (card locking + deletion state wiring)

## 3.6 Device Time Sync + First Discovery Time Alignment

### Goal
- Reduce schedule errors caused by wrong device time/timezone.

### Implemented direction
- Manual one-tap sync in settings to push phone time/timezone to WLED.
- First-discovery sync path in view model to align new devices.

### Main code areas
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/ComprehensiveSettingsView.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/WLEDAPIService.swift`

## 4) What Is Working Well Right Now

1. Branches are aligned at same latest commit (`d8dcb60`).
2. Automation row interaction lock is in place during sync/delete.
3. Timer slot instrumentation and strict slot model are active.
4. Transition replay path and fallback logic are implemented.
5. App has stronger logging for automation slot selection, readiness, and delete pipeline.

## 5) Known Risk Areas / Intermittent Behaviors (Observed in testing history)

1. Intermittent WLED instability during heavy automation/cleanup traffic.
- Symptoms: request timeouts, decode failures, temporary offline behavior.
- Typical logs: `NSURLErrorDomain -1001`, websocket timeout, `Failed to decode response`.

2. Timer delete verification mismatch can occur.
- Example logs:
  - `timer.verify.mismatch ... expected=false actual=true`
  - `timer.delete.verify_failed`
- Queue retry and post-check requeue are present, but behavior is device-load sensitive.

3. Automation import visibility can be inconsistent during startup race windows.
- Usually due to canceled background fetches or catalog unavailability.
- Instrumentation added to show placeholder import decisions and retry states.

4. presets.json safety remains high-priority risk surface.
- Historical issue: aggressive concurrent cleanup/write cycles correlated with degraded reads/corruption reports.
- Current mitigation: more guarded cleanup sequencing and ownership-aware deletion.

## 6) High-Signal Debug Logs (Use These During Testing)

### Scheduling / timer selection
- `timer.slots.reported device=<id> cfgInsCount=<n> logicalSlots=10`
- `automation.slot.selected ... reason=<existing|preferred|free|reclaimable|...>`
- `automation.slot.unavailable ...`
- `automation.slot.occupied ...`

### Sync readiness lifecycle
- `automation.sync.ready ...`
- `automation.sync.not_ready ... reason=<...>`
- `automation.sync.defer transient ...`

### Delete lifecycle
- `automation.delete.pipeline.begin ...`
- `automation.delete.pipeline.immediate ...`
- `automation.delete.timer.postcheck ...`
- `automation.delete.timer.postcheck_requeue ...`
- `automation.delete.pipeline.summary ...`

### Timer delete internals
- `timer.delete.begin ...`
- `timer.delete.verify_failed ...`

## 7) Manual Test Plan (Current Recommended)

## A. Transition + Preset replay
1. Save transition preset from color tab.
2. Replay from presets tab 3 times consecutively.
3. Verify:
- starts quickly
- no stuck chip state
- no duplicate rebuild unless forced by invalid device state

## B. Automation create/edit
1. Create 1 time-of-day gradient automation.
2. Confirm row goes `Getting ready` -> `Ready`.
3. Edit only time; verify no heavy asset regeneration unless action changed.
4. Edit transition duration (e.g., 10m -> 2m); verify safe re-sync and no orphan assets.

## C. Slot limits and semantics
1. Create up to 8 time-of-day automations.
2. Verify 9th time-of-day is blocked with clear capacity message.
3. Test sunrise/sunset separately after location/timezone configured.

## D. Automation delete
1. Delete one ready automation.
2. Verify timer slot is no longer actionable in `/json/cfg` timers.
3. Verify managed playlist/managed presets are cleaned when owned.
4. Verify user-owned source preset/playlist is retained.

## E. Resilience
1. Repeat create/delete/edit cycles under light and heavy use.
2. Watch for timeout bursts and ensure queue eventually settles.

## 8) Fast Validation Commands

```bash
# Repo/branch alignment
git -C /Users/ryan/Documents/Aesdetic-Control status --short --branch
git -C /Users/ryan/Documents/Aesdetic-Control rev-parse --short HEAD origin/main codex/core codex/clean-main-push

# Build (simulator)
cd /Users/ryan/Documents/Aesdetic-Control
xcodebuild -project Aesdetic-Control.xcodeproj -scheme Aesdetic-Control -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Grep automation/timer signals in runtime logs exported from xcresult or console dumps
rg -n "automation\.sync|automation\.slot|timer\.slots\.reported|timer\.delete|automation\.delete\.pipeline" <logfile.txt>
```

## 9) xcresult Review Inputs Used in This Project

Primary pattern in this thread:
- User runs tests on device.
- Export/attach `.xcresult` path from:
  - `/Users/ryan/Library/Developer/Xcode/DerivedData/Aesdetic-Control-hezboohypnztumfilnxtkthbsgwk/Logs/Launch/`
- Correlate runtime console + app logs + `/json/cfg`/`presets.json` snapshots.

## 10) Decisions Locked in This Thread

1. Keep strict WLED-style timer slot semantics.
2. Keep user-facing statuses as `Ready / Getting ready / Partially ready / Not ready`.
3. Keep automation row locked during sync/delete.
4. Keep branch safety model (`codex/core` stable, experiment branches for risky work).
5. Preserve and prioritize presets.json integrity over aggressive cleanup speed.

## 11) Open Follow-up Items (Next Session)

1. Tighten delete idempotency under transient decode/timeouts.
2. Confirm no duplicate timer ownership drift in long-running sessions.
3. Add additional guardrails for high-traffic cleanup windows (rate control / staged delete batches if needed).
4. Continue verifying automation-import consistency on cold launch + catalog cancellation conditions.

## 12) One-Message New-Thread Bootstrap

Use this exact prompt in a new Codex thread:

"Read `/Users/ryan/Documents/Aesdetic-Control/HANDOFF_2026-03-31_FULL.md`, assume current stable target is commit `d8dcb60`, continue from section 11 open follow-up items, and prioritize automation delete reliability + presets.json safety."

