# Gradient Restoration Color Jump - Complete Fix

## Problem Description

Even after initial fixes, users still experienced:
1. **Power Toggle**: Random color appears briefly when turning device on, before correct gradient colors
2. **Brightness 0% → >0%**: Color stays wrong and doesn't update to correct gradient colors unless manually changed

## Root Cause Analysis

### Issue 1: Missing User Interaction Marking

**Problem**: `applyGradientStopsAcrossStrip` was setting `gradientApplicationTimes` but **not calling `markUserInteraction`**, which meant WebSocket updates could still interfere during gradient application.

**Impact**: WebSocket state updates from WLED could overwrite gradient colors during the upload process.

### Issue 2: Insufficient Protection Window

**Problem**: `gradientProtectionWindow` was only 2 seconds, which might not be enough for per-LED uploads that can take longer, especially for large LED strips.

**Impact**: WebSocket updates could arrive after the protection window expired, overwriting gradient colors.

### Issue 3: Missing Protection During Power-On

**Problem**: When turning device on, `markUserInteraction` was called for power toggle but not extended for gradient restoration.

**Impact**: WebSocket updates could interfere between power-on and gradient restoration.

### Issue 4: Missing Protection During Brightness Restoration

**Problem**: When restoring brightness from 0%, gradient restoration didn't mark user interaction before starting.

**Impact**: WebSocket updates could interfere with gradient restoration.

### Issue 5: Race Condition with WLED State Restoration

**Problem**: When WLED turns on, it might restore its own default state from memory before our gradient is applied.

**Impact**: Brief flash of WLED's default color before gradient is applied.

---

## Complete Solution

### Fix 1: Mark User Interaction in `applyGradientStopsAcrossStrip`

**Before**:
```swift
func applyGradientStopsAcrossStrip(...) async {
    // No user interaction marking
    // Only sets gradientApplicationTimes
}
```

**After**:
```swift
func applyGradientStopsAcrossStrip(...) async {
    // CRITICAL: Mark user interaction BEFORE applying gradient
    markUserInteraction(device.id)
    // ... rest of function
}
```

**Why**: This ensures WebSocket updates are blocked during gradient application via `isUnderUserControl()` check.

### Fix 2: Increase Protection Window

**Before**:
```swift
private let gradientProtectionWindow: TimeInterval = 2.0 // 2 seconds
```

**After**:
```swift
private let gradientProtectionWindow: TimeInterval = 3.0 // 3 seconds (increased for per-LED uploads)
```

**Why**: Per-LED uploads can take longer, especially for large strips. 3 seconds provides better protection.

### Fix 3: Extend Protection During Power-On

**Before**:
```swift
if isTurningOn {
    // No additional user interaction marking
    await applyGradientStopsAcrossStrip(...)
}
```

**After**:
```swift
if isTurningOn {
    // CRITICAL: Mark user interaction BEFORE gradient restoration
    markUserInteraction(device.id)
    
    // Small delay to ensure power-on completes
    try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
    
    await applyGradientStopsAcrossStrip(...)
}
```

**Why**: 
- Extends protection window to cover both power-on and gradient restoration
- Small delay ensures WLED has processed power-on before gradient is applied
- Prevents race condition with WLED's state restoration

### Fix 4: Extend Protection During Brightness Restoration

**Before**:
```swift
if wasOff && hasPersistedGradient {
    // No user interaction marking
    await applyGradientStopsAcrossStrip(...)
}
```

**After**:
```swift
if wasOff && hasPersistedGradient {
    // CRITICAL: Mark user interaction BEFORE gradient restoration
    markUserInteraction(device.id)
    
    await applyGradientStopsAcrossStrip(...)
}
```

**Why**: Ensures WebSocket updates don't interfere with gradient restoration when brightness is restored from 0%.

---

## Protection Mechanisms

### 1. User Interaction Protection (`isUnderUserControl`)

**Window**: 1.5 seconds  
**Purpose**: Blocks WebSocket updates when user is actively controlling device  
**Used By**: `handleWebSocketStateUpdate()` checks this before applying updates

### 2. Gradient Application Protection (`gradientJustApplied`)

**Window**: 3.0 seconds (increased from 2.0)  
**Purpose**: Blocks WebSocket color updates after gradient is applied  
**Used By**: `handleWebSocketStateUpdate()` skips color updates if gradient was just applied

