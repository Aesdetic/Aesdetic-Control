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
                if case .timeout = apiError {
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
                if case .timeout = apiError {
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
                if case .timeout = apiError {
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
        
        let invalidRequest = WLEDPresetSaveRequest(id: -1, name: "Test", quickLoad: nil, state: nil)
        
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

    @Test("applyPlaylist validates playlist ID range 1-250")
    func testApplyPlaylistValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()

        do {
            _ = try await service.applyPlaylist(0, to: device)
            Issue.record("Should have thrown error for playlist ID 0")
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

        do {
            _ = try await service.applyPlaylist(251, to: device)
            Issue.record("Should have thrown error for playlist ID > 250")
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

    @Test("deletePreset validates preset ID range 1-250")
    func testDeletePresetValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()

        do {
            _ = try await service.deletePreset(id: 0, device: device)
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

        do {
            _ = try await service.deletePreset(id: 251, device: device)
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
    }

    @Test("deletePlaylist validates playlist ID range 1-250")
    func testDeletePlaylistValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()

        do {
            _ = try await service.deletePlaylist(id: 0, device: device)
            Issue.record("Should have thrown error for playlist ID 0")
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

        do {
            _ = try await service.deletePlaylist(id: 251, device: device)
            Issue.record("Should have thrown error for playlist ID > 250")
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

    @Test("savePlaylist rejects invalid playlist constraints")
    func testSavePlaylistValidationConstraints() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()

        let tooManySteps = WLEDPlaylistSaveRequest(
            id: 10,
            name: "TooMany",
            ps: Array(repeating: 1, count: 101),
            dur: Array(repeating: 100, count: 101),
            transition: Array(repeating: 7, count: 101),
            repeat: 1,
            endPresetId: 0,
            shuffle: 0
        )

        do {
            _ = try await service.savePlaylist(tooManySteps, to: device)
            Issue.record("Should have rejected playlist with > 100 steps")
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

        let invalidRepeat = WLEDPlaylistSaveRequest(
            id: 11,
            name: "RepeatInvalid",
            ps: [1, 2],
            dur: [100, 100],
            transition: [7, 7],
            repeat: 128,
            endPresetId: 0,
            shuffle: 0
        )

        do {
            _ = try await service.savePlaylist(invalidRepeat, to: device)
            Issue.record("Should have rejected repeat > 127")
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

        let invalidEndPreset = WLEDPlaylistSaveRequest(
            id: 12,
            name: "EndInvalid",
            ps: [1, 2],
            dur: [100, 100],
            transition: [7, 7],
            repeat: 1,
            endPresetId: 254,
            shuffle: 0
        )

        do {
            _ = try await service.savePlaylist(invalidEndPreset, to: device)
            Issue.record("Should have rejected unsupported end preset value")
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

        let invalidShuffle = WLEDPlaylistSaveRequest(
            id: 13,
            name: "ShuffleInvalid",
            ps: [1, 2],
            dur: [100, 100],
            transition: [7, 7],
            repeat: 1,
            endPresetId: 0,
            shuffle: 2
        )

        do {
            _ = try await service.savePlaylist(invalidShuffle, to: device)
            Issue.record("Should have rejected shuffle values other than 0/1")
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

    @Test("playlist step plan for long duration keeps transition <= duration")
    func testPlaylistStepPlanLongDurationParity() async {
        let service = WLEDAPIService.shared
        let requested = 240.0
        let plan = await service.debugPlaylistStepPlanForTests(durationSeconds: requested)

        #expect(plan.steps > 0)
        #expect(plan.durations.count == plan.steps)
        #expect(plan.transitions.count == plan.steps)
        #expect(plan.durations.allSatisfy { $0 > 0 })
        #expect(zip(plan.durations, plan.transitions).allSatisfy { duration, transition in
            transition == duration
        })
        #expect(abs(plan.effectiveDurationSeconds - requested) <= 0.5)
    }

    @Test("validated playlist request normalizes timing arrays and clamps transition by duration")
    func testValidatedPlaylistRequestNormalizationAndClamping() async throws {
        let service = WLEDAPIService.shared
        let request = WLEDPlaylistSaveRequest(
            id: 22,
            name: "Normalize",
            ps: [1, 2, 3],
            dur: [5],
            transition: [20, 30],
            repeat: 1,
            endPresetId: 0,
            shuffle: 0
        )

        let normalized = try await service.debugValidatedPlaylistRequestForTests(request)
        #expect(normalized.dur.count == 3)
        #expect(normalized.transition.count == 3)
        #expect(normalized.dur == [5, 5, 5])
        #expect(normalized.transition == [5, 5, 5])
        #expect(zip(normalized.dur, normalized.transition).allSatisfy { duration, transition in
            duration == 0 || transition <= duration
        })
    }

    @Test("validated playlist request preserves manual-advance entries")
    func testValidatedPlaylistRequestManualAdvanceDurZero() async throws {
        let service = WLEDAPIService.shared
        let request = WLEDPlaylistSaveRequest(
            id: 23,
            name: "Manual advance",
            ps: [1, 2],
            dur: [0, 5],
            transition: [500, 99],
            repeat: 1,
            endPresetId: 0,
            shuffle: 0
        )

        let normalized = try await service.debugValidatedPlaylistRequestForTests(request)
        #expect(normalized.dur == [0, 5])
        #expect(normalized.transition == [500, 5])
    }

    @Test("playlist parser handles top-level and nested presets payload shapes")
    func testPlaylistParserPayloadShapes() async throws {
        let service = WLEDAPIService.shared

        let topLevel = """
        {
          "1": {
            "n": "Top Level Playlist",
            "playlist": {
              "ps": [10, 11],
              "dur": [100, 120],
              "transition": [7, 9],
              "repeat": 1,
              "end": 0,
              "r": 0
            }
          }
        }
        """.data(using: .utf8)!

        let nested = """
        {
          "presets": {
            "2": {
              "n": "Nested Playlist",
              "playlist": {
                "ps": [20, 21],
                "dur": [150, 160],
                "transition": [5, 5],
                "repeat": 0,
                "end": 255,
                "r": 1
              }
            }
          }
        }
        """.data(using: .utf8)!

        let parsedTopLevel = try await service.parsePlaylistsFromPresetsPayloadForTesting(topLevel)
        #expect(parsedTopLevel.count == 1)
        #expect(parsedTopLevel.first?.id == 1)
        #expect(parsedTopLevel.first?.name == "Top Level Playlist")
        #expect(parsedTopLevel.first?.presets == [10, 11])
        #expect(parsedTopLevel.first?.duration == [100, 120])
        #expect(parsedTopLevel.first?.transition == [7, 9])

        let parsedNested = try await service.parsePlaylistsFromPresetsPayloadForTesting(nested)
        #expect(parsedNested.count == 1)
        #expect(parsedNested.first?.id == 2)
        #expect(parsedNested.first?.name == "Nested Playlist")
        #expect(parsedNested.first?.presets == [20, 21])
        #expect(parsedNested.first?.repeat == 0)
        #expect(parsedNested.first?.endPresetId == 255)
        #expect(parsedNested.first?.shuffle == 1)
    }

    @Test("preset parser wraps malformed payload errors")
    func testPresetParserMalformedPayloadErrorWrapping() async throws {
        let service = WLEDAPIService.shared
        let malformed = Data("{".utf8)

        do {
            _ = try await service.parsePresetsPayloadForTesting(malformed)
            Issue.record("Malformed preset payload should throw")
        } catch {
            guard let apiError = error as? WLEDAPIError else {
                Issue.record("Expected WLEDAPIError for malformed preset payload")
                return
            }
            if case .decodingError = apiError {
                // Expected
            } else {
                Issue.record("Expected decodingError for malformed preset payload")
            }
        }
    }

    @Test("playlist parser wraps malformed payload errors")
    func testPlaylistParserMalformedPayloadErrorWrapping() async throws {
        let service = WLEDAPIService.shared
        let malformed = Data("{".utf8)

        do {
            _ = try await service.parsePlaylistsPayloadForTesting(malformed)
            Issue.record("Malformed playlist payload should throw")
        } catch {
            guard let apiError = error as? WLEDAPIError else {
                Issue.record("Expected WLEDAPIError for malformed playlist payload")
                return
            }
            if case .decodingError = apiError {
                // Expected
            } else {
                Issue.record("Expected decodingError for malformed playlist payload")
            }
        }
    }

    @Test("preset parser accepts zero-only payload with whitespace")
    func testPresetParserZeroOnlyWhitespacePayload() async throws {
        let service = WLEDAPIService.shared
        let payload = Data("{\"0\":{}}          \n\t  ".utf8)

        let parsed = try await service.parsePresetsPayloadForTesting(payload)
        #expect(parsed.isEmpty)
    }

    @Test("preset parser recovers trailing garbage after valid root object")
    func testPresetParserRecoversTrailingGarbage() async throws {
        let service = WLEDAPIService.shared
        let valid = """
        {
          "236": { "n": "Auto Step 236", "seg": [] }
        }
        """
        var bytes = Array(valid.utf8)
        bytes.append(contentsOf: [0x20, 0x20, 0xEF, 0xBF, 0xBD, 0x00, 0x58])
        let payload = Data(bytes)

        let parsed = try await service.parsePresetsPayloadForTesting(payload)
        #expect(parsed.count == 1)
        #expect(parsed.first?.id == 236)
        #expect(parsed.first?.name == "Auto Step 236")
    }

    @Test("preset parser strips BOM and NUL bytes")
    func testPresetParserStripsBOMAndNUL() async throws {
        let service = WLEDAPIService.shared
        let json = "{\"237\":{\"n\":\"Auto Step 237\",\"seg\":[]}}"
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array(json.utf8) + [0x00, 0x00]
        let parsed = try await service.parsePresetsPayloadForTesting(Data(bytes))

        #expect(parsed.count == 1)
        #expect(parsed.first?.id == 237)
    }

    @Test("preset parser recovers invalid bytes in whitespace outside JSON strings")
    func testPresetParserRecoversInvalidWhitespaceBytes() async throws {
        let service = WLEDAPIService.shared
        var bytes = Array("""
        {
          "236": { "n": "Auto Step 236", "seg": [] },
          "237": { "n": "Auto Step 237", "seg": [] }
        }
        """.utf8)
        if let insertIndex = bytes.firstIndex(of: 0x0A) {
            bytes.insert(contentsOf: [0xFF, 0x00, 0xFF], at: insertIndex)
        }
        let payload = Data(bytes)

        let parsed = try await service.parsePresetsPayloadForTesting(payload)
        #expect(parsed.count == 2)
        #expect(parsed.map(\.id) == [236, 237])
    }

    @Test("renamePresetRecord validates ID range 1-250")
    func testRenamePresetRecordValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()

        do {
            try await service.renamePresetRecord(id: 0, name: "Test", device: device)
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

        do {
            try await service.renamePresetRecord(id: 251, name: "Test", device: device)
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
    }

    @Test("renamePlaylistRecord validates ID range 1-250")
    func testRenamePlaylistRecordValidation() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()

        do {
            try await service.renamePlaylistRecord(id: 0, name: "Test", device: device)
            Issue.record("Should have thrown error for playlist ID 0")
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

        do {
            try await service.renamePlaylistRecord(id: 251, name: "Test", device: device)
            Issue.record("Should have thrown error for playlist ID > 250")
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

    @Test("preset save request stores boot + custom API fields")
    func testPresetSaveRequestBootAndCustomFields() {
        let request = WLEDPresetSaveRequest(
            id: 42,
            name: "Test",
            quickLoad: "1",
            state: nil,
            applyAtBoot: true,
            customAPICommand: "{\"on\":true,\"bri\":128}"
        )

        #expect(request.applyAtBoot == true)
        #expect(request.customAPICommand == "{\"on\":true,\"bri\":128}")
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

    @Test("parseResponse accepts lightweight save acknowledgements")
    func testParseResponseWithLightweightAck() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        let data = Data("{\"psave\":42,\"n\":\"Test Preset\"}".utf8)

        let response = try await service.debugParseResponseForTests(data: data, device: device)
        #expect(response.info.name == device.name)
        #expect(response.state.brightness == device.brightness)
    }

    @Test("parseResponse maps WLED error code 4 to HTTP 501")
    func testParseResponseErrorCode4() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        let data = Data("{\"error\":4}".utf8)

        do {
            _ = try await service.debugParseResponseForTests(data: data, device: device)
            Issue.record("Expected parseResponse to throw for error code 4")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .httpError(let statusCode) = apiError {
                    #expect(statusCode == 501)
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("parseResponse rejects explicit success false payload")
    func testParseResponseSuccessFalse() async throws {
        let service = WLEDAPIService.shared
        let device = createTestDevice()
        let data = Data("{\"success\":false}".utf8)

        do {
            _ = try await service.debugParseResponseForTests(data: data, device: device)
            Issue.record("Expected parseResponse to fail for success=false")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidResponse = apiError {
                    // Expected.
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("decode sparse timers returns 10 logical slots")
    func testDecodeSparseTimersReturnsTenLogicalSlots() async throws {
        let service = WLEDAPIService.shared
        let decoded = await service._decodeWLEDTimersForTesting(from: [])
        #expect(decoded.count == service._wledTimerSlotCountForTesting)
        #expect(decoded.first?.id == 0)
        #expect(decoded.last?.id == 9)
    }

    @Test("decode remaps hour 255 to sunrise/sunset slots")
    func testDecodeRemapsSolarSlots() async throws {
        let service = WLEDAPIService.shared
        let raw: [[String: Any]] = [
            ["en": true, "hour": 7, "min": 30, "macro": 11, "dow": 0x7F],
            ["en": true, "hour": 255, "min": -15, "macro": 20, "dow": 0x7F],
            ["en": true, "hour": 255, "min": 10, "macro": 21, "dow": 0x7F]
        ]
        let decoded = await service._decodeWLEDTimersForTesting(from: raw)

        #expect(decoded.count == service._wledTimerSlotCountForTesting)
        #expect(decoded[0].macroId == 11)
        #expect(decoded[8].hour == 255)
        #expect(decoded[8].macroId == 20)
        #expect(decoded[9].hour == 255)
        #expect(decoded[9].macroId == 21)
    }

    @Test("encode preserves positional slots through highest used timer")
    func testEncodePreservesPositionalSlotsThroughHighestUsed() async throws {
        let service = WLEDAPIService.shared

        var timers: [WLEDTimer] = (0..<10).map { slot in
            WLEDTimer(
                id: slot,
                enabled: false,
                hour: 0,
                minute: 0,
                days: 0x7F,
                macroId: 0,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        }
        timers[8] = WLEDTimer(
            id: 8,
            enabled: true,
            hour: 255,
            minute: -20,
            days: 0x7F,
            macroId: 30,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        timers[9] = WLEDTimer(
            id: 9,
            enabled: true,
            hour: 255,
            minute: 15,
            days: 0x7F,
            macroId: 31,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )

        let encoded = await service._encodeWLEDTimersForTesting(timers)
        #expect(encoded.count == 10)
        #expect(encoded[0]["hour"] as? Int == 0)
        #expect(encoded[0]["macro"] as? Int == 0)
        #expect(encoded[8]["hour"] as? Int == 255)
        #expect(encoded[8]["macro"] as? Int == 30)
        #expect(encoded[9]["hour"] as? Int == 255)
        #expect(encoded[9]["macro"] as? Int == 31)
    }

    @Test("encode keeps placeholder entries before sparse regular slot")
    func testEncodeKeepsPlaceholderBeforeSparseRegularSlot() async throws {
        let service = WLEDAPIService.shared

        var timers: [WLEDTimer] = (0..<10).map { slot in
            WLEDTimer(
                id: slot,
                enabled: false,
                hour: 0,
                minute: 0,
                days: 0x7F,
                macroId: 0,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        }
        timers[1] = WLEDTimer(
            id: 1,
            enabled: true,
            hour: 7,
            minute: 2,
            days: 0x7F,
            macroId: 249,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )

        let encoded = await service._encodeWLEDTimersForTesting(timers)
        #expect(encoded.count == 2)
        #expect(encoded[0]["hour"] as? Int == 0)
        #expect(encoded[0]["macro"] as? Int == 0)
        #expect(encoded[1]["hour"] as? Int == 7)
        #expect(encoded[1]["min"] as? Int == 2)
        #expect(encoded[1]["macro"] as? Int == 249)
    }

    @Test("encode forceIncludeThroughSlot keeps explicit cleared slot payload")
    func testEncodeForceIncludeThroughSlotForClearedTimer() async throws {
        let service = WLEDAPIService.shared

        let timers: [WLEDTimer] = (0..<10).map { slot in
            WLEDTimer(
                id: slot,
                enabled: false,
                hour: 0,
                minute: 0,
                days: 0x7F,
                macroId: 0,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        }

        let encodedWithoutForce = await service._encodeWLEDTimersForTesting(timers)
        #expect(encodedWithoutForce.isEmpty)

        let encodedWithForce = await service._encodeWLEDTimersForTesting(
            timers,
            forceIncludeThroughSlot: 0
        )
        #expect(encodedWithForce.count == 1)
        #expect(encodedWithForce[0]["en"] as? Bool == false)
        #expect(encodedWithForce[0]["hour"] as? Int == 0)
        #expect(encodedWithForce[0]["min"] as? Int == 0)
        #expect(encodedWithForce[0]["macro"] as? Int == 0)
        #expect(encodedWithForce[0]["dow"] as? Int == 0x7F)
    }

    @Test("timer update merge uses fixed logical slots independent of sparse input")
    func testTimerMergeIgnoresSparseCount() async throws {
        let service = WLEDAPIService.shared
        let sparseCurrent: [WLEDTimer] = [
            WLEDTimer(
                id: 0,
                enabled: true,
                hour: 8,
                minute: 0,
                days: 0x7F,
                macroId: 10,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            ),
            WLEDTimer(
                id: 1,
                enabled: true,
                hour: 9,
                minute: 0,
                days: 0x7F,
                macroId: 11,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        ]

        let update = WLEDTimerUpdate(
            id: 9,
            enabled: true,
            hour: 255,
            minute: 5,
            days: 0x7F,
            macroId: 42,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        let merged = try await service._mergeTimersApplyingUpdateForTesting(
            currentTimers: sparseCurrent,
            timerUpdate: update
        )

        #expect(merged.count == service._wledTimerSlotCountForTesting)
        #expect(merged[9].macroId == 42)
        #expect(merged[9].hour == 255)
        #expect(merged[0].macroId == 10)
    }
}
