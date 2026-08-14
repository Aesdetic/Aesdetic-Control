import Combine
import SwiftUI

struct AddDeviceProvisioningFlowView: View {
    @ObservedObject private var viewModel: DeviceControlViewModel
    private let purpose: WLEDProvisioningPurpose
    let onBeginProductSetup: (WLEDProvisioningResult) -> Void
    let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var coordinator: WLEDProvisioningCoordinator
    @State private var showCustomAPFields = false
    @State private var showSetupHelp = false
    @State private var showAdvancedSetupHelp = false
    @State private var showCancelConfirmation = false
    @State private var didHandoffToProductSetup = false
    @State private var manualIP = ""

    init(
        viewModel: DeviceControlViewModel,
        purpose: WLEDProvisioningPurpose = .addDevice,
        onCancel: (() -> Void)? = nil,
        onBeginProductSetup: @escaping (WLEDProvisioningResult) -> Void
    ) {
        self.viewModel = viewModel
        self.purpose = purpose
        self.onCancel = onCancel
        self.onBeginProductSetup = onBeginProductSetup
        _coordinator = StateObject(
            wrappedValue: WLEDProvisioningCoordinator(viewModel: viewModel, purpose: purpose)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if isCenteredState {
                    centeredContent
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            content
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(purpose.existingDevice == nil ? "Set Up Device" : "Reconnect Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        requestCancellation()
                    }
                }
            }
        }
        .onAppear(perform: coordinator.start)
        .onReceive(coordinator.$completedProvisioningResult.compactMap { $0 }) { result in
            guard !didHandoffToProductSetup else { return }
            didHandoffToProductSetup = true
            onBeginProductSetup(result)
            if onCancel == nil {
                dismiss()
            }
        }
        .interactiveDismissDisabled()
        .alert("Leave setup?", isPresented: $showCancelConfirmation) {
            Button("Keep Setting Up", role: .cancel) {}
            Button("Leave Setup", role: .destructive) {
                cancelAndClose()
            }
        } message: {
            Text("Your device may still be changing networks. You can find it again from the Devices tab.")
        }
    }

    private var isCenteredState: Bool {
        switch coordinator.presentationState {
        case .devicePageNotice, .connecting, .finishing, .takingLonger, .failure:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var centeredContent: some View {
        switch coordinator.presentationState {
        case .failure:
            ScrollView(.vertical, showsIndicators: false) {
                failureContent(coordinator.phase.subtitle)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(minHeight: 620)
            }
        default:
            provisioningProgressContent
                .padding(.horizontal, 28)
        }
    }

    private func requestCancellation() {
        if coordinator.requiresCancellationConfirmation {
            showCancelConfirmation = true
        } else {
            cancelAndClose()
        }
    }

    private func cancelAndClose() {
        coordinator.cancel()
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: coordinator.phase.iconName)
                .font(AppTypography.style(.title2, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.blue.opacity(0.9)))

            VStack(alignment: .leading, spacing: 3) {
                Text(coordinator.phase.title)
                    .font(AppTypography.style(.title2, weight: .semibold))
                    .foregroundColor(textPrimary)
                Text(coordinator.phase.subtitle)
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .idle, .discoveringLAN:
            discoveryContent
        case .devicesFound:
            foundDevicesContent
        case .collectingHomeWiFi:
            homeWiFiCredentialsContent
        case .presentingAccessoryPicker, .preparingDevicePage, .joiningAccessPoint, .probingAccessPoint,
             .verifyingHomeWiFi, .applyingHomeWiFi, .returningToHomeNetwork, .rediscovering,
             .rediscoveryTakingLonger, .recoveringSetupConnection:
            progressContent
        case .correctingHomeWiFi:
            homeWiFiCorrectionContent
        case .failed(let failure):
            failureContent(failure.message)
        }
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusPanel(
                title: "Searching your network",
                message: viewModel.wledService.discoveryProgress.isEmpty
                    ? coordinator.phase.subtitle
                    : viewModel.wledService.discoveryProgress,
                icon: "dot.radiowaves.left.and.right"
            )
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    private var foundDevicesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(coordinator.candidates) { device in
                Button {
                    onBeginProductSetup(coordinator.provisioningResult(for: device))
                    if onCancel == nil {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb")
                            .font(AppTypography.style(.title3, weight: .semibold))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(AppTypography.style(.headline, weight: .semibold))
                                .foregroundColor(textPrimary)
                            Text("Ready for product setup")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(textSecondary)
                    }
                    .padding(14)
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(CardButtonStyle())
            }

            Button("Set Up a New Plugged-In Device") {
                coordinator.beginNewDeviceSetup()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var homeWiFiCredentialsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusPanel(
                title: "Home Wi-Fi",
                message: "Your device will use this network after setup.",
                icon: "wifi"
            )

            homeWiFiCredentialsFields

            Button("Continue") {
                coordinator.showAccessoryPicker()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!coordinator.canBeginAccessorySetup)

            setupHelpContent(includesHomeSearch: false)
        }
    }

    private var progressContent: some View {
        provisioningProgressContent
    }

    private var provisioningProgressContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(panelBackground)
                    .frame(width: 156, height: 156)
                Image("product_image")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 116, height: 116)
                    .accessibilityHidden(true)
            }

            ProgressView()
                .controlSize(.large)
                .tint(textPrimary)

            VStack(spacing: 10) {
                Text(progressTitle)
                    .font(AppTypography.style(.title2, weight: .semibold))
                    .foregroundColor(textPrimary)
                    .multilineTextAlignment(.center)

                if coordinator.presentationState == .devicePageNotice ||
                    coordinator.presentationState == .takingLonger {
                    Text(coordinator.phase.subtitle)
                        .font(AppTypography.style(.subheadline))
                        .foregroundColor(textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if coordinator.presentationState == .takingLonger {
                VStack(spacing: 12) {
                    Button("Check Wi-Fi Details") {
                        coordinator.editHomeWiFiAfterFailure()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Find Device Again") {
                        coordinator.findProvisionedDeviceAgain()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: 420)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: 520, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var progressTitle: String {
        switch coordinator.presentationState {
        case .finishing, .takingLonger:
            return "Finishing setup"
        default:
            return "Connecting"
        }
    }

    private var homeWiFiCredentialsFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Network name")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(textSecondary)
                if coordinator.isLoadingCurrentSSID {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("Home Wi-Fi name", text: $coordinator.homeWiFiCredentials.ssid)
                .textContentType(.none)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(textPrimary)

            if !coordinator.homeWiFiCredentials.isOpenNetwork {
                SecureField("Wi-Fi password", text: $coordinator.homeWiFiCredentials.password)
                    .textContentType(.password)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(textPrimary)
            }

            Toggle(
                "This network has no password",
                isOn: Binding(
                    get: { coordinator.homeWiFiCredentials.isOpenNetwork },
                    set: coordinator.setHomeWiFiOpenNetwork
                )
            )
            .font(AppTypography.style(.subheadline))
            .foregroundColor(textPrimary)
            .tint(.blue)
        }
        .padding(14)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var homeWiFiCorrectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let message = coordinator.networkVerificationMessage {
                statusPanel(title: "Check network", message: message, icon: "wifi.exclamationmark")
            }

            homeWiFiCredentialsFields

            if !coordinator.availableNetworks.isEmpty {
                Text("Networks visible to this device")
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(textSecondary)

                VStack(spacing: 10) {
                    ForEach(coordinator.availableNetworks) { network in
                        networkRow(network)
                    }
                }
            }

            Button(coordinator.selectedNetwork == nil ? "Try Entered Network" : "Try This Wi-Fi") {
                coordinator.useEnteredHomeNetwork()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!coordinator.canBeginAccessorySetup)

            Button("Scan Again") {
                coordinator.refreshHomeNetworks()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 30)

            Image(systemName: "exclamationmark.circle")
                .font(AppTypography.display(size: 54, weight: .regular, relativeTo: .largeTitle))
                .foregroundColor(textPrimary)

            Text("Setup couldn’t finish")
                .font(AppTypography.style(.title2, weight: .semibold))
                .foregroundColor(textPrimary)

            Text(message)
                .font(AppTypography.style(.subheadline))
                .foregroundColor(textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Check Wi-Fi Details") {
                coordinator.editHomeWiFiAfterFailure()
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Find Device Again") {
                coordinator.discoverOnCurrentNetwork()
            }
            .buttonStyle(SecondaryButtonStyle())

            setupHelpContent(includesHomeSearch: false)

            Spacer(minLength: 30)
        }
    }

    private func setupHelpContent(includesHomeSearch: Bool) -> some View {
        DisclosureGroup(isExpanded: $showSetupHelp) {
            VStack(alignment: .leading, spacing: 12) {
                setupTip("Make sure your device is powered on.", icon: "power")
                setupTip("Keep your phone close to the device.", icon: "iphone.radiowaves.left.and.right")
                setupTip("Restart the device, wait a moment, then try again.", icon: "arrow.clockwise")

                if includesHomeSearch {
                    Button("Search Home Wi-Fi Again") {
                        coordinator.discoverOnCurrentNetwork()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                DisclosureGroup(isExpanded: $showAdvancedSetupHelp) {
                    VStack(alignment: .leading, spacing: 12) {
                        if coordinator.canResumeAuthorizedAccessory {
                            Button("Resume Previous Setup") {
                                coordinator.resumeAuthorizedAccessory()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!coordinator.canBeginAccessorySetup)
                        }

                        Button("Try Standard Setup Connection") {
                            coordinator.joinStandardAccessPoint()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!coordinator.canBeginAccessorySetup)

                        Button(showCustomAPFields ? "Hide Different Connection" : "Use Different Setup Connection") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showCustomAPFields.toggle()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        if showCustomAPFields {
                            customAPPanel
                        }

                        manualEntryPanel
                    }
                    .padding(.top, 10)
                } label: {
                    Text("Advanced")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(textPrimary)
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Setup Help", systemImage: "questionmark.circle")
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(textPrimary)
        }
        .padding(.horizontal, 2)
        .tint(textSecondary)
    }

    private func setupTip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(AppTypography.style(.subheadline))
            .foregroundColor(textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var manualEntryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device address")
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(textPrimary)
            HStack(spacing: 10) {
                TextField("192.168.1.100", text: $manualIP)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(textPrimary)

                Button("Add Device") {
                    coordinator.addManualDevice(ipAddress: manualIP)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 110)
                .disabled(manualIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var customAPPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Different setup connection")
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(textPrimary)
            TextField("Setup network name", text: $coordinator.customAPSSID)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(textPrimary)
            SecureField("Setup network password", text: $coordinator.customAPPassword)
                .textContentType(.password)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(textPrimary)
            Button("Connect") {
                coordinator.joinCustomAccessPoint()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(
                coordinator.customAPSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                coordinator.customAPPassword.trimmingCharacters(in: .whitespacesAndNewlines).count < 8
            )
        }
        .padding(14)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusPanel(title: String, message: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.style(.title3, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(textPrimary)
                Text(message)
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func networkRow(_ network: WiFiNetwork) -> some View {
        Button {
            coordinator.selectHomeNetwork(network)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: coordinator.selectedNetwork?.ssid == network.ssid ? "checkmark.circle.fill" : "wifi")
                    .font(AppTypography.style(.title3, weight: .semibold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(network.ssid)
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .foregroundColor(textPrimary)
                    Text(networkSummary(network))
                        .font(AppTypography.style(.caption))
                        .foregroundColor(textSecondary)
                }
                Spacer()
            }
            .padding(14)
            .background(coordinator.selectedNetwork?.ssid == network.ssid ? Color.blue.opacity(0.22) : panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
    }

    private var textPrimary: Color {
        AppTheme.text(.glassPrimary, for: colorScheme)
    }

    private var textSecondary: Color {
        AppTheme.text(.glassSecondary, for: colorScheme)
    }

    private var panelBackground: Color {
        GlassTheme.surfaces(for: colorScheme).panelFill
    }

    private var fieldBackground: Color {
        GlassTheme.surfaces(for: colorScheme).fieldFill
    }

    private func networkSummary(_ network: WiFiNetwork) -> String {
        let signal: String
        switch network.signalStrength {
        case -55...0:
            signal = "Strong signal"
        case -70..<(-55):
            signal = "Good signal"
        default:
            signal = "Weak signal"
        }
        let access = network.security.caseInsensitiveCompare("open") == .orderedSame
            ? "No password"
            : "Password required"
        return "\(signal) - \(access)"
    }
}
