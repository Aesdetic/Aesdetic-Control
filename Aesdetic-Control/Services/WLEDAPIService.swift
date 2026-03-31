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
import CoreLocation

// MARK: - API Service Protocol

protocol WLEDAPIServiceProtocol {
    func getState(for device: WLEDDevice) async throws -> WLEDResponse
    func updateState(for device: WLEDDevice, state: WLEDStateUpdate) async throws -> WLEDResponse
    func lastSuccessfulRequestDate(for deviceId: String) async -> Date?
    func ensureColorGammaCorrectionEnabled(for device: WLEDDevice) async throws -> Bool
    func setPower(for device: WLEDDevice, isOn: Bool, transitionDeciseconds: Int?) async throws -> WLEDResponse
    func setBrightness(for device: WLEDDevice, brightness: Int, transitionDeciseconds: Int?) async throws -> WLEDResponse
    func setColor(for device: WLEDDevice, color: [Int], cct: Int?, white: Int?, transitionDeciseconds: Int?, segmentId: Int?) async throws -> WLEDResponse
    func setCCT(for device: WLEDDevice, cct: Int, segmentId: Int) async throws -> WLEDResponse
    func setCCT(for device: WLEDDevice, cctKelvin: Int, segmentId: Int) async throws -> WLEDResponse
    func fetchPresets(for device: WLEDDevice) async throws -> [WLEDPreset]
    func savePreset(_ request: WLEDPresetSaveRequest, to device: WLEDDevice) async throws
    func setEffect(_ effectId: Int, forSegment segmentId: Int, speed: Int?, intensity: Int?, palette: Int?, custom1: Int?, custom2: Int?, custom3: Int?, option1: Bool?, option2: Bool?, option3: Bool?, colors: [[Int]]?, device: WLEDDevice, turnOn: Bool?, releaseRealtime: Bool) async throws -> WLEDState
    func fetchPalettePreviewPage(for device: WLEDDevice, page: Int) async throws -> (maxPage: Int, palettes: [String: Any])
    func releaseRealtimeOverride(for device: WLEDDevice) async
    
    // Playlist management
    func savePlaylist(_ request: WLEDPlaylistSaveRequest, to device: WLEDDevice) async throws -> [WLEDPlaylist]
    func fetchPlaylists(for device: WLEDDevice) async throws -> [WLEDPlaylist]
    func applyPlaylist(_ playlistId: Int, to device: WLEDDevice) async throws -> WLEDState
    func stopPlaylist(on device: WLEDDevice) async throws -> WLEDState
    func testPlaylist(_ request: WLEDPlaylistSaveRequest, on device: WLEDDevice) async throws -> WLEDState
    
    // Timer/Macro management
    func fetchTimers(for device: WLEDDevice) async throws -> [WLEDTimer]
    func updateTimer(_ timerUpdate: WLEDTimerUpdate, on device: WLEDDevice) async throws
    func disableTimer(slot: Int, device: WLEDDevice) async throws -> Bool
    
    // Deletion methods
    func deletePreset(id: Int, device: WLEDDevice) async throws -> Bool
    func deletePlaylist(id: Int, device: WLEDDevice) async throws -> Bool
    func renamePresetRecord(id: Int, name: String, device: WLEDDevice) async throws
    func renamePlaylistRecord(id: Int, name: String, device: WLEDDevice) async throws
    
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
    func fetchEffectNames(for device: WLEDDevice) async throws -> [String]
    func fetchFxData(for device: WLEDDevice) async throws -> [String]
    func fetchPaletteNames(for device: WLEDDevice) async throws -> [String]
    func rebootDevice(_ device: WLEDDevice) async throws
    func isPresetStoreMutationInFlight(deviceId: String) async -> Bool
    func isStateWriteBackoffActive(deviceId: String) async -> Bool
    func updateDeviceTimeSettings(for device: WLEDDevice, timeZone: TimeZone, coordinate: CLLocationCoordinate2D?) async throws
}

// MARK: - WLEDAPIService

