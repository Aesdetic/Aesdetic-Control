# Quick Fix: Widget Not Appearing (iOS 26 Beta)

## Most Likely Issue: Widget Extension Not Embedded

When widgets don't appear, it's usually because the widget extension isn't embedded in the main app target.

## ✅ Quick Fix Steps:

### 1. Embed Widget Extension in Main App

1. **Open Xcode**
2. Select **Aesdetic-Control** target (main app - blue icon)
3. Go to **General** tab
4. Scroll to **Frameworks, Libraries, and Embedded Content** section
5. Click the **"+"** button at the bottom
6. In the file picker:
   - Navigate to your project folder
   - Look for: `Aesdetic-Control-WidgetExtension.appex` 
   - OR: Select **"Add Other..." → "Add Files..."**
   - Navigate to: `DerivedData/[BuildFolder]/Products/Debug-iphonesimulator/Aesdetic-Control-WidgetExtension.appex`
7. Once added, **CRITICAL**: Set the **Embed** dropdown to **"Embed & Sign"** (NOT "Embed Without Signing")
   - If you see "Embed Without Signing", click the dropdown and change it to **"Embed & Sign"**
8. Verify it shows in the list with **"Embed & Sign"** status

### 2. Clean and Rebuild

1. **Product → Clean Build Folder** (Cmd+Shift+K)
2. **Product → Build** (Cmd+B)
3. **Product → Run** (Cmd+R) on your device/simulator

### 3. Uninstall and Reinstall

1. Delete the app completely from your device/simulator
2. Rebuild and install fresh
3. Restart your device (iOS 26 beta may need this)

### 4. Check Widget Availability

After reinstalling:
1. Long-press Home Screen
2. Tap **"+"** in top-left
3. Search for **"Aesdetic"** or **"WLED"**
4. Widget should appear under your app name

## Alternative: Verify via Build Log

If embedding doesn't work, check that the widget extension builds:

```bash
cd /Users/ryan/Documents/Aesdetic-Control
xcodebuild -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -i "widget\|embed"
```

Look for:
- `Aesdetic-Control-WidgetExtension.appex` being built
- Embedding messages

## Still Not Working?

1. **Check App Groups Match:**
   - Main app: `group.com.aesdetic.control`
   - Widget: `group.com.aesdetic.control`
   - Must be EXACTLY the same

2. **Verify Code Signing:**
   - Both targets must use same Development Team
   - Both must be signed (not "Automatically manage signing" with errors)

3. **iOS 26 Beta Notes:**
   - Widget discovery may be slower
   - Try restarting device after installation
   - Check Settings → Privacy → Local Network (widget needs this permission)

4. **Check Console Logs:**
   - Run app with Xcode console open
   - Look for widget bundle initialization messages
   - Add debug print to `DeviceControlWidgetBundle.init()` to verify it loads

