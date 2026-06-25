# WLED Features Analysis: Opportunities for Improvement

Based on codebase analysis, here are key WLED features that could significantly improve transitions, automation, and color setting in your app:

## 🎯 Critical Missing Features

### 1. **WLED's Built-in Transition Time (`tt` parameter)**
**Current State:** You have `tt` parameter support in `WLEDStateUpdate`, but it's rarely used:
- ❌ Preset applications in automations always use `transition: nil` (see `AutomationStore.swift:272`)
- ❌ Brightness changes don't use transition times
- ❌ Simple color changes don't use transition times
- ✅ Complex gradient transitions use client-side `GradientTransitionRunner` (sending many frames)

**WLED Capability:** WLED can handle smooth color/brightness transitions internally using the `tt` parameter (in deciseconds). This is more efficient than sending 60+ frames per second.

**Recommendation:**
- Use `tt` for simple brightness/color transitions (< 5 seconds)
- Keep `GradientTransitionRunner` for complex gradient transitions (multi-stop gradients)
- Add `transition` parameter to automation preset applications

**Example:**
```swift
// Current (AutomationStore.swift:272):
_ = try await apiService.applyPreset(payload.presetId, to: device, transition: nil)

// Better:
let transitionMs = Int(payload.durationSeconds * 1000) // Convert to milliseconds
_ = try await apiService.applyPreset(payload.presetId, to: device, transition: transitionMs)
```

---

### 2. **WLED Playlists for Automation**
**Current State:** You can fetch playlists (`fetchPlaylists`) but never use them.

**WLED Capability:** Playlists allow WLED devices to cycle through presets automatically with:
- Custom durations per preset
- Transition times between presets
- Repeat counts
- All handled on-device (reduces network traffic)

**Recommendation:**
- For automations that cycle through multiple presets/scenes, save as WLED playlists
- Let WLED handle the cycling logic on-device
- Reduces app complexity and network load
- Works even if app disconnects

**Use Case:**
- Sunrise automation: Create playlist with [warm → neutral → cool] presets
- Party mode: Cycle through colorful presets
- Sleep routine: Gradually dim through brightness presets

---

### 3. **WLED Macros for Time-Based Automation**
**Current State:** Not implemented at all.

**WLED Capability:** WLED macros can execute on time-based triggers (hourly, daily, at specific times). The device can handle simple automations locally.

**Recommendation:**
- For simple, time-based automations (e.g., "turn on at 7 AM"), use WLED macros
- Offloads automation logic to device
- Works independently of app
- Reduces network requests

**Configuration API:**
- Macros can be set via `/json/cfg` endpoint (macro presets)
- Button actions can trigger macros (as shown in your image)
- Time-based macros use preset IDs

---

### 4. **Preset Transitions in State Updates**
**Current State:** When applying presets, transitions are always `nil`.

**WLED Capability:** Presets can include transition times, and you can override them when applying:
```json
{"ps": 5, "tt": 30}  // Apply preset 5 with 3-second transition
```

**Recommendation:**
- Pass transition times when applying presets in automations
- Use preset's stored transition as default, allow override
- More efficient than manual state transitions

---

### 5. **Per-Segment Transitions**
**Current State:** You update segments but don't use segment-specific transition times.

**WLED Capability:** Each segment update can have its own transition behavior (though `tt` is usually global).

**Note:** This is less critical since `tt` is typically global, but worth knowing for multi-segment setups.

---

## 🚀 Implementation Priority

### High Priority (Immediate Impact)

1. **Add transition times to preset applications in automations**
   - File: `AutomationStore.swift`
   - Line: 272
   - Change: `transition: nil` → `transition: durationMs`

2. **Use `tt` parameter for brightness changes in automations**
   - When changing brightness over time, let WLED handle it
   - More efficient than manual brightness ramping

3. **Use WLED playlists for multi-preset automations**
   - Perfect for sunrise/sunset sequences
   - Reduces network traffic
   - More reliable (device-side execution)

### Medium Priority (Better User Experience)

4. **WLED macros for simple time-based automations**
   - Reduces app dependency
   - Works offline
   - Simplifies automation setup for users

5. **Hybrid approach: Use `tt` for simple transitions, keep `GradientTransitionRunner` for complex**
   - Simple color/brightness changes: Use WLED's `tt`
   - Complex multi-stop gradients: Keep client-side runner

### Low Priority (Nice to Have)

6. **Per-segment transition support**
   - Only relevant for multi-segment setups
   - Lower impact on most use cases

---

## 📊 Performance Impact

**Current Approach (Client-Side Transitions):**
- 60 FPS × 5 seconds = 300 API calls for a 5-second transition
- High network traffic
- Device must process each frame
- App must stay connected

**WLED Built-in Transitions (`tt`):**
- 1 API call with transition time
- Device handles interpolation
- Works offline (if using playlists/macros)
- More efficient CPU usage on device

---

## 🔍 Code Locations to Update

1. **AutomationStore.swift:272** - Add transition to preset applications
2. **AutomationStore.swift:279-300** - Consider using playlists for gradient actions
3. **DeviceControlViewModel.swift** - Add transition parameter to brightness updates
4. **WLEDAPIService.swift** - Ensure `applyPreset` properly uses transition parameter

---

## 📝 Example Improvements

### Example 1: Preset Transition in Automation
```swift
// Current:
case .preset(let payload):
    _ = try await apiService.applyPreset(payload.presetId, to: device, transition: nil)

// Improved:
case .preset(let payload):
    // Use payload's duration if available, otherwise default to 1 second
    let transitionMs = payload.durationSeconds.map { Int($0 * 1000) } ?? 1000
    _ = try await apiService.applyPreset(payload.presetId, to: device, transition: transitionMs)
```

### Example 2: Playlist for Multi-Preset Automation
```swift
// Instead of applying multiple presets sequentially:
// 1. Create playlist with presets [warm, neutral, cool]
// 2. Set durations [1800s, 1800s, 1800s] (30 min each)
// 3. Set transitions [300, 300, 300] (30s between)
// 4. Apply playlist once - WLED handles the rest
```

### Example 3: Brightness Transition
```swift
// Current: Manual brightness ramping (many API calls)
// Improved: Single API call with transition time
let stateUpdate = WLEDStateUpdate(
    bri: targetBrightness,
    transition: Int(durationSeconds * 1000)
)
_ = try await apiService.updateState(for: device, state: stateUpdate)
```

---

## ⚠️ Important Considerations

1. **Gradient Transitions:** Keep your `GradientTransitionRunner` for complex multi-stop gradients. WLED's `tt` only transitions between solid colors, not complex gradients.

2. **Per-LED Colors:** When using per-LED colors (gradients), you still need client-side transitions. `tt` works best for simple color/brightness changes.

3. **Compatibility:** All these features require WLED 0.13+ (which you already support per PRD).

4. **Hybrid Approach:** Best strategy is to use WLED transitions where appropriate (simple changes) and client-side transitions for complex gradients.
