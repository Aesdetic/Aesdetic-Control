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
    case updating(String)
    case upToDate(current: String, latest: String)
    case updateAvailable(current: String, latest: String)
    case error(String)
}

private struct WLEDWebDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private enum SavedWiFiAction {
    case saveOnly
    case changeNow
}

struct EmbeddedSettingsHeaderChrome: Equatable {
    var backTitle: String
    var backAccessibilityLabel: String
    var headerTitle: String
    var headerActionEnabled: Bool
    var headerAccessibilityLabel: String

    static let settings = EmbeddedSettingsHeaderChrome(
        backTitle: "Controls",
        backAccessibilityLabel: "Back to controls",
        headerTitle: "Settings",
        headerActionEnabled: false,
        headerAccessibilityLabel: "Settings status"
    )
}

struct EmbeddedSettingsHeaderActions {
    var back: (() -> Void)?
    var primary: (() -> Void)?

    static let none = EmbeddedSettingsHeaderActions(back: nil, primary: nil)
}

final class EmbeddedSettingsHeaderActionStore: ObservableObject {
    private var backAction: (() -> Void)?
    private var primaryAction: (() -> Void)?

    func update(_ actions: EmbeddedSettingsHeaderActions) {
        backAction = actions.back
        primaryAction = actions.primary
    }

    func reset() {
        backAction = nil
        primaryAction = nil
    }

    func performBack() {
        backAction?()
    }

    func performPrimary() {
        primaryAction?()
    }
}

enum SettingsDescriptionTone {
    case secondary
    case warning
    case error
}

struct SettingsDescriptionText: View {
    let markdown: String
    var tone: SettingsDescriptionTone = .secondary

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private var color: Color {
        switch tone {
        case .secondary:
            return theme.settingsText(.secondary)
        case .warning:
            return theme.status.warning
        case .error:
            return theme.status.negative
        }
    }

    var body: some View {
        Text(attributedText)
            .font(AppTypography.style(.caption))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ComprehensiveSettingsView: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.setupJourneyActions) private var setupJourneyActions
    @ObservedObject private var presetsStore = PresetsStore.shared
    @ObservedObject private var smartHomeStore = SmartHomeIntegrationStore.shared
    @ObservedObject private var automationStore = AutomationStore.shared
    let device: WLEDDevice
    let initialCategory: SettingsCategory
    let presentationMode: PresentationMode
    let contentBottomPadding: CGFloat
    let onSettingsHeaderStatusChange: ((String) -> Void)?
    let onSettingsHeaderChromeChange: ((EmbeddedSettingsHeaderChrome) -> Void)?
    let onSettingsHeaderActionsChange: ((EmbeddedSettingsHeaderActions) -> Void)?
    let onReconnectDevice: ((WLEDDevice) -> Void)?
    let onDeviceRemoved: (() -> Void)?

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
    @State private var timerFeedbackBySlotId: [Int: TimerEditorFeedback] = [:]
    @State private var editingName: String = ""
    @State private var isCommittingDeviceRename: Bool = false
    @FocusState private var isLampNameFieldFocused: Bool
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
    @State private var alexaIntegrationSupported: Bool = true
    @State private var hasLoadedAlexaIntegrationSettings: Bool = false
    @State private var isLoadingAlexaSettings: Bool = false
    @State private var isSavingAlexaSettings: Bool = false
    @State private var alexaSettingsMessage: String?
    @State private var alexaSettingsMessageIsError: Bool = false
    @State private var showAlexaDiscoveryInstructions: Bool = false
    @State private var showFactoryResetRecoveryActions: Bool = false
    @State private var isRemovingFactoryResetDevice: Bool = false
    @State private var isAlexaQuickSetupExpanded: Bool = false
    @State private var isHomeAssistantQuickSetupExpanded: Bool = false
    @State private var nativeIntegrationSettings: WLEDNativeIntegrationSettings = .defaults
    @State private var isLoadingNativeIntegrations: Bool = false
    @State private var isSavingNativeIntegrations: Bool = false
    @State private var hasLoadedNativeIntegrationSettings: Bool = false
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
    @State private var wledWebDestination: WLEDWebDestination?
    @State private var showFirmwareUpdate: Bool = false
    @State private var showAutomaticFirmwareUpdate: Bool = false
    @State private var showRecommendedSoftwareConfirmation: Bool = false
    @State private var showPostRenameWiFiPrompt: Bool = false
    @State private var updateCheckStatus: UpdateCheckStatus = .idle
    @State private var latestStableVersion: String?
    @State private var lastUpdateCheck: Date?
    @State private var didLoadBaseSettings: Bool = false
    @State private var didLoadScheduleSettings: Bool = false
    @State private var didLoadWiFiSettings: Bool = false
    @State private var didLoadIntegrationSettings: Bool = false
    @State private var didLoadAdvancedSettings: Bool = false
    @State private var isAdvancedCategoryDetailActive: Bool = false
    @State private var advancedInitialCategoryID: String?
    @State private var ledConfiguration: LEDConfiguration?
    @State private var isLoadingLEDConfiguration: Bool = false
    @State private var ledConfigurationMessage: String?

    // WiFi state variables
    @State private var availableNetworks: [WiFiNetwork] = []
    @State private var isConnecting: Bool = false
    @State private var currentWiFiInfo: WiFiInfo?
    @State private var isLoadingWiFiInfo: Bool = false
    @State private var savedNetworkSnapshot: WLEDSavedNetworkSnapshot?
    @State private var isLoadingSavedNetworks: Bool = false
    @State private var isMutatingSavedNetworks: Bool = false
    @State private var savedNetworkMessage: String?
    @State private var savedNetworkMessageIsError: Bool = false
    @State private var showManualNetworkEntry: Bool = false
    @State private var showAddNetworkFlow: Bool = false
    @State private var addNetworkUsesManualEntry: Bool = false
    @State private var isScanningAddNetworks: Bool = false
    @State private var addNetworkScanError: String?
    @State private var addNetworkSaveError: String?
    @State private var addNetworkSelection: WiFiNetwork?
    @State private var showAllAddNetworkScanResults: Bool = false
    @State private var addNetworkScanRequestID = UUID()
    @State private var manualNetworkDraft = WLEDSavedNetworkDraft()
    @State private var replacementSlot: Int?
    @State private var pendingNetworkRemoval: WLEDSavedNetwork?
    @State private var advancedNetworkDraft = WLEDNetworkConfiguration()
    @State private var isLoadingAdvancedNetwork: Bool = false
    @State private var isSavingAdvancedNetwork: Bool = false
    @State private var hasLoadedAdvancedNetworkConfiguration: Bool = false
    @State private var advancedNetworkMessage: String?
    @State private var advancedNetworkMessageIsError: Bool = false
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @AppStorage("showSegmentControlsInColorTabAdvanced") private var showSegmentControlsInColorTabAdvanced: Bool = true

