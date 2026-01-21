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
import SystemConfiguration.CaptiveNetwork
import os.log

@available(iOS 14.0, *)
class WLEDDiscoveryService: NSObject, ObservableObject {
    @Published var discoveredDevices: [WLEDDevice] = []
    @Published var isScanning: Bool = false
    @Published var discoveryProgress: String = ""
    @Published var lastDiscoveryTime: Date?
    
    private var session: URLSession
    private var scannedIPs = Set<String>()
    private let syncQueue = DispatchQueue(label: "wled.discovery.sync")
    private let logger = os.Logger(subsystem: "com.aesdetic.control", category: "Discovery")
    private var failedIPBanlist: [String: Date] = [:]
    private var deviceCountAtScanStart: Int = 0  // Track device count at start of scan
    private var discoveryStartTime: Date?
    private var fallbackScanWorkItem: DispatchWorkItem?
    
    // Network discovery components
    private var netServiceBrowsers: [NetServiceBrowser] = []
    private var netServiceBrowserTypes: [ObjectIdentifier: String] = [:]
    private var foundNetServices: [NetService] = []
    private var wasScanningBeforeBackground: Bool = false
    private var isPassiveListening: Bool = false
    private var udpListener: NWListener?
    private let udpQueue = DispatchQueue(label: "wled.discovery.udp")
    private var lastDiscoveryCheck: [String: Date] = [:]
    
    // Discovery configuration (aligned with WLED's approach)
    private let mDNSDiscoveryTimeout: TimeInterval = 4.0  // mDNS is fast, shorter timeout
    private let ipScanTimeout: TimeInterval = 8.0  // IP scanning takes longer
    private let httpTimeout: TimeInterval = 1.0  // Faster timeout for quicker discovery
    private let maxConcurrentHTTPRequests = 5   // Balanced between 3 and 8 for better discovery
    private let failureTTL: TimeInterval = 15 * 60
    private let udpPort: UInt16 = 21324
    private let udpPacketMinLength = 40
    private let udpCheckCooldown: TimeInterval = 20.0
    private let passiveDiscoveryWindow: TimeInterval = 30.0
    private let minimumDiscoveryDuration: TimeInterval = 30.0
    
    // Semaphore for controlling concurrent HTTP requests
    private let httpSemaphore: DispatchSemaphore

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
        httpSemaphore = DispatchSemaphore(value: maxConcurrentHTTPRequests)
        
        super.init()
        logger.info("🏠 WLEDDiscoveryService initialized with enhanced discovery capabilities")
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - App Lifecycle
    @objc private func appDidEnterBackground() {
        syncQueue.async { self.wasScanningBeforeBackground = self.isScanning }
        if isScanning { stopDiscovery() }
    }
    
    @objc private func appDidBecomeActive() {
        var shouldResume = false
        syncQueue.sync {
            shouldResume = wasScanningBeforeBackground
            wasScanningBeforeBackground = false
        }
        if shouldResume { startDiscovery() }
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
            // Track device count at start to detect NEW devices found during this scan
            self.deviceCountAtScanStart = self.discoveredDevices.count
            self.discoveryStartTime = Date()
            self.isScanning = true
            self.discoveredDevices.indices.forEach { self.discoveredDevices[$0].isOnline = false }
            self.discoveryProgress = "Initializing discovery..."
            self.syncQueue.async {
                self.scannedIPs.removeAll()
                self.failedIPBanlist.removeAll()
                self.lastDiscoveryCheck.removeAll()
            }
        }
        
