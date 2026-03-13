import Foundation
import SwiftUI

// MARK: - Color Preset (Gradient + Brightness + CCT)
/// Color preset that saves gradient stops, brightness, and CCT
/// Shared across all devices
struct ColorPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    
    // Gradient data
    var gradientStops: [GradientStop]
    
    // Gradient interpolation mode (how colors blend between stops)
    var gradientInterpolation: GradientInterpolation?
    
    // Brightness (0-255)
    var brightness: Int
    
    // CCT/Temperature (0.0-1.0, nil if not set)
    var temperature: Double?
    
    // White channel level (0.0-1.0, nil if not set)
    var whiteLevel: Double?

    // WLED save options
    var includeBrightness: Bool?
    var saveSegmentBounds: Bool?
    var selectedSegmentsOnly: Bool?
    var quickLoadTag: String?
    var applyAtBoot: Bool?
    var customAPICommand: String?
    
    // WLED preset IDs per device (nil until saved to device)
    var wledPresetIds: [String: Int]?
    // Legacy single-device preset ID (kept for migration fallback)
    var wledPresetId: Int?
    
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        gradientStops: [GradientStop],
        gradientInterpolation: GradientInterpolation? = nil,
        brightness: Int,
        temperature: Double? = nil,
        whiteLevel: Double? = nil,
        includeBrightness: Bool? = nil,
        saveSegmentBounds: Bool? = nil,
        selectedSegmentsOnly: Bool? = nil,
        quickLoadTag: String? = nil,
        applyAtBoot: Bool? = nil,
        customAPICommand: String? = nil,
        wledPresetIds: [String: Int]? = nil,
        wledPresetId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.gradientStops = gradientStops
        self.gradientInterpolation = gradientInterpolation
        self.brightness = max(0, min(255, brightness))
        self.temperature = temperature
        self.whiteLevel = whiteLevel
        self.includeBrightness = includeBrightness
        self.saveSegmentBounds = saveSegmentBounds
        self.selectedSegmentsOnly = selectedSegmentsOnly
        self.quickLoadTag = quickLoadTag
        self.applyAtBoot = applyAtBoot
        self.customAPICommand = customAPICommand
        self.wledPresetIds = wledPresetIds
        self.wledPresetId = wledPresetId
    }
}

// MARK: - Transition Preset (A→B, no loop)
/// Transition preset that saves Gradient A → Gradient B transition
/// Saved as WLED playlist (A→B, stops at B, no loop)
enum TransitionPresetWLEDSyncState: String, Codable {
    case synced
    case pendingSync
    case syncFailed
    case needsMigration
}

