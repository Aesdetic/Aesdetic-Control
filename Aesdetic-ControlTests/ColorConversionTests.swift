//
//  ColorConversionTests.swift
//  Aesdetic-ControlTests
//
//  Created on 2025-01-27
//  Tests for color conversion utilities (Kelvin/0-255 CCT, RGB/RGBW formats)
//

import Foundation
import SwiftUI
import Testing
@testable import Aesdetic_Control

struct ColorConversionTests {
    
    // MARK: - CCT Kelvin Conversion Tests
    
    @Test("kelvinValue converts normalized 0.0 to minimum Kelvin (1000K)")
    func testKelvinValueMinimum() {
        let normalized: Double = 0.0
        let kelvin = Segment.kelvinValue(fromNormalized: normalized)
        #expect(kelvin == 1000, "Normalized 0.0 should map to 1000K")
    }
    
    @Test("kelvinValue converts normalized 1.0 to maximum Kelvin (20000K)")
    func testKelvinValueMaximum() {
        let normalized: Double = 1.0
        let kelvin = Segment.kelvinValue(fromNormalized: normalized)
        #expect(kelvin == 20000, "Normalized 1.0 should map to 20000K")
    }
    
    @Test("kelvinValue converts normalized 0.5 to midpoint Kelvin (~10500K)")
    func testKelvinValueMidpoint() {
        let normalized: Double = 0.5
        let kelvin = Segment.kelvinValue(fromNormalized: normalized)
        let expected = Int(round(1000.0 + 0.5 * (20000.0 - 1000.0)))
        #expect(kelvin == expected, "Normalized 0.5 should map to midpoint (~10500K)")
    }
    
    @Test("kelvinValue clamps values below 0.0")
    func testKelvinValueClampsBelow() {
        let normalized: Double = -0.5
        let kelvin = Segment.kelvinValue(fromNormalized: normalized)
        #expect(kelvin == 1000, "Negative normalized should clamp to 1000K")
    }
    
    @Test("kelvinValue clamps values above 1.0")
    func testKelvinValueClampsAbove() {
        let normalized: Double = 1.5
        let kelvin = Segment.kelvinValue(fromNormalized: normalized)
        #expect(kelvin == 20000, "Normalized > 1.0 should clamp to 20000K")
    }
    
    @Test("kelvinValue handles common color temperatures")
    func testKelvinValueCommonTemperatures() {
        // Warm white ~2700K
        let warmNormalized = (2700.0 - 1000.0) / (20000.0 - 1000.0)
        let warmKelvin = Segment.kelvinValue(fromNormalized: warmNormalized)
        #expect(warmKelvin >= 2700 && warmKelvin <= 2700, "Warm white should be ~2700K")
        
        // Neutral white ~4000K
        let neutralNormalized = (4000.0 - 1000.0) / (20000.0 - 1000.0)
        let neutralKelvin = Segment.kelvinValue(fromNormalized: neutralNormalized)
        #expect(neutralKelvin >= 4000 && neutralKelvin <= 4000, "Neutral white should be ~4000K")
        
        // Cool white ~6500K
        let coolNormalized = (6500.0 - 1000.0) / (20000.0 - 1000.0)
        let coolKelvin = Segment.kelvinValue(fromNormalized: coolNormalized)
        #expect(coolKelvin >= 6500 && coolKelvin <= 6500, "Cool white should be ~6500K")
    }
    
    // MARK: - CCT Eight-Bit (0-255) Conversion Tests
    
    @Test("eightBitValue converts normalized 0.0 to 0")
    func testEightBitValueMinimum() {
        let normalized: Double = 0.0
        let eightBit = Segment.eightBitValue(fromNormalized: normalized)
        #expect(eightBit == 0, "Normalized 0.0 should map to 0")
    }
    
    @Test("eightBitValue converts normalized 1.0 to 255")
    func testEightBitValueMaximum() {
        let normalized: Double = 1.0
        let eightBit = Segment.eightBitValue(fromNormalized: normalized)
        #expect(eightBit == 255, "Normalized 1.0 should map to 255")
    }
    
