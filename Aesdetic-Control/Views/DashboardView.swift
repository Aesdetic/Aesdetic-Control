//
//  DashboardView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var dashboardViewModel = DashboardViewModel.shared
    @StateObject private var deviceControlViewModel = DeviceControlViewModel.shared
    @StateObject private var automationViewModel = AutomationViewModel.shared
    
    @Environment(\.colorScheme) var colorScheme
    
    // TEMP: Minimal debug mode to isolate background/layout issues
    @State private var debugMinimalMode: Bool = true
    // Safe area helper for consistent top spacing (avoids status indicators overlap)
    private var topSafeAreaInset: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.top
        }
        return 0
    }
    
    // MARK: - Performance Optimization Properties
    
    // Derived-data cache (updated only from explicit events, never from computed properties)
    @State private var memoizedDeviceStats: (total: Int, online: Int, offline: Int) = (0, 0, 0)
    @State private var memoizedFilteredDevices: [WLEDDevice] = []
    
    private let deviceUpdateThrottle: TimeInterval = 0.5 // 500ms throttle window
    @State private var lastDerivedUpdate: Date = .distantPast
    
    // Animation optimization
    private let standardAnimation: Animation = .easeInOut(duration: 0.25)
    private let fastAnimation: Animation = .easeInOut(duration: 0.15)
    private let smoothAnimation: Animation = .interpolatingSpring(stiffness: 300, damping: 30)
    
    // Background handled globally by AppBackground
    
    // Side-effect-free accessors
    private var deviceStatistics: (total: Int, online: Int, offline: Int) { memoizedDeviceStats }
    private var filteredDevices: [WLEDDevice] { memoizedFilteredDevices }
    
    private func updateMemoizedStats() {
        let devices = deviceControlViewModel.devices
        let total = devices.count
        let online = devices.filter { $0.isOnline }.count
        let offline = total - online
        
        memoizedDeviceStats = (total: total, online: online, offline: offline)
        lastDerivedUpdate = Date()
    }
    
    private func updateMemoizedFilteredDevices() {
        let devices = deviceControlViewModel.devices
        
        // Simple filtering - optimize for common cases first
        if deviceControlViewModel.selectedLocationFilter == .all {
            memoizedFilteredDevices = devices
        } else {
            memoizedFilteredDevices = devices.filter { device in
                device.location == deviceControlViewModel.selectedLocationFilter
            }
        }
        lastDerivedUpdate = Date()
    }

    // Call this when inputs change, throttled to 500ms
    private func recomputeDerivedIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastDerivedUpdate) >= deviceUpdateThrottle else { return }
        updateMemoizedStats()
        updateMemoizedFilteredDevices()
    }
    
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                // Combined header row: greeting aligned with logo bottom
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(dashboardViewModel.currentGreeting)
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .id(dashboardViewModel.currentGreeting)
                    Spacer()
                    Group {
                        if let logoImage = UIImage(named: "aesdetic_logo") {
                            Image(uiImage: logoImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                }
                .padding(.horizontal, 16)
                .padding(.top, topSafeAreaInset + 12)
                .padding(.bottom, 2)

                // Motivational text
                HStack {
                    Text(dashboardViewModel.currentQuote)
                        .font(.title3.weight(.regular))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .id(dashboardViewModel.currentQuote)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Scenes & Automations
                ScenesAutomationsSection(
                    automations: automationViewModel.automations,
                    onToggle: { automation in
                        Task { await automationViewModel.toggleAutomation(automation) }
                    }
                )
                .padding(.top, 0)
                .padding(.bottom, 8)
                .onReceive(automationViewModel.$automations) { _ in
                    DispatchQueue.main.async { recomputeDerivedIfNeeded() }
                }

                // Devices stats (from derived cache)
                DeviceStatsSection(
                    totalDevices: deviceStatistics.total,
                    activeDevices: deviceStatistics.online,
                    activeAutomations: automationViewModel.automations.filter { $0.isEnabled }.count
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Device cards grid (from derived cache)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 18)],
                    spacing: 18
                ) {
                    ForEach(filteredDevices, id: \.id) { device in
                        MiniDeviceCard(device: device)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .background(Color.clear)
                .onChange(of: deviceControlViewModel.devices) { _, _ in
                    DispatchQueue.main.async { recomputeDerivedIfNeeded() }
                }

                Spacer(minLength: 16)
            }
        }
    }
    
    // MARK: - Optimized Components
    
    @ViewBuilder
    private func headerSection(geometry: GeometryProxy) -> some View {
        HStack {
            Spacer()
            
            // Company logo positioned in top right
            Group {
                if let logoImage = UIImage(named: "aesdetic_logo") {
                    Image(uiImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // Fallback sparkles icon
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 50, height: 50)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private func greetingSection(geometry: GeometryProxy) -> some View {
        HStack {
            Text(dashboardViewModel.currentGreeting)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .id(dashboardViewModel.currentGreeting)
                .animation(fastAnimation, value: dashboardViewModel.currentGreeting)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private func motivationalSection(geometry: GeometryProxy) -> some View {
        HStack {
            Text(dashboardViewModel.currentQuote)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.gray)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .id(dashboardViewModel.currentQuote)
                .animation(fastAnimation, value: dashboardViewModel.currentQuote)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
    
    @ViewBuilder
    private func scenesSection(geometry: GeometryProxy) -> some View {
        ScenesAutomationsSection(
            automations: automationViewModel.automations,
            onToggle: { automation in
                Task { automationViewModel.toggleAutomation(automation) }
            }
        )
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private func statisticsSection(geometry: GeometryProxy) -> some View {
        let stats = deviceStatistics // Use memoized stats
        
        DeviceStatsSection(
            totalDevices: stats.total,
            activeDevices: stats.online,
            activeAutomations: automationViewModel.automations.filter { $0.isEnabled }.count
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(smoothAnimation, value: stats.total) // Smooth stat changes
    }
    
    @ViewBuilder
    private func deviceCardsSection(geometry: GeometryProxy) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 18)
            ],
            spacing: 18
        ) {
            // Use memoized filtered devices
            ForEach(filteredDevices, id: \.id) { device in
                MiniDeviceCard(device: device)
                    .id(device.id) // Stable identity for animations
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity).animation(smoothAnimation.delay(0.1)),
                        removal: .scale.combined(with: .opacity).animation(fastAnimation)
                    ))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .animation(standardAnimation, value: filteredDevices.count)
    }
    
    // MARK: - Performance Optimized Data Refresh
    
    @MainActor
    private func refreshData() async {
        // Await all async work, then update derived caches once
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await deviceControlViewModel.refreshDevices() }
            group.addTask { await dashboardViewModel.updateCurrentGreeting() }
            for await _ in group { }
        }
        DispatchQueue.main.async { recomputeDerivedIfNeeded() }
    }
}





// MARK: - Scenes & Automations Section

struct ScenesAutomationsSection: View {
    let automations: [Automation]
    let onToggle: (Automation) -> Void
    
    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
            Text("Scenes & Automations")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(automations) { automation in
                        SceneAutomationButton(
                            automation: automation,
                            onToggle: { onToggle(automation) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .background(Color.clear)
            }
            .frame(height: 52)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollClipDisabled()
        }
        .background(Color.clear)
    }
}

// MARK: - Scene/Automation Button (Apple Home App Style)

struct SceneAutomationButton: View {
    let automation: Automation
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: automation.automationType.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)

                Text(automation.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 160, maxWidth: 220)
            .liquidGlassButton(cornerRadius: 18, active: automation.isEnabled, tint: .blue)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.2), value: automation.isEnabled)
    }
}

