import SwiftUI

struct DeviceDetailView: View {
    let device: WLEDDevice
    @ObservedObject var viewModel: DeviceControlViewModel
    @State private var selectedTab: String = "Colors"
    
    // State variables for new features
    @State private var showSettings: Bool = false
    @State private var showSaveSceneDialog: Bool = false
    @State private var showAddAutomation: Bool = false
    @State private var pendingAutomationTemplate: AutomationTemplate? = nil
    @State private var udpnSend: Bool = false
    @State private var udpnReceive: Bool = false
    @State private var udpnNetwork: Int = 0
    @StateObject private var scenesStore = ScenesStore.shared
    @StateObject private var automationStore = AutomationStore.shared
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
    @State private var hasSeededAutomationTemplates: Bool = false
    
    // Use coordinated power state from ViewModel
    private var currentPowerState: Bool {
        return viewModel.getCurrentPowerState(for: device.id)
    }
    
    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                backgroundLayer
                contentLayer
                    .padding(.top, viewModel.currentError == nil ? 0 : topInset + 72)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8, blendDuration: 0.2), value: viewModel.currentError)
                bannerOverlay(topInset: topInset)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.ultraThinMaterial)
            .navigationBarHidden(true)
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
            .onChange(of: dismissColorPicker) { _, newValue in
                if newValue {
                    dismissColorPicker = false
                }
            }
            .sheet(isPresented: $showAddAutomation, onDismiss: {
                pendingAutomationTemplate = nil
                editingAutomation = nil
                automationEditorDefaultName = nil
            }) {
                let deviceScenes = scenesStore.scenes.filter { $0.deviceId == device.id }
                let effectOptions = viewModel.colorSafeEffectOptions(for: device)
                let prefill = pendingAutomationTemplate.map {
                    $0.prefill(for: AutomationTemplate.Context(
                        device: device,
                        availableDevices: viewModel.devices,
                        defaultGradient: viewModel.automationGradient(for: device)
                    ))
                }
                AddAutomationDialog(
                    device: device,
                    scenes: deviceScenes,
                    effectOptions: effectOptions,
                    availableDevices: viewModel.devices,
                    viewModel: viewModel,
                    defaultName: automationEditorDefaultName,
                    editingAutomation: editingAutomation,
                    templatePrefill: prefill
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
                EditDeviceInfoDialog(device: device)
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    ComprehensiveSettingsView(device: device)
                        .environmentObject(viewModel)
                }
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
            .onAppear {
                Task {
                    await viewModel.refreshDeviceState(device)
                }
            }
        }
    }
    
    private var backgroundLayer: some View {
        LiquidGlassOverlay(
            blurOpacity: 0.65,
            highlightOpacity: 0.18,
            verticalTopOpacity: 0.08,
            verticalBottomOpacity: 0.08,
            vignetteOpacity: 0.12,
            centerSheenOpacity: 0.06
        )
        .overlay(
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
    
    private func errorAction(for error: DeviceControlViewModel.WLEDError) -> (() -> Void)? {
        switch error {
        case .deviceOffline, .timeout:
            return {
                Task {
                    await viewModel.refreshDeviceState(device)
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
            .accessibilityLabel("Power")
            .accessibilityHint(currentPowerState ? "Turns the device off." : "Turns the device on.")
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    statusDot
                    Text(viewModel.isDeviceOnline(device) || isToggling ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    // Active run status chip
                    if let activeRun = viewModel.activeRunStatus[device.id] {
                        activeRunStatusChip(activeRun)
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
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
    
    private var statusDot: some View {
        Circle()
            .fill((viewModel.isDeviceOnline(device) || isToggling) ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .shadow(color: (viewModel.isDeviceOnline(device) || isToggling) ? Color.green.opacity(0.5) : Color.red.opacity(0.5), radius: 4, x: 0, y: 0)
    }
    
    @ViewBuilder
    private func activeRunStatusChip(_ run: ActiveRunStatus) -> some View {
        HStack(spacing: 6) {
            // Status text
            Group {
                switch run.kind {
                case .automation, .transition:
                    if run.progress > 0 {
                        Text("\(run.title) \(Int(run.progress * 100))%")
                    } else {
                        Text("Running: \(run.title)")
                    }
                case .effect:
                    Text("Effect: \(run.title)")
                case .applying:
                    Text("Applying: \(run.title)")
                }
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.85))
            
            // Cancel button (if cancellable)
            if run.isCancellable {
                Button(action: {
                    Task {
                        await viewModel.cancelActiveRun(for: device)
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
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
    }
    
    private var powerButtonContent: some View {
        ZStack {
            Image(systemName: "power")
                .font(.title3)
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
        viewModel.setUIOptimisticState(deviceId: device.id, isOn: targetState)
        if !device.isOnline {
            viewModel.markDeviceOnline(device.id)
        }
        isToggling = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await viewModel.toggleDevicePower(device)
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
                                .font(.title3)
                                .foregroundColor(selectedTab == tabItem.title ? .white : .white.opacity(0.4))
                            
                            Text(tabItem.title)
                                .font(.footnote.weight(.medium))
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
            if viewModel.hasMultipleSegments(for: device) {
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
    
    // MARK: - Segment Picker
    
    private var segmentPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Segment")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            
            // Segmented control for segment selection
            Picker("Segment", selection: $selectedSegmentId) {
                ForEach(0..<viewModel.getSegmentCount(for: device), id: \.self) { segmentId in
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
        PresetsListView(device: device, onRequestRename: startPresetRename)
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
                    ForEach(deviceAutomations) { automation in
                        AutomationRow(
                            automation: automation,
                            scenes: scenesStore.scenes,
                            isNext: nextAutomationID == automation.id,
                            subtitle: device.name,
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
                            onDelete: {
                                automationPendingDelete = automation
                            }
                        )
                        .id(automation.id) // Explicit ID for proper view updates
                    }
                }
            }
        }
        .onAppear {
            seedDefaultAutomationsIfNeeded()
        }
    }
    
    private var automationShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcuts")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                if !shortcutAutomations.isEmpty {
                    Text("\(shortcutAutomations.count)")
                        .font(.caption)
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
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .accessibilityLabel("Add shortcut")
            }
            
            if shortcutAutomations.isEmpty {
                Text("Pin an automation with the heart icon to surface it here for quick toggles.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
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
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    private var automationsHeader: some View {
        HStack(alignment: .center) {
            Text("Automations")
                .font(.callout.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Button {
                startAutomationCreation()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3.weight(.semibold))
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
                .font(.title2.weight(.light))
                .foregroundColor(.white.opacity(0.6))
            Text("No automations for this device yet.")
                .font(.headline)
                .foregroundColor(.white)
            Text("Create a shortcut to wake up with sunrise colors or wind down at night.")
                .font(.footnote)
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
        automationStore.automations.filter { $0.targets.deviceIds.contains(device.id) }
    }
    
    private var shortcutAutomations: [Automation] {
        deviceAutomations.filter { $0.metadata.pinnedToShortcuts ?? false }
    }
    
    private var upcomingAutomation: (automation: Automation, date: Date?)? {
        if let scheduled = automationStore.upcomingAutomationInfo,
           scheduled.automation.targets.deviceIds.contains(device.id) {
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
    
    private func startRename() {
        showEditDeviceInfo = true
    }
    
    private var defaultAutomationName: String {
        "Automation \(automationStore.automations.count + 1)"
    }
    
    private func seedDefaultAutomationsIfNeeded() {
        guard !hasSeededAutomationTemplates else { return }
        hasSeededAutomationTemplates = true
        let context = AutomationTemplate.Context(
            device: device,
            availableDevices: viewModel.devices,
            defaultGradient: viewModel.automationGradient(for: device)
        )
        let existingTemplateIDs = Set(deviceAutomations.compactMap { $0.metadata.templateId })
        for template in AutomationTemplate.quickStartTemplates {
            guard !existingTemplateIDs.contains(template.id) else { continue }
            let prefill = template.prefill(for: context)
            if let automation = automation(from: prefill, templateName: template.name, context: context) {
                automationStore.add(automation)
            }
        }
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
    
    private var syncTabContent: some View {
        VStack(spacing: 16) {
            // UDPN Send Toggle
            HStack {
                Text("Send UDP Sync")
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $udpnSend)
                    .onChange(of: udpnSend) { _, newValue in
                        Task {
                            await viewModel.setUDPSync(device, send: newValue, recv: nil)
                        }
                    }
            }
            
            // UDPN Receive Toggle
            HStack {
                Text("Receive UDP Sync")
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $udpnReceive)
                    .onChange(of: udpnReceive) { _, newValue in
                        Task {
                            await viewModel.setUDPSync(device, send: nil, recv: newValue)
                        }
                    }
            }
            
            // Network ID Stepper
            HStack {
                Text("Network ID")
                    .foregroundColor(.white)
                Spacer()
                Stepper("\(udpnNetwork)", value: $udpnNetwork, in: 0...255)
                    .onChange(of: udpnNetwork) { _, newValue in
                        Task {
                            await viewModel.setUDPSync(device, send: nil, recv: nil, network: newValue)
                        }
                    }
            }
        }
        .padding()
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
        
        switch context {
        case .color(let preset):
            guard preset.name != trimmed else { break }
            var updated = preset
            updated.name = trimmed
            store.updateColorPreset(updated)
        case .transition(let preset):
            guard preset.name != trimmed else { break }
            var updated = preset
            updated.name = trimmed
            store.updateTransitionPreset(updated)
        case .effect(let preset):
            guard preset.name != trimmed else { break }
            var updated = preset
            updated.name = trimmed
            store.updateEffectPreset(updated)
        }
        
        cancelPresetRename()
    }
    
    private func cancelPresetRename() {
        isPresetRenameFieldFocused = false
        presetRenameContext = nil
        presetRenameEditedName = ""
    }
    
    private func resetAnimationModesIfNeeded() {
        guard !didResetAnimationModes else { return }
        didResetAnimationModes = true
        let currentSegmentId = selectedSegmentId
        Task {
            await viewModel.cancelActiveTransitionIfNeeded(for: device)
            // Only disable effect if it's actually enabled to prevent unnecessary flash
            let effectState = viewModel.currentEffectState(for: device, segmentId: currentSegmentId)
            if effectState.isEnabled {
                await viewModel.disableEffect(for: device, segmentId: currentSegmentId)
            }
            await MainActor.run {
                isTransitionPaneExpanded = false
                isEffectsPaneExpanded = false
            }
        }
    }
    
    // MARK: - Colors Tab Helper Views
    
    
    private var globalBrightnessSlider: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Global Brightness")
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(round(Double(device.brightness)/255.0*100)))%")
                    .foregroundColor(.white.opacity(0.8))
            }
            Slider(value: Binding(
                get: { Double(device.brightness) },
                set: { newValue in
                    // Update will be handled on release
                }
            ), in: 0...255, step: 1, onEditingChanged: { editing in
                if !editing {
                    Task {
                        await viewModel.updateDeviceBrightness(device, brightness: Int(round(Double(device.brightness))))
                    }
                }
            })
            .sensorySelection(trigger: device.brightness)
            .accessibilityLabel("Global brightness")
            .accessibilityValue("\(Int(round(Double(device.brightness)/255.0*100))) percent")
            .accessibilityHint("Adjusts the device brightness globally.")
            .accessibilityAdjustableAction { direction in
                let current = Double(device.brightness)
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
                Task { await viewModel.updateDeviceBrightness(device, brightness: rounded) }
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
                Text("\(Int(round(Double(device.brightness)/255.0*100)))%")
                    .foregroundColor(.white.opacity(0.8))
            }
            Slider(value: Binding(
                get: { Double(device.brightness) },
                set: { newValue in
                    // This will be handled by the UnifiedColorPane
                }
            ), in: 0...255, step: 1)
            .accessibilityLabel("A brightness")
            .accessibilityValue("\(Int(round(Double(device.brightness)/255.0*100))) percent")
            .accessibilityHint("Adjusts brightness for gradient A.")
        }
        .padding(.horizontal, 16)
    }
    
    private var gradientAEditor: some View {
        UnifiedColorPane(device: device, dismissColorPicker: $dismissColorPicker, segmentId: selectedSegmentId)
    }
    
    private var effectsSection: some View {
        EffectsPane(
            device: device,
            segmentId: selectedSegmentId,
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
            device: device,
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
        if isNext {
            return Color.orange
        }
        return automation.enabled ? Color.white : Color.white.opacity(0.12)
    }
    
    private var textColor: Color {
        automation.enabled ? .black.opacity(0.8) : .white.opacity(0.8)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let icon = automation.metadata.iconName {
                        Image(systemName: icon)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(automation.enabled ? .black : .white)
                    }
                    Text(automation.name)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                }
                
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                }
                
                Text(automation.trigger.displayName)
                    .font(.caption2)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                if isNext {
                    Text("Next")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.black.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isNext ? Color.white.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
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
}
