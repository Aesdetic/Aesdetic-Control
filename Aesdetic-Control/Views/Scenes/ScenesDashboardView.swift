import SwiftUI

struct ScenesDashboardView: View {
    @ObservedObject private var deviceViewModel = DeviceControlViewModel.shared
    @StateObject private var scenesStore = SceneGroupStore.shared
    @State private var showingEditor = false
    @State private var editingScene: SceneGroup? = nil
    @State private var undoContext: SceneUndoContext? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    scenesSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 80)
            }

            if let undoContext {
                SceneUndoBanner(
                    title: "Scene applied",
                    subtitle: undoContext.sceneName,
                    actionTitle: "Undo",
                    onAction: { undoLastScene(undoContext) },
                    onDismiss: { self.undoContext = nil }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingEditor) {
            SceneEditorSheet(existingScene: editingScene)
        }
        .background(Color.clear)
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scenes")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("Run multiple devices together with one tap.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
            }
            Spacer()
            Button(action: { beginCreateScene() }) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.black)
                    .padding()
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Scenes")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { beginCreateScene() }) {
                    Label("Create", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if scenesStore.scenes.isEmpty {
                EmptyScenesCard(onCreate: { beginCreateScene() })
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sortedScenes) { scene in
                        SceneGroupCard(scene: scene, onRun: { runScene(scene) })
                            .contextMenu {
                                Button("Edit") {
                                    beginEditScene(scene)
                                }
                                Button("Duplicate") {
                                    duplicateScene(scene)
                                }
                                Button(role: .destructive) {
                                    scenesStore.remove(scene.id)
                                } label: {
                                    Text("Delete")
                                }
                            }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var sortedScenes: [SceneGroup] {
        scenesStore.scenes.sorted { $0.createdAt > $1.createdAt }
    }

    private func beginCreateScene() {
        editingScene = nil
        showingEditor = true
    }

    private func beginEditScene(_ scene: SceneGroup) {
        editingScene = scene
        showingEditor = true
    }

    private func duplicateScene(_ scene: SceneGroup) {
        let copy = SceneGroup(
            name: "\(scene.name) Copy",
            createdAt: Date(),
            deviceScenes: scene.deviceScenes
        )
        scenesStore.add(copy)
    }

    private func runScene(_ scene: SceneGroup) {
        let devicesById = Dictionary(uniqueKeysWithValues: deviceViewModel.devices.map { ($0.id, $0) })
        let previousScenes: [Scene] = scene.deviceScenes.compactMap { deviceScene in
            guard let device = devicesById[deviceScene.deviceId] else { return nil }
            return deviceViewModel.captureSceneSnapshot(for: device, name: deviceScene.name)
        }
        let context = SceneUndoContext(sceneName: scene.name, scenes: previousScenes)
        undoContext = context
        scheduleUndoDismiss(for: context)

        Task {
            await withTaskGroup(of: Void.self) { group in
                for scene in scene.deviceScenes {
                    guard let device = devicesById[scene.deviceId] else { continue }
                    group.addTask {
                        await deviceViewModel.applyScene(scene, to: device)
                    }
                }
            }
        }
    }

    private func undoLastScene(_ context: SceneUndoContext) {
        let devicesById = Dictionary(uniqueKeysWithValues: deviceViewModel.devices.map { ($0.id, $0) })
        undoContext = nil

        Task {
            await withTaskGroup(of: Void.self) { group in
                for scene in context.scenes {
                    guard let device = devicesById[scene.deviceId] else { continue }
                    group.addTask {
                        await deviceViewModel.applyScene(scene, to: device)
                    }
                }
            }
        }
    }

    private func scheduleUndoDismiss(for context: SceneUndoContext) {
        let contextId = context.id
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if undoContext?.id == contextId {
                    undoContext = nil
                }
            }
        }
    }
}

private struct SceneUndoContext: Identifiable {
    let id = UUID()
    let sceneName: String
    let scenes: [Scene]
}

private struct SceneGroupCard: View {
    let scene: SceneGroup
    let onRun: () -> Void

