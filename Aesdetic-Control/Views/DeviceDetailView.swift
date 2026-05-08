import SwiftUI
import Combine

enum DeviceDetailBackgroundStyle {
    case frosted
    case liquidGlass
}

struct DeviceDetailView: View {
    let device: WLEDDevice
    private let backgroundStyle: DeviceDetailBackgroundStyle
    private let containerCornerRadius: CGFloat
    private let presentationProgress: CGFloat
    private let onClose: (() -> Void)?
    @ObservedObject var viewModel: DeviceControlViewModel
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: String = "Light"
    
    // State variables for new features
    @State private var showSettings: Bool = false
    @State private var settingsInitialCategory: ComprehensiveSettingsView.SettingsCategory = .overview
    @State private var showProductSetup: Bool = false
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
    @State private var showSaveColorPresetDialog: Bool = false
    @State private var dismissColorPicker: Bool = false
    @State private var selectedSegmentId: Int = 0  // Track selected segment for multi-segment devices
    @State private var presetRenameContext: PresetRenameContext?
    @State private var presetRenameEditedName: String = ""
    @FocusState private var isPresetRenameFieldFocused: Bool
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

    init(
        device: WLEDDevice,
        viewModel: DeviceControlViewModel,
        initialTab: String = "Light",
        backgroundStyle: DeviceDetailBackgroundStyle = .frosted,
        containerCornerRadius: CGFloat = DeviceDetailPresentation.expandedCornerRadius,
        presentationProgress: CGFloat = 1,
        onClose: (() -> Void)? = nil
    ) {
        self.device = device
        self.backgroundStyle = backgroundStyle
        self.containerCornerRadius = containerCornerRadius
        self.presentationProgress = presentationProgress
        self.onClose = onClose
        self.viewModel = viewModel
        _selectedTab = State(initialValue: Self.normalizedTabName(initialTab))
    }

    private static func normalizedTabName(_ tab: String) -> String {
        switch tab {
        case "Colors":
            return "Light"
        case "Presets":
            return "Saves"
        case "Automation":
            return "Automations"
        default:
            return tab
        }
    }
    