// MARK: - Device Statistics Section

struct DeviceStatsSection: View {
    let totalDevices: Int
    let activeDevices: Int
    let activeAutomations: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Devices")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            // Unified Statistics Card with Vertical Dividers
            UnifiedStatsCard(
                totalDevices: totalDevices,
                activeDevices: activeDevices,
                activeAutomations: activeAutomations
            )
        }
    }
}

// MARK: - Unified Statistics Card with Vertical Dividers

struct UnifiedStatsCard: View {
    let totalDevices: Int
    let activeDevices: Int
    let activeAutomations: Int
    
    var body: some View {
        HStack(spacing: 0) {
            // Total Devices
            StatisticItem(
                number: "\(totalDevices)",
                label: "Total\nDevices"
            )
            
            // Vertical Divider
            VerticalDivider()
            
            // Active Devices
            StatisticItem(
                number: "\(activeDevices)",
                label: "Active\nDevices"
            )
            
            // Vertical Divider
            VerticalDivider()
            
            // Scenes On
            StatisticItem(
                number: "\(activeAutomations)",
                label: "Scenes\nOn"
            )
        }
        .frame(height: 68)
        .liquidGlassButton(cornerRadius: 20, active: true, tint: .blue)
    }
}

// MARK: - Individual Statistic Item

