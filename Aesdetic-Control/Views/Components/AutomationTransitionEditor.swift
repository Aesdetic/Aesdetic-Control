import SwiftUI

/// Transition editor component for automation dialogs that works with bindings instead of direct device updates
struct AutomationTransitionEditor: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @ObservedObject private var presetsStore = PresetsStore.shared
    let device: WLEDDevice
    
    // Bindings for automation state
    @Binding var startGradient: LEDGradient
    @Binding var endGradient: LEDGradient
    @Binding var startBrightness: Double
    @Binding var endBrightness: Double
    @Binding var durationSeconds: Double
    
    // Preview state
    @State private var previewEnabled: Bool = false
    
    // Internal UI state
    @State private var selectedA: UUID? = nil
    @State private var selectedB: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var wheelTarget: Character = "A" // 'A' or 'B'
    @State private var selectedStartPresetId: UUID?
    @State private var selectedEndPresetId: UUID?
    @State private var selectedTransitionPresetId: UUID?
    @State private var durationHours: Int = 0
    @State private var durationMinutes: Int = 1
    @State private var isApplyingTransition: Bool = false
    
    private var allowedMinuteValues: [Int] {
        durationHours >= 24 ? [0] : Array(0...59)
    }
    
    private var colorPresets: [ColorPreset] {
        presetsStore.colorPresets
    }
    
    private var transitionPresets: [TransitionPreset] {
        presetsStore.transitionPresets(for: device.id)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            headerRow
            transitionPresetSelector
            durationSection
            startSection
            endSection
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
        .onAppear {
            // Initialize duration from durationSeconds
            updateDurationFromSeconds(durationSeconds)
        }
        .onChange(of: durationSeconds) { _, newValue in
            updateDurationFromSeconds(newValue)
        }
    }
    
    // MARK: - Section Views
    
    private var headerRow: some View {
        HStack {
            Label("Transitions", systemImage: "arrow.triangle.2.circlepath")
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
    private var transitionPresetSelector: some View {
        if !transitionPresets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Transitions")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(transitionPresets) { preset in
                            transitionPresetChip(preset: preset)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func transitionPresetChip(preset: TransitionPreset) -> some View {
        let isSelected = selectedTransitionPresetId == preset.id
        return Button {
            selectedTransitionPresetId = preset.id
            startGradient = preset.gradientA
            endGradient = preset.gradientB
            startBrightness = Double(preset.brightnessA)
            endBrightness = Double(preset.brightnessB)
            durationSeconds = preset.durationSec
            
            if previewEnabled {
                Task {
                    await previewTransition()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Start gradient preview
                    LinearGradient(
                        gradient: Gradient(colors: preset.gradientA.stops.map { Color(hex: $0.hexColor) }),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 40, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    
                    // End gradient preview
                    LinearGradient(
                        gradient: Gradient(colors: preset.gradientB.stops.map { Color(hex: $0.hexColor) }),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 40, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                
                Text(preset.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(Int(preset.durationSec))s")
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
    
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duration")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
            
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Hours")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Picker("Hours", selection: $durationHours) {
                        ForEach(0...24, id: \.self) { value in
                            Text(String(format: "%02d", value))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                    .clipped()
                    .onChange(of: durationHours) { _, _ in
                        updateDurationToSeconds()
                    }
                }
                
                VStack(spacing: 4) {
                    Text("Minutes")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Picker("Minutes", selection: $durationMinutes) {
                        ForEach(allowedMinuteValues, id: \.self) { value in
                            Text(String(format: "%02d", value))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                    .clipped()
                    .onChange(of: durationMinutes) { _, _ in
                        updateDurationToSeconds()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
    }
    
    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("Start")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(Int(round(startBrightness/255.0*100)))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Slider(value: $startBrightness, in: 0...255, step: 1)
                .tint(.white)
                .onChange(of: startBrightness) { _, _ in
                    if previewEnabled {
                        Task {
                            await previewTransition()
                        }
                    }
                }
            
            GradientBar(
                gradient: $startGradient,
                selectedStopId: $selectedA,
                onTapStop: { id in
                    wheelTarget = "A"
                    selectedA = id
                    if let idx = startGradient.stops.firstIndex(where: { $0.id == id }) {
                        wheelInitial = startGradient.stops[idx].color
                        showWheel = true
                    }
                },
                onTapAnywhere: { t, _ in
                    let color = GradientSampler.sampleColor(at: t, stops: startGradient.stops, interpolation: startGradient.interpolation)
                    let new = GradientStop(position: t, hexColor: color.toHex())
                    var updatedStops = startGradient.stops
                    updatedStops.append(new)
                    updatedStops.sort { $0.position < $1.position }
                    startGradient = LEDGradient(stops: updatedStops, interpolation: startGradient.interpolation)
                    selectedA = new.id
                    
                    if previewEnabled {
                        Task {
                            await previewTransition()
                        }
                    }
                },
                onStopsChanged: { stops, phase in
                    startGradient = LEDGradient(stops: stops, interpolation: startGradient.interpolation)
                    if previewEnabled && phase == .ended {
                        Task {
                            await previewTransition()
                        }
                    }
                }
            )
            .frame(height: 56)
            
            if !colorPresets.isEmpty {
                colorPresetSelector(target: .start)
            }
            
            if showWheel && wheelTarget == "A", let selectedId = selectedA {
                colorWheelView(selectedId: selectedId, target: .start)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var endSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("End")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(Int(round(endBrightness/255.0*100)))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Slider(value: $endBrightness, in: 0...255, step: 1)
                .tint(.white)
                .onChange(of: endBrightness) { _, _ in
                    if previewEnabled {
                        Task {
                            await previewTransition()
                        }
                    }
                }
            
            GradientBar(
                gradient: $endGradient,
                selectedStopId: $selectedB,
                onTapStop: { id in
                    wheelTarget = "B"
                    selectedB = id
                    if let idx = endGradient.stops.firstIndex(where: { $0.id == id }) {
                        wheelInitial = endGradient.stops[idx].color
                        showWheel = true
                    }
                },
                onTapAnywhere: { t, _ in
                    let color = GradientSampler.sampleColor(at: t, stops: endGradient.stops, interpolation: endGradient.interpolation)
                    let new = GradientStop(position: t, hexColor: color.toHex())
                    var updatedStops = endGradient.stops
                    updatedStops.append(new)
                    updatedStops.sort { $0.position < $1.position }
                    endGradient = LEDGradient(stops: updatedStops, interpolation: endGradient.interpolation)
                    selectedB = new.id
                    
                    if previewEnabled {
                        Task {
                            await previewTransition()
                        }
                    }
                },
                onStopsChanged: { stops, phase in
                    endGradient = LEDGradient(stops: stops, interpolation: endGradient.interpolation)
                    if previewEnabled && phase == .ended {
                        Task {
                            await previewTransition()
                        }
                    }
                }
            )
            .frame(height: 56)
            
            if !colorPresets.isEmpty {
                colorPresetSelector(target: .end)
            }
            
            if showWheel && wheelTarget == "B", let selectedId = selectedB {
                colorWheelView(selectedId: selectedId, target: .end)
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func colorPresetSelector(target: GradientTarget) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(colorPresets) { preset in
                    colorPresetChip(preset: preset, target: target)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, 4)
    }
    
    private enum GradientTarget {
        case start
        case end
    }
    
    private func colorPresetChip(preset: ColorPreset, target: GradientTarget) -> some View {
        let isSelected = (target == .start && selectedStartPresetId == preset.id) || 
                        (target == .end && selectedEndPresetId == preset.id)
        return Button {
            if target == .start {
                selectedStartPresetId = preset.id
                startGradient = LEDGradient(stops: preset.gradientStops, interpolation: preset.gradientInterpolation ?? .linear)
                startBrightness = Double(preset.brightness)
            } else {
                selectedEndPresetId = preset.id
                endGradient = LEDGradient(stops: preset.gradientStops, interpolation: preset.gradientInterpolation ?? .linear)
                endBrightness = Double(preset.brightness)
            }
            
            if previewEnabled {
                Task {
                    await previewTransition()
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
    private func colorWheelView(selectedId: UUID, target: GradientTarget) -> some View {
        let currentGradient = target == .start ? startGradient : endGradient
        let canRemove = currentGradient.stops.count > 1
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
                if target == .start {
                    guard let idx = startGradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
                    var updatedStops = startGradient.stops
                    if let temp = temperature {
                        updatedStops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                    } else {
                        updatedStops[idx].hexColor = color.toHex()
                    }
                    startGradient = LEDGradient(stops: updatedStops, interpolation: startGradient.interpolation)
                } else {
                    guard let idx = endGradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
                    var updatedStops = endGradient.stops
                    if let temp = temperature {
                        updatedStops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                    } else {
                        updatedStops[idx].hexColor = color.toHex()
                    }
                    endGradient = LEDGradient(stops: updatedStops, interpolation: endGradient.interpolation)
                }
                
                if previewEnabled {
                    Task {
                        await previewTransition()
                    }
                }
            },
            onRemove: {
                if target == .start {
                    if startGradient.stops.count > 1 {
                        var updatedStops = startGradient.stops
                        updatedStops.removeAll { $0.id == selectedId }
                        startGradient = LEDGradient(stops: updatedStops, interpolation: startGradient.interpolation)
                        selectedA = nil
                    }
                } else {
                    if endGradient.stops.count > 1 {
                        var updatedStops = endGradient.stops
                        updatedStops.removeAll { $0.id == selectedId }
                        endGradient = LEDGradient(stops: updatedStops, interpolation: endGradient.interpolation)
                        selectedB = nil
                    }
                }
                showWheel = false
                
                if previewEnabled {
                    Task {
                        await previewTransition()
                    }
                }
            },
            onDismiss: { showWheel = false }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder
    private var previewSection: some View {
        if previewEnabled && isApplyingTransition {
            Button(action: cancelPreview) {
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
    
    private func updateDurationFromSeconds(_ seconds: Double) {
        let total = Int(seconds)
        durationHours = total / 3600
        durationMinutes = (total % 3600) / 60
    }
    
    private func updateDurationToSeconds() {
        durationSeconds = Double(max(0, durationHours * 3600 + durationMinutes * 60))
    }
    
    // MARK: - Preview Functions
    
    private func previewTransition() async {
        await MainActor.run {
            isApplyingTransition = true
        }
        
        await viewModel.cancelActiveTransitionIfNeeded(for: device)
        try? await Task.sleep(nanoseconds: 120_000_000)
        
        await viewModel.startTransition(
            from: startGradient,
            aBrightness: Int(startBrightness),
            to: endGradient,
            bBrightness: Int(endBrightness),
            durationSec: durationSeconds,
            device: device
        )
        
        await MainActor.run {
            isApplyingTransition = false
        }
    }
    
    private func cancelPreview() {
        Task {
            await viewModel.stopTransitionAndRevertToA(device: device)
            await MainActor.run {
                isApplyingTransition = false
            }
        }
    }
}

