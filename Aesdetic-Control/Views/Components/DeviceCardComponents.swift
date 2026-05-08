//
//  DeviceCardComponents.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI
import Foundation

enum DeviceDetailPresentation {
    static let coordinateSpaceName = "device-detail-presentation"
    static let animation = Animation.spring(response: 0.54, dampingFraction: 0.91, blendDuration: 0.1)
    static let expandedCornerRadius: CGFloat = 30
    static let dismissGestureActivationHeight: CGFloat = 168

    static func interactiveProgress(isPresented: Bool, dragOffset: CGFloat) -> CGFloat {
        let baseProgress: CGFloat = isPresented ? 1 : 0
        guard isPresented, dragOffset > 0 else { return baseProgress }

        let collapseAmount = min(max(dragOffset, 0), 260) / 260
        let softenedCollapse = collapseAmount * collapseAmount * (3 - (2 * collapseAmount))
        return max(0.46, baseProgress - (softenedCollapse * 0.54))
    }

    static func canStartDismissGesture(at startLocation: CGPoint) -> Bool {
        startLocation.y <= dismissGestureActivationHeight
    }

    static func sourceCornerRadius(for sourceFrame: CGRect?) -> CGFloat {
        guard let sourceFrame else { return 20 }
        return abs(sourceFrame.width - sourceFrame.height) < 24 ? 20 : 16
    }

    static func fallbackSourceFrame(for panelFrame: CGRect) -> CGRect {
        CGRect(
            x: panelFrame.minX + 18,
            y: panelFrame.maxY - 178,
            width: max(1, panelFrame.width - 36),
            height: 158
        )
    }

    static func morphFrame(sourceFrame: CGRect?, panelFrame: CGRect, progress: CGFloat) -> CGRect {
        let source = sourceFrame ?? fallbackSourceFrame(for: panelFrame)
        let clampedProgress = min(1, max(0, progress))

        return CGRect(
            x: source.minX + ((panelFrame.minX - source.minX) * clampedProgress),
            y: source.minY + ((panelFrame.minY - source.minY) * clampedProgress),
            width: source.width + ((panelFrame.width - source.width) * clampedProgress),
            height: source.height + ((panelFrame.height - source.height) * clampedProgress)
        )
    }

    static func cornerRadius(sourceFrame: CGRect?, progress: CGFloat) -> CGFloat {
        let sourceRadius = sourceCornerRadius(for: sourceFrame)
        let clampedProgress = min(1, max(0, progress))
        return sourceRadius + ((expandedCornerRadius - sourceRadius) * clampedProgress)
    }
}

struct DeviceDetailPresentationState {
    var device: WLEDDevice?
    var sourceFrame: CGRect?
    var isPresented = false
    var isClosing = false
    var closingDragOffset: CGFloat = 0

    mutating func prepare(device: WLEDDevice, sourceFrame: CGRect?) {
        self.device = device
        self.sourceFrame = sourceFrame
        isPresented = false
        isClosing = false
        closingDragOffset = 0
    }

    mutating func reset() {
        device = nil
        sourceFrame = nil
        isPresented = false
        isClosing = false
        closingDragOffset = 0
    }
}

struct DeviceDetailSourceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct DeviceDetailSourceFrameModifier: ViewModifier {
    let deviceId: String

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: DeviceDetailSourceFramePreferenceKey.self,
                            value: [
                                deviceId: proxy.frame(in: .named(DeviceDetailPresentation.coordinateSpaceName))
                            ]
                        )
                }
            }
    }
}

extension View {
    func deviceDetailSourceFrame(deviceId: String) -> some View {
        modifier(DeviceDetailSourceFrameModifier(deviceId: deviceId))
    }
}

// MARK: - Performance Configuration

struct PerformanceConfig {
    static let enableAnimations = true // Feature flag for animations
    static let enableTransitions = true // Feature flag for transitions
    static let animationDuration: Double = 0.2
    static let transitionDuration: Double = 0.3
}

// MARK: - Enhanced Device Card with Modern Design

