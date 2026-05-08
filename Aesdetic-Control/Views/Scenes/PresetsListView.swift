import SwiftUI

private struct PresetGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let tone: AppCardTone

    func body(content: Content) -> some View {
        content
            .background(
                AppCardBackground(
                    style: AppCardStyles.glass(
                        for: colorScheme,
                        tone: tone,
                        cornerRadius: cornerRadius
                    )
                )
            )
    }
}

private extension View {
    func presetGlassCard(
        cornerRadius: CGFloat = 18,
        tone: AppCardTone = .muted
    ) -> some View {
        modifier(PresetGlassCardModifier(cornerRadius: cornerRadius, tone: tone))
    }
}

struct PresetsListView: View {
    @ObservedObject var store = PresetsStore.shared
    @ObservedObject private var automationStore = AutomationStore.shared
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice
    let onRequestRename: (PresetRenameContext) -> Void
    let onOpenIntegrations: () -> Void
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @State private var isPlaylistEditorPresented = false
    @State private var playlistEditorOriginalId: Int?
    @State private var playlistEditorDraft = PlaylistEditorDraft.defaultDraft
    @State private var expandedAutomationFolders: Set<UUID> = []
    @State private var deletingColorPresetIds: Set<UUID> = []
    @State private var deletingTransitionPresetIds: Set<UUID> = []
    @State private var deletingEffectPresetIds: Set<UUID> = []

    init(
        device: WLEDDevice,
        onRequestRename: @escaping (PresetRenameContext) -> Void,
        onOpenIntegrations: @escaping () -> Void = {}
    ) {
        self.device = device
        self.onRequestRename = onRequestRename
        self.onOpenIntegrations = onOpenIntegrations
    }
    
    var body: some View {
        VStack(spacing: 16) {
            colorPresetsSection
            effectPresetsSection

            if advancedUIEnabled {
                automationAssetsAdvancedSection
            }
        }
        .navigationTitle("Saves")
        .sheet(isPresented: $isPlaylistEditorPresented) {
            PlaylistEditorSheet(
                draft: $playlistEditorDraft,
                originalId: playlistEditorOriginalId,
                device: device,
                availablePresetIds: viewModel.presets(for: device).map(\.id),
                onCancel: {
                    isPlaylistEditorPresented = false
                },
                onSave: { draft in
                    Task {
                        let resolvedId: Int
                        if let existingId = playlistEditorOriginalId {
                            resolvedId = existingId
                        } else if let nextId = viewModel.nextPlaylistId(for: device) {
                            resolvedId = nextId
                        } else {
                            return
                        }
                        let request = draft.asSaveRequest(withId: resolvedId)
                        let success = await viewModel.savePlaylistRecord(request, for: device)
                        if success {
                            isPlaylistEditorPresented = false
                        }
                    }
                },
                onTest: { draft in
                    Task {
                        let request = draft.asSaveRequest(withId: playlistEditorOriginalId ?? 1)
                        _ = await viewModel.testPlaylistRecord(request, for: device)
                    }
                },
                onRun: { playlistId in
                    Task {
                        let targetId = playlistId ?? playlistEditorOriginalId
                        guard let targetId else { return }
                        _ = await viewModel.startPlaylist(
                            device: device,
                            playlistId: targetId,
                            runTitle: playlistEditorDraft.name,
                            expectedDurationSeconds: nil,
                            transitionDeciseconds: nil,
                            runKind: .effect,
                            preferWebSocketFirst: true
                        )
                    }
                },
                onStop: {
                    Task {
                        _ = await viewModel.stopPlaylist(for: device)
                    }
                }
            )
            .presentationDetents([.large])
        }
        .task {
            await viewModel.refreshPresetsIfModified(for: device)
            if advancedUIEnabled {
                await viewModel.loadPlaylists(for: device, force: false)
                await viewModel.loadPresets(for: device, force: false)
            }
        }
        .onChange(of: advancedUIEnabled) { _, enabled in
            guard enabled else { return }
            Task {
                await viewModel.loadPlaylists(for: device, force: false)
                await viewModel.loadPresets(for: device, force: false)
            }
        }
    }

    private var alexaFavoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Alexa Favorites", icon: "star", count: "\(alexaFavorites.count)/9")

