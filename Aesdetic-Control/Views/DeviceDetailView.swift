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
    @State private var isEditingName: Bool = false
    @State private var editingName: String = ""
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Enhanced thin material with heavy blur for contrast
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
            
            // Content with thin material background
            VStack(spacing: 0) {
                // Custom Header (blended with overall background)
                headerRow
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                
                // Tab Navigation Bar (blended with overall background)
                tabNavigationBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                
                // Tab Content (blended with overall background)
                ScrollView {
                    tabContent
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
        .navigationBarHidden(true)
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
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 16) {
            // Power Toggle (left)
            Button(action: {
                Task {
                    await viewModel.toggleDevicePower(device)
                }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(device.isOn ? Color.white : Color.white.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(device.isOn ? .black : .white)
                }
            }
            .buttonStyle(.plain)
            
            // Device Name (center) - Editable
            if isEditingName {
                TextField("Device Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .focused($isNameFieldFocused)
                    .onSubmit {
                        Task {
                            await saveDeviceName()
                        }
                    }
                    .frame(maxWidth: .infinity)
            } else {
                Text(device.name)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        startEditingName()
                    }
            }
            
            Spacer()
            
            // Settings Gear (right)
            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
            }
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
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(selectedTab == tabItem.title ? .white : .white.opacity(0.4))
                            
                            Text(tabItem.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selectedTab == tabItem.title ? .white : .white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                .buttonStyle(.plain)
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
            // Gradient Editor (includes working brightness control)
            gradientAEditor
            
            // Transition Section
            transitionSection
        }
    }
    
    private var scenesTabContent: some View {
        VStack(spacing: 16) {
            // Save Current State Button
            Button("Save Current as Scene") {
                showSaveSceneDialog = true
            }
            .buttonStyle(PrimaryButtonStyle())
            
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
        }
        .padding(.horizontal, 16)
    }
    
    private var gradientAEditor: some View {
        UnifiedColorPane(device: device)
    }
    
    private var transitionSection: some View {
        TransitionPane(device: device)
    }
    
    // MARK: - Helper Functions
    
    private func startEditingName() {
        editingName = device.name
        isEditingName = true
        // Focus the text field after a brief delay to ensure the view has updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
    
    private func saveDeviceName() async {
        // Trim whitespace
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate name is not empty
        guard !newName.isEmpty else {
            // Reset to original name if empty
            editingName = device.name
            isEditingName = false
            isNameFieldFocused = false
            return
        }
        
        // Only save if name actually changed
        guard newName != device.name else {
            isEditingName = false
            isNameFieldFocused = false
            return
        }
        
        // Save the new name via ViewModel
        await viewModel.renameDevice(device, to: newName)
        
        // Exit edit mode
        isEditingName = false
        isNameFieldFocused = false
    }
}