    enum SettingsCategory: String, CaseIterable {
        case overview = "Device"
        case timeSchedules = "Time & Schedules"
        case wifiUpdates = "WiFi"
        case integrations = "Integrations"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .timeSchedules: return "clock"
            case .wifiUpdates: return "wifi"
            case .integrations: return "link"
            case .advanced: return "slider.horizontal.3"
            }
        }

        func title(for presentationMode: PresentationMode, productType: ProductType) -> String {
            if self == .overview {
                return productType.settingsObjectName
            }
            switch (self, presentationMode) {
            case (.timeSchedules, .embedded):
                return "Time"
            case (.timeSchedules, .standalone):
                return "Time & Routines"
            case (.wifiUpdates, _):
                return "WiFi"
            case (.integrations, _):
                return "Smart Home"
            default:
                return rawValue
            }
        }
    }

    enum PresentationMode {
        case standalone
        case embedded
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

    private var theme: AppSemanticTheme {
        AppTheme.tokens(for: colorScheme)
    }

    private var settingsObjectName: String {
        activeDevice.productType.settingsObjectName
    }

    private var settingsObjectNameLowercased: String {
        activeDevice.productType.settingsObjectNameLowercased
    }

    private var alexaFavoritesCount: Int {
        presetsStore.alexaFavorites(for: activeDevice.id).count
    }

    private var alexaIntegrationStatus: SmartHomeIntegrationStatus {
        smartHomeStore.status(for: .alexa, deviceId: activeDevice.id)
    }

    private var homeAssistantSetupState: HomeAssistantSetupState {
        smartHomeStore.homeAssistantSetup(for: activeDevice.id)
    }

    private var homeAssistantIntegrationStatus: SmartHomeIntegrationStatus {
        smartHomeStore.status(for: .homeAssistant, deviceId: activeDevice.id)
    }

    private var alexaAutoFillBinding: Binding<Bool> {
        Binding(
            get: { presetsStore.alexaAutoFillEnabled(for: activeDevice.id) },
            set: { presetsStore.setAlexaAutoFillEnabled($0, for: activeDevice.id) }
        )
    }

    private func homeAssistantChecklistBinding(_ keyPath: WritableKeyPath<HomeAssistantSetupState, Bool>) -> Binding<Bool> {
        Binding(
            get: { homeAssistantSetupState[keyPath: keyPath] },
            set: { newValue in
                smartHomeStore.updateHomeAssistantSetup(for: activeDevice.id) { setup in
                    setup[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func homeAssistantTextBinding(_ keyPath: WritableKeyPath<HomeAssistantSetupState, String?>) -> Binding<String> {
        Binding(
            get: { homeAssistantSetupState[keyPath: keyPath] ?? "" },
            set: { newValue in
                smartHomeStore.updateHomeAssistantSetup(for: activeDevice.id) { setup in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    setup[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    private var deviceScheduleAutomationCount: Int {
        deviceScheduleAutomations.count
    }

    private var deviceScheduleAutomations: [Automation] {
        automationStore.automations.filter { automation in
            automation.targets.deviceIds.contains(activeDevice.id)
        }
    }

    private func deviceSolarAutomationCount(isSunrise: Bool) -> Int {
        deviceScheduleAutomations.filter { automation in
            switch automation.trigger {
            case .sunrise:
                return isSunrise
            case .sunset:
                return !isSunrise
            case .specificTime:
                return false
            }
        }.count
    }

    init(
        device: WLEDDevice,
        initialCategory: SettingsCategory = .overview,
        presentationMode: PresentationMode = .standalone,
        contentBottomPadding: CGFloat = 20,
        onSettingsHeaderStatusChange: ((String) -> Void)? = nil,
        onSettingsHeaderChromeChange: ((EmbeddedSettingsHeaderChrome) -> Void)? = nil,
        onSettingsHeaderActionsChange: ((EmbeddedSettingsHeaderActions) -> Void)? = nil,
        onReconnectDevice: ((WLEDDevice) -> Void)? = nil,
        onDeviceRemoved: (() -> Void)? = nil
    ) {
        self.device = device
        self.initialCategory = initialCategory
        self.presentationMode = presentationMode
        self.contentBottomPadding = contentBottomPadding
        self.onSettingsHeaderStatusChange = onSettingsHeaderStatusChange
        self.onSettingsHeaderChromeChange = onSettingsHeaderChromeChange
        self.onSettingsHeaderActionsChange = onSettingsHeaderActionsChange
        self.onReconnectDevice = onReconnectDevice
        self.onDeviceRemoved = onDeviceRemoved
        _selectedSettingsCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        ZStack {
            if presentationMode == .standalone {
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
            }

            VStack(spacing: 0) {
                if presentationMode == .standalone {
                    // Header with device name
                    headerSection
                }

                if !shouldHideSettingsCategorySelector {
                    categorySelector
                }

                // Content based on selected category
                if selectedSettingsCategory == .advanced {
                    advancedSection
                        .padding(
                            .horizontal,
                            presentationMode == .embedded ? DeviceDetailPresentation.contentHorizontalInset : 0
                        )
                } else {
                    GeometryReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 12) {
                                nonAdvancedPageHeading
                                selectedNonAdvancedSection
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .frame(
                                width: max(0, proxy.size.width - settingsContentHorizontalInset * 2),
                                alignment: .topLeading
                            )
                            .padding(.horizontal, settingsContentHorizontalInset)
                            .padding(.bottom, contentBottomPadding)
                        }
                    }
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
        .task(id: selectedSettingsCategory) {
            // Let the pill selection render first and avoid launching network
            // work for rapid intermediate taps.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await loadSettingsForCurrentCategory()
        }
        .onChange(of: selectedSettingsCategory) { _, category in
            if category != .advanced {
                isAdvancedCategoryDetailActive = false
                onSettingsHeaderChromeChange?(.settings)
                onSettingsHeaderActionsChange?(.none)
                onSettingsHeaderStatusChange?("Settings")
            }
        }
        .onDisappear {
            manualNetworkDraft.clearSensitiveValues()
            onSettingsHeaderChromeChange?(.settings)
            onSettingsHeaderActionsChange?(.none)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            manualNetworkDraft.clearSensitiveValues()
        }
        .sheet(item: $wledWebDestination) { destination in
            WLEDWebConfigView(url: destination.url)
        }
        .sheet(isPresented: $showAutomaticFirmwareUpdate) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/update")!)
        }
        .sheet(isPresented: $showFirmwareUpdate) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/update")!)
        }
        .overlay {
        }
        .confirmationDialog(
            "\(settingsObjectName) Name Updated",
            isPresented: $showPostRenameWiFiPrompt,
            titleVisibility: .visible
        ) {
            Button("Review WiFi Settings") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedSettingsCategory = .wifiUpdates
                }
            }
            Button("Done", role: .cancel) {}
        } message: {
            Text("Your local web address stays unchanged unless you edit it in Advanced WiFi & Network.")
        }
        .confirmationDialog(
            "Install recommended software?",
            isPresented: $showRecommendedSoftwareConfirmation,
            titleVisibility: .visible
        ) {
            Button("Install Update") {
                Task { await installRecommendedSoftware() }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Your lamp will restart while we install the Aesdetic-recommended software. Keep your phone on the same Wi-Fi network and do not remove power.")
        }
        .confirmationDialog(
            "Factory Reset Sent",
            isPresented: $showFactoryResetRecoveryActions,
            titleVisibility: .visible
        ) {
            Button("Set Up Again") {
                onReconnectDevice?(activeDevice)
            }
            Button("Remove From App", role: .destructive) {
                removeFactoryResetDeviceFromApp()
            }
            Button("Keep Offline", role: .cancel) {}
        } message: {
            Text("WLED erased its settings and WiFi credentials. Choose whether to reconnect it, remove its saved app record, or keep it offline for later.")
        }
        .alert(item: $pendingNetworkRemoval) { network in
            Alert(
                title: Text("Remove \(network.ssid)?"),
                message: Text("The device will no longer connect to this network automatically."),
                primaryButton: .destructive(Text("Remove")) {
                    removeSavedNetwork(network)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var shouldHideSettingsCategorySelector: Bool {
        selectedSettingsCategory == .advanced && isAdvancedCategoryDetailActive
    }

    private var settingsContentHorizontalInset: CGFloat {
        if presentationMode == .embedded {
            return DeviceDetailPresentation.contentHorizontalInset + 16
        }
        return 16
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
                    Text("Restarting \(settingsObjectName)")
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                    Text("Reconnecting... \(max(0, rebootWaitRemainingSeconds))s")
                        .font(AppTypography.style(.subheadline))
                        .settingsForegroundStyle(.secondary)
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
                    Text(activeDevice.name)
                        .font(AppTypography.style(.title2, weight: .semibold))
                        .settingsForegroundStyle(.primary)

                    Text(activeDevice.ipAddress)
                        .font(AppTypography.style(.caption))
                        .settingsForegroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    AppGlassIconButton(
                        systemName: "arrow.clockwise",
                        isProminent: false,
                        size: 38
                    ) {
                        Task { await reloadVisibleSettings() }
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
        // The viewport is intentionally full-width in the embedded detail panel;
        // only the resting tab content receives an inset.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsCategory.allCases, id: \.self) { category in
                    AppGlassPillButton(
                        title: category.title(for: presentationMode, productType: activeDevice.productType),
                        isSelected: selectedSettingsCategory == category,
                        iconName: category.icon,
                        size: presentationMode == .embedded ? .compact : .regular,
                        useControlGlassRecipe: true,
                        useAppleSelectedStyle: true,
                        selectedGlassRole: .control,
                        selectedFrostUsesMaterial: false,
                        foregroundColorOverride: .white
                    ) {
                        guard selectedSettingsCategory != category else { return }
                        if category == .advanced {
                            advancedInitialCategoryID = nil
                        }
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            selectedSettingsCategory = category
                        }
                    }
                    .accessibilityIdentifier("settings-tab-\(category.rawValue)")
                    .accessibilityValue(selectedSettingsCategory == category ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("settings-category-selector")
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    // MARK: - Settings Sections

    private var nonAdvancedPageHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedSettingsCategory.title(for: presentationMode, productType: activeDevice.productType))
                .font(AppTypography.style(.title2, weight: .semibold))
                .foregroundStyle(theme.settingsText(.primary))
                .accessibilityAddTraits(.isHeader)

            Text(nonAdvancedPageSubtitle)
                .font(AppTypography.style(.subheadline))
                .foregroundStyle(theme.settingsText(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var nonAdvancedPageSubtitle: String {
        switch selectedSettingsCategory {
        case .overview:
            return "Everyday behavior, connection, and software for this \(settingsObjectNameLowercased)."
        case .timeSchedules:
            return "Clock, location, sunrise, sunset, and scheduled routines."
        case .wifiUpdates:
            return "Current connection, saved networks, and recovery access."
        case .integrations:
            return "Connect Alexa, Home Assistant, and advanced services."
        case .advanced:
            return ""
        }
    }

    @ViewBuilder
    private var selectedNonAdvancedSection: some View {
        switch selectedSettingsCategory {
        case .overview:
            overviewSection
        case .timeSchedules:
            timeSchedulesSection
        case .wifiUpdates:
            wifiUpdatesSection
        case .integrations:
            compactIntegrationsSection
        case .advanced:
            EmptyView()
        }
    }

    private var overviewSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "\(settingsObjectName) Profile", glassStyle: .detailControl) {
                VStack(spacing: 12) {
                    lampNameOverviewRow
                    InfoRow(label: "Room", value: activeDevice.location.displayName)
                    InfoRow(label: "Look", value: activeDevice.lookId ?? "Default")

                    Button(action: { setupJourneyActions.beginProductSetup(activeDevice, nil) }) {
                        SettingsButton(
                            title: activeDevice.setupState == .pendingSelection ? "Complete Setup" : "Change Product",
                            icon: "sparkles",
                            style: .overviewRow
                        )
                    }
                }
            }

            DeviceBehaviorSettingsCard(
                device: activeDevice,
                objectName: settingsObjectName,
                glassStyle: .detailControl,
                openAdvanced: { openAdvancedCategory("led-hardware") }
            )
            .id("behavior-\(activeDevice.id)-\(activeDevice.ipAddress)")

            SettingsCard(title: "Status", glassStyle: .detailControl) {
                VStack(spacing: 12) {
                    InfoRow(label: "Connection", value: viewModel.isDeviceOnline(activeDevice) || activeDevice.isOnline ? "Online" : "Offline")
                    InfoRow(label: "Device address", value: activeDevice.ipAddress)

                    if let wifiInfo = currentWiFiInfo {
                        InfoRow(label: "Network", value: wifiInfo.ssid)
                        InfoRow(label: "Signal", value: wifiSignalSummary(wifiInfo.signalStrength))
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading network status...")
                                .font(AppTypography.style(.subheadline))
                                .settingsForegroundStyle(.secondary)
                            Spacer()
                        }
                    }

                    Button(action: {
                        selectedSettingsCategory = .wifiUpdates
                        Task { await loadCurrentWiFiInfo() }
                    }) {
                        SettingsButton(title: "Manage WiFi", icon: "wifi", style: .overviewRow)
                    }
                }
            }

            healthAndRecoveryCard

            softwareUpdateCard
        }
    }

    private var healthAndRecoveryCard: some View {
        SettingsCard(title: "Health & Recovery", glassStyle: .detailControl) {
            VStack(spacing: 12) {
                InfoRow(label: "Last checked", value: lastSeenSummary)
                InfoRow(label: "WLED version", value: info?.ver ?? "Not checked")

                if !isWiFiDeviceReachable, let onReconnectDevice {
                    Button {
                        onReconnectDevice(activeDevice)
                    } label: {
                        SettingsButton(title: "Set Up or Reconnect", icon: "wifi.exclamationmark", style: .overviewRow)
                    }
                }

                Button(action: { Task { await viewModel.rebootDevice(device) } }) {
                    SettingsButton(
                        title: isRebootWaitActive
                            ? "Restarting... \(max(0, rebootWaitRemainingSeconds))s"
                            : "Restart \(settingsObjectName)",
                        icon: "arrow.clockwise.circle",
                        style: .overviewRow
                    )
                }
                .disabled(isRebootWaitActive || !isWiFiDeviceReachable)

                Button(action: { openAdvancedCategory("security-updates") }) {
                    SettingsButton(title: "Backup & Recovery", icon: "externaldrive", style: .overviewRow)
                }
            }
        }
    }

    private var lastSeenSummary: String {
        if isWiFiDeviceReachable {
            return "Now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: activeDevice.lastSeen, relativeTo: Date())
    }

    private var lampNameOverviewRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(settingsObjectName) name")
                .font(AppTypography.style(.subheadline, weight: .medium))
                .foregroundColor(AppTheme.tokens(for: colorScheme).settingsText(.secondary))

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if isCommittingDeviceRename {
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(AppTheme.tokens(for: colorScheme).settingsText(.primary))
                }

                TextField("\(settingsObjectName) name", text: $editingName)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(AppTheme.tokens(for: colorScheme).settingsText(.primary))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isLampNameFieldFocused)
                    .disabled(isCommittingDeviceRename)
                    .frame(minWidth: 120, maxWidth: 210, alignment: .trailing)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.tokens(for: colorScheme).surfaceMuted.opacity(isLampNameFieldFocused ? 1 : 0.42))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isLampNameFieldFocused
                                    ? AppTheme.tokens(for: colorScheme).divider.opacity(0.9)
                                    : AppTheme.tokens(for: colorScheme).divider.opacity(0.45),
                                lineWidth: 1
                            )
                    )
                    .onSubmit {
                        Task { await commitDeviceRename() }
                    }
                    .onChange(of: isLampNameFieldFocused) { _, isFocused in
                        if !isFocused {
                            Task { await commitDeviceRename() }
                        }
                    }
                    .onAppear {
                        if editingName.isEmpty {
                            editingName = activeDevice.name
                        }
                    }
                    .onChange(of: activeDevice.name) { _, name in
                        if !isLampNameFieldFocused {
                            editingName = name
                        }
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

    private func loadSettingsForCurrentCategory() async {
        let category = await MainActor.run { selectedSettingsCategory }

        // UI tests use a deterministic offline fixture. Keep navigation tests
        // read-only and local instead of probing the fixture's reserved IP.
        if AppRuntimeEnvironment.isRunningUITests {
            await MainActor.run {
                didLoadBaseSettings = true
                switch category {
                case .overview:
                    break
                case .timeSchedules:
                    didLoadScheduleSettings = true
                case .wifiUpdates:
                    didLoadWiFiSettings = true
                case .integrations:
                    didLoadIntegrationSettings = true
                case .advanced:
                    didLoadAdvancedSettings = true
                }
            }
            return
        }

        let needsBaseLoad = await MainActor.run { !didLoadBaseSettings }

        if needsBaseLoad {
            await loadState()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                didLoadBaseSettings = true
            }
        }

        switch category {
        case .overview:
            let shouldLoadOverviewWiFi = await MainActor.run {
                currentWiFiInfo == nil
            }
            if shouldLoadOverviewWiFi {
                await loadCurrentWiFiInfo()
                guard !Task.isCancelled else { return }
            }
        case .timeSchedules:
            let shouldLoad = await MainActor.run { !didLoadScheduleSettings }
            if shouldLoad {
                await loadTimersAndMacros()
                guard !Task.isCancelled else { return }
                await MainActor.run { didLoadScheduleSettings = true }
            }
        case .wifiUpdates:
            let shouldLoad = await MainActor.run { !didLoadWiFiSettings }
            if shouldLoad {
                await loadSavedNetworkSnapshot()
                guard !Task.isCancelled else { return }
                await MainActor.run { didLoadWiFiSettings = true }
            }
        case .integrations:
            let shouldLoad = await MainActor.run { !didLoadIntegrationSettings }
            if shouldLoad {
                // Keep tab navigation cheap. Integration loading touches WLED,
                // shared stores, and the large integrations view, so load it
                // from explicit Refresh actions instead of pill selection.
                await MainActor.run { didLoadIntegrationSettings = true }
            }
        case .advanced:
            let shouldLoad = await MainActor.run { !didLoadAdvancedSettings }
            if shouldLoad {
                await loadLEDConfigurationSummary()
                guard !Task.isCancelled else { return }
                await MainActor.run { didLoadAdvancedSettings = true }
            }
        }
    }

    private func reloadVisibleSettings() async {
        let category = await MainActor.run { selectedSettingsCategory }
        await MainActor.run {
            didLoadBaseSettings = false
            switch category {
            case .overview:
                break
            case .timeSchedules:
                didLoadScheduleSettings = false
            case .wifiUpdates:
                didLoadWiFiSettings = false
            case .integrations:
                didLoadIntegrationSettings = false
            case .advanced:
                didLoadAdvancedSettings = false
            }
        }
        await loadSettingsForCurrentCategory()
    }

    private func loadLEDConfigurationSummary() async {
        await MainActor.run {
            isLoadingLEDConfiguration = true
            ledConfigurationMessage = nil
        }

        do {
            let configuration = try await WLEDAPIService.shared.getLEDConfiguration(for: activeDevice)
            await MainActor.run {
                ledConfiguration = configuration
                isLoadingLEDConfiguration = false
            }
        } catch {
            await MainActor.run {
                ledConfiguration = nil
                isLoadingLEDConfiguration = false
                ledConfigurationMessage = "Could not read LED preferences from WLED."
            }
        }
    }

    private var timeSchedulesSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Time & Location", glassStyle: .detailControl) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Sync from this phone:** Updates WLED's clock, timezone, and solar location."
                    )

                    if let deviceTime = info?.time, !deviceTime.isEmpty {
                        InfoRow(label: "\(settingsObjectName) clock", value: deviceTime)
                    } else {
                        InfoRow(label: "\(settingsObjectName) clock", value: "Unavailable")
                    }
                    InfoRow(label: "Phone timezone", value: TimeZone.current.identifier)

                    Button(action: syncDeviceTimeFromPhone) {
                        SyncLampClockButton(isSyncing: isSyncingDeviceTime, objectName: settingsObjectName)
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

            SettingsCard(title: "Automations & Sunrise/Sunset", glassStyle: .detailControl) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Aesdetic routines:** Sunrise, sunset, and schedules. Firmware timers stay in Advanced."
                    )

                    InfoRow(label: "App automations", value: "\(deviceScheduleAutomationCount)")
                    InfoRow(label: "Sunrise automations", value: "\(deviceSolarAutomationCount(isSunrise: true))")
                    InfoRow(label: "Sunset automations", value: "\(deviceSolarAutomationCount(isSunrise: false))")

                    if enabledNativeTimerCount > 0 {
                        Divider()
                            .background(Color.white.opacity(0.16))
                        InfoRow(label: "Firmware timers", value: "\(enabledNativeTimerCount) active")
                        SettingsDescriptionText(
                            markdown: "**Runs separately:** Check firmware timers if the light changes unexpectedly."
                        )
                    }

                    Button(action: { openAdvancedCategory("time-macros") }) {
                        SettingsButton(title: "Open Advanced Time & Macros", icon: "slider.horizontal.3")
                    }
                }
            }
        }
    }

    private var enabledNativeTimerCount: Int {
        timerDrafts.filter(\.enabled).count
    }

    private var wifiUpdatesSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Current Network", content: {
                VStack(spacing: 12) {
                    if !isWiFiDeviceReachable {
                        InfoRow(label: "Connection", value: "Offline")
                        SettingsDescriptionText(
                            markdown: "**Offline:** Reconnect this \(settingsObjectNameLowercased) to manage saved networks."
                        )

                        if let onReconnectDevice {
                            Button {
                                onReconnectDevice(activeDevice)
                            } label: {
                                SettingsButton(title: "Reconnect Device", icon: "wifi.exclamationmark")
                            }
                        }
                    } else if let snapshot = savedNetworkSnapshot {
                        InfoRow(label: "Network", value: snapshot.connectedSSID ?? "Could not identify")
                        if let signal = snapshot.signalStrength {
                            InfoRow(label: "Signal", value: wifiSignalSummary(signal))
                        }
                        if snapshot.connectedSSID == nil {
                            SettingsDescriptionText(
                                markdown: "**Network not identified:** Refresh before replacing or removing a saved network."
                            )
                        }
                    } else {
                        HStack(spacing: 8) {
                            if isLoadingSavedNetworks {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isLoadingSavedNetworks ? "Checking connection..." : "Tap Refresh to check the connection.")
                                .font(AppTypography.style(.subheadline))
                                .settingsForegroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }, headerContent: {
                AnyView(
                    Button("Refresh") {
                        Task {
                            await loadSavedNetworkSnapshot()
                        }
                    }
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.18))
                    .cornerRadius(8)
                )
            })

            if isWiFiDeviceReachable {
                SettingsCard(title: "Networks", content: {
                    VStack(spacing: 10) {
                        if let snapshot = savedNetworkSnapshot {
                            if !snapshot.supportsMultipleNetworks {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "arrow.up.circle")
                                        .settingsForegroundStyle(.primary)
                                    SettingsDescriptionText(
                                        markdown: "**Update required:** WLED 0.15 or newer supports multiple saved networks."
                                    )
                                }
                            } else if snapshot.networks.isEmpty {
                                Text("No saved networks were returned by the device.")
                                    .font(AppTypography.style(.subheadline))
                                    .settingsForegroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(snapshot.networks) { network in
                                    savedNetworkRow(network, snapshot: snapshot)
                                }
                            }

                            Divider().background(Color.white.opacity(0.16))

                            HStack {
                                Text("\(snapshot.networks.count) of \(snapshot.capacity) saved")
                                    .font(AppTypography.style(.caption))
                                    .foregroundColor(.white.opacity(0.78))
                                Spacer()
                                Button {
                                    presentAddNetworkFlow()
                                } label: {
                                    Label("Add Network", systemImage: "plus")
                                        .font(AppTypography.style(.subheadline, weight: .semibold))
                                        .settingsForegroundStyle(.primary)
                                }
                                .disabled(
                                    !snapshot.supportsMultipleNetworks ||
                                        isMutatingSavedNetworks ||
                                        showAddNetworkFlow
                                )
                            }

                            if showAddNetworkFlow {
                                addSavedNetworkInlinePanel
                            } else if showManualNetworkEntry {
                                manualSavedNetworkPanel
                            }
                        } else if isLoadingSavedNetworks {
                            ProgressView().tint(.white)
                        }
                    }
                })
            }

            if let savedNetworkMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: savedNetworkMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(savedNetworkMessage)
                        .font(AppTypography.style(.caption))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .settingsForegroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background((savedNetworkMessageIsError ? Color.red : Color.green).opacity(0.18))
                .cornerRadius(8)
            }

            advancedNetworkShortcutSection
        }
    }

    private var softwareUpdateCard: some View {
        SettingsCard(title: "Software Update", glassStyle: .detailControl) {
            VStack(spacing: 12) {
                InfoRow(label: "Installed version", value: info?.ver ?? "Unknown")

                HStack {
                    Text("Recommended software")
                        .font(AppTypography.style(.subheadline, weight: .medium))
                        .settingsForegroundStyle(.primary)
                    Spacer()
                    Text("Aesdetic")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }

                updateStatusView

                if case .updateAvailable = updateCheckStatus {
                    Button(action: { showRecommendedSoftwareConfirmation = true }) {
                        SettingsButton(title: "Update Recommended Software", icon: "arrow.up.circle.fill")
                    }
                }

                Button(action: { Task { await checkForStableUpdate() } }) {
                    SettingsButton(title: "Check Software Update", icon: "arrow.clockwise")
                }
                .disabled(isSoftwareUpdateInProgress)
            }
        }
    }

    private var isSoftwareUpdateInProgress: Bool {
        if case .updating = updateCheckStatus { return true }
        return false
    }

    private var isWiFiDeviceReachable: Bool {
        activeDevice.isOnline || viewModel.isDeviceOnline(activeDevice)
    }

    private var replacementOptions: [WLEDSavedNetwork] {
        guard let snapshot = savedNetworkSnapshot,
              snapshot.connectedSlot != nil else { return [] }
        return snapshot.networks.filter { $0.slot != snapshot.connectedSlot }
    }

    private func requiresReplacement(for ssid: String) -> Bool {
        guard let snapshot = savedNetworkSnapshot else { return false }
        let alreadySaved = snapshot.networks.contains {
            $0.ssid.caseInsensitiveCompare(ssid.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
        let highestOccupiedSlot = snapshot.networks.map(\.slot).max() ?? -1
        return !alreadySaved && highestOccupiedSlot + 1 >= snapshot.capacity
    }

    @ViewBuilder
    private func savedNetworkRow(_ network: WLEDSavedNetwork, snapshot: WLEDSavedNetworkSnapshot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: network.status == .connected ? "wifi.circle.fill" : "wifi")
                .font(AppTypography.style(.title3))
                .settingsForegroundStyle(.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(network.ssid)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                    .lineLimit(2)
                Text(savedNetworkStatusText(network.status))
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.78))
            }

            Spacer(minLength: 8)

            Image(systemName: network.hasPassword ? "lock.fill" : "lock.open")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.74))
                .accessibilityLabel(network.hasPassword ? "Password protected" : "Open network")

            Button {
                beginEditingSavedNetwork(network)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))
            .disabled(isMutatingSavedNetworks)
            .accessibilityLabel("Edit \(network.ssid)")

            if network.slot != snapshot.connectedSlot {
                Button(role: .destructive) {
                    pendingNetworkRemoval = network
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.9))
                .disabled(snapshot.connectedSlot == nil || isMutatingSavedNetworks)
                .accessibilityLabel("Remove \(network.ssid)")
            }
        }
        .padding(.vertical, 4)
    }

    private func savedNetworkStatusText(_ status: WLEDSavedNetworkStatus) -> String {
        switch status {
        case .connected: return "Connected now"
        case .saved: return "Saved"
        case .notTested: return "Saved, not tested yet"
        }
    }

    private var addNetworkScanResults: [WiFiNetwork] {
        WLEDSavedNetworkService.strongestNetworksBySSID(availableNetworks)
    }

    private var visibleAddNetworkScanResults: [WiFiNetwork] {
        showAllAddNetworkScanResults
            ? addNetworkScanResults
            : Array(addNetworkScanResults.prefix(3))
    }

    private var addNetworkCanSubmit: Bool {
        manualNetworkDraft.isValid &&
            !isMutatingSavedNetworks &&
            (!requiresReplacement(for: manualNetworkDraft.normalizedSSID) || replacementSlot != nil)
    }

    private var addSavedNetworkInlinePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().background(Color.white.opacity(0.16))

            HStack {
                Text("Add Network")
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                Spacer()
                Button {
                    showAddNetworkFlow = false
                    resetAddNetworkFlow()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.9))
                .disabled(isMutatingSavedNetworks)
                .accessibilityLabel("Close add network")
            }

            if !addNetworkUsesManualEntry && addNetworkSelection == nil {
                addNetworkScanSection
            }

            if addNetworkUsesManualEntry || addNetworkSelection != nil {
                addNetworkCredentialsSection
            }

            if !addNetworkUsesManualEntry && addNetworkSelection == nil {
                Button {
                    addNetworkUsesManualEntry = true
                    addNetworkSelection = nil
                    replacementSlot = nil
                    addNetworkSaveError = nil
                    manualNetworkDraft = WLEDSavedNetworkDraft()
                } label: {
                    Label("Enter Network Manually", systemImage: "keyboard")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else if addNetworkUsesManualEntry {
                Button {
                    addNetworkUsesManualEntry = false
                    addNetworkSelection = nil
                    replacementSlot = nil
                    addNetworkSaveError = nil
                    manualNetworkDraft = WLEDSavedNetworkDraft()
                    addNetworkScanRequestID = UUID()
                } label: {
                    Label("Choose a Nearby Network", systemImage: "wifi")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addNetworkSelection = nil
                        replacementSlot = nil
                        addNetworkSaveError = nil
                        manualNetworkDraft.clearSensitiveValues()
                        manualNetworkDraft = WLEDSavedNetworkDraft()
                    }
                } label: {
                    Label("Choose Another Network", systemImage: "arrow.left")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isMutatingSavedNetworks)
            }
        }
        .task(id: addNetworkScanRequestID) {
            await scanForAddNetwork()
        }
    }

    private var addNetworkScanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby Networks")
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                Spacer()
                if isScanningAddNetworks && !addNetworkScanResults.isEmpty {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                }
                Button {
                    addNetworkScanRequestID = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .settingsForegroundStyle(.primary)
                .disabled(isScanningAddNetworks)
                .accessibilityLabel("Scan again")
            }

            if isScanningAddNetworks && addNetworkScanResults.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Searching...")
                        .font(AppTypography.style(.subheadline))
                        .settingsForegroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            } else {
                if let addNetworkScanError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text(addNetworkScanError)
                            .font(AppTypography.style(.subheadline))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .settingsForegroundStyle(.primary)
                    .padding(12)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                if addNetworkScanResults.isEmpty {
                    Text("Nearby networks have not loaded yet.")
                        .font(AppTypography.style(.subheadline))
                        .settingsForegroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }

                LazyVStack(spacing: 8) {
                    ForEach(visibleAddNetworkScanResults) { network in
                        addNetworkScanRow(network)
                    }
                }

                if addNetworkScanResults.count > 3 {
                    Button {
                        showAllAddNetworkScanResults.toggle()
                    } label: {
                        Text(
                            showAllAddNetworkScanResults
                                ? "Show Fewer"
                                : "Show More (\(addNetworkScanResults.count - 3))"
                        )
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundStyle(AppTheme.tokens(for: colorScheme).settingsText(.primary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wifi-show-more-networks")
                }
            }
        }
    }

    @ViewBuilder
    private var addNetworkCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().background(Color.white.opacity(0.16))

            Text("Network Details")
                .font(AppTypography.style(.headline, weight: .semibold))
                .settingsForegroundStyle(.primary)

            if addNetworkUsesManualEntry {
                TextField("Network name", text: $manualNetworkDraft.ssid)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Toggle("This network has no password", isOn: $manualNetworkDraft.isOpenNetwork)
                    .settingsToggleStyle()
                    .onChange(of: manualNetworkDraft.isOpenNetwork) { _, isOpen in
                        if isOpen { manualNetworkDraft.clearSensitiveValues() }
                        addNetworkSaveError = nil
                    }
            } else if let selection = addNetworkSelection {
                HStack(spacing: 10) {
                    Image(systemName: "wifi")
                    Text(selection.ssid)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                    Spacer()
                    Image(systemName: manualNetworkDraft.isOpenNetwork ? "lock.open" : "lock.fill")
                }
                .settingsForegroundStyle(.primary)
            }

            if !manualNetworkDraft.isOpenNetwork {
                SecureField("Network password", text: $manualNetworkDraft.password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            } else {
                Label("No password required", systemImage: "lock.open")
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
            }

            if requiresReplacement(for: manualNetworkDraft.normalizedSSID) {
                replacementPicker
            }

            SettingsDescriptionText(
                markdown: "**Save for later** keeps the current connection. **Connect now** moves this device to the selected network."
            )

            if let addNetworkSaveError {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(addNetworkSaveError)
                        .font(AppTypography.style(.caption))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .settingsForegroundStyle(.primary)
                .padding(12)
                .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 8) {
                Button {
                    performSavedNetworkAction(.saveOnly, draft: manualNetworkDraft)
                } label: {
                    SettingsButton(title: "Save for Later", icon: "plus.circle.fill")
                }

                Button {
                    performSavedNetworkAction(.changeNow, draft: manualNetworkDraft)
                } label: {
                    SettingsButton(title: "Connect Now", icon: "arrow.triangle.swap")
                }
            }
            .disabled(!addNetworkCanSubmit || isConnecting)

            if isConnecting || isMutatingSavedNetworks {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text(isConnecting ? "Moving to the new network..." : "Saving...")
                        .font(AppTypography.style(.caption, weight: .medium))
                        .settingsForegroundStyle(.secondary)
                }
            }
        }
    }

    private func addNetworkScanRow(_ network: WiFiNetwork) -> some View {
        let status = addNetworkStatus(for: network)
        let isSelected = addNetworkSelection?.ssid.caseInsensitiveCompare(network.ssid) == .orderedSame

        return Button {
            guard status == nil else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                addNetworkSelection = network
                replacementSlot = nil
                addNetworkSaveError = nil
                manualNetworkDraft = WLEDSavedNetworkDraft(
                    ssid: network.ssid,
                    password: "",
                    isOpenNetwork: isOpenNetwork(network)
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: status == "Connected" ? "wifi.circle.fill" : "wifi")
                    .font(AppTypography.style(.title3))
                    .settingsForegroundStyle(.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(network.ssid)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .lineLimit(2)
                    Text(status ?? wifiSignalSummary(network.signalStrength))
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.78))
                }

                Spacer(minLength: 8)

                Image(systemName: isOpenNetwork(network) ? "lock.open" : "lock.fill")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.74))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .settingsForegroundStyle(.primary)
                } else if status == nil {
                    Image(systemName: "chevron.right")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(0.64))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.14 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(isSelected ? 0.28 : 0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(status != nil || isMutatingSavedNetworks)
        .accessibilityLabel(status.map { "\(network.ssid), \($0)" } ?? "Add \(network.ssid)")
    }

    @ViewBuilder
    private var manualSavedNetworkPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().background(Color.white.opacity(0.16))

            TextField("Network name", text: $manualNetworkDraft.ssid)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Toggle("This network has no password", isOn: $manualNetworkDraft.isOpenNetwork)
                .settingsToggleStyle()
                .onChange(of: manualNetworkDraft.isOpenNetwork) { _, isOpen in
                    if isOpen { manualNetworkDraft.clearSensitiveValues() }
                }

            if !manualNetworkDraft.isOpenNetwork {
                SecureField("Network password", text: $manualNetworkDraft.password)
                    .textFieldStyle(.roundedBorder)
            }

            if requiresReplacement(for: manualNetworkDraft.normalizedSSID) {
                replacementPicker
            }

            SettingsDescriptionText(
                markdown: "**Save for later:** The password is tested when the device reaches that network."
            )

            VStack(spacing: 8) {
                Button {
                    performSavedNetworkAction(.saveOnly, draft: manualNetworkDraft)
                } label: {
                    Label("Save for Another Location", systemImage: "plus.circle")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.16))
                        .cornerRadius(8)
                }

                Button {
                    performSavedNetworkAction(.changeNow, draft: manualNetworkDraft)
                } label: {
                    Label("Change to This Network", systemImage: "arrow.triangle.swap")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.16))
                        .cornerRadius(8)
                }
            }
            .settingsForegroundStyle(.primary)
            .disabled(
                !manualNetworkDraft.isValid ||
                isMutatingSavedNetworks ||
                (requiresReplacement(for: manualNetworkDraft.normalizedSSID) && replacementSlot == nil)
            )
        }
    }

    @ViewBuilder
    private var replacementPicker: some View {
        if replacementOptions.isEmpty {
            Text("Refresh the connection before choosing a saved network to replace.")
                .font(AppTypography.style(.caption))
                .settingsForegroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Replace a saved network")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .settingsForegroundStyle(.secondary)
                Picker("Saved network to replace", selection: $replacementSlot) {
                    Text("Choose a network").tag(Int?.none)
                    ForEach(replacementOptions) { network in
                        Text(network.ssid).tag(Optional(network.slot))
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
        }
    }

    private var advancedNetworkShortcutSection: some View {
        SettingsCard(title: "Advanced Network") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsDescriptionText(
                    markdown: "**Technical network controls:** Local address, static IP, recovery hotspot, radio, Ethernet, and ESP-NOW."
                )

                Button(action: openAdvancedWiFiNetworkSettings) {
                    SettingsButton(title: "Open Advanced WiFi & Network", icon: "slider.horizontal.3")
                }
            }
        }
    }

    private var integrationsSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Alexa") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Basic Alexa control:** Power, brightness, and color. Save, then run Discover Devices."
                    )

                    Button(action: {
                        Task { await loadAlexaIntegrationSettings() }
                    }) {
                        SettingsInlineButton(title: "Refresh Alexa Status", icon: "arrow.clockwise")
                    }
                    .disabled(isLoadingAlexaSettings)

                    SmartHomeIntegrationStatusRow(status: alexaIntegrationStatus)

                    if !alexaIntegrationSupported {
                        Text("This WLED firmware build does not include Alexa support.")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .settingsForegroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Toggle("Enable Alexa Control", isOn: $alexaEnabled)
                        .tint(.white)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .disabled(!alexaIntegrationSupported || isLoadingAlexaSettings)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Alexa Name")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .settingsForegroundStyle(.secondary)
                        TextField("Bedroom Lights", text: $alexaInvocationName)
                            .settingsTextFieldChrome(theme: AppTheme.tokens(for: colorScheme))
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .disabled(!alexaIntegrationSupported)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        InfoRow(label: "Alexa Favorites", value: "\(alexaFavoritesCount)/9")

                        Toggle("Automatically add new presets while space is available", isOn: alexaAutoFillBinding)
                            .settingsToggleStyle()
                            .disabled(!alexaIntegrationSupported)

                        Button(action: {
                            alexaSettingsMessage = "Manage Alexa Favorites from this device's Presets tab."
                            alexaSettingsMessageIsError = false
                        }) {
                            SettingsButton(title: "Manage Alexa Favorites", icon: "star.circle")
                        }
                        .disabled(!alexaIntegrationSupported)
                    }

                    if isLoadingAlexaSettings {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("Loading Alexa settings...")
                                .font(AppTypography.style(.caption))
                                .settingsForegroundStyle(.secondary)
                        }
                    }

                    if let alexaSettingsMessage {
                        Text(alexaSettingsMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(alexaSettingsMessageIsError ? .orange : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showAlexaDiscoveryInstructions {
                        AlexaDiscoveryInstructionsView(deviceName: alexaInvocationName)
                    }

                    Button(action: saveAlexaIntegrationSettings) {
                        HStack(spacing: 8) {
                            if isSavingAlexaSettings {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text("Save Alexa Setup")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(10)
                    }
                    .disabled(
                        !alexaIntegrationSupported ||
                            isSavingAlexaSettings ||
                            alexaInvocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if alexaIntegrationSupported {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                SettingsDescriptionText(
                                    markdown: "**Optional preset actions:** Use `0` to leave an action disabled."
                                )

                                IntStepperRow(title: "Alexa On Action", value: $macroAlexaOn, range: 0...250, onEnd: commitMacroBindings)
                                IntStepperRow(title: "Alexa Off Action", value: $macroAlexaOff, range: 0...250, onEnd: commitMacroBindings)

                                Button(action: commitMacroBindings) {
                                    HStack(spacing: 8) {
                                        if isSavingMacroBindings {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(.white)
                                        }
                                        Text("Save Alexa Actions")
                                            .font(AppTypography.style(.subheadline, weight: .semibold))
                                            .settingsForegroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.18))
                                    .cornerRadius(10)
                                }
                                .disabled(isSavingMacroBindings)
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.3")
                                    .settingsForegroundStyle(.secondary)
                                Text("Advanced Alexa Actions")
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
                                    .settingsForegroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .tint(.white)
                    }
                }
            }

            SettingsCard(title: "Home Assistant") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Recommended bridge:** Home Assistant usually discovers this \(settingsObjectNameLowercased) on the same network."
                    )

                    SmartHomeIntegrationStatusRow(status: homeAssistantIntegrationStatus)

                    InfoRow(label: "Device IP", value: activeDevice.ipAddress)
                    InfoRow(label: "Setup type", value: "Discovered device or WLED integration")
                    InfoRow(label: "Cleanup default", value: "Hide segment entities")
                    InfoRow(label: "Best for", value: "Power, brightness, bridge control")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Optional details")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .settingsForegroundStyle(.secondary)

                        TextField("http://homeassistant.local:8123", text: homeAssistantTextBinding(\.homeAssistantURL))
                            .settingsTextFieldChrome(theme: AppTheme.tokens(for: colorScheme))
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .disableAutocorrection(true)

                        TextField("light.bedroom_lights", text: homeAssistantTextBinding(\.mainEntityName))
                            .settingsTextFieldChrome(theme: AppTheme.tokens(for: colorScheme))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HomeAssistantChecklistRow(
                            title: "WLED discovered or added in Home Assistant",
                            detail: "Use the discovered WLED device. If it does not appear, add WLED from Settings > Devices & services > Add integration.",
                            isComplete: homeAssistantChecklistBinding(\.isWLEDAdded)
                        )
                        HomeAssistantChecklistRow(
                            title: "Main light kept",
                            detail: "Keep the main/master WLED light entity for power and whole-device brightness.",
                            isComplete: homeAssistantChecklistBinding(\.isMainLightKept)
                        )
                        HomeAssistantChecklistRow(
                            title: "Segment entities hidden",
                            detail: "Hide segment lights and segment controls unless you intentionally want per-segment HA control.",
                            isComplete: homeAssistantChecklistBinding(\.areSegmentsDisabled)
                        )
                    }

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            HomeAssistantInstructionRow(index: 1, text: "Open Home Assistant > Settings > Devices & services > WLED > your device > menu > Entities.")
                            HomeAssistantInstructionRow(index: 2, text: "Search for Segment.")
                            HomeAssistantInstructionRow(index: 3, text: "Press the select icon near the filters.")
                            HomeAssistantInstructionRow(index: 4, text: "Select entities whose names start with Segment. Do not select the main light entity.")
                            HomeAssistantInstructionRow(index: 5, text: "Open the top-right menu, choose Hide selected, then confirm Hide.")
                            SettingsDescriptionText(
                                markdown: "**Keep the main light:** Hide, but do not delete, segment entities or app-managed presets."
                            )
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .settingsForegroundStyle(.secondary)
                            Text("Batch-hide segment instructions")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .tint(.white)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            HomeAssistantInstructionRow(index: 1, text: "Use Aesdetic for colors, gradients, saves, transitions, and sunrise routines.")
                            HomeAssistantInstructionRow(index: 2, text: "Use Home Assistant for power, brightness, smart-home sync, and HA automations.")
                            HomeAssistantInstructionRow(index: 3, text: "Keep app-managed presets and automation steps in WLED. They may be required by Aesdetic routines or transitions.")
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .settingsForegroundStyle(.secondary)
                            Text("Recommended use")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .tint(.white)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            HomeAssistantInstructionRow(index: 1, text: "Playlists are WLED playlists. In Aesdetic, these usually represent saved transitions.")
                            HomeAssistantInstructionRow(index: 2, text: "Presets are WLED presets. Aesdetic may use them for saved colors, effects, transitions, and internal routine steps.")
                            HomeAssistantInstructionRow(index: 3, text: "Ignore app-managed automation step presets unless you know exactly what they do. Deleting them can break saved routines or transitions.")
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "text.book.closed")
                                .settingsForegroundStyle(.secondary)
                            Text("Home Assistant wording")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .tint(.white)

                    Button(action: { openExternalURL("https://www.home-assistant.io/integrations/wled/") }) {
                        SettingsButton(title: "Open Home Assistant Guide", icon: "house")
                    }
                }
            }

            SettingsCard(title: "Smart Homes through Home Assistant") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Bridge from Home Assistant:** Expose the main light to Apple Home, Alexa, or Google."
                    )

                    InfoRow(label: "Apple Home", value: "HomeKit Bridge")
                    InfoRow(label: "Alexa or Google", value: "Expose from Home Assistant")
                    InfoRow(label: "Default", value: "Main WLED light only")

                    HomeAssistantChecklistRow(
                        title: "HomeKit Bridge exposes main light only",
                        detail: "Include the main light entity. Leave segment entities hidden or excluded from Apple Home.",
                        isComplete: homeAssistantChecklistBinding(\.isHomeKitBridgeConfigured)
                    )

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            HomeAssistantInstructionRow(index: 1, text: "In Home Assistant, add or open HomeKit Bridge.")
                            HomeAssistantInstructionRow(index: 2, text: "Use include mode or selected entities.")
                            HomeAssistantInstructionRow(index: 3, text: "Select only the main WLED light entity, for example light.bedroom_lights.")
                            HomeAssistantInstructionRow(index: 4, text: "Add the HomeKit Bridge code in the Apple Home app.")
                            SettingsDescriptionText(
                                markdown: "**Keep it focused:** Expose the main light or selected scenes, not every segment."
                            )
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "homekit")
                                .settingsForegroundStyle(.secondary)
                            Text("Apple Home bridge steps")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .tint(.white)

                    Button(action: { openExternalURL("https://www.home-assistant.io/integrations/homekit/") }) {
                        SettingsButton(title: "Open HomeKit Bridge Guide", icon: "homekit")
                    }
                    Button(action: { openExternalURL("https://www.home-assistant.io/integrations/google_assistant/") }) {
                        SettingsButton(title: "Google Home from Home Assistant", icon: "person.wave.2")
                    }
                }
            }

            SettingsCard(title: "Advanced Connections") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Technical connections:** Sync, MQTT, Hue, DMX, realtime input, and firmware extensions."
                    )

                    Button(action: { openAdvancedCategory("sync-interfaces") }) {
                        SettingsButton(title: "Open Network & Sync Settings", icon: "slider.horizontal.3")
                    }
                }
            }
        }
    }

    private var compactIntegrationsSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Alexa", glassStyle: .detailControl) {
                VStack(alignment: .leading, spacing: 12) {
                    SmartHomeIntegrationStatusRow(status: alexaIntegrationStatus)

                    Button {
                        isAlexaQuickSetupExpanded.toggle()
                        if isAlexaQuickSetupExpanded && !hasLoadedAlexaIntegrationSettings {
                            Task { await loadAlexaIntegrationSettings() }
                        }
                    } label: {
                        SettingsButton(
                            title: isAlexaQuickSetupExpanded
                                ? "Hide Alexa Setup"
                                : (alexaIntegrationStatus.state == .enabled ? "Manage Alexa" : "Set Up Alexa"),
                            icon: "waveform.circle"
                        )
                    }

                    if isAlexaQuickSetupExpanded {
                        Divider().overlay(AppTheme.tokens(for: colorScheme).divider)
                        alexaQuickSetupContent
                    }
                }
            }

            SettingsCard(title: "Home Assistant", glassStyle: .detailControl) {
                VStack(alignment: .leading, spacing: 12) {
                    SmartHomeIntegrationStatusRow(status: homeAssistantIntegrationStatus)

                    SettingsDescriptionText(
                        markdown: "**Usually discovered automatically:** Keep the main light in Home Assistant and manage segments in Aesdetic."
                    )

                    Button {
                        isHomeAssistantQuickSetupExpanded.toggle()
                    } label: {
                        SettingsButton(
                            title: isHomeAssistantQuickSetupExpanded
                                ? "Hide Home Assistant Setup"
                                : (homeAssistantSetupState.hasStartedSetup ? "Continue Setup" : "Set Up Home Assistant"),
                            icon: "house"
                        )
                    }

                    if isHomeAssistantQuickSetupExpanded {
                        Divider().overlay(AppTheme.tokens(for: colorScheme).divider)
                        homeAssistantQuickSetupContent
                    }
                }
            }

            SettingsCard(title: "Advanced Connections", glassStyle: .detailControl) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Technical connections:** Sync, MQTT, Hue, realtime input, DMX, and serial."
                    )

                    Button(action: { openAdvancedCategory("sync-interfaces") }) {
                        SettingsButton(title: "Open Advanced Connections", icon: "slider.horizontal.3")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var alexaQuickSetupContent: some View {
        let theme = AppTheme.tokens(for: colorScheme)

        if isLoadingAlexaSettings {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(.white)
                Text("Loading Alexa settings...")
                    .font(AppTypography.style(.subheadline))
                    .foregroundStyle(theme.settingsText(.secondary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !alexaIntegrationSupported {
            Text("Alexa control is not included in this WLED firmware build.")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundStyle(theme.status.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Toggle("Enable Alexa control", isOn: $alexaEnabled)
                .settingsToggleStyle()

            VStack(alignment: .leading, spacing: 6) {
                Text("Name Alexa will discover")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundStyle(theme.settingsText(.secondary))

                TextField(activeDevice.name, text: $alexaInvocationName)
                    .settingsTextFieldChrome(theme: theme)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)

                Text("Use a short, distinct name such as Bedroom Lamp.")
                    .font(AppTypography.style(.caption2))
                    .foregroundStyle(theme.settingsText(.secondary))
            }

            Button(action: saveAlexaIntegrationSettings) {
                SettingsButton(
                    title: isSavingAlexaSettings ? "Saving Alexa Setup..." : "Save Alexa Setup",
                    icon: "checkmark.circle"
                )
            }
            .disabled(
                isSavingAlexaSettings
                    || alexaInvocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }

        if let alexaSettingsMessage {
            Text(alexaSettingsMessage)
                .font(AppTypography.style(.caption, weight: .medium))
                .foregroundStyle(alexaSettingsMessageIsError ? theme.status.warning : theme.settingsText(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if showAlexaDiscoveryInstructions {
            AlexaDiscoveryInstructionsView(deviceName: alexaInvocationName)
        }
    }

    private var homeAssistantQuickSetupContent: some View {
        let theme = AppTheme.tokens(for: colorScheme)

        return VStack(alignment: .leading, spacing: 12) {
            SettingsDescriptionText(
                markdown: "**Add the WLED integration:** Keep the main light visible, then mark each completed step."
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Home Assistant address")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundStyle(theme.settingsText(.secondary))
                TextField("http://homeassistant.local:8123", text: homeAssistantTextBinding(\.homeAssistantURL))
                    .settingsTextFieldChrome(theme: theme)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
            }

            Button(action: openHomeAssistantIntegrations) {
                SettingsButton(title: "Open Home Assistant Integrations", icon: "arrow.up.forward.app")
            }

            HomeAssistantChecklistRow(
                title: "WLED device added",
                detail: "In Home Assistant, add the WLED integration and select this device.",
                isComplete: homeAssistantChecklistBinding(\.isWLEDAdded)
            )
            HomeAssistantChecklistRow(
                title: "Main light kept",
                detail: "Keep the main light entity for power and whole-device brightness.",
                isComplete: homeAssistantChecklistBinding(\.isMainLightKept)
            )
            HomeAssistantChecklistRow(
                title: "Extra segment entities hidden",
                detail: "Hide segment entities unless you intentionally need separate segment control.",
                isComplete: homeAssistantChecklistBinding(\.areSegmentsDisabled)
            )

            Button(action: { openExternalURL("https://www.home-assistant.io/integrations/wled/") }) {
                SettingsButton(title: "Open WLED Integration Guide", icon: "book")
            }
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
                        .settingsForegroundStyle(.secondary)

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
                        .settingsForegroundStyle(.secondary)

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
                        .settingsForegroundStyle(.primary)

                    Text("MQTT is only available on firmware builds compiled with MQTT support.")
                        .font(AppTypography.style(.caption))
                        .settingsForegroundStyle(.secondary)
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
                        .settingsForegroundStyle(.secondary)
                    Text("Hue sync is only available on firmware builds compiled with Hue support.")
                        .font(AppTypography.style(.caption))
                        .settingsForegroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                integrationDisclosureLabel("Philips Hue Sync", icon: "lightbulb.2")
            }
            .tint(.white)
        }
    }

    private var ledHardwareStatus: String {
        if isLoadingLEDConfiguration {
            return "Loading"
        }
        if let ledConfiguration {
            return "\(ledConfiguration.ledCount) LEDs"
        }
        if activeDevice.setupState == .pendingSelection {
            return "Setup needed"
        }
        return "Guided setup"
    }

    private var scheduleStatusSummary: String {
        if isLoadingTimers {
            return "Loading"
        }
        let enabledCount = timerDrafts.filter { $0.enabled && $0.macroId > 0 }.count
        if enabledCount == 0 {
            return "No timers"
        }
        return "\(enabledCount) timer(s)"
    }

    private var protocolStatusSummary: String {
        if isLoadingNativeIntegrations {
            return "Loading"
        }
        let enabledProtocols = [
            nativeIntegrationSettings.sync.receiveBrightness ||
                nativeIntegrationSettings.sync.receiveColor ||
                nativeIntegrationSettings.sync.receiveEffects ||
                nativeIntegrationSettings.sync.sendDirectChanges,
            nativeIntegrationSettings.realtime.receiveRealtime,
            nativeIntegrationSettings.mqtt.enabled,
            nativeIntegrationSettings.hue.enabled
        ].filter { $0 }.count

        return enabledProtocols == 0 ? "Native + web" : "\(enabledProtocols) active"
    }

    private var ledHardwareSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingLEDConfiguration {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                    Text("Loading LED preferences...")
                        .font(AppTypography.style(.caption))
                        .settingsForegroundStyle(.secondary)
                }
            } else if let ledConfiguration {
                InfoRow(label: "LED type", value: ledStripTypeName(ledConfiguration.stripType))
                InfoRow(label: "LED count", value: "\(ledConfiguration.ledCount)")
                InfoRow(label: "GPIO", value: "\(ledConfiguration.gpioPin)")
                InfoRow(label: "Color order", value: ledColorOrderName(ledConfiguration.colorOrder))
                InfoRow(label: "Current limit", value: ledConfiguration.enableABL ? "\(ledConfiguration.maxTotalCurrent) mA" : "Disabled")
                InfoRow(label: "Refresh rate", value: "\(ledConfiguration.targetFPS) FPS")
                InfoRow(label: "Gamma", value: String(format: "%.1f", ledConfiguration.gammaValue))
            } else {
                Text(ledConfigurationMessage ?? "LED summary is unavailable. Use guided product setup or WLED's full LED preferences to review hardware details.")
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let ledConfigurationMessage, ledConfiguration != nil {
                Text(ledConfigurationMessage)
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func ledStripTypeName(_ type: Int) -> String {
        LEDStripType.fromWLEDType(type)?.displayName ?? "Type \(type)"
    }

    private func ledColorOrderName(_ order: Int) -> String {
        LEDColorOrder(rawValue: order)?.displayName ?? "Order \(order)"
    }

    private var advancedSection: some View {
        WLEDAdvancedSettingsView(
            device: activeDevice,
            contentBottomPadding: contentBottomPadding,
            initialCategoryID: advancedInitialCategoryID,
            openWLEDPath: openWLEDPath,
            openTimeSchedules: {
                advancedInitialCategoryID = nil
                isAdvancedCategoryDetailActive = false
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    selectedSettingsCategory = .timeSchedules
                }
            },
            onHeaderStatusChange: { status in
                onSettingsHeaderStatusChange?(status)
            },
            onCategoryDetailActiveChange: { isActive in
                isAdvancedCategoryDetailActive = isActive
            },
            onHeaderChromeChange: { chrome in
                onSettingsHeaderChromeChange?(chrome)
            },
            onHeaderActionsChange: { actions in
                onSettingsHeaderActionsChange?(actions)
            },
            onFactoryResetComplete: {
                showFactoryResetRecoveryActions = true
            }
        )
    }

    private func removeFactoryResetDeviceFromApp() {
        guard !isRemovingFactoryResetDevice else { return }
        isRemovingFactoryResetDevice = true
        Task { @MainActor in
            await viewModel.removeDevice(activeDevice)
            isRemovingFactoryResetDevice = false
            onDeviceRemoved?()
        }
    }

    private var wledBuiltInSchedulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { openWLEDPath("/settings/time") }) {
                SettingsButton(title: "Open WLED Time Settings", icon: "clock")
            }

            Button(action: syncDeviceTimeFromPhone) {
                SyncLampClockButton(isSyncing: isSyncingDeviceTime, objectName: settingsObjectName)
            }
            .disabled(isSyncingDeviceTime)

            if let deviceTimeSyncMessage {
                Text(deviceTimeSyncMessage)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(deviceTimeSyncMessageIsError ? .orange : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            nativeWLEDTimersContent

            timedLightContent
        }
    }

    private var nativeWLEDTimersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsDescriptionText(
                markdown: "**Eight basic schedules:** Sunrise, sunset, and extra firmware rows remain separate."
            )

            if isLoadingTimers {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading timers...")
                        .font(AppTypography.style(.subheadline))
                        .settingsForegroundStyle(.secondary)
                }
            } else {
                ForEach(Array(timerDrafts.enumerated()), id: \.element.id) { index, draft in
                    TimerSlotEditorCard(
                        draft: Binding(
                            get: { timerDrafts[index] },
                            set: { timerDrafts[index] = $0 }
                        ),
                        isSaving: savingTimerSlotIds.contains(draft.id),
                        feedback: timerFeedbackBySlotId[draft.id],
                        onSave: {
                            commitTimerDraft(slotId: draft.id)
                        }
                    )
                }
            }

            Button(action: {
                Task {
                    await loadTimersAndMacros()
                    await MainActor.run { didLoadScheduleSettings = true }
                }
            }) {
                SettingsInlineButton(title: "Refresh Timers", icon: "arrow.clockwise")
            }
        }
    }

    private var timedLightContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsDescriptionText(
                markdown: "**Firmware timed light:** Use Aesdetic automations for normal wake and sleep routines."
            )

            Toggle("Enabled", isOn: $nightLightOn)
                .tint(.white)
                .settingsForegroundStyle(.primary)
            IntStepperRow(title: "Duration (min)", value: $nightLightDurationMin, range: 1...255, onEnd: commitNightLight)
            IntStepperRow(title: "Mode", value: $nightLightMode, range: 0...3, onEnd: commitNightLight)
            IntStepperRow(title: "Target Brightness", value: $nightLightTargetBri, range: 0...255, onEnd: commitNightLight)

            Button(action: commitNightLight) {
                SettingsInlineButton(title: "Apply Timed Light", icon: "timer")
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Realtime connection")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
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
            SettingsDescriptionText(
                markdown: "**Back up first:** Firmware uploads, resets, and raw config changes can be destructive.",
                tone: .warning
            )

            Button(action: { openWLEDPath("/settings/sec") }) {
                SettingsButton(title: "Security, PIN & OTA Locks", icon: "lock.shield")
            }
            Button(action: { openWLEDPath("/settings/sec#backup") }) {
                SettingsButton(title: "Backup & Restore", icon: "externaldrive")
            }
            Button(action: { showFirmwareUpdate = true }) {
                DangerSettingsButton(title: "Open WLED Firmware Upload", icon: "arrow.up.circle", level: .warning)
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
            Button(action: { openWLEDPath("/settings") }) {
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
        }
    }

    private var firmwareCoverageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsDescriptionText(
                markdown: "**Native where safe:** Firmware-specific tools remain available on their WLED pages."
            )

            ForEach(WLEDFirmwareSettingsArea.overviewAreas) { area in
                FirmwareCoverageRow(area: area)
            }
        }
    }

    private var ledsSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "LED Configuration") {
                VStack(spacing: 12) {
                    Button(action: { openWLEDPath("/settings/leds") }) {
                        SettingsButton(title: "LED Preferences", icon: "lightbulb")
                    }
                    Button(action: { openWLEDPath("/settings/leds") }) {
                        SettingsButton(title: "Pin Configuration", icon: "cable.connector")
                    }
                    Button(action: { openWLEDPath("/settings/leds") }) {
                        SettingsButton(title: "LED Type Settings", icon: "gear")
                    }
                }
            }

            if supportsCCTInSettings {
                SettingsCard(title: "Temperature") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use CCT for temperature stops", isOn: $temperatureStopsUseCCT)
                            .tint(.white)
                            .settingsForegroundStyle(.primary)
                            .onChange(of: temperatureStopsUseCCT) { _, value in
                                viewModel.setTemperatureStopsUseCCT(value, for: device)
                            }
                        SettingsDescriptionText(
                            markdown: "**Enabled:** Sends CCT per segment. **Disabled:** Maps temperature to RGB."
                        )
                    }
                }
            }

        }
    }

    private var config2dSection: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "2D Configuration") {
                VStack(spacing: 12) {
                    Button(action: { openWLEDPath("/settings/2D") }) {
                        SettingsButton(title: "Matrix Setup", icon: "rectangle.grid.2x2")
                    }
                    Button(action: { openWLEDPath("/settings/2D") }) {
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
                    SettingsDescriptionText(
                        markdown: "**Recommended:** About 18 active segments balances smooth gradients and preset size."
                    )
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
                                .settingsForegroundStyle(.primary)
                            Spacer()
                            Text("\(activeSegmentCountDraft)")
                                .settingsForegroundStyle(.primary)
                        }
                    }
                    .tint(.white)

                    SettingsDescriptionText(
                        markdown: "**Segment density:** Used by Aesdetic gradients and effects."
                    )

                    Button(action: applyActiveSegmentCountSetting) {
                        HStack(spacing: 8) {
                            if isApplyingSegmentCount {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text("Apply Segment Count")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(10)
                    }
                    .disabled(isApplyingSegmentCount)

                    Toggle("Show segment controls in Colors tab (Advanced UI)", isOn: $showSegmentControlsInColorTabAdvanced)
                        .tint(.white)
                        .settingsForegroundStyle(.primary)

                    if let segmentSettingsMessage {
                        Text(segmentSettingsMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(segmentSettingsMessageIsError ? .orange : .green)
                    }
                }
            }

            SettingsCard(title: "3) Segment Detail Edit (Temporary Override)") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsDescriptionText(
                        markdown: "**Temporary overrides:** Applying a color or gradient replaces them."
                    )

                    if editableSegments.isEmpty {
                        Text("No segments detected yet. Refresh device state and try again.")
                            .font(AppTypography.style(.footnote))
                            .settingsForegroundStyle(.secondary)
                    } else {
                        ForEach(editableSegments, id: \.id) { segment in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Segment \(segment.id + 1)")
                                        .font(AppTypography.style(.subheadline, weight: .semibold))
                                        .settingsForegroundStyle(.primary)
                                    Spacer()
                                    Text("LED \(segment.start)-\(segment.stop)")
                                        .font(AppTypography.style(.caption))
                                        .settingsForegroundStyle(.secondary)
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
                                                    .tint(.white)
                                            }
                                            Text("Apply")
                                                .font(AppTypography.style(.caption, weight: .semibold))
                                                .settingsForegroundStyle(.primary)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Color.white.opacity(0.18))
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
                        .settingsForegroundStyle(.primary)
                        SettingsDescriptionText(
                            markdown: "**Manual:** Keeps custom bounds. **Auto:** Optimizes Aesdetic gradients."
                        )

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
                    .settingsForegroundStyle(.primary)
                    .onChange(of: advancedUIEnabled) { _, newValue in
                        if !newValue {
                            viewModel.resetManualSegmentationForAllDevices()
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
                    Button(action: { openWLEDPath("/settings/sync") }) {
                        SettingsButton(title: "DMX Configuration", icon: "cable.connector")
                    }
                    Button(action: { openWLEDPath("/settings/sync") }) {
                        SettingsButton(title: "Art-Net Settings", icon: "network")
                    }
                    Button(action: { openWLEDPath("/settings/sync") }) {
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
                    Button(action: { openWLEDPath("/settings/time") }) {
                        SettingsButton(title: "Time Settings", icon: "clock")
                    }
                    Button(action: { openWLEDPath("/settings/time") }) {
                        SettingsButton(title: "Macro Configuration", icon: "play.circle")
                    }
                    Button(action: { openWLEDPath("/settings/time") }) {
                        SettingsButton(title: "Timer Settings", icon: "timer")
                    }
                    Button(action: syncDeviceTimeFromPhone) {
                        HStack(spacing: 10) {
                            if isSyncingDeviceTime {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
                                    .settingsForegroundStyle(.primary)
                            }

                            Text("Sync Device Time/Timezone from Phone")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.18))
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
                    SettingsDescriptionText(
                        markdown: "**Slots 1-8:** Basic preset schedules. Sunrise and sunset stay in Aesdetic automations."
                    )

                    if isLoadingTimers {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading timers...")
                                .font(AppTypography.style(.subheadline))
                                .settingsForegroundStyle(.secondary)
                        }
                    } else {
                        ForEach(Array(timerDrafts.enumerated()), id: \.element.id) { index, draft in
                            TimerSlotEditorCard(
                                draft: Binding(
                                    get: { timerDrafts[index] },
                                    set: { timerDrafts[index] = $0 }
                                ),
                                isSaving: savingTimerSlotIds.contains(draft.id),
                                feedback: timerFeedbackBySlotId[draft.id],
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
                            .settingsForegroundStyle(.primary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(10)
                    }
                }
            }

            SettingsCard(title: "Night Light") {
                VStack(spacing: 12) {
                    Toggle("Enabled", isOn: $nightLightOn)
                        .tint(.white)
                        .settingsForegroundStyle(.primary)

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
                        .settingsForegroundStyle(.primary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(10)
                }
            }

            SettingsCard(title: "Macro Triggers") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Use `0` to disable:** These are WLED hooks, not Aesdetic automations."
                    )

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
                                    .tint(.white)
                            }
                            Text("Apply Macro Triggers")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.18))
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
                    Button(action: { openWLEDPath("/settings/um") }) {
                        SettingsButton(title: "Custom Modifications", icon: "puzzlepiece")
                    }
                    Button(action: { openWLEDPath("/settings/um") }) {
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
                    Button(action: { openWLEDPath("/settings/sec") }) {
                        SettingsButton(title: "Security Settings", icon: "lock.shield")
                    }
                    Button(action: { openWLEDPath("/update") }) {
                        SettingsButton(title: "Firmware Update", icon: "arrow.up.circle")
                    }
                    Button(action: { openWLEDPath("/reset") }) {
                        SettingsButton(title: "Factory Reset", icon: "arrow.clockwise")
                    }
                }
            }

            SettingsCard(title: "Realtime Updates") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Realtime Updates")
                            .font(AppTypography.style(.headline, weight: .semibold))
                            .settingsForegroundStyle(.primary)
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
                                .settingsForegroundStyle(.primary)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color.white.opacity(0.18))
                                .cornerRadius(10)
                        }

                        Button(action: { Task { await WLEDAPIService.shared.clearCache() } }) {
                            Text("Clear Cache")
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .settingsForegroundStyle(.primary)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color.white.opacity(0.18))
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

            var coordinate = await AutomationStore.shared.currentCoordinate(requestAuthorization: true)
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
                .settingsForegroundStyle(.secondary)
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .settingsForegroundStyle(.primary)
            Spacer()
        }
    }

    private func commitTimerDraft(slotId: Int) {
        guard let draft = timerDrafts.first(where: { $0.id == slotId }) else { return }
        savingTimerSlotIds.insert(slotId)
        timerFeedbackBySlotId.removeValue(forKey: slotId)

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

            let outcome = await WLEDAPIService.shared.updateAndVerifyTimer(update, on: device)
            await MainActor.run {
                switch outcome {
                case .committed:
                    timerFeedbackBySlotId[slotId] = .verified
                case .verificationNeeded:
                    timerFeedbackBySlotId[slotId] = .verificationNeeded
                case .notCommitted:
                    timerFeedbackBySlotId[slotId] = .notSaved
                }
            }
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
                hasLoadedAlexaIntegrationSettings = true
                alexaIntegrationSupported = settings.isSupported
                alexaEnabled = settings.isSupported && settings.isEnabled
                alexaInvocationName = settings.invocationName
                alexaPresetCount = settings.exposedPresetCount
                viewModel.setAlexaIntegrationEnabled(settings.isSupported && settings.isEnabled, for: activeDevice.id)
                SmartHomeIntegrationStore.shared.setStatus(
                    settings.isSupported ? (settings.isEnabled ? .enabled : .notSetUp) : .unsupported,
                    for: .alexa,
                    deviceId: activeDevice.id,
                    message: settings.isSupported ? nil : "This WLED firmware build does not include Alexa support.",
                    verificationSource: .reportedByDevice
                )
                if !settings.isSupported {
                    alexaSettingsMessage = "This WLED firmware build does not include Alexa support."
                    alexaSettingsMessageIsError = true
                    showAlexaDiscoveryInstructions = false
                }
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
        guard alexaIntegrationSupported else {
            alexaSettingsMessage = "This WLED firmware build does not include Alexa support."
            alexaSettingsMessageIsError = true
            showAlexaDiscoveryInstructions = false
            return
        }

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
                    hasLoadedAlexaIntegrationSettings = true
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
                hasLoadedNativeIntegrationSettings = true
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
        guard hasLoadedNativeIntegrationSettings else {
            nativeIntegrationsMessage = "Load WLED integration settings before saving."
            nativeIntegrationsMessageIsError = true
            return
        }

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
                Text("Check whether your lamp has Aesdetic-recommended software.")
                    .font(AppTypography.style(.subheadline))
                    .settingsForegroundStyle(.secondary)
            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking software...")
                        .font(AppTypography.style(.subheadline))
                        .settingsForegroundStyle(.secondary)
                }
            case .updating(let message):
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(message)
                        .font(AppTypography.style(.subheadline))
                        .settingsForegroundStyle(.secondary)
                }
            case .upToDate(let current, let latest):
                Text("Your lamp software is ready.")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                Text("Version \(current) (recommended \(latest))")
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.secondary)
            case .updateAvailable(let current, let latest):
                Text("A recommended update is ready.")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                Text("Current \(current) → Recommended \(latest)")
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.secondary)
            case .error(let message):
                Text(message)
                    .font(AppTypography.style(.subheadline))
                    .settingsForegroundStyle(.secondary)
            }

            if let lastUpdateCheck {
                Text("Last checked \(lastUpdateCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppTypography.style(.caption2))
                    .settingsForegroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkForStableUpdate() async {
        updateCheckStatus = .checking
        do {
            let isAesdeticProduct = activeDevice.productType != .generic
            let assessment = try await WLEDFirmwareUpdateService.shared.recommendedAssessment(
                for: activeDevice,
                isAesdeticProduct: isAesdeticProduct
            )
            lastUpdateCheck = Date()
            switch assessment {
            case .upToDate(let current, let target):
                latestStableVersion = target
                updateCheckStatus = .upToDate(current: current, latest: target)
            case .available(let current, let target, _):
                latestStableVersion = target
                updateCheckStatus = .updateAvailable(current: current, latest: target)
            case .manualUpdateRequired, .unavailable:
                updateCheckStatus = .error("This lamp needs a manual software update.")
            }
        } catch {
            lastUpdateCheck = Date()
            updateCheckStatus = .error("Could not check for software updates.")
        }
    }

    private func installRecommendedSoftware() async {
        updateCheckStatus = .updating(WLEDFirmwareUpdatePhase.preflight.customerMessage)
        do {
            let version = try await WLEDFirmwareUpdateService.shared.installRecommendedUpdate(for: activeDevice) { phase in
                updateCheckStatus = .updating(phase.customerMessage)
            }
            await viewModel.refreshDeviceState(activeDevice)
            latestStableVersion = WLEDFirmwareUpdateService.approvedBaselineVersion
            lastUpdateCheck = Date()
            updateCheckStatus = .upToDate(
                current: version,
                latest: WLEDFirmwareUpdateService.approvedBaselineVersion
            )
        } catch {
            lastUpdateCheck = Date()
            updateCheckStatus = .error("We couldn’t complete the software update. Try again later or use Advanced update options.")
        }
    }

    private func openWLEDPath(_ path: String) {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: "http://\(activeDevice.ipAddress)\(normalizedPath)") else { return }
        wledWebDestination = WLEDWebDestination(url: url)
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private func openHomeAssistantIntegrations() {
        let savedAddress = homeAssistantSetupState.homeAssistantURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var address = savedAddress.flatMap { $0.isEmpty ? nil : $0 }
            ?? "http://homeassistant.local:8123"

        if !address.contains("://") {
            address = "http://\(address)"
        }

        guard var components = URLComponents(string: address) else {
            openExternalURL("https://www.home-assistant.io/integrations/wled/")
            return
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/config/integrations/dashboard"
        }

        guard let url = components.url else {
            openExternalURL("https://www.home-assistant.io/integrations/wled/")
            return
        }
        openURL(url)
    }

    private func openAdvancedWiFiNetworkSettings() {
        openAdvancedCategory("wifi-network")
    }

    private func openAdvancedCategory(_ categoryID: String) {
        advancedInitialCategoryID = categoryID
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            selectedSettingsCategory = .advanced
        }
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
                hasLoadedAdvancedNetworkConfiguration = true
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
        guard hasLoadedAdvancedNetworkConfiguration else {
            advancedNetworkMessage = "Load advanced network settings before saving."
            advancedNetworkMessageIsError = true
            return
        }

        let validationIssues = advancedNetworkDraft.validationIssues
        guard validationIssues.isEmpty else {
            advancedNetworkMessage = validationIssues.prefix(2).joined(separator: " ")
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
                    advancedNetworkMessage = "Advanced network settings saved. If the \(settingsObjectNameLowercased) address changed, use discovery or reopen it from its new IP."
                    advancedNetworkMessageIsError = false
                }
                await refreshWiFiStatusAfterNetworkChange()
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
        await loadSavedNetworkSnapshot()
    }

    private func loadSavedNetworkSnapshot(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isLoadingWiFiInfo = true
                isLoadingSavedNetworks = true
            }
        }
        defer {
            Task { @MainActor in
                isLoadingWiFiInfo = false
                isLoadingSavedNetworks = false
            }
        }

        guard isWiFiDeviceReachable else { return }
        do {
            let snapshot = try await WLEDSavedNetworkService.shared.loadSnapshot(for: activeDevice)
            await MainActor.run {
                savedNetworkSnapshot = snapshot
                currentWiFiInfo = WiFiInfo(
                    ssid: snapshot.connectedSSID ?? "Unknown",
                    signalStrength: snapshot.signalStrength ?? -100,
                    channel: 0,
                    security: "Unknown",
                    ipAddress: activeDevice.ipAddress,
                    macAddress: activeDevice.id,
                    bssid: snapshot.connectedBSSID,
                    firmwareVersion: snapshot.firmwareVersion
                )
            }
        } catch {
            await MainActor.run {
                savedNetworkMessage = "Could not load the device's saved networks."
                savedNetworkMessageIsError = true
            }
        }
    }

    private func presentAddNetworkFlow() {
        showManualNetworkEntry = false
        addNetworkUsesManualEntry = false
        isScanningAddNetworks = false
        addNetworkScanError = nil
        addNetworkSaveError = nil
        addNetworkSelection = nil
        showAllAddNetworkScanResults = false
        replacementSlot = nil
        manualNetworkDraft.clearSensitiveValues()
        manualNetworkDraft = WLEDSavedNetworkDraft()
        addNetworkScanRequestID = UUID()
        showAddNetworkFlow = true
    }

    private func resetAddNetworkFlow() {
        addNetworkSelection = nil
        showAllAddNetworkScanResults = false
        addNetworkUsesManualEntry = false
        isScanningAddNetworks = false
        addNetworkScanError = nil
        addNetworkSaveError = nil
        replacementSlot = nil
        manualNetworkDraft.clearSensitiveValues()
        manualNetworkDraft = WLEDSavedNetworkDraft()
    }

    private func scanForAddNetwork() async {
        await MainActor.run {
            isScanningAddNetworks = true
            addNetworkScanError = nil
            showAllAddNetworkScanResults = false
        }

        do {
            let networks = try await WLEDWiFiService.shared.scanForNetworks(device: activeDevice)
            try Task.checkCancellation()
            await MainActor.run {
                if !networks.isEmpty {
                    availableNetworks = networks
                } else if availableNetworks.isEmpty {
                    addNetworkScanError = "The network list is still loading. Tap refresh to try again."
                } else {
                    addNetworkScanError = "The latest search did not finish. Showing the previous results."
                }
                isScanningAddNetworks = false
            }
            await loadSavedNetworkSnapshot(showLoading: false)
        } catch is CancellationError {
            await MainActor.run {
                isScanningAddNetworks = false
            }
        } catch {
            await MainActor.run {
                isScanningAddNetworks = false
                addNetworkScanError = "The device could not search for nearby networks."
            }
        }
    }

    private func addNetworkStatus(for network: WiFiNetwork) -> String? {
        if savedNetworkSnapshot?.connectedSSID?.caseInsensitiveCompare(network.ssid) == .orderedSame {
            return "Connected"
        }
        if savedNetworkSnapshot?.networks.contains(where: {
            $0.ssid.caseInsensitiveCompare(network.ssid) == .orderedSame
        }) == true {
            return "Saved"
        }
        return nil
    }

    private func isOpenNetwork(_ network: WiFiNetwork) -> Bool {
        network.security
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Open") == .orderedSame
    }

    private func isUnknownWiFiValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("unknown") == .orderedSame
    }

    private func beginEditingSavedNetwork(_ network: WLEDSavedNetwork) {
        if showAddNetworkFlow {
            showAddNetworkFlow = false
            resetAddNetworkFlow()
        }
        manualNetworkDraft = WLEDSavedNetworkDraft(
            ssid: network.ssid,
            password: "",
            isOpenNetwork: !network.hasPassword
        )
        replacementSlot = nil
        showManualNetworkEntry = true
    }

    private func performSavedNetworkAction(_ action: SavedWiFiAction, draft: WLEDSavedNetworkDraft) {
        guard draft.isValid, !isMutatingSavedNetworks else { return }
        if requiresReplacement(for: draft.normalizedSSID), replacementSlot == nil {
            savedNetworkMessage = "Choose a saved network to replace."
            savedNetworkMessageIsError = true
            return
        }

        switch action {
        case .saveOnly:
            saveAlternateNetwork(draft)
        case .changeNow:
            let network = WiFiNetwork(
                ssid: draft.normalizedSSID,
                signalStrength: -100,
                security: draft.isOpenNetwork ? "Open" : "Secured",
                channel: 0,
                bssid: nil
            )
            changeCurrentNetwork(to: network, password: draft.isOpenNetwork ? nil : draft.password)
        }
    }

    private func saveAlternateNetwork(_ draft: WLEDSavedNetworkDraft) {
        isMutatingSavedNetworks = true
        savedNetworkMessage = nil
        savedNetworkMessageIsError = false
        addNetworkSaveError = nil
        let slotToReplace = replacementSlot

        Task {
            defer {
                Task { @MainActor in
                    isMutatingSavedNetworks = false
                    manualNetworkDraft.clearSensitiveValues()
                }
            }
            do {
                let result = try await WLEDSavedNetworkService.shared.save(
                    draft,
                    for: activeDevice,
                    replacingSlot: slotToReplace,
                    restartAfterSave: false
                )
                if result == .requiresRediscovery {
                    try await waitForSavedNetworkRediscovery()
                }
                await loadSavedNetworkSnapshot(showLoading: false)
                await MainActor.run {
                    savedNetworkMessage = "\(draft.normalizedSSID) is saved. It will be tested when the device can reach it."
                    savedNetworkMessageIsError = false
                    replacementSlot = nil
                    showManualNetworkEntry = false
                    showAddNetworkFlow = false
                }
            } catch {
                await MainActor.run {
                    if showAddNetworkFlow {
                        addNetworkSaveError = error.localizedDescription
                    } else {
                        savedNetworkMessage = error.localizedDescription
                        savedNetworkMessageIsError = true
                    }
                }
            }
        }
    }

    private func removeSavedNetwork(_ network: WLEDSavedNetwork) {
        guard !isMutatingSavedNetworks else { return }
        isMutatingSavedNetworks = true
        savedNetworkMessage = nil

        Task {
            defer { Task { @MainActor in isMutatingSavedNetworks = false } }
            do {
                let result = try await WLEDSavedNetworkService.shared.remove(network, from: activeDevice)
                if result == .requiresRediscovery {
                    try await waitForSavedNetworkRediscovery()
                }
                await loadSavedNetworkSnapshot(showLoading: false)
                await MainActor.run {
                    savedNetworkMessage = "\(network.ssid) was removed."
                    savedNetworkMessageIsError = false
                }
            } catch {
                await MainActor.run {
                    savedNetworkMessage = error.localizedDescription
                    savedNetworkMessageIsError = true
                }
            }
        }
    }

    private func waitForSavedNetworkRediscovery(timeout: TimeInterval = 35) async throws {
        viewModel.startPassiveDiscovery()
        viewModel.wledService.startDiscovery()
        let expectedID = WLEDDeviceIdentity.canonicalID(for: activeDevice.id)
        let deadline = Date().addingTimeInterval(timeout)

        while !Task.isCancelled && Date() < deadline {
            if let candidate = viewModel.devices.first(where: {
                WLEDDeviceIdentity.canonicalID(for: $0.id) == expectedID && ($0.isOnline || viewModel.isDeviceOnline($0))
            }), (try? await WLEDSavedNetworkService.shared.loadSnapshot(for: candidate)) != nil {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw WiFiError.networkError("The device is still reconnecting. Keep it powered on and refresh in a moment.")
    }

    @MainActor
    private func commitDeviceRename() async {
        guard !isCommittingDeviceRename else { return }

        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            editingName = activeDevice.name
            return
        }

        guard trimmed != activeDevice.name else {
            editingName = activeDevice.name
            return
        }

        isCommittingDeviceRename = true
        defer { isCommittingDeviceRename = false }

        await viewModel.renameDevice(activeDevice, to: trimmed)

        if viewModel.currentError == nil {
            editingName = trimmed
            showPostRenameWiFiPrompt = true
            return
        }
    }

    private func changeCurrentNetwork(to network: WiFiNetwork, password newPassword: String?) {
        guard !isConnecting else { return }
        isConnecting = true
        isMutatingSavedNetworks = true
        savedNetworkMessage = nil
        savedNetworkMessageIsError = false
        addNetworkSaveError = nil
        let slotToReplace = replacementSlot

        Task {
            let outcome = await WLEDSafeWiFiChangeService.shared.changeNetwork(
                device: activeDevice,
                network: network,
                password: newPassword,
                viewModel: viewModel,
                replacingSlot: slotToReplace
            )

            await MainActor.run {
                isConnecting = false
                isMutatingSavedNetworks = false
                manualNetworkDraft.clearSensitiveValues()
            }

            guard case .verified = outcome else {
                if outcome == .stayedOnPreviousNetwork || outcome == .returnedButCouldNotVerify {
                    await loadSavedNetworkSnapshot(showLoading: false)
                }
                await MainActor.run {
                    let message = outcome.failureMessage ?? "The new Wi-Fi could not be verified."
                    if showAddNetworkFlow {
                        addNetworkSaveError = message
                    } else {
                        savedNetworkMessage = message
                        savedNetworkMessageIsError = true
                    }
                }
                return
            }

            await loadSavedNetworkSnapshot(showLoading: false)
            await MainActor.run {
                showManualNetworkEntry = false
                showAddNetworkFlow = false
                addNetworkSelection = nil
                addNetworkSaveError = nil
                replacementSlot = nil
                savedNetworkMessage = "Connected to \(network.ssid)."
                savedNetworkMessageIsError = false
            }
        }
    }

    private func refreshWiFiStatusAfterNetworkChange() async {
        let refreshDelays: [UInt64] = [
            2_000_000_000,
            6_000_000_000,
            12_000_000_000
        ]

        for delay in refreshDelays {
            try? await Task.sleep(nanoseconds: delay)
            await loadSavedNetworkSnapshot(showLoading: false)
        }
    }
}

