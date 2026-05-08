import CoreLocation
import SwiftUI
import UIKit

struct ProductSetupFlowView: View {
    private enum SetupStep: Int, CaseIterable {
        case product = 0
        case ledPreferences = 1
        case nameAndWiFi = 2
        case smartHome = 3
        case automation = 4

        var title: String {
            switch self {
            case .product:
                return "Select Product"
            case .ledPreferences:
                return "LED Preferences"
            case .nameAndWiFi:
                return "Name & Wi-Fi"
            case .smartHome:
                return "Smart Home"
            case .automation:
                return "First Automation"
            }
        }

        var subtitle: String {
            switch self {
            case .product:
                return "Choose your Aesdetic product to start setup."
            case .ledPreferences:
                return "We'll apply safe recommended LED settings."
            case .nameAndWiFi:
                return "Name your device and confirm network before continuing."
            case .smartHome:
                return "Connect Alexa now or set up smart home later."
            case .automation:
                return "Set a wake automation from sunrise to sky blue."
            }
        }
    }

    private enum MotionDirection {
        case forward
        case backward
    }

    private enum WakeTriggerMode: String, CaseIterable {
        case sunrise
        case specificTime

        var displayName: String {
            switch self {
            case .sunrise:
                return "Wake With Sunrise"
            case .specificTime:
                return "Wake At Specific Time"
            }
        }
    }

    private static let defaultSunriseStartGradient = LEDGradient(stops: [
        GradientStop(position: 0.0, hexColor: "#FF3232"),
        GradientStop(position: 1.0, hexColor: "#FFC92E")
    ])

    private static let defaultSunriseEndGradient = LEDGradient(stops: [
        GradientStop(position: 0.0, hexColor: "#8EB8FF"),
        GradientStop(position: 1.0, hexColor: "#FFFFFF")
    ])

    private struct LEDRecommendation {
        let stripType: Int
        let gpioPin: Int
        let ledCount: Int
        let skipFirstLEDs: Int
        let maxCurrentPerLED: Int
        let autoWhiteMode: Int
        let maxTotalCurrent: Int
        let enableABL: Bool
        let initialBrightness: Int
    }

    private struct ProductOption: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let imageName: String
        let productType: ProductType
        let isCustom: Bool
        let recommendation: LEDRecommendation?

        static let skyLantern = ProductOption(
            id: "sky_lantern",
            title: "Sky Lantern",
            subtitle: "Sunrise lamp tuned for soft dawn transitions.",
            imageName: "product_image",
            productType: .sunriseLamp,
            isCustom: false,
            recommendation: LEDRecommendation(
                stripType: 30,
                gpioPin: 16,
                ledCount: 120,
                skipFirstLEDs: 5,
                maxCurrentPerLED: 55,
                autoWhiteMode: 2,
                maxTotalCurrent: 3800,
                enableABL: true,
                initialBrightness: 170
            )
        )

        static let bloom = ProductOption(
            id: "bloom",
            title: "Bloom",
            subtitle: "Sunrise lamp profile with slightly softer brightness.",
            imageName: "product_image",
            productType: .sunriseLamp,
            isCustom: false,
            recommendation: LEDRecommendation(
                stripType: 30,
                gpioPin: 16,
                ledCount: 120,
                skipFirstLEDs: 5,
                maxCurrentPerLED: 55,
                autoWhiteMode: 2,
                maxTotalCurrent: 3200,
                enableABL: true,
                initialBrightness: 160
            )
        )

        static let custom = ProductOption(
            id: "custom_wled",
            title: "Custom WLED Device",
            subtitle: "Keep default WLED behavior and tune manually.",
            imageName: "product_image",
            productType: .generic,
            isCustom: true,
            recommendation: nil
        )

