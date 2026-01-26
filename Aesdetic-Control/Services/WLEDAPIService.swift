//
//  WLEDAPIService.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine
import os.log
import SwiftUI

// MARK: - API Service Protocol

protocol WLEDAPIServiceProtocol {
    func getState(for device: WLEDDevice) async throws -> WLEDResponse
    func updateState(for device: WLEDDevice, state: WLEDStateUpdate) async throws -> WLEDResponse
    func setPower(for device: WLEDDevice, isOn: Bool, transition: Int?) async throws -> WLEDResponse
    func setBrightness(for device: WLEDDevice, brightness: Int, transition: Int?) async throws -> WLEDResponse
    func setColor(for device: WLEDDevice, color: [Int], cct: Int?, white: Int?, transition: Int?) async throws -> WLEDResponse
    func setCCT(for device: WLEDDevice, cct: Int, segmentId: Int) async throws -> WLEDResponse
    func setCCT(for device: WLEDDevice, cctKelvin: Int, segmentId: Int) async throws -> WLEDResponse
    func fetchPresets(for device: WLEDDevice) async throws -> [WLEDPreset]
    func savePreset(_ request: WLEDPresetSaveRequest, to device: WLEDDevice) async throws
    func setEffect(_ effectId: Int, forSegment segmentId: Int, speed: Int?, intensity: Int?, palette: Int?, colors: [[Int]]?, device: WLEDDevice, turnOn: Bool?, releaseRealtime: Bool) async throws -> WLEDState
    func releaseRealtimeOverride(for device: WLEDDevice) async
    
    // Playlist management
    func savePlaylist(_ request: WLEDPlaylistSaveRequest, to device: WLEDDevice) async throws -> [WLEDPlaylist]
    func fetchPlaylists(for device: WLEDDevice) async throws -> [WLEDPlaylist]
    func applyPlaylist(_ playlistId: Int, to device: WLEDDevice) async throws -> WLEDState
    
    // Timer/Macro management
    func fetchTimers(for device: WLEDDevice) async throws -> [WLEDTimer]
    func updateTimer(_ timerUpdate: WLEDTimerUpdate, on device: WLEDDevice) async throws
    func disableTimer(slot: Int, device: WLEDDevice) async throws -> Bool
    
    // Deletion methods
    func deletePreset(id: Int, device: WLEDDevice) async throws -> Bool
    func deletePlaylist(id: Int, device: WLEDDevice) async throws -> Bool
    
    // Preset saving helpers
    func saveColorPreset(_ preset: ColorPreset, to device: WLEDDevice, presetId: Int) async throws -> Int
    func saveTransitionPreset(_ preset: TransitionPreset, to device: WLEDDevice, playlistId: Int) async throws -> Int
    func saveEffectPreset(_ preset: WLEDEffectPreset, to device: WLEDDevice, presetId: Int) async throws -> Int
    func setSegmentPixels(
        for device: WLEDDevice,
        segmentId: Int?,
        startIndex: Int,
        hexColors: [String],
        cct: Int?,
        on: Bool?,
        brightness: Int?,
        afterChunk: (() async -> Void)?
    ) async throws
    func fetchEffectMetadata(for device: WLEDDevice) async throws -> [String]
}

// MARK: - WLEDAPIService