// MARK: - Supporting Views

enum SettingsCardGlassStyle {
    case standard
    case clear
    case detailControl
    case miniDeviceCard
}

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content
    let headerContent: (() -> AnyView)?
    let glassStyle: SettingsCardGlassStyle
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var cornerRadius: CGFloat {
        glassStyle == .miniDeviceCard ? DeviceDetailPresentation.folderSourceCornerRadius : 16
    }

    init(title: String, glassStyle: SettingsCardGlassStyle = .detailControl, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.headerContent = nil
        self.glassStyle = glassStyle
    }

    init(title: String, glassStyle: SettingsCardGlassStyle = .detailControl, @ViewBuilder content: () -> Content, @ViewBuilder headerContent: @escaping () -> AnyView) {
        self.title = title
        self.content = content()
        self.headerContent = headerContent
        self.glassStyle = glassStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(theme.settingsText(.primary))
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if let headerContent = headerContent {
                    headerContent()
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCardGlassBackground(
            style: glassStyle,
            cornerRadius: cornerRadius,
            colorScheme: colorScheme,
            theme: theme
        )
        .overlay(
            LinearGradient(
                colors: [
                    Color.white.opacity(cardHighlightOpacity),
                    Color.white.opacity(
                        glassStyle == .detailControl || glassStyle == .miniDeviceCard ? 0 : 0.02
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var cardHighlightOpacity: Double {
        switch glassStyle {
        case .detailControl, .miniDeviceCard:
            return 0
        case .clear:
            return colorScheme == .dark ? 0.06 : 0.08
        case .standard:
            return colorScheme == .dark ? 0.08 : 0.10
        }
    }
}

private extension View {
    @ViewBuilder
    func settingsCardGlassBackground(
        style: SettingsCardGlassStyle,
        cornerRadius: CGFloat,
        colorScheme: ColorScheme,
        theme: AppSemanticTheme
    ) -> some View {
        switch style {
        case .standard:
            background(
                GlassCardBackground(
                    cornerRadius: cornerRadius,
                    fill: AppTheme.cardFill(for: colorScheme, isActive: true),
                    outerStroke: theme.cardStrokeOuter,
                    innerStroke: theme.cardStrokeInner,
                    keyShadow: theme.cardShadowKey,
                    ambientShadow: theme.cardShadowAmbient
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(max(0, AppTheme.settingsGlassDarkTint(.card, for: colorScheme) - 0.03)))
                )
            )
        case .clear:
            background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.20), lineWidth: 1)
                )
                .appLiquidGlass(
                    role: .highContrast,
                    cornerRadius: cornerRadius,
                    highContrastDarkTintOpacity: AppTheme.settingsGlassDarkTint(.card, for: colorScheme)
                )
                .shadow(
                    color: theme.controlShadowAmbient.color,
                    radius: theme.controlShadowAmbient.radius,
                    x: theme.controlShadowAmbient.x,
                    y: theme.controlShadowAmbient.y
                )
                .shadow(
                    color: theme.controlShadowKey.color,
                    radius: theme.controlShadowKey.radius,
                    x: theme.controlShadowKey.x,
                    y: theme.controlShadowKey.y
                )
        case .detailControl:
            settingsDetailControlBackground(cornerRadius: cornerRadius)
        case .miniDeviceCard:
            background(
                FolderGlassContainerBackground(cornerRadius: cornerRadius)
            )
        }
    }
}

struct SettingsDetailControlBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return shape
            .fill(Color.white.opacity(0.12))
            .overlay(
                shape
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08),
                radius: 7,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func settingsDetailControlBackground(cornerRadius: CGFloat = 16) -> some View {
        background(SettingsDetailControlBackground(cornerRadius: cornerRadius))
    }
}

