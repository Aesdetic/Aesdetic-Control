//
//  WiFiSetupView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI
import Network
import SystemConfiguration.CaptiveNetwork

struct WiFiSetupView: View {
    let device: WLEDDevice
    @ObservedObject private var viewModel = DeviceControlViewModel.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var availableNetworks: [WiFiNetwork] = []
    @State private var isScanning: Bool = false
    @State private var selectedNetwork: WiFiNetwork?
    @State private var password: String = ""
    @State private var isConnecting: Bool = false
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var showPasswordField: Bool = false
    @State private var currentWiFiInfo: WiFiInfo?
    @State private var showFullNetworkList: Bool = false
    
    enum ConnectionStatus: Equatable {
        case idle
        case scanning
        case connecting
        case connected
        case failed(String)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Enhanced thin material with heavy blur for contrast - matching DeviceDetailView
                LiquidGlassOverlay(
                    blurOpacity: 0.65,  // Slightly reduced blur for better visibility
                    highlightOpacity: 0.18,
                    verticalTopOpacity: 0.08,
                    verticalBottomOpacity: 0.08,
                    vignetteOpacity: 0.12,
                    centerSheenOpacity: 0.06
                )
                .overlay(
                    // Add subtle grain texture
                    RoundedRectangle(cornerRadius: 0)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.01),
                                    Color.black.opacity(0.01),
                                    Color.white.opacity(0.015),
                                    Color.black.opacity(0.005)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .allowsHitTesting(false)
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Current WiFi Status
                        currentWiFiStatusCard
                        
                        // Available Networks
                        availableNetworksCard
                        