            let conflicts = viewModel.alexaMirrorConflictSlots(for: device)
            if !conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    alexaStatusRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Alexa slots need review",
                        message: "WLED slots \(conflicts.map(String.init).joined(separator: ", ")) already contain presets.",
                        actionTitle: "Use Existing",
                        action: {
                            store.clearAlexaFavorites(for: device.id)
                            viewModel.clearAlexaMirrorConflicts(for: device)
                        }
                    )
                    Button("Replace with Aesdetic Favorites") {
                        Task {
                            _ = await viewModel.syncAlexaFavoritesToDevice(
                                device,
                                enabled: true,
                                invocationName: device.name,
                                allowReplacingExisting: true
                            )
                        }
                    }
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white)
                    .cornerRadius(8)
                }
            }

            if alexaFavorites.isEmpty {
                emptyStateView(
                    icon: "star",
                    message: "No Alexa favorites",
                    hint: "Choose up to 9 presets Alexa can discover"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(alexaFavorites) { favorite in
                        AlexaFavoriteRow(favorite: favorite) {
                            viewModel.removeAlexaFavorite(favorite, for: device)
                        }
                    }
                }
            }
        }
    }

    private var alexaFavorites: [AlexaFavorite] {
        store.alexaFavorites(for: device.id)
    }

    private var alexaIntegrationEnabled: Bool {
        viewModel.isAlexaIntegrationEnabled(for: device)
    }

    private func alexaStatusRow(
        icon: String,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.62))
            }
            Spacer()
            Button(actionTitle, action: action)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.14)))
        }
        .padding(10)
        .presetGlassCard(cornerRadius: 16)
    }

    private func sectionHeader(_ title: String, icon: String, count: String? = nil) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(AppTypography.style(.headline, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            if let count {
                Text(count)
                    .font(AppTypography.style(.caption2, weight: .semibold))
                    .foregroundColor(.white.opacity(0.74))
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
        }
    }

    private var devicePlaylistsById: [Int: WLEDPlaylist] {
        Dictionary(uniqueKeysWithValues: viewModel.playlists(for: device).map { ($0.id, $0) })
    }

    private var automationFolders: [AutomationAssetFolder] {
        automationStore.automations.compactMap { automation in
            guard automation.metadata.runOnDevice,
                  automation.targets.deviceIds.contains(device.id) else {
                return nil
            }
            let mappedPlaylistId = automation.metadata.wledPlaylistIdsByDevice?[device.id]
            let fallbackPlaylistId = automation.targets.deviceIds.count == 1 ? automation.metadata.wledPlaylistId : nil
            let mappedPresetId = automation.metadata.wledPresetIdsByDevice?[device.id]
            let playlistId = mappedPlaylistId ?? fallbackPlaylistId
            guard (playlistId ?? mappedPresetId) != nil else { return nil }
            return AutomationAssetFolder(
                automationId: automation.id,
                automationName: automation.name,
                playlistId: playlistId,
                presetId: mappedPresetId,
                action: automation.action
            )
        }
        .sorted { $0.automationName.localizedCaseInsensitiveCompare($1.automationName) == .orderedAscending }
    }

    private var nonPlaylistDevicePresets: [WLEDPreset] {
        if viewModel.isLoadingPlaylists(for: device), viewModel.playlists(for: device).isEmpty {
            return []
        }
        let playlistIds = Set(devicePlaylistsById.keys)
        return viewModel
            .presets(for: device)
            .filter { !playlistIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private func colorAlexaCandidate(_ preset: ColorPreset) -> AlexaFavoriteCandidate? {
        guard let wledId = preset.wledPresetIds?[device.id] ?? preset.wledPresetId else { return nil }
        return viewModel.alexaFavoriteCandidate(sourceType: .color, sourceId: preset.id, wledPresetId: wledId, name: preset.name)
    }

    private func transitionAlexaCandidate(_ preset: TransitionPreset) -> AlexaFavoriteCandidate? {
        guard preset.wledSyncState == .synced,
              let playlistId = preset.wledPlaylistId,
              !(temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains(playlistId) else {
            return nil
        }
        return viewModel.alexaFavoriteCandidate(sourceType: .transition, sourceId: preset.id, wledPresetId: playlistId, name: preset.name)
    }

    private func effectAlexaCandidate(_ preset: WLEDEffectPreset) -> AlexaFavoriteCandidate? {
        guard let wledId = preset.wledPresetId else { return nil }
        return viewModel.alexaFavoriteCandidate(sourceType: .effect, sourceId: preset.id, wledPresetId: wledId, name: preset.name)
    }

    private func addToAlexa(_ candidate: AlexaFavoriteCandidate?) {
        guard let candidate else { return }
        _ = viewModel.addAlexaFavorite(candidate, for: device)
    }

    private func isEffectDevicePreset(_ preset: WLEDPreset) -> Bool {
        let segments = preset.state?.seg ?? (preset.segment.map { [$0] } ?? [])
        if let fx = segments.compactMap(\.fx).first {
            return fx > 0
        }
        return false
    }
    
    // MARK: - Color Presets Section
    
    private var colorPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Colors", icon: "sun.max")
            
            let colorPresets = store.colorPresets
            if colorPresets.isEmpty {
                emptyStateView(
                    icon: "paintbrush",
                    message: "No saved colors",
                    hint: "Tap + to save current gradient"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(colorPresets) { preset in
                        let alexaCandidate = colorAlexaCandidate(preset)
                        ColorPresetRow(
                            preset: preset,
                            isDeleting: deletingColorPresetIds.contains(preset.id),
                            isAlexaFavorite: alexaCandidate.map { store.isAlexaFavorite($0, for: device.id) } ?? false,
                            canAddToAlexa: alexaIntegrationEnabled && alexaCandidate != nil && alexaFavorites.count < alexaReservedPresetRange.count,
                            onAddToAlexa: alexaIntegrationEnabled ? { addToAlexa(alexaCandidate) } : nil,
                            onApply: {
                        Task {
                            await viewModel.cancelActiveTransitionIfNeeded(for: device)
                            // Try WLED preset ID first (if synced), otherwise apply directly
                            let presetId = preset.wledPresetIds?[device.id] ?? preset.wledPresetId
                            if let presetId = presetId {
                                _ = await viewModel.applyPresetId(presetId, to: device)
                            } else {
                                // Apply preset directly using gradient stops and brightness
                                let ledCount = viewModel.totalLEDCount(for: device)
                                
                                // Convert temperature/white to stop maps if present
                                var stopTemperatures: [UUID: Double]? = nil
                                var stopWhiteLevels: [UUID: Double]? = nil
                                if let temp = preset.temperature {
                                    stopTemperatures = Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, temp) })
                                }
                                if let white = preset.whiteLevel {
                                    stopWhiteLevels = Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, white) })
                                }
                                
                                // Apply gradient
                                await viewModel.applyGradientStopsAcrossStrip(
                                    device,
                                    stops: preset.gradientStops,
                                    ledCount: ledCount,
                                    stopTemperatures: stopTemperatures,
                                    stopWhiteLevels: stopWhiteLevels,
                                    preferSegmented: true
                                )
                                
                                // Apply brightness via API
                                let apiService = WLEDAPIService.shared
                                _ = try? await apiService.setBrightness(for: device, brightness: preset.brightness)
                            }
                        }
                    }, onEdit: {
                        onRequestRename(.color(preset))
                    }, onDelete: {
                        guard !deletingColorPresetIds.contains(preset.id) else { return }
                        deletingColorPresetIds.insert(preset.id)
                        Task {
                            defer { deletingColorPresetIds.remove(preset.id) }
                            let deleted = await requestColorPresetDeletion(preset, on: device)
                            if deleted {
                                store.removeColorPreset(preset.id)
                            }
                        }
                    })
                    }
                }
            }
        }
    }
    
    // MARK: - Effect Presets Section
    
    private var effectPresetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Transitions", icon: "arrow.triangle.2.circlepath")
                
                let transitionPresets = store.transitionPresets(for: device.id)
                if transitionPresets.isEmpty {
                    emptyStateView(
                        icon: "arrow.triangle.2.circlepath",
                        message: "No saved transitions",
                        hint: "Tap + to save current transition"
                    )
                } else {
                    VStack(spacing: 8) {
                        let queuedPresetId = viewModel.queuedTransitionPresetApplyByDeviceId[device.id]
                        ForEach(transitionPresets) { preset in
                            let alexaCandidate = transitionAlexaCandidate(preset)
                            TransitionPresetRow(
                                preset: preset,
                                isQueued: queuedPresetId == preset.id,
                                isDeleting: deletingTransitionPresetIds.contains(preset.id),
                                isAlexaFavorite: alexaCandidate.map { store.isAlexaFavorite($0, for: device.id) } ?? false,
                                canAddToAlexa: alexaIntegrationEnabled && alexaCandidate != nil && alexaFavorites.count < alexaReservedPresetRange.count,
                                onAddToAlexa: alexaIntegrationEnabled ? { addToAlexa(alexaCandidate) } : nil,
                                onApply: {
                                Task {
                                    _ = await viewModel.applyTransitionPreset(preset, to: device)
                                }
                            }, onEdit: {
                                onRequestRename(.transition(preset))
                            }, onDelete: {
                                guard !deletingTransitionPresetIds.contains(preset.id) else { return }
                                deletingTransitionPresetIds.insert(preset.id)
                                Task {
                                    defer { deletingTransitionPresetIds.remove(preset.id) }
                                    let deleted = await requestTransitionPresetDeletion(preset, on: device)
                                    if deleted {
                                        store.removeTransitionPreset(preset.id)
                                    }
                                }
                            })
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Animations", icon: "sparkles")
                
                let effectPresets = store.effectPresets(for: device.id)
                if effectPresets.isEmpty {
                    emptyStateView(
                        icon: "sparkles",
                        message: "No saved animations",
                        hint: "Tap + to save current effect"
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(effectPresets) { preset in
                            let alexaCandidate = effectAlexaCandidate(preset)
                            EffectPresetRow(
                                preset: preset,
                                isDeleting: deletingEffectPresetIds.contains(preset.id),
                                isAlexaFavorite: alexaCandidate.map { store.isAlexaFavorite($0, for: device.id) } ?? false,
                                canAddToAlexa: alexaIntegrationEnabled && alexaCandidate != nil && alexaFavorites.count < alexaReservedPresetRange.count,
                                onAddToAlexa: alexaIntegrationEnabled ? { addToAlexa(alexaCandidate) } : nil,
                                onApply: {
                            Task {
                                await viewModel.cancelActiveTransitionIfNeeded(for: device)
                                if let stops = preset.gradientStops, !stops.isEmpty {
                                    let gradient = LEDGradient(
                                        stops: stops,
                                        interpolation: preset.gradientInterpolation ?? .linear
                                    )
                                    await viewModel.updateDeviceBrightness(device, brightness: preset.brightness)
                                    await viewModel.applyColorSafeEffect(
                                        preset.effectId,
                                        with: gradient,
                                        segmentId: 0,
                                        device: device
                                    )
                                } else if let presetId = preset.wledPresetId {
                                    _ = await viewModel.applyPresetId(presetId, to: device)
                                } else {
                                    // Apply effect directly
                                    let apiService = WLEDAPIService.shared
                                    
                                    // Set brightness first
                                    _ = try? await apiService.setBrightness(for: device, brightness: preset.brightness)
                                    
                                    // Then set effect with parameters
                                    let segmentUpdate = SegmentUpdate(
                                        id: 0,
                                        bri: preset.brightness,
                                        fx: preset.effectId,
                                        sx: preset.speed,
                                        ix: preset.intensity,
                                        pal: preset.paletteId
                                    )
                                    let stateUpdate = WLEDStateUpdate(
                                        bri: preset.brightness,
                                        seg: [segmentUpdate]
                                    )
                                    _ = try? await apiService.updateState(for: device, state: stateUpdate)
                                }
                            }
                        }, onEdit: {
                            onRequestRename(.effect(preset))
                        }, onDelete: {
                            guard !deletingEffectPresetIds.contains(preset.id) else { return }
                            deletingEffectPresetIds.insert(preset.id)
                            Task {
                                defer { deletingEffectPresetIds.remove(preset.id) }
                                let deleted = await requestEffectPresetDeletion(preset, on: device)
                                if deleted {
                                    store.removeEffectPreset(preset.id)
                                }
                            }
                        })
                        }
                    }
                }
            }

            if alexaIntegrationEnabled {
                Divider()
                    .background(Color.white.opacity(0.2))

                alexaFavoritesSection
            }
        }
    }

    private var automationAssetsAdvancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Automation Assets (Advanced)", systemImage: "folder")
                    .font(AppTypography.style(.headline))
                    .foregroundColor(.white)
                Spacer()
            }

            if automationFolders.isEmpty {
                emptyStateView(
                    icon: "folder",
                    message: "No automation-managed assets",
                    hint: "Automation-created presets/playlists will appear here"
                )
            } else {
                let presetById = Dictionary(uniqueKeysWithValues: nonPlaylistDevicePresets.map { ($0.id, $0) })
                VStack(spacing: 8) {
                    ForEach(automationFolders) { folder in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedAutomationFolders.contains(folder.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedAutomationFolders.insert(folder.id)
                                    } else {
                                        expandedAutomationFolders.remove(folder.id)
                                    }
                                }
                            )
                        ) {
                            VStack(spacing: 8) {
                                if let playlistId = folder.playlistId,
                                   let playlist = devicePlaylistsById[playlistId] {
                                    let preview = automationManagedPlaylistPreview(
                                        for: folder,
                                        playlist: playlist,
                                        presetById: presetById
                                    )
                                    DevicePlaylistRecordRow(
                                        playlist: playlist,
                                        preview: preview,
                                        isDeleting: viewModel.isDeletingPlaylistRecord(playlist.id, for: device),
                                        onRun: {
                                            Task {
                                                _ = await viewModel.startPlaylist(
                                                    device: device,
                                                    playlistId: playlist.id,
                                                    runTitle: playlist.name,
                                                    expectedDurationSeconds: nil,
                                                    transitionDeciseconds: nil,
                                                    runKind: .automation,
                                                    preferWebSocketFirst: true
                                                )
                                            }
                                        },
                                        onEdit: {
                                            onRequestRename(.devicePlaylist(id: playlist.id, name: playlist.name, device: device))
                                        },
                                        onDelete: {
                                            Task {
                                                await viewModel.deletePlaylist(playlist, for: device)
                                            }
                                        }
                                    )

                                    let stepIds = playlist.presets.filter { $0 > 0 }
                                    if !stepIds.isEmpty {
                                        Text("Step presets: \(stepIds.map(String.init).joined(separator: ", "))")
                                            .font(AppTypography.style(.caption2))
                                            .foregroundColor(.white.opacity(0.55))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }

                                if let presetId = folder.presetId,
                                   let preset = nonPlaylistDevicePresets.first(where: { $0.id == presetId }) {
                                    let preview = devicePresetPreview(for: preset)
                                    DevicePresetRecordRow(
                                        preset: preset,
                                        previewGradient: preview.gradient,
                                        previewBrightness: preview.brightness,
                                        isDeleting: viewModel.isDeletingPresetRecord(preset.id, for: device),
                                        onApply: {
                                            Task {
                                                _ = await viewModel.applyPresetId(
                                                    preset.id,
                                                    to: device,
                                                    transitionDeciseconds: nil,
                                                    preferWebSocketFirst: true
                                                )
                                            }
                                        },
                                        onEdit: {
                                            onRequestRename(.devicePreset(id: preset.id, name: preset.name, device: device))
                                        },
                                        onDelete: {
                                            Task {
                                                _ = await viewModel.deletePresetRecord(preset.id, for: device)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.white.opacity(0.85))
                                Text(folder.automationName)
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                if folder.playlistId != nil {
                                    Text("Playlist")
                                        .font(AppTypography.style(.caption2))
                                        .foregroundColor(.white.opacity(0.65))
                                } else if folder.presetId != nil {
                                    Text("Preset")
                                        .font(AppTypography.style(.caption2))
                                        .foregroundColor(.white.opacity(0.65))
                                }
                            }
                        }
                        .padding(12)
                        .presetGlassCard(cornerRadius: 16)
                    }
                }
            }
        }
    }

    // MARK: - Advanced Playlists Section (WLED)

    private var playlistDiscoverabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Device Presets & Playlists", systemImage: "list.bullet.rectangle")
                    .font(AppTypography.style(.headline))
                    .foregroundColor(.white)
                Spacer()
            }

            Text("Device preset and playlist controls are available in Advanced mode.")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.75))
            Text("Enable Advanced mode to view, run, rename, and delete WLED preset/playlist records.")
                .font(AppTypography.style(.caption2))
                .foregroundColor(.white.opacity(0.55))

            Button {
                advancedUIEnabled = true
                Task {
                    await viewModel.loadPresets(for: device, force: false)
                    await viewModel.loadPlaylists(for: device, force: false)
                }
            } label: {
                Label("Enable Advanced Mode", systemImage: "slider.horizontal.3")
                    .font(AppTypography.style(.caption, weight: .semibold))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var advancedDevicePresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Device Presets", systemImage: "square.stack.3d.down.forward")
                    .font(AppTypography.style(.headline))
                    .foregroundColor(.white)
                Spacer()
                Button("Refresh") {
                    Task { await viewModel.refreshPresets(for: device) }
                }
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                )
            }

            let presets = viewModel.presets(for: device)
            if presets.isEmpty {
                emptyStateView(
                    icon: "square.stack.3d.down.forward",
                    message: viewModel.isLoadingPresets(for: device) ? "Loading presets…" : "No presets found",
                    hint: "Preset records saved in WLED will appear here"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(presets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                    .font(AppTypography.style(.subheadline, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Preset \(preset.id)")
                                    .font(AppTypography.style(.caption))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            Button("Run") {
                                Task {
                                    _ = await viewModel.applyPresetId(
                                        preset.id,
                                        to: device,
                                        transitionDeciseconds: nil,
                                        preferWebSocketFirst: true
                                    )
                                }
                            }
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.7))
                            )
                        }
                        .padding(12)
                        .presetGlassCard(cornerRadius: 16)
                    }
                }
            }
        }
    }

    private var advancedPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Device Playlists", systemImage: "list.bullet.rectangle")
                    .font(AppTypography.style(.headline))
                    .foregroundColor(.white)
                Spacer()
                Button("New") {
                    playlistEditorOriginalId = nil
                    playlistEditorDraft = PlaylistEditorDraft.defaultDraft
                    isPlaylistEditorPresented = true
                }
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                )
                Button("Stop") {
                    Task { _ = await viewModel.stopPlaylist(for: device) }
                }
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                )
                Button("Refresh") {
                    Task { await viewModel.refreshPlaylists(for: device) }
                }
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                )
            }

            let playlists = viewModel.playlists(for: device)
            if playlists.isEmpty {
                emptyStateView(
                    icon: "list.bullet.rectangle",
                    message: viewModel.isLoadingPlaylists(for: device) ? "Loading playlists…" : "No playlists found",
                    hint: "Playlists saved in WLED will appear here"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(playlists) { playlist in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(AppTypography.style(.subheadline, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Steps: \(playlist.presets.count)")
                                    .font(AppTypography.style(.caption))
                                    .foregroundColor(.white.opacity(0.6))
                                Text(playlistSummary(playlist))
                                    .font(AppTypography.style(.caption2))
                                    .foregroundColor(.white.opacity(0.55))
                                if viewModel.isPlaylistRenamePending(playlist.id, for: device) {
                                    Text("Rename pending sync")
                                        .font(AppTypography.style(.caption2, weight: .semibold))
                                        .foregroundColor(.yellow.opacity(0.9))
                                }
                            }
                            Spacer()
                            Button("Run") {
                                Task {
                                    _ = await viewModel.startPlaylist(
                                        device: device,
                                        playlistId: playlist.id,
                                        runTitle: playlist.name,
                                        expectedDurationSeconds: nil,
                                        transitionDeciseconds: nil,
                                        runKind: .effect,
                                        preferWebSocketFirst: true
                                    )
                                }
                            }
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.7))
                            )

                            Button("Edit") {
                                playlistEditorOriginalId = playlist.id
                                playlistEditorDraft = PlaylistEditorDraft(playlist: playlist)
                                isPlaylistEditorPresented = true
                            }
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.18))
                            )

                            Button("Copy") {
                                Task {
                                    _ = await viewModel.duplicatePlaylist(playlist, for: device)
                                }
                            }
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.18))
                            )

                            Button {
                                Task { await viewModel.deletePlaylist(playlist, for: device) }
                            } label: {
                                if viewModel.isDeletingPlaylistRecord(playlist.id, for: device) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .controlSize(.mini)
                                } else {
                                    Text("Delete")
                                }
                            }
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.55))
                            )
                            .disabled(viewModel.isDeletingPlaylistRecord(playlist.id, for: device))
                        }
                        .padding(12)
                        .presetGlassCard(cornerRadius: 16)
                    }
                }
            }
        }
    }

    private func playlistSummary(_ playlist: WLEDPlaylist) -> String {
        let repeatText: String
        if let repeatValue = playlist.repeat {
            repeatText = repeatValue == 0 ? "∞" : "\(repeatValue)x"
        } else {
            repeatText = "default"
        }
        let shuffleText = playlist.shuffle == 1 ? "On" : "Off"
        let endText: String
        switch playlist.endPresetId {
        case 255:
            endText = "Restore"
        case let id? where id > 0:
            endText = "Preset \(id)"
        default:
            endText = "None"
        }
        return "Repeat \(repeatText) • Shuffle \(shuffleText) • End \(endText)"
    }

    private struct DevicePresetPreview {
        let gradient: LEDGradient
        let brightness: Int
    }

    private struct AutomationAssetFolder: Identifiable {
        let automationId: UUID
        let automationName: String
        let playlistId: Int?
        let presetId: Int?
        let action: AutomationAction

        var id: UUID { automationId }
    }

    struct DevicePlaylistPreview {
        let gradientA: LEDGradient
        let brightnessA: Int
        let gradientB: LEDGradient
        let brightnessB: Int
        let durationSec: Double
    }

    private func devicePresetPreview(for preset: WLEDPreset) -> DevicePresetPreview {
        let preferredSegments = (preset.state?.seg ?? []).filter { ($0.col?.isEmpty == false) }
        let segments: [SegmentUpdate]
        if !preferredSegments.isEmpty {
            segments = preferredSegments
        } else if let segment = preset.segment, segment.col?.isEmpty == false {
            segments = [segment]
        } else {
            segments = []
        }

        let stops = gradientStopsFromSegments(segments)
        let gradient = LEDGradient(
            stops: stops.isEmpty ? fallbackGradientStops() : stops,
            interpolation: .linear
        )
        let brightness = max(0, min(255, preset.state?.bri ?? preset.segment?.bri ?? 255))
        return DevicePresetPreview(gradient: gradient, brightness: brightness)
    }

    private func devicePlaylistPreview(for playlist: WLEDPlaylist, presetById: [Int: WLEDPreset]) -> DevicePlaylistPreview {
        let firstPresetId = playlist.presets.first(where: { $0 > 0 })
        let lastPresetId = playlist.presets.last(where: { $0 > 0 }) ?? firstPresetId

        let first = firstPresetId.flatMap { presetById[$0] }.map(devicePresetPreview(for:))
        let last = lastPresetId.flatMap { presetById[$0] }.map(devicePresetPreview(for:))

        let fallback = DevicePresetPreview(
            gradient: LEDGradient(stops: fallbackGradientStops(), interpolation: .linear),
            brightness: 255
        )

        let start = first ?? fallback
        let end = last ?? first ?? fallback
        let totalDurationSec = Double(playlist.duration.reduce(0) { $0 + max(0, $1) }) / 10.0

        return DevicePlaylistPreview(
            gradientA: start.gradient,
            brightnessA: start.brightness,
            gradientB: end.gradient,
            brightnessB: end.brightness,
            durationSec: max(0, totalDurationSec)
        )
    }

    private func automationManagedPlaylistPreview(
        for folder: AutomationAssetFolder,
        playlist: WLEDPlaylist,
        presetById: [Int: WLEDPreset]
    ) -> DevicePlaylistPreview {
        if case .transition(let payload) = folder.action {
            return DevicePlaylistPreview(
                gradientA: payload.startGradient,
                brightnessA: payload.startBrightness,
                gradientB: payload.endGradient,
                brightnessB: payload.endBrightness,
                durationSec: max(0, payload.durationSeconds)
            )
        }
        return devicePlaylistPreview(for: playlist, presetById: presetById)
    }

    private func effectIdForDevicePreset(_ preset: WLEDPreset) -> Int? {
        let segments = preset.state?.seg ?? (preset.segment.map { [$0] } ?? [])
        return segments.compactMap(\.fx).first
    }

    private func gradientStopsFromSegments(_ segments: [SegmentUpdate]) -> [GradientStop] {
        guard !segments.isEmpty else { return [] }

        struct SegmentColorSpan {
            let index: Int
            let start: Int?
            let stop: Int?
            let hexColor: String
        }

        let spans = segments.enumerated().compactMap { index, segment -> SegmentColorSpan? in
            guard let hex = primaryHexColor(from: segment) else { return nil }
            return SegmentColorSpan(index: index, start: segment.start, stop: segment.stop, hexColor: hex)
        }
        guard !spans.isEmpty else { return [] }

        let useAbsoluteBounds = spans.allSatisfy { span in
            guard let start = span.start, let stop = span.stop else { return false }
            return stop > start
        }

        let ordered = useAbsoluteBounds ? spans.sorted { ($0.start ?? 0) < ($1.start ?? 0) } : spans.sorted { $0.index < $1.index }

        var stops: [GradientStop] = []
        if useAbsoluteBounds {
            let minStart = ordered.compactMap(\.start).min() ?? 0
            let maxStop = ordered.compactMap(\.stop).max() ?? (minStart + 1)
            let spanLength = max(1, maxStop - minStart)

            for span in ordered {
                guard let start = span.start, let stop = span.stop else { continue }
                let startPos = max(0.0, min(1.0, Double(start - minStart) / Double(spanLength)))
                let endPos = max(0.0, min(1.0, Double(stop - minStart) / Double(spanLength)))
                stops.append(GradientStop(position: startPos, hexColor: span.hexColor))
                stops.append(GradientStop(position: endPos, hexColor: span.hexColor))
            }
        } else {
            let count = max(1, ordered.count)
            for (idx, span) in ordered.enumerated() {
                let startPos = count == 1 ? 0.0 : Double(idx) / Double(count)
                let endPos = count == 1 ? 1.0 : Double(idx + 1) / Double(count)
                stops.append(GradientStop(position: startPos, hexColor: span.hexColor))
                stops.append(GradientStop(position: endPos, hexColor: span.hexColor))
            }
        }

        let sorted = stops.sorted { $0.position < $1.position }
        var normalized: [GradientStop] = []
        for stop in sorted {
            if let last = normalized.last, abs(last.position - stop.position) < 0.0005 {
                normalized[normalized.count - 1] = GradientStop(position: last.position, hexColor: stop.hexColor)
            } else {
                normalized.append(stop)
            }
        }

        guard let first = normalized.first else { return [] }
        if first.position > 0 {
            normalized.insert(GradientStop(position: 0, hexColor: first.hexColor), at: 0)
        }
        if let last = normalized.last, last.position < 1 {
            normalized.append(GradientStop(position: 1, hexColor: last.hexColor))
        }
        if normalized.count == 1, let single = normalized.first {
            normalized.append(GradientStop(position: 1, hexColor: single.hexColor))
        }

        return normalized
    }

    private func primaryHexColor(from segment: SegmentUpdate) -> String? {
        guard let rgb = segment.col?.first, rgb.count >= 3 else { return nil }
        let r = max(0, min(255, rgb[0]))
        let g = max(0, min(255, rgb[1]))
        let b = max(0, min(255, rgb[2]))
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func fallbackGradientStops() -> [GradientStop] {
        [
            GradientStop(position: 0.0, hexColor: "FFA000"),
            GradientStop(position: 1.0, hexColor: "FFA000")
        ]
    }
    
    private func emptyStateView(icon: String, message: String, hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(AppTypography.style(.title2))
                .foregroundColor(.white.opacity(0.58))
            Text(message)
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.74))
            Text(hint)
                .font(AppTypography.style(.caption2))
                .foregroundColor(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .presetGlassCard(cornerRadius: 18)
    }

    private func requestColorPresetDeletion(_ preset: ColorPreset, on device: WLEDDevice) async -> Bool {
        if let idsByDevice = preset.wledPresetIds, !idsByDevice.isEmpty {
            for (deviceId, presetId) in idsByDevice {
                if let target = viewModel.devices.first(where: { $0.id == deviceId }) {
                    enqueuePresetStoreDelete(type: .preset, deviceId: deviceId, ids: [presetId], target: target)
                } else {
                    DeviceCleanupManager.shared.enqueue(type: .preset, deviceId: deviceId, ids: [presetId])
                }
            }
            return true
        }
        if let legacyId = preset.wledPresetId {
            enqueuePresetStoreDelete(type: .preset, deviceId: device.id, ids: [legacyId], target: device)
        }
        return true
    }

    private func requestTransitionPresetDeletion(_ preset: TransitionPreset, on device: WLEDDevice) async -> Bool {
        guard let playlistId = preset.wledPlaylistId else { return true }
        enqueueCombinedPresetStoreDelete(
            deviceId: device.id,
            playlistIds: [playlistId],
            presetIds: preset.wledStepPresetIds ?? [],
            target: device
        )
        return true
    }

    private func requestEffectPresetDeletion(_ preset: WLEDEffectPreset, on device: WLEDDevice) async -> Bool {
        guard let presetId = preset.wledPresetId else { return true }
        enqueuePresetStoreDelete(type: .preset, deviceId: device.id, ids: [presetId], target: device)
        return true
    }

    private func enqueuePresetStoreDelete(
        type: PendingDeviceDelete.DeleteType,
        deviceId: String,
        ids: [Int],
        target: WLEDDevice?
    ) {
        DeviceCleanupManager.shared.enqueue(type: type, deviceId: deviceId, ids: ids)
        guard let target, target.isOnline else { return }
        Task {
            await DeviceCleanupManager.shared.processQueue(for: target.id)
        }
    }

    private func enqueueCombinedPresetStoreDelete(
        deviceId: String,
        playlistIds: [Int],
        presetIds: [Int],
        target: WLEDDevice?
    ) {
        DeviceCleanupManager.shared.enqueuePresetStoreDelete(
            deviceId: deviceId,
            playlistIds: playlistIds,
            presetIds: presetIds,
            verificationRequired: true
        )
        guard let target, target.isOnline else { return }
        Task {
            await DeviceCleanupManager.shared.processQueue(for: target.id)
        }
    }
}

