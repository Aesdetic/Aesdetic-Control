//
//  DashboardView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI
import UIKit

private enum DashboardTypography {
    static let greeting = AppTypography.role(.hero)
    static let sectionTitle = AppTypography.role(.sectionTitle)
    static let cardTitle = AppTypography.role(.cardTitle)
    static let body = AppTypography.role(.body)
    static let bodyStrong = AppTypography.role(.bodyStrong)
    static let meta = AppTypography.role(.caption)
    static let micro = AppTypography.role(.micro)
    static let countBadge = AppTypography.role(.countBadge)
    static let metricValue = AppTypography.role(.metricValue)
    static let metricLabel = AppTypography.role(.metricLabel)
    static let buttonCompact = AppTypography.text(size: 12, weight: .semibold, relativeTo: .caption)
    static let buttonRegular = AppTypography.role(.button)
}

private struct SnappyTapButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.95
    var response: CGFloat = 0.2
    var damping: CGFloat = 0.82

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(
                .spring(response: response, dampingFraction: damping),
                value: configuration.isPressed
            )
    }
}

private struct DashboardSectionEntranceModifier: ViewModifier {
    let active: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
    }
}

private extension View {
    func dashboardSectionEntrance(active: Bool, index: Int) -> some View {
        modifier(DashboardSectionEntranceModifier(active: active, index: index))
    }

    func dashboardLegibility(strength: Double) -> some View {
        modifier(DashboardLegibilityTextModifier(strength: strength))
    }
}

private struct AesdeticWebDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DashboardLegibilityTextModifier: ViewModifier {
    let strength: Double

    func body(content: Content) -> some View {
        let normalized = min(max(strength, 0), 1)
        content
            .shadow(
                color: Color.black.opacity(0.06 + normalized * 0.08),
                radius: 6 + normalized * 4,
                x: 0,
                y: 2 + normalized * 1.5
            )
            .shadow(
                color: Color.black.opacity(0.035 + normalized * 0.055),
                radius: 14 + normalized * 8,
                x: 0,
                y: 5 + normalized * 2
            )
    }
}

private struct DashboardSectionHeader<Trailing: View>: View {
    let title: String
    let count: Int?
    private let trailing: Trailing

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        count: Int? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.count = count
        self.trailing = trailing()
    }

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(DashboardTypography.sectionTitle)
                .foregroundColor(AppTheme.text(.glassPrimary, for: colorScheme))
                .dashboardLegibility(strength: colorScheme == .dark ? 0.35 : 0.55)

            if let count {
                Text("\(count)")
                    .font(DashboardTypography.countBadge)
                    .foregroundColor(AppTheme.text(.glassSecondary, for: colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(theme.surfaceMuted)
                    )
            }

            Spacer()

            trailing
        }
    }
}

private struct DashboardEmptyDevicesState: View {
    let onAddDevice: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("No devices yet")
                    .font(DashboardTypography.cardTitle)
                    .foregroundColor(AppTheme.text(.glassPrimary, for: colorScheme))

                Text("Add your first Aesdetic or WLED device.")
                    .font(DashboardTypography.body)
                    .foregroundColor(AppTheme.text(.glassSecondary, for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onAddDevice) {
                Label("Add Device", systemImage: "plus.circle.fill")
                    .font(DashboardTypography.buttonRegular)
                    .foregroundColor(AppTheme.text(.glassPrimary, for: colorScheme).opacity(0.94))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(SnappyTapButtonStyle(pressedScale: 0.96, response: 0.16, damping: 0.8))
            .appLiquidGlass(role: .control)
            .accessibilityLabel("Add Device")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appLiquidGlass(role: .highContrast, cornerRadius: 20, highContrastDarkTintOpacity: colorScheme == .dark ? 0.10 : 0.08)
    }
}

struct DashboardView: View {
    var activeTab: DockTab? = nil
    var onOpenDevices: () -> Void = {}
    var onDetailPresentationChange: (Bool) -> Void = { _ in }
    @StateObject private var dashboardViewModel = DashboardViewModel.shared
    @StateObject private var deviceControlViewModel = DeviceControlViewModel.shared
    @StateObject private var automationViewModel = AutomationViewModel.shared
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.setupJourneyActions) private var setupJourneyActions
    @AppStorage(AppBackgroundPreference.selectedChoiceKey) private var selectedBackground = AppBackgroundChoice.defaultChoice.rawValue
    @State private var navigationPath = NavigationPath()
    @State private var detailPresentation = DeviceDetailPresentationState()
    @State private var detailSourceFrames: [String: CGRect] = [:]
    @State private var detailTransitionID = UUID()
    @State private var aesdeticWebDestination: AesdeticWebDestination?
    @State private var detailBackgroundDismissEnabledAt: Date = .distantPast
    @State private var detailContentRevealProgress: CGFloat = 0
    @State private var detailContentRevealWorkItem: DispatchWorkItem?
    @GestureState private var detailDragOffset: CGFloat = 0
    
    // MARK: - Performance Optimization Properties
    
    // Derived-data cache (updated only from explicit events, never from computed properties)
    @State private var memoizedDeviceStats: (total: Int, online: Int, offline: Int) = (0, 0, 0)
    @State private var memoizedFilteredDevices: [WLEDDevice] = []
    
    private let deviceUpdateThrottle: TimeInterval = 0.5 // 500ms throttle window
    @State private var lastDerivedUpdate: Date = .distantPast
    @State private var derivedUpdateWorkItem: DispatchWorkItem?
    @State private var hasAnimatedSections = false
    
    private let fastAnimation: Animation = .easeInOut(duration: 0.15)
    private let contentHorizontalPadding: CGFloat = 20
    private let sectionSpacing: CGFloat = 20
    private let detailDismissGuardDelay: TimeInterval = 0.45
    private let detailContentRevealDelay: TimeInterval = 0.20
    private let detailPanelAnimation: Animation = DeviceDetailPresentation.animation
    private let aesdeticWebsiteURL = URL(string: "https://aesdetic.com")!
    private let debugHideGreeting = false
    private let debugHideQuote = false
    private let debugHideScenes = false
    private let debugHideLogo = false
    private let debugHideStats = false
    
    // Background handled globally by AppBackground
    
    // Side-effect-free accessors
    private var deviceStatistics: (total: Int, online: Int, offline: Int) { memoizedDeviceStats }
    private var filteredDevices: [WLEDDevice] { memoizedFilteredDevices }

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var primaryTextColor: Color {
        AppTheme.text(.glassPrimary, for: colorScheme)
    }
    private var secondaryTextColor: Color {
        AppTheme.text(.glassSecondary, for: colorScheme)
    }
    private var dashboardBackgroundChoice: AppBackgroundChoice {
        AppBackgroundChoice(rawValue: selectedBackground) ?? .defaultChoice
    }
    private var dashboardReadabilityStrength: Double {
        switch dashboardBackgroundChoice {
        case .custom, .sunrise, .alpine, .neutral:
            return colorScheme == .dark ? 0.55 : 0.72
        case .sunset, .blueHour4, .blueHour5:
            return colorScheme == .dark ? 0.45 : 0.58
        case .blueHour, .blueHour6:
            return colorScheme == .dark ? 0.36 : 0.46
        }
    }
    
