# CI/CD Pipeline Status

[![CI/CD Pipeline](https://github.com/Aesdetic/Aesdetic-Control/workflows/CI/CD%20Pipeline/badge.svg)](https://github.com/Aesdetic/Aesdetic-Control/actions)

This project uses GitHub Actions for continuous integration and deployment.

## Automated Testing

Every commit and pull request automatically triggers:

- ✅ **Unit Tests** - All unit test suites (`Aesdetic-ControlTests`)
- ✅ **UI Tests** - All UI test suites (`Aesdetic-ControlUITests`)
- ✅ **Build Verification** - Ensures project compiles successfully
- ✅ **Code Quality** - Linting and structure verification

## Test Coverage

Code coverage reports are generated for each test run and can be viewed in the Actions artifacts.

## Running Tests Locally

```bash
# Run all unit tests
xcodebuild test \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Aesdetic-ControlTests

# Run all UI tests
xcodebuild test \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Aesdetic-ControlUITests

# Run specific test suite
xcodebuild test \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Aesdetic-ControlTests/CapabilityDetectorTests
```

## Viewing Test Results

1. Go to the [Actions tab](https://github.com/Aesdetic/Aesdetic-Control/actions) on GitHub
2. Click on a workflow run
3. Download artifacts to view detailed test results and coverage reports

## Workflow Details

The CI/CD pipeline runs 5 jobs in parallel:

1. **Unit Tests** (30 min timeout) - Runs all unit test suites with code coverage
2. **UI Tests** (45 min timeout) - Runs all UI test suites with code coverage
3. **Build Verification** (20 min timeout) - Verifies project builds successfully
4. **Code Quality** (10 min timeout) - Runs linting and structure checks
5. **Test Summary** - Aggregates results from all test jobs

See [.github/workflows/README.md](.github/workflows/README.md) for detailed documentation.


