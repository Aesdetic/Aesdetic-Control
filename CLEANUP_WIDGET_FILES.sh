#!/bin/bash

# Script to clean up Xcode-generated widget files
# Run this from the project root directory

WIDGET_DIR="Aesdetic-Control-Widget"

echo "🧹 Cleaning up generated widget files..."

# Files to delete (Xcode generated these, we have our own)
FILES_TO_DELETE=(
    "Aesdetic_Control_Widget.swift"
    "Aesdetic_Control_WidgetBundle.swift"
    "Aesdetic_Control_WidgetControl.swift"
    "Aesdetic_Control_WidgetLiveActivity.swift"
    "AppIntent.swift"
)

for file in "${FILES_TO_DELETE[@]}"; do
    if [ -f "$WIDGET_DIR/$file" ]; then
        echo "  ❌ Deleting $file"
        rm "$WIDGET_DIR/$file"
    else
        echo "  ⏭️  $file not found (already deleted or never existed)"
    fi
done

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📝 Next steps:"
echo "   1. In Xcode, ensure these files are added to the Aesdetic-Control-Widget target:"
echo "      - DeviceControlWidget.swift"
echo "      - DeviceWidgetView.swift"
echo "      - TogglePowerIntent.swift"
echo "      - Info.plist"
echo "      - Aesdetic-Control-Widget.entitlements"
echo ""
echo "   2. Configure App Groups capability:"
echo "      - Select Aesdetic-Control-Widget target"
echo "      - Go to Signing & Capabilities"
echo "      - Add 'App Groups' capability"
echo "      - Add group: group.com.aesdetic.control"
echo ""
echo "   3. Build and test! 🚀"


