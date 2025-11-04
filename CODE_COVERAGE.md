# Code Coverage Analysis

## Current Coverage Status

**Overall App Coverage: 13.20% (4,629 / 35,060 lines)**

### Coverage by Target

| Target | Coverage | Lines Covered | Total Lines |
|--------|----------|---------------|-------------|
| Aesdetic-Control.app | 13.20% | 4,629 | 35,060 |
| Aesdetic-ControlTests.xctest | 93.02% | 1,079 | 1,160 |
| Aesdetic-ControlUITests.xctest | 0.00% | 0 | 2,200 |
| Widget Extension | 0.00% | 0 | 746 |

## Coverage Goals

### Target Coverage (PHASE4-11)

- **Models/Services: 80%+** ⚠️ **Current: ~13%**
- **ViewModels: 60%+** ⚠️ **Current: ~13%**

## Coverage Analysis

### Current State

The app currently has **13.20% code coverage**, which is below the target thresholds. This is expected for an app in active development, but needs improvement before production release.

### Test Coverage Breakdown

1. **Unit Tests (Aesdetic-ControlTests)**: 93.02% coverage
   - Excellent test code coverage
   - Tests are well-written and comprehensive

2. **App Code (Aesdetic-Control.app)**: 13.20% coverage
   - **Models**: Partial coverage (WLEDAPIModels, WLEDCapabilities tested)
   - **Services**: Partial coverage (WLEDAPIService, CapabilityDetector tested)
   - **ViewModels**: Minimal coverage (DeviceControlViewModel partially tested)
   - **Views**: No coverage (UI code not tested in unit tests)

3. **UI Tests**: 0% coverage
   - UI tests verify functionality but don't contribute to code coverage metrics
   - Coverage is measured at the unit test level

## Areas Needing More Coverage

### Models (Target: 80%+)
- ✅ `WLEDCapabilities.swift` - Well tested
- ✅ `WLEDAPIModels.swift` - Well tested
- ⚠️ `GradientModels.swift` - Needs more tests
- ⚠️ `Automation.swift` - Needs tests
- ⚠️ `Scene.swift` - Needs tests
- ⚠️ `CoreDataEntities.swift` - Needs tests

### Services (Target: 80%+)
- ✅ `CapabilityDetector.swift` - Well tested
- ✅ `WLEDAPIService.swift` - Well tested
- ⚠️ `WLEDWebSocketManager.swift` - Needs tests
- ⚠️ `WLEDDiscoveryService.swift` - Needs tests
- ⚠️ `AutomationStore.swift` - Needs tests
- ⚠️ `CoreDataManager.swift` - Needs tests
- ⚠️ `ResourceManager.swift` - Needs tests
- ⚠️ `WidgetDataSync.swift` - Needs tests

### ViewModels (Target: 60%+)
- ⚠️ `DeviceControlViewModel.swift` - Partially tested (needs more)
- ⚠️ `DashboardViewModel.swift` - Needs tests
- ⚠️ `AutomationViewModel.swift` - Needs tests
- ⚠️ `WellnessViewModel.swift` - Needs tests

## How to Generate Coverage Reports

### Using the Coverage Script

```bash
./scripts/coverage-report.sh
```

### Manual Coverage Generation

```bash
# Run tests with coverage
xcodebuild test \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Aesdetic-ControlTests \
  -enableCodeCoverage YES \
  -resultBundlePath ./coverage-results.xcresult

# View coverage report
xcrun xccov view --report --only-targets ./coverage-results.xcresult

# View coverage for specific files
xcrun xccov view --report --files-for-target Aesdetic-Control ./coverage-results.xcresult | grep -E "(Models|Services|ViewModels)"
```

### Viewing Coverage in Xcode

1. Run tests with coverage enabled
2. Open the test navigator (⌘6)
3. Click on a test result
4. Coverage data appears in the editor gutter
5. Use the Coverage Report (⌘⇧⌘C) to see detailed metrics

## CI/CD Integration

Coverage reports are automatically generated in the CI/CD pipeline:

1. **GitHub Actions**: Coverage reports are uploaded as artifacts
2. **Codecov** (optional): Automatic coverage tracking and PR comments
3. **Coverage Thresholds**: Can be configured to fail builds if coverage drops below thresholds

## Next Steps to Improve Coverage

1. **Add Unit Tests for Untested Services**
   - `WLEDWebSocketManager` - WebSocket connection handling
   - `WLEDDiscoveryService` - Network discovery logic
   - `AutomationStore` - Automation persistence
   - `CoreDataManager` - Core Data operations

2. **Add Unit Tests for ViewModels**
   - `DashboardViewModel` - Dashboard state management
   - `AutomationViewModel` - Automation logic
   - `WellnessViewModel` - Wellness features

3. **Add Tests for Models**
   - `GradientModels` - Gradient manipulation
   - `Automation` - Automation model validation
   - `Scene` - Scene model validation

4. **Mock External Dependencies**
   - Network requests (URLSession)
   - Core Data contexts
   - UserDefaults
   - File system operations

5. **Increase ViewModel Test Coverage**
   - Test state management
   - Test error handling
   - Test async operations
   - Test data transformations

## Coverage Best Practices

- **Focus on Critical Paths**: Test core business logic first
- **Mock External Dependencies**: Don't test network/disk operations
- **Test Error Cases**: Cover error handling and edge cases
- **Maintain Test Quality**: Keep tests simple and focused
- **Regular Coverage Reviews**: Check coverage regularly, not just before release

## Notes

- **UI Code Coverage**: UI code (SwiftUI views) typically has low coverage as it's tested via UI tests
- **Coverage vs Quality**: High coverage doesn't guarantee quality - focus on meaningful tests
- **Integration Tests**: Some features (like network discovery) may need integration tests rather than unit tests
- **Test Maintainability**: Ensure tests are maintainable - avoid brittle tests that break on refactoring


