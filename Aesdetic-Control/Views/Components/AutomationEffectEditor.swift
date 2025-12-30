import SwiftUI

/// Effect editor component for automation dialogs that works with bindings instead of direct device updates
struct AutomationEffectEditor: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @ObservedObject private var presetsStore = PresetsStore.shared
    let device: WLEDDevice
    let effectOptions: [EffectMetadata]
    
    // Bindings for automation state
    @Binding var effectId: Int
    @Binding var brightness: Double
    @Binding var speed: Int
    @Binding var intensity: Int
    @Binding var gradient: LEDGradient
    @Binding var selectedEffectPresetId: UUID?
    
    // Preview state
    @State private var previewEnabled: Bool = false
    @State private var isApplyingEffect: Bool = false
    
    // Internal UI state
    @State private var selectedStopId: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var selectedColorPresetId: UUID? = nil
    @State private var stagedSpeedValue: Double?
    @State private var stagedIntensityValue: Double?
    @State private var isAdjustingSpeed = false
    @State private var isAdjustingIntensity = false
    
    private var activeEffectMetadata: EffectMetadata? {
        effectOptions.first(where: { $0.id == effectId })
    }
    
    private var slotCount: Int {
        max(activeEffectMetadata?.colorSlotCount ?? 2, 1)
    }
    
    private var canEditGradient: Bool {
        slotCount >= 2
    }
    
    private var speedLabel: String {
        activeEffectMetadata?.parameters.first(where: { $0.kind == .speed })?.label ?? "Speed"
    }
    
    private var intensityLabel: String {
        activeEffectMetadata?.parameters.first(where: { $0.kind == .intensity })?.label ?? "Intensity"
    }
    
    private var showsSpeed: Bool {
        activeEffectMetadata?.supportsSpeed ?? true
    }
    
    private var showsIntensity: Bool {
        activeEffectMetadata?.supportsIntensity ?? true
    }
    
    private var colorPresets: [ColorPreset] {
        presetsStore.colorPresets
    }
    
    private var effectPresets: [WLEDEffectPreset] {
        presetsStore.effectPresets(for: device.id)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            headerRow
            effectPresetSelector
            effectPicker
            gradientSection
            brightnessSection
            speedSection
            intensitySection
            previewSection
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .onChange(of: effectId) { _, newId in
            // Update gradient for new slot count when effect changes
            updateGradientForSlotCount()
        }
        .onChange(of: previewEnabled) { _, enabled in
            if !enabled && isApplyingEffect {
                stopPreview()
            }
        }
    }
    
    // MARK: - Section Views
    
    private var headerRow: some View {
        HStack {
            Label("Animations", systemImage: "sparkles")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            
            Toggle(isOn: $previewEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: previewEnabled ? "eye.fill" : "eye.slash.fill")
                        .font(.caption2)
                    Text("Preview")
                        .font(.caption.weight(.medium))
                }
            }
            .toggleStyle(.button)
            .tint(previewEnabled ? .green : .gray)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var effectPresetSelector: some View {
        if !effectPresets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Effects")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(effectPresets) { preset in
                            effectPresetChip(preset: preset)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func effectPresetChip(preset: WLEDEffectPreset) -> some View {
        let isSelected = selectedEffectPresetId == preset.id
        return Button {
            selectedEffectPresetId = preset.id
            effectId = preset.effectId
            brightness = Double(preset.brightness)
            speed = preset.speed ?? 128
            intensity = preset.intensity ?? 128
            if let presetStops = preset.gradientStops, !presetStops.isEmpty {
                gradient = LEDGradient(
                    stops: presetStops,
                    interpolation: preset.gradientInterpolation ?? .linear
                )
            }
            
            if previewEnabled {
                Task {
                    await previewEffect()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("Effect \(preset.effectId)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(8)
            .frame(width: 120, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var effectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Animation")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
            
            if effectOptions.isEmpty {
                Text("No gradient-friendly animations available for this device.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Picker("Animation", selection: $effectId) {
                    ForEach(effectOptions) { effect in
                        Text(effect.name).tag(effect.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .onChange(of: effectId) { _, _ in
                    selectedEffectPresetId = nil
                    updateGradientForSlotCount()
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var gradientSection: some View {
        if canEditGradient {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gradient")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                
                GradientBar(
                    gradient: $gradient,
                    selectedStopId: $selectedStopId,
                    onTapStop: { id in
                        selectedStopId = id
                        if let stop = gradient.stops.first(where: { $0.id == id }) {
                            wheelInitial = stop.color
                            showWheel = true
                        }
                    },
                    onTapAnywhere: { t, _ in
                        let color = GradientSampler.sampleColor(at: t, stops: gradient.stops, interpolation: gradient.interpolation)
                        let newStop = GradientStop(position: t, hexColor: color.toHex())
                        var updatedStops = gradient.stops
                        updatedStops.append(newStop)
                        updatedStops.sort { $0.position < $1.position }
                        gradient = LEDGradient(stops: updatedStops, interpolation: gradient.interpolation)
                        selectedStopId = newStop.id
                        wheelInitial = color
                        showWheel = true
                        
                        if previewEnabled {
                            Task {
                                await previewEffect()
                            }
                        }
                    },
                    onStopsChanged: { stops, phase in
                        gradient = LEDGradient(stops: stops, interpolation: gradient.interpolation)
                        if previewEnabled && phase == .ended {
                            Task {
                                await previewEffect()
                            }
                        }
                    }
                )
                .frame(height: 56)
                
                if !colorPresets.isEmpty {
                    colorPresetSelector
                }
                
                if showWheel, let selectedId = selectedStopId {
                    colorWheelView(selectedId: selectedId)
                }
            }
            .padding(.horizontal, 16)
        } else {
            // Single color mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                
                Button(action: {
                    selectedStopId = gradient.stops.first?.id ?? UUID()
                    wheelInitial = gradient.stops.first?.color ?? .white
                    showWheel = true
                }) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(gradient.stops.first?.color ?? .white)
                        .frame(height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                if showWheel, let selectedId = selectedStopId {
                    colorWheelView(selectedId: selectedId)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private var colorPresetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(colorPresets) { preset in
                    colorPresetChip(preset: preset)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, 4)
    }
    
    private func colorPresetChip(preset: ColorPreset) -> some View {
        let isSelected = selectedColorPresetId == preset.id
        return Button {
            selectedColorPresetId = preset.id
            let sortedStops = preset.gradientStops.sorted { $0.position < $1.position }
            guard !sortedStops.isEmpty else { return }
            gradient = LEDGradient(
                stops: sortedStops,
                interpolation: preset.gradientInterpolation ?? gradient.interpolation
            )
            updateGradientForSlotCount()
            
            if previewEnabled {
                Task {
                    await previewEffect()
                }
            }
        } label: {
            LinearGradient(
                gradient: Gradient(colors: preset.gradientStops.map { Color(hex: $0.hexColor) }),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 60, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func colorWheelView(selectedId: UUID) -> some View {
        let canRemove = canEditGradient && gradient.stops.count > 1
        let supportsCCT = viewModel.supportsCCT(for: device, segmentId: 0)
        let supportsWhite = viewModel.supportsWhite(for: device, segmentId: 0)
        let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: 0)
        
        ColorWheelInline(
            initialColor: wheelInitial,
            canRemove: canRemove,
            supportsCCT: supportsCCT,
            supportsWhite: supportsWhite,
            usesKelvinCCT: usesKelvin,
            onColorChange: { color, temperature, whiteLevel in
                guard let idx = gradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
                var updatedStops = gradient.stops
                if let temp = temperature {
                    updatedStops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                } else {
                    updatedStops[idx].hexColor = color.toHex()
                }
                gradient = LEDGradient(stops: updatedStops, interpolation: gradient.interpolation)
                
                if previewEnabled {
                    Task {
                        await previewEffect()
                    }
                }
            },
            onRemove: {
                if canEditGradient && gradient.stops.count > 1 {
                    var updatedStops = gradient.stops
                    updatedStops.removeAll { $0.id == selectedId }
                    gradient = LEDGradient(stops: updatedStops, interpolation: gradient.interpolation)
                    selectedStopId = nil
                    
                    if previewEnabled {
                        Task {
                            await previewEffect()
                        }
                    }
                }
                showWheel = false
            },
            onDismiss: { showWheel = false }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Brightness")
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(Int(brightness))%")
                    .foregroundColor(.white.opacity(0.8))
            }
            Slider(value: $brightness, in: 1...255, step: 1)
                .tint(.white)
                .onChange(of: brightness) { _, _ in
                    if previewEnabled {
                        Task {
                            await previewBrightness(Int(brightness))
                        }
                    }
                }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var speedSection: some View {
        if showsSpeed {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(speedLabel)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(currentSpeedValue))")
                        .foregroundColor(.white.opacity(0.8))
                }
                Slider(
                    value: Binding(
                        get: { currentSpeedValue },
                        set: { stagedSpeedValue = $0 }
                    ),
                    in: 0...255,
                    step: 1,
                    onEditingChanged: { editing in
                        isAdjustingSpeed = editing
                        if !editing {
                            let target = Int(round(stagedSpeedValue ?? currentSpeedValue))
                            speed = target
                            stagedSpeedValue = nil
                            if previewEnabled {
                                Task {
                                    await previewSpeed(target)
                                }
                            }
                        }
                    }
                )
                .tint(.white)
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private var intensitySection: some View {
        if showsIntensity {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(intensityLabel)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(currentIntensityValue))")
                        .foregroundColor(.white.opacity(0.8))
                }
                Slider(
                    value: Binding(
                        get: { currentIntensityValue },
                        set: { stagedIntensityValue = $0 }
                    ),
                    in: 0...255,
                    step: 1,
                    onEditingChanged: { editing in
                        isAdjustingIntensity = editing
                        if !editing {
                            let target = Int(round(stagedIntensityValue ?? currentIntensityValue))
                            intensity = target
                            stagedIntensityValue = nil
                            if previewEnabled {
                                Task {
                                    await previewIntensity(target)
                                }
                            }
                        }
                    }
                )
                .tint(.white)
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private var previewSection: some View {
        if previewEnabled && isApplyingEffect {
            Button(action: stopPreview) {
                Text("Stop Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Helper Functions
    
    private var currentSpeedValue: Double {
        stagedSpeedValue ?? Double(speed)
    }
    
    private var currentIntensityValue: Double {
        stagedIntensityValue ?? Double(intensity)
    }
    
    private func updateGradientForSlotCount() {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        if slotCount <= 1 {
            let hex = sortedStops.first?.hexColor ?? "FFFFFF"
            gradient = LEDGradient(stops: [GradientStop(position: 0.0, hexColor: hex)], interpolation: gradient.interpolation)
        } else {
            let clampedCount = max(2, slotCount)
            let positions: [Double]
            if clampedCount == 2 {
                positions = [0.0, 1.0]
            } else {
                positions = (0..<clampedCount).map { Double($0) / Double(clampedCount - 1) }
            }
            let generatedStops = positions.map { t -> GradientStop in
                let sourceStops = sortedStops.isEmpty ? gradient.stops : sortedStops
                let color = GradientSampler.sampleColor(at: t, stops: sourceStops, interpolation: gradient.interpolation)
                return GradientStop(position: t, hexColor: color.toHex())
            }
            gradient = LEDGradient(stops: generatedStops, interpolation: gradient.interpolation)
        }
    }
    
    // MARK: - Preview Functions
    
    private func previewEffect() async {
        await MainActor.run {
            isApplyingEffect = true
        }
        
        let preparedGradient = preparedGradientForSlotCount(gradient, slotCount: slotCount)
        await viewModel.applyColorSafeEffect(effectId, with: preparedGradient, segmentId: 0, device: device)
        await viewModel.updateDeviceBrightness(device, brightness: Int(brightness))
        
        await MainActor.run {
            isApplyingEffect = false
        }
    }
    
    private func previewBrightness(_ brightness: Int) async {
        await viewModel.updateDeviceBrightness(device, brightness: brightness)
    }
    
    private func previewSpeed(_ speed: Int) async {
        await viewModel.updateEffectSpeed(for: device, segmentId: 0, speed: speed)
    }
    
    private func previewIntensity(_ intensity: Int) async {
        await viewModel.updateEffectIntensity(for: device, segmentId: 0, intensity: intensity)
    }
    
    private func stopPreview() {
        Task {
            await viewModel.disableEffect(for: device, segmentId: 0)
            await MainActor.run {
                isApplyingEffect = false
                previewEnabled = false
            }
        }
    }
    
    private func preparedGradientForSlotCount(_ gradient: LEDGradient, slotCount: Int) -> LEDGradient {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        if slotCount <= 1 {
            let hex = sortedStops.first?.hexColor ?? "FFFFFF"
            return LEDGradient(stops: [GradientStop(position: 0.0, hexColor: hex)], interpolation: gradient.interpolation)
        }
        let clampedCount = max(2, slotCount)
        let positions: [Double]
        if clampedCount == 2 {
            positions = [0.0, 1.0]
        } else {
            positions = (0..<clampedCount).map { Double($0) / Double(clampedCount - 1) }
        }
        let generatedStops = positions.map { t -> GradientStop in
            let sourceStops = sortedStops.isEmpty ? gradient.stops : sortedStops
            let color = GradientSampler.sampleColor(at: t, stops: sourceStops, interpolation: gradient.interpolation)
            return GradientStop(position: t, hexColor: color.toHex())
        }
        return LEDGradient(stops: generatedStops, interpolation: gradient.interpolation)
    }
}