    @Test("eightBitValue converts normalized 0.5 to 128")
    func testEightBitValueMidpoint() {
        let normalized: Double = 0.5
        let eightBit = Segment.eightBitValue(fromNormalized: normalized)
        #expect(eightBit == 128, "Normalized 0.5 should map to 128")
    }
    
    @Test("eightBitValue clamps values below 0.0")
    func testEightBitValueClampsBelow() {
        let normalized: Double = -0.1
        let eightBit = Segment.eightBitValue(fromNormalized: normalized)
        #expect(eightBit == 0, "Negative normalized should clamp to 0")
    }
    
    @Test("eightBitValue clamps values above 1.0")
    func testEightBitValueClampsAbove() {
        let normalized: Double = 1.1
        let eightBit = Segment.eightBitValue(fromNormalized: normalized)
        #expect(eightBit == 255, "Normalized > 1.0 should clamp to 255")
    }
    
    // MARK: - CCT Format Detection Tests
    
    // Helper to create Segment for testing (Segment is Codable, so we can decode from JSON)
    private func createSegment(cct: Int?) -> Segment {
        let json: [String: Any] = ["cct": cct as Any]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Segment.self, from: data)
    }
    
    @Test("cctIsKelvin detects Kelvin values (>= 1000)")
    func testCCTIsKelvinDetection() {
        // Test Kelvin values - use Segment from WLEDDevice.swift
        let segmentKelvin = createSegment(cct: 2700)
        #expect(segmentKelvin.cctIsKelvin == true, "2700 should be detected as Kelvin")
        
        let segmentKelvin2 = createSegment(cct: 1000)
        #expect(segmentKelvin2.cctIsKelvin == true, "1000 should be detected as Kelvin")
        
        let segmentKelvin3 = createSegment(cct: 20000)
        #expect(segmentKelvin3.cctIsKelvin == true, "20000 should be detected as Kelvin")
        
        // Test 0-255 values
        let segmentEightBit = createSegment(cct: 128)
        #expect(segmentEightBit.cctIsKelvin == false, "128 should be detected as 0-255 format")
        
        let segmentEightBit2 = createSegment(cct: 0)
        #expect(segmentEightBit2.cctIsKelvin == false, "0 should be detected as 0-255 format")
        
        let segmentEightBit3 = createSegment(cct: 255)
        #expect(segmentEightBit3.cctIsKelvin == false, "255 should be detected as 0-255 format")
        
        // Test boundary (999 should be 0-255, 1000 should be Kelvin)
        let segmentBoundary = createSegment(cct: 999)
        #expect(segmentBoundary.cctIsKelvin == false, "999 should be detected as 0-255 format")
    }
    
    @Test("cctKelvinValue returns Kelvin value when cctIsKelvin is true")
    func testCCTKelvinValue() {
        let segment = createSegment(cct: 2700)
        #expect(segment.cctKelvinValue == 2700, "Should return Kelvin value when cctIsKelvin is true")
        
        let segmentEightBit = createSegment(cct: 128)
        #expect(segmentEightBit.cctKelvinValue == nil, "Should return nil when cctIsKelvin is false")
    }
    
    @Test("cctEightBitValue returns 0-255 value when cctIsKelvin is false")
    func testCCTEightBitValue() {
        let segment = createSegment(cct: 128)
        #expect(segment.cctEightBitValue == 128, "Should return 0-255 value when cctIsKelvin is false")
        
        let segmentKelvin = createSegment(cct: 2700)
        #expect(segmentKelvin.cctEightBitValue == nil, "Should return nil when cctIsKelvin is true")
    }
    
    // MARK: - CCT Normalized Conversion Tests
    
    @Test("cctNormalized converts Kelvin to normalized 0.0-1.0")
    func testCCTNormalizedFromKelvin() {
        // Minimum Kelvin (1000K) should normalize to 0.0
        let segmentMin = createSegment(cct: 1000)
        let normalizedMin = segmentMin.cctNormalized ?? -1.0
        #expect(abs(normalizedMin - 0.0) < 0.001, "1000K should normalize to ~0.0")
        
        // Maximum Kelvin (20000K) should normalize to 1.0
        let segmentMax = createSegment(cct: 20000)
        let normalizedMax = segmentMax.cctNormalized ?? -1.0
        #expect(abs(normalizedMax - 1.0) < 0.001, "20000K should normalize to ~1.0")
        
        // Midpoint Kelvin (~10500K) should normalize to ~0.5
        let segmentMid = createSegment(cct: 10500)
        let normalizedMid = segmentMid.cctNormalized ?? -1.0
        #expect(abs(normalizedMid - 0.5) < 0.01, "10500K should normalize to ~0.5")
        
        // Common temperatures
        let segment2700 = createSegment(cct: 2700)
        let normalized2700 = segment2700.cctNormalized ?? -1.0
        let expected2700 = (2700.0 - 1000.0) / (20000.0 - 1000.0)
        #expect(abs(normalized2700 - expected2700) < 0.001, "2700K should normalize correctly")
    }
    
    @Test("cctNormalized converts 0-255 to normalized 0.0-1.0")
    func testCCTNormalizedFromEightBit() {
        // Minimum (0) should normalize to 0.0
        let segmentMin = createSegment(cct: 0)
        let normalizedMin = segmentMin.cctNormalized ?? -1.0
        #expect(abs(normalizedMin - 0.0) < 0.001, "0 should normalize to 0.0")
        
        // Maximum (255) should normalize to 1.0
        let segmentMax = createSegment(cct: 255)
        let normalizedMax = segmentMax.cctNormalized ?? -1.0
        #expect(abs(normalizedMax - 1.0) < 0.001, "255 should normalize to 1.0")
        
        // Midpoint (128) should normalize to ~0.5
        let segmentMid = createSegment(cct: 128)
        let normalizedMid = segmentMid.cctNormalized ?? -1.0
        #expect(abs(normalizedMid - 128.0 / 255.0) < 0.001, "128 should normalize to ~128/255")
        
        // Quarter point (64) should normalize to ~0.25
        let segmentQuarter = createSegment(cct: 64)
        let normalizedQuarter = segmentQuarter.cctNormalized ?? -1.0
        #expect(abs(normalizedQuarter - 64.0 / 255.0) < 0.001, "64 should normalize to ~64/255")
    }
    
    @Test("cctNormalized returns nil when CCT is nil")
    func testCCTNormalizedNil() {
        let segment = createSegment(cct: nil)
        #expect(segment.cctNormalized == nil, "Should return nil when CCT is nil")
    }
    
    // MARK: - RGB/RGBW Format Conversion Tests
    
    @Test("toRGBWArray converts Color to RGBW format")
    func testToRGBWArray() {
        // Test pure white (all channels equal)
        let white = Color.white
        let rgbwWhite = white.toRGBWArray()
        #expect(rgbwWhite.count == 4, "RGBW array should have 4 elements")
        #expect(rgbwWhite[0] == 255 && rgbwWhite[1] == 255 && rgbwWhite[2] == 255, "White should have max RGB")
        #expect(rgbwWhite[3] == 255, "White channel should be 255 for pure white")
        
        // Test pure red (white channel = min(R,G,B) = 0)
        let red = Color.red
        let rgbwRed = red.toRGBWArray()
        #expect(rgbwRed.count == 4, "RGBW array should have 4 elements")
        #expect(rgbwRed[0] == 255 && rgbwRed[1] == 0 && rgbwRed[2] == 0, "Red should have correct RGB")
        #expect(rgbwRed[3] == 0, "White channel should be 0 for pure red")
        
        // Test color with white component (e.g., light pink)
        // Note: This tests the white extraction logic (min of R, G, B)
        let colorWithWhite = Color(red: 255/255.0, green: 200/255.0, blue: 200/255.0)
        let rgbwColor = colorWithWhite.toRGBWArray()
        #expect(rgbwColor.count == 4, "RGBW array should have 4 elements")
        #expect(rgbwColor[3] == min(255, 200, 200), "White channel should be min(R, G, B)")
    }
    
    @Test("fromRGBArray converts RGB array to Color")
    func testFromRGBArray() {
        // Test standard RGB
        let rgb = [255, 0, 0]
        let color = Color.fromRGBArray(rgb)
        #expect(color.toRGBArray()[0] == 255, "Red component should be 255")
        #expect(color.toRGBArray()[1] == 0, "Green component should be 0")
        #expect(color.toRGBArray()[2] == 0, "Blue component should be 0")
        
        // Test RGB with values clamped
        let rgbClamped = [300, -10, 128]
        let colorClamped = Color.fromRGBArray(rgbClamped)
        #expect(colorClamped.toRGBArray()[0] == 255, "Should clamp 300 to 255")
        #expect(colorClamped.toRGBArray()[1] == 0, "Should clamp -10 to 0")
        #expect(colorClamped.toRGBArray()[2] == 128, "Should keep 128 as is")
    }
    
    @Test("fromRGBArray handles invalid arrays")
    func testFromRGBArrayInvalid() {
        // Test with insufficient elements
        let rgbShort = [255]
        let colorShort = Color.fromRGBArray(rgbShort)
        // Should default to black for invalid input
        let rgbResult = colorShort.toRGBArray()
        #expect(rgbResult.count == 3, "Should have 3 RGB components")
        
        // Test with empty array
        let rgbEmpty: [Int] = []
        let colorEmpty = Color.fromRGBArray(rgbEmpty)
        let rgbEmptyResult = colorEmpty.toRGBArray()
        #expect(rgbEmptyResult.count == 3, "Should have 3 RGB components")
    }
    
    // MARK: - Round-Trip Conversion Tests
    
    @Test("CCT conversion round-trip: Kelvin normalized -> Kelvin")
    func testCCTRoundTripKelvin() {
        let originalKelvin = 2700
        let segment = createSegment(cct: originalKelvin)
        
        guard let normalized = segment.cctNormalized else {
            Issue.record("cctNormalized should not be nil")
            return
        }
        
        let convertedKelvin = Segment.kelvinValue(fromNormalized: normalized)
        #expect(abs(convertedKelvin - originalKelvin) <= 1, "Round-trip should preserve Kelvin value within rounding")
    }
    
    @Test("CCT conversion round-trip: Eight-bit normalized -> Eight-bit")
    func testCCTRoundTripEightBit() {
        let originalEightBit = 128
        let segment = createSegment(cct: originalEightBit)
        
        guard let normalized = segment.cctNormalized else {
            Issue.record("cctNormalized should not be nil")
            return
        }
        
        let convertedEightBit = Segment.eightBitValue(fromNormalized: normalized)
        #expect(convertedEightBit == originalEightBit, "Round-trip should preserve eight-bit value")
    }
    
    @Test("toRGBWArray formats correctly and extracts white channel")
    func testToRGBWArrayWhiteExtraction() {
        let originalColor = Color(red: 200/255.0, green: 150/255.0, blue: 100/255.0)
        let rgbw = originalColor.toRGBWArray()
        #expect(rgbw.count == 4, "Should have 4 elements in RGBW")
        
        // Verify white channel extraction logic (min of R, G, B)
        let expectedWhite = min(rgbw[0], rgbw[1], rgbw[2])
        #expect(rgbw[3] == expectedWhite, "White channel should equal min(R, G, B)")
        
        // For pure white, all channels should be 255
        let whiteColor = Color.white
        let rgbwWhite = whiteColor.toRGBWArray()
        #expect(rgbwWhite.count == 4, "White color should have 4 elements")
        #expect(rgbwWhite[3] == 255, "White channel should be 255 for pure white")
        
        // For pure red (no white component), white should be 0
        let redColor = Color.red
        let rgbwRed = redColor.toRGBWArray()
        #expect(rgbwRed.count == 4, "Red color should have 4 elements")
        #expect(rgbwRed[3] == 0, "White channel should be 0 for pure red (no white component)")
    }
}

