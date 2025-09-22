//
//  DeviceControlViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine
import SwiftUI
import os.log

@MainActor
class DeviceControlViewModel: ObservableObject {
    static let shared = DeviceControlViewModel()
    
    // MARK: - Device Sorting
    
    enum DeviceSortOption: String, CaseIterable {
        case name = "Name"
        case location = "Location"
        case status = "Status"
        case brightness = "Brightness"
        
        var title: String {
            return self.rawValue
        }
    }
    
    @Published var sortOption: DeviceSortOption = .name
    @Published var locationFilter: DeviceLocation = .all
    @Published var selectedLocationFilter: DeviceLocation = .all
    @Published var webSocketConnectionStatus: WLEDWebSocketManager.ConnectionStatus = .disconnected
    
    // Computed filtered devices based on current filters
    var filteredDevices: [WLEDDevice] {
        var filtered = devices
        
        // Apply location filter
        if selectedLocationFilter != .all {
            filtered = filtered.filter { $0.location == selectedLocationFilter }
        }
        
        // Apply sorting
        switch sortOption {
        case .name:
            filtered = filtered.sorted { $0.name < $1.name }
        case .location:
            filtered = filtered.sorted { $0.location.displayName < $1.location.displayName }
        case .status:
            filtered = filtered.sorted { $0.isOnline && !$1.isOnline }
        case .brightness:
            filtered = filtered.sorted { $0.brightness > $1.brightness }
        }
        
        return filtered
    }
    
    // MARK: - State Management Optimization
    
    @Published var devices: [WLEDDevice] = [] {
        didSet {
            // Only update metrics if devices actually changed
            if devices.count != oldValue.count || 
               !devices.elementsEqual(oldValue, by: { $0.id == $1.id && $0.isOnline == $1.isOnline }) {
                // Update handled by WebSocketManager directly
            }
        }
    }
    @Published var isScanning: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var reconnectionStatus: [String: String] = [:]
    
    // Service dependencies
    private let apiService = WLEDAPIService.shared
    private let colorPipeline = ColorPipeline()
    private lazy var transitionRunner = GradientTransitionRunner(pipeline: colorPipeline)
    let wledService = WLEDDiscoveryService()
    private let coreDataManager = CoreDataManager.shared
    private let webSocketManager = WLEDWebSocketManager.shared
    private let connectionMonitor = WLEDConnectionMonitor.shared
    
    // Combine cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // User interaction tracking for optimistic updates
    private var lastUserInput: [String: Date] = [:]
    private let userInputProtectionWindow: TimeInterval = 1.5
    
    private func isUnderUserControl(_ deviceId: String) -> Bool {
        guard let lastInput = lastUserInput[deviceId] else { return false }
        return Date().timeIntervalSince(lastInput) < userInputProtectionWindow
    }
    
    private func markUserInteraction(_ deviceId: String) {
        lastUserInput[deviceId] = Date()
    }
    
    // Pending toggles tracking (anti-flicker)
    private var pendingToggles: [String: Bool] = [:]
    
    // Add this dictionary to coordinate with UI-level optimistic state
    private var uiToggleStates: [String: Bool] = [:]
    
    // Real-time control state
    @Published var isRealTimeEnabled: Bool = true
    
    // Multi-device batch operations
    @Published var selectedDevices: Set<String> = []
    @Published var isBatchMode: Bool = false
    @Published var batchOperationInProgress: Bool = false
    
    // State change batching for performance
    private var pendingDeviceUpdates: [String: WLEDDevice] = [:]
    private var batchUpdateTimer: Timer?
    private let batchUpdateInterval: TimeInterval = 0.1 // 100ms batching window
    
    // MARK: - UI State Coordination
    
    func registerUIOptimisticState(deviceId: String, state: Bool) {
        uiToggleStates[deviceId] = state
    }
    
    func clearUIOptimisticState(deviceId: String) {
        uiToggleStates.removeValue(forKey: deviceId)
    }

