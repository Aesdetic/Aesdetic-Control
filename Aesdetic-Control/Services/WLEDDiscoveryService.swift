//
//  WLEDDiscoveryService.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Network
import Combine
import SwiftUI
import os.log

@available(iOS 14.0, *)
class WLEDDiscoveryService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var discoveredDevices: [WLEDDevice] = []
    @Published var isScanning: Bool = false
    @Published var discoveryProgress: String = ""
    @Published var lastDiscoveryTime: Date?
    @Published var discoveryErrorMessage: String?
    @Published var lastDiscoveryErrorDate: Date?
    @Published var lastDiscoverySourceByDevice: [String: String] = [:]
    @Published var lastDiscoverySourceByIP: [String: String] = [:]
    
    private var session: URLSession
    private var scannedIPs = Set<String>()
    private let syncQueue = DispatchQueue(label: "wled.discovery.sync")
    private let logger = os.Logger(subsystem: "com.aesdetic.control", category: "Discovery")
    private let coreDataManager = CoreDataManager.shared
    private var failedIPBanlist: [String: Date] = [:]
    private var deviceCountAtScanStart: Int = 0  // Track device count at start of scan
    private var discoveryStartTime: Date?
    private var fallbackScanWorkItem: DispatchWorkItem?
    
    // Network discovery components
    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "wled.discovery.browser")
    private var wasScanningBeforeBackground: Bool = false
    private var isPassiveListening: Bool = false
    private var lastDiscoveryCheck: [String: Date] = [:]
    private var lastErrorBroadcast: Date?
    
    // Discovery configuration (aligned with WLED's approach)
    private let activeDiscoveryWindow: TimeInterval = 4.0
    private let httpTimeout: TimeInterval = 3.0  // Base timeout for discovery requests
    private let deviceCheckTimeout: TimeInterval = 5.0
    private let deviceCheckInitialDelay: TimeInterval = 1.5
    private let deviceCheckFailureThreshold: Int = 3
    private let deviceCheckBaseBackoff: TimeInterval = 2.0
    private let deviceCheckMaxBackoff: TimeInterval = 20.0
    private let failureTTL: TimeInterval = 15 * 60
    private let discoveryCheckCooldown: TimeInterval = 20.0
    private let minimumDiscoveryDuration: TimeInterval = 30.0
    private var deviceCheckFailures: [String: Int] = [:]
    private var deviceCheckBackoffUntil: [String: Date] = [:]

    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = httpTimeout
        config.timeoutIntervalForResource = httpTimeout * 2
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        session = URLSession(configuration: config)
        
        super.init()
        logger.info("🏠 WLEDDiscoveryService initialized with enhanced discovery capabilities")
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - App Lifecycle
    @objc private func appDidEnterBackground() {
        syncQueue.async { self.wasScanningBeforeBackground = self.isScanning }
        if isScanning { stopDiscovery() }
        if isPassiveListening { stopPassiveDiscovery() }
    }
    
    @objc private func appDidBecomeActive() {
        var shouldResume = false
        syncQueue.sync {
            shouldResume = wasScanningBeforeBackground
            wasScanningBeforeBackground = false
        }
        if shouldResume { startDiscovery() }
        if !isPassiveListening { startPassiveDiscovery() }
    }
    
    deinit {
        stopDiscovery()
    }
    
    // MARK: - Public Methods
    
    func startDiscovery() {
        guard !isScanning else {
            logger.warning("⚠️ Already scanning, ignoring start request")
            return
        }
        
        logger.info("🚀 Starting comprehensive WLED discovery...")
        DispatchQueue.main.async {
            self.clearDiscoveryError()
            // Track device count at start to detect NEW devices found during this scan
            self.deviceCountAtScanStart = self.discoveredDevices.count
            self.discoveryStartTime = Date()
            self.isScanning = true
            self.discoveryProgress = "Initializing discovery..."
            self.syncQueue.async {
                self.scannedIPs.removeAll()
                self.failedIPBanlist.removeAll()
                self.lastDiscoveryCheck.removeAll()
                self.deviceCheckFailures.removeAll()
                self.deviceCheckBackoffUntil.removeAll()
            }
        }
        
        startComprehensiveDiscovery()
    }

    func startPassiveDiscovery() {
        guard !isPassiveListening else { return }
        isPassiveListening = true

        DispatchQueue.main.async {
            self.clearDiscoveryError()
            self.discoveryProgress = "Listening for WLED devices (mDNS)..."
        }

        DispatchQueue.main.async {
            self.startmDNSDiscovery()
        }
    }

    func stopPassiveDiscovery() {
        guard isPassiveListening else { return }
        isPassiveListening = false
        stopmDNSDiscovery()
        DispatchQueue.main.async {
            if !self.isScanning {
                self.discoveryProgress = "Passive discovery stopped"
            }
        }
    }
    
    func stopDiscovery() {
        guard isScanning else { return }
        
        logger.info("⏹️ Stopping WLED discovery")
        
        // Clean up timer
        deviceUpdateTimer?.invalidate()
        deviceUpdateTimer = nil
        
        // Stop mDNS discovery
        if !isPassiveListening {
            stopmDNSDiscovery()
        }
        fallbackScanWorkItem?.cancel()
        fallbackScanWorkItem = nil

        // Cancel in-flight HTTP scans by invalidating and recreating the session
        session.invalidateAndCancel()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = httpTimeout
        config.timeoutIntervalForResource = httpTimeout * 2
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        session = URLSession(configuration: config)
        
        DispatchQueue.main.async {
            self.isScanning = false
            self.discoveryProgress = "Discovery stopped"
            self.lastDiscoveryTime = Date()
        }
    }
    
    /// Manually add a device by IP address
    func addDeviceByIP(_ ipAddress: String) {
        logger.info("🎯 Manually checking device at IP: \(ipAddress)")
        DispatchQueue.main.async {
            self.discoveryProgress = "Checking \(ipAddress)..."
        }
        
        checkWLEDDevice(at: ipAddress, allowRescan: true, bypassBanlist: true) { result in
            self.handleDeviceCheckResult(result, source: "Manual")
        }
    }
    
    // MARK: - Comprehensive Discovery
    
    private func startComprehensiveDiscovery() {
        DispatchQueue.global(qos: .userInitiated).async {
            // WLED native approach: foreground mDNS discovery only.
            DispatchQueue.main.async {
                self.discoveryProgress = "Searching for WLED devices (mDNS)..."
            }
            
            DispatchQueue.main.async {
                self.startmDNSDiscovery()
            }
            self.scheduleDiscoveryFinish()
        }
    }
    
    // MARK: - mDNS/Bonjour Discovery (WLED's Primary Method)
    
    private func startmDNSDiscovery() {
        logger.info("🔍 Starting mDNS discovery for WLED devices...")
        stopmDNSDiscovery()

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_wled._tcp", domain: "local.")
        let parameters = NWParameters()
        parameters.allowLocalEndpointReuse = true
        parameters.acceptLocalOnly = true
        parameters.allowFastOpen = true

        let browser = NWBrowser(for: descriptor, using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results, changes)
            }
        }
        self.browser = browser
        browser.start(queue: browserQueue)
    }

    private func stopmDNSDiscovery() {
        browser?.cancel()
        browser = nil
    }

    private func scheduleDiscoveryFinish() {
        fallbackScanWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isScanning else { return }
            self.finishDiscovery()
        }
        fallbackScanWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + activeDiscoveryWindow, execute: workItem)
    }

    private func shouldStartQuickCheck(for ipAddress: String) -> Bool {
        var shouldCheck = false
        syncQueue.sync {
            let now = Date()
            if let lastSeen = lastDiscoveryCheck[ipAddress], now.timeIntervalSince(lastSeen) < discoveryCheckCooldown {
                return
            }
            lastDiscoveryCheck[ipAddress] = now
            failedIPBanlist.removeValue(forKey: ipAddress)
            shouldCheck = true
        }
        return shouldCheck
    }

    private func finishDiscovery() {
        let elapsed = Date().timeIntervalSince(discoveryStartTime ?? Date())
        let delay = max(0, minimumDiscoveryDuration - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isScanning else { return }
            let totalNewDevices = self.discoveredDevices.count - self.deviceCountAtScanStart
            self.logger.info("✅ Discovery completed - found \(totalNewDevices) new device(s), total: \(self.discoveredDevices.count)")
            self.isScanning = false
            self.discoveryProgress = "Discovery completed - found \(totalNewDevices) new device(s)"
            self.lastDiscoveryTime = Date()
            if !self.isPassiveListening {
                self.stopmDNSDiscovery()
            }
        }
    }
    // MARK: - Device Checking and Parsing
    
    private func handleDeviceCheckResult(_ result: Result<WLEDDevice, Error>, source: String) {
        switch result {
        case .success(let device):
            logger.info("🎉 Found WLED device via \(source): \(device.name) at \(device.ipAddress)")
            clearDiscoveryError()
            recordDiscoverySource(deviceId: device.id, ipAddress: device.ipAddress, source: source)
            addOrUpdateDevice(device)
        case .failure(let error):
            // Suppress expected failures during network scanning:
            // - Timeouts (most IPs don't have WLED devices)
            // - Connection refused/not reachable (normal during scan)
            // - Already scanned (no need to log)
            let errorDesc = error.localizedDescription.lowercased()
            let isExpectedFailure = errorDesc.contains("timeout") ||
                                   errorDesc.contains("unreachable") ||
                                   errorDesc.contains("could not connect") ||
                                   errorDesc.contains("already scanned") ||
                                   errorDesc.contains("backoff") ||
                                   errorDesc.contains("banned") ||
                                   errorDesc.contains("not a wled device")
            
            // Only log unexpected errors (e.g., decoding errors, invalid responses)
            if !isExpectedFailure {
                logger.debug("Device check failed via \(source): \(error.localizedDescription)")
            }
        }
    }

    private func addPlaceholderDevice(name: String, ipAddress: String, source: String) {
        let displayName = name.isEmpty ? "WLED" : name
        let placeholder = WLEDDevice(
            id: "ip:\(ipAddress)",
            name: displayName,
            ipAddress: ipAddress,
            isOnline: true,
            brightness: 0,
            currentColor: WLEDDevice.wledBootDefaultColor,
            productType: .generic,
            location: .all,
            lastSeen: Date(),
            state: nil
        )
        logger.info("⚡️ Quick discovery via \(source): \(displayName) at \(ipAddress)")
        recordDiscoverySource(deviceId: placeholder.id, ipAddress: ipAddress, source: source)
        addOrUpdateDevice(placeholder)
    }
    
    private func checkWLEDDevice(at ipAddress: String, allowRescan: Bool = false, bypassBanlist: Bool = false, completion: @escaping (Result<WLEDDevice, Error>) -> Void) {
        // Check if already scanned
        var alreadyScanned = false
        var isBanned = false
        var isBackedOff = false
        syncQueue.sync {
            if allowRescan {
                _ = scannedIPs.insert(ipAddress)
            } else {
                alreadyScanned = !scannedIPs.insert(ipAddress).inserted
            }
            if !bypassBanlist, let ts = failedIPBanlist[ipAddress], Date().timeIntervalSince(ts) < failureTTL {
                isBanned = true
            }
            if !bypassBanlist, let backoffUntil = deviceCheckBackoffUntil[ipAddress], backoffUntil > Date() {
                isBackedOff = true
            }
        }
        
        if alreadyScanned || isBanned || isBackedOff {
            let reason: String
            if isBackedOff {
                reason = "Backoff in progress"
            } else if isBanned {
                reason = "Temporarily banned"
            } else {
                reason = "Already scanned"
            }
            completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: reason])))
            return
        }
        
        let urlString = "http://\(ipAddress)/json/info"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = deviceCheckTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WLED-Discovery/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("close", forHTTPHeaderField: "Connection")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                let nserr = error as NSError
                let isTransient = nserr.domain == NSURLErrorDomain &&
                    (nserr.code == NSURLErrorTimedOut ||
                     nserr.code == NSURLErrorCannotConnectToHost ||
                     nserr.code == NSURLErrorNetworkConnectionLost ||
                     nserr.code == NSURLErrorCannotFindHost)
                if isTransient {
                    self.syncQueue.async {
                        let failures = (self.deviceCheckFailures[ipAddress] ?? 0) + 1
                        self.deviceCheckFailures[ipAddress] = failures
                        let backoff = min(self.deviceCheckBaseBackoff * pow(2.0, Double(failures - 1)), self.deviceCheckMaxBackoff)
                        self.deviceCheckBackoffUntil[ipAddress] = Date().addingTimeInterval(backoff)
                        if failures >= self.deviceCheckFailureThreshold {
                            self.failedIPBanlist[ipAddress] = Date()
                        }
                    }
                }
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            // Verify it's a WLED device by checking:
            // 1. HTTP 200 status
            // 2. Valid JSON response with WLED structure
            // 3. Optional: Check for WLED-specific headers (Server header may contain "WLED")
            guard httpResponse.statusCode == 200, let data = data else {
                completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a WLED device"])))
                return
            }
            
            // Try to parse as WLED /json/info to verify it's actually a WLED device
            do {
                let testParse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard testParse?["mac"] != nil || testParse?["name"] != nil else {
                    completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a WLED device"])))
                    return
                }
            } catch {
                completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a WLED device"])))
                return
            }
            
            self.syncQueue.async {
                self.deviceCheckFailures[ipAddress] = 0
                self.deviceCheckBackoffUntil.removeValue(forKey: ipAddress)
                self.failedIPBanlist.removeValue(forKey: ipAddress)
            }
            self.parseWLEDInfoResponse(from: data, ipAddress: ipAddress, completion: completion)
        }.resume()
    }
    
    private func parseWLEDInfoResponse(from data: Data, ipAddress: String, completion: @escaping (Result<WLEDDevice, Error>) -> Void) {
        do {
            let info = try JSONDecoder().decode(WLEDInfo.self, from: data)
            let wledDevice = WLEDDevice(
                id: info.mac,
                name: info.name.isEmpty ? "WLED" : info.name,
                ipAddress: ipAddress,
                isOnline: true,
                brightness: 0,
                currentColor: WLEDDevice.wledBootDefaultColor,
                temperature: nil,
                productType: .generic,
                location: .all,
                lastSeen: Date(),
                state: nil
            )
            
            completion(.success(wledDevice))
        } catch {
            logger.error("🚨 JSON parsing error for IP \(ipAddress): \(error)")
            completion(.failure(error))
        }
    }

    private var pendingDeviceUpdates: [WLEDDevice] = []
    private var deviceUpdateTimer: Timer?
    
    private func addOrUpdateDevice(_ device: WLEDDevice) {
        // Batch device updates to avoid flooding main queue
        syncQueue.async {
            self.pendingDeviceUpdates.append(device)
            
            // Schedule batched update if not already scheduled
            DispatchQueue.main.async {
                self.deviceUpdateTimer?.invalidate()
                self.deviceUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    self.flushPendingDeviceUpdates()
                }
            }
        }
    }
    
    private func flushPendingDeviceUpdates() {
        syncQueue.async {
            let updates = self.pendingDeviceUpdates
            self.pendingDeviceUpdates.removeAll()
            
            DispatchQueue.main.async {
                for device in updates {
                    if let index = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                        // Update existing device - preserve user-customized name
                        let existingName = self.discoveredDevices[index].name
                        let resolvedName = self.resolvedDeviceName(existing: existingName, incoming: device.name)
                        let resolvedAutoWhite = device.autoWhiteMode ?? self.discoveredDevices[index].autoWhiteMode
                        self.discoveredDevices[index] = WLEDDevice(
                            id: device.id,
                            name: resolvedName,
                            ipAddress: device.ipAddress,
                            isOnline: true,
                            brightness: device.brightness,
                            currentColor: device.currentColor,
                            autoWhiteMode: resolvedAutoWhite,
                            productType: device.productType,
                            location: self.discoveredDevices[index].location,
                            lastSeen: Date(),
                            state: device.state
                        )
                        self.logger.info("🔄 Updated device: \(existingName)")
                    } else if let index = self.discoveredDevices.firstIndex(where: { $0.ipAddress == device.ipAddress }) {
                        // Replace placeholder entries created from UDP/mDNS
                        let existingName = self.discoveredDevices[index].name
                        let resolvedName = self.resolvedDeviceName(existing: existingName, incoming: device.name)
                        let resolvedAutoWhite = device.autoWhiteMode ?? self.discoveredDevices[index].autoWhiteMode
                        self.discoveredDevices[index] = WLEDDevice(
                            id: device.id,
                            name: resolvedName,
                            ipAddress: device.ipAddress,
                            isOnline: true,
                            brightness: device.brightness,
                            currentColor: device.currentColor,
                            autoWhiteMode: resolvedAutoWhite,
                            productType: device.productType,
                            location: self.discoveredDevices[index].location,
                            lastSeen: Date(),
                            state: device.state
                        )
                        self.logger.info("🔄 Replaced placeholder for \(existingName)")
                    } else {
                        // Add new device
                        self.discoveredDevices.append(device)
                        self.logger.info("🎉 Added new device: \(device.name) at \(device.ipAddress)")
                    }
                    
                    // Notify the ViewModel
                    NotificationCenter.default.post(
                        name: NSNotification.Name("DeviceDiscovered"),
                        object: nil,
                        userInfo: ["deviceId": device.id, "isOnline": true]
                    )
                }
            }
        }
    }

    private func recordDiscoverySource(deviceId: String?, ipAddress: String?, source: String) {
        DispatchQueue.main.async {
            if let deviceId {
                self.lastDiscoverySourceByDevice[deviceId] = source
            }
            if let ipAddress {
                self.lastDiscoverySourceByIP[ipAddress] = source
            }
            self.lastDiscoveryTime = Date()
        }
    }

    private func isGenericDeviceName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        if lower == "wled" || lower == "wled-ap" || lower == "aesdetic-led" {
            return true
        }
        if lower.hasPrefix("wled-") {
            let suffix = lower.dropFirst(5)
            let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            let isHexOrNumeric = !suffix.isEmpty && suffix.unicodeScalars.allSatisfy { hexSet.contains($0) }
            if isHexOrNumeric { return true }
        }
        return false
    }

    private func resolvedDeviceName(existing: String, incoming: String) -> String {
        let existingTrimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingTrimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrimmed.isEmpty else {
            return existingTrimmed.isEmpty ? "WLED" : existingTrimmed
        }

        let existingGeneric = isGenericDeviceName(existingTrimmed)
        let incomingGeneric = isGenericDeviceName(incomingTrimmed)

        if existingGeneric && !incomingGeneric { return incomingTrimmed }
        if !existingGeneric && incomingGeneric { return existingTrimmed }
        return incomingTrimmed
    }
}

