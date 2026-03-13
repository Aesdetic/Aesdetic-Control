import SwiftUI

struct PresetsListView: View {
    @ObservedObject var store = PresetsStore.shared
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice
    let onRequestRename: (PresetRenameContext) -> Void
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @State private var isPlaylistEditorPresented = false
    @State private var playlistEditorOriginalId: Int?
    @State private var playlistEditorDraft = PlaylistEditorDraft.defaultDraft
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Color Presets Section
                colorPresetsSection
                
                // Effect Presets Section
                effectPresetsSection
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .navigationTitle("Presets")
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
        }
    }
    
    // MARK: - Color Presets Section
    
    private var colorPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Color Presets", systemImage: "paintbrush.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            let colorPresets = store.colorPresets
            if colorPresets.isEmpty {
                emptyStateView(
                    icon: "paintbrush",
                    message: "No color presets",
                    hint: "Tap + to save current gradient"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(colorPresets) { preset in
                        ColorPresetRow(preset: preset, onApply: {
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
                        Task { await requestColorPresetDeletion(preset, on: device) }
                        store.removeColorPreset(preset.id)
                    })
                    }
                }
            }
        }
    }
    
    // MARK: - Effect Presets Section
    
    private var effectPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Effect Presets", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            // Transitions Subsection
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Transitions")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                
                let transitionPresets = store.transitionPresets(for: device.id)
                if transitionPresets.isEmpty {
                    emptyStateView(
                        icon: "arrow.triangle.2.circlepath",
                        message: "No transition presets",
                        hint: "Tap + to save current transition"
                    )
                } else {
                    VStack(spacing: 8) {
                        let queuedPresetId = viewModel.queuedTransitionPresetApplyByDeviceId[device.id]
                        ForEach(transitionPresets) { preset in
                            TransitionPresetRow(
                                preset: preset,
                                isQueued: queuedPresetId == preset.id,
                                onApply: {
                                Task {
                                    _ = await viewModel.applyTransitionPreset(preset, to: device)
                                }
                            }, onEdit: {
                                onRequestRename(.transition(preset))
                            }, onDelete: {
                                Task { await requestTransitionPresetDeletion(preset, on: device) }
                                store.removeTransitionPreset(preset.id)
                            })
                        }
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Effects Subsection
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Animations")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                
                let effectPresets = store.effectPresets(for: device.id)
                if effectPresets.isEmpty {
                    emptyStateView(
                        icon: "sparkles",
                        message: "No effect presets",
                        hint: "Tap + to save current effect"
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(effectPresets) { preset in
                            EffectPresetRow(preset: preset, onApply: {
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
                            Task { await requestEffectPresetDeletion(preset, on: device) }
                            store.removeEffectPreset(preset.id)
                        })
                        }
                    }
                }
            }
        }
    }

    // MARK: - Advanced Playlists Section (WLED)

    private var playlistDiscoverabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Device Playlists", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            Text("Device playlist controls are available in Advanced mode.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
            Text("Enable Advanced mode to view, run, and delete playlists synced from WLED.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))

            Button {
                advancedUIEnabled = true
                Task { await viewModel.loadPlaylists(for: device, force: false) }
            } label: {
                Label("Enable Advanced Mode", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var advancedPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Device Playlists", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("New") {
                    playlistEditorOriginalId = nil
                    playlistEditorDraft = PlaylistEditorDraft.defaultDraft
                    isPlaylistEditorPresented = true
                }
                .font(.caption.weight(.semibold))
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
                .font(.caption.weight(.semibold))
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
                .font(.caption.weight(.semibold))
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
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Text("Steps: \(playlist.presets.count)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                Text(playlistSummary(playlist))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.55))
                                if viewModel.isPlaylistRenamePending(playlist.id, for: device) {
                                    Text("Rename pending sync")
                                        .font(.caption2.weight(.semibold))
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
                            .font(.caption.weight(.semibold))
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
                            .font(.caption.weight(.semibold))
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
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.18))
                            )

                            Button("Delete") {
                                Task { await viewModel.deletePlaylist(playlist, for: device) }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.55))
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
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
    
    private func emptyStateView(icon: String, message: String, hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white.opacity(0.4))
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Text(hint)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func requestColorPresetDeletion(_ preset: ColorPreset, on device: WLEDDevice) async {
        if let idsByDevice = preset.wledPresetIds, !idsByDevice.isEmpty {
            for (deviceId, presetId) in idsByDevice {
                if let target = viewModel.devices.first(where: { $0.id == deviceId }) {
                    await DeviceCleanupManager.shared.requestDelete(type: .preset, device: target, ids: [presetId])
                } else {
                    DeviceCleanupManager.shared.enqueue(type: .preset, deviceId: deviceId, ids: [presetId])
                }
            }
            return
        }
        if let legacyId = preset.wledPresetId {
            await DeviceCleanupManager.shared.requestDelete(type: .preset, device: device, ids: [legacyId])
        }
    }

    private func requestTransitionPresetDeletion(_ preset: TransitionPreset, on device: WLEDDevice) async {
        guard let playlistId = preset.wledPlaylistId else { return }
        await DeviceCleanupManager.shared.requestDelete(type: .playlist, device: device, ids: [playlistId])
        if let stepIds = preset.wledStepPresetIds, !stepIds.isEmpty {
            await DeviceCleanupManager.shared.requestDelete(type: .preset, device: device, ids: stepIds)
        }
    }

    private func requestEffectPresetDeletion(_ preset: WLEDEffectPreset, on device: WLEDDevice) async {
        guard let presetId = preset.wledPresetId else { return }
        await DeviceCleanupManager.shared.requestDelete(type: .preset, device: device, ids: [presetId])
    }
}