    func getCurrentPowerState(for deviceId: String) -> Bool {
        if let optimisticState = uiToggleStates[deviceId] {
            return optimisticState
        }
        return devices.first { $0.id == deviceId }?.isOn ?? false
    }

    // MARK: - Initialization
    
    private init() {
        setupSubscriptions()
        loadDevicesFromPersistence()
        setupWebSocketSubscriptions()
    }
    
    deinit {
        cancellables.removeAll()
        batchUpdateTimer?.invalidate()
    }
    
    // MARK: - Subscription Setup
    
    private func setupSubscriptions() {
        // Subscribe to discovered devices from WLEDDiscoveryService
        wledService.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discoveredDevices in
                Task {
                    await self?.handleDiscoveredDevices(discoveredDevices)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to scanning status
        wledService.$isScanning
            .receive(on: DispatchQueue.main)
            .assign(to: \.isScanning, on: self)
            .store(in: &cancellables)
    }
    
    private func setupWebSocketSubscriptions() {
        // Subscribe to WebSocket state updates
        webSocketManager.deviceStateUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stateUpdate in
                // Defer state writes to next runloop to avoid re-entrant view updates
                DispatchQueue.main.async { [weak self] in
                    self?.handleWebSocketStateUpdate(stateUpdate)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to connection status changes
        webSocketManager.$connectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.webSocketConnectionStatus, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Batched Device Updates
    
    private func scheduleDeviceUpdate(_ device: WLEDDevice) {
        pendingDeviceUpdates[device.id] = device
        
        // Cancel existing timer and start new one
        batchUpdateTimer?.invalidate()
        batchUpdateTimer = Timer.scheduledTimer(withTimeInterval: batchUpdateInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processBatchedUpdates()
            }
        }
    }
    
    private func processBatchedUpdates() {
        guard !pendingDeviceUpdates.isEmpty else { return }
        
        // Apply all pending updates at once to minimize UI notifications
        var updatedDevices = devices
        var hasChanges = false
        
        for (deviceId, updatedDevice) in pendingDeviceUpdates {
            if let index = updatedDevices.firstIndex(where: { $0.id == deviceId }) {
                // Only update if there are actual changes
                if !devicesAreEqual(updatedDevices[index], updatedDevice) {
                    updatedDevices[index] = updatedDevice
                    hasChanges = true
                }
            }
        }
        
        if hasChanges {
            devices = updatedDevices
        }
        
        pendingDeviceUpdates.removeAll()
        batchUpdateTimer = nil
    }
    
    private func devicesAreEqual(_ device1: WLEDDevice, _ device2: WLEDDevice) -> Bool {
        return device1.id == device2.id &&
               device1.isOn == device2.isOn &&
               device1.brightness == device2.brightness &&
               device1.isOnline == device2.isOnline &&
               device1.name == device2.name &&
               device1.ipAddress == device2.ipAddress &&
               device1.currentColor == device2.currentColor // Simple color comparison
    }
    
    // MARK: - Optimized WebSocket State Updates
    
    private func handleWebSocketStateUpdate(_ stateUpdate: WLEDDeviceStateUpdate) {
        guard let index = devices.firstIndex(where: { $0.id == stateUpdate.deviceId }) else {
            return
        }
        
        // If the UI has an optimistic state for this device, don't let WebSockets override it.
        if uiToggleStates[stateUpdate.deviceId] != nil {
            return
        }

        // Skip update if device is under user control (prevent conflicts)
        if isUnderUserControl(stateUpdate.deviceId) {
            return
        }
        
        // Skip update if currently toggling to prevent flicker
        if pendingToggles[stateUpdate.deviceId] != nil {
            return
        }
        
        var updatedDevice = devices[index]
        var hasSignificantChanges = false
        
        if let state = stateUpdate.state {
            // Check for significant state changes to prevent jitter
            let powerChanged = updatedDevice.isOn != state.isOn
            let brightnessChanged = abs(updatedDevice.brightness - state.brightness) > 15 // Increased threshold to 15
            
            if powerChanged || brightnessChanged {
                hasSignificantChanges = true
                
                updatedDevice.isOn = state.isOn
                updatedDevice.brightness = state.brightness
                updatedDevice.isOnline = true
                updatedDevice.lastSeen = stateUpdate.timestamp
                
                // Update color if available from segments
                if let segment = state.segments.first,
                   let colors = segment.colors,
                   let firstColor = colors.first,
                   firstColor.count >= 3 {
                    updatedDevice.currentColor = Color(
                        red: Double(firstColor[0]) / 255.0,
                        green: Double(firstColor[1]) / 255.0,
                        blue: Double(firstColor[2]) / 255.0
                    )
                }
            }
        }
        
        // Update device info if available (always safe to update)
        if let info = stateUpdate.info {
            if updatedDevice.name != info.name {
                updatedDevice.name = info.name
                hasSignificantChanges = true
            }
        }
        
        // Use batched updates for better performance
        if hasSignificantChanges {
            scheduleDeviceUpdate(updatedDevice)
            
            // Persist the updated state in background
            Task.detached(priority: .background) {
                await CoreDataManager.shared.saveDevice(updatedDevice)
            }
        } else {
            // Just update the last seen timestamp for connection tracking (no UI update needed)
            devices[index].lastSeen = stateUpdate.timestamp
            devices[index].isOnline = true
        }
    }
    
    // MARK: - Multi-Device Batch Operations
    
    func toggleBatchMode() {
        isBatchMode.toggle()
        if !isBatchMode {
            selectedDevices.removeAll()
        }
    }
    
    func selectDevice(_ deviceId: String) {
        guard isBatchMode else { return }
        selectedDevices.insert(deviceId)
    }
    
    func deselectDevice(_ deviceId: String) {
        selectedDevices.remove(deviceId)
    }
    
    func selectAllDevices() {
        guard isBatchMode else { return }
        selectedDevices = Set(filteredDevices.map { $0.id })
    }
    
    func deselectAllDevices() {
        selectedDevices.removeAll()
    }
    
    func batchTogglePower() async {
        await performBatchOperation { device in
            await self.toggleDevicePower(device)
        }
    }
    
    func batchSetBrightness(_ brightness: Int) async {
        await performBatchOperation { device in
            await self.updateDeviceBrightness(device, brightness: brightness)
        }
    }
    
    func batchSetColor(_ color: Color) async {
        await performBatchOperation { device in
            await self.updateDeviceColor(device, color: color)
        }
    }
    
    func batchConnectRealTime() async {
        guard isRealTimeEnabled else { return }
        
        let selectedDeviceList = devices.filter { selectedDevices.contains($0.id) }
        let priorities = Dictionary(uniqueKeysWithValues: selectedDeviceList.enumerated().map { 
            ($0.element.id, $0.offset + 10) // Higher priority for selected devices
        })
        
        await webSocketManager.connectToDevices(selectedDeviceList, priorities: priorities)
    }
    
    func batchDisconnectRealTime() {
        for deviceId in selectedDevices {
            webSocketManager.disconnect(from: deviceId)
        }
    }
    
    private func performBatchOperation(_ operation: @escaping (WLEDDevice) async -> Void) async {
        guard !selectedDevices.isEmpty else { return }
        
        batchOperationInProgress = true
        defer { batchOperationInProgress = false }
        
        let selectedDeviceList = devices.filter { selectedDevices.contains($0.id) }
        
        await withTaskGroup(of: Void.self) { group in
            for device in selectedDeviceList {
                group.addTask {
                    await operation(device)
                }
            }
        }
    }
    
    // MARK: - Enhanced Device Management
    
    func optimizeWebSocketConnections() {
        webSocketManager.optimizeConnections()
    }
    
    func getConnectionStatus(for device: WLEDDevice) -> WLEDWebSocketManager.DeviceConnectionStatus? {
        return webSocketManager.getConnectionStatus(for: device.id)
    }
    
    func connectWithPriority(_ device: WLEDDevice, priority: Int = 0) {
        webSocketManager.connect(to: device, priority: priority)
    }
    
    func refreshDeviceMetrics() {
        // Connection metrics are automatically updated by the WebSocket manager
        // This method can be used to trigger manual updates if needed
    }
    
    // MARK: - Enhanced WebSocket Management
    
    private func connectWebSocketsForAllDevices() {
        guard isRealTimeEnabled else { return }
        
        // Prioritize devices that are currently online and recently used
        let onlineDevices = devices.filter { $0.isOnline }
        let priorities = Dictionary(uniqueKeysWithValues: onlineDevices.enumerated().map { 
            ($0.element.id, $0.offset) 
        })
        
        Task {
            await webSocketManager.connectToDevices(onlineDevices, priorities: priorities)
        }
    }
    
    private func disconnectAllWebSockets() {
        webSocketManager.disconnectAll()
    }
    
    private func connectWebSocketIfNeeded(for device: WLEDDevice) {
        guard isRealTimeEnabled && device.isOnline else { return }
        
        // Check if already connected
        let connectionStatus = webSocketManager.getConnectionStatus(for: device.id)
        if connectionStatus?.status != .connected {
            // Assign higher priority to newly online devices
            let priority = Int(Date().timeIntervalSince1970) % 1000
            webSocketManager.connect(to: device, priority: priority)
        }
    }
    
    private func disconnectWebSocket(for device: WLEDDevice) {
        webSocketManager.disconnect(from: device.id)
    }
    
    // MARK: - Device Management
    
    private func loadDevicesFromPersistence() {
        Task { @MainActor in
            let persistedDevices = await coreDataManager.fetchDevices()
            await MainActor.run {
                self.devices = persistedDevices
                
                // Register persisted devices with connection monitor
                for device in persistedDevices {
                    self.connectionMonitor.registerDevice(device)
                }
                
                // Auto-connect real-time WebSocket for online devices if enabled
                if self.isRealTimeEnabled {
                    let onlineDevices = persistedDevices.filter { $0.isOnline }
                    if !onlineDevices.isEmpty {
                        // Small delay to allow app to fully initialize
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            self.connectWebSocketsForAllDevices()
                        }
                    }
                }
            }
        }
    }
    
    private func handleDiscoveredDevices(_ discoveredDevices: [WLEDDevice]) async {
        for discoveredDevice in discoveredDevices {
            // Check if device already exists
            if let existingIndex = devices.firstIndex(where: { $0.id == discoveredDevice.id }) {
                // Update existing device with any new information
                var updatedDevice = devices[existingIndex]
                updatedDevice.name = discoveredDevice.name
                updatedDevice.ipAddress = discoveredDevice.ipAddress
                updatedDevice.productType = discoveredDevice.productType
                updatedDevice.lastSeen = Date()
                
                devices[existingIndex] = updatedDevice
                await coreDataManager.saveDevice(updatedDevice)
            } else {
                // Add new device
                var newDevice = discoveredDevice
                newDevice.lastSeen = Date()
                devices.append(newDevice)
                await coreDataManager.saveDevice(newDevice)
            }
            
            // Register with connection monitor
            connectionMonitor.registerDevice(discoveredDevice)
            
            // Connect WebSocket if real-time is enabled
            connectWebSocketIfNeeded(for: discoveredDevice)
        }
    }
    
    private func updateDeviceHealthStatus(_ healthStatus: [String: Bool]) {
        for (deviceId, isOnline) in healthStatus {
            if let index = devices.firstIndex(where: { $0.id == deviceId }) {
                devices[index].isOnline = isOnline
            }
        }
    }
    
    // MARK: - Real-Time State Management
    
    // Toggle control for preventing rapid toggles
    private var toggleTimers: [String: Timer] = [:]
    
    // MARK: - Enhanced Device Control
    
    func toggleDevicePower(_ device: WLEDDevice) async {
        // The UI will have already registered the optimistic state.
        // The `targetState` is what the UI *wants* the device to be.
        let targetState = uiToggleStates[device.id] ?? !device.isOn
        
        // Mark interaction and set pending toggle
        markUserInteraction(device.id)
        pendingToggles[device.id] = targetState
        
        // Set a timer to clear the pending state if API call fails/hangs
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pendingToggles.removeValue(forKey: device.id)
                self?.uiToggleStates.removeValue(forKey: device.id)
            }
        }
        toggleTimers[device.id] = timer

