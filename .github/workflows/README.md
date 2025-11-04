# CI/CD Pipeline for Aesdetic-Control iOS App

This GitHub Actions workflow automatically runs tests and builds on every commit and pull request.

## Workflow Overview

The CI/CD pipeline consists of several jobs that run in parallel:

1. **Unit Tests** - Runs all unit tests (`Aesdetic-ControlTests`)
2. **UI Tests** - Runs all UI tests (`Aesdetic-ControlUITests`)
3. **Build Verification** - Verifies the project builds successfully
4. **Code Quality Check** - Runs linting (if SwiftLint is configured)
5. **Test Summary** - Generates a summary of all test results

## Jobs

### Unit Tests Job
- **Triggers**: Push to main/develop, Pull Requests
- **Actions**: 
  - Runs all unit test suites
  - Generates code coverage reports
  - Uploads test results as artifacts
  - Uploads coverage to Codecov (if configured)

### UI Tests Job
- **Triggers**: Push to main/develop, Pull Requests
- **Actions**:
  - Boots iOS Simulator
  - Runs all UI test suites
  - Generates UI test coverage reports
  - Uploads test results as artifacts

### Build Verification Job
- **Triggers**: Push to main/develop, Pull Requests
- **Actions**:
  - Builds the project without running tests
  - Verifies build artifacts are created
  - Ensures project compiles successfully

### Code Quality Check Job
- **Triggers**: Push to main/develop, Pull Requests
- **Actions**:
  - Runs SwiftLint (if installed)
  - Verifies project structure
  - Checks code quality

## Artifacts

Test results and coverage reports are uploaded as GitHub Actions artifacts:
- `unit-test-results` - Unit test results and coverage
- `ui-test-results` - UI test results and coverage

Artifacts are retained for 30 days and can be downloaded from the Actions tab.

## Coverage Reports

Code coverage is generated for both unit tests and UI tests. Coverage reports are:
- Saved as `.xcresult` bundles
- Exported as text reports
- Uploaded to Codecov (if configured with repository secret)

## Setup Instructions

### Prerequisites
- GitHub repository with Actions enabled
- Xcode project configured with test targets
- (Optional) Codecov account for coverage tracking

### Configuration

1. **Enable GitHub Actions**: Ensure Actions are enabled in your repository settings

2. **Add Codecov (Optional)**:
   - Sign up at https://codecov.io
   - Add repository secret: `CODECOV_TOKEN`
   - Coverage reports will be automatically uploaded

3. **Customize Workflow**:
   - Update simulator names/versions if needed
   - Adjust timeout values based on your test suite size
   - Add additional steps as needed

## Manual Triggering

The workflow can be manually triggered from the Actions tab:
1. Go to Actions → CI/CD Pipeline
2. Click "Run workflow"
3. Select branch and click "Run workflow"

## Troubleshooting

### Tests Fail in CI but Pass Locally
- Ensure simulator is properly booted
- Check timeout values are sufficient
- Verify all dependencies are cached correctly

### Build Fails
- Verify Xcode version compatibility
- Check that all SPM dependencies resolve
- Ensure project structure is correct

### Coverage Reports Not Generated
- Verify `-enableCodeCoverage YES` flag is set
- Check that test targets are properly configured
- Ensure xcresult bundles are created

## Status Badge

Add this to your README.md to show CI status:

```markdown
![CI/CD Pipeline](https://github.com/Aesdetic/Aesdetic-Control/workflows/CI/CD%20Pipeline/badge.svg)
```