private enum SettingsAreaRisk {
    case normal
    case warning
    case danger

    var color: Color {
        switch self {
        case .normal:
            return .white
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

private struct SettingsAreaCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let status: String
    let exposure: FirmwareSettingsExposure
    let riskLevel: SettingsAreaRisk
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private let cornerRadius: CGFloat = 16

    init(
        title: String,
        subtitle: String,
        icon: String,
        status: String,
        exposure: FirmwareSettingsExposure,
        riskLevel: SettingsAreaRisk = .normal,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.status = status
        self.exposure = exposure
        self.riskLevel = riskLevel
        self.content = content()
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                SettingsDescriptionText(markdown: subtitle)

                content
            }
            .padding(.top, 12)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(riskLevel == .normal ? exposure.color : riskLevel.color)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .foregroundColor(theme.settingsText(.primary))
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 8) {
                        badge(text: exposure.rawValue, color: exposure.color)
                        badge(text: status, color: riskLevel == .normal ? .white : riskLevel.color)
                    }
                }

                Spacer(minLength: 8)
            }
        }
        .tint(theme.settingsText(.primary))
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
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    riskLevel == .normal ? Color.white.opacity(0.08) : riskLevel.color.opacity(0.5),
                    lineWidth: riskLevel == .normal ? 1 : 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(AppTypography.style(.caption2, weight: .semibold))
            .foregroundColor(color.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(color.opacity(colorScheme == .dark ? 0.14 : 0.18))
            )
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
                .foregroundColor(theme.settingsText(.secondary))
            Spacer()
            Text(value)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(theme.settingsText(.primary))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private enum FirmwareSettingsExposure: String {
    case native = "Native"
    case guided = "Guided"
    case advancedNative = "Advanced Native"
    case plannedNative = "Planned Native"
    case webFallback = "Web Fallback"

    var color: Color {
        switch self {
        case .native:
            return .green
        case .guided:
            return .cyan
        case .advancedNative:
            return .orange
        case .plannedNative:
            return .yellow
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
            title: "WiFi, IP address, update check",
            location: "Device > Status",
            exposure: .native
        ),
        WLEDFirmwareSettingsArea(
            id: "firmware-install",
            title: "Current firmware upload path",
            location: "Device > Software Update",
            exposure: .webFallback
        ),
        WLEDFirmwareSettingsArea(
            id: "native-firmware-updater",
            title: "Native upload progress and reboot recovery",
            location: "Planned before replacing WLED updater",
            exposure: .plannedNative
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
            location: "Detailed Device View + Time & Schedules",
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
            title: "8 guided timers; full WLED timer table",
            location: "Time & Schedules + WLED Time Settings",
            exposure: .advancedNative
        ),
        WLEDFirmwareSettingsArea(
            id: "timezone-solar",
            title: "Clock sync, WLED timezone index, solar reference",
            location: "Time & Schedules",
            exposure: .native
        ),
        WLEDFirmwareSettingsArea(
            id: "sync-realtime",
            title: "UDP sync, realtime, nodes, peers",
            location: "Integrations + Advanced > Diagnostics",
            exposure: .advancedNative
        ),
        WLEDFirmwareSettingsArea(
            id: "integrations",
            title: "MQTT, DMX/E1.31, Hue, Alexa, IR",
            location: "Integrations + Advanced > Protocols",
            exposure: .advancedNative
        ),
        WLEDFirmwareSettingsArea(
            id: "ddp-compiled-modules",
            title: "DDP and compiled firmware modules",
            location: "Advanced > WLED Web Settings",
            exposure: .webFallback
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
                    .foregroundColor(theme.settingsText(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(area.location)
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer(minLength: 8)

            Text(area.exposure.rawValue)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(area.exposure == .webFallback ? .white.opacity(0.88) : .black)
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
    enum Style {
        case fullGlass
        case overviewRow
    }

    let title: String
    let icon: String
    var style: Style = .fullGlass
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var foreground: Color { theme.settingsText(.primary) }
    private let cornerRadius: CGFloat = 12

    var body: some View {
        switch style {
        case .fullGlass:
            fullGlassBody
        case .overviewRow:
            overviewRowBody
        }
    }

    private var fullGlassBody: some View {
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
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        )
        .appLiquidGlass(
            role: .highContrast,
            cornerRadius: cornerRadius,
            highContrastDarkTintOpacity: AppTheme.settingsGlassDarkTint(.control, for: colorScheme)
        )
    }

    private var overviewRowBody: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(foreground.opacity(0.78))
                .frame(width: 24, height: 24)

            Text(title)
                .foregroundColor(foreground)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(AppTypography.style(.caption, weight: .bold))
                .foregroundColor(foreground.opacity(0.72))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.20), lineWidth: 1)
                )
                .appLiquidGlass(role: .control, cornerRadius: 15)
        }
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    enum Style {
        case fullGlass
        case overviewRow
    }

    let isSyncing: Bool
    var objectName: String = "Lamp"
    var style: Style = .fullGlass
    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color { AppTheme.controlForeground(for: colorScheme, isActive: true) }

    var body: some View {
        switch style {
        case .fullGlass:
            fullGlassBody
        case .overviewRow:
            overviewRowBody
        }
    }

    private var fullGlassBody: some View {
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

            Text("Sync \(objectName) Clock from Phone")
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

    private var overviewRowBody: some View {
        HStack(spacing: 12) {
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.78)
                    .tint(foreground)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(foreground.opacity(0.78))
                    .frame(width: 24, height: 24)
            }

            Text("Sync \(objectName) Clock from Phone")
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.clockwise")
                .font(AppTypography.style(.caption, weight: .bold))
                .foregroundColor(foreground.opacity(0.72))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.20), lineWidth: 1)
                )
                .appLiquidGlass(role: .control, cornerRadius: 15)
        }
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .foregroundColor(theme.settingsText(.secondary))

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

