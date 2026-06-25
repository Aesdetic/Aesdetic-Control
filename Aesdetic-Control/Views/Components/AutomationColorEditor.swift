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
    @Binding var powerOn: Bool
    @Binding var selectedPresetId: UUID?
    @Binding var temperature: Double?
    @Binding var whiteLevel: Double?
    let showFadeControls: Bool
    let isInline: Bool
    let externalPreviewEnabled: Binding<Bool>?
    
    // Preview state
    @State private var localPreviewEnabled: Bool = false
    @State private var gradientPreviewTask: Task<Void, Never>?
    @State private var brightnessPreviewTask: Task<Void, Never>?
    
    // Internal UI state
    @State private var selectedStopId: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var stopTemperatures: [UUID: Double] = [:]
    @State private var stopWhiteLevels: [UUID: Double] = [:]
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false

    init(
        viewModel: DeviceControlViewModel,
        device: WLEDDevice,
        gradient: Binding<LEDGradient>,
        brightness: Binding<Double>,
        interpolation: Binding<GradientInterpolation>,
        fadeDuration: Binding<Double>,
        enableFade: Binding<Bool>,
        powerOn: Binding<Bool>,
        selectedPresetId: Binding<UUID?>,
        temperature: Binding<Double?>,
        whiteLevel: Binding<Double?>,
        showFadeControls: Bool,
        isInline: Bool,
        externalPreviewEnabled: Binding<Bool>? = nil
    ) {
        self.viewModel = viewModel
        self.device = device
        self._gradient = gradient
        self._brightness = brightness
        self._interpolation = interpolation
        self._fadeDuration = fadeDuration
        self._enableFade = enableFade
        self._powerOn = powerOn
        self._selectedPresetId = selectedPresetId
        self._temperature = temperature
        self._whiteLevel = whiteLevel
        self.showFadeControls = showFadeControls
        self.isInline = isInline
        self.externalPreviewEnabled = externalPreviewEnabled
    }
    
    var body: some View {
        VStack(spacing: isInline ? 12 : 16) {
            if !isInline {
                headerRow
            } else if externalPreviewEnabled == nil {
                inlinePreviewToggle
            }
            powerSection
            if powerOn {
                VStack(spacing: isInline ? 6 : 8) {
                    brightnessSection
                    gradientSection
                }
                blendSelector
                presetSelector
                colorWheel
                if showFadeControls {
                    fadeSection
                }
            } else {
                powerOffSummary
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isInline ? 0 : 16)
        .background {
            if !isInline {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .onChange(of: previewEnabled) { _, enabled in
            if enabled {
                if powerOn {
                    scheduleGradientPreview(gradient)
                } else {
                    schedulePowerPreview(isOn: false)
                }
            } else {
                cancelPreviewTasks()
            }
        }
        .onChange(of: powerOn) { _, isOn in
            if !isOn {
                showWheel = false
            }
            if previewEnabled {
                if isOn {
                    scheduleGradientPreview(gradient)
                } else {
                    schedulePowerPreview(isOn: false)
                }
            }
        }
        .onAppear {
            hydrateStopMapsIfNeeded()
        }
        .onChange(of: advancedUIEnabled) { _, enabled in
            if !enabled {
                previewEnabled = false
                cancelPreviewTasks()
            }
        }
        .onDisappear {
            cancelPreviewTasks()
        }
    }
    
    // MARK: - Section Views

    private func hydrateStopMapsIfNeeded() {
        if stopTemperatures.isEmpty, let temp = temperature {
            stopTemperatures = Dictionary(uniqueKeysWithValues: gradient.stops.map { ($0.id, temp) })
        }
        if stopWhiteLevels.isEmpty, let white = whiteLevel {
            stopWhiteLevels = Dictionary(uniqueKeysWithValues: gradient.stops.map { ($0.id, white) })
        }
    }
    
    @ViewBuilder
    private var presetSelector: some View {
        if !presetsStore.colorPresets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(presetsStore.colorPresets) { preset in
                        presetChip(preset: preset)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, isInline ? 0 : 16)
        }
    }
    
    private func presetChip(preset: ColorPreset) -> some View {
        let isSelected = selectedPresetId == preset.id
        return Button {
            selectedPresetId = preset.id
            gradient = LEDGradient(stops: preset.gradientStops, interpolation: preset.gradientInterpolation ?? .linear)
            brightness = Double(preset.brightness)
            interpolation = preset.gradientInterpolation ?? gradient.interpolation
            stopTemperatures = preset.temperature.map { temp in
                Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, temp) })
            } ?? [:]
            stopWhiteLevels = preset.whiteLevel.map { white in
                Dictionary(uniqueKeysWithValues: preset.gradientStops.map { ($0.id, white) })
            } ?? [:]
            temperature = stopTemperatures.values.first
            whiteLevel = stopWhiteLevels.values.first
            selectedPresetId = preset.id
            
            if previewEnabled {
                scheduleGradientPreview(gradient)
            }
        } label: {
            presetSwatchGradient(stops: preset.gradientStops)
                .opacity(0.72)
                .frame(width: 48, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(presetSwatchHighlight(cornerRadius: 6))
                .overlay(presetSwatchSelection(isSelected: isSelected, cornerRadius: 6))
                .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.0), radius: 4, x: 0, y: 2)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
    }

    private func presetSwatchGradient(stops: [GradientStop]) -> LinearGradient {
        let colors = stops.isEmpty ? [Color.white.opacity(0.8), Color.white.opacity(0.35)] : stops.map { Color(hex: $0.hexColor) }
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func presetSwatchSelection(isSelected: Bool, cornerRadius: CGFloat) -> some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.52 : 0.12), lineWidth: isSelected ? 1.5 : 1)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(AppTypography.style(.caption2, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
            }
        }
    }

    private func presetSwatchHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    private var headerRow: some View {
        HStack {
            Label("Colors", systemImage: "paintbrush.fill")
                .font(AppTypography.style(.headline))
                .foregroundColor(.white)
            Spacer()

            if advancedUIEnabled {
                Toggle(isOn: previewToggleBinding) {
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

            if powerOn {
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
                .disabled(isSavingPreset)
            }
        }
        .padding(.horizontal, isInline ? 0 : 16)
    }

    private var inlinePreviewToggle: some View {
        HStack {
            Spacer(minLength: 0)
            previewToggleLabel
        }
    }

    private var previewToggleLabel: some View {
        Toggle(isOn: previewToggleBinding) {
            HStack(spacing: 5) {
                Image(systemName: previewEnabled ? "eye.fill" : "eye")
                    .font(AppTypography.style(.caption2, weight: .semibold))
                Text("Preview")
                    .font(AppTypography.style(.caption, weight: .semibold))
            }
        }
        .toggleStyle(.button)
        .tint(previewEnabled ? .white.opacity(0.24) : .white.opacity(0.12))
        .foregroundColor(.white.opacity(previewEnabled ? 0.96 : 0.78))
        .clipShape(Capsule(style: .continuous))
    }

    private var previewEnabled: Bool {
        get {
            externalPreviewEnabled?.wrappedValue ?? localPreviewEnabled
        }
        nonmutating set {
            if let externalPreviewEnabled {
                externalPreviewEnabled.wrappedValue = newValue
            } else {
                localPreviewEnabled = newValue
            }
        }
    }

    private var previewToggleBinding: Binding<Bool> {
        Binding(
            get: { previewEnabled },
            set: { previewEnabled = $0 }
        )
    }

    private var powerSection: some View {
        HStack {
            Text("Power")
                .font(AppTypography.style(.callout, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
            Spacer()
            Button {
                powerOn.toggle()
            } label: {
                Text(powerOn ? "On" : "Off")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(powerOn ? .black.opacity(0.78) : .white.opacity(0.64))
                    .frame(width: 58, height: 32)
                    .background(secondaryControlBackground(isActive: powerOn, cornerRadius: 15))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, isInline ? 0 : 16)
    }

    private func automationSegmentBackground(isActive: Bool, cornerRadius: CGFloat = 14) -> some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .appLiquidGlass(role: .card, cornerRadius: cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.54),
                                        Color.white.opacity(0.22),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .background(.ultraThinMaterial.opacity(0.64), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            }
        }
    }

    private func secondaryControlBackground(isActive: Bool, cornerRadius: CGFloat = 15) -> some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .appLiquidGlass(role: .control, cornerRadius: cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.58),
                                        Color.white.opacity(0.28)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .background(.ultraThinMaterial.opacity(0.64), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            }
        }
    }
    
    private var brightnessSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Brightness")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                Spacer()
                Text("\(Int(round(brightness/255.0*100)))%")
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
            }
            Slider(value: $brightness, in: 0...255, step: 1)
                .tint(.white)
                .onChange(of: brightness) { _, newValue in
                    if previewEnabled {
                        scheduleBrightnessPreview(Int(newValue))
                    }
                }
        }
        .padding(.horizontal, isInline ? 0 : 16)
    }

    private var powerOffSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "poweroff")
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(.white.opacity(0.70))

            Text("This automation is set to turn the device off. Turn Power on to edit colors.")
                .font(AppTypography.style(.footnote))
                .foregroundColor(.white.opacity(0.64))
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isInline ? 0 : 16)
    }
    
    @ViewBuilder
    private var blendSelector: some View {
        if advancedUIEnabled, gradient.stops.count >= 2 {
            VStack(spacing: 8) {
                HStack {
                    Text("Blend Style")
                        .font(AppTypography.style(.footnote, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
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
            .padding(.horizontal, isInline ? 0 : 16)
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
                scheduleGradientPreview(updatedGradient)
            }
        }) {
            Text(mode.displayName)
                .font(AppTypography.style(.caption, weight: .medium))
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
        .padding(.horizontal, isInline ? 0 : 16)
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

        if !stopWhiteLevels.isEmpty {
            let sortedStops = updatedGradient.stops.sorted { $0.position < $1.position }
            if let newIndex = sortedStops.firstIndex(where: { $0.id == new.id }) {
                var nearestWhite: Double? = nil
                var minDistance: Double = Double.greatestFiniteMagnitude

                for (idx, stop) in sortedStops.enumerated() {
                    if idx != newIndex, let white = stopWhiteLevels[stop.id] {
                        let distance = abs(stop.position - new.position)
                        if distance < minDistance {
                            minDistance = distance
                            nearestWhite = white
                        }
                    }
                }

                if let inheritedWhite = nearestWhite {
                    stopWhiteLevels[new.id] = inheritedWhite
                }
            }
        }
        
        gradient = updatedGradient
        temperature = stopTemperatures.values.first
        whiteLevel = stopWhiteLevels.values.first
        selectedStopId = new.id
        selectedPresetId = nil // Clear preset when manually adding a stop
        
        if previewEnabled {
            scheduleGradientPreview(updatedGradient)
        }
    }
    
    private func handleStopsChanged(stops: [GradientStop], phase: DragPhase) {
        var updatedGradient = gradient
        updatedGradient.stops = stops
        gradient = updatedGradient
        selectedPresetId = nil // Clear preset when manually dragging stops
        let stopIds = Set(stops.map { $0.id })
        stopTemperatures = stopTemperatures.filter { stopIds.contains($0.key) }
        stopWhiteLevels = stopWhiteLevels.filter { stopIds.contains($0.key) }
        temperature = stopTemperatures.values.first
        whiteLevel = stopWhiteLevels.values.first
        
        if previewEnabled && phase == .ended {
            scheduleGradientPreview(updatedGradient)
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
            initialTemperature: stopTemperatures[selectedId],
            initialWhiteLevel: stopWhiteLevels[selectedId],
            canRemove: gradient.stops.count > 1,
            supportsCCT: supportsCCT,
            supportsWhite: supportsWhite,
            usesKelvinCCT: usesKelvin,
            allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device)
                && viewModel.supportsCCTOutput(for: device, segmentId: 0),
            allowManualWhite: advancedUIEnabled,
            autoWhiteEnabled: viewModel.isAutoWhiteEnabled(for: device),
            cctKelvinRange: viewModel.cctKelvinRange(for: device),
            onColorChange: { color, temperature, whiteLevel in
                handleColorChange(selectedId: selectedId, color: color, temperature: temperature, whiteLevel: whiteLevel)
            },
            onRemove: {
                handleColorRemove(selectedId: selectedId)
            },
            onDismiss: { showWheel = false }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .padding(.horizontal, isInline ? 0 : 16)
    }
    
    private func handleColorChange(selectedId: UUID, color: Color, temperature: Double?, whiteLevel: Double?) {
        guard let idx = gradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
        
        var updatedGradient = gradient
        
        if let temp = temperature {
            stopTemperatures[selectedId] = temp
            updatedGradient.stops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
            if let white = whiteLevel {
                stopWhiteLevels[selectedId] = white
            } else {
                stopWhiteLevels.removeValue(forKey: selectedId)
            }
        } else {
            updatedGradient.stops[idx].hexColor = color.toHex()
            stopTemperatures.removeValue(forKey: selectedId)
            if let white = whiteLevel {
                stopWhiteLevels[selectedId] = white
            } else {
                stopWhiteLevels.removeValue(forKey: selectedId)
            }
        }
        self.temperature = stopTemperatures.values.first
        self.whiteLevel = stopWhiteLevels.values.first
        
        gradient = updatedGradient
        selectedPresetId = nil // Clear preset when manually changing a stop color
        
        if previewEnabled {
            scheduleGradientPreview(updatedGradient)
        }
    }
    
    private func handleColorRemove(selectedId: UUID) {
        if gradient.stops.count > 1 {
            var updatedGradient = gradient
            updatedGradient.stops.removeAll { $0.id == selectedId }
            stopTemperatures.removeValue(forKey: selectedId)
            stopWhiteLevels.removeValue(forKey: selectedId)
            temperature = stopTemperatures.values.first
            whiteLevel = stopWhiteLevels.values.first
            gradient = updatedGradient
            selectedStopId = nil
            selectedPresetId = nil // Clear preset when manually removing a stop
            
            if previewEnabled {
                scheduleGradientPreview(updatedGradient)
            }
        }
    }
    
    @ViewBuilder
    private var fadeSection: some View {
        Toggle(isOn: $enableFade) {
            Text("Fade over time")
                .font(AppTypography.style(.footnote, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
        }
        .toggleStyle(SwitchToggleStyle(tint: .white))
        .padding(.horizontal, isInline ? 0 : 16)
        
        if enableFade {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fade duration")
                        .font(AppTypography.style(.footnote, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                    Spacer()
                    Text("\(Int(fadeDuration)) sec")
                        .font(AppTypography.style(.caption, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                }
                Slider(value: $fadeDuration, in: 5...300, step: 5)
                    .tint(.white)
            }
            .padding(.horizontal, isInline ? 0 : 16)
        }
    }
    
    // MARK: - Preview Functions

    private func scheduleGradientPreview(_ gradient: LEDGradient) {
        guard powerOn else {
            schedulePowerPreview(isOn: false)
            return
        }
        gradientPreviewTask?.cancel()
        gradientPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await previewGradient(gradient)
        }
    }

    private func scheduleBrightnessPreview(_ brightness: Int) {
        guard powerOn else { return }
        brightnessPreviewTask?.cancel()
        brightnessPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await previewBrightness(brightness)
        }
    }

    private func schedulePowerPreview(isOn: Bool) {
        gradientPreviewTask?.cancel()
        brightnessPreviewTask?.cancel()
        gradientPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await previewPower(isOn: isOn)
        }
    }

    private func cancelPreviewTasks() {
        gradientPreviewTask?.cancel()
        gradientPreviewTask = nil
        brightnessPreviewTask?.cancel()
        brightnessPreviewTask = nil
    }
    
    private func previewGradient(_ gradient: LEDGradient) async {
        if viewModel.activeRunStatus[device.id] != nil {
            return
        }
        let ledCount = viewModel.totalLEDCount(for: device)
        await viewModel.applyGradientStopsAcrossStrip(
            device,
            stops: gradient.stops,
            ledCount: ledCount,
            stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures,
            stopWhiteLevels: stopWhiteLevels.isEmpty ? nil : stopWhiteLevels,
            disableActiveEffect: true,
            segmentId: 0,
            interpolation: gradient.interpolation,
            preferSegmented: true,
            forceSegmentedOnly: true
        )
    }
    
    private func previewBrightness(_ brightness: Int) async {
        if viewModel.activeRunStatus[device.id] != nil {
            return
        }
        await viewModel.updateDeviceBrightness(device, brightness: brightness, userInitiated: false)
    }

    private func previewPower(isOn: Bool) async {
        if viewModel.activeRunStatus[device.id] != nil {
            return
        }
        let apiService = WLEDAPIService.shared
        let transitionDs: Int? = enableFade ? Int((fadeDuration * 10.0).rounded()) : nil
        _ = try? await apiService.setPower(for: device, isOn: isOn, transitionDeciseconds: transitionDs)
    }
    
    // MARK: - Preset Saving
    
    private func saveColorPreset() async {
        await MainActor.run {
            isSavingPreset = true
            showSaveSuccess = false
        }
        
        let presetName = "Color Preset \(Date().presetNameTimestamp())"
        var preset = ColorPreset(
            name: presetName,
            gradientStops: gradient.stops,
            gradientInterpolation: gradient.interpolation,
            brightness: Int(brightness),
            temperature: stopTemperatures.values.first,
            whiteLevel: stopWhiteLevels.values.first
        )

        do {
            let savedId = try await PresetSyncManager.shared.saveColorPreset(preset, to: device)
            await MainActor.run {
                var ids = preset.wledPresetIds ?? [:]
                ids[device.id] = savedId
                preset.wledPresetIds = ids
                preset.wledPresetId = savedId
                PresetsStore.shared.addColorPreset(preset)
                selectedPresetId = preset.id
                isSavingPreset = false
                showSaveSuccess = true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                showSaveSuccess = false
            }
            #if DEBUG
            print("✅ Color preset saved to WLED device: ID \(savedId)")
            #endif
        } catch {
            await MainActor.run {
                isSavingPreset = false
                showSaveSuccess = false
            }
            #if DEBUG
            print("⚠️ Failed to save color preset to WLED: \(error.localizedDescription)")
            #endif
        }
    }
}
