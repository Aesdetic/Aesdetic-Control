//
//  CapabilityDetector.swift
//  Aesdetic-Control
//
//  Created on 2025-10-31
//  Actor for detecting and caching WLED device capabilities
//

import Foundation
import OSLog

/// Thread-safe actor for detecting and caching WLED device capabilities
actor CapabilityDetector {
    
    // MARK: - Properties
    
    /// Logger for capability detection
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "CapabilityDetector")
    
    /// Cache of device capabilities indexed by device ID
    private var capabilitiesCache: [String: WLEDCapabilities] = [:]
    
    /// Singleton instance
    static let shared = CapabilityDetector()
    
    private init() {}
    
    // MARK: - Detection Methods
    
    /// Detect and cache capabilities from WLED response
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - seglc: Array of segment capability flags from info.leds.seglc
    /// - Returns: Detected capabilities
    @discardableResult
    func detect(deviceId: String, seglc: [Int]?) -> WLEDCapabilities {
        guard let seglc = seglc, !seglc.isEmpty else {
            // No seglc data - assume basic RGB-only strip
            logger.debug("No seglc data for device \(deviceId), assuming RGB-only")
            let fallback = WLEDCapabilities(deviceId: deviceId, seglc: [1]) // 0b001 = RGB only
            capabilitiesCache[deviceId] = fallback
            return fallback
        }
        
        let capabilities = WLEDCapabilities(deviceId: deviceId, seglc: seglc)
        capabilitiesCache[deviceId] = capabilities
        
        logger.info("Detected capabilities for \(deviceId): \(capabilities.segments.count) segments")
        for (segId, segCap) in capabilities.segments {
            logger.debug("  Segment \(segId): \(segCap.description)")
        }
        
        return capabilities
    }
    
    /// Get cached capabilities for a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Cached capabilities or nil if not yet detected
    func getCached(deviceId: String) -> WLEDCapabilities? {
        return capabilitiesCache[deviceId]
    }
    
    /// Get capabilities for a specific segment, with fallback
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - segmentId: Segment index (default: 0)
    /// - Returns: Segment capabilities or RGB-only fallback
    func getSegmentCapabilities(deviceId: String, segmentId: Int = 0) -> SegmentCapabilities {
        guard let capabilities = capabilitiesCache[deviceId],
              let segmentCap = capabilities.capabilities(for: segmentId) else {
            // Fallback to RGB-only if not detected
            return SegmentCapabilities.rgbOnly
        }
        return segmentCap
    }
    
    /// Clear cached capabilities for a device (useful when device is removed)
    /// - Parameter deviceId: Device identifier
    func clearCache(for deviceId: String) {
        capabilitiesCache.removeValue(forKey: deviceId)
        logger.debug("Cleared capability cache for \(deviceId)")
    }
    
    /// Clear all cached capabilities
    func clearAllCaches() {
        capabilitiesCache.removeAll()
        logger.debug("Cleared all capability caches")
    }
    
    // MARK: - UI Helper Methods
    
    /// Check if white channel slider should be shown
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - segmentId: Segment index (default: 0)
    /// - Returns: True if white channel is supported
    func shouldShowWhiteSlider(for deviceId: String, segmentId: Int = 0) -> Bool {
        let capabilities = getSegmentCapabilities(deviceId: deviceId, segmentId: segmentId)
        return capabilities.supportsWhite
    }
    
    /// Check if CCT (temperature) slider should be shown
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - segmentId: Segment index (default: 0)
    /// - Returns: True if CCT is supported
    func shouldShowCCTSlider(for deviceId: String, segmentId: Int = 0) -> Bool {
        let capabilities = getSegmentCapabilities(deviceId: deviceId, segmentId: segmentId)
        return capabilities.supportsCCT
    }
    
    /// Check if RGB color controls should be shown
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - segmentId: Segment index (default: 0)
    /// - Returns: True if RGB is supported
    func shouldShowRGBControls(for deviceId: String, segmentId: Int = 0) -> Bool {
        let capabilities = getSegmentCapabilities(deviceId: deviceId, segmentId: segmentId)
        return capabilities.supportsRGB
    }
    
    /// Get human-readable capability description
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - segmentId: Segment index (default: 0)
    /// - Returns: Description string (e.g., "RGB, White, CCT")
    func getCapabilityDescription(for deviceId: String, segmentId: Int = 0) -> String {
        let capabilities = getSegmentCapabilities(deviceId: deviceId, segmentId: segmentId)
        return capabilities.description
    }
    
    /// Get number of segments for a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Number of segments or 1 if not detected
    func getSegmentCount(for deviceId: String) -> Int {
        guard let capabilities = capabilitiesCache[deviceId] else {
            return 1 // Default to single segment
        }
        return capabilities.segments.count
    }
    
    /// Check if device has multiple segments
    /// - Parameter deviceId: Device identifier
    /// - Returns: True if device has more than one segment
    func hasMultipleSegments(for deviceId: String) -> Bool {
        return getSegmentCount(for: deviceId) > 1
    }
}