struct AdvancedNetworkMDNSField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("mDNS address (leave empty for no mDNS)")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(theme.settingsText(.secondary))

            HStack(spacing: 6) {
                Text("http://")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .foregroundColor(theme.settingsText(.primary))

                TextField("device-name", text: $text)
                    .settingsTextFieldChrome(theme: theme)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text(".local")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .foregroundColor(theme.settingsText(.primary))
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
                SettingsDescriptionText(
                    markdown: subtitle,
                    tone: isWarning ? .warning : .secondary
                )

                content
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(isWarning ? .orange : theme.settingsText(.secondary))
                    .frame(width: 22)
                Text(title)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(theme.settingsText(.primary))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
        }
        .tint(theme.settingsText(.primary))
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
            .foregroundColor(theme.settingsText(.primary))
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
            .settingsForegroundStyle(.primary)
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
                .foregroundColor(theme.settingsText(.secondary))

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
                .foregroundColor(theme.settingsText(.primary))
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
                .foregroundColor(theme.settingsText(.primary))
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(theme.settingsText(.primary))
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
                .foregroundColor(theme.settingsText(.secondary))

            HStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    Button(action: { toggle(index) }) {
                        Text("\(index + 1)")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(isEnabled(index) ? .black : theme.settingsText(.primary))
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
                    .settingsForegroundStyle(.primary)
                if let message = status.message, !message.isEmpty {
                    Text(message)
                        .font(AppTypography.style(.caption2))
                        .settingsForegroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    Text(status.resolvedVerificationSource.displayName)
                    if status.resolvedVerificationSource != .notVerified {
                        Text("·")
                        Text(statusTimestampLabel)
                    }
                }
                .font(AppTypography.style(.caption2, weight: .medium))
                .settingsForegroundStyle(.secondary)
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
        case .inProgress: return "clock.arrow.circlepath"
        case .needsSync: return "arrow.triangle.2.circlepath.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .requiresBridge: return "point.3.connected.trianglepath.dotted"
        case .unsupported: return "minus.circle.fill"
        case .notSetUp: return "circle"
        }
    }

    private var statusTimestampLabel: String {
        if Calendar.current.isDateInToday(status.updatedAt) {
            return "Checked \(status.updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Checked \(status.updatedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var statusColor: Color {
        switch status.state {
        case .enabled: return .green
        case .inProgress: return .cyan
        case .needsSync: return .yellow
        case .conflict, .failed: return .orange
        case .requiresBridge: return .blue
        case .unsupported: return .gray
        case .notSetUp: return .white.opacity(0.62)
        }
    }
}

