import SwiftUI

struct TransitionPane: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let device: WLEDDevice
    @Binding var dismissColorPicker: Bool
    @Binding var isExpanded: Bool
    let onActivate: () -> Void

    // A/B gradients (lazy initialization)
    @State private var stopsA: [GradientStop]?
    @State private var stopsB: [GradientStop]?
    
    // Cached gradients to prevent re-creation on every render
    @State private var gradientA: LEDGradient?
    @State private var gradientB: LEDGradient?

    @State private var selectedA: UUID? = nil
    @State private var selectedB: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var wheelTarget: Character = "A" // 'A' or 'B'

    @State private var aBrightness: Double
    @State private var bBrightness: Double
    @State private var transitionOn: Bool = false
    @State private var applyWorkItem: DispatchWorkItem? = nil
    @State private var durationHours: Int = 0
    @State private var durationMinutes: Int = 1
    @State private var selectedStartPresetId: UUID?
    @State private var selectedEndPresetId: UUID?
    @State private var isApplyingTransition: Bool = false

    init(
        device: WLEDDevice,
        dismissColorPicker: Binding<Bool>,
        isExpanded: Binding<Bool>,
        onActivate: @escaping () -> Void
    ) {
        self.device = device
        self._dismissColorPicker = dismissColorPicker
        self._isExpanded = isExpanded
        self.onActivate = onActivate
        _aBrightness = State(initialValue: Double(device.brightness))
        _bBrightness = State(initialValue: Double(device.brightness))
        // Initialize gradients immediately in init to avoid main queue dispatch during rendering
        let defaultStartStops = [
            GradientStop(position: 0.0, hexColor: "FFA000"),
            GradientStop(position: 1.0, hexColor: "FFFFFF")
        ]
        let defaultEndStops = [
            GradientStop(position: 0.0, hexColor: "FFFFFF"),
            GradientStop(position: 1.0, hexColor: "FFA000")
        ]
        _gradientA = State(initialValue: LEDGradient(stops: defaultStartStops))
        _stopsA = State(initialValue: defaultStartStops)
        _gradientB = State(initialValue: LEDGradient(stops: defaultEndStops))
        _stopsB = State(initialValue: defaultEndStops)
    }
    // Direct gradient access (no longer lazy)
    private var currentGradientA: LEDGradient {
        gradientA ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFA000"),
            GradientStop(position: 1.0, hexColor: "FFFFFF")
        ])
    }
    
    private var currentGradientB: LEDGradient {
        gradientB ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFFFFF"),
            GradientStop(position: 1.0, hexColor: "FFA000")
        ])
    }
    
    private var durationTotalSeconds: Double {
        Double(max(0, durationHours * 3600 + durationMinutes * 60))
    }
    
    private var allowedMinuteValues: [Int] {
        durationHours >= 24 ? [0] : Array(0...59)
    }
    
    private var colorPresets: [ColorPreset] {
        PresetsStore.shared.colorPresets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Transitions", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                
                // Preset button (only when transitions are ON and expanded)
                if transitionOn && isExpanded {
                    Button(action: {
                        Task {
                            await saveTransitionPresetDirectly()
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
                
                // Transition On/Off Toggle (like EffectsPane)
                Button(action: {
                    if transitionOn {
                        // Turn transitions OFF
                        transitionOn = false
                        isExpanded = false
                        Task { await stopAndRevertTransition() }
                    } else {
                        // Turn transitions ON
                        transitionOn = true
                        isExpanded = true
                        onActivate()
                        // Make B a deep copy of A on first enable
                        if currentGradientB.stops.isEmpty {
                            let copiedStops = currentGradientA.stops.map { GradientStop(position: $0.position, hexColor: $0.hexColor) }
                            stopsB = copiedStops
                            gradientB = LEDGradient(stops: copiedStops)
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: transitionOn ? "power" : "poweroff")
                            .font(.caption)
                        Text(transitionOn ? "ON" : "OFF")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(transitionOn ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(transitionOn ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                }
                
                // Explanatory subtext (only when transitions are off)
                if !transitionOn {
                    Text("Smoothly blend between two color gradients over time")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // Transition Controls
            if transitionOn && isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                    // Duration (hh:mm)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 16) {
                            VStack(spacing: 4) {
                                Text("Hours")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                                Picker("Hours", selection: $durationHours) {
                                    ForEach(0...24, id: \.self) { value in
                                        Text("\(value)")
                                            .tag(value)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 110)
                                .clipped()
                                .accessibilityLabel("Transition hours")
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
                                .accessibilityLabel("Transition minutes")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Start section
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
                                Text("\(Int(round(aBrightness/255.0*100)))%")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Slider(value: $aBrightness, in: 0...255, step: 1)
                                .tint(.white)
                                .accessibilityLabel("Gradient A brightness")
                                .accessibilityValue("\(Int(round(aBrightness/255.0*100))) percent")
                                .accessibilityHint("Controls the brightness of gradient A during transitions.")
                                .accessibilityAdjustableAction { direction in
                                    let step: Double = 12.75
                                    switch direction {
                                    case .increment:
                                        aBrightness = min(255, aBrightness + step)
                                    case .decrement:
                                        aBrightness = max(0, aBrightness - step)
                                    @unknown default:
                                        break
                                    }
                                }
                        }
                        
                        GradientBar(
                            gradient: Binding(
                                get: { currentGradientA },
                                set: { newGradient in
                                    gradientA = newGradient
                                    stopsA = newGradient.stops
                                }
                            ),
                            selectedStopId: $selectedA,
                            onTapStop: { id in
                                wheelTarget = "A"; selectedA = id
                                if let idx = currentGradientA.stops.firstIndex(where: { $0.id == id }) { 
                                    wheelInitial = currentGradientA.stops[idx].color
                                    showWheel = true 
                                }
                            },
                            onTapAnywhere: { t, _ in
                                let c = GradientSampler.sampleColor(at: t, stops: currentGradientA.stops)
                                let new = GradientStop(position: t, hexColor: c.toHex())
                                var updatedStops = currentGradientA.stops
                                updatedStops.append(new)
                                updatedStops.sort { $0.position < $1.position }
                                gradientA = LEDGradient(stops: updatedStops)
                                stopsA = updatedStops
                                selectedA = new.id
                                throttleApply(stops: updatedStops, phase: .changed)
                            },
                            onStopsChanged: { stops, phase in
                                gradientA = LEDGradient(stops: stops)
                                stopsA = stops
                                throttleApply(stops: stops, phase: phase)
                            }
                        )
                        .frame(height: 56)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Start gradient editor")
                        .accessibilityValue("\(currentGradientA.stops.count) color stops")
                        .accessibilityHint("Double tap to adjust colors in the starting gradient.")
                        
                        if !colorPresets.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(colorPresets) { preset in
                                        presetChip(for: preset, target: .start)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Inline color picker for Gradient A
                    if showWheel && wheelTarget == "A", let selectedId = selectedA {
                        let currentStops = currentGradientA.stops
                        let canRemove = currentStops.count > 1
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
                                if let idx = currentGradientA.stops.firstIndex(where: { $0.id == selectedId }) {
                                    var updatedStops = currentGradientA.stops
                                    
                                       // Handle temperature if provided
                                       if let temp = temperature {
                                           // Use shared CCT color calculation utility
                                           updatedStops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                                    } else {
                                        updatedStops[idx].hexColor = color.toHex()
                                    }
                                    
                                    gradientA = LEDGradient(stops: updatedStops)
                                    stopsA = updatedStops
                                    Task { await applyNow(stops: updatedStops) }
                                }
                            },
                            onRemove: {
                                if currentGradientA.stops.count > 1, let id = selectedA {
                                    var updatedStops = currentGradientA.stops
                                    updatedStops.removeAll { $0.id == id }
                                    gradientA = LEDGradient(stops: updatedStops)
                                    stopsA = updatedStops
                                    selectedA = nil
                                    Task { await applyNow(stops: updatedStops) }
                                }
                                showWheel = false
                            },
                            onDismiss: {
                                showWheel = false
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // End section
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
                                Text("\(Int(round(bBrightness/255.0*100)))%")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Slider(value: $bBrightness, in: 0...255, step: 1)
                                .tint(.white)
                                .accessibilityLabel("Gradient B brightness")
                                .accessibilityValue("\(Int(round(bBrightness/255.0*100))) percent")
                                .accessibilityHint("Controls the brightness of gradient B during transitions.")
                                .accessibilityAdjustableAction { direction in
                                    let step: Double = 12.75
                                    switch direction {
                                    case .increment:
                                        bBrightness = min(255, bBrightness + step)
                                    case .decrement:
                                        bBrightness = max(0, bBrightness - step)
                                    @unknown default:
                                        break
                                    }
                                }
                        }
                        
                        GradientBar(
                            gradient: Binding(
                                get: { currentGradientB },
                                set: { newGradient in
                                    gradientB = newGradient
                                    stopsB = newGradient.stops
                                }
                            ),
                            selectedStopId: $selectedB,
                            onTapStop: { id in
                                wheelTarget = "B"; selectedB = id
                                let currentStops = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                if let idx = currentStops.firstIndex(where: { $0.id == id }) {
                                    wheelInitial = currentStops[idx].color
                                    showWheel = true
                                }
                            },
                            onTapAnywhere: { t, _ in
                                var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                let c = GradientSampler.sampleColor(at: t, stops: src)
                                let new = GradientStop(position: t, hexColor: c.toHex())
                                src.append(new)
                                src.sort { $0.position < $1.position }
                                gradientB = LEDGradient(stops: src)
                                stopsB = src
                                selectedB = new.id
                                throttleApplyB(stops: src, phase: .changed)
                            },
                            onStopsChanged: { stops, phase in
                                gradientB = LEDGradient(stops: stops)
                                stopsB = stops
                                throttleApplyB(stops: stops, phase: phase)
                            }
                        )
                        .frame(height: 56)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("End gradient editor")
                        .accessibilityValue("\((currentGradientB.stops.isEmpty ? currentGradientA.stops.count : currentGradientB.stops.count)) color stops")
                        .accessibilityHint("Double tap to adjust colors in the ending gradient.")
                        
                        if !colorPresets.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(colorPresets) { preset in
                                        presetChip(for: preset, target: .end)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Inline color picker for Gradient B
                    if showWheel && wheelTarget == "B", let selectedId = selectedB {
                        let currentStops = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                        let canRemove = currentStops.count > 1
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
                                var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                if let idx = src.firstIndex(where: { $0.id == selectedId }) {
                                       // Handle temperature if provided
                                       if let temp = temperature {
                                           // Use shared CCT color calculation utility
                                           src[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                                    } else {
                                        src[idx].hexColor = color.toHex()
                                    }
                                    
                                    gradientB = LEDGradient(stops: src)
                                    stopsB = src
                                    Task { await applyNowB(stops: src) }
                                }
                            },
                            onRemove: {
                                var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                if src.count > 1, let id = selectedB {
                                    src.removeAll { $0.id == id }
                                    gradientB = LEDGradient(stops: src)
                                    stopsB = src
                                    selectedB = nil
                                    Task { await applyNowB(stops: src) }
                                }
                                showWheel = false
                            },
                            onDismiss: {
                                showWheel = false
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Bottom button: Apply Transition + Cancel affordance
            if transitionOn && isExpanded {
                VStack(spacing: 8) {
                    Button(action: applyTransition) {
                        Group {
                            if isApplyingTransition {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            } else {
                                Text("Apply")
                                    .font(.callout.weight(.semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(height: 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .opacity((durationTotalSeconds <= 0 || isApplyingTransition) ? 0.45 : 1)
                    .accessibilityLabel("Apply transition")
                    .accessibilityHint("Preview the transition using the selected gradients.")
                    .disabled(durationTotalSeconds <= 0 || isApplyingTransition)
                    
                    if isApplyingTransition {
                        Button(action: cancelTransition) {
                            Text("Stop & Cancel")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop and cancel transition")
                        .accessibilityHint("Stops the current transition immediately.")
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            transitionOn = false
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
        .task {
            // Initialize gradients on first appearance
            if let storedDuration = viewModel.transitionDuration(for: device.id) {
                applyIncomingDuration(storedDuration)
            }
            if gradientA == nil {
                gradientA = LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: "FF0000"),
                    GradientStop(position: 1.0, hexColor: "0000FF")
                ])
                stopsA = gradientA?.stops
            }
            if gradientB == nil {
                gradientB = LEDGradient(stops: [])
                stopsB = []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceUpdated"))) { _ in
            if let d = viewModel.devices.first(where: { $0.id == device.id }) {
                aBrightness = Double(d.brightness)
                bBrightness = Double(d.brightness)
            }
        }
        .onChange(of: viewModel.latestTransitionDurations[device.id]) { _, newValue in
            if let value = newValue {
                applyIncomingDuration(value)
            }
        }
        .onChange(of: dismissColorPicker) { _, newValue in
            if newValue {
                showWheel = false
            }
        }
        .onChange(of: durationHours) { _, newValue in
            if newValue >= 24 {
                if durationHours != 24 {
                    durationHours = 24
                }
                if durationMinutes != 0 {
                    durationMinutes = 0
                }
            }
            persistDurationSelection()
        }
        .onChange(of: durationMinutes) { _, newValue in
            if durationHours >= 24 && newValue != 0 {
                durationMinutes = 0
            }
            persistDurationSelection()
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded && transitionOn {
                transitionOn = false
                Task { await stopAndRevertTransition() }
            }
        }
    }

    private func applyIncomingDuration(_ seconds: Double) {
        let clamped = max(0, min(seconds, 24 * 3600))
        var hours = Int(clamped) / 3600
        var minutes = (Int(clamped) % 3600) / 60
        if clamped > 0, hours == 0, minutes == 0 {
            minutes = 1
        }
        if hours >= 24 {
            hours = 24
            minutes = 0
        }
        durationHours = hours
        durationMinutes = minutes
    }
    
    private func persistDurationSelection() {
        viewModel.setTransitionDuration(durationTotalSeconds, for: device.id)
    }

    private enum PresetTarget {
        case start
        case end
    }

    @ViewBuilder
    private func presetChip(for preset: ColorPreset, target: PresetTarget) -> some View {
        let isSelected = target == .start ? selectedStartPresetId == preset.id : selectedEndPresetId == preset.id
        Button(action: {
            applyPreset(preset, to: target)
        }) {
            Text(preset.name)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(isSelected ? 0.95 : 0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.22 : 0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) preset")
        .accessibilityHint(target == .start ? "Apply to start gradient" : "Apply to end gradient")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func applyPreset(_ preset: ColorPreset, to target: PresetTarget) {
        let sortedStops = preset.gradientStops
            .sorted { $0.position < $1.position }
        switch target {
        case .start:
            selectedStartPresetId = preset.id
            gradientA = LEDGradient(stops: sortedStops)
            stopsA = sortedStops
            aBrightness = Double(preset.brightness)
            Task { await applyNow(stops: sortedStops) }
        case .end:
            selectedEndPresetId = preset.id
            gradientB = LEDGradient(stops: sortedStops)
            stopsB = sortedStops
            bBrightness = Double(preset.brightness)
            Task { await applyNowB(stops: sortedStops) }
        }
    }

    private func throttleApply(stops: [GradientStop], phase: DragPhase) {
        let applyTask = {
            Task {
                await viewModel.applyGradientStopsAcrossStrip(device, stops: stops)
            }
        }
        if phase == .changed {
            applyWorkItem?.cancel()
            let work = DispatchWorkItem {
                applyTask()
            }
            applyWorkItem = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                work.perform()
            }
        } else {
            applyTask()
        }
    }
    
    // Separate work item for Gradient B to avoid conflicts
    @State private var applyWorkItemB: DispatchWorkItem? = nil
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    
    private func throttleApplyB(stops: [GradientStop], phase: DragPhase) {
        let applyTask = {
            Task {
                await viewModel.applyGradientStopsAcrossStrip(device, stops: stops)
            }
        }
        if phase == .changed {
            applyWorkItemB?.cancel()
            let work = DispatchWorkItem {
                applyTask()
            }
            applyWorkItemB = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                work.perform()
            }
        } else {
            applyTask()
        }
    }

    private func applyNow(stops: [GradientStop]) async {
        if stops.count == 1 {
            await viewModel.updateDeviceColor(device, color: stops[0].color)
        } else {
            await viewModel.applyGradientStopsAcrossStrip(device, stops: stops)
        }
    }
    
    private func applyNowB(stops: [GradientStop]) async {
        if stops.count == 1 {
            await viewModel.updateDeviceColor(device, color: stops[0].color)
        } else {
            await viewModel.applyGradientStopsAcrossStrip(device, stops: stops)
        }
    }
    
    private func stopAndRevertTransition() async {
        await viewModel.stopTransitionAndRevertToA(device: device)
        let stops = await MainActor.run { currentGradientA.stops }
        await viewModel.applyGradientStopsAcrossStrip(device, stops: stops)
    }
    
    private func applyTransition() {
        guard !isApplyingTransition else { return }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        isApplyingTransition = true
        
        Task {
            await viewModel.cancelActiveTransitionIfNeeded(for: device)
            try? await Task.sleep(nanoseconds: 120_000_000)
            
            let input = await MainActor.run { () -> (LEDGradient, LEDGradient, Int, Int, Double) in
                let startGradient = currentGradientA
                let endGradient = currentGradientB.stops.isEmpty ? currentGradientA : currentGradientB
                let startBrightness = Int(aBrightness)
                let endBrightness = Int(bBrightness)
                let duration = durationTotalSeconds
                return (startGradient, endGradient, startBrightness, endBrightness, duration)
            }
            
            let (startGradient, endGradient, startBrightness, endBrightness, duration) = input
            
            await viewModel.startTransition(
                from: startGradient,
                aBrightness: startBrightness,
                to: endGradient,
                bBrightness: endBrightness,
                durationSec: duration,
                device: device
            )
            
            await MainActor.run {
                isApplyingTransition = false
            }
        }
    }
    
    private func cancelTransition() {
        guard isApplyingTransition else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            await viewModel.cancelActiveTransitionIfNeeded(for: device)
            await MainActor.run {
                isApplyingTransition = false
            }
        }
    }
}

private extension TransitionPane {
    var backgroundFill: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 0.12 : 0.06)
    }
    
    // MARK: - Direct Preset Saving
    
    func saveTransitionPresetDirectly() async {
        await MainActor.run {
            isSavingPreset = true
            showSaveSuccess = false
        }
        
        let presetName = "Transition \(Date().formatted(date: .omitted, time: .shortened))"
        let gB = currentGradientB.stops.isEmpty ? currentGradientA : currentGradientB
        let duration = durationTotalSeconds
        var preset = TransitionPreset(
            name: presetName,
            deviceId: device.id,
            gradientA: currentGradientA,
            brightnessA: Int(aBrightness),
            gradientB: gB,
            brightnessB: Int(bBrightness),
            durationSec: duration
        )
        
        // STEP 1: Save locally FIRST (immediate feedback, works even if WLED is offline)
        await MainActor.run {
            PresetsStore.shared.addTransitionPreset(preset)
            isSavingPreset = false
            showSaveSuccess = true
            
            // Hide success indicator after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    showSaveSuccess = false
                }
            }
        }
        
        // STEP 2: Try to sync to WLED device in background (non-blocking)
        Task.detached(priority: .background) {
            do {
                let apiService = WLEDAPIService.shared
                let existingPlaylists = try await apiService.fetchPlaylists(for: device)
                let usedIds = Set(existingPlaylists.map { $0.id })
                let playlistId = (1...16).first { !usedIds.contains($0) } ?? 1
                
                let savedId = try await apiService.saveTransitionPreset(preset, to: device, playlistId: playlistId)
                
                // Update local preset with WLED ID if sync succeeded
                await MainActor.run {
                    preset.wledPlaylistId = savedId
                    PresetsStore.shared.updateTransitionPreset(preset)
                }
                
                #if DEBUG
                print("✅ Transition preset synced to WLED device: Playlist ID \(savedId)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ Failed to sync transition preset to WLED (saved locally): \(error.localizedDescription)")
                #endif
                // Preset is still saved locally, just not synced to WLED
            }
        }
    }
}
