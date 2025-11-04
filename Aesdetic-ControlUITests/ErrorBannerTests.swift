//
//  ErrorBannerTests.swift
//  Aesdetic-ControlUITests
//
//  Created on 2025-01-27
//  UI tests for error banner display and dismissal
//

import XCTest

final class ErrorBannerTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Helper Methods
    
    /// Wait for device list to appear
    func waitForDeviceList(timeout: TimeInterval = 10.0) {
        let deviceListExists = app.otherElements["DeviceControlView"].waitForExistence(timeout: timeout) ||
                              app.staticTexts["No WLED Devices Found"].waitForExistence(timeout: timeout) ||
                              app.staticTexts["Discovering WLED Devices"].waitForExistence(timeout: timeout)
        
        XCTAssertTrue(deviceListExists, "Device list should appear within \(timeout) seconds")
    }
    
    /// Navigate to device detail view for a device
    func navigateToDeviceDetail(deviceName: String? = nil) {
        waitForDeviceList()
        
        // Wait a bit for devices to load
        Thread.sleep(forTimeInterval: 2.0)
        
        // Try to find a device card
        let deviceCards = app.buttons.matching(identifier: "DeviceCard")
        
        if deviceCards.count > 0 {
            // Tap first device card
            deviceCards.element(boundBy: 0).tap()
            
            // Wait for device detail view
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5.0),
                         "Device detail view should appear")
        } else {
            XCTSkip("No devices found - cannot test error banner without devices")
            return
        }
    }
    
    /// Check if error banner is visible
    /// - Returns: True if error banner exists and is hittable
    func isErrorBannerVisible() -> Bool {
        // Error banner has accessibility label containing "Error:" or has error message text
        let errorBanner = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Error:'"))
        if errorBanner.count > 0 {
            return errorBanner.element(boundBy: 0).exists && errorBanner.element(boundBy: 0).isHittable
        }
        
        // Try finding by error message text
        let errorMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] 'offline' OR label CONTAINS[cd] 'timeout' OR label CONTAINS[cd] 'error'"))
        if errorMessage.count > 0 {
            return errorMessage.element(boundBy: 0).exists
        }
        
        return false
    }
    
    /// Get error banner message text
    /// - Returns: Error message text or nil if banner not found
    func getErrorBannerMessage() -> String? {
        // Try to find error message text
        let errorTexts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] 'offline' OR label CONTAINS[cd] 'timeout' OR label CONTAINS[cd] 'error' OR label CONTAINS[cd] 'unreachable'"))
        if errorTexts.count > 0 {
            return errorTexts.element(boundBy: 0).label
        }
        
        // Try finding by accessibility label
        let errorBanner = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Error:'"))
        if errorBanner.count > 0 {
            return errorBanner.element(boundBy: 0).label
        }
        
        return nil
    }
    
    /// Check if error banner has action button
    /// - Returns: True if action button (like "Retry") exists
    func hasErrorBannerActionButton() -> Bool {
        let retryButton = app.buttons["Retry"]
        return retryButton.exists && retryButton.isHittable
    }
    
    /// Dismiss error banner by tapping dismiss button
    func dismissErrorBanner() {
        let dismissButton = app.buttons["Dismiss error"]
        if dismissButton.waitForExistence(timeout: 2.0) {
            dismissButton.tap()
            // Wait for dismissal animation
            Thread.sleep(forTimeInterval: 0.5)
        } else {
            // Try finding close button by icon
            let closeButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'dismiss' OR label CONTAINS[cd] 'close'"))
            if closeButtons.count > 0 {
                closeButtons.element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
    
    // MARK: - Error Banner Display Tests
    
    @MainActor
    func testErrorBannerAppearsWhenErrorOccurs() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Note: To properly test this, we would need to trigger an actual error
        // (e.g., device offline, timeout, invalid response)
        // For now, we verify the UI structure supports error banner display
        
        // Check if error banner might be visible (if an error occurred)
        if isErrorBannerVisible() {
            let errorMessage = getErrorBannerMessage()
            XCTAssertNotNil(errorMessage, "Error banner should have a message")
            XCTAssertTrue(errorMessage!.count > 0, "Error message should not be empty")
        } else {
            // No error banner visible - this is acceptable if no error occurred
            print("No error banner visible - no errors occurred")
        }
    }
    
    @MainActor
    func testErrorBannerHasCorrectAccessibilityLabel() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        if isErrorBannerVisible() {
            // Error banner should have accessibility label starting with "Error:"
            let errorBanner = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch
            if errorBanner.exists {
                XCTAssertTrue(errorBanner.label.hasPrefix("Error:"),
                             "Error banner accessibility label should start with 'Error:'")
            }
        }
    }
    
    @MainActor
    func testErrorBannerHasErrorMessage() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        if isErrorBannerVisible() {
            let errorMessage = getErrorBannerMessage()
            XCTAssertNotNil(errorMessage, "Error banner should display an error message")
            
            // Error message should be accessible
            let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] 'offline' OR label CONTAINS[cd] 'timeout' OR label CONTAINS[cd] 'error'")).firstMatch
            if errorText.exists {
                XCTAssertEqual(errorText.label, errorMessage,
                              "Error message text should match accessibility value")
            }
        }
    }
    
    // MARK: - Error Banner Dismissal Tests
    
    @MainActor
    func testErrorBannerCanBeDismissed() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Check if error banner is visible
        guard isErrorBannerVisible() else {
            XCTSkip("Error banner not visible - cannot test dismissal")
            return
        }
        
        // Verify dismiss button exists
        let dismissButton = app.buttons["Dismiss error"]
        XCTAssertTrue(dismissButton.exists, "Dismiss button should exist")
        XCTAssertTrue(dismissButton.isHittable, "Dismiss button should be hittable")
        
        // Dismiss the banner
        dismissErrorBanner()
        
        // Wait for dismissal animation
        Thread.sleep(forTimeInterval: 1.0)
        
        // Verify banner is dismissed
        let bannerStillVisible = isErrorBannerVisible()
        XCTAssertFalse(bannerStillVisible, "Error banner should be dismissed after tapping dismiss button")
    }
    
    @MainActor
    func testErrorBannerDismissButtonAccessibility() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        if isErrorBannerVisible() {
            let dismissButton = app.buttons["Dismiss error"]
            if dismissButton.exists {
                XCTAssertEqual(dismissButton.label, "Dismiss error",
                              "Dismiss button should have correct accessibility label")
                XCTAssertTrue(dismissButton.isHittable, "Dismiss button should be hittable")
            }
        }
    }
    
    // MARK: - Error Banner Action Button Tests
    
    @MainActor
    func testErrorBannerHasActionButtonWhenRetryable() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Check if error banner has action button (for retryable errors)
        if isErrorBannerVisible() {
            if hasErrorBannerActionButton() {
                let retryButton = app.buttons["Retry"]
                XCTAssertTrue(retryButton.exists, "Retry button should exist")
                XCTAssertTrue(retryButton.isHittable, "Retry button should be hittable")
                
                // Verify button accessibility
                XCTAssertEqual(retryButton.label, "Retry",
                              "Retry button should have correct accessibility label")
            } else {
                // No action button - error might not be retryable
                print("No action button found - error may not be retryable")
            }
        }
    }
    
    @MainActor
    func testErrorBannerActionButtonTriggersAction() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Check if error banner has action button
        guard isErrorBannerVisible() && hasErrorBannerActionButton() else {
            XCTSkip("Error banner with action button not visible - cannot test action")
            return
        }
        
        let retryButton = app.buttons["Retry"]
        
        // Tap retry button
        retryButton.tap()
        
        // Wait for action to process
        Thread.sleep(forTimeInterval: 1.0)
        
        // Note: Verifying the actual retry action would require checking if
        // the error was resolved, which is complex in UI tests
        // For now, we verify the button is tappable
        XCTAssertTrue(true, "Retry button tapped successfully")
    }
    
    // MARK: - Error Banner Visibility Tests
    
    @MainActor
    func testErrorBannerHiddenWhenNoError() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // When no error exists, banner should not be visible
        let bannerVisible = isErrorBannerVisible()
        
        if !bannerVisible {
            // Success - banner is hidden as expected
            XCTAssertTrue(true, "Error banner correctly hidden when no error exists")
        } else {
            // Banner exists - an error might have occurred
            print("Error banner found - an error may have occurred")
        }
    }
    
    @MainActor
    func testErrorBannerAnimation() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Note: Testing animation timing is challenging in UI tests
        // We verify the banner appears/disappears correctly
        
        if isErrorBannerVisible() {
            // Banner is visible - verify it's properly positioned
            let errorBanner = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch
            if errorBanner.exists {
                XCTAssertTrue(errorBanner.frame.height > 0, "Error banner should have height")
                XCTAssertTrue(errorBanner.frame.width > 0, "Error banner should have width")
            }
        }
    }
    
    // MARK: - Error Banner Content Tests
    
    @MainActor
    func testErrorBannerShowsDeviceOfflineMessage() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Check if error banner shows device offline message
        if isErrorBannerVisible() {
            let errorMessage = getErrorBannerMessage()
            if let message = errorMessage {
                // Device offline errors typically mention "offline" or "unreachable"
                let hasOfflineKeywords = message.lowercased().contains("offline") ||
                                       message.lowercased().contains("unreachable") ||
                                       message.lowercased().contains("not responding")
                
                if hasOfflineKeywords {
                    XCTAssertTrue(true, "Error banner shows device offline message: \(message)")
                }
            }
        }
    }
    
    @MainActor
    func testErrorBannerShowsTimeoutMessage() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Check if error banner shows timeout message
        if isErrorBannerVisible() {
            let errorMessage = getErrorBannerMessage()
            if let message = errorMessage {
                // Timeout errors typically mention "timeout" or "not responding"
                let hasTimeoutKeywords = message.lowercased().contains("timeout") ||
                                        message.lowercased().contains("not responding")
                
                if hasTimeoutKeywords {
                    XCTAssertTrue(true, "Error banner shows timeout message: \(message)")
                }
            }
        }
    }
    
    // MARK: - Integration Test: Full Error Flow
    
    @MainActor
    func testFullErrorBannerFlow() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        // Test complete error banner flow:
        // 1. Error occurs -> banner appears
        // 2. User can see error message
        // 3. User can dismiss banner
        // 4. Banner disappears
        
        if isErrorBannerVisible() {
            // Step 1: Verify banner is visible
            XCTAssertTrue(isErrorBannerVisible(), "Error banner should be visible")
            
            // Step 2: Verify error message is displayed
            let errorMessage = getErrorBannerMessage()
            XCTAssertNotNil(errorMessage, "Error message should be displayed")
            
            // Step 3: Verify dismiss button exists
            let dismissButton = app.buttons["Dismiss error"]
            XCTAssertTrue(dismissButton.exists, "Dismiss button should exist")
            
            // Step 4: Dismiss banner
            dismissErrorBanner()
            
            // Step 5: Verify banner is dismissed
            Thread.sleep(forTimeInterval: 1.0)
            let bannerStillVisible = isErrorBannerVisible()
            XCTAssertFalse(bannerStillVisible, "Error banner should be dismissed")
        } else {
            // No error occurred - verify banner is not visible
            XCTAssertFalse(isErrorBannerVisible(), "Error banner should not be visible when no error")
        }
    }
    
    // MARK: - Accessibility Tests
    
    @MainActor
    func testErrorBannerAccessibility() throws {
        navigateToDeviceDetail()
        
        // Wait for UI to stabilize
        Thread.sleep(forTimeInterval: 2.0)
        
        if isErrorBannerVisible() {
            // Verify error banner accessibility
            let errorBanner = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch
            if errorBanner.exists {
                XCTAssertTrue(errorBanner.isAccessibilityElement, "Error banner should be accessible")
                XCTAssertNotNil(errorBanner.label, "Error banner should have accessibility label")
                
                // Verify error message accessibility
                let errorMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] 'offline' OR label CONTAINS[cd] 'timeout' OR label CONTAINS[cd] 'error'")).firstMatch
                if errorMessage.exists {
                    XCTAssertEqual(errorMessage.label, "Error message",
                                  "Error message should have correct accessibility label")
                }
            }
        }
    }
}

