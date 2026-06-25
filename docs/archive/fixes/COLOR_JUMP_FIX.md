# Color Jump Issue - Diagnosis and Fix

## Problem Description

When turning a device off/on or setting brightness to 0% and then back up, the device would:
1. Jump to a different solid color (not from the gradient)
2. Then jump back to the correct gradient colors

This created a visual "flash" of incorrect color before the gradient was restored.

---

## Root Cause Analysis

### Issue 1: Power Toggle Color Jump

**Problem**: When turning a device on, `updateDeviceState` was sending a solid color (`col` field) before the gradient was restored.

**Flow**:
1. User turns device on
2. `updateDeviceState` sends: `{"on": true, "bri": 255, "seg": [{"col": [[r, g, b]]}]}`
3. WLED applies the solid color immediately
4. 0.1 seconds later, gradient restoration happens
5. Result: Color jump visible to user

**Code Location**: `DeviceControlViewModel.updateDeviceState()` (line 1368)

### Issue 2: Brightness 0% → >0% Color Jump

**Problem**: When brightness goes from 0% to >0%, only brightness was sent (`{"bri": 255}`), but WLED might restore a default color from its internal state, or WebSocket might send old color state.

**Flow**:
1. User sets brightness to 0%
2. User sets brightness back to >0%
3. `updateDeviceBrightness` sends: `{"bri": 255}` (no color)
4. WLED restores default color or old color from state
5. Gradient colors are not restored
6. Result: Wrong color displayed

**Code Location**: `DeviceControlViewModel.updateDeviceBrightness()` (line 1221)

---

## WLED Behavior

According to WLED's API documentation:
- When `col` field is sent, WLED applies that color immediately
- When only `on` and `bri` are sent (no `col`), WLED preserves existing colors
- WLED processes state updates sequentially

**Key Insight**: We should NOT send `col` field when we have a persisted gradient that will be restored immediately.

---

## Solution

### Fix 1: Power Toggle - Don't Send Color When Gradient Exists

**Before**:
```swift
// Always sent a solid color, even when gradient would be restored
let rgb = Color(hex: firstStop.hexColor).toRGBArray()
let stateUpdate = WLEDStateUpdate(
    on: updatedDevice.isOn,
    bri: updatedDevice.brightness,
    seg: [SegmentUpdate(col: [[rgb[0], rgb[1], rgb[2]]])]  // ❌ Causes color jump
)
```

**After**:
```swift
// Check if we have a persisted gradient
let hasPersistedGradient = gradientStops(for: device.id)?.isEmpty == false

if hasPersistedGradient {
    // Don't send col field - let gradient restoration handle colors
    stateUpdate = WLEDStateUpdate(
        on: updatedDevice.isOn,
        bri: updatedDevice.brightness,
        seg: nil  // ✅ No color sent - WLED preserves existing colors
    )
} else {
    // No gradient - send solid color as before
    let rgb = updatedDevice.currentColor.toRGBArray()
    stateUpdate = WLEDStateUpdate(
        on: updatedDevice.isOn,
        bri: updatedDevice.brightness,
        seg: [SegmentUpdate(col: [[rgb[0], rgb[1], rgb[2]]])]
    )
}
```

**Also**: Removed the 0.1 second delay before gradient restoration - no longer needed since we're not sending a conflicting color.

### Fix 2: Brightness Restoration - Restore Gradient Instead of Just Brightness

**Before**:
```swift
// Only sent brightness, causing WLED to restore default color
let stateUpdate = WLEDStateUpdate(bri: brightness)
```

**After**:
```swift
// Check if brightness is being restored from 0
let wasOff = device.brightness == 0 && brightness > 0
let hasPersistedGradient = gradientStops(for: device.id)?.isEmpty == false

if wasOff && hasPersistedGradient {
    // Restore gradient with new brightness - applies both correctly
    await applyGradientStopsAcrossStrip(
        updatedDevice,
        stops: persistedStops,
        ledCount: ledCount,
        disableActiveEffect: false
    )
    return  // ✅ Gradient restored with correct brightness
}

// Normal brightness update (no gradient restoration needed)
let stateUpdate = WLEDStateUpdate(bri: brightness)
```

---

## Changes Made

### File: `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`

1. **`updateDeviceState()` method** (line ~1368):
   - Added check for persisted gradient
   - Don't send `col` field when gradient exists
   - Only send `on` and `bri` fields
   - Let gradient restoration handle colors

2. **`toggleDevicePower()` method** (line ~1192):
   - Removed 0.1 second delay before gradient restoration
   - Gradient restoration happens immediately after power-on

3. **`updateDeviceBrightness()` method** (line ~1221):
   - Added check for brightness restoration from 0%
   - If restoring from 0% and gradient exists, restore gradient instead of just brightness
   - This ensures colors are correct when brightness comes back

---

## Expected Behavior After Fix

### Power Toggle:
1. User turns device on
2. `updateDeviceState` sends: `{"on": true, "bri": 255}` (no `col` field)
3. WLED preserves existing colors (or uses last known colors)
4. Gradient restoration happens immediately
5. Result: ✅ No color jump - smooth transition to gradient

### Brightness 0% → >0%:
1. User sets brightness to 0%
2. User sets brightness back to >0%
3. `updateDeviceBrightness` detects restoration from 0%
4. Gradient is restored with correct brightness
5. Result: ✅ No color jump - correct gradient colors applied immediately

---

## Testing Recommendations

1. **Power Toggle Test**:
   - Set a gradient with multiple colors
   - Turn device off
   - Turn device on
   - ✅ Verify: No color jump, gradient appears immediately

2. **Brightness Test**:
   - Set a gradient with multiple colors
   - Set brightness to 0%
   - Set brightness back to 100%
   - ✅ Verify: No color jump, gradient colors are correct

3. **Edge Cases**:
   - Device without persisted gradient (should still work with solid color)
   - Multiple rapid power toggles
   - Brightness changes while gradient is active

---

## Alignment with WLED API

✅ **Correct**: Sending only `on` and `bri` when gradient will be restored  
✅ **Correct**: WLED preserves existing colors when `col` is not sent  
✅ **Correct**: Gradient restoration happens immediately after power-on  
✅ **Correct**: Brightness restoration also restores gradient colors  

**Reference**: [WLED GitHub Repository](https://github.com/wled/WLED)

---

## Conclusion

The color jump issue was caused by sending a solid color (`col` field) before gradient restoration. The fix ensures that:

1. When a persisted gradient exists, we don't send `col` field during power/brightness updates
2. Gradient restoration happens immediately (no delay)
3. Brightness restoration from 0% also restores gradient colors

This aligns with WLED's API behavior where colors are preserved when `col` is not sent, allowing smooth gradient restoration without color jumps.


