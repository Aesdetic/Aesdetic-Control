import Foundation

enum ColorMode: String, Codable {
    case solid
    case perLED
    case palette
}

struct ColorIntent: Codable {
    var deviceId: String
    var mode: ColorMode
    var segmentId: Int = 0

    // Core fields
    var brightness: Int? = nil            // 0...255
    var transitionMs: Int? = nil          // optional top-level transition

    // Solid color
    var solidRGB: [Int]? = nil            // [r,g,b] or [r,g,b,w]
    
    // White channel (0-255, for RGBW strips)
    var whiteLevel: Int? = nil            // Dedicated white LED channel

    // Per-LED upload
    var perLEDHex: [String]? = nil        // ["RRGGBB", ...]
    
    // Color temperature (0-255, for RGBW/RGBCW strips)
    var cct: Int? = nil                   // 0=warm ~2700K, 255=cool ~6500K

    // Effect/Palette
    var effectId: Int? = nil
    var paletteId: Int? = nil
    var speed: Int? = nil
    var intensity: Int? = nil

    init(deviceId: String, mode: ColorMode) {
        self.deviceId = deviceId
        self.mode = mode
    }
}