    private func updateMemoizedStats() {
        let devices = deviceControlViewModel.devices
        let total = devices.count
        // Optimized: Use reduce instead of filter+count (single pass, better performance)
        let online = devices.reduce(0) { $0 + ($1.isOnline ? 1 : 0) }
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
        let elapsed = now.timeIntervalSince(lastDerivedUpdate)
        if elapsed >= deviceUpdateThrottle {
            derivedUpdateWorkItem?.cancel()
            updateMemoizedStats()
            updateMemoizedFilteredDevices()
            return
        }
        
        // Debounce: schedule a trailing update so we don't miss the final state
        derivedUpdateWorkItem?.cancel()
        let delay = deviceUpdateThrottle - elapsed
        let workItem = DispatchWorkItem {
            updateMemoizedStats()
            updateMemoizedFilteredDevices()
        }
        derivedUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        headerIntroSection
                            .padding(.horizontal, contentHorizontalPadding)
                            .padding(.top, 14)
                            .dashboardSectionEntrance(active: hasAnimatedSections, index: 0)

                        if !debugHideStats {
                            DeviceStatsSection(
                                totalDevices: deviceStatistics.total,
                                activeDevices: deviceStatistics.online,
                                activeAutomations: automationViewModel.automations.filter { $0.enabled }.count
                            )
                            .padding(.horizontal, contentHorizontalPadding)
                            .dashboardSectionEntrance(active: hasAnimatedSections, index: 1)
                        }

                        if !debugHideScenes {
                            ScenesAutomationsSection(
                                automations: automationViewModel.automations,
                                deviceCount: deviceControlViewModel.devices.count,
                                deviceViewModel: deviceControlViewModel,
                                onToggle: { automation in
                                    Task { automationViewModel.toggleAutomation(automation) }
                                }
                            )
                            .onReceive(automationViewModel.$automations) { _ in
                                DispatchQueue.main.async { recomputeDerivedIfNeeded() }
                            }
                            .dashboardSectionEntrance(active: hasAnimatedSections, index: 2)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            DashboardSectionHeader(title: "Devices", count: filteredDevices.count) {
                                EmptyView()
                            }

                            if filteredDevices.isEmpty {
                                DashboardEmptyDevicesState(onAddDevice: onOpenDevices)
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)],
                                    spacing: 14
                                ) {
                                    ForEach(filteredDevices, id: \.id) { device in
                                        MiniDeviceCard(
                                            device: device,
                                            onTap: {
                                                openDeviceDetail(device)
                                            }
                                        )
                                        .deviceDetailSourceFrame(deviceId: device.id)
                                        .id(device.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, contentHorizontalPadding)
                        .dashboardSectionEntrance(active: hasAnimatedSections, index: 3)
                    }
                    .padding(.bottom, 104)
                    .onChange(of: deviceControlViewModel.devices) { _, _ in
                        DispatchQueue.main.async { recomputeDerivedIfNeeded() }
                    }
                    .onChange(of: deviceControlViewModel.selectedLocationFilter) { _, _ in
                        DispatchQueue.main.async { updateMemoizedFilteredDevices() }
                    }
                }
                .refreshable {
                    await refreshData()
                }
                .opacity(detailPresentation.isPresented ? 0 : 1)
                .allowsHitTesting(!detailPresentation.isPresented)
                .animation(detailPanelAnimation, value: detailPresentation.isPresented)
            }
            .sheet(item: $aesdeticWebDestination) { destination in
                WLEDWebConfigView(url: destination.url)
            }
            .coordinateSpace(name: DeviceDetailPresentation.coordinateSpaceName)
            .onPreferenceChange(DeviceDetailSourceFramePreferenceKey.self) { frames in
                detailSourceFrames = frames
            }
            .onAppear {
                updateMemoizedStats()
                updateMemoizedFilteredDevices()
                if !hasAnimatedSections {
                    hasAnimatedSections = true
                }
            }
            .onChange(of: activeTab) { _, newValue in
                if newValue != .dashboard {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        closeDeviceDetail(animated: false)
                    }
                }
            }
            .overlay { dashboardDeviceDetailOverlay }
            .navigationBarHidden(true)
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var dashboardDeviceDetailOverlay: some View {
        if let selectedDevice = detailPresentation.device {
            GeometryReader { proxy in
                let liveDragOffset = max(0, detailDragOffset)
                let dragOffset = liveDragOffset > 0 ? liveDragOffset : detailPresentation.closingDragOffset
                let panelFrame = DeviceDetailPresentation.expandedPanelFrame(
                    in: proxy.size,
                    bottomSafeAreaInset: proxy.safeAreaInsets.bottom
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
                let morphBottomCornerRadius = DeviceDetailPresentation.bottomCornerRadius(
                    sourceFrame: detailPresentation.sourceFrame,
                    progress: presentationProgress,
                    bottomSafeAreaInset: proxy.safeAreaInsets.bottom
                )
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .allowsHitTesting(canDismissDetailFromBackground && detailPresentation.isPresented && !detailPresentation.isClosing)
                        .onTapGesture {
                            closeDeviceDetail()
                        }

                    DeviceDetailView(
                        device: selectedDevice,
                        viewModel: deviceControlViewModel,
                        backgroundStyle: .liquidGlass,
                        containerCornerRadius: morphCornerRadius,
                        containerBottomCornerRadius: morphBottomCornerRadius,
                        presentationProgress: presentationProgress,
                        delaysContentUntilExpanded: true,
                        contentRevealProgress: detailContentRevealProgress,
                        presentationBottomSafeAreaInset: proxy.safeAreaInsets.bottom,
                        onClose: { closeDeviceDetail() }
                    )
                    .frame(width: morphFrame.width, height: morphFrame.height, alignment: .top)
                    .deviceDetailPanelClip(
                        topCornerRadius: morphCornerRadius,
                        bottomCornerRadius: morphBottomCornerRadius,
                        usesScreenConcentricBottomCorners: true
                    )
                    .compositingGroup()
                    .position(x: morphFrame.midX, y: morphFrame.midY)
                    .opacity(detailShellOpacity(for: presentationProgress))
                    .simultaneousGesture(detailCollapseDragGesture)
                }
            }
            .zIndex(2)
        }
    }

    private var canDismissDetailFromBackground: Bool {
        Date() >= detailBackgroundDismissEnabledAt
    }

    private func detailShellOpacity(for progress: CGFloat) -> Double {
        guard detailPresentation.isClosing else { return 1 }

        let normalized = min(1, max(0, (progress - 0.08) / 0.22))
        let eased = normalized * normalized * (3 - (2 * normalized))
        return Double(eased)
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

    // MARK: - Optimized Components

    @ViewBuilder
    private var headerIntroSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if !debugHideGreeting {
                    Text(dashboardViewModel.currentGreeting)
                        .font(DashboardTypography.greeting)
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .dashboardLegibility(strength: dashboardReadabilityStrength)
                        .id(dashboardViewModel.currentGreeting)
                }

                if !debugHideQuote {
                    Text(dashboardViewModel.currentQuote)
                        .font(DashboardTypography.body)
                        .foregroundColor(secondaryTextColor.opacity(0.94))
                        .lineLimit(deviceStatistics.total > 0 ? 1 : 2)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .dashboardLegibility(strength: dashboardReadabilityStrength * 0.85)
                        .id(dashboardViewModel.currentQuote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !debugHideLogo {
                dashboardLogoWebsiteButton(size: 44, hitSize: 56)
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func dashboardLogoGlyph(size: CGFloat) -> some View {
        Group {
            if let logoImage = UIImage(named: "aesdetic_logo") {
                LiquidGlassLogoGlyph(logoImage: logoImage)
            } else {
                Image(systemName: "sparkles")
                    .font(AppTypography.style(.title3, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .padding(6)
                    .frame(width: size, height: size)
                    .background(
                        Color.clear
                            .appLiquidGlass(role: .highContrast, cornerRadius: 14)
                    )
            }
        }
        .frame(width: size, height: size)
    }

    private func dashboardLogoWebsiteButton(size: CGFloat, hitSize: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: hitSize, height: hitSize)

            dashboardLogoGlyph(size: size)
        }
        .frame(width: hitSize, height: hitSize)
        .contentShape(Rectangle())
        .onTapGesture(perform: openAesdeticWebsite)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Open Aesdetic website")
        .accessibilityHint("Opens aesdetic.com")
    }

    private func openAesdeticWebsite() {
        aesdeticWebDestination = AesdeticWebDestination(url: aesdeticWebsiteURL)
    }

    @ViewBuilder
    private func headerSection(geometry: GeometryProxy) -> some View {
        HStack {
            Spacer()
            
            // Company logo positioned in top right
            dashboardLogoWebsiteButton(size: 50, hitSize: 60)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private func greetingSection(geometry: GeometryProxy) -> some View {
        HStack {
            Text(dashboardViewModel.currentGreeting)
                .font(AppTypography.style(.largeTitle, weight: .bold))
                .foregroundColor(primaryTextColor)
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
                .font(AppTypography.style(.title2))
                .foregroundColor(.white.opacity(0.58))
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
            deviceCount: deviceControlViewModel.devices.count,
            deviceViewModel: deviceControlViewModel,
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
            activeAutomations: automationViewModel.automations.filter { $0.enabled }.count
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.2), value: stats.total) // Reduced animation duration
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
                MiniDeviceCard(
                    device: device,
                    onTap: {
                        openDeviceDetail(device)
                    }
                )
                    .deviceDetailSourceFrame(deviceId: device.id)
                    .id(device.id) // Stable identity for animations
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.2).delay(0.1)),
                        removal: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.15))
                    ))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .animation(.easeInOut(duration: 0.2), value: filteredDevices.count)
    }

    private func openDeviceDetail(_ device: WLEDDevice) {
        if detailPresentation.device?.id == device.id &&
            (detailPresentation.isPreparing || detailPresentation.isPresented) {
            return
        }

        if deviceControlViewModel.requiresProfileSetup(device) {
            closeDeviceDetail(animated: false)
            setupJourneyActions.beginProductSetup(device, nil)
            return
        }
        detailContentRevealWorkItem?.cancel()
        detailContentRevealProgress = 0
        let transitionID = UUID()
        detailTransitionID = transitionID
        detailBackgroundDismissEnabledAt = .distantFuture
        detailPresentation.prepare(device: device, sourceFrame: detailSourceFrames[device.id])
        onDetailPresentationChange(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + DeviceDetailPresentation.dockHideLeadTime) {
            guard detailTransitionID == transitionID else { return }
            if let refreshedSourceFrame = detailSourceFrames[device.id] {
                detailPresentation.sourceFrame = refreshedSourceFrame
            }
            detailPresentation.isPreparing = false
            detailBackgroundDismissEnabledAt = Date().addingTimeInterval(detailDismissGuardDelay)
            withAnimation(detailPanelAnimation) {
                detailPresentation.isPresented = true
            }
            scheduleDetailContentReveal(for: device.id, transitionID: transitionID)
        }
    }

    private func scheduleDetailContentReveal(for deviceId: String, transitionID: UUID) {
        let workItem = DispatchWorkItem {
            guard detailTransitionID == transitionID,
                  detailPresentation.device?.id == deviceId,
                  detailPresentation.isPresented,
                  !detailPresentation.isClosing else {
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                detailContentRevealProgress = 1
            }
        }
        detailContentRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + detailContentRevealDelay, execute: workItem)
    }

    private func closeDeviceDetail(fromDragOffset dragOffset: CGFloat = 0, animated: Bool = true) {
        let transitionID = UUID()
        detailTransitionID = transitionID

        guard detailPresentation.device != nil else {
            detailBackgroundDismissEnabledAt = .distantPast
            return
        }
        detailContentRevealWorkItem?.cancel()
        detailContentRevealProgress = 0
        guard animated, !detailPresentation.isPreparing else {
            detailPresentation.reset()
            detailBackgroundDismissEnabledAt = .distantPast
            onDetailPresentationChange(false)
            return
        }

        detailPresentation.isClosing = true
        if let deviceId = detailPresentation.device?.id,
           let latestSourceFrame = detailSourceFrames[deviceId] {
            detailPresentation.sourceFrame = latestSourceFrame
        }
        detailPresentation.closingDragOffset = max(0, dragOffset)
        withAnimation(detailPanelAnimation) {
            detailPresentation.isPresented = false
            detailPresentation.closingDragOffset = 0
        } completion: {
            guard detailTransitionID == transitionID else { return }
            detailPresentation.reset()
            detailBackgroundDismissEnabledAt = .distantPast
            onDetailPresentationChange(false)
        }
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
        // Already on MainActor (function is @MainActor), no need for async dispatch
        recomputeDerivedIfNeeded()
    }
}