                        // Connection Status
                        if isConnecting || connectionStatus != .idle {
                            connectionStatusCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("WiFi Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .settingsForegroundStyle(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Scan") {
                        scanForNetworks()
                    }
                    .settingsForegroundStyle(.primary)
                    .disabled(isScanning)
                }
            }
            .task {
                await loadCurrentWiFiInfo()
                scanForNetworks()
            }
        }
    }
    
    // MARK: - Current WiFi Status Card
    
    private var currentWiFiStatusCard: some View {
        SettingsCard(title: "Current WiFi") {
            VStack(spacing: 12) {
                if let wifiInfo = currentWiFiInfo {
                    InfoRow(label: "SSID", value: wifiInfo.ssid)
                    InfoRow(label: "Signal", value: "\(wifiInfo.signalStrength) dBm")
                    InfoRow(label: "Channel", value: "\(wifiInfo.channel)")
                    InfoRow(label: "Security", value: wifiInfo.security)
                    
                    // Helpful note about WiFi disconnection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("💡 To disconnect from WiFi:")
                            .font(AppTypography.style(.caption, weight: .medium))
                            .settingsForegroundStyle(.secondary)
                        Text("Connect to a different network below")
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    
                    Button("Refresh") {
                        Task { 
                            await loadCurrentWiFiInfo()
                            // Also refresh the network list
                            scanForNetworks()
                        }
                    }
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.white.opacity(0.18))
                    .cornerRadius(10)
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading WiFi information...")
                            .settingsForegroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Available Networks Card
    
    private var availableNetworksCard: some View {
        SettingsCard(title: "Available Networks") {
            VStack(spacing: 12) {
                if isScanning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning for networks...")
                            .settingsForegroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                } else if availableNetworks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(AppTypography.style(.title, weight: .medium))
                            .settingsForegroundStyle(.secondary)
                        Text("No networks found")
                            .settingsForegroundStyle(.secondary)
                        Text("Tap 'Scan' to search for WiFi networks")
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(visibleAvailableNetworks, id: \.id) { network in
                        VStack(spacing: 0) {
                            WiFiNetworkRow(
                                network: network,
                                isSelected: selectedNetwork?.id == network.id,
                                onSelect: { selectNetwork(network) }
                            )
                            
                            // Password field and connect button - right below selected network
                            if selectedNetwork?.id == network.id {
                                VStack(spacing: 12) {
                                    Divider()
                                        .background(Color.white.opacity(0.2))
                                    
                                    if network.security == "Open" {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Open Network")
                                                .font(AppTypography.style(.subheadline, weight: .medium))
                                                .settingsForegroundStyle(.primary)
                                            
                                            Text("No password required for \(network.ssid)")
                                                .font(AppTypography.style(.caption))
                                                .settingsForegroundStyle(.secondary)
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Password for \(network.ssid)")
                                                .font(AppTypography.style(.subheadline, weight: .medium))
                                                .settingsForegroundStyle(.primary)
                                            
                                            SecureField("Enter WiFi password", text: $password)
                                                .textFieldStyle(PlainTextFieldStyle())
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 16)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.white.opacity(0.1))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                        )
                                                )
                                                .settingsForegroundStyle(.primary)
                                        }
                                    }
                                    
                                    Button(action: connectToNetwork) {
                                        HStack {
                                            if isConnecting {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .settingsForegroundStyle(.primary)
                                            }
                                            Text(isConnecting ? "Connecting..." : "Connect")
                                                .font(AppTypography.style(.headline, weight: .semibold))
                                                .settingsForegroundStyle(.primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.white.opacity(0.18))
                                        .cornerRadius(10)
                                    }
                                    .disabled(isConnecting || (network.security != "Open" && password.isEmpty))
                                }
                                .padding(.top, 8)
                            }
                        }
                    }

                    if availableNetworks.count > compactNetworkListLimit {
                        Button(showFullNetworkList ? "Show Fewer Networks" : "Show All \(availableNetworks.count) Networks") {
                            showFullNetworkList.toggle()
                        }
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var compactNetworkListLimit: Int { 3 }

    private var visibleAvailableNetworks: [WiFiNetwork] {
        guard !showFullNetworkList, availableNetworks.count > compactNetworkListLimit else {
            return availableNetworks
        }
        return Array(availableNetworks.prefix(compactNetworkListLimit))
    }
    
    // MARK: - Connection Status Card
    
    private var connectionStatusCard: some View {
        SettingsCard(title: "Connection Status") {
            VStack(spacing: 12) {
                switch connectionStatus {
                case .idle:
                    EmptyView()
                    
                case .scanning:
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning for networks...")
                            .settingsForegroundStyle(.secondary)
                    }
                    
                case .connecting:
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting to \(selectedNetwork?.ssid ?? "network")...")
                            .settingsForegroundStyle(.secondary)
                    }
                    
                case .connected:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .settingsForegroundStyle(.primary)
                        Text("Successfully connected!")
                            .settingsForegroundStyle(.primary)
                    }
                    
                case .failed(let error):
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .settingsForegroundStyle(.primary)
                            Text("Connection failed")
                                .settingsForegroundStyle(.primary)
                        }
                        Text(error)
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func scanForNetworks() {
        isScanning = true
        connectionStatus = .scanning
        showFullNetworkList = false
        
        Task {
            do {
                let networks = try await WLEDWiFiService.shared.scanForNetworks(device: device)
                await MainActor.run {
                    self.availableNetworks = networks
                    self.isScanning = false
                    self.connectionStatus = .idle
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.connectionStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    private func selectNetwork(_ network: WiFiNetwork) {
        selectedNetwork = network
        showPasswordField = network.security != "Open"
        password = ""
    }
    
    private func connectToNetwork() {
        guard let network = selectedNetwork else { return }
        
        isConnecting = true
        connectionStatus = .connecting
        
        Task {
            do {
                let outcome = await WLEDSafeWiFiChangeService.shared.changeNetwork(
                    device: device,
                    network: network,
                    password: password.isEmpty ? nil : password,
                    viewModel: viewModel
                )
                guard case .verified = outcome else {
                    throw WiFiError.networkError(outcome.failureMessage ?? "The new Wi-Fi could not be verified.")
                }
                
                await MainActor.run {
                    self.isConnecting = false
                    self.connectionStatus = .connected
                    // Clear password field after successful connection
                    self.password = ""
                    // Refresh WiFi info after successful connection
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        await self.loadCurrentWiFiInfo()
                        // Clear success message after 3 seconds
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        await MainActor.run {
                            self.connectionStatus = .idle
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.connectionStatus = .failed(error.localizedDescription)
                    // Clear error message after 5 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        await MainActor.run {
                            self.connectionStatus = .idle
                        }
                    }
                }
            }
        }
    }
    
    
    private func loadCurrentWiFiInfo() async {
        do {
            let wifiInfo = try await WLEDWiFiService.shared.getCurrentWiFiInfo(device: device)
            await MainActor.run {
                if let previous = self.currentWiFiInfo,
                   isUnknownSSID(wifiInfo.ssid),
                   !isUnknownSSID(previous.ssid) {
                    self.currentWiFiInfo = WiFiInfo(
                        ssid: previous.ssid,
                        signalStrength: wifiInfo.signalStrength,
                        channel: wifiInfo.channel,
                        security: isUnknownSSID(wifiInfo.security) ? previous.security : wifiInfo.security,
                        ipAddress: wifiInfo.ipAddress ?? previous.ipAddress,
                        macAddress: wifiInfo.macAddress ?? previous.macAddress,
                        bssid: wifiInfo.bssid ?? previous.bssid,
                        firmwareVersion: wifiInfo.firmwareVersion ?? previous.firmwareVersion
                    )
                } else {
                    self.currentWiFiInfo = wifiInfo
                }
            }
        } catch {
            // Preserve last known value during transient connectivity changes.
        }
    }

    private func isUnknownSSID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("unknown") == .orderedSame
    }
}

// MARK: - WiFi Network Row

struct WiFiNetworkRow: View {
    let network: WiFiNetwork
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Signal strength icon
                Image(systemName: signalStrengthIcon)
                    .foregroundColor(signalStrengthColor)
                    .font(AppTypography.style(.headline))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(network.ssid)
                        .settingsForegroundStyle(.primary)
                        .font(AppTypography.style(.headline))
                    
                    HStack(spacing: 8) {
                        Text(network.security)
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                        
                        Text("\(network.signalStrength) dBm")
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                        
                        if network.channel > 0 {
                            Text("Ch \(network.channel)")
                                .font(AppTypography.style(.caption))
                                .settingsForegroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .settingsForegroundStyle(.primary)
                        .font(AppTypography.style(.headline))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var signalStrengthIcon: String {
        switch network.signalStrength {
        case -30...0:
            return "wifi"
        case -50..<(-30):
            return "wifi"
        case -70..<(-50):
            return "wifi"
        default:
            return "wifi"
        }
    }
    
    private var signalStrengthColor: Color {
        switch network.signalStrength {
        case -30...0:
            return .green
        case -50..<(-30):
            return .yellow
        case -70..<(-50):
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - Data Models

struct WiFiNetwork: Identifiable, Codable {
    let id = UUID()
    let ssid: String
    let signalStrength: Int
    let security: String
    let channel: Int
    let bssid: String?
    
    enum CodingKeys: String, CodingKey {
        case ssid, signalStrength, security, channel, bssid
    }
}

struct WiFiInfo: Codable {
    let ssid: String
    let signalStrength: Int
    let channel: Int
    let security: String
    let ipAddress: String?
    let macAddress: String?
    let bssid: String?
    let firmwareVersion: String?
}

struct WLEDNetworkOption: Equatable, Identifiable {
    let value: Int
    let label: String

    var id: Int { value }
}

struct WLEDNetworkConfiguration: Equatable {
    static let apBehaviorOptions: [WLEDNetworkOption] = [
        WLEDNetworkOption(value: 0, label: "No connection after boot"),
        WLEDNetworkOption(value: 1, label: "Disconnected"),
        WLEDNetworkOption(value: 2, label: "Always"),
        WLEDNetworkOption(value: 3, label: "Never (not recommended)"),
        WLEDNetworkOption(value: 4, label: "Temporary (no connection after boot)")
    ]

    static let txPowerOptions: [WLEDNetworkOption] = [
        WLEDNetworkOption(value: 78, label: "19.5 dBm"),
        WLEDNetworkOption(value: 76, label: "19 dBm"),
        WLEDNetworkOption(value: 74, label: "18.5 dBm"),
        WLEDNetworkOption(value: 68, label: "17 dBm"),
        WLEDNetworkOption(value: 60, label: "15 dBm"),
        WLEDNetworkOption(value: 52, label: "13 dBm"),
        WLEDNetworkOption(value: 44, label: "11 dBm"),
        WLEDNetworkOption(value: 34, label: "8.5 dBm"),
        WLEDNetworkOption(value: 28, label: "7 dBm"),
        WLEDNetworkOption(value: 20, label: "5 dBm"),
        WLEDNetworkOption(value: 8, label: "2 dBm")
    ]

    var mdnsName: String
    var stationSSID: String
    var staticIP: String
    var staticGateway: String
    var staticSubnet: String
    var dnsServer: String
    var apSSID: String
    var apPassword: String
    var apPasswordConfigured: Bool
    var hideAP: Bool
    var apChannel: Int
    var apBehavior: Int
    var disableWiFiSleep: Bool
    var force80211g: Bool
    var txPower: Int

    init(
        mdnsName: String = "",
        stationSSID: String = "",
        staticIP: String = "0.0.0.0",
        staticGateway: String = "0.0.0.0",
        staticSubnet: String = "255.255.255.0",
        dnsServer: String = "0.0.0.0",
        apSSID: String = "",
        apPassword: String = "",
        apPasswordConfigured: Bool = false,
        hideAP: Bool = false,
        apChannel: Int = 1,
        apBehavior: Int = 0,
        disableWiFiSleep: Bool = false,
        force80211g: Bool = false,
        txPower: Int = 78
    ) {
        self.mdnsName = mdnsName
        self.stationSSID = stationSSID
        self.staticIP = staticIP
        self.staticGateway = staticGateway
        self.staticSubnet = staticSubnet
        self.dnsServer = dnsServer
        self.apSSID = apSSID
        self.apPassword = apPassword
        self.apPasswordConfigured = apPasswordConfigured
        self.hideAP = hideAP
        self.apChannel = apChannel
        self.apBehavior = apBehavior
        self.disableWiFiSleep = disableWiFiSleep
        self.force80211g = force80211g
        self.txPower = txPower
    }

    var normalizedMDNSName: String {
        Self.normalizeMDNSName(mdnsName)
    }

    var validationIssues: [String] {
        var issues: [String] = []

        if !isValidHostnamePart(mdnsName) {
            issues.append("mDNS must be empty or a valid .local host name.")
        }
        if !isValidIPv4(staticIP) {
            issues.append("Static IP must be four numbers from 0 to 255.")
        }
        if !isValidIPv4(staticGateway) {
            issues.append("Gateway must be four numbers from 0 to 255.")
        }
        if !isValidIPv4(staticSubnet) {
            issues.append("Subnet must be four numbers from 0 to 255.")
        }
        if !isValidIPv4(dnsServer) {
            issues.append("DNS must be four numbers from 0 to 255.")
        }
        if apSSID.trimmingCharacters(in: .whitespacesAndNewlines).count > 32 {
            issues.append("Fallback hotspot name must be 32 characters or fewer.")
        }
        if !apPassword.isEmpty && !(8...63).contains(apPassword.count) {
            issues.append("Fallback hotspot password must be empty to preserve it or 8-63 characters to replace it.")
        }
        if !(1...13).contains(apChannel) {
            issues.append("Fallback hotspot channel must be 1-13.")
        }
        if !Self.apBehaviorOptions.contains(where: { $0.value == apBehavior }) {
            issues.append("Fallback hotspot behavior must match one of WLED's AP opens options.")
        }
        if !Self.txPowerOptions.contains(where: { $0.value == txPower }) {
            issues.append("WiFi transmit power must match one of WLED's supported TX power options.")
        }

        return issues
    }

    var isValid: Bool {
        validationIssues.isEmpty
    }

    static func apBehaviorLabel(for value: Int) -> String {
        apBehaviorOptions.first { $0.value == value }?.label ?? "Unknown"
    }

    static func txPowerLabel(for value: Int) -> String {
        txPowerOptions.first { $0.value == value }?.label ?? "\(value)"
    }

    private func isValidHostnamePart(_ value: String) -> Bool {
        let normalized = Self.normalizeMDNSName(value)
        guard normalized.count <= 32 else { return false }
        guard !normalized.hasPrefix("-"), !normalized.hasPrefix("."),
              !normalized.hasSuffix("-"), !normalized.hasSuffix("."),
              !normalized.contains("..") else { return false }
        return normalized.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "."
        }
    }

    private static func normalizeMDNSName(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("http://") {
            normalized.removeFirst("http://".count)
        } else if normalized.lowercased().hasPrefix("https://") {
            normalized.removeFirst("https://".count)
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        if normalized.lowercased().hasSuffix(".local") {
            normalized.removeLast(".local".count)
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
    }

    private func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, let number = Int(part), (0...255).contains(number) else {
                return false
            }
            return String(number) == String(part) || part == "0"
        }
    }
}

// MARK: - Error Types

enum WiFiError: LocalizedError {
    case invalidURL
    case networkError(String)
    case invalidResponse
    case invalidRequest
    case connectionFailed
    case encodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from device"
        case .invalidRequest:
            return "Invalid request"
        case .connectionFailed:
            return "Failed to connect to network"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        }
    }
}

// MARK: - WiFi Service

class WLEDWiFiService {
    static let shared = WLEDWiFiService()
    static let provisioningRestartResponseTimeout: TimeInterval = 3
    static let provisioning = WLEDWiFiService(
        session: makeProvisioningSession(),
        restartResponseTimeout: provisioningRestartResponseTimeout,
        restartSettleDelay: 0.2
    )

    private let session: URLSession
    private let restartResponseTimeout: TimeInterval
    private let restartSettleDelay: TimeInterval
    private let scanMaxAttempts: Int
    private let scanRetryDelayNanoseconds: UInt64

    init(
        session: URLSession = .shared,
        restartResponseTimeout: TimeInterval = 15,
        restartSettleDelay: TimeInterval = 1,
        scanMaxAttempts: Int = 9,
        scanRetryDelay: TimeInterval = 0.75
    ) {
        self.session = session
        self.restartResponseTimeout = restartResponseTimeout
        self.restartSettleDelay = restartSettleDelay
        self.scanMaxAttempts = max(1, scanMaxAttempts)
        self.scanRetryDelayNanoseconds = UInt64(max(0, scanRetryDelay) * 1_000_000_000)
    }

    private static func makeProvisioningSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }
    
    func scanForNetworks(device: WLEDDevice) async throws -> [WiFiNetwork] {
        // `/json/net` starts an asynchronous radio scan and may return an empty
        // list for several seconds before the completed result is available.
        for attempt in 0..<scanMaxAttempts {
            try Task.checkCancellation()
            let networks = try await fetchNetworksOnce(device: device)
            if !networks.isEmpty {
                return networks
            }

            if attempt < scanMaxAttempts - 1 {
                try await Task.sleep(nanoseconds: scanRetryDelayNanoseconds)
            }
        }

        return []
    }
    
    func getCurrentWiFiInfo(device: WLEDDevice) async throws -> WiFiInfo {
        // Make real API call to get current WiFi info from WLED
        guard let url = URL(string: "http://\(device.ipAddress)/json/info") else {
            throw WiFiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.networkError("Failed to get WiFi info")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Extract WiFi info from the response - WLED /json/info doesn't include SSID
        let wifiInfo = json?["wifi"] as? [String: Any]
        let signalStrength = parseInt(wifiInfo?["rssi"]) ?? -100
        let channel = parseInt(wifiInfo?["channel"]) ?? 0
        let ipAddress = json?["ip"] as? String ?? device.ipAddress
        let macAddress = json?["mac"] as? String ?? device.id
        let bssid = parseString(wifiInfo?["bssid"])
        let firmwareVersion = parseString(json?["ver"])

        let directSSID = parseString(wifiInfo?["ssid"]) ?? parseString(json?["ssid"])
        
        var ssid = directSSID?.isEmpty == false ? directSSID! : "Unknown"
        let security = "Unknown"

        // Keep status loading cheap. A full network scan is intentionally only
        // run from explicit Scan actions because WLED scans can take seconds.
        if isUnknownSSID(ssid) {
            let configuredSSID = (try? await fetchConfiguredSSID(device: device))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !configuredSSID.isEmpty {
                ssid = configuredSSID
            }
        }
        
        return WiFiInfo(
            ssid: ssid,
            signalStrength: signalStrength,
            channel: channel,
            security: security,
            ipAddress: ipAddress,
            macAddress: macAddress,
            bssid: bssid,
            firmwareVersion: firmwareVersion
        )
    }
    
    func connectToNetwork(device: WLEDDevice, ssid: String, password: String?) async throws {
        // Follow WLED's proper /json/cfg read-modify-write pattern
        // 1. GET /json/cfg → parse JSON
        // 2. Modify only the Wi-Fi fields you need (nw.ins[0].ssid / nw.ins[0].psk)
        // 3. POST the full, edited object back to /json/cfg
        
        guard let configUrl = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WiFiError.invalidURL
        }
        
        // Step 1: GET /json/cfg to read current configuration
        let (configData, configResponse) = try await session.data(from: configUrl)
        
        guard let httpConfigResponse = configResponse as? HTTPURLResponse,
              httpConfigResponse.statusCode == 200 else {
            throw WiFiError.networkError("Failed to read device configuration")
        }
        
        // Parse the current configuration
        guard var config = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw WiFiError.invalidResponse
        }
        
        if password == nil {
            try await connectToOpenNetwork(device: device, ssid: ssid, config: config)
            return
        }

        // Step 2: Update WiFi credentials in WLED-native config paths.
        // WLED stores station credentials under `nw.ins[]`.
        applyWiFiCredentials(to: &config, ssid: ssid, password: password)
        config["sv"] = true
        config["rb"] = true
        
        // Step 3: POST the full, edited object back to /json/cfg
        var request = URLRequest(url: configUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = restartResponseTimeout
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: config)
        } catch {
            throw WiFiError.encodingError(error.localizedDescription)
        }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.connectionFailed
        }
        
        // Give the response a brief moment to leave the device before iOS drops its setup network.
        if restartSettleDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(restartSettleDelay * 1_000_000_000))
        }
    }

    func connectToNetworkPreservingFallback(device: WLEDDevice, ssid: String, password: String?) async throws {
        var config = try await fetchConfig(device: device)

        if password == nil {
            try await connectToOpenNetworkPreservingFallback(device: device, ssid: ssid, config: config)
            return
        }
        guard let password else { return }

        applyWiFiCredentialsPreservingFallback(to: &config, ssid: ssid, password: password)
        config["sv"] = true
        config["rb"] = true
        try await postRestartingConfig(config, to: device)
    }

    func getNetworkConfiguration(device: WLEDDevice) async throws -> WLEDNetworkConfiguration {
        let config = try await fetchConfig(device: device)
        return parseNetworkConfiguration(from: config)
    }

    func updateNetworkConfiguration(device: WLEDDevice, configuration: WLEDNetworkConfiguration) async throws {
        guard configuration.isValid else {
            throw WiFiError.invalidRequest
        }

        var config = try await fetchConfig(device: device)
        applyNetworkConfiguration(configuration, to: &config)
        if var wrapped = config["cfg"] as? [String: Any] {
            applyNetworkConfiguration(configuration, to: &wrapped)
            config["cfg"] = wrapped
        }

        guard let configUrl = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WiFiError.invalidURL
        }
        var request = URLRequest(url: configUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0
        request.httpBody = try JSONSerialization.data(withJSONObject: config)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.connectionFailed
        }
    }

    private func fetchConfiguredSSID(device: WLEDDevice) async throws -> String? {
        guard let configURL = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WiFiError.invalidURL
        }
        let (data, response) = try await session.data(from: configURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return extractConfiguredSSID(from: config)
    }

    private func applyWiFiCredentials(to config: inout [String: Any], ssid: String, password: String?) {
        // Some firmware responses are wrapped under "cfg", others are flat.
        applyWiFiCredentialsInRoot(&config, ssid: ssid, password: password)
        if var wrapped = config["cfg"] as? [String: Any] {
            applyWiFiCredentialsInRoot(&wrapped, ssid: ssid, password: password)
            config["cfg"] = wrapped
        }
    }

    private func applyWiFiCredentialsInRoot(_ root: inout [String: Any], ssid: String, password: String?) {
        var nw = root["nw"] as? [String: Any] ?? [:]
        var wifiInputs = nw["ins"] as? [[String: Any]] ?? []
        if wifiInputs.isEmpty {
            wifiInputs.append([:])
        }

        var primary = wifiInputs[0]
        primary["ssid"] = ssid
        // WLED expects `psk` for incoming config writes.
        primary["psk"] = password ?? ""
        // pskl is read-only metadata in serialized config; remove stale value before write.
        primary.removeValue(forKey: "pskl")
        wifiInputs[0] = primary

        nw["ins"] = wifiInputs
        root["nw"] = nw
    }

    private func applyWiFiCredentialsPreservingFallback(
        to config: inout [String: Any],
        ssid: String,
        password: String
    ) {
        applyWiFiCredentialsPreservingFallbackInRoot(&config, ssid: ssid, password: password)
        if var wrapped = config["cfg"] as? [String: Any] {
            applyWiFiCredentialsPreservingFallbackInRoot(&wrapped, ssid: ssid, password: password)
            config["cfg"] = wrapped
        }
    }

    private func applyWiFiCredentialsPreservingFallbackInRoot(
        _ root: inout [String: Any],
        ssid: String,
        password: String
    ) {
        var networkConfig = root["nw"] as? [String: Any] ?? [:]
        var stations = networkConfig["ins"] as? [[String: Any]] ?? []
        let targetIndex = stations.firstIndex { station in
            (parseString(station["ssid"]) ?? "").caseInsensitiveCompare(ssid) == .orderedSame
        }

        if let targetIndex {
            stations[targetIndex]["ssid"] = ssid
            stations[targetIndex]["psk"] = password
            stations[targetIndex].removeValue(forKey: "pskl")
        } else {
            stations.append([
                "ssid": ssid,
                "psk": password,
                "ip": [0, 0, 0, 0],
                "gw": [0, 0, 0, 0],
                "sn": [255, 255, 255, 0]
            ])
        }

        networkConfig["ins"] = stations
        root["nw"] = networkConfig
    }

    private func postRestartingConfig(_ config: [String: Any], to device: WLEDDevice) async throws {
        guard let configURL = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WiFiError.invalidURL
        }

        var request = URLRequest(url: configURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = restartResponseTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: config)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.connectionFailed
        }

        if restartSettleDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(restartSettleDelay * 1_000_000_000))
        }
    }

    private func connectToOpenNetworkPreservingFallback(
        device: WLEDDevice,
        ssid: String,
        config: [String: Any]
    ) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/wifi") else {
            throw WiFiError.invalidURL
        }

        let root = (config["cfg"] as? [String: Any]) ?? config
        var values = openNetworkFormValues(from: root, ssid: nil)
        var networkConfig = root["nw"] as? [String: Any] ?? [:]
        var stations = networkConfig["ins"] as? [[String: Any]] ?? []
        let targetIndex = stations.firstIndex { station in
            (parseString(station["ssid"]) ?? "").caseInsensitiveCompare(ssid) == .orderedSame
        } ?? stations.count

        if targetIndex == stations.count {
            stations.append(["ssid": ssid])
            values.append(("CS\(targetIndex)", ssid))
            values.append(("PW\(targetIndex)", ""))
            values.append(("BS\(targetIndex)", ""))
            appendIPv4FormValues(nil, prefix: "IP\(targetIndex)", to: &values)
            appendIPv4FormValues(nil, prefix: "GW\(targetIndex)", to: &values)
            appendIPv4FormValues([255, 255, 255, 0], prefix: "SN\(targetIndex)", to: &values)
        } else {
            values.removeAll { key, _ in key == "PW\(targetIndex)" }
            values.append(("PW\(targetIndex)", ""))
        }
        networkConfig["ins"] = stations

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = restartResponseTimeout
        request.httpBody = formEncodedData(values)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            throw WiFiError.connectionFailed
        }
    }

    private func connectToOpenNetwork(device: WLEDDevice, ssid: String, config: [String: Any]) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/wifi") else {
            throw WiFiError.invalidURL
        }

        let root = (config["cfg"] as? [String: Any]) ?? config
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = restartResponseTimeout
        request.httpBody = formEncodedData(openNetworkFormValues(from: root, ssid: ssid))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            throw WiFiError.connectionFailed
        }

        // WLED's Wi-Fi form sets forceReconnect when PW0 changes to empty.
        if restartSettleDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(restartSettleDelay * 1_000_000_000))
        }
    }

    private func openNetworkFormValues(from root: [String: Any], ssid: String?) -> [(String, String)] {
        let nw = root["nw"] as? [String: Any] ?? [:]
        let stations = nw["ins"] as? [[String: Any]] ?? []
        var values: [(String, String)] = []

        for (index, station) in stations.enumerated() {
            values.append(("CS\(index)", index == 0 ? (ssid ?? (parseString(station["ssid"]) ?? "")) : (parseString(station["ssid"]) ?? "")))
            let passwordLength = parseInt(station["pskl"]) ?? 0
            let shouldClearPrimaryPassword = index == 0 && ssid != nil
            values.append(("PW\(index)", shouldClearPrimaryPassword ? "" : String(repeating: "*", count: passwordLength)))
            values.append(("BS\(index)", parseString(station["bssid"]) ?? ""))
            appendIPv4FormValues(station["ip"], prefix: "IP\(index)", to: &values)
            appendIPv4FormValues(station["gw"], prefix: "GW\(index)", to: &values)
            appendIPv4FormValues(station["sn"], prefix: "SN\(index)", to: &values)
            if let encryptionType = parseInt(station["enc_type"]) {
                values.append(("ET\(index)", String(encryptionType)))
                values.append(("EA\(index)", parseString(station["e_anon_ident"]) ?? ""))
                values.append(("EI\(index)", parseString(station["e_ident"]) ?? ""))
            }
        }

        if stations.isEmpty {
            values.append(("CS0", ssid ?? ""))
            values.append(("PW0", ""))
            values.append(("BS0", ""))
            appendIPv4FormValues(nil, prefix: "IP0", to: &values)
            appendIPv4FormValues(nil, prefix: "GW0", to: &values)
            appendIPv4FormValues([255, 255, 255, 0], prefix: "SN0", to: &values)
        }

        appendIPv4FormValues(nw["dns"], prefix: "D", to: &values)
        values.append(("CM", parseString((root["id"] as? [String: Any])?["mdns"]) ?? ""))

        let ap = root["ap"] as? [String: Any] ?? [:]
        values.append(("AS", parseString(ap["ssid"]) ?? ""))
        values.append(("AP", String(repeating: "*", count: parseInt(ap["pskl"]) ?? 0)))
        values.append(("AC", String(parseInt(ap["chan"]) ?? 1)))
        values.append(("AB", String(parseInt(ap["behav"]) ?? 0)))
        if parseBool(ap["hide"]) == true { values.append(("AH", "on")) }

        let wifi = root["wifi"] as? [String: Any] ?? [:]
        values.append(("TX", String(parseInt(wifi["txpwr"]) ?? 78)))
        if parseBool(wifi["phy"]) == true { values.append(("FG", "on")) }
        if parseBool(wifi["sleep"]) == false { values.append(("WS", "on")) }

        if parseBool(nw["espnow"]) == true { values.append(("RE", "on")) }
        if let remotes = nw["linked_remote"] as? [String] {
            for (index, remote) in remotes.prefix(10).enumerated() {
                values.append(("RM\(index)", remote))
            }
        }
        if let ethernetType = parseInt((root["eth"] as? [String: Any])?["type"]) {
            values.append(("ETH", String(ethernetType)))
        }
        return values
    }

    private func appendIPv4FormValues(_ value: Any?, prefix: String, to values: inout [(String, String)]) {
        let parts = value as? [Any] ?? []
        for index in 0..<4 {
            values.append(("\(prefix)\(index)", String(index < parts.count ? parseInt(parts[index]) ?? 0 : 0)))
        }
    }

    private func formEncodedData(_ values: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func extractConfiguredSSID(from config: [String: Any]) -> String? {
        if let ssid = extractConfiguredSSID(fromRoot: config) {
            return ssid
        }
        if let wrapped = config["cfg"] as? [String: Any] {
            return extractConfiguredSSID(fromRoot: wrapped)
        }
        return nil
    }

    private func fetchConfig(device: WLEDDevice) async throws -> [String: Any] {
        guard let configURL = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WiFiError.invalidURL
        }
        var request = URLRequest(url: configURL)
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WiFiError.invalidResponse
        }
        return config
    }

    private func parseNetworkConfiguration(from config: [String: Any]) -> WLEDNetworkConfiguration {
        let root = (config["cfg"] as? [String: Any]) ?? config
        let id = root["id"] as? [String: Any] ?? [:]
        let nw = root["nw"] as? [String: Any] ?? [:]
        let station = (nw["ins"] as? [[String: Any]])?.first ?? [:]
        let ap = root["ap"] as? [String: Any] ?? [:]
        let wifi = root["wifi"] as? [String: Any] ?? [:]

        return WLEDNetworkConfiguration(
            mdnsName: parseString(id["mdns"]) ?? "",
            stationSSID: parseString(station["ssid"]) ?? "",
            staticIP: ipv4String(from: station["ip"], fallback: "0.0.0.0"),
            staticGateway: ipv4String(from: station["gw"], fallback: "0.0.0.0"),
            staticSubnet: ipv4String(from: station["sn"], fallback: "255.255.255.0"),
            dnsServer: ipv4String(from: nw["dns"], fallback: "0.0.0.0"),
            apSSID: parseString(ap["ssid"]) ?? "",
            apPassword: "",
            apPasswordConfigured: (parseInt(ap["pskl"]) ?? 0) > 0,
            hideAP: parseBool(ap["hide"]) ?? false,
            apChannel: parseInt(ap["chan"]) ?? 1,
            apBehavior: parseInt(ap["behav"]) ?? 0,
            disableWiFiSleep: !(parseBool(wifi["sleep"]) ?? true),
            force80211g: parseBool(wifi["phy"]) ?? false,
            txPower: parseInt(wifi["txpwr"]) ?? 78
        )
    }

    private func applyNetworkConfiguration(_ configuration: WLEDNetworkConfiguration, to root: inout [String: Any]) {
        var id = root["id"] as? [String: Any] ?? [:]
        id["mdns"] = configuration.normalizedMDNSName
        root["id"] = id

        var nw = root["nw"] as? [String: Any] ?? [:]
        var wifiInputs = nw["ins"] as? [[String: Any]] ?? []
        if wifiInputs.isEmpty {
            wifiInputs.append([:])
        }
        var station = wifiInputs[0]
        station["ip"] = ipv4Array(from: configuration.staticIP)
        station["gw"] = ipv4Array(from: configuration.staticGateway)
        station["sn"] = ipv4Array(from: configuration.staticSubnet)
        wifiInputs[0] = station
        nw["ins"] = wifiInputs
        nw["dns"] = ipv4Array(from: configuration.dnsServer)
        root["nw"] = nw

        var ap = root["ap"] as? [String: Any] ?? [:]
        ap["ssid"] = configuration.apSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuration.apPassword.isEmpty {
            ap["psk"] = configuration.apPassword
            ap.removeValue(forKey: "pskl")
        }
        ap["hide"] = configuration.hideAP
        ap["chan"] = configuration.apChannel
        ap["behav"] = configuration.apBehavior
        root["ap"] = ap

        var wifi = root["wifi"] as? [String: Any] ?? [:]
        wifi["sleep"] = !configuration.disableWiFiSleep
        wifi["phy"] = configuration.force80211g
        wifi["txpwr"] = configuration.txPower
        root["wifi"] = wifi
    }

    private func ipv4String(from value: Any?, fallback: String) -> String {
        guard let parts = value as? [Any], parts.count >= 4 else {
            return fallback
        }
        return parts.prefix(4).map { String(parseInt($0) ?? 0) }.joined(separator: ".")
    }

    private func ipv4Array(from value: String) -> [Int] {
        value.split(separator: ".").prefix(4).map { Int($0) ?? 0 }
    }

    private func extractConfiguredSSID(fromRoot root: [String: Any]) -> String? {
        guard let nw = root["nw"] as? [String: Any],
              let wifiInputs = nw["ins"] as? [[String: Any]] else {
            return nil
        }
        for entry in wifiInputs {
            if let ssid = entry["ssid"] as? String {
                let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func fetchNetworksOnce(device: WLEDDevice) async throws -> [WiFiNetwork] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/net") else {
            throw WiFiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.networkError("Failed to scan networks")
        }

        let parsed = try JSONSerialization.jsonObject(with: data)
        let networksArray: [[String: Any]]
        if let root = parsed as? [String: Any],
           let networks = root["networks"] as? [[String: Any]] {
            networksArray = networks
        } else if let root = parsed as? [[String: Any]] {
            networksArray = root
        } else {
            throw WiFiError.invalidResponse
        }

        var wifiNetworks: [WiFiNetwork] = []
        for networkData in networksArray {
            guard let rawSSID = networkData["ssid"] as? String else { continue }
            let ssid = rawSSID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ssid.isEmpty else { continue }

            let rssi = parseInt(networkData["rssi"]) ?? -100
            let bssid = (networkData["bssid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let channel = parseInt(networkData["channel"]) ?? 0
            let enc = parseInt(networkData["enc"])
            let securityString = (networkData["security"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let security = (securityString?.isEmpty == false) ? securityString! : getSecurityString(from: enc ?? 0)

            wifiNetworks.append(
                WiFiNetwork(
                    ssid: ssid,
                    signalStrength: rssi,
                    security: security,
                    channel: channel,
                    bssid: bssid
                )
            )
        }

        let deduplicated = Dictionary(
            wifiNetworks.map { network in
                (
                    (normalizeBSSID(network.bssid ?? "").isEmpty
                        ? network.ssid.lowercased()
                        : normalizeBSSID(network.bssid ?? "")),
                    network
                )
            },
            uniquingKeysWith: { lhs, rhs in
                lhs.signalStrength >= rhs.signalStrength ? lhs : rhs
            }
        ).values

        return deduplicated.sorted { $0.signalStrength > $1.signalStrength }
    }

    private func normalizeBSSID(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    private func isUnknownSSID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("unknown") == .orderedSame
    }

    private func parseString(_ value: Any?) -> String? {
        if let stringValue = value as? String {
            return stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        }
        return nil
    }

    private func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func parseBool(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let stringValue = value as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "on"].contains(normalized) { return true }
            if ["false", "0", "no", "off"].contains(normalized) { return false }
        }
        return nil
    }
    
    
    // Helper function to convert WLED encryption type to readable string
    private func getSecurityString(from enc: Int) -> String {
        switch enc {
        case 0:
            return "Open"
        case 1:
            return "WEP"
        case 2:
            return "WPA"
        case 3:
            return "WPA2"
        case 4:
            return "WPA3"
        case 5:
            return "WPA2/WPA3"
        default:
            return "Unknown"
        }
    }
}