struct EnhancedDeviceCard: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    let device: WLEDDevice
    let viewModel: DeviceControlViewModel
    let onTap: () -> Void
    
    // Local state for interactive controls
    @State private var localBrightness: Double
    @State private var isControlling: Bool = false
    @State private var brightnessUpdateTimer: Timer?
    @State private var lastBrightnessSet: Date? = nil
    @State private var showImagePicker: Bool = false
    @State private var isToggling: Bool = false
    
    // Performance optimization: Memoized computed properties
    private let deviceId: String
    private let animationDuration: Double = PerformanceConfig.animationDuration
    
    // Initialize local state from device
    init(
        device: WLEDDevice,
        viewModel: DeviceControlViewModel,
        onTap: @escaping () -> Void
    ) {
        self.device = device
        self.viewModel = viewModel
        self.onTap = onTap
        self.deviceId = device.id
        self._localBrightness = State(initialValue: Double(device.brightness))
    }
    
    // Use coordinated power state from ViewModel - optimized with memoization
    private var currentPowerState: Bool {
        return viewModel.getCurrentPowerState(for: deviceId)
    }
    
    // Optimized brightness effect calculation
    private var brightnessEffect: Double {
        guard currentPowerState && device.isOnline else { return 0 }
        return Double(device.brightness) / 255.0
    }
    
    // Memoized device status for performance
    private var deviceStatus: (isOnline: Bool, isOn: Bool) {
        (device.isOnline, currentPowerState)
    }

    private var activeRunStatus: ActiveRunStatus? {
        viewModel.activeRunStatus[device.id]
    }
    private var requiresSetup: Bool {
        device.setupState == .pendingSelection
    }
    
    private let cardHeight: CGFloat = 193
    private let controlHeight: CGFloat = 28
    private let controlCornerRadius: CGFloat = 8
    private var glassSurface: GlassSurfaceStyle { GlassTheme.surfaces(for: colorScheme) }
    private var glassText: GlassTextStyle { GlassTheme.text(for: colorScheme) }
    private var isReferenceLightMode: Bool { colorScheme == .light }
    private var cardPrimaryTextColor: Color { .white.opacity(0.96) }
    private var cardSecondaryTextColor: Color { .white.opacity(0.86) }

    var body: some View {
        ZStack {
            // Product image as background element, aligned bottom-right
            productImageSection
            
            // Content layered on top - all interactive elements
            VStack(spacing: 0) {
                // Header section
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                // Push brightness to bottom with more spacing
                Spacer()
                Spacer(minLength: 8) // Additional spacing before brightness section
                
                // Brightness section - aligned to bottom with consistent margin
                if currentPowerState {
                    brightnessSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20) // Same margin as top/sides for consistency
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
        .appLiquidGlass(role: .card, cornerRadius: 16)
        .deviceDetailSourceFrame(deviceId: device.id)
        .overlay {
            if requiresSetup {
                Button(action: onTap) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete setup for \(device.name)")
            }
        }
        .contentShape(Rectangle())
        // .onTapGesture removed - NavigationLink in DeviceListView handles navigation
        // This allows the card's interactive controls (power, brightness) to work independently
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceUpdated"))) { _ in
            syncWithDeviceState()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerSheet(deviceId: device.id)
        }
        .onAppear {
            syncWithDeviceState()
        }
        // CRITICAL: Watch device brightness changes directly for immediate UI sync
        // This ensures UI follows device brightness changes without lag
        .onChange(of: device.brightness) { oldValue, newValue in
            // Only sync if we're not actively controlling and not recently set
            let now = Date()
            let canSync = !isControlling && (lastBrightnessSet == nil || now.timeIntervalSince(lastBrightnessSet!) > 1.0)
            if canSync {
                // CRITICAL: Use effective brightness (preserved brightness if device is off)
                // This prevents UI from jumping to 0 when device is turned off
                let effectiveBrightness = viewModel.getEffectiveBrightness(for: device)
                let deviceBrightness = Double(effectiveBrightness)
                // Reduced threshold for more responsive sync
                if abs(localBrightness - deviceBrightness) > 5 {
                    localBrightness = deviceBrightness
                }
            }
        }
        .onDisappear {
            // Clean up timers to prevent memory leaks
            brightnessUpdateTimer?.invalidate()
            brightnessUpdateTimer = nil
        }
    }
    
    private var productImageSection: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    ProductImageWithBrightness(
                        brightness: Double(device.brightness),
                        isOn: currentPowerState,
                        isOnline: device.isOnline,
                        deviceId: device.id
                    )
                    .frame(
                        width: geometry.size.width * 0.5,
                        height: geometry.size.height * 0.5
                    )
                    .offset(x: 20, y: 20)
                    .opacity(currentPowerState && device.isOnline ? 1.0 : 0.5)
                }
            }
        }
        .clipped()
    }
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(device.name)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(cardPrimaryTextColor)
                    .opacity(device.isOnline ? 1.0 : 0.58)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                
                VStack(alignment: .leading, spacing: 5) {
                    statusIndicator

                    if let run = activeRunStatus {
                        runStatusChip(run)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()

            powerButton
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func runStatusChip(_ run: ActiveRunStatus) -> some View {
        Text(runStatusText(run))
            .font(AppTypography.style(.caption2))
            .foregroundColor(cardSecondaryTextColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    private func runStatusText(_ run: ActiveRunStatus) -> String {
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
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(device.isOnline ? Color.white : Color.clear)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.95), lineWidth: 1.4)
                )
                .frame(width: 8, height: 8)
        }
        .opacity(device.isOnline ? 1.0 : 0.58)
    }

    private var powerButton: some View {
        Button(action: {
            if requiresSetup {
                onTap()
                return
            }
            // Calculate target state BEFORE any state changes
            let targetState = !currentPowerState

            // CRITICAL: Set optimistic state BEFORE calling toggleDevicePower
            // This ensures toggleDevicePower uses the correct target state
            viewModel.setUIOptimisticState(deviceId: device.id, isOn: targetState)

            // If device appears offline but we're trying to control it, mark it as online
            // This handles cases where discovery set isOnline=true but UI hasn't updated yet
            if !device.isOnline {
                viewModel.markDeviceOnline(device.id)
            }

            isToggling = true

            // Haptic feedback for immediate response
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            Task {
                await viewModel.toggleDevicePower(device)
                let settled = await viewModel.awaitPowerToggleSettlement(for: device, targetState: targetState)

                // Reset UI state after completion
                await MainActor.run {
                    isToggling = false

                    // ViewModel will handle state cleanup automatically
                    // UI will reflect the coordinated state through currentPowerState
                    let finalState = viewModel.getCurrentPowerState(for: deviceId)

                    if settled && finalState == targetState {
                        #if DEBUG
                        print("✅ Device tab toggle successful: \(targetState ? "ON" : "OFF")")
                        #endif
                    } else {
                        #if DEBUG
                        print("⚠️ Device tab toggle mismatch - wanted: \(targetState), got: \(finalState)")
                        #endif
                    }
                }
            }
        }) {
            ZStack {
                Image(systemName: "power")
                    .font(AppTypography.style(.headline, weight: .medium))
                    .foregroundColor(powerIconColor)
                    .opacity(isToggling ? 0.7 : 1.0)

                // Loading indicator overlay
                if isToggling {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(
                            isReferenceLightMode
                                ? AppTheme.controlForeground(for: colorScheme, isActive: currentPowerState)
                                : powerIconColor
                        )
                }
            }
            .frame(width: 36, height: 36)
            .background(
                Group {
                    if isReferenceLightMode {
                        Circle()
                            .fill(Color.white.opacity(currentPowerState ? 0.14 : 0.08))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(currentPowerState ? 0.20 : 0.11), lineWidth: 0.9)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(currentPowerState ? .white : .clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(colorScheme == .dark ? .white : .clear, lineWidth: currentPowerState ? 0 : 1.5)
                            )
                    }
                }
            )
            .shadow(
                color: glassSurface.controlShadowAmbient.color,
                radius: glassSurface.controlShadowAmbient.radius,
                x: glassSurface.controlShadowAmbient.x,
                y: glassSurface.controlShadowAmbient.y
            )
            .shadow(
                color: glassSurface.controlShadowKey.color,
                radius: glassSurface.controlShadowKey.radius,
                x: glassSurface.controlShadowKey.x,
                y: glassSurface.controlShadowKey.y
            )
            .scaleEffect(isToggling ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isToggling)
            .animation(.easeInOut(duration: 0.2), value: currentPowerState)
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel("Power")
        .accessibilityValue(currentPowerState ? "On" : "Off")
        .accessibilityHint(currentPowerState ? "Double tap to turn the device off." : "Double tap to turn the device on.")
        .sensorySelection(trigger: isToggling)
        .disabled(!device.isOnline || isToggling || requiresSetup)
    }
    

    
    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                Text("Brightness")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(cardSecondaryTextColor)
                
                Spacer()
            }
            
            HStack(alignment: .center, spacing: 8) {
                brightnessBar

                imageChangeButton
            }
        }
    }

    private var imageChangeButton: some View {
        Button(action: {
            showImagePicker = true
        }) {
            Image(systemName: "pencil")
                .font(AppTypography.style(.caption))
                .foregroundColor(cardSecondaryTextColor)
                .frame(width: controlHeight, height: controlHeight)
                .background {
                    subtleControlGlassBackground(cornerRadius: controlCornerRadius)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change device image")
        .accessibilityHint("Choose a different product image for this device.")
        .sensorySelection(trigger: showImagePicker)
        .disabled(requiresSetup)
    }
    
    private var brightnessBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.03 : 0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08), lineWidth: 0.8)
                    )
                    .frame(height: controlHeight)
                
                // Progress fill
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(progressFill)
                    .frame(width: max(controlHeight, geometry.size.width * CGFloat(localBrightness / 255.0)), height: controlHeight)
                .animation(PerformanceConfig.enableAnimations ? .easeInOut(duration: 0.1) : nil, value: Int(localBrightness / 5.0))

                // Brightness percentage text
                HStack {
                    Text("\(Int(localBrightness / 255.0 * 100))%")
                        .font(AppTypography.style(.caption, weight: .medium))
                        .foregroundColor(progressLabelColor)
                        .padding(.leading, 8)
                    Spacer()
                }
            }
            .background {
                subtleControlGlassBackground(cornerRadius: controlCornerRadius)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isControlling = true
                        let percentage = max(0, min(1, value.location.x / geometry.size.width))
                        let newBrightness = percentage * 255.0
                    
                    // Only update if change is significant enough (increased threshold for better performance)
                    if abs(newBrightness - localBrightness) >= 10 {
                        localBrightness = newBrightness
                        
                        // Cancel previous timer and create new one with longer interval for better performance
                        brightnessUpdateTimer?.invalidate()
                        brightnessUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            Task { await updateBrightness() }
                        }
                    }
                }
                .onEnded { _ in
                    // Final update when gesture ends
                    brightnessUpdateTimer?.invalidate()
                    Task {
                        await updateBrightness()
                    }
                }
            )
            .disabled(!device.isOnline || !currentPowerState || requiresSetup)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Brightness")
            .accessibilityValue("\(Int(round(localBrightness / 255.0 * 100))) percent")
            .accessibilityHint("Swipe up or down to adjust brightness for \(device.name).")
            .accessibilityAdjustableAction { direction in
                let step: Double = 12.75
                switch direction {
                case .increment:
                    localBrightness = min(255, localBrightness + step)
                case .decrement:
                    localBrightness = max(0, localBrightness - step)
                @unknown default:
                    break
                }
                brightnessUpdateTimer?.invalidate()
                Task { await updateBrightness() }
            }
            .accessibilityHidden(!device.isOnline || !currentPowerState || requiresSetup)
        }
        .frame(height: controlHeight)
        .onDisappear {
            // Flush any pending brightness updates when view disappears
            brightnessUpdateTimer?.invalidate()
            if isControlling {
                Task {
                    await updateBrightness()
                }
            }
        }
    }

    @ViewBuilder
    private func subtleControlGlassBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.001))
            .appLiquidGlass(role: .control, cornerRadius: cornerRadius)
            .opacity(colorScheme == .dark ? 0.62 : 0.58)
    }
    
    private var cardFill: Color {
        if colorSchemeContrast == .increased {
            if colorScheme == .dark {
                return Color.white.opacity(currentPowerState ? 0.18 : 0.12)
            }
            return Color.white.opacity(currentPowerState ? 0.28 : 0.22)
        }
        return currentPowerState ? glassSurface.cardFillActive : glassSurface.cardFillInactive
    }

    private var cardStyle: AppCardStyle {
        if colorSchemeContrast == .increased {
            return AppCardStyle(
                cornerRadius: 16,
                fill: cardFill,
                outerStroke: borderStrokeOuter,
                innerStroke: borderStrokeInner,
                keyShadow: cardShadowKey,
                ambientShadow: cardShadowAmbient
            )
        }

        return AppCardStyles.glass(
            for: colorScheme,
            tone: currentPowerState ? .active : .inactive,
            cornerRadius: 16
        )
    }

    private var powerIconColor: Color {
        if isReferenceLightMode {
            return Color.white.opacity(currentPowerState ? 0.90 : 0.72)
        }
        if !currentPowerState {
            return .white
        }
        return colorScheme == .dark ? .black : glassText.pagePrimaryText
    }

    private var borderStrokeOuter: Color {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.11)
        }
        return glassSurface.cardStrokeOuter
    }

    private var borderStrokeInner: Color {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.36)
        }
        return glassSurface.cardStrokeInner
    }

    private var cardShadowKey: GlassShadowStyle {
        if colorSchemeContrast == .increased {
            if colorScheme == .dark {
                return GlassShadowStyle(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 5)
            }
            return GlassShadowStyle(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 12)
        }
        return glassSurface.cardShadowKey
    }

    private var cardShadowAmbient: GlassShadowStyle {
        if colorSchemeContrast == .increased {
            if colorScheme == .dark {
                return GlassShadowStyle(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 1)
            }
            return GlassShadowStyle(color: Color.black.opacity(0.07), radius: 6, x: 0, y: 2)
        }
        return glassSurface.cardShadowAmbient
    }

    private var progressFill: LinearGradient {
        let startOpacity = colorSchemeContrast == .increased ? 1.0 : 0.7
        return LinearGradient(
            colors: [device.currentColor.opacity(startOpacity), device.currentColor],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var progressLabelColor: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 1.0 : 0.94)
    }
    
    private func syncWithDeviceState() {
        guard let updatedDevice = viewModel.devices.first(where: { $0.id == deviceId }) else { return }
        
        // Only sync if we're not actively controlling and not recently set
        let now = Date()
        let canSync = !isControlling && (lastBrightnessSet == nil || now.timeIntervalSince(lastBrightnessSet!) > 1.0)  // Reduced from 2.0s to 1.0s for faster sync
        if canSync {
            // CRITICAL: Use effective brightness (preserved brightness if device is off)
            // This prevents UI from jumping to 0 when device is turned off
            let effectiveBrightness = viewModel.getEffectiveBrightness(for: updatedDevice)
            let deviceBrightness = Double(effectiveBrightness)
            // CRITICAL: Reduced threshold from 20 to 5 for more responsive UI sync
            // This prevents UI from showing wrong brightness when device brightness changes
            if abs(localBrightness - deviceBrightness) > 5 {
                localBrightness = deviceBrightness
            }
        }
    }
    
    private func updateBrightness() async {
        let brightnessToSet = Int(localBrightness)
        lastBrightnessSet = Date()
        isControlling = false
        
        await viewModel.updateDeviceBrightness(device, brightness: brightnessToSet)
    }
}

