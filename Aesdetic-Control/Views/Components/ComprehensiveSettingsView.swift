//
//  ComprehensiveSettingsView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI

struct ComprehensiveSettingsView: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.openURL) private var openURL
    let device: WLEDDevice
    
    @State private var isOn: Bool = false
    @State private var brightnessDouble: Double = 50
    @State private var segStart: Int = 0
    @State private var segStop: Int = 60
    @State private var udpSend: Bool = false
    @State private var udpRecv: Bool = false
    @State private var udpNetwork: Int = 0
    @State private var info: Info?
    @State private var isLoading: Bool = false
    @State private var nightLightOn: Bool = false
    @State private var nightLightDurationMin: Int = 10
    @State private var nightLightMode: Int = 0
    @State private var nightLightTargetBri: Int = 0
    @State private var isEditingName: Bool = false
    @State private var editingName: String = ""
    
    // New state variables for comprehensive settings
    @State private var selectedSettingsCategory: SettingsCategory = .info
    @State private var showWebConfig: Bool = false
    
    // WiFi state variables
    @State private var availableNetworks: [WiFiNetwork] = []
    @State private var isScanning: Bool = false
    @State private var selectedNetwork: WiFiNetwork?
    @State private var password: String = ""
    @State private var isConnecting: Bool = false
    @State private var connectionStatus: WiFiSetupView.ConnectionStatus = .idle
    @State private var showPasswordField: Bool = false
    @State private var currentWiFiInfo: WiFiInfo?
    @State private var showAllNetworks: Bool = true
    @State private var showConnectedMessage: Bool = true
    
    enum SettingsCategory: String, CaseIterable {
        case info = "Info"
        case wifi = "WiFi Setup"
        case leds = "LED Preferences"
        case config2d = "2D Configuration"
        case ui = "User Interface"
        case sync = "Sync Interfaces"
        case time = "Time & Macros"
        case usermods = "Usermods"
        case security = "Security & Updates"
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .wifi: return "wifi"
            case .leds: return "lightbulb"
            case .config2d: return "rectangle.grid.2x2"
            case .ui: return "paintbrush"
            case .sync: return "arrow.triangle.2.circlepath"
            case .time: return "clock"
            case .usermods: return "puzzlepiece"
            case .security: return "lock.shield"
            }
        }
    }
    
    var body: some View {
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
            
            VStack(spacing: 0) {
                // Header with device name
                headerSection
                
                // Category selector chips
                categorySelector
                
                // Content based on selected category
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        switch selectedSettingsCategory {
                        case .info:
                            infoSection
                        case .wifi:
                            wifiSection
                        case .leds:
                            ledsSection
                        case .config2d:
                            config2dSection
                        case .ui:
                            uiSection
                        case .sync:
                            syncSection
                        case .time:
                            timeSection
                        case .usermods:
                            usermodsSection
                        case .security:
                            securitySection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { 
            await loadState()
            await loadCurrentWiFiInfo()
            scanForNetworks()
        }
        .sheet(isPresented: $showWebConfig) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/settings")!)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isEditingName {
                        TextField("Device Name", text: $editingName)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .font(.title2.weight(.semibold))
                            .onSubmit {
                                Task {
                                    await viewModel.renameDevice(device, to: editingName)
                                    isEditingName = false
                                }
                            }
                            .onAppear {
                                editingName = device.name
                            }
                    } else {
                        Text(device.name)
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text(device.ipAddress)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        if isEditingName {
                            isEditingName = false
                        } else {
                            isEditingName = true
                            editingName = device.name
                        }
                    }) {
                        Image(systemName: isEditingName ? "xmark" : "pencil")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 16, weight: .medium))
                    }
                    
                    Button(action: { Task { await loadState() } }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Category Selector
    
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SettingsCategory.allCases, id: \.self) { category in
                    Button(action: {
                        selectedSettingsCategory = category
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(category.rawValue)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(selectedSettingsCategory == category ? .black : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(selectedSettingsCategory == category ? Color.white : Color.white.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Settings Sections
    
    private var infoSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Device Information") {
                VStack(spacing: 12) {
                    InfoRow(label: "IP Address", value: device.ipAddress)
                    InfoRow(label: "MAC Address", value: device.id)
                    if let ver = info?.ver {
                        InfoRow(label: "Firmware", value: ver)
                    }
                    InfoRow(label: "LED Count", value: "\(segStop)")
                    if let ledCount = info?.leds.count {
                        InfoRow(label: "LED Count (API)", value: "\(ledCount)")
                    }
                    
                    Button(action: { showWebConfig = true }) {
                        SettingsButton(title: "Open Web Config", icon: "globe")
                    }
                }
            }
            
            SettingsCard(title: "Power Control") {
                PowerToggleRow(isOn: $isOn, device: device)
                    .environmentObject(viewModel)
            }
            
            SettingsCard(title: "Brightness") {
                SliderRow(
                    label: "Level",
                    value: $brightnessDouble,
                    range: 0...100
                ) {
                    Task {
                        let bri = Int((brightnessDouble / 100.0 * 255.0).rounded())
                        await viewModel.updateDeviceBrightness(device, brightness: bri)
                    }
                }
            }
        }
    }
    
    private var wifiSection: some View {
        VStack(spacing: 12) {
            // Current WiFi
            SettingsCard(title: "Current WiFi", content: {
                VStack(spacing: 12) {
                    if let wifiInfo = currentWiFiInfo {
                        InfoRow(label: "SSID", value: wifiInfo.ssid)
                        InfoRow(label: "Signal", value: "\(wifiInfo.signalStrength) dBm")
                        InfoRow(label: "Channel", value: "\(wifiInfo.channel)")
                        InfoRow(label: "Security", value: wifiInfo.security)

                        // Helpful note about WiFi disconnection
                        Text("💡 To disconnect from WiFi, connect to a different network below")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading WiFi information...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.vertical, 8)
                    }
                }
            }, headerContent: {
                AnyView(
                    Button("Refresh") {
                        Task {
                            await loadCurrentWiFiInfo()
                            scanForNetworks()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.white)
                    .cornerRadius(8)
                )
            })
            
            // Available Networks
            SettingsCard(title: "Available Networks", content: {
                VStack(spacing: 12) {
                    if availableNetworks.isEmpty && !isScanning {
                        Text("No networks found. Tap 'Scan' to search.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.vertical, 8)
                    } else if !showAllNetworks && !availableNetworks.isEmpty {
                        // Show only connected network when collapsed
                        if let wifiInfo = currentWiFiInfo,
                           let connectedNetwork = availableNetworks.first(where: { $0.ssid == wifiInfo.ssid }) {
                            WiFiNetworkRow(
                                network: connectedNetwork,
                                isSelected: false,
                                onSelect: { }
                            )
                            
                            VStack(alignment: .leading, spacing: 8) {
                                if showConnectedMessage {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.green)
                                        
                                        Text("Connected")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                Text("Tap 'Scan' to see all available networks")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                            .onAppear {
                                // Auto-hide the success message after 5 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                    showConnectedMessage = false
                                }
                            }
                        }
                    } else {
                        // Show all networks when expanded
                        ForEach(availableNetworks, id: \.ssid) { network in
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
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Password Required")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(.white)
                                            
                                            SecureField("Enter password", text: $password)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .font(.subheadline)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    
                                    Button("Connect to \(network.ssid)") {
                                        connectToNetwork()
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.black)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(Color.white)
                                    .cornerRadius(10)
                                    .disabled(isConnecting || (network.security != "Open" && password.isEmpty))
                                    
                                    if isConnecting {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Connecting...")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    
                                    // Connection status feedback
                                    if connectionStatus != .idle {
                                        VStack(spacing: 4) {
                                            switch connectionStatus {
                                            case .connecting:
                                                HStack {
                                                    ProgressView()
                                                        .scaleEffect(0.8)
                                                    Text("Connecting to \(selectedNetwork?.ssid ?? "network")...")
                                                        .font(.caption)
                                                        .foregroundColor(.white.opacity(0.8))
                                                }
                                            case .connected:
                                                HStack {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.green)
                                                    Text("Successfully connected!")
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                }
                                            case .failed(let message):
                                                HStack {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .foregroundColor(.red)
                                                    Text("Failed: \(message)")
                                                        .font(.caption)
                                                        .foregroundColor(.red)
                                                }
                                            default:
                                                EmptyView()
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                }
            }, headerContent: {
                AnyView(
                    HStack(spacing: 8) {
                        Button("Scan") {
                            scanForNetworks()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.white)
                        .cornerRadius(8)
                        .disabled(isScanning)

                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                )
            })
            
            // Web Config Access
            SettingsCard(title: "Advanced Configuration") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/wifi")!) }) {
                        SettingsButton(title: "Open Web Config", icon: "globe")
                    }
                }
            }
        }
    }
    
    private var ledsSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "LED Configuration") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/leds")!) }) {
                        SettingsButton(title: "LED Preferences", icon: "lightbulb")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/leds")!) }) {
                        SettingsButton(title: "Pin Configuration", icon: "cable.connector")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/leds")!) }) {
                        SettingsButton(title: "LED Type Settings", icon: "gear")
                    }
                }
            }
            
            SettingsCard(title: "Segment Configuration") {
                SegmentBoundsRow(
                    device: device,
                    segmentId: 0,
                    start: segStart,
                    stop: segStop
                )
                .environmentObject(viewModel)
            }
        }
    }
    
    private var config2dSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "2D Configuration") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/2D")!) }) {
                        SettingsButton(title: "Matrix Setup", icon: "rectangle.grid.2x2")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/2D")!) }) {
                        SettingsButton(title: "Layout Configuration", icon: "square.grid.3x3")
                    }
                }
            }
        }
    }
    
    private var uiSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "User Interface") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/ui")!) }) {
                        SettingsButton(title: "UI Preferences", icon: "paintbrush")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/ui")!) }) {
                        SettingsButton(title: "Theme Settings", icon: "paintpalette")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/ui")!) }) {
                        SettingsButton(title: "Display Options", icon: "display")
                    }
                }
            }
        }
    }
    
    private var syncSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Sync Interfaces") {
                VStack(spacing: 12) {
                    UDPTogglesRow(udpSend: $udpSend, udpRecv: $udpRecv, device: device)
                        .environmentObject(viewModel)
                    UDPNetworkRow(network: $udpNetwork, device: device)
                }
            }
            
            SettingsCard(title: "Additional Sync Options") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/sync")!) }) {
                        SettingsButton(title: "DMX Configuration", icon: "cable.connector")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/sync")!) }) {
                        SettingsButton(title: "Art-Net Settings", icon: "network")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/sync")!) }) {
                        SettingsButton(title: "E1.31 Configuration", icon: "cable.connector")
                    }
                }
            }
        }
    }
    
    private var timeSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Time & Macros") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/time")!) }) {
                        SettingsButton(title: "Time Settings", icon: "clock")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/time")!) }) {
                        SettingsButton(title: "Macro Configuration", icon: "play.circle")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/time")!) }) {
                        SettingsButton(title: "Timer Settings", icon: "timer")
                    }
                }
            }
            
            SettingsCard(title: "Night Light") {
                VStack(spacing: 12) {
                    Toggle("Enabled", isOn: $nightLightOn)
                        .tint(.white)
                        .foregroundColor(.white)
                    
                    IntStepperRow(
                        title: "Duration (min)",
                        value: $nightLightDurationMin,
                        range: 1...255,
                        onEnd: commitNightLight
                    )
                    
                    IntStepperRow(
                        title: "Mode",
                        value: $nightLightMode,
                        range: 0...3,
                        onEnd: commitNightLight
                    )
                    
                    IntStepperRow(
                        title: "Target Brightness",
                        value: $nightLightTargetBri,
                        range: 0...255,
                        onEnd: commitNightLight
                    )
                    
                    Button("Apply Night Light") { commitNightLight() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white)
                        .cornerRadius(10)
                }
            }
        }
    }
    
    private var usermodsSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Usermods") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/um")!) }) {
                        SettingsButton(title: "Custom Modifications", icon: "puzzlepiece")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/um")!) }) {
                        SettingsButton(title: "Plugin Configuration", icon: "plus.circle")
                    }
                }
            }
        }
    }
    
    private var securitySection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Security & Updates") {
                VStack(spacing: 12) {
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/settings/sec")!) }) {
                        SettingsButton(title: "Security Settings", icon: "lock.shield")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/update")!) }) {
                        SettingsButton(title: "Firmware Update", icon: "arrow.up.circle")
                    }
                    Button(action: { openURL(URL(string: "http://\(device.ipAddress)/reset")!) }) {
                        SettingsButton(title: "Factory Reset", icon: "arrow.clockwise")
                    }
                }
            }
            
            SettingsCard(title: "Realtime Updates") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Realtime Updates")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: Binding(get: { viewModel.isRealTimeEnabled }, set: { v in
                            if v { viewModel.enableRealTimeUpdates() } else { viewModel.disableRealTimeUpdates() }
                        }))
                        .labelsHidden()
                        .tint(.white)
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: { Task { await viewModel.forceReconnection(device) } }) {
                            Text("Reconnect")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color.white)
                                .cornerRadius(10)
                        }
                        
                        Button(action: { WLEDAPIService.shared.clearCache() }) {
                            Text("Clear Cache")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color.white)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func commitNightLight() {
        Task {
            _ = try? await WLEDAPIService.shared.configureNightLight(
                enabled: nightLightOn,
                duration: nightLightDurationMin,
                mode: nightLightMode,
                targetBrightness: nightLightTargetBri,
                for: device
            )
        }
    }
    
    private func loadState() async {
        isLoading = true
        defer { isLoading = false }
        
        isOn = device.isOn
        brightnessDouble = Double(device.brightness) / 255.0 * 100.0
        segStart = 0
        segStop = device.state?.segments.first?.len ?? segStop
        
        do {
            let resp = try await WLEDAPIService.shared.getState(for: device)
            await MainActor.run {
                info = resp.info
                isOn = resp.state.isOn
                brightnessDouble = Double(resp.state.brightness) / 255.0 * 100.0
                if let len = resp.state.segments.first?.len { segStop = len }
            }
        } catch { }
    }
    
    // MARK: - WiFi Helper Functions
    
    private func loadCurrentWiFiInfo() async {
        do {
            let wifiInfo = try await WLEDWiFiService.shared.getCurrentWiFiInfo(device: device)
            await MainActor.run {
                self.currentWiFiInfo = wifiInfo
            }
        } catch {
            print("Failed to load WiFi info: \(error)")
        }
    }
    
    private func scanForNetworks() {
        isScanning = true
        showAllNetworks = true  // Show all networks when scanning
        showConnectedMessage = true  // Reset success message for new connections
        
        Task {
            do {
                let networks = try await WLEDWiFiService.shared.scanForNetworks(device: device)
                await MainActor.run {
                    self.availableNetworks = networks
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    print("Failed to scan networks: \(error)")
                }
            }
        }
    }
    
    private func selectNetwork(_ network: WiFiNetwork) {
        selectedNetwork = network
        password = ""
        connectionStatus = .idle
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
                    self.showAllNetworks = false  // Collapse networks on successful connection
                    self.showConnectedMessage = true  // Show success message
                    
                    // Clear password and selected network
                    self.password = ""
                    self.selectedNetwork = nil
                    
                    // Clear success message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        await MainActor.run {
                            self.connectionStatus = .idle
                        }
                    }
                    // Refresh WiFi info after successful connection
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        await self.loadCurrentWiFiInfo()
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
}