        static let all: [ProductOption] = [.skyLantern, .bloom, .custom]
        static let aesdeticOnly: [ProductOption] = [.skyLantern, .bloom]
    }

    enum SetupError: LocalizedError {
        case locationRequired
        case invalidDeviceName
        case noWeekdaysSelected
        case invalidOnDeviceSchedule(String)

        var errorDescription: String? {
            switch self {
            case .locationRequired:
                return "Location access is required for sunrise-based wake automation. Switch to specific time or enable location access."
            case .invalidDeviceName:
                return "Please enter a valid device name."
            case .noWeekdaysSelected:
                return "Select at least one day for your wake automation."
            case .invalidOnDeviceSchedule(let message):
                return message
            }
        }
    }

    let device: WLEDDevice
    let onClose: (() -> Void)?
    let allowsManualClose: Bool
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @ObservedObject private var smartHomeStore = SmartHomeIntegrationStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: SetupStep = .product
    @State private var transitionDirection: MotionDirection = .forward

    @State private var selectedProductId: String = ProductOption.skyLantern.id
    @State private var deviceName: String
    @State private var hasConfirmedWiFi: Bool = false

    @State private var currentWiFiInfo: WiFiInfo?
    @State private var isLoadingWiFiInfo: Bool = false
    @State private var availableNetworks: [WiFiNetwork] = []
    @State private var isScanningWiFi: Bool = false
    @State private var selectedNetwork: WiFiNetwork?
    @State private var wifiPassword: String = ""
    @State private var isConnectingWiFi: Bool = false
    @State private var wifiConnectionStatus: WiFiSetupView.ConnectionStatus = .idle
    @State private var wifiScanTask: Task<Void, Never>?
    @State private var selectedRoomLocation: DeviceLocation = .bedroom
    @State private var customRoomName: String = ""
    @State private var setupAlexaEnabled: Bool = false
    @State private var setupAlexaName: String = ""
    @State private var isSavingSetupSmartHome: Bool = false
    @State private var setupSmartHomeMessage: String?
    @State private var setupSmartHomeMessageIsError: Bool = false
    @State private var showSetupAlexaDiscoveryInstructions: Bool = false

    @State private var wakeTriggerMode: WakeTriggerMode = .sunrise
    @State private var wakeTime: Date
    @State private var sunriseOffsetMinutes: Int = -15
    @State private var wakeWeekdays: [Bool] = WeekdayMask.allDaysSunFirst
    @State private var weekdayDragSelectionMode: Bool? = nil

    @State private var transitionStartGradient: LEDGradient = ProductSetupFlowView.defaultSunriseStartGradient
    @State private var transitionEndGradient: LEDGradient = ProductSetupFlowView.defaultSunriseEndGradient
    @State private var transitionStartBrightness: Double = 30
    @State private var transitionEndBrightness: Double = 190
    @State private var transitionDurationSeconds: Double = 600
    @State private var transitionStartTemperature: Double?
    @State private var transitionStartWhiteLevel: Double?
    @State private var transitionEndTemperature: Double?
    @State private var transitionEndWhiteLevel: Double?

    @State private var isApplying: Bool = false
    @State private var localError: String?
    @State private var showLocationSettingsAlert: Bool = false

    init(
        device: WLEDDevice,
        onClose: (() -> Void)? = nil,
        allowsManualClose: Bool = true
    ) {
        self.device = device
        self.onClose = onClose
        self.allowsManualClose = allowsManualClose
        _deviceName = State(initialValue: device.name)
        _wakeTime = State(initialValue: Self.defaultWakeTime())
    }

    private static func defaultWakeTime() -> Date {
        var components = DateComponents()
        components.hour = 7
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private var activeDevice: WLEDDevice {
        if let matchedById = viewModel.devices.first(where: { $0.id == device.id }) {
            return matchedById
        }
        if let matchedByIP = viewModel.devices.first(where: { $0.ipAddress == device.ipAddress }) {
            return matchedByIP
        }
        if device.id.hasPrefix("ip:") {
            let normalizedName = device.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalizedName.isEmpty {
                let nameMatches = viewModel.devices.filter {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
                }
                if nameMatches.count == 1, let match = nameMatches.first {
                    return match
                }
            }

            let pending = viewModel.devices.filter { $0.setupState == .pendingSelection }
            if pending.count == 1, let match = pending.first {
                return match
            }
        }
        return device
    }

    private var selectedProduct: ProductOption {
        ProductOption.all.first(where: { $0.id == selectedProductId }) ?? .skyLantern
    }

    private var isCustomProduct: Bool {
        selectedProduct.isCustom
    }

    private var activeSetupSteps: [SetupStep] {
        if isCustomProduct {
            return [.product, .ledPreferences, .nameAndWiFi, .smartHome]
        }
        return SetupStep.allCases
    }

    private var finalStep: SetupStep {
        activeSetupSteps.last ?? .automation
    }

    private var currentStepOrdinal: Int {
        (activeSetupSteps.firstIndex(of: step) ?? 0) + 1
    }

    private var canGoNext: Bool {
        switch step {
        case .product:
            return true
        case .ledPreferences:
            return true
        case .nameAndWiFi:
            return !trimmedDeviceName.isEmpty && hasConfirmedWiFi && setupLocationValidationError == nil
        case .smartHome:
            return !isSavingSetupSmartHome && (!setupAlexaEnabled || !trimmedSetupAlexaName.isEmpty)
        case .automation:
            return !isApplying && wakeWeekdays.contains(true)
        }
    }

    private var trimmedDeviceName: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCustomRoomName: String {
        customRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSetupAlexaName: String {
        setupAlexaName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetSmartHomeSetupSaveState() {
        guard !isSavingSetupSmartHome else { return }
        showSetupAlexaDiscoveryInstructions = false
        setupSmartHomeMessage = nil
        setupSmartHomeMessageIsError = false
    }

    private var setupLocationValidationError: String? {
        if case .custom = selectedRoomLocation, trimmedCustomRoomName.isEmpty {
            return "Enter a name for Other location."
        }
        return nil
    }

    private var setupLocationOptions: [DeviceLocation] {
        [.bedroom, .livingRoom, .kitchen, .office, .hallway, .bathroom, .outdoor, .custom("")]
    }

    private var stepProgressValue: Double {
        Double(currentStepOrdinal)
    }

    private var totalSteps: Double {
        Double(activeSetupSteps.count)
    }

    private var contentTransition: AnyTransition {
        switch transitionDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private var theme: AppSemanticTheme {
        AppTheme.tokens(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                VStack(spacing: 16) {
                    headerSection

                    ZStack {
                        stepContent
                            .id(step.rawValue)
                            .transition(contentTransition)
                    }
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: step)

                    footerSection
                }
                .padding(16)
                .appLiquidGlass(role: .highContrast, cornerRadius: 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Product Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsManualClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            closeFlow()
                        }
                        .font(AppTypography.style(.subheadline, weight: .medium))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .presentationBackground(.ultraThinMaterial)
            .alert("Location Access Needed", isPresented: $showLocationSettingsAlert) {
                Button("Not Now", role: .cancel) {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } message: {
                Text("Enable location to use sunrise-based wake automation, or switch to specific time.")
            }
            .task {
                initializeSelectionIfNeeded()
                await loadCurrentWiFiInfo()
                scanForWiFiNetworks()
            }
            .onChange(of: step) { _, newStep in
                guard newStep == .nameAndWiFi else { return }
                Task {
                    await loadCurrentWiFiInfo()
                    scanForWiFiNetworks()
                }
            }
            .onChange(of: selectedProductId) { _, newValue in
                guard newValue == ProductOption.custom.id, step == .automation else { return }
                moveToStep(SetupStep.nameAndWiFi.rawValue)
            }
            .onChange(of: setupAlexaEnabled) { _, _ in
                resetSmartHomeSetupSaveState()
            }
            .onChange(of: setupAlexaName) { _, _ in
                resetSmartHomeSetupSaveState()
            }
            .onAppear {
                viewModel.isMandatorySetupFlowActive = true
            }
            .onDisappear {
                wifiScanTask?.cancel()
                viewModel.isMandatorySetupFlowActive = false
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(AppTypography.display(size: 22, weight: .semibold, relativeTo: .title3))
                        .foregroundColor(theme.textPrimary)
                    Text(step.subtitle)
                        .font(AppTypography.style(.subheadline))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 10)
                Text("Step \(currentStepOrdinal) of \(activeSetupSteps.count)")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(theme.surfaceMuted.opacity(0.92))
                            .overlay(
                                Capsule()
                                    .stroke(theme.divider.opacity(0.85), lineWidth: 1)
                            )
                    )
            }
            ProgressView(value: stepProgressValue, total: totalSteps)
                .tint(theme.accent)
        }
        .padding(14)
        .appLiquidGlass(role: .panel, cornerRadius: 18)
    }

    @ViewBuilder
    private var stepContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                switch step {
                case .product:
                    productStep
                case .ledPreferences:
                    ledPreferencesStep
                case .nameAndWiFi:
                    nameAndWiFiStep
                case .smartHome:
                    smartHomeStep
                case .automation:
                    automationStep
                }

                if let localError {
                    Text(localError)
                        .font(AppTypography.style(.caption))
                        .foregroundStyle(theme.status.negative)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(4)
        }
    }

    private var productStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ProductOption.aesdeticOnly) { option in
                productCard(option)
            }

            compactCustomCard
        }
    }

    private func productCard(_ option: ProductOption) -> some View {
        Button {
            selectedProductId = option.id
        } label: {
            HStack(spacing: 12) {
                Image(option.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(option.title)
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(option.subtitle)
                        .font(AppTypography.style(.subheadline))
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: selectedProductId == option.id ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundStyle(selectedProductId == option.id ? theme.status.positive : theme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .appLiquidGlass(role: selectedProductId == option.id ? .highContrast : .panel, cornerRadius: 16)
    }

    private var compactCustomCard: some View {
        Button {
            selectedProductId = ProductOption.custom.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ProductOption.custom.title)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(ProductOption.custom.subtitle)
                        .font(AppTypography.style(.caption))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: selectedProductId == ProductOption.custom.id ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundStyle(selectedProductId == ProductOption.custom.id ? theme.status.positive : theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .appLiquidGlass(role: .panel, cornerRadius: 14)
    }

    private var ledPreferencesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recommendation = selectedProduct.recommendation {
                infoPanel(title: "Recommended Configuration") {
                    VStack(spacing: 10) {
                        infoRow(label: "Product", value: selectedProduct.title)
                        infoRow(label: "Strip Type", value: "SK6812/WS2814 RGBW")
                        infoRow(label: "Data GPIO", value: "\(recommendation.gpioPin)")
                        infoRow(label: "Length", value: "\(recommendation.ledCount) LEDs")
                        infoRow(label: "Skip First LEDs", value: "\(recommendation.skipFirstLEDs)")
                        infoRow(label: "Current / LED", value: "\(recommendation.maxCurrentPerLED) mA")
                        infoRow(label: "Auto White", value: autoWhiteDisplayName(recommendation.autoWhiteMode))
                        infoRow(label: "Max Current", value: "\(recommendation.maxTotalCurrent) mA")
                        infoRow(label: "Auto Brightness Limiter", value: recommendation.enableABL ? "Enabled" : "Disabled")
                        infoRow(label: "Initial Brightness", value: "\(recommendation.initialBrightness)")
                    }
                }

                Text("These settings are applied using WLED's native `/json/cfg` LED configuration path without touching Wi-Fi keys.")
                    .font(AppTypography.style(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                infoPanel(title: "Custom WLED") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your current LED/controller settings will be preserved. Open native WLED LED settings if you want to tune strip type, count, GPIO, and power manually.")
                            .font(AppTypography.style(.subheadline))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            openCustomLEDSettingsInWebUI()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                Text("Open WLED LED Settings")
                            }
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                            )
                        }
                        .buttonStyle(.plain)

                        Text("Custom setup ends after Smart Home. No automation is created.")
                            .font(AppTypography.style(.caption))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var nameAndWiFiStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoPanel(title: "Device Name") {
                TextField("Device Name", text: $deviceName)
                    .textFieldStyle(.plain)
                    .font(AppTypography.style(.title3, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.surfaceMuted)
                    )
            }

            infoPanel(title: "Device Location") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose where this lamp is placed in your home.")
                        .font(AppTypography.style(.caption))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(setupLocationOptions, id: \.self) { location in
                            roomLocationChip(location: location)
                        }
                    }

                    if case .custom = selectedRoomLocation {
                        TextField("Enter location (e.g., Nursery)", text: $customRoomName)
                            .textFieldStyle(.plain)
                            .font(AppTypography.style(.subheadline, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.surfaceMuted)
                            )
                    }

                    if let setupLocationValidationError {
                        Text(setupLocationValidationError)
                            .font(AppTypography.style(.caption))
                            .foregroundStyle(theme.status.negative)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Location helps organize your devices in the app.")
                            .font(AppTypography.style(.caption))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            infoPanel(title: "Wi-Fi Confirmation") {
                VStack(alignment: .leading, spacing: 10) {
                    if isLoadingWiFiInfo {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Loading current Wi-Fi…")
                                .font(AppTypography.style(.subheadline))
                                .foregroundStyle(theme.textSecondary)
                        }
                    } else if let wifi = currentWiFiInfo {
                        infoRow(label: "Current SSID", value: wifi.ssid)
                        infoRow(label: "Signal", value: "\(wifi.signalStrength) dBm")
                        infoRow(label: "Security", value: wifi.security)
                    } else {
                        Text("Unable to read current SSID. You can still open Wi-Fi settings to verify.")
                            .font(AppTypography.style(.subheadline))
                            .foregroundStyle(theme.textSecondary)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await loadCurrentWiFiInfo()
                            }
                            scanForWiFiNetworks()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Scan Networks")
                            }
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isScanningWiFi || isConnectingWiFi)

                        if isScanningWiFi {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                    }

                    if !availableNetworks.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(availableNetworks, id: \.ssid) { network in
                                WiFiNetworkRow(
                                    network: network,
                                    isSelected: selectedNetwork?.ssid == network.ssid,
                                    onSelect: { selectWiFiNetwork(network) }
                                )

                                if selectedNetwork?.ssid == network.ssid {
                                    VStack(spacing: 10) {
                                        Divider()
                                            .background(Color.white.opacity(0.2))

                                        if network.security != "Open" {
                                            SecureField("Enter Wi-Fi password", text: $wifiPassword)
                                                .textFieldStyle(.plain)
                                                .font(AppTypography.style(.subheadline))
                                                .foregroundColor(theme.textPrimary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(theme.surfaceMuted)
                                                )
                                        } else {
                                            Text("Open network: no password needed.")
                                                .font(AppTypography.style(.caption))
                                                .foregroundStyle(theme.textSecondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        Button {
                                            connectToSelectedWiFiNetwork()
                                        } label: {
                                            HStack(spacing: 8) {
                                                if isConnectingWiFi {
                                                    ProgressView()
                                                        .scaleEffect(0.8)
                                                        .tint(.black)
                                                }
                                                Text(isConnectingWiFi ? "Connecting..." : "Connect to \(network.ssid)")
                                            }
                                            .font(AppTypography.style(.subheadline, weight: .semibold))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(Color.white)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(isConnectingWiFi || (network.security != "Open" && wifiPassword.isEmpty))

                                        wifiConnectionStatusView
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    } else if !isScanningWiFi {
                        Text("No networks listed yet. Tap Scan Networks to find available Wi-Fi.")
                            .font(AppTypography.style(.caption))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        hasConfirmedWiFi.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: hasConfirmedWiFi ? "checkmark.circle.fill" : "circle")
                            Text("I confirm this device is on the correct Wi-Fi")
                                .font(AppTypography.style(.subheadline, weight: .medium))
                        }
                        .foregroundStyle(hasConfirmedWiFi ? theme.status.positive : theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var smartHomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoPanel(title: "Alexa") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Alexa Control", isOn: $setupAlexaEnabled)
                        .settingsToggleStyle()

                    if setupAlexaEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Alexa Name")
                                .font(AppTypography.style(.caption, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                            TextField("Bedroom Lights", text: $setupAlexaName)
                                .textFieldStyle(.plain)
                                .font(AppTypography.style(.subheadline, weight: .semibold))
                                .foregroundColor(theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(theme.surfaceMuted)
                                )
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            setupBullet("Uses WLED native Alexa support")
                            setupBullet("Auto-fills up to 9 eligible favorites")
                            setupBullet("You will finish in the Alexa app with Discover Devices")
                        }
                    } else {
                        Text("You can set up Alexa later from Device Settings > Integrations.")
                            .font(AppTypography.style(.subheadline))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isSavingSetupSmartHome {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("Saving Alexa setup...")
                                .font(AppTypography.style(.caption))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }

                    if let setupSmartHomeMessage {
                        Text(setupSmartHomeMessage)
                            .font(AppTypography.style(.caption))
                            .foregroundStyle(setupSmartHomeMessageIsError ? theme.status.negative : theme.status.positive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showSetupAlexaDiscoveryInstructions {
                        AlexaDiscoveryInstructionsView()
                    }
                }
            }

            infoPanel(title: "Coming Next") {
                VStack(spacing: 10) {
                    setupIntegrationStatusRow(kind: .homeAssistant)
                    setupIntegrationStatusRow(kind: .appleHome)
                    setupIntegrationStatusRow(kind: .googleHome)
                    setupIntegrationStatusRow(kind: .mqtt)
                }
            }
        }
    }

    private func setupBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundStyle(theme.status.positive)
                .padding(.top, 1)
            Text(text)
                .font(AppTypography.style(.caption))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setupIntegrationStatusRow(kind: SmartHomeIntegrationKind) -> some View {
        let status = smartHomeStore.status(for: kind, deviceId: activeDevice.id)
        return HStack(spacing: 10) {
            Image(systemName: kind.iconName)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.displayName)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(status.state.displayName)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceMuted)
        )
    }

    private var automationStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoPanel(title: "Wake Trigger") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        wakeModeChip(title: "Wake With Sunrise", mode: .sunrise)
                        wakeModeChip(title: "Wake At Specific Time", mode: .specificTime)
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    )

                    wakeTriggerDetailPanel
                }
            }

            infoPanel(title: "Repeat Schedule") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Choose days")
                            .font(AppTypography.style(.footnote, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        let allDaysSelected = wakeWeekdays.allSatisfy { $0 }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                let newValue = !allDaysSelected
                                wakeWeekdays = Array(repeating: newValue, count: 7)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: allDaysSelected ? "checkmark.circle.fill" : "circle")
                                    .font(AppTypography.style(.caption2))
                                Text("Every day")
                                    .font(AppTypography.style(.caption, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(automationTabButtonBackground(isActive: allDaysSelected))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    GeometryReader { geo in
                        let spacing: CGFloat = 5
                        HStack(spacing: spacing) {
                            ForEach(weekdayNames.indices, id: \.self) { idx in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        wakeWeekdays[idx].toggle()
                                    }
                                } label: {
                                    Text(weekdayNames[idx].uppercased())
                                        .font(AppTypography.style(.caption2, weight: .semibold))
                                        .tracking(0.3)
                                        .foregroundColor(wakeWeekdays[idx] ? .black : .white.opacity(0.7))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 34)
                                        .background(weekdayButtonBackground(isSelected: wakeWeekdays[idx]))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .overlay(
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let width = geo.size.width
                                            let totalSpacing = spacing * 6
                                            let chipWidth = (width - totalSpacing) / 7
                                            let slotWidth = chipWidth + spacing
                                            let idx = min(max(Int(value.location.x / slotWidth), 0), 6)
                                            if weekdayDragSelectionMode == nil, idx < wakeWeekdays.count {
                                                weekdayDragSelectionMode = !wakeWeekdays[idx]
                                            }
                                            if let mode = weekdayDragSelectionMode, idx < wakeWeekdays.count, wakeWeekdays[idx] != mode {
                                                withAnimation(.easeInOut(duration: 0.1)) {
                                                    wakeWeekdays[idx] = mode
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            weekdayDragSelectionMode = nil
                                        }
                                )
                        )
                    }
                    .frame(height: 34)

                    if !wakeWeekdays.contains(true) {
                        Text("Select at least one day to continue.")
                            .font(AppTypography.style(.caption))
                            .foregroundStyle(theme.status.negative)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Transition")
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                AutomationTransitionEditor(
                    viewModel: viewModel,
                    device: activeDevice,
                    startGradient: $transitionStartGradient,
                    endGradient: $transitionEndGradient,
                    startBrightness: $transitionStartBrightness,
                    endBrightness: $transitionEndBrightness,
                    durationSeconds: $transitionDurationSeconds,
                    startTemperature: $transitionStartTemperature,
                    startWhiteLevel: $transitionStartWhiteLevel,
                    endTemperature: $transitionEndTemperature,
                    endWhiteLevel: $transitionEndWhiteLevel,
                    maxDurationMinutes: 30,
                    showsDurationRecommendationGuide: false
                )
            }
        }
    }

    @ViewBuilder
    private var wakeTriggerDetailPanel: some View {
        if wakeTriggerMode == .specificTime {
            specificTimeWakePanel
        } else {
            sunriseWakePanel
        }
    }

    private var specificTimeWakePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Wake Time")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                DatePicker(
                    "",
                    selection: $wakeTime,
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Text("Morning transition starts 10 minutes before your selected wake time.")
                    .font(AppTypography.style(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Runs daily at your selected local time.")
                .font(AppTypography.style(.caption))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var sunriseWakePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SolarOffsetArcSlider(
                offsetMinutes: Binding(
                    get: { Double(sunriseOffsetMinutes) },
                    set: { sunriseOffsetMinutes = SolarTrigger.clampOnDeviceOffset(Int($0.rounded())) }
                ),
                eventType: .sunrise,
                device: activeDevice,
                maintainAspectRatio: false
            )
            .frame(maxWidth: .infinity)
            .frame(height: 178)

            Text("Sunrise trigger uses your location and device timezone.")
                .font(AppTypography.style(.caption))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .top)
    }

    private var weekdayNames: [String] {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    private func wakeModeChip(title: String, mode: WakeTriggerMode) -> some View {
        let isActive = wakeTriggerMode == mode
        let foregroundColor = isActive ? Color.black : Color.white.opacity(0.92)
        let fillColor = isActive ? Color.white.opacity(0.94) : Color.white.opacity(0.08)
        let borderColor = isActive ? Color.white.opacity(0.2) : Color.white.opacity(0.12)
        let shadowColor = isActive ? Color.black.opacity(0.12) : Color.clear
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                wakeTriggerMode = mode
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
                Text(title)
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
                    .foregroundColor(foregroundColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .shadow(color: shadowColor, radius: isActive ? 3 : 0, x: 0, y: isActive ? 1 : 0)
        }
        .buttonStyle(.plain)
        .contentShape(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    @ViewBuilder
    private func automationTabButtonBackground(isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func weekdayButtonBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), Color.white.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            if let previous = previousStep(before: step) {
                AppGlassPillButton(
                    title: "Back",
                    isSelected: false,
                    iconName: "chevron.left",
                    size: .compact,
                    useControlGlassRecipe: true
                ) {
                    moveToStep(previous.rawValue)
                }
            }

            if step == .automation {
                AppGlassPillButton(
                    title: "Skip",
                    isSelected: false,
                    iconName: "forward.end",
                    size: .compact,
                    useControlGlassRecipe: true
                ) {
                    Task {
                        localError = nil
                        await applySetup(skipAutomationCreation: true)
                    }
                }
                .disabled(isApplying)
                .opacity(isApplying ? 0.6 : 1.0)
            }

            Spacer(minLength: 0)

            AppGlassPillButton(
                title: primaryButtonTitle,
                isSelected: true,
                iconName: primaryButtonIcon,
                size: .regular,
                useControlGlassRecipe: true,
                useAppleSelectedStyle: true
            ) {
                Task {
                    await handlePrimaryAction()
                }
            }
            .disabled(!canGoNext)
            .opacity(canGoNext ? 1.0 : 0.6)
        }
        .padding(10)
        .appLiquidGlass(role: .panel, cornerRadius: 18)
    }

    private var primaryButtonTitle: String {
        if isApplying { return "Applying…" }
        if isSavingSetupSmartHome { return "Saving…" }
        if step == .smartHome {
            if setupAlexaEnabled && !showSetupAlexaDiscoveryInstructions {
                return "Save Alexa Setup"
            }
            return step == finalStep ? "Finish Setup" : "Continue"
        }
        return step == finalStep ? "Finish Setup" : "Continue"
    }

    private var primaryButtonIcon: String {
        if isApplying || isSavingSetupSmartHome { return "hourglass" }
        if step == .smartHome && setupAlexaEnabled && !showSetupAlexaDiscoveryInstructions {
            return "checkmark"
        }
        return step == finalStep ? "checkmark" : "chevron.right"
    }

    private func moveToStep(_ rawStep: Int) {
        guard let target = SetupStep(rawValue: rawStep) else { return }
        transitionDirection = target.rawValue >= step.rawValue ? .forward : .backward
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            step = target
        }
    }

    private func nextStep(after current: SetupStep) -> SetupStep? {
        guard let index = activeSetupSteps.firstIndex(of: current) else { return nil }
        let nextIndex = activeSetupSteps.index(after: index)
        guard nextIndex < activeSetupSteps.endIndex else { return nil }
        return activeSetupSteps[nextIndex]
    }

    private func previousStep(before current: SetupStep) -> SetupStep? {
        guard let index = activeSetupSteps.firstIndex(of: current), index > activeSetupSteps.startIndex else {
            return nil
        }
        return activeSetupSteps[activeSetupSteps.index(before: index)]
    }

    private func handlePrimaryAction() async {
        localError = nil

        if step == .smartHome {
            if setupAlexaEnabled && showSetupAlexaDiscoveryInstructions {
                if let next = nextStep(after: step) {
                    moveToStep(next.rawValue)
                } else {
                    await applySetup(skipAutomationCreation: true)
                }
                return
            }

            let saved = await saveSmartHomeSetupIfNeeded()
            guard saved else { return }
            if setupAlexaEnabled {
                return
            }
            if let next = nextStep(after: step) {
                moveToStep(next.rawValue)
            } else {
                await applySetup(skipAutomationCreation: true)
            }
            return
        }

        if step == finalStep {
            await applySetup(skipAutomationCreation: false)
            return
        }

        if let next = nextStep(after: step) {
            moveToStep(next.rawValue)
            return
        }

        await applySetup(skipAutomationCreation: false)
    }

    private func initializeSelectionIfNeeded() {
        let live = activeDevice
        deviceName = setupSuggestedName(for: live)

        if live.setupState == .genericManual {
            selectedProductId = ProductOption.custom.id
        } else if live.lookId == ProductOption.bloom.id {
            selectedProductId = ProductOption.bloom.id
        } else {
            selectedProductId = ProductOption.skyLantern.id
        }

        hasConfirmedWiFi = false
        setupAlexaEnabled = false
        setupAlexaName = setupSuggestedName(for: live)
        isSavingSetupSmartHome = false
        setupSmartHomeMessage = nil
        setupSmartHomeMessageIsError = false
        showSetupAlexaDiscoveryInstructions = false
        wakeTriggerMode = .sunrise
        wakeTime = Self.defaultWakeTime()
        sunriseOffsetMinutes = -15
        wakeWeekdays = WeekdayMask.allDaysSunFirst
        weekdayDragSelectionMode = nil

        transitionStartGradient = Self.defaultSunriseStartGradient
        transitionEndGradient = Self.defaultSunriseEndGradient
        transitionStartBrightness = 30
        transitionEndBrightness = 190
        transitionDurationSeconds = 600
        transitionStartTemperature = nil
        transitionStartWhiteLevel = nil
        transitionEndTemperature = nil
        transitionEndWhiteLevel = nil
        switch live.location {
        case .all:
            selectedRoomLocation = .bedroom
            customRoomName = ""
        case .custom(let name):
            selectedRoomLocation = .custom("")
            customRoomName = name
        default:
            selectedRoomLocation = live.location
            customRoomName = ""
        }
    }

    private func setupSuggestedName(for device: WLEDDevice) -> String {
        let trimmed = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if device.setupState == .pendingSelection {
            return "Aesdetic Sunrise Lamp"
        }
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("wled") == .orderedSame || trimmed.lowercased().hasPrefix("wled-") {
            return "Aesdetic Sunrise Lamp"
        }
        return device.name
    }

    private func loadCurrentWiFiInfo() async {
        isLoadingWiFiInfo = true
        defer { isLoadingWiFiInfo = false }
        do {
            let fetched = try await WLEDWiFiService.shared.getCurrentWiFiInfo(device: activeDevice)
            if let previous = currentWiFiInfo,
               isUnknownWiFiValue(fetched.ssid),
               !isUnknownWiFiValue(previous.ssid) {
                currentWiFiInfo = WiFiInfo(
                    ssid: previous.ssid,
                    signalStrength: fetched.signalStrength,
                    channel: fetched.channel,
                    security: isUnknownWiFiValue(fetched.security) ? previous.security : fetched.security,
                    ipAddress: fetched.ipAddress ?? previous.ipAddress,
                    macAddress: fetched.macAddress ?? previous.macAddress
                )
            } else {
                currentWiFiInfo = fetched
            }
        } catch {
            // Keep the previous reading visible if we temporarily lose connectivity while Wi-Fi changes.
        }
    }

    private var resolvedSetupLocation: DeviceLocation {
        if case .custom = selectedRoomLocation {
            return .custom(trimmedCustomRoomName)
        }
        return selectedRoomLocation
    }

    private func applyDeviceRoomLocationIfNeeded(to device: WLEDDevice) async {
        let location = resolvedSetupLocation
        guard location != device.location else { return }
        await viewModel.updateDeviceLocation(device, location: location)
    }

    private func scanForWiFiNetworks() {
        wifiScanTask?.cancel()
        isScanningWiFi = true
        wifiConnectionStatus = .scanning
        let targetDevice = activeDevice

        wifiScanTask = Task {
            do {
                let networks = try await WLEDWiFiService.shared.scanForNetworks(device: targetDevice)
                await MainActor.run {
                    if !networks.isEmpty {
                        availableNetworks = networks
                    } else if availableNetworks.isEmpty {
                        availableNetworks = []
                    }
                    isScanningWiFi = false
                    if case .connecting = wifiConnectionStatus {
                        return
                    }
                    if networks.isEmpty && !availableNetworks.isEmpty {
                        wifiConnectionStatus = .failed("No networks returned in this scan. Try again.")
                    } else {
                        wifiConnectionStatus = .idle
                    }
                }
            } catch {
                if error is CancellationError {
                    await MainActor.run {
                        isScanningWiFi = false
                    }
                    return
                }
                await MainActor.run {
                    isScanningWiFi = false
                    wifiConnectionStatus = .failed("Unable to scan right now. Keep setup open and retry in a moment.")
                }
            }
        }
    }

    private func selectWiFiNetwork(_ network: WiFiNetwork) {
        selectedNetwork = network
        wifiPassword = ""
        wifiConnectionStatus = .idle
    }

    private func connectToSelectedWiFiNetwork() {
        guard let network = selectedNetwork, !isConnectingWiFi else { return }

        isConnectingWiFi = true
        wifiConnectionStatus = .connecting
        let targetDevice = activeDevice

        Task {
            do {
                try await WLEDWiFiService.shared.connectToNetwork(
                    device: targetDevice,
                    ssid: network.ssid,
                    password: wifiPassword.isEmpty ? nil : wifiPassword
                )

                await MainActor.run {
                    isConnectingWiFi = false
                    wifiConnectionStatus = .connected
                    hasConfirmedWiFi = true
                    wifiPassword = ""
                }

                // Device may reboot/reconnect after credentials are applied.
                // Trigger passive discovery and then refresh Wi-Fi information.
                viewModel.startPassiveDiscovery()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await loadCurrentWiFiInfo()
                scanForWiFiNetworks()

                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if case .connected = wifiConnectionStatus {
                        wifiConnectionStatus = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    isConnectingWiFi = false
                    wifiConnectionStatus = .failed("Wi-Fi update did not complete. Verify password and try again.")
                }

                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if case .failed = wifiConnectionStatus {
                        wifiConnectionStatus = .idle
                    }
                }
            }
        }
    }

    private func saveSmartHomeSetupIfNeeded() async -> Bool {
        setupSmartHomeMessage = nil
        setupSmartHomeMessageIsError = false
        showSetupAlexaDiscoveryInstructions = false

        guard setupAlexaEnabled else {
            SmartHomeIntegrationStore.shared.setStatus(
                .notSetUp,
                for: .alexa,
                deviceId: activeDevice.id
            )
            return true
        }

        let name = trimmedSetupAlexaName
        guard !name.isEmpty else {
            setupSmartHomeMessage = "Add a name Alexa can discover."
            setupSmartHomeMessageIsError = true
            return false
        }

        isSavingSetupSmartHome = true
        defer { isSavingSetupSmartHome = false }

        let success = await viewModel.syncAlexaFavoritesToDevice(
            activeDevice,
            enabled: true,
            invocationName: name
        )

        if success {
            showSetupAlexaDiscoveryInstructions = true
            setupSmartHomeMessage = nil
            setupSmartHomeMessageIsError = false
            return true
        }

        let conflicts = viewModel.alexaMirrorConflictSlots(for: activeDevice)
        setupSmartHomeMessage = conflicts.isEmpty
            ? "Could not save Alexa setup. You can continue and set it up later from Integrations."
            : "Alexa slots \(conflicts.map(String.init).joined(separator: ", ")) already contain WLED presets."
        setupSmartHomeMessageIsError = true
        return false
    }

    private func applySetup(skipAutomationCreation: Bool) async {
        guard !trimmedDeviceName.isEmpty else {
            localError = SetupError.invalidDeviceName.localizedDescription
            return
        }

        let live = activeDevice
        isApplying = true
        defer { isApplying = false }

        do {
            if trimmedDeviceName != live.name {
                await viewModel.renameDevice(live, to: trimmedDeviceName)
                if viewModel.currentError != nil {
                    localError = viewModel.currentError?.message
                    return
                }
            }

            await applyDeviceRoomLocationIfNeeded(to: live)

            if isCustomProduct {
                await viewModel.setDeviceSetupMode(live, generic: true)
                closeFlow()
                return
            } else {
                try await applyRecommendedLEDPreferences(to: live)
                await applyInitialSunriseColor(to: live)
                await viewModel.completeAesdeticOnboardingSetup(
                    live,
                    productType: selectedProduct.productType,
                    variantId: selectedProduct.id
                )
            }

            if !skipAutomationCreation {
                try await createOrUpdateWakeAutomation(for: live)
            }
            closeFlow()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func openCustomLEDSettingsInWebUI() {
        guard let url = URL(string: "http://\(activeDevice.ipAddress)/settings/leds") else {
            localError = "Unable to open LED settings URL."
            return
        }
        openURL(url)
    }

    private func applyRecommendedLEDPreferences(to device: WLEDDevice) async throws {
        guard let recommendation = selectedProduct.recommendation else { return }
        let service = WLEDAPIService.shared
        let current = try await service.getLEDConfiguration(for: device)

        let updated = LEDConfiguration(
            stripType: recommendation.stripType,
            colorOrder: current.colorOrder,
            gpioPin: recommendation.gpioPin,
            ledCount: recommendation.ledCount,
            startLED: current.startLED,
            skipFirstLEDs: recommendation.skipFirstLEDs,
            reverseDirection: current.reverseDirection,
            offRefresh: current.offRefresh,
            autoWhiteMode: recommendation.autoWhiteMode,
            cctKelvinMin: current.cctKelvinMin,
            cctKelvinMax: current.cctKelvinMax,
            maxCurrentPerLED: recommendation.maxCurrentPerLED,
            maxTotalCurrent: recommendation.maxTotalCurrent,
            usePerOutputLimiter: current.usePerOutputLimiter,
            enableABL: recommendation.enableABL
        )

        _ = try await service.updateLEDConfiguration(updated, for: device)
        await viewModel.refreshLEDPreferences(for: device)
    }

    private func applyInitialSunriseColor(to device: WLEDDevice) async {
        let fallbackBrightness = selectedProduct.recommendation?.initialBrightness ?? 170
        let startBrightness = min(255, max(1, Int(transitionStartBrightness.rounded())))

        await viewModel.applyGradientA(
            transitionStartGradient,
            aBrightness: startBrightness > 0 ? startBrightness : fallbackBrightness,
            to: device
        )
    }

    private func createOrUpdateWakeAutomation(for device: WLEDDevice) async throws {
        let normalizedWeekdays = WeekdayMask.normalizeSunFirst(wakeWeekdays)
        guard normalizedWeekdays.contains(true) else {
            throw SetupError.noWeekdaysSelected
        }

        if wakeTriggerMode == .sunrise {
            let coordinate = await AutomationStore.shared.currentCoordinate()
            if coordinate == nil {
                showLocationSettingsAlert = true
                throw SetupError.locationRequired
            }
        }

        let trigger: AutomationTrigger
        switch wakeTriggerMode {
        case .sunrise:
            let clamped = SolarTrigger.clampOnDeviceOffset(sunriseOffsetMinutes)
            let solar = SolarTrigger(
                offset: .minutes(clamped),
                location: .followDevice,
                weekdays: normalizedWeekdays
            )
            trigger = .sunrise(solar)
        case .specificTime:
            let components = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
            let hour = components.hour ?? 7
            let minute = components.minute ?? 0
            let hhmm = String(format: "%02d:%02d", hour, minute)
            trigger = .specificTime(
                TimeTrigger(
                    time: hhmm,
                    weekdays: normalizedWeekdays,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            )
        }
        let action = AutomationAction.transition(
            TransitionActionPayload(
                startGradient: transitionStartGradient,
                startBrightness: min(255, max(0, Int(transitionStartBrightness.rounded()))),
                startTemperature: transitionStartTemperature,
                startWhiteLevel: transitionStartWhiteLevel,
                endGradient: transitionEndGradient,
                endBrightness: min(255, max(0, Int(transitionEndBrightness.rounded()))),
                endTemperature: transitionEndTemperature,
                endWhiteLevel: transitionEndWhiteLevel,
                durationSeconds: max(0, min(1800, transitionDurationSeconds)),
                shouldLoop: false,
                presetId: nil,
                presetName: "Morning Wake"
            )
        )

        let metadata = AutomationMetadata(
            colorPreviewHex: transitionEndGradient.stops.last?.hexColor ?? "#7EC8FF",
            accentColorHex: transitionEndGradient.stops.last?.hexColor ?? "#7EC8FF",
            iconName: "sunrise.fill",
            notes: "Created during device setup",
            templateId: "onboarding_wake_v2",
            pinnedToShortcuts: true,
            runOnDevice: true
        )

        let store = AutomationStore.shared
        let targetIds = [device.id]
        let automationName = "Sunrise"
        let targets = AutomationTargets(
            deviceIds: targetIds,
            syncGroupName: nil,
            allowPartialFailure: true
        )

        let draft: Automation
        if let existing = store.automations.first(where: {
            $0.metadata.templateId == "onboarding_wake_v2" && Set($0.targets.deviceIds) == Set(targetIds)
        }) {
            var updated = existing
            updated.name = automationName
            updated.trigger = trigger
            updated.action = action
            updated.targets = targets
            updated.metadata = metadata
            updated.enabled = true
            updated.updatedAt = Date()
            draft = updated
        } else {
            draft = Automation(
                name: automationName,
                enabled: true,
                trigger: trigger,
                action: action,
                targets: targets,
                metadata: metadata
            )
        }

        // Match AddAutomationDialog path: validate on-device schedule before persisting.
        let validation = await store.validateOnDeviceSchedule(for: draft)
        guard validation.isValid else {
            throw SetupError.invalidOnDeviceSchedule(
                validation.message ?? "No available on-device timer slots for this schedule."
            )
        }

        if store.automations.contains(where: { $0.id == draft.id }) {
            store.update(draft)
        } else {
            guard store.add(draft) else {
                throw SetupError.invalidOnDeviceSchedule(
                    "Automation could not be saved because the device is busy syncing. Please wait a moment and try again."
                )
            }
        }
    }

    private func autoWhiteDisplayName(_ mode: Int) -> String {
        switch mode {
        case 0: return "None"
        case 1: return "Brighter"
        case 2: return "Accurate"
        case 3: return "Dual"
        case 4: return "Maximum"
        default: return "Mode \(mode)"
        }
    }

    private func isUnknownWiFiValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("unknown") == .orderedSame
    }

    private func offsetLabel(minutes: Int) -> String {
        if minutes == 0 { return "At sunrise" }
        if minutes > 0 { return "+\(minutes) min" }
        return "\(minutes) min"
    }

    @ViewBuilder
    private var wifiConnectionStatusView: some View {
        switch wifiConnectionStatus {
        case .idle:
            EmptyView()
        case .scanning:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.75)
                Text("Scanning for networks…")
                    .font(AppTypography.style(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.75)
                Text("Applying Wi-Fi settings…")
                    .font(AppTypography.style(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
        case .connected:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.status.positive)
                Text("Connected. Wi-Fi confirmed.")
                    .font(AppTypography.style(.caption))
                    .foregroundStyle(theme.status.positive)
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.status.negative)
                Text(message)
                    .font(AppTypography.style(.caption))
                    .foregroundStyle(theme.status.negative)
                    .lineLimit(2)
            }
        }
    }

    private func closeFlow() {
        wifiScanTask?.cancel()
        viewModel.isMandatorySetupFlowActive = false
        if let onClose {
            onClose()
            return
        }
        dismiss()
    }

    private func infoPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.style(.headline, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appLiquidGlass(role: .panel, cornerRadius: 14)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 6)
            Text(value)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func roomLocationChip(location: DeviceLocation) -> some View {
        let isOther = { if case .custom = location { return true } else { return false } }()
        let isSelected = {
            if isOther {
                if case .custom = selectedRoomLocation { return true }
                return false
            }
            return selectedRoomLocation == location
        }()
        let title = isOther ? "Other" : location.displayName

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedRoomLocation = isOther ? .custom("") : location
            }
        } label: {
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(isSelected ? .black : theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.white : theme.surfaceMuted)
                )
        }
        .buttonStyle(.plain)
    }

    private func gradientSwatch(_ hexes: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, hex in
                Rectangle()
                    .fill(Color(hex: hex))
            }
        }
        .frame(width: 88, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }
}