actor WLEDAPIService: WLEDAPIServiceProtocol, CleanupCapable {
    static let shared = WLEDAPIService()

    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "APIService")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let wledTimerSlotCount = 10
    private let strictTimerCodecFeatureFlagKey = "wled.strict_timer_codec.enabled"
    private let defaultPresetSegmentCount: Int = 12
    private let maxPresetSegmentCount: Int = 16
    private var presetQueues: [String: Task<Void, Never>] = [:]
    private var presetQueueTokens: [String: Int] = [:]
    private var presetStoreQueueKeyByDeviceId: [String: String] = [:]
    private let presetWriteCooldownNanos: UInt64 = 700_000_000
    
    // Performance optimization: Request batching and caching
    private var requestCache: [String: (response: WLEDResponse, timestamp: Date)] = [:]
    private let cacheExpirationInterval: TimeInterval = 2.0 // 2 seconds cache
    private let maxConcurrentRequests = 6 // Limit concurrent requests for better performance
    private let maxCacheSize = 50 // Maximum number of cached responses
    private var lastCacheEviction: Date = .distantPast
    private let cacheEvictionInterval: TimeInterval = 10.0 // Only evict every 10 seconds
    private var lastStatePayloadByDevice: [String: (payload: Data, timestamp: Date)] = [:]
    private var lastStateSemanticSignatureByDevice: [String: (signature: String, timestamp: Date)] = [:]
    private var lastSuccessfulRequestByDevice: [String: Date] = [:]
    private var stateMutationsInFlight: Set<String> = []
    private var latestStateMutationSequenceByDevice: [String: Int] = [:]
    private var lastStateWriteAttemptAtByDevice: [String: Date] = [:]
    private var stateWriteNextAllowedAtByDevice: [String: Date] = [:]
    private var consecutiveStateWriteFailuresByDevice: [String: Int] = [:]
    private let stateWriteMinInterval: TimeInterval = 0.10
    private let stateWriteFailureBaseBackoff: TimeInterval = 0.25
    private let stateWriteFailureMaxBackoff: TimeInterval = 2.5
    private var lastCacheBypassLogByDevice: [String: Date] = [:]
    private var solarReferenceCache: [String: (coordinate: CLLocationCoordinate2D?, timeZone: TimeZone?, timestamp: Date)] = [:]
    private let solarReferenceCacheTTL: TimeInterval = 60
    private var presetJsonEndpointUnsupportedByStoreKey: Set<String> = []
    private var presetRecordPayloadCacheByStoreKey: [String: (records: [Int: [String: Any]], timestamp: Date)] = [:]
    private let presetRecordPayloadCacheTTL: TimeInterval = 20
    private var didLogTimerCodecLegacyFallback = false
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0 // Reduced timeout for better responsiveness
        config.timeoutIntervalForResource = 20.0
        config.httpMaximumConnectionsPerHost = 4 // Limit connections per host
        config.requestCachePolicy = .useProtocolCachePolicy
        self.urlSession = URLSession(configuration: config)
        
        // Configure JSON encoder to omit nil values
        // This ensures CCT-only updates don't include col: null
        #if DEBUG
        self.encoder.outputFormatting = [.prettyPrinted]
        #endif
    }

    func enqueuePresetStoreMutation<T>(
        deviceId: String,
        label: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let queueKey = resolvedPresetStoreQueueKey(forDeviceId: deviceId)
        return try await enqueuePresetOperation(deviceId: queueKey, label: label, operation: operation)
    }

    func waitForPresetStoreIdle(deviceId: String) async {
        let queueKey = resolvedPresetStoreQueueKey(forDeviceId: deviceId)
        #if DEBUG
        logger.debug("preset_store.mutation.wait_idle device=\(deviceId, privacy: .public)")
        #endif
        while presetQueues[queueKey] != nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func isPresetStoreMutationInFlight(deviceId: String) async -> Bool {
        let queueKey = resolvedPresetStoreQueueKey(forDeviceId: deviceId)
        return presetQueues[queueKey] != nil
    }

    func isStateWriteBackoffActive(deviceId: String) async -> Bool {
        guard let nextAllowed = stateWriteNextAllowedAtByDevice[deviceId] else {
            return false
        }
        return Date() < nextAllowed
    }

    private func enqueuePresetOperation<T>(
        deviceId: String,
        label: String? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let previous = presetQueues[deviceId]
        let token = (presetQueueTokens[deviceId] ?? 0) + 1
        presetQueueTokens[deviceId] = token
        let debugLabel = label
        let localLogger = logger
        let cooldownNanos = presetWriteCooldownNanos
        #if DEBUG
        if let label {
            logger.debug("preset_store.mutation.begin device=\(deviceId, privacy: .public) label=\(label, privacy: .public)")
        }
        #endif
        let task = Task<T, Error> {
            if let previous {
                _ = await previous.result
            }
            do {
                let result = try await operation()
                return result
            } catch {
                #if DEBUG
                if let debugLabel {
                    localLogger.error("preset_store.mutation.error device=\(deviceId, privacy: .public) label=\(debugLabel, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                }
                #endif
                throw error
            }
        }
        let cooldownTask = Task<T, Error> {
            let result = try await task.value
            if cooldownNanos > 0 {
                try? await Task.sleep(nanoseconds: cooldownNanos)
            }
            return result
        }
        presetQueues[deviceId] = Task { _ = try? await cooldownTask.value }
        defer {
            if presetQueueTokens[deviceId] == token {
                presetQueues.removeValue(forKey: deviceId)
                presetQueueTokens.removeValue(forKey: deviceId)
            }
            // Preset/playlist writes mutate preset store records; discard cached raw payloads.
            presetRecordPayloadCacheByStoreKey.removeValue(forKey: deviceId)
            #if DEBUG
            if let debugLabel {
                logger.debug("preset_store.mutation.end device=\(deviceId, privacy: .public) label=\(debugLabel, privacy: .public)")
            }
            #endif
        }
        return try await cooldownTask.value
    }

    private func presetStoreQueueKey(for device: WLEDDevice) -> String {
        let trimmedIP = device.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = trimmedIP.isEmpty ? device.id : "ip:\(trimmedIP)"
        presetStoreQueueKeyByDeviceId[device.id] = key
        return key
    }

    private func resolvedPresetStoreQueueKey(forDeviceId deviceId: String) -> String {
        if let mapped = presetStoreQueueKeyByDeviceId[deviceId] {
            return mapped
        }
        return deviceId
    }

    private enum StateMutationSlotResult {
        case acquired
        case superseded
        case cancelled
    }

    private func nextStateMutationSequence(deviceId: String) -> Int {
        let next = (latestStateMutationSequenceByDevice[deviceId] ?? 0) + 1
        latestStateMutationSequenceByDevice[deviceId] = next
        return next
    }

    private func isSupersededStateMutation(deviceId: String, sequence: Int) -> Bool {
        guard let latest = latestStateMutationSequenceByDevice[deviceId] else { return false }
        return sequence < latest
    }

    private func acquireStateMutationSlot(deviceId: String, sequence: Int) async -> StateMutationSlotResult {
        while stateMutationsInFlight.contains(deviceId) {
            if Task.isCancelled {
                return .cancelled
            }
            if isSupersededStateMutation(deviceId: deviceId, sequence: sequence) {
                return .superseded
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if isSupersededStateMutation(deviceId: deviceId, sequence: sequence) {
            return .superseded
        }
        stateMutationsInFlight.insert(deviceId)
        return .acquired
    }

    private func acquireStateMutationSlot(deviceId: String) async -> Bool {
        while stateMutationsInFlight.contains(deviceId) {
            if Task.isCancelled {
                return false
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        stateMutationsInFlight.insert(deviceId)
        return true
    }

    private func releaseStateMutationSlot(deviceId: String) {
        stateMutationsInFlight.remove(deviceId)
    }

    private func isStateWriteBackoffExempt(_ state: WLEDStateUpdate) -> Bool {
        // Keep explicit preset/playlist/reboot commands responsive; these are infrequent and user-intentional.
        return state.ps != nil || state.pl != nil || state.rb == true
    }

    private func waitForStateWriteBudget(
        deviceId: String,
        sequence: Int,
        state: WLEDStateUpdate
    ) async -> StateMutationSlotResult {
        if isStateWriteBackoffExempt(state) {
            return .acquired
        }
        while true {
            if Task.isCancelled {
                return .cancelled
            }
            if isSupersededStateMutation(deviceId: deviceId, sequence: sequence) {
                return .superseded
            }
            let now = Date()
            let minIntervalReadyAt = (lastStateWriteAttemptAtByDevice[deviceId] ?? .distantPast)
                .addingTimeInterval(stateWriteMinInterval)
            let failureBackoffReadyAt = stateWriteNextAllowedAtByDevice[deviceId] ?? .distantPast
            let readyAt = max(minIntervalReadyAt, failureBackoffReadyAt)
            if now >= readyAt {
                return .acquired
            }
            let delay = readyAt.timeIntervalSince(now)
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
        }
    }

    private func shouldApplyStateWriteFailureBackoff(_ error: WLEDAPIError) -> Bool {
        switch error {
        case .timeout, .deviceOffline, .deviceUnreachable, .deviceBusy, .networkError:
            return true
        case .httpError(let code):
            return code == 429 || code >= 500
        default:
            return false
        }
    }

    private func noteStateWriteSuccess(deviceId: String) {
        consecutiveStateWriteFailuresByDevice[deviceId] = 0
        stateWriteNextAllowedAtByDevice.removeValue(forKey: deviceId)
    }

    private func noteStateWriteFailure(deviceId: String, error: WLEDAPIError) {
        guard shouldApplyStateWriteFailureBackoff(error) else { return }
        let failures = min(8, (consecutiveStateWriteFailuresByDevice[deviceId] ?? 0) + 1)
        consecutiveStateWriteFailuresByDevice[deviceId] = failures
        let delay = min(
            stateWriteFailureMaxBackoff,
            stateWriteFailureBaseBackoff * pow(1.8, Double(max(0, failures - 1)))
        )
        let until = Date().addingTimeInterval(delay)
        stateWriteNextAllowedAtByDevice[deviceId] = until
        #if DEBUG
        logger.debug("state_write.backoff device=\(deviceId, privacy: .public) failures=\(failures) delay=\(delay, privacy: .public)")
        #endif
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
            
            recordSuccessfulRequest(deviceId: device.id)
            return wledResponse
        } catch {
            throw handleError(error, device: device)
        }
    }
    
    func updateState(for device: WLEDDevice, state: WLEDStateUpdate) async throws -> WLEDResponse {
        guard let url = URL(string: device.jsonEndpoint) else {
            throw WLEDAPIError.invalidURL
        }
        let mutationSequence = nextStateMutationSequence(deviceId: device.id)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try encoder.encode(state)
            let now = Date()
            if state.ps == nil && state.pl == nil,
               let last = lastStatePayloadByDevice[device.id],
               last.payload == jsonData,
               now.timeIntervalSince(last.timestamp) < 0.25 {
                #if DEBUG
                logger.debug("🔵 [Dedup] Skipping identical state update for \(device.name)")
                #endif
                return createSuccessResponse(for: device)
            }
            let relaxedSignature = relaxedStateDedupSignature(from: state, jsonData: jsonData)
            if state.ps == nil && state.pl == nil,
               let signature = relaxedSignature,
               let last = lastStateSemanticSignatureByDevice[device.id],
               last.signature == signature,
               now.timeIntervalSince(last.timestamp) < 0.35 {
                #if DEBUG
                logger.debug("🔵 [Dedup] Skipping semantically identical state update for \(device.name)")
                #endif
                return createSuccessResponse(for: device)
            }
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

        let slotResult = await acquireStateMutationSlot(deviceId: device.id, sequence: mutationSequence)
        switch slotResult {
        case .acquired:
            break
        case .superseded:
            #if DEBUG
            logger.debug("🔵 [Dedup] Dropping superseded state update for \(device.name)")
            #endif
            return createSuccessResponse(for: device)
        case .cancelled:
            throw WLEDAPIError.networkError(URLError(.cancelled))
        }
        defer { releaseStateMutationSlot(deviceId: device.id) }
        let pacingResult = await waitForStateWriteBudget(
            deviceId: device.id,
            sequence: mutationSequence,
            state: state
        )
        switch pacingResult {
        case .acquired:
            break
        case .superseded:
            #if DEBUG
            logger.debug("🔵 [Dedup] Dropping superseded state update after pacing for \(device.name)")
            #endif
            return createSuccessResponse(for: device)
        case .cancelled:
            throw WLEDAPIError.networkError(URLError(.cancelled))
        }
        lastStateWriteAttemptAtByDevice[device.id] = Date()
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            if state.ps == nil && state.pl == nil, let body = request.httpBody {
                let writeRecordedAt = Date()
                lastStatePayloadByDevice[device.id] = (body, writeRecordedAt)
                if let signature = relaxedStateDedupSignature(from: state, jsonData: body) {
                    lastStateSemanticSignatureByDevice[device.id] = (signature, writeRecordedAt)
                }
            }
            
            // Handle empty response for successful POST requests
            if data.isEmpty {
                return createSuccessResponse(for: device)
            }
            
            let wledResponse = try parseResponse(data: data, device: device)
            
            // Optimistic update: Bypass cache immediately after successful POST
            // This ensures fresh data is shown after user actions
            bypassCache(for: device.id)
            
            recordSuccessfulRequest(deviceId: device.id)
            noteStateWriteSuccess(deviceId: device.id)
            return wledResponse
        } catch {
            let mapped = handleError(error, device: device)
            noteStateWriteFailure(deviceId: device.id, error: mapped)
            throw mapped
        }
    }

    func lastSuccessfulRequestDate(for deviceId: String) async -> Date? {
        return lastSuccessfulRequestByDevice[deviceId]
    }

    private func relaxedStateDedupSignature(from state: WLEDStateUpdate, jsonData: Data) -> String? {
        guard state.ps == nil, state.pl == nil, state.udpn == nil, state.nl == nil, state.rb == nil else {
            return nil
        }
        guard let object = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else {
            return nil
        }
        let allowedTopLevelKeys: Set<String> = ["on", "bri", "seg", "tt", "transition", "mainseg", "lor"]
        guard Set(object.keys).isSubset(of: allowedTopLevelKeys) else { return nil }
        guard let segments = object["seg"] as? [[String: Any]], !segments.isEmpty else { return nil }

        let allowedSegmentKeys: Set<String> = [
            "id", "start", "stop", "on", "bri", "col", "cct",
            "fx", "sx", "ix", "pal", "c1", "c2", "c3", "frz"
        ]
        guard segments.allSatisfy({ Set($0.keys).isSubset(of: allowedSegmentKeys) }) else {
            return nil
        }

        var normalized = object
        normalized["seg"] = segments.map { segment -> [String: Any] in
            var copy = segment
            copy.removeValue(forKey: "start")
            copy.removeValue(forKey: "stop")
            return copy
        }
        return canonicalJSONSignature(normalized)
    }

    private func canonicalJSONSignature(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            return "{\(dict.keys.sorted().map { "\($0):\(canonicalJSONSignature(dict[$0] as Any))" }.joined(separator: ","))}"
        }
        if let array = value as? [Any] {
            return "[\(array.map { canonicalJSONSignature($0) }.joined(separator: ","))]"
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let string = value as? String {
            return "\"\(string)\""
        }
        if value is NSNull { return "null" }
        return String(describing: value)
    }
    
    func setPower(for device: WLEDDevice, isOn: Bool, transitionDeciseconds: Int? = nil) async throws -> WLEDResponse {
        let stateUpdate = WLEDStateUpdate(on: isOn, transitionDeciseconds: transitionDeciseconds)
        return try await updateState(for: device, state: stateUpdate)
    }
    
    func setBrightness(for device: WLEDDevice, brightness: Int, transitionDeciseconds: Int? = nil) async throws -> WLEDResponse {
        let stateUpdate = WLEDStateUpdate(bri: max(0, min(255, brightness)), transitionDeciseconds: transitionDeciseconds)
        return try await updateState(for: device, state: stateUpdate)
    }
    
    func setColor(for device: WLEDDevice, color: [Int], cct: Int? = nil, white: Int? = nil, transitionDeciseconds: Int? = nil, segmentId: Int? = nil) async throws -> WLEDResponse {
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

        let resolvedSegmentId = segmentId ?? device.state?.mainSegment ?? 0
        let segment = SegmentUpdate(id: resolvedSegmentId, col: [colorArray], cct: cct)
        let stateUpdate = WLEDStateUpdate(seg: [segment], transitionDeciseconds: transitionDeciseconds)
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
        let storeKey = presetStoreQueueKey(for: device)
        do {
            let presets = try await fetchPresetsFromFile(device: device)
            await MainActor.run {
                DeviceControlViewModel.shared.notePresetStoreHealthyReadSuccess(deviceId: device.id)
            }
            return presets
        } catch {
            var primaryError = normalizePresetPayloadError(error, device: device)
            if shouldRetryPresetPayloadRead(after: primaryError) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                do {
                    let presets = try await fetchPresetsFromFile(device: device)
                    await MainActor.run {
                        DeviceControlViewModel.shared.notePresetStoreHealthyReadSuccess(deviceId: device.id)
                    }
                    return presets
                } catch {
                    primaryError = normalizePresetPayloadError(error, device: device)
                }
            }

            guard !presetJsonEndpointUnsupportedByStoreKey.contains(storeKey),
                  shouldAttemptPresetJsonFallback(after: primaryError) else {
                throw primaryError
            }

            do {
                let fallback = try await fetchPresetsFromJsonEndpoint(device: device)
                await MainActor.run {
                    DeviceControlViewModel.shared.notePresetStoreDegradedReadable(
                        deviceId: device.id,
                        message: "Recovered preset read from /json/presets fallback"
                    )
                }
                return fallback
            } catch {
                let fallbackError = normalizePresetPayloadError(error, device: device)
                if case .httpError(let statusCode) = fallbackError, statusCode == 501 {
                    presetJsonEndpointUnsupportedByStoreKey.insert(storeKey)
                }
                if shouldRetryPresetPayloadRead(after: fallbackError),
                   let fallback = try? await fetchPresetsFromJsonEndpoint(device: device) {
                    await MainActor.run {
                        DeviceControlViewModel.shared.notePresetStoreDegradedReadable(
                            deviceId: device.id,
                            message: "Recovered preset read from /json/presets fallback"
                        )
                    }
                    return fallback
                }
                throw primaryError
            }
        }
    }
    
    func savePreset(_ request: WLEDPresetSaveRequest, to device: WLEDDevice) async throws {
        guard (1...250).contains(request.id) else {
            throw WLEDAPIError.invalidConfiguration
        }
        let queueKey = presetStoreQueueKey(for: device)
        try await enqueuePresetOperation(deviceId: queueKey, label: "preset.save") {
            try await self.savePresetViaState(request, device: device)
        }
    }
    
    // MARK: - Playlist Management
    
    func savePlaylist(_ request: WLEDPlaylistSaveRequest, to device: WLEDDevice) async throws -> [WLEDPlaylist] {
        let normalizedRequest = try validatedPlaylistRequest(request)
        let queueKey = presetStoreQueueKey(for: device)
        try await enqueuePresetOperation(deviceId: queueKey, label: "playlist.save") {
            try await self.savePlaylistViaState(normalizedRequest, device: device)
        }
        return (try? await fetchPlaylists(for: device)) ?? []
    }
    
    func fetchPlaylists(for device: WLEDDevice) async throws -> [WLEDPlaylist] {
        let storeKey = presetStoreQueueKey(for: device)
        do {
            let playlists = try await fetchPlaylistsFromPresetsFile(device: device)
            await MainActor.run {
                DeviceControlViewModel.shared.notePresetStoreHealthyReadSuccess(deviceId: device.id)
            }
            return playlists
        } catch {
            var primaryError = normalizePresetPayloadError(error, device: device)
            if shouldRetryPresetPayloadRead(after: primaryError) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                do {
                    let playlists = try await fetchPlaylistsFromPresetsFile(device: device)
                    await MainActor.run {
                        DeviceControlViewModel.shared.notePresetStoreHealthyReadSuccess(deviceId: device.id)
                    }
                    return playlists
                } catch {
                    primaryError = normalizePresetPayloadError(error, device: device)
                }
            }

            guard !presetJsonEndpointUnsupportedByStoreKey.contains(storeKey),
                  shouldAttemptPresetJsonFallback(after: primaryError) else {
                throw primaryError
            }

            do {
                let fallback = try await fetchPlaylistsFromJsonEndpoint(device: device)
                await MainActor.run {
                    DeviceControlViewModel.shared.notePresetStoreDegradedReadable(
                        deviceId: device.id,
                        message: "Recovered playlist read from /json/presets fallback"
                    )
                }
                return fallback
            } catch {
                let fallbackError = normalizePresetPayloadError(error, device: device)
                if case .httpError(let statusCode) = fallbackError, statusCode == 501 {
                    presetJsonEndpointUnsupportedByStoreKey.insert(storeKey)
                }
                if shouldRetryPresetPayloadRead(after: fallbackError),
                   let fallback = try? await fetchPlaylistsFromJsonEndpoint(device: device) {
                    await MainActor.run {
                        DeviceControlViewModel.shared.notePresetStoreDegradedReadable(
                            deviceId: device.id,
                            message: "Recovered playlist read from /json/presets fallback"
                        )
                    }
                    return fallback
                }
                throw primaryError
            }
        }
    }

    func rebootDevice(_ device: WLEDDevice) async throws {
        let stateUpdate = WLEDStateUpdate(rb: true)
        _ = try await updateState(for: device, state: stateUpdate)
    }
    
    /// Apply a playlist by selecting its playlist preset ID (`ps`) in the WLED JSON API.
    /// - Parameters:
    ///   - playlistId: The playlist ID to apply (1-250)
    ///   - device: The target WLED device
    /// - Returns: The updated WLEDState after applying the playlist
    /// - Throws: WLEDAPIError if the request fails
    func applyPlaylist(_ playlistId: Int, to device: WLEDDevice) async throws -> WLEDState {
        guard playlistId > 0 && playlistId <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }
        return try await applyPlaylist(
            playlistId,
            to: device,
            releaseRealtime: false,
            transitionDeciseconds: nil
        )
    }

    func applyPlaylist(_ playlistId: Int, to device: WLEDDevice, releaseRealtime: Bool) async throws -> WLEDState {
        return try await applyPlaylist(
            playlistId,
            to: device,
            releaseRealtime: releaseRealtime,
            transitionDeciseconds: nil
        )
    }

    func applyPlaylist(
        _ playlistId: Int,
        to device: WLEDDevice,
        releaseRealtime: Bool,
        transitionDeciseconds: Int?
    ) async throws -> WLEDState {
        guard playlistId > 0 && playlistId <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }
        let clampedTransition = transitionDeciseconds.map { min(max(0, $0), maxWLEDTransitionDeciseconds) }
        let stateUpdate = WLEDStateUpdate(
            on: true,
            transitionDeciseconds: clampedTransition,
            ps: playlistId,
            lor: releaseRealtime ? 0 : nil
        )
        let response = try await updateState(for: device, state: stateUpdate)
        return response.state
    }

    func stopPlaylist(on device: WLEDDevice) async throws -> WLEDState {
        var body: [String: Any] = ["playlist": [String: Any]()]
        body["lor"] = 0
        let response = try await postState(device, body: body)
        return response.state
    }

    func testPlaylist(_ request: WLEDPlaylistSaveRequest, on device: WLEDDevice) async throws -> WLEDState {
        let normalizedRequest = try validatedPlaylistRequest(request)
        var body: [String: Any] = [
            "playlist": playlistPayload(from: normalizedRequest),
            "on": true
        ]
        body["lor"] = 0
        let response = try await postState(device, body: body)
        return response.state
    }
    
    // MARK: - Timer/Macro Management

    private func decodeWLEDTimers(from rawTimersArray: [[String: Any]]) -> [WLEDTimer] {
        var timers = defaultLogicalWLEDTimers()

        // WLED stores timers as sparse positional entries.
        // During load, hour==255 entries are remapped to slots 8/9 (sunrise/sunset).
        var slot = 0
        for timerDict in rawTimersArray {
            guard slot <= 9 else { break }

            let enabled = (timerDict["en"] as? Bool)
                ?? ((timerDict["en"] as? Int ?? 0) != 0)
            let hour = timerDict["hour"] as? Int ?? 0
            let minute = timerDict["min"] as? Int ?? 0
            let days = timerDict["dow"] as? Int ?? 0x7F
            let macroId = timerDict["macro"] as? Int ?? 0
            let start = timerDict["start"] as? [String: Any]
            let end = timerDict["end"] as? [String: Any]
            let startMonth = start?["mon"] as? Int
            let startDay = start?["day"] as? Int
            let endMonth = end?["mon"] as? Int
            let endDay = end?["day"] as? Int

            if slot < 8 && hour == 255 {
                slot = 8
            }
            guard slot <= 9 else { break }

            timers[slot] = WLEDTimer(
                id: slot,
                enabled: enabled,
                hour: hour,
                minute: minute,
                days: days,
                macroId: macroId,
                startMonth: startMonth,
                startDay: startDay,
                endMonth: endMonth,
                endDay: endDay
            )
            slot += 1
        }

        return timers
    }

    private func legacyDecodeWLEDTimers(from rawTimersArray: [[String: Any]]) -> [WLEDTimer] {
        rawTimersArray.prefix(wledTimerSlotCount).enumerated().map { (offset, timerDict) in
            let enabled = (timerDict["en"] as? Bool)
                ?? ((timerDict["en"] as? Int ?? 0) != 0)
            let hour = timerDict["hour"] as? Int ?? 0
            let minute = timerDict["min"] as? Int ?? 0
            let days = timerDict["dow"] as? Int ?? 0x7F
            let macroId = timerDict["macro"] as? Int ?? 0
            let start = timerDict["start"] as? [String: Any]
            let end = timerDict["end"] as? [String: Any]
            let startMonth = start?["mon"] as? Int
            let startDay = start?["day"] as? Int
            let endMonth = end?["mon"] as? Int
            let endDay = end?["day"] as? Int

            return WLEDTimer(
                id: offset,
                enabled: enabled,
                hour: hour,
                minute: minute,
                days: days,
                macroId: macroId,
                startMonth: startMonth,
                startDay: startDay,
                endMonth: endMonth,
                endDay: endDay
            )
        }
    }

    private func defaultLogicalWLEDTimers() -> [WLEDTimer] {
        (0..<wledTimerSlotCount).map { defaultWLEDTimer(slot: $0) }
    }

    private func defaultWLEDTimer(slot: Int) -> WLEDTimer {
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

    private func mergeTimersApplyingUpdate(
        currentTimers: [WLEDTimer],
        timerUpdate: WLEDTimerUpdate
    ) throws -> [WLEDTimer] {
        guard timerUpdate.id >= 0, timerUpdate.id < wledTimerSlotCount else {
            throw WLEDAPIError.invalidConfiguration
        }

        let timersById = Dictionary(uniqueKeysWithValues: currentTimers.map { ($0.id, $0) })
        var normalizedById: [Int: WLEDTimer] = [:]
        for slot in 0..<wledTimerSlotCount {
            normalizedById[slot] = timersById[slot] ?? defaultWLEDTimer(slot: slot)
        }

        let existingTimer = normalizedById[timerUpdate.id] ?? defaultWLEDTimer(slot: timerUpdate.id)
        let updatedTimer = WLEDTimer(
            id: existingTimer.id,
            enabled: timerUpdate.enabled ?? existingTimer.enabled,
            hour: timerUpdate.hour ?? existingTimer.hour,
            minute: timerUpdate.minute ?? existingTimer.minute,
            days: timerUpdate.days ?? existingTimer.days,
            macroId: timerUpdate.macroId ?? existingTimer.macroId,
            startMonth: (timerUpdate.startMonth != nil && timerUpdate.startDay != nil) ? timerUpdate.startMonth : nil,
            startDay: (timerUpdate.startMonth != nil && timerUpdate.startDay != nil) ? timerUpdate.startDay : nil,
            endMonth: (timerUpdate.endMonth != nil && timerUpdate.endDay != nil) ? timerUpdate.endMonth : nil,
            endDay: (timerUpdate.endMonth != nil && timerUpdate.endDay != nil) ? timerUpdate.endDay : nil
        )
        normalizedById[timerUpdate.id] = updatedTimer

        return (0..<wledTimerSlotCount).map { slot in
            normalizedById[slot] ?? defaultWLEDTimer(slot: slot)
        }
    }

    private func legacyMergeTimersApplyingUpdate(
        currentTimers: [WLEDTimer],
        timerUpdate: WLEDTimerUpdate
    ) throws -> [WLEDTimer] {
        let targetCount = min(max(currentTimers.count, 1), wledTimerSlotCount)
        guard timerUpdate.id >= 0, timerUpdate.id < targetCount else {
            throw WLEDAPIError.invalidConfiguration
        }

        var timers = currentTimers
        while timers.count < targetCount {
            timers.append(defaultWLEDTimer(slot: timers.count))
        }

        let existingTimer = timers[timerUpdate.id]
        timers[timerUpdate.id] = WLEDTimer(
            id: existingTimer.id,
            enabled: timerUpdate.enabled ?? existingTimer.enabled,
            hour: timerUpdate.hour ?? existingTimer.hour,
            minute: timerUpdate.minute ?? existingTimer.minute,
            days: timerUpdate.days ?? existingTimer.days,
            macroId: timerUpdate.macroId ?? existingTimer.macroId,
            startMonth: (timerUpdate.startMonth != nil && timerUpdate.startDay != nil) ? timerUpdate.startMonth : nil,
            startDay: (timerUpdate.startMonth != nil && timerUpdate.startDay != nil) ? timerUpdate.startDay : nil,
            endMonth: (timerUpdate.endMonth != nil && timerUpdate.endDay != nil) ? timerUpdate.endMonth : nil,
            endDay: (timerUpdate.endMonth != nil && timerUpdate.endDay != nil) ? timerUpdate.endDay : nil
        )

        return timers
    }

    private func isStrictTimerCodecEnabled() -> Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: strictTimerCodecFeatureFlagKey) != nil {
            return UserDefaults.standard.bool(forKey: strictTimerCodecFeatureFlagKey)
        }
        #endif
        return true
    }

    private func timerHasPersistedMeaning(_ timer: WLEDTimer, slot: Int) -> Bool {
        let hasDateRange = timer.startMonth != nil || timer.startDay != nil || timer.endMonth != nil || timer.endDay != nil
        let hasNonDefaultDays = timer.days != 0x7F
        let hasMacro = timer.macroId != 0
        let hasClockTime = timer.hour != 0 || timer.minute != 0
        if slot >= 8 {
            // Solar slots are represented by hour=255; preserve that marker when present.
            let hasSolarMarker = timer.hour == 255
            return timer.enabled || hasMacro || hasClockTime || hasSolarMarker || hasNonDefaultDays || hasDateRange
        }
        return timer.enabled || hasMacro || hasClockTime || hasNonDefaultDays || hasDateRange
    }

    private func encodeWLEDTimersForConfig(_ timers: [WLEDTimer]) -> [[String: Any]] {
        let timerById = Dictionary(uniqueKeysWithValues: timers.map { ($0.id, $0) })
        var highestSlotToEncode: Int? = nil

        for slot in 0..<wledTimerSlotCount {
            let timer = timerById[slot] ?? defaultWLEDTimer(slot: slot)
            if timerHasPersistedMeaning(timer, slot: slot) {
                highestSlotToEncode = slot
            }
        }

        guard let highestSlotToEncode else {
            return []
        }

        // Encode positionally through the highest used slot so slot indices remain stable.
        // This avoids shifting timer slots when intermediate slots are empty.
        var encoded: [[String: Any]] = []
        for slot in 0...highestSlotToEncode {
            let timer = timerById[slot] ?? defaultWLEDTimer(slot: slot)
            var item: [String: Any] = [
                "en": timer.enabled,
                "hour": timer.hour,
                "min": timer.minute,
                "macro": timer.macroId,
                "dow": timer.days
            ]
            if let startMonth = timer.startMonth, let startDay = timer.startDay {
                item["start"] = ["mon": startMonth, "day": startDay]
            }
            if let endMonth = timer.endMonth, let endDay = timer.endDay {
                item["end"] = ["mon": endMonth, "day": endDay]
            }
            encoded.append(item)
        }

        return encoded
    }
    
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

            // /json/cfg can be either flat or nested under "cfg" depending on firmware/proxy path.
            let resolvedCfg = (json?["cfg"] as? [String: Any]) ?? json ?? [:]
            let rootTimersObject = json?["timers"] as? [String: Any]
            let resolvedTimersObject = (resolvedCfg["timers"] as? [String: Any]) ?? rootTimersObject

            let strictCodec = isStrictTimerCodecEnabled()
            let rawTimersArray = resolvedTimersObject?["ins"] as? [[String: Any]]
            let timersArray = rawTimersArray ?? []
            let timers: [WLEDTimer]
            if strictCodec {
                timers = decodeWLEDTimers(from: timersArray)
            } else {
                timers = legacyDecodeWLEDTimers(from: timersArray)
                if !didLogTimerCodecLegacyFallback {
                    logger.warning("timer.codec.legacy_fallback enabled=true")
                    didLogTimerCodecLegacyFallback = true
                }
            }

            #if DEBUG
            print("timer.slots.reported device=\(device.id) cfgInsCount=\(timersArray.count) logicalSlots=\(timers.count)")
            #endif
            return timers.sorted { $0.id < $1.id }
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
        guard timerUpdate.id >= 0, timerUpdate.id < wledTimerSlotCount else {
            throw WLEDAPIError.invalidConfiguration
        }
        let strictCodec = isStrictTimerCodecEnabled()

        // First, fetch current config to get timers array
        let fetchedTimers = try await fetchTimers(for: device)
        let currentTimers = strictCodec
            ? (fetchedTimers.isEmpty ? defaultLogicalWLEDTimers() : fetchedTimers)
            : fetchedTimers

        if let existing = currentTimers.first(where: { $0.id == timerUpdate.id }) {
            let desiredEnabled = timerUpdate.enabled ?? existing.enabled
            let desiredHour = timerUpdate.hour ?? existing.hour
            let desiredMinute = timerUpdate.minute ?? existing.minute
            let desiredDays = timerUpdate.days ?? existing.days
            let desiredMacroId = timerUpdate.macroId ?? existing.macroId
            let desiredStartMonth: Int? = (timerUpdate.startMonth != nil && timerUpdate.startDay != nil) ? timerUpdate.startMonth : nil
            let desiredStartDay: Int? = (timerUpdate.startMonth != nil && timerUpdate.startDay != nil) ? timerUpdate.startDay : nil
            let desiredEndMonth: Int? = (timerUpdate.endMonth != nil && timerUpdate.endDay != nil) ? timerUpdate.endMonth : nil
            let desiredEndDay: Int? = (timerUpdate.endMonth != nil && timerUpdate.endDay != nil) ? timerUpdate.endDay : nil

            let isUnchanged =
                existing.enabled == desiredEnabled &&
                existing.hour == desiredHour &&
                existing.minute == desiredMinute &&
                existing.days == desiredDays &&
                existing.macroId == desiredMacroId &&
                existing.startMonth == desiredStartMonth &&
                existing.startDay == desiredStartDay &&
                existing.endMonth == desiredEndMonth &&
                existing.endDay == desiredEndDay

            if isUnchanged {
                return
            }
        }

        let updatedTimers: [WLEDTimer]
        do {
            updatedTimers = try strictCodec
                ? mergeTimersApplyingUpdate(currentTimers: currentTimers, timerUpdate: timerUpdate)
                : legacyMergeTimersApplyingUpdate(currentTimers: currentTimers, timerUpdate: timerUpdate)
        } catch {
            if strictCodec, !didLogTimerCodecLegacyFallback {
                logger.warning("timer.codec.strict_write_failed_fallback_to_legacy error=\(error.localizedDescription, privacy: .public)")
                didLogTimerCodecLegacyFallback = true
            }
            throw error
        }
        let timersArray = encodeWLEDTimersForConfig(updatedTimers)
        
        // Send update
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use read-modify-write for /json/cfg so unrelated settings (gamma, LED preferences, etc.) are preserved
        // even on firmware variants that are less tolerant of partial config payloads.
        var configPayload = try await fetchRawConfig(for: device)
        configPayload["timers"] = ["ins": timersArray]
        if var cfg = configPayload["cfg"] as? [String: Any] {
            cfg["timers"] = ["ins": timersArray]
            configPayload["cfg"] = cfg
        }
        _ = enforceColorGammaCorrection(in: &configPayload)
        httpRequest.httpBody = try JSONSerialization.data(withJSONObject: configPayload, options: [])
        
        let (_, response) = try await urlSession.data(for: httpRequest)
        try validateHTTPResponse(response, device: device)
    }

