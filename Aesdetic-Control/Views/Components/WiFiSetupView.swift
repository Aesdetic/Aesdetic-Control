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
    @Environment(\.dismiss) private var dismiss
    
    @State private var availableNetworks: [WiFiNetwork] = []
    @State private var isScanning: Bool = false
    @State private var selectedNetwork: WiFiNetwork?
    @State private var password: String = ""
    @State private var isConnecting: Bool = false
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var showPasswordField: Bool = false
    @State private var currentWiFiInfo: WiFiInfo?
    
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
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Scan") {
                        scanForNetworks()
                    }
                    .foregroundColor(.white)
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
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("Connect to a different network below")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 4)
                    
                    Button("Refresh") {
                        Task { 
                            await loadCurrentWiFiInfo()
                            // Also refresh the network list
                            scanForNetworks()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.white)
                    .cornerRadius(10)
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading WiFi information...")
                            .foregroundColor(.white.opacity(0.7))
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
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.vertical, 20)
                } else if availableNetworks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.5))
                        Text("No networks found")
                            .foregroundColor(.white.opacity(0.7))
                        Text("Tap 'Scan' to search for WiFi networks")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(availableNetworks, id: \.ssid) { network in
                        VStack(spacing: 0) {
                            WiFiNetworkRow(
                                network: network,
                                isSelected: selectedNetwork?.ssid == network.ssid,
                                onSelect: { selectNetwork(network) }
                            )
                            
                            // Password field and connect button - right below selected network
                            if selectedNetwork?.ssid == network.ssid {
                                VStack(spacing: 12) {
                                    Divider()
                                        .background(Color.white.opacity(0.2))
                                    
                                    if network.security == "Open" {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Open Network")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(.white)
                                            
                                            Text("No password required for \(network.ssid)")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Password for \(network.ssid)")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(.white)
                                            
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
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    Button(action: connectToNetwork) {
                                        HStack {
                                            if isConnecting {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .foregroundColor(.black)
                                            }
                                            Text(isConnecting ? "Connecting..." : "Connect")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.black)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.white)
                                        .cornerRadius(10)
                                    }
                                    .disabled(isConnecting || (network.security != "Open" && password.isEmpty))
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                }
            }
        }
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
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                case .connecting:
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting to \(selectedNetwork?.ssid ?? "network")...")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                case .connected:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Successfully connected!")
                            .foregroundColor(.white)
                    }
                    
                case .failed(let error):
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Connection failed")
                                .foregroundColor(.white)
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
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
                try await WLEDWiFiService.shared.connectToNetwork(
                    device: device,
                    ssid: network.ssid,
                    password: password.isEmpty ? nil : password
                )
                
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
                self.currentWiFiInfo = wifiInfo
            }
        } catch {
            await MainActor.run {
                self.currentWiFiInfo = nil
            }
        }
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
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(network.ssid)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                    
                    HStack(spacing: 8) {
                        Text(network.security)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("\(network.signalStrength) dBm")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        if network.channel > 0 {
                            Text("Ch \(network.channel)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
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
}

// MARK: - Error Types

enum WiFiError: LocalizedError {
    case invalidURL
    case networkError(String)
    case invalidResponse
    case invalidRequest
    case connectionFailed
    
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
        }
    }
}

// MARK: - WiFi Service

class WLEDWiFiService {
    static let shared = WLEDWiFiService()
    
    private init() {}
    
    func scanForNetworks(device: WLEDDevice) async throws -> [WiFiNetwork] {
        // Make real API call to WLED device to scan for networks
        guard let url = URL(string: "http://\(device.ipAddress)/json/net") else {
            throw WiFiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.networkError("Failed to scan networks")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let networksArray = json?["networks"] as? [[String: Any]] else {
            throw WiFiError.invalidResponse
        }
        
        var wifiNetworks: [WiFiNetwork] = []
        
        for networkData in networksArray {
            guard let ssid = networkData["ssid"] as? String,
                  let rssi = networkData["rssi"] as? Int,
                  let bssid = networkData["bssid"] as? String,
                  let channel = networkData["channel"] as? Int,
                  let enc = networkData["enc"] as? Int else {
                continue
            }
            
            // Convert encryption type to readable string
            let security = getSecurityString(from: enc)
            
            wifiNetworks.append(WiFiNetwork(
                ssid: ssid,
                signalStrength: rssi,
                security: security,
                channel: channel,
                bssid: bssid
            ))
        }
        
        // Sort by signal strength (strongest first)
        return wifiNetworks.sorted { $0.signalStrength > $1.signalStrength }
    }
    
    func getCurrentWiFiInfo(device: WLEDDevice) async throws -> WiFiInfo {
        // Make real API call to get current WiFi info from WLED
        guard let url = URL(string: "http://\(device.ipAddress)/json/info") else {
            throw WiFiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.networkError("Failed to get WiFi info")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Extract WiFi info from the response - WLED /json/info doesn't include SSID
        let wifiInfo = json?["wifi"] as? [String: Any]
        let signalStrength = wifiInfo?["rssi"] as? Int ?? -100
        let channel = wifiInfo?["channel"] as? Int ?? 0
        let bssid = wifiInfo?["bssid"] as? String ?? ""
        let ipAddress = json?["ip"] as? String ?? device.ipAddress
        let macAddress = json?["mac"] as? String ?? device.id
        
        // Try to get SSID from the network scan by matching BSSID
        var ssid = "Unknown"
        var security = "Unknown"
        
        do {
            let networks = try await scanForNetworks(device: device)
            if let currentNetwork = networks.first(where: { $0.bssid == bssid }) {
                ssid = currentNetwork.ssid
                security = currentNetwork.security
            }
        } catch {
            // If scan fails, use device name as fallback
            ssid = device.name
        }
        
        return WiFiInfo(
            ssid: ssid,
            signalStrength: signalStrength,
            channel: channel,
            security: security,
            ipAddress: ipAddress,
            macAddress: macAddress
        )
    }
    
    func connectToNetwork(device: WLEDDevice, ssid: String, password: String?) async throws {
        // This would make an API call to configure WiFi on the WLED device
        // Implementation would use WLED's JSON API to set WiFi credentials
        
        let url = URL(string: "http://\(device.ipAddress)/json")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var jsonBody: [String: Any] = [:]
        
        // Configure WiFi settings according to WLED's API
        var wifiConfig: [String: Any] = [:]
        wifiConfig["ssid"] = ssid
        if let password = password {
            wifiConfig["password"] = password
        }
        
        jsonBody["wifi"] = wifiConfig
        
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WiFiError.connectionFailed
        }
        
        // Wait a moment for the device to process the configuration
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
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
