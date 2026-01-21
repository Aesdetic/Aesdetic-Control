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
    @State private var stopTemperaturesA: [UUID: Double] = [:]
    @State private var stopTemperaturesB: [UUID: Double] = [:]
    @State private var stopWhiteLevelsA: [UUID: Double] = [:]
    @State private var stopWhiteLevelsB: [UUID: Double] = [:]
    
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
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false

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

    private var endInterpolation: GradientInterpolation {
        currentGradientB.stops.isEmpty ? currentGradientA.interpolation : currentGradientB.interpolation
    }

    private var activeTransitionId: UUID? {
        guard let status = viewModel.activeRunStatus[device.id], status.kind == .transition else {
            return nil
        }
        return status.id
    }
    
    private var durationTotalSeconds: Double {
        Double(max(0, durationHours * 3600 + durationMinutes * 60))
    }

    private var isTransitionActive: Bool {
        transitionOn && isExpanded
    }

    private var isApplyDisabled: Bool {
        durationTotalSeconds <= 0 || isApplyingTransition
    }
    
    private var allowedMinuteValues: [Int] {
        durationHours >= 24 ? [0] : Array(0...59)
    }
    
    private var colorPresets: [ColorPreset] {
        PresetsStore.shared.colorPresets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            // Transition Controls
            if isTransitionActive {
                transitionControls
            }
            
            // Bottom button: Apply Transition + Cancel affordance
            if isTransitionActive {
                applySection
            }
        }
        .onAppear {
            if activeTransitionId == nil {
                transitionOn = false
            }
        }
        .onChange(of: activeTransitionId) { _, newValue in
            isApplyingTransition = newValue != nil
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

    private func blendSelector(
        title: String,
        selection: GradientInterpolation,
        onSelect: @escaping (GradientInterpolation) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GradientInterpolation.allCases, id: \.self) { mode in
                        Button(action: { onSelect(mode) }) {
                            Text(mode.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundColor(selection == mode ? .black : .white.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selection == mode ? Color.white : Color.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 2)
    }

    private func applyPreset(_ preset: ColorPreset, to target: PresetTarget) {
        let sortedStops = preset.gradientStops
            .sorted { $0.position < $1.position }
        let interpolation = preset.gradientInterpolation ?? (target == .start ? currentGradientA.interpolation : endInterpolation)
        let temperatureMap = preset.temperature.map { temp in
            Dictionary(uniqueKeysWithValues: sortedStops.map { ($0.id, temp) })
        } ?? [:]
        let whiteMap = preset.whiteLevel.map { white in
            Dictionary(uniqueKeysWithValues: sortedStops.map { ($0.id, white) })
        } ?? [:]
        switch target {
        case .start:
            selectedStartPresetId = preset.id
            gradientA = LEDGradient(stops: sortedStops, interpolation: interpolation)
            stopsA = sortedStops
            stopTemperaturesA = temperatureMap
            stopWhiteLevelsA = whiteMap
            aBrightness = Double(preset.brightness)
            Task { await applyNow(stops: sortedStops, interpolation: interpolation) }
        case .end:
            selectedEndPresetId = preset.id
            gradientB = LEDGradient(stops: sortedStops, interpolation: interpolation)
            stopsB = sortedStops
            stopTemperaturesB = temperatureMap
            stopWhiteLevelsB = whiteMap
            bBrightness = Double(preset.brightness)
            Task { await applyNowB(stops: sortedStops, interpolation: interpolation) }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Transitions", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()

                if isTransitionActive {
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

                Button(action: {
                    if transitionOn {
                        transitionOn = false
                        isExpanded = false
                        Task { await stopAndRevertTransition() }
                    } else {
                        transitionOn = true
                        isExpanded = true
                        onActivate()
                        if currentGradientB.stops.isEmpty {
                            let copiedStops = currentGradientA.stops.map {
                                GradientStop(position: $0.position, hexColor: $0.hexColor)
                            }
                            stopsB = copiedStops
                            gradientB = LEDGradient(stops: copiedStops, interpolation: currentGradientA.interpolation)
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

            if !transitionOn {
                Text("Smoothly blend between two color gradients over time")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var transitionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            durationSection
            startSection
            startColorPicker
            endSection
            endColorPicker
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var durationSection: some View {
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
    }

    @ViewBuilder
    private var startSection: some View {
        let brightnessPercent = Int(round(aBrightness / 255.0 * 100))
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
                    Text("\(brightnessPercent)%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Slider(value: $aBrightness, in: 0...255, step: 1)
                    .tint(.white)
                    .accessibilityLabel("Gradient A brightness")
                    .accessibilityValue("\(brightnessPercent) percent")
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
                    wheelTarget = "A"
                    selectedA = id
                    if let idx = currentGradientA.stops.firstIndex(where: { $0.id == id }) {
                        wheelInitial = currentGradientA.stops[idx].color
                        showWheel = true
                    }
                },
                onTapAnywhere: { t, _ in
                    let c = GradientSampler.sampleColor(
                        at: t,
                        stops: currentGradientA.stops,
                        interpolation: currentGradientA.interpolation
                    )
                    let new = GradientStop(position: t, hexColor: c.toHex())
                    var updatedStops = currentGradientA.stops
                    updatedStops.append(new)
                    updatedStops.sort { $0.position < $1.position }

                    if !stopTemperaturesA.isEmpty {
                        if let newIndex = updatedStops.firstIndex(where: { $0.id == new.id }) {
                            var nearestTemp: Double? = nil
                            var minDistance: Double = Double.greatestFiniteMagnitude
                            for (idx, stop) in updatedStops.enumerated() {
                                if idx != newIndex, let temp = stopTemperaturesA[stop.id] {
                                    let distance = abs(stop.position - new.position)
                                    if distance < minDistance {
                                        minDistance = distance
                                        nearestTemp = temp
                                    }
                                }
                            }
                            if let inheritedTemp = nearestTemp {
                                stopTemperaturesA[new.id] = inheritedTemp
                            }
                        }
                    }

                    if !stopWhiteLevelsA.isEmpty {
                        if let newIndex = updatedStops.firstIndex(where: { $0.id == new.id }) {
                            var nearestWhite: Double? = nil
                            var minDistance: Double = Double.greatestFiniteMagnitude
                            for (idx, stop) in updatedStops.enumerated() {
                                if idx != newIndex, let white = stopWhiteLevelsA[stop.id] {
                                    let distance = abs(stop.position - new.position)
                                    if distance < minDistance {
                                        minDistance = distance
                                        nearestWhite = white
                                    }
                                }
                            }
                            if let inheritedWhite = nearestWhite {
                                stopWhiteLevelsA[new.id] = inheritedWhite
                            }
                        }
                    }

                    gradientA = LEDGradient(stops: updatedStops, interpolation: currentGradientA.interpolation)
                    stopsA = updatedStops
                    selectedA = new.id
                    throttleApply(stops: updatedStops, phase: .changed)
                },
                onStopsChanged: { stops, phase in
                    gradientA = LEDGradient(stops: stops, interpolation: currentGradientA.interpolation)
                    stopsA = stops
                    let stopIds = Set(stops.map { $0.id })
                    stopTemperaturesA = stopTemperaturesA.filter { stopIds.contains($0.key) }
                    stopWhiteLevelsA = stopWhiteLevelsA.filter { stopIds.contains($0.key) }
                    throttleApply(stops: stops, phase: phase)
                }
            )
            .frame(height: 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Start gradient editor")
            .accessibilityValue("\(currentGradientA.stops.count) color stops")
            .accessibilityHint("Double tap to adjust colors in the starting gradient.")

            if advancedUIEnabled && currentGradientA.stops.count >= 2 {
                blendSelector(
                    title: "Blend Style",
                    selection: currentGradientA.interpolation
                ) { mode in
                    var updated = currentGradientA
                    updated.interpolation = mode
                    gradientA = updated
                    stopsA = updated.stops
                    Task { await applyNow(stops: updated.stops, interpolation: updated.interpolation) }
                }
            }

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
    }

    @ViewBuilder
    private var startColorPicker: some View {
        if showWheel && wheelTarget == "A", let selectedId = selectedA {
            let currentStops = currentGradientA.stops
            let canRemove = currentStops.count > 1
            let supportsCCT = viewModel.supportsCCT(for: device, segmentId: 0)
            let supportsWhite = viewModel.supportsWhite(for: device, segmentId: 0)
            let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: 0)

            ColorWheelInline(
                initialColor: wheelInitial,
                initialTemperature: stopTemperaturesA[selectedId],
                initialWhiteLevel: stopWhiteLevelsA[selectedId],
                canRemove: canRemove,
                supportsCCT: supportsCCT,
                supportsWhite: supportsWhite,
                usesKelvinCCT: usesKelvin,
                allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device),
                allowManualWhite: advancedUIEnabled,
                cctKelvinRange: viewModel.cctKelvinRange(for: device),
                onColorChange: { color, temperature, whiteLevel in
                    if let idx = currentGradientA.stops.firstIndex(where: { $0.id == selectedId }) {
                        var updatedStops = currentGradientA.stops
                        if let temp = temperature {
                            updatedStops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                            stopTemperaturesA[selectedId] = temp
                            if let white = whiteLevel {
                                stopWhiteLevelsA[selectedId] = white
                            } else {
                                stopWhiteLevelsA.removeValue(forKey: selectedId)
                            }
                        } else {
                            updatedStops[idx].hexColor = color.toHex()
                            stopTemperaturesA.removeValue(forKey: selectedId)
                            if let white = whiteLevel {
                                stopWhiteLevelsA[selectedId] = white
                            } else {
                                stopWhiteLevelsA.removeValue(forKey: selectedId)
                            }
                        }
                        gradientA = LEDGradient(stops: updatedStops, interpolation: currentGradientA.interpolation)
                        stopsA = updatedStops
                        Task { await applyNow(stops: updatedStops, interpolation: currentGradientA.interpolation) }
                    }
                },
                onRemove: {
                    if currentGradientA.stops.count > 1, let id = selectedA {
                        var updatedStops = currentGradientA.stops
                        updatedStops.removeAll { $0.id == id }
                        gradientA = LEDGradient(stops: updatedStops, interpolation: currentGradientA.interpolation)
                        stopsA = updatedStops
                        stopTemperaturesA.removeValue(forKey: id)
                        stopWhiteLevelsA.removeValue(forKey: id)
                        selectedA = nil
                        Task { await applyNow(stops: updatedStops, interpolation: currentGradientA.interpolation) }
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

    @ViewBuilder
    private var endSection: some View {
        let brightnessPercent = Int(round(bBrightness / 255.0 * 100))
        let endStopsCount = currentGradientB.stops.isEmpty ? currentGradientA.stops.count : currentGradientB.stops.count
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
                    Text("\(brightnessPercent)%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Slider(value: $bBrightness, in: 0...255, step: 1)
                    .tint(.white)
                    .accessibilityLabel("Gradient B brightness")
                    .accessibilityValue("\(brightnessPercent) percent")
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
                    wheelTarget = "B"
                    selectedB = id
                    let currentStops = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                    if let idx = currentStops.firstIndex(where: { $0.id == id }) {
                        wheelInitial = currentStops[idx].color
                        showWheel = true
                    }
                },
                onTapAnywhere: { t, _ in
                    var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                    let c = GradientSampler.sampleColor(
                        at: t,
                        stops: src,
                        interpolation: endInterpolation
                    )
                    let new = GradientStop(position: t, hexColor: c.toHex())
                    src.append(new)
                    src.sort { $0.position < $1.position }

                    if !stopTemperaturesB.isEmpty {
                        if let newIndex = src.firstIndex(where: { $0.id == new.id }) {
                            var nearestTemp: Double? = nil
                            var minDistance: Double = Double.greatestFiniteMagnitude
                            for (idx, stop) in src.enumerated() {
                                if idx != newIndex, let temp = stopTemperaturesB[stop.id] {
                                    let distance = abs(stop.position - new.position)
                                    if distance < minDistance {
                                        minDistance = distance
                                        nearestTemp = temp
                                    }
                                }
                            }
                            if let inheritedTemp = nearestTemp {
                                stopTemperaturesB[new.id] = inheritedTemp
                            }
                        }
                    }

                    if !stopWhiteLevelsB.isEmpty {
                        if let newIndex = src.firstIndex(where: { $0.id == new.id }) {
                            var nearestWhite: Double? = nil
                            var minDistance: Double = Double.greatestFiniteMagnitude
                            for (idx, stop) in src.enumerated() {
                                if idx != newIndex, let white = stopWhiteLevelsB[stop.id] {
                                    let distance = abs(stop.position - new.position)
                                    if distance < minDistance {
                                        minDistance = distance
                                        nearestWhite = white
                                    }
                                }
                            }
                            if let inheritedWhite = nearestWhite {
                                stopWhiteLevelsB[new.id] = inheritedWhite
                            }
                        }
                    }

                    gradientB = LEDGradient(stops: src, interpolation: endInterpolation)
                    stopsB = src
                    selectedB = new.id
                    throttleApplyB(stops: src, phase: .changed)
                },
                onStopsChanged: { stops, phase in
                    gradientB = LEDGradient(stops: stops, interpolation: endInterpolation)
                    stopsB = stops
                    let stopIds = Set(stops.map { $0.id })
                    stopTemperaturesB = stopTemperaturesB.filter { stopIds.contains($0.key) }
                    stopWhiteLevelsB = stopWhiteLevelsB.filter { stopIds.contains($0.key) }
                    throttleApplyB(stops: stops, phase: phase)
                }
            )
            .frame(height: 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("End gradient editor")
            .accessibilityValue("\(endStopsCount) color stops")
            .accessibilityHint("Double tap to adjust colors in the ending gradient.")

            if advancedUIEnabled && endStopsCount >= 2 {
                blendSelector(
                    title: "Blend Style",
                    selection: endInterpolation
                ) { mode in
                    var updated = currentGradientB.stops.isEmpty ? currentGradientA : currentGradientB
                    updated.interpolation = mode
                    gradientB = updated
                    stopsB = updated.stops
                    Task { await applyNowB(stops: updated.stops, interpolation: updated.interpolation) }
                }
            }

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
    }

    @ViewBuilder
    private var endColorPicker: some View {
        if showWheel && wheelTarget == "B", let selectedId = selectedB {
            let currentStops = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
            let canRemove = currentStops.count > 1
            let supportsCCT = viewModel.supportsCCT(for: device, segmentId: 0)
            let supportsWhite = viewModel.supportsWhite(for: device, segmentId: 0)
            let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: 0)

            ColorWheelInline(
                initialColor: wheelInitial,
                initialTemperature: stopTemperaturesB[selectedId],
                initialWhiteLevel: stopWhiteLevelsB[selectedId],
                canRemove: canRemove,
                supportsCCT: supportsCCT,
                supportsWhite: supportsWhite,
                usesKelvinCCT: usesKelvin,
                allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device),
                allowManualWhite: advancedUIEnabled,
                cctKelvinRange: viewModel.cctKelvinRange(for: device),
                onColorChange: { color, temperature, whiteLevel in
                    var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                    if let idx = src.firstIndex(where: { $0.id == selectedId }) {
                        if let temp = temperature {
                            src[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                            stopTemperaturesB[selectedId] = temp
                            if let white = whiteLevel {
                                stopWhiteLevelsB[selectedId] = white
                            } else {
                                stopWhiteLevelsB.removeValue(forKey: selectedId)
                            }
                        } else {
                            src[idx].hexColor = color.toHex()
                            stopTemperaturesB.removeValue(forKey: selectedId)
                            if let white = whiteLevel {
                                stopWhiteLevelsB[selectedId] = white
                            } else {
                                stopWhiteLevelsB.removeValue(forKey: selectedId)
                            }
                        }
                        gradientB = LEDGradient(stops: src, interpolation: endInterpolation)
                        stopsB = src
                        Task { await applyNowB(stops: src, interpolation: endInterpolation) }
                    }
                },
                onRemove: {
                    var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                    if src.count > 1, let id = selectedB {
                        src.removeAll { $0.id == id }
                        gradientB = LEDGradient(stops: src, interpolation: endInterpolation)
                        stopsB = src
                        stopTemperaturesB.removeValue(forKey: id)
                        stopWhiteLevelsB.removeValue(forKey: id)
                        selectedB = nil
                        Task { await applyNowB(stops: src, interpolation: endInterpolation) }
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

    @ViewBuilder
    private var applySection: some View {
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
            .opacity(isApplyDisabled ? 0.45 : 1)
            .accessibilityLabel("Apply transition")
            .accessibilityHint("Preview the transition using the selected gradients.")
            .disabled(isApplyDisabled)
        }
        .transition(.opacity)
    }

    private func throttleApply(stops: [GradientStop], phase: DragPhase) {
        if isApplyingTransition {
            return
        }
        let ledCount = viewModel.totalLEDCount(for: device)
        let interpolation = currentGradientA.interpolation
        if phase == .changed {
            applyWorkItem?.cancel()
            let work = DispatchWorkItem {
                Task {
                    await viewModel.applyGradientStopsAcrossStrip(
                        device,
                        stops: stops,
                        ledCount: ledCount,
                        stopTemperatures: stopTemperaturesA.isEmpty ? nil : stopTemperaturesA,
                        stopWhiteLevels: stopWhiteLevelsA.isEmpty ? nil : stopWhiteLevelsA,
                        interpolation: interpolation,
                        preferSegmented: true
                    )
                }
            }
            applyWorkItem = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !work.isCancelled else { return }
                work.perform()
            }
        } else {
            Task {
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: stops,
                    ledCount: ledCount,
                    stopTemperatures: stopTemperaturesA.isEmpty ? nil : stopTemperaturesA,
                    stopWhiteLevels: stopWhiteLevelsA.isEmpty ? nil : stopWhiteLevelsA,
                    interpolation: interpolation,
                    preferSegmented: true
                )
            }
        }
    }
    
    // Separate work item for Gradient B to avoid conflicts
    @State private var applyWorkItemB: DispatchWorkItem? = nil
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    
    private func throttleApplyB(stops: [GradientStop], phase: DragPhase) {
        if isApplyingTransition {
            return
        }
        let ledCount = viewModel.totalLEDCount(for: device)
        let interpolation = endInterpolation
        if phase == .changed {
            applyWorkItemB?.cancel()
            let work = DispatchWorkItem {
                Task {
                    await viewModel.applyGradientStopsAcrossStrip(
                        device,
                        stops: stops,
                        ledCount: ledCount,
                        stopTemperatures: stopTemperaturesB.isEmpty ? nil : stopTemperaturesB,
                        stopWhiteLevels: stopWhiteLevelsB.isEmpty ? nil : stopWhiteLevelsB,
                        interpolation: interpolation,
                        preferSegmented: true
                    )
                }
            }
            applyWorkItemB = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !work.isCancelled else { return }
                work.perform()
            }
        } else {
            Task {
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: stops,
                    ledCount: ledCount,
                    stopTemperatures: stopTemperaturesB.isEmpty ? nil : stopTemperaturesB,
                    stopWhiteLevels: stopWhiteLevelsB.isEmpty ? nil : stopWhiteLevelsB,
                    interpolation: interpolation,
                    preferSegmented: true
                )
            }
        }
    }

    private func applyNow(stops: [GradientStop], interpolation: GradientInterpolation) async {
        if isApplyingTransition {
            return
        }
        let ledCount = viewModel.totalLEDCount(for: device)
        let tempMap = stopTemperaturesA.isEmpty ? nil : stopTemperaturesA
        let whiteMap = stopWhiteLevelsA.isEmpty ? nil : stopWhiteLevelsA
        if stops.count == 1 && tempMap == nil && whiteMap == nil {
            await viewModel.updateDeviceColor(device, color: stops[0].color)
            return
        }
        await viewModel.applyGradientStopsAcrossStrip(
            device,
            stops: stops,
            ledCount: ledCount,
            stopTemperatures: tempMap,
            stopWhiteLevels: whiteMap,
            interpolation: interpolation,
            preferSegmented: true
        )
    }
    
    private func applyNowB(stops: [GradientStop], interpolation: GradientInterpolation) async {
        if isApplyingTransition {
            return
        }
        let ledCount = viewModel.totalLEDCount(for: device)
        let tempMap = stopTemperaturesB.isEmpty ? nil : stopTemperaturesB
        let whiteMap = stopWhiteLevelsB.isEmpty ? nil : stopWhiteLevelsB
        if stops.count == 1 && tempMap == nil && whiteMap == nil {
            await viewModel.updateDeviceColor(device, color: stops[0].color)
            return
        }
        await viewModel.applyGradientStopsAcrossStrip(
            device,
            stops: stops,
            ledCount: ledCount,
            stopTemperatures: tempMap,
            stopWhiteLevels: whiteMap,
            interpolation: interpolation,
            preferSegmented: true
        )
    }
    
    private func stopAndRevertTransition() async {
        await viewModel.stopTransitionAndRevertToA(device: device)
        let output = await MainActor.run { () -> ([GradientStop], Int) in
            let stops = currentGradientA.stops
            let count = viewModel.totalLEDCount(for: device)
            return (stops, count)
        }
        await viewModel.applyGradientStopsAcrossStrip(
            device,
            stops: output.0,
            ledCount: output.1,
            stopTemperatures: stopTemperaturesA.isEmpty ? nil : stopTemperaturesA,
            stopWhiteLevels: stopWhiteLevelsA.isEmpty ? nil : stopWhiteLevelsA,
            preferSegmented: true
        )
    }
    
    private func applyTransition() {
        guard !isApplyingTransition, durationTotalSeconds > 0 else { return }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        isApplyingTransition = true
        applyWorkItem?.cancel()
        applyWorkItem = nil
        applyWorkItemB?.cancel()
        applyWorkItemB = nil
        
        Task {
            let hasActiveRun = await MainActor.run {
                viewModel.activeRunStatus[device.id] != nil
            }
            if hasActiveRun {
                await viewModel.cancelActiveRun(for: device, force: true)
                try? await Task.sleep(nanoseconds: 200_000_000)
            } else {
                await viewModel.cancelActiveTransitionIfNeeded(for: device)
            }
            
            let input = await MainActor.run { () -> (LEDGradient, LEDGradient, Int, Int, Double, [UUID: Double]?, [UUID: Double]?, [UUID: Double]?, [UUID: Double]?) in
                let startGradient = currentGradientA
                let endGradient = currentGradientB.stops.isEmpty ? currentGradientA : currentGradientB
                let startBrightness = Int(aBrightness)
                let endBrightness = Int(bBrightness)
                let duration = durationTotalSeconds
                let startTemps = stopTemperaturesA.isEmpty ? nil : stopTemperaturesA
                let startWhites = stopWhiteLevelsA.isEmpty ? nil : stopWhiteLevelsA
                let resolvedEndTemps = stopTemperaturesB.isEmpty ? startTemps : stopTemperaturesB
                let resolvedEndWhites = stopWhiteLevelsB.isEmpty ? startWhites : stopWhiteLevelsB
                return (startGradient, endGradient, startBrightness, endBrightness, duration, startTemps, startWhites, resolvedEndTemps, resolvedEndWhites)
            }
            
            let (startGradient, endGradient, startBrightness, endBrightness, duration, startTemps, startWhites, endTemps, endWhites) = input
            
            await viewModel.startTransition(
                from: startGradient,
                aBrightness: startBrightness,
                to: endGradient,
                bBrightness: endBrightness,
                durationSec: duration,
                device: device,
                startStopTemperatures: startTemps,
                startStopWhiteLevels: startWhites,
                endStopTemperatures: endTemps,
                endStopWhiteLevels: endWhites
            )
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
        let resolvedTempB = stopTemperaturesB.values.first ?? stopTemperaturesA.values.first
        let resolvedWhiteB = stopWhiteLevelsB.values.first ?? stopWhiteLevelsA.values.first
        let duration = durationTotalSeconds
        var preset = TransitionPreset(
            name: presetName,
            deviceId: device.id,
            gradientA: currentGradientA,
            brightnessA: Int(aBrightness),
            temperatureA: stopTemperaturesA.values.first,
            whiteLevelA: stopWhiteLevelsA.values.first,
            gradientB: gB,
            brightnessB: Int(bBrightness),
            temperatureB: resolvedTempB,
            whiteLevelB: resolvedWhiteB,
            durationSec: duration
        )

        if let result = await viewModel.saveTransitionPresetToDevice(preset, device: device) {
            await MainActor.run {
                preset.wledPlaylistId = result.playlistId
                preset.wledStepPresetIds = result.stepPresetIds
                PresetsStore.shared.addTransitionPreset(preset)
                isSavingPreset = false
                showSaveSuccess = true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showSaveSuccess = false
            }
            #if DEBUG
            print("✅ Transition preset saved to WLED device: Playlist ID \(result.playlistId)")
            #endif
        } else {
            await MainActor.run {
                isSavingPreset = false
                showSaveSuccess = false
            }
            #if DEBUG
            print("⚠️ Failed to save transition preset to WLED: playlist build failed")
            #endif
        }
    }
}
