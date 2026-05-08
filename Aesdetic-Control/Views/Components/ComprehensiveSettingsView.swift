//
//  ComprehensiveSettingsView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import CoreLocation
import SwiftUI
import UIKit

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
    @ObservedObject private var presetsStore = PresetsStore.shared
    @ObservedObject private var smartHomeStore = SmartHomeIntegrationStore.shared
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
    @State private var alexaEnabled: Bool = false
    @State private var alexaInvocationName: String = ""
    @State private var alexaPresetCount: Int = 0
    @State private var isLoadingAlexaSettings: Bool = false
    @State private var isSavingAlexaSettings: Bool = false
    @State private var alexaSettingsMessage: String?
    @State private var alexaSettingsMessageIsError: Bool = false
    @State private var showAlexaDiscoveryInstructions: Bool = false
    @State private var nativeIntegrationSettings: WLEDNativeIntegrationSettings = .defaults
    @State private var isLoadingNativeIntegrations: Bool = false
    @State private var isSavingNativeIntegrations: Bool = false
    @State private var nativeIntegrationsMessage: String?
    @State private var nativeIntegrationsMessageIsError: Bool = false
    @State private var isSyncingDeviceTime: Bool = false
    @State private var deviceTimeSyncMessage: String?
    @State private var deviceTimeSyncMessageIsError: Bool = false
    @State private var suppressUDPNUpdates: Bool = false
    @State private var activeSegmentCountDraft: Int = 1
    @State private var isApplyingSegmentCount: Bool = false
    @State private var segmentSettingsMessage: String?
    @State private var segmentSettingsMessageIsError: Bool = false
    @State private var segmentColorDrafts: [Int: Color] = [:]
    @State private var applyingSegmentColorIds: Set<Int> = []

    // New state variables for comprehensive settings
    @State private var selectedSettingsCategory: SettingsCategory = .overview
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
    @State private var advancedNetworkDraft = WLEDNetworkConfiguration()
    @State private var isLoadingAdvancedNetwork: Bool = false
    @State private var isSavingAdvancedNetwork: Bool = false
    @State private var advancedNetworkMessage: String?
    @State private var advancedNetworkMessageIsError: Bool = false
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @AppStorage("showSegmentControlsInColorTabAdvanced") private var showSegmentControlsInColorTabAdvanced: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    enum SettingsCategory: String, CaseIterable {
        case overview = "Overview"
        case wifiUpdates = "WiFi & Updates"
        case integrations = "Integrations"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .wifiUpdates: return "wifi"
            case .integrations: return "link"
            case .advanced: return "slider.horizontal.3"
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

    private var alexaFavoritesCount: Int {
        presetsStore.alexaFavorites(for: activeDevice.id).count
    }

    private var alexaIntegrationStatus: SmartHomeIntegrationStatus {
        smartHomeStore.status(for: .alexa, deviceId: activeDevice.id)
    }

    private var alexaAutoFillBinding: Binding<Bool> {
        Binding(
            get: { presetsStore.alexaAutoFillEnabled(for: activeDevice.id) },
            set: { presetsStore.setAlexaAutoFillEnabled($0, for: activeDevice.id) }
        )
    }

    init(device: WLEDDevice, initialCategory: SettingsCategory = .overview) {
        self.device = device
        self.initialCategory = initialCategory
        _selectedSettingsCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        ZStack {
            AppBackground()

            LiquidGlassOverlay(
                blurOpacity: 0.34,
                highlightOpacity: 0.14,
                verticalTopOpacity: 0.04,
                verticalBottomOpacity: 0.06,
                vignetteOpacity: 0.08,
                centerSheenOpacity: 0.04
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
                        case .overview:
                            overviewSection
                        case .wifiUpdates:
                            wifiUpdatesSection
                        case .integrations:
                            integrationsSection
                        case .advanced:
                            advancedSection
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
            await loadAdvancedNetworkConfiguration()
            scanForNetworks()
        }
        .sheet(isPresented: $showWebConfig) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/settings")!)
        }
        .sheet(isPresented: $showAutomaticFirmwareUpdate) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/update")!)
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
                    selectedSettingsCategory = .wifiUpdates
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
                    AppGlassIconButton(
                        systemName: isEditingName ? "xmark" : "pencil",
                        isProminent: false,
                        size: 38
                    ) {
                        if isEditingName {
                            isEditingName = false
                            editingName = activeDevice.name
                        } else {
                            isEditingName = true
                            editingName = activeDevice.name
                        }
                    }
                    .accessibilityLabel(isEditingName ? "Cancel rename" : "Rename device")

                    AppGlassIconButton(
                        systemName: "arrow.clockwise",
                        isProminent: false,
                        size: 38
                    ) {
                        Task { await loadState() }
                    }
                    .accessibilityLabel("Refresh settings")
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
                    AppGlassPillButton(
                        title: category.rawValue,
                        isSelected: selectedSettingsCategory == category,
                        iconName: category.icon,
                        useControlGlassRecipe: true,
                        useAppleSelectedStyle: true
                    ) {
                        selectedSettingsCategory = category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Settings Sections

    private var overviewSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Lamp Profile") {
                VStack(spacing: 12) {
                    InfoRow(label: "Lamp name", value: activeDevice.name)
                    InfoRow(label: "Room", value: activeDevice.location.displayName)
                    InfoRow(label: "Setup", value: activeDevice.setupState.displayName)
                    InfoRow(label: "Product", value: activeDevice.productType.displayName)
                    InfoRow(label: "Look", value: activeDevice.lookId ?? "Default")
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
                }
            }

            SettingsCard(title: "Status") {
                VStack(spacing: 12) {
                    InfoRow(label: "Connection", value: viewModel.isDeviceOnline(activeDevice) || activeDevice.isOnline ? "Online" : "Offline")
                    InfoRow(label: "Device address", value: activeDevice.ipAddress)
                    if let ver = info?.ver {
                        InfoRow(label: "Software version", value: ver)
                    }
                    if let deviceTime = info?.time, !deviceTime.isEmpty {
                        InfoRow(label: "Lamp clock", value: deviceTime)
                    } else {
                        InfoRow(label: "Lamp clock", value: "Unavailable")
                    }

                    if let wifiInfo = currentWiFiInfo {
                        InfoRow(label: "Network", value: wifiInfo.ssid)
                        InfoRow(label: "Signal", value: wifiSignalSummary(wifiInfo.signalStrength))
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading network status...")
                                .font(AppTypography.style(.subheadline))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                    }

                    Button(action: {
                        selectedSettingsCategory = .wifiUpdates
                        Task { await loadCurrentWiFiInfo() }
                    }) {
                        SettingsButton(title: "Manage Network & Updates", icon: "wifi")
                    }
                }
            }

            SettingsCard(title: "Setup & Support Actions") {
                VStack(spacing: 12) {
                    Button(action: syncDeviceTimeFromPhone) {
                        SyncLampClockButton(isSyncing: isSyncingDeviceTime)
                    }
                    .disabled(isSyncingDeviceTime)

                    if let deviceTimeSyncMessage {
                        Text(deviceTimeSyncMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(deviceTimeSyncMessageIsError ? .orange : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: { Task { await checkForStableUpdate() } }) {
                        SettingsButton(title: "Check for Software Update", icon: "arrow.clockwise")
                    }

                    Button(action: { showWebConfig = true }) {
                        SettingsButton(title: "Open Full WLED Web Settings", icon: "globe")
                    }

                    Button(action: { Task { await viewModel.rebootDevice(device) } }) {
                        SettingsButton(
                            title: isRebootWaitActive ? "Rebooting... \(max(0, rebootWaitRemainingSeconds))s" : "Restart Lamp",
                            icon: "arrow.clockwise.circle"
                        )
                    }
                    .disabled(isRebootWaitActive)
                }
            }
        }
    }

    private func wifiSignalSummary(_ rssi: Int) -> String {
        if rssi <= -100 {
            return "Unknown"
        }

        let quality: String
        switch rssi {
        case -49...0:
            quality = "Excellent"
        case -59..<(-49):
            quality = "Good"
        case -69..<(-59):
            quality = "Fair"
        default:
            quality = "Weak"
        }

        return "\(quality) (\(rssi) dBm)"
    }

    private var wifiUpdatesSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Current Network", content: {
                VStack(spacing: 12) {
                    if let wifiInfo = currentWiFiInfo {
                        InfoRow(label: "Network", value: wifiInfo.ssid)
                        InfoRow(label: "Signal", value: wifiSignalSummary(wifiInfo.signalStrength))
                        InfoRow(label: "Channel", value: "\(wifiInfo.channel)")
                        InfoRow(label: "Security", value: wifiInfo.security)

                        Text("To move this lamp to another network, choose a network below and connect again.")
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
                                await loadAdvancedNetworkConfiguration()
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

                                            SecureField("Enter network password", text: $password)
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

            SettingsCard(title: "Software Update") {
                VStack(spacing: 12) {
                    InfoRow(label: "Current version", value: info?.ver ?? "Unknown")

                    HStack {
                        Text("Update channel")
                            .font(AppTypography.style(.subheadline, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Text("Stable")
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                    }

                    updateStatusView

                    if case .updateAvailable = updateCheckStatus {
                        Button(action: { showAutomaticFirmwareUpdate = true }) {
                            SettingsButton(title: "Update Now", icon: "arrow.up.circle.fill")
                        }
                    }

                    Button(action: { Task { await checkForStableUpdate() } }) {
                        SettingsButton(title: "Check for Software Update", icon: "arrow.clockwise")
                    }

                    Button(action: { showFirmwareUpdate = true }) {
                        SettingsButton(title: "Manual Firmware Update", icon: "arrow.up.circle")
                    }
                }
            }

            advancedNetworkSection
        }
    }

    private var advancedNetworkSection: some View {
        SettingsCard(title: "Advanced Network") {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Expert network settings are for static IP, fallback hotspot, and WiFi radio behavior. Most customers should leave these unchanged.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isLoadingAdvancedNetwork {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading advanced network settings...")
                                .font(AppTypography.style(.subheadline))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }

                    AdvancedNetworkTextField(
                        title: "mDNS name",
                        placeholder: "lamp-name",
                        text: advancedNetworkBinding(\.mdnsName)
                    )
                    AdvancedNetworkTextField(
                        title: "Static IP",
                        placeholder: "0.0.0.0",
                        text: advancedNetworkBinding(\.staticIP),
                        keyboardType: .numbersAndPunctuation
                    )
                    AdvancedNetworkTextField(
                        title: "Gateway",
                        placeholder: "0.0.0.0",
                        text: advancedNetworkBinding(\.staticGateway),
                        keyboardType: .numbersAndPunctuation
                    )
                    AdvancedNetworkTextField(
                        title: "Subnet",
                        placeholder: "255.255.255.0",
                        text: advancedNetworkBinding(\.staticSubnet),
                        keyboardType: .numbersAndPunctuation
                    )
                    AdvancedNetworkTextField(
                        title: "DNS",
                        placeholder: "0.0.0.0",
                        text: advancedNetworkBinding(\.dnsServer),
                        keyboardType: .numbersAndPunctuation
                    )

                    Divider()
                        .background(Color.white.opacity(0.15))

                    AdvancedNetworkTextField(
                        title: "Fallback hotspot name",
                        placeholder: "WLED-AP",
                        text: advancedNetworkBinding(\.apSSID)
                    )
                    AdvancedNetworkTextField(
                        title: advancedNetworkDraft.apPasswordConfigured ? "New hotspot password" : "Hotspot password",
                        placeholder: advancedNetworkDraft.apPasswordConfigured ? "Leave blank to keep existing" : "8-63 characters",
                        text: advancedNetworkBinding(\.apPassword),
                        isSecure: true
                    )

                    Toggle("Hide fallback hotspot", isOn: advancedNetworkBinding(\.hideAP))
                        .tint(.white)
                        .foregroundColor(.white)

                    Stepper(
                        "Fallback hotspot channel: \(advancedNetworkDraft.apChannel)",
                        value: advancedNetworkBinding(\.apChannel),
                        in: 1...13
                    )
                    .tint(.white)
                    .foregroundColor(.white)

                    Stepper(
                        "Fallback hotspot behavior: \(advancedNetworkDraft.apBehavior)",
                        value: advancedNetworkBinding(\.apBehavior),
                        in: 0...4
                    )
                    .tint(.white)
                    .foregroundColor(.white)

                    Toggle("Disable WiFi sleep", isOn: advancedNetworkBinding(\.disableWiFiSleep))
                        .tint(.white)
                        .foregroundColor(.white)

                    Toggle("Force 802.11g compatibility", isOn: advancedNetworkBinding(\.force80211g))
                        .tint(.white)
                        .foregroundColor(.white)

                    Picker("WiFi transmit power", selection: advancedNetworkBinding(\.txPower)) {
                        Text("19.5 dBm").tag(78)
                        Text("19 dBm").tag(76)
                        Text("18.5 dBm").tag(74)
                        Text("17 dBm").tag(68)
                        Text("15 dBm").tag(60)
                        Text("13 dBm").tag(52)
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .foregroundColor(.white)

                    if let advancedNetworkMessage {
                        Text(advancedNetworkMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(advancedNetworkMessageIsError ? .orange : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        Button(action: {
                            Task { await loadAdvancedNetworkConfiguration() }
                        }) {
                            SettingsInlineButton(title: "Reload", icon: "arrow.clockwise")
                        }
                        .disabled(isLoadingAdvancedNetwork || isSavingAdvancedNetwork)

                        Button(action: saveAdvancedNetworkConfiguration) {
                            HStack(spacing: 8) {
                                if isSavingAdvancedNetwork {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.black)
                                }
                                Text("Save Network Settings")
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .cornerRadius(10)
                        }
                        .disabled(isSavingAdvancedNetwork)
                    }

                    Button(action: { openWLEDPath("/settings/wifi") }) {
                        SettingsButton(title: "Open WLED WiFi Settings", icon: "globe")
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.white.opacity(0.75))
                    Text("Static IP, fallback hotspot, radio options")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
            }
            .tint(.white)
        }
    }

    private var integrationsSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Alexa") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use Alexa for power, brightness, and color. Save these settings, then open the Alexa app and run Discover Devices.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    SmartHomeIntegrationStatusRow(status: alexaIntegrationStatus)

                    Toggle("Enable Alexa Control", isOn: $alexaEnabled)
                        .tint(.white)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Alexa Name")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        TextField("Bedroom Lights", text: $alexaInvocationName)
                            .settingsTextFieldChrome(theme: AppTheme.tokens(for: colorScheme))
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        InfoRow(label: "Alexa Favorites", value: "\(alexaFavoritesCount)/9")

                        Toggle("Automatically add new presets while space is available", isOn: alexaAutoFillBinding)
                            .settingsToggleStyle()

                        Button(action: {
                            alexaSettingsMessage = "Manage Alexa Favorites from this device's Presets tab."
                            alexaSettingsMessageIsError = false
                        }) {
                            SettingsButton(title: "Manage Alexa Favorites", icon: "star.circle")
                        }
                    }

                    if isLoadingAlexaSettings {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("Loading Alexa settings...")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(.white.opacity(0.72))
                        }
                    }

                    if let alexaSettingsMessage {
                        Text(alexaSettingsMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(alexaSettingsMessageIsError ? .orange : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showAlexaDiscoveryInstructions {
                        AlexaDiscoveryInstructionsView()
                    }

                    Button(action: saveAlexaIntegrationSettings) {
                        HStack(spacing: 8) {
                            if isSavingAlexaSettings {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                            }
                            Text("Save Alexa Setup")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                    .disabled(isSavingAlexaSettings || alexaInvocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Optional WLED macro hooks. Set a preset number to run when Alexa turns this device on or off; use 0 to leave the action disabled.")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(.white.opacity(0.7))

                            IntStepperRow(title: "Alexa On Action", value: $macroAlexaOn, range: 0...250, onEnd: commitMacroBindings)
                            IntStepperRow(title: "Alexa Off Action", value: $macroAlexaOff, range: 0...250, onEnd: commitMacroBindings)

                            Button(action: commitMacroBindings) {
                                HStack(spacing: 8) {
                                    if isSavingMacroBindings {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.black)
                                    }
                                    Text("Save Alexa Actions")
                                        .font(AppTypography.style(.subheadline, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(10)
                            }
                            .disabled(isSavingMacroBindings)
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.white.opacity(0.75))
                            Text("Advanced Alexa Actions")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .tint(.white)
                }
            }

            SettingsCard(title: "Home Assistant") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Home Assistant is the best hub path for advanced automations and for bridging this light to Apple Home or Google Home.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    InfoRow(label: "Device IP", value: activeDevice.ipAddress)
                    InfoRow(label: "Setup type", value: "Add WLED integration in Home Assistant")

                    Button(action: { openExternalURL("https://www.home-assistant.io/integrations/wled/") }) {
                        SettingsButton(title: "Open Home Assistant Guide", icon: "house")
                    }
                }
            }

            SettingsCard(title: "Apple Home & Google Home") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WLED does not connect directly to Apple Home or Google Home. Use Home Assistant or Homebridge as the bridge, then keep advanced effects in Aesdetic.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    InfoRow(label: "Apple Home", value: "Use Home Assistant HomeKit Bridge")
                    InfoRow(label: "Google Home", value: "Expose from Home Assistant")

                    Button(action: { openExternalURL("https://www.home-assistant.io/integrations/homekit/") }) {
                        SettingsButton(title: "Apple Home Bridge Guide", icon: "homekit")
                    }
                    Button(action: { openExternalURL("https://www.home-assistant.io/integrations/google_assistant/") }) {
                        SettingsButton(title: "Google Home Guide", icon: "person.wave.2")
                    }
                }
            }

            SettingsCard(title: "Advanced Integrations") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Native WLED protocol settings for multi-controller sync, MQTT brokers, Hue polling, DDP, E1.31, Art-Net, and DMX-style realtime input.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isLoadingNativeIntegrations {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("Loading WLED integration settings...")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(.white.opacity(0.72))
                        }
                    }

                    if let nativeIntegrationsMessage {
                        Text(nativeIntegrationsMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(nativeIntegrationsMessageIsError ? .orange : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    nativeIntegrationControls

                    Button(action: saveNativeIntegrationSettings) {
                        HStack(spacing: 8) {
                            if isSavingNativeIntegrations {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                            }
                            Text("Save WLED Integration Settings")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSavingNativeIntegrations)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Button(action: { openWLEDPath("/settings/sync") }) {
                                SettingsButton(title: "Open WLED Sync Page", icon: "network")
                            }
                            Button(action: { openWLEDPath("/settings/dmx") }) {
                                SettingsButton(title: "Open WLED DMX Output Page", icon: "cable.connector")
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .foregroundColor(.white.opacity(0.75))
                            Text("Raw WLED Pages")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .tint(.white)
                }
            }

            SettingsCard(title: "Physical Controls & Extensions") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These are firmware-specific WLED options for buttons, IR receivers, relays, and usermods.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { openWLEDPath("/settings/leds") }) {
                        SettingsButton(title: "IR, Relay & Button Hardware", icon: "switch.2")
                    }
                    Button(action: { openWLEDPath("/settings/um") }) {
                        SettingsButton(title: "Open WLED Extensions", icon: "puzzlepiece")
                    }
                }
            }
        }
        .task {
            await loadAlexaIntegrationSettings()
            await loadNativeIntegrationSettings()
            await loadUDPSyncState()
        }
    }

    private var nativeIntegrationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    IntegrationNumberFieldRow(title: "WLED Broadcast Port", value: syncIntegrationBinding(\.udpPort), range: 1...65535)
                    IntegrationNumberFieldRow(title: "Secondary UDP Port", value: syncIntegrationBinding(\.secondaryUdpPort), range: 1...65535)

                    Toggle("Use ESP-NOW sync", isOn: syncIntegrationBinding(\.espNowEnabled))
                        .settingsToggleStyle()

                    IntegrationGroupMaskRow(title: "Send Groups", mask: syncIntegrationBinding(\.sendGroups))
                    IntegrationGroupMaskRow(title: "Receive Groups", mask: syncIntegrationBinding(\.receiveGroups))

                    Divider().background(Color.white.opacity(0.16))

                    Text("Receive")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))

                    IntegrationToggleGrid(items: [
                        IntegrationToggleItem(title: "Brightness", binding: syncIntegrationBinding(\.receiveBrightness)),
                        IntegrationToggleItem(title: "Color", binding: syncIntegrationBinding(\.receiveColor)),
                        IntegrationToggleItem(title: "Effects", binding: syncIntegrationBinding(\.receiveEffects)),
                        IntegrationToggleItem(title: "Palette", binding: syncIntegrationBinding(\.receivePalette)),
                        IntegrationToggleItem(title: "Segment Options", binding: syncIntegrationBinding(\.receiveSegmentOptions)),
                        IntegrationToggleItem(title: "Segment Bounds", binding: syncIntegrationBinding(\.receiveSegmentBounds))
                    ])

                    Divider().background(Color.white.opacity(0.16))

                    Text("Send")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))

                    IntegrationToggleGrid(items: [
                        IntegrationToggleItem(title: "On Start", binding: syncIntegrationBinding(\.sendOnStart)),
                        IntegrationToggleItem(title: "Direct Changes", binding: syncIntegrationBinding(\.sendDirectChanges)),
                        IntegrationToggleItem(title: "Button / IR", binding: syncIntegrationBinding(\.sendButtonChanges)),
                        IntegrationToggleItem(title: "Alexa Changes", binding: syncIntegrationBinding(\.sendAlexaChanges)),
                        IntegrationToggleItem(title: "Hue Changes", binding: syncIntegrationBinding(\.sendHueChanges))
                    ])

                    IntegrationNumberFieldRow(title: "UDP Retransmissions", value: syncIntegrationBinding(\.udpRetransmissions), range: 0...30)

                    Toggle("Enable instance list", isOn: syncIntegrationBinding(\.nodeListEnabled))
                        .settingsToggleStyle()
                    Toggle("Make this instance discoverable", isOn: syncIntegrationBinding(\.nodeBroadcastEnabled))
                        .settingsToggleStyle()
                }
                .padding(.top, 8)
            } label: {
                integrationDisclosureLabel("WLED Broadcast & Groups", icon: "dot.radiowaves.left.and.right")
            }
            .tint(.white)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Receive realtime data", isOn: realtimeIntegrationBinding(\.receiveRealtime))
                        .settingsToggleStyle()
                    Toggle("Use main segment only", isOn: realtimeIntegrationBinding(\.mainSegmentOnly))
                        .settingsToggleStyle()
                    Toggle("Respect LED maps", isOn: realtimeIntegrationBinding(\.respectLedMaps))
                        .settingsToggleStyle()

                    IntegrationPickerRow(title: "Network DMX Type", selection: realtimeProtocolBinding) {
                        ForEach(WLEDRealtimeProtocolMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if nativeIntegrationSettings.realtime.protocolMode == .custom {
                        IntegrationNumberFieldRow(title: "Custom Port", value: realtimeIntegrationBinding(\.port), range: 1...65535)
                    } else {
                        InfoRow(label: "Port", value: "\(nativeIntegrationSettings.realtime.protocolMode.rawValue)")
                    }

                    Toggle("Multicast", isOn: realtimeIntegrationBinding(\.multicast))
                        .settingsToggleStyle()
                    IntegrationNumberFieldRow(title: "Start Universe", value: realtimeIntegrationBinding(\.startUniverse), range: 0...63999)
                    Toggle("Skip out-of-sequence packets", isOn: realtimeIntegrationBinding(\.skipOutOfSequence))
                        .settingsToggleStyle()
                    IntegrationNumberFieldRow(title: "DMX Start Address", value: realtimeIntegrationBinding(\.dmxStartAddress), range: 1...510)
                    IntegrationNumberFieldRow(title: "DMX Segment Spacing", value: realtimeIntegrationBinding(\.dmxSegmentSpacing), range: 0...150)
                    IntegrationNumberFieldRow(title: "E1.31 Priority", value: realtimeIntegrationBinding(\.e131Priority), range: 0...200)

                    IntegrationPickerRow(title: "DMX Mode", selection: realtimeIntegrationBinding(\.dmxMode)) {
                        ForEach(WLEDDMXMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    IntegrationNumberFieldRow(title: "Realtime Timeout (ms)", value: realtimeIntegrationBinding(\.timeoutMs), range: 100...65000)
                    Toggle("Force max brightness", isOn: realtimeIntegrationBinding(\.forceMaxBrightness))
                        .settingsToggleStyle()
                    Toggle("Disable realtime gamma correction", isOn: realtimeIntegrationBinding(\.disableGammaCorrection))
                        .settingsToggleStyle()
                    IntegrationNumberFieldRow(title: "Realtime LED Offset", value: realtimeIntegrationBinding(\.ledOffset), range: -255...255)
                }
                .padding(.top, 8)
            } label: {
                integrationDisclosureLabel("Realtime Input, E1.31 & Art-Net", icon: "cable.connector")
            }
            .tint(.white)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable MQTT", isOn: mqttIntegrationBinding(\.enabled))
                        .settingsToggleStyle()
                    IntegrationTextFieldRow(title: "Broker", placeholder: "192.168.1.10", text: mqttIntegrationBinding(\.broker))
                    IntegrationNumberFieldRow(title: "Port", value: mqttIntegrationBinding(\.port), range: 1...65535)
                    IntegrationTextFieldRow(title: "Username", placeholder: "Optional", text: mqttIntegrationBinding(\.username))
                    IntegrationTextFieldRow(title: "Password", placeholder: "Leave blank to keep existing", text: mqttIntegrationBinding(\.password), secure: true)
                    IntegrationTextFieldRow(title: "Client ID", placeholder: activeDevice.name, text: mqttIntegrationBinding(\.clientID))
                    IntegrationTextFieldRow(title: "Device Topic", placeholder: "wled/device", text: mqttIntegrationBinding(\.deviceTopic))
                    IntegrationTextFieldRow(title: "Group Topic", placeholder: "wled/group", text: mqttIntegrationBinding(\.groupTopic))
                    Toggle("Publish button presses", isOn: mqttIntegrationBinding(\.publishButtonPresses))
                        .settingsToggleStyle()
                    Toggle("Retain brightness and color messages", isOn: mqttIntegrationBinding(\.retainMessages))
                        .settingsToggleStyle()

                    Text("MQTT credentials are sent to WLED over the local HTTP connection. Use a broker-specific password.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.orange.opacity(0.9))
                }
                .padding(.top, 8)
            } label: {
                integrationDisclosureLabel("MQTT Broker", icon: "server.rack")
            }
            .tint(.white)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Poll Philips Hue light", isOn: hueIntegrationBinding(\.enabled))
                        .settingsToggleStyle()
                    IntegrationTextFieldRow(title: "Hue Bridge IP", placeholder: "192.168.1.20", text: hueIntegrationBinding(\.bridgeIP))
                    IntegrationNumberFieldRow(title: "Hue Light ID", value: hueIntegrationBinding(\.lightID), range: 1...99)
                    IntegrationNumberFieldRow(title: "Poll Interval (ms)", value: hueIntegrationBinding(\.pollIntervalMs), range: 100...65000)
                    IntegrationToggleGrid(items: [
                        IntegrationToggleItem(title: "On / Off", binding: hueIntegrationBinding(\.receiveOnOff)),
                        IntegrationToggleItem(title: "Brightness", binding: hueIntegrationBinding(\.receiveBrightness)),
                        IntegrationToggleItem(title: "Color", binding: hueIntegrationBinding(\.receiveColor))
                    ])
                    Text("Press the Hue bridge link button before saving when pairing for the first time.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.68))
                }
                .padding(.top, 8)
            } label: {
                integrationDisclosureLabel("Philips Hue Sync", icon: "lightbulb.2")
            }
            .tint(.white)
        }
    }

    private var advancedSection: some View {
        VStack(spacing: 12) {
            SettingsDisclosureSection(
                title: "Product & Hardware Setup",
                subtitle: "One-time setup for product profile, LED output, GPIO, power limits, color order, and matrix hardware.",
                icon: "wrench.and.screwdriver"
            ) {
                Button(action: { showProductSetup = true }) {
                    SettingsButton(
                        title: activeDevice.setupState == .pendingSelection ? "Complete Product Setup" : "Change Product Setup",
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
                Button(action: { openWLEDPath("/settings/leds") }) {
                    SettingsButton(title: "WLED LED Hardware Setup", icon: "lightbulb")
                }
                Button(action: { openWLEDPath("/settings/2D") }) {
                    SettingsButton(title: "2D Matrix Setup", icon: "rectangle.grid.2x2")
                }
                if supportsCCTInSettings {
                    Toggle("Use native CCT for temperature stops", isOn: $temperatureStopsUseCCT)
                        .tint(.white)
                        .foregroundColor(.white)
                        .onChange(of: temperatureStopsUseCCT) { _, value in
                            viewModel.setTemperatureStopsUseCCT(value, for: device)
                        }
                    Text("Enabled sends temperature values directly to WLED when supported. Disabled maps temperature to RGB.")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            SettingsDisclosureSection(
                title: "LED Layout & Segments",
                subtitle: "Advanced segment density and manual overrides for installers or recovery.",
                icon: "square.split.2x2"
            ) {
                segmentsSection
            }

            SettingsDisclosureSection(
                title: "WLED Built-In Schedules",
                subtitle: "Native WLED timers, timed light, and clock setup. App automations stay in the detailed device view.",
                icon: "clock"
            ) {
                wledBuiltInSchedulesSection
            }

            SettingsDisclosureSection(
                title: "Protocols",
                subtitle: "Advanced native WLED protocols for external controllers and lighting networks.",
                icon: "network"
            ) {
                Button(action: { openWLEDPath("/settings/sync") }) {
                    SettingsButton(title: "Sync, MQTT, Hue, Art-Net, E1.31 & DDP", icon: "arrow.triangle.2.circlepath")
                }
                Button(action: { openWLEDPath("/settings/dmx") }) {
                    SettingsButton(title: "DMX Output Setup", icon: "cable.connector")
                }
                Button(action: { openWLEDPath("/settings/um") }) {
                    SettingsButton(title: "Extension Protocol Modules", icon: "puzzlepiece")
                }
            }

            SettingsDisclosureSection(
                title: "Diagnostics",
                subtitle: "Connection tools for troubleshooting stale state, cache, and realtime updates.",
                icon: "stethoscope"
            ) {
                diagnosticsSection
            }

            SettingsDisclosureSection(
                title: "Maintenance & Safety",
                subtitle: "Security, backup, manual firmware upload, and reset actions. Review carefully before changing.",
                icon: "exclamationmark.triangle",
                isWarning: true
            ) {
                maintenanceSection
            }

            SettingsDisclosureSection(
                title: "WLED Web Settings",
                subtitle: "Complete WLED web settings are kept here for expert support and firmware parity.",
                icon: "globe"
            ) {
                wledWebSettingsSection
            }

            SettingsDisclosureSection(
                title: "WLED Compatibility",
                subtitle: "Internal coverage map for native, guided, advanced, and web-fallback settings.",
                icon: "checklist"
            ) {
                firmwareCoverageSection
            }
        }
    }

    private var wledBuiltInSchedulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { openWLEDPath("/settings/time") }) {
                SettingsButton(title: "Open WLED Time Settings", icon: "clock")
            }

            Button(action: syncDeviceTimeFromPhone) {
                SyncLampClockButton(isSyncing: isSyncingDeviceTime)
            }
            .disabled(isSyncingDeviceTime)

            if let deviceTimeSyncMessage {
                Text(deviceTimeSyncMessage)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(deviceTimeSyncMessageIsError ? .orange : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Native WLED Timers")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                Text("Timer slots 1-8 are for direct WLED preset scheduling. Sunrise and sunset should stay in app automations.")
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
                    SettingsInlineButton(title: "Refresh Timers", icon: "arrow.clockwise")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Timed Light")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                Text("Native WLED timed-light behavior. Use app automations for normal wake and sleep routines.")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))

                Toggle("Enabled", isOn: $nightLightOn)
                    .tint(.white)
                    .foregroundColor(.white)
                IntStepperRow(title: "Duration (min)", value: $nightLightDurationMin, range: 1...255, onEnd: commitNightLight)
                IntStepperRow(title: "Mode", value: $nightLightMode, range: 0...3, onEnd: commitNightLight)
                IntStepperRow(title: "Target Brightness", value: $nightLightTargetBri, range: 0...255, onEnd: commitNightLight)

                Button(action: commitNightLight) {
                    SettingsInlineButton(title: "Apply Timed Light", icon: "timer")
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Realtime connection")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: Binding(get: { viewModel.isRealTimeEnabled }, set: { v in
                    if v { viewModel.enableRealTimeUpdates() } else { viewModel.disableRealTimeUpdates() }
                }))
                .labelsHidden()
                .tint(.white)
            }

            InfoRow(label: "Online status", value: viewModel.isDeviceOnline(activeDevice) || activeDevice.isOnline ? "Online" : "Offline")
            InfoRow(label: "Device address", value: activeDevice.ipAddress)
            InfoRow(label: "MAC address", value: activeDevice.id)

            HStack(spacing: 10) {
                Button(action: { Task { await viewModel.forceReconnection(device) } }) {
                    SettingsInlineButton(title: "Reconnect", icon: "arrow.triangle.2.circlepath")
                }

                Button(action: { Task { await WLEDAPIService.shared.clearCache() } }) {
                    SettingsInlineButton(title: "Clear Cache", icon: "trash")
                }
            }
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use backup before firmware uploads, reset, or raw WLED configuration changes.")
                .font(AppTypography.style(.caption))
                .foregroundColor(.orange.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { openWLEDPath("/settings/sec") }) {
                SettingsButton(title: "Security, PIN & OTA Locks", icon: "lock.shield")
            }
            Button(action: { openWLEDPath("/settings/sec#backup") }) {
                SettingsButton(title: "Backup & Restore", icon: "externaldrive")
            }
            Button(action: { showFirmwareUpdate = true }) {
                DangerSettingsButton(title: "Manual Firmware Upload", icon: "arrow.up.circle", level: .warning)
            }
            Button(action: { openWLEDPath("/json/cfg") }) {
                DangerSettingsButton(title: "Raw WLED Configuration", icon: "curlybraces", level: .warning)
            }
            Button(action: { openWLEDPath("/reset") }) {
                DangerSettingsButton(title: "Factory Reset", icon: "exclamationmark.triangle", level: .danger)
            }
        }
    }

    private var wledWebSettingsSection: some View {
        VStack(spacing: 12) {
            Button(action: { showWebConfig = true }) {
                SettingsButton(title: "All WLED Settings", icon: "slider.horizontal.3")
            }
            Button(action: { openWLEDPath("/settings/wifi") }) {
                SettingsButton(title: "WLED WiFi Settings", icon: "wifi")
            }
            Button(action: { openWLEDPath("/settings/leds") }) {
                SettingsButton(title: "WLED LED Settings", icon: "lightbulb")
            }
            Button(action: { openWLEDPath("/settings/2D") }) {
                SettingsButton(title: "WLED 2D Matrix Settings", icon: "rectangle.grid.2x2")
            }
            Button(action: { openWLEDPath("/settings/sync") }) {
                SettingsButton(title: "WLED Sync Settings", icon: "network")
            }
            Button(action: { openWLEDPath("/settings/time") }) {
                SettingsButton(title: "WLED Time Settings", icon: "clock")
            }
            Button(action: { openWLEDPath("/settings/um") }) {
                SettingsButton(title: "WLED Extensions", icon: "puzzlepiece")
            }
            Button(action: { openWLEDPath("/settings/sec") }) {
                SettingsButton(title: "WLED Security Settings", icon: "lock.shield")
            }
            Button(action: { openWLEDPath("/settings/ui") }) {
                SettingsButton(title: "WLED Web UI Settings", icon: "paintbrush")
            }
        }
    }

    private var firmwareCoverageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Customer-critical setup is native or guided. Expert WLED firmware pages stay available here without crowding the main settings flow.")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(WLEDFirmwareSettingsArea.overviewAreas) { area in
                FirmwareCoverageRow(area: area)
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
                    UDPTogglesRow(
                        udpSend: $udpSend,
                        udpRecv: $udpRecv,
                        suppressUpdates: $suppressUDPNUpdates,
                        device: activeDevice
                    )
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
        .task {
            await loadUDPSyncState()
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

    private func loadUDPSyncState() async {
        guard let state = await viewModel.fetchUDPSyncState(for: activeDevice) else { return }
        await MainActor.run {
            suppressUDPNUpdates = true
            udpSend = state.send
            udpRecv = state.recv
            DispatchQueue.main.async {
                suppressUDPNUpdates = false
            }
        }
    }

    private func syncIntegrationBinding<Value>(_ keyPath: WritableKeyPath<WLEDIntegrationSyncSettings, Value>) -> Binding<Value> {
        Binding(
            get: { nativeIntegrationSettings.sync[keyPath: keyPath] },
            set: { nativeIntegrationSettings.sync[keyPath: keyPath] = $0 }
        )
    }

    private func realtimeIntegrationBinding<Value>(_ keyPath: WritableKeyPath<WLEDIntegrationRealtimeSettings, Value>) -> Binding<Value> {
        Binding(
            get: { nativeIntegrationSettings.realtime[keyPath: keyPath] },
            set: { nativeIntegrationSettings.realtime[keyPath: keyPath] = $0 }
        )
    }

    private var realtimeProtocolBinding: Binding<WLEDRealtimeProtocolMode> {
        Binding(
            get: { nativeIntegrationSettings.realtime.protocolMode },
            set: { mode in
                nativeIntegrationSettings.realtime.protocolMode = mode
                if mode != .custom {
                    nativeIntegrationSettings.realtime.port = mode.rawValue
                }
            }
        )
    }

    private func mqttIntegrationBinding<Value>(_ keyPath: WritableKeyPath<WLEDIntegrationMQTTSettings, Value>) -> Binding<Value> {
        Binding(
            get: { nativeIntegrationSettings.mqtt[keyPath: keyPath] },
            set: { nativeIntegrationSettings.mqtt[keyPath: keyPath] = $0 }
        )
    }

    private func hueIntegrationBinding<Value>(_ keyPath: WritableKeyPath<WLEDIntegrationHueSettings, Value>) -> Binding<Value> {
        Binding(
            get: { nativeIntegrationSettings.hue[keyPath: keyPath] },
            set: { nativeIntegrationSettings.hue[keyPath: keyPath] = $0 }
        )
    }

    private func integrationDisclosureLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.75))
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
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

    private func loadAlexaIntegrationSettings() async {
        await MainActor.run {
            isLoadingAlexaSettings = true
            alexaSettingsMessage = nil
            alexaSettingsMessageIsError = false
        }

        do {
            let settings = try await WLEDAPIService.shared.fetchAlexaIntegrationSettings(for: activeDevice)
            await MainActor.run {
                alexaEnabled = settings.isEnabled
                alexaInvocationName = settings.invocationName
                alexaPresetCount = settings.exposedPresetCount
                viewModel.setAlexaIntegrationEnabled(settings.isEnabled, for: activeDevice.id)
                SmartHomeIntegrationStore.shared.setStatus(
                    settings.isEnabled ? .enabled : .notSetUp,
                    for: .alexa,
                    deviceId: activeDevice.id
                )
                isLoadingAlexaSettings = false
            }
        } catch {
            await MainActor.run {
                if alexaInvocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    alexaInvocationName = activeDevice.name
                }
                isLoadingAlexaSettings = false
                alexaSettingsMessage = "Could not load Alexa settings."
                alexaSettingsMessageIsError = true
                showAlexaDiscoveryInstructions = false
            }
        }
    }

    private func saveAlexaIntegrationSettings() {
        let trimmedName = alexaInvocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alexaSettingsMessage = "Add a name Alexa can discover."
            alexaSettingsMessageIsError = true
            return
        }

        isSavingAlexaSettings = true
        alexaSettingsMessage = nil
        alexaSettingsMessageIsError = false
        showAlexaDiscoveryInstructions = false

        Task {
            let success = await viewModel.syncAlexaFavoritesToDevice(
                activeDevice,
                enabled: alexaEnabled,
                invocationName: trimmedName
            )
            await MainActor.run {
                if success {
                    alexaInvocationName = String(trimmedName.prefix(32))
                    alexaPresetCount = alexaEnabled ? alexaFavoritesCount : 0
                    isSavingAlexaSettings = false
                    alexaSettingsMessage = alexaEnabled ? nil : "Alexa control disabled on this WLED device."
                    showAlexaDiscoveryInstructions = alexaEnabled
                    alexaSettingsMessageIsError = false
                } else {
                    isSavingAlexaSettings = false
                    let conflicts = viewModel.alexaMirrorConflictSlots(for: activeDevice)
                    alexaSettingsMessage = conflicts.isEmpty
                        ? "Could not save Alexa setup."
                        : "Alexa slots \(conflicts.map(String.init).joined(separator: ", ")) already contain WLED presets."
                    alexaSettingsMessageIsError = true
                    showAlexaDiscoveryInstructions = false
                }
            }
        }
    }

    private func loadNativeIntegrationSettings() async {
        await MainActor.run {
            isLoadingNativeIntegrations = true
            nativeIntegrationsMessage = nil
            nativeIntegrationsMessageIsError = false
        }

        do {
            let settings = try await WLEDAPIService.shared.fetchNativeIntegrationSettings(for: activeDevice)
            await MainActor.run {
                nativeIntegrationSettings = settings
                isLoadingNativeIntegrations = false
            }
        } catch {
            await MainActor.run {
                nativeIntegrationSettings = .defaults
                isLoadingNativeIntegrations = false
                nativeIntegrationsMessage = "Could not load WLED integration settings."
                nativeIntegrationsMessageIsError = true
            }
        }
    }

    private func saveNativeIntegrationSettings() {
        isSavingNativeIntegrations = true
        nativeIntegrationsMessage = nil
        nativeIntegrationsMessageIsError = false

        let settings = nativeIntegrationSettings

        Task {
            do {
                try await WLEDAPIService.shared.updateNativeIntegrationSettings(settings, for: activeDevice)
                await MainActor.run {
                    nativeIntegrationSettings.mqtt.password = ""
                    isSavingNativeIntegrations = false
                    nativeIntegrationsMessage = "WLED integration settings saved. Some protocol changes may need a WLED reboot."
                    nativeIntegrationsMessageIsError = false
                }
                await loadNativeIntegrationSettings()
            } catch {
                await MainActor.run {
                    isSavingNativeIntegrations = false
                    nativeIntegrationsMessage = "Could not save WLED integration settings."
                    nativeIntegrationsMessageIsError = true
                }
            }
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

    private func openWLEDPath(_ path: String) {
        guard let url = URL(string: "http://\(device.ipAddress)\(path)") else { return }
        openURL(url)
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private func advancedNetworkBinding<Value>(_ keyPath: WritableKeyPath<WLEDNetworkConfiguration, Value>) -> Binding<Value> {
        Binding<Value>(
            get: { advancedNetworkDraft[keyPath: keyPath] },
            set: { advancedNetworkDraft[keyPath: keyPath] = $0 }
        )
    }

    private func loadAdvancedNetworkConfiguration() async {
        await MainActor.run {
            isLoadingAdvancedNetwork = true
            advancedNetworkMessage = nil
            advancedNetworkMessageIsError = false
        }

        do {
            let configuration = try await WLEDWiFiService.shared.getNetworkConfiguration(device: device)
            await MainActor.run {
                advancedNetworkDraft = configuration
                isLoadingAdvancedNetwork = false
            }
        } catch {
            await MainActor.run {
                isLoadingAdvancedNetwork = false
                advancedNetworkMessage = "Could not load advanced network settings."
                advancedNetworkMessageIsError = true
            }
        }
    }

    private func saveAdvancedNetworkConfiguration() {
        guard advancedNetworkDraft.isValid else {
            advancedNetworkMessage = "Check network names, IP addresses, channel, password length, and transmit power."
            advancedNetworkMessageIsError = true
            return
        }

        isSavingAdvancedNetwork = true
        advancedNetworkMessage = nil
        advancedNetworkMessageIsError = false

        Task {
            do {
                try await WLEDWiFiService.shared.updateNetworkConfiguration(device: device, configuration: advancedNetworkDraft)
                await MainActor.run {
                    isSavingAdvancedNetwork = false
                    advancedNetworkMessage = "Advanced network settings saved. Reconnect may take a moment if the address changed."
                    advancedNetworkMessageIsError = false
                }
                await loadCurrentWiFiInfo()
            } catch {
                await MainActor.run {
                    isSavingAdvancedNetwork = false
                    advancedNetworkMessage = "Could not save advanced network settings."
                    advancedNetworkMessageIsError = true
                }
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
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private let cornerRadius: CGFloat = 16

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
                    .foregroundColor(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if let headerContent = headerContent {
                    headerContent()
                }
            }

            content
        }
        .padding(16)
        .background(
            GlassCardBackground(
                cornerRadius: cornerRadius,
                fill: AppTheme.cardFill(for: colorScheme, isActive: true),
                outerStroke: theme.cardStrokeOuter,
                innerStroke: theme.cardStrokeInner,
                keyShadow: theme.cardShadowKey,
                ambientShadow: theme.cardShadowAmbient
            )
        )
        .overlay(
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.22),
                    Color.white.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .foregroundColor(theme.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private enum FirmwareSettingsExposure: String {
    case native = "Native"
    case guided = "Guided"
    case advanced = "Advanced"
    case webFallback = "Web"

    var color: Color {
        switch self {
        case .native:
            return .green
        case .guided:
            return .cyan
        case .advanced:
            return .orange
        case .webFallback:
            return .white
        }
    }
}

private struct WLEDFirmwareSettingsArea: Identifiable {
    let id: String
    let title: String
    let location: String
    let exposure: FirmwareSettingsExposure

    static let overviewAreas: [WLEDFirmwareSettingsArea] = [
        WLEDFirmwareSettingsArea(
            id: "overview-wifi-firmware",
            title: "WiFi, IP address, software updates",
            location: "WiFi & Updates",
            exposure: .native
        ),
        WLEDFirmwareSettingsArea(
            id: "led-hardware",
            title: "LED type, GPIO, count, current",
            location: "Advanced > Product & Hardware Setup",
            exposure: .guided
        ),
        WLEDFirmwareSettingsArea(
            id: "daily-control",
            title: "Power, brightness, CCT/white, night light",
            location: "Detailed Device View + Advanced timed light",
            exposure: .native
        ),
        WLEDFirmwareSettingsArea(
            id: "segments-effects",
            title: "Segments, effects, palettes, presets",
            location: "Detailed Device View + Advanced",
            exposure: .native
        ),
        WLEDFirmwareSettingsArea(
            id: "timers-playlists",
            title: "WLED timers, playlists, boot presets",
            location: "Advanced > WLED Built-In Schedules",
            exposure: .advanced
        ),
        WLEDFirmwareSettingsArea(
            id: "sync-realtime",
            title: "UDP sync, realtime, nodes, peers",
            location: "Integrations + Advanced > Diagnostics",
            exposure: .advanced
        ),
        WLEDFirmwareSettingsArea(
            id: "integrations",
            title: "MQTT, DDP, DMX/E1.31, Hue, Alexa, IR",
            location: "Integrations + Advanced > Protocols",
            exposure: .advanced
        ),
        WLEDFirmwareSettingsArea(
            id: "maintenance",
            title: "Security, filesystem, reset, raw config",
            location: "Advanced > Maintenance & Safety",
            exposure: .webFallback
        )
    ]
}

private struct FirmwareCoverageRow: View {
    let area: WLEDFirmwareSettingsArea
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(area.exposure.color.opacity(0.75))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(area.title)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(area.location)
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer(minLength: 8)

            Text(area.exposure.rawValue)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(area.exposure == .webFallback ? .white.opacity(0.82) : .black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(area.exposure == .webFallback ? Color.white.opacity(0.12) : area.exposure.color)
                )
        }
        .padding(.vertical, 4)
    }
}

struct SettingsButton: View {
    let title: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var foreground: Color { theme.textPrimary }
    private let cornerRadius: CGFloat = 12

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(foreground.opacity(0.78))
                .font(AppTypography.style(.headline, weight: .medium))
                .frame(width: 20)

            Text(title)
                .foregroundColor(foreground)
                .font(AppTypography.style(.headline, weight: .medium))
                .lineLimit(2)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(foreground.opacity(0.48))
                .font(AppTypography.style(.caption, weight: .medium))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        )
        .appLiquidGlass(role: .control, cornerRadius: cornerRadius)
    }
}

struct SettingsInlineButton: View {
    let title: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color { AppTheme.controlForeground(for: colorScheme, isActive: true) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(AppTypography.style(.subheadline, weight: .semibold))
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundColor(foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.controlFillStyle(for: colorScheme, isActive: true))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.controlStroke(for: colorScheme, isActive: true), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SyncLampClockButton: View {
    let isSyncing: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color { AppTheme.controlForeground(for: colorScheme, isActive: true) }

    var body: some View {
        HStack(spacing: 10) {
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(foreground)
            } else {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(foreground)
            }

            Text("Sync Lamp Clock from Phone")
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.controlFillStyle(for: colorScheme, isActive: true))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.controlStroke(for: colorScheme, isActive: true), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DangerSettingsButton: View {
    enum Level {
        case warning
        case danger

        var tint: Color {
            switch self {
            case .warning:
                return .orange
            case .danger:
                return .red
            }
        }
    }

    let title: String
    let icon: String
    let level: Level
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private let cornerRadius: CGFloat = 12

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.style(.headline, weight: .medium))
                .frame(width: 20)
            Text(title)
                .font(AppTypography.style(.headline, weight: .medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTypography.style(.caption, weight: .medium))
                .opacity(0.65)
        }
        .foregroundColor(level.tint.opacity(0.95))
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.surfaceMuted)
                .overlay(level.tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(level.tint.opacity(0.35), lineWidth: 1)
        )
        .appLiquidGlass(role: .control, cornerRadius: cornerRadius)
    }
}

struct AdvancedNetworkTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .settingsTextFieldChrome(theme: theme)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: $text)
                    .settingsTextFieldChrome(theme: theme)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }
}

