import SwiftUI

/// Color editor component for automation dialogs that works with bindings instead of direct device updates
struct AutomationColorEditor: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @ObservedObject private var presetsStore = PresetsStore.shared
    let device: WLEDDevice
    
    // Bindings for automation state
    @Binding var gradient: LEDGradient
    @Binding var brightness: Double
    @Binding var interpolation: GradientInterpolation
    @Binding var fadeDuration: Double
    @Binding var enableFade: Bool
    @Binding var selectedPresetId: UUID?
    
    // Preview state
    @State private var previewEnabled: Bool = false
    
    // Internal UI state
    @State private var selectedStopId: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var stopTemperatures: [UUID: Double] = [:]
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    
    var body: some View {
        VStack(spacing: 16) {
            headerRow
            brightnessSection
            blendSelector
            gradientSection
            presetSelector
            colorWheel
            fadeSection
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
        .onChange(of: previewEnabled) { _, enabled in
            if enabled {
                Task {
                    await previewGradient(gradient)
                }
            }
        }
    }
    
    // MARK: - Section Views
    
    @ViewBuilder
    private var presetSelector: some View {
        if !presetsStore.colorPresets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Colors")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(presetsStore.colorPresets) { preset in
                            presetChip(preset: preset)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func presetChip(preset: ColorPreset) -> some View {
        let isSelected = selectedPresetId == preset.id
        return Button {
            selectedPresetId = preset.id
            gradient = LEDGradient(stops: preset.gradientStops, interpolation: preset.gradientInterpolation ?? .linear)
            brightness = Double(preset.brightness)
            interpolation = preset.gradientInterpolation ?? gradient.interpolation
            
            if previewEnabled {
                Task {
                    await previewGradient(gradient)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                LinearGradient(
                    gradient: Gradient(colors: preset.gradientStops.map { Color(hex: $0.hexColor) }),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                Text(preset.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
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
    
    private var headerRow: some View {
        HStack {
            Label("Colors", systemImage: "paintbrush.fill")
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
            
            Button(action: {
                Task {
                    await saveColorPreset()
                }
            }) {
                HStack(spacing: 6) {
                    if isSavingPreset {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else if showSaveSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                    }
                    Text("Preset")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isSavingPreset)
        }
        .padding(.horizontal, 16)
    }
    
    private var brightnessSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Brightness")
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(round(brightness/255.0*100)))%")
                    .foregroundColor(.white.opacity(0.8))
            }
            Slider(value: $brightness, in: 0...255, step: 1)
                .tint(.white)
                .onChange(of: brightness) { _, newValue in
                    if previewEnabled {
                        Task {
                            await previewBrightness(Int(newValue))
                        }
                    }
                }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var blendSelector: some View {
        if gradient.stops.count >= 2 {
            VStack(spacing: 6) {
                HStack {
                    Text("Blend Style")
                        .foregroundColor(.white)
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GradientInterpolation.allCases, id: \.self) { mode in
                            blendModeButton(mode: mode)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func blendModeButton(mode: GradientInterpolation) -> some View {
        Button(action: {
            interpolation = mode
            var updatedGradient = gradient
            updatedGradient.interpolation = mode
            gradient = updatedGradient
            selectedPresetId = nil // Clear preset when manually changing interpolation
            if previewEnabled {
                Task {
                    await previewGradient(updatedGradient)
                }
            }
        }) {
            Text(mode.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(interpolation == mode ? .black : .white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(interpolation == mode ? Color.white : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
    
    private var gradientSection: some View {
        GradientBar(
            gradient: $gradient,
            selectedStopId: $selectedStopId,
            onTapStop: handleTapStop,
            onTapAnywhere: handleTapAnywhere,
            onStopsChanged: handleStopsChanged
        )
        .frame(height: 56)
        .padding(.horizontal, 16)
    }
    
    private func handleTapStop(id: UUID) {
        if let stop = gradient.stops.first(where: { $0.id == id }) {
            wheelInitial = stop.color
            showWheel = true
        }
    }
    
    private func handleTapAnywhere(t: Double, tappedStopId: UUID?) {
        let color = GradientSampler.sampleColor(at: t, stops: gradient.stops, interpolation: gradient.interpolation)
        let new = GradientStop(position: t, hexColor: color.toHex())
        var updatedGradient = gradient
        updatedGradient.stops.append(new)
        updatedGradient.stops.sort { $0.position < $1.position }
        
        // Inherit temperature from nearest stop
        if !stopTemperatures.isEmpty {
            let sortedStops = updatedGradient.stops.sorted { $0.position < $1.position }
            if let newIndex = sortedStops.firstIndex(where: { $0.id == new.id }) {
                var nearestTemperature: Double? = nil
                var minDistance: Double = Double.greatestFiniteMagnitude
                
                for (idx, stop) in sortedStops.enumerated() {
                    if idx != newIndex, let temp = stopTemperatures[stop.id] {
                        let distance = abs(stop.position - new.position)
                        if distance < minDistance {
                            minDistance = distance
                            nearestTemperature = temp
                        }
                    }
                }
                
                if let inheritedTemp = nearestTemperature {
                    stopTemperatures[new.id] = inheritedTemp
                }
            }
        }
        
        gradient = updatedGradient
        selectedStopId = new.id
        selectedPresetId = nil // Clear preset when manually adding a stop
        
        if previewEnabled {
            Task {
                await previewGradient(updatedGradient)
            }
        }
    }
    
    private func handleStopsChanged(stops: [GradientStop], phase: DragPhase) {
        var updatedGradient = gradient
        updatedGradient.stops = stops
        gradient = updatedGradient
        selectedPresetId = nil // Clear preset when manually dragging stops
        
        if previewEnabled && phase == .ended {
            Task {
                await previewGradient(updatedGradient)
            }
        }
    }
    
    @ViewBuilder
    private var colorWheel: some View {
        if showWheel {
            let effectiveSelectedId = selectedStopId ?? gradient.stops.first?.id
            if let selectedId = effectiveSelectedId {
                colorWheelView(selectedId: selectedId)
            }
        }
    }
    
    private func colorWheelView(selectedId: UUID) -> some View {
        let supportsCCT = viewModel.supportsCCT(for: device, segmentId: 0)
        let supportsWhite = viewModel.supportsWhite(for: device, segmentId: 0)
        let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: 0)
        return ColorWheelInline(
            initialColor: wheelInitial,
            canRemove: gradient.stops.count > 1,
            supportsCCT: supportsCCT,
            supportsWhite: supportsWhite,
            usesKelvinCCT: usesKelvin,
            onColorChange: { color, temperature, whiteLevel in
                handleColorChange(selectedId: selectedId, color: color, temperature: temperature)
            },
            onRemove: {
                handleColorRemove(selectedId: selectedId)
            },
            onDismiss: { showWheel = false }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .padding(.horizontal, 16)
    }
    
    private func handleColorChange(selectedId: UUID, color: Color, temperature: Double?) {
        guard let idx = gradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
        
        var updatedGradient = gradient
        
        if let temp = temperature {
            stopTemperatures[selectedId] = temp
            updatedGradient.stops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
        } else {
            updatedGradient.stops[idx].hexColor = color.toHex()
            stopTemperatures.removeValue(forKey: selectedId)
        }
        
        gradient = updatedGradient
        selectedPresetId = nil // Clear preset when manually changing a stop color
        
        if previewEnabled {
            Task {
                await previewGradient(updatedGradient)
            }
        }
    }
    
    private func handleColorRemove(selectedId: UUID) {
        if gradient.stops.count > 1 {
            var updatedGradient = gradient
            updatedGradient.stops.removeAll { $0.id == selectedId }
            stopTemperatures.removeValue(forKey: selectedId)
            gradient = updatedGradient
            selectedStopId = nil
            selectedPresetId = nil // Clear preset when manually removing a stop
            
            if previewEnabled {
                Task {
                    await previewGradient(updatedGradient)
                }
            }
        }
    }
    
    @ViewBuilder
    private var fadeSection: some View {
        Toggle(isOn: $enableFade) {
            Text("Fade over time")
                .foregroundColor(.white.opacity(0.9))
        }
        .toggleStyle(SwitchToggleStyle(tint: .white))
        .padding(.horizontal, 16)
        
        if enableFade {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fade duration")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(fadeDuration)) sec")
                        .foregroundColor(.white)
                }
                Slider(value: $fadeDuration, in: 5...300, step: 5)
                    .tint(.white)
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Preview Functions
    
    private func previewGradient(_ gradient: LEDGradient) async {
        let ledCount = device.state?.segments.first?.len ?? 120
        await viewModel.applyGradientStopsAcrossStrip(
            device,
            stops: gradient.stops,
            ledCount: ledCount,
            stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures,
            disableActiveEffect: true,
            segmentId: 0,
            interpolation: gradient.interpolation
        )
    }
    
    private func previewBrightness(_ brightness: Int) async {
        await viewModel.updateDeviceBrightness(device, brightness: brightness)
    }
    
    // MARK: - Preset Saving
    
    private func saveColorPreset() async {
        await MainActor.run {
            isSavingPreset = true
            showSaveSuccess = false
        }
        
        let presetName = "Color Preset \(Date().formatted(date: .omitted, time: .shortened))"
        let preset = ColorPreset(
            name: presetName,
            gradientStops: gradient.stops,
            gradientInterpolation: gradient.interpolation,
            brightness: Int(brightness),
            temperature: stopTemperatures.values.first
        )
        
        await MainActor.run {
            PresetsStore.shared.addColorPreset(preset)
            selectedPresetId = preset.id  // Select the newly saved preset
            isSavingPreset = false
            showSaveSuccess = true
            
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    showSaveSuccess = false
                }
            }
        }
    }
}