// MARK: - Supporting Views

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content
    let headerContent: (() -> AnyView)?
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.headerContent = nil
    }
    
    init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder headerContent: @escaping () -> AnyView) {
        self.title = title
        self.content = content()
        self.headerContent = headerContent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if let headerContent = headerContent {
                    headerContent()
                }
            }
            
            content
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundColor(.white)
        }
    }
}

struct SettingsButton: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            Text(title)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .medium))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Reused Components from WLEDSettingsView

fileprivate struct PowerToggleRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Binding var isOn: Bool
    let device: WLEDDevice

    var body: some View {
        HStack {
            Text("Power")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.white)
                .onChange(of: isOn) { _, val in
                    Task { await viewModel.setDevicePower(device, isOn: val) }
                }
        }
    }
}

fileprivate struct UDPTogglesRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Binding var udpSend: Bool
    @Binding var udpRecv: Bool
    let device: WLEDDevice

    var body: some View {
        HStack {
            Toggle("Send (UDPN)", isOn: $udpSend)
                .tint(.white)
                .foregroundColor(.white)
                .onChange(of: udpSend) { _, v in
                    Task { await viewModel.setUDPSync(device, send: v, recv: nil) }
                }
            Spacer()
            Toggle("Receive", isOn: $udpRecv)
                .tint(.white)
                .foregroundColor(.white)
                .onChange(of: udpRecv) { _, v in
                    Task { await viewModel.setUDPSync(device, send: nil, recv: v) }
                }
        }
    }
}

