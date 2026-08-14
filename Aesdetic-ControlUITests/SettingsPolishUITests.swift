import XCTest

final class SettingsPolishUITests: XCTestCase {
    private var app: XCUIApplication!

    private func selectSettingsTab(_ tabID: String) {
        let selector = app.scrollViews["settings-category-selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 3), "Missing settings category selector")

        let tab = app.buttons[tabID]
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "Missing settings tab \(tabID)")

        for _ in 0..<4 {
            let selectorFrame = selector.frame.insetBy(dx: 4, dy: 0)
            let tabFrame = tab.frame
            let isFullyVisible = tabFrame.minX >= selectorFrame.minX
                && tabFrame.maxX <= selectorFrame.maxX

            if isFullyVisible && tab.isHittable {
                break
            }

            if tabFrame.midX > selectorFrame.midX {
                selector.swipeLeft()
            } else {
                selector.swipeRight()
            }
        }

        XCTAssertTrue(tab.isHittable, "Settings tab is not visibly tappable: \(tabID)")
        tab.tap()

        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Selected'"),
            object: tab
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selected], timeout: 2),
            .completed,
            "Settings tab did not become selected: \(tabID)"
        )
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testRapidSettingsNavigationRemainsResponsive() throws {
        let devicesTab = app.buttons["Devices"]
        XCTAssertTrue(devicesTab.waitForExistence(timeout: 8))
        devicesTab.tap()

        let cardName = app.staticTexts["UI Test Device"]
        XCTAssertTrue(cardName.waitForExistence(timeout: 8), "Missing deterministic UI-test device")
        cardName.tap()

        let options = app.descendants(matching: .any)["device-options-menu"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let tabIDs = [
            "settings-tab-Device",
            "settings-tab-Time & Schedules",
            "settings-tab-WiFi",
            "settings-tab-Integrations",
            "settings-tab-Advanced"
        ]

        for _ in 0..<5 {
            for tabID in tabIDs {
                selectSettingsTab(tabID)
            }
        }

        selectSettingsTab("settings-tab-Advanced")
        XCTAssertTrue(
            app.staticTexts["Advanced Settings"].waitForExistence(timeout: 5),
            "Advanced settings page did not appear"
        )

        for categoryID in ["led-hardware", "wifi-network", "sync-interfaces", "time-macros", "usermods"] {
            let category = app.descendants(matching: .any)["advanced-category-\(categoryID)"]
            XCTAssertTrue(category.waitForExistence(timeout: 5), "Missing Advanced category \(categoryID)")
            category.tap()

            let back = app.buttons["Back to advanced settings categories"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
    }
}
