# Automation System Overview & Recent Changes

## 📋 Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Recent Changes Summary](#recent-changes-summary)
3. [Current Implementation State](#current-implementation-state)
4. [Key Components](#key-components)
5. [Data Models](#data-models)
6. [Scheduling System (Current)](#scheduling-system-current)
7. [Next Steps: BGTaskScheduler Implementation](#next-steps-bgtaskscheduler-implementation)

---

## Architecture Overview

The automation system is built around a **centralized `AutomationStore`** that manages:
- **Storage**: JSON-based persistence (`automations.json`)
- **Scheduling**: Timer-based execution (currently foreground-only)
- **Execution**: Multi-device action application with retry logic
- **Solar Calculations**: Sunrise/sunset trigger resolution with caching

### Key Design Decisions
- **@MainActor** singleton pattern for `AutomationStore`
- **Binding-based editors** for automation creation (no direct device updates)
- **Preset integration** for colors, transitions, and effects
- **Metadata tracking** for previews, WLED device-side execution, and UI state

---

## Recent Changes Summary

### 1. **Automation Editor Refactoring** ✅
**Files Changed:**
- `AddAutomationDialog.swift` - Main dialog orchestrator
- `AutomationColorEditor.swift` - NEW: Dedicated color/gradient editor
- `AutomationTransitionEditor.swift` - NEW: Dedicated transition editor
- `AutomationEffectEditor.swift` - NEW: Dedicated effect editor

**What Changed:**
- **Before**: Monolithic `VStack` in `AddAutomationDialog` causing type-checking issues
- **After**: Three separate editor components with computed view properties
- **Benefit**: Faster compilation, better code organization, reusable components

**Key Features Added:**
- Preset selection with visual chips
- Preview toggle for live device updates
- Gradient interpolation mode selection
- Temperature/CCT support in color editors
- Duration pickers (hours/minutes) for transitions

### 2. **Preset Model Enhancement** ✅
**Files Changed:**
- `PresetModels.swift`

**What Changed:**
- Added `gradientInterpolation: GradientInterpolation?` to `ColorPreset`
- Added `gradientInterpolation: GradientInterpolation?` to `WLEDEffectPreset`
- Preserves interpolation mode when saving/loading presets

**Impact:**
- Automations now correctly preserve blend styles (linear, ease-in, ease-out, etc.)
- Preset chips show accurate gradient previews

### 3. **Device Sync Section UI Improvements** ✅
**Files Changed:**
- `AddAutomationDialog.swift` - `deviceSyncSection`

**What Changed:**
- Removed glass card wrapper (more compact)
- Status dot moved to right of "Online"/"Offline" text
- Summary moved to top-right, aligned with heading
- Improved accessibility labels and hit areas (44pt minimum)

**Visual Result:**
```
Sync to devices                    Syncing to 2 of 3 devices
┌─────────────────────────────────────────────────────────┐
│ Device Name                    Online ●                 │
│ Device Name                    Offline ●                │
└─────────────────────────────────────────────────────────┘
```

### 4. **Compiler Warning Fixes** ✅
**Files Changed:**
- `DeviceControlViewModel.swift`

**What Changed:**
- Changed `var bodies` to `let bodies` (line 2339)
- Replaced unused `let currentBrightness` with `_ = ...` (line 2264)

### 5. **Metadata Regeneration** ✅
**Files Changed:**
- `AddAutomationDialog.swift` - `buildAutomation()`

**What Changed:**
- `buildAutomation()` now regenerates `AutomationMetadata` with fresh `colorPreviewHex`
- Ensures edited automations show correct previews in list/summary views

---

## Current Implementation State

### ✅ Fully Implemented

1. **Automation Creation & Editing**
   - Three action types: Colors, Transitions, Animations
   - Three trigger types: Specific Time, Sunrise, Sunset
   - Multi-device selection with online/offline status
   - Preset integration for all action types
   - Preview functionality for all editors

2. **Action Execution**
   - Gradient application with interpolation modes
   - Transition execution (start → end gradients)
   - Effect application with speed/intensity/palette
   - Multi-device coordination with partial failure handling
   - Retry logic for failed devices

3. **Solar Trigger Resolution**
   - Location-based sunrise/sunset calculation
   - 30-day location caching
   - Offset support (±120 minutes)
   - Solar cache for performance

4. **Data Persistence**
   - JSON-based storage (`automations.json`)
   - Legacy migration support
   - Metadata preservation

### ⚠️ Current Limitations

1. **Scheduling Reliability**
   - **Current**: `Timer.scheduledTimer()` - dies when app is suspended
   - **Problem**: Automations don't fire if app is in background
   - **Impact**: Users must keep app open for automations to work

2. **No Background Execution**
   - No `BGTaskScheduler` integration
   - No notification fallback
   - No launch-time missed automation check

3. **WLED Native Support (Partial)**
   - `AutomationMetadata` has fields for `wledPlaylistId` and `wledTimerSlot`
   - No API methods for timer management (`fetchTimers`, `saveTimer`)
   - No playlist API methods (`fetchPlaylists`, `applyPlaylist`)
   - No execution mode selection UI

4. **Hub Integration (Not Started)**
   - No HomeKit hub detection
   - No Home Assistant MQTT integration
   - No execution mode enum or routing layer

---

## Key Components

### 1. AutomationStore (`Services/AutomationStore.swift`)
**Role**: Central automation manager

**Key Methods:**
- `scheduleNext()` - Finds next automation and schedules Timer
- `triggerAutomation(_:)` - Executes automation when timer fires
- `applyAutomation(_:)` - Applies action to target devices
- `resolveNextAutomation(referenceDate:)` - Finds next scheduled automation
- `computeSolarDate(...)` - Calculates sunrise/sunset times

**Current Scheduling Flow:**
```
scheduleNext()
  → resolveNextAutomation()
  → scheduleTimer(for:fireDate:)
  → Timer.scheduledTimer(...)
  → triggerAutomation()
  → applyAutomation()
  → scheduleNext() (recurse)
```

**Problem**: Timer dies when app is suspended

### 2. AddAutomationDialog (`Views/Components/AddAutomationDialog.swift`)
**Role**: Main UI for creating/editing automations

**Key Sections:**
- `automationSettingsSection` - Trigger selection (Time/Sunrise/Sunset)
- `repeatScheduleSection` - Weekday selection with swipe-to-select
- `automationActionSection` - Action type picker (Colors/Transitions/Animations)
- `deviceSyncSection` - Multi-device selection with status indicators

**State Management:**
- 20+ `@State` variables for UI state
- Bindings passed to child editors
- Template prefill support for quick creation

### 3. AutomationColorEditor (`Views/Components/AutomationColorEditor.swift`)
**Role**: Color/gradient editor for automations

**Key Features:**
- Gradient bar with stop manipulation
- Color wheel with CCT support
- Preset chip selector
- Brightness slider
- Fade duration toggle
- Preview toggle

**Computed Views:**
- `headerRow` - Title, preview toggle, save preset button
- `brightnessSection` - Brightness slider
- `blendSelector` - Interpolation mode picker
- `gradientSection` - GradientBar component
- `presetSelector` - Preset chips
- `colorWheel` - ColorWheelInline component
- `fadeSection` - Fade toggle and duration slider

### 4. AutomationTransitionEditor (`Views/Components/AutomationTransitionEditor.swift`)
**Role**: Transition editor (start → end gradients)

**Key Features:**
- Separate gradient bars for start and end
- Duration picker (hours/minutes)
- Transition preset selector
- Color preset selector for each gradient
- Preview with cancellation

### 5. AutomationEffectEditor (`Views/Components/AutomationEffectEditor.swift`)
**Role**: Effect/animation editor

**Key Features:**
- Effect picker with metadata
- Gradient editor (adapts to effect's color slot count)
- Brightness, speed, intensity sliders
- Effect preset selector
- Color preset selector
- Debounced preview (180ms)

---

## Data Models

### Automation (`Models/Automation.swift`)
```swift
struct Automation {
    let id: UUID
    var name: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastTriggered: Date?
    
    var trigger: AutomationTrigger  // .specificTime, .sunrise, .sunset
    var action: AutomationAction   // .gradient, .transition, .effect, etc.
    var targets: AutomationTargets // deviceIds, allowPartialFailure
    var metadata: AutomationMetadata // previews, WLED IDs, execution mode
}
```

### AutomationTrigger
- **`.specificTime(TimeTrigger)`** - Fixed time with weekdays
- **`.sunrise(SolarTrigger)`** - Sunrise with offset
- **`.sunset(SolarTrigger)`** - Sunset with offset

### AutomationAction
- **`.gradient(GradientActionPayload)`** - Single gradient with fade
- **`.transition(TransitionActionPayload)`** - Start → end gradient transition
- **`.effect(EffectActionPayload)`** - WLED effect with gradient
- **`.preset(PresetActionPayload)`** - WLED preset recall
- **`.playlist(PlaylistActionPayload)`** - WLED playlist
- **`.scene(SceneActionPayload)`** - Legacy scene (migrated to gradient)
- **`.directState(DirectStatePayload)`** - Direct color/brightness

### AutomationMetadata
```swift
struct AutomationMetadata {
    var colorPreviewHex: String?
    var accentColorHex: String?
    var iconName: String?
    var notes: String?
    var templateId: String?
    var pinnedToShortcuts: Bool?
    
    // WLED device-side execution (for future use)
    var wledPlaylistId: Int?
    var wledTimerSlot: Int?
    var runOnDevice: Bool
}
```

**Note**: `executionMode`, `externalId`, `lastDelegatedAt` fields are **NOT YET IMPLEMENTED** (planned for hybrid approach)

---

## Scheduling System (Current)

### Current Flow
```
App Launch
  → AutomationStore.init()
  → load() (from JSON)
  → scheduleNext()
  → resolveNextAutomation()
  → scheduleTimer(for:fireDate:)
  → Timer.scheduledTimer(...) [FOREGROUND ONLY]
  
When Timer Fires:
  → triggerAutomation()
  → applyAutomation()
  → scheduleNext() (recurse)
```

### Timer Implementation
```swift
private func scheduleTimer(for automation: Automation, fireDate: Date) {
    schedulerTimer?.invalidate()
    let interval = max(1.0, fireDate.timeIntervalSince(Date()))
    schedulerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
        Task { @MainActor in
            self?.triggerAutomation(automation)
        }
    }
}
```

**Problems:**
1. Timer is invalidated when app is suspended
2. No background task registration
3. No notification fallback
4. No missed automation detection on launch

---

## Next Steps: BGTaskScheduler Implementation

### Phase 1: BGTaskScheduler Foundation (Priority 1)

**Files to Modify:**
- `Aesdetic-Control/Services/AutomationStore.swift`
- `Aesdetic-Control/Aesdetic_ControlApp.swift` (register identifiers)

**Changes Required:**

1. **Register Background Task Identifiers**
   ```swift
   // In Aesdetic_ControlApp.init()
   BGTaskScheduler.shared.register(
       forTaskWithIdentifier: "com.aesdetic.automation.refresh",
       using: nil
   ) { task in
       Task { @MainActor in
           await AutomationStore.shared.handleBackgroundTask(task: task)
       }
   }
   ```

2. **Replace Timer with BGTaskScheduler**
   ```swift
   // In AutomationStore
   private func scheduleNext() {
       // ... existing resolveNextAutomation logic ...
       
       // Choose task type based on duration
       if automationNeedsLongTask(nextAutomation) {
           scheduleBackgroundProcessingTask(...)
       } else {
           scheduleBackgroundRefreshTask(...)
       }
       
       // Always schedule notification fallback
       scheduleNotificationFallback(...)
       
       // Keep foreground timer as last-second verification
       scheduleForegroundTimer(...)
   }
   ```

3. **Add Notification Fallback**
   ```swift
   private func scheduleNotificationFallback(...) {
       // UNNotificationRequest with "tap to run now" action
   }
   ```

4. **Add Launch-Time Missed Automation Check**
   ```swift
   func checkMissedAutomations() {
       // Compare lastTriggered vs nextTriggerDate for past hour
       // Log missed automations
       // Optionally execute immediately
   }
   ```

### Phase 2: WLED Native Support (Priority 2)

**Files to Create/Modify:**
- `Aesdetic-Control/Services/WLEDAPIService.swift` (add timer/playlist methods)
- `Aesdetic-Control/Models/WLEDAPIModels.swift` (add timer models)

**API Methods to Add:**
- `fetchTimers(for:)` - GET `/json/timers`
- `saveTimer(_:to:)` - POST `/json/timers`
- `fetchPlaylists(for:)` - GET `/json/playlists`
- `applyPlaylist(_:to:)` - Apply playlist via state update

### Phase 3: Execution Mode Selection (Priority 3)

**Files to Create/Modify:**
- `Aesdetic-Control/Models/Automation.swift` (add `AutomationExecutionMode`)
- `Aesdetic-Control/Views/Components/AddAutomationDialog.swift` (add mode selector)

**New Enum:**
```swift
enum AutomationExecutionMode: String, Codable {
    case homeKit
    case homeAssistant
    case wledNative
    case appBackground
}
```

**Metadata Extension:**
```swift
struct AutomationMetadata {
    // ... existing fields ...
    var executionMode: AutomationExecutionMode?
    var externalId: String? // Hub/device ID
    var lastDelegatedAt: Date?
}
```

### Phase 4: Hub Integration (Priority 4)

**Files to Create:**
- `Aesdetic-Control/Services/HubDetectionService.swift`
- `Aesdetic-Control/Services/HomeKitIntegration.swift`
- `Aesdetic-Control/Services/HomeAssistantIntegration.swift`

**Detection Logic:**
- HomeKit: `HMHomeManager.hubState`
- Home Assistant: User-provided URL + MQTT credentials
- WLED Native: Device has free timer slots + preset support

---

## Summary

### What We've Built ✅
- Complete automation creation/editing UI
- Three dedicated editor components (Color, Transition, Effect)
- Preset integration with interpolation mode support
- Multi-device coordination with status indicators
- Solar trigger resolution with caching
- JSON-based persistence with legacy migration

### What's Missing ⚠️
- **BGTaskScheduler** for background execution
- **Notification fallback** for missed automations
- **WLED timer/playlist API** methods
- **Execution mode selection** UI
- **Hub detection and delegation**

### Next Immediate Step 🎯
**Implement BGTaskScheduler foundation** to fix the #1 reliability issue: automations not firing when app is in background.

---

**Last Updated**: After commit `1e63560` (Automation editor refactoring checkpoint)
