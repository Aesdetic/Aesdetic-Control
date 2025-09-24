import Foundation
import Network
import Combine
import OSLog
import SwiftUI

/// Reconnection strategy configuration
struct ReconnectionStrategy {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double
    
    static let `default` = ReconnectionStrategy(
        maxRetries: 5,
        baseDelay: 2.0,
        maxDelay: 60.0,
        backoffMultiplier: 2.0
    )
}

/// Connection attempt tracking
struct ConnectionAttempt {
    let timestamp: Date
    let success: Bool
    let error: Error?
}

/// Connection health monitoring service for WLED devices with intelligent reconnection
@MainActor
class WLEDConnectionMonitor: ObservableObject {
    static let shared = WLEDConnectionMonitor()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AesdeticControl", category: "ConnectionMonitor")
    private let apiService: WLEDAPIServiceProtocol
    private let coreDataManager: CoreDataManager
    
    // Health check configuration
    private let healthCheckInterval: TimeInterval = 15.0 // Check every 15 seconds (reduced from 30)
    private let quickCheckInterval: TimeInterval = 3.0   // Quick check every 3 seconds (reduced from 5)
    private let connectionTimeout: TimeInterval = 2.0    // Connection timeout (reduced from 3)
    
    // Reconnection configuration
    private let reconnectionStrategy = ReconnectionStrategy.default
    
    // State management
    @Published var deviceHealthStatus: [String: Bool] = [:]
    @Published var isNetworkAvailable: Bool = true
    @Published var reconnectionStatus: [String: String] = [:] // deviceId -> status message
    
    // Internal tracking
    private var registeredDevices: Set<String> = []
    private var consecutiveFailures: [String: Int] = [:]
    private var pathMonitor: NWPathMonitor?
    private var monitorQueue = DispatchQueue(label: "WLEDConnectionMonitor.networkQueue")
    private var healthCheckTimer: Timer?
    private var quickCheckTimer: Timer?
    
    // Reconnection tracking
    private var reconnectionAttempts: [String: Int] = [:]
    private var reconnectionTasks: [String: Task<Void, Never>] = [:]
    private var lastReconnectionAttempt: [String: Date] = [:]
    private var connectionHistory: [String: [ConnectionAttempt]] = [:]
    
    private init() {
        self.apiService = WLEDAPIService.shared
        self.coreDataManager = CoreDataManager.shared
        setupNetworkMonitoring()
        startHealthChecks()
    }
    
    deinit {
        healthCheckTimer?.invalidate()
        quickCheckTimer?.invalidate()
        pathMonitor?.cancel()
        healthCheckTimer = nil
        quickCheckTimer = nil
        pathMonitor = nil
        
        // Cancel all reconnection tasks
        for task in reconnectionTasks.values {
            task.cancel()
        }
        reconnectionTasks.removeAll()
    }
    
    // MARK: - Network Path Monitoring
    