        await updateDeviceState(device) { currentDevice in
            var updatedDevice = currentDevice
            updatedDevice.isOn = targetState
            return updatedDevice
        }
        
        // On success, clear the pending state from the timer
        pendingToggles.removeValue(forKey: device.id)
        toggleTimers[device.id]?.invalidate()
        toggleTimers.removeValue(forKey: device.id)
    }
    
    // Execute the actual device toggle with proper error handling
    private func executeDeviceToggle(_ device: WLEDDevice, targetState: Bool) async {
        guard let pendingState = pendingToggles[device.id],
              pendingState == targetState else {
            // State changed since this was queued, ignore
            return
        }
        
        do {
            // Create state update
            let rgb = device.currentColor.toRGBArray()
            let stateUpdate = WLEDStateUpdate(
                on: targetState,
                bri: device.brightness,
                seg: [SegmentUpdate(col: [rgb])]
            )
            
            // Send to device via API
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            
            // Send via WebSocket for faster feedback (if connected)
            if isRealTimeEnabled {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            
            // Success - clear pending state and ensure device stays online
            await MainActor.run {
                pendingToggles.removeValue(forKey: device.id)
                toggleTimers[device.id]?.invalidate()
                toggleTimers.removeValue(forKey: device.id)
                
                // Clear user control window to allow future updates
                lastUserInput.removeValue(forKey: device.id)
                
                // Ensure device reflects the successful toggle
                if let index = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[index].isOn = targetState
                    devices[index].isOnline = true
                    devices[index].lastSeen = Date()
                }
                
                // Force UI update by triggering objectWillChange
                objectWillChange.send()
                
                errorMessage = nil
                
                print("✅ Toggle successful for device \(device.id): \(targetState ? "ON" : "OFF")")
            }
            
            // Persist the change
            var updatedDevice = device
            updatedDevice.isOn = targetState
            updatedDevice.isOnline = true
            updatedDevice.lastSeen = Date()
            await coreDataManager.saveDevice(updatedDevice)
            
        } catch {
            // Handle toggle failure
            await MainActor.run {
                // Revert optimistic state
                if let index = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[index].isOn = !targetState // Revert to original state
                }
                
                // Clear pending toggle and user control window
                pendingToggles.removeValue(forKey: device.id)
                toggleTimers[device.id]?.invalidate()
                toggleTimers.removeValue(forKey: device.id)
                lastUserInput.removeValue(forKey: device.id)
                
                // Force UI update by triggering objectWillChange
                objectWillChange.send()
                
                // Only mark offline for connection errors, not busy/timeout
                if error.localizedDescription.lowercased().contains("connection") || 
                   error.localizedDescription.lowercased().contains("unreachable") {
                    if let index = devices.firstIndex(where: { $0.id == device.id }) {
                        devices[index].isOnline = false
                    }
                    errorMessage = "Connection lost to device: \(device.name)"
                } else {
                    // For other errors (busy, timeout), keep device online
                    print("❌ Toggle failed but keeping device online: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func updateDeviceBrightness(_ device: WLEDDevice, brightness: Int) async {
        markUserInteraction(device.id)
        var intent = ColorIntent(deviceId: device.id, mode: .solid)
        intent.segmentId = 0
        intent.brightness = max(0, min(255, brightness))
        await colorPipeline.apply(intent, to: device)
        // Optimistic local update
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].brightness = brightness
            devices[index].isOnline = true
        }
    }
    
    func updateDeviceColor(_ device: WLEDDevice, color: Color) async {
        // Mark device under user control for color changes too
        markUserInteraction(device.id)
        
        await updateDeviceState(device) { currentDevice in
            var updatedDevice = currentDevice
            updatedDevice.currentColor = color
            return updatedDevice
        }
    }
    
    func setDevicePower(_ device: WLEDDevice, isOn: Bool) async {
        // Respect user interaction protection and perform an optimistic state update via unified path
        markUserInteraction(device.id)
        await updateDeviceState(device) { currentDevice in
            var updatedDevice = currentDevice
            updatedDevice.isOn = isOn
            return updatedDevice
        }
    }

    func setUDPSync(_ device: WLEDDevice, send: Bool?, recv: Bool?) async {
        // Build UDPN update and call API; optimistic no-op on UI
        let udpn = UDPNUpdate(send: send, recv: recv, nn: nil)
        let state = WLEDStateUpdate(udpn: udpn)
        _ = try? await apiService.updateState(for: device, state: state)
    }
    
    private func updateDeviceState(_ device: WLEDDevice, update: (WLEDDevice) -> WLEDDevice) async {
        let updatedDevice = update(device)
        
        do {
            // Create state update based on changes
            let rgb = updatedDevice.currentColor.toRGBArray()
            let stateUpdate = WLEDStateUpdate(
                on: updatedDevice.isOn,
                bri: updatedDevice.brightness,
                seg: [SegmentUpdate(col: [rgb])]
            )
            
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            
            // Send WebSocket update if connected (for faster local feedback)
            if isRealTimeEnabled {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            
            // Update local device list immediately with optimistic update
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    self.devices[index] = updatedDevice
                    self.devices[index].isOnline = true // Ensure device stays online after successful update
                }
                self.errorMessage = nil
            }
            
            // Persist to Core Data
            await coreDataManager.saveDevice(updatedDevice)
            
            // DO NOT call refreshDeviceState here - it causes race conditions with user input
            
        } catch {
            // Log error but don't immediately mark device offline
            // Only mark offline for specific connection errors, not busy/timeout errors
            await MainActor.run {
                // Only show error message, don't mark offline unless it's a connection error
                if error.localizedDescription.lowercased().contains("connection") || 
                   error.localizedDescription.lowercased().contains("network") ||
                   error.localizedDescription.lowercased().contains("unreachable") {
                    self.errorMessage = "Connection lost to device: \(device.name)"
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[index].isOnline = false
                    }
                } else {
                    // For other errors (busy, timeout, etc.), just log but keep device online
                    print("Device update failed (keeping online): \(error.localizedDescription)")
                    // Revert to previous state if needed
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        // Keep the device state as-is instead of marking offline
                        self.devices[index].isOnline = true
                    }
                }
            }
        }
    }
    
    // MARK: - Device Discovery
    
    func startScanning() async {
        wledService.startDiscovery()
    }
    
    func stopScanning() async {
        wledService.stopDiscovery()
    }
    
    func addDeviceByIP(_ ipAddress: String) {
        wledService.addDeviceByIP(ipAddress)
    }
    
    func refreshDevices() async {
        // Coalesce refresh storms with a short TTL window
        if let last = _lastRefreshRequested, Date().timeIntervalSince(last) < 1.5 { return }
        _lastRefreshRequested = Date()
        isLoading = true
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        // Limit concurrency to avoid memory/network pressure
        let limit = 4
        var index = 0
        while index < devices.count {
            await withTaskGroup(of: Void.self) { group in
                for d in devices[index..<min(index+limit, devices.count)] {
                    group.addTask { [weak self] in
                        await self?.refreshDeviceState(d)
                    }
                }
                for await _ in group { }
            }
            index += limit
        }
    }
    
    private func refreshDeviceState(_ device: WLEDDevice) async {
        do {
            let response = try await apiService.getState(for: device)
            
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    var updatedDevice = self.devices[index]
                    updatedDevice.brightness = response.state.brightness
                    updatedDevice.isOn = response.state.isOn
                    updatedDevice.isOnline = true
                    updatedDevice.lastSeen = Date()
                    
                    // Update color if available
                    if let segment = response.state.segments.first,
                       let colors = segment.colors,
                       let firstColor = colors.first,
                       firstColor.count >= 3 {
                        updatedDevice.currentColor = Color(
                            red: Double(firstColor[0]) / 255.0,
                            green: Double(firstColor[1]) / 255.0,
                            blue: Double(firstColor[2]) / 255.0
                        )
                    }
                    
                    self.devices[index] = updatedDevice
                }
            }
            
            // Update persistence
            var persistDevice = device
            persistDevice.brightness = response.state.brightness
            persistDevice.isOn = response.state.isOn
            persistDevice.isOnline = true
            persistDevice.lastSeen = Date()
            
            if let segment = response.state.segments.first,
               let colors = segment.colors,
               let firstColor = colors.first,
               firstColor.count >= 3 {
                persistDevice.currentColor = Color(
                    red: Double(firstColor[0]) / 255.0,
                    green: Double(firstColor[1]) / 255.0,
                    blue: Double(firstColor[2]) / 255.0
                )
            }
            
            await coreDataManager.saveDevice(persistDevice)
            
        } catch {
            // Don't update UI for background refresh failures
            // Connection monitor will handle offline detection
            // Avoid spamming logs on timeouts
        }
    }

    // MARK: - Refresh Coalescing
    private var _lastRefreshRequested: Date?
    
    // MARK: - Additional Device Control Methods
    
    func setDeviceBrightness(_ device: WLEDDevice, brightness: Int) async {
        await updateDeviceBrightness(device, brightness: brightness)
    }
    
    func setDeviceColor(_ device: WLEDDevice, color: Color) async {
        await updateDeviceColor(device, color: color)
    }
    
    func refreshAllDevicesStates() async {
        await refreshDevices()
    }
    
    // Method for DashboardViewModel compatibility
    func refreshAllDevices() async {
        await refreshDevices()
    }
    
    // MARK: - Reconnection Control
    
    func forceReconnection(_ device: WLEDDevice) async {
        await connectionMonitor.forceReconnection(device.id)
    }
    
    func resetReconnectionAttempts(_ device: WLEDDevice) {
        connectionMonitor.resetReconnectionAttempts(device.id)
    }
    
    func getReconnectionStatus(_ device: WLEDDevice) -> String {
        return connectionMonitor.getReconnectionStatus(device.id)
    }
    
    func getConnectionHistory(_ device: WLEDDevice) -> [ConnectionAttempt] {
        return connectionMonitor.getConnectionHistory(device.id)
    }
    
    func isDeviceOnline(_ device: WLEDDevice) -> Bool {
        return connectionMonitor.isDeviceOnline(device.id)
    }
    
    // MARK: - Real-Time Control
    
    func enableRealTimeUpdates() {
        isRealTimeEnabled = true
    }
    
    func disableRealTimeUpdates() {
        isRealTimeEnabled = false
    }
    
    func toggleRealTimeUpdates() {
        isRealTimeEnabled.toggle()
    }
    
    func connectRealTimeForDevice(_ device: WLEDDevice) {
        connectWebSocketIfNeeded(for: device)
    }
    
    func disconnectRealTimeForDevice(_ device: WLEDDevice) {
        disconnectWebSocket(for: device)
    }
    
    func refreshRealTimeConnections() {
        if isRealTimeEnabled {
            connectWebSocketsForAllDevices()
        } else {
            disconnectAllWebSockets()
        }
    }
    
    // MARK: - Prefetching Helpers
    
    /// Warm up data and connections for a device detail view
    func prefetchDeviceDetailData(for device: WLEDDevice) async {
        // Refresh latest state in background
        await refreshDeviceState(device)
        
        // Ensure real-time connection if enabled
        connectWebSocketIfNeeded(for: device)
    }
    
    // MARK: - Error Handling
    
    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Gradient Helpers (foundation)

    func applyGradientStopsAcrossStrip(_ device: WLEDDevice, stops: [GradientStop], ledCount: Int) async {
        let gradient = LEDGradient(stops: stops)
        let frame = GradientSampler.sample(gradient, ledCount: ledCount)
        var intent = ColorIntent(deviceId: device.id, mode: .perLED)
        intent.segmentId = 0
        intent.perLEDHex = frame
        await colorPipeline.apply(intent, to: device)
    }

    func startSmoothABStreaming(_ device: WLEDDevice, from: LEDGradient, to: LEDGradient, durationSec: Double, fps: Int = 20, aBrightness: Int? = nil, bBrightness: Int? = nil) async {
        await transitionRunner.start(
            device: device,
            from: from,
            to: to,
            durationSec: durationSec,
            fps: fps,
            segmentId: 0,
            onProgress: nil
        )
    }

    func cancelStreaming(for device: WLEDDevice) async {
        await transitionRunner.cancel(deviceId: device.id)
    }

    // MARK: - Segments
    func updateSegmentBounds(device: WLEDDevice, segmentId: Int, start: Int, stop: Int) async {
        let seg = SegmentUpdate(id: segmentId, start: start, stop: stop)
        let state = WLEDStateUpdate(seg: [seg])
        _ = try? await apiService.updateState(for: device, state: state)
        // Optimistic update: adjust device.brightness or lastSeen only; avoid mutating nested state structures that may be immutable in models
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx].lastSeen = Date()
            devices[idx].isOnline = true
        }
    }

    // MARK: - Scenes

    func saveCurrentScene(device: WLEDDevice, primaryStops: [GradientStop], transitionEnabled: Bool, secondaryStops: [GradientStop]?, durationSec: Double?, aBrightness: Int?, bBrightness: Int?, effectsEnabled: Bool, effectId: Int?, paletteId: Int?, speed: Int?, intensity: Int?, name: String) {
        let scene = Scene(
            name: name,
            deviceId: device.id,
            brightness: device.brightness,
            primaryStops: primaryStops,
            transitionEnabled: transitionEnabled,
            secondaryStops: secondaryStops,
            durationSec: durationSec,
            aBrightness: aBrightness,
            bBrightness: bBrightness,
            effectsEnabled: effectsEnabled,
            effectId: effectId,
            paletteId: paletteId,
            speed: speed,
            intensity: intensity
        )
        ScenesStore.shared.add(scene)
    }

    func applyScene(_ scene: Scene, to device: WLEDDevice) async {
        // 1) Cancel any running streams
        await cancelStreaming(for: device)

        // 2) Brightness first (bri-only)
        await updateDeviceBrightness(device, brightness: scene.brightness)

        // 3) Effects
        if scene.effectsEnabled {
            // If base colors are available, set them via segment update first
            if let baseA = scene.primaryStops.first?.color.toRGBArray() {
                let seg = SegmentUpdate(id: 0, col: [baseA])
                let st = WLEDStateUpdate(seg: [seg])
                _ = try? await apiService.updateState(for: device, state: st)
            }
            _ = try? await apiService.setEffect(
                scene.effectId ?? 0,
                forSegment: 0,
                speed: scene.speed,
                intensity: scene.intensity,
                palette: scene.paletteId,
                device: device
            )
            return
        }

        // 4) Transition vs static
        if scene.transitionEnabled, let secondary = scene.secondaryStops, let dur = scene.durationSec {
            let gA = LEDGradient(stops: scene.primaryStops)
            let gB = LEDGradient(stops: secondary)
            await startSmoothABStreaming(
                device,
                from: gA,
                to: gB,
                durationSec: dur,
                fps: 20,
                aBrightness: scene.aBrightness,
                bBrightness: scene.bBrightness
            )
        } else {
            let ledCount = device.state?.segments.first?.len ?? 120
            await applyGradientStopsAcrossStrip(device, stops: scene.primaryStops, ledCount: ledCount)
        }
    }
} 