struct SettingsDisclosureSection<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    var isWarning: Bool = false
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    init(
        title: String,
        subtitle: String,
        icon: String,
        isWarning: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isWarning = isWarning
        self.content = content()
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(subtitle)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(isWarning ? .orange.opacity(0.9) : theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                content
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(isWarning ? .orange : theme.textSecondary)
                    .frame(width: 22)
                Text(title)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
        }
        .tint(theme.textPrimary)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isWarning ? Color.orange.opacity(0.28) : theme.divider, lineWidth: 1)
        )
        .appLiquidGlass(role: isWarning ? .highContrast : .control, cornerRadius: 16)
    }
}

extension View {
    func settingsTextFieldChrome(theme: AppSemanticTheme) -> some View {
        self
            .font(AppTypography.style(.subheadline))
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.divider, lineWidth: 1)
            )
    }

    func settingsToggleStyle() -> some View {
        self
            .tint(.white)
            .font(AppTypography.style(.subheadline, weight: .medium))
            .foregroundColor(.white)
    }
}

// MARK: - Reused Components from WLEDSettingsView

fileprivate struct IntegrationTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            if secure {
                SecureField(placeholder, text: $text)
                    .settingsTextFieldChrome(theme: theme)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: $text)
                    .settingsTextFieldChrome(theme: theme)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }
}