    private func setupNetworkMonitoring() {
        pathMonitor = NWPathMonitor()
        
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let isAvailable = path.status == .satisfied
                if isAvailable != self?.isNetworkAvailable {
                    self?.isNetworkAvailable = isAvailable
                    
                    if isAvailable {
                        self?.handleNetworkRestored()
                    } else {
                        self?.handleNetworkLost()
                    }
                }
            }
        }
        
        pathMonitor?.start(queue: monitorQueue)
    }
    
    @MainActor
    private func handleNetworkRestored() {
        logger.info("Network connectivity restored - resuming health checks")
        
        // Clear network-related status messages
        for deviceId in reconnectionStatus.keys where reconnectionStatus[deviceId] == "Network unavailable" {
            reconnectionStatus[deviceId] = "Checking connection..."
        }
        
        // Resume monitoring for all registered devices
        Task {
            let devices = await coreDataManager.fetchDevices()
            for device in devices {
                registerDevice(device)
            }
        }
    }
    
    @MainActor
    private func handleNetworkLost() {
        logger.warning("Network connectivity lost")
        
        // Update all devices to offline
        for deviceId in deviceHealthStatus.keys {
            deviceHealthStatus[deviceId] = false
            reconnectionStatus[deviceId] = "Network unavailable"
        }
        
        // Cancel all active reconnection tasks
        for task in reconnectionTasks.values {
            task.cancel()
        }
        reconnectionTasks.removeAll()
    }
    
    // MARK: - Device Registration
    
    func registerDevice(_ device: WLEDDevice) {
        registeredDevices.insert(device.id)
        deviceHealthStatus[device.id] = device.isOnline
        consecutiveFailures[device.id] = 0
        reconnectionAttempts[device.id] = 0
        reconnectionStatus[device.id] = "Monitoring"
        connectionHistory[device.id] = []
        
        logger.info("Registered device for monitoring: \(device.name) (\(device.id))")
        
        // Trigger immediate health check for new device
        Task {
            await checkDeviceHealth(device)
        }
    }
    
    func unregisterDevice(_ deviceId: String) {
        registeredDevices.remove(deviceId)
        deviceHealthStatus.removeValue(forKey: deviceId)
        consecutiveFailures.removeValue(forKey: deviceId)
        reconnectionAttempts.removeValue(forKey: deviceId)
        reconnectionStatus.removeValue(forKey: deviceId)
        lastReconnectionAttempt.removeValue(forKey: deviceId)
        connectionHistory.removeValue(forKey: deviceId)
        
        // Cancel any active reconnection task
        reconnectionTasks[deviceId]?.cancel()
        reconnectionTasks.removeValue(forKey: deviceId)
        
        logger.info("Unregistered device from monitoring: \(deviceId)")
    }
    
    /// Perform immediate health checks for all registered devices
    func performImmediateHealthChecks() async {
        logger.info("Performing immediate health checks for all devices")
        
        let devices = await loadRegisteredDevices()
        
        await withTaskGroup(of: Void.self) { group in
            for device in devices {
                group.addTask { [weak self] in
                    await self?.checkDeviceHealth(device)
                }
            }
        }
    }
    
    // MARK: - Health Check System
    
    private func startHealthChecks() {
        // Regular health checks every 30 seconds
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performHealthChecks()
            }
        }
        
        // Quick checks every 5 seconds for problem devices
        quickCheckTimer = Timer.scheduledTimer(withTimeInterval: quickCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performQuickChecks()
            }
        }
    }
    
    private func performHealthChecks() async {
        guard isNetworkAvailable else {
            logger.debug("Skipping health checks - network unavailable")
            return
        }
        
        let devices = await loadRegisteredDevices()
        logger.debug("Performing health checks for \(devices.count) devices")
        
        await withTaskGroup(of: Void.self) { group in
            for device in devices {
                group.addTask { [weak self] in
                    await self?.checkDeviceHealth(device)
                }
            }
        }
    }
    
    private func performQuickChecks() async {
        guard isNetworkAvailable else { return }
        
        let problemDevices = await loadRegisteredDevices().filter { device in
            consecutiveFailures[device.id, default: 0] > 0
        }
        
        if !problemDevices.isEmpty {
            logger.debug("Performing quick checks for \(problemDevices.count) problem devices")
            
            await withTaskGroup(of: Void.self) { group in
                for device in problemDevices {
                    group.addTask { [weak self] in
                        await self?.checkDeviceHealth(device)
                    }
                }
            }
        }
    }
    
    private func checkDeviceHealth(_ device: WLEDDevice) async {
        do {
            let response = try await apiService.getState(for: device)
            handleHealthCheckSuccess(device, response: response)
        } catch {
            await handleHealthCheckFailure(device, error: error)
        }
    }
    
    @MainActor
    private func handleHealthCheckSuccess(_ device: WLEDDevice, response: WLEDResponse) {
        consecutiveFailures[device.id] = 0
        reconnectionAttempts[device.id] = 0
        
        let wasOffline = deviceHealthStatus[device.id] == false
        deviceHealthStatus[device.id] = true
        
        if wasOffline {
            logger.info("Device came online: \(device.name) (\(device.id))")
            reconnectionStatus[device.id] = "Online"
            
            // Cancel any active reconnection task
            reconnectionTasks[device.id]?.cancel()
            reconnectionTasks.removeValue(forKey: device.id)
        }
        
        // Record successful connection attempt
        recordConnectionAttempt(deviceId: device.id, success: true, error: nil)
        
        // Update Core Data with latest state
        Task {
            await updateDeviceInCoreData(device, isOnline: true, response: response)
        }
    }
    
    @MainActor
    private func handleHealthCheckFailure(_ device: WLEDDevice, error: Error) async {
        let currentFailures = consecutiveFailures[device.id, default: 0] + 1
        consecutiveFailures[device.id] = currentFailures
        
        logger.debug("Health check failed for \(device.name): \(error.localizedDescription) (attempt \(currentFailures)/3)")
        
        // Record failed connection attempt
        recordConnectionAttempt(deviceId: device.id, success: false, error: error)
        
        // Mark as offline after 3 consecutive failures
        if currentFailures >= 3 {
            let wasOnline = deviceHealthStatus[device.id] == true
            deviceHealthStatus[device.id] = false
            
            if wasOnline {
                logger.info("Device went offline: \(device.name) (\(device.id)) - initiating reconnection")
                await initiateReconnection(device)
            }
            
            // Update Core Data
            Task {
                await updateDeviceInCoreData(device, isOnline: false, response: nil)
            }
        } else {
            reconnectionStatus[device.id] = "Connection issues detected (\(currentFailures)/3)"
        }
    }
    
    // MARK: - Intelligent Reconnection Logic
    
    @MainActor
    private func initiateReconnection(_ device: WLEDDevice) async {
        guard isNetworkAvailable else {
            reconnectionStatus[device.id] = "Waiting for network"
            return
        }
        
        let attempts = reconnectionAttempts[device.id, default: 0]
        
        // Check if we've exceeded max retries
        if attempts >= reconnectionStrategy.maxRetries {
            logger.warning("Max reconnection attempts reached for \(device.name) (\(device.id))")
            reconnectionStatus[device.id] = "Max retries exceeded"
            return
        }
        
        // Cancel any existing reconnection task
        reconnectionTasks[device.id]?.cancel()
        
        // Calculate exponential backoff delay
        let delay = calculateBackoffDelay(attempt: attempts)
        reconnectionAttempts[device.id] = attempts + 1
        lastReconnectionAttempt[device.id] = Date()
        
        logger.info("Scheduling reconnection attempt \(attempts + 1)/\(self.reconnectionStrategy.maxRetries) for \(device.name) in \(delay)s")
        reconnectionStatus[device.id] = "Reconnecting in \(Int(delay))s... (\(attempts + 1)/\(reconnectionStrategy.maxRetries))"
        
        // Create reconnection task
        reconnectionTasks[device.id] = Task { [weak self] in
            // Wait for backoff delay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            await self?.attemptReconnection(device)
        }
    }
    
    private func calculateBackoffDelay(attempt: Int) -> TimeInterval {
        let delay = reconnectionStrategy.baseDelay * pow(reconnectionStrategy.backoffMultiplier, Double(attempt))
        return min(delay, reconnectionStrategy.maxDelay)
    }
    
    @MainActor
    private func attemptReconnection(_ device: WLEDDevice) async {
        guard !Task.isCancelled && isNetworkAvailable else { return }
        
        let attemptNumber = reconnectionAttempts[device.id, default: 0]
        logger.info("Attempting reconnection \(attemptNumber)/\(self.reconnectionStrategy.maxRetries) for \(device.name)")
        
        reconnectionStatus[device.id] = "Attempting reconnection..."
        
        do {
            // Try to get device state
            let response = try await apiService.getState(for: device)
            
            // Success! Reset everything
            handleReconnectionSuccess(device, response: response)
            
        } catch {
            handleReconnectionFailure(device, error: error)
        }
        
        // Clean up task reference
        reconnectionTasks.removeValue(forKey: device.id)
    }
    
    @MainActor
    private func handleReconnectionSuccess(_ device: WLEDDevice, response: WLEDResponse) {
        logger.info("Reconnection successful for \(device.name) (\(device.id))")
        
        // Reset all failure counters
        consecutiveFailures[device.id] = 0
        reconnectionAttempts[device.id] = 0
        deviceHealthStatus[device.id] = true
        reconnectionStatus[device.id] = "Reconnected successfully"
        
        // Record successful reconnection
        recordConnectionAttempt(deviceId: device.id, success: true, error: nil)
        
        // Update Core Data
        Task {
            await updateDeviceInCoreData(device, isOnline: true, response: response)
        }
        
        // Clear status after a delay
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            reconnectionStatus[device.id] = "Online"
        }
    }
    
    @MainActor
    private func handleReconnectionFailure(_ device: WLEDDevice, error: Error) {
        let attempts = reconnectionAttempts[device.id, default: 0]
        logger.warning("Reconnection attempt \(attempts)/\(self.reconnectionStrategy.maxRetries) failed for \(device.name): \(error.localizedDescription)")
        
        // Record failed reconnection attempt
        recordConnectionAttempt(deviceId: device.id, success: false, error: error)
        
        if attempts >= reconnectionStrategy.maxRetries {
            reconnectionStatus[device.id] = "Reconnection failed - device may be offline"
            logger.error("All reconnection attempts exhausted for \(device.name) (\(device.id))")
        } else {
            // Schedule next attempt
            Task {
                await initiateReconnection(device)
            }
        }
    }
    
    // MARK: - Connection History
    
    private func recordConnectionAttempt(deviceId: String, success: Bool, error: Error?) {
        let attempt = ConnectionAttempt(timestamp: Date(), success: success, error: error)
        
        if connectionHistory[deviceId] == nil {
            connectionHistory[deviceId] = []
        }
        
        connectionHistory[deviceId]?.append(attempt)
        
        // Keep only last 50 attempts
        if let history = connectionHistory[deviceId], history.count > 50 {
            connectionHistory[deviceId] = Array(history.suffix(50))
        }
    }
    
    // MARK: - Data Management
    
    private func loadRegisteredDevices() async -> [WLEDDevice] {
                let devices = await coreDataManager.fetchDevices()
        return devices.filter { registeredDevices.contains($0.id) }
    }
    
    private func updateDeviceInCoreData(_ device: WLEDDevice, isOnline: Bool, response: WLEDResponse?) async {
        var updatedDevice = device
        updatedDevice.isOnline = isOnline
        updatedDevice.lastSeen = Date()
        
        if let response = response {
            updatedDevice.brightness = response.state.brightness
            updatedDevice.isOn = response.state.isOn
            
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
        }
        
        await coreDataManager.saveDevice(updatedDevice)
    }
    
    // MARK: - Public Interface
    
    func isDeviceOnline(_ deviceId: String) -> Bool {
        return deviceHealthStatus[deviceId, default: false]
    }
    
    func getDeviceHealthStatus() -> [String: Bool] {
        return deviceHealthStatus
    }
    
    func getReconnectionStatus(_ deviceId: String) -> String {
        return reconnectionStatus[deviceId, default: "Unknown"]
    }
    
    func getConnectionHistory(_ deviceId: String) -> [ConnectionAttempt] {
        return connectionHistory[deviceId, default: []]
    }
    
    func forceHealthCheck() async {
        await performHealthChecks()
    }
    
    func forceReconnection(_ deviceId: String) async {
        guard let device = await loadRegisteredDevices().first(where: { $0.id == deviceId }) else {
            logger.error("Cannot force reconnection - device \(deviceId) not found")
            return
        }
        
        logger.info("Force reconnection requested for \(device.name)")
        reconnectionAttempts[deviceId] = 0 // Reset attempt counter
        await initiateReconnection(device)
    }
    
    func resetReconnectionAttempts(_ deviceId: String) {
        reconnectionAttempts[deviceId] = 0
        reconnectionTasks[deviceId]?.cancel()
        reconnectionTasks.removeValue(forKey: deviceId)
        reconnectionStatus[deviceId] = "Reset - monitoring"
        logger.info("Reset reconnection attempts for device \(deviceId)")
    }
} 