import SwiftUI
import Combine

enum DeviceDetailBackgroundStyle {
    case frosted
    case liquidGlass
}

struct DeviceDetailView: View {
    let device: WLEDDevice
    private let backgroundStyle: DeviceDetailBackgroundStyle
    @ObservedObject var viewModel: DeviceControlViewModel
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: String = "Colors"
    
    // State variables for new features
    @State private var showSettings: Bool = false
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
    private let detailCardCornerRadius: CGFloat = 30

    init(
        device: WLEDDevice,
        viewModel: DeviceControlViewModel,
        initialTab: String = "Colors",
        backgroundStyle: DeviceDetailBackgroundStyle = .frosted
    ) {
        self.device = device
        self.backgroundStyle = backgroundStyle
        self.viewModel = viewModel
        _selectedTab = State(initialValue: initialTab)
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

    private var isRebootWaitActive: Bool {
        viewModel.isRebootWaitActive(for: activeDevice.id)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(detailContainerBackground)
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
                    if editingAutomation != nil {
                        automationStore.update(automation)
                    } else {
                        automationStore.add(automation)
                    }
                    editingAutomation = nil
                    automationEditorDefaultName = nil
                    pendingAutomationTemplate = nil
                }
            }
            .sheet(isPresented: $showEditDeviceInfo) {
                EditDeviceInfoDialog(device: activeDevice)
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    ComprehensiveSettingsView(device: activeDevice)
                        .environmentObject(viewModel)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.ultraThinMaterial)
            }
            .confirmationDialog(
                "Delete automation?",
                isPresented: Binding(
                    get: { automationPendingDelete != nil },
                    set: { if !$0 { automationPendingDelete = nil } }
                ),
                presenting: automationPendingDelete
            ) { automation in
                Button("Delete \(automation.name)", role: .destructive) {
                    automationStore.delete(id: automation.id)
                    automationPendingDelete = nil
                }
            }
        }
    }
    
    private var backgroundLayer: some View {
        Color.clear
        .ignoresSafeArea()
    }
    
    private var contentLayer: some View {
        VStack(spacing: 0) {
            condensedHeader
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
            
            tabNavigationBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 2)
            
            ScrollView {
                tabContent
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
        }
        .contentShape(Rectangle())
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
        HStack(alignment: .center, spacing: 16) {
            Button(action: togglePower) {
                powerButtonContent
            }
            .buttonStyle(.plain)
            .disabled(isToggling || isRebootWaitActive)
            .accessibilityLabel("Power")
            .accessibilityHint(currentPowerState ? "Turns the device off." : "Turns the device on.")

            VStack(alignment: .leading, spacing: 4) {
                Text(activeDevice.name)
                    .font(AppTypography.style(.title3, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    statusDot
                    Text(viewModel.isDeviceOnline(activeDevice) || isToggling ? "Online" : "Offline")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))

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

            Menu {
                Button(action: startRename) {
                    Label("Rename Device", systemImage: "pencil")
                }
                Button(action: { showSettings.toggle() }) {
                    Label("Settings", systemImage: "gearshape")
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
                Image(systemName: "ellipsis.circle")
                    .font(AppTypography.style(.title2, weight: .semibold))
                    .foregroundColor(.white)
            }
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
            .fill((viewModel.isDeviceOnline(activeDevice) || isToggling) ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .shadow(color: (viewModel.isDeviceOnline(activeDevice) || isToggling) ? Color.green.opacity(0.5) : Color.red.opacity(0.5), radius: 4, x: 0, y: 0)
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
                    Text(statusLabel)
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(.white.opacity(0.85))

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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
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
    
    
    // MARK: - Tab Navigation Bar
    
    private var tabNavigationBar: some View {
        HStack(spacing: 0) {
            ForEach(tabItems, id: \.title) { tabItem in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tabItem.title
                        }
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: tabItem.icon)
                                .font(AppTypography.style(.title3))
                                .foregroundColor(selectedTab == tabItem.title ? .white : .white.opacity(0.4))
                            
                            Text(tabItem.title)
                                .font(AppTypography.style(.footnote, weight: .medium))
                                .foregroundColor(selectedTab == tabItem.title ? .white : .white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                .buttonStyle(.plain)
                .accessibilityLabel(tabItem.title)
                .accessibilityHint("Shows the \(tabItem.title.lowercased()) controls.")
            }
        }
        .background(Color.clear)
    }
    
    private var tabItems: [(title: String, icon: String)] {
        [
            ("Colors", "paintbrush.fill"),
            ("Presets", "rectangle.stack.fill"),
            ("Automation", "clock.fill"),
            ("Sync", "arrow.triangle.2.circlepath")
        ]
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "Colors":
            colorsTabContent
        case "Presets":
            presetsTabContent
        case "Automation":
            automationTabContent
        case "Sync":
            syncTabContent
        default:
            EmptyView()
        }
    }
    
    private var colorsTabContent: some View {
        VStack(spacing: 16) {
            // Segment Picker (only show for multi-segment devices)
            if advancedUIEnabled,
               showSegmentControlsInColorTabAdvanced,
               viewModel.hasMultipleSegments(for: activeDevice) {
                segmentPicker
            }
            
            // Gradient Editor (includes working brightness control)
            gradientAEditor
            
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
        PresetsListView(device: activeDevice, onRequestRename: startPresetRename)
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
                        AutomationRow(
                            automation: automation,
                            scenes: scenesStore.scenes,
                            isNext: nextAutomationID == automation.id,
                            isDeleting: automationStore.isDeletionInProgress(for: automation.id),
                            isRunning: runStatus != nil,
                            runningProgress: runStatus?.progress,
                            subtitle: activeDevice.name,
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcuts")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                if !shortcutAutomations.isEmpty {
                    Text("\(shortcutAutomations.count)")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Menu {
                    Button("New Automation") {
                        startAutomationCreation()
                    }
                    ForEach(AutomationTemplate.quickStartTemplates) { template in
                        Button(template.name) {
                            startAutomationCreation(using: template)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(AppTypography.style(.title3, weight: .semibold))
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Add shortcut")
            }
            
            if shortcutAutomations.isEmpty {
                Text("Pin an automation with the heart icon to surface it here for quick toggles.")
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shortcutAutomations) { automation in
                            ShortcutAutomationChip(
                                automation: automation,
                                isNext: nextAutomationID == automation.id,
                                onTap: { toggleAutomationEnabled(automation) },
                                onLongPress: { editAutomation(automation) }
                            )
                            .id(automation.id) // Explicit ID for proper view updates
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)
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
        automationStore.update(updated)
    }
    
    private func startAutomationCreation(using template: AutomationTemplate? = nil) {
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
            return "Select devices to start automatic sync."
        }
        return "Syncing to \(syncTargetCount) device\(syncTargetCount == 1 ? "" : "s")"
    }
    
    private var syncTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sync Targets")
                    .font(AppTypography.style(.callout, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(syncStatusLine)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
            }

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
            suppressUDPNUpdates = false
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
    
    
    private var globalBrightnessSlider: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Global Brightness")
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(round(Double(activeDevice.brightness)/255.0*100)))%")
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: Binding(
                get: { Double(activeDevice.brightness) },
                set: { newValue in
                    // Update will be handled on release
                }
            ), in: 0...255, step: 1, onEditingChanged: { editing in
                if !editing {
                    Task {
                        await viewModel.updateDeviceBrightness(activeDevice, brightness: Int(round(Double(activeDevice.brightness))))
                    }
                }
            })
            .sensorySelection(trigger: activeDevice.brightness)
            .accessibilityLabel("Global brightness")
            .accessibilityValue("\(Int(round(Double(activeDevice.brightness)/255.0*100))) percent")
            .accessibilityHint("Adjusts the device brightness globally.")
            .accessibilityAdjustableAction { direction in
                let current = Double(activeDevice.brightness)
                let step: Double = 12.75
                var newValue = current
                switch direction {
                case .increment:
                    newValue = min(255, current + step)
                case .decrement:
                    newValue = max(0, current - step)
                @unknown default:
                    break
                }
                let rounded = Int(round(newValue))
                Task { await viewModel.updateDeviceBrightness(activeDevice, brightness: rounded) }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var aBrightnessSlider: some View {
        VStack(spacing: 6) {
            HStack {
                Text("A Brightness")
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(round(Double(activeDevice.brightness)/255.0*100)))%")
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: Binding(
                get: { Double(activeDevice.brightness) },
                set: { newValue in
                    // This will be handled by the UnifiedColorPane
                }
            ), in: 0...255, step: 1)
            .accessibilityLabel("A brightness")
            .accessibilityValue("\(Int(round(Double(activeDevice.brightness)/255.0*100))) percent")
            .accessibilityHint("Adjusts brightness for gradient A.")
        }
        .padding(.horizontal, 16)
    }
    
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

    private var cancellables = Set<AnyCancellable>()
    private let isRunningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    init() {
        guard !isRunningInPreview else { return }

        let store = AutomationStore.shared
        automations = store.automations
        upcomingAutomationInfo = store.upcomingAutomationInfo

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
    }

    func add(_ automation: Automation) {
        guard !isRunningInPreview else { return }
        AutomationStore.shared.add(automation)
    }

    func update(_ automation: Automation) {
        guard !isRunningInPreview else { return }
        AutomationStore.shared.update(automation)
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
    var subtitle: String? = nil
    var onTap: () -> Void
    var onLongPress: () -> Void
    
    private var titleColor: Color {
        automation.enabled ? .black : .white
    }
    
    private var fillColor: Color {
        return automation.enabled ? Color.white : Color.white.opacity(0.12)
    }
    
    private var textColor: Color {
        automation.enabled ? .black.opacity(0.8) : .white.opacity(0.8)
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let icon = automation.metadata.iconName {
                            Image(systemName: icon)
                                .font(AppTypography.style(.caption, weight: .semibold))
                                .foregroundColor(automation.enabled ? .black : .white)
                        }
                        Text(automation.name)
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(titleColor)
                            .lineLimit(1)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.style(.caption2))
                            .foregroundColor(textColor)
                            .lineLimit(1)
                    }

                    Text(automation.trigger.displayName)
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                }

                if isNext {
                    nextBadge
                        .offset(x: -8, y: -8)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
            .foregroundColor(.white.opacity(0.96))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}
