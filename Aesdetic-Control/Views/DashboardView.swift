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
    @State private var navigationPath = NavigationPath()
    @State private var selectedDevice: WLEDDevice?
    
    // MARK: - Performance Optimization Properties
    
    // Derived-data cache (updated only from explicit events, never from computed properties)
    @State private var memoizedDeviceStats: (total: Int, online: Int, offline: Int) = (0, 0, 0)
    @State private var memoizedFilteredDevices: [WLEDDevice] = []
    
    private let deviceUpdateThrottle: TimeInterval = 0.5 // 500ms throttle window
    @State private var lastDerivedUpdate: Date = .distantPast
    @State private var derivedUpdateWorkItem: DispatchWorkItem?
    
    // Animation optimization
    private let standardAnimation: Animation = .easeInOut(duration: 0.25)
    private let fastAnimation: Animation = .easeInOut(duration: 0.15)
    private let smoothAnimation: Animation = .interpolatingSpring(stiffness: 300, damping: 30)
    private let debugHideGreeting = false
    private let debugHideQuote = false
    private let debugHideScenes = false
    private let debugHideLogo = false
    private let debugHideStats = false
    
    // Background handled globally by AppBackground
    
    // Side-effect-free accessors
    private var deviceStatistics: (total: Int, online: Int, offline: Int) { memoizedDeviceStats }
    private var filteredDevices: [WLEDDevice] { memoizedFilteredDevices }

    private var primaryTextColor: Color { DashboardPalette.primaryText(colorScheme) }
    private var secondaryTextColor: Color { DashboardPalette.secondaryText(colorScheme) }
    
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

                VStack(spacing: 0) {
                // Header hierarchy: greeting dominates, quote sits as supporting copy.
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !debugHideGreeting {
                            Text(dashboardViewModel.currentGreeting)
                                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                                .foregroundColor(primaryTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .id(dashboardViewModel.currentGreeting)
                        }

                        if !debugHideQuote {
                            Text(dashboardViewModel.currentQuote)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(secondaryTextColor.opacity(0.92))
                                .lineLimit(2)
                                .lineSpacing(2)
                                .multilineTextAlignment(.leading)
                                .id(dashboardViewModel.currentQuote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !debugHideLogo {
                        Group {
                            if let logoImage = UIImage(named: "aesdetic_logo") {
                                Image(uiImage: logoImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.title3.weight(.medium))
                                    .foregroundColor(primaryTextColor)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Scenes & Automations
                if !debugHideScenes {
                    ScenesAutomationsSection(
                        automations: automationViewModel.automations,
                        deviceViewModel: deviceControlViewModel,
                        onToggle: { automation in
                            Task { automationViewModel.toggleAutomation(automation) }
                        }
                    )
                    .padding(.top, 0)
                    .padding(.bottom, 8)
                    .onReceive(automationViewModel.$automations) { _ in
                        DispatchQueue.main.async { recomputeDerivedIfNeeded() }
                    }
                }

                // Devices stats (from derived cache)
                if !debugHideStats {
                    DeviceStatsSection(
                        totalDevices: deviceStatistics.total,
                        activeDevices: deviceStatistics.online,
                        activeAutomations: automationViewModel.automations.filter { $0.enabled }.count
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Device cards grid (from derived cache)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 18)],
                    spacing: 18
                ) {
                    ForEach(filteredDevices, id: \.id) { device in
                        MiniDeviceCard(device: device, onTap: {
                            selectedDevice = device
                        })
                        .id(device.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .background(Color.clear)
                .onChange(of: deviceControlViewModel.devices) { _, _ in
                    DispatchQueue.main.async { recomputeDerivedIfNeeded() }
                }
                .onChange(of: deviceControlViewModel.selectedLocationFilter) { _, _ in
                    DispatchQueue.main.async { updateMemoizedFilteredDevices() }
                }

                Spacer(minLength: 8)
            }
        }
            .onAppear {
                updateMemoizedStats()
                updateMemoizedFilteredDevices()
            }
            .sheet(item: $selectedDevice) { device in
                DeviceDetailView(device: device, viewModel: deviceControlViewModel)
            }
            .navigationBarHidden(true)
        }
        .background(Color.clear)
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
                        .font(.title3.weight(.medium))
                        .foregroundColor(primaryTextColor)
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
                .font(.largeTitle.bold())
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
                .font(.title2)
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
                MiniDeviceCard(device: device, onTap: {
                    selectedDevice = device
                })
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


// MARK: - Scenes & Automations Section

struct ScenesAutomationsSection: View {
    let automations: [Automation]
    let deviceViewModel: DeviceControlViewModel
    let onToggle: (Automation) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var scenesStore = SceneGroupStore.shared
    @ObservedObject private var presetsStore = PresetsStore.shared
    @StateObject private var usageStore = DashboardShortcutUsageStore.shared
    @StateObject private var favoritesStore = SceneFavoritesStore.shared
    @StateObject private var presetFavoritesStore = PresetFavoritesStore.shared
    private let pillRowHeight: CGFloat = 44
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Scenes")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(DashboardPalette.primaryText(colorScheme))

                Spacer()

                AddSceneButton(compact: true)
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(displayedSceneShortcuts) { item in
                        DashboardPillButton(
                            title: item.title,
                            isSelected: false,
                            action: {
                                usageStore.increment(key: item.usageKey)
                                handleSceneShortcut(item)
                            }
                        )
                        .contextMenu {
                            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                                toggleFavorite(for: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: pillRowHeight)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollClipDisabled()
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Automations")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(DashboardPalette.primaryText(colorScheme))

                Spacer()

                AddAutomationButton(compact: true)
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(displayedAutomations) { automation in
                        DashboardPillButton(
                            title: automation.name,
                            isSelected: automation.enabled,
                            action: {
                                usageStore.increment(key: "automation:\(automation.id.uuidString)")
                                onToggle(automation)
                            }
                        )
                        .contextMenu {
                            Button((automation.metadata.pinnedToShortcuts ?? false) ? "Unfavorite" : "Favorite") {
                                var updated = automation
                                var metadata = updated.metadata
                                metadata.pinnedToShortcuts = !(automation.metadata.pinnedToShortcuts ?? false)
                                updated.metadata = metadata
                                AutomationStore.shared.update(updated)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: pillRowHeight)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollClipDisabled()
        }
        .background(Color.clear)
    }
    
    private var displayedSceneShortcuts: [SceneShortcutItem] {
        let sceneItems = scenesStore.scenes.map { scene in
            SceneShortcutItem(
                id: "scene:\(scene.id.uuidString)",
                title: scene.name,
                createdAt: scene.createdAt,
                usageKey: "scene:\(scene.id.uuidString)",
                kind: .sceneGroup(scene),
                isFavorite: favoritesStore.contains(scene.id)
            )
        }
        let presetItems = presetsStore.colorPresets.map { preset in
            SceneShortcutItem(
                id: "preset:\(preset.id.uuidString)",
                title: preset.name,
                createdAt: preset.createdAt,
                usageKey: "preset:\(preset.id.uuidString)",
                kind: .preset(preset),
                isFavorite: presetFavoritesStore.contains(preset.id)
            )
        }
        let items = sceneItems + presetItems
        let favorites = items.filter { $0.isFavorite }
        let base = favorites.isEmpty ? items : favorites
        let sorted = base.sorted { lhs, rhs in
            let lhsCount = usageStore.count(for: lhs.usageKey)
            let rhsCount = usageStore.count(for: rhs.usageKey)
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            return lhs.createdAt > rhs.createdAt
        }
        return favorites.isEmpty ? Array(sorted.prefix(3)) : sorted
    }
    
    private var displayedAutomations: [Automation] {
        let favorites = automations.filter { $0.metadata.pinnedToShortcuts ?? false }
        let base = favorites.isEmpty ? automations : favorites
        let sorted = base.sorted { lhs, rhs in
            let lhsCount = usageStore.count(for: "automation:\(lhs.id.uuidString)")
            let rhsCount = usageStore.count(for: "automation:\(rhs.id.uuidString)")
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            let lhsDate = lhs.lastTriggered ?? lhs.updatedAt
            let rhsDate = rhs.lastTriggered ?? rhs.updatedAt
            return lhsDate > rhsDate
        }
        return favorites.isEmpty ? Array(sorted.prefix(3)) : sorted
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
    
    private func handleSceneShortcut(_ item: SceneShortcutItem) {
        switch item.kind {
        case .sceneGroup(let scene):
            applySceneGroup(scene)
        case .preset(let preset):
            applyPreset(preset)
        }
    }
    
    private func toggleFavorite(for item: SceneShortcutItem) {
        switch item.kind {
        case .sceneGroup(let scene):
            favoritesStore.toggle(scene.id)
        case .preset(let preset):
            presetFavoritesStore.toggle(preset.id)
        }
    }
    
    private struct SceneShortcutItem: Identifiable {
        enum Kind {
            case sceneGroup(SceneGroup)
            case preset(ColorPreset)
        }
        
        let id: String
        let title: String
        let createdAt: Date
        let usageKey: String
        let kind: Kind
        let isFavorite: Bool
    }
}

// MARK: - Dashboard Pill Button (Matches Device Location Pills)

struct DashboardPillButton: View {
    enum Size {
        case regular
        case compact
    }

    let title: String
    let isSelected: Bool
    var iconName: String? = nil
    var trailingText: String? = nil
    var size: Size = .regular
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var fillColor: Color { DashboardPalette.pillFill(colorScheme, isSelected: isSelected) }
    private var strokeColor: Color { DashboardPalette.pillStroke(colorScheme, isSelected: isSelected) }
    private var textColor: Color { DashboardPalette.pillText(colorScheme, isSelected: isSelected) }
    private var secondaryTextColor: Color { DashboardPalette.pillSubtext(colorScheme, isSelected: isSelected) }
    private var surfaceStyle: GlassSurfaceStyle { GlassTheme.surfaces(for: colorScheme) }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .compact ? 6 : 8) {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(size == .compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundColor(textColor)
                }
                
                Text(title)
                    .font(size == .compact ? .caption.weight(.semibold) : .subheadline.weight(.medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                if let trailingText = trailingText {
                    Text(trailingText)
                        .font(size == .compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(.horizontal, size == .compact ? 12 : 16)
            .padding(.vertical, size == .compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: size == .compact ? 14 : 18, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size == .compact ? 14 : 18, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(
                color: surfaceStyle.controlShadowAmbient.color,
                radius: surfaceStyle.controlShadowAmbient.radius,
                x: surfaceStyle.controlShadowAmbient.x,
                y: surfaceStyle.controlShadowAmbient.y
            )
            .shadow(
                color: surfaceStyle.controlShadowKey.color,
                radius: surfaceStyle.controlShadowKey.radius,
                x: surfaceStyle.controlShadowKey.x,
                y: surfaceStyle.controlShadowKey.y
            )
        }
        .buttonStyle(.plain)
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

// MARK: - Device Statistics Section

struct DeviceStatsSection: View {
    let totalDevices: Int
    let activeDevices: Int
    let activeAutomations: Int
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Devices")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(DashboardPalette.primaryText(colorScheme))
            
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
    private let cornerRadius: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme
    
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
        .background(
            GlassCardBackground(
                cornerRadius: cornerRadius,
                fill: DashboardPalette.cardFill(colorScheme),
                outerStroke: DashboardPalette.cardStrokeOuter(colorScheme),
                innerStroke: DashboardPalette.cardStrokeInner(colorScheme),
                keyShadow: DashboardPalette.cardShadowKey(colorScheme).asGlassShadow,
                ambientShadow: DashboardPalette.cardShadowAmbient(colorScheme).asGlassShadow
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Individual Statistic Item

struct StatisticItem: View {
    let number: String
    let label: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Large Number (left side)
            Text(number)
                .font(.title.bold())
                .foregroundColor(DashboardPalette.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            // Description Text (right side, left-aligned)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(DashboardPalette.secondaryText(colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(DashboardPalette.divider(colorScheme))
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

    init(device: WLEDDevice, onTap: @escaping () -> Void = {}, showPowerToggle: Bool = true) {
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

    private var primaryTextColor: Color { DashboardPalette.primaryText(colorScheme) }
    private var secondaryTextColor: Color { DashboardPalette.secondaryText(colorScheme) }
    private var cardFillColor: Color { DashboardPalette.cardFill(colorScheme, isActive: currentPowerState) }
    private var surfaceStyle: GlassSurfaceStyle { GlassTheme.surfaces(for: colorScheme) }
    private var activeRunStatus: ActiveRunStatus? { viewModel.activeRunStatus[device.id] }
    
    var body: some View {
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
                                .font(.headline.weight(.semibold))
                                .foregroundColor(primaryTextColor)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(device.location.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(secondaryTextColor)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let run = activeRunStatus {
                                runStatusChip(run)
                            }
                        }
                        
                        Spacer()
                        
                        // Toggle button on the right - this is the ONLY interactive button
                        if showPowerToggle {
                            powerToggleButton
                        }
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
                    
                    Spacer()
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .scaleEffect(1.0)
        .background(
            GlassCardBackground(
                cornerRadius: 20,
                fill: cardFillColor,
                outerStroke: DashboardPalette.cardStrokeOuter(colorScheme),
                innerStroke: DashboardPalette.cardStrokeInner(colorScheme),
                keyShadow: DashboardPalette.cardShadowKey(colorScheme).asGlassShadow,
                ambientShadow: DashboardPalette.cardShadowAmbient(colorScheme).asGlassShadow
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            onTap()
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
                    .font(.headline.weight(.medium))
                    .foregroundColor(DashboardPalette.powerIcon(colorScheme, isOn: currentPowerState))
                    .opacity(isToggling ? 0.7 : 1.0)
                
                // Loading indicator overlay
                if isToggling {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(DashboardPalette.powerIcon(colorScheme, isOn: currentPowerState))
                }
            }
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DashboardPalette.powerFill(colorScheme, isOn: currentPowerState))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DashboardPalette.powerStroke(colorScheme, isOn: currentPowerState), lineWidth: 1.2)
                    )
            )
            .shadow(
                color: surfaceStyle.controlShadowAmbient.color,
                radius: surfaceStyle.controlShadowAmbient.radius,
                x: surfaceStyle.controlShadowAmbient.x,
                y: surfaceStyle.controlShadowAmbient.y
            )
            .shadow(
                color: surfaceStyle.controlShadowKey.color,
                radius: surfaceStyle.controlShadowKey.radius,
                x: surfaceStyle.controlShadowKey.x,
                y: surfaceStyle.controlShadowKey.y
            )
            .scaleEffect(isToggling ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isToggling)
            .animation(.easeInOut(duration: 0.2), value: currentPowerState)
        }
        .buttonStyle(.plain)
        .sensorySelection(trigger: isToggling)
        .disabled(!device.isOnline || isToggling)
    }

    @ViewBuilder
    private func runStatusChip(_ run: ActiveRunStatus) -> some View {
        Text(runStatusText(run))
        .font(.caption2)
        .foregroundColor(.white.opacity(0.85))
        .lineLimit(1)
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
        .padding(.top, 1)
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
}

// MARK: - Add Scene Button
struct AddSceneButton: View {
    @State private var showAddScene = false
    var compact: Bool = false
    
    var body: some View {
        DashboardPillButton(
            title: "Add Scene",
            isSelected: false,
            iconName: "plus.circle",
            size: compact ? .compact : .regular,
            action: { showAddScene = true }
        )
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
    var compact: Bool = false
    
    var body: some View {
        DashboardPillButton(
            title: "Add Automation",
            isSelected: false,
            iconName: "plus.circle",
            size: compact ? .compact : .regular,
            action: { showAddAutomation = true }
        )
        .sheet(isPresented: $showAddAutomation, onDismiss: {
            builderDevice = nil
            pendingTemplate = nil
        }) {
            AutomationCreationSheet(
                builderDevice: $builderDevice,
                pendingTemplate: $pendingTemplate,
                isPresented: $showAddAutomation
            )
        }
    }
}

private enum DashboardPalette {
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    private static let lightDashboardText = Color(red: 95.0 / 255.0, green: 91.0 / 255.0, blue: 87.0 / 255.0) // #5F5B57

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? GlassTheme.text(for: scheme).pagePrimaryText : lightDashboardText
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? GlassTheme.text(for: scheme).pageSecondaryText : lightDashboardText
    }

    static func cardFill(_ scheme: ColorScheme, isActive: Bool = true) -> Color {
        let style = GlassTheme.surfaces(for: scheme)
        return isActive ? style.cardFillActive : style.cardFillInactive
    }

    static func cardStrokeOuter(_ scheme: ColorScheme) -> Color {
        GlassTheme.surfaces(for: scheme).cardStrokeOuter
    }

    static func cardStrokeInner(_ scheme: ColorScheme) -> Color {
        GlassTheme.surfaces(for: scheme).cardStrokeInner
    }

    static func cardShadowKey(_ scheme: ColorScheme) -> ShadowStyle {
        let shadow = GlassTheme.surfaces(for: scheme).cardShadowKey
        return ShadowStyle(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    static func cardShadowAmbient(_ scheme: ColorScheme) -> ShadowStyle {
        let shadow = GlassTheme.surfaces(for: scheme).cardShadowAmbient
        return ShadowStyle(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    static func divider(_ scheme: ColorScheme) -> Color {
        GlassTheme.surfaces(for: scheme).separator
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
        if scheme == .dark {
            let textStyle = GlassTheme.text(for: scheme)
            return isSelected ? textStyle.pillTextSelected : textStyle.pillTextDefault
        }
        return lightDashboardText
    }

    static func pillSubtext(_ scheme: ColorScheme, isSelected: Bool) -> Color {
        if scheme == .dark {
            let textStyle = GlassTheme.text(for: scheme)
            return isSelected ? textStyle.pillSubtextSelected : textStyle.pillSubtextDefault
        }
        return lightDashboardText
    }

    static func powerIcon(_ scheme: ColorScheme, isOn: Bool) -> Color {
        if scheme == .dark {
            return isOn ? .black : .white
        }
        return lightDashboardText
    }

    static func powerFill(_ scheme: ColorScheme, isOn: Bool) -> Color {
        isOn ? .white : .clear
    }

    static func powerStroke(_ scheme: ColorScheme, isOn: Bool) -> Color {
        scheme == .dark ? (isOn ? .clear : .white) : .clear
    }
}

private extension DashboardPalette.ShadowStyle {
    var asGlassShadow: GlassShadowStyle {
        GlassShadowStyle(color: color, radius: radius, x: x, y: y)
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .preferredColorScheme(.dark)
    }
}
