//
//  ComprehensiveSettingsView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import CoreLocation
import SwiftUI

private enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case upToDate(current: String, latest: String)
    case updateAvailable(current: String, latest: String)
    case error(String)
}

struct ComprehensiveSettingsView: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.openURL) private var openURL
    let device: WLEDDevice
    let initialCategory: SettingsCategory
    
    @State private var isOn: Bool = false
    @State private var brightnessDouble: Double = 50
    @State private var segStart: Int = 0
    @State private var segStop: Int = 60
    @State private var udpSend: Bool = false
    @State private var udpRecv: Bool = false
    @State private var info: Info?
    @State private var isLoading: Bool = false
    @State private var nightLightOn: Bool = false
    @State private var nightLightDurationMin: Int = 10
    @State private var nightLightMode: Int = 0
    @State private var nightLightTargetBri: Int = 0
    @State private var timerDrafts: [NativeTimerDraft] = NativeTimerDraft.standardDefaults
    @State private var isLoadingTimers: Bool = false
    @State private var savingTimerSlotIds: Set<Int> = []
    @State private var isEditingName: Bool = false
    @State private var editingName: String = ""
    @State private var temperatureStopsUseCCT: Bool = false
    @State private var macroButtonPress: Int = 0
    @State private var macroButtonLongPress: Int = 0
    @State private var macroButtonDoublePress: Int = 0
    @State private var macroAlexaOn: Int = 0
    @State private var macroAlexaOff: Int = 0
    @State private var macroNightLight: Int = 0
    @State private var isSavingMacroBindings: Bool = false
    @State private var isSyncingDeviceTime: Bool = false
    @State private var deviceTimeSyncMessage: String?
    @State private var deviceTimeSyncMessageIsError: Bool = false
    @State private var activeSegmentCountDraft: Int = 1
    @State private var isApplyingSegmentCount: Bool = false
    @State private var segmentSettingsMessage: String?
    @State private var segmentSettingsMessageIsError: Bool = false
    @State private var segmentColorDrafts: [Int: Color] = [:]
    @State private var applyingSegmentColorIds: Set<Int> = []
    
    // New state variables for comprehensive settings
    @State private var selectedSettingsCategory: SettingsCategory = .info
    @State private var showWebConfig: Bool = false
    @State private var showFirmwareUpdate: Bool = false
    @State private var showAutomaticFirmwareUpdate: Bool = false
    @State private var showProductSetup: Bool = false
    @State private var showPostRenameWiFiPrompt: Bool = false
    @State private var updateCheckStatus: UpdateCheckStatus = .idle
    @State private var latestStableVersion: String?
    @State private var lastUpdateCheck: Date?
    
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
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @AppStorage("showSegmentControlsInColorTabAdvanced") private var showSegmentControlsInColorTabAdvanced: Bool = true
    
    enum SettingsCategory: String, CaseIterable {
        case info = "Info"
        case wifi = "WiFi Setup"
        case leds = "LED Preferences"
        case segments = "Segments"
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
            case .segments: return "square.split.2x2"
            case .config2d: return "rectangle.grid.2x2"
            case .ui: return "paintbrush"
            case .sync: return "arrow.triangle.2.circlepath"
            case .time: return "clock"
            case .usermods: return "puzzlepiece"
            case .security: return "lock.shield"
            }
        }
    }

    private var isRebootWaitActive: Bool {
        viewModel.isRebootWaitActive(for: device.id)
    }

    private var rebootWaitRemainingSeconds: Int {
        viewModel.rebootWaitRemainingSeconds(for: device.id)
    }

    private var activeDevice: WLEDDevice {
        if let matchedById = viewModel.devices.first(where: { $0.id == device.id }) {
            return matchedById
        }
        if let matchedByIP = viewModel.devices.first(where: { $0.ipAddress == device.ipAddress }) {
            return matchedByIP
        }
        return device
    }

    init(device: WLEDDevice, initialCategory: SettingsCategory = .info) {
        self.device = device
        self.initialCategory = initialCategory
        _selectedSettingsCategory = State(initialValue: initialCategory)
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
                        case .segments:
                            segmentsSection
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
            .disabled(isRebootWaitActive)

            if isRebootWaitActive {
                rebootWaitOverlay
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .presentationBackground(.ultraThinMaterial)
        .task { 
            await loadState()
            await loadCurrentWiFiInfo()
            scanForNetworks()
        }
        .sheet(isPresented: $showWebConfig) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/settings")!)
        }
        .sheet(isPresented: $showAutomaticFirmwareUpdate) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/settings/sec")!)
        }
        .sheet(isPresented: $showFirmwareUpdate) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/update")!)
        }
        .overlay {
            if showProductSetup {
                productSetupOverlay
            }
        }
        .confirmationDialog(
            "Check WiFi After Renaming?",
            isPresented: $showPostRenameWiFiPrompt,
            titleVisibility: .visible
        ) {
            Button("Review WiFi Now") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedSettingsCategory = .wifi
                }
            }
            Button("Done", role: .cancel) {}
        } message: {
            Text("Confirm this device is on the correct network or switch WiFi now.")
        }
    }

    @ViewBuilder
    private var productSetupOverlay: some View {
        GeometryReader { proxy in
            let maxPopupHeight = max(320, proxy.size.height - proxy.safeAreaInsets.bottom - 80)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showProductSetup = false
                    }

                ProductSetupFlowView(
                    device: activeDevice,
                    onClose: { self.showProductSetup = false }
                )
                .environmentObject(viewModel)
                .frame(maxHeight: maxPopupHeight, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.identity)
        .zIndex(4)
    }

    private var rebootWaitOverlay: some View {
        GeometryReader { proxy in
            let maxCardWidth = min(proxy.size.width - 48, 360)
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .background(.ultraThinMaterial)
                    .blur(radius: 2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Intentionally swallow taps while reboot wait is active.
                    }

                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("Rebooting Device")
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Reconnecting... \(max(0, rebootWaitRemainingSeconds))s")
                        .font(AppTypography.style(.subheadline))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: maxCardWidth)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isRebootWaitActive)
        .zIndex(3)
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
                            .font(AppTypography.style(.title2, weight: .semibold))
                            .onSubmit {
                                Task {
                                    await commitDeviceRenameFromHeader()
                                }
                            }
                            .onAppear {
                                editingName = activeDevice.name
                            }
                    } else {
                        Text(activeDevice.name)
                            .font(AppTypography.style(.title2, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text(activeDevice.ipAddress)
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        if isEditingName {
                            isEditingName = false
                            editingName = activeDevice.name
                        } else {
                            isEditingName = true
                            editingName = activeDevice.name
                        }
                    }) {
                        Image(systemName: isEditingName ? "xmark" : "pencil")
                            .foregroundColor(.white.opacity(0.7))
                            .font(AppTypography.style(.headline, weight: .medium))
                    }
                    
                    Button(action: { Task { await loadState() } }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white.opacity(0.7))
                            .font(AppTypography.style(.headline, weight: .medium))
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
                                .font(AppTypography.style(.subheadline, weight: .medium))
                            Text(category.rawValue)
                                .font(AppTypography.style(.subheadline, weight: .medium))
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
            SettingsCard(title: "Aesdetic Profile") {
                VStack(spacing: 12) {
                    InfoRow(label: "Setup", value: activeDevice.setupState.displayName)
                    InfoRow(label: "Product", value: activeDevice.productType.displayName)
                    InfoRow(label: "Variant", value: activeDevice.lookId ?? "Default")
                    if activeDevice.profileVersionApplied > 0 {
                        InfoRow(label: "Profile Version", value: "v\(activeDevice.profileVersionApplied)")
                    }

                    Button(action: { showProductSetup = true }) {
                        SettingsButton(
                            title: activeDevice.setupState == .pendingSelection ? "Complete Setup" : "Change Product",
                            icon: "sparkles"
                        )
                    }

                    if activeDevice.productType != .generic {
                        Button(action: {
                            Task {
                                _ = await viewModel.reapplyCurrentProfile(activeDevice)
                            }
                        }) {
                            SettingsButton(title: "Reapply Recommended Setup", icon: "arrow.triangle.2.circlepath")
                        }
                    }

                    if activeDevice.backupSnapshotId != nil {
                        Button(action: {
                            Task {
                                _ = await viewModel.revertLastProfileInstall(activeDevice)
                            }
                        }) {
                            SettingsButton(title: "Revert Last Install", icon: "arrow.uturn.backward")
                        }
                    }
                }
            }

            SettingsCard(title: "Device Information") {
                VStack(spacing: 12) {
                    InfoRow(label: "IP Address", value: activeDevice.ipAddress)
                    InfoRow(label: "MAC Address", value: activeDevice.id)
                    if let ver = info?.ver {
                        InfoRow(label: "Firmware", value: ver)
                    }
                    if let deviceTime = info?.time, !deviceTime.isEmpty {
                        InfoRow(label: "Device Time", value: deviceTime)
                    } else {
                        InfoRow(label: "Device Time", value: "Unavailable")
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

            SettingsCard(title: "Firmware Update") {
                VStack(spacing: 12) {
                    if let ver = info?.ver {
                        InfoRow(label: "Current Version", value: ver)
                    } else {
                        InfoRow(label: "Current Version", value: "Unknown")
                    }

                    HStack {
                        Text("Update Channel")
                            .font(AppTypography.style(.subheadline, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Text("Stable")
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.white.opacity(0.15))
                            )
                    }

                    updateStatusView

                    if case .updateAvailable = updateCheckStatus {
                        Button(action: { showAutomaticFirmwareUpdate = true }) {
                            SettingsButton(title: "Update Now", icon: "arrow.up.circle.fill")
                        }
                    }

                    Button(action: { Task { await checkForStableUpdate() } }) {
                        SettingsButton(title: "Check for Update", icon: "arrow.clockwise")
                    }

                    Button(action: { showFirmwareUpdate = true }) {
                        SettingsButton(title: "Manual Update", icon: "arrow.up.circle")
                    }
                }
            }
            
            SettingsCard(title: "Power Control") {
                VStack(spacing: 12) {
                    PowerToggleRow(isOn: $isOn, device: device)
                        .environmentObject(viewModel)

                    Button(action: { Task { await viewModel.rebootDevice(device) } }) {
                        SettingsButton(
                            title: isRebootWaitActive ? "Rebooting... \(max(0, rebootWaitRemainingSeconds))s" : "Reboot Device",
                            icon: "arrow.clockwise.circle"
                        )
                    }
                    .disabled(isRebootWaitActive)
                }
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
                            .font(AppTypography.style(.caption))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading WiFi information...")
                                .font(AppTypography.style(.subheadline))
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
                    .font(AppTypography.style(.subheadline, weight: .semibold))
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
                            .font(AppTypography.style(.subheadline))
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
                                            .font(AppTypography.style(.subheadline, weight: .medium))
                                            .foregroundColor(.green)
                                        
                                        Text("Connected")
                                            .font(AppTypography.style(.subheadline, weight: .medium))
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                Text("Tap 'Scan' to see all available networks")
                                    .font(AppTypography.style(.caption))
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
                                                .font(AppTypography.style(.subheadline, weight: .medium))
                                                .foregroundColor(.white)
                                            
                                            Text("No password required for \(network.ssid)")
                                                .font(AppTypography.style(.caption))
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
                                                .font(AppTypography.style(.subheadline, weight: .medium))
                                                .foregroundColor(.white)
                                            
                                            SecureField("Enter password", text: $password)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .font(AppTypography.style(.subheadline))
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
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
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
                                                .font(AppTypography.style(.caption))
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
                                                        .font(AppTypography.style(.caption))
                                                        .foregroundColor(.white.opacity(0.8))
                                                }
                                            case .connected:
                                                HStack {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.green)
                                                    Text("Successfully connected!")
                                                        .font(AppTypography.style(.caption))
                                                        .foregroundColor(.green)
                                                }
                                            case .failed(let message):
                                                HStack {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .foregroundColor(.red)
                                                    Text("Failed: \(message)")
                                                        .font(AppTypography.style(.caption))
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
                        .font(AppTypography.style(.subheadline, weight: .semibold))
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

            if supportsCCTInSettings {
                SettingsCard(title: "Temperature") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use CCT for temperature stops", isOn: $temperatureStopsUseCCT)
                            .tint(.white)
                            .foregroundColor(.white)
                            .onChange(of: temperatureStopsUseCCT) { _, value in
                                viewModel.setTemperatureStopsUseCCT(value, for: device)
                            }
                        Text("Enabled: temperature-only stops send CCT per segment. Disabled: temperature maps to RGB.")
                            .font(AppTypography.style(.caption))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
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

    private var maxDeviceSegments: Int {
        let fromInfo = info?.leds.maxseg ?? 0
        if fromInfo > 0 { return fromInfo }
        return max(1, viewModel.deviceMaxSegmentCapacity(for: activeDevice))
    }

    private var maxDeviceSegmentsSourceLabel: String {
        let fromInfo = info?.leds.maxseg ?? 0
        return fromInfo > 0 ? "firmware" : "estimated"
    }

    private var maxUsableSegments: Int {
        max(1, min(viewModel.totalLEDCount(for: activeDevice), maxDeviceSegments))
    }

    private var currentActiveSegments: Int {
        max(1, viewModel.getSegmentCount(for: activeDevice))
    }

    private var recommendedSegmentCount: Int {
        min(maxUsableSegments, viewModel.recommendedActiveSegmentCount(for: activeDevice))
    }

    private var editableSegments: [(id: Int, start: Int, stop: Int, color: Color)] {
        guard let segments = activeDevice.state?.segments, !segments.isEmpty else {
            return []
        }
        return segments.enumerated().map { index, segment in
            let id = segment.id ?? index
            let start = segment.start ?? 0
            let stop = segment.stop ?? max(start, (segment.len ?? 1) + start)
            let fallback = segment.colors?.first.map { Color.color(fromRGBArray: $0) } ?? activeDevice.currentColor
            return (id: id, start: start, stop: stop, color: fallback)
        }
        .sorted { lhs, rhs in lhs.id < rhs.id }
    }

    private var segmentsSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "1) Segment Info") {
                VStack(spacing: 12) {
                    InfoRow(label: "Max Segments (Device)", value: "\(maxDeviceSegments)")
                    InfoRow(label: "Max Source", value: maxDeviceSegmentsSourceLabel)
                    InfoRow(label: "Current Active Segments", value: "\(currentActiveSegments)")
                    InfoRow(label: "Max Usable (LED Count Cap)", value: "\(maxUsableSegments)")
                    InfoRow(label: "Recommended Active", value: "\(recommendedSegmentCount)")
                    Text("Recommended defaults to about 18 active segments when supported, reducing preset size while keeping gradients smooth.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsCard(title: "2) Active Segment Count") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper(
                        value: $activeSegmentCountDraft,
                        in: 1...maxUsableSegments,
                        step: 1
                    ) {
                        HStack {
                            Text("Active Segments")
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(activeSegmentCountDraft)")
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .tint(.white)

                    Text("This controls segment density used by app-managed gradients and effects for this device.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))

                    Button(action: applyActiveSegmentCountSetting) {
                        HStack(spacing: 8) {
                            if isApplyingSegmentCount {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                            }
                            Text("Apply Segment Count")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                    .disabled(isApplyingSegmentCount)

                    Toggle("Show segment controls in Colors tab (Advanced UI)", isOn: $showSegmentControlsInColorTabAdvanced)
                        .tint(.white)
                        .foregroundColor(.white)

                    if let segmentSettingsMessage {
                        Text(segmentSettingsMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(segmentSettingsMessageIsError ? .orange : .green)
                    }
                }
            }

            SettingsCard(title: "3) Segment Detail Edit (Temporary Override)") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Manual segment color edits are temporary overrides. Applying color/gradient from the Colors tab will replace them.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))

                    if editableSegments.isEmpty {
                        Text("No segments detected yet. Refresh device state and try again.")
                            .font(AppTypography.style(.footnote))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        ForEach(editableSegments, id: \.id) { segment in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Segment \(segment.id + 1)")
                                        .font(AppTypography.style(.subheadline, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("LED \(segment.start)-\(segment.stop)")
                                        .font(AppTypography.style(.caption))
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(segmentColorDrafts[segment.id] ?? segment.color)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                        )

                                    ColorPicker(
                                        "Color",
                                        selection: colorDraftBinding(segmentId: segment.id, fallback: segment.color),
                                        supportsOpacity: false
                                    )
                                    .labelsHidden()

                                    Spacer(minLength: 8)

                                    Button {
                                        applySegmentColorOverride(segmentId: segment.id, fallback: segment.color)
                                    } label: {
                                        HStack(spacing: 6) {
                                            if applyingSegmentColorIds.contains(segment.id) {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                                    .tint(.black)
                                            }
                                            Text("Apply")
                                                .font(AppTypography.style(.caption, weight: .semibold))
                                                .foregroundColor(.black)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Color.white)
                                        .cornerRadius(8)
                                    }
                                    .disabled(applyingSegmentColorIds.contains(segment.id))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    if advancedUIEnabled {
                        Divider()
                            .background(Color.white.opacity(0.15))
                            .padding(.vertical, 4)

                        Toggle(
                            "Manual segment layout",
                            isOn: Binding(
                                get: { viewModel.isManualSegmentationEnabled(for: device.id) },
                                set: { value in
                                    viewModel.setManualSegmentationEnabled(value, for: device.id)
                                }
                            )
                        )
                        .tint(.white)
                        .foregroundColor(.white)
                        Text("Manual layout preserves custom segment bounds. Auto layout is used by app-managed gradient rendering.")
                            .font(AppTypography.style(.caption))
                            .foregroundColor(.white.opacity(0.7))

                        if viewModel.isManualSegmentationEnabled(for: device.id) {
                            SegmentBoundsRow(
                                device: activeDevice,
                                segmentId: 0,
                                start: segStart,
                                stop: segStop
                            )
                            .environmentObject(viewModel)
                        }
                    }
                }
            }
        }
    }
    
    private var uiSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Advanced UI") {
                Toggle("Enable Advanced UI", isOn: $advancedUIEnabled)
                    .tint(.white)
                    .foregroundColor(.white)
                    .onChange(of: advancedUIEnabled) { _, newValue in
                        if !newValue {
                            viewModel.resetManualSegmentationForAllDevices()
                        }
                    }
            }
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
                    Button(action: syncDeviceTimeFromPhone) {
                        HStack(spacing: 10) {
                            if isSyncingDeviceTime {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                            } else {
                                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
                                    .foregroundColor(.black)
                            }

                            Text("Sync Device Time/Timezone from Phone")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSyncingDeviceTime)

                    if let deviceTimeSyncMessage {
                        Text(deviceTimeSyncMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(deviceTimeSyncMessageIsError ? .orange : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SettingsCard(title: "Native Timers") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timer slots 1-8 are available here for basic preset scheduling. Sunrise and sunset remain managed by the app's automation flow and WLED solar slots.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))

                    if isLoadingTimers {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading timers...")
                                .font(AppTypography.style(.subheadline))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    } else {
                        ForEach(Array(timerDrafts.enumerated()), id: \.element.id) { index, draft in
                            TimerSlotEditorCard(
                                draft: Binding(
                                    get: { timerDrafts[index] },
                                    set: { timerDrafts[index] = $0 }
                                ),
                                isSaving: savingTimerSlotIds.contains(draft.id),
                                onSave: {
                                    commitTimerDraft(slotId: draft.id)
                                }
                            )
                        }
                    }

                    Button(action: {
                        Task { await loadTimersAndMacros() }
                    }) {
                        Text("Refresh Timers & Macros")
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white)
                            .cornerRadius(10)
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
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white)
                        .cornerRadius(10)
                }
            }

            SettingsCard(title: "Macro Triggers") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("0 disables the trigger. These are native WLED hardware and Alexa hooks, not app automations.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))

                    IntStepperRow(title: "Button Press", value: $macroButtonPress, range: 0...250, onEnd: commitMacroBindings)
                    IntStepperRow(title: "Button Long Press", value: $macroButtonLongPress, range: 0...250, onEnd: commitMacroBindings)
                    IntStepperRow(title: "Button Double Press", value: $macroButtonDoublePress, range: 0...250, onEnd: commitMacroBindings)
                    IntStepperRow(title: "Alexa On", value: $macroAlexaOn, range: 0...250, onEnd: commitMacroBindings)
                    IntStepperRow(title: "Alexa Off", value: $macroAlexaOff, range: 0...250, onEnd: commitMacroBindings)
                    IntStepperRow(title: "Night Light End", value: $macroNightLight, range: 0...250, onEnd: commitMacroBindings)

                    Button(action: commitMacroBindings) {
                        HStack(spacing: 8) {
                            if isSavingMacroBindings {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                            }
                            Text("Apply Macro Triggers")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSavingMacroBindings)
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
                            .font(AppTypography.style(.headline, weight: .semibold))
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
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color.white)
                                .cornerRadius(10)
                        }
                        
                        Button(action: { Task { await WLEDAPIService.shared.clearCache() } }) {
                            Text("Clear Cache")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
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

    private func syncDeviceTimeFromPhone() {
        guard !isSyncingDeviceTime else { return }

        isSyncingDeviceTime = true
        deviceTimeSyncMessage = nil
        deviceTimeSyncMessageIsError = false

        Task {
            defer {
                Task { @MainActor in
                    isSyncingDeviceTime = false
                }
            }

            var coordinate = await AutomationStore.shared.currentCoordinate()
            if coordinate == nil {
                let existingReference = try? await WLEDAPIService.shared.fetchSolarReference(for: device)
                coordinate = existingReference?.coordinate
            }

            do {
                try await WLEDAPIService.shared.updateDeviceTimeSettings(
                    for: device,
                    timeZone: .current,
                    coordinate: coordinate
                )
                await MainActor.run {
                    deviceTimeSyncMessageIsError = false
                    if coordinate == nil {
                        deviceTimeSyncMessage = "Device time/timezone synced. Location was unchanged."
                    } else {
                        deviceTimeSyncMessage = "Device time/timezone synced from phone."
                    }
                }
                await loadState()
            } catch {
                await MainActor.run {
                    deviceTimeSyncMessageIsError = true
                    deviceTimeSyncMessage = "Sync failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func commitTimerDraft(slotId: Int) {
        guard let draft = timerDrafts.first(where: { $0.id == slotId }) else { return }
        savingTimerSlotIds.insert(slotId)

        Task {
            defer {
                Task { @MainActor in
                    savingTimerSlotIds.remove(slotId)
                }
            }

            let update = WLEDTimerUpdate(
                id: draft.id,
                enabled: draft.enabled,
                hour: max(0, min(23, draft.hour)),
                minute: max(0, min(59, draft.minute)),
                days: WeekdayMask.wledDow(fromSunFirst: draft.weekdays),
                macroId: max(0, min(250, draft.macroId)),
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )

            try? await WLEDAPIService.shared.updateTimer(update, on: device)
            await loadTimersAndMacros()
        }
    }

    private func commitMacroBindings() {
        isSavingMacroBindings = true
        Task {
            defer {
                Task { @MainActor in
                    isSavingMacroBindings = false
                }
            }

            try? await WLEDAPIService.shared.updateMacroBindings(
                WLEDMacroBindingsUpdate(
                    buttonPressMacro: macroButtonPress,
                    buttonLongPressMacro: macroButtonLongPress,
                    buttonDoublePressMacro: macroButtonDoublePress,
                    alexaOnMacro: macroAlexaOn,
                    alexaOffMacro: macroAlexaOff,
                    nightLightMacro: macroNightLight
                ),
                for: device
            )
            await loadTimersAndMacros()
        }
    }

    private func loadTimersAndMacros() async {
        await MainActor.run {
            isLoadingTimers = true
        }

        async let timersTask = WLEDAPIService.shared.fetchTimers(for: device)
        async let macrosTask = WLEDAPIService.shared.fetchMacroBindings(for: device)

        let timers = try? await timersTask
        let macros = try? await macrosTask

        await MainActor.run {
            if let timers {
                var timerById: [Int: WLEDTimer] = [:]
                for timer in timers {
                    timerById[timer.id] = timer
                }
                timerDrafts = NativeTimerDraft.standardDefaults.map { fallback in
                    guard let timer = timerById[fallback.id] else { return fallback }
                    return NativeTimerDraft(timer: timer)
                }
            }

            if let macros {
                macroButtonPress = macros.buttonPressMacro
                macroButtonLongPress = macros.buttonLongPressMacro
                macroButtonDoublePress = macros.buttonDoublePressMacro
                macroAlexaOn = macros.alexaOnMacro
                macroAlexaOff = macros.alexaOffMacro
                macroNightLight = macros.nightLightMacro
            }

            isLoadingTimers = false
        }
    }
    
    private func loadState() async {
        isLoading = true
        defer { isLoading = false }
        
        // CRITICAL: Get live device from ViewModel immediately to avoid using stale snapshot
        // The device parameter passed to this view is a snapshot and may be outdated
        // Since viewModel is @MainActor, we can access devices directly
        let liveDevice = await MainActor.run {
            return viewModel.devices.first(where: { $0.id == device.id })
        }
        
        guard let liveDevice = liveDevice else {
            // Fallback to snapshot device if not found in ViewModel
            await MainActor.run {
        isOn = device.isOn
                let effectiveBrightness = viewModel.getEffectiveBrightness(for: device)
                brightnessDouble = Double(effectiveBrightness) / 255.0 * 100.0
        segStart = 0
        segStop = device.state?.segments.first?.len ?? segStop
                activeSegmentCountDraft = viewModel.preferredActiveSegmentCount(for: device)
                seedSegmentColorDrafts(from: device.state?.segments)
            }
            return
        }
        
        // Use live device for all state initialization
        await MainActor.run {
            isOn = liveDevice.isOn
            // CRITICAL: Use effective brightness (preserved brightness if device is off)
            let effectiveBrightness = viewModel.getEffectiveBrightness(for: liveDevice)
            brightnessDouble = Double(effectiveBrightness) / 255.0 * 100.0
            segStart = 0
            segStop = liveDevice.state?.segments.first?.len ?? segStop
            temperatureStopsUseCCT = viewModel.temperatureStopsUseCCT(for: device)
            activeSegmentCountDraft = viewModel.preferredActiveSegmentCount(for: liveDevice)
            seedSegmentColorDrafts(from: liveDevice.state?.segments)
        }
        
        do {
            let resp = try await WLEDAPIService.shared.getState(for: liveDevice)
            await MainActor.run {
                info = resp.info
                isOn = resp.state.isOn
                
                // CRITICAL: Always use getEffectiveBrightness from live device to get the correct brightness
                // This ensures consistency with the initial brightness set above and handles
                // preserved brightness correctly when device is off
                // Get the updated device from the ViewModel again to ensure we have the absolute latest state
                if let updatedDevice = viewModel.devices.first(where: { $0.id == device.id }) {
                    let effectiveBrightness = viewModel.getEffectiveBrightness(for: updatedDevice)
                    brightnessDouble = Double(effectiveBrightness) / 255.0 * 100.0
                } else {
                    // Fallback: Use API response brightness if device not found in ViewModel
                    let deviceBrightness = resp.state.brightness
                    if !resp.state.isOn && deviceBrightness == 0 {
                        let preservedBrightness = viewModel.getPreservedBrightness(for: device.id) ?? 128
                        brightnessDouble = Double(preservedBrightness) / 255.0 * 100.0
                    } else {
                        brightnessDouble = Double(deviceBrightness) / 255.0 * 100.0
                    }
                }
                if let len = resp.state.segments.first?.len { segStop = len }
                temperatureStopsUseCCT = viewModel.temperatureStopsUseCCT(for: device)
                activeSegmentCountDraft = viewModel.preferredActiveSegmentCount(for: activeDevice)
                seedSegmentColorDrafts(from: resp.state.segments)
            }
        } catch { }

        await loadTimersAndMacros()
    }

    private var supportsCCTInSettings: Bool {
        if viewModel.supportsCCT(for: device, segmentId: 0) {
            return true
        }
        if let info = info {
            if info.leds.cct == true {
                return true
            }
            if let lc = info.leds.lc, (lc & 0b100) != 0 {
                return true
            }
            if let seglc = info.leds.seglc, seglc.contains(where: { ($0 & 0b100) != 0 }) {
                return true
            }
        }
        return false
    }

    private func seedSegmentColorDrafts(from segments: [Segment]?) {
        guard let segments, !segments.isEmpty else {
            segmentColorDrafts = [:]
            return
        }
        var drafts: [Int: Color] = [:]
        for (index, segment) in segments.enumerated() {
            let id = segment.id ?? index
            let color = segment.colors?.first.map { Color.color(fromRGBArray: $0) } ?? activeDevice.currentColor
            drafts[id] = color
        }
        segmentColorDrafts = drafts
    }

    private func colorDraftBinding(segmentId: Int, fallback: Color) -> Binding<Color> {
        Binding<Color>(
            get: {
                segmentColorDrafts[segmentId] ?? fallback
            },
            set: { newValue in
                segmentColorDrafts[segmentId] = newValue
            }
        )
    }

    private func applyActiveSegmentCountSetting() {
        isApplyingSegmentCount = true
        segmentSettingsMessage = nil
        segmentSettingsMessageIsError = false

        Task {
            let success = await viewModel.applyActiveSegmentCount(activeSegmentCountDraft, for: activeDevice)
            await MainActor.run {
                isApplyingSegmentCount = false
                segmentSettingsMessage = success ? "Segment count updated." : "Failed to update segment count."
                segmentSettingsMessageIsError = !success
            }
            if success {
                await loadState()
            }
        }
    }

    private func applySegmentColorOverride(segmentId: Int, fallback: Color) {
        let selectedColor = segmentColorDrafts[segmentId] ?? fallback
        applyingSegmentColorIds.insert(segmentId)

        Task {
            let success = await viewModel.applySegmentColorOverride(
                device: activeDevice,
                segmentId: segmentId,
                color: selectedColor
            )
            await MainActor.run {
                applyingSegmentColorIds.remove(segmentId)
                segmentSettingsMessage = success
                    ? "Segment \(segmentId + 1) color override applied."
                    : "Failed to apply Segment \(segmentId + 1) color override."
                segmentSettingsMessageIsError = !success
            }
            if success {
                await loadState()
            }
        }
    }

    // MARK: - Firmware Update Helpers

    private var updateStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch updateCheckStatus {
            case .idle:
                Text("Check for updates on the stable channel.")
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(.white.opacity(0.7))
            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking for updates...")
                        .font(AppTypography.style(.subheadline))
                        .foregroundColor(.white.opacity(0.8))
                }
            case .upToDate(let current, let latest):
                Text("Your device is up to date.")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                Text("Version \(current) (latest \(latest))")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
            case .updateAvailable(let current, let latest):
                Text("Update available.")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                Text("Current \(current) → Latest \(latest)")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
            case .error(let message):
                Text(message)
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(.white.opacity(0.75))
            }

            if let lastUpdateCheck {
                Text("Last checked \(lastUpdateCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkForStableUpdate() async {
        guard let currentVersion = info?.ver, !currentVersion.isEmpty else {
            await MainActor.run {
                updateCheckStatus = .error("Current version unavailable.")
            }
            return
        }

        await MainActor.run {
            updateCheckStatus = .checking
        }

        do {
            let latest = try await WLEDUpdateService.shared.fetchLatestStableVersion()
            let comparison = VersionComparator.compare(currentVersion, latest)
            let hasBetaSuffix = currentVersion.contains("-b")

            await MainActor.run {
                latestStableVersion = latest
                lastUpdateCheck = Date()
                if comparison == .orderedAscending || (comparison == .orderedSame && hasBetaSuffix) {
                    updateCheckStatus = .updateAvailable(current: currentVersion, latest: latest)
                } else {
                    updateCheckStatus = .upToDate(current: currentVersion, latest: latest)
                }
            }
        } catch {
            await MainActor.run {
                lastUpdateCheck = Date()
                updateCheckStatus = .error("Could not check for updates.")
            }
        }
    }
    
    // MARK: - WiFi Helper Functions
    
    private func loadCurrentWiFiInfo() async {
        do {
            let wifiInfo = try await WLEDWiFiService.shared.getCurrentWiFiInfo(device: device)
            await MainActor.run {
                if let previous = self.currentWiFiInfo,
                   isUnknownWiFiValue(wifiInfo.ssid),
                   !isUnknownWiFiValue(previous.ssid) {
                    self.currentWiFiInfo = WiFiInfo(
                        ssid: previous.ssid,
                        signalStrength: wifiInfo.signalStrength,
                        channel: wifiInfo.channel,
                        security: isUnknownWiFiValue(wifiInfo.security) ? previous.security : wifiInfo.security,
                        ipAddress: wifiInfo.ipAddress ?? previous.ipAddress,
                        macAddress: wifiInfo.macAddress ?? previous.macAddress
                    )
                } else {
                    self.currentWiFiInfo = wifiInfo
                }
            }
        } catch {
            #if DEBUG
            print("Failed to load WiFi info: \(error)")
            #endif
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
                    #if DEBUG
                    print("Failed to scan networks: \(error)")
                    #endif
                }
            }
        }
    }

    private func isUnknownWiFiValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("unknown") == .orderedSame
    }
    
    private func selectNetwork(_ network: WiFiNetwork) {
        selectedNetwork = network
        password = ""
        connectionStatus = .idle
    }

    @MainActor
    private func commitDeviceRenameFromHeader() async {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            editingName = activeDevice.name
            isEditingName = false
            return
        }

        guard trimmed != activeDevice.name else {
            editingName = activeDevice.name
            isEditingName = false
            return
        }

        await viewModel.renameDevice(activeDevice, to: trimmed)

        if viewModel.currentError == nil {
            editingName = trimmed
            isEditingName = false
            showPostRenameWiFiPrompt = true
            return
        }

        isEditingName = false
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
                    .font(AppTypography.style(.headline, weight: .semibold))
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
                .font(AppTypography.style(.headline, weight: .medium))
                .frame(width: 20)
            
            Text(title)
                .foregroundColor(.white)
                .font(AppTypography.style(.headline, weight: .medium))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
                .font(AppTypography.style(.caption, weight: .medium))
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
                .font(AppTypography.style(.headline, weight: .semibold))
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

private struct NativeTimerDraft: Identifiable, Equatable {
    let id: Int
    var enabled: Bool
    var hour: Int
    var minute: Int
    var weekdays: [Bool]
    var macroId: Int

    static let standardDefaults: [NativeTimerDraft] = (0..<8).map {
        NativeTimerDraft(
            id: $0,
            enabled: false,
            hour: 18,
            minute: 0,
            weekdays: WeekdayMask.allDaysSunFirst,
            macroId: 0
        )
    }

    init(id: Int, enabled: Bool, hour: Int, minute: Int, weekdays: [Bool], macroId: Int) {
        self.id = id
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.weekdays = WeekdayMask.normalizeSunFirst(weekdays)
        self.macroId = macroId
    }

    init(timer: WLEDTimer) {
        self.init(
            id: timer.id,
            enabled: timer.enabled,
            hour: timer.hour == 255 || timer.hour == 24 ? 0 : max(0, min(23, timer.hour)),
            minute: max(0, min(59, timer.minute)),
            weekdays: WeekdayMask.sunFirst(fromWLEDDow: timer.days),
            macroId: timer.macroId
        )
    }

    var timeLabel: String {
        String(format: "%02d:%02d", max(0, min(23, hour)), max(0, min(59, minute)))
    }

    var weekdaySummary: String {
        let names = ["S", "M", "T", "W", "T", "F", "S"]
        let selected = weekdays.enumerated().compactMap { index, enabled in
            enabled ? names[index] : nil
        }
        return selected.isEmpty ? "No days" : selected.joined(separator: " ")
    }
}

private struct TimerSlotEditorCard: View {
    @Binding var draft: NativeTimerDraft
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timer \(draft.id + 1)")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(draft.timeLabel)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Toggle("", isOn: $draft.enabled)
                    .labelsHidden()
                    .tint(.white)
            }

            HStack(spacing: 12) {
                IntStepperMini(title: "Hour", value: $draft.hour, range: 0...23)
                IntStepperMini(title: "Minute", value: $draft.minute, range: 0...59)
                IntStepperMini(title: "Preset", value: $draft.macroId, range: 0...250)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Days")
                    .font(AppTypography.style(.caption2, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let labels = ["S", "M", "T", "W", "T", "F", "S"]
                        Button {
                            draft.weekdays[dayIndex].toggle()
                        } label: {
                            Text(labels[dayIndex])
                                .font(AppTypography.style(.caption, weight: .semibold))
                                .foregroundColor(draft.weekdays[dayIndex] ? .black : .white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(draft.weekdays[dayIndex] ? Color.white : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(draft.enabled ? "Runs preset \(draft.macroId) on \(draft.weekdaySummary)" : "Disabled")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Button(action: onSave) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.black)
                        }
                        Text(draft.enabled ? "Save" : "Apply Disabled")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(10)
                }
                .disabled(isSaving)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

private struct IntStepperMini: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
            HStack(spacing: 8) {
                Button {
                    value = max(range.lowerBound, value - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Text("\(value)")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 28)

                Button {
                    value = min(range.upperBound, value + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