#if DEBUG
    nonisolated var _wledTimerSlotCountForTesting: Int { 10 }

    func _decodeWLEDTimersForTesting(from rawTimersArray: [[String: Any]]) -> [WLEDTimer] {
        decodeWLEDTimers(from: rawTimersArray)
    }

    func _encodeWLEDTimersForTesting(_ timers: [WLEDTimer]) -> [[String: Any]] {
        encodeWLEDTimersForConfig(timers)
    }

    func _mergeTimersApplyingUpdateForTesting(
        currentTimers: [WLEDTimer],
        timerUpdate: WLEDTimerUpdate
    ) throws -> [WLEDTimer] {
        try mergeTimersApplyingUpdate(currentTimers: currentTimers, timerUpdate: timerUpdate)
    }
#endif

    /// Verify a timer slot matches the expected values after update.
    /// Only fields explicitly provided in `timerUpdate` are asserted.
    func verifyTimer(_ timerUpdate: WLEDTimerUpdate, on device: WLEDDevice) async throws -> Bool {
        let timers = try await fetchTimers(for: device)
        guard let timer = timers.first(where: { $0.id == timerUpdate.id }) else {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) reason=slot_missing available=\(timers.map { $0.id })")
            #endif
            return false
        }
        if let enabled = timerUpdate.enabled, timer.enabled != enabled {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=en expected=\(enabled) actual=\(timer.enabled)")
            #endif
            return false
        }
        if let hour = timerUpdate.hour, timer.hour != hour {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=hour expected=\(hour) actual=\(timer.hour)")
            #endif
            return false
        }
        if let minute = timerUpdate.minute, timer.minute != minute {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=min expected=\(minute) actual=\(timer.minute)")
            #endif
            return false
        }
        if let days = timerUpdate.days, timer.days != days {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=dow expected=\(days) actual=\(timer.days)")
            #endif
            return false
        }
        if let macroId = timerUpdate.macroId, timer.macroId != macroId {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=macro expected=\(macroId) actual=\(timer.macroId)")
            #endif
            return false
        }
        if let startMonth = timerUpdate.startMonth, timer.startMonth != startMonth {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=start.mon expected=\(startMonth) actual=\(timer.startMonth ?? -1)")
            #endif
            return false
        }
        if let startDay = timerUpdate.startDay, timer.startDay != startDay {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=start.day expected=\(startDay) actual=\(timer.startDay ?? -1)")
            #endif
            return false
        }
        if let endMonth = timerUpdate.endMonth, timer.endMonth != endMonth {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=end.mon expected=\(endMonth) actual=\(timer.endMonth ?? -1)")
            #endif
            return false
        }
        if let endDay = timerUpdate.endDay, timer.endDay != endDay {
            #if DEBUG
            print("timer.verify.mismatch device=\(device.id) slot=\(timerUpdate.id) field=end.day expected=\(endDay) actual=\(timer.endDay ?? -1)")
            #endif
            return false
        }
        return true
    }
    
    /// Disable a timer slot on a WLED device
    /// - Parameters:
    ///   - slot: Timer slot ID (0-9)
    ///   - device: The target WLED device
    /// - Returns: true if successful, false otherwise
    /// - Throws: WLEDAPIError if the request fails
    func disableTimer(slot: Int, device: WLEDDevice) async throws -> Bool {
        guard slot >= 0 else {
            throw WLEDAPIError.invalidConfiguration
        }

        // Fetch current timers
        let currentTimers = try await fetchTimers(for: device)

        guard let current = currentTimers.first(where: { $0.id == slot }) else {
            logger.warning("timer.delete.slot_missing device=\(device.id, privacy: .public) slot=\(slot, privacy: .public)")
            return true
        }

        #if DEBUG
        print("timer.delete.begin device=\(device.id) slot=\(slot) current=en:\(current.enabled) hour:\(current.hour) min:\(current.minute) dow:\(current.days) macro:\(current.macroId)")
        #endif

        // Timer-slot deletion should fully clear actionable state so it is reusable.
        let clearUpdate = WLEDTimerUpdate(
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

        do {
            try await updateTimer(clearUpdate, on: device)
        } catch {
            logger.error("timer.delete.update_failed device=\(device.id, privacy: .public) slot=\(slot, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }

        let verifyUpdate = WLEDTimerUpdate(
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
        let verified = try await verifyTimer(verifyUpdate, on: device)
        if !verified {
            logger.warning("timer.delete.verify_failed device=\(device.id, privacy: .public) slot=\(slot, privacy: .public)")
            return false
        }

        #if DEBUG
        if let latest = try? await fetchTimers(for: device).first(where: { $0.id == slot }) {
            print("timer.delete.done device=\(device.id) slot=\(slot) final=en:\(latest.enabled) hour:\(latest.hour) min:\(latest.minute) dow:\(latest.days) macro:\(latest.macroId)")
        }
        #endif
        logger.info("timer.delete.cleared device=\(device.id, privacy: .public) slot=\(slot, privacy: .public)")
        return true
    }

    // MARK: - Macro Trigger Bindings

    /// Fetch native WLED macro trigger bindings (button/voice/nightlight) from /json/cfg.
    func fetchMacroBindings(for device: WLEDDevice) async throws -> WLEDMacroBindings {
        let config = try await fetchRawConfig(for: device)
        let resolved = (config["cfg"] as? [String: Any]) ?? config

        let hw = resolved["hw"] as? [String: Any] ?? [:]
        let btn = hw["btn"] as? [String: Any] ?? [:]
        let ins = btn["ins"] as? [[String: Any]] ?? []
        let buttonMacrosRaw = (ins.first?["macros"] as? [Any]) ?? []
        let buttonPress = decodeInt(buttonMacrosRaw.indices.contains(0) ? buttonMacrosRaw[0] : nil) ?? 0
        let buttonLong = decodeInt(buttonMacrosRaw.indices.contains(1) ? buttonMacrosRaw[1] : nil) ?? 0
        let buttonDouble = decodeInt(buttonMacrosRaw.indices.contains(2) ? buttonMacrosRaw[2] : nil) ?? 0

        let interfaces = resolved["if"] as? [String: Any] ?? [:]
        let va = interfaces["va"] as? [String: Any] ?? [:]
        let voiceMacrosRaw = va["macros"] as? [Any] ?? []
        let alexaOn = decodeInt(voiceMacrosRaw.indices.contains(0) ? voiceMacrosRaw[0] : nil) ?? 0
        let alexaOff = decodeInt(voiceMacrosRaw.indices.contains(1) ? voiceMacrosRaw[1] : nil) ?? 0

        let light = resolved["light"] as? [String: Any] ?? [:]
        let nightLight = light["nl"] as? [String: Any] ?? [:]
        let nightLightMacro = decodeInt(nightLight["macro"]) ?? 0

        return WLEDMacroBindings(
            buttonPressMacro: clampMacroId(buttonPress),
            buttonLongPressMacro: clampMacroId(buttonLong),
            buttonDoublePressMacro: clampMacroId(buttonDouble),
            alexaOnMacro: clampMacroId(alexaOn),
            alexaOffMacro: clampMacroId(alexaOff),
            nightLightMacro: clampMacroId(nightLightMacro)
        )
    }

    /// Update native WLED macro trigger bindings (button/voice/nightlight) in /json/cfg.
    func updateMacroBindings(_ update: WLEDMacroBindingsUpdate, for device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }

        var configPayload = try await fetchRawConfig(for: device)
        applyMacroBindings(update, to: &configPayload)
        if var cfg = configPayload["cfg"] as? [String: Any] {
            applyMacroBindings(update, to: &cfg)
            configPayload["cfg"] = cfg
        }
        _ = enforceColorGammaCorrection(in: &configPayload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: configPayload, options: [])

        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)
    }
    
    /// Delete a preset from a WLED device
    /// - Parameters:
    ///   - id: Preset ID to delete
    ///   - device: The target WLED device
    /// - Returns: true if successful, false otherwise
    /// - Throws: WLEDAPIError if the request fails
    func deletePreset(id: Int, device: WLEDDevice) async throws -> Bool {
        guard (1...250).contains(id) else {
            throw WLEDAPIError.invalidConfiguration
        }
        let queueKey = presetStoreQueueKey(for: device)
        return try await enqueuePresetOperation(deviceId: queueKey, label: "preset.delete") {
            do {
                _ = try await self.postState(device, body: ["pdel": id])
                return true
            } catch {
                if let apiError = error as? WLEDAPIError,
                   case .httpError(let statusCode) = apiError,
                   statusCode == 404 {
                    return true
                }
                self.logger.warning("Preset deletion failed for \(id) on device \(device.id), will retry later")
                return false
            }
        }
    }

    private func applyMacroBindings(_ update: WLEDMacroBindingsUpdate, to root: inout [String: Any]) {
        if update.buttonPressMacro != nil || update.buttonLongPressMacro != nil || update.buttonDoublePressMacro != nil {
            var hw = root["hw"] as? [String: Any] ?? [:]
            var btn = hw["btn"] as? [String: Any] ?? [:]
            var ins = btn["ins"] as? [[String: Any]] ?? []
            if ins.isEmpty {
                ins = [[:]]
            }
            var firstButton = ins[0]
            var macros = firstButton["macros"] as? [Any] ?? []
            while macros.count < 3 {
                macros.append(0)
            }
            if let value = update.buttonPressMacro {
                macros[0] = clampMacroId(value)
            }
            if let value = update.buttonLongPressMacro {
                macros[1] = clampMacroId(value)
            }
            if let value = update.buttonDoublePressMacro {
                macros[2] = clampMacroId(value)
            }
            firstButton["macros"] = macros
            ins[0] = firstButton
            btn["ins"] = ins
            hw["btn"] = btn
            root["hw"] = hw
        }

        if update.alexaOnMacro != nil || update.alexaOffMacro != nil {
            var interfaces = root["if"] as? [String: Any] ?? [:]
            var va = interfaces["va"] as? [String: Any] ?? [:]
            var macros = va["macros"] as? [Any] ?? []
            while macros.count < 2 {
                macros.append(0)
            }
            if let value = update.alexaOnMacro {
                macros[0] = clampMacroId(value)
            }
            if let value = update.alexaOffMacro {
                macros[1] = clampMacroId(value)
            }
            va["macros"] = macros
            interfaces["va"] = va
            root["if"] = interfaces
        }

        if let value = update.nightLightMacro {
            var light = root["light"] as? [String: Any] ?? [:]
            var nl = light["nl"] as? [String: Any] ?? [:]
            nl["macro"] = clampMacroId(value)
            light["nl"] = nl
            root["light"] = light
        }
    }

    private func clampMacroId(_ value: Int) -> Int {
        min(250, max(0, value))
    }
    
    /// Delete a playlist from a WLED device
    /// - Parameters:
    ///   - id: Playlist ID to delete
    ///   - device: The target WLED device
    /// - Returns: true if successful, false otherwise
    /// - Throws: WLEDAPIError if the request fails
    func deletePlaylist(id: Int, device: WLEDDevice) async throws -> Bool {
        guard (1...250).contains(id) else {
            throw WLEDAPIError.invalidConfiguration
        }
        let queueKey = presetStoreQueueKey(for: device)
        return try await enqueuePresetOperation(deviceId: queueKey, label: "playlist.delete") {
            do {
                _ = try await self.postState(device, body: ["pdel": id])
                return true
            } catch {
                if let apiError = error as? WLEDAPIError,
                   case .httpError(let statusCode) = apiError,
                   statusCode == 404 {
                    return true
                }
                self.logger.warning("Playlist deletion failed for \(id) on device \(device.id), will retry later")
                return false
            }
        }
    }

    func renamePresetRecord(id: Int, name: String, device: WLEDDevice) async throws {
        guard (1...250).contains(id) else {
            throw WLEDAPIError.invalidConfiguration
        }
        let sanitizedName = sanitizedPresetName(name, fallback: "Preset \(id)")
        let queueKey = presetStoreQueueKey(for: device)
        try await enqueuePresetOperation(deviceId: queueKey, label: "preset.rename") {
            var payload = try await self.fetchPresetRecordPayload(id: id, device: device)
            payload["psave"] = id
            payload["n"] = sanitizedName
            payload["o"] = true
            payload.removeValue(forKey: "v")
            payload.removeValue(forKey: "time")
            payload.removeValue(forKey: "error")
            _ = try await self.postState(device, body: payload)
        }
    }

    func renamePlaylistRecord(id: Int, name: String, device: WLEDDevice) async throws {
        guard (1...250).contains(id) else {
            throw WLEDAPIError.invalidConfiguration
        }
        let queueKey = presetStoreQueueKey(for: device)
        try await enqueuePresetOperation(deviceId: queueKey, label: "playlist.rename") {
            var payload = try await self.fetchPresetRecordPayload(id: id, device: device)
            payload["psave"] = id
            payload["n"] = self.sanitizedPresetName(name, fallback: "Playlist \(id)")
            payload["o"] = true
            payload.removeValue(forKey: "v")
            payload.removeValue(forKey: "time")
            payload.removeValue(forKey: "error")
            _ = try await self.postState(device, body: payload)
        }
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
            whiteLevel: preset.whiteLevel,
            includeSegmentBounds: true
        )
        let saveRequest = WLEDPresetSaveRequest(
            id: presetId,
            name: preset.name,
            quickLoad: preset.quickLoadTag,
            state: stateUpdate,
            includeBrightness: preset.includeBrightness,
            saveSegmentBounds: preset.saveSegmentBounds,
            selectedSegmentsOnly: preset.selectedSegmentsOnly,
            applyAtBoot: preset.applyAtBoot,
            customAPICommand: preset.customAPICommand
        )
        try await savePreset(saveRequest, to: device)
        
        return presetId
    }
    
    /// Save a TransitionPreset as a multi-step WLED playlist (A→B, one cycle)
    @available(*, deprecated, message: "Use DeviceControlViewModel.createTransitionPlaylist(... persist: true) for transition preset generation")
    func saveTransitionPreset(_ preset: TransitionPreset, to device: WLEDDevice, playlistId: Int) async throws -> Int {
        #if DEBUG
        print("transition_preset.legacy_api_generator_called device=\(device.id) playlistId=\(playlistId)")
        #endif
        let existingPresets = try await fetchPresets(for: device)
        var usedPresetIds = Set(existingPresets.map { $0.id })
        usedPresetIds.insert(playlistId)
        let stepPlan = playlistStepPlan(
            for: preset.durationSec,
            timingUnit: playlistTimingUnit(for: device)
        )
        let stepCount = stepPlan.steps
        let existingStepIds = preset.wledStepPresetIds ?? []
        var reusableStepIds: [Int] = []
        if existingStepIds.count == stepCount {
            let validIds = existingStepIds.filter { (1...250).contains($0) }
            if validIds.count == stepCount, Set(validIds).isSubset(of: usedPresetIds) {
                reusableStepIds = validIds
                reusableStepIds.forEach { usedPresetIds.remove($0) }
            }
        }
        let presetIds: [Int]
        if reusableStepIds.count == stepCount {
            presetIds = reusableStepIds
        } else {
            guard let allocated = allocateIds(from: 250, excluding: usedPresetIds, count: stepCount) else {
                throw WLEDAPIError.invalidConfiguration
            }
            presetIds = allocated
        }

        let denom = Double(max(1, stepCount - 1))
        for (idx, presetId) in presetIds.enumerated() {
            let t = Double(idx) / denom
            let gradient = interpolatedGradient(from: preset.gradientA, to: preset.gradientB, t: t)
            let brightness = Int(round(Double(preset.brightnessA) * (1.0 - t) + Double(preset.brightnessB) * t))
            let presetBrightness = max(1, brightness)
            let temperature = interpolateOptional(preset.temperatureA, preset.temperatureB, t: t)
            let whiteLevel = interpolateOptional(preset.whiteLevelA, preset.whiteLevelB, t: t)
            let state = segmentedPresetState(
                device: device,
                gradient: gradient,
                brightness: presetBrightness,
                on: true,
                temperature: temperature,
                whiteLevel: whiteLevel,
                includeSegmentBounds: true
            )
            try await savePreset(
                WLEDPresetSaveRequest(
                    id: presetId,
                    name: "\(preset.name) Step \(idx + 1)",
                    quickLoad: nil,
                    state: state,
                    saveOnly: true,
                    includeBrightness: true,
                    saveSegmentBounds: true,
                    selectedSegmentsOnly: false,
                    transitionDeciseconds: device.state?.transitionDeciseconds ?? 7
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
            repeat: 1,  // Single cycle - stops at B
            endPresetId: 0,
            shuffle: 0
        )
        
        _ = try await savePlaylist(playlistRequest, to: device)

        if reusableStepIds.isEmpty, !existingStepIds.isEmpty {
            let newIds = Set(presetIds)
            let staleIds = existingStepIds.filter { !newIds.contains($0) }
            for presetId in staleIds {
                _ = try? await deletePreset(id: presetId, device: device)
            }
        }
        
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
            quickLoad: preset.quickLoadTag,
            state: stateUpdate,
            includeBrightness: preset.includeBrightness,
            saveSegmentBounds: preset.saveSegmentBounds,
            selectedSegmentsOnly: preset.selectedSegmentsOnly,
            applyAtBoot: preset.applyAtBoot,
            customAPICommand: preset.customAPICommand
        )
        
        try await savePreset(saveRequest, to: device)
        
        return presetId
    }

    func fetchEffectNames(for device: WLEDDevice) async throws -> [String] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/effects") else {
            throw WLEDAPIError.invalidURL
        }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            if let names = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return names
            }
            if let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return entries.compactMap { $0 as? String }
            }
            throw WLEDAPIError.decodingError(
                DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Unable to decode effects array")
                )
            )
        } catch {
            throw handleError(error, device: device)
        }
    }

    func fetchFxData(for device: WLEDDevice) async throws -> [String] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/fxdata") else {
            throw WLEDAPIError.invalidURL
        }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            if let fxdata = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return fxdata
            }
            if let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return entries.compactMap { $0 as? String }
            }
            throw WLEDAPIError.decodingError(
                DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Unable to decode fxdata array")
                )
            )
        } catch {
            throw handleError(error, device: device)
        }
    }

    func fetchPaletteNames(for device: WLEDDevice) async throws -> [String] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/palettes") else {
            throw WLEDAPIError.invalidURL
        }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            if let names = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return names
            }
            if let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return entries.compactMap { $0 as? String }
            }
            throw WLEDAPIError.decodingError(
                DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Unable to decode palette names")
                )
            )
        } catch {
            throw handleError(error, device: device)
        }
    }

    func fetchPalettePreviewPage(for device: WLEDDevice, page: Int) async throws -> (maxPage: Int, palettes: [String: Any]) {
        guard let url = URL(string: "http://\(device.ipAddress)/json/palx?page=\(page)") else {
            throw WLEDAPIError.invalidURL
        }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WLEDAPIError.decodingError(
                    DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: [], debugDescription: "Unable to decode palette preview JSON")
                    )
                )
            }
            let maxPage = root["m"] as? Int ?? 0
            let palettes = root["p"] as? [String: Any] ?? [:]
            return (maxPage: maxPage, palettes: palettes)
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

    func fetchUDPSyncConfig(for device: WLEDDevice) async throws -> (send: Bool, recv: Bool, network: Int) {
        let config = try await fetchRawConfig(for: device)
        let udpn = (config["udpn"] as? [String: Any])
            ?? ((config["cfg"] as? [String: Any])?["udpn"] as? [String: Any])
            ?? [:]
        let send = decodeBool(udpn["send"]) ?? false
        let recv = decodeBool(udpn["recv"]) ?? false
        let network = decodeInt(udpn["nn"]) ?? 0
        return (send: send, recv: recv, network: network)
    }

    /// Fetch WLED-configured solar location/timezone from /json/cfg (if.ntp).
    /// Returns nil components when the device has not set them.
    func fetchSolarReference(for device: WLEDDevice) async throws -> (coordinate: CLLocationCoordinate2D?, timeZone: TimeZone?) {
        if let cached = solarReferenceCache[device.id],
           Date().timeIntervalSince(cached.timestamp) < solarReferenceCacheTTL {
            return (cached.coordinate, cached.timeZone)
        }

        let config = try await fetchRawConfig(for: device)
        let resolved = parseSolarReference(from: config)
        solarReferenceCache[device.id] = (
            coordinate: resolved.coordinate,
            timeZone: resolved.timeZone,
            timestamp: Date()
        )
        return resolved
    }

    /// Update WLED solar reference (if.ntp) using app-provided location/timezone.
    /// This keeps sunrise/sunset timers device-native while removing manual setup friction.
    func updateSolarReference(
        for device: WLEDDevice,
        coordinate: CLLocationCoordinate2D,
        timeZone: TimeZone = .current
    ) async throws {
        try await updateDeviceTimeSettings(for: device, timeZone: timeZone, coordinate: coordinate)
    }

    /// Update WLED device time settings (if.ntp) using app-provided timezone,
    /// optionally updating solar location when coordinate is available.
    /// This keeps device clock alignment reliable even when location permission is unavailable.
    func updateDeviceTimeSettings(
        for device: WLEDDevice,
        timeZone: TimeZone = .current,
        coordinate: CLLocationCoordinate2D? = nil
    ) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }

        var configPayload = try await fetchRawConfig(for: device)
        applyTimeSettings(
            to: &configPayload,
            coordinate: coordinate,
            timeZone: timeZone
        )
        if var cfg = configPayload["cfg"] as? [String: Any] {
            applyTimeSettings(
                to: &cfg,
                coordinate: coordinate,
                timeZone: timeZone
            )
            configPayload["cfg"] = cfg
        }
        _ = enforceColorGammaCorrection(in: &configPayload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: configPayload, options: [])

        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)

        solarReferenceCache[device.id] = (
            coordinate: coordinate,
            timeZone: timeZone,
            timestamp: Date()
        )
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
        _ = enforceColorGammaCorrection(in: &existingConfig)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: existingConfig)

        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)

        // After config update, fetch the current state to return
        return try await getState(for: device)
    }

    /// Ensures WLED color gamma correction is enabled for this device.
    /// Returns true only when a config write was needed.
    @discardableResult
    func ensureColorGammaCorrectionEnabled(for device: WLEDDevice) async throws -> Bool {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }

        var config = try await fetchRawConfig(for: device)
        let changed = enforceColorGammaCorrection(in: &config)
        guard changed else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: config)

        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response, device: device)
        return true
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

    private func parseSolarReference(from config: [String: Any]) -> (coordinate: CLLocationCoordinate2D?, timeZone: TimeZone?) {
        let interfaces = (config["if"] as? [String: Any])
            ?? ((config["cfg"] as? [String: Any])?["if"] as? [String: Any])
            ?? [:]
        let ntp = interfaces["ntp"] as? [String: Any] ?? [:]

        let latitude = decodeDouble(ntp["lt"] ?? ntp["lat"])
        let longitude = decodeDouble(ntp["ln"] ?? ntp["lon"])
        let coordinate: CLLocationCoordinate2D? = {
            guard let latitude, let longitude else { return nil }
            guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return nil }
            // WLED uses 0/0 as unset in practice.
            guard abs(latitude) > 0.0001 || abs(longitude) > 0.0001 else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }()

        let timeZoneValue = ntp["tz"]
        let offsetSeconds = decodeInt(ntp["offset"])
        let timeZone: TimeZone? = {
            if let identifier = decodeString(timeZoneValue),
               let zone = TimeZone(identifier: identifier) {
                return zone
            }
            if let offsetSeconds,
               let zone = TimeZone(secondsFromGMT: offsetSeconds) {
                return zone
            }
            return nil
        }()

        return (coordinate: coordinate, timeZone: timeZone)
    }

    private func applySolarReference(
        to root: inout [String: Any],
        coordinate: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) {
        applyTimeSettings(
            to: &root,
            coordinate: coordinate,
            timeZone: timeZone
        )
    }

    private func applyTimeSettings(
        to root: inout [String: Any],
        coordinate: CLLocationCoordinate2D?,
        timeZone: TimeZone
    ) {
        var interfaces = root["if"] as? [String: Any] ?? [:]
        var ntp = interfaces["ntp"] as? [String: Any] ?? [:]
        ntp["en"] = true
        ntp["offset"] = timeZone.secondsFromGMT()
        if let coordinate {
            ntp["lt"] = coordinate.latitude
            ntp["ln"] = coordinate.longitude
        }
        interfaces["ntp"] = ntp
        root["if"] = interfaces
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

    /// Enforces color gamma correction while preserving all other WLED preferences.
    /// Only `light.gc.col` (and `light.gc.val` when invalid) is normalized.
    @discardableResult
    private func enforceColorGammaCorrection(in config: inout [String: Any]) -> Bool {
        var changed = false
        if enforceColorGammaCorrectionInRoot(&config) {
            changed = true
        }
        if var cfg = config["cfg"] as? [String: Any] {
            if enforceColorGammaCorrectionInRoot(&cfg) {
                config["cfg"] = cfg
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    private func enforceColorGammaCorrectionInRoot(_ root: inout [String: Any]) -> Bool {
        var light = root["light"] as? [String: Any] ?? [:]
        var gc = light["gc"] as? [String: Any] ?? [:]

        let currentVal = decodeDouble(gc["val"])
        let currentCol = decodeDouble(gc["col"])
        let validVal = (currentVal != nil && currentVal! > 1.0 && currentVal! <= 3.0) ? currentVal! : nil
        let validCol = (currentCol != nil && currentCol! > 1.0 && currentCol! <= 3.0) ? currentCol! : nil
        let targetGamma = validVal ?? validCol ?? 2.2

        var changed = false
        if validVal == nil {
            gc["val"] = targetGamma
            changed = true
        }
        if validCol == nil {
            gc["col"] = targetGamma
            changed = true
        }
        if changed {
            light["gc"] = gc
            root["light"] = light
        }
        return changed
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

        _ = enforceColorGammaCorrection(in: &config)
        
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
            if Task.isCancelled {
                throw CancellationError()
            }
            _ = try await postRawState(for: device, body: body)
            if Task.isCancelled {
                throw CancellationError()
            }
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

        guard await acquireStateMutationSlot(deviceId: device.id) else {
            throw WLEDAPIError.networkError(URLError(.cancelled))
        }
        defer { releaseStateMutationSlot(deviceId: device.id) }
        
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

            // Ensure realtime/live override is released after per-LED updates
            if end == total {
                body["lor"] = 0
            }
            
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
            seg: state.segments.map { segment in
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
    ///   - transitionDeciseconds: Optional transition time in deciseconds (tt)
    /// - Returns: The updated WLEDState after applying the preset
    /// - Throws: WLEDAPIError if the request fails
    func applyPreset(_ presetId: Int, to device: WLEDDevice, transitionDeciseconds: Int? = nil) async throws -> WLEDState {
        guard presetId > 0 && presetId <= 250 else {
            throw WLEDAPIError.invalidConfiguration
        }

        if let directBody = directPresetApplyBody(
            presetId: presetId,
            device: device,
            transitionDeciseconds: transitionDeciseconds
        ) {
            do {
                let response = try await postState(device, body: directBody)
                #if DEBUG
                logger.debug("preset.apply.direct_pd device=\(device.id, privacy: .public) preset=\(presetId, privacy: .public)")
                #endif
                return response.state
            } catch {
                #if DEBUG
                logger.debug("preset.apply.direct_pd_fallback device=\(device.id, privacy: .public) preset=\(presetId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                #endif
            }
        }

        let stateUpdate = WLEDStateUpdate(
            transitionDeciseconds: transitionDeciseconds,
            ps: presetId,
            lor: 0
        )
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
                  intensity: Int? = nil, palette: Int? = nil, custom1: Int? = nil, custom2: Int? = nil, custom3: Int? = nil,
                  option1: Bool? = nil, option2: Bool? = nil, option3: Bool? = nil, colors: [[Int]]? = nil,
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
            c1: custom1,
            c2: custom2,
            c3: custom3,
            sel: baseSegment?.sel,
            rev: baseSegment?.rev,
            mi: baseSegment?.mi,
            cln: baseSegment?.cln,
            o1: option1,
            o2: option2,
            o3: option3,
            frz: false  // Explicitly unfreeze segment so effects can run
        )
        
        #if DEBUG
        print("[Effects][API] Sending segment update: id=\(segmentId) fx=\(effectId) sx=\(speed ?? -1) ix=\(intensity ?? -1) pal=\(palette ?? -1) c1=\(custom1 ?? -1) c2=\(custom2 ?? -1) c3=\(custom3 ?? -1) o1=\(option1?.description ?? "nil") o2=\(option2?.description ?? "nil") o3=\(option3?.description ?? "nil") on=\(turnOn?.description ?? "nil") colors=\(colors?.description ?? "nil")")
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
    ///   - transitionDeciseconds: Optional transition time (tt, deciseconds)
    /// - Returns: Dictionary mapping device IDs to their updated states
    /// - Throws: WLEDAPIError for any device that fails
    func applyBatchPreset(_ presetId: Int, to devices: [WLEDDevice], transitionDeciseconds: Int? = nil) async throws -> [String: WLEDState] {
        return try await withThrowingTaskGroup(of: (String, WLEDState).self, returning: [String: WLEDState].self) { group in
            for device in devices {
                group.addTask {
                    let updatedState = try await self.applyPreset(presetId, to: device, transitionDeciseconds: transitionDeciseconds)
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
            .compactMap { update -> (deviceId: String, state: WLEDState)? in
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
            .compactMap { update -> (deviceId: String, state: WLEDState)? in
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
        let dictionary = try parseJSONObjectDictionary(from: data)
        let payload = dictionary["presets"] as? [String: Any] ?? dictionary
        var presets: [WLEDPreset] = []
        for (key, value) in payload {
            guard let id = Int(key),
                  (1...250).contains(id),
                  let presetDict = value as? [String: Any] else { continue }
            let name = presetDict["n"] as? String ?? "Preset \(id)"
            let quickLoad = decodeQuickLoadTag(presetDict["ql"])
            let segment = parsePresetSegment(from: presetDict["seg"])
            let stateUpdate = decodeStateUpdate(from: presetDict["win"] as? [String: Any])
            presets.append(
                WLEDPreset(
                    id: id,
                    name: name,
                    quickLoad: quickLoad,
                    segment: segment,
                    state: stateUpdate
                )
            )
        }
        return presets.sorted { $0.id < $1.id }
    }

    private func parsePlaylists(from data: Data) throws -> [WLEDPlaylist] {
        let dictionary = try parseJSONObjectDictionary(from: data)
        let payload = dictionary["playlists"] as? [String: Any]
            ?? dictionary["playlist"] as? [String: Any]
            ?? dictionary
        var playlists: [WLEDPlaylist] = []
        for (key, value) in payload {
            guard let id = Int(key),
                  (1...250).contains(id),
                  let playlistDict = value as? [String: Any] else { continue }
            let name = playlistDict["n"] as? String ?? "Playlist \(id)"
            let presets = decodeIntArray(playlistDict["ps"])
            let durations = decodeIntArray(playlistDict["dur"])
            let transitions = decodeIntArray(playlistDict["transition"])
            let repeatCount = decodeInt(playlistDict["repeat"])
            let endPresetId = decodeInt(playlistDict["end"])
            let shuffle = decodeInt(playlistDict["r"])
            if presets.contains(where: { !(1...250).contains($0) }) {
                continue
            }
            playlists.append(
                WLEDPlaylist(
                    id: id,
                    name: name,
                    presets: presets,
                    duration: durations,
                    transition: transitions,
                    repeat: repeatCount,
                    endPresetId: endPresetId,
                    shuffle: shuffle
                )
            )
        }
        return playlists.sorted { $0.id < $1.id }
    }

    private func parsePlaylistsFromPresets(data: Data) throws -> [WLEDPlaylist] {
        let root = try parseJSONObjectDictionary(from: data)
        let dictionary = root["presets"] as? [String: Any] ?? root
        var playlists: [WLEDPlaylist] = []
        for (key, value) in dictionary {
            guard let id = Int(key),
                  (1...250).contains(id),
                  let presetDict = value as? [String: Any] else { continue }
            guard let playlistDict = presetDict["playlist"] as? [String: Any] else { continue }
            let name = presetDict["n"] as? String ?? "Playlist \(id)"
            let presets = decodeIntArray(playlistDict["ps"])
            let durations = decodeIntArray(playlistDict["dur"])
            let transitions = decodeIntArray(playlistDict["transition"])
            let repeatCount = decodeInt(playlistDict["repeat"])
            let endPresetId = decodeInt(playlistDict["end"])
            let shuffle = decodeInt(playlistDict["r"])
            if presets.contains(where: { !(1...250).contains($0) }) {
                continue
            }
            playlists.append(
                WLEDPlaylist(
                    id: id,
                    name: name,
                    presets: presets,
                    duration: durations,
                    transition: transitions,
                    repeat: repeatCount,
                    endPresetId: endPresetId,
                    shuffle: shuffle
                )
            )
        }
        return playlists.sorted { $0.id < $1.id }
    }

    func parsePlaylistsFromPresetsPayloadForTesting(_ data: Data) throws -> [WLEDPlaylist] {
        try parsePlaylistsFromPresets(data: data)
    }

    func parsePlaylistsPayloadForTesting(_ data: Data) throws -> [WLEDPlaylist] {
        try parsePlaylists(from: data)
    }

    func parsePresetsPayloadForTesting(_ data: Data) throws -> [WLEDPreset] {
        try parsePresets(from: data)
    }

    private func decodeStateUpdate(from dict: [String: Any]?) -> WLEDStateUpdate? {
        guard let dict, JSONSerialization.isValidJSONObject(dict) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return nil }
        return try? decoder.decode(WLEDStateUpdate.self, from: data)
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

    private func decodeDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let floatValue = value as? Float { return Double(floatValue) }
        if let intValue = value as? Int { return Double(intValue) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func decodeString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func decodeQuickLoadTag(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let boolValue = value as? Bool {
            return boolValue ? "1" : nil
        }
        if let intValue = value as? Int {
            return intValue == 0 ? nil : String(intValue)
        }
        if let number = value as? NSNumber {
            return number.intValue == 0 ? nil : String(number.intValue)
        }
        return nil
    }

    private func decodeBool(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool { return boolValue }
        if let intValue = value as? Int { return intValue != 0 }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let string = value as? String, let intValue = Int(string) { return intValue != 0 }
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
        cachePresetRecordPayloads(from: data, device: device)
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
        cachePresetRecordPayloads(from: data, device: device)
        return try parsePlaylistsFromPresets(data: data)
    }

    private func fetchPresetsFromJsonEndpoint(device: WLEDDevice) async throws -> [WLEDPreset] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/presets") else {
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
        cachePresetRecordPayloads(from: data, device: device)
        return try parsePresets(from: data)
    }

    private func fetchPlaylistsFromJsonEndpoint(device: WLEDDevice) async throws -> [WLEDPlaylist] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/presets") else {
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
        cachePresetRecordPayloads(from: data, device: device)
        return try parsePlaylistsFromPresets(data: data)
    }

    private func fetchPresetRecordPayload(id: Int, device: WLEDDevice) async throws -> [String: Any] {
        if let cached = cachedPresetRecordPayload(id: id, device: device) {
            return cached
        }

        do {
            guard let fileURL = URL(string: "http://\(device.ipAddress)/presets.json") else {
                throw WLEDAPIError.invalidURL
            }
            let (data, response) = try await urlSession.data(for: URLRequest(url: fileURL))
            try validateHTTPResponse(response, device: device)
            cachePresetRecordPayloads(from: data, device: device)
            if let payload = try parsePresetPayloadMap(data: data, id: id) {
                return payload
            }
        } catch {
            // Fall back to /json/presets below.
        }

        guard let jsonURL = URL(string: "http://\(device.ipAddress)/json/presets") else {
            throw WLEDAPIError.invalidURL
        }
        let (jsonData, jsonResponse) = try await urlSession.data(for: URLRequest(url: jsonURL))
        try validateHTTPResponse(jsonResponse, device: device)
        cachePresetRecordPayloads(from: jsonData, device: device)
        if let payload = try parsePresetPayloadMap(data: jsonData, id: id) {
            return payload
        }
        throw WLEDAPIError.invalidResponse
    }

    private func directPresetApplyBody(
        presetId: Int,
        device: WLEDDevice,
        transitionDeciseconds: Int?
    ) -> [String: Any]? {
        guard var payload = cachedPresetRecordPayload(id: presetId, device: device) else {
            return nil
        }
        guard payload["playlist"] == nil else {
            return nil
        }
        payload.removeValue(forKey: "n")
        payload.removeValue(forKey: "ql")
        payload["pd"] = presetId
        payload["lor"] = 0
        if let transitionDeciseconds {
            payload["tt"] = min(max(0, transitionDeciseconds), maxWLEDTransitionDeciseconds)
        }
        return payload
    }

    private func cachePresetRecordPayloads(from data: Data, device: WLEDDevice) {
        guard let records = try? parsePresetPayloadMapById(data: data), !records.isEmpty else {
            return
        }
        let storeKey = presetStoreQueueKey(for: device)
        presetRecordPayloadCacheByStoreKey[storeKey] = (records: records, timestamp: Date())
    }

    private func cachedPresetRecordPayload(id: Int, device: WLEDDevice) -> [String: Any]? {
        let storeKey = presetStoreQueueKey(for: device)
        guard let cached = presetRecordPayloadCacheByStoreKey[storeKey] else {
            return nil
        }
        guard Date().timeIntervalSince(cached.timestamp) <= presetRecordPayloadCacheTTL else {
            presetRecordPayloadCacheByStoreKey.removeValue(forKey: storeKey)
            return nil
        }
        return cached.records[id]
    }

    private func parsePresetPayloadMapById(data: Data) throws -> [Int: [String: Any]] {
        let dictionary = try parseJSONObjectDictionary(from: data)
        let payload = dictionary["presets"] as? [String: Any] ?? dictionary
        var parsed: [Int: [String: Any]] = [:]
        for (key, value) in payload {
            guard let id = Int(key),
                  (1...250).contains(id),
                  let record = value as? [String: Any] else {
                continue
            }
            parsed[id] = sanitizedPresetRecord(record)
        }
        return parsed
    }

    private func sanitizedPresetRecord(_ record: [String: Any]) -> [String: Any] {
        var sanitized = record
        sanitized.removeValue(forKey: "psave")
        sanitized.removeValue(forKey: "pdel")
        sanitized.removeValue(forKey: "v")
        sanitized.removeValue(forKey: "time")
        sanitized.removeValue(forKey: "error")
        sanitized.removeValue(forKey: "rb")
        return sanitized
    }

    private func parsePresetPayloadMap(data: Data, id: Int) throws -> [String: Any]? {
        let payloadById = try parsePresetPayloadMapById(data: data)
        return payloadById[id]
    }
    
    private func parseResponse(data: Data, device: WLEDDevice) throws -> WLEDResponse {
        // Handle empty data by creating a default success response
        guard !data.isEmpty else {
            return createSuccessResponse(for: device)
        }

        if let errorCode = wledErrorCode(from: data) {
            if errorCode == 4 {
                throw WLEDAPIError.httpError(501)
            }
            throw WLEDAPIError.invalidResponse
        }
        
        // First, try to decode the simple `{"success":true}` response
        if let successResponse = try? decoder.decode(WLEDSuccessResponse.self, from: data) {
            if successResponse.success {
                return createSuccessResponse(for: device)
            }
            throw WLEDAPIError.invalidResponse
        }
        
        // If that fails, try to decode the full WLEDResponse
        do {
            return try decoder.decode(WLEDResponse.self, from: data)
        } catch {
            // WLED preset/playlist save endpoints often return lightweight ack objects
            // that don't include full `info` + `state`. Treat those as successful writes.
            if let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let dictionary = json as? [String: Any] {
                let hasFullStatePayload = dictionary["info"] != nil || dictionary["state"] != nil
                if !hasFullStatePayload {
                    return createSuccessResponse(for: device)
                }
            }
            #if DEBUG
            print("Failed to decode WLED response: \(String(data: data, encoding: .utf8) ?? "invalid UTF-8")")
            #endif
            throw WLEDAPIError.decodingError(error)
        }
    }

    #if DEBUG
    func debugParseResponseForTests(data: Data, device: WLEDDevice) throws -> WLEDResponse {
        try parseResponse(data: data, device: device)
    }

    func debugValidatedPlaylistRequestForTests(_ request: WLEDPlaylistSaveRequest) throws -> WLEDPlaylistSaveRequest {
        try validatedPlaylistRequest(request)
    }

    func debugPlaylistStepPlanForTests(durationSeconds: Double) -> (steps: Int, durations: [Int], transitions: [Int], effectiveDurationSeconds: Double) {
        let plan = playlistStepPlan(for: durationSeconds, timingUnit: .deciseconds)
        return (plan.steps, plan.durations, plan.transitions, plan.effectiveDurationSeconds)
    }
    #endif
    
    private func createSuccessResponse(for device: WLEDDevice) -> WLEDResponse {
        return WLEDResponse(
            info: Info(
                name: device.name,
                mac: device.id,
                ver: "0.15.3",
                leds: LedInfo(count: 30, seglc: nil, lc: nil, cct: nil, rgbw: nil, wv: nil, matrix: nil),
                fs: nil
            ),
            state: WLEDState(
                brightness: device.brightness,
                isOn: device.isOn,
                segments: [],
                transitionDeciseconds: nil,
                presetId: nil,
                playlistId: nil,
                mainSegment: nil
            )
        )
    }
    
    private func handleError(_ error: Error, device: WLEDDevice) -> WLEDAPIError {
        if let apiError = error as? WLEDAPIError {
            return apiError
        }

        if error is DecodingError || isJSONSerializationError(error) {
            return .decodingError(error)
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

    private func parseJSONObjectDictionary(from data: Data) throws -> [String: Any] {
        try parseJSONObjectDictionaryResilient(from: data)
    }

    private func parseJSONObjectDictionaryResilient(from data: Data) throws -> [String: Any] {
        do {
            let sanitized = sanitizePresetPayloadBytes(data)
            let json = try JSONSerialization.jsonObject(with: sanitized, options: [])
            return json as? [String: Any] ?? [:]
        } catch {
            let sanitized = sanitizePresetPayloadBytes(data)
            if let extracted = extractFirstJSONObjectPayload(sanitized),
               let json = try? JSONSerialization.jsonObject(with: extracted, options: []),
               let dictionary = json as? [String: Any] {
                #if DEBUG
                print("⚠️ preset_payload.recovered_tail_garbage bytes=\(max(0, sanitized.count - extracted.count))")
                #endif
                return dictionary
            }
            let permissive = sanitizePresetPayloadBytesPermissive(sanitized)
            if permissive.replacedByteCount > 0 {
                if let json = try? JSONSerialization.jsonObject(with: permissive.data, options: []),
                   let dictionary = json as? [String: Any] {
                    #if DEBUG
                    print("⚠️ preset_payload.recovered_invalid_whitespace_bytes count=\(permissive.replacedByteCount)")
                    #endif
                    return dictionary
                }
                if let extracted = extractFirstJSONObjectPayload(permissive.data),
                   let json = try? JSONSerialization.jsonObject(with: extracted, options: []),
                   let dictionary = json as? [String: Any] {
                    #if DEBUG
                    print("⚠️ preset_payload.recovered_invalid_whitespace_bytes count=\(permissive.replacedByteCount)")
                    print("⚠️ preset_payload.recovered_tail_garbage bytes=\(max(0, permissive.data.count - extracted.count))")
                    #endif
                    return dictionary
                }
            }
            let strict = sanitizePresetPayloadBytesStrictOutsideStrings(permissive.data)
            if strict.replacedByteCount > 0 {
                if let json = try? JSONSerialization.jsonObject(with: strict.data, options: []),
                   let dictionary = json as? [String: Any] {
                    #if DEBUG
                    print("⚠️ preset_payload.recovered_invalid_json_tokens count=\(strict.replacedByteCount)")
                    #endif
                    return dictionary
                }
                if let extracted = extractFirstJSONObjectPayload(strict.data),
                   let json = try? JSONSerialization.jsonObject(with: extracted, options: []),
                   let dictionary = json as? [String: Any] {
                    #if DEBUG
                    print("⚠️ preset_payload.recovered_invalid_json_tokens count=\(strict.replacedByteCount)")
                    print("⚠️ preset_payload.recovered_tail_garbage bytes=\(max(0, strict.data.count - extracted.count))")
                    #endif
                    return dictionary
                }
            }
            let lossyUTF8 = normalizePresetPayloadBytesLossyUTF8(strict.data)
            if lossyUTF8.wasModified {
                let lossyStrict = sanitizePresetPayloadBytesStrictOutsideStrings(lossyUTF8.data)
                if let json = try? JSONSerialization.jsonObject(with: lossyStrict.data, options: []),
                   let dictionary = json as? [String: Any] {
                    #if DEBUG
                    print("⚠️ preset_payload.recovered_lossy_utf8 bytes_modified=\(lossyUTF8.modifiedByteCount) strict_replaced=\(lossyStrict.replacedByteCount)")
                    #endif
                    return dictionary
                }
                if let extracted = extractFirstJSONObjectPayload(lossyStrict.data),
                   let json = try? JSONSerialization.jsonObject(with: extracted, options: []),
                   let dictionary = json as? [String: Any] {
                    #if DEBUG
                    print("⚠️ preset_payload.recovered_lossy_utf8 bytes_modified=\(lossyUTF8.modifiedByteCount) strict_replaced=\(lossyStrict.replacedByteCount)")
                    print("⚠️ preset_payload.recovered_tail_garbage bytes=\(max(0, lossyStrict.data.count - extracted.count))")
                    #endif
                    return dictionary
                }
            }
            throw wrappedPresetPayloadError(error)
        }
    }

    private func sanitizePresetPayloadBytes(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes.removeFirst(3)
        }
        bytes.removeAll { $0 == 0x00 }
        while let last = bytes.last, last == 0x20 || last == 0x09 || last == 0x0A || last == 0x0D {
            bytes.removeLast()
        }
        return Data(bytes)
    }

    private func sanitizePresetPayloadBytesPermissive(_ data: Data) -> (data: Data, replacedByteCount: Int) {
        var bytes = [UInt8](data)
        var inString = false
        var escaping = false
        var replaced = 0

        for idx in bytes.indices {
            let byte = bytes[idx]
            if inString {
                if escaping {
                    escaping = false
                    continue
                }
                if byte == 0x5C { // \
                    escaping = true
                    continue
                }
                if byte == 0x22 { // "
                    inString = false
                }
                continue
            }

            if byte == 0x22 { // "
                inString = true
                continue
            }

            // Outside strings, replace clearly invalid bytes/control chars with spaces.
            let isAsciiWhitespace = byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
            let isPrintableASCII = (0x20...0x7E).contains(byte)
            let isAllowedControl = isAsciiWhitespace
            if !isPrintableASCII && !isAllowedControl {
                bytes[idx] = 0x20
                replaced += 1
                continue
            }
            if byte < 0x20 && !isAllowedControl {
                bytes[idx] = 0x20
                replaced += 1
            }
        }

        return (Data(bytes), replaced)
    }

    private func sanitizePresetPayloadBytesStrictOutsideStrings(_ data: Data) -> (data: Data, replacedByteCount: Int) {
        var bytes = [UInt8](data)
        var inString = false
        var escaping = false
        var replaced = 0
        let allowedOutsideStringBytes: Set<UInt8> = Set([
            0x20, 0x09, 0x0A, 0x0D, // whitespace
            0x7B, 0x7D, // { }
            0x5B, 0x5D, // [ ]
            0x3A, 0x2C, // : ,
            0x2D, 0x2B, 0x2E, // - + .
            0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, // 0...9
            0x45, 0x65, // E e
            0x74, 0x72, 0x75, 0x65, // t r u e
            0x66, 0x61, 0x6C, 0x73, // f a l s
            0x6E, // n
            0x22, 0x5C // " \
        ])

        for idx in bytes.indices {
            let byte = bytes[idx]
            if inString {
                if escaping {
                    escaping = false
                    continue
                }
                if byte == 0x5C { // \
                    escaping = true
                    continue
                }
                if byte == 0x22 { // "
                    inString = false
                }
                continue
            }

            if byte == 0x22 { // "
                inString = true
                continue
            }

            if !allowedOutsideStringBytes.contains(byte) {
                bytes[idx] = 0x20
                replaced += 1
            }
        }

        return (Data(bytes), replaced)
    }

    private func normalizePresetPayloadBytesLossyUTF8(_ data: Data) -> (data: Data, wasModified: Bool, modifiedByteCount: Int) {
        let decoded = String(decoding: data, as: UTF8.self)
        let encoded = Data(decoded.utf8)
        if encoded == data {
            return (data, false, 0)
        }
        let sharedCount = min(encoded.count, data.count)
        var byteDiffs = abs(encoded.count - data.count)
        if sharedCount > 0 {
            byteDiffs += zip(encoded.prefix(sharedCount), data.prefix(sharedCount)).reduce(0) { partial, pair in
                partial + (pair.0 == pair.1 ? 0 : 1)
            }
        }
        return (encoded, true, byteDiffs)
    }

    private func extractFirstJSONObjectPayload(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let start = bytes.firstIndex(of: 0x7B) else { return nil } // {
        var depth = 0
        var inString = false
        var escaping = false
        for idx in start..<bytes.count {
            let byte = bytes[idx]
            if inString {
                if escaping {
                    escaping = false
                    continue
                }
                if byte == 0x5C { // \
                    escaping = true
                    continue
                }
                if byte == 0x22 { // "
                    inString = false
                }
                continue
            }
            if byte == 0x22 { // "
                inString = true
                continue
            }
            if byte == 0x7B { // {
                depth += 1
            } else if byte == 0x7D { // }
                depth -= 1
                if depth == 0 {
                    return Data(bytes[start...idx])
                }
            }
        }
        return nil
    }

    private func wrappedPresetPayloadError(_ error: Error) -> WLEDAPIError {
        if let apiError = error as? WLEDAPIError {
            return apiError
        }
        if error is DecodingError || isJSONSerializationError(error) {
            return .decodingError(error)
        }
        return .invalidResponse
    }

    private func normalizePresetPayloadError(_ error: Error, device: WLEDDevice) -> WLEDAPIError {
        if let apiError = error as? WLEDAPIError {
            return apiError
        }
        if error is DecodingError || isJSONSerializationError(error) {
            return .decodingError(error)
        }
        return handleError(error, device: device)
    }

    private func shouldRetryPresetPayloadRead(after error: WLEDAPIError) -> Bool {
        switch error {
        case .decodingError, .invalidResponse, .deviceBusy:
            return true
        case .httpError(let statusCode):
            return statusCode == 503
        default:
            return false
        }
    }

    private func shouldAttemptPresetJsonFallback(after error: WLEDAPIError) -> Bool {
        switch error {
        case .decodingError, .invalidResponse:
            return true
        case .httpError(let statusCode):
            return statusCode >= 500
        case .timeout, .networkError, .deviceBusy:
            return true
        case .deviceOffline, .deviceUnreachable:
            return false
        default:
            return false
        }
    }

    private func isJSONSerializationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else {
            return false
        }
        return nsError.code == 3840 || nsError.code == 4864 || nsError.code == 4865
    }

    // MARK: - Internal helpers
    private func segmentedPresetState(
        device: WLEDDevice,
        gradient: LEDGradient,
        brightness: Int,
        on: Bool,
        temperature: Double?,
        whiteLevel: Double?,
        includeSegmentBounds: Bool = true
    ) -> WLEDStateUpdate {
        let maxStop = device.state?.segments.compactMap { $0.stop }.max().map { max(1, $0) }
        let sumLen = device.state?.segments.compactMap { $0.len }.reduce(0, +)
        let totalLEDs: Int?
        if let maxStop, maxStop > 0 {
            totalLEDs = maxStop
        } else if let sumLen, sumLen > 0 {
            totalLEDs = sumLen
        } else {
            totalLEDs = nil
        }
        let segmentCount: Int
        if let totalLEDs {
            segmentCount = max(1, min(min(totalLEDs, maxPresetSegmentCount), defaultPresetSegmentCount))
        } else {
            let existingCount = device.state?.segments.count ?? defaultPresetSegmentCount
            segmentCount = max(1, min(existingCount, maxPresetSegmentCount))
        }
        let stops = presetSegmentStops(totalLEDs: totalLEDs ?? segmentCount, segmentCount: segmentCount)
        let colors = presetSegmentColors(for: gradient, count: segmentCount)
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == sortedStops.first?.hexColor }
        let cctValue = isSolidColor ? temperature.map { Int(round($0 * 255.0)) } : nil
        let whiteValue = whiteLevel.map { Int(round(max(0.0, min(1.0, $0)) * 255.0)) }
        let useCCTOnly = isSolidColor && cctValue != nil && whiteValue == nil
        let includeBounds = includeSegmentBounds && totalLEDs != nil

        var updates: [SegmentUpdate] = []
        for (idx, range) in stops.enumerated() {
            let baseSegment = device.state?.segments.first(where: { $0.id == idx })
                ?? (device.state?.segments.indices.contains(idx) == true ? device.state?.segments[idx] : nil)
            let rgb = colors[idx]
            let col: [[Int]]?
            if useCCTOnly {
                col = nil
            } else if let whiteValue {
                col = [[rgb[0], rgb[1], rgb[2], whiteValue]]
            } else {
                col = [[rgb[0], rgb[1], rgb[2], 0]]
            }
            updates.append(
                SegmentUpdate(
                    id: idx,
                    start: includeBounds ? range.start : nil,
                    stop: includeBounds ? range.stop : nil,
                    grp: baseSegment?.grp ?? 1,
                    spc: baseSegment?.spc ?? 0,
                    ofs: baseSegment?.ofs ?? 0,
                    on: on,
                    bri: baseSegment?.bri ?? 255,
                    col: col,
                    cct: useCCTOnly ? cctValue : (baseSegment?.cct ?? 127),
                    fx: 0,
                    sx: baseSegment?.sx ?? 128,
                    ix: baseSegment?.ix ?? 128,
                    pal: 0,
                    c1: baseSegment?.c1 ?? 128,
                    c2: baseSegment?.c2 ?? 128,
                    c3: baseSegment?.c3 ?? 16,
                    sel: baseSegment?.sel ?? true,
                    rev: baseSegment?.rev ?? false,
                    mi: baseSegment?.mi ?? false,
                    cln: baseSegment?.cln,
                    o1: baseSegment?.o1 ?? false,
                    o2: baseSegment?.o2 ?? false,
                    o3: baseSegment?.o3 ?? false,
                    si: baseSegment?.si ?? 0,
                    m12: baseSegment?.m12 ?? 0,
                    setId: baseSegment?.setId ?? 0,
                    name: baseSegment?.name ?? "",
                    frz: baseSegment?.frz ?? false
                )
            )
        }

        return WLEDStateUpdate(
            on: on,
            bri: brightness,
            seg: updates,
            mainSegment: device.state?.mainSegment
        )
    }

    private enum PlaylistTimingUnit: String {
        case deciseconds
    }

    private struct PlaylistStepPlan {
        let steps: Int
        let durations: [Int]
        let transitions: [Int]
        let effectiveDurationSeconds: Double
    }

    private func playlistTimingUnit(for device: WLEDDevice) -> PlaylistTimingUnit {
        let key = "playlistTimingUnit.\(device.id)"
        if let stored = UserDefaults.standard.string(forKey: key),
           let unit = PlaylistTimingUnit(rawValue: stored),
           unit == .deciseconds {
            return unit
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return .deciseconds
    }

    private func playlistStepPlan(for durationSeconds: Double) -> PlaylistStepPlan {
        playlistStepPlan(for: durationSeconds, timingUnit: .deciseconds)
    }

    private func playlistStepPlan(
        for durationSeconds: Double,
        timingUnit: PlaylistTimingUnit
    ) -> PlaylistStepPlan {
        let clampedDuration = min(maxWLEDPlaylistDurationSeconds, max(0.0, durationSeconds))
        if clampedDuration == 0 {
            return PlaylistStepPlan(steps: 1, durations: [0], transitions: [0], effectiveDurationSeconds: 0)
        }

        let unitScale: Double
        switch timingUnit {
        case .deciseconds:
            unitScale = 10.0
        }

        let requestedUnits = max(1, Int(round(clampedDuration * unitScale)))
        let targetStepUnits = max(1, Int(round(maxWLEDPlaylistTransitionSeconds * unitScale)))
        var legs = max(1, Int(ceil(Double(requestedUnits) / Double(targetStepUnits))))
        legs = min(maxWLEDPlaylistEntries - 1, legs)

        var steps = min(maxWLEDPlaylistEntries, legs + 1)
        steps = min(steps, requestedUnits)

        let baseDurationUnits = max(1, requestedUnits / steps)
        let durationRemainder = max(0, requestedUnits % steps)
        var durations = Array(repeating: baseDurationUnits, count: steps)
        if durationRemainder > 0 {
            for idx in 0..<durationRemainder {
                durations[idx] += 1
            }
        }

        let transitions = durations.map { durationUnits in
            durationUnits > 0 ? min(maxWLEDPlaylistTransitionDeciseconds, durationUnits) : 0
        }
        let effectiveDurationSeconds = Double(durations.reduce(0, +)) / unitScale
        return PlaylistStepPlan(
            steps: steps,
            durations: durations,
            transitions: transitions,
            effectiveDurationSeconds: effectiveDurationSeconds
        )
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
        let denom = Double(max(1, count - 1))
        return (0..<count).map { idx in
            let t = count == 1 ? 0.5 : (Double(idx) / denom)
            let color = GradientSampler.sampleColor(at: t, stops: sortedStops, interpolation: gradient.interpolation)
            return color.toRGBArray()
        }
    }

    private func savePresetViaState(_ request: WLEDPresetSaveRequest, device: WLEDDevice) async throws {
        let includeBrightness = request.includeBrightness ?? true
        let saveBounds = request.saveSegmentBounds ?? true
        let selectedOnly = request.selectedSegmentsOnly ?? false
        let presetName = sanitizedPresetName(request.name, fallback: "Preset \(request.id)")
        let customCommand = request.customAPICommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let customCommand, !customCommand.isEmpty {
            var body: [String: Any] = [
                "psave": request.id,
                "n": presetName,
                "o": true
            ]
            if let quickLoad = request.quickLoad {
                body["ql"] = quickLoad
            }
            if request.applyAtBoot == true {
                body["bootps"] = request.id
            }
            if let data = customCommand.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let jsonDict = jsonObject as? [String: Any] {
                for (key, value) in jsonDict {
                    body[key] = value
                }
            } else {
                body["win"] = customCommand
            }
            _ = try await postState(device, body: body)
            return
        }
        var body: [String: Any] = [
            "psave": request.id,
            "n": presetName,
            "ib": includeBrightness,
            "sb": saveBounds,
            "sc": selectedOnly
        ]
        if request.applyAtBoot == true {
            body["bootps"] = request.id
        }
        if request.saveOnly == true {
            body["o"] = true
        }
        if let transition = request.transitionDeciseconds {
            body["transition"] = transition
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
        if presetName.hasPrefix("Auto Step ") || presetName.hasPrefix("Automation Step ") {
            let ttPresent = body["tt"] != nil
            assert(!ttPresent, "Generated transition step presets must not include tt; playlist.transition[] drives timing.")
            print("🔎 Generated step preset timing for \(device.name): source=playlist.transition[] preset.transition_ignored_if_playlist_active=true tt_present=\(ttPresent)")
        }
        #endif
        _ = try await postState(device, body: body)
    }

    private func savePlaylistViaState(_ request: WLEDPlaylistSaveRequest, device: WLEDDevice) async throws {
        let playlistName = sanitizedPresetName(request.name, fallback: "Playlist \(request.id)")
        let playlist = playlistPayload(from: request)
        let body: [String: Any] = [
            "psave": request.id,
            "n": playlistName,
            "playlist": playlist,
            "o": true
        ]
        #if DEBUG
        let keys = body.keys.sorted().joined(separator: ",")
        print("🔎 Playlist psave request for \(device.name): id=\(request.id) keys=[\(keys)]")
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("🔎 Playlist psave JSON for \(device.name):")
            print(jsonString)
        }
        #endif
        _ = try await postState(device, body: body)
    }

    private func playlistPayload(from request: WLEDPlaylistSaveRequest) -> [String: Any] {
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
        if let shuffle = request.shuffle {
            playlist["r"] = shuffle
        }
        return playlist
    }

    private func validatedPlaylistRequest(_ request: WLEDPlaylistSaveRequest) throws -> WLEDPlaylistSaveRequest {
        guard (1...250).contains(request.id) else {
            throw WLEDAPIError.invalidConfiguration
        }
        guard !request.ps.isEmpty,
              request.ps.count <= maxWLEDPlaylistEntries,
              request.ps.allSatisfy({ (1...250).contains($0) }) else {
            throw WLEDAPIError.invalidConfiguration
        }

        let stepCount = request.ps.count
        let durations = normalizedPlaylistTimingArray(
            request.dur,
            count: stepCount,
            fallback: 100,
            range: 0...65530
        )
        let transitions = normalizedPlaylistTimingArray(
            request.transition,
            count: stepCount,
            fallback: 7,
            range: 0...65530
        )
        let normalizedTransitions = zip(durations, transitions).map { duration, transition in
            guard duration > 0 else { return transition }
            return min(transition, duration)
        }

        let repeatCount: Int?
        if let value = request.repeat {
            guard (0...127).contains(value) else {
                throw WLEDAPIError.invalidConfiguration
            }
            repeatCount = value
        } else {
            repeatCount = nil
        }

        let endPresetId: Int?
        if let value = request.endPresetId {
            guard value == 0 || value == 255 || (1...250).contains(value) else {
                throw WLEDAPIError.invalidConfiguration
            }
            endPresetId = value
        } else {
            endPresetId = nil
        }

        let shuffle: Int?
        if let value = request.shuffle {
            guard value == 0 || value == 1 else {
                throw WLEDAPIError.invalidConfiguration
            }
            shuffle = value
        } else {
            shuffle = nil
        }

        return WLEDPlaylistSaveRequest(
            id: request.id,
            name: request.name,
            ps: request.ps,
            dur: durations,
            transition: normalizedTransitions,
            repeat: repeatCount,
            endPresetId: endPresetId,
            shuffle: shuffle
        )
    }

    private func normalizedPlaylistTimingArray(
        _ values: [Int],
        count: Int,
        fallback: Int,
        range: ClosedRange<Int>
    ) -> [Int] {
        guard count > 0 else { return [] }
        let seed: [Int]
        if values.isEmpty {
            seed = [fallback]
        } else {
            seed = values
        }
        var normalized = Array(seed.prefix(count))
        if normalized.count < count {
            let fillValue = normalized.last ?? fallback
            normalized.append(contentsOf: Array(repeating: fillValue, count: count - normalized.count))
        }
        return normalized.map { min(max($0, range.lowerBound), range.upperBound) }
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

    private func sanitizedPresetName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar) {
                return " "
            }
            return String(scalar)
        }.joined()
        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let result = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : result
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
        
        // Fetch existing config so we preserve user LED preferences (gamma/correction/etc.)
        var configPayload = try await fetchRawConfig(for: device)
        var hw = configPayload["hw"] as? [String: Any] ?? [:]
        var led = hw["led"] as? [String: Any] ?? [:]
        led["total"] = config.ledCount
        led["maxpwr"] = config.maxTotalCurrent
        led["rgbwm"] = config.autoWhiteMode
        led["abl"] = config.enableABL
        hw["led"] = led
        configPayload["hw"] = hw
        
        var leds = configPayload["leds"] as? [[String: Any]] ?? []
        if leds.isEmpty {
            leds = [[:]]
        }
        var first = leds[0]
        first["pin"] = [config.gpioPin]
        first["len"] = config.ledCount
        first["type"] = config.stripType
        first["co"] = config.colorOrder
        first["start"] = config.startLED
        first["skip"] = config.skipFirstLEDs
        first["rev"] = config.reverseDirection
        first["rf"] = config.offRefresh
        first["aw"] = config.autoWhiteMode
        first["la"] = config.maxCurrentPerLED
        first["ma"] = config.maxTotalCurrent
        first["per"] = config.usePerOutputLimiter
        leds[0] = first
        configPayload["leds"] = leds
        _ = enforceColorGammaCorrection(in: &configPayload)
        
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
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WLEDAPIError.invalidResponse
            }

            let hw = json["hw"] as? [String: Any]
            let led = hw?["led"] as? [String: Any] ?? [:]
            let ledIns = led["ins"] as? [[String: Any]] ?? []
            let legacyIns = json["leds"] as? [[String: Any]] ?? []
            let allBuses = !ledIns.isEmpty ? ledIns : legacyIns

            #if DEBUG
            if let ledIns = led["ins"] as? [[String: Any]] {
                print("🔧 [LED cfg] \(device.name) ins count=\(ledIns.count) payload=\(ledIns)")
            } else {
                print("🔧 [LED cfg] \(device.name) ins missing; hw.led=\(led)")
            }
            if let legacyIns = json["leds"] as? [[String: Any]] {
                print("🔧 [LED cfg] \(device.name) legacy leds count=\(legacyIns.count) payload=\(legacyIns)")
            }
            #endif

            let selectedBus: [String: Any]? = {
                guard !allBuses.isEmpty else { return nil }
                return allBuses.sorted { lhs, rhs in
                    let lhsStart = lhs["start"] as? Int ?? Int.max
                    let rhsStart = rhs["start"] as? Int ?? Int.max
                    if lhsStart == rhsStart {
                        let lhsLen = lhs["len"] as? Int ?? 0
                        let rhsLen = rhs["len"] as? Int ?? 0
                        return lhsLen > rhsLen
                    }
                    return lhsStart < rhsStart
                }.first
            }()

            #if DEBUG
            if let selectedBus {
                print("🔧 [LED cfg] \(device.name) selected bus=\(selectedBus)")
            } else {
                print("🔧 [LED cfg] \(device.name) no bus selected")
            }
            #endif
            
            // Extract configuration values with defaults
            let stripType = selectedBus?["type"] as? Int ?? 0
            let colorOrder = (selectedBus?["order"] as? Int)
                ?? (selectedBus?["co"] as? Int)
                ?? 0
            let gpioPin = (selectedBus?["pin"] as? [Int])?.first
                ?? (selectedBus?["pin"] as? Int)
                ?? 16
            let ledCount = selectedBus?["len"] as? Int
                ?? led["total"] as? Int
                ?? 120
            let startLED = selectedBus?["start"] as? Int ?? 0
            let skipFirstLEDs = selectedBus?["skip"] as? Int ?? 0
            let reverseDirection = selectedBus?["rev"] as? Bool ?? false
            let offRefresh = selectedBus?["ref"] as? Bool ?? false
            let autoWhiteMode = selectedBus?["rgbwm"] as? Int
                ?? led["rgbwm"] as? Int
                ?? 0
            let maxCurrentPerLED = selectedBus?["ledma"] as? Int ?? 55
            let maxTotalCurrent = selectedBus?["maxpwr"] as? Int
                ?? led["maxpwr"] as? Int
                ?? 3850
            let usePerOutputLimiter = selectedBus?["per"] as? Bool ?? false
            let enableABL = led["abl"] as? Bool ?? true
            let cctRangeSource = led["cct"] ?? selectedBus?["cct"]
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

    /// Drop cached `/json` state for one device so the next `getState` hits the network.
    func invalidateStateCache(for deviceId: String) {
        bypassCache(for: deviceId)
    }
    
    // MARK: - Advanced Cache Management
    
    /// Bypass cache for a specific device after successful POST operations
    private func bypassCache(for deviceId: String) {
        let cacheKey = "\(deviceId)_state"
        requestCache.removeValue(forKey: cacheKey)
        
        #if DEBUG
        let now = Date()
        let lastLog = lastCacheBypassLogByDevice[deviceId] ?? .distantPast
        if now.timeIntervalSince(lastLog) >= 10 {
            lastCacheBypassLogByDevice[deviceId] = now
            logger.debug("Cache bypassed for device: \(deviceId)")
        }
        #endif
    }

    private func recordSuccessfulRequest(deviceId: String) {
        lastSuccessfulRequestByDevice[deviceId] = Date()
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
    let r: Int?
}

struct WLEDPlaylistSaveRequest: Encodable {
    let id: Int
    let name: String
    let ps: [Int]  // Preset IDs
    let dur: [Int]  // Entry durations in deciseconds (native WLED `dur`)
    let transition: [Int]  // Transition times in deciseconds (native WLED)
    let `repeat`: Int?  // Repeat count (1 = one cycle, 0 = infinite, nil = WLED default)
    let endPresetId: Int?  // Preset to apply at end (optional)
    let shuffle: Int?  // Shuffle entries (0 = off, 1 = on)

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ps
        case dur
        case transition
        case `repeat` = "repeat"
        case endPresetId = "end"
        case shuffle = "r"
    }
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
    let r: Int?
} 
