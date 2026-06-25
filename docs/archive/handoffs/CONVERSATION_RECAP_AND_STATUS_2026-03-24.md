# Aesdetic Control: Conversation Recap and Current Status

Date: 2026-03-24  
Scope: Presets, playlists, transitions, colors-tab lifecycle, automation parity with WLED, cleanup behavior, replay reliability.

## 1) Conceptual Summary of What We Changed

### A. Transition save/replay model was split into 2 clear paths
- Temporary transition from Colors tab:
  - Runs app-side (segmented stepper / native `tt` fallback), not persisted as temp playlists in WLED.
  - Designed to avoid heavy temp `psave/pdel` churn and reduce preset-store stress.
- Saved transition (`+Preset`) path:
  - Saves persistent WLED assets (`psave` presets + playlist) and replays by starting stored playlist.
  - Reuse/replay is intended to avoid regeneration each tap.

### B. Persistent transition ID policy
- Persistent saved transition assets use permanent ID space and are intended to avoid temp reserved bands.
- Replay relies on saved playlist metadata when sync state is ready.

### C. Colors-tab lifecycle behavior tightened
- Colors tab should not cancel active playlist/transition on appear/tab switch.
- User intent actions (apply transition, brightness/color/effect change, explicit cancel) remain authoritative.

### D. Cleanup strategy was reduced/reoriented
- Aggressive temporary cleanup loops were a major regression source (deleting in-flight assets).
- We moved away from temp-playlist-heavy runtime behavior and kept cleanup focused on managed assets (especially automation-managed data).

### E. Automation moved toward strict WLED slot semantics
- Specific-time automations: timer slots `0...7`.
- Sunrise: slot `8`.
- Sunset: slot `9`.
- Timer codec/read-write paths were hardened for sparse/full `timers.ins`.

### F. Automation managed asset lifecycle
- Managed assets for automation-generated transition/gradient/effect/scene flows are tracked.
- Deleting such automation enqueues deletion of linked timer/playlist/preset assets (including managed step presets for managed transition playlists).
- User-selected preset/playlist actions are preserved (not deleted as managed assets).

### G. Replay responsiveness direction
- Preset/playlist replay paths were aligned closer to WLED behavior and optimized where possible.
- Additional parity work (WebSocket-first and direct preset optimizations) was discussed and partially integrated in related flows.

## 2) What Is Working Now

- Build compiles successfully after recent warning fix (`DeviceControlViewModel` `MainActor.run` unused-result warnings).
- Temporary Colors-tab transitions run without requiring temporary WLED playlist generation.
- Saved transition presets can save persistent playlist + steps and can replay from Presets tab.
- Transition cancellation chip UX path exists and supports explicit cancel interaction.
- Automation delete path enqueues timer deletion and managed asset cleanup.
- Automation slot policy is implemented as strict WLED-style mapping (specific-time/sunrise/sunset slot bands).
- Timer fetch logs consistently report logical 10 slots (`timer.slots.reported ... logicalSlots=10`).

## 3) What Is Not Fully Working / Still Open

### A. “No available timer slots” for automation creation
- Root cause can be true device exhaustion, not parser failure.
- On `192.168.0.6`, timer slots `0...7` have been observed occupied with non-zero macros, so specific-time scheduling has no free slot.
- We added slot-occupancy diagnostics and matching-slot recovery logic, but if all 0...7 are genuinely occupied, creation is correctly blocked.

### B. Not all device automations imported into app list
- Import intentionally filters to actionable WLED timers (`macroId > 0`) and applies safety filters (pending delete, catalog availability).
- There is still an open UX/logic gap where users expect complete visibility of all device-side timer entries.
- Needs explicit import policy decision:
  - strict actionable-only (current tendency), or
  - “show all device timers” mode with unsupported entries flagged.

### C. Device overload/timeout sensitivity
- Repeated network timeouts (`/json`, `/presets.json`, websocket) still appear in stress conditions.
- Current behavior has backoff and transient handling, but device-side saturation can still produce degraded interactions.

### D. UI state-sync polish gaps
- Some flows still show lag/desync between chip/UI state and actual device state during heavy transitions or reconnect moments.

## 4) Key Files Carrying This Work

- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/TransitionPane.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Scenes/PresetsListView.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/WLEDAPIService.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/AutomationStore.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/DeviceCleanupManager.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Services/TemporaryTransitionCleanupService.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Models/Automation.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-ControlTests/AutomationModelTests.swift`

## 5) Current Practical Status (Short)

- Presets/playlists core flow: mostly functional.
- Transition save/replay: functional with much better stability than earlier regression period.
- Automation: core architecture implemented, but still has open import/slot-visibility and operational clarity issues depending on on-device timer occupancy.
- Remaining risk is now mostly in edge-case synchronization and device saturation behavior, not in the original catastrophic cleanup-race failure mode.

## 6) Immediate Next Steps (Recommended)

1. Add a “Timer Slots Inspector” UI/debug panel per device:
   - show slot, hour/min, macro, enabled, source (app/imported/unknown), and occupancy reason.
2. Decide import policy explicitly:
   - actionable-only vs full timer visibility with warnings.
3. Add one-click safe “reclaim stale automation timers” action (manual, explicit) for slots `0...7`.
4. Add a tight validation suite for:
   - specific-time slot exhaustion,
   - import completeness behavior,
   - delete/recreate slot reuse determinism.

## 7) Latest Fixes Added (2026-03-24 evening)

### A. Automation visibility import reliability
- Device automation import no longer suppresses visible timers just because timer-delete entries are pending.
- Import now proceeds even when preset/playlist catalogs are temporarily unavailable (placeholder-action import), then resolves later.
- Foreground/first-healthy reconnect paths were wired so import runs more consistently instead of waiting for specific transitions.
- Added import diagnostics:
  - `automation.import.reported device=<id> configuredTimers=<n> pendingTimerDeletes=<...>`

### B. Automation delete reliability + diagnostics (timer slots)
- Found a root issue: timer “delete” was only toggling `enabled=false` but leaving `macroId` populated, so slots still looked occupied (`macroId > 0`).
- `disableTimer(slot:)` now clears timer slot state for deletion semantics:
  - `enabled=false`, `hour=0`, `minute=0`, `days=0x7F`, `macroId=0`
  - plus post-write verification.
- Added focused delete-path logs in queue processing and timer deletion:
  - `cleanup.queue_attempt ...`
  - `cleanup.delete.begin ...`
  - `cleanup.timer.delete.before/after ...` (DEBUG)
  - `timer.delete.begin/done/verify_failed ...`
  - `cleanup.delete.error ...`
