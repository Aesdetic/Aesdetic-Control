# Widget Troubleshooting Guide

## Issue: Widget Not Appearing in Widget Gallery (iOS 26 Beta)

### Critical Checks:

1. **Widget Extension Must Be Embedded in Main App**
   - In Xcode: Select **Aesdetic-Control** target → **General** tab
   - Scroll to **Frameworks, Libraries, and Embedded Content**
   - Verify **Aesdetic-Control-WidgetExtension.appex** is listed
   - If missing, add it manually:
     - Click "+" → Select **Aesdetic-Control-WidgetExtension** product
     - Set **Embed** to **"Embed & Sign"**

2. **Both App and Widget Must Be Installed**
   - Build and install BOTH targets:
     - Main app (Aesdetic-Control)
     - Widget extension (Aesdetic-Control-WidgetExtension)
   - On physical device: Both must be installed for widgets to appear

3. **App Groups Must Match Exactly**
   - Main app: `Aesdetic-Control.entitlements` → `group.com.aesdetic.control`
   - Widget: `Aesdetic-Control-Widget.entitlements` → `group.com.aesdetic.control`
   - Both MUST use the exact same group ID

4. **Widget Bundle Registration**
   - ✅ `@main struct DeviceControlWidgetBundle` is defined
   - ✅ Bundle is in the widget extension target
   - Verify in Xcode: Check file membership in target

5. **Build Configuration**
   - Widget target must be included in the build scheme
   - Check: **Product → Scheme → Edit Scheme → Build**
   - Ensure **Aesdetic-Control-WidgetExtension** is checked and builds

### iOS 26 Beta Specific Notes:

- Widgets might need explicit registration
- Try: Uninstall app completely, then reinstall
- Restart device after installation
- Check Settings → Privacy → Local Network (widget needs this)

### Verification Steps:

1. **Check Widget Extension is Built:**
   ```bash
   xcodebuild -project Aesdetic-Control.xcodeproj \
     -scheme Aesdetic-Control \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     build 2>&1 | grep "Aesdetic-Control-WidgetExtension"
   ```

2. **Verify Widget is Embedded:**
   - Product → Archive
   - Check that widget extension appears in archive contents

3. **Test Widget Availability:**
   - Install app on device
   - Long-press home screen → "+" → Search for your app name
   - Widget should appear under your app's widget collection

### Quick Fixes:

**Fix 1: Reinstall App**
1. Delete app from device/simulator
2. Clean build folder (Cmd+Shift+K)
3. Build and install fresh copy
4. Restart device/simulator

**Fix 2: Verify Embedding**
1. Select **Aesdetic-Control** target in Xcode
2. **General** tab → **Frameworks, Libraries, and Embedded Content**
3. If widget extension missing, add it manually
4. Set to **"Embed & Sign"**

**Fix 3: Check Code Signing**
1. Ensure both targets have same Development Team
2. Widget extension must be signed with same team as main app
3. Check **Signing & Capabilities** for both targets

### Debug Widget Availability:

Add to `DeviceControlWidgetBundle`:
```swift
@main
struct DeviceControlWidgetBundle: WidgetBundle {
    init() {
        print("🚀 Widget bundle initialized!")
    }
    
    var body: some Widget {
        DeviceControlWidget()
    }
}
```

Check console logs when adding widget to see if bundle loads.