// MARK: - Preset Row Views

struct ColorPresetRow: View {
    let preset: ColorPreset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: Name + Edit icon
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    onEdit()
                }) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
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
                        .font(.system(size: 10))
                    Text(brightnessString)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(brightnessLabelColor)
                .opacity(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .padding(4)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

struct TransitionPresetRow: View {
    let preset: TransitionPreset
    let isQueued: Bool
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row aligning with color preset styling
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                if let status = statusBadgeText {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                
                Spacer()
                
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    onEdit()
                }) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            // Gradient preview (two bars side by side)
            HStack(spacing: 4) {
                gradientPreview(for: preset.gradientA, brightness: preset.brightnessA)
                gradientPreview(for: preset.gradientB, brightness: preset.brightnessB)
            }
            .onTapGesture(perform: handleApply)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .font(.system(size: 10))
                Text(brightnessString(for: brightness))
                    .font(.system(size: 11, weight: .medium))
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

struct EffectPresetRow: View {
    let preset: WLEDEffectPreset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("FX \(preset.effectId)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
                if let palette = preset.paletteId {
                    Text("Pal \(palette)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    onEdit()
                }) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
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
                        .font(.system(size: 10))
                    Text(brightnessString)
                        .font(.system(size: 11, weight: .medium))
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
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if let intensity = preset.intensity {
                    Label("Intensity \(intensity)", systemImage: "wave.3.backward")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if preset.brightness < 255 {
                    Label("\(Int(round(Double(preset.brightness) / 255.0 * 100.0)))%", systemImage: "sun.max")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Playlist Name")
                            .font(.caption.weight(.semibold))
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
                            .font(.headline)
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
                                .font(.caption.weight(.semibold))
                        }
                    }

                    ForEach(Array(draft.steps.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Step \(index + 1)")
                                    .font(.subheadline.weight(.semibold))
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
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset Name")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                
                TextField("Enter preset name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(.body)
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
                        .font(.subheadline.weight(.medium))
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
                        .font(.subheadline.weight(.semibold))
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
    
    var currentName: String {
        switch self {
        case .color(let preset):
            return preset.name
        case .transition(let preset):
            return preset.name
        case .effect(let preset):
            return preset.name
        }
    }
}