fileprivate struct IntegrationNumberFieldRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var keyboardType: UIKeyboardType { range.lowerBound < 0 ? .numbersAndPunctuation : .numberPad }

    private var textBinding: Binding<String> {
        Binding(
            get: { "\(value)" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = Int(trimmed) else { return }
                value = min(range.upperBound, max(range.lowerBound, parsed))
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .foregroundColor(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            TextField("", text: textBinding)
                .settingsTextFieldChrome(theme: theme)
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
                .frame(width: 92)

            Stepper("", value: $value, in: range)
                .labelsHidden()
                .frame(width: 52)
        }
    }
}

fileprivate struct IntegrationPickerRow<SelectionValue: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let options: () -> Options
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    init(
        title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder options: @escaping () -> Options
    ) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .foregroundColor(theme.textPrimary)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(theme.textPrimary)
        }
    }
}

fileprivate struct IntegrationToggleItem {
    let title: String
    let binding: Binding<Bool>
}

fileprivate struct IntegrationToggleGrid: View {
    let items: [IntegrationToggleItem]

    private let columns = [
        GridItem(.adaptive(minimum: 136), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                Toggle(items[index].title, isOn: items[index].binding)
                    .settingsToggleStyle()
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
    }
}

fileprivate struct IntegrationGroupMaskRow: View {
    let title: String
    @Binding var mask: Int
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            HStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    Button(action: { toggle(index) }) {
                        Text("\(index + 1)")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(isEnabled(index) ? .black : theme.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(isEnabled(index) ? Color.white : theme.surfaceMuted)
                            )
                            .overlay(
                                Circle()
                                    .stroke(theme.divider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func isEnabled(_ index: Int) -> Bool {
        (mask & (1 << index)) != 0
    }

    private func toggle(_ index: Int) {
        let bit = 1 << index
        if isEnabled(index) {
            mask &= ~bit
        } else {
            mask |= bit
        }
        mask = min(255, max(0, mask))
    }
}

fileprivate struct SmartHomeIntegrationStatusRow: View {
    let status: SmartHomeIntegrationStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(statusColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.state.displayName)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white)
                if let message = status.message, !message.isEmpty {
                    Text(message)
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(statusColor.opacity(0.32), lineWidth: 1)
        )
    }

    private var statusIcon: String {
        switch status.state {
        case .enabled: return "checkmark.circle.fill"
        case .needsSync: return "arrow.triangle.2.circlepath.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .requiresBridge: return "point.3.connected.trianglepath.dotted"
        case .unsupported: return "minus.circle.fill"
        case .notSetUp: return "circle"
        }
    }

    private var statusColor: Color {
        switch status.state {
        case .enabled: return .green
        case .needsSync: return .yellow
        case .conflict, .failed: return .orange
        case .requiresBridge: return .blue
        case .unsupported: return .gray
        case .notSetUp: return .white.opacity(0.62)
        }
    }
}

struct AlexaDiscoveryInstructionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            instructionRow(icon: "checkmark.circle.fill", title: "Alexa setup saved")
            instructionRow(icon: "iphone", title: "Open Alexa app")
            instructionRow(icon: "magnifyingglass.circle.fill", title: "Run Discover Devices")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
    }

    private func instructionRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(.green)
                .frame(width: 22, height: 22)
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(.white)
            Spacer(minLength: 0)
        }
    }
}

