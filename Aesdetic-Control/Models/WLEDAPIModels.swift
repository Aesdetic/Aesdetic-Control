//
//  WLEDAPIModels.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import SwiftUI
import UIKit

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
    
    init(on: Bool? = nil, bri: Int? = nil, seg: [SegmentUpdate]? = nil, udpn: UDPNUpdate? = nil, transition: Int? = nil, ps: Int? = nil, nl: NightLightUpdate? = nil) {
        self.on = on
        self.bri = bri
        self.seg = seg
        self.udpn = udpn
        self.transition = transition
        self.ps = ps
        self.nl = nl
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