// MARK: - NWBrowser Handling

private extension WLEDDiscoveryService {
    func handleBrowserState(_ newState: NWBrowser.State) {
        switch newState {
        case .failed(let error):
            logger.error("NWBrowser failed: \(error.localizedDescription)")
            setDiscoveryError("mDNS discovery failed. Check Local Network permission and Wi-Fi.")
            browser?.cancel()
        case .ready:
            logger.info("NWBrowser ready for mDNS discovery")
        case .setup:
            logger.debug("NWBrowser setup")
        default:
            break
        }
    }

    func handleBrowseResults(_ results: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            if case .added(let result) = change {
                resolveService(for: result)
            }
        }
    }

    func resolveService(for result: NWBrowser.Result) {
        var macAddress: String?
        if case .bonjour(let txtRecord) = result.metadata {
            macAddress = txtRecord["mac"]
        }

        if case .service(let name, _, _, _) = result.endpoint {
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleConnectionState(state, connection: connection, name: name, macAddress: macAddress)
                }
            }
            connection.start(queue: browserQueue)
        }
    }

    func handleConnectionState(_ state: NWConnection.State, connection: NWConnection, name: String, macAddress: String?) {
        switch state {
        case .ready:
            if let innerEndpoint = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, _) = innerEndpoint {
                let remoteHost = "\(host)".split(separator: "%")[0]
                handleBonjourDiscovery(address: String(remoteHost), macAddress: macAddress, nameHint: name)
            }
            connection.cancel()
        case .failed:
            connection.cancel()
        case .cancelled:
            connection.cancel()
        default:
            break
        }
    }

    func handleBonjourDiscovery(address: String, macAddress: String?, nameHint: String) {
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAddress.isEmpty else { return }

        if let macAddress, !macAddress.isEmpty {
            Task {
                if let existing = await coreDataManager.fetchDevice(id: macAddress) {
                    var updated = existing
                    if updated.ipAddress != cleanAddress {
                        updated.ipAddress = cleanAddress
                    }
                    updated.isOnline = true
                    updated.lastSeen = Date()
                    recordDiscoverySource(deviceId: updated.id, ipAddress: updated.ipAddress, source: "mDNS")
                    addOrUpdateDevice(updated)
                    return
                }

                guard shouldStartQuickCheck(for: cleanAddress) else { return }
                addPlaceholderDevice(name: nameHint, ipAddress: cleanAddress, source: "mDNS")
                DispatchQueue.global().asyncAfter(deadline: .now() + deviceCheckInitialDelay) {
                    self.checkWLEDDevice(at: cleanAddress, allowRescan: true, bypassBanlist: true) { result in
                        self.handleDeviceCheckResult(result, source: "mDNS Full")
                    }
                }
            }
        } else {
            guard shouldStartQuickCheck(for: cleanAddress) else { return }
            addPlaceholderDevice(name: nameHint, ipAddress: cleanAddress, source: "mDNS")
            DispatchQueue.global().asyncAfter(deadline: .now() + deviceCheckInitialDelay) {
                self.checkWLEDDevice(at: cleanAddress, allowRescan: true, bypassBanlist: true) { result in
                    self.handleDeviceCheckResult(result, source: "mDNS Full")
                }
            }
        }
    }
}

// MARK: - Error Handling

private extension WLEDDiscoveryService {
    func setDiscoveryError(_ message: String) {
        let now = Date()
        if let last = lastErrorBroadcast, now.timeIntervalSince(last) < 20 { return }
        lastErrorBroadcast = now
        DispatchQueue.main.async {
            self.discoveryErrorMessage = message
            self.lastDiscoveryErrorDate = now
        }
    }
    
    func clearDiscoveryError() {
        DispatchQueue.main.async {
            self.discoveryErrorMessage = nil
        }
    }
}

// MARK: - Import necessary headers

import os.log
