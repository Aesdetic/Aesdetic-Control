//
//  WLEDDevice.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import SwiftUI

struct WLEDDevice: Identifiable, Hashable {
    let id: String // mac address
    var name: String
    var ipAddress: String
    var isOnline: Bool
    var brightness: Int // 0-255 from API
    var currentColor: Color // Derived from state
    var temperature: Double? // Color temperature (0.0-1.0, from CCT 0-255)
    var productType: ProductType
    var location: DeviceLocation
    var lastSeen: Date
    var state: WLEDState?
    
    
    // Computed property for device on/off state
    var isOn: Bool {
        get {
            return state?.isOn ?? false
        }
        set {
            // Update the state if it exists, otherwise create a new one
            if var currentState = state {
                currentState = WLEDState(
                    brightness: currentState.brightness,
                    isOn: newValue,
                    segments: currentState.segments
                )
                state = currentState
            } else {
                // Create a basic state if none exists
                state = WLEDState(
                    brightness: brightness,
                    isOn: newValue,
                    segments: []
                )
            }
        }
    }
    
    // Conformance to Hashable
    static func == (lhs: WLEDDevice, rhs: WLEDDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    init(id: String, name: String, ipAddress: String, isOnline: Bool = false, brightness: Int = 0, currentColor: Color = .black, temperature: Double? = nil, productType: ProductType = .generic, location: DeviceLocation = .all, lastSeen: Date = Date(), state: WLEDState? = nil) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.isOnline = isOnline
        self.brightness = brightness
        self.currentColor = currentColor
        self.temperature = temperature
        self.productType = productType
        self.location = location
        self.lastSeen = lastSeen
        self.state = state
    }
    
    // WLED API endpoints
    var jsonEndpoint: String {
        return "http://\(ipAddress)/json"
    }
    
    var websocketEndpoint: String {
        return "ws://\(ipAddress)/ws"
    }
}

// MARK: - Codable Models for WLED JSON Response
// Corrected based on official WLED JSON API documentation to prevent parsing crashes.

struct WLEDResponse: Codable {
    let info: Info
    let state: WLEDState
}

struct Info: Codable {
    let name: String
    let mac: String
    let ver: String
    let leds: LedInfo
}

struct LedInfo: Codable {
    let count: Int
    // Segment LED capabilities (array) - optional, present on newer WLED builds
    // Bit 2 (0b100) indicates CCT/temperature capability for the segment.
    let seglc: [Int]?
}

struct WLEDState: Codable {
    let brightness: Int
    let isOn: Bool
    let segments: [Segment]

    enum CodingKeys: String, CodingKey {
        case brightness = "bri"
        case isOn = "on"
        case segments = "seg"
    }
}

struct Segment: Codable {
    // Most fields are optional for robust decoding, preventing crashes if the JSON is missing keys.
    let id: Int?
    let start: Int?
    let stop: Int?
    let len: Int?
    let grp: Int?
    let spc: Int?
    let ofs: Int?
    let on: Bool?
    let bri: Int?
    let colors: [[Int]]?
    let cct: Int?  // Color temperature (0-255 relative or Kelvin)
    let fx: Int?
    let sx: Int?
    let ix: Int?
    let pal: Int?
    let sel: Bool?
    let rev: Bool?
    let mi: Bool?
    let cln: Int?
    /// Freeze flag: true = freeze segment (stop animations), false = resume
    let frz: Bool?

    private static let kelvinMin: Double = 1000.0
    private static let kelvinMax: Double = 20000.0
    private static let kelvinRange: Double = kelvinMax - kelvinMin

    static func kelvinValue(fromNormalized normalized: Double) -> Int {
        let clamped = min(max(normalized, 0.0), 1.0)
        return Int(round(kelvinMin + clamped * kelvinRange))
    }

    static func eightBitValue(fromNormalized normalized: Double) -> Int {
        let clamped = min(max(normalized, 0.0), 1.0)
        return Int(round(clamped * 255.0))
    }

    var cctIsKelvin: Bool {
        guard let cct = cct else { return false }
        return cct >= 1000
    }

    var cctKelvinValue: Int? {
        cctIsKelvin ? cct : nil
    }

    var cctEightBitValue: Int? {
        guard let cct = cct, !cctIsKelvin else { return nil }
        return cct
    }

    var cctNormalized: Double? {
        guard let cct = cct else { return nil }
        if cctIsKelvin {
            let value = min(max(Double(cct), Self.kelvinMin), Self.kelvinMax)
            return (value - Self.kelvinMin) / Self.kelvinRange
        } else {
            return Double(cct) / 255.0
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, start, stop, len, grp, spc, ofs, on, bri
        case colors = "col"
        case cct
        case fx, sx, ix, pal, sel, rev, mi, cln, frz
    }
}

enum ProductType: String, CaseIterable, Codable {
    case sunriseLamp = "sunrise_lamp"
    case deskStrip = "desk_strip"
    case ambianceStrip = "ambiance_strip"
    case ceilingPanel = "ceiling_panel"
    case generic = "generic"
    
