import Foundation

struct Scene: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var deviceId: String
    var createdAt: Date

    // Core
    var brightness: Int
    var primaryStops: [GradientStop]

    // Transition
    var transitionEnabled: Bool
    var secondaryStops: [GradientStop]? = nil
    var durationSec: Double? = nil
    var aBrightness: Int? = nil
    var bBrightness: Int? = nil

    // Effects
    var effectsEnabled: Bool
    var effectId: Int? = nil
    var paletteId: Int? = nil
    var speed: Int? = nil
    var intensity: Int? = nil

    init(
        id: UUID = UUID(),
        name: String,
        deviceId: String,
        createdAt: Date = Date(),
        brightness: Int,
        primaryStops: [GradientStop],
        transitionEnabled: Bool = false,
        secondaryStops: [GradientStop]? = nil,
        durationSec: Double? = nil,
        aBrightness: Int? = nil,
        bBrightness: Int? = nil,
        effectsEnabled: Bool = false,
        effectId: Int? = nil,
        paletteId: Int? = nil,
        speed: Int? = nil,
        intensity: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.brightness = max(0, min(255, brightness))
        self.primaryStops = primaryStops
        self.transitionEnabled = transitionEnabled
        self.secondaryStops = secondaryStops
        self.durationSec = durationSec
        self.aBrightness = aBrightness
        self.bBrightness = bBrightness
        self.effectsEnabled = effectsEnabled
        self.effectId = effectId
        self.paletteId = paletteId
        self.speed = speed
        self.intensity = intensity
    }
}


