import CoreGraphics
import Testing
@testable import Aesdetic_Control

struct AppBackgroundPreferenceTests {
    @Test("background blur defaults preserve existing appearance")
    func backgroundBlurDefaults() {
        #expect(AppBackgroundPreference.defaultBlurEnabled == false)
        #expect(AppBackgroundPreference.defaultBlurIntensity == 0.35)
    }

    @Test("background blur intensity clamps to its supported range")
    func backgroundBlurIntensityClamping() {
        #expect(AppBackgroundPreference.clampedBlurIntensity(-1) == 0.10)
        #expect(AppBackgroundPreference.clampedBlurIntensity(0.35) == 0.35)
        #expect(AppBackgroundPreference.clampedBlurIntensity(2) == 1.00)
    }

    @Test("background blur radius maps from 2.4 to 24 points")
    func backgroundBlurRadiusMapping() {
        let minimumRadius = AppBackgroundPreference.blurRadius(for: 0.10)
        let maximumRadius = AppBackgroundPreference.blurRadius(for: 1.00)

        #expect(abs(minimumRadius - 2.4) < 0.001)
        #expect(abs(maximumRadius - 24) < 0.001)
        #expect(AppBackgroundPreference.blurRadius(for: -1) == minimumRadius)
        #expect(AppBackgroundPreference.blurRadius(for: 2) == maximumRadius)
    }
}