// MARK: - Preset Row Views

private struct PresetDeleteButton: View {
    let isDeleting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isDeleting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.8)))
                        .controlSize(.mini)
                } else {
                    Image(systemName: "trash")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
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
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .accessibilityLabel(isDeleting ? "Deleting" : "Delete")
    }
}

private struct PresetIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    var activeColor: Color = .white
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(isActive ? activeColor : .white.opacity(isDisabled ? 0.34 : 0.76))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.16 : 0.10))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.20), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1.0)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ColorPresetRow: View {
    let preset: ColorPreset
    let isDeleting: Bool
    var isAlexaFavorite: Bool = false
    var canAddToAlexa: Bool = false
    var onAddToAlexa: (() -> Void)? = nil
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: Name + Edit icon
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()

                alexaFavoriteButton
                
                PresetDeleteButton(isDeleting: isDeleting) {
                    onDelete()
                }
                
                PresetIconButton(
                    systemName: "pencil",
                    accessibilityLabel: "Rename color preset",
                    action: onEdit
                )
            }
            
            // Simple Gradient Preview (no tabs/handles) with brightness indicator
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    gradient: Gradient(stops: gradientStops),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                
                // Brightness indicator inside preview (bottom right)
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.text(size: 10, weight: .regular, relativeTo: .caption2))
                    Text(brightnessString)
                        .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
                }
                .foregroundColor(brightnessLabelColor)
                .opacity(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .padding(4)
            }
        }
        .padding(14)
        .presetGlassCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: handleApply)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Color preset \(preset.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Apply"), handleApply)
    }
    
    private func handleApply() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onApply()
    }

    @ViewBuilder
    private var alexaFavoriteButton: some View {
        if let onAddToAlexa {
            Button(action: onAddToAlexa) {
                    Image(systemName: isAlexaFavorite ? "star.fill" : "star.badge.plus")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(isAlexaFavorite || canAddToAlexa ? 0.78 : 0.35))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isAlexaFavorite ? 0.16 : 0.10))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                )
                        )
            }
            .buttonStyle(.plain)
            .disabled(isAlexaFavorite || !canAddToAlexa)
            .accessibilityLabel(isAlexaFavorite ? "Already in Alexa Favorites" : "Add to Alexa Favorites")
        }
    }

    private var gradientStops: [Gradient.Stop] {
        preset.gradientStops
            .sorted { $0.position < $1.position }
            .map { Gradient.Stop(color: Color(hex: $0.hexColor), location: $0.position) }
    }
    
    private var brightnessString: String {
        let percent = Double(preset.brightness) / 255.0 * 100.0
        return "\(Int(round(percent)))%"
    }
    
    private var brightnessLabelColor: Color {
        guard let trailingStop = preset.gradientStops.max(by: { $0.position < $1.position }) else {
            return .white
        }
        let sanitizedHex = trailingStop.hexColor
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitizedHex.count >= 6 else {
            return .white
        }
        let rHex = String(sanitizedHex.prefix(2))
        let gHex = String(sanitizedHex.dropFirst(2).prefix(2))
        let bHex = String(sanitizedHex.dropFirst(4).prefix(2))
        let r = Double(Int(rHex, radix: 16) ?? 0) / 255.0
        let g = Double(Int(gHex, radix: 16) ?? 0) / 255.0
        let b = Double(Int(bHex, radix: 16) ?? 0) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance > 0.82 {
            return Color(.sRGB, white: 0.42)
        } else {
            return .white
        }
    }
}

