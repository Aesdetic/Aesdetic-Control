import Foundation

enum SyncOrigin {
    case user
    case propagated
}

enum ColorsSyncPayload {
    case brightness(value: Int)
    case gradient(stops: [GradientStop], interpolation: GradientInterpolation, segmentId: Int, brightness: Int?, on: Bool?)
    case effectState(effectId: Int, gradient: LEDGradient, segmentId: Int)
    case effectParameter(SyncEffectParameter)
    case transitionStart(TransitionSyncPayload)
    case effectDisable(segmentId: Int)
}

enum SyncEffectParameter {
    case speed(segmentId: Int, value: Int)
    case intensity(segmentId: Int, value: Int)
    case custom(segmentId: Int, index: Int, value: Int)
    case palette(segmentId: Int, paletteId: Int?)
    case segmentBrightness(segmentId: Int, value: Int)
    case option(segmentId: Int, optionIndex: Int, value: Bool)
}

struct TransitionSyncPayload {
    let from: LEDGradient
    let aBrightness: Int
    let to: LEDGradient
    let bBrightness: Int
    let durationSec: Double
    let startStopTemperatures: [UUID: Double]?
    let startStopWhiteLevels: [UUID: Double]?
    let endStopTemperatures: [UUID: Double]?
    let endStopWhiteLevels: [UUID: Double]?
    let forceSegmentedOnly: Bool
}

struct SyncDispatchSummary: Equatable {
    let applied: Int
    let downgraded: Int
    let skipped: Int

    var message: String {
        "Applied \(applied), downgraded \(downgraded), skipped \(skipped)"
    }

    static let idle = SyncDispatchSummary(applied: 0, downgraded: 0, skipped: 0)
}