// MARK: - Scenes & Shortcuts Section

struct ScenesAutomationsSection: View {
    let automations: [Automation]
    let deviceCount: Int
    let deviceViewModel: DeviceControlViewModel
    let onToggle: (Automation) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var scenesStore = SceneGroupStore.shared
    @ObservedObject private var presetsStore = PresetsStore.shared
    @StateObject private var usageStore = DashboardShortcutUsageStore.shared
    @StateObject private var favoritesStore = SceneFavoritesStore.shared
    @StateObject private var presetFavoritesStore = PresetFavoritesStore.shared
    @StateObject private var recoveredPresetFavoritesStore = RecoveredPresetFavoritesStore.shared
    private let sceneShortcutRowHeight: CGFloat = 90
    private let quickActionChipHeight: CGFloat = 54
    private let sectionHorizontalPadding: CGFloat = 20
    private var quickActionGridHeight: CGFloat {
        CGFloat(shortcutGridRows.count) * quickActionChipHeight
            + CGFloat(max(0, shortcutGridRows.count - 1)) * 6
    }
    private var shouldShowScenesHeader: Bool { deviceCount > 1 }
    private var shouldShowScenesChips: Bool { shouldShowScenesHeader && !displayedSceneItems.isEmpty }
    private var shouldShowQuickActions: Bool {
        !displayedShortcutItems.isEmpty
            || !menuSceneShortcutCandidates.isEmpty
            || !menuPresetShortcutCandidates.isEmpty
            || !menuRecoveredPresetShortcutCandidates.isEmpty
            || !menuAutomationShortcutCandidates.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if shouldShowScenesHeader {
                scenesRow
            }
            if shouldShowQuickActions {
                quickActionsRow
            }
        }
        .background(Color.clear)
    }

    private var scenesRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Scenes") {
                AddSceneButton(compact: true)
            }
            .padding(.horizontal, sectionHorizontalPadding)
            
            if shouldShowScenesChips {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(displayedSceneItems) { item in
                            DashboardAutomationShortcutChip(
                                title: item.title,
                                description: "Scene",
                                detail: "",
                                isEnabled: true,
                                previewGradients: [],
                                action: {
                                    usageStore.increment(key: item.usageKey)
                                    handleSceneShortcut(item)
                                }
                            )
                            .contextMenu {
                                Button(item.isFavorite ? "Remove quick action" : "Add quick action") {
                                    toggleFavorite(for: item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                }
                .frame(height: sceneShortcutRowHeight)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollClipDisabled()
            }
        }
        .background(Color.clear)
    }

    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Quick Actions") {
                shortcutAddMenu
            }
            .padding(.horizontal, sectionHorizontalPadding)

            if !displayedShortcutItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(shortcutGridRows.enumerated()), id: \.offset) { _, rowItems in
                            HStack(alignment: .center, spacing: 6) {
                                ForEach(rowItems) { item in
                                    DashboardAutomationShortcutChip(
                                        title: item.title,
                                        description: sceneShortcutDescription(for: item),
                                        detail: sceneShortcutMetadataDetail(for: item),
                                        isEnabled: sceneShortcutIsEnabled(item),
                                        previewGradients: sceneShortcutPreviewGradients(for: item),
                                        action: {
                                            usageStore.increment(key: item.usageKey)
                                            handleSceneShortcut(item)
                                        }
                                    )
                                    .contextMenu {
                                        Button(sceneShortcutFavoriteTitle(for: item)) {
                                            toggleFavorite(for: item)
                                        }
                                    }
                                }
                            }
                            .frame(height: quickActionChipHeight, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                }
                .frame(height: quickActionGridHeight)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollClipDisabled()
            }
        }
        .background(Color.clear)
    }
    
    private var displayedSceneItems: [SceneShortcutItem] {
        sortedSceneItems
    }

    private var displayedShortcutItems: [SceneShortcutItem] {
        sortedAutomationShortcutItems + sortedFavoriteSceneItems + sortedFavoritePresetItems
    }

    private var shortcutGridRows: [[SceneShortcutItem]] {
        guard displayedShortcutItems.count > 1 else { return [displayedShortcutItems] }
        let topRowCount = Int(ceil(Double(displayedShortcutItems.count) / 2.0))
        return [
            Array(displayedShortcutItems.prefix(topRowCount)),
            Array(displayedShortcutItems.dropFirst(topRowCount))
        ].filter { !$0.isEmpty }
    }

    private var sortedSceneItems: [SceneShortcutItem] {
        scenesStore.scenes.map { scene in
            SceneShortcutItem(
                id: "scene:\(scene.id.uuidString)",
                title: scene.name,
                createdAt: scene.createdAt,
                usageKey: "scene:\(scene.id.uuidString)",
                kind: .sceneGroup(scene),
                isFavorite: favoritesStore.contains(scene.id)
            )
        }
        .sorted { lhs, rhs in
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var sortedFavoriteSceneItems: [SceneShortcutItem] {
        sortedSceneItems.filter(\.isFavorite)
    }

    private var sortedFavoritePresetItems: [SceneShortcutItem] {
        let localItems = presetsStore.colorPresets
            .filter { presetFavoritesStore.contains($0.id) }
            .map { preset in
                SceneShortcutItem(
                    id: "preset:\(preset.id.uuidString)",
                    title: preset.name,
                    createdAt: preset.createdAt,
                    usageKey: "preset:\(preset.id.uuidString)",
                    kind: .preset(preset),
                    isFavorite: presetFavoritesStore.contains(preset.id)
                )
            }

        let recoveredItems = recoveredColorPresets
            .filter { recoveredPresetFavoritesStore.contains(recoveredPresetFavoriteKey(for: $0)) }
            .map { preset in
                let deviceId = preferredShortcutDevice?.id ?? ""
                return SceneShortcutItem(
                    id: "recovered-preset:\(recoveredPresetFavoriteKey(for: preset, deviceId: deviceId))",
                    title: preset.displayName,
                    createdAt: .distantPast,
                    usageKey: "recovered-preset:\(recoveredPresetFavoriteKey(for: preset, deviceId: deviceId))",
                    kind: .recoveredPreset(preset, deviceId: deviceId),
                    isFavorite: true
                )
            }

        return (localItems + recoveredItems)
            .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
    }

    private var sortedAutomationShortcutItems: [SceneShortcutItem] {
        automations
            .filter { $0.metadata.pinnedToShortcuts ?? false }
            .map { automation in
                SceneShortcutItem(
                    id: "automation:\(automation.id.uuidString)",
                    title: automation.name,
                    createdAt: automation.updatedAt,
                    usageKey: "automation:\(automation.id.uuidString)",
                    kind: .automation(automation),
                    isFavorite: true
                )
            }
            .sorted { lhs, rhs in
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var menuSceneShortcutCandidates: [SceneGroup] {
        scenesStore.scenes
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var menuPresetShortcutCandidates: [ColorPreset] {
        presetsStore.colorPresets
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var preferredShortcutDevice: WLEDDevice? {
        deviceViewModel.devices.first(where: { $0.isOnline }) ?? deviceViewModel.devices.first
    }

    private var recoveredColorPresets: [WLEDRecoveredColorPreset] {
        guard let device = preferredShortcutDevice else { return [] }
        return WLEDDevicePresetRecovery.recoveredColorPresets(
            for: device.id,
            presets: deviceViewModel.presets(for: device),
            playlists: deviceViewModel.playlists(for: device),
            localColorPresets: presetsStore.colorPresets
        )
    }

    private var menuRecoveredPresetShortcutCandidates: [WLEDRecoveredColorPreset] {
        recoveredColorPresets
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var menuAutomationShortcutCandidates: [Automation] {
        automations
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var shortcutAddMenu: some View {
        Menu {
            Section("Scenes") {
                if menuSceneShortcutCandidates.isEmpty {
                    Button("No scenes yet") {}
                        .disabled(true)
                } else {
                    ForEach(menuSceneShortcutCandidates) { scene in
                        let isShortcut = favoritesStore.contains(scene.id)
                        Button {
                            favoritesStore.toggle(scene.id)
                        } label: {
                            Label(
                                scene.name,
                                systemImage: shortcutMenuIcon(isSelected: isShortcut, fallback: "sparkles")
                            )
                        }
                    }
                }
            }

            Section("Saved Colors") {
                if menuPresetShortcutCandidates.isEmpty && menuRecoveredPresetShortcutCandidates.isEmpty {
                    Button("No saved colors yet") {}
                        .disabled(true)
                } else {
                    ForEach(menuPresetShortcutCandidates) { preset in
                        let isShortcut = presetFavoritesStore.contains(preset.id)
                        Button {
                            presetFavoritesStore.toggle(preset.id)
                        } label: {
                            Label(
                                preset.name,
                                systemImage: shortcutMenuIcon(isSelected: isShortcut, fallback: "paintpalette")
                            )
                        }
                    }
                    ForEach(menuRecoveredPresetShortcutCandidates) { preset in
                        let key = recoveredPresetFavoriteKey(for: preset)
                        let isShortcut = recoveredPresetFavoritesStore.contains(key)
                        Button {
                            recoveredPresetFavoritesStore.toggle(key)
                        } label: {
                            Label(
                                preset.displayName,
                                systemImage: shortcutMenuIcon(isSelected: isShortcut, fallback: "paintpalette")
                            )
                        }
                    }
                }
            }

            Section("Routines") {
                if menuAutomationShortcutCandidates.isEmpty {
                    Button("No routines yet") {}
                        .disabled(true)
                } else {
                    ForEach(menuAutomationShortcutCandidates) { automation in
                        let isShortcut = automation.metadata.pinnedToShortcuts ?? false
                        Button {
                            setAutomationShortcut(automation, pinned: !isShortcut)
                        } label: {
                            Label(
                                automation.name,
                                systemImage: shortcutMenuIcon(isSelected: isShortcut, fallback: "power")
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(DashboardTypography.buttonCompact)
                Text("Add")
                    .font(DashboardTypography.buttonCompact)
            }
            .foregroundColor(AppTheme.text(.glassPrimary, for: colorScheme).opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(SnappyTapButtonStyle(pressedScale: 0.96, response: 0.16, damping: 0.8))
        .appLiquidGlass(role: .control)
        .accessibilityLabel("Add quick action")
    }

    private func shortcutMenuIcon(isSelected: Bool, fallback: String) -> String {
        isSelected ? "checkmark" : fallback
    }

    private func sceneShortcutDescription(for item: SceneShortcutItem) -> String {
        switch item.kind {
        case .sceneGroup:
            return "Scene"
        case .preset:
            return "Saved color"
        case .recoveredPreset:
            return "Saved color"
        case .automation:
            return "Routine"
        }
    }

    private func sceneShortcutMetadataDetail(for item: SceneShortcutItem) -> String {
        switch item.kind {
        case .sceneGroup:
            return ""
        case .preset, .recoveredPreset:
            return ""
        case .automation(let automation):
            return automationShortcutTriggerDescription(for: automation)
        }
    }

    private func sceneShortcutIsEnabled(_ item: SceneShortcutItem) -> Bool {
        switch item.kind {
        case .sceneGroup, .preset, .recoveredPreset:
            return true
        case .automation(let automation):
            return automation.enabled
        }
    }

    private func sceneShortcutPreviewGradients(for item: SceneShortcutItem) -> [LEDGradient] {
        switch item.kind {
        case .sceneGroup:
            return []
        case .preset(let preset):
            return [
                LEDGradient(
                    stops: preset.gradientStops,
                    interpolation: preset.gradientInterpolation ?? .linear
                )
            ]
        case .recoveredPreset(let preset, _):
            return [preset.gradient]
        case .automation(let automation):
            return automationShortcutColorPreviews(for: automation)
        }
    }

    private func automationShortcutTriggerDescription(for automation: Automation) -> String {
        switch automation.trigger {
        case .specificTime(let trigger):
            return compactTimeTriggerDisplay(trigger)
        case .sunrise:
            return "Sunrise"
        case .sunset:
            return "Sunset"
        }
    }

    private func compactTimeTriggerDisplay(_ trigger: TimeTrigger) -> String {
        trigger.time
    }

    private func automationShortcutColorPreviews(for automation: Automation) -> [LEDGradient] {
        switch automation.action {
        case .gradient(let payload):
            return payload.powerOn ? [payload.gradient] : []
        case .transition(let payload):
            return [payload.startGradient, payload.endGradient]
        case .effect(let payload):
            if let gradient = payload.gradient {
                return [gradient]
            }
            if let hex = automation.metadata.colorPreviewHex, !hex.isEmpty {
                return [solidShortcutPreviewGradient(hex: hex)]
            }
            return []
        case .directState(let payload):
            return [solidShortcutPreviewGradient(hex: payload.colorHex)]
        case .scene, .preset, .playlist:
            if let hex = automation.metadata.colorPreviewHex, !hex.isEmpty {
                return [solidShortcutPreviewGradient(hex: hex)]
            }
            return []
        }
    }

    private func solidShortcutPreviewGradient(hex: String) -> LEDGradient {
        LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: hex),
            GradientStop(position: 1.0, hexColor: hex)
        ])
    }

    private func sceneShortcutFavoriteTitle(for item: SceneShortcutItem) -> String {
        switch item.kind {
        case .automation:
            return "Remove quick action"
        case .sceneGroup, .preset, .recoveredPreset:
            return item.isFavorite ? "Remove quick action" : "Add quick action"
        }
    }
    
    private func applySceneGroup(_ scene: SceneGroup) {
        let devicesById = Dictionary(uniqueKeysWithValues: deviceViewModel.devices.map { ($0.id, $0) })
        Task {
            await withTaskGroup(of: Void.self) { group in
                for deviceScene in scene.deviceScenes {
                    guard let device = devicesById[deviceScene.deviceId] else { continue }
                    group.addTask {
                        await deviceViewModel.applyScene(deviceScene, to: device)
                    }
                }
            }
        }
    }
    
    private func applyPreset(_ preset: ColorPreset) {
        guard let device = deviceViewModel.devices.first(where: { $0.isOnline }) ?? deviceViewModel.devices.first else { return }
        Task {
            await deviceViewModel.cancelActiveTransitionIfNeeded(for: device)
            let presetId = preset.wledPresetIds?[device.id] ?? preset.wledPresetId
            if let presetId = presetId {
                _ = await deviceViewModel.applyPresetId(presetId, to: device)
            } else {
                let ledCount = deviceViewModel.totalLEDCount(for: device)
                var stopTemperatures: [UUID: Double]? = nil
                var stopWhiteLevels: [UUID: Double]? = nil
                if let temp = preset.temperature {
                    stopTemperatures = Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, temp) })
                }
                if let white = preset.whiteLevel {
                    stopWhiteLevels = Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, white) })
                }
                await deviceViewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: preset.gradientStops,
                    ledCount: ledCount,
                    stopTemperatures: stopTemperatures,
                    stopWhiteLevels: stopWhiteLevels,
                    preferSegmented: true
                )
                let apiService = WLEDAPIService.shared
                _ = try? await apiService.setBrightness(for: device, brightness: preset.brightness)
            }
        }
    }

    private func applyRecoveredPreset(_ preset: WLEDRecoveredColorPreset, deviceId: String) {
        let fallbackDevice = preferredShortcutDevice
        guard let device = deviceViewModel.devices.first(where: { $0.id == deviceId }) ?? fallbackDevice else { return }
        Task {
            await deviceViewModel.cancelActiveTransitionIfNeeded(for: device)
            _ = await deviceViewModel.applyPresetId(preset.id, to: device)
        }
    }
    
    private func handleSceneShortcut(_ item: SceneShortcutItem) {
        switch item.kind {
        case .sceneGroup(let scene):
            applySceneGroup(scene)
        case .preset(let preset):
            applyPreset(preset)
        case .recoveredPreset(let preset, let deviceId):
            applyRecoveredPreset(preset, deviceId: deviceId)
        case .automation(let automation):
            onToggle(automation)
        }
    }
    
    private func toggleFavorite(for item: SceneShortcutItem) {
        switch item.kind {
        case .sceneGroup(let scene):
            favoritesStore.toggle(scene.id)
        case .preset(let preset):
            presetFavoritesStore.toggle(preset.id)
        case .recoveredPreset(let preset, let deviceId):
            recoveredPresetFavoritesStore.toggle(recoveredPresetFavoriteKey(for: preset, deviceId: deviceId))
        case .automation(let automation):
            var updated = automation
            var metadata = automation.metadata
            metadata.pinnedToShortcuts = !(automation.metadata.pinnedToShortcuts ?? false)
            updated.metadata = metadata
            AutomationStore.shared.update(updated, syncOnDevice: false)
        }
    }

    private func setAutomationShortcut(_ automation: Automation, pinned: Bool) {
        var updated = automation
        var metadata = automation.metadata
        metadata.pinnedToShortcuts = pinned
        updated.metadata = metadata
        AutomationStore.shared.update(updated, syncOnDevice: false)
    }

    private func recoveredPresetFavoriteKey(for preset: WLEDRecoveredColorPreset, deviceId: String? = nil) -> String {
        let deviceId = deviceId ?? preferredShortcutDevice?.id ?? ""
        return "\(deviceId):\(preset.id)"
    }
    
    private struct SceneShortcutItem: Identifiable {
        enum Kind {
            case sceneGroup(SceneGroup)
            case preset(ColorPreset)
            case recoveredPreset(WLEDRecoveredColorPreset, deviceId: String)
            case automation(Automation)
        }
        
        let id: String
        let title: String
        let createdAt: Date
        let usageKey: String
        let kind: Kind
        let isFavorite: Bool
    }
}

private struct DashboardAutomationShortcutChip: View {
    let title: String
    let description: String
    let detail: String
    let isEnabled: Bool
    let previewGradients: [LEDGradient]
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        AppTheme.text(.glassPrimary, for: colorScheme).opacity(isEnabled ? 0.96 : 0.62)
    }

    private var secondaryTextColor: Color {
        AppTheme.text(.glassSecondary, for: colorScheme).opacity(isEnabled ? 0.74 : 0.48)
    }

    private var preferredWidth: CGFloat {
        let metadataCount = description.count + (detail.isEmpty ? 0 : detail.count + 3)
        let previewAllowance = hasSplitPreview ? previewRailWidth * 2 + 60 : previewRailWidth + 48
        let titleWidth = CGFloat(title.count) * 6.4 + previewAllowance
        let metadataWidth = CGFloat(metadataCount) * 5.4 + previewAllowance
        return min(300, max(126, max(titleWidth, metadataWidth)))
    }

    private var previewRailWidth: CGFloat { 8 }
    private var previewRailHeight: CGFloat { 28 }
    private var hasSplitPreview: Bool { previewGradients.count > 1 }

    private var chipFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(isEnabled ? 0.12 : 0.08)
            : Color.white.opacity(isEnabled ? 0.22 : 0.16)
    }

    private var chipStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.24)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 9) {
                previewAccent(for: leadingPreviewGradient)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppTypography.text(size: 13, weight: .semibold, relativeTo: .caption))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)

                    metadataRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if let trailingPreviewGradient {
                    previewAccent(for: trailingPreviewGradient)
                }
            }
            .padding(.horizontal, 16)
            .frame(width: preferredWidth, height: 54, alignment: .leading)
            .background(chipBackground)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if detail.isEmpty {
            return "\(title), \(description)"
        }
        return "\(title), \(description), \(detail)"
    }

    private var metadataRow: some View {
        HStack(spacing: 5) {
            Text(description)
                .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
                .foregroundColor(secondaryTextColor.opacity(0.88))
                .lineLimit(1)

            if !detail.isEmpty {
                Circle()
                    .fill(secondaryTextColor.opacity(0.62))
                    .frame(width: 2.5, height: 2.5)
                    .accessibilityHidden(true)

                Text(detail)
                    .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
                    .foregroundColor(secondaryTextColor.opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .truncationMode(.tail)
            }
        }
    }

    private var leadingPreviewGradient: LEDGradient? {
        previewGradients.first
    }

    private var trailingPreviewGradient: LEDGradient? {
        guard hasSplitPreview else { return nil }
        return previewGradients.dropFirst().first
    }

    @ViewBuilder
    private func previewAccent(for gradient: LEDGradient?) -> some View {
        if let gradient {
            previewRail(for: gradient)
        } else {
            Capsule()
                .fill(Color.white.opacity(isEnabled ? 0.22 : 0.12))
                .frame(width: previewRailWidth, height: previewRailHeight)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isEnabled ? 0.16 : 0.10), lineWidth: 1)
                )
                .accessibilityHidden(true)
        }
    }

    private func previewRail(for gradient: LEDGradient) -> some View {
        LinearGradient(
            gradient: Gradient(stops: gradient.stops.sorted { $0.position < $1.position }.map {
                .init(color: $0.color, location: $0.position)
            }),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: previewRailWidth, height: previewRailHeight)
        .opacity(isEnabled ? 0.96 : 0.58)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(isEnabled ? 0.24 : 0.16), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var chipBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isEnabled {
            shape
                .fill(Color.clear)
                .appLiquidGlass(role: .card, cornerRadius: 16)
        } else {
            shape
                .fill(chipFill)
                .overlay(
                    shape
                        .stroke(chipStroke, lineWidth: 1)
                )
        }
    }
}

