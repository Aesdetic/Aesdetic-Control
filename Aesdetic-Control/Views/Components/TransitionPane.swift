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
    @State private var durationMinutesPart: Int = 1
    @State private var durationSecondsPart: Int = 0
    @State private var selectedStartPresetId: UUID?
    @State private var selectedEndPresetId: UUID?
    @State private var isApplyingTransition: Bool = false
    @State private var isCancellingTransition: Bool = false
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @AppStorage("perLedTransitionsEnabled") private var perLedTransitionsEnabled: Bool = false

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

    private var hasActiveTransitionRun: Bool {
        activeTransitionId != nil
    }
    
    private var durationTotalSeconds: Double {
        Double(transitionPickerDurationSeconds())
    }

    private var isTransitionActive: Bool {
        transitionOn && isExpanded
    }

    private var isTransitionLoading: Bool {
        guard let status = viewModel.activeRunStatus[device.id], status.kind == .transition else {
            return viewModel.presetWriteInProgress.contains(device.id)
        }
        return status.title == "Loading..." || viewModel.presetWriteInProgress.contains(device.id)
    }

    private var isPresetButtonDisabled: Bool {
        isSavingPreset || viewModel.isTransitionPresetButtonDisabled(for: device.id)
    }

    private var isApplyDisabled: Bool {
        durationTotalSeconds <= 0
            || isApplyingTransition
            || viewModel.isTransitionCleanupInProgress(for: device.id)
    }

    private var isCancelDisabled: Bool {
        isCancellingTransition
            || viewModel.isTransitionCleanupInProgress(for: device.id)
    }

    private var preferSegmentedUpdates: Bool {
        !(advancedUIEnabled && perLedTransitionsEnabled)
    }
    
    private var allowedSecondValues: [Int] {
        durationMinutesPart >= 60 ? [0] : Array(0...59)
    }

    private var selectedDurationSeconds: Int {
        transitionPickerDurationSeconds()
    }

    private var transitionExceedsRecommendedMax: Bool {
        TransitionDurationPicker.exceedsRecommendedMax(Double(selectedDurationSeconds))
    }
    
    private var colorPresets: [ColorPreset] {
        PresetsStore.shared.colorPresets
    }

    var body: some View {
        let base = paneCardContent
        let runtimeBound = applyRuntimeModifiers(to: base)
        applyDraftPersistenceModifiers(to: runtimeBound)
    }

    @ViewBuilder
    private var paneCardContent: some View {
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
    }

    @ViewBuilder
    private func applyRuntimeModifiers<Content: View>(to content: Content) -> some View {
        content
        .onAppear {
            restoreDraftSessionIfAvailable()
            if activeTransitionId != nil || isSavingPreset {
                transitionOn = true
                isExpanded = true
            } else if activeTransitionId == nil, !transitionOn {
                transitionOn = false
            }
            persistDraftSession()
        }
        .onDisappear {
            persistDraftSession()
        }
        .onChange(of: activeTransitionId) { _, newValue in
            isApplyingTransition = newValue != nil
            if newValue == nil {
                isCancellingTransition = false
            }
            if newValue != nil {
                transitionOn = true
                isExpanded = true
            }
            persistDraftSession()
        }
        .task {
            // Initialize gradients on first appearance
            await viewModel.refreshTransitionCleanupPendingCount(for: device.id)
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
        .task(id: device.id) {
            while !Task.isCancelled {
                await viewModel.refreshTransitionCleanupPendingCount(for: device.id)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
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
    }

    @ViewBuilder
    private func applyDraftPersistenceModifiers<Content: View>(to content: Content) -> some View {
        content
        .onChange(of: durationMinutesPart) { _, _ in
            if durationMinutesPart > 60 {
                durationMinutesPart = 60
            }
            if durationMinutesPart < 0 {
                durationMinutesPart = 0
            }
            if durationMinutesPart == 60, durationSecondsPart != 0 {
                durationSecondsPart = 0
            }
            persistDurationSelection()
            persistDraftSession()
        }
        .onChange(of: durationSecondsPart) { _, _ in
            if durationMinutesPart == 60, durationSecondsPart != 0 {
                durationSecondsPart = 0
            }
            if durationSecondsPart < 0 {
                durationSecondsPart = 0
            }
            if durationSecondsPart > 59 {
                durationSecondsPart = 59
            }
            persistDurationSelection()
            persistDraftSession()
        }
        .onChange(of: isExpanded) { _, expanded in
            // UI-only: pane collapse (including tab switches/view recreation) must not stop transitions.
            persistDraftSession()
        }
        .onChange(of: transitionOn) { _, _ in persistDraftSession() }
        .onChange(of: gradientA) { _, _ in persistDraftSession() }
        .onChange(of: gradientB) { _, _ in persistDraftSession() }
        .onChange(of: stopTemperaturesA) { _, _ in persistDraftSession() }
        .onChange(of: stopTemperaturesB) { _, _ in persistDraftSession() }
        .onChange(of: stopWhiteLevelsA) { _, _ in persistDraftSession() }
        .onChange(of: stopWhiteLevelsB) { _, _ in persistDraftSession() }
        .onChange(of: aBrightness) { _, _ in persistDraftSession() }
        .onChange(of: bBrightness) { _, _ in persistDraftSession() }
        .onChange(of: selectedStartPresetId) { _, _ in persistDraftSession() }
        .onChange(of: selectedEndPresetId) { _, _ in persistDraftSession() }
        .onChange(of: isSavingPreset) { _, _ in persistDraftSession() }
        .onChange(of: showSaveSuccess) { _, _ in persistDraftSession() }
    }

    private func applyIncomingDuration(_ seconds: Double) {
        let components = TransitionDurationPicker.components(from: seconds)
        durationMinutesPart = components.minutes
        durationSecondsPart = components.seconds
    }
    
    private func persistDurationSelection() {
        viewModel.setTransitionDuration(durationTotalSeconds, for: device.id)
    }

    private func transitionPickerDurationSeconds() -> Int {
        TransitionDurationPicker.totalSeconds(minutes: durationMinutesPart, seconds: durationSecondsPart)
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
                .font(AppTypography.style(.caption, weight: .medium))
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
                                .font(AppTypography.style(.caption, weight: .medium))
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
                    .font(AppTypography.style(.headline))
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
                                    .font(AppTypography.style(.caption))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(AppTypography.style(.caption))
                            }
                            Text("Preset")
                                .font(AppTypography.style(.caption, weight: .medium))
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
                    .disabled(isPresetButtonDisabled)
                    .opacity(isPresetButtonDisabled ? 0.45 : 1.0)
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
                            .font(AppTypography.style(.caption))
                        Text(transitionOn ? "ON" : "OFF")
                            .font(AppTypography.style(.caption, weight: .medium))
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
                    .font(AppTypography.style(.caption))
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
                    Text("Minutes")
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(.white.opacity(0.6))
                    Picker("Minutes", selection: $durationMinutesPart) {
                        ForEach(0...60, id: \.self) { value in
                            Text(String(format: "%02d", value))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                    .clipped()
                    .accessibilityLabel("Transition minutes")
                }

                VStack(spacing: 4) {
                    Text("Seconds")
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(.white.opacity(0.6))
                    Picker("Seconds", selection: $durationSecondsPart) {
                        ForEach(allowedSecondValues, id: \.self) { value in
                            Text(String(format: "%02d", value))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                    .clipped()
                    .accessibilityLabel("Transition seconds")
                }
            }
            .frame(maxWidth: .infinity)

            durationRecommendationGuide
        }
    }

    private var durationRecommendationGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let progress = min(
                    1.0,
                    Double(selectedDurationSeconds) / Double(TransitionDurationPicker.maxSeconds)
                )
                let markerX = width * TransitionDurationPicker.recommendedMaxRatio

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    Capsule()
                        .fill(transitionExceedsRecommendedMax ? Color.orange.opacity(0.9) : Color.white.opacity(0.45))
                        .frame(width: width * progress, height: 6)

                    Rectangle()
                        .fill(Color.orange.opacity(0.95))
                        .frame(width: 2, height: 12)
                        .offset(x: max(0, min(width - 2, markerX - 1)))
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recommended transition duration marker")
            .accessibilityValue("Recommended max \(TransitionDurationPicker.clockString(seconds: Double(TransitionDurationPicker.recommendedMaxSeconds)))")

            HStack {
                Text("0:00")
                Spacer()
                Text("\(TransitionDurationPicker.clockString(seconds: Double(TransitionDurationPicker.recommendedMaxSeconds))) recommended")
                    .foregroundColor(.orange.opacity(0.9))
                Spacer()
                Text("60:00")
            }
            .font(AppTypography.style(.caption2))
            .foregroundColor(.white.opacity(0.55))

            if transitionExceedsRecommendedMax {
                Text("Above \(TransitionDurationPicker.clockString(seconds: Double(TransitionDurationPicker.recommendedMaxSeconds))) may be less reliable on some devices and use more preset storage.")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.orange.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var startSection: some View {
        let brightnessPercent = Int(round(aBrightness / 255.0 * 100))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("Start")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(brightnessPercent)%")
                        .font(AppTypography.style(.caption))
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
                allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device)
                    && viewModel.supportsCCTOutput(for: device, segmentId: 0),
                allowManualWhite: advancedUIEnabled,
                autoWhiteEnabled: viewModel.isAutoWhiteEnabled(for: device),
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
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(brightnessPercent)%")
                        .font(AppTypography.style(.caption))
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
                allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device)
                    && viewModel.supportsCCTOutput(for: device, segmentId: 0),
                allowManualWhite: advancedUIEnabled,
                autoWhiteEnabled: viewModel.isAutoWhiteEnabled(for: device),
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
            if hasActiveTransitionRun {
                Button(action: cancelTransition) {
                    Group {
                        if isCancellingTransition || viewModel.isTransitionCleanupInProgress(for: device.id) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Text("Cancel")
                                .font(AppTypography.style(.callout, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(height: 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.30))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(isCancelDisabled ? 0.45 : 1)
                .accessibilityLabel("Cancel transition")
                .accessibilityHint("Stop the currently running transition.")
                .disabled(isCancelDisabled)
            } else {
                Button(action: applyTransition) {
                    Group {
                        if isApplyingTransition || viewModel.isTransitionCleanupInProgress(for: device.id) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Text("Apply")
                                .font(AppTypography.style(.callout, weight: .semibold))
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

            Text("Transitions here are temporary and require the app to keep running. For offline playback, save as Preset or Automation.")
                .font(AppTypography.style(.caption2))
                .foregroundColor(.white.opacity(0.64))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        preferSegmented: preferSegmentedUpdates
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
                    preferSegmented: preferSegmentedUpdates
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
                        preferSegmented: preferSegmentedUpdates
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
                    preferSegmented: preferSegmentedUpdates
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
            preferSegmented: preferSegmentedUpdates
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
            preferSegmented: preferSegmentedUpdates
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
            preferSegmented: preferSegmentedUpdates
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
                endStopWhiteLevels: endWhites,
                forceSegmentedOnly: false
            )
        }
    }

    private func cancelTransition() {
        guard !isCancellingTransition else { return }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        isCancellingTransition = true

        Task {
            await viewModel.cancelActiveRun(
                for: device,
                releaseRealtimeOverride: false,
                force: false,
                endReason: .cancelledByManualInput
            )
            await MainActor.run {
                isCancellingTransition = false
            }
        }
    }
    
}

private extension TransitionPane {
    var backgroundFill: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 0.12 : 0.06)
    }

    func persistDraftSession() {
        let session = TransitionDraftSession(
            gradientA: currentGradientA,
            gradientB: currentGradientB,
            stopTemperaturesA: stopTemperaturesA,
            stopTemperaturesB: stopTemperaturesB,
            stopWhiteLevelsA: stopWhiteLevelsA,
            stopWhiteLevelsB: stopWhiteLevelsB,
            brightnessA: aBrightness,
            brightnessB: bBrightness,
            selectedStartPresetId: selectedStartPresetId,
            selectedEndPresetId: selectedEndPresetId,
            transitionOn: transitionOn,
            isExpanded: isExpanded,
            isSavingPreset: isSavingPreset,
            showSaveSuccess: showSaveSuccess,
            updatedAt: Date()
        )
        viewModel.setTransitionDraftSession(session, for: device.id)
    }

    func restoreDraftSessionIfAvailable() {
        guard let session = viewModel.transitionDraftSession(for: device.id) else { return }
        gradientA = session.gradientA
        stopsA = session.gradientA.stops
        gradientB = session.gradientB
        stopsB = session.gradientB.stops
        stopTemperaturesA = session.stopTemperaturesA
        stopTemperaturesB = session.stopTemperaturesB
        stopWhiteLevelsA = session.stopWhiteLevelsA
        stopWhiteLevelsB = session.stopWhiteLevelsB
        aBrightness = session.brightnessA
        bBrightness = session.brightnessB
        selectedStartPresetId = session.selectedStartPresetId
        selectedEndPresetId = session.selectedEndPresetId
        transitionOn = session.transitionOn || activeTransitionId != nil
        isExpanded = session.isExpanded || activeTransitionId != nil || session.isSavingPreset
        isSavingPreset = session.isSavingPreset
        showSaveSuccess = session.showSaveSuccess
    }
    
    // MARK: - Direct Preset Saving
    
    func saveTransitionPresetDirectly() async {
        guard viewModel.shouldAllowInteractivePresetSaveTap(for: device.id) else {
            #if DEBUG
            let reason = viewModel.transitionPresetSaveBlockReasonDebug(for: device.id) ?? "unknown"
            print("⚠️ Preset save blocked for \(device.name): \(reason)")
            #endif
            return
        }
        await MainActor.run {
            isSavingPreset = true
            showSaveSuccess = false
            viewModel.updateTransitionDraftSaveUIState(
                deviceId: device.id,
                isSavingPreset: true,
                showSaveSuccess: false
            )
        }
        await MainActor.run {
            persistDraftSession()
        }
        
        let presetName = "Transition \(Date().presetNameTimestamp())"
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

        let outcome = await viewModel.saveTransitionPresetWithActiveRunHandling(
            device: device,
            presetInputSnapshot: preset
        )

        switch outcome {
        case .some(.saved(let result)):
            await MainActor.run {
                preset.wledPlaylistId = result.playlistId
                preset.wledStepPresetIds = result.stepPresetIds
                preset.wledSyncState = .synced
                preset.lastWLEDSyncError = nil
                preset.lastWLEDSyncAt = Date()
                PresetsStore.shared.addTransitionPreset(preset)
                isSavingPreset = false
                showSaveSuccess = true
                persistDraftSession()
                viewModel.updateTransitionDraftSaveUIState(
                    deviceId: device.id,
                    isSavingPreset: false,
                    showSaveSuccess: true
                )
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showSaveSuccess = false
                persistDraftSession()
                viewModel.updateTransitionDraftSaveUIState(
                    deviceId: device.id,
                    isSavingPreset: false,
                    showSaveSuccess: false
                )
            }
            #if DEBUG
            print("✅ Transition preset saved to WLED device: Playlist ID \(result.playlistId)")
            print("transition_preset.save.synced playlist=\(result.playlistId) stepIds=\(result.stepPresetIds)")
            #endif
        case .some(.deferred):
            await MainActor.run {
                preset.wledPlaylistId = nil
                preset.wledStepPresetIds = nil
                preset.wledSyncState = .pendingSync
                preset.lastWLEDSyncError = "Deferred WLED sync"
                preset.lastWLEDSyncAt = nil
                PresetsStore.shared.addTransitionPreset(preset)
                isSavingPreset = false
                showSaveSuccess = true
                persistDraftSession()
                viewModel.updateTransitionDraftSaveUIState(
                    deviceId: device.id,
                    isSavingPreset: false,
                    showSaveSuccess: true
                )
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showSaveSuccess = false
                persistDraftSession()
                viewModel.updateTransitionDraftSaveUIState(
                    deviceId: device.id,
                    isSavingPreset: false,
                    showSaveSuccess: false
                )
            }
            #if DEBUG
            print("⚠️ Transition preset save deferred for WLED device due to preset store health")
            print("transition_preset.save.deferred_local_only device=\(device.id)")
            #endif
        case .some(.suppressedBusy):
            await MainActor.run {
                isSavingPreset = false
                showSaveSuccess = false
                persistDraftSession()
                viewModel.updateTransitionDraftSaveUIState(
                    deviceId: device.id,
                    isSavingPreset: false,
                    showSaveSuccess: false
                )
            }
            #if DEBUG
            print("preset_save.suppressed_busy_ui device=\(device.id)")
            #endif
        case .none:
            await MainActor.run {
                isSavingPreset = false
                showSaveSuccess = false
                persistDraftSession()
                viewModel.updateTransitionDraftSaveUIState(
                    deviceId: device.id,
                    isSavingPreset: false,
                    showSaveSuccess: false
                )
            }
        }
    }
}