    var displayName: String {
        switch self {
        case .sunriseLamp:
            return "Sunrise Lamp"
        case .deskStrip:
            return "Desk Strip"
        case .ambianceStrip:
            return "Ambiance Strip"
        case .ceilingPanel:
            return "Ceiling Panel"
        case .generic:
            return "WLED Device"
        }
    }
    
    var systemImage: String {
        switch self {
        case .sunriseLamp:
            return "sun.max.fill"
        case .deskStrip:
            return "lightbulb.fill"
        case .ambianceStrip:
            return "light.strip.horizontal"
        case .ceilingPanel:
            return "light.panel.fill"
        case .generic:
            return "lightbulb"
        }
    }
}

enum DeviceLocation: Hashable, Codable {
    case all
    case livingRoom
    case bedroom
    case kitchen
    case office
    case hallway
    case bathroom
    case outdoor
    case custom(String)
    
    static var allCases: [DeviceLocation] {
        return [.all, .livingRoom, .bedroom, .kitchen, .office, .hallway, .bathroom, .outdoor]
    }
    
    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .livingRoom:
            return "Living Room"
        case .bedroom:
            return "Bedroom"
        case .kitchen:
            return "Kitchen"
        case .office:
            return "Office"
        case .hallway:
            return "Hallway"
        case .bathroom:
            return "Bathroom"
        case .outdoor:
            return "Outdoor"
        case .custom(let name):
            return name
        }
    }
    
    var rawValue: String {
        switch self {
        case .all:
            return "all"
        case .livingRoom:
            return "living_room"
        case .bedroom:
            return "bedroom"
        case .kitchen:
            return "kitchen"
        case .office:
            return "office"
        case .hallway:
            return "hallway"
        case .bathroom:
            return "bathroom"
        case .outdoor:
            return "outdoor"
        case .custom(let name):
            return "custom_\(name)"
        }
    }
    
    init(rawValue: String) {
        switch rawValue {
        case "all":
            self = .all
        case "living_room":
            self = .livingRoom
        case "bedroom":
            self = .bedroom
        case "kitchen":
            self = .kitchen
        case "office":
            self = .office
        case "hallway":
            self = .hallway
        case "bathroom":
            self = .bathroom
        case "outdoor":
            self = .outdoor
        default:
            if rawValue.hasPrefix("custom_") {
                let customName = String(rawValue.dropFirst(7)) // Remove "custom_" prefix
                self = .custom(customName)
            } else {
                self = .bedroom // Default fallback
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self.init(rawValue: rawValue)
    }
    
    var systemImage: String {
        switch self {
        case .all:
            return "house"
        case .livingRoom:
            return "sofa"
        case .bedroom:
            return "bed.double"
        case .kitchen:
            return "refrigerator"
        case .office:
            return "desktopcomputer"
        case .hallway:
            return "door.left.hand.open"
        case .bathroom:
            return "bathtub"
        case .outdoor:
            return "tree"
        case .custom:
            return "house"
        }
    }
}

// Extension for Color Codable support
extension Color: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        self = Color(hex: hex)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.toHex())
    }
}

// Helper extensions for Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        // CRITICAL FIX: Use toRGBArray() which correctly extracts sRGB values
        // DO NOT use cgColor.components directly - it may be in P3 color space
        // on wide-gamut displays, giving wrong hex values (orange #FFA000 → yellow #FFFF00)
        let rgb = self.toRGBArray()
        guard rgb.count >= 3 else { return "000000" }
        return String(format: "%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }
    
    func toRGBArray() -> [Int] {
        // Handle common SwiftUI colors explicitly for reliability
        if self == .red { return [255, 0, 0] }
        if self == .green { return [0, 255, 0] }
        if self == .blue { return [0, 0, 255] }
        if self == .white { return [255, 255, 255] }
        if self == .black { return [0, 0, 0] }
        if self == .yellow { return [255, 255, 0] }
        if self == .orange { return [255, 165, 0] }
        if self == .purple { return [128, 0, 128] }
        if self == .pink { return [255, 192, 203] }
        
        // CRITICAL FIX: Force conversion to sRGB before extracting RGB values
        // This ensures we always get sRGB values, even if Color was created in P3 space
        guard let cgColor = self.cgColor,
              let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let sRGBColor = cgColor.converted(to: sRGBColorSpace, intent: .defaultIntent, options: nil),
              let components = sRGBColor.components, components.count >= 3 else {
            // Fallback: try UIColor.getRed() if CGColor conversion fails
            let uiColor = UIColor(self)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            
            if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                return [
                    Int((red * 255).rounded()),
                    Int((green * 255).rounded()),
                    Int((blue * 255).rounded())
                ]
            }
            return [0, 0, 0] // Black fallback
        }
        
        // Extract sRGB components (guaranteed to be in sRGB color space)
        let redInt = Int((components[0] * 255).rounded())
        let greenInt = Int((components[1] * 255).rounded())
        let blueInt = Int((components[2] * 255).rounded())
        
        return [redInt, greenInt, blueInt]
    }
}