//  WLEDAPIModels.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import SwiftUI

// MARK: - API Request Models

/// Model for updating WLED device state via API
/// - Note: Top-level `transition` (ms) is honored by WLED for solid/preset jumps.
struct WLEDStateUpdate: Codable {
    /// Power state (on/off)
    let on: Bool?
    /// Brightness (0-255)
    let bri: Int?
    /// Array of segment updates
    let seg: [SegmentUpdate]?
    let udpn: UDPNUpdate?
    /// Transition time in milliseconds
    let transition: Int?
    /// Apply preset by ID
    let ps: Int?
    /// Night Light configuration
    let nl: NightLightUpdate?
    /// Live override release (0 disables realtime streaming)
    let lor: Int?
    
    init(on: Bool? = nil, bri: Int? = nil, seg: [SegmentUpdate]? = nil, udpn: UDPNUpdate? = nil, transition: Int? = nil, ps: Int? = nil, nl: NightLightUpdate? = nil, lor: Int? = nil) {
        self.on = on
        self.bri = bri
        self.seg = seg
        self.udpn = udpn
        self.transition = transition
        self.ps = ps
        self.nl = nl
        self.lor = lor
    }
}

// UDP sync options
struct UDPNUpdate: Codable {
    let send: Bool?
    let recv: Bool?
    let nn: Int?
}

// Night Light update
struct NightLightUpdate: Codable {
    let on: Bool?
    let dur: Int?
    let mode: Int?
    let tbri: Int?
}

/// Model for updating specific WLED segments
struct SegmentUpdate: Codable {
    // Identification
    let id: Int?

    // Bounds and options
    let start: Int?
    let stop: Int?
    let len: Int?
    let grp: Int?
    let spc: Int?
    let ofs: Int?

    // State
    let on: Bool?
    let bri: Int?
    let col: [[Int]]?
    /// Color temperature (0-255, 0=warm, 255=cool)
    let cct: Int?

    // Effect
    let fx: Int?
    let sx: Int?
    let ix: Int?
    let pal: Int?

    // Flags
    let sel: Bool?
    let rev: Bool?
    let mi: Bool?
    let cln: Int?
    /// Freeze flag: true = freeze segment (stop animations), false = resume
    let frz: Bool?

    init(
        id: Int? = nil,
        start: Int? = nil,
        stop: Int? = nil,
        len: Int? = nil,
        grp: Int? = nil,
        spc: Int? = nil,
        ofs: Int? = nil,
        on: Bool? = nil,
        bri: Int? = nil,
        col: [[Int]]? = nil,
        cct: Int? = nil,
        fx: Int? = nil,
        sx: Int? = nil,
        ix: Int? = nil,
        pal: Int? = nil,
        sel: Bool? = nil,
        rev: Bool? = nil,
        mi: Bool? = nil,
        cln: Int? = nil,
        frz: Bool? = nil
    ) {
        self.id = id
        self.start = start
        self.stop = stop
        self.len = len
        self.grp = grp
        self.spc = spc
        self.ofs = ofs
        self.on = on
        self.bri = bri
        self.col = col
        self.cct = cct
        self.fx = fx
        self.sx = sx
        self.ix = ix
        self.pal = pal
        self.sel = sel
        self.rev = rev
        self.mi = mi
        self.cln = cln
        self.frz = frz
    }
    
    // CRITICAL: Custom encoding to omit col when nil
    // WLED ignores CCT if col is present (even as null)
    // So we must completely omit col when sending CCT-only updates
    enum CodingKeys: String, CodingKey {
        case id, start, stop, len, grp, spc, ofs
        case on, bri, col, cct
        case fx, sx, ix, pal
        case sel, rev, mi, cln, frz
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Only encode col if it's not nil
        // This ensures CCT-only updates don't include col: null
        if let col = col {
            try container.encode(col, forKey: .col)
        }
        // Explicitly don't encode col if nil - this omits it from JSON
        
        // Encode all other fields if they're not nil
        try id.map { try container.encode($0, forKey: .id) }
        try start.map { try container.encode($0, forKey: .start) }
        try stop.map { try container.encode($0, forKey: .stop) }
        try len.map { try container.encode($0, forKey: .len) }
        try grp.map { try container.encode($0, forKey: .grp) }
        try spc.map { try container.encode($0, forKey: .spc) }
        try ofs.map { try container.encode($0, forKey: .ofs) }
        try on.map { try container.encode($0, forKey: .on) }
        try bri.map { try container.encode($0, forKey: .bri) }
        try cct.map { try container.encode($0, forKey: .cct) }
        try fx.map { try container.encode($0, forKey: .fx) }
        try sx.map { try container.encode($0, forKey: .sx) }
        try ix.map { try container.encode($0, forKey: .ix) }
        try pal.map { try container.encode($0, forKey: .pal) }
        try sel.map { try container.encode($0, forKey: .sel) }
        try rev.map { try container.encode($0, forKey: .rev) }
        try mi.map { try container.encode($0, forKey: .mi) }
        try cln.map { try container.encode($0, forKey: .cln) }
        try frz.map { try container.encode($0, forKey: .frz) }
    }
}

