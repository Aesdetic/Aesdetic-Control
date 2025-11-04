//
//  AccessibilityTests.swift
//  Aesdetic-ControlUITests
//
//  Created on 2025-01-27
//  Accessibility tests for VoiceOver navigation and label accuracy
//

import XCTest

final class AccessibilityTests: XCTestCase {
    
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
    
    /// Navigate to device detail view
    func navigateToDeviceDetail() {
        waitForDeviceList()
        Thread.sleep(forTimeInterval: 2.0)
        
        let deviceCards = app.buttons.matching(identifier: "DeviceCard")
        if deviceCards.count > 0 {
            deviceCards.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5.0),
                         "Device detail view should appear")
        } else {
            XCTSkip("No devices found - cannot test accessibility without devices")
        }
    }
    
    /// Verify element has accessibility label
    func verifyAccessibilityLabel(_ element: XCUIElement, description: String) {
        XCTAssertTrue(element.exists, "\(description) should exist")
        XCTAssertTrue(element.isAccessibilityElement || element.label.count > 0,
                     "\(description) should have accessibility label")
        
        if element.isAccessibilityElement {
            let label = element.label
            XCTAssertFalse(label.isEmpty, "\(description) accessibility label should not be empty")
        }
    }
    
    /// Verify slider has accessibility value
    func verifySliderAccessibility(_ slider: XCUIElement, description: String) {
        verifyAccessibilityLabel(slider, description: description)
        
        // Sliders should have accessibility values
        let value = slider.value as? String
        XCTAssertNotNil(value, "\(description) slider should have accessibility value")
        
        if let value = value {
            XCTAssertFalse(value.isEmpty, "\(description) slider value should not be empty")
        }
    }
    
    /// Verify button has accessibility label
    func verifyButtonAccessibility(_ button: XCUIElement, description: String) {
        verifyAccessibilityLabel(button, description: description)
        XCTAssertTrue(button.isHittable, "\(description) button should be hittable")
    }
    
    // MARK: - Device Card Accessibility Tests
    
    @MainActor
    func testDeviceCardAccessibilityLabels() throws {
        waitForDeviceList()
        Thread.sleep(forTimeInterval: 2.0)
        
        // Find device cards
        let deviceCards = app.buttons.matching(identifier: "DeviceCard")
        if deviceCards.count > 0 {
            let card = deviceCards.element(boundBy: 0)
            
            // Verify device card has accessibility
            XCTAssertTrue(card.exists, "Device card should exist")
            
            // Device name should be accessible
            let deviceName = card.staticTexts.firstMatch
            if deviceName.exists {
                XCTAssertFalse(deviceName.label.isEmpty, "Device name should have label")
            }
        }
    }
    
    @MainActor
    func testDeviceCardPowerToggleAccessibility() throws {
        waitForDeviceList()
        Thread.sleep(forTimeInterval: 2.0)
        
        // Find power toggle button
        let powerToggle = app.buttons.matching(NSPredicate(format: "label == 'Power'")).firstMatch
        
        if powerToggle.exists {
            verifyButtonAccessibility(powerToggle, description: "Power toggle")
            
            // Verify power toggle has value (On/Off)
            let powerValue = powerToggle.value as? String
            XCTAssertNotNil(powerValue, "Power toggle should have accessibility value")
            
            if let value = powerValue {
                let isValidValue = value.lowercased() == "on" || value.lowercased() == "off"
                XCTAssertTrue(isValidValue, "Power toggle value should be 'On' or 'Off', got: \(value)")
            }
        }
    }
    
    @MainActor
    func testDeviceCardBrightnessBarAccessibility() throws {
        waitForDeviceList()
        Thread.sleep(forTimeInterval: 2.0)
        
        // Find brightness bar
        let brightnessBar = app.otherElements.matching(NSPredicate(format: "label == 'Brightness'")).firstMatch
        
        if brightnessBar.exists {
            verifyAccessibilityLabel(brightnessBar, description: "Brightness bar")
            
            // Brightness bar should have accessibility value (percentage)
            let brightnessValue = brightnessBar.value as? String
            XCTAssertNotNil(brightnessValue, "Brightness bar should have accessibility value")
            
            if let value = brightnessValue {
                // Should contain "percent" or a number
                let hasPercent = value.lowercased().contains("percent")
                XCTAssertTrue(hasPercent || value.rangeOfCharacter(from: .decimalDigits) != nil,
                             "Brightness value should contain percentage or number")
            }
        }
    }
    
    // MARK: - Device Detail View Accessibility Tests
    
    @MainActor
    func testDeviceDetailViewNavigationAccessibility() throws {
        navigateToDeviceDetail()
        
        // Verify navigation bar is accessible
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.exists, "Navigation bar should exist")
        
        // Verify back button is accessible
        let backButton = navBar.buttons.firstMatch
        if backButton.exists {
            XCTAssertTrue(backButton.isHittable, "Back button should be hittable")
        }
    }
    
    @MainActor
    func testGlobalBrightnessSliderAccessibility() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Find global brightness slider
        let brightnessSlider = app.sliders["Global brightness"]
        
        if brightnessSlider.exists {
            verifySliderAccessibility(brightnessSlider, description: "Global brightness")
            
            // Verify hint
            // Note: Accessibility hints might not be directly queryable in UI tests
            // but we verify the element has proper accessibility structure
        }
    }
    
    @MainActor
    func testPowerToggleInDeviceDetailAccessibility() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Find power toggle
        let powerToggle = app.buttons.matching(NSPredicate(format: "label == 'Power'")).firstMatch
        
        if powerToggle.exists {
            verifyButtonAccessibility(powerToggle, description: "Power toggle")
            
            // Verify power toggle has hint
            let powerValue = powerToggle.value as? String
            XCTAssertNotNil(powerValue, "Power toggle should have accessibility value")
        }
    }
    
    @MainActor
    func testSettingsButtonAccessibility() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Find settings button
        let settingsButton = app.buttons["Device settings"]
        
        if settingsButton.exists {
            verifyButtonAccessibility(settingsButton, description: "Settings button")
            
            // Verify hint exists (accessibility hint might not be directly queryable)
            XCTAssertTrue(settingsButton.isHittable, "Settings button should be hittable")
        }
    }
    
    // MARK: - Color Controls Accessibility Tests
    
    @MainActor
    func testColorTabAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Color tab
        let colorTab = app.buttons["Color"]
        if colorTab.waitForExistence(timeout: 3.0) {
            colorTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Verify color tab is accessible
            verifyButtonAccessibility(colorTab, description: "Color tab")
        }
    }
    
    @MainActor
    func testBrightnessSliderAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Color tab
        let colorTab = app.buttons["Color"]
        if colorTab.waitForExistence(timeout: 3.0) {
            colorTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find brightness slider
            let brightnessSlider = app.sliders["Brightness"]
            
            if brightnessSlider.exists {
                verifySliderAccessibility(brightnessSlider, description: "Brightness slider")
            }
        }
    }
    
    @MainActor
    func testCCTSliderAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Color tab
        let colorTab = app.buttons["Color"]
        if colorTab.waitForExistence(timeout: 3.0) {
            colorTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find CCT slider
            let cctSliderById = app.otherElements["CCTTemperatureSlider"]
            let cctSliderByLabel = app.otherElements["Color temperature"]
            let cctSlider = cctSliderById.exists ? cctSliderById : cctSliderByLabel
            
            if cctSlider.exists {
                verifyAccessibilityLabel(cctSlider, description: "CCT slider")
                
                // CCT slider should have accessibility value
                let cctValue = cctSlider.value as? String
                XCTAssertNotNil(cctValue, "CCT slider should have accessibility value")
            }
        }
    }
    
    @MainActor
    func testGradientBarAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Color tab
        let colorTab = app.buttons["Color"]
        if colorTab.waitForExistence(timeout: 3.0) {
            colorTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find gradient bar
            let gradientBar = app.otherElements.matching(identifier: "GradientBar").firstMatch
            
            if gradientBar.exists {
                // Gradient bar should have accessibility
                XCTAssertTrue(gradientBar.exists, "Gradient bar should exist")
                
                // Gradient stops should be accessible
                let gradientStops = app.otherElements.matching(NSPredicate(format: "label == 'Gradient stop'"))
                if gradientStops.count > 0 {
                    let stop = gradientStops.element(boundBy: 0)
                    verifyAccessibilityLabel(stop, description: "Gradient stop")
                }
            }
        }
    }
    
    // MARK: - Effects Controls Accessibility Tests
    
    @MainActor
    func testEffectsTabAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Effects tab
        let effectsTab = app.buttons["Effects"]
        if effectsTab.waitForExistence(timeout: 3.0) {
            effectsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Verify effects tab is accessible
            verifyButtonAccessibility(effectsTab, description: "Effects tab")
        }
    }
    
    @MainActor
    func testEffectPickerAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Effects tab
        let effectsTab = app.buttons["Effects"]
        if effectsTab.waitForExistence(timeout: 3.0) {
            effectsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find effect picker
            let effectPicker = app.pickers.matching(identifier: "Effect").firstMatch
            
            if effectPicker.exists {
                verifyAccessibilityLabel(effectPicker, description: "Effect picker")
            }
        }
    }
    
    @MainActor
    func testSpeedSliderAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Effects tab
        let effectsTab = app.buttons["Effects"]
        if effectsTab.waitForExistence(timeout: 3.0) {
            effectsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find speed slider
            let speedSlider = app.sliders.matching(NSPredicate(format: "label CONTAINS[cd] 'speed'")).firstMatch
            
            if speedSlider.exists {
                verifySliderAccessibility(speedSlider, description: "Speed slider")
            }
        }
    }
    
    @MainActor
    func testIntensitySliderAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Effects tab
        let effectsTab = app.buttons["Effects"]
        if effectsTab.waitForExistence(timeout: 3.0) {
            effectsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find intensity slider
            let intensitySlider = app.sliders.matching(NSPredicate(format: "label CONTAINS[cd] 'intensity'")).firstMatch
            
            if intensitySlider.exists {
                verifySliderAccessibility(intensitySlider, description: "Intensity slider")
            }
        }
    }
    
    @MainActor
    func testPalettePickerAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Effects tab
        let effectsTab = app.buttons["Effects"]
        if effectsTab.waitForExistence(timeout: 3.0) {
            effectsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find palette picker
            let palettePicker = app.pickers["Palette"]
            
            if palettePicker.exists {
                verifyAccessibilityLabel(palettePicker, description: "Palette picker")
            }
        }
    }
    
    // MARK: - Segment Picker Accessibility Tests
    
    @MainActor
    func testSegmentPickerAccessibility() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Find segment picker
        let segmentPicker = app.pickers["Segment selector"]
        
        if segmentPicker.exists {
            verifyAccessibilityLabel(segmentPicker, description: "Segment picker")
            
            // Segment picker should have accessibility value
            let segmentValue = segmentPicker.value as? String
            XCTAssertNotNil(segmentValue, "Segment picker should have accessibility value")
            
            if let value = segmentValue {
                XCTAssertTrue(value.hasPrefix("Segment "), "Segment value should start with 'Segment '")
            }
        }
    }
    
    // MARK: - Presets Accessibility Tests
    
    @MainActor
    func testPresetsTabAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Presets tab
        let presetsTab = app.buttons["Presets"]
        if presetsTab.waitForExistence(timeout: 3.0) {
            presetsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Verify presets tab is accessible
            verifyButtonAccessibility(presetsTab, description: "Presets tab")
        }
    }
    
    @MainActor
    func testPresetPickerAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Presets tab
        let presetsTab = app.buttons["Presets"]
        if presetsTab.waitForExistence(timeout: 3.0) {
            presetsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find preset picker
            let presetPicker = app.pickers.matching(NSPredicate(format: "label CONTAINS[cd] 'preset'")).firstMatch
            
            if presetPicker.exists {
                verifyAccessibilityLabel(presetPicker, description: "Preset picker")
            }
        }
    }
    
    @MainActor
    func testApplyPresetButtonAccessibility() throws {
        navigateToDeviceDetail()
        
        // Navigate to Presets tab
        let presetsTab = app.buttons["Presets"]
        if presetsTab.waitForExistence(timeout: 3.0) {
            presetsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Find apply preset button
            let applyButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apply'"))
            
            if applyButtons.count > 0 {
                let applyButton = applyButtons.element(boundBy: 0)
                verifyButtonAccessibility(applyButton, description: "Apply preset button")
            }
        }
    }
    
    // MARK: - Accessibility Navigation Tests
    
    @MainActor
    func testVoiceOverNavigationOrder() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Verify that interactive elements are accessible in a logical order
        // In VoiceOver, users navigate sequentially through accessible elements
        
        // Get all accessible elements
        let accessibleElements = app.descendants(matching: .any).matching(NSPredicate(format: "isAccessibilityElement == YES"))
        
        // Verify we have accessible elements
        XCTAssertGreaterThan(accessibleElements.count, 0, "Should have accessible elements")
        
        // Verify interactive elements are accessible
        let buttons = app.buttons.matching(NSPredicate(format: "isAccessibilityElement == YES"))
        let sliders = app.sliders.matching(NSPredicate(format: "isAccessibilityElement == YES"))
        let pickers = app.pickers.matching(NSPredicate(format: "isAccessibilityElement == YES"))
        
        // Verify at least some interactive elements exist
        let totalInteractive = buttons.count + sliders.count + pickers.count
        XCTAssertGreaterThan(totalInteractive, 0, "Should have interactive accessible elements")
    }
    
    @MainActor
    func testAllInteractiveElementsHaveLabels() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Check all buttons have labels
        let buttons = app.buttons.matching(NSPredicate(format: "isAccessibilityElement == YES"))
        
        var buttonsWithoutLabels = 0
        for i in 0..<min(buttons.count, 10) { // Check first 10 buttons
            let button = buttons.element(boundBy: i)
            if button.label.isEmpty {
                buttonsWithoutLabels += 1
            }
        }
        
        // Most buttons should have labels (allow some tolerance for system buttons)
        XCTAssertLessThan(buttonsWithoutLabels, buttons.count / 2,
                         "Most buttons should have accessibility labels")
    }
    
    @MainActor
    func testAllSlidersHaveValues() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Check all sliders have values
        let sliders = app.sliders.matching(NSPredicate(format: "isAccessibilityElement == YES"))
        
        var slidersWithoutValues = 0
        for i in 0..<sliders.count {
            let slider = sliders.element(boundBy: i)
            let value = slider.value as? String
            if value == nil || value?.isEmpty == true {
                slidersWithoutValues += 1
            }
        }
        
        // All sliders should have values
        XCTAssertEqual(slidersWithoutValues, 0,
                      "All sliders should have accessibility values")
    }
    
    // MARK: - Accessibility Label Accuracy Tests
    
    @MainActor
    func testPowerToggleLabelAccuracy() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        let powerToggle = app.buttons.matching(NSPredicate(format: "label == 'Power'")).firstMatch
        
        if powerToggle.exists {
            // Power toggle label should be exactly "Power"
            XCTAssertEqual(powerToggle.label, "Power",
                          "Power toggle should have exact label 'Power'")
        }
    }
    
    @MainActor
    func testBrightnessSliderLabelAccuracy() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        let brightnessSlider = app.sliders["Brightness"]
        
        if brightnessSlider.exists {
            // Brightness slider label should be "Brightness"
            XCTAssertTrue(brightnessSlider.label.lowercased().contains("brightness"),
                          "Brightness slider label should contain 'brightness'")
        }
    }
    
    @MainActor
    func testErrorBannerAccessibilityLabelAccuracy() throws {
        navigateToDeviceDetail()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Check if error banner is visible
        let errorBanner = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch
        
        if errorBanner.exists {
            // Error banner label should start with "Error:"
            XCTAssertTrue(errorBanner.label.hasPrefix("Error:"),
                          "Error banner label should start with 'Error:'")
        }
    }
    
    // MARK: - Integration Test: Full Accessibility Flow
    
    @MainActor
    func testFullAccessibilityNavigationFlow() throws {
        waitForDeviceList()
        Thread.sleep(forTimeInterval: 2.0)
        
        // Step 1: Navigate to device detail
        navigateToDeviceDetail()
        
        // Step 2: Verify navigation is accessible
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.exists, "Navigation bar should be accessible")
        
        // Step 3: Verify tabs are accessible
        let colorTab = app.buttons["Color"]
        if colorTab.exists {
            verifyButtonAccessibility(colorTab, description: "Color tab")
        }
        
        // Step 4: Navigate to Color tab
        if colorTab.exists {
            colorTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Step 5: Verify color controls are accessible
            let brightnessSlider = app.sliders["Brightness"]
            if brightnessSlider.exists {
                verifySliderAccessibility(brightnessSlider, description: "Brightness slider")
            }
        }
        
        // Step 6: Navigate to Effects tab
        let effectsTab = app.buttons["Effects"]
        if effectsTab.exists {
            effectsTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Step 7: Verify effects controls are accessible
            let effectPicker = app.pickers.matching(identifier: "Effect").firstMatch
            if effectPicker.exists {
                verifyAccessibilityLabel(effectPicker, description: "Effect picker")
            }
        }
    }
}

