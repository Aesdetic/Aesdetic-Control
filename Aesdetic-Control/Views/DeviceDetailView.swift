import SwiftUI

struct DeviceDetailView: View {
    let device: WLEDDevice
    @ObservedObject var viewModel: DeviceControlViewModel
    @State private var selectedTab: String = "Colors"
    
    // State variables for new features
    @State private var showSettings: Bool = false
    @State private var showSaveSceneDialog: Bool = false
    @State private var showAddAutomation: Bool = false
    @State private var udpnSend: Bool = false
    @State private var udpnReceive: Bool = false
    @State private var udpnNetwork: Int = 0
    @StateObject private var scenesStore = ScenesStore.shared
    @StateObject private var automationStore = AutomationStore.shared
    @State private var showEditDeviceInfo: Bool = false
    @State private var isToggling: Bool = false
    @State private var dismissColorPicker: Bool = false
    @State private var selectedSegmentId: Int = 0  // Track selected segment for multi-segment devices
    
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
            .onChange(of: dismissColorPicker) { _, newValue in
                if newValue {
                    dismissColorPicker = false
                }
            }
            .sheet(isPresented: $showSaveSceneDialog) {
                SaveSceneDialog(device: device, onSave: { scene in
                    scenesStore.add(scene)
                })
            }
            .sheet(isPresented: $showAddAutomation) {
                AddAutomationDialog(device: device, scenes: scenesStore.scenes) { automation in
                    automationStore.add(automation)
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
            headerRow
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
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 16) {
            // Power Toggle (left) - Match device card styling exactly
            Button(action: {
                // Calculate target state BEFORE any state changes
                let targetState = !currentPowerState
                
                // Set optimistic state for immediate UI feedback
                viewModel.setUIOptimisticState(deviceId: device.id, isOn: targetState)
                
                // If device appears offline but we're trying to control it, mark it as online
                if !device.isOnline {
                    viewModel.markDeviceOnline(device.id)
                }
                
                isToggling = true
                
                // Haptic feedback for immediate response
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                Task {
                    // Use the same toggle method as device card
                    await viewModel.toggleDevicePower(device)
                    
                    // Reset toggling state after operation
                    await MainActor.run {
                        isToggling = false
                    }
                }
            }) {
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
                .frame(width: 45, height: 45)
                .background(currentPowerState ? Color.white : Color.white.opacity(0.18))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(currentPowerState ? 0 : 0.3), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: currentPowerState)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Power")
            .accessibilityHint(currentPowerState ? "Turns the device off." : "Turns the device on.")
            
            VStack(alignment: .leading, spacing: 6) {
                Text(device.name)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill((viewModel.isDeviceOnline(device) || isToggling) ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: (viewModel.isDeviceOnline(device) || isToggling) ? Color.green.opacity(0.5) : Color.red.opacity(0.5), radius: 4, x: 0, y: 0)
                    
                    Text(viewModel.isDeviceOnline(device) || isToggling ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    if !device.ipAddress.isEmpty {
                        Text(device.ipAddress)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            
            Spacer()
            
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Device settings")
            .accessibilityHint("Opens advanced options for this device.")
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
            ("Scenes", "rectangle.stack.fill"),
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
        case "Scenes":
            scenesTabContent
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
            
            // Presets Section
            presetsSection
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
    
    private var scenesTabContent: some View {
        VStack(spacing: 16) {
            // Save Current State Button
            Button("Save Current as Scene") {
                showSaveSceneDialog = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Stores the current device state as a new scene.")
            
            // Scenes List
            ForEach(scenesStore.scenes.filter { $0.deviceId == device.id }) { scene in
                SceneRow(scene: scene) {
                    Task {
                        await viewModel.applyScene(scene, to: device)
                    }
                }
            }
        }
    }
    
    private var automationTabContent: some View {
        VStack(spacing: 16) {
            // Add Automation Button
            Button("Add Automation") {
                showAddAutomation = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Creates a new automation for this device.")
            
            // Automations List
            ForEach(automationStore.automations.filter { $0.deviceId == device.id }) { automation in
                AutomationRow(
                    automation: automation,
                    scenes: scenesStore.scenes,
                    onToggle: { enabled in
                        var updated = automation
                        updated.enabled = enabled
                        automationStore.update(updated)
                    }
                )
            }
        }
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
        EffectsPane(device: device, segmentId: selectedSegmentId)
            .environmentObject(viewModel)
    }
    
    private var presetsSection: some View {
        PresetsPane(device: device)
            .environmentObject(viewModel)
    }
    
    private var transitionSection: some View {
        TransitionPane(device: device, dismissColorPicker: $dismissColorPicker)
    }
    
}
