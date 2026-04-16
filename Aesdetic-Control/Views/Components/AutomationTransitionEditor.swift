import SwiftUI

/// Transition editor component for automation dialogs that works with bindings instead of direct device updates
struct AutomationTransitionEditor: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @ObservedObject private var presetsStore = PresetsStore.shared
    let device: WLEDDevice
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    
    // Bindings for automation state
    @Binding var startGradient: LEDGradient
    @Binding var endGradient: LEDGradient
    @Binding var startBrightness: Double
    @Binding var endBrightness: Double
    @Binding var durationSeconds: Double
    @Binding var startTemperature: Double?
    @Binding var startWhiteLevel: Double?
    @Binding var endTemperature: Double?
    @Binding var endWhiteLevel: Double?
    let transitionProfile: TransitionStepProfile?
    let automationGuaranteeCount: Int
    let maxDurationMinutes: Int
    let showsDurationRecommendationGuide: Bool
    
    // Preview state
    @State private var previewEnabled: Bool = true
    
    // Internal UI state
    @State private var selectedA: UUID? = nil
    @State private var selectedB: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var wheelTarget: Character = "A" // 'A' or 'B'
    @State private var stopTemperaturesA: [UUID: Double] = [:]
    @State private var stopTemperaturesB: [UUID: Double] = [:]
    @State private var stopWhiteLevelsA: [UUID: Double] = [:]
    @State private var stopWhiteLevelsB: [UUID: Double] = [:]
    @State private var selectedStartPresetId: UUID?
    @State private var selectedEndPresetId: UUID?
    @State private var selectedTransitionPresetId: UUID?
    @State private var durationMinutesPart: Int = 1
    @State private var durationSecondsPart: Int = 0
    @State private var isApplyingTransition: Bool = false
    @State private var previewTask: Task<Void, Never>?
    @State private var lastPreviewTarget: GradientTarget = .end

    init(
        viewModel: DeviceControlViewModel,
        device: WLEDDevice,
        startGradient: Binding<LEDGradient>,
        endGradient: Binding<LEDGradient>,
        startBrightness: Binding<Double>,
        endBrightness: Binding<Double>,
        durationSeconds: Binding<Double>,
        startTemperature: Binding<Double?>,
        startWhiteLevel: Binding<Double?>,
        endTemperature: Binding<Double?>,
        endWhiteLevel: Binding<Double?>,
        transitionProfile: TransitionStepProfile? = nil,
        automationGuaranteeCount: Int = 5,
        maxDurationMinutes: Int = TransitionDurationPicker.maxMinutes,
        showsDurationRecommendationGuide: Bool = true
    ) {
        self.viewModel = viewModel
        self.device = device
        self._startGradient = startGradient
        self._endGradient = endGradient
        self._startBrightness = startBrightness
        self._endBrightness = endBrightness
        self._durationSeconds = durationSeconds
        self._startTemperature = startTemperature
        self._startWhiteLevel = startWhiteLevel
        self._endTemperature = endTemperature
        self._endWhiteLevel = endWhiteLevel
        self.transitionProfile = transitionProfile
        self.automationGuaranteeCount = automationGuaranteeCount
        self.maxDurationMinutes = max(0, maxDurationMinutes)
        self.showsDurationRecommendationGuide = showsDurationRecommendationGuide
    }
    
    private var allowedSecondValues: [Int] {
        durationMinutesPart >= maxDurationMinutes ? [0] : Array(0...59)
    }

    private var selectedDurationSeconds: Int {
        totalDurationSeconds(minutes: durationMinutesPart, seconds: durationSecondsPart)
    }

    private var transitionExceedsRecommendedMax: Bool {
        TransitionDurationPicker.exceedsRecommendedMax(Double(selectedDurationSeconds))
    }

    private var maxDurationSeconds: Int {
        max(0, maxDurationMinutes) * 60
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
            previewEnabled = true
            // Initialize duration from durationSeconds
            updateDurationFromSeconds(durationSeconds)
            hydrateStopMapsIfNeeded()
        }
        .onChange(of: previewEnabled) { _, enabled in
            if enabled {
                schedulePreview()
            } else {
                cancelPreview()
            }
        }
        .onChange(of: durationSeconds) { _, newValue in
            updateDurationFromSeconds(newValue)
        }
        .onChange(of: advancedUIEnabled) { _, enabled in
            if !enabled {
                previewEnabled = true
            }
        }
        .onDisappear {
            Task {
                await stopPreviewOnExit()
            }
        }
    }
    
    // MARK: - Section Views
    
    private var headerRow: some View {
        HStack {
            Label("Transitions", systemImage: "arrow.triangle.2.circlepath")
                .font(AppTypography.style(.headline))
                .foregroundColor(.white)
            Spacer()

            if advancedUIEnabled {
                Toggle(isOn: $previewEnabled) {
                    HStack(spacing: 4) {
                        Image(systemName: previewEnabled ? "eye.fill" : "eye.slash.fill")
                            .font(AppTypography.style(.caption2))
                        Text("Preview")
                            .font(AppTypography.style(.caption, weight: .medium))
                    }
                }
                .toggleStyle(.button)
                .tint(previewEnabled ? .green : .gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var transitionPresetSelector: some View {
        if !transitionPresets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Transitions")
                    .font(AppTypography.style(.footnote, weight: .semibold))
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
            stopTemperaturesA = preset.temperatureA.map { temp in
                Dictionary(uniqueKeysWithValues: preset.gradientA.stops.map { ($0.id, temp) })
            } ?? [:]
            stopWhiteLevelsA = preset.whiteLevelA.map { white in
                Dictionary(uniqueKeysWithValues: preset.gradientA.stops.map { ($0.id, white) })
            } ?? [:]
            stopTemperaturesB = preset.temperatureB.map { temp in
                Dictionary(uniqueKeysWithValues: preset.gradientB.stops.map { ($0.id, temp) })
            } ?? [:]
            stopWhiteLevelsB = preset.whiteLevelB.map { white in
                Dictionary(uniqueKeysWithValues: preset.gradientB.stops.map { ($0.id, white) })
            } ?? [:]
            startTemperature = preset.temperatureA
            startWhiteLevel = preset.whiteLevelA
            endTemperature = preset.temperatureB
            endWhiteLevel = preset.whiteLevelB
            
            if previewEnabled {
                schedulePreview(target: .end)
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
                        .font(AppTypography.style(.caption2))
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
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(formatDuration(preset.durationSec))
                    .font(AppTypography.style(.caption2))
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
                .font(AppTypography.style(.footnote, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Minutes")
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(.white.opacity(0.6))
                    Picker("Minutes", selection: $durationMinutesPart) {
                        ForEach(0...maxDurationMinutes, id: \.self) { value in
                            Text(String(format: "%02d", value))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                    .clipped()
                    .accessibilityLabel("Transition minutes")
                    .onChange(of: durationMinutesPart) { _, _ in
                        updateDurationToSeconds()
                    }
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
                    .onChange(of: durationSecondsPart) { _, _ in
                        updateDurationToSeconds()
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if showsDurationRecommendationGuide {
                durationRecommendationGuide
            }
            transitionPlanningSummary
        }
        .padding(.horizontal, 16)
    }

    private var durationRecommendationGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let progress = min(
                    1.0,
                    Double(selectedDurationSeconds) / Double(max(1, maxDurationSeconds))
                )
                let recommendedRatio = min(
                    1.0,
                    Double(TransitionDurationPicker.recommendedMaxSeconds) / Double(max(1, maxDurationSeconds))
                )
                let markerX = width * recommendedRatio

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

            HStack {
                Text("0:00")
                Spacer()
                Text("\(TransitionDurationPicker.clockString(seconds: Double(TransitionDurationPicker.recommendedMaxSeconds))) recommended")
                    .foregroundColor(.orange.opacity(0.9))
                Spacer()
                Text(formatDuration(Double(maxDurationSeconds)))
            }
            .font(AppTypography.style(.caption2))
            .foregroundColor(.white.opacity(0.55))

            if transitionExceedsRecommendedMax {
                Text("Above \(TransitionDurationPicker.clockString(seconds: Double(TransitionDurationPicker.recommendedMaxSeconds))) may reduce automation reliability and increase preset storage use.")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.orange.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var transitionPlanningSummary: some View {
        if let profile = transitionProfile {
            VStack(alignment: .leading, spacing: 6) {
                let budgetText = profile.perAutomationBudget.map { "\($0) slots / automation" } ?? "No budget limit"
                let quality = profile.qualityLabel.displayName
                Text("Estimated storage: \(profile.slotsRequired) slots")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                Text("Quality: \(quality) (\(Int(profile.legSeconds))s legs)")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(automationGuaranteeCount)-automation budget: \(budgetText)")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.65))
                if profile.wasCoarsened {
                    Text("Auto-adjusted from \(Int(profile.baseLegSeconds))s to \(Int(profile.legSeconds))s legs to fit storage budget.")
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(.orange.opacity(0.92))
                }
                Text(profile.fitsBudget ? "Fits guaranteed storage budget." : "Exceeds guaranteed storage budget. Reduce duration or free preset slots.")
                    .font(AppTypography.style(.caption2, weight: .semibold))
                    .foregroundColor(profile.fitsBudget ? .green.opacity(0.9) : .orange.opacity(0.95))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }
    
    private var startSection: some View {
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
                    Text("\(Int(round(startBrightness/255.0*100)))%")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Slider(value: $startBrightness, in: 0...255, step: 1)
                .tint(.white)
                .onChange(of: startBrightness) { _, _ in
                    if previewEnabled {
                        schedulePreview(target: .start)
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
                    startTemperature = stopTemperaturesA.values.first
                    startWhiteLevel = stopWhiteLevelsA.values.first
                    startGradient = LEDGradient(stops: updatedStops, interpolation: startGradient.interpolation)
                    selectedA = new.id
                    
                    if previewEnabled {
                        schedulePreview(target: .start)
                    }
                },
                onStopsChanged: { stops, phase in
                    startGradient = LEDGradient(stops: stops, interpolation: startGradient.interpolation)
                    let stopIds = Set(stops.map { $0.id })
                    stopTemperaturesA = stopTemperaturesA.filter { stopIds.contains($0.key) }
                    stopWhiteLevelsA = stopWhiteLevelsA.filter { stopIds.contains($0.key) }
                    startTemperature = stopTemperaturesA.values.first
                    startWhiteLevel = stopWhiteLevelsA.values.first
                    if previewEnabled && phase == .ended {
                        schedulePreview(target: .start)
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
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(Int(round(endBrightness/255.0*100)))%")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Slider(value: $endBrightness, in: 0...255, step: 1)
                .tint(.white)
                .onChange(of: endBrightness) { _, _ in
                    if previewEnabled {
                        schedulePreview(target: .end)
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
                    if !stopTemperaturesB.isEmpty {
                        if let newIndex = updatedStops.firstIndex(where: { $0.id == new.id }) {
                            var nearestTemp: Double? = nil
                            var minDistance: Double = Double.greatestFiniteMagnitude
                            for (idx, stop) in updatedStops.enumerated() {
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
                        if let newIndex = updatedStops.firstIndex(where: { $0.id == new.id }) {
                            var nearestWhite: Double? = nil
                            var minDistance: Double = Double.greatestFiniteMagnitude
                            for (idx, stop) in updatedStops.enumerated() {
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
                    endTemperature = stopTemperaturesB.values.first
                    endWhiteLevel = stopWhiteLevelsB.values.first
                    endGradient = LEDGradient(stops: updatedStops, interpolation: endGradient.interpolation)
                    selectedB = new.id
                    
                    if previewEnabled {
                        schedulePreview(target: .end)
                    }
                },
                onStopsChanged: { stops, phase in
                    endGradient = LEDGradient(stops: stops, interpolation: endGradient.interpolation)
                    let stopIds = Set(stops.map { $0.id })
                    stopTemperaturesB = stopTemperaturesB.filter { stopIds.contains($0.key) }
                    stopWhiteLevelsB = stopWhiteLevelsB.filter { stopIds.contains($0.key) }
                    endTemperature = stopTemperaturesB.values.first
                    endWhiteLevel = stopWhiteLevelsB.values.first
                    if previewEnabled && phase == .ended {
                        schedulePreview(target: .end)
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
                stopTemperaturesA = preset.temperature.map { temp in
                    Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, temp) })
                } ?? [:]
                stopWhiteLevelsA = preset.whiteLevel.map { white in
                    Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, white) })
                } ?? [:]
                startTemperature = preset.temperature
                startWhiteLevel = preset.whiteLevel
            } else {
                selectedEndPresetId = preset.id
                endGradient = LEDGradient(stops: preset.gradientStops, interpolation: preset.gradientInterpolation ?? .linear)
                endBrightness = Double(preset.brightness)
                stopTemperaturesB = preset.temperature.map { temp in
                    Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, temp) })
                } ?? [:]
                stopWhiteLevelsB = preset.whiteLevel.map { white in
                    Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, white) })
                } ?? [:]
                endTemperature = preset.temperature
                endWhiteLevel = preset.whiteLevel
            }
            
            if previewEnabled {
                schedulePreview(target: target)
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
        let initialTemp = target == .start ? stopTemperaturesA[selectedId] : stopTemperaturesB[selectedId]
        let initialWhite = target == .start ? stopWhiteLevelsA[selectedId] : stopWhiteLevelsB[selectedId]
        
        ColorWheelInline(
            initialColor: wheelInitial,
            initialTemperature: initialTemp,
            initialWhiteLevel: initialWhite,
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
                if target == .start {
                    guard let idx = startGradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
                    var updatedStops = startGradient.stops
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
                    startGradient = LEDGradient(stops: updatedStops, interpolation: startGradient.interpolation)
                    startTemperature = stopTemperaturesA.values.first
                    startWhiteLevel = stopWhiteLevelsA.values.first
                } else {
                    guard let idx = endGradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
                    var updatedStops = endGradient.stops
                    if let temp = temperature {
                        updatedStops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                        stopTemperaturesB[selectedId] = temp
                        if let white = whiteLevel {
                            stopWhiteLevelsB[selectedId] = white
                        } else {
                            stopWhiteLevelsB.removeValue(forKey: selectedId)
                        }
                    } else {
                        updatedStops[idx].hexColor = color.toHex()
                        stopTemperaturesB.removeValue(forKey: selectedId)
                        if let white = whiteLevel {
                            stopWhiteLevelsB[selectedId] = white
                        } else {
                            stopWhiteLevelsB.removeValue(forKey: selectedId)
                        }
                    }
                    endGradient = LEDGradient(stops: updatedStops, interpolation: endGradient.interpolation)
                    endTemperature = stopTemperaturesB.values.first
                    endWhiteLevel = stopWhiteLevelsB.values.first
                }
                
                if previewEnabled {
                    schedulePreview(target: target)
                }
            },
            onRemove: {
                if target == .start {
                    if startGradient.stops.count > 1 {
                        var updatedStops = startGradient.stops
                        updatedStops.removeAll { $0.id == selectedId }
                        startGradient = LEDGradient(stops: updatedStops, interpolation: startGradient.interpolation)
                        stopTemperaturesA.removeValue(forKey: selectedId)
                        stopWhiteLevelsA.removeValue(forKey: selectedId)
                        startTemperature = stopTemperaturesA.values.first
                        startWhiteLevel = stopWhiteLevelsA.values.first
                        selectedA = nil
                    }
                } else {
                    if endGradient.stops.count > 1 {
                        var updatedStops = endGradient.stops
                        updatedStops.removeAll { $0.id == selectedId }
                        endGradient = LEDGradient(stops: updatedStops, interpolation: endGradient.interpolation)
                        stopTemperaturesB.removeValue(forKey: selectedId)
                        stopWhiteLevelsB.removeValue(forKey: selectedId)
                        endTemperature = stopTemperaturesB.values.first
                        endWhiteLevel = stopWhiteLevelsB.values.first
                        selectedB = nil
                    }
                }
                showWheel = false
                
                if previewEnabled {
                    schedulePreview(target: target)
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
                    .font(AppTypography.style(.caption, weight: .semibold))
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
        let total = clampedDurationTotalSeconds(seconds)
        durationMinutesPart = total / 60
        durationSecondsPart = total % 60
        if Double(total) != seconds {
            durationSeconds = Double(total)
        }
    }
    
    private func updateDurationToSeconds() {
        if durationMinutesPart > maxDurationMinutes {
            durationMinutesPart = maxDurationMinutes
        }
        if durationMinutesPart < 0 {
            durationMinutesPart = 0
        }
        if durationMinutesPart == maxDurationMinutes {
            durationSecondsPart = 0
        }
        durationSecondsPart = max(0, min(durationSecondsPart, 59))
        durationSeconds = Double(totalDurationSeconds(minutes: durationMinutesPart, seconds: durationSecondsPart))
    }

    private func formatDuration(_ seconds: Double) -> String {
        TransitionDurationPicker.clockString(seconds: seconds)
    }

    private func clampedDurationTotalSeconds(_ seconds: Double) -> Int {
        max(0, min(Int(seconds.rounded()), maxDurationSeconds))
    }

    private func totalDurationSeconds(minutes: Int, seconds: Int) -> Int {
        let clampedMinutes = max(0, min(minutes, maxDurationMinutes))
        if clampedMinutes == maxDurationMinutes {
            return maxDurationSeconds
        }
        let clampedSeconds = max(0, min(seconds, 59))
        return clampedMinutes * 60 + clampedSeconds
    }

    private func hydrateStopMapsIfNeeded() {
        if stopTemperaturesA.isEmpty, let temp = startTemperature {
            stopTemperaturesA = Dictionary(uniqueKeysWithValues: startGradient.stops.map { ($0.id, temp) })
        }
        if stopWhiteLevelsA.isEmpty, let white = startWhiteLevel {
            stopWhiteLevelsA = Dictionary(uniqueKeysWithValues: startGradient.stops.map { ($0.id, white) })
        }
        if stopTemperaturesB.isEmpty, let temp = endTemperature {
            stopTemperaturesB = Dictionary(uniqueKeysWithValues: endGradient.stops.map { ($0.id, temp) })
        }
        if stopWhiteLevelsB.isEmpty, let white = endWhiteLevel {
            stopWhiteLevelsB = Dictionary(uniqueKeysWithValues: endGradient.stops.map { ($0.id, white) })
        }
    }
    
    // MARK: - Preview Functions

    private func schedulePreview(target: GradientTarget? = nil) {
        if let target {
            lastPreviewTarget = target
        }
        previewTask?.cancel()
        previewTask = Task {
            // Debounce rapid edits from sliders/wheels so only latest preview starts.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await previewTransition()
        }
    }
    
    private func previewTransition() async {
        await MainActor.run {
            isApplyingTransition = true
        }

        defer {
            Task { @MainActor in
                isApplyingTransition = false
            }
        }

        guard !Task.isCancelled else { return }

        let hasActiveRun = await MainActor.run {
            viewModel.activeRunStatus[device.id] != nil
        }
        guard !hasActiveRun else { return }

        let snapshot = await MainActor.run {
            let target = lastPreviewTarget
            switch target {
            case .start:
                return (
                    gradient: startGradient,
                    brightness: Int(startBrightness),
                    temperatures: stopTemperaturesA.isEmpty ? nil : stopTemperaturesA,
                    whites: stopWhiteLevelsA.isEmpty ? nil : stopWhiteLevelsA
                )
            case .end:
                return (
                    gradient: endGradient,
                    brightness: Int(endBrightness),
                    temperatures: stopTemperaturesB.isEmpty ? nil : stopTemperaturesB,
                    whites: stopWhiteLevelsB.isEmpty ? nil : stopWhiteLevelsB
                )
            }
        }

        let ledCount = await MainActor.run {
            viewModel.totalLEDCount(for: device)
        }

        await viewModel.applyGradientStopsAcrossStrip(
            device,
            stops: snapshot.gradient.stops,
            ledCount: ledCount,
            stopTemperatures: snapshot.temperatures,
            stopWhiteLevels: snapshot.whites,
            interpolation: snapshot.gradient.interpolation,
            brightness: snapshot.brightness,
            preferSegmented: true,
            forceSegmentedOnly: true
        )
    }
    
    private func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        Task { @MainActor in
            isApplyingTransition = false
        }
    }

    private func stopPreviewOnExit() async {
        previewTask?.cancel()
        previewTask = nil
        await MainActor.run {
            isApplyingTransition = false
            previewEnabled = false
        }
    }
}
