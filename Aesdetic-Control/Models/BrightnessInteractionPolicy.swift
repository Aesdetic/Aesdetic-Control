import Foundation

enum BrightnessInteractionPolicy {
    static let previewCadence: TimeInterval = 0.14

    static func permitsPreview(
        isOn: Bool,
        currentBrightness: Int,
        requestedBrightness: Int
    ) -> Bool {
        isOn && currentBrightness > 0 && requestedBrightness > 0
    }
}
