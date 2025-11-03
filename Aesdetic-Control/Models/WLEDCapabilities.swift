//
//  WLEDCapabilities.swift
//  Aesdetic-Control
//
//  Created on 2025-10-31
//  Centralized WLED device capability detection and feature flags
//

import Foundation

/// Represents the capabilities of a WLED device based on info.leds.seglc
/// seglc is an array of integers where each bit represents a capability:
/// - Bit 0 (0b001 = 1): RGB support
/// - Bit 1 (0b010 = 2): White channel (W) support
/// - Bit 2 (0b100 = 4): CCT (Correlated Color Temperature) support
struct WLEDCapabilities: Codable, Equatable {
    /// Device ID this capability set belongs to
    let deviceId: String
    
    /// Segment capabilities indexed by segment ID
    var segments: [Int: SegmentCapabilities]
    
    /// Timestamp when capabilities were last detected
    var lastUpdated: Date
    
    /// Initialize with device ID and empty segments
    init(deviceId: String) {
        self.deviceId = deviceId
        self.segments = [:]
        self.lastUpdated = Date()
    }
    
    /// Initialize from WLED info.leds.seglc array
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - seglc: Array of segment capability flags from WLED
    init(deviceId: String, seglc: [Int]) {
        self.deviceId = deviceId
        self.segments = [:]
        self.lastUpdated = Date()
        
        // Parse each segment's capabilities
        for (index, flags) in seglc.enumerated() {
            self.segments[index] = SegmentCapabilities(flags: flags)
        }
    }
    
    /// Get capabilities for a specific segment
    /// - Parameter segmentId: Segment index (default: 0)
    /// - Returns: Segment capabilities or nil if segment doesn't exist
    func capabilities(for segmentId: Int = 0) -> SegmentCapabilities? {
        return segments[segmentId]
    }
    
    /// Check if device has any segments with specific capability
    /// - Parameter check: Closure to test capability
    /// - Returns: True if any segment matches
    func hasAnySegment(where check: (SegmentCapabilities) -> Bool) -> Bool {
        return segments.values.contains(where: check)
    }
}

/// Capabilities for a single WLED segment
struct SegmentCapabilities: Codable, Equatable {
    /// Raw capability flags from WLED
    let rawFlags: Int
    
    /// RGB color support (bit 0)
    let supportsRGB: Bool
    
    /// White channel support (bit 1) - for RGBW strips
    let supportsWhite: Bool
    
    /// CCT support (bit 2) - for tunable white/RGBCW strips
    let supportsCCT: Bool
    
    /// Initialize from raw WLED capability flags
    /// - Parameter flags: Integer with bit flags from info.leds.seglc
    init(flags: Int) {
        self.rawFlags = flags
        self.supportsRGB = (flags & 0b001) != 0    // Bit 0
        self.supportsWhite = (flags & 0b010) != 0  // Bit 1
        self.supportsCCT = (flags & 0b100) != 0    // Bit 2
    }
    
    /// Convenience initializer for testing
    init(rgb: Bool = true, white: Bool = false, cct: Bool = false) {
        var flags = 0
        if rgb { flags |= 0b001 }
        if white { flags |= 0b010 }
        if cct { flags |= 0b100 }
        
        self.rawFlags = flags
        self.supportsRGB = rgb
        self.supportsWhite = white
        self.supportsCCT = cct
    }
    
    /// Human-readable description of capabilities
    var description: String {
        var parts: [String] = []
        if supportsRGB { parts.append("RGB") }
        if supportsWhite { parts.append("White") }
        if supportsCCT { parts.append("CCT") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
    
    /// Check if this is a basic RGB-only strip
    var isRGBOnly: Bool {
        return supportsRGB && !supportsWhite && !supportsCCT
    }
    
    /// Check if this is an RGBW strip (RGB + White)
    var isRGBW: Bool {
        return supportsRGB && supportsWhite && !supportsCCT
    }
    
    /// Check if this is an RGBCW strip (RGB + CCT)
    var isRGBCCT: Bool {
        return supportsRGB && supportsCCT
    }
    
    /// Check if this is a tunable white strip (White + CCT, no RGB)
    var isTunableWhiteOnly: Bool {
        return !supportsRGB && supportsWhite && supportsCCT
    }
}

// MARK: - Example Capability Flags

extension SegmentCapabilities {
    /// Common strip type examples
    static let rgbOnly = SegmentCapabilities(flags: 0b001)      // 1
    static let rgbw = SegmentCapabilities(flags: 0b011)         // 3 (RGB + White)
    static let rgbcct = SegmentCapabilities(flags: 0b101)       // 5 (RGB + CCT)
    static let rgbwcct = SegmentCapabilities(flags: 0b111)      // 7 (RGB + White + CCT)
    static let tunableWhite = SegmentCapabilities(flags: 0b110) // 6 (White + CCT, no RGB)
}