// MARK: - API Response Models (Extended)

/// Extended WLED response with additional API metadata
struct WLEDAPIResponse: Codable {
    let success: Bool
    let data: WLEDResponse?
    let error: String?
    
    init(success: Bool, data: WLEDResponse? = nil, error: String? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }
}

struct WLEDSuccessResponse: Codable {
    let success: Bool
}

// MARK: - Future API Models (Prepared for extension)

/// Model for WLED effects management (future use)
struct WLEDEffect: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
}

/// Model for WLED presets management (future use)
struct WLEDPreset: Codable, Identifiable {
    let id: Int
    let name: String
    let quickLoad: Bool?
    let segment: SegmentUpdate?
}

struct WLEDPresetSaveRequest {
    let id: Int
    let name: String
    let quickLoad: Bool?
    let state: WLEDStateUpdate?
}

/// Model for WLED playlist management (future use)
struct WLEDPlaylist: Codable, Identifiable {
    let id: Int
    let name: String
    let presets: [Int]
    let duration: [Int]
    let transition: [Int]
    let `repeat`: Int?
}

// MARK: - API Configuration Models

/// Configuration for WLED API client
struct WLEDAPIConfiguration {
    let timeoutInterval: TimeInterval
    let maxRetries: Int
    let retryDelay: TimeInterval
    let enableLogging: Bool
    
    static let `default` = WLEDAPIConfiguration(
        timeoutInterval: 10.0,
        maxRetries: 3,
        retryDelay: 1.0,
        enableLogging: true
    )
}

// MARK: - Color Conversion Extensions

extension Color {    
    /// Convert Color to RGBW array for WLED API (with white channel)
    func toRGBWArray() -> [Int] {
        let rgb = toRGBArray()
        let white = min(rgb[0], rgb[1], rgb[2]) // Simple white extraction
        return [rgb[0], rgb[1], rgb[2], white]
    }
    
    /// Create Color from RGB array received from WLED API
    static func fromRGBArray(_ rgb: [Int]) -> Color {
        guard rgb.count >= 3 else { return .black }
        
        let red = Double(max(0, min(255, rgb[0]))) / 255.0
        let green = Double(max(0, min(255, rgb[1]))) / 255.0
        let blue = Double(max(0, min(255, rgb[2]))) / 255.0
        
        return Color(red: red, green: green, blue: blue)
    }
    static func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ar = a.toRGBArray()
        let br = b.toRGBArray()
        func mix(_ x: Int, _ y: Int) -> Double { Double(x) * (1 - t) + Double(y) * t }
        return Color(
            red: mix(ar[0], br[0]) / 255.0,
            green: mix(ar[1], br[1]) / 255.0,
            blue: mix(ar[2], br[2]) / 255.0
        )
    }
}

// MARK: - WebSocket Models

/// WLED device info from WebSocket response
struct WLEDInfo: Codable {
    let name: String
    let mac: String
    let version: String
    let brand: String?
    let product: String?
    let uptime: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, mac
        case version = "ver"
        case brand, product
        case uptime = "uptime"
    }
}

/// Device state update model for real-time synchronization
struct WLEDDeviceStateUpdate {
    let deviceId: String
    let state: WLEDState?
    let info: WLEDInfo?
    let timestamp: Date
    
    init(deviceId: String, state: WLEDState? = nil, info: WLEDInfo? = nil, timestamp: Date = Date()) {
        self.deviceId = deviceId
        self.state = state
        self.info = info
        self.timestamp = timestamp
    }
}

// MARK: - Configuration Models

/// Model for updating WLED device configuration
/// Used to change device name (server description) and other settings
struct WLEDConfigUpdate: Codable {
    /// Device/Server description (the name shown in UI)
    let name: String?
    
    init(name: String? = nil) {
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case name = "server-name"
    }
}

// MARK: - LED Configuration Models

/// LED hardware configuration for WLED devices
struct LEDConfiguration: Codable {
    /// LED strip type (WS281x, SK6812, etc.)
    let stripType: Int
    /// Color order (GRB, RGB, BRG, etc.)
    let colorOrder: Int
    /// GPIO pin for data
    let gpioPin: Int
    /// Number of LEDs
    let ledCount: Int
    /// Start LED index
    let startLED: Int
    /// Skip first N LEDs
    let skipFirstLEDs: Int
    /// Reverse direction
    let reverseDirection: Bool
    /// Refresh when off
    let offRefresh: Bool
    /// Auto white mode (0=none, 1=brighter, 2=accurate, 3=dual, 4=max)
    let autoWhiteMode: Int
    /// Maximum current per LED in mA
    let maxCurrentPerLED: Int
    /// Maximum total current in mA
    let maxTotalCurrent: Int
    /// Use per-output limiter
    let usePerOutputLimiter: Bool
    /// Enable automatic brightness limiter
    let enableABL: Bool
    