struct AlexaFavoriteRow: View {
    let favorite: AlexaFavorite
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(favorite.slot)")
                .font(AppTypography.style(.caption, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white))

            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.displayName)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(favorite.sourceType.displayName)
                    Text("-")
                    Text(favorite.syncState.displayName)
                }
                .font(AppTypography.style(.caption2, weight: .medium))
                .foregroundColor(statusColor)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(favorite.displayName) from Alexa Favorites")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .presetGlassCard(cornerRadius: 16)
    }

    private var statusColor: Color {
        switch favorite.syncState {
        case .synced: return .green.opacity(0.9)
        case .pending: return .white.opacity(0.58)
        case .conflict: return .orange.opacity(0.95)
        case .failed: return .red.opacity(0.9)
        }
    }
}

struct TransitionPresetRow: View {
    let preset: TransitionPreset
    let isQueued: Bool
    let isDeleting: Bool
    var isAlexaFavorite: Bool = false
    var canAddToAlexa: Bool = false
    var onAddToAlexa: (() -> Void)? = nil
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row aligning with color preset styling
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(formattedDuration)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))

                if let status = statusBadgeText {
                    Text(status)
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                
                Spacer()

                alexaFavoriteButton
                
                PresetDeleteButton(isDeleting: isDeleting) {
                    onDelete()
                }
                
                PresetIconButton(
                    systemName: "pencil",
                    accessibilityLabel: "Rename transition preset",
                    action: onEdit
                )
            }
            
            // Gradient preview (two bars side by side)
            HStack(spacing: 4) {
                gradientPreview(for: preset.gradientA, brightness: preset.brightnessA)
                gradientPreview(for: preset.gradientB, brightness: preset.brightnessB)
            }
            .onTapGesture(perform: handleApply)
        }
        .padding(14)
        .presetGlassCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: handleApply)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transition preset \(preset.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Apply"), handleApply)
    }
    
    private func handleApply() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onApply()
    }

    @ViewBuilder
    private var alexaFavoriteButton: some View {
        if let onAddToAlexa {
            Button(action: onAddToAlexa) {
                    Image(systemName: isAlexaFavorite ? "star.fill" : "star.badge.plus")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(isAlexaFavorite || canAddToAlexa ? 0.78 : 0.35))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isAlexaFavorite ? 0.16 : 0.10))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                )
                        )
            }
            .buttonStyle(.plain)
            .disabled(isAlexaFavorite || !canAddToAlexa)
            .accessibilityLabel(isAlexaFavorite ? "Already in Alexa Favorites" : "Add to Alexa Favorites")
        }
    }
    
    @ViewBuilder
    private func gradientPreview(for gradient: LEDGradient, brightness: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(gradient: Gradient(stops: gradientStops(for: gradient)),
                            startPoint: .leading,
                            endPoint: .trailing)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(AppTypography.text(size: 10, weight: .regular, relativeTo: .caption2))
                Text(brightnessString(for: brightness))
                    .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
            }
            .foregroundColor(brightnessLabelColor(for: gradient))
            .opacity(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .padding(4)
        }
    }
    
    private func gradientStops(for gradient: LEDGradient) -> [Gradient.Stop] {
        gradient.stops
            .sorted { $0.position < $1.position }
            .map { stop in
                let location = max(0.0, min(1.0, stop.position))
                return Gradient.Stop(color: Color(hex: stop.hexColor), location: location)
            }
    }
    
    private func brightnessString(for brightness: Int) -> String {
        let clamped = max(0, min(255, brightness))
        return "\(Int(round(Double(clamped) / 255.0 * 100.0)))%"
    }
    
    private func brightnessLabelColor(for gradient: LEDGradient) -> Color {
        guard let trailingStop = gradient.stops.max(by: { $0.position < $1.position }) else {
            return .white
        }
        let sanitizedHex = trailingStop.hexColor
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitizedHex.count >= 6 else {
            return .white
        }
        let rHex = String(sanitizedHex.prefix(2))
        let gHex = String(sanitizedHex.dropFirst(2).prefix(2))
        let bHex = String(sanitizedHex.dropFirst(4).prefix(2))
        let r = Double(Int(rHex, radix: 16) ?? 0) / 255.0
        let g = Double(Int(gHex, radix: 16) ?? 0) / 255.0
        let b = Double(Int(bHex, radix: 16) ?? 0) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance > 0.82 {
            return Color(.sRGB, white: 0.42)
        } else {
            return .white
        }
    }
    
    private var formattedDuration: String {
        TransitionDurationPicker.summaryString(seconds: preset.durationSec)
    }

    private var statusBadgeText: String? {
        if isQueued { return "Queued" }
        switch preset.wledSyncState {
        case .synced:
            return nil
        case .pendingSync:
            return "Sync pending"
        case .needsMigration:
            return "Needs migration"
        case .syncFailed:
            return "Sync issue"
        }
    }
}