    var body: some View {
        Button(action: onRun) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(scene.name)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyScenesCard: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No scenes yet")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Text("Save the current settings across devices and launch them with a single tap.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Button(action: onCreate) {
                Label("Create Scene", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct SceneUndoBanner: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button(actionTitle) {
                onAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white)
            .foregroundColor(.black)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

struct SceneEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var deviceViewModel = DeviceControlViewModel.shared
    @ObservedObject private var scenesStore = SceneGroupStore.shared

    let existingScene: SceneGroup?

    @State private var name: String
    @State private var selectedDeviceIds: Set<String>
    @State private var applyFromDeviceId: String? = nil
    @State private var editingDevice: WLEDDevice? = nil

    init(existingScene: SceneGroup? = nil) {
        self.existingScene = existingScene
        _name = State(initialValue: existingScene?.name ?? "")
        _selectedDeviceIds = State(initialValue: Set(existingScene?.deviceScenes.map { $0.deviceId } ?? []))
        _applyFromDeviceId = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        sceneNameSection
                        quickPickSection
                        applyFromSection
                        devicePickerSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
            }
            .navigationTitle(existingScene == nil ? "New Scene" : "Edit Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveScene()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .sheet(item: $editingDevice) { device in
            DeviceDetailView(device: device, viewModel: deviceViewModel)
                .preferredColorScheme(.light)
        }
    }

    private var sceneNameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scene name")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            TextField("Evening Chill", text: $name)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(14)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)
            Text("We will capture the current settings from each device.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(18)
        .background(cardBackground)
    }

    private var quickPickSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPicks, id: \.self) { label in
                    Button(label) {
                        name = label
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    private var applyAllSection: some View {
        EmptyView()
    }

    private var applyFromSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use settings from")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Menu {
                Button("Use each device's current settings") {
                    applyFromDeviceId = nil
                }
                ForEach(deviceViewModel.devices.filter { selectedDeviceIds.contains($0.id) }) { device in
                    Button(device.name) {
                        applyFromDeviceId = device.id
                    }
                }
            } label: {
                HStack {
                    Text(applyFromLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(Capsule())
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var devicePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(selectedDeviceIds.count) selected")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
            }
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(deviceViewModel.devices) { device in
                    SceneDeviceCard(
                        device: device,
                        isSelected: selectedDeviceIds.contains(device.id),
                        onToggle: { toggleDevice(device) },
                        onConfigure: {
                            editingDevice = device
                        }
                    )
                }
            }
            Text("Tap a device to tweak its settings before saving.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(18)
        .background(cardBackground)
        .onAppear(perform: seedDefaultsIfNeeded)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDeviceIds.isEmpty
    }

    private func seedDefaultsIfNeeded() {
        if selectedDeviceIds.isEmpty {
            selectedDeviceIds = Set(deviceViewModel.devices.map { $0.id })
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = "Scene \(nextSceneNumber())"
        }
    }

    private func toggleDevice(_ device: WLEDDevice) {
        if selectedDeviceIds.contains(device.id) {
            selectedDeviceIds.remove(device.id)
        } else {
            selectedDeviceIds.insert(device.id)
        }
    }

    private func saveScene() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedDevices = deviceViewModel.devices.filter { selectedDeviceIds.contains($0.id) }
        guard !trimmedName.isEmpty, !selectedDevices.isEmpty else { return }

        let baseScenes = selectedDevices.map { deviceViewModel.captureSceneSnapshot(for: $0, name: trimmedName) }
        let scenes: [Scene]
        if let sourceId = applyFromDeviceId,
           let primaryScene = baseScenes.first(where: { $0.deviceId == sourceId }) {
            scenes = selectedDevices.map { device in
                Scene(
                    name: trimmedName,
                    deviceId: device.id,
                    brightness: primaryScene.brightness,
                    primaryStops: primaryScene.primaryStops,
                    transitionEnabled: primaryScene.transitionEnabled,
                    secondaryStops: primaryScene.secondaryStops,
                    durationSec: primaryScene.durationSec,
                    aBrightness: primaryScene.aBrightness,
                    bBrightness: primaryScene.bBrightness,
                    effectsEnabled: primaryScene.effectsEnabled,
                    effectId: primaryScene.effectId,
                    paletteId: primaryScene.paletteId,
                    speed: primaryScene.speed,
                    intensity: primaryScene.intensity,
                    presetId: primaryScene.presetId,
                    playlistId: primaryScene.playlistId
                )
            }
        } else {
            scenes = baseScenes
        }

        let sceneGroup = SceneGroup(
            id: existingScene?.id ?? UUID(),
            name: trimmedName,
            createdAt: existingScene?.createdAt ?? Date(),
            deviceScenes: scenes
        )
        scenesStore.upsert(sceneGroup)
        dismiss()
    }

    private var quickPicks: [String] {
        ["Work", "Focus", "Cozy", "Romantic"]
    }

    private func nextSceneNumber() -> Int {
        let prefix = "Scene "
        let numbers = scenesStore.scenes.compactMap { scene -> Int? in
            guard scene.name.hasPrefix(prefix) else { return nil }
            let suffix = scene.name.dropFirst(prefix.count)
            return Int(suffix.trimmingCharacters(in: .whitespaces))
        }
        let maxValue = numbers.max() ?? 0
        return maxValue + 1
    }

    private var applyFromLabel: String {
        if let sourceId = applyFromDeviceId,
           let device = deviceViewModel.devices.first(where: { $0.id == sourceId }) {
            return device.name
        }
        return "Each device"
    }
}

private struct SceneDeviceCard: View {
    let device: WLEDDevice
    let isSelected: Bool
    let onToggle: () -> Void
    let onConfigure: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MiniDeviceCard(device: device, onTap: onConfigure, showPowerToggle: true)
                .opacity(isSelected ? 1.0 : 0.45)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.8) : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )

            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .padding(6)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .padding(.trailing, 8)
        }
    }
}

struct ScenesDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        ScenesDashboardView()
    }
}