actor WLEDAPIService: WLEDAPIServiceProtocol, CleanupCapable {
    static let shared = WLEDAPIService()
    
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "APIService")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let defaultPresetSegmentCount: Int = 12
    private let maxPresetSegmentCount: Int = 16
    
    // Performance optimization: Request batching and caching
    private var requestCache: [String: (response: WLEDResponse, timestamp: Date)] = [:]
    private let cacheExpirationInterval: TimeInterval = 2.0 // 2 seconds cache
    private let maxConcurrentRequests = 6 // Limit concurrent requests for better performance
    private let maxCacheSize = 50 // Maximum number of cached responses
    private var lastCacheEviction: Date = .distantPast
    private let cacheEvictionInterval: TimeInterval = 10.0 // Only evict every 10 seconds
    private var lastStatePayloadByDevice: [String: (payload: Data, timestamp: Date)] = [:]
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0 // Reduced timeout for better responsiveness
        config.timeoutIntervalForResource = 20.0
        config.httpMaximumConnectionsPerHost = 4 // Limit connections per host
        config.requestCachePolicy = .useProtocolCachePolicy
        self.urlSession = URLSession(configuration: config)
        
        // Configure JSON encoder to omit nil values
        // This ensures CCT-only updates don't include col: null
        self.encoder.outputFormatting = [.prettyPrinted]
    }
    
    // MARK: - API Methods
    
    func getState(for device: WLEDDevice) async throws -> WLEDResponse {
        let cacheKey = "\(device.id)_state"
        let now = Date()
        
        // Only evict cache periodically to avoid performance issues
        if now.timeIntervalSince(lastCacheEviction) > cacheEvictionInterval {
            evictCacheIfNeeded()
            lastCacheEviction = now
        }
        
        // Check cache first
        if let cached = requestCache[cacheKey],
           now.timeIntervalSince(cached.timestamp) < cacheExpirationInterval {
            return cached.response
        }
        
        guard let url = URL(string: device.jsonEndpoint) else {
            throw WLEDAPIError.invalidURL
        }
        
        let request = URLRequest(url: url)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            let wledResponse = try parseResponse(data: data, device: device)
            
            // Cache the response
            requestCache[cacheKey] = (wledResponse, now)
            
            return wledResponse
        } catch {
            throw handleError(error, device: device)
        }
    }
    
    func updateState(for device: WLEDDevice, state: WLEDStateUpdate) async throws -> WLEDResponse {
        guard let url = URL(string: device.jsonEndpoint) else {
            throw WLEDAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try encoder.encode(state)
            let now = Date()
            if let last = lastStatePayloadByDevice[device.id],
               last.payload == jsonData,
               now.timeIntervalSince(last.timestamp) < 0.25 {
                #if DEBUG
                logger.debug("🔵 [Dedup] Skipping identical state update for \(device.name)")
                #endif
                return createSuccessResponse(for: device)
            }
            lastStatePayloadByDevice[device.id] = (jsonData, now)
            request.httpBody = jsonData
            
            #if DEBUG
            if let segments = state.seg {
                let cctSegments = segments.compactMap { segment -> String? in
                    guard let cctValue = segment.cct else { return nil }
                    let segId = segment.id ?? -1
                    return "id=\(segId),cct=\(cctValue)"
                }
                if !cctSegments.isEmpty {
                    print("🔵 [CCT] Sending CCT update to \(device.name): \(cctSegments.joined(separator: ", "))")
                }
                let whiteSegments = segments.compactMap { segment -> String? in
                    guard let col = segment.col?.first, col.count >= 4 else { return nil }
                    let whiteValue = col[3]
                    guard whiteValue > 0 else { return nil }
                    let segId = segment.id ?? -1
                    return "id=\(segId),w=\(whiteValue)"
                }
                if !whiteSegments.isEmpty {
                    print("🔵 [White] Sending manual white to \(device.name): \(whiteSegments.joined(separator: ", "))")
                }
            }
            // Log the actual JSON being sent for effects debugging
            if state.seg?.first?.fx != nil {
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("[Effects][API] JSON payload being sent to WLED:")
                    print(jsonString)
                }
            }
            #endif
        } catch {
            throw WLEDAPIError.encodingError(error)
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            
            // Handle empty response for successful POST requests
            if data.isEmpty {
                return createSuccessResponse(for: device)
            }
            
            let wledResponse = try parseResponse(data: data, device: device)
            
            // Optimistic update: Bypass cache immediately after successful POST
            // This ensures fresh data is shown after user actions
            bypassCache(for: device.id)
            
            return wledResponse
        } catch {
            throw handleError(error, device: device)
        }
    }
    
    func setPower(for device: WLEDDevice, isOn: Bool, transition: Int? = nil) async throws -> WLEDResponse {
        let stateUpdate = WLEDStateUpdate(on: isOn, transition: transition)
        return try await updateState(for: device, state: stateUpdate)
    }
    
    func setBrightness(for device: WLEDDevice, brightness: Int, transition: Int? = nil) async throws -> WLEDResponse {
        let stateUpdate = WLEDStateUpdate(bri: max(0, min(255, brightness)), transition: transition)
        return try await updateState(for: device, state: stateUpdate)
    }
    
    func setColor(for device: WLEDDevice, color: [Int], cct: Int? = nil, white: Int? = nil, transition: Int? = nil) async throws -> WLEDResponse {
        guard color.count >= 3 else {
            throw WLEDAPIError.invalidConfiguration
        }
        
        // WLED expects col as [[Int]] where the inner array is [R, G, B] or [R, G, B, W]
        // For RGB strips: [[255, 165, 0]]
        // For RGBW strips: [[255, 165, 0, 128]] (where last value is white component 0-255)
        // CCT: 0-255 (0=warm, 255=cool) for RGBCCT strips
        
        let resolvedWhite = white
        let colorArray: [Int]
        if let whiteValue = resolvedWhite {
            // RGBW: Include white channel as 4th element
            colorArray = [color[0], color[1], color[2], max(0, min(255, whiteValue))]
        } else {
            // RGB: Standard 3-element array
            colorArray = [color[0], color[1], color[2]]
        }

        let segment = SegmentUpdate(id: 0, col: [colorArray])
        let stateUpdate = WLEDStateUpdate(seg: [segment], transition: transition)
        return try await updateState(for: device, state: stateUpdate)
    }
    
    /// Set CCT (Correlated Color Temperature) for a WLED device
    /// - Parameters:
    ///   - device: The WLED device
    ///   - cct: Color temperature (0-255, 0=warm ~2700K, 255=cool ~6500K)
    /// - Returns: Updated device state
    func setCCT(for device: WLEDDevice, cct: Int, segmentId: Int = 0) async throws -> WLEDResponse {
        guard cct >= 0 && cct <= 255 else {
            throw WLEDAPIError.invalidConfiguration
        }
        return try await setCCTInternal(for: device, cct: cct, segmentId: segmentId)
    }
    
    func setCCT(for device: WLEDDevice, cctKelvin: Int, segmentId: Int = 0) async throws -> WLEDResponse {
        guard cctKelvin >= 1000 else {
            throw WLEDAPIError.invalidConfiguration
        }
        return try await setCCTInternal(for: device, cct: cctKelvin, segmentId: segmentId)
    }
    
    private func setCCTInternal(for device: WLEDDevice, cct: Int, segmentId: Int = 0) async throws -> WLEDResponse {
        // CRITICAL: When setting CCT, we must also disable effects (fx: 0) 
        // Otherwise WLED may keep using effect colors instead of CCT
        // Also ensure col is NOT included for explicit CCT-only updates
        let segment = SegmentUpdate(id: segmentId, cct: cct, fx: 0)
        let stateUpdate = WLEDStateUpdate(seg: [segment])
        
        // Debug logging
        if let jsonData = try? encoder.encode(stateUpdate),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            #if DEBUG
            print("🔵 Setting CCT: segmentId=\(segmentId), cct=\(cct)")
            print("🔵 JSON: \(jsonString)")
            
            // Verify col is NOT in the JSON
            if jsonString.contains("\"col\"") {
                print("⚠️ WARNING: col field found in CCT JSON! This will cause WLED to ignore CCT.")
            } else {
                print("✅ Confirmed: col field is NOT in JSON (correct)")
            }
            #endif
        }
        
        return try await updateState(for: device, state: stateUpdate)
    }

    func fetchPresets(for device: WLEDDevice) async throws -> [WLEDPreset] {
        return try await fetchPresetsFromFile(device: device)
    }
    
    func savePreset(_ request: WLEDPresetSaveRequest, to device: WLEDDevice) async throws {
        guard request.id >= 0 else {
            throw WLEDAPIError.invalidConfiguration
        }
        try await savePresetViaState(request, device: device)
    }
    
    // MARK: - Playlist Management
    
    func savePlaylist(_ request: WLEDPlaylistSaveRequest, to device: WLEDDevice) async throws -> [WLEDPlaylist] {
        guard request.id >= 0 else {
            throw WLEDAPIError.invalidConfiguration
        }
        try await savePlaylistViaState(request, device: device)
        return []
    }
    
    func fetchPlaylists(for device: WLEDDevice) async throws -> [WLEDPlaylist] {
        return try await fetchPlaylistsFromPresetsFile(device: device)
    }
    
    /// Apply a playlist by selecting its preset ID (`ps`); `pl` is read-only in WLED JSON API.
    /// - Parameters:
    ///   - playlistId: The playlist ID to apply (0-250)
    ///   - device: The target WLED device
    /// - Returns: The updated WLEDState after applying the playlist
    /// - Throws: WLEDAPIError if the request fails
    func applyPlaylist(_ playlistId: Int, to device: WLEDDevice) async throws -> WLEDState {
        guard playlistId >= 0 && playlistId <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }
        let stateUpdate = WLEDStateUpdate(ps: playlistId)
        let response = try await updateState(for: device, state: stateUpdate)
        return response.state
    }

    func applyPlaylist(_ playlistId: Int, to device: WLEDDevice, releaseRealtime: Bool) async throws -> WLEDState {
        guard playlistId >= 0 && playlistId <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }
        let stateUpdate = WLEDStateUpdate(ps: playlistId, lor: releaseRealtime ? 0 : nil)
        let response = try await updateState(for: device, state: stateUpdate)
        return response.state
    }
    
    // MARK: - Timer/Macro Management
    
    /// Fetch all timer configurations from a WLED device
    /// - Parameter device: The target WLED device
    /// - Returns: Array of timer configurations
    /// - Throws: WLEDAPIError if the request fails
    func fetchTimers(for device: WLEDDevice) async throws -> [WLEDTimer] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }
        let request = URLRequest(url: url)
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            // Timers are typically under "timers" key in cfg
            guard let timersArray = json?["timers"] as? [[String: Any]] else {
                return []
            }
            
            var timers: [WLEDTimer] = []
            for (index, timerDict) in timersArray.enumerated() {
                let enabled = timerDict["en"] as? Bool ?? false
                let time = timerDict["time"] as? Int ?? 0
                let days = timerDict["dow"] as? Int ?? 0
                let action = timerDict["act"] as? Int ?? 0
                let presetId = timerDict["ps"] as? Int ?? 0
                let startPresetId = timerDict["ps1"] as? Int
                let endPresetId = timerDict["ps2"] as? Int
                let transition = timerDict["tt"] as? Int
                
                let timer = WLEDTimer(
                    id: index,
                    enabled: enabled,
                    time: time,
                    days: days,
                    action: action,
                    presetId: presetId,
                    startPresetId: startPresetId,
                    endPresetId: endPresetId,
                    transition: transition
                )
                timers.append(timer)
            }
            return timers
        } catch {
            throw handleError(error, device: device)
        }
    }
    
    /// Update a timer configuration on a WLED device
    /// - Parameters:
    ///   - timerUpdate: The timer update configuration
    ///   - device: The target WLED device
    /// - Throws: WLEDAPIError if the request fails
    func updateTimer(_ timerUpdate: WLEDTimerUpdate, on device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }
        
        // First, fetch current config to get timers array
        let currentTimers = try await fetchTimers(for: device)
        
        // Convert timers to mutable dictionary format for update
        var timersArray: [[String: Any]] = Array(repeating: [:], count: max(currentTimers.count, timerUpdate.id + 1))
        
        // Populate existing timers
        for timer in currentTimers {
            if timer.id < timersArray.count {
                timersArray[timer.id] = [
                    "en": timer.enabled,
                    "time": timer.time,
                    "dow": timer.days,
                    "act": timer.action,
                    "ps": timer.presetId
                ]
                if let ps1 = timer.startPresetId {
                    timersArray[timer.id]["ps1"] = ps1
                }
                if let ps2 = timer.endPresetId {
                    timersArray[timer.id]["ps2"] = ps2
                }
                if let tt = timer.transition {
                    timersArray[timer.id]["tt"] = tt
                }
            }
        }
        
        // Apply updates
        if timerUpdate.id < timersArray.count {
            if let enabled = timerUpdate.enabled {
                timersArray[timerUpdate.id]["en"] = enabled
            }
            if let time = timerUpdate.time {
                timersArray[timerUpdate.id]["time"] = time
            }
            if let days = timerUpdate.days {
                timersArray[timerUpdate.id]["dow"] = days
            }
            if let action = timerUpdate.action {
                timersArray[timerUpdate.id]["act"] = action
            }
            if let presetId = timerUpdate.presetId {
                timersArray[timerUpdate.id]["ps"] = presetId
            }
            if let ps1 = timerUpdate.startPresetId {
                timersArray[timerUpdate.id]["ps1"] = ps1
            }
            if let ps2 = timerUpdate.endPresetId {
                timersArray[timerUpdate.id]["ps2"] = ps2
            }
            if let tt = timerUpdate.transition {
                timersArray[timerUpdate.id]["tt"] = tt
            }
        }
        
        // Send update
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["timers": timersArray]
        httpRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (_, response) = try await urlSession.data(for: httpRequest)
        try validateHTTPResponse(response, device: device)
    }
    
    /// Disable a timer slot on a WLED device
    /// - Parameters:
    ///   - slot: Timer slot ID (0-9)
    ///   - device: The target WLED device
    /// - Returns: true if successful, false otherwise
    /// - Throws: WLEDAPIError if the request fails
    func disableTimer(slot: Int, device: WLEDDevice) async throws -> Bool {
        guard slot >= 0 && slot < 10 else {
            throw WLEDAPIError.invalidConfiguration
        }
        
        // Fetch current timers
        let currentTimers = try await fetchTimers(for: device)
        
        // Verify the timer slot exists
        guard currentTimers.contains(where: { $0.id == slot }) else {
            logger.warning("Timer slot \(slot) not found on device \(device.id)")
            return true
        }
        
        // Create update to disable the timer
        let timerUpdate = WLEDTimerUpdate(
            id: slot,
            enabled: false,
            time: nil,
            days: nil,
            action: nil,
            presetId: nil,
            startPresetId: nil,
            endPresetId: nil,
            transition: nil
        )
        
        try await updateTimer(timerUpdate, on: device)
        return true
    }
    
    /// Delete a preset from a WLED device
    /// - Parameters:
    ///   - id: Preset ID to delete
    ///   - device: The target WLED device
    /// - Returns: true if successful, false otherwise
    /// - Throws: WLEDAPIError if the request fails
    func deletePreset(id: Int, device: WLEDDevice) async throws -> Bool {
        guard id >= 0 && id <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }
        do {
            _ = try await postState(device, body: ["pdel": id])
            return true
        } catch {
            if let apiError = error as? WLEDAPIError,
               case .httpError(let statusCode) = apiError,
               statusCode == 404 {
                return true
            }
            logger.warning("Preset deletion failed for \(id) on device \(device.id), will retry later")
            return false
        }
    }
    
    /// Delete a playlist from a WLED device
    /// - Parameters:
    ///   - id: Playlist ID to delete
    ///   - device: The target WLED device
    /// - Returns: true if successful, false otherwise
    /// - Throws: WLEDAPIError if the request fails
    func deletePlaylist(id: Int, device: WLEDDevice) async throws -> Bool {
        guard id >= 0 && id <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }
        return try await deletePreset(id: id, device: device)
    }
    
    // MARK: - Preset Saving Helpers
    
    /// Save a ColorPreset as a WLED preset with per-LED colors
    func saveColorPreset(_ preset: ColorPreset, to device: WLEDDevice, presetId: Int) async throws -> Int {
        let interpolation = preset.gradientInterpolation ?? .linear
        let gradient = LEDGradient(stops: preset.gradientStops, interpolation: interpolation)
        let stateUpdate = segmentedPresetState(
            device: device,
            gradient: gradient,
            brightness: preset.brightness,
            on: true,
            temperature: preset.temperature,
            whiteLevel: preset.whiteLevel
        )
        let saveRequest = WLEDPresetSaveRequest(
            id: presetId,
            name: preset.name,
            quickLoad: false,
            state: stateUpdate
        )
        try await savePreset(saveRequest, to: device)
        
        return presetId
    }
    
    /// Save a TransitionPreset as a multi-step WLED playlist (A→B, one cycle)
    func saveTransitionPreset(_ preset: TransitionPreset, to device: WLEDDevice, playlistId: Int) async throws -> Int {
        let existingPresets = try await fetchPresets(for: device)
        var usedPresetIds = Set(existingPresets.map { $0.id })
        usedPresetIds.insert(playlistId)
        let stepPlan = playlistStepPlan(for: preset.durationSec)
        let stepCount = stepPlan.steps
        guard let presetIds = allocateIds(from: 250, excluding: usedPresetIds, count: stepCount) else {
            throw WLEDAPIError.invalidConfiguration
        }

        let denom = Double(max(1, stepCount - 1))
        for (idx, presetId) in presetIds.enumerated() {
            let t = Double(idx) / denom
            let gradient = interpolatedGradient(from: preset.gradientA, to: preset.gradientB, t: t)
            let brightness = Int(round(Double(preset.brightnessA) * (1.0 - t) + Double(preset.brightnessB) * t))
            let temperature = interpolateOptional(preset.temperatureA, preset.temperatureB, t: t)
            let whiteLevel = interpolateOptional(preset.whiteLevelA, preset.whiteLevelB, t: t)
            let state = segmentedPresetState(
                device: device,
                gradient: gradient,
                brightness: brightness,
                on: true,
                temperature: temperature,
                whiteLevel: whiteLevel
            )
            try await savePreset(
                WLEDPresetSaveRequest(
                    id: presetId,
                    name: "\(preset.name) Step \(idx + 1)",
                    quickLoad: false,
                    state: state,
                    saveOnly: true
                ),
                to: device
            )
        }
        
        // Create playlist: A→B, one cycle
        let playlistRequest = WLEDPlaylistSaveRequest(
            id: playlistId,
            name: preset.name,
            ps: presetIds,
            dur: stepPlan.durations,
            transition: stepPlan.transitions,
            repeat: 1,  // One cycle - stops at B
            endPresetId: presetIds.last
        )
        
        _ = try await savePlaylist(playlistRequest, to: device)
        
        return playlistId
    }
    
    /// Save a WLEDEffectPreset as a WLED preset
    func saveEffectPreset(_ preset: WLEDEffectPreset, to device: WLEDDevice, presetId: Int) async throws -> Int {
        let segmentUpdate = SegmentUpdate(
            id: 0,
            bri: preset.brightness,
            fx: preset.effectId,
            sx: preset.speed,
            ix: preset.intensity,
            pal: preset.paletteId
        )
        
        let stateUpdate = WLEDStateUpdate(
            bri: preset.brightness,
            seg: [segmentUpdate]
        )
        
        let saveRequest = WLEDPresetSaveRequest(
            id: presetId,
            name: preset.name,
            quickLoad: false,
            state: stateUpdate
        )
        
        try await savePreset(saveRequest, to: device)
        
        return presetId
    }

    func fetchEffectMetadata(for device: WLEDDevice) async throws -> [String] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/fxdata") else {
            throw WLEDAPIError.invalidURL
        }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            let rawString: String
            if let utf8 = String(data: data, encoding: .utf8) {
                rawString = utf8
            } else if let ascii = String(data: data, encoding: .ascii) {
                rawString = ascii
            } else {
                throw WLEDAPIError.decodingError(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode fxdata string")))
            }
            let lines = rawString
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines
        } catch {
            throw handleError(error, device: device)
        }
    }

    // MARK: - UDP Sync Controls
    @discardableResult
    func setUDPSync(for device: WLEDDevice, send: Bool? = nil, recv: Bool? = nil, network: Int? = nil) async throws -> WLEDResponse {
        let udpn = UDPNUpdate(send: send, recv: recv, nn: network)
        let stateUpdate = WLEDStateUpdate(udpn: udpn)
        return try await updateState(for: device, state: stateUpdate)
    }
    
    // MARK: - Configuration Update
    
    /// Updates the WLED device configuration (e.g., device name)
    /// - Parameters:
    ///   - device: The WLED device to update
    ///   - name: The new device name (server description)
    /// - Returns: The updated device state
    func updateConfig(for device: WLEDDevice, name: String) async throws -> WLEDResponse {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }

        // Fetch the existing configuration so we can preserve LED preferences (gamma, etc.)
        var existingConfig = try await fetchRawConfig(for: device)

        // Update every known location for the server name without altering other fields
        updateServerName(in: &existingConfig, to: name)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: existingConfig)

        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)

        // After config update, fetch the current state to return
        return try await getState(for: device)
    }

    /// Fetches the raw configuration dictionary from the device without decoding into strongly typed models.
    private func fetchRawConfig(for device: WLEDDevice) async throws -> [String: Any] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)
        try validateHTTPResponse(response, device: device)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WLEDAPIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unable to decode configuration JSON")))
        }

        return json
    }

    /// Mutates the provided configuration dictionary to update the server name in all known locations.
    private func updateServerName(in config: inout [String: Any], to newName: String) {
        // Top-level id block
        if var id = config["id"] as? [String: Any] {
            id["name"] = newName
            config["id"] = id
        }

        // Some firmware builds wrap configuration under "cfg"
        if var cfg = config["cfg"] as? [String: Any] {
            if var id = cfg["id"] as? [String: Any] {
                id["name"] = newName
                cfg["id"] = id
            }
            cfg["server-name"] = newName
            config["cfg"] = cfg
        }

        // Legacy field used by certain tooling
        config["server-name"] = newName
    }
    
    /// Enables audio reactive mode in WLED configuration
    /// - Parameter device: The WLED device to update
    /// - Returns: Success status
    func enableAudioReactive(for device: WLEDDevice) async throws -> Bool {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }
        
        // Fetch existing configuration
        var config = try await fetchRawConfig(for: device)
        
        // Update audio reactive setting
        // WLED stores this in different locations depending on firmware version
        var updated = false
        
        // Helper function to update sound config recursively
        func updateSoundConfig(_ dict: inout [String: Any], path: String = "") -> Bool {
            // Try direct sound block
            if var sound = dict["sound"] as? [String: Any] {
                sound["enabled"] = true
                dict["sound"] = sound
                return true
            }
            
            // Try cfg.sound block
            if var cfg = dict["cfg"] as? [String: Any] {
                if updateSoundConfig(&cfg, path: "cfg") {
                    dict["cfg"] = cfg
                    return true
                }
            }
            
            return false
        }
        
        updated = updateSoundConfig(&config)
        
        // If no sound block exists, create one at the top level
        if !updated {
            config["sound"] = ["enabled": true]
        }
        
        // Send updated config
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: config)
        
        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)
        
        return true
    }
    
    /// Check if audio reactive mode is enabled in WLED configuration
    func isAudioReactiveEnabled(for device: WLEDDevice) async throws -> Bool {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }
        
        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        // Check various possible locations for sound.enabled
        func checkSoundEnabled(_ dict: [String: Any]) -> Bool? {
            // Direct sound block
            if let sound = dict["sound"] as? [String: Any],
               let enabled = sound["enabled"] as? Bool {
                return enabled
            }
            
            // cfg.sound block
            if let cfg = dict["cfg"] as? [String: Any],
               let sound = cfg["sound"] as? [String: Any],
               let enabled = sound["enabled"] as? Bool {
                return enabled
            }
            
            return nil
        }
        
        if let enabled = checkSoundEnabled(json) {
            return enabled
        }
        
        // Default to false if not found
        return false
    }

    // MARK: - Per-LED Control
    
    /// Calculate optimal chunk size based on network MTU constraints
    /// - Parameters:
    ///   - hasSegmentId: Whether segment ID will be included in JSON
    ///   - hasCCT: Whether CCT will be included (typically only first chunk)
    ///   - customMTU: Optional custom MTU size (default: 1500 bytes)
    /// - Returns: Optimal number of LEDs per chunk
    /// 
    /// Calculation:
    /// - Network MTU: 1500 bytes (typical Ethernet)
    /// - Safe payload: 1300 bytes (leaves room for HTTP headers ~200 bytes)
    /// - JSON overhead: ~60 bytes (base structure + segment ID + CCT if present)
    /// - Per LED: ~8 bytes ("RRGGBB", including quotes and comma)
    /// - Optimal: (1300 - overhead) / 8 ≈ 155 LEDs (conservative)
    private static func calculateOptimalChunkSize(hasSegmentId: Bool, hasCCT: Bool, hasOnOrBri: Bool = false, customMTU: Int? = nil) -> Int {
        let mtu = customMTU ?? 1500  // Standard Ethernet MTU
        let safePayload = mtu - 200  // Reserve 200 bytes for HTTP headers
        let baseOverhead = 25  // Base JSON structure: {"seg":[{"i":[]}]}
        let segmentIdOverhead = hasSegmentId ? 7 : 0  // "id":0,
        let cctOverhead = hasCCT ? 10 : 0  // "cct":116,
        let onOrBriOverhead = hasOnOrBri ? 15 : 0  // "on":true,"bri":255, (only in first chunk)
        let startIndexOverhead = 5  // Start index in array
        let totalOverhead = baseOverhead + segmentIdOverhead + cctOverhead + onOrBriOverhead + startIndexOverhead
        
        let bytesPerLED = 8  // "RRGGBB", (including quotes, comma, space)
        let availableBytes = safePayload - totalOverhead
        let optimalLEDs = max(1, availableBytes / bytesPerLED)
        
        // Clamp to reasonable bounds: minimum 50, maximum 300
        // Minimum ensures we don't create too many tiny chunks
        // Maximum prevents issues with very large MTUs
        return min(300, max(50, optimalLEDs))
    }
    
    func setSegmentPixels(
        for device: WLEDDevice,
        segmentId: Int? = nil,
        startIndex: Int = 0,
        hexColors: [String],
        cct: Int? = nil,
        on: Bool? = nil,
        brightness: Int? = nil,
        afterChunk: (() async -> Void)? = nil
    ) async throws {
        guard !hexColors.isEmpty else { return }
        // Calculate optimal chunk size based on MTU
        // If including on/bri, account for additional overhead
        let hasOnOrBri = on != nil || brightness != nil
        let optimalChunkSize = Self.calculateOptimalChunkSize(
            hasSegmentId: segmentId != nil,
            hasCCT: cct != nil,
            hasOnOrBri: hasOnOrBri
        )
        let bodies = Self.buildSegmentPixelBodies(
            segmentId: segmentId,
            startIndex: startIndex,
            hexColors: hexColors,
            cct: cct,
            chunkSize: optimalChunkSize,
            on: on,
            brightness: brightness
        )
        
        #if DEBUG
        let totalLEDs = hexColors.count
        let chunkCount = bodies.count
        let oldChunkSize = 256  // Previous fixed chunk size
        let oldChunkCount = (totalLEDs + oldChunkSize - 1) / oldChunkSize  // Ceiling division
        let improvement = oldChunkCount > chunkCount ? "↓ \(oldChunkCount - chunkCount) fewer chunks" : "same"
        logger.debug("📦 [Chunking] \(totalLEDs) LEDs → \(chunkCount) chunk(s) @ \(optimalChunkSize)/chunk (was: \(oldChunkCount) @ \(oldChunkSize)) \(improvement)")
        #endif
        
        for body in bodies {
            _ = try await postRawState(for: device, body: body)
            if let cb = afterChunk { await cb() }
        }
    }
    
    /// Post raw JSON state update (for per-LED pixel uploads with custom body structure)
    func postRawState(for device: WLEDDevice, body: [String: Any]) async throws -> WLEDResponse {
        guard let url = URL(string: device.jsonEndpoint) else {
            throw WLEDAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
            request.httpBody = jsonData
            
            #if DEBUG
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📤 [Per-LED] Sending JSON: \(jsonString)")
            }
            #endif
        } catch {
            throw WLEDAPIError.encodingError(error)
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            
            // Handle empty response for successful POST requests
            if data.isEmpty {
                return createSuccessResponse(for: device)
            }
            
            let wledResponse = try parseResponse(data: data, device: device)
            
            // Optimistic update: Bypass cache immediately after successful POST
            bypassCache(for: device.id)
            
            return wledResponse
        } catch {
            throw handleError(error, device: device)
        }
    }

    // Helper to build chunked POST bodies
    /// - Parameters:
    ///   - segmentId: Optional segment ID
    ///   - startIndex: Starting LED index
    ///   - hexColors: Array of hex color strings ("RRGGBB")
    ///   - cct: Optional CCT value (only included in first chunk)
    ///   - chunkSize: Number of LEDs per chunk (defaults to optimal MTU-based size)
    /// - Returns: Array of JSON body dictionaries ready for POST requests
    internal static func buildSegmentPixelBodies(segmentId: Int?, startIndex: Int, hexColors: [String], cct: Int? = nil, chunkSize: Int? = nil, on: Bool? = nil, brightness: Int? = nil) -> [[String: Any]] {
        guard !hexColors.isEmpty else { return [] }
        
        // Use provided chunk size or calculate optimal based on MTU
        let effectiveChunkSize: Int
        if let providedSize = chunkSize {
            effectiveChunkSize = max(1, providedSize)  // Ensure at least 1 LED per chunk
        } else {
            // Calculate optimal chunk size dynamically
            let hasOnOrBri = on != nil || brightness != nil
            effectiveChunkSize = calculateOptimalChunkSize(
                hasSegmentId: segmentId != nil,
                hasCCT: cct != nil,
                hasOnOrBri: hasOnOrBri
            )
        }
        
        var out: [[String: Any]] = []
        let total = hexColors.count
        var idx = 0
        while idx < total {
            let end = min(idx + effectiveChunkSize, total)
            let chunk = Array(hexColors[idx..<end])
            var seg: [String: Any] = ["i": [startIndex + idx] + chunk]
            if let sid = segmentId { seg["id"] = sid }
            // Add CCT to segment if provided (only on first chunk to avoid redundancy)
            if let cctValue = cct, idx == 0 {
                seg["cct"] = cctValue
            }
            
            // Build body - include on/bri only in FIRST chunk to combine with gradient colors
            var body: [String: Any] = [:]
            
            // CRITICAL: Include on/bri in first chunk to prevent WLED from showing restored colors
            if idx == 0 {
                if let onValue = on {
                    body["on"] = onValue
                }
                if let briValue = brightness {
                    body["bri"] = briValue
                }
            }
            
            // Add segment data
            // CRITICAL: WLED API expects seg to always be an array, even for single segments without explicit IDs
            // Always wrap seg in an array regardless of whether segmentId is nil
            body["seg"] = [seg]
            
            out.append(body)
            idx = end
        }
        return out
    }

    // MARK: - Convenience State Methods (Enhanced)
    
    /// Get just the state portion from a WLED device (convenience method)
    /// - Parameter device: The WLED device to query
    /// - Returns: The current WLEDState of the device
    /// - Throws: WLEDAPIError if the request fails
    func getDeviceState(for device: WLEDDevice) async throws -> WLEDState {
        let response = try await getState(for: device)
        return response.state
    }
    
    /// Set the complete state of a WLED device (convenience method)
    /// - Parameters:
    ///   - state: The complete WLEDState to apply to the device
    ///   - device: The target WLED device
    /// - Returns: The updated WLEDState after the operation
    /// - Throws: WLEDAPIError if the request fails
    ///
    /// Note: This converts the full WLEDState to a WLEDStateUpdate for the API call
    func setState(_ state: WLEDState, for device: WLEDDevice) async throws -> WLEDState {
        // Convert WLEDState to WLEDStateUpdate for the API
        let stateUpdate = WLEDStateUpdate(
            on: state.isOn,
            bri: state.brightness,
            seg: state.segments.compactMap { segment in
                SegmentUpdate(
                    id: segment.id,
                    col: segment.colors,
                    fx: segment.fx,
                    sx: segment.sx,
                    ix: segment.ix,
                    pal: segment.pal,
                    sel: segment.sel,
                    rev: segment.rev
                )
            }
        )
        
        let response = try await updateState(for: device, state: stateUpdate)
        return response.state
    }
    
    /// Apply a preset to a WLED device
    /// - Parameters:
    ///   - presetId: The preset ID to apply (1-250)
    ///   - device: The target WLED device
    ///   - transition: Optional transition time in deciseconds
    /// - Returns: The updated WLEDState after applying the preset
    /// - Throws: WLEDAPIError if the request fails
    func applyPreset(_ presetId: Int, to device: WLEDDevice, transition: Int? = nil) async throws -> WLEDState {
        guard presetId > 0 && presetId <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }
        
        let stateUpdate = WLEDStateUpdate(transition: transition, ps: presetId)
        let response = try await updateState(for: device, state: stateUpdate)
        return response.state
    }
    
    /// Configure night light for a WLED device
    /// - Parameters:
    ///   - enabled: Whether to enable night light
    ///   - duration: Duration in minutes
    ///   - mode: Fade mode (0=instant, 1=fade, 2=color fade, 3=sunrise)
    ///   - targetBrightness: Target brightness (0-255)
    ///   - device: The target WLED device
    /// - Returns: The updated WLEDState after configuration
    /// - Throws: WLEDAPIError if the request fails
    func configureNightLight(enabled: Bool, duration: Int? = nil, mode: Int? = nil, 
                           targetBrightness: Int? = nil, for device: WLEDDevice) async throws -> WLEDState {
        let nightLightUpdate = NightLightUpdate(on: enabled, dur: duration, mode: mode, tbri: targetBrightness)
        let stateUpdate = WLEDStateUpdate(nl: nightLightUpdate)
        let response = try await updateState(for: device, state: stateUpdate)
        return response.state
    }
    
    /// Set effect for a specific segment
    /// - Parameters:
    ///   - effectId: The effect ID to apply
    ///   - segmentId: The segment ID (default: 0)
    ///   - speed: Effect speed (0-255, optional)
    ///   - intensity: Effect intensity (0-255, optional)
    ///   - palette: Palette ID (optional)
    ///   - device: The target WLED device
    /// - Returns: The updated WLEDState after setting the effect
    /// - Throws: WLEDAPIError if the request fails
    func setEffect(_ effectId: Int, forSegment segmentId: Int = 0, speed: Int? = nil,
                  intensity: Int? = nil, palette: Int? = nil, colors: [[Int]]? = nil,
                  device: WLEDDevice, turnOn: Bool? = nil, releaseRealtime: Bool = false) async throws -> WLEDState {
        let baseSegment = device.state?.segments.first(where: { ($0.id ?? 0) == segmentId }) ?? device.state?.segments.first
        
        // When sending colors with effects, omit palette (pal: 0 can conflict with col)
        // Only set palette if colors are NOT provided (let effect use palette)
        let effectivePalette: Int? = colors != nil ? nil : palette
        
        // When applying effects, ensure segment is not frozen and is explicitly on
        // Don't send segment brightness - let device brightness control it
        // Ensure freeze is false so effects can run
        let segment = SegmentUpdate(
            id: segmentId,
            start: baseSegment?.start,
            stop: baseSegment?.stop,
            len: baseSegment?.len,
            grp: baseSegment?.grp,
            spc: baseSegment?.spc,
            ofs: baseSegment?.ofs,
            on: turnOn,
            bri: nil,  // Don't override segment brightness - use device brightness
            col: colors,
            cct: nil,  // Don't send CCT when applying effects (CCT conflicts with effects)
            fx: effectId,
            sx: speed,
            ix: intensity,
            pal: effectivePalette,
            sel: baseSegment?.sel,
            rev: baseSegment?.rev,
            mi: baseSegment?.mi,
            cln: baseSegment?.cln,
            frz: false  // Explicitly unfreeze segment so effects can run
        )
        
        #if DEBUG
        print("[Effects][API] Sending segment update: id=\(segmentId) fx=\(effectId) sx=\(speed ?? -1) ix=\(intensity ?? -1) pal=\(palette ?? -1) on=\(turnOn?.description ?? "nil") colors=\(colors?.description ?? "nil")")
        print("[Effects][API] Segment also includes: len=\(baseSegment?.len ?? -1) start=\(baseSegment?.start ?? -1) stop=\(baseSegment?.stop ?? -1)")
        #endif
        
        // CRITICAL: Always include brightness when applying effects to prevent flash
        // Even if turnOn is nil, we should preserve current brightness atomically
        let deviceBrightness: Int?
        if turnOn == true {
            deviceBrightness = device.brightness > 0 ? device.brightness : nil
        } else if device.brightness > 0 {
            deviceBrightness = device.brightness
        } else {
            deviceBrightness = nil
        }
        // CRITICAL: Include lor: 0 atomically if needed to release realtime override
        // This prevents flash by combining realtime release with effect application in one call
        // Also always include brightness to prevent brightness reset during effect switch
        let stateUpdate = WLEDStateUpdate(
            on: turnOn,
            bri: deviceBrightness,
            seg: [segment],
            lor: releaseRealtime ? 0 : nil  // Release realtime override atomically if needed
        )
        
        #if DEBUG
        print("[Effects][API] State update includes: on=\(String(describing: turnOn)) bri=\(String(describing: deviceBrightness))")
        #endif
        
        let response = try await updateState(for: device, state: stateUpdate)
        
        #if DEBUG
        print("[Effects][API] Received response from updateState")
        #endif
        
        return response.state
    }
    
    func releaseRealtimeOverride(for device: WLEDDevice) async {
        #if DEBUG
        print("[Effects][API] Releasing realtime override (lor: 0) for device \(device.name)")
        #endif
        let stateUpdate = WLEDStateUpdate(lor: 0)
        do {
            _ = try await updateState(for: device, state: stateUpdate)
            #if DEBUG
            print("[Effects][API] Realtime override released successfully")
            #endif
        } catch {
            #if DEBUG
            print("[Effects][WARNING] Failed to release realtime override: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Batch Operations
    
    /// Apply the same state to multiple devices
    /// - Parameters:
    ///   - state: The WLEDState to apply
    ///   - devices: Array of target devices
    /// - Returns: Dictionary mapping device IDs to their updated states
    /// - Throws: WLEDAPIError for any device that fails
    func setBatchState(_ state: WLEDState, for devices: [WLEDDevice]) async throws -> [String: WLEDState] {
        return try await withThrowingTaskGroup(of: (String, WLEDState).self, returning: [String: WLEDState].self) { group in
            for device in devices {
                group.addTask {
                    let updatedState = try await self.setState(state, for: device)
                    return (device.id, updatedState)
                }
            }
            
            var results: [String: WLEDState] = [:]
            for try await (deviceId, state) in group {
                results[deviceId] = state
            }
            return results
        }
    }
    
    /// Apply the same preset to multiple devices
    /// - Parameters:
    ///   - presetId: The preset ID to apply
    ///   - devices: Array of target devices
    ///   - transition: Optional transition time
    /// - Returns: Dictionary mapping device IDs to their updated states
    /// - Throws: WLEDAPIError for any device that fails
    func applyBatchPreset(_ presetId: Int, to devices: [WLEDDevice], transition: Int? = nil) async throws -> [String: WLEDState] {
        return try await withThrowingTaskGroup(of: (String, WLEDState).self, returning: [String: WLEDState].self) { group in
            for device in devices {
                group.addTask {
                    let updatedState = try await self.applyPreset(presetId, to: device, transition: transition)
                    return (device.id, updatedState)
                }
            }
            
            var results: [String: WLEDState] = [:]
            for try await (deviceId, state) in group {
                results[deviceId] = state
            }
            return results
        }
    }
    
    // MARK: - WebSocket Integration Methods
    
    /// Subscribe to real-time state updates for specific devices via WebSocket
    /// - Parameter deviceIds: Array of device IDs to monitor
    /// - Returns: Publisher that emits WLEDState updates with device ID
    ///
    /// Usage: 
    /// ```swift
    /// let cancellable = wledAPI.subscribeToStateUpdates(deviceIds: ["device1", "device2"])
    ///     .sink { (deviceId, state) in
    ///         print("Device \(deviceId) state updated: \(state)")
    ///     }
    /// ```
    @MainActor
    func subscribeToStateUpdates(deviceIds: [String]) -> AnyPublisher<(deviceId: String, state: WLEDState), Never> {
        return WLEDWebSocketManager.shared.deviceStateUpdates
            .compactMap { update in
                guard deviceIds.contains(update.deviceId),
                      let state = update.state else { return nil }
                return (update.deviceId, state)
            }
            .eraseToAnyPublisher()
    }
    
    /// Subscribe to all real-time state updates via WebSocket
    /// - Returns: Publisher that emits all WLEDState updates with device ID
    ///
    /// Usage:
    /// ```swift
    /// let cancellable = wledAPI.subscribeToAllStateUpdates()
    ///     .sink { (deviceId, state) in
    ///         // Handle state update for any device
    ///         print("Device \(deviceId) updated: on=\(state.isOn), brightness=\(state.brightness)")
    ///     }
    /// ```
    @MainActor
    func subscribeToAllStateUpdates() -> AnyPublisher<(deviceId: String, state: WLEDState), Never> {
        return WLEDWebSocketManager.shared.deviceStateUpdates
            .compactMap { update in
                guard let state = update.state else { return nil }
                return (update.deviceId, state)
            }
            .eraseToAnyPublisher()
    }
    
    /// Enable real-time WebSocket connection for a device
    /// - Parameters:
    ///   - device: The WLED device to connect to
    ///   - priority: Connection priority (higher values get preference during connection limits)
    ///
    /// Usage:
    /// ```swift
    /// // Enable real-time updates for high-priority device
    /// wledAPI.enableRealTimeUpdates(for: device, priority: 10)
    /// ```
    @MainActor
    func enableRealTimeUpdates(for device: WLEDDevice, priority: Int = 5) {
        WLEDWebSocketManager.shared.connect(to: device, priority: priority)
    }
    
    /// Disable real-time WebSocket connection for a device
    /// - Parameter device: The WLED device to disconnect from
    @MainActor
    func disableRealTimeUpdates(for device: WLEDDevice) {
        WLEDWebSocketManager.shared.disconnect(from: device.id)
    }
    
    /// Enable real-time updates for multiple devices with priority handling
    /// - Parameters:
    ///   - devices: Array of devices to connect
    ///   - priorities: Optional dictionary mapping device IDs to priorities
    /// - Returns: Async operation that completes when all connections are established
    @MainActor
    func enableBatchRealTimeUpdates(for devices: [WLEDDevice], priorities: [String: Int] = [:]) async {
        await WLEDWebSocketManager.shared.connectToDevices(devices, priorities: priorities)
    }
    
    /// Get connection status for a specific device
    /// - Parameter device: The WLED device to check
    /// - Returns: Connection status information, or nil if not connected
    @MainActor
    func getConnectionStatus(for device: WLEDDevice) -> WLEDWebSocketManager.DeviceConnectionStatus? {
        return WLEDWebSocketManager.shared.getConnectionStatus(for: device.id)
    }
    
    /// Get all currently connected device IDs
    /// - Returns: Array of device IDs that are currently connected via WebSocket
    @MainActor
    var connectedDeviceIds: [String] {
        return WLEDWebSocketManager.shared.connectedDeviceIds
    }
    
    /// Send real-time state update via WebSocket (faster than HTTP for frequent updates)
    /// - Parameters:
    ///   - state: The state update to send
    ///   - device: The target device
    /// - Note: Device must be connected via WebSocket first using enableRealTimeUpdates
    @MainActor
    func sendRealTimeStateUpdate(_ state: WLEDStateUpdate, to device: WLEDDevice) {
        WLEDWebSocketManager.shared.sendStateUpdate(state, to: device.id)
    }
    
    // MARK: - Helper Methods
    
    private func validateHTTPResponse(_ response: URLResponse, device: WLEDDevice) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WLEDAPIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw WLEDAPIError.httpError(httpResponse.statusCode)
        }
    }

    private func wledErrorCode(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = json as? [String: Any],
              let errorValue = dictionary["error"] else {
            return nil
        }
        if let code = errorValue as? Int {
            return code
        }
        if let number = errorValue as? NSNumber {
            return number.intValue
        }
        if let string = errorValue as? String, let code = Int(string) {
            return code
        }
        return nil
    }

    private func parsePresets(from data: Data) throws -> [WLEDPreset] {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        let dictionary = json as? [String: Any] ?? [:]
        let payload = dictionary["presets"] as? [String: Any] ?? dictionary
        var presets: [WLEDPreset] = []
        for (key, value) in payload {
            guard let id = Int(key), let presetDict = value as? [String: Any] else { continue }
            let name = presetDict["n"] as? String ?? "Preset \(id)"
            let quickLoad = presetDict["ql"] as? Bool
            let segment = parsePresetSegment(from: presetDict["seg"])
            presets.append(
                WLEDPreset(
                    id: id,
                    name: name,
                    quickLoad: quickLoad,
                    segment: segment
                )
            )
        }
        return presets.sorted { $0.id < $1.id }
    }

    private func parsePlaylists(from data: Data) throws -> [WLEDPlaylist] {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        let dictionary = json as? [String: Any] ?? [:]
        let payload = dictionary["playlists"] as? [String: Any]
            ?? dictionary["playlist"] as? [String: Any]
            ?? dictionary
        var playlists: [WLEDPlaylist] = []
        for (key, value) in payload {
            guard let id = Int(key), let playlistDict = value as? [String: Any] else { continue }
            let name = playlistDict["n"] as? String ?? "Playlist \(id)"
            let presets = decodeIntArray(playlistDict["ps"])
            let durations = decodeIntArray(playlistDict["dur"])
            let transitions = decodeIntArray(playlistDict["transition"])
            let repeatCount = decodeInt(playlistDict["repeat"])
            let endPresetId = decodeInt(playlistDict["end"])
            playlists.append(
                WLEDPlaylist(
                    id: id,
                    name: name,
                    presets: presets,
                    duration: durations,
                    transition: transitions,
                    repeat: repeatCount,
                    endPresetId: endPresetId
                )
            )
        }
        return playlists.sorted { $0.id < $1.id }
    }

    private func parsePlaylistsFromPresets(data: Data) throws -> [WLEDPlaylist] {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        let dictionary = json as? [String: Any] ?? [:]
        var playlists: [WLEDPlaylist] = []
        for (key, value) in dictionary {
            guard let id = Int(key), let presetDict = value as? [String: Any] else { continue }
            guard let playlistDict = presetDict["playlist"] as? [String: Any] else { continue }
            let name = presetDict["n"] as? String ?? "Playlist \(id)"
            let presets = decodeIntArray(playlistDict["ps"])
            let durations = decodeIntArray(playlistDict["dur"])
            let transitions = decodeIntArray(playlistDict["transition"])
            let repeatCount = decodeInt(playlistDict["repeat"])
            let endPresetId = decodeInt(playlistDict["end"])
            playlists.append(
                WLEDPlaylist(
                    id: id,
                    name: name,
                    presets: presets,
                    duration: durations,
                    transition: transitions,
                    repeat: repeatCount,
                    endPresetId: endPresetId
                )
            )
        }
        return playlists.sorted { $0.id < $1.id }
    }

    private func parsePresetSegment(from value: Any?) -> SegmentUpdate? {
        guard let value else { return nil }
        if let segments = value as? [[String: Any]], let first = segments.first {
            return decodeSegmentUpdate(from: first)
        }
        if let segment = value as? [String: Any] {
            return decodeSegmentUpdate(from: segment)
        }
        return nil
    }

    private func decodeSegmentUpdate(from dict: [String: Any]) -> SegmentUpdate? {
        guard JSONSerialization.isValidJSONObject(dict) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return nil }
        return try? decoder.decode(SegmentUpdate.self, from: data)
    }

    private func decodeIntArray(_ value: Any?) -> [Int] {
        if let ints = value as? [Int] { return ints }
        if let numbers = value as? [NSNumber] { return numbers.map { $0.intValue } }
        if let strings = value as? [String] { return strings.compactMap { Int($0) } }
        if let mixed = value as? [Any] {
            return mixed.compactMap { decodeInt($0) }
        }
        return []
    }

    private func decodeInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func fetchPresetsFromFile(device: WLEDDevice) async throws -> [WLEDPreset] {
        guard let url = URL(string: "http://\(device.ipAddress)/presets.json") else {
            throw WLEDAPIError.invalidURL
        }
        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)
        if let errorCode = wledErrorCode(from: data) {
            if errorCode == 4 {
                throw WLEDAPIError.httpError(501)
            }
            throw WLEDAPIError.invalidResponse
        }
        return try parsePresets(from: data)
    }

    private func fetchPlaylistsFromPresetsFile(device: WLEDDevice) async throws -> [WLEDPlaylist] {
        guard let url = URL(string: "http://\(device.ipAddress)/presets.json") else {
            throw WLEDAPIError.invalidURL
        }
        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)
        if let errorCode = wledErrorCode(from: data) {
            if errorCode == 4 {
                throw WLEDAPIError.httpError(501)
            }
            throw WLEDAPIError.invalidResponse
        }
        return try parsePlaylistsFromPresets(data: data)
    }
    
    private func parseResponse(data: Data, device: WLEDDevice) throws -> WLEDResponse {
        // Handle empty data by creating a default success response
        guard !data.isEmpty else {
            return createSuccessResponse(for: device)
        }
        
        // First, try to decode the simple `{"success":true}` response
        if let successResponse = try? decoder.decode(WLEDSuccessResponse.self, from: data), successResponse.success {
            return createSuccessResponse(for: device)
        }
        
        // If that fails, try to decode the full WLEDResponse
        do {
            return try decoder.decode(WLEDResponse.self, from: data)
        } catch {
            print("Failed to decode WLED response: \(String(data: data, encoding: .utf8) ?? "invalid UTF-8")")
            throw WLEDAPIError.decodingError(error)
        }
    }
    
    private func createSuccessResponse(for device: WLEDDevice) -> WLEDResponse {
        return WLEDResponse(
            info: Info(
                name: device.name,
                mac: device.id,
                ver: "0.14.0",
                leds: LedInfo(count: 30, seglc: nil, lc: nil, cct: nil, rgbw: nil, wv: nil)
            ),
            state: WLEDState(
                brightness: device.brightness,
                isOn: device.isOn,
                segments: [],
                transitionDeciseconds: nil,
                presetId: nil,
                playlistId: nil
            )
        )
    }
    
    private func handleError(_ error: Error, device: WLEDDevice) -> WLEDAPIError {
        if let apiError = error as? WLEDAPIError {
            return apiError
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .notConnectedToInternet, .networkConnectionLost:
                return .deviceOffline(device.name)
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .deviceUnreachable(device.name)
            case .badURL, .unsupportedURL:
                return .invalidURL
            default:
                return .networkError(urlError)
            }
        }
        
        return .networkError(error)
}

    // MARK: - Internal helpers
    private func segmentedPresetState(
        device: WLEDDevice,
        gradient: LEDGradient,
        brightness: Int,
        on: Bool,
        temperature: Double?,
        whiteLevel: Double?
    ) -> WLEDStateUpdate {
        let totalLEDs = device.state?.segments.compactMap { $0.stop }.max().map { max(1, $0) }
            ?? device.state?.segments.compactMap { $0.len }.reduce(0, +)
            ?? 120
        let segmentCount = min(maxPresetSegmentCount, max(2, min(defaultPresetSegmentCount, totalLEDs)))
        let stops = presetSegmentStops(totalLEDs: totalLEDs, segmentCount: segmentCount)
        let colors = presetSegmentColors(for: gradient, count: segmentCount)
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == sortedStops.first?.hexColor }
        let cctValue = temperature.map { Int(round($0 * 255.0)) }
        var whiteValue = whiteLevel.map { Int(round(max(0.0, min(1.0, $0)) * 255.0)) }
        if whiteValue == nil, cctValue != nil {
            whiteValue = 255
        }
        let useWhite = whiteValue != nil
        let useCCTOnly = isSolidColor && cctValue != nil && !useWhite

        var updates: [SegmentUpdate] = []
        for (idx, range) in stops.enumerated() {
            let rgb = colors[idx]
            var col: [[Int]]? = [[rgb[0], rgb[1], rgb[2]]]
            if useCCTOnly {
                col = nil
            } else if useWhite, let whiteValue {
                col = [[rgb[0], rgb[1], rgb[2], whiteValue]]
            }
            updates.append(
                SegmentUpdate(
                    id: idx,
                    start: range.start,
                    stop: range.stop,
                    on: on,
                    col: col,
                    cct: cctValue
                )
            )
        }

        return WLEDStateUpdate(
            on: on,
            bri: brightness,
            seg: updates
        )
    }

    private struct PlaylistStepPlan {
        let steps: Int
        let durations: [Int]
        let transitions: [Int]
    }

    private func playlistStepPlan(for durationSeconds: Double) -> PlaylistStepPlan {
        let clampedDuration = min(maxWLEDPlaylistDurationSeconds, max(0.1, durationSeconds))
        let holdSeconds = clampedDuration >= playlistHoldThresholdSeconds
            ? min(playlistHoldMaxSeconds, clampedDuration / playlistHoldScaleSeconds)
            : 0.0
        let targetLegSeconds = maxWLEDPlaylistTransitionSeconds + holdSeconds
        var legs = max(1, Int(ceil(clampedDuration / targetLegSeconds)))
        legs = min(maxWLEDPlaylistEntries - 1, legs)
        let stepTransitionSeconds = max(
            0.1,
            min(
                maxWLEDPlaylistTransitionSeconds,
                (clampedDuration / Double(legs)) - holdSeconds
            )
        )
        let transitionDeciseconds = max(1, min(maxWLEDTransitionDeciseconds, Int(round(stepTransitionSeconds * 10.0))))
        let holdDeciseconds = max(0, Int(round(holdSeconds * 10.0)))
        let durationDeciseconds = min(maxWLEDTransitionDeciseconds, transitionDeciseconds + holdDeciseconds)
        let steps = legs + 1
        let durations = Array(repeating: durationDeciseconds, count: steps)
        let transitions = Array(repeating: transitionDeciseconds, count: steps)
        return PlaylistStepPlan(steps: steps, durations: durations, transitions: transitions)
    }

    private func interpolatedGradient(from: LEDGradient, to: LEDGradient, t: Double) -> LEDGradient {
        let a = from.stops.sorted { $0.position < $1.position }
        let b = to.stops.sorted { $0.position < $1.position }
        let count = max(a.count, b.count, 2)
        let denom = Double(max(1, count - 1))
        let positions = (0..<count).map { Double($0) / denom }
        let stops = positions.map { pos in
            let ca = GradientSampler.sampleColor(at: pos, stops: a, interpolation: from.interpolation).toRGBArray()
            let cb = GradientSampler.sampleColor(at: pos, stops: b, interpolation: to.interpolation).toRGBArray()
            let r = Int(round(Double(ca[0]) * (1.0 - t) + Double(cb[0]) * t))
            let g = Int(round(Double(ca[1]) * (1.0 - t) + Double(cb[1]) * t))
            let b = Int(round(Double(ca[2]) * (1.0 - t) + Double(cb[2]) * t))
            let mixed = Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
            return GradientStop(position: pos, hexColor: mixed.toHex())
        }
        return LEDGradient(stops: stops, interpolation: to.interpolation)
    }

    private func interpolateOptional(_ start: Double?, _ end: Double?, t: Double) -> Double? {
        if let start, let end {
            return start + (end - start) * t
        }
        return start ?? end
    }

    private func presetSegmentStops(totalLEDs: Int, segmentCount: Int) -> [(start: Int, stop: Int)] {
        guard totalLEDs > 0, segmentCount > 0 else { return [] }
        let base = totalLEDs / segmentCount
        let remainder = totalLEDs % segmentCount
        var stops: [(Int, Int)] = []
        var cursor = 0
        for idx in 0..<segmentCount {
            let extra = idx < remainder ? 1 : 0
            let len = max(1, base + extra)
            let start = cursor
            let stop = min(totalLEDs, cursor + len)
            stops.append((start: start, stop: stop))
            cursor = stop
        }
        return stops
    }

    private func allocateIds(from start: Int, excluding used: Set<Int>, count: Int) -> [Int]? {
        guard count > 0 else { return [] }
        var results: [Int] = []
        for id in stride(from: start, through: 1, by: -1) {
            if !used.contains(id) {
                results.append(id)
                if results.count == count {
                    break
                }
            }
        }
        return results.count == count ? results : nil
    }

    private func presetSegmentColors(for gradient: LEDGradient, count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let denom = Double(count)
        return (0..<count).map { idx in
            let t = (Double(idx) + 0.5) / denom
            let color = GradientSampler.sampleColor(at: t, stops: sortedStops, interpolation: gradient.interpolation)
            return color.toRGBArray()
        }
    }

    private func savePresetViaState(_ request: WLEDPresetSaveRequest, device: WLEDDevice) async throws {
        var body: [String: Any] = [
            "psave": request.id,
            "n": request.name,
            "ib": true,
            "sb": true,
            "sc": true
        ]
        if request.saveOnly == true {
            body["o"] = true
        }
        if let quickLoad = request.quickLoad {
            body["ql"] = quickLoad
        }
        if let state = request.state {
            let stateData = try encoder.encode(state)
            if let stateDict = try JSONSerialization.jsonObject(with: stateData, options: []) as? [String: Any] {
                for (key, value) in stateDict {
                    body[key] = value
                }
            }
        }
        #if DEBUG
        let keys = body.keys.sorted().joined(separator: ",")
        print("🔎 Preset psave request for \(device.name): id=\(request.id) keys=[\(keys)]")
        #endif
        _ = try await postState(device, body: body)
    }

    private func savePlaylistViaState(_ request: WLEDPlaylistSaveRequest, device: WLEDDevice) async throws {
        var playlist: [String: Any] = [
            "ps": request.ps,
            "dur": request.dur,
            "transition": request.transition
        ]
        if let repeatCount = request.repeat {
            playlist["repeat"] = repeatCount
        }
        if let endPresetId = request.endPresetId {
            playlist["end"] = endPresetId
        }
        let body: [String: Any] = [
            "psave": request.id,
            "n": request.name,
            "playlist": playlist,
            "o": true
        ]
        #if DEBUG
        let keys = body.keys.sorted().joined(separator: ",")
        print("🔎 Playlist psave request for \(device.name): id=\(request.id) keys=[\(keys)]")
        #endif
        _ = try await postState(device, body: body)
    }

    private func postState(_ device: WLEDDevice, body: [String: Any]) async throws -> WLEDResponse {
        guard let url = URL(string: device.jsonEndpoint) else {
            throw WLEDAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)
        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            let snippet = debugPayloadSnippet(data, limit: 200)
            print("✅ State POST for \(device.name): status=\(httpResponse.statusCode) bytes=\(data.count) body=\(snippet)")
        }
        #endif
        return try parseResponse(data: data, device: device)
    }

    private func debugPayloadSnippet(_ data: Data, limit: Int) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        if text.count <= limit {
            return text
        }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "..."
    }

    // MARK: - LED Configuration API
    
    /// Update LED hardware configuration for a WLED device
    /// - Parameters:
    ///   - config: The LED configuration to apply
    ///   - device: The target WLED device
    /// - Returns: Success response
    /// - Throws: WLEDAPIError if the request fails
    func updateLEDConfiguration(_ config: LEDConfiguration, for device: WLEDDevice) async throws -> WLEDResponse {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the configuration payload matching WLED's expected format
        let configPayload: [String: Any] = [
            "hw": [
                "led": [
                    "total": config.ledCount,
                    "maxpwr": config.maxTotalCurrent,
                    "rgbwm": config.autoWhiteMode,
                    "cct": false, // Color correction temperature
                    "cr": false,  // Color correction from RGB
                    "ic": false,  // Color correction IC
                    "cb": 0,      // Color correction blending
                    "fps": 42,    // Target FPS
                    "prl": false  // Parallel I2S
                ]
            ],
            "leds": [
                [
                    "pin": [config.gpioPin],
                    "len": config.ledCount,
                    "type": config.stripType,
                    "co": config.colorOrder,
                    "start": config.startLED,
                    "skip": config.skipFirstLEDs,
                    "rev": config.reverseDirection,
                    "rf": config.offRefresh,
                    "aw": config.autoWhiteMode,
                    "la": config.maxCurrentPerLED,
                    "ma": config.maxTotalCurrent,
                    "per": config.usePerOutputLimiter
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: configPayload)
        } catch {
            throw WLEDAPIError.encodingError(error)
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            
            // Handle empty response for successful POST requests
            if data.isEmpty {
                return createSuccessResponse(for: device)
            }
            
            return try parseResponse(data: data, device: device)
        } catch {
            throw handleError(error, device: device)
        }
    }
    
    /// Get current LED configuration from a WLED device
    /// - Parameter device: The target WLED device
    /// - Returns: Current LED configuration
    /// - Throws: WLEDAPIError if the request fails
    func getLEDConfiguration(for device: WLEDDevice) async throws -> LEDConfiguration {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            try validateHTTPResponse(response, device: device)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hw = json["hw"] as? [String: Any],
                  let led = hw["led"] as? [String: Any],
                  let leds = json["leds"] as? [[String: Any]],
                  let firstLED = leds.first else {
                throw WLEDAPIError.invalidResponse
            }
            
            // Extract configuration values with defaults
            let stripType = firstLED["type"] as? Int ?? 0
            let colorOrder = firstLED["co"] as? Int ?? 0
            let gpioPin = (firstLED["pin"] as? [Int])?.first ?? 16
            let ledCount = firstLED["len"] as? Int ?? 120
            let startLED = firstLED["start"] as? Int ?? 0
            let skipFirstLEDs = firstLED["skip"] as? Int ?? 0
            let reverseDirection = firstLED["rev"] as? Bool ?? false
            let offRefresh = firstLED["rf"] as? Bool ?? false
            let autoWhiteMode = firstLED["aw"] as? Int ?? 0
            let maxCurrentPerLED = firstLED["la"] as? Int ?? 55
            let maxTotalCurrent = led["maxpwr"] as? Int ?? 3850
            let usePerOutputLimiter = firstLED["per"] as? Bool ?? false
            let enableABL = led["abl"] as? Bool ?? true
            let cctRangeSource = led["cct"] ?? firstLED["cct"]
            let (cctMin, cctMax): (Int?, Int?) = {
                if let range = cctRangeSource as? [Int], range.count >= 2 {
                    return (range[0], range[1])
                }
                if let range = cctRangeSource as? [Double], range.count >= 2 {
                    return (Int(round(range[0])), Int(round(range[1])))
                }
                if let dict = cctRangeSource as? [String: Any] {
                    let minInt = dict["min"] as? Int
                    let minDouble = dict["min"] as? Double
                    let maxInt = dict["max"] as? Int
                    let maxDouble = dict["max"] as? Double
                    let resolvedMin = minInt ?? minDouble.map { Int(round($0)) }
                    let resolvedMax = maxInt ?? maxDouble.map { Int(round($0)) }
                    return (resolvedMin, resolvedMax)
                }
                return (nil, nil)
            }()
            
            return LEDConfiguration(
                stripType: stripType,
                colorOrder: colorOrder,
                gpioPin: gpioPin,
                ledCount: ledCount,
                startLED: startLED,
                skipFirstLEDs: skipFirstLEDs,
                reverseDirection: reverseDirection,
                offRefresh: offRefresh,
                autoWhiteMode: autoWhiteMode,
                cctKelvinMin: cctMin,
                cctKelvinMax: cctMax,
                maxCurrentPerLED: maxCurrentPerLED,
                maxTotalCurrent: maxTotalCurrent,
                usePerOutputLimiter: usePerOutputLimiter,
                enableABL: enableABL
            )
        } catch {
            throw handleError(error, device: device)
        }
    }
    
    /// Update specific LED settings without full configuration
    /// - Parameters:
    ///   - device: The target WLED device
    ///   - stripType: LED strip type (optional)
    ///   - colorOrder: Color order (optional)
    ///   - gpioPin: GPIO pin (optional)
    ///   - ledCount: Number of LEDs (optional)
    ///   - maxCurrent: Maximum current in mA (optional)
    ///   - enableABL: Enable automatic brightness limiter (optional)
    /// - Returns: Success response
    /// - Throws: WLEDAPIError if the request fails
    func updateLEDSettings(for device: WLEDDevice, 
                          stripType: Int? = nil,
                          colorOrder: Int? = nil,
                          gpioPin: Int? = nil,
                          ledCount: Int? = nil,
                          maxCurrent: Int? = nil,
                          enableABL: Bool? = nil) async throws -> WLEDResponse {
        
        // Get current configuration first
        let currentConfig = try await getLEDConfiguration(for: device)
        
        // Create updated configuration with provided values
        let updatedConfig = LEDConfiguration(
            stripType: stripType ?? currentConfig.stripType,
            colorOrder: colorOrder ?? currentConfig.colorOrder,
            gpioPin: gpioPin ?? currentConfig.gpioPin,
            ledCount: ledCount ?? currentConfig.ledCount,
            startLED: currentConfig.startLED,
            skipFirstLEDs: currentConfig.skipFirstLEDs,
            reverseDirection: currentConfig.reverseDirection,
            offRefresh: currentConfig.offRefresh,
            autoWhiteMode: currentConfig.autoWhiteMode,
            cctKelvinMin: currentConfig.cctKelvinMin,
            cctKelvinMax: currentConfig.cctKelvinMax,
            maxCurrentPerLED: currentConfig.maxCurrentPerLED,
            maxTotalCurrent: maxCurrent ?? currentConfig.maxTotalCurrent,
            usePerOutputLimiter: currentConfig.usePerOutputLimiter,
            enableABL: enableABL ?? currentConfig.enableABL
        )
        
        return try await updateLEDConfiguration(updatedConfig, for: device)
    }
    
    // MARK: - Cache Management for ResourceManager
    
    func getCacheSize() async -> Int {
        return requestCache.count
    }
    
    func clearCache() async {
        requestCache.removeAll()
        urlSession.configuration.urlCache?.removeAllCachedResponses()
    }
    
    func cleanup() async {
        await clearCache()
    }
    
    // MARK: - Advanced Cache Management
    
    /// Bypass cache for a specific device after successful POST operations
    private func bypassCache(for deviceId: String) {
        let cacheKey = "\(deviceId)_state"
        requestCache.removeValue(forKey: cacheKey)
        
        #if DEBUG
        logger.debug("Cache bypassed for device: \(deviceId)")
        #endif
    }
    
    /// Evict expired entries and enforce cache size limits
    private func evictCacheIfNeeded() {
        let now = Date()
        
        // Remove expired entries efficiently
        // Optimized: Remove expired entries in a single pass
        let expiredKeys = requestCache.compactMap { (key, value) -> String? in
            now.timeIntervalSince(value.timestamp) >= cacheExpirationInterval ? key : nil
        }
        
        // Batch remove expired entries
        for key in expiredKeys {
            requestCache.removeValue(forKey: key)
        }
        
        // If still over limit, remove oldest entries efficiently
        // Optimized: Only sort what we need to remove, not the entire cache
        if requestCache.count > maxCacheSize {
            let entriesToRemove = requestCache.count - maxCacheSize
            // Find oldest entries by sorting and taking only what we need to remove
            let oldestEntries = requestCache.sorted { $0.value.timestamp < $1.value.timestamp }.prefix(entriesToRemove)
            
            for (key, _) in oldestEntries {
                requestCache.removeValue(forKey: key)
            }
            
            #if DEBUG
            logger.debug("Cache evicted \(entriesToRemove) entries, current size: \(self.requestCache.count)")
            #endif
        }
    }
} 

private struct PresetStorePayload: Encodable {
    let ps: [String: PresetStoreBody]
}

private struct PresetStoreBody: Encodable {
    let n: String
    let ql: Bool?
    let win: WLEDStateUpdate?
    let playlist: PresetPlaylistBody?
}

// MARK: - Playlist Models

private struct PresetPlaylistBody: Encodable {
    let ps: [Int]
    let dur: [Int]
    let transition: [Int]
    let `repeat`: Int?
    let end: Int?
}

struct WLEDPlaylistSaveRequest: Encodable {
    let id: Int
    let name: String
    let ps: [Int]  // Preset IDs
    let dur: [Int]  // Durations in deciseconds (per preset)
    let transition: [Int]  // Transition times in deciseconds (per preset)
    let `repeat`: Int?  // Repeat count (1 = one cycle, 0 = infinite, nil = WLED default)
    let endPresetId: Int?  // Preset to apply at end (optional)
}

private struct PlaylistStorePayload: Encodable {
    let playlist: [String: PlaylistStoreBody]
}

private struct PlaylistStoreBody: Encodable {
    let n: String
    let ps: [Int]
    let dur: [Int]
    let transition: [Int]
    let `repeat`: Int?
    let end: Int?
} 
