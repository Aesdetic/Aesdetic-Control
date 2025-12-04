import XCTest
import SwiftUI
@testable import Aesdetic_Control

final class AutomationModelTests: XCTestCase {
    
    func testSunriseTemplatePrefillBuildsTransition() {
        let device = WLEDDevice(
            id: "demo-device",
            name: "Aurora",
            ipAddress: "192.168.1.20",
            isOnline: true,
            brightness: 42,
            currentColor: .orange
        )
        let context = AutomationTemplate.Context(
            device: device,
            availableDevices: [device],
            defaultGradient: LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: "#FFD8A8"),
                GradientStop(position: 1.0, hexColor: "#FFFFFF")
            ])
        )
        
        let prefill = AutomationTemplate.sunrise.prefill(for: context)
        
        switch prefill.trigger {
        case .sunrise(let offsetMinutes):
            XCTAssertEqual(offsetMinutes, -15)
        default:
            XCTFail("Expected sunrise trigger")
        }
        
        switch prefill.action {
        case .transition(let payload, let duration, let endBrightness):
            XCTAssertEqual(Int(duration ?? 0), 1800)
            XCTAssertEqual(endBrightness, 255)
            XCTAssertEqual(payload.presetName, "Sunrise Glow")
            XCTAssertEqual(payload.startBrightness, 6)
            XCTAssertEqual(payload.endGradient.stops.count, 2)
        default:
            XCTFail("Expected transition payload")
        }
        
        XCTAssertEqual(prefill.metadata?.templateId, "sunrise")
    }
    
    func testTimeTriggerNextDateAdvancesToNextValidDay() {
        var trigger = TimeTrigger(time: "06:30", weekdays: [false, true, true, true, true, true, false])
        let calendar = Calendar(identifier: .gregorian)
        let mondayComponents = DateComponents(calendar: calendar, year: 2025, month: 1, day: 6, hour: 7, minute: 0) // Monday
        let reference = calendar.date(from: mondayComponents)!
        guard let nextDate = trigger.nextTriggerDate(referenceDate: reference, calendar: calendar) else {
            return XCTFail("Expected next trigger date")
        }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: nextDate)
        XCTAssertEqual(components.weekday, 3) // Tuesday
        XCTAssertEqual(components.hour, 6)
        XCTAssertEqual(components.minute, 30)
    }
}

