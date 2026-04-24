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
        #expect(SolarTrigger.clampOnDeviceOffset(-120) == -120)
        #expect(SolarTrigger.clampOnDeviceOffset(120) == 120)
        #expect(SolarTrigger.clampOnDeviceOffset(15) == 15)
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
}
