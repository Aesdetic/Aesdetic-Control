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
struct WLEDStateUpdate: Codable {
    /// Power state (on/off)
    let on: Bool?
    /// Brightness (0-255)
    let bri: Int?
    /// Array of segment updates
    let seg: [SegmentUpdate]?
    /// Transition time in deciseconds (0.1s units)
    let transition: Int?
    /// Preset ID to apply (-1 = no preset)
    let ps: Int?
    /// Playlist ID to apply (-1 = no playlist)  
    let pl: Int?
    /// Night light settings
    let nl: NightLightUpdate?
    /// UDP sync settings
    let udpn: UDPSyncUpdate?
    /// Live data override
    let lor: Int?
    /// Main segment ID
    let mainseg: Int?
    /// Live data override mode
    let lormode: Int?
    
    init(on: Bool? = nil, bri: Int? = nil, seg: [SegmentUpdate]? = nil, transition: Int? = nil, 
         ps: Int? = nil, pl: Int? = nil, nl: NightLightUpdate? = nil, udpn: UDPSyncUpdate? = nil,
         lor: Int? = nil, mainseg: Int? = nil, lormode: Int? = nil) {
        self.on = on
        self.bri = bri
        self.seg = seg
        self.transition = transition
        self.ps = ps
        self.pl = pl
        self.nl = nl
        self.udpn = udpn
        self.lor = lor
        self.mainseg = mainseg
        self.lormode = lormode
    }
}

/// Model for updating night light settings
struct NightLightUpdate: Codable {
    let on: Bool?           // Enable/disable night light
    let dur: Int?           // Duration in minutes
    let mode: Int?          // Fade mode (0=instant, 1=fade, 2=color fade, 3=sunrise)
    let tbri: Int?          // Target brightness
}

/// Model for updating UDP sync settings
struct UDPSyncUpdate: Codable {
    let send: Bool?         // Send UDP sync packets
    let recv: Bool?         // Receive UDP sync packets
    let sgrp: Int?          // Sync groups bitmask
    let rgrp: Int?          // Receive groups bitmask
}

/// Model for updating specific WLED segments
struct SegmentUpdate: Codable {
    /// Segment ID (0-based)
    let id: Int?
    /// Colors array (RGB values)
    let col: [[Int]]?
    /// Effect ID
    let fx: Int?
    /// Effect speed (0-255)
    let sx: Int?
    /// Effect intensity (0-255)
    let ix: Int?
    /// Palette ID
    let pal: Int?
    /// Segment selection
    let sel: Bool?
    /// Reverse direction
    let rev: Bool?
    
    init(id: Int? = nil, col: [[Int]]? = nil, fx: Int? = nil, sx: Int? = nil, ix: Int? = nil, pal: Int? = nil, sel: Bool? = nil, rev: Bool? = nil) {
        self.id = id
        self.col = col
        self.fx = fx
        self.sx = sx
        self.ix = ix
        self.pal = pal
        self.sel = sel
        self.rev = rev
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