    // Use coordinated power state from ViewModel
    private var currentPowerState: Bool {
        return viewModel.getCurrentPowerState(for: activeDevice.id)
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
            return "Playlist #\(playlistId)"
        }
        if let presetId = activeDevice.state?.presetId, presetId > 0 {
            return "Preset #\(presetId)"
        }
        return nil
    }

    private var currentModeLabel: String {
        if let run = viewModel.activeRunStatus[activeDevice.id] {
            return run.title
        }
        if let playlistId = activeDevice.state?.playlistId, playlistId > 0 {
            return "Playlist #\(playlistId)"
        }
        if let presetId = activeDevice.state?.presetId, presetId > 0 {
            return "Preset #\(presetId)"
        }
        return currentPowerState ? "Manual color" : "Standby"
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
        !automationStore.deletingAutomationIds.isEmpty
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
    }

    private var fullDetailBody: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                backgroundLayer
                contentLayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(detailContainerBackground)
                    .overlay(alignment: .bottom) {
                        detailDockFade
                    }
                    .clipShape(RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous))
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
                        if !showProductSetup {
                            showProductSetup = true
                        }
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
                if let renameContext = presetRenameContext {
                    GeometryReader { proxy in
                        let maxCardWidth = min(proxy.size.width - 48, 360)
                        ZStack {
                            Rectangle()
                                .fill(Color.black.opacity(0.08))
                                .background(.ultraThinMaterial)
                                .blur(radius: 2)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    cancelPresetRename()
                                }
                            EditPresetNamePopup(
                                currentName: renameContext.currentName,
                                editedName: $presetRenameEditedName,
                                isPresented: Binding(
                                    get: { presetRenameContext != nil },
                                    set: { isPresented in
                                        if !isPresented {
                                            cancelPresetRename()
                                        }
                                    }
                                ),
                                isTextFieldFocused: $isPresetRenameFieldFocused,
                                onSave: { newName in
                                    applyPresetRename(newName, for: renameContext)
                                },
                                onCancel: {
                                    cancelPresetRename()
                                }
                            )
                            .frame(maxWidth: maxCardWidth)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: presetRenameContext != nil)
                }
            }
            .overlay {
                if isRebootWaitActive {
                    rebootWaitOverlay
                }
            }
            .overlay {
                if showProductSetup {
                    productSetupOverlay
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
                if newValue == .pendingSelection && !showProductSetup {
                    showProductSetup = true
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
            .sheet(isPresented: $showAddAutomation, onDismiss: {
                pendingAutomationTemplate = nil
                editingAutomation = nil
                automationEditorDefaultName = nil
            }) {
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
                AddAutomationDialog(
                    device: activeDevice,
                    scenes: deviceScenes,
                    effectOptions: effectOptions,
                    availableDevices: viewModel.devices,
                    viewModel: viewModel,
                    defaultName: automationEditorDefaultName,
                    editingAutomation: editingAutomation,
                    templatePrefill: prefill,
                    allowSceneAction: allowSceneAction
                ) { automation in
                    let saved: Bool
                    if editingAutomation != nil {
                        automationStore.update(automation)
                        saved = true
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
            }
            .sheet(isPresented: $showEditDeviceInfo) {
                EditDeviceInfoDialog(device: activeDevice)
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    ComprehensiveSettingsView(device: activeDevice, initialCategory: settingsInitialCategory)
                        .environmentObject(viewModel)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.ultraThinMaterial)
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
                "Delete automation?",
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
                Text("Delete \"\(automation.name)\" from this device?")
            }
        }
    }
    
    private var backgroundLayer: some View {
        Color.clear
        .ignoresSafeArea()
    }

    private var detailContentOpacity: Double {
        guard onClose != nil else { return 1 }
        let normalized = (presentationProgress - 0.36) / 0.42
        return Double(min(1, max(0, normalized)))
    }

    private var detailContentOffset: CGFloat {
        guard onClose != nil else { return 0 }
        return (1 - min(1, max(0, presentationProgress))) * 18
    }
    
    private var contentLayer: some View {
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
                .padding(.horizontal, 16)
                .padding(.top, onClose == nil ? 20 : 10)
                .padding(.bottom, 10)
            
            tabNavigationBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 2)
            
            ScrollView {
                tabContent
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, onClose == nil ? 16 : 152)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(detailContentOpacity)
        .offset(y: detailContentOffset)
        .allowsHitTesting(detailContentOpacity > 0.82)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissColorPicker = true
        }
    }

    @ViewBuilder
    private var detailDockFade: some View {
        if onClose != nil {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.82),
                                .black
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.10),
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 156)
            .opacity(detailContentOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

    private var setupLockOverlay: some View {
        GeometryReader { proxy in
            let maxCardWidth = min(proxy.size.width - 56, 420)
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showProductSetup = true
                    }

                VStack(spacing: 12) {
                    Text("Setup Required")
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Complete setup to unlock device controls.")
                        .font(AppTypography.style(.subheadline))
                        .foregroundColor(.white.opacity(0.82))
                    AppGlassPillButton(
                        title: "Continue Setup",
                        isSelected: true,
                        iconName: "arrow.right",
                        size: .regular,
                        useControlGlassRecipe: true
                    ) {
                        showProductSetup = true
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

    @ViewBuilder
    private var productSetupOverlay: some View {
        GeometryReader { proxy in
            let maxPopupHeight = max(320, proxy.size.height - proxy.safeAreaInsets.bottom - 80)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .allowsHitTesting(!requiresProductSetup)
                    .onTapGesture {
                        if !requiresProductSetup {
                            showProductSetup = false
                        }
                    }

                ProductSetupFlowView(
                    device: activeDevice,
                    onClose: { self.showProductSetup = false },
                    allowsManualClose: !requiresProductSetup
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
        let isDeviceOnline = viewModel.isDeviceOnline(activeDevice) || isToggling
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeDevice.name)
                    .font(AppTypography.style(.title2, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(isDeviceOnline ? 1.0 : 0.58)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 8) {
                    statusDot
                        .opacity(isDeviceOnline ? 1.0 : 0.58)

                    Text(activeDevice.location.displayName)
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(isDeviceOnline ? 0.7 : 0.42))
                        .lineLimit(1)

                    if let activeRun = viewModel.activeRunStatus[activeDevice.id] {
                        activeRunStatusChip(activeRun)
                    }

                    if let activePresetLabel {
                        Text(activePresetLabel)
                            .font(AppTypography.style(.caption2, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.12))
                            )
                    }

                    if requiresProductSetup {
                        Text("Setup Required")
                            .font(AppTypography.style(.caption2, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.16))
                            )
                    }
                }
            }

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
                        .font(AppTypography.style(.subheadline, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Text("\(quickBrightnessPercent)%")
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .monospacedDigit()

                        Text("Brightness")
                            .font(AppTypography.style(.caption2, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
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
                .tint(currentPowerState ? Color.white : Color.white.opacity(0.45))
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .onAppear {
            syncQuickBrightnessIfNeeded()
        }
        .onChange(of: activeDevice.brightness) { _, _ in
            syncQuickBrightnessIfNeeded()
        }
    }

    private var saveColorPill: some View {
        Button(action: {
            if advancedUIEnabled {
                showSaveColorPresetDialog = true
            } else {
                Task {
                    await saveLightColorPresetDirectly()
                }
            }
        }) {
            HStack(spacing: 6) {
                if isSavingColorPreset {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                } else if showSaveColorSuccess {
                    Image(systemName: "checkmark.circle")
                        .font(AppTypography.style(.caption))
                } else {
                    Image(systemName: "plus.circle")
                        .font(AppTypography.style(.caption))
                }
                Text("Save Color")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
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
        .disabled(isSavingColorPreset || AutomationStore.shared.hasAnyDeletionInProgress)
        .opacity((isSavingColorPreset || AutomationStore.shared.hasAnyDeletionInProgress) ? 0.45 : 1.0)
        .accessibilityLabel("Save color")
    }

    private var deviceOptionsMenu: some View {
        Menu {
            Button(action: startRename) {
                Label("Rename Device", systemImage: "pencil")
            }
            Button(action: { openSettings(.overview) }) {
                Label("Settings", systemImage: "gearshape")
            }
            Button(action: { openSettings(.integrations) }) {
                Label("Integrations", systemImage: "link")
            }
            Button(action: { showProductSetup = true }) {
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
                .font(AppTypography.style(.headline, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.white.opacity(0.92))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
    }

    private func openSettings(_ category: ComprehensiveSettingsView.SettingsCategory) {
        settingsInitialCategory = category
        showSettings = true
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
        Color.clear
            .appLiquidGlass(role: .highContrast, cornerRadius: detailCardCornerRadius)
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
            .fill((viewModel.isDeviceOnline(activeDevice) || isToggling) ? Color.white : Color.clear)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.95), lineWidth: 1.4)
            )
            .frame(width: 8, height: 8)
            .shadow(color: Color.white.opacity((viewModel.isDeviceOnline(activeDevice) || isToggling) ? 0.35 : 0.0), radius: 4, x: 0, y: 0)
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
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .transition(.opacity)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: run.kind == .transition ? "arrow.triangle.2.circlepath" : "waveform.path.ecg")
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))

                    Text(statusLabel)
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)

                    if run.isCancellable {
                        Button(action: armCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.style(.caption2))
                                .foregroundColor(.white.opacity(0.7))
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
                .font(AppTypography.style(.title3))
                .foregroundColor(currentPowerState ? .black : .white)
                .opacity(isToggling ? 0.7 : 1.0)
            
            if isToggling {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .frame(width: 44, height: 44)
        .background(currentPowerState ? Color.white : Color.white.opacity(0.18))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(currentPowerState ? 0 : 0.3), lineWidth: 1)
        )
    }

    private var largePowerButtonContent: some View {
        ZStack {
            Image(systemName: "power")
                .font(AppTypography.style(.title2, weight: .semibold))
                .foregroundColor(currentPowerState ? .black : .white)
                .opacity(isToggling ? 0.65 : 1)

            if isToggling {
                ProgressView()
                    .scaleEffect(0.82)
            }
        }
        .frame(width: 58, height: 58)
        .background(currentPowerState ? Color.white : Color.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(currentPowerState ? 0 : 0.24), lineWidth: 1)
        )
    }

    private var compactPowerButtonContent: some View {
        ZStack {
            Image(systemName: "power")
                .font(AppTypography.style(.headline, weight: .semibold))
                .foregroundColor(currentPowerState ? .black : .white)
                .opacity(isToggling ? 0.65 : 1)

            if isToggling {
                ProgressView()
                    .scaleEffect(0.68)
            }
        }
        .frame(width: 44, height: 44)
        .background(currentPowerState ? Color.white : Color.white.opacity(0.16))
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(currentPowerState ? 0 : 0.24), lineWidth: 1)
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
        let preset = ColorPreset(
            name: "Color Preset \(Date().presetNameTimestamp())",
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
    
    private var tabNavigationBar: some View {
        HStack(spacing: 4) {
            ForEach(tabItems, id: \.title) { tabItem in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tabItem.title
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tabItem.icon)
                                .font(AppTypography.style(.title3, weight: .medium))
                                .foregroundColor(selectedTab == tabItem.title ? .white : .white.opacity(0.4))
                            
                            Text(tabItem.title)
                                .font(AppTypography.style(.caption, weight: .medium))
                                .foregroundColor(selectedTab == tabItem.title ? .white : .white.opacity(0.4))
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                .buttonStyle(.plain)
                .accessibilityLabel(tabItem.title)
                .accessibilityHint("Shows the \(tabItem.title.lowercased()) controls.")
            }
        }
        .padding(.bottom, 10)
        .background(Color.clear)
    }
    
    private var tabItems: [(title: String, icon: String)] {
        [
            ("Light", "sun.max"),
            ("Saves", "bookmark"),
            ("Automations", "clock"),
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
        case "Automations":
            automationTabContent
        case "Sync":
            syncTabContent
        default:
            EmptyView()
        }
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
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var presetsTabContent: some View {
        PresetsListView(
            device: activeDevice,
            onRequestRename: startPresetRename,
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
                            isDeleteDisabled: automationStore.hasAnyDeletionInProgress && !isDeleting,
                            deletionProgress: automationStore.deletionProgress(for: automation.id),
                            isRunning: runStatus != nil,
                            runningProgress: runStatus?.progress,
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
                                automationStore.retryOnDeviceSync(for: automation.id)
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
                    .font(AppTypography.style(.callout, weight: .semibold))
                    .foregroundColor(.white)
                if !shortcutAutomations.isEmpty {
                    Text("\(shortcutAutomations.count)")
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
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
                        Text("No user automations available")
                    } else {
                        ForEach(shortcutMenuAutomations, id: \.id) { automation in
                            Button(automation.name) {
                                toggleAutomationShortcut(automation, pinned: true)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
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
                .opacity((isAutomationMutationLocked || shortcutMenuAutomations.isEmpty) ? 0.45 : 1.0)
                .accessibilityLabel("Add shortcut")
            }
            
            if shortcutAutomations.isEmpty {
                Text("Pin automations with the heart icon for quick toggles.")
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(.white.opacity(0.70))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
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
            Text("Automations")
                .font(AppTypography.style(.callout, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                startAutomationCreation()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(AppTypography.style(.title3, weight: .semibold))
                    .foregroundStyle(Color.white, Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(isAutomationMutationLocked)
            .opacity(isAutomationMutationLocked ? 0.45 : 1.0)
            .accessibilityLabel("Add automation")
        }
        .padding(.top, 6)
    }
    
    private var automationEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(AppTypography.style(.title2, weight: .light))
                .foregroundColor(.white.opacity(0.7))
            Text("No automations for this device yet.")
                .font(AppTypography.style(.headline))
                .foregroundColor(.white)
            Text("Create a shortcut to wake up with sunrise colors or wind down at night.")
                .font(AppTypography.style(.footnote))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
        "Automation \(automationStore.automations.count + 1)"
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
            return "Preset · #\(payload.presetId)"
        case .playlist(let payload):
            let playlistName = payload.playlistName ?? "Playlist #\(payload.playlistId)"
            return "Playlist · \(playlistName)"
        case .gradient(let payload):
            return payload.powerOn ? "Color · \(automation.summary)" : "Power · Off"
        case .transition:
            return "Transition · \(automation.summary)"
        case .effect(let payload):
            return "Animation · \(payload.effectName ?? "Effect \(payload.effectId)")"
        case .directState:
            return "Custom state"
        }
    }
    
    private func startAutomationCreation(using template: AutomationTemplate? = nil) {
        guard !isAutomationMutationLocked else { return }
        pendingAutomationTemplate = template
        editingAutomation = nil
        automationEditorDefaultName = template?.name ?? defaultAutomationName
        showAddAutomation = true
    }
    
    private func editAutomation(_ automation: Automation) {
        editingAutomation = automation
        automationEditorDefaultName = automation.name
        pendingAutomationTemplate = nil
        showAddAutomation = true
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
                    .font(AppTypography.style(.callout, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(syncStatusLine)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
            }

            Text("Mirrors live color, brightness, effect, and transition actions. Saved presets, playlists, automations, and WLED settings stay device-specific.")
                .font(AppTypography.style(.caption2))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            if syncTargetDevices.isEmpty {
                Text("No other devices available. Add more devices to sync.")
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.7))
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
                                        .fill(target.isOnline ? Color.green : Color.orange)
                                        .frame(width: 6, height: 6)
                                    Text(target.name)
                                        .font(AppTypography.style(.caption, weight: .semibold))
                                        .foregroundColor(isSelected ? .black : .white)
                                        .lineLimit(1)
                                }

                                HStack(spacing: 4) {
                                    capabilityChip("RGB", enabled: viewModel.supportsRGB(for: target))
                                    capabilityChip("W", enabled: viewModel.supportsWhite(for: target))
                                    capabilityChip("CCT", enabled: viewModel.supportsCCT(for: target))
                                }

                                Text("Seg \(viewModel.getSegmentCount(for: target))")
                                    .font(AppTypography.style(.caption2))
                                    .foregroundColor(isSelected ? .black.opacity(0.7) : .white.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? Color.white : Color.white.opacity(0.07))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.12), lineWidth: 1)
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
                                .font(AppTypography.style(.caption, weight: .semibold))
                                .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .opacity(syncTargetCount == 0 ? 0.45 : 1.0)
                    .disabled(syncTargetCount == 0)
                }

                Spacer()

                Button(role: .destructive) {
                    viewModel.clearSyncTargets(sourceId: activeDevice.id)
                } label: {
                    Label("Stop Sync", systemImage: "xmark.circle")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .opacity(syncTargetCount == 0 ? 0.45 : 1.0)
                .disabled(syncTargetCount == 0)
            }

            if let summary = viewModel.syncDispatchMessage(for: activeDevice.id), syncTargetCount > 0 {
                Text(summary)
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.7))
            }

            if advancedUIEnabled {
                nativeWLEDSyncSection
            }
        }
        .padding()
        .task(id: advancedUIEnabled) {
            if advancedUIEnabled {
                await loadUDPSyncState()
            }
        }
    }

    @ViewBuilder
    private func capabilityChip(_ title: String, enabled: Bool) -> some View {
        Text(title)
            .font(AppTypography.style(.caption2, weight: .semibold))
            .foregroundColor(enabled ? .white : .white.opacity(0.35))
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
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white)

            HStack {
                Text("Send UDP Sync")
                    .foregroundColor(.white)
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
                    .foregroundColor(.white)
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
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(.white)
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
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
    
    // MARK: - Preset Rename Handling

    private func startPresetRename(_ context: PresetRenameContext) {
        presetRenameContext = context
        presetRenameEditedName = context.currentName
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPresetRenameFieldFocused = true
        }
    }
    
    private func applyPresetRename(_ newName: String, for context: PresetRenameContext) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelPresetRename()
            return
        }
        
        let store = PresetsStore.shared
        var presetRenameTargets: [(device: WLEDDevice, id: Int)] = []
        var playlistRenameTargets: [(device: WLEDDevice, id: Int)] = []
        let resolveDevice: (String) -> WLEDDevice? = { deviceId in
            viewModel.devices.first(where: { $0.id == deviceId })
                ?? (activeDevice.id == deviceId ? activeDevice : nil)
        }
        
        switch context {
        case .color(let preset):
            guard preset.name != trimmed else { break }
            var updated = preset
            updated.name = trimmed
            store.updateColorPreset(updated)
            if let idsByDevice = updated.wledPresetIds, !idsByDevice.isEmpty {
                for (deviceId, presetId) in idsByDevice where (1...250).contains(presetId) {
                    if let targetDevice = resolveDevice(deviceId) {
                        presetRenameTargets.append((targetDevice, presetId))
                    }
                }
            } else if let legacyId = updated.wledPresetId, (1...250).contains(legacyId) {
                presetRenameTargets.append((activeDevice, legacyId))
            }
        case .transition(let preset):
            guard preset.name != trimmed else { break }
            var updated = preset
            updated.name = trimmed
            store.updateTransitionPreset(updated)
            if let playlistId = updated.wledPlaylistId, (1...250).contains(playlistId),
               let targetDevice = resolveDevice(updated.deviceId) {
                playlistRenameTargets.append((targetDevice, playlistId))
            }
        case .effect(let preset):
            guard preset.name != trimmed else { break }
            var updated = preset
            updated.name = trimmed
            store.updateEffectPreset(updated)
            if let presetId = updated.wledPresetId, (1...250).contains(presetId),
               let targetDevice = resolveDevice(updated.deviceId) {
                presetRenameTargets.append((targetDevice, presetId))
            }
        case .devicePreset(let presetId, let name, let targetDevice):
            guard name != trimmed else { break }
            presetRenameTargets.append((targetDevice, presetId))
        case .devicePlaylist(let playlistId, let name, let targetDevice):
            guard name != trimmed else { break }
            playlistRenameTargets.append((targetDevice, playlistId))
        }
        
        cancelPresetRename()
        guard !presetRenameTargets.isEmpty || !playlistRenameTargets.isEmpty else { return }
        Task {
            for target in presetRenameTargets {
                _ = await viewModel.renamePresetRecord(target.id, to: trimmed, for: target.device)
            }
            for target in playlistRenameTargets {
                _ = await viewModel.renamePlaylistRecord(target.id, to: trimmed, for: target.device)
            }
        }
    }
    
    private func cancelPresetRename() {
        isPresetRenameFieldFocused = false
        presetRenameContext = nil
        presetRenameEditedName = ""
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

    func update(_ automation: Automation, syncOnDevice: Bool = true) {
        guard !isRunningInPreview else { return }
        AutomationStore.shared.update(automation, syncOnDevice: syncOnDevice)
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

    func isDeletionInProgress(for id: UUID) -> Bool {
        deletingAutomationIds.contains(id)
    }

    func deletionProgress(for id: UUID) -> AutomationDeletionProgress? {
        deletionProgressByAutomationId[id]
    }

    var hasAnyDeletionInProgress: Bool {
        AutomationStore.shared.hasAnyDeletionInProgress
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

    private var chipFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(automation.enabled ? 0.12 : 0.08)
            : Color.white.opacity(automation.enabled ? 0.22 : 0.16)
    }

    private var chipStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.24)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(automation.name)
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if isNext {
                        nextBadge
                            .allowsHitTesting(false)
                    }
                }

                Text(actionDescription)
                    .font(AppTypography.style(.caption2, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: 168, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(chipFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(chipStroke, lineWidth: 1)
                    )
            )
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
            .font(AppTypography.style(.caption2, weight: .semibold))
            .foregroundColor(.white.opacity(0.94))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