@MainActor
final class DashboardShortcutUsageStore: ObservableObject {
    static let shared = DashboardShortcutUsageStore()
    @Published private(set) var counts: [String: Int] = [:]
    private let key = "aesdetic_dashboard_shortcut_usage_v1"
    
    private init() {
        load()
    }
    
    func count(for key: String) -> Int {
        counts[key] ?? 0
    }
    
    func increment(key: String) {
        var updated = counts
        updated[key, default: 0] += 1
        counts = updated
        save()
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        counts = decoded
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(counts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

@MainActor
final class SceneFavoritesStore: ObservableObject {
    static let shared = SceneFavoritesStore()
    @Published private(set) var sceneIds: Set<UUID> = []
    private let key = "aesdetic_scene_favorites_v1"
    
    private init() {
        load()
    }
    
    func contains(_ id: UUID) -> Bool {
        sceneIds.contains(id)
    }
    
    func toggle(_ id: UUID) {
        var updated = sceneIds
        if updated.contains(id) {
            updated.remove(id)
        } else {
            updated.insert(id)
        }
        sceneIds = updated
        save()
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        sceneIds = Set(decoded.compactMap { UUID(uuidString: $0) })
    }
    
    private func save() {
        let list = sceneIds.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

@MainActor
final class PresetFavoritesStore: ObservableObject {
    static let shared = PresetFavoritesStore()
    @Published private(set) var presetIds: Set<UUID> = []
    private let key = "aesdetic_preset_favorites_v1"
    
    private init() {
        load()
    }
    
    func contains(_ id: UUID) -> Bool {
        presetIds.contains(id)
    }
    
    func toggle(_ id: UUID) {
        var updated = presetIds
        if updated.contains(id) {
            updated.remove(id)
        } else {
            updated.insert(id)
        }
        presetIds = updated
        save()
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        presetIds = Set(decoded.compactMap { UUID(uuidString: $0) })
    }
    
    private func save() {
        let list = presetIds.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

@MainActor
final class RecoveredPresetFavoritesStore: ObservableObject {
    static let shared = RecoveredPresetFavoritesStore()
    @Published private(set) var presetKeys: Set<String> = []
    private let key = "aesdetic_recovered_preset_favorites_v1"

    private init() {
        load()
    }

    func contains(_ key: String) -> Bool {
        presetKeys.contains(key)
    }

    func toggle(_ key: String) {
        var updated = presetKeys
        if updated.contains(key) {
            updated.remove(key)
        } else {
            updated.insert(key)
        }
        presetKeys = updated
        save()
    }

    private func load() {
        guard let decoded = UserDefaults.standard.array(forKey: key) as? [String] else { return }
        presetKeys = Set(decoded)
    }

    private func save() {
        UserDefaults.standard.set(Array(presetKeys), forKey: key)
    }
}

// MARK: - Device Statistics Section

struct DeviceStatsSection: View {
    let totalDevices: Int
    let activeDevices: Int
    let activeAutomations: Int
    @Environment(\.colorScheme) private var colorScheme

    private var valueColor: Color {
        AppTheme.text(.glassPrimary, for: colorScheme)
    }
    private var labelColor: Color {
        AppTheme.text(.glassSecondary, for: colorScheme)
    }
    private var dividerColor: Color {
        AppTheme.text(.glassTertiary, for: colorScheme).opacity(colorScheme == .dark ? 0.42 : 0.38)
    }

    var body: some View {
        AppOverviewCard(
            metrics: [
                AppOverviewMetric(value: "\(totalDevices)", label: "Devices"),
                AppOverviewMetric(value: "\(activeDevices)", label: "Online"),
                AppOverviewMetric(value: "\(activeAutomations)", label: "Routines")
            ],
            style: .systemGlass(tint: nil, interactive: false),
            cornerRadius: 20,
            valueColorOverride: valueColor,
            labelColorOverride: labelColor,
            dividerColorOverride: dividerColor,
            valueFontOverride: DashboardTypography.metricValue,
            labelFontOverride: DashboardTypography.metricLabel,
            height: 60
        )
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
                MiniDeviceCard(device: device, onTap: {
                    // Navigation will be handled by parent view
                })
            }
        }
    }
}

// MARK: - Mini Device Card (HomePod Style)

struct MiniDeviceCard: View {
    let device: WLEDDevice
    let onTap: () -> Void
    var showPowerToggle: Bool = true
    @ObservedObject private var viewModel = DeviceControlViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isToggling: Bool = false

    init(
        device: WLEDDevice,
        onTap: @escaping () -> Void = {},
        showPowerToggle: Bool = true
    ) {
        self.device = device
        self.onTap = onTap
        self.showPowerToggle = showPowerToggle
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

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var isReferenceLightMode: Bool { colorScheme == .light }
    private var primaryTextColor: Color {
        AppTheme.text(.glassPrimary, for: colorScheme).opacity(colorScheme == .dark ? 0.92 : 0.96)
    }
    private var secondaryTextColor: Color {
        AppTheme.text(.glassSecondary, for: colorScheme).opacity(colorScheme == .dark ? 0.95 : 1.0)
    }
    private let miniCardCornerRadius: CGFloat = DeviceDetailPresentation.folderSourceCornerRadius
    private var requiresSetup: Bool { device.setupState == .pendingSelection }
    private var statusAccessibilityText: String {
        if requiresSetup {
            return "Setup required"
        }
        return device.isOnline ? "Online" : "Offline"
    }

    @ViewBuilder
    private var statusDot: some View {
        let shape = Circle()
        if device.isOnline && !requiresSetup {
            shape
                .fill(Color.white.opacity(0.92))
                .frame(width: 6, height: 6)
        } else {
            shape
                .stroke(Color.white.opacity(requiresSetup ? 0.76 : 0.58), lineWidth: 1.2)
                .frame(width: 6, height: 6)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                cardTapSurface

                miniCardBackground
                    .allowsHitTesting(false)

                // Product image positioned to peek out from bottom (contained within card)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        productImageSection(cardWidth: geometry.size.width)
                            .offset(y: currentPowerState ? geometry.size.height * 0.04 : geometry.size.height * 0.12)
                        Spacer()
                    }
                }
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            
                // Text content stays non-interactive so card taps pass through to cardTapSurface.
                VStack(alignment: .leading, spacing: 0) {
                    deviceTextContent
                        .padding(.top, 18)
                        .padding(.leading, 18)
                        .padding(.trailing, showPowerToggle ? 68 : 18)

                    Spacer()
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1)

                if showPowerToggle {
                    HStack {
                        Spacer()
                        powerToggleButton
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .zIndex(2)
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .scaleEffect(1.0)
        .clipShape(RoundedRectangle(cornerRadius: miniCardCornerRadius, style: .continuous))
        .overlay {
            if requiresSetup {
                Button(action: onTap) {
                    RoundedRectangle(cornerRadius: miniCardCornerRadius, style: .continuous)
                        .fill(Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete setup for \(device.name)")
            }
        }
        .onAppear {
            // Clear any UI optimistic state on appear
            viewModel.clearUIOptimisticState(deviceId: device.id)
        }
        .onDisappear {
            // Clean up UI optimistic state when view disappears
            viewModel.clearUIOptimisticState(deviceId: device.id)
        }
    }

    private var cardTapSurface: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: miniCardCornerRadius, style: .continuous)
                .fill(Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: miniCardCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(.plain)
        .accessibilityLabel("Open details for \(device.name), \(device.location.displayName), \(statusAccessibilityText)")
    }

    private var deviceTextContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                statusDot

                Text(device.location.displayName)
                    .font(DashboardTypography.micro.weight(.medium))
                    .foregroundColor(secondaryTextColor.opacity(device.isOnline ? 0.92 : 0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }

            Text(device.name)
                .font(DashboardTypography.cardTitle)
                .foregroundColor(primaryTextColor)
                .opacity(device.isOnline ? 1.0 : 0.64)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var miniCardBackground: some View {
        FolderGlassContainerBackground(cornerRadius: miniCardCornerRadius)
    }

    // MARK: - Product Image Section (SIMPLIFIED - No glow effects)
    private func productImageSection(cardWidth: CGFloat) -> some View {
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
        .frame(width: cardWidth * 0.7)
        .opacity(device.isOnline && currentPowerState ? 1.0 : 0.5)
    }

    // MARK: - Enhanced Power Toggle Button with Coordinated State Management
    private var powerToggleButton: some View {
        Button(action: {
            if requiresSetup {
                onTap()
                return
            }
            // Calculate target state BEFORE any state changes
            let targetState = !currentPowerState
            
            // If device appears offline but we're trying to control it, mark it as online
            // This handles cases where discovery set isOnline=true but UI hasn't updated yet
            if !device.isOnline {
                viewModel.markDeviceOnline(device.id)
            }
            
            // Register UI optimistic state with ViewModel for coordination
            // Register optimistic UI state for immediate feedback
            // Note: This method was removed to prevent memory leaks
            isToggling = true
            
            // Haptic feedback for immediate response
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            Task {
                #if DEBUG
                print("🎯 Dashboard toggle initiated: \(device.id) → \(targetState ? "ON" : "OFF")")
                #endif
                
                await viewModel.toggleDevicePower(device)
                let settled = await viewModel.awaitPowerToggleSettlement(for: device, targetState: targetState)
                
                // Reset UI state after completion (next runloop tick)
                DispatchQueue.main.async {
                    isToggling = false
                    let finalState = viewModel.getCurrentPowerState(for: device.id)
                    if settled && finalState == targetState {
                        #if DEBUG
                        print("✅ Dashboard toggle successful: \(targetState ? "ON" : "OFF")")
                        #endif
                    } else {
                        #if DEBUG
                        print("⚠️ Dashboard toggle mismatch - wanted: \(targetState), got: \(finalState)")
                        #endif
                    }
                }
            }
        }) {
            ZStack {
                Image(systemName: "power")
                    .font(AppTypography.style(.headline, weight: .medium))
                    .foregroundColor(
                        isReferenceLightMode
                            ? Color.white.opacity(currentPowerState ? 0.90 : 0.72)
                            : AppTheme.controlForeground(for: colorScheme, isActive: currentPowerState)
                    )
                    .opacity(isToggling ? 0.7 : 1.0)
                
                // Loading indicator overlay
                if isToggling {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(AppTheme.controlForeground(for: colorScheme, isActive: currentPowerState))
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
                            .fill(currentPowerState ? AppTheme.controlFill(for: colorScheme, isActive: true) : .clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppTheme.controlStroke(for: colorScheme, isActive: currentPowerState), lineWidth: currentPowerState ? 1 : 1.5)
                            )
                    }
                }
            )
            .shadow(
                color: theme.controlShadowAmbient.color,
                radius: theme.controlShadowAmbient.radius,
                x: theme.controlShadowAmbient.x,
                y: theme.controlShadowAmbient.y
            )
            .shadow(
                color: theme.controlShadowKey.color,
                radius: theme.controlShadowKey.radius,
                x: theme.controlShadowKey.x,
                y: theme.controlShadowKey.y
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .scaleEffect(isToggling ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isToggling)
            .animation(.easeInOut(duration: 0.2), value: currentPowerState)
        }
        .buttonStyle(SnappyTapButtonStyle(pressedScale: 0.9, response: 0.16, damping: 0.78))
        .sensorySelection(trigger: isToggling)
        .accessibilityLabel(currentPowerState ? "Turn \(device.name) off" : "Turn \(device.name) on")
        .disabled(isToggling || requiresSetup)
    }

}

// MARK: - Add Scene Button
struct AddSceneButton: View {
    @State private var showAddScene = false
    var compact: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private var actionTextColor: Color {
        AppTheme.text(.glassPrimary, for: colorScheme).opacity(0.92)
    }
    
    var body: some View {
        Button(action: { showAddScene = true }) {
            HStack(spacing: compact ? 6 : 8) {
                Image(systemName: "plus.circle")
                    .font(compact ? DashboardTypography.buttonCompact : DashboardTypography.buttonRegular)
                Text(compact ? "Scene" : "Add")
                    .font(compact ? DashboardTypography.buttonCompact : DashboardTypography.buttonRegular)
            }
            .foregroundColor(actionTextColor)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 8)
        }
        .buttonStyle(SnappyTapButtonStyle(pressedScale: 0.96, response: 0.16, damping: 0.8))
        .accessibilityLabel("Add Scene")
        .appLiquidGlass(role: .control)
        .sheet(isPresented: $showAddScene) {
            SceneEditorSheet()
        }
    }
}

// MARK: - Add Automation Button
struct AddAutomationButton: View {
    @State private var showAddAutomation = false
    @State private var builderDevice: WLEDDevice?
    @State private var pendingTemplate: AutomationTemplate?
    @State private var editingAutomation: Automation?
    @ObservedObject private var automationStore = AutomationStore.shared
    var compact: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private var actionTextColor: Color {
        AppTheme.text(.glassPrimary, for: colorScheme).opacity(0.92)
    }
    
    var body: some View {
        Button(action: { showAddAutomation = true }) {
            HStack(spacing: compact ? 6 : 8) {
                Image(systemName: "plus.circle")
                    .font(compact ? DashboardTypography.buttonCompact : DashboardTypography.buttonRegular)
                Text("Add")
                    .font(compact ? DashboardTypography.buttonCompact : DashboardTypography.buttonRegular)
            }
            .foregroundColor(actionTextColor)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 8)
        }
        .buttonStyle(SnappyTapButtonStyle(pressedScale: 0.96, response: 0.16, damping: 0.8))
        .accessibilityLabel("Add Automation")
        .appLiquidGlass(role: .control)
        .disabled(automationStore.hasAnyDeletionInProgress)
        .opacity(automationStore.hasAnyDeletionInProgress ? 0.45 : 1.0)
        .sheet(isPresented: $showAddAutomation, onDismiss: {
            builderDevice = nil
            pendingTemplate = nil
            editingAutomation = nil
        }) {
            AutomationCreationSheet(
                builderDevice: $builderDevice,
                pendingTemplate: $pendingTemplate,
                editingAutomation: $editingAutomation,
                isPresented: $showAddAutomation
            )
        }
    }
}

private struct LiquidGlassLogoGlyph: View {
    let logoImage: UIImage

    var body: some View {
        let glyphMask = Image(uiImage: logoImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(4)

        Color.clear
            .appLiquidGlass(role: .control, cornerRadius: 14)
            .mask(glyphMask)
        .frame(width: 44, height: 44)
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
