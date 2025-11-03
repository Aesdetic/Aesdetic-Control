import SwiftUI

struct EffectsPane: View {
    @EnvironmentObject private var viewModel: DeviceControlViewModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let device: WLEDDevice
    let segmentId: Int
    
    private var metadataBundle: EffectMetadataBundle? {
        viewModel.effectMetadata(for: device)
    }
    
    private var effectOptions: [EffectMetadata] {
        metadataBundle?.effects ?? []
    }
    
    private var paletteOptions: [PaletteMetadata] {
        metadataBundle?.palettes ?? []
    }
    
    private var currentState: DeviceEffectState {
        viewModel.currentEffectState(for: device, segmentId: segmentId)
    }
    
    private var activeEffectMetadata: EffectMetadata? {
        effectOptions.first(where: { $0.id == currentState.effectId })
    }
    
    private var effectSelection: Binding<Int> {
        Binding(
            get: { currentState.effectId },
            set: { newValue in
                Task { await viewModel.setEffect(for: device, segmentId: segmentId, effectId: newValue) }
            }
        )
    }
    
    private var speedBinding: Binding<Double> {
        Binding(
            get: { Double(currentState.speed) },
            set: { newValue in
                Task { await viewModel.updateEffectSpeed(for: device, segmentId: segmentId, speed: Int(newValue.rounded())) }
            }
        )
    }
    
    private var intensityBinding: Binding<Double> {
        Binding(
            get: { Double(currentState.intensity) },
            set: { newValue in
                Task { await viewModel.updateEffectIntensity(for: device, segmentId: segmentId, intensity: Int(newValue.rounded())) }
            }
        )
    }
    
    private var paletteBinding: Binding<Int> {
        Binding(
            get: { currentState.paletteId },
            set: { newValue in
                Task { await viewModel.updateEffectPalette(for: device, segmentId: segmentId, paletteId: newValue) }
            }
        )
    }
    
    private var speedLabel: String {
        activeEffectMetadata?.parameters.first(where: { $0.kind == .speed })?.label ?? "Speed"
    }
    
    private var intensityLabel: String {
        activeEffectMetadata?.parameters.first(where: { $0.kind == .intensity })?.label ?? "Intensity"
    }
    
    private var supportsPalette: Bool {
        if let effect = activeEffectMetadata {
            return effect.supportsPalette
        }
        return true
    }
    
    private var showsSpeed: Bool {
        if let effect = activeEffectMetadata {
            return effect.supportsSpeed
        }
        return true
    }
    
    private var showsIntensity: Bool {
        if let effect = activeEffectMetadata {
            return effect.supportsIntensity
        }
        return true
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Effects", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if effectOptions.isEmpty {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            
            if effectOptions.isEmpty {
                fallbackEffectPicker
            } else {
                effectPicker
            }
            
            if showsSpeed {
                sliderRow(label: speedLabel, value: speedBinding)
            }
            
            if showsIntensity {
                sliderRow(label: intensityLabel, value: intensityBinding)
            }
            
            if supportsPalette, !paletteOptions.isEmpty {
                palettePicker
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
    }
    
    private var effectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Effect")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Picker("Effect", selection: effectSelection) {
                ForEach(effectOptions) { effect in
                    Text(effect.name)
                        .tag(effect.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .accessibilityHint("Selects a lighting effect.")
        }
    }
    
    private func sliderRow(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: value, in: 0...255, step: 1)
                .tint(.white)
                .accessibilityLabel(label)
                .accessibilityValue("\(Int(value.wrappedValue))")
                .accessibilityHint("Adjusts \(label.lowercased()) for the current effect.")
        }
    }
    
    private var palettePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Palette")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Picker("Palette", selection: paletteBinding) {
                ForEach(paletteOptions) { palette in
                    Text(palette.name)
                        .tag(palette.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .accessibilityHint("Selects a color palette for the current effect.")
        }
    }
    
    private var fallbackEffectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Effect ID")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Stepper(value: effectSelection, in: 0...255) {
                Text("Mode \(currentState.effectId)")
                    .foregroundColor(.white)
            }
        }
    }
}

private extension EffectsPane {
    var backgroundFill: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 0.12 : 0.06)
    }
}