fileprivate struct HomeAssistantChecklistRow: View {
    let title: String
    let detail: String
    @Binding var isComplete: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isComplete.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(isComplete ? .green : theme.settingsText(.secondary))
                    .frame(width: 22, height: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(theme.settingsText(.primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(detail)
                        .font(AppTypography.style(.caption))
                        .foregroundColor(theme.settingsText(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isComplete ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isComplete ? Color.green.opacity(0.32) : theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct HomeAssistantInstructionRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(AppTypography.style(.caption, weight: .bold))
                .settingsForegroundStyle(.primary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.18)))
                .padding(.top, 1)

            Text(text)
                .font(AppTypography.style(.caption))
                .settingsForegroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AlexaDiscoveryInstructionsView: View {
    var deviceName: String? = nil

    private var trimmedDeviceName: String? {
        guard let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            instructionRow(icon: "checkmark.circle.fill", title: "Alexa setup saved")
            instructionRow(icon: "iphone", title: "Open the Alexa app")
            instructionRow(icon: "magnifyingglass.circle.fill", title: "Run Discover Devices")
            if let trimmedDeviceName {
                instructionRow(icon: "lightbulb", title: "Test: Alexa, turn on \(trimmedDeviceName)")
            }
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
                .settingsForegroundStyle(.primary)
                .frame(width: 22, height: 22)
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .settingsForegroundStyle(.primary)
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
                .foregroundColor(theme.settingsText(.primary))
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
                .foregroundColor(theme.settingsText(.primary))
                .onChange(of: udpSend) { _, v in
                    guard !suppressUpdates else { return }
                    Task { await viewModel.setUDPSync(device, send: v, recv: nil) }
                }
            Spacer()
            Toggle("Receive", isOn: $udpRecv)
                .tint(theme.accent)
                .foregroundColor(theme.settingsText(.primary))
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
                    .foregroundColor(theme.settingsText(.primary))
                Spacer()
                Text("\(Int(value))")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.settingsText(.secondary))
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
                .foregroundColor(theme.settingsText(.primary))
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

private enum TimerEditorFeedback: Equatable {
    case verified
    case verificationNeeded
    case notSaved

    var message: String {
        switch self {
        case .verified:
            return "Saved and verified on the lamp."
        case .verificationNeeded:
            return "The write result is uncertain. Refresh after the lamp reconnects."
        case .notSaved:
            return "The lamp did not confirm this timer change."
        }
    }

    var isSuccess: Bool {
        self == .verified
    }
}

private struct TimerSlotEditorCard: View {
    @Binding var draft: NativeTimerDraft
    let isSaving: Bool
    let feedback: TimerEditorFeedback?
    let onSave: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var primaryButtonForeground: Color { AppTheme.controlForeground(for: colorScheme, isActive: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timer \(draft.id + 1)")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(theme.settingsText(.primary))
                Spacer()
                Text(draft.timeLabel)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.settingsText(.secondary))
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
                    .foregroundColor(theme.settingsText(.secondary))
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
                                        : theme.settingsText(.secondary)
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

            if let feedback {
                Label(
                    feedback.message,
                    systemImage: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(feedback.isSuccess ? .green : .orange)
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
                .foregroundColor(theme.settingsText(.secondary))
            HStack(spacing: 8) {
                Button {
                    value = max(range.lowerBound, value - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(theme.settingsText(.primary))
                }
                .buttonStyle(.plain)

                Text("\(value)")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.settingsText(.primary))
                    .frame(minWidth: 28)

                Button {
                    value = min(range.upperBound, value + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(theme.settingsText(.primary))
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