        startComprehensiveDiscovery()
    }

    func startPassiveDiscovery() {
        guard !isPassiveListening else { return }
        isPassiveListening = true

        DispatchQueue.main.async {
            self.discoveryProgress = "Listening for WLED broadcasts..."
        }

        startUDPListener()
        DispatchQueue.main.async {
            self.startmDNSDiscovery()
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
            netServiceBrowsers.forEach { $0.stop() }
            netServiceBrowsers.removeAll()
            netServiceBrowserTypes.removeAll()
            foundNetServices.removeAll()
            stopUDPListener()
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
            // WLED devices are passive: listen first, then fall back to scanning only if needed.
            DispatchQueue.main.async {
                self.discoveryProgress = "Listening for WLED broadcasts..."
            }
            
            self.startUDPListener()
            DispatchQueue.main.async {
                self.startmDNSDiscovery()
            }
            self.scheduleFallbackScan()
        }
    }
    
    // MARK: - mDNS/Bonjour Discovery (WLED's Primary Method)
    
    private func startmDNSDiscovery() {
        // WLED's official service type is "_wled._tcp."
        // Also search for generic HTTP services as fallback (some WLED devices may not register _wled._tcp.)
        let serviceTypes = [
            "_wled._tcp.",      // WLED's official mDNS service type (prioritized)
            "_http._tcp."       // Generic HTTP fallback for devices that don't register _wled._tcp.
        ]
        
        logger.info("🔍 Starting mDNS discovery for WLED devices...")
        netServiceBrowsers.forEach { $0.stop() }
        netServiceBrowsers.removeAll()
        netServiceBrowserTypes.removeAll()

        for serviceType in serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.includesPeerToPeer = true
            browser.schedule(in: .main, forMode: .default)
            netServiceBrowsers.append(browser)
            netServiceBrowserTypes[ObjectIdentifier(browser)] = serviceType
            logger.info("🔍 Searching for \(serviceType)")
            browser.searchForServices(ofType: serviceType, inDomain: "local.")
        }
        
        // Keep browser active during discovery to catch late arrivals
    }

    // MARK: - UDP Discovery

    private func startUDPListener() {
        guard udpListener == nil else { return }
        do {
            let port = NWEndpoint.Port(rawValue: udpPort) ?? 21324
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)

            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.logger.error("❌ UDP listener failed: \(error.localizedDescription)")
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleUDPConnection(connection)
            }
            listener.start(queue: udpQueue)
            udpListener = listener
            logger.info("📡 UDP listener started on port \(self.udpPort)")
        } catch {
            logger.error("❌ Failed to start UDP listener: \(error.localizedDescription)")
        }
    }

    private func stopUDPListener() {
        udpListener?.cancel()
        udpListener = nil
    }

    private func handleUDPConnection(_ connection: NWConnection) {
        connection.start(queue: udpQueue)
        receiveUDPMessage(on: connection)
    }

    private func receiveUDPMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.handleUDPPacket(data)
            }
            if error == nil {
                self.receiveUDPMessage(on: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func handleUDPPacket(_ data: Data) {
        guard data.count >= udpPacketMinLength else { return }
        let bytes = [UInt8](data)
        guard bytes[0] == 255, bytes[1] == 1 else { return }

        let ipAddress = "\(bytes[2]).\(bytes[3]).\(bytes[4]).\(bytes[5])"
        let nameData = data.subdata(in: 6..<38)
        let name = String(decoding: nameData, as: UTF8.self).split(separator: "\0").first.map(String.init) ?? "WLED"

        guard shouldStartQuickCheck(for: ipAddress) else { return }
        logger.info("📡 UDP broadcast from \(name) at \(ipAddress)")
        addPlaceholderDevice(name: name, ipAddress: ipAddress, source: "UDP")
        checkWLEDDevice(at: ipAddress, allowRescan: true, bypassBanlist: true) { result in
            self.handleDeviceCheckResult(result, source: "UDP Full")
        }
    }

    // MARK: - AP Mode Quick Check

    private func checkAPModeDefaults() {
        let localIPs = getCurrentDeviceIPs()
        let isAPSubnet = localIPs.contains { $0.hasPrefix("192.168.4.") }
        guard isAPSubnet else {
            logger.debug("Skipping AP mode check (not on 192.168.4.x subnet)")
            return
        }

        let apAddresses = ["192.168.4.1"]
        for ip in apAddresses {
            checkWLEDDevice(at: ip, allowRescan: true, bypassBanlist: true) { result in
                self.handleDeviceCheckResult(result, source: "AP Mode")
            }
        }
    }

    private func scheduleFallbackScan() {
        fallbackScanWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isScanning else { return }
            let newDevicesFound = self.discoveredDevices.count - self.deviceCountAtScanStart
            if newDevicesFound == 0 {
                self.logger.info("📡 No new devices found via UDP/mDNS, starting IP scan fallback...")
                DispatchQueue.main.async {
                    self.discoveryProgress = "Scanning IP ranges (fallback)..."
                }
                self.startComprehensiveIPScanning {
                    self.finishDiscovery()
                }
            } else {
                self.finishDiscovery()
            }
        }
        fallbackScanWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + passiveDiscoveryWindow, execute: workItem)
    }

    private func shouldStartQuickCheck(for ipAddress: String) -> Bool {
        var shouldCheck = false
        syncQueue.sync {
            let now = Date()
            if let lastSeen = lastDiscoveryCheck[ipAddress], now.timeIntervalSince(lastSeen) < udpCheckCooldown {
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
                self.netServiceBrowsers.forEach { $0.stop() }
                self.netServiceBrowsers.removeAll()
                self.netServiceBrowserTypes.removeAll()
                self.foundNetServices.removeAll()
                self.stopUDPListener()
            }
        }
    }
    
    // Note: UDP port 21324 is used by WLED for node broadcasts; apps can listen for discovery.
    
    // MARK: - Comprehensive IP Scanning
    
    private func startComprehensiveIPScanning(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Limit to current device subnets only to avoid massive sweeps
            let networkRanges = self.getNetworkRanges().prefix(2)
            let scanGroup = DispatchGroup()
            
            self.logger.info("🔍 Starting IP scan on \(networkRanges.count) network ranges")
            self.logger.info("📡 Scanning IP ranges: \(networkRanges)")
            self.logger.info("⚙️ Using \(self.maxConcurrentHTTPRequests) concurrent requests with \(self.httpTimeout)s timeout")
            
            for networkRange in networkRanges {
                scanGroup.enter()
                self.scanIPRange(networkRange) {
                    scanGroup.leave()
                }
            }
            
            scanGroup.notify(queue: .main) {
                self.logger.info("✅ IP range scanning completed - found \(self.discoveredDevices.count) devices total")
                completion()
            }
        }
    }
    
    private func getNetworkRanges() -> [String] {
        var ranges: [String] = []
        
        // Get current device's IP to determine network ranges
        let currentIPs = getCurrentDeviceIPs()
        for ip in currentIPs {
            let networkBase = getNetworkBase(from: ip)
            if !ranges.contains(networkBase) {
                ranges.append(networkBase)
            }
        }
        
        // Remove large hard-coded ranges to prevent excessive scanning
        
        logger.info("📊 Will scan \(ranges.count) network ranges: \(ranges)")
        return ranges
    }

    // Removed setSession helper; session is now a var and directly reassigned.
    
    private func getCurrentDeviceIPs() -> [String] {
        var ips: [String] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return ips }
        guard let firstAddr = ifaddr else { return ips }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.starts(with: "en") || name.starts(with: "bridge") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && ip != "0.0.0.0" {
                        ips.append(ip)
                    }
                }
            }
        }
        
        freeifaddrs(ifaddr)
        return ips
    }
    
    private func getNetworkBase(from ip: String) -> String {
        let components = ip.components(separatedBy: ".")
        if components.count >= 3 {
            return "\(components[0]).\(components[1]).\(components[2])"
        }
        return ip
    }
    
    private func scanIPRange(_ networkBase: String, completion: @escaping () -> Void) {
        let scanGroup = DispatchGroup()
        
        // Full IP sweep (1-254) with intelligent auto-stop when devices are found
        for i in 1...254 {
            let ipAddress = "\(networkBase).\(i)"
            
            scanGroup.enter()
            httpSemaphore.wait() // Control concurrent requests
            
            // Allow cancellation during long scans or when devices are found
            if !self.isScanning {
                self.httpSemaphore.signal()
                scanGroup.leave()
                continue
            }

            // No delay needed - let semaphore control the flow
            self.checkWLEDDevice(at: ipAddress) { result in
                self.handleDeviceCheckResult(result, source: "IP Scan")
                self.httpSemaphore.signal()
                scanGroup.leave()
            }
        }
        
        scanGroup.notify(queue: .global()) {
            completion()
        }
    }
    
    // MARK: - Device Checking and Parsing
    
    private func handleDeviceCheckResult(_ result: Result<WLEDDevice, Error>, source: String) {
        switch result {
        case .success(let device):
            logger.info("🎉 Found WLED device via \(source): \(device.name) at \(device.ipAddress)")
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
            currentColor: .black,
            productType: .generic,
            location: .all,
            lastSeen: Date(),
            state: nil
        )
        logger.info("⚡️ Quick discovery via \(source): \(displayName) at \(ipAddress)")
        addOrUpdateDevice(placeholder)
    }
    
    private func checkWLEDDevice(at ipAddress: String, allowRescan: Bool = false, bypassBanlist: Bool = false, completion: @escaping (Result<WLEDDevice, Error>) -> Void) {
        // Check if already scanned
        var alreadyScanned = false
        var isBanned = false
        syncQueue.sync {
            if allowRescan {
                _ = scannedIPs.insert(ipAddress)
            } else {
                alreadyScanned = !scannedIPs.insert(ipAddress).inserted
            }
            if !bypassBanlist, let ts = failedIPBanlist[ipAddress], Date().timeIntervalSince(ts) < failureTTL {
                isBanned = true
            }
        }
        
        if alreadyScanned || isBanned {
            completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already scanned"])))
            return
        }
        
        let urlString = "http://\(ipAddress)/json"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = httpTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WLED-Discovery/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("close", forHTTPHeaderField: "Connection")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                // Fast-ban endpoints that timeout/unreachable to avoid energy drains
                let nserr = error as NSError
                if nserr.domain == NSURLErrorDomain && (nserr.code == NSURLErrorTimedOut || nserr.code == NSURLErrorCannotConnectToHost || nserr.code == NSURLErrorNetworkConnectionLost || nserr.code == NSURLErrorCannotFindHost) {
                    self.syncQueue.async {
                        self.failedIPBanlist[ipAddress] = Date()
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
            
            // Try to parse as WLED JSON to verify it's actually a WLED device
            // This prevents false positives from other HTTP servers
            do {
                let testParse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard testParse?["state"] != nil || testParse?["info"] != nil else {
                    completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a WLED device"])))
                    return
                }
            } catch {
                completion(.failure(NSError(domain: "WLEDDiscovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a WLED device"])))
                return
            }
            
            self.parseWLEDResponse(from: data, ipAddress: ipAddress, completion: completion)
        }.resume()
    }
    
    private func parseWLEDResponse(from data: Data, ipAddress: String, completion: @escaping (Result<WLEDDevice, Error>) -> Void) {
        do {
            let wledData = try JSONDecoder().decode(WLEDResponse.self, from: data)
            let info = wledData.info
            let state = wledData.state
            
            // Extract color information
            let firstSegment = state.segments.first
            let baseColor: Color
            if let normalized = firstSegment?.cctNormalized {
                baseColor = Color.color(fromCCTTemperature: normalized)
            } else if let colors = firstSegment?.colors?.first, colors.count >= 3 {
                baseColor = Color.color(fromRGBArray: colors)
            } else {
                baseColor = .black
            }
            let currentColor = baseColor.opacity(state.isOn ? 1.0 : 0.5)

            let wledDevice = WLEDDevice(
                id: info.mac,
                name: info.name.isEmpty ? "Aesdetic-LED" : info.name,  // Use WLED's device name, fallback to default
                ipAddress: ipAddress,
                isOnline: true,
                brightness: state.brightness,
                currentColor: currentColor,
                temperature: firstSegment?.cctNormalized,
                productType: .generic,
                location: .all,
                lastSeen: Date(),
                state: state
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
                        let resolvedAutoWhite = device.autoWhiteMode ?? self.discoveredDevices[index].autoWhiteMode
                        self.discoveredDevices[index] = WLEDDevice(
                            id: device.id,
                            name: existingName,
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
                        let resolvedAutoWhite = device.autoWhiteMode ?? self.discoveredDevices[index].autoWhiteMode
                        self.discoveredDevices[index] = WLEDDevice(
                            id: device.id,
                            name: existingName,
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
}

// MARK: - NetServiceBrowserDelegate

extension WLEDDiscoveryService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        logger.info("🔍 Found mDNS service: \(service.name) of type \(service.type)")
        foundNetServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        // Error -72008 (kCFNetServiceErrorNotFound) is normal when no mDNS services are found
        let errorCode = errorDict["NSNetServicesErrorCode"]?.intValue ?? 0
        let serviceType = netServiceBrowserTypes[ObjectIdentifier(browser)] ?? "unknown"
        if errorCode == -72008 {
            logger.debug("mDNS search completed for \(serviceType) (no services found) - this is normal")
        } else {
            logger.error("❌ NetService search failed for \(serviceType): \(errorDict)")
        }
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        logger.debug("mDNS browser stopped")
    }
}

// MARK: - NetServiceDelegate

extension WLEDDiscoveryService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        
        for address in addresses {
            let ip = getIPString(from: address)
            if !ip.isEmpty && ip.contains(".") {
                let name = sender.name.lowercased()
                let type = sender.type.lowercased()
                
                // WLED devices register with "_wled._tcp." service type
                // Also check for devices with WLED-related names or generic HTTP services
                let isWLEDService = type.contains("wled") || 
                                   name.contains("wled") || 
                                   name.contains("led") || 
                                   name.contains("light") ||
                                   name.contains("esp") ||
                                   name.contains("arduino")
                
                if isWLEDService {
                    logger.info("🔍 Resolved mDNS service '\(sender.name)' (\(type)) to IP: \(ip)")
                    guard shouldStartQuickCheck(for: ip) else { return }
                    addPlaceholderDevice(name: sender.name, ipAddress: ip, source: "mDNS")
                    checkWLEDDevice(at: ip, allowRescan: true, bypassBanlist: true) { result in
                        self.handleDeviceCheckResult(result, source: "mDNS Full")
                    }
                } else {
                    logger.debug("Skipping non-WLED mDNS service: \(sender.name) (\(type))")
                }
            }
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let errorCode = errorDict["NSNetServicesErrorCode"]?.intValue ?? 0
        if errorCode != 0 {
            logger.debug("Failed to resolve mDNS service '\(sender.name)': error \(errorCode)")
        }
    }
    
    private func getIPString(from address: Data) -> String {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        
        let result = address.withUnsafeBytes { bytes in
            getnameinfo(bytes.bindMemory(to: sockaddr.self).baseAddress, socklen_t(address.count),
                       &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
        }
        
        if result == 0 {
            return String(cString: hostname)
        }
        return ""
    }
}

// MARK: - Import necessary headers

import os.log
