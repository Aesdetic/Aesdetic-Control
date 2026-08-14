import SwiftUI
import Combine

enum DeviceDetailBackgroundStyle {
    case frosted
    case liquidGlass
}

private enum DeviceDetailDockTypography {
    static func style(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(textStyle, design: .default).weight(weight)
    }
}

struct DeviceDetailView: View {
    let device: WLEDDevice
    private let backgroundStyle: DeviceDetailBackgroundStyle
    private let containerCornerRadius: CGFloat
    private let containerBottomCornerRadius: CGFloat
    private let presentationProgress: CGFloat
    private let delaysContentUntilExpanded: Bool
    private let contentRevealProgress: CGFloat?
    private let presentationBottomSafeAreaInset: CGFloat
    private let onClose: (() -> Void)?
    private let onReconnectDevice: ((WLEDDevice) -> Void)?
    @ObservedObject var viewModel: DeviceControlViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.setupJourneyActions) private var setupJourneyActions
    @State private var selectedTab: String = "Light"

    // State variables for new features
    @State private var showSettings: Bool = false
    @State private var settingsInitialCategory: ComprehensiveSettingsView.SettingsCategory = .overview
    @State private var tabBeforeSettings: String = "Light"
    @State private var settingsHeaderChrome: EmbeddedSettingsHeaderChrome = .settings
    @StateObject private var settingsHeaderActionStore = EmbeddedSettingsHeaderActionStore()
    @State private var showSaveSceneDialog: Bool = false
    @State private var showAddAutomation: Bool = false
    @State private var pendingAutomationTemplate: AutomationTemplate? = nil
    @State private var udpnSend: Bool = false
    @State private var udpnReceive: Bool = false
    @StateObject private var scenesStore = ScenesStore.shared
    @StateObject private var automationStore = DeviceDetailAutomationStoreBridge()
    @State private var showEditDeviceInfo: Bool = false
    @State private var isToggling: Bool = false
    @State private var quickBrightness: Double = 0
    @State private var isAdjustingQuickBrightness: Bool = false
    @State private var isSavingColorPreset: Bool = false
    @State private var showSaveColorSuccess: Bool = false
    @State private var saveColorFeedbackTrigger: Int = 0
    @State private var showSaveColorPresetDialog: Bool = false
    @State private var dismissColorPicker: Bool = false
    @State private var selectedSegmentId: Int = 0  // Track selected segment for multi-segment devices
    @State private var isTransitionPaneExpanded: Bool = false
    @State private var isEffectsPaneExpanded: Bool = false
    @State private var didResetAnimationModes: Bool = false
    @State private var editingAutomation: Automation? = nil
    @State private var automationEditorDefaultName: String? = nil
    @State private var automationPendingDelete: Automation? = nil
    @State private var suppressUDPNUpdates: Bool = false
    @State private var showRebootConfirm: Bool = false
    @State private var armedCancelRunId: UUID? = nil
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @AppStorage("showSegmentControlsInColorTabAdvanced") private var showSegmentControlsInColorTabAdvanced: Bool = true
    private var detailCardCornerRadius: CGFloat { containerCornerRadius }
    private var detailCardBottomCornerRadius: CGFloat { containerBottomCornerRadius }
    private var usesScreenConcentricBottomCorners: Bool { onClose != nil }
    private var detailForegroundColor: Color {
        AppTheme.deviceDetailText(.primary, for: colorScheme)
    }
    private var detailSecondaryForegroundColor: Color {
        AppTheme.deviceDetailText(.secondary, for: colorScheme)
    }
    private var detailTertiaryForegroundColor: Color {
        AppTheme.deviceDetailText(.tertiary, for: colorScheme)
    }
    private var detailDisabledForegroundColor: Color {
        AppTheme.deviceDetailText(.disabled, for: colorScheme)
    }
    private var detailPowerActiveBackground: Color {
        Color.white.opacity(0.16)
    }
    private var detailPowerInactiveBackground: Color {
        Color.white.opacity(0.16)
    }

    init(
        device: WLEDDevice,
        viewModel: DeviceControlViewModel,
        initialTab: String = "Light",
        backgroundStyle: DeviceDetailBackgroundStyle = .frosted,
        containerCornerRadius: CGFloat = DeviceDetailPresentation.expandedTopCornerRadius,
        containerBottomCornerRadius: CGFloat? = nil,
        presentationProgress: CGFloat = 1,
        delaysContentUntilExpanded: Bool = false,
        contentRevealProgress: CGFloat? = nil,
        presentationBottomSafeAreaInset: CGFloat = 0,
        onClose: (() -> Void)? = nil,
        onReconnectDevice: ((WLEDDevice) -> Void)? = nil
    ) {
        self.device = device
        self.backgroundStyle = backgroundStyle
        self.containerCornerRadius = containerCornerRadius
        self.containerBottomCornerRadius = containerBottomCornerRadius ?? containerCornerRadius
        self.presentationProgress = presentationProgress
        self.delaysContentUntilExpanded = delaysContentUntilExpanded
        self.contentRevealProgress = contentRevealProgress
        self.presentationBottomSafeAreaInset = presentationBottomSafeAreaInset
        self.onClose = onClose
        self.onReconnectDevice = onReconnectDevice
        self.viewModel = viewModel
        _selectedTab = State(initialValue: Self.normalizedTabName(initialTab))
    }

    private static func normalizedTabName(_ tab: String) -> String {
        switch tab {
        case "Colors":
            return "Light"
        case "Presets":
            return "Saves"
        case "Automation", "Automations":
            return "Routines"
        default:
            return tab
        }
    }

    // Use coordinated power state from ViewModel
    private var currentPowerState: Bool {
        return viewModel.getCurrentPowerState(for: activeDevice.id)
    }

    private var isStatusOnline: Bool {
        activeDevice.isOnline || isToggling
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

    private var activeDeviceIds: Set<String> {
        var ids: Set<String> = [activeDevice.id]
        ids.insert(device.id)
        return ids
    }

    private var activePresetLabel: String? {
        guard advancedUIEnabled else { return nil }
        if let playlistId = activeDevice.state?.playlistId, playlistId > 0 {
            return activePlaylistDisplayName(for: playlistId)
        }
        if let presetId = activeDevice.state?.presetId, presetId > 0 {
            return activePresetDisplayName(for: presetId)
        }
        return nil
    }

    private var currentModeLabel: String {
        if let run = viewModel.activeRunStatus[activeDevice.id] {
            return run.title
        }
        if let playlistId = activeDevice.state?.playlistId, playlistId > 0 {
            return activePlaylistDisplayName(for: playlistId) ?? "Playlist"
        }
        if let presetId = activeDevice.state?.presetId, presetId > 0 {
            return activePresetDisplayName(for: presetId) ?? "Saved color"
        }
        return currentPowerState ? "Manual color" : "Standby"
    }

    private func activePresetDisplayName(for presetId: Int) -> String? {
        firstDisplayName([
            viewModel.presetName(for: presetId, device: activeDevice),
            localColorPresetName(for: presetId),
            localEffectPresetName(for: presetId)
        ], excludingRawIdPattern: #"^preset\s*#?\s*\d+$"#)
    }

    private func activePlaylistDisplayName(for playlistId: Int) -> String? {
        firstDisplayName([
            viewModel.playlistName(for: playlistId, device: activeDevice),
            localTransitionPresetName(for: playlistId)
        ], excludingRawIdPattern: #"^playlist\s*#?\s*\d+$"#)
    }

    private func firstDisplayName(_ candidates: [String?], excludingRawIdPattern pattern: String) -> String? {
        candidates.compactMap { candidate -> String? in
            guard let candidate else { return nil }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil else {
                return nil
            }
            return trimmed
        }.first
    }

    private func localColorPresetName(for presetId: Int) -> String? {
        PresetsStore.shared.colorPresets.first { preset in
            preset.wledPresetIds?[activeDevice.id] == presetId || preset.wledPresetId == presetId
        }?.name
    }

    private func localEffectPresetName(for presetId: Int) -> String? {
        PresetsStore.shared.effectPresets(for: activeDevice.id).first { preset in
            preset.wledPresetId == presetId
        }?.name
    }

    private func localTransitionPresetName(for playlistId: Int) -> String? {
        PresetsStore.shared.transitionPresets(for: activeDevice.id).first { preset in
            preset.wledPlaylistId == playlistId
        }?.name
    }

    private var effectiveBrightnessValue: Double {
        Double(max(1, viewModel.getEffectiveBrightness(for: activeDevice)))
    }

    private var quickBrightnessDisplayValue: Double {
        quickBrightness > 0 ? quickBrightness : effectiveBrightnessValue
    }

    private var quickBrightnessPercent: Int {
        Int(round((quickBrightnessDisplayValue / 255.0) * 100.0))
    }

    private var quickBrightnessBinding: Binding<Double> {
        Binding(
            get: { quickBrightnessDisplayValue },
            set: { newValue in
                quickBrightness = min(255, max(1, newValue))
            }
        )
    }

    private var isRebootWaitActive: Bool {
        viewModel.isRebootWaitActive(for: activeDevice.id)
    }

    private var isAutomationMutationLocked: Bool {
        automationStore.hasAnyDeletionInProgress
            || automationStore.hasOnDeviceSyncInProgress(for: activeDeviceIds)
    }

    private var rebootWaitRemainingSeconds: Int {
        viewModel.rebootWaitRemainingSeconds(for: activeDevice.id)
    }

    private var currentActiveRunId: UUID? {
        viewModel.activeRunStatus[activeDevice.id]?.id
    }

    private var requiresProductSetup: Bool {
        viewModel.requiresProfileSetup(activeDevice)
    }

    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        fullDetailBody
            .symbolRenderingMode(.hierarchical)
    }

    private var fullDetailBody: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                backgroundLayer
                // Horizontal margins belong to each content branch so full-width rails
                // do not force the header and embedded editors to become full-width.
                contentLayer(bottomSafeAreaInset: presentationBottomSafeAreaInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
                    .background(detailContainerBackground)
                    .deviceDetailPanelClip(
                        topCornerRadius: detailCardCornerRadius,
                        bottomCornerRadius: detailCardBottomCornerRadius,
                        usesScreenConcentricBottomCorners: usesScreenConcentricBottomCorners
                    )
                    .disabled(isRebootWaitActive || requiresProductSetup)
                bannerOverlay(topInset: topInset)
                if requiresProductSetup {
                    setupLockOverlay
                }
            }
            .modifier(DeviceDetailPresentationModifier(isRunningInPreview: isRunningInPreview))
            .onAppear {
                guard !isRunningInPreview else { return }
                viewModel.setActiveDevice(activeDevice)
                Task {
                    await viewModel.prefetchDeviceDetailData(for: activeDevice)
                }
                if requiresProductSetup {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        openProductSetup()
                    }
                }
            }
            .onChange(of: activeDevice.id) { _, _ in
                guard !isRunningInPreview else { return }
                viewModel.setActiveDevice(activeDevice)
            }
            .onDisappear {
                guard !isRunningInPreview else { return }
                viewModel.clearActiveDeviceIfNeeded(activeDevice.id)
                viewModel.clearActiveDeviceIfNeeded(device.id)
            }
            .overlay {
                if isRebootWaitActive {
                    rebootWaitOverlay
                }
            }
            .onChange(of: dismissColorPicker) { _, newValue in
                if newValue {
                    dismissColorPicker = false
                }
            }
            .onChange(of: currentActiveRunId) { _, newValue in
                if newValue != armedCancelRunId {
                    armedCancelRunId = nil
                }
            }
            .onChange(of: advancedUIEnabled) { _, newValue in
                if !newValue {
                    viewModel.resetManualSegmentationForAllDevices()
                }
            }
            .onChange(of: activeDevice.setupState) { _, newValue in
                if newValue == .pendingSelection {
                    openProductSetup()
                }
            }
            .alert("Reboot Device?", isPresented: $showRebootConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reboot", role: .destructive) {
                    Task {
                        await viewModel.rebootDevice(activeDevice)
                    }
                }
            } message: {
                Text("The device will restart and go offline briefly.")
            }
            .sheet(isPresented: $showEditDeviceInfo) {
                EditDeviceInfoDialog(device: activeDevice)
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showSaveColorPresetDialog) {
                SaveColorPresetDialog(
                    device: activeDevice,
                    currentGradient: currentLightGradientForSaving,
                    currentBrightness: currentBrightnessValueForSaving,
                    currentTemperature: nil,
                    currentWhiteLevel: nil
                ) { preset in
                    Task {
                        await saveLightColorPreset(preset)
                    }
                }
            }
            .alert(
                "Delete routine?",
                isPresented: Binding(
                    get: { automationPendingDelete != nil },
                    set: { if !$0 { automationPendingDelete = nil } }
                ),
                presenting: automationPendingDelete
            ) { automation in
                Button("Delete", role: .destructive) {
                    automationStore.delete(id: automation.id)
                    automationPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    automationPendingDelete = nil
                }
            } message: { automation in
                Text("Delete routine \"\(automation.name)\" from this device?")
            }
        }
    }

    private var backgroundLayer: some View {
        Color.clear
        .ignoresSafeArea()
    }

    private var detailContentOpacity: Double {
        guard onClose != nil else { return 1 }
        if delaysContentUntilExpanded {
            if let contentRevealProgress {
                let normalized = min(1, max(0, contentRevealProgress))
                let eased = normalized * normalized * (3 - (2 * normalized))
                return Double(eased)
            }
            let normalized = min(1, max(0, (presentationProgress - 0.78) / 0.16))
            let eased = normalized * normalized * (3 - (2 * normalized))
            return Double(eased)
        }
        let normalized = (presentationProgress - 0.36) / 0.42
        return Double(min(1, max(0, normalized)))
    }

    private var detailContentOffset: CGFloat {
        guard onClose != nil else { return 0 }
        if delaysContentUntilExpanded {
            return 0
        }
        return (1 - min(1, max(0, presentationProgress))) * 18
    }

    private func contentLayer(bottomSafeAreaInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            if onClose != nil {
                Capsule()
                    .fill(Color.white.opacity(0.34))
                    .frame(width: 42, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
            }

            condensedHeader
                .padding(.horizontal, DeviceDetailPresentation.tabContentHorizontalInset)
                .padding(.top, onClose == nil ? 20 : 10)
                .padding(.bottom, 10)

            if showSettings {
                settingsModeHeader
                    .padding(.horizontal, DeviceDetailPresentation.contentHorizontalInset + 20)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            } else if !showAddAutomation {
                tabNavigationBar
                    .padding(.horizontal, DeviceDetailPresentation.contentHorizontalInset + 20)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }

            if showSettings {
                GeometryReader { proxy in
                    embeddedSettingsContent
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else if showAddAutomation {
                embeddedAutomationEditor
                    .id(automationEditorIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, DeviceDetailPresentation.contentHorizontalInset)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            } else {
                ScrollView {
                    tabContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, DeviceDetailPresentation.tabContentHorizontalInset)
                        .padding(.top, 16)
                        .padding(
                            .bottom,
                            onClose == nil ? 16 : max(24, bottomSafeAreaInset + 20)
                        )
                }
                .frame(maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(detailContentOpacity)
        .offset(y: detailContentOffset)
        .allowsHitTesting(detailContentOpacity > 0.82)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showAddAutomation)
        .onTapGesture {
            dismissColorPicker = true
        }
    }

    private func bannerOverlay(topInset: CGFloat) -> some View {
        Group {
            if let error = viewModel.currentError {
                let action = errorAction(for: error)
                ErrorBanner(
                    message: error.message,
                    icon: error.iconName,
                    actionTitle: error.actionTitle,
                    onAction: action,
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, 16)
                .padding(.top, topInset + 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.2), value: viewModel.currentError)
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
                        .tint(detailForegroundColor)
                        .scaleEffect(1.2)
                    Text("Rebooting Device")
                        .font(DeviceDetailDockTypography.style(.headline, weight: .semibold))
                        .foregroundColor(detailForegroundColor)
                    Text("Reconnecting... \(max(0, rebootWaitRemainingSeconds))s")
                        .font(DeviceDetailDockTypography.style(.subheadline))
                        .foregroundColor(detailSecondaryForegroundColor)
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

    private var setupLockOverlay: some View {
        GeometryReader { proxy in
            let maxCardWidth = min(proxy.size.width - 56, 420)
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        openProductSetup()
                    }

                VStack(spacing: 12) {
                    Text("Setup Required")
                        .font(DeviceDetailDockTypography.style(.headline, weight: .semibold))
                        .foregroundColor(detailForegroundColor)
                    Text("Complete setup to unlock device controls.")
                        .font(DeviceDetailDockTypography.style(.subheadline))
                        .foregroundColor(detailSecondaryForegroundColor)
                    AppGlassPillButton(
                        title: "Continue Setup",
                        isSelected: true,
                        iconName: "arrow.right",
                        size: .regular,
                        useControlGlassRecipe: true
                    ) {
                        openProductSetup()
                    }
                }
                .frame(maxWidth: maxCardWidth)
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: requiresProductSetup)
        .zIndex(2)
    }

    private func openProductSetup() {
        setupJourneyActions.beginProductSetup(activeDevice, nil)
    }

    private func errorAction(for error: DeviceControlViewModel.WLEDError) -> (() -> Void)? {
        switch error {
        case .deviceOffline, .timeout:
            return {
                Task {
                    await viewModel.refreshDeviceState(activeDevice)
                }
            }
        default:
            return nil
        }
    }

    private var condensedHeader: some View {
        let isDeviceOnline = isStatusOnline
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeDevice.name)
                    .font(DeviceDetailTypography.deviceTitle)
                    .foregroundColor(isDeviceOnline ? detailForegroundColor : detailDisabledForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)

                HStack(spacing: 8) {
                    statusDot
                        .opacity(isDeviceOnline ? 1.0 : 0.58)

                    Text(activeDevice.location.displayName)
                        .font(DeviceDetailDockTypography.style(.caption))
                        .foregroundColor(isDeviceOnline ? detailSecondaryForegroundColor : detailDisabledForegroundColor)
                        .lineLimit(1)

                    if let activeRun = viewModel.activeRunStatus[activeDevice.id] {
                        activeRunStatusChip(activeRun)
                    }

                    if let activePresetLabel {
                        Text(activePresetLabel)
                            .font(DeviceDetailDockTypography.style(.caption2, weight: .semibold))
                            .foregroundColor(detailSecondaryForegroundColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.12))
                            )
                    }

                    if requiresProductSetup {
                        Text("Setup Required")
                            .font(DeviceDetailDockTypography.style(.caption2, weight: .semibold))
                            .foregroundColor(detailForegroundColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.16))
                            )
                    }
                }
            }
            .layoutPriority(1)

            Spacer()

            HStack(spacing: 10) {
                deviceOptionsMenu

                Button(action: togglePower) {
                    compactPowerButtonContent
                }
                .buttonStyle(.plain)
                .disabled(isToggling || isRebootWaitActive)
                .accessibilityLabel("Power")
                .accessibilityHint(currentPowerState ? "Turns the device off." : "Turns the device on.")
            }
        }
    }

    private var primaryControlSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentModeLabel)
                        .font(DeviceDetailTypography.cardTitle)
                        .foregroundColor(detailSecondaryForegroundColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Text("\(quickBrightnessPercent)%")
                            .font(DeviceDetailDockTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(detailForegroundColor)
                            .monospacedDigit()

                        Text("Brightness")
                            .font(DeviceDetailDockTypography.style(.caption2, weight: .medium))
                            .foregroundColor(detailSecondaryForegroundColor)
                    }
                }

                Spacer(minLength: 8)
                saveColorPill
            }

            VStack(alignment: .leading, spacing: 8) {
                Slider(
                    value: quickBrightnessBinding,
                    in: 1...255,
                    onEditingChanged: { editing in
                        isAdjustingQuickBrightness = editing
                        if !editing {
                            commitQuickBrightness()
                        }
                    }
                )
                .tint(currentPowerState ? detailForegroundColor : detailForegroundColor.opacity(0.45))
                .disabled(!activeDevice.isOnline || !currentPowerState || isRebootWaitActive)
                .accessibilityLabel("Brightness")
                .accessibilityValue("\(quickBrightnessPercent) percent")

            }

            UnifiedColorPane(
                device: activeDevice,
                dismissColorPicker: $dismissColorPicker,
                segmentId: effectiveSegmentId,
                presentation: .compactControl,
                brightnessOverride: Int(round(quickBrightnessDisplayValue)),
                showsCompactSaveButton: false
            )
            .environmentObject(viewModel)
        }
        .padding(16)
        .settingsDetailControlBackground()
        .onAppear {
            syncQuickBrightnessIfNeeded()
        }
        .onChange(of: activeDevice.brightness) { _, _ in
            syncQuickBrightnessIfNeeded()
        }
    }

    private var saveColorPill: some View {
        PresetSavePillButton(
            title: "Save Color",
            isSaving: isSavingColorPreset,
            isSuccess: showSaveColorSuccess,
            isDisabled: isSavingColorPreset || AutomationStore.shared.hasAnyDeletionInProgress,
            minWidth: 112,
            normalForegroundColor: detailForegroundColor,
            disabledForegroundColor: detailDisabledForegroundColor
        ) {
            if advancedUIEnabled {
                showSaveColorPresetDialog = true
            } else {
                Task {
                    await saveLightColorPresetDirectly()
                }
            }
        }
        .sensorySuccess(trigger: saveColorFeedbackTrigger)
    }

    private var deviceOptionsMenu: some View {
        Menu {
            Button(action: startRename) {
                Label("Rename Device", systemImage: "pencil")
            }
            Button(action: { openSettings(.overview) }) {
                Label("Settings", systemImage: "gearshape")
            }
            Button(action: { openSettings(.timeSchedules) }) {
                Label("Time & Schedules", systemImage: "clock")
            }
            Button(action: { openSettings(.integrations) }) {
                Label("Integrations", systemImage: "link")
            }
            Button(action: openProductSetup) {
                Label("Aesdetic Profile", systemImage: "sparkles")
            }
            Button(action: { advancedUIEnabled.toggle() }) {
                Label(
                    advancedUIEnabled ? "Disable Advanced UI" : "Enable Advanced UI",
                    systemImage: advancedUIEnabled ? "checkmark.circle.fill" : "circle"
                )
            }
            Button(action: {
                Task {
                    await viewModel.clearProtectionWindows(for: activeDevice)
                }
            }) {
                Label("Recover Device", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(role: .destructive, action: {
                showRebootConfirm = true
            }) {
                Label("Reboot Device", systemImage: "power")
            }
            .disabled(isRebootWaitActive)
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(DeviceDetailDockTypography.style(.headline, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(detailForegroundColor)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .accessibilityIdentifier("device-options-menu")
    }

    private func openSettings(_ category: ComprehensiveSettingsView.SettingsCategory) {
        if !showSettings {
            tabBeforeSettings = selectedTab
        }
        settingsInitialCategory = category
        settingsHeaderChrome = .settings
        settingsHeaderActionStore.reset()
        withAnimation(.easeInOut(duration: 0.22)) {
            showAddAutomation = false
            showSettings = true
        }
    }

    private func closeSettingsMode() {
        settingsHeaderChrome = .settings
        settingsHeaderActionStore.reset()
        withAnimation(.easeInOut(duration: 0.22)) {
            showSettings = false
            selectedTab = tabBeforeSettings
        }
    }

    @ViewBuilder
    private var detailContainerBackground: some View {
        switch backgroundStyle {
        case .frosted:
            detailFrostedBackground
        case .liquidGlass:
            detailLiquidGlassBackground
        }
    }

    @ViewBuilder
    private var detailLiquidGlassBackground: some View {
        FolderGlassContainerBackground(
            cornerRadius: detailCardCornerRadius,
            bottomCornerRadius: detailCardBottomCornerRadius,
            usesScreenConcentricBottomCorners: usesScreenConcentricBottomCorners
        )
    }

    private var detailFrostedBackground: some View {
        let shape = RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)

        return shape
            .fill(.ultraThinMaterial.opacity(0.62))
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.62, green: 0.90, blue: 1.0).opacity(0.12),
                            Color(red: 0.18, green: 0.82, blue: 1.0).opacity(0.28)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .blur(radius: 50)
                    .offset(x: -90, y: -10)
                    .mask(shape)
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.20), lineWidth: 0.9)
            )
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.28), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .clipShape(shape)
            )
    }

    private var statusDot: some View {
        Circle()
            .fill(isStatusOnline ? Color.white : Color.clear)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.95), lineWidth: 1.4)
            )
            .frame(width: 8, height: 8)
            .shadow(color: Color.white.opacity(isStatusOnline ? 0.35 : 0.0), radius: 4, x: 0, y: 0)
    }

    @ViewBuilder
    private func activeRunStatusChip(_ run: ActiveRunStatus) -> some View {
        let isCancelArmed = armedCancelRunId == run.id
        let statusLabel: String = {
            let percentValue = Int(round(min(1.0, max(0.0, run.progress)) * 100.0))
            switch run.kind {
            case .automation, .transition:
                if run.title == "Loading..." {
                    return "Loading..."
                } else if run.expectedEnd != nil || run.progress > 0 {
                    return "\(run.title) \(percentValue)%"
                } else {
                    return "Running: \(run.title)"
                }
            case .effect:
                return "Effect: \(run.title)"
            case .applying:
                return "Applying: \(run.title)"
            }
        }()
        let confirmCancel = {
            armedCancelRunId = nil
            Task {
                await viewModel.cancelActiveRun(
                    for: activeDevice,
                    releaseRealtimeOverride: false,
                    force: false,
                    endReason: .cancelledByManualInput
                )
            }
        }
        let armCancel = {
            armedCancelRunId = run.id
            let runId = run.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if armedCancelRunId == runId {
                    armedCancelRunId = nil
                }
            }
        }

        Group {
            if run.isCancellable && isCancelArmed {
                ZStack {
                    Text(statusLabel)
                        .opacity(0)
                    Text("CANCEL")
                        .font(DeviceDetailDockTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(detailForegroundColor)
                        .transition(.opacity)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: run.kind == .transition ? "arrow.triangle.2.circlepath" : "waveform.path.ecg")
                        .font(DeviceDetailDockTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(detailSecondaryForegroundColor)

                    Text(statusLabel)
                        .font(DeviceDetailDockTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(detailSecondaryForegroundColor)
                        .lineLimit(1)

                    if run.isCancellable {
                        Button(action: armCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(DeviceDetailDockTypography.style(.caption2))
                                .foregroundColor(detailSecondaryForegroundColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isCancelArmed)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .contentShape(Capsule())
        .onTapGesture {
            guard run.isCancellable, isCancelArmed else { return }
            confirmCancel()
        }
    }

    private var powerButtonContent: some View {
        ZStack {
            Image(systemName: "power")
                .font(DeviceDetailDockTypography.style(.title3))
                .foregroundColor(detailForegroundColor)
                .opacity(isToggling ? 0.7 : 1.0)

            if isToggling {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .frame(width: 44, height: 44)
        .background(currentPowerState ? detailPowerActiveBackground : detailPowerInactiveBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(detailForegroundColor.opacity(currentPowerState ? 0 : 0.3), lineWidth: 1)
        )
    }

    private var largePowerButtonContent: some View {
        ZStack {
            Image(systemName: "power")
                .font(DeviceDetailDockTypography.style(.title2, weight: .semibold))
                .foregroundColor(detailForegroundColor)
                .opacity(isToggling ? 0.65 : 1)

            if isToggling {
                ProgressView()
                    .scaleEffect(0.82)
            }
        }
        .frame(width: 58, height: 58)
        .background(currentPowerState ? detailPowerActiveBackground : detailPowerInactiveBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(detailForegroundColor.opacity(currentPowerState ? 0 : 0.24), lineWidth: 1)
        )
    }

    private var compactPowerButtonContent: some View {
        ZStack {
            Image(systemName: "power")
                .font(DeviceDetailDockTypography.style(.headline, weight: .semibold))
                .foregroundColor(detailForegroundColor)
                .opacity(isToggling ? 0.65 : 1)

            if isToggling {
                ProgressView()
                    .scaleEffect(0.68)
            }
        }
        .frame(width: 44, height: 44)
        .background(currentPowerState ? detailPowerActiveBackground : detailPowerInactiveBackground)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(detailForegroundColor.opacity(currentPowerState ? 0 : 0.24), lineWidth: 1)
        )
    }

    private func togglePower() {
        let targetState = !currentPowerState
        viewModel.setUIOptimisticState(deviceId: activeDevice.id, isOn: targetState)
        if !activeDevice.isOnline {
            viewModel.markDeviceOnline(activeDevice.id)
        }
        isToggling = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await viewModel.toggleDevicePower(activeDevice)
            await MainActor.run { isToggling = false }
        }
    }

    private func syncQuickBrightnessIfNeeded() {
        guard !isAdjustingQuickBrightness else { return }
        quickBrightness = effectiveBrightnessValue
    }

    private func commitQuickBrightness() {
        let targetBrightness = Int(min(255, max(1, quickBrightnessDisplayValue)).rounded())
        quickBrightness = Double(targetBrightness)
        Task {
            await viewModel.updateDeviceBrightness(activeDevice, brightness: targetBrightness)
        }
    }

    private var currentBrightnessValueForSaving: Int {
        Int(min(255, max(1, quickBrightnessDisplayValue)).rounded())
    }

    private var currentLightGradientForSaving: LEDGradient {
        let stops = viewModel.gradientStops(for: activeDevice.id) ?? [
            GradientStop(position: 0.0, hexColor: activeDevice.currentColor.toHex()),
            GradientStop(position: 1.0, hexColor: activeDevice.currentColor.toHex())
        ]
        return LEDGradient(stops: stops, interpolation: .linear)
    }

    private func saveLightColorPresetDirectly() async {
        guard !AutomationStore.shared.hasAnyDeletionInProgress else { return }
        let presetName = await MainActor.run {
            PresetDefaultNaming.colorName(existingNames: PresetsStore.shared.colorPresets.map(\.name))
        }
        let preset = ColorPreset(
            name: presetName,
            gradientStops: currentLightGradientForSaving.stops,
            gradientInterpolation: currentLightGradientForSaving.interpolation,
            brightness: currentBrightnessValueForSaving,
            temperature: nil,
            whiteLevel: nil
        )
        await saveLightColorPreset(preset)
    }

    private func saveLightColorPreset(_ presetInput: ColorPreset) async {
        guard !AutomationStore.shared.hasAnyDeletionInProgress else { return }
        await MainActor.run {
            isSavingColorPreset = true
            showSaveColorSuccess = false
        }
        var preset = presetInput

        do {
            let savedId = try await PresetSyncManager.shared.saveColorPreset(preset, to: activeDevice)
            await MainActor.run {
                var ids = preset.wledPresetIds ?? [:]
                ids[activeDevice.id] = savedId
                preset.wledPresetIds = ids
                preset.wledPresetId = savedId
                PresetsStore.shared.addColorPreset(preset)
                isSavingColorPreset = false
                showSaveColorSuccess = true
                saveColorFeedbackTrigger += 1
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showSaveColorSuccess = false
            }
        } catch {
            await MainActor.run {
                isSavingColorPreset = false
                showSaveColorSuccess = false
            }
        }
    }


    // MARK: - Tab Navigation Bar

    private var settingsModeHeader: some View {
        HStack(spacing: 10) {
            Button(action: settingsHeaderBackAction) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(DeviceDetailDockTypography.style(.caption, weight: .semibold))
                    Text(settingsHeaderChrome.backTitle)
                        .font(DeviceDetailDockTypography.style(.caption, weight: .semibold))
                }
                .foregroundColor(detailForegroundColor)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settingsHeaderChrome.backAccessibilityLabel)

            Spacer()

            Button(action: settingsHeaderAction) {
                Text(settingsHeaderChrome.headerTitle)
                    .font(DeviceDetailDockTypography.style(.caption, weight: .semibold))
                    .foregroundColor(settingsHeaderChrome.headerActionEnabled ? detailForegroundColor : detailSecondaryForegroundColor)
                    .padding(.horizontal, settingsHeaderChrome.headerActionEnabled ? 12 : 0)
                    .frame(height: settingsHeaderChrome.headerActionEnabled ? 38 : nil)
                    .background {
                        if settingsHeaderChrome.headerActionEnabled {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                )
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!settingsHeaderChrome.headerActionEnabled)
            .accessibilityLabel(settingsHeaderChrome.headerAccessibilityLabel)
        }
        .frame(minHeight: 48)
    }

    private func settingsHeaderBackAction() {
        if settingsHeaderChrome.backTitle == "Settings" {
            settingsHeaderActionStore.performBack()
        } else {
            closeSettingsMode()
        }
    }

    private func settingsHeaderAction() {
        guard settingsHeaderChrome.headerActionEnabled else { return }
        settingsHeaderActionStore.performPrimary()
    }

    private var embeddedSettingsContent: some View {
        ComprehensiveSettingsView(
            device: activeDevice,
            initialCategory: settingsInitialCategory,
            presentationMode: .embedded,
            contentBottomPadding: onClose == nil ? 20 : 152,
            onSettingsHeaderChromeChange: { chrome in
                settingsHeaderChrome = chrome
            },
            onSettingsHeaderActionsChange: { actions in
                settingsHeaderActionStore.update(actions)
            },
            onReconnectDevice: onReconnectDevice,
            onDeviceRemoved: onClose
        )
        .environmentObject(viewModel)
        .id(settingsInitialCategory)
    }

    private var tabNavigationBar: some View {
        HStack(spacing: 0) {
            ForEach(tabItems, id: \.title) { tabItem in
                let isLockedByEditor = showAddAutomation && tabItem.title != "Routines"
                let isSelected = selectedTab == tabItem.title
                Button(action: {
                    guard !isLockedByEditor else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tabItem.title
                    }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: tabItem.icon)
                            .font(.system(size: 17, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .frame(width: 24, height: 21)

                        Text(tabItem.title)
                            .font(.system(size: 10, weight: .regular))
                            .lineLimit(1)
                    }
                    .foregroundColor(
                        isSelected
                            ? detailForegroundColor
                            : (isLockedByEditor ? detailDisabledForegroundColor : detailSecondaryForegroundColor)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLockedByEditor)
                .accessibilityLabel(tabItem.title)
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityHint("Shows the \(tabItem.title.lowercased()) controls.")
            }
        }
        .frame(height: 48)
        .background(Color.clear)
    }

    private var tabItems: [(title: String, icon: String)] {
        [
            ("Light", "lamp.table"),
            ("Saves", "bookmark"),
            ("Routines", "clock"),
            ("Sync", "arrow.triangle.2.circlepath")
        ]
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "Light":
            colorsTabContent
        case "Saves":
            presetsTabContent
        case "Routines":
            automationTabContent
        case "Sync":
            syncTabContent
        default:
            EmptyView()
        }
    }

    private var embeddedAutomationEditor: some View {
        let deviceScenes = scenesStore.scenes.filter { activeDeviceIds.contains($0.deviceId) }
        let effectOptions = viewModel.colorSafeEffectOptions(for: activeDevice)
        let prefill = pendingAutomationTemplate.map {
            $0.prefill(for: AutomationTemplate.Context(
                device: activeDevice,
                availableDevices: viewModel.devices,
                defaultGradient: viewModel.automationGradient(for: activeDevice)
            ))
        }
        let allowSceneAction = {
            guard let editing = editingAutomation else { return false }
            if case .scene = editing.action {
                return true
            }
            return false
        }()

        return AddAutomationDialog(
            device: activeDevice,
            scenes: deviceScenes,
            effectOptions: effectOptions,
            availableDevices: viewModel.devices,
            viewModel: viewModel,
            defaultName: automationEditorDefaultName,
            editingAutomation: editingAutomation,
            templatePrefill: prefill,
            allowSceneAction: allowSceneAction,
            presentationStyle: .embedded,
            onCancel: closeAutomationEditor
        ) { automation in
            let saved: Bool
            if editingAutomation != nil {
                saved = automationStore.update(automation)
            } else {
                saved = automationStore.add(automation)
            }
            if saved {
                editingAutomation = nil
                automationEditorDefaultName = nil
                pendingAutomationTemplate = nil
            }
            return saved
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var colorsTabContent: some View {
        VStack(spacing: 16) {
            primaryControlSection

            // Segment Picker (only show for multi-segment devices)
            if advancedUIEnabled,
               showSegmentControlsInColorTabAdvanced,
               viewModel.hasMultipleSegments(for: activeDevice) {
                segmentPicker
            }

            // Transition Section
            transitionSection

            // Effects Section
            effectsSection
        }
        .onAppear {
            resetAnimationModesIfNeeded()
        }
    }

    private var effectiveSegmentId: Int {
        if advancedUIEnabled {
            return selectedSegmentId
        }
        return viewModel.preferredSegmentId(for: activeDevice)
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Segment")
                    .font(DeviceDetailDockTypography.style(.caption))
                    .foregroundColor(detailSecondaryForegroundColor)
                Spacer()
            }

            // Segmented control for segment selection
            Picker("Segment", selection: $selectedSegmentId) {
                ForEach(0..<viewModel.getSegmentCount(for: activeDevice), id: \.self) { segmentId in
                    Text("Seg \(segmentId + 1)")
                        .tag(segmentId)
                }
            }
            .pickerStyle(.segmented)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .accessibilityLabel("Segment selector")
            .accessibilityValue("Segment \(selectedSegmentId + 1)")
            .accessibilityHint("Selects which LED segment you are editing.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .settingsDetailControlBackground()
    }

    private var presetsTabContent: some View {
        PresetsListView(
            device: activeDevice,
            onOpenIntegrations: { openSettings(.integrations) }
        )
            .environmentObject(viewModel)
    }

    private var automationTabContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            automationShortcutsSection
            automationsHeader

            if deviceAutomations.isEmpty {
                automationEmptyState
            } else {
                VStack(spacing: 14) {
                    ForEach(deviceAutomations, id: \.id) { (automation: Automation) in
                        let runStatus = activeAutomationRunStatus(for: automation)
                        let isDeleting = automationStore.isDeletionInProgress(for: automation.id)
                        AutomationRow(
                            automation: automation,
                            scenes: scenesStore.scenes,
                            isNext: nextAutomationID == automation.id,
                            isDeleting: isDeleting,
                            isDeleteDisabled: isDeleting,
                            deletionProgress: automationStore.deletionProgress(for: automation.id),
                            isRunning: runStatus != nil,
                            runningProgress: runStatus?.progress,
                            usesDetailSecondaryContainer: true,
                            displayNoun: "routine",
                            onToggle: { enabled in
                                var updated = automation
                                updated.enabled = enabled
                                automationStore.update(updated)
                            },
                            onRun: {
                                automationStore.applyAutomation(automation)
                            },
                            onEdit: {
                                editAutomation(automation)
                            },
                            onShortcutToggle: { pinned in
                                toggleAutomationShortcut(automation, pinned: pinned)
                            },
                            onRetrySync: {
                                automationStore.retryRoutine(id: automation.id)
                            },
                            onDelete: {
                                automationPendingDelete = automation
                            }
                        )
                        .id(automation.id) // Explicit ID for proper view updates
                    }
                }
            }
        }
    }

    private var automationShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts")
                    .font(DeviceDetailTypography.sectionTitle)
                    .foregroundColor(detailForegroundColor)
                if !shortcutAutomations.isEmpty {
                    Text("\(shortcutAutomations.count)")
                        .font(DeviceDetailDockTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(detailSecondaryForegroundColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                )
                        )
                }
                Spacer()
                Menu {
                    if shortcutMenuAutomations.isEmpty {
                        Text("No user routines available")
                    } else {
                        ForEach(shortcutMenuAutomations, id: \.id) { automation in
                            Button(automation.name) {
                                toggleAutomationShortcut(automation, pinned: true)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(DeviceDetailDockTypography.style(.caption, weight: .bold))
                        .foregroundColor(
                            isAutomationMutationLocked || shortcutMenuAutomations.isEmpty
                                ? detailDisabledForegroundColor
                                : detailForegroundColor
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                )
                        )
                }
                .disabled(isAutomationMutationLocked || shortcutMenuAutomations.isEmpty)
                .accessibilityLabel("Add shortcut")
            }

            if shortcutAutomations.isEmpty {
                Text("Pin routines with the heart icon for quick toggles.")
                    .font(DeviceDetailDockTypography.style(.caption, weight: .medium))
                    .foregroundColor(detailTertiaryForegroundColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .settingsDetailControlBackground(cornerRadius: 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shortcutAutomations) { automation in
                            ShortcutAutomationChip(
                                automation: automation,
                                isNext: nextAutomationID == automation.id,
                                actionDescription: shortcutActionDescription(for: automation),
                                onTap: { toggleAutomationEnabled(automation) },
                                onLongPress: { editAutomation(automation) }
                            )
                            .id(automation.id) // Explicit ID for proper view updates
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private var automationsHeader: some View {
        HStack(alignment: .center) {
            Text("Routines")
                .font(DeviceDetailTypography.sectionTitle)
                .foregroundColor(detailForegroundColor)
            Spacer()
            Button {
                startAutomationCreation()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(DeviceDetailDockTypography.style(.title3, weight: .semibold))
                    .foregroundStyle(
                        isAutomationMutationLocked ? detailDisabledForegroundColor : detailForegroundColor,
                        isAutomationMutationLocked ? detailDisabledForegroundColor : detailSecondaryForegroundColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(isAutomationMutationLocked)
            .accessibilityLabel("Add routine")
        }
        .padding(.top, 6)
    }

    private var automationEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(DeviceDetailDockTypography.style(.title2, weight: .light))
                .foregroundColor(detailSecondaryForegroundColor)
            Text("No routines for this device yet.")
                .font(DeviceDetailTypography.cardTitle)
                .foregroundColor(detailForegroundColor)
            Text("Create a shortcut to wake up with sunrise colors or wind down at night.")
                .font(DeviceDetailDockTypography.style(.footnote))
                .foregroundColor(detailTertiaryForegroundColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .settingsDetailControlBackground(cornerRadius: 22)
    }

    private var deviceAutomations: [Automation] {
        automationStore.automations.filter { automation in
            automation.targets.deviceIds.contains(where: activeDeviceIds.contains)
        }
    }

    private var shortcutAutomations: [Automation] {
        let pinned = deviceAutomations.filter { $0.metadata.pinnedToShortcuts ?? false }
        guard let nextId = nextAutomationID else { return pinned }

        return pinned.sorted { lhs, rhs in
            let lhsIsNext = lhs.id == nextId
            let rhsIsNext = rhs.id == nextId
            if lhsIsNext != rhsIsNext {
                return lhsIsNext
            }

            let lhsDate = lhs.lastTriggered ?? lhs.updatedAt
            let rhsDate = rhs.lastTriggered ?? rhs.updatedAt
            return lhsDate > rhsDate
        }
    }

    private var shortcutMenuAutomations: [Automation] {
        deviceAutomations
            .filter { !($0.metadata.pinnedToShortcuts ?? false) }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var upcomingAutomation: (automation: Automation, date: Date?)? {
        if let scheduled = automationStore.upcomingAutomationInfo,
           scheduled.automation.targets.deviceIds.contains(where: activeDeviceIds.contains) {
            return (scheduled.automation, scheduled.date)
        }
        if let dated = deviceAutomations.compactMap({ automation -> (Automation, Date)? in
            guard let next = automation.nextTriggerDate() else { return nil }
            return (automation, next)
        }).sorted(by: { $0.1 < $1.1 }).first {
            return (dated.0, dated.1)
        }
        if let solar = deviceAutomations.first(where: { automation in
            switch automation.trigger {
            case .sunrise, .sunset:
                return true
            default:
                return false
            }
        }) {
            return (solar, nil)
        }
        return nil
    }

    private func infoDescription(for info: (automation: Automation, date: Date?)) -> String {
        if let date = info.date {
            return "\(info.automation.trigger.displayName) · \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "\(info.automation.trigger.displayName) · next event"
    }

    private var nextAutomationID: UUID? {
        upcomingAutomation?.automation.id
    }

    private func activeAutomationRunStatus(for automation: Automation) -> ActiveRunStatus? {
        guard let status = viewModel.activeRunStatus[activeDevice.id] else { return nil }
        guard status.kind == .automation, status.title == automation.name else { return nil }
        return status
    }

    private func startRename() {
        showEditDeviceInfo = true
    }

    private var defaultAutomationName: String {
        AutomationDefaultNaming.defaultName(for: automationStore.automations)
    }

    private func automation(from prefill: AutomationTemplate.Prefill, templateName: String, context: AutomationTemplate.Context) -> Automation? {
        guard let trigger = buildTrigger(from: prefill.trigger),
              let action = buildAction(from: prefill.action, context: context) else {
            return nil
        }
        var metadata = prefill.metadata ?? AutomationMetadata()
        let targetIds = prefill.targetDeviceIds?.isEmpty == false ? prefill.targetDeviceIds! : [context.device.id]
        let targets = AutomationTargets(
            deviceIds: targetIds,
            syncGroupName: nil,
            allowPartialFailure: prefill.allowPartialFailure ?? true
        )
        let name: String
        if metadata.templateId != nil {
            name = templateName
        } else {
            name = prefill.name ?? templateName
        }
        if metadata.notes == nil {
            metadata.notes = context.device.name
        }
        return Automation(
            name: name,
            trigger: trigger,
            action: action,
            targets: targets,
            metadata: metadata
        )
    }

    private func buildTrigger(from prefillTrigger: AutomationTemplate.Prefill.Trigger) -> AutomationTrigger? {
        switch prefillTrigger {
        case .time(let hour, let minute, let weekdays):
            var selectedWeekdays = weekdays ?? Array(repeating: true, count: 7)
            if selectedWeekdays.count != 7 {
                selectedWeekdays = Array(repeating: true, count: 7)
            }
            let timeString = String(format: "%02d:%02d", hour, minute)
            let trigger = TimeTrigger(time: timeString, weekdays: selectedWeekdays)
            return .specificTime(trigger)
        case .sunrise(let offsetMinutes):
            let trigger = SolarTrigger(offset: .minutes(offsetMinutes), location: .followDevice)
            return .sunrise(trigger)
        case .sunset(let offsetMinutes):
            let trigger = SolarTrigger(offset: .minutes(offsetMinutes), location: .followDevice)
            return .sunset(trigger)
        }
    }

    private func buildAction(from prefillAction: AutomationTemplate.Prefill.Action, context: AutomationTemplate.Context) -> AutomationAction? {
        switch prefillAction {
        case .gradient(let gradient, let brightness, let fadeDuration):
            let resolvedGradient = gradient ?? context.defaultGradient
            return .gradient(
                GradientActionPayload(
                    gradient: resolvedGradient,
                    brightness: brightness,
                    durationSeconds: fadeDuration,
                    shouldLoop: false
                )
            )
        case .transition(let payload, _, _):
            return .transition(payload)
        case .effect(let effectId, let brightness, let gradient, let speed, let intensity):
            return .effect(
                EffectActionPayload(
                    effectId: effectId,
                    effectName: nil,
                    gradient: gradient ?? context.defaultGradient,
                    speed: speed,
                    intensity: intensity,
                    paletteId: nil,
                    brightness: brightness
                )
            )
        }
    }

    private func toggleAutomationEnabled(_ automation: Automation) {
        var updated = automation
        updated.enabled.toggle()
        automationStore.update(updated)
    }

    private func toggleAutomationShortcut(_ automation: Automation, pinned: Bool) {
        var updated = automation
        var metadata = automation.metadata
        metadata.pinnedToShortcuts = pinned
        updated.metadata = metadata
        automationStore.update(updated, syncOnDevice: false)
    }

    private func shortcutActionDescription(for automation: Automation) -> String {
        switch automation.action {
        case .scene(let payload):
            let sceneName = payload.sceneName
                ?? scenesStore.scenes.first(where: { $0.id == payload.sceneId })?.name
                ?? "Scene"
            return "Scene · \(sceneName)"
        case .preset(let payload):
            return payload.paletteName ?? "Saved color"
        case .playlist(let payload):
            let playlistName = payload.playlistName ?? "Playlist #\(payload.playlistId)"
            return "Playlist · \(playlistName)"
        case .gradient(let payload):
            return payload.powerOn ? "Color · \(automation.summary)" : "Power · Off"
        case .transition:
            let summary = automation.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.lowercased().hasPrefix("transition") {
                return summary
            }
            return "Transition · \(summary)"
        case .effect(let payload):
            return "Animation · \(payload.effectName ?? "Effect \(payload.effectId)")"
        case .directState:
            return "Custom state"
        }
    }

    private func startAutomationCreation(using template: AutomationTemplate? = nil) {
        guard !isAutomationMutationLocked else { return }
        selectedTab = "Routines"
        pendingAutomationTemplate = template
        editingAutomation = nil
        automationEditorDefaultName = template?.name ?? defaultAutomationName
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showAddAutomation = true
        }
    }

    private func editAutomation(_ automation: Automation) {
        guard !isAutomationMutationLocked else { return }
        selectedTab = "Routines"
        editingAutomation = automation
        automationEditorDefaultName = automation.name
        pendingAutomationTemplate = nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showAddAutomation = true
        }
    }

    private func closeAutomationEditor() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showAddAutomation = false
        }
        pendingAutomationTemplate = nil
        editingAutomation = nil
        automationEditorDefaultName = nil
    }

    private var automationEditorIdentity: String {
        if let editingAutomation {
            return "edit-\(editingAutomation.id.uuidString)"
        }
        if let pendingAutomationTemplate {
            return "template-\(pendingAutomationTemplate.id)-\(activeDevice.id)"
        }
        return "create-\(activeDevice.id)"
    }

    private var syncTargetDevices: [WLEDDevice] {
        viewModel.devices
            .filter { $0.id != activeDevice.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var syncTargetCount: Int {
        viewModel.syncTargetCount(for: activeDevice.id)
    }

    private var syncStatusLine: String {
        if syncTargetCount == 0 {
            return "Select devices for live sync."
        }
        return "Live-syncing to \(syncTargetCount) device\(syncTargetCount == 1 ? "" : "s")"
    }

    private var syncTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live Sync Targets")
                    .font(DeviceDetailTypography.sectionTitle)
                    .foregroundColor(detailForegroundColor)
                Spacer()
                Text(syncStatusLine)
                    .font(DeviceDetailDockTypography.style(.caption))
                    .foregroundColor(detailSecondaryForegroundColor)
            }

            Text("Mirrors live color, brightness, effect, and transition actions. Saved presets, playlists, routines, and WLED settings stay device-specific.")
                .font(DeviceDetailDockTypography.style(.caption2))
                .foregroundColor(detailTertiaryForegroundColor)
                .fixedSize(horizontal: false, vertical: true)

            if syncTargetDevices.isEmpty {
                Text("No other devices available. Add more devices to sync.")
                    .font(DeviceDetailDockTypography.style(.footnote))
                    .foregroundColor(detailSecondaryForegroundColor)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 10)], spacing: 10) {
                    ForEach(syncTargetDevices) { target in
                        let isSelected = viewModel.isSyncTargetSelected(sourceId: activeDevice.id, targetId: target.id)
                        Button {
                            viewModel.toggleSyncTarget(sourceId: activeDevice.id, targetId: target.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(target.isOnline ? Color.white : Color.clear)
                                        .overlay(
                                            Circle()
                                                .stroke((isSelected ? Color.black : Color.white).opacity(0.82), lineWidth: 1)
                                        )
                                        .frame(width: 6, height: 6)
                                    Text(target.name)
                                        .font(DeviceDetailDockTypography.style(.caption, weight: .semibold))
                                        .foregroundColor(detailForegroundColor)
                                        .lineLimit(1)
                                }

                                HStack(spacing: 4) {
                                    capabilityChip("RGB", enabled: viewModel.supportsRGB(for: target))
                                    capabilityChip("W", enabled: viewModel.supportsWhite(for: target))
                                    capabilityChip("CCT", enabled: viewModel.supportsCCT(for: target))
                                }

                                Text("Seg \(viewModel.getSegmentCount(for: target))")
                                    .font(DeviceDetailDockTypography.style(.caption2))
                                    .foregroundColor(isSelected ? detailSecondaryForegroundColor : detailTertiaryForegroundColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(SettingsDetailControlBackground(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isSelected ? detailForegroundColor.opacity(0.28) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                if advancedUIEnabled {
                    Button {
                        Task { await viewModel.copyNowFromSource(activeDevice) }
                    } label: {
                            Label("Copy Now", systemImage: "doc.on.doc")
                                .font(DeviceDetailDockTypography.style(.caption, weight: .semibold))
                                .foregroundColor(syncTargetCount == 0 ? detailDisabledForegroundColor : detailForegroundColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(syncTargetCount == 0)
                }

                Spacer()

                Button(role: .destructive) {
                    viewModel.clearSyncTargets(sourceId: activeDevice.id)
                } label: {
                    Label("Stop Sync", systemImage: "xmark.circle")
                        .font(DeviceDetailDockTypography.style(.caption, weight: .semibold))
                        .foregroundColor(syncTargetCount == 0 ? detailDisabledForegroundColor : detailForegroundColor)
                }
                .buttonStyle(.plain)
                .disabled(syncTargetCount == 0)
            }

            if let summary = viewModel.syncDispatchMessage(for: activeDevice.id), syncTargetCount > 0 {
                Text(summary)
                    .font(DeviceDetailDockTypography.style(.caption2))
                    .foregroundColor(detailSecondaryForegroundColor)
            }

            if advancedUIEnabled {
                nativeWLEDSyncSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: advancedUIEnabled) {
            if advancedUIEnabled {
                await loadUDPSyncState()
            }
        }
    }

    @ViewBuilder
    private func capabilityChip(_ title: String, enabled: Bool) -> some View {
        Text(title)
            .font(DeviceDetailDockTypography.style(.caption2, weight: .semibold))
            .foregroundColor(enabled ? detailForegroundColor : detailDisabledForegroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.17 : 0.05))
            )
    }

    private var nativeWLEDSyncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Native WLED Sync")
                .font(DeviceDetailTypography.cardTitle)
                .foregroundColor(detailForegroundColor)

            HStack {
                Text("Send UDP Sync")
                    .foregroundColor(detailForegroundColor)
                Spacer()
                Toggle("", isOn: $udpnSend)
                    .labelsHidden()
                    .onChange(of: udpnSend) { _, newValue in
                        guard !suppressUDPNUpdates else { return }
                        Task {
                            await viewModel.setUDPSync(activeDevice, send: newValue, recv: nil)
                        }
                    }
            }

            HStack {
                Text("Receive UDP Sync")
                    .foregroundColor(detailForegroundColor)
                Spacer()
                Toggle("", isOn: $udpnReceive)
                    .labelsHidden()
                    .onChange(of: udpnReceive) { _, newValue in
                        guard !suppressUDPNUpdates else { return }
                        Task {
                            await viewModel.setUDPSync(activeDevice, send: nil, recv: newValue)
                        }
                    }
            }

            Button {
                if let url = URL(string: "http://\(activeDevice.ipAddress)/settings/sync") {
                    openURL(url)
                }
            } label: {
                Label("Open Full Sync Settings", systemImage: "arrow.up.right.square")
                    .font(DeviceDetailDockTypography.style(.caption, weight: .medium))
                    .foregroundColor(detailForegroundColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .settingsDetailControlBackground(cornerRadius: 14)
    }

    private func loadUDPSyncState() async {
        guard let state = await viewModel.fetchUDPSyncState(for: activeDevice) else { return }
        await MainActor.run {
            suppressUDPNUpdates = true
            udpnSend = state.send
            udpnReceive = state.recv
            DispatchQueue.main.async {
                suppressUDPNUpdates = false
            }
        }
    }

    private func resetAnimationModesIfNeeded() {
        guard !didResetAnimationModes else { return }
        didResetAnimationModes = true
        // UI-only reset on first Colors tab appearance. Do not send device commands here:
        // tab switches/appear should never cancel active playlists/transitions/effects.
        let transitionActive = viewModel.activeRunStatus[activeDevice.id]?.kind == .transition
        let transitionSaveInFlight = viewModel.transitionDraftSession(for: activeDevice.id)?.isSavingPreset == true
        isTransitionPaneExpanded = transitionActive || transitionSaveInFlight
        isEffectsPaneExpanded = false
        #if DEBUG
        print("colors_tab.on_appear ui_only")
        #endif
    }

    // MARK: - Colors Tab Helper Views

    private var gradientAEditor: some View {
        UnifiedColorPane(device: activeDevice, dismissColorPicker: $dismissColorPicker, segmentId: effectiveSegmentId)
            .environmentObject(viewModel)
    }

    private var effectsSection: some View {
        EffectsPane(
            device: activeDevice,
            segmentId: effectiveSegmentId,
            isExpanded: $isEffectsPaneExpanded,
            onActivate: {
                if !isEffectsPaneExpanded {
                    isEffectsPaneExpanded = true
                }
                if isTransitionPaneExpanded {
                    isTransitionPaneExpanded = false
                }
            }
        )
        .environmentObject(viewModel)
    }

    private var transitionSection: some View {
        TransitionPane(
            device: activeDevice,
            dismissColorPicker: $dismissColorPicker,
            isExpanded: $isTransitionPaneExpanded,
            onActivate: {
                if !isTransitionPaneExpanded {
                    isTransitionPaneExpanded = true
                }
                if isEffectsPaneExpanded {
                    isEffectsPaneExpanded = false
                }
            }
        )
        .environmentObject(viewModel)
    }

}

private struct DeviceDetailPresentationModifier: ViewModifier {
    let isRunningInPreview: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRunningInPreview {
            content
                .navigationBarHidden(true)
        } else {
            content
                .presentationDetents([.fraction(0.86)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(40)
                .presentationBackground(.clear)
                .navigationBarHidden(true)
        }
    }
}

@MainActor
private final class DeviceDetailAutomationStoreBridge: ObservableObject {
    @Published private(set) var automations: [Automation] = []
    @Published private(set) var upcomingAutomationInfo: (automation: Automation, date: Date)?
    @Published private(set) var deletingAutomationIds: Set<UUID> = []
    @Published private(set) var deletionProgressByAutomationId: [UUID: AutomationDeletionProgress] = [:]

    private var cancellables = Set<AnyCancellable>()
    private let isRunningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    init() {
        guard !isRunningInPreview else { return }

        let store = AutomationStore.shared
        automations = store.automations
        upcomingAutomationInfo = store.upcomingAutomationInfo
        deletingAutomationIds = store.deletingAutomationIds
        deletionProgressByAutomationId = store.deletionProgressByAutomationId

        store.$automations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automations = $0 }
            .store(in: &cancellables)

        store.$upcomingAutomationInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.upcomingAutomationInfo = $0 }
            .store(in: &cancellables)

        store.$deletingAutomationIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.deletingAutomationIds = $0 }
            .store(in: &cancellables)

        store.$deletionProgressByAutomationId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.deletionProgressByAutomationId = $0 }
            .store(in: &cancellables)
    }

    func add(_ automation: Automation) -> Bool {
        guard !isRunningInPreview else { return false }
        return AutomationStore.shared.add(automation)
    }

    @discardableResult
    func update(_ automation: Automation, syncOnDevice: Bool = true) -> Bool {
        guard !isRunningInPreview else { return false }
        return AutomationStore.shared.update(automation, syncOnDevice: syncOnDevice)
    }

    func delete(id: UUID) {
        guard !isRunningInPreview else { return }
        AutomationStore.shared.delete(id: id)
    }

    func applyAutomation(_ automation: Automation) {
        guard !isRunningInPreview else { return }
        AutomationStore.shared.applyAutomation(automation)
    }

    func retryOnDeviceSync(for automationId: UUID) {
        guard !isRunningInPreview else { return }
        AutomationStore.shared.retryOnDeviceSync(for: automationId)
    }

    func retryRoutine(id automationId: UUID) {
        guard !isRunningInPreview else { return }
        AutomationStore.shared.retryRoutine(id: automationId)
    }

    func isDeletionInProgress(for id: UUID) -> Bool {
        deletingAutomationIds.contains(id)
    }

    func deletionProgress(for id: UUID) -> AutomationDeletionProgress? {
        deletionProgressByAutomationId[id]
    }

    var hasAnyDeletionInProgress: Bool {
        AutomationStore.shared.hasAnyDeletionInProgress
    }

    func hasOnDeviceSyncInProgress(for deviceIds: Set<String>) -> Bool {
        AutomationStore.shared.hasOnDeviceSyncInProgress(for: deviceIds)
    }
}

#if DEBUG
struct DeviceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceDetailView(
            device: previewDevice,
            viewModel: previewViewModel,
            initialTab: "Presets"
        )
        .preferredColorScheme(.dark)
    }

    @MainActor
    private static var previewViewModel: DeviceControlViewModel {
        let viewModel = DeviceControlViewModel.shared
        viewModel.devices = [previewDevice]
        viewModel.dismissError()
        return viewModel
    }

    private static var previewDevice: WLEDDevice {
        WLEDDevice(
            id: "preview-device-1",
            name: "Living Room Lamp",
            ipAddress: "192.168.1.120",
            isOnline: true,
            brightness: 180,
            currentColor: Color(red: 1.0, green: 0.62, blue: 0.12),
            location: .livingRoom,
            state: WLEDState(
                brightness: 180,
                isOn: true,
                segments: [
                    Segment(
                        id: 0,
                        start: 0,
                        stop: 60,
                        len: 60,
                        on: true,
                        bri: 180,
                        colors: [[255, 160, 0], [255, 60, 0], [255, 20, 0]],
                        cct: 128,
                        fx: 0,
                        sx: 128,
                        ix: 128,
                        pal: 0,
                        sel: true
                    )
                ],
                transitionDeciseconds: 7,
                presetId: nil,
                playlistId: nil,
                mainSegment: 0
            )
        )
    }
}
#endif

private struct ShortcutAutomationChip: View {
    let automation: Automation
    let isNext: Bool
    let actionDescription: String
    var onTap: () -> Void
    var onLongPress: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var detailForegroundColor: Color {
        AppTheme.deviceDetailText(.primary, for: colorScheme)
    }

    private var detailSecondaryForegroundColor: Color {
        AppTheme.deviceDetailText(.secondary, for: colorScheme)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(automation.name)
                    .font(DeviceDetailDockTypography.style(.caption, weight: .semibold))
                    .foregroundColor(detailForegroundColor)
                    .lineLimit(1)

                Text(actionDescription)
                    .font(DeviceDetailDockTypography.style(.caption2, weight: .medium))
                    .foregroundColor(detailSecondaryForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.trailing, 40)
            }
            .frame(width: 168, height: 38, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .settingsDetailControlBackground(cornerRadius: 16)
            .overlay(alignment: .bottomTrailing) {
                if isNext {
                    nextBadge
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                onLongPress()
            }
        )
        .accessibilityLabel("\(automation.name) shortcut")
        .accessibilityHint("Tap to \(automation.enabled ? "disable" : "enable"). Long press to edit.")
    }

    private var nextBadge: some View {
        Text("Next")
            .font(DeviceDetailDockTypography.style(.caption2, weight: .medium))
            .foregroundColor(detailForegroundColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}
