//
//  CapabilityDetectorTests.swift
//  Aesdetic-ControlTests
//
//  Created on 2025-01-27
//  Tests for CapabilityDetector actor
//

import Testing
@testable import Aesdetic_Control

struct CapabilityDetectorTests {
    
    // MARK: - CCT Detection Tests
    
    @Test("Detect CCT support from seglc bit 2 (0b100)")
    func testCCTDetection() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-cct"
        
        // seglc = 5 means bits 0 and 2 set (0b101 = RGB + CCT)
        // Note: seglc = 4 (0b100) means CCT-only without RGB
        let seglc = [5]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsCCT == true, "CCT should be detected from seglc bit 2")
        #expect(segmentCap.supportsRGB == true, "RGB should be supported when bit 0 is set")
        #expect(await detector.shouldShowCCTSlider(for: deviceId, segmentId: 0) == true)
        
        await detector.clearCache(for: deviceId)
    }
    
    @Test("No CCT support when bit 2 not set")
    func testNoCCTDetection() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-no-cct"
        
        // seglc = 1 means only RGB (0b001)
        let seglc = [1]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsCCT == false, "CCT should not be detected")
        #expect(segmentCap.supportsRGB == true, "RGB should still be supported")
        #expect(await detector.shouldShowCCTSlider(for: deviceId, segmentId: 0) == false)
        
        await detector.clearCache(for: deviceId)
    }
    
    // MARK: - White Channel Detection Tests
    
    @Test("Detect white channel support from seglc bit 1 (0b010)")
    func testWhiteChannelDetection() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-white"
        
        // seglc = 3 means bits 0 and 1 set (0b011 = RGB + White)
        // Note: Bit 1 alone (0b010 = 2) means White-only without RGB
        let seglc = [3]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsWhite == true, "White channel should be detected from seglc bit 1")
        #expect(segmentCap.supportsRGB == true, "RGB should be supported when bit 0 is set")
        #expect(await detector.shouldShowWhiteSlider(for: deviceId, segmentId: 0) == true)
        
        await detector.clearCache(for: deviceId)
    }
    
    @Test("RGBW detection (RGB + White channel)")
    func testRGBWDetection() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-rgbw"
        
        // seglc = 3 means bits 0 and 1 set (0b011 = RGB + White)
        let seglc = [3]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsRGB == true)
        #expect(segmentCap.supportsWhite == true)
        #expect(segmentCap.supportsCCT == false)
        #expect(await detector.shouldShowWhiteSlider(for: deviceId, segmentId: 0) == true)
        #expect(await detector.shouldShowRGBControls(for: deviceId, segmentId: 0) == true)
        
        await detector.clearCache(for: deviceId)
    }
    
    // MARK: - RGB Detection Tests
    
    @Test("RGB-only detection (bit 0 set)")
    func testRGBOnlyDetection() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-rgb"
        
        // seglc = 1 means only bit 0 set (0b001 = RGB only)
        let seglc = [1]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsRGB == true)
        #expect(segmentCap.supportsWhite == false)
        #expect(segmentCap.supportsCCT == false)
        #expect(await detector.shouldShowRGBControls(for: deviceId, segmentId: 0) == true)
        #expect(await detector.shouldShowWhiteSlider(for: deviceId, segmentId: 0) == false)
        #expect(await detector.shouldShowCCTSlider(for: deviceId, segmentId: 0) == false)
        
        await detector.clearCache(for: deviceId)
    }
    
    // MARK: - Combined Capabilities Tests
    
    @Test("Full RGBWCCT detection (all bits set)")
    func testFullCapabilitiesDetection() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-full"
        
        // seglc = 7 means bits 0, 1, 2 all set (0b111 = RGB + White + CCT)
        let seglc = [7]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsRGB == true)
        #expect(segmentCap.supportsWhite == true)
        #expect(segmentCap.supportsCCT == true)
        #expect(await detector.shouldShowRGBControls(for: deviceId, segmentId: 0) == true)
        #expect(await detector.shouldShowWhiteSlider(for: deviceId, segmentId: 0) == true)
        #expect(await detector.shouldShowCCTSlider(for: deviceId, segmentId: 0) == true)
        
        await detector.clearCache(for: deviceId)
    }
    
    @Test("CCT with White detection (no RGB)")
    func testCCTWithWhiteDetection() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-cct-white"
        
        // seglc = 6 means bits 1 and 2 set (0b110 = White + CCT, but no RGB since bit 0 is not set)
        let seglc = [6]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        // This combination is White + CCT without RGB (tunable white strip)
        #expect(segmentCap.supportsCCT == true)
        #expect(segmentCap.supportsWhite == true)
        #expect(segmentCap.supportsRGB == false, "RGB should not be supported when bit 0 is not set")
        
        await detector.clearCache(for: deviceId)
    }
    
    // MARK: - Multi-Segment Tests
    
    @Test("Multi-segment device with different capabilities")
    func testMultiSegmentCapabilities() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-multi"
        
        // Segment 0: RGB only (1)
        // Segment 1: RGB + White (3)
        // Segment 2: RGB + CCT (5)
        let seglc = [1, 3, 5]
        let capabilities = await detector.detect(deviceId: deviceId, seglc: seglc)
        
        // Test segment 0 (RGB only)
        let seg0Cap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(seg0Cap.supportsRGB == true)
        #expect(seg0Cap.supportsWhite == false)
        #expect(seg0Cap.supportsCCT == false)
        
        // Test segment 1 (RGB + White)
        let seg1Cap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 1)
        #expect(seg1Cap.supportsRGB == true)
        #expect(seg1Cap.supportsWhite == true)
        #expect(seg1Cap.supportsCCT == false)
        
        // Test segment 2 (RGB + CCT)
        let seg2Cap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 2)
        #expect(seg2Cap.supportsRGB == true)
        #expect(seg2Cap.supportsWhite == false)
        #expect(seg2Cap.supportsCCT == true)
        
        #expect(await detector.getSegmentCount(for: deviceId) == 3)
        #expect(await detector.hasMultipleSegments(for: deviceId) == true)
        
        await detector.clearCache(for: deviceId)
    }
    
    // MARK: - Fallback Tests
    
    @Test("Fallback to RGB-only when seglc is nil")
    func testNilSeglcFallback() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-nil"
        
        let capabilities = await detector.detect(deviceId: deviceId, seglc: nil)
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsRGB == true, "Should fallback to RGB-only")
        #expect(segmentCap.supportsWhite == false)
        #expect(segmentCap.supportsCCT == false)
        
        await detector.clearCache(for: deviceId)
    }
    
    @Test("Fallback to RGB-only when seglc is empty")
    func testEmptySeglcFallback() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-empty"
        
        let capabilities = await detector.detect(deviceId: deviceId, seglc: [])
        
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 0)
        #expect(segmentCap.supportsRGB == true, "Should fallback to RGB-only")
        #expect(segmentCap.supportsWhite == false)
        #expect(segmentCap.supportsCCT == false)
        
        await detector.clearCache(for: deviceId)
    }
    
    @Test("Fallback for non-existent segment")
    func testNonExistentSegmentFallback() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-single"
        
        // Device with only segment 0
        let seglc = [1]
        await detector.detect(deviceId: deviceId, seglc: seglc)
        
        // Try to access segment 1 (doesn't exist)
        let segmentCap = await detector.getSegmentCapabilities(deviceId: deviceId, segmentId: 1)
        // Should fallback to RGB-only
        #expect(segmentCap.supportsRGB == true)
        #expect(segmentCap.supportsWhite == false)
        #expect(segmentCap.supportsCCT == false)
        
        await detector.clearCache(for: deviceId)
    }
    
    // MARK: - Caching Tests
    
    @Test("Capabilities are cached after detection")
    func testCapabilityCaching() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-cache"
        
        let seglc = [7] // Full capabilities
        await detector.detect(deviceId: deviceId, seglc: seglc)
        
        // Get cached capabilities
        let cached = await detector.getCached(deviceId: deviceId)
        #expect(cached != nil, "Capabilities should be cached")
        #expect(cached?.deviceId == deviceId)
        #expect(cached?.segments.count == 1)
        
        await detector.clearCache(for: deviceId)
    }
    
    @Test("Clear cache removes capabilities")
    func testClearCache() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-clear"
        
        let seglc = [7]
        await detector.detect(deviceId: deviceId, seglc: seglc)
        
        // Verify cached
        let cachedBefore = await detector.getCached(deviceId: deviceId)
        #expect(cachedBefore != nil)
        
        // Clear cache
        await detector.clearCache(for: deviceId)
        
        // Verify cleared
        let cachedAfter = await detector.getCached(deviceId: deviceId)
        #expect(cachedAfter == nil, "Cache should be cleared")
    }
    
    // MARK: - Description Tests
    
    @Test("Capability description formats correctly")
    func testCapabilityDescription() async {
        let detector = CapabilityDetector.shared
        let deviceId = "test-device-desc"
        
        // Test RGB only
        await detector.detect(deviceId: deviceId, seglc: [1])
        var description = await detector.getCapabilityDescription(for: deviceId, segmentId: 0)
        #expect(description.contains("RGB"))
        
        // Test RGB + White
        await detector.detect(deviceId: deviceId, seglc: [3])
        description = await detector.getCapabilityDescription(for: deviceId, segmentId: 0)
        #expect(description.contains("RGB"))
        #expect(description.contains("White"))
        
        // Test Full
        await detector.detect(deviceId: deviceId, seglc: [7])
        description = await detector.getCapabilityDescription(for: deviceId, segmentId: 0)
        #expect(description.contains("RGB"))
        #expect(description.contains("White"))
        #expect(description.contains("CCT"))
        
        await detector.clearCache(for: deviceId)
    }
}