struct StatisticItem: View {
    let number: String
    let label: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Large Number (left side)
            Text(number)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            // Description Text (right side, left-aligned)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: - Vertical Divider

struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1)
            .padding(.vertical, 16)
    }
}

// MARK: - Mini Device Cards Section

struct MiniDeviceCardsSection: View {
    let devices: [WLEDDevice]
    
    var body: some View {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
        ], spacing: 12) {
                ForEach(devices) { device in
                MiniDeviceCard(device: device)
            }
        }
    }
}

// MARK: - Mini Device Card (HomePod Style)

struct MiniDeviceCard: View {
    let device: WLEDDevice
    @ObservedObject private var viewModel = DeviceControlViewModel.shared
    @State private var isToggling: Bool = false

    init(device: WLEDDevice) {
        self.device = device
    }

    var currentPowerState: Bool {
        // Use the new coordinated state management from ViewModel
        return viewModel.getCurrentPowerState(for: device.id)
    }

    var displayPowerState: Bool {
        // For UI display purposes (button state, etc.)
        currentPowerState
    }

    var brightnessEffect: Double {
        currentPowerState ? Double(device.brightness) / 255.0 : 0.0
    }
    
    var body: some View {
        // Remove the outer Button wrapper - no nested buttons!
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Product image positioned to peek out from bottom (contained within card)
                VStack {
                    Spacer()
            HStack {
                        Spacer()
                        productImageSection(cardWidth: geometry.size.width)
                            .offset(y: currentPowerState ? geometry.size.height * 0.35 : geometry.size.height * 0.18)
                Spacer()
                    }
            }
                .clipped()
            
                // Content positioned at top
                VStack(alignment: .leading, spacing: 0) {
                    // Header with device info and toggle button
                    HStack(alignment: .top) {
                        // Device info on the left
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                                .font(.system(size: 18, weight: .semibold)) // Increased from 16 to 18
                                .foregroundColor(.white)
                    .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(device.location.displayName)
                                .font(.system(size: 14, weight: .medium)) // Increased from 12 to 14
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Spacer()
                        
                        // Toggle button on the right - this is the ONLY interactive button
                        powerToggleButton
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
                    
                    Spacer()
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(1.0)
        .liquidGlassButton(cornerRadius: 19, active: currentPowerState, tint: device.currentColor)
        .onAppear {
            // Clear any UI optimistic state on appear
            viewModel.clearUIOptimisticState(deviceId: device.id)
        }
        .onDisappear {
            // Clean up UI optimistic state when view disappears
            viewModel.clearUIOptimisticState(deviceId: device.id)
        }
    }

    // MARK: - Product Image Section (Matching Device Tab Implementation)
    private func productImageSection(cardWidth: CGFloat) -> some View {
        ZStack {
            // Enhanced glow effect positioned around the image (matches device tab with enhanced visibility)
            if currentPowerState && device.isOnline {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(max(0.3, brightnessEffect * 0.6)),
                                Color.blue.opacity(max(0.15, brightnessEffect * 0.4)),
                                Color.blue.opacity(max(0.08, brightnessEffect * 0.2)),
                                Color.blue.opacity(max(0.04, brightnessEffect * 0.1)),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .scaleEffect(1.4)
                    .blur(radius: 8 + (brightnessEffect * 4))
                    .shadow(
                        color: Color.blue.opacity(max(0.2, brightnessEffect * 0.4)),
                        radius: 4 + (brightnessEffect * 3),
                        x: 0,
                        y: 0
                    )
                    .shadow(
                        color: Color.blue.opacity(max(0.15, brightnessEffect * 0.3)),
                        radius: 8 + (brightnessEffect * 4),
                        x: 0,
                        y: 0
                    )
                    .shadow(
                        color: Color.blue.opacity(max(0.1, brightnessEffect * 0.2)),
                        radius: 12 + (brightnessEffect * 6),
                        x: 0,
                        y: 0
                    )
                    .animation(.easeInOut(duration: 0.3), value: device.brightness)
                    .animation(.easeInOut(duration: 0.3), value: currentPowerState)
                    .animation(.easeInOut(duration: 0.3), value: device.isOnline)
            }
            
            // Product image with comprehensive brightness effects (matches device tab)
            Group {
                let imageName = DeviceImageManager.shared.getImageName(for: device.id)
                if let customURL = DeviceImageManager.shared.getCustomImageURL(for: imageName),
                   let uiImage = UIImage(contentsOfFile: customURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: cardWidth * 0.85)
            .opacity(imageOpacity)
            .saturation(saturationEffect)
            .brightness(brightnessBoost)
            .scaleEffect(scaleEffect)
            .shadow(color: glowColor, radius: glowRadius)
            .animation(.easeInOut(duration: 0.3), value: device.brightness)
            .animation(.easeInOut(duration: 0.3), value: currentPowerState)
            .animation(.easeInOut(duration: 0.3), value: device.isOnline)
        }
    }

    // MARK: - Brightness Visual Effects (Matching Device Tab with Enhanced Contrast)
    private var imageOpacity: Double {
        if !device.isOnline {
            return 0.3
        } else if !currentPowerState {
            return 0.5
        } else {
            let baseOpacity = 0.9
            let brightnessOpacity = brightnessEffect * 0.15
            return min(1.0, baseOpacity + brightnessOpacity)
        }
    }

    private var saturationEffect: Double {
        if !device.isOnline || !currentPowerState {
            return 0.3
        } else {
            return 0.8 + (brightnessEffect * 0.4)
        }
    }

    private var brightnessBoost: Double {
        if !device.isOnline || !currentPowerState {
            return -0.2
        } else {
            return brightnessEffect * 0.3
        }
    }

    private var scaleEffect: Double {
        if !device.isOnline || !currentPowerState {
            return 0.95
        } else {
            return 1.0 + (brightnessEffect * 0.05)
        }
    }

    private var glowColor: Color {
        if !device.isOnline || !currentPowerState {
            return .clear
        } else {
            return .yellow.opacity(brightnessEffect * 0.6)
        }
    }

    private var glowRadius: CGFloat {
        if !device.isOnline || !currentPowerState {
            return 0
        } else {
            return CGFloat(brightnessEffect * 15)
        }
    }

    // MARK: - Enhanced Power Toggle Button with Coordinated State Management
    private var powerToggleButton: some View {
        Button(action: {
            // Calculate target state BEFORE any state changes
            let targetState = !currentPowerState
            
            // Register UI optimistic state with ViewModel for coordination
            viewModel.registerUIOptimisticState(deviceId: device.id, state: targetState)
            isToggling = true
            
            // Haptic feedback for immediate response
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            Task {
                print("🎯 Dashboard toggle initiated: \(device.id) → \(targetState ? "ON" : "OFF")")
                
                await viewModel.toggleDevicePower(device)
                
                // Allow time for the API call and state propagation
                try? await Task.sleep(nanoseconds: 750_000_000) // 0.75 seconds
                
                // Reset UI state after completion (next runloop tick)
                DispatchQueue.main.async {
                    isToggling = false
                    let finalState = viewModel.getCurrentPowerState(for: device.id)
                    if finalState == targetState {
                        print("✅ Dashboard toggle successful: \(targetState ? "ON" : "OFF")")
                    } else {
                        print("⚠️ Dashboard toggle mismatch - wanted: \(targetState), got: \(finalState)")
                    }
                }
            }
        }) {
            ZStack {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(currentPowerState ? .black : .white)
                    .opacity(isToggling ? 0.7 : 1.0)
                
                // Loading indicator overlay
                if isToggling {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(currentPowerState ? .black : .white)
                }
            }
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(currentPowerState ? .white : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white, lineWidth: currentPowerState ? 0 : 1.5)
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .scaleEffect(isToggling ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isToggling)
            .animation(.easeInOut(duration: 0.2), value: currentPowerState)
        }
        .buttonStyle(.plain)
        .sensorySelection(trigger: isToggling)
        .disabled(!device.isOnline || isToggling)
    }
}

#Preview {
    DashboardView()
        .preferredColorScheme(.dark)
} 