import SwiftUI

struct PresetsListView: View {
    @ObservedObject var store = PresetsStore.shared
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice
    
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
                            // Try WLED preset ID first (if synced), otherwise apply directly
                            if let presetId = preset.wledPresetId {
                                let apiService = WLEDAPIService.shared
                                _ = try? await apiService.applyPreset(presetId, to: device)
                            } else {
                                // Apply preset directly using gradient stops and brightness
                                let ledCount = device.state?.segments.first?.len ?? 120
                                
                                // Convert temperature to stopTemperatures map if present
                                var stopTemperatures: [UUID: Double]? = nil
                                if let temp = preset.temperature {
                                    stopTemperatures = Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, temp) })
                                }
                                
                                // Apply gradient
                                await viewModel.applyGradientStopsAcrossStrip(
                                    device,
                                    stops: preset.gradientStops,
                                    ledCount: ledCount,
                                    stopTemperatures: stopTemperatures
                                )
                                
                                // Apply brightness via API
                                let apiService = WLEDAPIService.shared
                                _ = try? await apiService.setBrightness(for: device, brightness: preset.brightness)
                            }
                        }
                    }, onEdit: {
                        // Edit handled in row
                    }, onDelete: {
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
                        ForEach(transitionPresets) { preset in
                            TransitionPresetRow(preset: preset, onApply: {
                            Task {
                                // Try WLED playlist ID first (if synced), otherwise apply directly
                                if preset.wledPlaylistId != nil {
                                    // WLED playlists would normally run on-device; for now we
                                    // fall back to the client-side transition implementation.
                                    await viewModel.startTransition(
                                        from: preset.gradientA,
                                        aBrightness: preset.brightnessA,
                                        to: preset.gradientB,
                                        bBrightness: preset.brightnessB,
                                        durationSec: preset.durationSec,
                                        device: device
                                    )
                                } else {
                                    // Apply transition directly
                                    await viewModel.startTransition(
                                        from: preset.gradientA,
                                        aBrightness: preset.brightnessA,
                                        to: preset.gradientB,
                                        bBrightness: preset.brightnessB,
                                        durationSec: preset.durationSec,
                                        device: device
                                    )
                                }
                            }
                        }, onEdit: {
                            // Edit handled in row
                        }, onDelete: {
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
                    Text("WLED Effects")
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
                                // Try WLED preset ID first (if synced), otherwise apply directly
                                if let presetId = preset.wledPresetId {
                                    let apiService = WLEDAPIService.shared
                                    _ = try? await apiService.applyPreset(presetId, to: device)
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
                            // Edit handled in row
                        }, onDelete: {
                            store.removeEffectPreset(preset.id)
                        })
                        }
                    }
                }
            }
        }
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
}

// MARK: - Preset Row Views

struct ColorPresetRow: View {
    let preset: ColorPreset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showEditPopup = false
    @State private var editedName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: Name + Edit icon
            HStack {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    editedName = preset.name
                    showEditPopup = true
                    // Focus text field after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
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
            
            // Content row: Gradient Preview + Action buttons
            HStack(spacing: 12) {
                // Simple Gradient Preview (no tabs/handles) with brightness indicator
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(
                        gradient: Gradient(stops: gradientStops),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 34)
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
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.4))
                    )
                    .padding(4)
                }
                
                // Action buttons
                HStack(spacing: 8) {
                    // Delete button (trash icon only)
                    Button(action: {
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
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
        .overlay {
            // Popup overlay for editing name
            if showEditPopup {
                EditPresetNamePopup(
                    currentName: preset.name,
                    editedName: $editedName,
                    isPresented: $showEditPopup,
                    isTextFieldFocused: $isTextFieldFocused,
                    onSave: { newName in
                        var updatedPreset = preset
                        updatedPreset.name = newName
                        PresetsStore.shared.updateColorPreset(updatedPreset)
                        showEditPopup = false
                    },
                    onCancel: {
                        showEditPopup = false
                    }
                )
            }
        }
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
}

struct TransitionPresetRow: View {
    let preset: TransitionPreset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showEditPopup = false
    @State private var editedName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: Name + Edit icon
            HStack {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    editedName = preset.name
                    showEditPopup = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
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
            
            // Content row: Icon + Action buttons
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(10)
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    // Delete button (trash icon only)
                    Button(action: {
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    // Apply button (tick icon only)
                    Button(action: {
                        onApply()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Details row
            HStack(spacing: 12) {
                Label("\(Int(preset.durationSec))s", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Label("A→B", systemImage: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.blue.opacity(0.8))
                
                Spacer()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            if showEditPopup {
                EditPresetNamePopup(
                    currentName: preset.name,
                    editedName: $editedName,
                    isPresented: $showEditPopup,
                    isTextFieldFocused: $isTextFieldFocused,
                    onSave: { newName in
                        var updatedPreset = preset
                        updatedPreset.name = newName
                        PresetsStore.shared.updateTransitionPreset(updatedPreset)
                        showEditPopup = false
                    },
                    onCancel: {
                        showEditPopup = false
                    }
                )
            }
        }
    }
}

struct EffectPresetRow: View {
    let preset: WLEDEffectPreset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showEditPopup = false
    @State private var editedName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: Name + Edit icon
            HStack {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    editedName = preset.name
                    showEditPopup = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
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
            
            // Content row: Icon + Action buttons
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(.yellow)
                    .frame(width: 48, height: 48)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(10)
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    // Delete button (trash icon only)
                    Button(action: {
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    // Apply button (tick icon only)
                    Button(action: {
                        onApply()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Details row
            HStack(spacing: 12) {
                Text("Effect \(preset.effectId)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                if preset.speed != nil || preset.intensity != nil {
                    Label("Custom", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.8))
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
        .overlay {
            if showEditPopup {
                EditPresetNamePopup(
                    currentName: preset.name,
                    editedName: $editedName,
                    isPresented: $showEditPopup,
                    isTextFieldFocused: $isTextFieldFocused,
                    onSave: { newName in
                        var updatedPreset = preset
                        updatedPreset.name = newName
                        PresetsStore.shared.updateEffectPreset(updatedPreset)
                        showEditPopup = false
                    },
                    onCancel: {
                        showEditPopup = false
                    }
                )
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
        ZStack {
            // Background overlay (darker for better contrast)
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Popup content
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
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(10)
                    
                    Button("Save") {
                        if !editedName.isEmpty && editedName != currentName {
                            onSave(editedName)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.25))
                    .cornerRadius(10)
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
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
        .onAppear {
            editedName = currentName
        }
    }
}