    enum CodingKeys: String, CodingKey {
        case stripType = "type"
        case colorOrder = "co"
        case gpioPin = "pin"
        case ledCount = "len"
        case startLED = "start"
        case skipFirstLEDs = "skip"
        case reverseDirection = "rev"
        case offRefresh = "rf"
        case autoWhiteMode = "aw"
        case maxCurrentPerLED = "la"
        case maxTotalCurrent = "ma"
        case usePerOutputLimiter = "per"
        case enableABL = "abl"
    }
}

/// LED strip types supported by WLED
enum LEDStripType: Int, CaseIterable, Codable {
    case ws281x = 0
    case sk6812 = 1
    case tm1814 = 2
    case ws2801 = 3
    case apa102 = 4
    case lpd8806 = 5
    case tm1829 = 6
    case ucs8903 = 7
    case apa106 = 8
    case tm1914 = 9
    case fw1906 = 10
    case ucs8904 = 11
    case ws2805 = 12
    case sm16825 = 13
    case ws2811White = 14
    case ws281xWWA = 15
    
    var displayName: String {
        switch self {
        case .ws281x: return "WS281x"
        case .sk6812: return "SK6812/WS2814 RGBW"
        case .tm1814: return "TM1814"
        case .ws2801: return "WS2801"
        case .apa102: return "APA102"
        case .lpd8806: return "LPD8806"
        case .tm1829: return "TM1829"
        case .ucs8903: return "UCS8903"
        case .apa106: return "APA106/PL9823"
        case .tm1914: return "TM1914"
        case .fw1906: return "FW1906 GRBCW"
        case .ucs8904: return "UCS8904 RGBW"
        case .ws2805: return "WS2805 RGBCW"
        case .sm16825: return "SM16825 RGBCW"
        case .ws2811White: return "WS2811 White"
        case .ws281xWWA: return "WS281x WWA"
        }
    }
    
    var description: String {
        switch self {
        case .ws281x: return "Standard WS2812/WS2813 RGB LEDs"
        case .sk6812: return "SK6812/WS2814 RGBW LEDs with white channel"
        case .tm1814: return "TM1814 RGB LEDs"
        case .ws2801: return "WS2801 RGB LEDs (3-wire)"
        case .apa102: return "APA102 RGB LEDs (4-wire)"
        case .lpd8806: return "LPD8806 RGB LEDs"
        case .tm1829: return "TM1829 RGB LEDs"
        case .ucs8903: return "UCS8903 RGB LEDs"
        case .apa106: return "APA106/PL9823 RGB LEDs"
        case .tm1914: return "TM1914 RGB LEDs"
        case .fw1906: return "FW1906 GRBCW LEDs"
        case .ucs8904: return "UCS8904 RGBW LEDs"
        case .ws2805: return "WS2805 RGBCW LEDs"
        case .sm16825: return "SM16825 RGBCW LEDs"
        case .ws2811White: return "WS2811 White LEDs"
        case .ws281xWWA: return "WS281x Warm White Amber LEDs"
        }
    }
}

/// Color order options for LED strips
enum LEDColorOrder: Int, CaseIterable, Codable {
    case grb = 0
    case rgb = 1
    case brg = 2
    case grbw = 3
    case rgbw = 4
    
    var displayName: String {
        switch self {
        case .grb: return "GRB"
        case .rgb: return "RGB"
        case .brg: return "BRG"
        case .grbw: return "GRBW"
        case .rgbw: return "RGBW"
        }
    }
    
    var description: String {
        switch self {
        case .grb: return "Green-Red-Blue (most common)"
        case .rgb: return "Red-Green-Blue"
        case .brg: return "Blue-Red-Green"
        case .grbw: return "Green-Red-Blue-White"
        case .rgbw: return "Red-Green-Blue-White"
        }
    }
}

/// Auto white mode options
enum AutoWhiteMode: Int, CaseIterable, Codable {
    case none = 0
    case brighter = 1
    case accurate = 2
    case dual = 3
    case max = 4
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .brighter: return "Brighter"
        case .accurate: return "Accurate"
        case .dual: return "Dual"
        case .max: return "Max"
        }
    }
    
    var description: String {
        switch self {
        case .none: return "No auto white calculation"
        case .brighter: return "Brighter white calculation"
        case .accurate: return "Accurate white calculation"
        case .dual: return "Dual white calculation"
        case .max: return "Maximum white calculation"
        }
    }
} 