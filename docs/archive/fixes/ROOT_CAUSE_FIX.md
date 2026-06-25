# Root Cause Fix - Atomic Power-On/Brightness with Gradient Colors

## Root Cause Identified

**The Problem**: We were making **TWO separate API calls**:
1. First: `{"on": true, "bri": 255}` or `{"bri": brightness}`
2. Then: `{"seg": [{"i": [...]}]}` (per-LED colors)

This created a **gap** where WLED would:
- Process the first call
- Show its restored state (colors from memory)
- Then process the second call with gradient colors
- Result: **Visible color flash**

## The Solution: Atomic API Calls

**Include `on` and `bri` in the FIRST chunk of per-LED upload**, so everything happens in **ONE atomic operation**:

```json
{
  "on": true,
  "bri": 255,
  "seg": [{
    "id": 0,
    "i": [0, "RRGGBB", "RRGGBB", ...]
  }]
}
```

This ensures WLED receives power-on/brightness **ALONG WITH** gradient colors in the **SAME API call**, preventing any gap where restored colors can appear.

---

## Changes Made

### 1. Added `on` field to `ColorIntent`
- **File**: `Aesdetic-Control/ColorEngine/ColorIntent.swift`
- **Change**: Added `var on: Bool? = nil` to support power-on in gradient application

### 2. Updated `buildSegmentPixelBodies` to include `on`/`bri` in first chunk
- **File**: `Aesdetic-Control/Services/WLEDAPIService.swift`
- **Change**: 
  - Added `on: Bool?` and `brightness: Int?` parameters
  - Include `on` and `bri` in the **first chunk only** (line ~720)
  - Updated MTU calculation to account for `on`/`bri` overhead

### 3. Updated `setSegmentPixels` to accept `on`/`brightness`
- **File**: `Aesdetic-Control/Services/WLEDAPIService.swift`
- **Change**: Added `on: Bool?` and `brightness: Int?` parameters, passed to `buildSegmentPixelBodies`

### 4. Updated `ColorPipeline` to pass `on`/`brightness` to `setSegmentPixels`
- **File**: `Aesdetic-Control/ColorEngine/ColorPipeline.swift`
- **Change**: Extract `on` and `brightness` from `ColorIntent` and pass to `setSegmentPixels`

### 5. Updated `applyGradientStopsAcrossStrip` to accept `on` parameter
- **File**: `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
- **Change**: 
  - Added `on: Bool?` parameter
  - Set `intent.on = onValue` when provided
  - Set `intent.brightness = brightness` when provided

### 6. Updated `toggleDevicePower` to include `on` in gradient application
- **File**: `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`
- **Change**: Pass `on: true` to `applyGradientStopsAcrossStrip` when turning on with gradient

### 7. Created `postRawState` helper function
- **File**: `Aesdetic-Control/Services/WLEDAPIService.swift`
- **Change**: Created private `postRawState(for:body:)` function to send raw JSON dictionaries for per-LED uploads

---

## How It Works Now

### Power-On Flow:
1. User turns device on
2. `toggleDevicePower()` detects gradient exists
3. **Skip separate `updateDeviceState` call**
4. Call `applyGradientStopsAcrossStrip(..., on: true, brightness: 255)`
5. `ColorPipeline` creates `ColorIntent` with `on: true` and `brightness: 255`
6. `setSegmentPixels` includes `on` and `bri` in **first chunk**:
   ```json
   {
     "on": true,
     "bri": 255,
     "seg": [{"id": 0, "i": [0, "RRGGBB", ...]}]
   }
   ```
7. WLED receives **everything in one call** - no gap, no color flash!

### Brightness Adjustment Flow:
1. User adjusts brightness slider
2. `updateDeviceBrightness()` detects gradient exists
3. Call `applyGradientStopsAcrossStrip(..., brightness: newBrightness)`
4. `ColorPipeline` creates `ColorIntent` with `brightness: newBrightness`
5. `setSegmentPixels` includes `bri` in **first chunk**:
   ```json
   {
     "bri": 128,
     "seg": [{"id": 0, "i": [0, "RRGGBB", ...]}]
   }
   ```
6. WLED receives brightness **ALONG WITH** gradient colors - colors remain visible!

---

## Expected Behavior After Fix

✅ **Power Toggle**: No color flash - gradient appears immediately with power-on  
✅ **Brightness Adjustment**: Colors remain visible at all brightness levels  
✅ **Atomic Operations**: Power-on/brightness and gradient colors sent in same API call  

---

## Alignment with WLED API

✅ **Correct**: WLED supports `on`, `bri`, and `seg` in the same JSON request  
✅ **Correct**: Including `on`/`bri` in first chunk prevents restored colors from appearing  
✅ **Correct**: Per-LED colors (`seg[].i[]`) work correctly with `on`/`bri` in same request  

**Reference**: [WLED GitHub Repository](https://github.com/wled/WLED)

---

## Testing Recommendations

1. **Power Toggle Test**:
   - Set a multi-color gradient
   - Turn device off
   - Turn device on
   - ✅ Verify: No color flash, gradient appears immediately

2. **Brightness Adjustment Test**:
   - Set a multi-color gradient
   - Adjust brightness slider (50%, 100%, 25%, etc.)
   - ✅ Verify: Colors remain visible at all brightness levels

3. **Brightness 0% → >0% Test**:
   - Set a multi-color gradient
   - Set brightness to 0%
   - Set brightness back to 100%
   - ✅ Verify: Gradient colors are correct immediately

---

## Conclusion

The root cause was **two separate API calls creating a gap**. The fix is to **combine power-on/brightness with gradient colors in a single atomic API call**, preventing WLED from showing restored colors before gradient is applied.

This ensures smooth, instant gradient restoration without color flashes or disappearing colors.