struct DevicePresetRecordRow: View {
    let preset: WLEDPreset
    let previewGradient: LEDGradient
    let previewBrightness: Int
    let isDeleting: Bool
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("Preset \(preset.id)")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                PresetDeleteButton(isDeleting: isDeleting, action: onDelete)

                PresetIconButton(
                    systemName: "pencil",
                    accessibilityLabel: "Rename device preset",
                    action: onEdit
                )
            }

            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    gradient: Gradient(stops: gradientStops(for: previewGradient)),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.text(size: 10, weight: .regular, relativeTo: .caption2))
                    Text(brightnessString)
                        .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
                }
                .foregroundColor(brightnessLabelColor(for: previewGradient))
                .opacity(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .padding(4)
            }
        }
        .padding(14)
        .presetGlassCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: handleApply)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Device preset \(preset.name)")
        .accessibilityAddTraits(.isButton)
    }

    private func handleApply() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onApply()
    }

    private func gradientStops(for gradient: LEDGradient) -> [Gradient.Stop] {
        gradient.stops
            .sorted { $0.position < $1.position }
            .map { stop in
                Gradient.Stop(color: Color(hex: stop.hexColor), location: max(0.0, min(1.0, stop.position)))
            }
    }

    private var brightnessString: String {
        "\(Int(round(Double(max(0, min(255, previewBrightness))) / 255.0 * 100.0)))%"
    }

    private func brightnessLabelColor(for gradient: LEDGradient) -> Color {
        guard let trailingStop = gradient.stops.max(by: { $0.position < $1.position }) else { return .white }
        return labelColor(forHex: trailingStop.hexColor)
    }

    private func labelColor(forHex hex: String) -> Color {
        let sanitizedHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitizedHex.count >= 6 else { return .white }
        let rHex = String(sanitizedHex.prefix(2))
        let gHex = String(sanitizedHex.dropFirst(2).prefix(2))
        let bHex = String(sanitizedHex.dropFirst(4).prefix(2))
        let r = Double(Int(rHex, radix: 16) ?? 0) / 255.0
        let g = Double(Int(gHex, radix: 16) ?? 0) / 255.0
        let b = Double(Int(bHex, radix: 16) ?? 0) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance > 0.82 {
            return Color(.sRGB, white: 0.42)
        }
        return .white
    }
}

