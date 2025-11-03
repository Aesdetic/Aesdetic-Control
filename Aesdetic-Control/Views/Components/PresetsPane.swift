import SwiftUI
import Combine

struct PresetsPane: View {
    @EnvironmentObject private var viewModel: DeviceControlViewModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let device: WLEDDevice
    
    @State private var selectedPresetId: Int?
    @State private var showSaveSheet: Bool = false
    @State private var presetName: String = ""
    @State private var markQuickLoad: Bool = false
    @State private var isApplying: Bool = false
    @State private var isSaving: Bool = false
    @State private var shouldSkipNextApply: Bool = false
    @State private var pendingSavedPresetId: Int?
    @State private var showSaveConfirmation: Bool = false
    
    private var presets: [WLEDPreset] {
        viewModel.presets(for: device)
    }
    
    private var isLoading: Bool {
        viewModel.isLoadingPresets(for: device)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isLoading {
                HStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading presets…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if presets.isEmpty {
                emptyState
            } else {
                presetsPicker
                actions
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
        .task {
            if presets.isEmpty {
                await viewModel.loadPresets(for: device)
                let firstId = viewModel.presets(for: device).first?.id
                if selectedPresetId != firstId {
                    shouldSkipNextApply = true
                    selectedPresetId = firstId
                }
            } else if selectedPresetId == nil {
                shouldSkipNextApply = true
                selectedPresetId = presets.first?.id
            }
        }
        .onReceive(viewModel.$presetsCache) { cache in
            let updated = cache[device.id] ?? []
            if updated.isEmpty {
                shouldSkipNextApply = true
                selectedPresetId = nil
                return
            }
            if let pendingId = pendingSavedPresetId, updated.contains(where: { $0.id == pendingId }) {
                shouldSkipNextApply = true
                selectedPresetId = pendingId
                pendingSavedPresetId = nil
                return
            }
            if let selectedId = selectedPresetId, updated.contains(where: { $0.id == selectedId }) {
                return
            }
            shouldSkipNextApply = true
            selectedPresetId = updated.first?.id
        }
        .onChange(of: selectedPresetId) { oldValue, newValue in
            guard let presetId = newValue else { return }
            if shouldSkipNextApply {
                shouldSkipNextApply = false
                return
            }
            applyPreset(withId: presetId)
        }
        .sheet(isPresented: $showSaveSheet, onDismiss: { resetSaveForm() }) {
            savePresetSheet
        }
    }
    
    private var header: some View {
        HStack {
            Label("Presets", systemImage: "square.stack")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button(action: {
                Task { await viewModel.refreshPresets(for: device) }
            }) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("Refresh presets")
            .accessibilityHint("Fetches the latest presets from the device.")
        }
    }
    
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No presets found on this device.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Button("Refresh") {
                Task { await viewModel.refreshPresets(for: device) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
        }
    }
    
    private var presetsPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preset")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Picker("Preset", selection: Binding(
                get: { selectedPresetId ?? presets.first?.id ?? 0 },
                set: { selectedPresetId = $0 }
            )) {
                ForEach(presets) { preset in
                    Text(preset.name)
                        .tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .accessibilityHint("Choose which preset to apply.")
        }
    }
    
    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                applySelectedPreset()
            } label: {
                if isApplying {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Apply Preset")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryActionTint)
            .disabled(isApplying || selectedPresetId == nil)
            .accessibilityHint("Applies the selected preset to the device.")
            
            Button {
                prepareSaveForm()
                showSaveSheet = true
            } label: {
                Text("Save Current State…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(secondaryActionTint)
            .disabled(isSaving)
            .accessibilityHint("Saves the device's current settings as a new preset.")
        }
    }
    
    private var savePresetSheet: some View {
        NavigationStack {
            Form {
                Section("Preset Details") {
                    TextField("Name", text: $presetName)
                        .textInputAutocapitalization(.words)
                    Toggle("Quick Load", isOn: $markQuickLoad)
                        .accessibilityHint("Adds this preset to the device's quick-load slots.")
                }
                Section {
                    Button {
                        attemptSavePreset()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Preset")
                        }
                    }
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .accessibilityHint("Stores the preset with the provided name.")
                }
            }
            .navigationTitle("Save Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSaveSheet = false
                    }
                }
            }
        }
        .alert("Save Preset?", isPresented: $showSaveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                executeSavePreset()
            }
        } message: {
            Text("Save “\(presetName.trimmingCharacters(in: .whitespacesAndNewlines))” to this WLED device?" + (markQuickLoad ? " It will be available for quick access." : ""))
        }
    }
    
    private func applySelectedPreset() {
        guard let presetId = selectedPresetId else { return }
        applyPreset(withId: presetId)
    }
    
    private func applyPreset(withId presetId: Int) {
        guard let preset = presets.first(where: { $0.id == presetId }) else { return }
        if isApplying { return }
        isApplying = true
        Task {
            await viewModel.applyPreset(preset, to: device)
            await MainActor.run {
                isApplying = false
            }
        }
    }
    
    private func prepareSaveForm() {
        presetName = "Preset \(viewModel.nextPresetId(for: device))"
        markQuickLoad = false
        pendingSavedPresetId = nil
    }
    
    private func resetSaveForm() {
        presetName = ""
        markQuickLoad = false
        isSaving = false
        pendingSavedPresetId = nil
        showSaveConfirmation = false
    }
    
    private func attemptSavePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isSaving else { return }
        showSaveConfirmation = true
    }
    
    private func executeSavePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSaving = true
        let targetId = pendingSavedPresetId ?? viewModel.nextPresetId(for: device)
        pendingSavedPresetId = targetId
        Task {
            await viewModel.savePreset(name: name, quickLoad: markQuickLoad, for: device, presetId: targetId)
            await MainActor.run {
                isSaving = false
                showSaveSheet = false
            }
        }
    }
    
    private var backgroundFill: Color {
        Color.white.opacity(adjustedOpacity(0.06))
    }
    
    private var primaryActionTint: Color {
        colorSchemeContrast == .increased ? Color.white.opacity(0.45) : Color.white.opacity(0.25)
    }
    
    private var secondaryActionTint: Color {
        colorSchemeContrast == .increased ? Color.white.opacity(0.6) : Color.white.opacity(0.4)
    }
    
    private func adjustedOpacity(_ base: Double) -> Double {
        colorSchemeContrast == .increased ? min(1.0, base * 1.6) : base
    }
}


