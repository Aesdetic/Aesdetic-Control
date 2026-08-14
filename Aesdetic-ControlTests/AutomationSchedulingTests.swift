import Foundation
import Testing
@testable import Aesdetic_Control

struct AutomationSchedulingTests {

    @Test("WeekdayMask encodes Sunday-first weekdays to WLED Monday-first dow")
    func testWeekdayMaskEncoding() {
        // Sun + Mon + Fri enabled (Sun...Sat)
        let sunFirst = [true, true, false, false, false, true, false]
        let dow = WeekdayMask.wledDow(fromSunFirst: sunFirst)

        // WLED bits: Mon=bit0, Fri=bit4, Sun=bit6 => 0b1010001 (81)
        #expect(dow == 0b1010001)
    }

    @Test("WeekdayMask round-trips between app and WLED representations")
    func testWeekdayMaskRoundTrip() {
        let original = [false, true, true, false, true, false, true] // Sun...Sat
        let dow = WeekdayMask.wledDow(fromSunFirst: original)
        let decoded = WeekdayMask.sunFirst(fromWLEDDow: dow)
        #expect(decoded == original)
    }

    @Test("Empty weekday selections default to all-days mask for WLED safety")
    func testWeekdayMaskEmptyDefaultsToAllDays() {
        let noneSelected = Array(repeating: false, count: 7)
        #expect(WeekdayMask.wledDow(fromSunFirst: noneSelected) == 0x7F)
        #expect(WeekdayMask.sunFirst(fromWLEDDow: 0) == WeekdayMask.allDaysSunFirst)
    }

    @Test("SolarTrigger offset clamping follows on-device WLED limits")
    func testSolarOffsetClamping() {
        #expect(SolarTrigger.clampOnDeviceOffset(-60) == -59)
        #expect(SolarTrigger.clampOnDeviceOffset(-59) == -59)
        #expect(SolarTrigger.clampOnDeviceOffset(15) == 15)
        #expect(SolarTrigger.clampOnDeviceOffset(59) == 59)
        #expect(SolarTrigger.clampOnDeviceOffset(60) == 59)
    }

    @Test("SolarTrigger decodes legacy payloads without weekdays as all days")
    func testSolarTriggerLegacyDecodeDefaultsWeekdays() throws {
        let legacyJSON = """
        {
          "offset": { "minutes": 10 },
          "location": { "followDevice": {} }
        }
        """
        let trigger = try JSONDecoder().decode(SolarTrigger.self, from: Data(legacyJSON.utf8))
        #expect(trigger.weekdays == WeekdayMask.allDaysSunFirst)
    }

    @MainActor
    @Test("On-device schedule preview warns when a timed automation overlaps another automation")
    func testOnDeviceScheduleOverlapWarning() async {
        let store = AutomationStore.shared
        let original = store.automations
        defer { store.automations = original }

        let deviceId = "overlap-warning-device-\(UUID().uuidString)"
        let calendar = Calendar.current
        let now = Date()
        let firstTime = calendar.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
        let secondTime = calendar.date(byAdding: .minute, value: 3, to: now) ?? now.addingTimeInterval(180)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let firstAutomation = Automation(
            name: "Morning Fade",
            trigger: .specificTime(
                TimeTrigger(
                    time: formatter.string(from: firstTime),
                    weekdays: WeekdayMask.allDaysSunFirst,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            ),
            action: .transition(
                TransitionActionPayload(
                    startGradient: LEDGradient(stops: [
                        GradientStop(position: 0.0, hexColor: "FFA000"),
                        GradientStop(position: 1.0, hexColor: "FFFFFF")
                    ]),
                    startBrightness: 128,
                    endGradient: LEDGradient(stops: [
                        GradientStop(position: 0.0, hexColor: "FFFFFF"),
                        GradientStop(position: 1.0, hexColor: "59A4FF")
                    ]),
                    endBrightness: 128,
                    durationSeconds: 600
                )
            ),
            targets: AutomationTargets(deviceIds: [deviceId]),
            metadata: AutomationMetadata(runOnDevice: true)
        )

        let secondAutomation = Automation(
            name: "Sleep Off",
            trigger: .specificTime(
                TimeTrigger(
                    time: formatter.string(from: secondTime),
                    weekdays: WeekdayMask.allDaysSunFirst,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            ),
            action: .preset(PresetActionPayload(presetId: 1, paletteName: nil, durationSeconds: nil)),
            targets: AutomationTargets(deviceIds: [deviceId]),
            metadata: AutomationMetadata(runOnDevice: true)
        )

        store.automations = [firstAutomation, secondAutomation]

        let warning = await store.previewOnDeviceScheduleOverlapWarning(for: firstAutomation)
        #expect(warning?.contains("Sleep Off") == true)
        #expect(warning?.contains("interrupt") == true)
    }

    @MainActor
    @Test("On-device schedule preview warns when a new automation interrupts an already-running transition")
    func testOnDeviceScheduleOverlapWarningIncludesRunningWindow() async {
        let store = AutomationStore.shared
        let original = store.automations
        defer { store.automations = original }

        let deviceId = "running-overlap-warning-device-\(UUID().uuidString)"
        let calendar = Calendar.current
        let now = Date()
        let runningStart = calendar.date(byAdding: .minute, value: -2, to: now) ?? now.addingTimeInterval(-120)
        let interruptTime = calendar.date(byAdding: .minute, value: 2, to: now) ?? now.addingTimeInterval(120)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let runningTransition = Automation(
            name: "Running Fade",
            trigger: .specificTime(
                TimeTrigger(
                    time: formatter.string(from: runningStart),
                    weekdays: WeekdayMask.allDaysSunFirst,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            ),
            action: .transition(
                TransitionActionPayload(
                    startGradient: LEDGradient(stops: [
                        GradientStop(position: 0.0, hexColor: "FFA000"),
                        GradientStop(position: 1.0, hexColor: "FFFFFF")
                    ]),
                    startBrightness: 128,
                    endGradient: LEDGradient(stops: [
                        GradientStop(position: 0.0, hexColor: "FFFFFF"),
                        GradientStop(position: 1.0, hexColor: "59A4FF")
                    ]),
                    endBrightness: 128,
                    durationSeconds: 600
                )
            ),
            targets: AutomationTargets(deviceIds: [deviceId]),
            metadata: AutomationMetadata(runOnDevice: true)
        )

        let interruptingAutomation = Automation(
            name: "Device Off",
            trigger: .specificTime(
                TimeTrigger(
                    time: formatter.string(from: interruptTime),
                    weekdays: WeekdayMask.allDaysSunFirst,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            ),
            action: .preset(PresetActionPayload(presetId: 1, paletteName: nil, durationSeconds: nil)),
            targets: AutomationTargets(deviceIds: [deviceId]),
            metadata: AutomationMetadata(runOnDevice: true)
        )

        store.automations = [runningTransition]

        let warning = await store.previewOnDeviceScheduleOverlapWarning(for: interruptingAutomation)
        #expect(warning?.contains("Running Fade") == true)
        #expect(warning?.contains("interrupt") == true)
    }
}
