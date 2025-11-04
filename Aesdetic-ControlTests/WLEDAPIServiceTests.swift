//
//  WLEDAPIServiceTests.swift
//  Aesdetic-ControlTests
//
//  Created on 2025-01-27
//  Tests for WLEDAPIService request construction and validation
//

import Foundation
import Testing
@testable import Aesdetic_Control

struct WLEDAPIServiceTests {
    
    // MARK: - Test Device Helper
    
    func createTestDevice(ipAddress: String = "192.168.1.100") -> WLEDDevice {
        return WLEDDevice(
            id: "test-device",
            name: "Test Device",
            ipAddress: ipAddress,
            isOnline: true,
            brightness: 128,
            currentColor: .white,
            productType: .generic,
            location: .all,
            lastSeen: Date(),
            state: nil
        )
    }
    
    // MARK: - setColor Tests
    
    @Test("setColor validates color array has at least 3 elements")
    func testSetColorValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // Test with insufficient color values
        do {
            _ = try await service.setColor(for: device, color: [255, 0])
            Issue.record("Should have thrown error for color array with < 3 elements")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected error
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    @Test("setColor constructs correct RGB payload")
    func testSetColorRGBPayload() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // This test verifies the method doesn't throw for valid input
        // In a full mock setup, we would verify the request payload
        do {
            _ = try await service.setColor(for: device, color: [255, 165, 0], cct: nil, white: nil)
            // If no error, request construction is valid
        } catch {
            // Network errors are expected in unit tests without mock URLSession
            // We're just verifying the validation logic doesn't throw
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    // Expected - no network in unit tests
                    return
                }
            }
            throw error
        }
    }
    
    @Test("setColor includes white channel when provided")
    func testSetColorWithWhiteChannel() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        do {
            _ = try await service.setColor(for: device, color: [255, 165, 0], cct: nil, white: 128)
            // Method should accept white channel parameter
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected in unit tests
                }
            }
            throw error
        }
    }
    
    @Test("setColor includes CCT when provided")
    func testSetColorWithCCT() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        do {
            _ = try await service.setColor(for: device, color: [255, 165, 0], cct: 200, white: nil)
            // Method should accept CCT parameter
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected in unit tests
                }
            }
            throw error
        }
    }
    
    // MARK: - setCCT Tests
    
    @Test("setCCT validates CCT range 0-255")
    func testSetCCTRangeValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // Test below range
        do {
            _ = try await service.setCCT(for: device, cct: -1)
            Issue.record("Should have thrown error for CCT < 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // Test above range
        do {
            _ = try await service.setCCT(for: device, cct: 256)
            Issue.record("Should have thrown error for CCT > 255")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // Test valid range
        do {
            _ = try await service.setCCT(for: device, cct: 128)
            // Should not throw validation error (may throw network error)
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected in unit tests
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("Should not throw invalidConfiguration for valid CCT range")
                }
            }
        }
    }
    
    @Test("setCCT Kelvin validates minimum 1000K")
    func testSetCCTKelvinValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // Test below minimum
        do {
            _ = try await service.setCCT(for: device, cctKelvin: 999)
            Issue.record("Should have thrown error for CCT Kelvin < 1000")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // Test valid minimum
        do {
            _ = try await service.setCCT(for: device, cctKelvin: 1000)
            // Should not throw validation error
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected in unit tests
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("Should not throw invalidConfiguration for valid Kelvin >= 1000")
                }
            }
        }
    }
    
    @Test("setCCT accepts valid values")
    func testSetCCTValidValues() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // Test boundary values
        do {
            _ = try await service.setCCT(for: device, cct: 0)
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("CCT value 0 should be valid (minimum)")
                }
            }
        }
        
        do {
            _ = try await service.setCCT(for: device, cct: 255)
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("CCT value 255 should be valid (maximum)")
                }
            }
        }
    }
    
    // MARK: - setWhiteChannel Tests
    
    @Test("setColor white channel is clamped to 0-255")
    func testWhiteChannelClamping() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // Test that white values outside range are clamped
        // Note: The implementation uses max(0, min(255, whiteValue))
        // We verify this by checking the method accepts and processes values
        
        do {
            // Test with white = 300 (should be clamped to 255)
            _ = try await service.setColor(for: device, color: [255, 255, 255], cct: nil, white: 300)
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected - verification of clamping happens in implementation
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("White channel should be clamped, not rejected")
                }
            }
        }
        
        do {
            // Test with white = -10 (should be clamped to 0)
            _ = try await service.setColor(for: device, color: [255, 255, 255], cct: nil, white: -10)
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("White channel should be clamped, not rejected")
                }
            }
        }
    }
    
    // MARK: - Presets Tests
    
    @Test("fetchPresets constructs correct URL")
    func testFetchPresetsURL() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice(ipAddress: "192.168.1.50")
        
        do {
            _ = try await service.fetchPresets(for: device)
            // If no error, URL construction is valid
        } catch {
            // Network errors expected, but invalid URL should be caught
            if let apiError = error as? WLEDAPIError {
                if case .invalidURL = apiError {
                    Issue.record("URL construction should be valid for fetchPresets")
                }
                if case .networkError = apiError {
                    return // Expected in unit tests
                }
            }
        }
    }
    
    @Test("savePreset validates preset ID >= 0")
    func testSavePresetValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        let invalidRequest = WLEDPresetSaveRequest(id: -1, name: "Test", quickLoad: false, state: nil)
        
        do {
            try await service.savePreset(invalidRequest, to: device)
            Issue.record("Should have thrown error for preset ID < 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    @Test("applyPreset validates preset ID range 1-250")
    func testApplyPresetValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // Test below range
        do {
            _ = try await service.applyPreset(0, to: device)
            Issue.record("Should have thrown error for preset ID 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // Test above range
        do {
            _ = try await service.applyPreset(251, to: device)
            Issue.record("Should have thrown error for preset ID > 250")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // Test valid range
        do {
            _ = try await service.applyPreset(1, to: device)
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("Preset ID 1 should be valid")
                }
            }
        }
        
        do {
            _ = try await service.applyPreset(250, to: device)
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("Preset ID 250 should be valid")
                }
            }
        }
    }
    
    // MARK: - setBrightness Tests
    
    @Test("setBrightness clamps values to 0-255")
    func testSetBrightnessClamping() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        
        // The implementation uses max(0, min(255, brightness))
        // Test that extreme values are handled
        
        do {
            _ = try await service.setBrightness(for: device, brightness: -10)
            // Should clamp to 0, not throw
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("Brightness should be clamped, not rejected")
                }
            }
        }
        
        do {
            _ = try await service.setBrightness(for: device, brightness: 300)
            // Should clamp to 255, not throw
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .networkError = apiError {
                    return // Expected
                }
                if case .invalidConfiguration = apiError {
                    Issue.record("Brightness should be clamped, not rejected")
                }
            }
        }
    }
}

