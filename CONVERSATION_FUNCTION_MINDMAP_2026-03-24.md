# Aesdetic Control Function Mindmap (Conversation Scope)

Date: 2026-03-24  
Coverage: Features and functions touched/discussed in this conversation (not every unrelated function in the entire app).

## 1) Architecture Mindmap (Concept + Function-Level)

```mermaid
mindmap
  root((Aesdetic Control\nPresets/Playlists/Transitions/Automation))
    "DeviceControlViewModel (runtime orchestration)"
      "Transition save/apply"
        "createTransitionPlaylist(...)"
        "saveTransitionPresetToDevice(...)"
        "saveTransitionPresetWithActiveRunHandling(...)"
        "applyTransitionPreset(...)"
      "Playlist runtime"
        "startPlaylist(...)"
        "stopPlaylist(...)"
        "stopPlaylistViaWebSocketIfConnected(...)"
      "Run/cleanup controls"
        "waitForHeavyOpQuiescence(...)"
        "cancelActiveRun(...)"
        "cancelActiveTransitionIfNeeded(...)"
        "cleanupTransitionPlaylist(...)"
      "Discovery/state refresh"
        "scheduleDiscoveryStateRefresh(...)"
        "refreshDeviceState(...)"
      "Error UX handling"
        "presentError(...) suppression for cancelled/transient paths"
    "WLEDAPIService (device I/O)"
      "Preset/playlist APIs"
        "savePreset(...)"
        "savePlaylist(...)"
        "fetchPresets(...)"
        "fetchPlaylists(...)"
        "applyPlaylist(...)"
        "stopPlaylist(on:)"
      "Timer APIs"
        "fetchTimers(...)"
        "updateTimer(...)"
        "disableTimer(...)"
        "decodeWLEDTimers(...)"
        "encodeWLEDTimersForConfig(...)"
      "State write control"
        "updateState(...)"
        "state_write.backoff"
        "semantic dedup signatures"
    "AutomationStore (WLED timer orchestration)"
      "CRUD & scheduling"
        "add(...)"
        "update(...)"
        "delete(...)"
        "applyAutomation(...)"
        "scheduleNext(...)"
      "On-device sync"
        "syncOnDeviceScheduleIfNeeded(...)"
        "ensureTimerSlot(...)"
        "validateOnDeviceSchedule(...)"
        "validateLocalTimerCapacity(...)"
      "Slot strategy (strict WLED)"
        "wledTimerConfig(...)"
        "reservedTimerSlots(...)"
        "selectTimerSlot(...)"
        "findMatchingTimerSlotOnDevice(...)"
        "recoverMatchingTimerSlotWhenUnavailable(...)"
      "Readiness state"
        "updateAutomationSyncMetadata(...)"
        "markOnDeviceNotReady(...)"
        "retryOnDeviceSync(...)"
      "Import from WLED"
        "importOnDeviceAutomations(...)"
        "importedTemplateId(...)"
      "Managed assets"
        "ensureAutomationTransitionPlaylist(...)"
        "ensureAutomationPresetSnapshot(...)"
        "resolveOnDeviceActionTarget(...)"
        "cleanupDeviceEntries(...)"
        "shouldDeleteManagedPlaylistAsset(...)"
        "shouldDeleteManagedPresetAsset(...)"
      "Safety & observability"
        "verifyTimerWithRetry(...)"
        "disarmTimerSlotFailClosed(...)"
        "disableDuplicateTimerSlotsIfNeeded(...)"
        "logOccupiedTimerSlots(...)"
    "DeviceCleanupManager / Cleanup services"
      "queue-based deletion intent"
      "timer/preset/playlist pending delete processing"
      "stale managed asset cleanup (bounded)"
    "UI surfaces"
      "TransitionPane"
        "save transition + preset path binding"
      "PresetsListView"
        "replay saved transition/preset/playlist"
      "AutomationRow/AddAutomationDialog/AutomationColorEditor"
        "Ready/Not Ready/Geting Ready states"
        "retry + toggle + delete actions"
```

## 2) Runtime Flow Mindmap (How it Works)

```mermaid
mindmap
  root((Runtime Flows))
    "Temporary Transition (Colors tab)"
      "User presses Apply transition"
      "app-side runner starts"
      "no temp WLED playlist persistence by default path"
      "manual user inputs cancel active run"
      "tab switch should not auto-cancel"
    "Saved Transition (+Preset)"
      "waitForHeavyOpQuiescence"
      "createTransitionPlaylist(... persist:true)"
      "save step presets via psave"
      "save playlist via psave+playlist payload"
      "mark preset synced/pendingSync"
      "apply from Presets -> startPlaylist(ps=id)"
    "Preset/Playlist Replay"
      "prefer direct stored macro replay"
      "websocket-first stop/start where available"
      "HTTP fallback"
      "probe/log verify running pl/ps"
    "Automation On-Device"
      "compute trigger -> timer config"
      "resolve macro target (preset/playlist/managed asset)"
      "select/reuse slot"
      "write timer in /json/cfg"
      "verify timer"
      "state Ready or Not ready"
    "Automation Delete"
      "enqueue timer slot delete"
      "delete managed playlist/preset assets only"
      "preserve user-selected preset/playlist assets"
```

## 3) What Was Added/Changed in This Conversation (Key Functional Deltas)

- Transition save/replay unification around `createTransitionPlaylist(... persist:true)` + replay via `startPlaylist(...)`.
- Colors-tab lifecycle protection from unintended state writes/cancels during tab switch.
- Cancel/noise suppression for benign cancellation errors in background paths.
- Automation strict WLED slot policy (`0...7`, `8`, `9`) and sparse/full timer codec handling.
- Slot selection hardening:
  - `reservedTimerSlots(...)` constrained by `runOnDevice` and target device.
  - recovery path for matching existing slot when initial selection is unavailable.
  - occupancy diagnostics with slot/macro detail.
- Managed transition asset delete correctness:
  - step preset IDs tracked and deleted for managed transition automations.
- Build warning fix:
  - `MainActor.run` calls in `DeviceControlViewModel` now consume returned value (`_ = ...`).

## 4) Current Working vs Open (Feature-Level)

### Working
- Temporary transitions generally stable and no longer dependent on aggressive temp playlist cleanup.
- Saved transition preset creation and replay path works in normal conditions.
- Preset/playlist run/apply paths function with WLED-compatible psave/apply semantics.
- Automation on-device scheduling pipeline exists end-to-end with readiness states and retry.
- Build compiles after current warning fix.

### Open / Incomplete
- Device-side timer visibility/import expectations:
  - not all device timer rows are always surfaced exactly as user expects in Automation tab.
- Real device saturation scenarios still produce timeouts and degraded sync.
- If slots `0...7` are fully occupied with active macros, specific-time automation creation is correctly blocked; this still appears as user-facing friction.
- Some UI state sync lag can still happen under heavy network churn.

## 5) Notes on “Every Detail”

This mindmap captures the full conversation scope at function-level for the affected systems.  
It does not enumerate every unrelated function in the whole codebase (for example wellness/widget internals that were not part of this workstream).