fileprivate struct PowerToggleRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isOn: Bool
    let device: WLEDDevice

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack {
            Text("Power")
                .font(AppTypography.style(.headline, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.accent)
                .onChange(of: isOn) { _, val in
                    Task { await viewModel.setDevicePower(device, isOn: val) }
                }
        }
    }
}

fileprivate struct UDPTogglesRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var udpSend: Bool
    @Binding var udpRecv: Bool
    @Binding var suppressUpdates: Bool
    let device: WLEDDevice

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack {
            Toggle("Send (UDPN)", isOn: $udpSend)
                .tint(theme.accent)
                .foregroundColor(theme.textPrimary)
                .onChange(of: udpSend) { _, v in
                    guard !suppressUpdates else { return }
                    Task { await viewModel.setUDPSync(device, send: v, recv: nil) }
                }
            Spacer()
            Toggle("Receive", isOn: $udpRecv)
                .tint(theme.accent)
                .foregroundColor(theme.textPrimary)
                .onChange(of: udpRecv) { _, v in
                    guard !suppressUpdates else { return }
                    Task { await viewModel.setUDPSync(device, send: nil, recv: v) }
                }
        }
    }
}

fileprivate struct SliderRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEnd: (() -> Void)?

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Text("\(Int(value))")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
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
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var onEnd: (() -> Void)? = nil

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack {
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .foregroundColor(theme.textPrimary)
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
            hour: timer.hour == 255 || timer.hour == 254 || timer.hour == 24 ? 0 : max(0, min(23, timer.hour)),
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
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var primaryButtonForeground: Color { AppTheme.controlForeground(for: colorScheme, isActive: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timer \(draft.id + 1)")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Text(draft.timeLabel)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                Toggle("", isOn: $draft.enabled)
                    .labelsHidden()
                    .tint(theme.accent)
            }

            HStack(spacing: 12) {
                IntStepperMini(title: "Hour", value: $draft.hour, range: 0...23)
                IntStepperMini(title: "Minute", value: $draft.minute, range: 0...59)
                IntStepperMini(title: "Preset", value: $draft.macroId, range: 0...250)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Days")
                    .font(AppTypography.style(.caption2, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let labels = ["S", "M", "T", "W", "T", "F", "S"]
                        Button {
                            draft.weekdays[dayIndex].toggle()
                        } label: {
                            Text(labels[dayIndex])
                                .font(AppTypography.style(.caption, weight: .semibold))
                                .foregroundColor(
                                    draft.weekdays[dayIndex]
                                        ? AppTheme.controlForeground(for: colorScheme, isActive: true)
                                        : theme.textSecondary
                                )
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(draft.weekdays[dayIndex] ? AppTheme.controlFillStyle(for: colorScheme, isActive: true) : AnyShapeStyle(theme.surfaceMuted))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(theme.divider, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(draft.enabled ? "Runs preset \(draft.macroId) on \(draft.weekdaySummary)" : "Disabled")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(theme.textTertiary)
                Spacer()
                Button(action: onSave) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(primaryButtonForeground)
                        }
                        Text(draft.enabled ? "Save" : "Apply Disabled")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(primaryButtonForeground)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.controlFillStyle(for: colorScheme, isActive: true))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.controlStroke(for: colorScheme, isActive: true), lineWidth: 1)
                    )
                }
                .disabled(isSaving)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        )
        .appLiquidGlass(role: .control, cornerRadius: 12)
    }
}

private struct IntStepperMini: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(theme.textSecondary)
            HStack(spacing: 8) {
                Button {
                    value = max(range.lowerBound, value - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                }
                .buttonStyle(.plain)

                Text("\(value)")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .frame(minWidth: 28)

                Button {
                    value = min(range.upperBound, value + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.surfaceMuted)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.divider, lineWidth: 1)
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
