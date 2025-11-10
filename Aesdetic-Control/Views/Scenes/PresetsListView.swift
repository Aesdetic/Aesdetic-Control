import SwiftUI

struct PresetsListView: View {
    @ObservedObject var store = PresetsStore.shared
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice
    let onRequestRename: (PresetRenameContext) -> Void
    
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
                        onRequestRename(.color(preset))
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
                            onRequestRename(.transition(preset))
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
                            onRequestRename(.effect(preset))
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
                
                Text("\(Int(round(preset.durationSec)))s")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
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
        effectPreviewHexColors.map { Color(hex: $0) }
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
        guard let hex = effectPreviewHexColors.last else { return .white }
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
