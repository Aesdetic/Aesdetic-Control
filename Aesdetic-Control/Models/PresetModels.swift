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
    
    // Brightness (0-255)
    var brightness: Int
    
    // CCT/Temperature (0.0-1.0, nil if not set)
    var temperature: Double?
    
    // WLED preset ID (nil until saved to device)
    var wledPresetId: Int?
    
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        gradientStops: [GradientStop],
        brightness: Int,
        temperature: Double? = nil,
        wledPresetId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.gradientStops = gradientStops
        self.brightness = max(0, min(255, brightness))
        self.temperature = temperature
        self.wledPresetId = wledPresetId
    }
}

// MARK: - Transition Preset (A→B, no loop)
/// Transition preset that saves Gradient A → Gradient B transition
/// Saved as WLED playlist (A→B, stops at B, no loop)
struct TransitionPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var deviceId: String  // Device-specific (playlists are per-device)
    var createdAt: Date
    
    // Gradient A
    var gradientA: LEDGradient
    var brightnessA: Int
    
    // Gradient B
    var gradientB: LEDGradient
    var brightnessB: Int
    
    // Transition duration (seconds)
    var durationSec: Double
    
    // WLED playlist ID (nil until saved to device)
    var wledPlaylistId: Int?
    
    init(
        id: UUID = UUID(),
        name: String,
        deviceId: String,
        createdAt: Date = Date(),
        gradientA: LEDGradient,
        brightnessA: Int,
        gradientB: LEDGradient,
        brightnessB: Int,
        durationSec: Double,
        wledPlaylistId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.gradientA = gradientA
        self.brightnessA = max(0, min(255, brightnessA))
        self.gradientB = gradientB
        self.brightnessB = max(0, min(255, brightnessB))
        self.durationSec = max(0.1, durationSec)
        self.wledPlaylistId = wledPlaylistId
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
    
    // Brightness
    var brightness: Int
    
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
        brightness: Int,
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
        self.brightness = max(0, min(255, brightness))
        self.wledPresetId = wledPresetId
    }
}


