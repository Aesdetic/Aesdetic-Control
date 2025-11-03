# Widget Extension Setup Guide

This guide explains how to add the Widget Extension target to your Xcode project.

## Files Created

The following widget extension files have been created in `Aesdetic-Control-Widget/`:

- `DeviceControlWidget.swift` - Main widget configuration and timeline provider
- `DeviceWidgetView.swift` - Widget view implementations for all widget families
- `TogglePowerIntent.swift` - App Intents for widget interactions
- `Info.plist` - Widget extension configuration
- `Aesdetic-Control-Widget.entitlements` - App Group entitlements

## Adding the Widget Extension Target in Xcode

### Step 1: Open Xcode Project
Open `Aesdetic-Control.xcodeproj` in Xcode.

### Step 2: Add Widget Extension Target

1. **File → New → Target...**
2. Select **"Widget Extension"** under iOS
3. Click **Next**
4. Configure the target:
   - **Product Name:** `Aesdetic-Control-Widget`
   - **Organization Identifier:** `com.aesdetic`
   - **Bundle Identifier:** `com.aesdetic.Aesdetic-Control-WLED.Widget`
   - **Language:** Swift
   - **Include Configuration Intent:** No (we're using App Intents instead)
5. Click **Finish**

### Step 3: Delete Generated Files

Xcode will generate some default files. Delete these:
- `Aesdetic-Control-Widget/Aesdetic_Control_Widget.swift` (if generated)
- `Aesdetic-Control-Widget/Aesdetic_Control_WidgetBundle.swift` (if generated)

### Step 4: Add Our Widget Files

1. Right-click on the `Aesdetic-Control-Widget` folder in the project navigator
2. Select **"Add Files to 'Aesdetic-Control-Widget'..."**
3. Navigate to `Aesdetic-Control-Widget/` directory
4. Select all files:
   - `DeviceControlWidget.swift`
   - `DeviceWidgetView.swift`
   - `TogglePowerIntent.swift`
   - `Info.plist`
   - `Aesdetic-Control-Widget.entitlements`
5. Ensure **"Copy items if needed"** is checked
6. Ensure **"Aesdetic-Control-Widget"** target is selected
7. Click **Add**

### Step 5: Embed Widget Extension in Main App ⚠️ CRITICAL

**This is the most common reason widgets don't appear!**

1. Select the **Aesdetic-Control** target (main app, NOT the widget)
2. Go to **General** tab
3. Scroll down to **Frameworks, Libraries, and Embedded Content**
4. Click the **"+"** button
5. In the dialog, select **Aesdetic-Control-WidgetExtension.appex**
   - If you don't see it, select **"Add Other..." → "Add Files..."**
   - Navigate to: `DerivedData/[YourBuildPath]/Debug-iphonesimulator/Aesdetic-Control-WidgetExtension.appex`
6. Once added, ensure the **Embed** dropdown is set to **"Embed & Sign"**
7. Verify it appears in the list with **Embed & Sign** status

### Step 5b: Configure Widget Extension Build Settings

1. Select the **Aesdetic-Control-WidgetExtension** target
2. Go to **Build Settings**
3. Set the following:

**General Tab:**
- **Display Name:** `Aesdetic Control Widget`
- **Bundle Identifier:** `com.aesdetic.Aesdetic-Control-WLED.Widget`
- **Deployment Info:** iOS 17.0 or later (for WidgetKit support)
- **App Groups:** Add `group.com.aesdetic.control`

**Signing & Capabilities:**
- Add the **App Groups** capability
- Add the group: `group.com.aesdetic.control`
- Ensure **Development Team** matches the main app

**Info Tab:**
- Set **NSExtension → NSExtensionPointIdentifier** to `com.apple.widgetkit-extension`

**Build Settings Tab:**
- **Product Bundle Identifier:** `com.aesdetic.Aesdetic-Control-WLED.Widget`
- **SWIFT_ACTIVE_COMPILATION_CONDITIONS:** Add `WIDGETKIT` if needed

### Step 6: Update Entitlements

1. Ensure `Aesdetic-Control-Widget.entitlements` includes:
   ```xml
   <key>com.apple.security.application-groups</key>
   <array>
       <string>group.com.aesdetic.control</string>
   </array>
   ```

2. Ensure `Aesdetic-Control.entitlements` (main app) also includes the same App Group.

### Step 7: Update Main App to Listen for Widget Actions

Add to `Aesdetic_ControlApp.swift`:

```swift
.onAppear {
    // ... existing code ...
    
    // Listen for widget intents
    NotificationCenter.default.addObserver(
        forName: NSNotification.Name("WidgetTogglePower"),
        object: nil,
        queue: .main
    ) { notification in
        if let userInfo = notification.userInfo,
           let deviceId = userInfo["deviceId"] as? String,
           let device = deviceControlViewModel.devices.first(where: { $0.id == deviceId }) {
            Task {
                await deviceControlViewModel.toggleDevicePower(device)
            }
        }
    }
    
    NotificationCenter.default.addObserver(
        forName: NSNotification.Name("WidgetSetBrightness"),
        object: nil,
        queue: .main
    ) { notification in
        if let userInfo = notification.userInfo,
           let deviceId = userInfo["deviceId"] as? String,
           let brightness = userInfo["brightness"] as? Int,
           let device = deviceControlViewModel.devices.first(where: { $0.id == deviceId }) {
            Task {
                await deviceControlViewModel.updateDeviceBrightness(device, brightness: brightness)
            }
        }
    }
}
```

### Step 8: Build and Run

1. Select the **Aesdetic-Control** scheme
2. Build the project (`Cmd+B`)
3. Fix any compilation errors
4. Run on simulator or device (`Cmd+R`)

## Testing the Widget

1. After installing the app, add the widget to your Home Screen:
   - Long-press on Home Screen
   - Tap **"+"** button
   - Search for **"Aesdetic Control Widget"**
   - Select widget size and tap **"Add Widget"**

2. For StandBy mode (iOS 18+):
   - The widget should automatically appear when the phone is in StandBy mode
   - Test on a physical device (StandBy requires locked screen)

## Troubleshooting

### Widget not appearing
- Ensure App Groups are configured in both main app and widget extension
- Check that `UserDefaults(suiteName: "group.com.aesdetic.control")` works
- Verify widget target is included in the build scheme

### Widget data not updating
- Check that `WidgetDataSync.shared.syncDevice()` is being called
- Verify App Group UserDefaults are shared correctly
- Check widget timeline refresh policy

### Build errors
- Ensure all widget files are added to the widget target
- Check that `WidgetKit` and `AppIntents` are imported
- Verify deployment target is iOS 17.0 or later

## Next Steps

Once the widget is working:
- Test widget interactions (power toggle, brightness)
- Optimize widget for StandBy mode (PHASE3-15)
- Add Night mode support (PHASE3-16)
- Test on physical devices


