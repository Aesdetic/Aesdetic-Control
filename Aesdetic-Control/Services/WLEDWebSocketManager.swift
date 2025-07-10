import Foundation
import Combine
import Network
import os.log
import UIKit // Added for UIApplication notifications

/// Manages WebSocket connections to WLED devices for real-time state updates
class WLEDWebSocketManager: ObservableObject {
    static let shared = WLEDWebSocketManager()
    
    // MARK: - Published Properties
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: WLEDWebSocketError?
    @Published var deviceConnectionStatuses: [String: DeviceConnectionStatus] = [:]
    @Published var connectionMetrics: ConnectionMetrics = ConnectionMetrics()
    
    // MARK: - Private Properties
    private var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    private var urlSession: URLSession
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "WebSocket")
    private let maxReconnectAttempts = 5
    private var reconnectAttempts: [String: Int] = [:]
    private var reconnectTimers: [String: Timer] = [:]
    private var connectionHealthTimers: [String: Timer] = [:]
    private var lastPingTimes: [String: Date] = [:]
    
    // Connection pool management
    private let maxConcurrentConnections = 20
    private var connectionPriorities: [String: Int] = [:]
    
    // MARK: - State Publishers
    private let deviceStateSubject = PassthroughSubject<WLEDDeviceStateUpdate, Never>()
    var deviceStateUpdates: AnyPublisher<WLEDDeviceStateUpdate, Never> {
        deviceStateSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Connection Status Types
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case limitReached
    }
    
    struct DeviceConnectionStatus {
        let deviceId: String
        var status: ConnectionStatus
        var lastConnected: Date?
        var lastError: WLEDWebSocketError?
        var reconnectAttempts: Int
        var latency: TimeInterval?
        var isHealthy: Bool
        
        init(deviceId: String) {
            self.deviceId = deviceId
            self.status = .disconnected
            self.lastConnected = nil
            self.lastError = nil
            self.reconnectAttempts = 0
            self.latency = nil
            self.isHealthy = false
        }
    }
    
    struct ConnectionMetrics {
        var totalConnections: Int = 0
        var activeConnections: Int = 0
        var failedConnections: Int = 0
        var averageLatency: TimeInterval = 0.0
        var totalReconnections: Int = 0
    }
    
    // MARK: - Initialization
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: config)
        
        startConnectionMetricsTimer()
        
        // Observe app lifecycle to manage resources
        setupAppLifecycleObservers()
    }
    
    deinit {
        // Ensure all resources are cleaned up
        disconnectAll()
        // pathMonitor?.cancel() // This line was removed as pathMonitor is not defined in the original file
        NotificationCenter.default.removeObserver(self)
        
        // Cancel all timers explicitly
        for timer in connectionHealthTimers.values {
            timer.invalidate()
        }
        connectionHealthTimers.removeAll()
        
        for timer in reconnectTimers.values {
            timer.invalidate()
        }
        reconnectTimers.removeAll()
    }
    
    // MARK: - App Lifecycle Management
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidBecomeActive()
        }
    }
    
    private func handleAppDidEnterBackground() {
        // Pause health monitoring timers to save battery
        for timer in connectionHealthTimers.values {
            timer.invalidate()
        }
        connectionHealthTimers.removeAll()
    }
    
    private func handleAppDidBecomeActive() {
        // Resume health monitoring for connected devices
        for deviceId in connectedDeviceIds {
            startHealthMonitoring(for: deviceId)
        }
    }
    
    // MARK: - Public Methods
    
    /// Connect to a WLED device's WebSocket endpoint
    func connect(to device: WLEDDevice, priority: Int = 0) {
        // Check connection limits
        guard activeConnectionCount < maxConcurrentConnections else {
            logger.warning("Connection limit reached. Cannot connect to device: \(device.id)")
            updateDeviceConnectionStatus(deviceId: device.id) { status in
                status.status = .limitReached
                status.lastError = .maxConnectionsReached
            }
            return
        }
        
        guard let url = buildWebSocketURL(for: device) else {
            logger.error("Failed to build WebSocket URL for device: \(device.id)")
            updateDeviceConnectionStatus(deviceId: device.id) { status in
                status.lastError = .invalidURL
            }
            return
        }
        
        logger.info("Connecting to WebSocket for device: \(device.id) at \(url.absoluteString)")
        
        // Set priority and initial status
        connectionPriorities[device.id] = priority
        updateDeviceConnectionStatus(deviceId: device.id) { status in
            status.status = .connecting
            status.lastError = nil
        }
        
        let webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTasks[device.id] = webSocketTask
        
        setupWebSocketListeners(for: device.id, task: webSocketTask)
        webSocketTask.resume()
        
        // Start health monitoring
        startHealthMonitoring(for: device.id)
        
        // Request initial state
        requestFullState(for: device.id)
        
        updateConnectionMetrics()
    }
    
    /// Disconnect from a specific device's WebSocket
    func disconnect(from deviceId: String) {
        logger.info("Disconnecting WebSocket for device: \(deviceId)")
        
        webSocketTasks[deviceId]?.cancel(with: .normalClosure, reason: nil)
        webSocketTasks.removeValue(forKey: deviceId)
        reconnectAttempts.removeValue(forKey: deviceId)
        connectionPriorities.removeValue(forKey: deviceId)
        
        // Cancel timers
        reconnectTimers[deviceId]?.invalidate()
        reconnectTimers.removeValue(forKey: deviceId)
        connectionHealthTimers[deviceId]?.invalidate()
        connectionHealthTimers.removeValue(forKey: deviceId)
        lastPingTimes.removeValue(forKey: deviceId)
        
        updateDeviceConnectionStatus(deviceId: deviceId) { status in
            status.status = .disconnected
            status.isHealthy = false
            status.latency = nil
        }
        
        updateConnectionStatus()
        updateConnectionMetrics()
    }
    
    /// Disconnect from all devices
    func disconnectAll() {
        logger.info("Disconnecting all WebSocket connections")
        
        let deviceIds = Array(webSocketTasks.keys)
        for deviceId in deviceIds {
            disconnect(from: deviceId)
        }
        
        connectionStatus = .disconnected
        connectionMetrics = ConnectionMetrics()
    }
    
    /// Disconnect devices with low priority to make room for new connections
    func optimizeConnections() {
        guard activeConnectionCount >= maxConcurrentConnections else { return }
        
        // Sort devices by priority (lower values = lower priority)
        let sortedDevices = connectionPriorities.sorted { $0.value < $1.value }
        let devicesToDisconnect = sortedDevices.prefix(activeConnectionCount - maxConcurrentConnections + 1)
        
        for (deviceId, _) in devicesToDisconnect {
            logger.info("Disconnecting low-priority device: \(deviceId)")
            disconnect(from: deviceId)
        }
    }
    
    /// Get connection status for a specific device
    func getConnectionStatus(for deviceId: String) -> DeviceConnectionStatus? {
        return deviceConnectionStatuses[deviceId]
    }
    
    /// Get all connected device IDs
    var connectedDeviceIds: [String] {
        return deviceConnectionStatuses.compactMap { (deviceId, status) in
            status.status == .connected ? deviceId : nil
        }
    }
    
    /// Get current active connection count
    var activeConnectionCount: Int {
        return webSocketTasks.count
    }
    
    /// Send a state update to a device via WebSocket
    func sendStateUpdate(_ update: WLEDStateUpdate, to deviceId: String) {
        guard let webSocketTask = webSocketTasks[deviceId] else {
            logger.warning("No WebSocket connection for device: \(deviceId)")
            return
        }
        
        do {
            let jsonData = try JSONEncoder().encode(update)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            webSocketTask.send(message) { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to send WebSocket message: \(error.localizedDescription)")
                    self?.handleWebSocketError(.sendFailed(error), for: deviceId)
                }
            }
        } catch {
            logger.error("Failed to encode state update: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Batch Operations
    
    /// Connect to multiple devices with priority handling
    func connectToDevices(_ devices: [WLEDDevice], priorities: [String: Int] = [:]) async {
        await withTaskGroup(of: Void.self) { group in
            for device in devices {
                group.addTask { [weak self] in
                    let priority = priorities[device.id] ?? 0
                    await MainActor.run {
                        self?.connect(to: device, priority: priority)
                    }
                }
            }
        }
    }
    
    /// Send state updates to multiple devices
    func sendBatchUpdate(_ update: WLEDStateUpdate, to deviceIds: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for deviceId in deviceIds {
                group.addTask { [weak self] in
                    await MainActor.run {
                        self?.sendStateUpdate(update, to: deviceId)
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func updateConnectionMetrics() {
        DispatchQueue.main.async {
            self.connectionMetrics.totalConnections = self.deviceConnectionStatuses.count
            self.connectionMetrics.activeConnections = self.activeConnectionCount
            self.connectionMetrics.failedConnections = self.deviceConnectionStatuses.values.filter { 
                $0.lastError != nil 
            }.count
            
            let latencies = self.deviceConnectionStatuses.values.compactMap { $0.latency }
            self.connectionMetrics.averageLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        }
    }
    
    private func updateDeviceConnectionStatus(deviceId: String, update: @escaping (inout DeviceConnectionStatus) -> Void) {
        DispatchQueue.main.async {
            var status = self.deviceConnectionStatuses[deviceId] ?? DeviceConnectionStatus(deviceId: deviceId)
            update(&status)
            self.deviceConnectionStatuses[deviceId] = status
        }
    }
    
    private func startConnectionMetricsTimer() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.updateConnectionMetrics()
        }
    }
    
    private func startHealthMonitoring(for deviceId: String) {
        // Cancel existing timer first to prevent duplicates
        connectionHealthTimers[deviceId]?.invalidate()
        
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.performHealthCheck(for: deviceId)
        }
        connectionHealthTimers[deviceId] = timer
    }
    
    private func performHealthCheck(for deviceId: String) {
        guard let webSocketTask = webSocketTasks[deviceId] else { 
            // Clean up timer if WebSocket no longer exists
            connectionHealthTimers[deviceId]?.invalidate()
            connectionHealthTimers.removeValue(forKey: deviceId)
            return 
        }
        
        let pingTime = Date()
        lastPingTimes[deviceId] = pingTime
        
        let pingMessage = URLSessionWebSocketTask.Message.string("ping")
        webSocketTask.send(pingMessage) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.warning("Health check failed for device \(deviceId): \(error.localizedDescription)")
                self.updateDeviceConnectionStatus(deviceId: deviceId) { status in
                    status.isHealthy = false
                    status.latency = nil
                }
            } else {
                let latency = Date().timeIntervalSince(pingTime)
                self.updateDeviceConnectionStatus(deviceId: deviceId) { status in
                    status.isHealthy = true
                    status.latency = latency
                }
            }
        }
    }
    
    private func buildWebSocketURL(for device: WLEDDevice) -> URL? {
        guard let baseURL = URL(string: "ws://\(device.ipAddress)") else {
            return nil
        }
        return baseURL.appendingPathComponent("ws")
    }
    
    private func setupWebSocketListeners(for deviceId: String, task: URLSessionWebSocketTask) {
        receiveMessage(for: deviceId, task: task)
        
        // Update status to connected once setup is complete
        updateDeviceConnectionStatus(deviceId: deviceId) { status in
            status.status = .connected
            status.lastConnected = Date()
            status.isHealthy = true
        }
    }
    
    private func receiveMessage(for deviceId: String, task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleReceivedMessage(message, from: deviceId)
                
                // Update connection health on successful message
                self?.updateDeviceConnectionStatus(deviceId: deviceId) { status in
                    status.isHealthy = true
                }
                
                // Continue listening for more messages
                self?.receiveMessage(for: deviceId, task: task)
                
            case .failure(let error):
                self?.logger.error("WebSocket receive error for device \(deviceId): \(error.localizedDescription)")
                self?.handleWebSocketError(.connectionLost(error), for: deviceId)
            }
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message, from deviceId: String) {
        switch message {
        case .data(let data):
            parseStateUpdate(from: data, deviceId: deviceId)
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            parseStateUpdate(from: data, deviceId: deviceId)
        @unknown default:
            logger.warning("Received unknown WebSocket message type from device: \(deviceId)")
        }
    }
    
    private func parseStateUpdate(from data: Data, deviceId: String) {
        do {
            let response = try JSONDecoder().decode(WLEDResponse.self, from: data)
            
            let deviceUpdate = WLEDDeviceStateUpdate(
                deviceId: deviceId,
                state: response.state,
                info: WLEDInfo(
                    name: response.info.name,
                    mac: response.info.mac,
                    version: response.info.ver,
                    brand: nil,
                    product: nil,
                    uptime: nil
                ),
                timestamp: Date()
            )
            
            DispatchQueue.main.async {
                self.deviceStateSubject.send(deviceUpdate)
            }
            
            logger.debug("Received state update for device: \(deviceId)")
            
        } catch {
            logger.error("Failed to parse WebSocket message for device \(deviceId): \(error.localizedDescription)")
        }
    }
    
    private func requestFullState(for deviceId: String) {
        // Send request for full JSON state object
        let request = ["v": true]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: request)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            webSocketTasks[deviceId]?.send(message) { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to request full state for device \(deviceId): \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to encode state request for device \(deviceId): \(error.localizedDescription)")
        }
    }
    
    private func handleWebSocketError(_ error: WLEDWebSocketError, for deviceId: String) {
        updateDeviceConnectionStatus(deviceId: deviceId) { status in
            status.lastError = error
            status.isHealthy = false
        }
        
        DispatchQueue.main.async {
            self.lastError = error
        }
        
        // Attempt reconnection
        attemptReconnection(for: deviceId)
    }
    
    private func attemptReconnection(for deviceId: String) {
        let currentAttempts = reconnectAttempts[deviceId, default: 0]
        
        guard currentAttempts < maxReconnectAttempts else {
            logger.error("Max reconnection attempts reached for device: \(deviceId)")
            updateDeviceConnectionStatus(deviceId: deviceId) { status in
                status.lastError = .maxReconnectAttemptsReached
                status.reconnectAttempts = currentAttempts
            }
            disconnect(from: deviceId)
            return
        }
        
        reconnectAttempts[deviceId] = currentAttempts + 1
        
        updateDeviceConnectionStatus(deviceId: deviceId) { status in
            status.status = .reconnecting
            status.reconnectAttempts = currentAttempts + 1
        }
        
        // Exponential backoff: 2^attempt seconds
        let delay = TimeInterval(pow(2.0, Double(currentAttempts)))
        
        logger.info("Attempting reconnection \(currentAttempts + 1)/\(self.maxReconnectAttempts) for device \(deviceId) in \(delay) seconds")
        
        // Cancel existing timer first
        reconnectTimers[deviceId]?.invalidate()
        
        reconnectTimers[deviceId] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            Task { @MainActor in
                guard let device = await self.findDevice(by: deviceId) else { 
                    // Clean up if device no longer exists
                    self.reconnectTimers.removeValue(forKey: deviceId)
                    return 
                }
                
                self.reconnectTimers.removeValue(forKey: deviceId)
                let priority = self.connectionPriorities[deviceId] ?? 0
                self.connect(to: device, priority: priority)
            }
        }
        
        updateConnectionMetrics()
    }
    
    @MainActor
    private func findDevice(by deviceId: String) -> WLEDDevice? {
        // This would typically come from the device manager/view model
        // For now, we'll need to get this from DeviceControlViewModel
        return DeviceControlViewModel.shared.devices.first { $0.id == deviceId }
    }
    
    private func updateConnectionStatus() {
        DispatchQueue.main.async {
            if self.webSocketTasks.isEmpty {
                self.connectionStatus = .disconnected
            } else {
                let hasConnectedDevices = self.deviceConnectionStatuses.values.contains { 
                    $0.status == .connected 
                }
                let hasReconnectingDevices = self.deviceConnectionStatuses.values.contains { 
                    $0.status == .reconnecting 
                }
                
                if hasConnectedDevices {
                    self.connectionStatus = .connected
                } else if hasReconnectingDevices {
                    self.connectionStatus = .reconnecting
                } else {
                    self.connectionStatus = .connecting
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Represents a WebSocket error
enum WLEDWebSocketError: Error, LocalizedError {
    case connectionFailed(Error)
    case connectionLost(Error)
    case sendFailed(Error)
    case invalidURL
    case maxReconnectAttemptsReached
    case maxConnectionsReached
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            return "Failed to connect: \(error.localizedDescription)"
        case .connectionLost(let error):
            return "Connection lost: \(error.localizedDescription)"
        case .sendFailed(let error):
            return "Failed to send message: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .maxReconnectAttemptsReached:
            return "Maximum reconnection attempts reached"
        case .maxConnectionsReached:
            return "Maximum connection attempts reached"
        }
    }
}

 