struct DeviceEffectRecordRow: View {
    let preset: WLEDPreset
    let previewGradient: LEDGradient
    let previewBrightness: Int
    let effectId: Int?
    let isDeleting: Bool = false
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("FX \(effectId ?? 0)")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))

                Text("Preset \(preset.id)")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                PresetDeleteButton(isDeleting: isDeleting, action: onDelete)

                PresetIconButton(
                    systemName: "pencil",
                    accessibilityLabel: "Rename device effect preset",
                    action: onEdit
                )
            }

            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    gradient: Gradient(stops: gradientStops(for: previewGradient)),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.text(size: 10, weight: .regular, relativeTo: .caption2))
                    Text(brightnessString)
                        .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
                }
                .foregroundColor(brightnessLabelColor(for: previewGradient))
                .opacity(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .padding(4)
            }
        }
        .padding(14)
        .presetGlassCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: handleApply)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Device effect preset \(preset.name)")
        .accessibilityAddTraits(.isButton)
    }

    private func handleApply() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onApply()
    }

    private func gradientStops(for gradient: LEDGradient) -> [Gradient.Stop] {
        gradient.stops
            .sorted { $0.position < $1.position }
            .map { stop in
                Gradient.Stop(color: Color(hex: stop.hexColor), location: max(0.0, min(1.0, stop.position)))
            }
    }

    private var brightnessString: String {
        "\(Int(round(Double(max(0, min(255, previewBrightness))) / 255.0 * 100.0)))%"
    }

    private func brightnessLabelColor(for gradient: LEDGradient) -> Color {
        guard let trailingStop = gradient.stops.max(by: { $0.position < $1.position }) else { return .white }
        let sanitizedHex = trailingStop.hexColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitizedHex.count >= 6 else { return .white }
        let rHex = String(sanitizedHex.prefix(2))
        let gHex = String(sanitizedHex.dropFirst(2).prefix(2))
        let bHex = String(sanitizedHex.dropFirst(4).prefix(2))
        let r = Double(Int(rHex, radix: 16) ?? 0) / 255.0
        let g = Double(Int(gHex, radix: 16) ?? 0) / 255.0
        let b = Double(Int(bHex, radix: 16) ?? 0) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance > 0.82 {
            return Color(.sRGB, white: 0.42)
        }
        return .white
    }
}