struct TransitionPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var deviceId: String  // Device-specific (playlists are per-device)
    var createdAt: Date
    
    // Gradient A
    var gradientA: LEDGradient
    var brightnessA: Int
    var temperatureA: Double?
    var whiteLevelA: Double?
    
    // Gradient B
    var gradientB: LEDGradient
    var brightnessB: Int
    var temperatureB: Double?
    var whiteLevelB: Double?
    
    // Transition duration (seconds)
    var durationSec: Double
    
    // WLED playlist ID (nil until saved to device)
    var wledPlaylistId: Int?
    // WLED step preset IDs used by this playlist (nil until saved to device)
    var wledStepPresetIds: [Int]?
    // WLED sync state for this device-specific playlist metadata
    var wledSyncState: TransitionPresetWLEDSyncState
    var lastWLEDSyncError: String?
    var lastWLEDSyncAt: Date?
    
    init(
        id: UUID = UUID(),
        name: String,
        deviceId: String,
        createdAt: Date = Date(),
        gradientA: LEDGradient,
        brightnessA: Int,
        temperatureA: Double? = nil,
        whiteLevelA: Double? = nil,
        gradientB: LEDGradient,
        brightnessB: Int,
        temperatureB: Double? = nil,
        whiteLevelB: Double? = nil,
        durationSec: Double,
        wledPlaylistId: Int? = nil,
        wledStepPresetIds: [Int]? = nil,
        wledSyncState: TransitionPresetWLEDSyncState? = nil,
        lastWLEDSyncError: String? = nil,
        lastWLEDSyncAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.gradientA = gradientA
        self.brightnessA = max(0, min(255, brightnessA))
        self.temperatureA = temperatureA
        self.whiteLevelA = whiteLevelA
        self.gradientB = gradientB
        self.brightnessB = max(0, min(255, brightnessB))
        self.temperatureB = temperatureB
        self.whiteLevelB = whiteLevelB
        self.durationSec = max(0.1, durationSec)
        self.wledPlaylistId = wledPlaylistId
        self.wledStepPresetIds = wledStepPresetIds
        self.wledSyncState = wledSyncState
            ?? TransitionPreset.inferLegacySyncState(playlistId: wledPlaylistId, stepPresetIds: wledStepPresetIds)
        self.lastWLEDSyncError = lastWLEDSyncError
        self.lastWLEDSyncAt = lastWLEDSyncAt
    }

    private static func inferLegacySyncState(playlistId: Int?, stepPresetIds: [Int]?) -> TransitionPresetWLEDSyncState {
        if let playlistId, (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains(playlistId) {
            return .needsMigration
        }
        if let stepPresetIds,
           stepPresetIds.contains(where: { (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains($0) }) {
            return .needsMigration
        }
        if playlistId != nil || !(stepPresetIds?.isEmpty ?? true) {
            return .synced
        }
        return .pendingSync
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case deviceId
        case createdAt
        case gradientA
        case brightnessA
        case temperatureA
        case whiteLevelA
        case gradientB
        case brightnessB
        case temperatureB
        case whiteLevelB
        case durationSec
        case wledPlaylistId
        case wledStepPresetIds
        case wledSyncState
        case lastWLEDSyncError
        case lastWLEDSyncAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        gradientA = try c.decode(LEDGradient.self, forKey: .gradientA)
        brightnessA = max(0, min(255, try c.decode(Int.self, forKey: .brightnessA)))
        temperatureA = try c.decodeIfPresent(Double.self, forKey: .temperatureA)
        whiteLevelA = try c.decodeIfPresent(Double.self, forKey: .whiteLevelA)
        gradientB = try c.decode(LEDGradient.self, forKey: .gradientB)
        brightnessB = max(0, min(255, try c.decode(Int.self, forKey: .brightnessB)))
        temperatureB = try c.decodeIfPresent(Double.self, forKey: .temperatureB)
        whiteLevelB = try c.decodeIfPresent(Double.self, forKey: .whiteLevelB)
        durationSec = max(0.1, try c.decode(Double.self, forKey: .durationSec))
        wledPlaylistId = try c.decodeIfPresent(Int.self, forKey: .wledPlaylistId)
        wledStepPresetIds = try c.decodeIfPresent([Int].self, forKey: .wledStepPresetIds)
        wledSyncState = try c.decodeIfPresent(TransitionPresetWLEDSyncState.self, forKey: .wledSyncState)
            ?? TransitionPreset.inferLegacySyncState(playlistId: wledPlaylistId, stepPresetIds: wledStepPresetIds)
        lastWLEDSyncError = try c.decodeIfPresent(String.self, forKey: .lastWLEDSyncError)
        lastWLEDSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastWLEDSyncAt)
    }
}

// MARK: - WLED Effect Preset
/// WLED effect preset (Fire, Rainbow, etc.) with speed/intensity/palette
struct WLEDEffectPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var deviceId: String  // Device-specific (effects are per-device)
    var createdAt: Date
    
    // Effect settings
    var effectId: Int
    var speed: Int?  // Effect speed
    var intensity: Int?  // Effect intensity
    var paletteId: Int?  // Color palette
    var gradientStops: [GradientStop]?  // Optional custom gradient colors
    var gradientInterpolation: GradientInterpolation?
    
    // Brightness
    var brightness: Int

    // WLED save options
    var includeBrightness: Bool?
    var saveSegmentBounds: Bool?
    var selectedSegmentsOnly: Bool?
    var quickLoadTag: String?
    var applyAtBoot: Bool?
    var customAPICommand: String?
    
    // WLED preset ID (nil until saved to device)
    var wledPresetId: Int?
    
    init(
        id: UUID = UUID(),
        name: String,
        deviceId: String,
        createdAt: Date = Date(),
        effectId: Int,
        speed: Int? = nil,
        intensity: Int? = nil,
        paletteId: Int? = nil,
        gradientStops: [GradientStop]? = nil,
        gradientInterpolation: GradientInterpolation? = nil,
        brightness: Int,
        includeBrightness: Bool? = nil,
        saveSegmentBounds: Bool? = nil,
        selectedSegmentsOnly: Bool? = nil,
        quickLoadTag: String? = nil,
        applyAtBoot: Bool? = nil,
        customAPICommand: String? = nil,
        wledPresetId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.effectId = effectId
        self.speed = speed
        self.intensity = intensity
        self.paletteId = paletteId
        self.gradientStops = gradientStops
        self.gradientInterpolation = gradientInterpolation
        self.brightness = max(0, min(255, brightness))
        self.includeBrightness = includeBrightness
        self.saveSegmentBounds = saveSegmentBounds
        self.selectedSegmentsOnly = selectedSegmentsOnly
        self.quickLoadTag = quickLoadTag
        self.applyAtBoot = applyAtBoot
        self.customAPICommand = customAPICommand
        self.wledPresetId = wledPresetId
    }
}

extension Date {
    private static let presetNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter
    }()

    func presetNameTimestamp() -> String {
        Date.presetNameFormatter.string(from: self)
    }
}
