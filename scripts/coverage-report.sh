#!/bin/bash
# Code Coverage Analysis Script for Aesdetic-Control
# Generates detailed coverage reports for models/services and ViewModels

set -e

PROJECT_NAME="Aesdetic-Control"
SCHEME="Aesdetic-Control"
DESTINATION="platform=iOS Simulator,name=iPhone 16 Pro"

echo "📊 Generating Code Coverage Report for $PROJECT_NAME"
echo "=================================================="

# Run tests with coverage
echo "Running unit tests with coverage..."
xcodebuild test \
  -project ${PROJECT_NAME}.xcodeproj \
  -scheme ${SCHEME} \
  -destination "${DESTINATION}" \
  -only-testing:Aesdetic-ControlTests \
  -enableCodeCoverage YES \
  -resultBundlePath ./coverage-results.xcresult \
  2>&1 | tail -5

# Find the latest xcresult bundle
XCRESULT=$(find ~/Library/Developer/Xcode/DerivedData -name "*.xcresult" -type d -mtime -1 2>/dev/null | head -1)

if [ -z "$XCRESULT" ]; then
  echo "❌ No test results found. Run tests first."
  exit 1
fi

echo ""
echo "📈 Coverage Summary"
echo "-------------------"
xcrun xccov view --report --only-targets "$XCRESULT" 2>&1 | grep -E "(Aesdetic-Control|Target)"

echo ""
echo "📁 Detailed File Coverage"
echo "-------------------------"
echo ""
echo "Models:"
xcrun xccov view --report --files-for-target Aesdetic-Control "$XCRESULT" 2>&1 | \
  grep -i "Models" | \
  awk '{printf "  %-60s %s\n", $1, $NF}' || echo "  No models files found"

echo ""
echo "Services:"
xcrun xccov view --report --files-for-target Aesdetic-Control "$XCRESULT" 2>&1 | \
  grep -i "Services" | \
  awk '{printf "  %-60s %s\n", $1, $NF}' || echo "  No services files found"

echo ""
echo "ViewModels:"
xcrun xccov view --report --files-for-target Aesdetic-Control "$XCRESULT" 2>&1 | \
  grep -i "ViewModels" | \
  awk '{printf "  %-60s %s\n", $1, $NF}' || echo "  No ViewModels files found"

echo ""
echo "Full file list (all targets):"
xcrun xccov view --report --files-for-target Aesdetic-Control "$XCRESULT" 2>&1 | \
  head -100 | \
  awk '{printf "  %-60s %s\n", $1, $NF}'

echo ""
echo "✅ Coverage report complete!"
echo ""
echo "Target Coverage Goals:"
echo "  • Models/Services: 80%+"
echo "  • ViewModels: 60%+"
echo ""
echo "Current Status: See details above"