struct DevicePlaylistRecordRow: View {
    let playlist: WLEDPlaylist
    let preview: PresetsListView.DevicePlaylistPreview
    let isDeleting: Bool
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(playlist.name)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(TransitionDurationPicker.summaryString(seconds: preview.durationSec))
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))

                Text("Playlist \(playlist.id)")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.55))

                Spacer()

                PresetDeleteButton(isDeleting: isDeleting, action: onDelete)

                PresetIconButton(
                    systemName: "pencil",
                    accessibilityLabel: "Rename playlist",
                    action: onEdit
                )
            }

            HStack(spacing: 4) {
                gradientPreview(for: preview.gradientA, brightness: preview.brightnessA)
                gradientPreview(for: preview.gradientB, brightness: preview.brightnessB)
            }
        }
        .padding(14)
        .presetGlassCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: handleRun)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Device playlist \(playlist.name)")
        .accessibilityAddTraits(.isButton)
    }

    private func handleRun() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onRun()
    }

    @ViewBuilder
    private func gradientPreview(for gradient: LEDGradient, brightness: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                gradient: Gradient(stops: gradientStops(for: gradient)),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(AppTypography.text(size: 10, weight: .regular, relativeTo: .caption2))
                Text(brightnessString(for: brightness))
                    .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
            }
            .foregroundColor(brightnessLabelColor(for: gradient))
            .opacity(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .padding(4)
        }
    }

    private func gradientStops(for gradient: LEDGradient) -> [Gradient.Stop] {
        gradient.stops
            .sorted { $0.position < $1.position }
            .map { stop in
                Gradient.Stop(color: Color(hex: stop.hexColor), location: max(0.0, min(1.0, stop.position)))
            }
    }

    private func brightnessString(for brightness: Int) -> String {
        "\(Int(round(Double(max(0, min(255, brightness))) / 255.0 * 100.0)))%"
    }

    private func brightnessLabelColor(for gradient: LEDGradient) -> Color {
        guard let trailingStop = gradient.stops.max(by: { $0.position < $1.position }) else { return .white }
        let sanitizedHex = trailingStop.hexColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitizedHex.count >= 6 else { return .white }
        let rHex = String(sanitizedHex.prefix(2))
        let gHex = String(sanitizedHex.dropFirst(2).prefix(2))
        let bHex = String(sanitizedHex.dropFirst(4).prefix(2))
        let r = Double(Int(rHex, radix: 16) ?? 0) / 255.0
        let g = Double(Int(gHex, radix: 16) ?? 0) / 255.0
        let b = Double(Int(bHex, radix: 16) ?? 0) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance > 0.82 {
            return Color(.sRGB, white: 0.42)
        }
        return .white
    }
}

struct EffectPresetRow: View {
    let preset: WLEDEffectPreset
    let isDeleting: Bool
    var isAlexaFavorite: Bool = false
    var canAddToAlexa: Bool = false
    var onAddToAlexa: (() -> Void)? = nil
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("FX \(preset.effectId)")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))
                
                if let palette = preset.paletteId {
                    Text("Pal \(palette)")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()

                alexaFavoriteButton
                
                PresetDeleteButton(isDeleting: isDeleting) {
                    onDelete()
                }
                
                PresetIconButton(
                    systemName: "pencil",
                    accessibilityLabel: "Rename animation preset",
                    action: onEdit
                )
            }
            
            // Gradient preview styled like transition presets
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: effectPreviewColors,
                                startPoint: .leading,
                                endPoint: .trailing)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.text(size: 10, weight: .regular, relativeTo: .caption2))
                    Text(brightnessString)
                        .font(AppTypography.text(size: 11, weight: .medium, relativeTo: .caption2))
                }
                .foregroundColor(brightnessLabelColor)
                .opacity(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .padding(4)
            }
            .onTapGesture(perform: handleApply)
            
            // Details row
            HStack(spacing: 12) {
                if let speed = preset.speed {
                    Label("Speed \(speed)", systemImage: "gauge")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if let intensity = preset.intensity {
                    Label("Intensity \(intensity)", systemImage: "wave.3.backward")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if preset.brightness < 255 {
                    Label("\(Int(round(Double(preset.brightness) / 255.0 * 100.0)))%", systemImage: "sun.max")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
        }
        .padding(14)
        .presetGlassCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: handleApply)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Effect preset \(preset.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Apply"), handleApply)
    }
    
    private func handleApply() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onApply()
    }

    @ViewBuilder
    private var alexaFavoriteButton: some View {
        if let onAddToAlexa {
            Button(action: onAddToAlexa) {
                    Image(systemName: isAlexaFavorite ? "star.fill" : "star.badge.plus")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(isAlexaFavorite || canAddToAlexa ? 0.78 : 0.35))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isAlexaFavorite ? 0.16 : 0.10))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                )
                        )
            }
            .buttonStyle(.plain)
            .disabled(isAlexaFavorite || !canAddToAlexa)
            .accessibilityLabel(isAlexaFavorite ? "Already in Alexa Favorites" : "Add to Alexa Favorites")
        }
    }
    
    private var effectPreviewColors: [Color] {
        if let stored = preset.gradientStops, !stored.isEmpty {
            return stored
                .sorted { $0.position < $1.position }
                .map { Color(hex: $0.hexColor) }
        }
        return effectPreviewHexColors.map { Color(hex: $0) }
    }
    
    private var effectPreviewHexColors: [String] {
        if let paletteId = preset.paletteId {
            return paletteGradientHex(for: paletteId)
        }
        switch preset.effectId % 4 {
        case 0:
            return ["#4F38FF", "#FF7CC3"]
        case 1:
            return ["#1FB1FF", "#66FFDA"]
        case 2:
            return ["#FF8A4C", "#FFD66B"]
        default:
            return ["#AC72FF", "#72E1FF"]
        }
    }
    
    private func paletteGradientHex(for paletteId: Int) -> [String] {
        switch paletteId % 6 {
        case 0:
            return ["#FF9A9E", "#FAD0C4"]
        case 1:
            return ["#A18CD1", "#FBC2EB"]
        case 2:
            return ["#84FAB0", "#8FD3F4"]
        case 3:
            return ["#F6D365", "#FDA085"]
        case 4:
            return ["#89F7FE", "#66A6FF"]
        default:
            return ["#FDEB71", "#F8D800"]
        }
    }
    
    private var brightnessString: String {
        let percent = Double(preset.brightness) / 255.0 * 100.0
        return "\(Int(round(percent)))%"
    }
    
    private var brightnessLabelColor: Color {
        if let stored = preset.gradientStops?.sorted(by: { $0.position < $1.position }).last?.hexColor {
            return labelColor(forHex: stored)
        }
        guard let hex = effectPreviewHexColors.last else { return .white }
        return labelColor(forHex: hex)
    }
    
    private func labelColor(forHex hex: String) -> Color {
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitized.count >= 6 else { return .white }
        let rHex = String(sanitized.prefix(2))
        let gHex = String(sanitized.dropFirst(2).prefix(2))
        let bHex = String(sanitized.dropFirst(4).prefix(2))
        let r = Double(Int(rHex, radix: 16) ?? 0) / 255.0
        let g = Double(Int(gHex, radix: 16) ?? 0) / 255.0
        let b = Double(Int(bHex, radix: 16) ?? 0) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance > 0.82 {
            return Color(.sRGB, white: 0.42)
        } else {
            return .white
        }
    }
}

// MARK: - Playlist Editor (Advanced)

