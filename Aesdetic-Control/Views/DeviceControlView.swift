//
//  DeviceControlView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI
import Network
import Foundation

struct DeviceControlView: View {
    @ObservedObject private var viewModel = DeviceControlViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showRealTimeSettings: Bool = false
    @State private var detailPresentation = DeviceDetailPresentationState()
    @State private var detailSourceFrames: [String: CGRect] = [:]
    @State private var setupDevice: WLEDDevice?
    @State private var detailBackgroundDismissEnabledAt: Date = .distantPast
    @State private var selectedLocation: DeviceLocation = .all
    @State private var showManualEntry: Bool = false
    @State private var manualIP: String = ""
    @State private var showDiagnostics: Bool = false
    @State private var diagnosticsTapCount: Int = 0
    @State private var diagnosticsResetWorkItem: DispatchWorkItem?
    @GestureState private var detailDragOffset: CGFloat = 0
    @AppStorage("DeviceListView.showOfflineDevices") private var showOfflineDevices: Bool = true
    private let detailDismissGuardDelay: TimeInterval = 0.45
    private let detailPanelAnimation: Animation = DeviceDetailPresentation.animation

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Enhanced safe area spacing for status bar
                        Spacer()
                            .frame(height: 16)
                        
                        // Header - matching Dashboard style exactly
                        HStack(alignment: .lastTextBaseline, spacing: 12) {
                            Text("Devices")
                                .font(AppTypography.style(.largeTitle, weight: .bold))
                                .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                                .lineLimit(1)
                                .onTapGesture {
                                    handleDiagnosticsTap()
                                }
                            
                            Spacer()
                            
                            // Real-Time Settings Button
                            Button {
                                showRealTimeSettings = true
                            } label: {
                                Image(systemName: "gear")
                                    .font(AppTypography.style(.title2))
                                    .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                            }
                            
                            // Add Device Button
                            Button {
                                showManualEntry = false
                                viewModel.enableActiveHealthChecksIfNeeded()
                                Task { await viewModel.startScanning() }
                            } label: {
                                Image(systemName: "plus")
                                    .font(AppTypography.style(.title2))
                                    .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                            }

                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                        if let discoveryErrorMessage = viewModel.discoveryErrorMessage {
                            ErrorBanner(
                                message: discoveryErrorMessage,
                                actionTitle: discoveryErrorActionTitle(for: discoveryErrorMessage),
                                onAction: { handleDiscoveryErrorAction(for: discoveryErrorMessage) },
                                onDismiss: { viewModel.dismissDiscoveryError() }
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                        }
                    
                    // Location Filter Pills
                    locationFilterPills
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    
                    // Main Content
                    if filteredDevicesByLocation.isEmpty && !viewModel.isScanning {
                        EmptyStateView(
                            onScan: {
                                showManualEntry = false
                                viewModel.enableActiveHealthChecksIfNeeded()
                                Task { await viewModel.startScanning() }
                            },
                            onAddDevice: {
                                showManualEntry = true
                                viewModel.enableActiveHealthChecksIfNeeded()
                                Task { await viewModel.startScanning() }
                            }
                        )
                    } else {
                        // Optional: Show small scanning indicator at top if still scanning
                        if viewModel.isScanning {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Discovering devices...")
                                        .font(AppTypography.style(.caption))
                                        .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
                                    Spacer()
                                    Text("\(viewModel.devices.count) found")
                                        .font(AppTypography.style(.caption))
                                        .foregroundColor(.green)
                                }
                                
                                Text("Listening for WLED devices (mDNS).")
                                    .font(AppTypography.style(.caption2))
                                    .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(DeviceLightPalette.panelFill(colorScheme))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                        }
                        
                        if viewModel.isScanning && viewModel.devices.isEmpty {
                            manualAddRow
                        }
                        
                        DeviceListView(
                            viewModel: viewModel,
                            selectedDevice: $detailPresentation.device,
                            devices: filteredDevicesByLocation,
                            onSelectDevice: openDeviceDetail
                        )
                    }
                    
                        // Bottom spacing to prevent tab bar overlap and shadow clipping
                        Spacer()
                            .frame(height: 16)
                    }
                }
            }
            .coordinateSpace(name: DeviceDetailPresentation.coordinateSpaceName)
            .onPreferenceChange(DeviceDetailSourceFramePreferenceKey.self) { frames in
                detailSourceFrames = frames
            }
            .background(Color.clear)
            .sheet(isPresented: $showRealTimeSettings) {
                RealTimeSettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView(viewModel: viewModel)
            }
            .overlay { deviceDetailOverlay }
            .overlay { productSetupOverlay }
            .navigationBarHidden(true)
            .onReceive(viewModel.$devices) { _ in
                updateAvailableLocations()
                if !viewModel.devices.isEmpty {
                    showManualEntry = false
                }
            }
            .onAppear {
                updateAvailableLocations()
                viewModel.startPassiveDiscovery()
                viewModel.enableActiveHealthChecksIfNeeded()
            }
            .onDisappear {
                detailPresentation.reset()
                detailBackgroundDismissEnabledAt = .distantPast
            }
            .onChange(of: detailPresentation.device?.id) { _, newValue in
                if newValue != nil {
                    // Ignore accidental backdrop tap dismissal from the same opening tap.
                    detailBackgroundDismissEnabledAt = Date().addingTimeInterval(detailDismissGuardDelay)
                } else {
                    detailBackgroundDismissEnabledAt = .distantPast
                }
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var deviceDetailOverlay: some View {
        if let selectedDevice = detailPresentation.device {
            GeometryReader { proxy in
                let liveDragOffset = max(0, detailDragOffset)
                let dragOffset = liveDragOffset > 0 ? liveDragOffset : detailPresentation.closingDragOffset
                let panelTopPadding: CGFloat = 4
                let panelHorizontalPadding: CGFloat = 8
                let dockOverlapAllowance: CGFloat = 0
                let panelWidth = max(1, proxy.size.width - (panelHorizontalPadding * 2))
                let panelHeight = max(420, proxy.size.height - proxy.safeAreaInsets.bottom - panelTopPadding + dockOverlapAllowance)
                let panelFrame = CGRect(
                    x: panelHorizontalPadding,
                    y: panelTopPadding,
                    width: panelWidth,
                    height: panelHeight
                )
                let presentationProgress = DeviceDetailPresentation.interactiveProgress(
                    isPresented: detailPresentation.isPresented,
                    dragOffset: dragOffset
                )
                let morphFrame = DeviceDetailPresentation.morphFrame(
                    sourceFrame: detailPresentation.sourceFrame,
                    panelFrame: panelFrame,
                    progress: presentationProgress
                )
                let morphCornerRadius = DeviceDetailPresentation.cornerRadius(
                    sourceFrame: detailPresentation.sourceFrame,
                    progress: presentationProgress
                )
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .ignoresSafeArea()
                        .allowsHitTesting(canDismissDetailFromBackground && detailPresentation.isPresented && !detailPresentation.isClosing)
                        .onTapGesture {
                            closeDeviceDetail()
                        }

                    DeviceDetailView(
                        device: selectedDevice,
                        viewModel: viewModel,
                        backgroundStyle: .liquidGlass,
                        containerCornerRadius: morphCornerRadius,
                        presentationProgress: presentationProgress,
                        onClose: { closeDeviceDetail() }
                    )
                    .frame(width: morphFrame.width, height: morphFrame.height, alignment: .top)
                    .position(x: morphFrame.midX, y: morphFrame.midY)
                    .opacity(Double(0.18 + (0.82 * presentationProgress)))
                    .simultaneousGesture(detailCollapseDragGesture)
                }
            }
            .zIndex(2)
        }
    }

    private var canDismissDetailFromBackground: Bool {
        Date() >= detailBackgroundDismissEnabledAt
    }

    private var detailCollapseDragGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .updating($detailDragOffset) { value, state, _ in
                let translation = value.translation
                guard DeviceDetailPresentation.canStartDismissGesture(at: value.startLocation),
                      translation.height > 0,
                      translation.height > abs(translation.width) * 0.8 else {
                    return
                }
                state = min(translation.height, 220)
            }
            .onEnded { value in
                let translation = value.translation
                let predictedDrop = value.predictedEndTranslation.height - translation.height
                guard DeviceDetailPresentation.canStartDismissGesture(at: value.startLocation),
                      translation.height > 0,
                      translation.height > abs(translation.width) * 0.8 else {
                    return
                }
                if translation.height > 150 || predictedDrop > 220 {
                    closeDeviceDetail(fromDragOffset: min(translation.height, 220))
                }
            }
    }

    @ViewBuilder
    private var productSetupOverlay: some View {
        if let setupDevice {
            GeometryReader { proxy in
                let maxPopupHeight = max(320, proxy.size.height - proxy.safeAreaInsets.bottom - 80)
                ZStack(alignment: .top) {
                    SetupBackdropBlur()

                    ProductSetupFlowView(
                        device: setupDevice,
                        onClose: { self.setupDevice = nil },
                        allowsManualClose: false
                    )
                    .environmentObject(viewModel)
                    .frame(maxHeight: maxPopupHeight, alignment: .top)
                    .padding(.horizontal, 16)
                    .padding(.top, 26)
                }
            }
            .transition(.identity)
            .zIndex(3)
        }
    }

    private func closeDeviceDetail(fromDragOffset dragOffset: CGFloat = 0, animated: Bool = true) {
        guard detailPresentation.device != nil else {
            detailBackgroundDismissEnabledAt = .distantPast
            return
        }
        guard animated else {
            detailPresentation.reset()
            detailBackgroundDismissEnabledAt = .distantPast
            return
        }

        detailPresentation.isClosing = true
        detailPresentation.closingDragOffset = max(0, dragOffset)
        withAnimation(detailPanelAnimation) {
            detailPresentation.isPresented = false
            detailPresentation.closingDragOffset = 0
        } completion: {
            detailPresentation.reset()
            detailBackgroundDismissEnabledAt = .distantPast
        }
    }

    private func openDeviceDetail(_ device: WLEDDevice) {
        if viewModel.requiresProfileSetup(device) {
            closeDeviceDetail(animated: false)
            setupDevice = device
            return
        }
        detailBackgroundDismissEnabledAt = Date().addingTimeInterval(detailDismissGuardDelay)
        detailPresentation.prepare(device: device, sourceFrame: detailSourceFrames[device.id])
        DispatchQueue.main.async {
            withAnimation(detailPanelAnimation) {
                detailPresentation.isPresented = true
            }
        }
    }

    // MARK: - Helper Properties
    
    
    private var realTimeStatusColor: Color {
        guard viewModel.isRealTimeEnabled else { return .gray }
        
        switch viewModel.webSocketConnectionStatus {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .limitReached:
            return .purple
        case .disconnected:
            return .red
        }
    }
    
    // MARK: - Filtered Devices

    private var filteredDevicesByLocation: [WLEDDevice] {
        var devices = viewModel.devices
        if selectedLocation != .all {
            devices = devices.filter { $0.location == selectedLocation }
        }
        if !showOfflineDevices {
            devices = devices.filter { $0.isOnline }
        }
        return devices
    }
    
    @State private var cachedAvailableLocations: [DeviceLocation] = [.all, .livingRoom, .bedroom]
    
    private var availableLocations: [DeviceLocation] {
        return cachedAvailableLocations
    }
    
    // MARK: - Location Filter Pills
    
    private var locationFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableLocations, id: \.self) { location in
                    LocationPillButton(
                        location: location,
                        isSelected: selectedLocation == location,
                        deviceCount: deviceCount(for: location)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedLocation = location
                        }
                    }
                }
            }
        }
    }
    
    private func deviceCount(for location: DeviceLocation) -> Int {
        if location == .all {
            return viewModel.devices.count
        }
        return viewModel.devices.filter { $0.location == location }.count
    }

    private func handleDiagnosticsTap() {
        diagnosticsTapCount += 1
        diagnosticsResetWorkItem?.cancel()
        let resetTask = DispatchWorkItem { diagnosticsTapCount = 0 }
        diagnosticsResetWorkItem = resetTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: resetTask)

        if diagnosticsTapCount >= 7 {
            diagnosticsTapCount = 0
            diagnosticsResetWorkItem?.cancel()
            diagnosticsResetWorkItem = nil
            showDiagnostics = true
        }
    }
    
    private func updateAvailableLocations() {
        // Get all unique locations from devices, plus the default ones
        let deviceLocations = Set(viewModel.devices.map { $0.location })
        let defaultLocations: [DeviceLocation] = [.all, .livingRoom, .bedroom]
        
        // Load custom locations from UserDefaults
        let customLocations: [DeviceLocation] = {
            guard let data = UserDefaults.standard.data(forKey: "customLocations"),
                  let customLocs = try? JSONDecoder().decode([CustomLocation].self, from: data) else {
                return []
            }
            return customLocs.map { .custom($0.name) }
        }()
        
        // Combine and sort
        let allLocations = deviceLocations.union(Set(defaultLocations)).union(Set(customLocations))
        let sortedLocations = allLocations.sorted { first, second in
            // Sort with "All" first, then alphabetically
            if first == .all { return true }
            if second == .all { return false }
            return first.displayName < second.displayName
        }
        
        // Only update if changed to avoid unnecessary view updates
        if sortedLocations != cachedAvailableLocations {
            cachedAvailableLocations = sortedLocations
        }
    }
    
    private var manualAddRow: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add device manually")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                
                Spacer()
                
                Button(showManualEntry ? "Hide" : "Enter IP") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showManualEntry.toggle()
                    }
                }
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.blue)
            }
            
            if showManualEntry {
                HStack(spacing: 12) {
                    TextField("192.168.1.100", text: $manualIP)
                        .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(DeviceLightPalette.fieldFill(colorScheme))
                        .cornerRadius(10)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    Button("Add") {
                        guard !manualIP.isEmpty else { return }
                        viewModel.addDeviceByIP(manualIP)
                        manualIP = ""
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(manualIP.isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DeviceLightPalette.panelFill(colorScheme))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

// MARK: - Location Pill Button

struct LocationPillButton: View {
    let location: DeviceLocation
    let isSelected: Bool
    let deviceCount: Int
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var surfaceStyle: GlassSurfaceStyle { GlassTheme.surfaces(for: colorScheme) }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(location.displayName)
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .foregroundColor(DeviceLightPalette.pillText(colorScheme, isSelected: isSelected))
                
                if deviceCount > 0 {
                    Text("\(deviceCount)")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(DeviceLightPalette.pillSubtext(colorScheme, isSelected: isSelected))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                }
            }
            .appLiquidGlass(role: .control, cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}




// MARK: - Empty State View

struct EmptyStateView: View {
    let onScan: () -> Void
    let onAddDevice: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "lightbulb.slash")
                .font(AppTypography.style(.largeTitle))
                .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
            
            // Title and Description
            VStack(spacing: 8) {
                Text("No WLED Devices Found")
                    .font(AppTypography.style(.title2))
                    .fontWeight(.semibold)
                    .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                
                Text("Make sure your WLED devices are powered on and connected to the same WiFi network.")
                    .font(AppTypography.style(.body))
                    .foregroundColor(DeviceLightPalette.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Action Buttons
            VStack(spacing: 12) {
                Button("Scan for Devices") {
                    onScan()
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button("Add Device Manually") {
                    onAddDevice()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Enhanced Scanning State View

struct ScanningStateView: View {
    let progress: String
    let devicesFound: Int
    let lastDiscoveryTime: Date?
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var animationProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated scanning icon
            VStack(spacing: 16) {
                ZStack {
                    // Outer scanning ring
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                        .frame(width: 100, height: 100)
                    
                    // Animated scanning ring
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(animationProgress * 360))
                        .animation(
                            Animation.linear(duration: 2)
                                .repeatForever(autoreverses: false),
                            value: animationProgress
                        )
                    
                    // Inner icon
                    Image(systemName: "wifi")
                        .font(AppTypography.style(.title, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            
            // Progress text and status
            VStack(spacing: 16) {
                Text("Discovering WLED Devices")
                    .font(AppTypography.style(.title2))
                    .fontWeight(.semibold)
                    .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                
                Text(progress)
                    .font(AppTypography.style(.body))
                    .foregroundColor(DeviceLightPalette.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: progress)
                
                // Devices found counter
                if devicesFound > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Text("Found \(devicesFound) device\(devicesFound == 1 ? "" : "s")")
                            .font(AppTypography.style(.caption))
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            // Discovery methods info
            VStack(spacing: 12) {
                Text("Using multiple discovery methods:")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
                
                HStack(spacing: 20) {
                    DiscoveryMethodBadge(
                        icon: "network",
                        title: "mDNS",
                        description: "Bonjour/Zeroconf"
                    )
                    
                    DiscoveryMethodBadge(
                        icon: "dot.radiowaves.left.and.right",
                        title: "UDP",
                        description: "Broadcast"
                    )
                    
                    DiscoveryMethodBadge(
                        icon: "globe",
                        title: "IP Scan",
                        description: "Network ranges"
                    )
                }
            }
            .padding(.top, 8)
            
            // Last discovery time
            if let lastTime = lastDiscoveryTime {
                Text("Last scan: \(formatRelativeTime(lastTime))")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 32)
        .onAppear {
            animationProgress = 1
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct DiscoveryMethodBadge: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppTypography.style(.caption))
                .foregroundColor(.blue)
            
            Text(title)
                .font(AppTypography.style(.caption2))
                .fontWeight(.medium)
                .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
            
            Text(description)
                .font(AppTypography.style(.caption2))
                .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DeviceLightPalette.panelFill(colorScheme))
        .cornerRadius(8)
    }
}

// MARK: - Button Styles

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}


// MARK: - Add Device Sheet

struct AddDeviceSheet: View {
    let viewModel: DeviceControlViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var manualIP: String = ""
    @State private var isScanning: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                
                if isScanning {
                    // Show enhanced scanning progress
                    VStack(spacing: 24) {
                        ScanningStateView(
                            progress: viewModel.wledService.discoveryProgress,
                            devicesFound: viewModel.devices.count,
                            lastDiscoveryTime: viewModel.wledService.lastDiscoveryTime
                        )
                        
                        Button("Stop Scanning") {
                            viewModel.wledService.stopDiscovery()
                            isScanning = false
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    VStack(spacing: 24) {
                        // Auto Discovery Section
                        VStack(spacing: 16) {
                            Text("Auto Discovery")
                                .font(AppTypography.style(.title2))
                                .fontWeight(.semibold)
                                .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                                
                            Text("Automatically scan your network for WLED devices using mDNS, UDP broadcasts, and IP scanning")
                                .font(AppTypography.style(.body))
                                .foregroundColor(DeviceLightPalette.textSecondary(colorScheme))
                                .multilineTextAlignment(.center)
                            
                            Button("Start Comprehensive Scan") {
                                Task {
                                    isScanning = true
                                    await viewModel.startScanning()
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
                                .padding(.horizontal, 16)
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                        }
                        
                        // Manual Entry Section
                        VStack(spacing: 16) {
                            Text("Manual Entry")
                                .font(AppTypography.style(.title2))
                                .fontWeight(.semibold)
                                .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                            
                            Text("Enter the IP address of your WLED device if auto-discovery doesn't find it")
                                .font(AppTypography.style(.body))
                                .foregroundColor(DeviceLightPalette.textSecondary(colorScheme))
                                .multilineTextAlignment(.center)
                            
                            TextField("192.168.1.100", text: $manualIP)
                                .foregroundColor(DeviceLightPalette.textPrimary(colorScheme))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(DeviceLightPalette.fieldFill(colorScheme))
                                .cornerRadius(12)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            
                            Button("Add Device") {
                                if !manualIP.isEmpty {
                                    viewModel.addDeviceByIP(manualIP)
                                    dismiss()
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(manualIP.isEmpty)
                        }
                        
                        Spacer()
                        
                        // Tips section
                        VStack(spacing: 8) {
                            Text("💡 Tips for finding your WLED device:")
                                .font(AppTypography.style(.caption))
                                .fontWeight(.medium)
                                .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
                            
                            Text("• Check your router's device list\n• Look for devices named 'WLED' or 'ESP'\n• Try accessing the WLED web interface\n• Use a network scanner app")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(DeviceLightPalette.textTertiary(colorScheme))
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .background(DeviceLightPalette.panelFill(colorScheme))
                        .cornerRadius(12)
                    }
                }
            }
            .navigationTitle("Add WLED Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isScanning {
                            viewModel.wledService.stopDiscovery()
                        }
                        dismiss()
                    }
                }
            }
        }
        .onReceive(viewModel.wledService.$isScanning) { scanning in
            if !scanning && isScanning {
                // Auto-dismiss after successful scan if devices were found
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !viewModel.devices.isEmpty {
                        dismiss()
                    } else {
                        isScanning = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private enum DeviceLightPalette {
    static func textPrimary(_ scheme: ColorScheme) -> Color {
        GlassTheme.text(for: scheme).pagePrimaryText
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        GlassTheme.text(for: scheme).pageSecondaryText
    }

    static func textTertiary(_ scheme: ColorScheme) -> Color {
        GlassTheme.text(for: scheme).pageTertiaryText
    }

    static func pillFill(_ scheme: ColorScheme, isSelected: Bool) -> Color {
        let style = GlassTheme.surfaces(for: scheme)
        return isSelected ? style.pillFillSelected : style.pillFillDefault
    }

    static func pillStroke(_ scheme: ColorScheme, isSelected: Bool) -> Color {
        if scheme == .dark && isSelected {
            return .clear
        }
        return GlassTheme.surfaces(for: scheme).pillStroke
    }

    static func pillText(_ scheme: ColorScheme, isSelected: Bool) -> Color {
        let style = GlassTheme.text(for: scheme)
        return isSelected ? style.pillTextSelected : style.pillTextDefault
    }

    static func pillSubtext(_ scheme: ColorScheme, isSelected: Bool) -> Color {
        let style = GlassTheme.text(for: scheme)
        return isSelected ? style.pillSubtextSelected : style.pillSubtextDefault
    }

    static func fieldFill(_ scheme: ColorScheme) -> Color {
        GlassTheme.surfaces(for: scheme).fieldFill
    }

    static func panelFill(_ scheme: ColorScheme) -> Color {
        GlassTheme.surfaces(for: scheme).panelFill
    }
}

private extension DeviceControlView {
    func discoveryErrorActionTitle(for message: String) -> String? {
        let lower = message.lowercased()
        if lower.contains("local network") || lower.contains("permission") {
            return "Open Settings"
        }
        return "Rescan"
    }
    
    func handleDiscoveryErrorAction(for message: String) {
        let lower = message.lowercased()
        if lower.contains("local network") || lower.contains("permission") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            viewModel.enableActiveHealthChecksIfNeeded()
            Task { await viewModel.startScanning() }
        }
    }
}


struct DeviceControlView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceControlView()
    }
}
