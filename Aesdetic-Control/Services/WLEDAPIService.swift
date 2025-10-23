//
//  WLEDAPIService.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine
import os.log

// MARK: - API Service Protocol

protocol WLEDAPIServiceProtocol {
    func getState(for device: WLEDDevice) async throws -> WLEDResponse
    func updateState(for device: WLEDDevice, state: WLEDStateUpdate) async throws -> WLEDResponse
    func setPower(for device: WLEDDevice, isOn: Bool) async throws -> WLEDResponse
    func setBrightness(for device: WLEDDevice, brightness: Int) async throws -> WLEDResponse
    func setColor(for device: WLEDDevice, color: [Int]) async throws -> WLEDResponse
    func setSegmentPixels(
        for device: WLEDDevice,
        segmentId: Int?,
        startIndex: Int,
        hexColors: [String],
        afterChunk: (() async -> Void)?
    ) async throws
}

// MARK: - WLEDAPIService

class WLEDAPIService: WLEDAPIServiceProtocol, CleanupCapable {
    static let shared = WLEDAPIService()
    
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "APIService")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - API Methods
    
    func getState(for device: WLEDDevice) async throws -> WLEDResponse {
        guard let url = URL(string: device.jsonEndpoint) else {
            throw WLEDAPIError.invalidURL
        }
        
        let request = URLRequest(url: url)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response, device: device)
            return try parseResponse(data: data, device: device)
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
            request.httpBody = try encoder.encode(state)
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
    
    func setPower(for device: WLEDDevice, isOn: Bool) async throws -> WLEDResponse {
        let stateUpdate = WLEDStateUpdate(on: isOn)
        return try await updateState(for: device, state: stateUpdate)
    }
    
    func setBrightness(for device: WLEDDevice, brightness: Int) async throws -> WLEDResponse {
        let stateUpdate = WLEDStateUpdate(bri: max(0, min(255, brightness)))
        return try await updateState(for: device, state: stateUpdate)
    }
    
    func setColor(for device: WLEDDevice, color: [Int]) async throws -> WLEDResponse {
        guard color.count >= 3 else {
            throw WLEDAPIError.invalidConfiguration
        }
        
        let segment = SegmentUpdate(id: 0, col: [color])
        let stateUpdate = WLEDStateUpdate(seg: [segment])
        return try await updateState(for: device, state: stateUpdate)
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
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the configuration update payload
        let payload: [String: Any] = [
            "id": [
                "mdns": name  // WLED uses "mdns" field for the device name
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WLEDAPIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw WLEDAPIError.httpError(httpResponse.statusCode)
        }
        
        // After config update, fetch the current state to return
        return try await getState(for: device)
    }

    // MARK: - Per-LED Control
    func setSegmentPixels(
        for device: WLEDDevice,
        segmentId: Int? = nil,
        startIndex: Int = 0,
        hexColors: [String],
        afterChunk: (() async -> Void)? = nil
    ) async throws {
        guard !hexColors.isEmpty else { return }
        let bodies = Self.buildSegmentPixelBodies(segmentId: segmentId, startIndex: startIndex, hexColors: hexColors, chunkSize: 256)
        for body in bodies {
            _ = try await postState(device, body: body)
            if let cb = afterChunk { await cb() }
        }
    }

    // Helper to build chunked POST bodies
    internal static func buildSegmentPixelBodies(segmentId: Int?, startIndex: Int, hexColors: [String], chunkSize: Int = 256) -> [[String: Any]] {
        guard !hexColors.isEmpty else { return [] }
        var out: [[String: Any]] = []
        let total = hexColors.count
        var idx = 0
        while idx < total {
            let end = min(idx + chunkSize, total)
            let chunk = Array(hexColors[idx..<end])
            var seg: [String: Any] = ["i": [startIndex + idx] + chunk]
            if let sid = segmentId { seg["id"] = sid }
            let body: [String: Any]
            if segmentId != nil { body = ["seg": [seg]] }
            else { body = ["seg": seg] }
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
        let response: WLEDResponse = try await getState(for: device)
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
                  intensity: Int? = nil, palette: Int? = nil, device: WLEDDevice) async throws -> WLEDState {
        let segment = SegmentUpdate(
            id: segmentId,
            fx: effectId,
            sx: speed,
            ix: intensity,
            pal: palette
        )
        
        let stateUpdate = WLEDStateUpdate(seg: [segment])
        let response = try await updateState(for: device, state: stateUpdate)
        return response.state
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
                leds: LedInfo(count: 30)
            ),
            state: WLEDState(
                brightness: device.brightness,
                isOn: device.isOn,
                segments: []
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
        return try parseResponse(data: data, device: device)
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
            maxCurrentPerLED: currentConfig.maxCurrentPerLED,
            maxTotalCurrent: maxCurrent ?? currentConfig.maxTotalCurrent,
            usePerOutputLimiter: currentConfig.usePerOutputLimiter,
            enableABL: enableABL ?? currentConfig.enableABL
        )
        
        return try await updateLEDConfiguration(updatedConfig, for: device)
    }
    
    // MARK: - Cache Management for ResourceManager
    
    func getCacheSize() -> Int {
        // Return cache size in bytes
        return 0 // Simple implementation
    }
    
    func clearCache() {
        // Clear any cached data
        urlSession.configuration.urlCache?.removeAllCachedResponses()
    }
    
    func cleanup() {
        clearCache()
    }
} 