// MARK: - Product Image Component

struct ProductImageWithBrightness: View {
    let brightness: Double
    let isOn: Bool
    let isOnline: Bool
    let deviceId: String
    @State private var selectedImageName: String = "product_image"
    
    var body: some View {
        ZStack {
            // Product image from assets or custom uploaded image
            Group {
                if let customURL = DeviceImageManager.shared.getCustomImageURL(for: selectedImageName),
                   let uiImage = UIImage(contentsOfFile: customURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(selectedImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .opacity(imageOpacity)
            .saturation(saturationEffect)
            .brightness(brightnessBoost)
            .scaleEffect(scaleEffect)
            .shadow(color: glowColor, radius: glowRadius)
            .animation(PerformanceConfig.enableAnimations ? .easeInOut(duration: PerformanceConfig.animationDuration) : nil, value: isOn)
            .onDisappear {
                // Clear image cache when view disappears to free memory
                if let customURL = DeviceImageManager.shared.getCustomImageURL(for: selectedImageName) {
                    // Force image deallocation
                    _ = try? FileManager.default.removeItem(at: customURL)
                }
            }
        }
        .onAppear {
            selectedImageName = DeviceImageManager.shared.getImageName(for: deviceId)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceImageChanged"))) { notification in
            if let changedDeviceId = notification.object as? String, changedDeviceId == deviceId {
                selectedImageName = DeviceImageManager.shared.getImageName(for: deviceId)
            }
        }
    }
    
    private var imageOpacity: Double {
        if !isOnline {
            return 0.3
        } else if !isOn {
            return 0.6
        } else {
            // When on, opacity also responds to brightness for more dramatic effect
            let baseOpacity = 0.8
            let brightnessOpacity = brightnessEffect * 0.2
            return baseOpacity + brightnessOpacity
        }
    }
    
    private var brightnessEffect: Double {
        guard isOn && isOnline else { return 0 }
        return brightness / 255.0
    }
    
    private var saturationEffect: Double {
        if !isOnline || !isOn {
            return 0.3 // Desaturated when off
        } else {
            // More saturated colors at higher brightness
            return 0.8 + (brightnessEffect * 0.4)
        }
    }
    
    private var brightnessBoost: Double {
        if !isOnline || !isOn {
            return -0.2 // Darker when off
        } else {
            // Brightness boost ranges from 0 to 0.3 based on device brightness
            return brightnessEffect * 0.3
        }
    }
    
    private var scaleEffect: Double {
        if !isOnline || !isOn {
            return 0.95 // Slightly smaller when off
        } else {
            // Subtle scale effect for high brightness (1.0 to 1.05)
            return 1.0 + (brightnessEffect * 0.05)
        }
    }
    
    private var glowColor: Color {
        if !isOnline || !isOn {
            return .clear
        } else {
            // Neutral white glow so the halo reads as brightness, not device color.
            return .white.opacity(brightnessEffect * 0.6)
        }
    }
    
    private var glowRadius: CGFloat {
        if !isOnline || !isOn {
            return 0
        } else {
            // Glow radius based on brightness (0 to 15)
            return CGFloat(brightnessEffect * 15)
        }
    }
}

// MARK: - Image Picker Sheet

struct ImagePickerSheet: View {
    let deviceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImage: String = "product_image"
    @State private var isLoading = false
    
    // Aesdetic brand product images
    private let aesdeticProducts = [
        ("aesdetic_strip_v1", "Aesdetic Strip V1"),
        ("aesdetic_bulb_smart", "Aesdetic Smart Bulb"),
        ("aesdetic_panel_rgb", "Aesdetic RGB Panel"),
        ("aesdetic_controller_pro", "Aesdetic Controller Pro")
    ]
    
    // Default/fallback images
    private let otherImages = [
        ("product_image", "Generic LED Device"),
        ("led_strip_default", "LED Strip"),
        ("smart_bulb_default", "Smart Bulb"),
        ("led_panel_default", "LED Panel"),
        ("rgb_controller_default", "RGB Controller")
    ]
    
    // Get user uploaded images
    private var uploadedImages: [(String, String)] {
        DeviceImageManager.shared.getUploadedImages()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Custom Upload Section
                    VStack(spacing: 16) {
                        Text("Upload Custom Image")
                            .font(AppTypography.style(.headline))
                            .fontWeight(.semibold)
                        
                        Button(action: {
                            // Custom image upload functionality not yet implemented
                        }) {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(AppTypography.style(.largeTitle))
                                    .foregroundColor(.accentColor)
                                
                                    Text("Choose from Photos")
                                        .font(AppTypography.style(.subheadline))
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text("Upload a PNG image for your device")
                                        .font(AppTypography.style(.caption))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Aesdetic Products Section
                    VStack(spacing: 16) {
                        Text("Aesdetic Products")
                            .font(AppTypography.style(.headline))
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(aesdeticProducts.enumerated()), id: \.offset) { index, imageInfo in
                                ImageSelectionCard(
                                    imageName: imageInfo.0,
                                    displayName: imageInfo.1,
                                    isSelected: selectedImage == imageInfo.0,
                                    deviceId: deviceId
                                ) {
                                    selectedImage = imageInfo.0
                                    DeviceImageManager.shared.setImageName(imageInfo.0, for: deviceId)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    if !uploadedImages.isEmpty {
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // Uploads Section
                        VStack(spacing: 16) {
                            Text("Uploads")
                                .font(AppTypography.style(.headline))
                                .fontWeight(.semibold)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(Array(uploadedImages.enumerated()), id: \.offset) { index, imageInfo in
                                    ImageSelectionCard(
                                        imageName: imageInfo.0,
                                        displayName: imageInfo.1,
                                        isSelected: selectedImage == imageInfo.0,
                                        deviceId: deviceId
                                    ) {
                                        selectedImage = imageInfo.0
                                        DeviceImageManager.shared.setImageName(imageInfo.0, for: deviceId)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Others Section
                    VStack(spacing: 16) {
                        Text("Others")
                            .font(AppTypography.style(.headline))
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(otherImages.enumerated()), id: \.offset) { index, imageInfo in
                                ImageSelectionCard(
                                    imageName: imageInfo.0,
                                    displayName: imageInfo.1,
                                    isSelected: selectedImage == imageInfo.0,
                                    deviceId: deviceId
                                ) {
                                    selectedImage = imageInfo.0
                                    DeviceImageManager.shared.setImageName(imageInfo.0, for: deviceId)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Choose Device Image")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            selectedImage = DeviceImageManager.shared.getImageName(for: deviceId)
        }
    }
}

// MARK: - Device Image Manager

class DeviceImageManager: ObservableObject {
    static let shared = DeviceImageManager()
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    func getImageName(for deviceId: String) -> String {
        return UserDefaults.standard.string(forKey: "deviceImage_\(deviceId)") ?? "product_image"
    }
    
    func setImageName(_ imageName: String, for deviceId: String) {
        UserDefaults.standard.set(imageName, forKey: "deviceImage_\(deviceId)")
        // Post notification to update UI
        NotificationCenter.default.post(name: NSNotification.Name("DeviceImageChanged"), object: deviceId)
    }
    
    func saveCustomImage(_ imageData: Data, for deviceId: String) async -> String {
        let customImageName = "custom_\(deviceId)_\(UUID().uuidString)"
        let imageURL = documentsDirectory.appendingPathComponent("\(customImageName).png")
        
        do {
            try imageData.write(to: imageURL)
            setImageName(customImageName, for: deviceId)
            return customImageName
        } catch {
            #if DEBUG
            print("Error saving custom image: \(error)")
            #endif
            return "product_image" // fallback to default
        }
    }
    
    func getCustomImageURL(for imageName: String) -> URL? {
        guard imageName.hasPrefix("custom_") else { return nil }
        return documentsDirectory.appendingPathComponent("\(imageName).png")
    }
    
    func getUploadedImages() -> [(String, String)] {
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            return files.compactMap { url in
                let filename = url.lastPathComponent
                guard filename.hasSuffix(".png") && filename.hasPrefix("custom_") else { return nil }
                
                let imageName = String(filename.dropLast(4)) // Remove .png extension
                let displayName = "Custom Image"
                return (imageName, displayName)
            }
        } catch {
            #if DEBUG
            print("Error reading uploaded images: \(error)")
            #endif
            return []
        }
    }
}

// MARK: - Image Selection Card

struct ImageSelectionCard: View {
    let imageName: String
    let displayName: String
    let isSelected: Bool
    let deviceId: String
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Image preview
            Group {
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
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.8) : Color.clear,
                        lineWidth: 2
                    )
            )
            .onTapGesture {
                onSelect()
            }
            
            // Image name
            Text(displayName)
                .font(AppTypography.style(.caption))
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
        )
    }
} 
