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
    
    // Network discovery components
    private var netServiceBrowser: NetServiceBrowser?
    private var foundNetServices: [NetService] = []
    private var udpSocket: NWConnection?
    private var udpListener: NWListener?
    private var wasScanningBeforeBackground: Bool = false
    
    // Discovery configuration
    private let discoveryTimeout: TimeInterval = 5.0
    private let httpTimeout: TimeInterval = 1.0  // Faster timeout for quicker discovery
    private let maxConcurrentHTTPRequests = 5   // Balanced between 3 and 8 for better discovery
    private let failureTTL: TimeInterval = 15 * 60
    
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
            self.isScanning = true
            self.discoveredDevices.indices.forEach { self.discoveredDevices[$0].isOnline = false }
            self.discoveryProgress = "Initializing discovery..."
            self.syncQueue.async {
                self.scannedIPs.removeAll()
            }
        }
        
        startComprehensiveDiscovery()
    }
    
    func stopDiscovery() {
        guard isScanning else { return }
        
        logger.info("⏹️ Stopping WLED discovery")
        
        // Stop mDNS discovery
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        foundNetServices.removeAll()
        
        // Stop UDP discovery
        udpSocket?.cancel()
        udpSocket = nil
        udpListener?.cancel()
        udpListener = nil

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
        
        checkWLEDDevice(at: ipAddress) { result in
            self.handleDeviceCheckResult(result, source: "Manual")
        }
    }
    
    // MARK: - Comprehensive Discovery
    
    private func startComprehensiveDiscovery() {
        DispatchQueue.global(qos: .userInitiated).async {
            let discoveryGroup = DispatchGroup()
            
            // Method 1: mDNS/Bonjour Discovery
            discoveryGroup.enter()
            DispatchQueue.main.async {
                self.discoveryProgress = "Searching via mDNS..."
            }
            self.startmDNSDiscovery {
                discoveryGroup.leave()
            }
            
            // Method 2: UDP Broadcast Discovery
            discoveryGroup.enter()
            DispatchQueue.main.async {
                self.discoveryProgress = "Broadcasting UDP discovery..."
            }
            self.startUDPDiscovery {
                discoveryGroup.leave()
            }
            
            // Method 3: Comprehensive IP Range Scanning
            discoveryGroup.enter()
            DispatchQueue.main.async {
                self.discoveryProgress = "Scanning IP ranges..."
            }
            self.startComprehensiveIPScanning {
                discoveryGroup.leave()
            }
            
            // Wait for all discovery methods to complete OR auto-stop after finding devices
            discoveryGroup.notify(queue: .main) {
                self.logger.info("✅ Comprehensive discovery completed")
                self.isScanning = false
                self.discoveryProgress = "Discovery completed - found \(self.discoveredDevices.count) devices"
                self.lastDiscoveryTime = Date()
            }
            
            // Auto-stop discovery after finding devices (with a small delay to find more)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.discoveredDevices.count > 0 && self.isScanning {
                    self.logger.info("🎯 Auto-stopping discovery after finding \(self.discoveredDevices.count) devices")
                    self.stopDiscovery()
                }
            }
        }
    }
    
    // MARK: - mDNS/Bonjour Discovery
    
    private func startmDNSDiscovery(completion: @escaping () -> Void) {
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        
        // Search for WLED devices using common service types
        let serviceTypes = [
            "_http._tcp.",      // HTTP services
            "_wled._tcp.",      // WLED specific service
            "_arduino._tcp.",   // Arduino devices
            "_esp32._tcp."      // ESP32 devices
        ]
        
        let discoveryGroup = DispatchGroup()
        
        for serviceType in serviceTypes {
            discoveryGroup.enter()
            logger.info("🔍 Starting mDNS search for \(serviceType)")
            netServiceBrowser?.searchForServices(ofType: serviceType, inDomain: "local.")
            
            // Give each service type some time to respond
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                discoveryGroup.leave()
            }
        }
        
        // Complete mDNS discovery after timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + discoveryTimeout) {
            self.netServiceBrowser?.stop()
            completion()
        }
    }
    
    // MARK: - UDP Discovery
    
    private func startUDPDiscovery(completion: @escaping () -> Void) {
        // WLED devices respond to UDP discovery on port 21324
        let port: UInt16 = 21324
        
        // Create UDP connection for broadcasting
        let endpoint = NWEndpoint.hostPort(host: "255.255.255.255", port: NWEndpoint.Port(rawValue: port)!)
        let connection = NWConnection(to: endpoint, using: .udp)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.logger.info("📡 UDP discovery connection ready")
                self.sendUDPDiscoveryBroadcast(connection)
            case .failed(let error):
                self.logger.error("❌ UDP discovery failed: \(error)")
            default:
                break
            }
        }
        
        connection.start(queue: .global())
        udpSocket = connection
        
        // Also start UDP listener for responses
        startUDPListener()
        
        // Complete UDP discovery after timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + discoveryTimeout) {
            connection.cancel()
            self.udpSocket = nil
            completion()
        }
    }
    
    private func sendUDPDiscoveryBroadcast(_ connection: NWConnection) {
        // Send discovery packet that WLED devices recognize
        let discoveryMessage = "{\"v\":true}".data(using: .utf8)!
        
        connection.send(content: discoveryMessage, completion: .contentProcessed { error in
            if let error = error {
                self.logger.error("Failed to send UDP discovery: \(error)")
            } else {
                self.logger.info("📡 UDP discovery broadcast sent")
            }
        })
    }
    
    private func startUDPListener() {
        do {
            udpListener = try NWListener(using: .udp, on: 21324)
            udpListener?.newConnectionHandler = { connection in
                self.handleUDPConnection(connection)
            }
            udpListener?.start(queue: .global())
            logger.info("👂 UDP listener started on port 21324")
        } catch {
            logger.error("Failed to start UDP listener: \(error)")
        }
    }
    
    private func handleUDPConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
            if let data = data, let response = String(data: data, encoding: .utf8) {
                self.logger.info("📡 Received UDP response: \(response)")
                // Parse UDP response and extract device info
                self.parseUDPResponse(response, from: connection)
            }
        }
    }
    
    private func parseUDPResponse(_ response: String, from connection: NWConnection) {
        // Try to parse JSON response from WLED device
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any],
              let ip = info["ip"] as? String else {
            return
        }
        
        logger.info("📡 Found WLED device via UDP: \(ip)")
        checkWLEDDevice(at: ip) { result in
            self.handleDeviceCheckResult(result, source: "UDP")
        }
    }
    
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
    
    private func checkWLEDDevice(at ipAddress: String, completion: @escaping (Result<WLEDDevice, Error>) -> Void) {
        // Check if already scanned
        var alreadyScanned = false
        var isBanned = false
        syncQueue.sync {
            alreadyScanned = !scannedIPs.insert(ipAddress).inserted
            if let ts = failedIPBanlist[ipAddress], Date().timeIntervalSince(ts) < failureTTL {
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
            
            // Check for WLED-specific headers or content
            let isWLED = httpResponse.statusCode == 200 &&
                        (httpResponse.allHeaderFields.keys.contains { ($0 as? String)?.lowercased().contains("wled") == true } ||
                         data != nil)
            
            guard isWLED, let data = data else {
                // Not a WLED device - do not ban, just ignore
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
            let colors = firstSegment?.colors?.first ?? [0, 0, 0]
            let red = colors.count > 0 ? colors[0] : 0
            let green = colors.count > 1 ? colors[1] : 0
            let blue = colors.count > 2 ? colors[2] : 0
            
            let currentColor = Color(.sRGB, 
                                   red: Double(red) / 255.0, 
                                   green: Double(green) / 255.0, 
                                   blue: Double(blue) / 255.0, 
                                   opacity: state.isOn ? 1.0 : 0.5)

            let wledDevice = WLEDDevice(
                id: info.mac,
                name: "Aesdetic-LED",
                ipAddress: ipAddress,
                isOnline: true,
                brightness: state.brightness,
                currentColor: currentColor,
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
                        self.discoveredDevices[index] = WLEDDevice(
                            id: device.id,
                            name: existingName,
                            ipAddress: device.ipAddress,
                            isOnline: true,
                            brightness: device.brightness,
                            currentColor: device.currentColor,
                            productType: device.productType,
                            location: self.discoveredDevices[index].location,
                            lastSeen: Date(),
                            state: device.state
                        )
                        self.logger.info("🔄 Updated device: \(existingName)")
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
        logger.info("🔍 Found service: \(service.name) of type \(service.type)")
        foundNetServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        // Error -72008 (kCFNetServiceErrorNotFound) is normal when no mDNS services are found
        let errorCode = errorDict["NSNetServicesErrorCode"]?.intValue ?? 0
        if errorCode == -72008 {
            logger.debug("mDNS search completed (no services found) - this is normal")
        } else {
            logger.error("❌ NetService search failed: \(errorDict)")
        }
    }
}

// MARK: - NetServiceDelegate

extension WLEDDiscoveryService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        
        for address in addresses {
            let ip = getIPString(from: address)
            if !ip.isEmpty && ip.contains(".") {
                logger.info("🔍 Resolved mDNS service \(sender.name) to IP: \(ip)")
                
                // Check if this could be a WLED device
                let name = sender.name.lowercased()
                let type = sender.type.lowercased()
                
                if name.contains("wled") || name.contains("led") || name.contains("light") || 
                   type.contains("wled") || name.contains("esp") || name.contains("arduino") {
                    checkWLEDDevice(at: ip) { result in
                        self.handleDeviceCheckResult(result, source: "mDNS")
                    }
                }
            }
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        logger.debug("Failed to resolve service: \(sender.name)")
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