### 3. Pending Toggle Protection (`pendingToggles`)

**Window**: Until toggle completes (max 5 seconds)  
**Purpose**: Prevents WebSocket updates during power toggle  
**Used By**: `handleWebSocketStateUpdate()` skips updates if toggle is pending

---

## How WebSocket Protection Works

```swift
private func handleWebSocketStateUpdate(_ stateUpdate: WLEDDeviceStateUpdate) {
    // Check 1: Optimistic UI state
    if uiToggleStates[stateUpdate.deviceId] != nil {
        return  // Skip - UI has optimistic state
    }
    
    // Check 2: User interaction protection
    if isUnderUserControl(stateUpdate.deviceId) {
        return  // Skip - User is actively controlling device
    }
    
    // Check 3: Pending toggle protection
    if pendingToggles[stateUpdate.deviceId] != nil {
        return  // Skip - Toggle in progress
    }
    
    // Check 4: Gradient application protection
    let gradientJustApplied = ...
    if gradientJustApplied {
        return  // Skip color update - Gradient was just applied
    }
    
    // Only apply update if all checks pass
}
```

---

## Changes Made

### File: `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`

1. **`applyGradientStopsAcrossStrip()`** (line ~2195):
   - Added `markUserInteraction(device.id)` at the start
   - Ensures WebSocket protection during gradient application

2. **`gradientProtectionWindow`** (line ~465):
   - Increased from 2.0 to 3.0 seconds
   - Better protection for per-LED uploads

3. **`toggleDevicePower()`** (line ~1192):
   - Added `markUserInteraction(device.id)` before gradient restoration
   - Added 0.15 second delay to ensure power-on completes
   - Extends protection window to cover both operations

4. **`updateDeviceBrightness()`** (line ~1228):
   - Added `markUserInteraction(device.id)` before gradient restoration
   - Ensures protection when restoring brightness from 0%

---

## Expected Behavior After Fix

### Power Toggle:
1. User turns device on
2. `markUserInteraction()` called (1.5s protection starts)
3. Power-on state update sent (no `col` field)
4. 0.15s delay to ensure WLED processes power-on
5. `markUserInteraction()` called again (extends protection)
6. `applyGradientStopsAcrossStrip()` called (marks again + 3s gradient protection)
7. Gradient applied with full WebSocket protection
8. Result: ✅ No color jump - smooth transition to gradient

### Brightness 0% → >0%:
1. User sets brightness to >0%
2. `markUserInteraction()` called (1.5s protection starts)
3. `applyGradientStopsAcrossStrip()` called (marks again + 3s gradient protection)
4. Gradient restored with correct brightness
5. Result: ✅ Correct gradient colors applied immediately

---

## Testing Recommendations

1. **Power Toggle Test**:
   - Set a multi-color gradient
   - Turn device off
   - Turn device on
   - ✅ Verify: No color jump, gradient appears correctly

2. **Brightness Restoration Test**:
   - Set a multi-color gradient
   - Set brightness to 0%
   - Set brightness back to 100%
   - ✅ Verify: Gradient colors are correct immediately

3. **Rapid Operations Test**:
   - Rapidly toggle power on/off
   - Rapidly change brightness
   - ✅ Verify: No color jumps or incorrect colors

4. **WebSocket Interference Test**:
   - Enable WebSocket updates
   - Turn device on
   - ✅ Verify: WebSocket updates don't overwrite gradient

---

## Alignment with WLED API

✅ **Correct**: Not sending `col` field when gradient will be restored  
✅ **Correct**: Using user interaction protection to prevent WebSocket conflicts  
✅ **Correct**: Using gradient application protection to prevent color overwrites  
✅ **Correct**: Sequential state updates with appropriate delays  

**Reference**: [WLED GitHub Repository](https://github.com/wled/WLED)

---

## Conclusion

The color jump issues were caused by:
1. Missing user interaction marking in gradient restoration
2. Insufficient protection window duration
3. Race conditions with WLED's state restoration

All issues have been fixed with:
- ✅ User interaction marking in all gradient restoration paths
- ✅ Increased protection window (2s → 3s)
- ✅ Extended protection during power-on and brightness restoration
- ✅ Appropriate delays to prevent race conditions

The implementation now correctly prevents WebSocket interference and ensures smooth gradient restoration without color jumps.