fileprivate struct UDPNetworkRow: View {
    @Binding var network: Int
    let device: WLEDDevice

    var body: some View {
        HStack {
            Text("Network")
                .foregroundColor(.white)
            Spacer()
            Stepper("\(network)", value: $network, in: 0...255, step: 1, onEditingChanged: { _ in
                Task { _ = try? await WLEDAPIService.shared.setUDPSync(for: device, send: nil, recv: nil, network: network) }
            })
            .labelsHidden()
        }
    }
}

fileprivate struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEnd: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value))")
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding<Double>(get: { value }, set: { value = $0 }),
                in: range,
                onEditingChanged: { editing in
                    if editing == false { onEnd?() }
                }
            )
        }
    }
}

fileprivate struct IntStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var onEnd: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Stepper("\(value)", value: $value, in: range, step: 1, onEditingChanged: { editing in
                if !editing { onEnd?() }
            })
            .labelsHidden()
        }
    }
}

fileprivate struct SegmentBoundsRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice
    let segmentId: Int
    @State var start: Int
    @State var stop: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Start \(start)")
                let startBinding: Binding<Double> = Binding<Double>(
                    get: { Double(start) },
                    set: { start = Int($0.rounded()) }
                )
                Slider(
                    value: startBinding,
                    in: 0...Double(stop)
                )
            }
            HStack {
                Text("Stop \(stop)")
                let stopBinding: Binding<Double> = Binding<Double>(
                    get: { Double(stop) },
                    set: { stop = Int($0.rounded()) }
                )
                Slider(
                    value: stopBinding,
                    in: Double(start + 1)...Double(max(start + 1, stop))
                )
            }
            Button("Apply") {
                Task {
                    await viewModel.updateSegmentBounds(
                        device: device,
                        segmentId: segmentId,
                        start: start,
                        stop: stop
                    )
                }
            }
        }
    }
}

extension ComprehensiveSettingsView: Hashable {
    static func == (lhs: ComprehensiveSettingsView, rhs: ComprehensiveSettingsView) -> Bool { 
        lhs.device.id == rhs.device.id 
    }
    func hash(into hasher: inout Hasher) { 
        hasher.combine(device.id) 
    }
}