private struct PlaylistStepDraft: Identifiable, Equatable {
    let id: UUID
    var presetId: Int
    var durationDs: Int
    var transitionDs: Int

    init(id: UUID = UUID(), presetId: Int, durationDs: Int, transitionDs: Int) {
        self.id = id
        self.presetId = presetId
        self.durationDs = durationDs
        self.transitionDs = transitionDs
    }
}

private struct PlaylistEditorDraft: Equatable {
    var name: String
    var steps: [PlaylistStepDraft]
    var repeatCount: Int
    var shuffle: Int
    var endPresetId: Int

    static let defaultDraft = PlaylistEditorDraft(
        name: "New Playlist",
        steps: [PlaylistStepDraft(presetId: 1, durationDs: 100, transitionDs: 7)],
        repeatCount: 1,
        shuffle: 0,
        endPresetId: 0
    )

    init(
        name: String,
        steps: [PlaylistStepDraft],
        repeatCount: Int,
        shuffle: Int,
        endPresetId: Int
    ) {
        self.name = name
        self.steps = steps
        self.repeatCount = repeatCount
        self.shuffle = shuffle
        self.endPresetId = endPresetId
    }

    init(playlist: WLEDPlaylist) {
        let stepCount = max(playlist.presets.count, playlist.duration.count, playlist.transition.count)
        var builtSteps: [PlaylistStepDraft] = []
        for index in 0..<max(1, stepCount) {
            let presetId = index < playlist.presets.count ? playlist.presets[index] : (playlist.presets.last ?? 1)
            let duration = index < playlist.duration.count ? playlist.duration[index] : (playlist.duration.last ?? 100)
            let transition = index < playlist.transition.count ? playlist.transition[index] : (playlist.transition.last ?? 7)
            builtSteps.append(
                PlaylistStepDraft(
                    presetId: max(1, min(250, presetId)),
                    durationDs: max(0, min(65530, duration)),
                    transitionDs: max(0, min(65530, transition))
                )
            )
        }
        self.init(
            name: playlist.name,
            steps: builtSteps,
            repeatCount: min(max(playlist.repeat ?? 1, 0), 127),
            shuffle: playlist.shuffle == 1 ? 1 : 0,
            endPresetId: playlist.endPresetId ?? 0
        )
    }

    var isManualAdvance: Bool {
        !steps.isEmpty && steps.allSatisfy { $0.durationDs == 0 }
    }

    mutating func setManualAdvance(_ enabled: Bool) {
        guard !steps.isEmpty else { return }
        if enabled {
            for index in steps.indices {
                steps[index].durationDs = 0
            }
        } else {
            for index in steps.indices where steps[index].durationDs == 0 {
                steps[index].durationDs = 100
            }
        }
    }

    func asSaveRequest(withId id: Int) -> WLEDPlaylistSaveRequest {
        WLEDPlaylistSaveRequest(
            id: id,
            name: name,
            ps: steps.map(\.presetId),
            dur: steps.map(\.durationDs),
            transition: steps.map(\.transitionDs),
            repeat: repeatCount,
            endPresetId: endPresetId,
            shuffle: shuffle
        )
    }
}

private struct PlaylistEditorSheet: View {
    @Binding var draft: PlaylistEditorDraft
    let originalId: Int?
    let device: WLEDDevice
    let availablePresetIds: [Int]
    let onCancel: () -> Void
    let onSave: (PlaylistEditorDraft) -> Void
    let onTest: (PlaylistEditorDraft) -> Void
    let onRun: (Int?) -> Void
    let onStop: () -> Void

    private var endPresetOptions: [Int] {
        let presetIds = availablePresetIds.filter { (1...250).contains($0) }.sorted()
        return [0, 255] + presetIds
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Device: \(device.name)")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Playlist Name")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextField("Playlist name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle(
                        "Shuffle",
                        isOn: Binding(
                            get: { draft.shuffle == 1 },
                            set: { draft.shuffle = $0 ? 1 : 0 }
                        )
                    )

                    Toggle(
                        "Manual advance (duration = 0 for each step)",
                        isOn: Binding(
                            get: { draft.isManualAdvance },
                            set: { draft.setManualAdvance($0) }
                        )
                    )

                    Stepper("Repeat count: \(draft.repeatCount) (0 = infinite)", value: $draft.repeatCount, in: 0...127)

                    Picker("End preset", selection: $draft.endPresetId) {
                        Text("None").tag(0)
                        Text("Restore previous preset").tag(255)
                        ForEach(endPresetOptions.filter { $0 != 0 && $0 != 255 }, id: \.self) { presetId in
                            Text("Preset \(presetId)").tag(presetId)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Steps")
                            .font(AppTypography.style(.headline))
                        Spacer()
                        Button {
                            let seed = draft.steps.last ?? PlaylistStepDraft(presetId: 1, durationDs: 100, transitionDs: 7)
                            draft.steps.append(
                                PlaylistStepDraft(
                                    presetId: seed.presetId,
                                    durationDs: seed.durationDs,
                                    transitionDs: seed.transitionDs
                                )
                            )
                        } label: {
                            Label("Add Step", systemImage: "plus")
                                .font(AppTypography.style(.caption, weight: .semibold))
                        }
                    }

                    ForEach(Array(draft.steps.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Step \(index + 1)")
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
                                Spacer()
                                if draft.steps.count > 1 {
                                    Button {
                                        draft.steps.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button {
                                    guard index > 0 else { return }
                                    draft.steps.swapAt(index, index - 1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                Button {
                                    guard index < draft.steps.count - 1 else { return }
                                    draft.steps.swapAt(index, index + 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.plain)
                                .disabled(index == draft.steps.count - 1)
                            }

                            Stepper(
                                "Preset ID: \(draft.steps[index].presetId)",
                                value: $draft.steps[index].presetId,
                                in: 1...250
                            )
                            Stepper(
                                "Duration: \(String(format: "%.1f", Double(draft.steps[index].durationDs) / 10.0))s",
                                value: $draft.steps[index].durationDs,
                                in: 0...65530,
                                step: 1
                            )
                            Stepper(
                                "Transition: \(String(format: "%.1f", Double(draft.steps[index].transitionDs) / 10.0))s",
                                value: $draft.steps[index].transitionDs,
                                in: 0...65530,
                                step: 1
                            )
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
                .padding(16)
            }
            .navigationTitle(originalId == nil ? "New Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .disabled(draft.steps.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button("Test") {
                        onTest(draft)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Run") {
                        onRun(originalId)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(originalId == nil)
                    Button("Stop") {
                        onStop()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Edit Preset Name Popup

struct EditPresetNamePopup: View {
    let currentName: String
    @Binding var editedName: String
    @Binding var isPresented: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Preset Name")
                .font(AppTypography.style(.headline, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset Name")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                TextField("Enter preset name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(AppTypography.style(.body))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if !editedName.isEmpty && editedName != currentName {
                            onSave(editedName)
                        }
                    }
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    onCancel()
                }) {
                    Text("Cancel")
                        .font(AppTypography.style(.subheadline, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(10)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if !editedName.isEmpty && editedName != currentName {
                        onSave(editedName)
                    }
                }) {
                    Text("Save")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.25))
                        .cornerRadius(10)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(editedName.isEmpty || editedName == currentName ? 0.4 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(editedName.isEmpty || editedName == currentName)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
        .onAppear {
            editedName = currentName
        }
    }
}

// MARK: - Rename Helpers

enum PresetRenameContext {
    case color(ColorPreset)
    case transition(TransitionPreset)
    case effect(WLEDEffectPreset)
    case devicePreset(id: Int, name: String, device: WLEDDevice)
    case devicePlaylist(id: Int, name: String, device: WLEDDevice)
    
    var currentName: String {
        switch self {
        case .color(let preset):
            return preset.name
        case .transition(let preset):
            return preset.name
        case .effect(let preset):
            return preset.name
        case .devicePreset(_, let name, _):
            return name
        case .devicePlaylist(_, let name, _):
            return name
        }
    }
}
