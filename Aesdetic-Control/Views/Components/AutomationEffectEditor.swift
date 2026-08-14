import SwiftUI

/// Effect editor component for automation dialogs that works with bindings instead of direct device updates
struct AutomationEffectEditor: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @ObservedObject private var presetsStore = PresetsStore.shared
    let device: WLEDDevice
    let effectOptions: [EffectMetadata]
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    
    // Bindings for automation state
    @Binding var effectId: Int
    @Binding var brightness: Double
    @Binding var speed: Int
    @Binding var intensity: Int
    @Binding var gradient: LEDGradient
    @Binding var selectedEffectPresetId: UUID?
    let isInline: Bool
    let externalPreviewEnabled: Binding<Bool>?
    
    // Preview state
    @State private var localPreviewEnabled: Bool = false
    @State private var isApplyingEffect: Bool = false
    
    // Internal UI state
    @State private var selectedStopId: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var selectedColorPresetId: UUID? = nil
    @State private var selectedRecoveredColorPresetId: Int? = nil
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

    private var recoveredColorPresets: [WLEDRecoveredColorPreset] {
        WLEDDevicePresetRecovery.recoveredColorPresets(
            for: device.id,
            presets: viewModel.presets(for: device),
            playlists: viewModel.playlists(for: device),
            localColorPresets: colorPresets
        )
    }
    
    private var effectPresets: [WLEDEffectPreset] {
        presetsStore.effectPresets(for: device.id)
    }

    init(
        viewModel: DeviceControlViewModel,
        device: WLEDDevice,
        effectOptions: [EffectMetadata],
        effectId: Binding<Int>,
        brightness: Binding<Double>,
        speed: Binding<Int>,
        intensity: Binding<Int>,
        gradient: Binding<LEDGradient>,
        selectedEffectPresetId: Binding<UUID?>,
        isInline: Bool,
        externalPreviewEnabled: Binding<Bool>? = nil
    ) {
        self.viewModel = viewModel
        self.device = device
        self.effectOptions = effectOptions
        self._effectId = effectId
        self._brightness = brightness
        self._speed = speed
        self._intensity = intensity
        self._gradient = gradient
        self._selectedEffectPresetId = selectedEffectPresetId
        self.isInline = isInline
        self.externalPreviewEnabled = externalPreviewEnabled
    }
    
    var body: some View {
        VStack(spacing: isInline ? 12 : 16) {
            if !isInline {
                headerRow
            }
            effectPresetSelector
            effectPicker
            VStack(spacing: isInline ? 6 : 8) {
                gradientSection
                brightnessSection
            }
            speedSection
            intensitySection
            previewSection
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
        .onChange(of: effectId) { _, newId in
            // Update gradient for new slot count when effect changes
            updateGradientForSlotCount()
        }
        .onChange(of: previewEnabled) { _, enabled in
            if enabled {
                Task {
                    await previewEffect()
                }
            } else {
                stopPreview()
            }
        }
    }
    
    // MARK: - Section Views
    
    private var headerRow: some View {
        HStack {
            Label("Animations", systemImage: "sparkles")
                .font(AppTypography.style(.headline))
                .foregroundColor(.white)
            Spacer()
            
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
        .padding(.horizontal, isInline ? 0 : 16)
    }
    
    @ViewBuilder
    private var effectPresetSelector: some View {
        if !effectPresets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(effectPresets) { preset in
                        effectPresetChip(preset: preset)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, isInline ? 0 : 16)
        }
    }
    
    private func effectPresetChip(preset: WLEDEffectPreset) -> some View {
        let isSelected = selectedEffectPresetId == preset.id
        return Button {
            selectedEffectPresetId = preset.id
            selectedColorPresetId = nil
            selectedRecoveredColorPresetId = nil
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
            selectedEffectPresetId = preset.id
            
            if previewEnabled {
                Task {
                    await previewEffect()
                }
            }
        } label: {
            effectPresetSwatch(preset: preset, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name), effect \(preset.effectId)")
    }

    private func effectPresetSwatch(preset: WLEDEffectPreset, isSelected: Bool) -> some View {
        ZStack {
            effectPresetGradient(preset: preset)
                .opacity(0.72)

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16 + Double(index) * 0.07))
                        .frame(width: 2, height: CGFloat(7 + index * 2))
                }
            }

            presetSwatchHighlight(cornerRadius: 6)
            presetSwatchSelection(isSelected: isSelected, cornerRadius: 6)
        }
        .frame(width: 48, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.0), radius: 4, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    private var effectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Animation")
                .font(AppTypography.style(.footnote, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
            
            if effectOptions.isEmpty {
                Text("No gradient-friendly animations available for this device.")
                    .font(AppTypography.style(.caption))
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
                    selectedColorPresetId = nil
                    selectedRecoveredColorPresetId = nil
                    updateGradientForSlotCount()
                }
            }
        }
        .padding(.horizontal, isInline ? 0 : 16)
    }
    
    @ViewBuilder
    private var gradientSection: some View {
        if canEditGradient {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gradient")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                
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
                        clearColorPresetSelectionForManualEdit()
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
                        clearColorPresetSelectionForManualEdit()
                        gradient = LEDGradient(stops: stops, interpolation: gradient.interpolation)
                        if previewEnabled && phase == .ended {
                            Task {
                                await previewEffect()
                            }
                        }
                    }
                )
                .frame(height: 56)
                
                if !colorPresets.isEmpty || !recoveredColorPresets.isEmpty {
                    colorPresetSelector
                }
                
                if showWheel, let selectedId = selectedStopId {
                    colorWheelView(selectedId: selectedId)
                }
            }
            .padding(.horizontal, isInline ? 0 : 16)
        } else {
            // Single color mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                
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
            .padding(.horizontal, isInline ? 0 : 16)
        }
    }
    
    @ViewBuilder
    private var colorPresetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(colorPresets) { preset in
                    colorPresetChip(preset: preset)
                }
                ForEach(recoveredColorPresets) { preset in
                    recoveredColorPresetChip(preset: preset)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .padding(.top, 4)
    }
    
    private func colorPresetChip(preset: ColorPreset) -> some View {
        let isSelected = selectedColorPresetId == preset.id
        return Button {
            selectedColorPresetId = preset.id
            selectedRecoveredColorPresetId = nil
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

    private func recoveredColorPresetChip(preset: WLEDRecoveredColorPreset) -> some View {
        let isSelected = selectedRecoveredColorPresetId == preset.id
        return Button {
            selectedColorPresetId = nil
            selectedRecoveredColorPresetId = preset.id
            let sortedStops = preset.gradient.stops.sorted { $0.position < $1.position }
            guard !sortedStops.isEmpty else { return }
            gradient = LEDGradient(
                stops: sortedStops,
                interpolation: preset.gradient.interpolation
            )
            brightness = Double(preset.brightness)
            updateGradientForSlotCount()

            if previewEnabled {
                Task {
                    await previewEffect()
                }
            }
        } label: {
            presetSwatchGradient(stops: preset.gradient.stops)
                .opacity(0.72)
                .frame(width: 48, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(presetSwatchHighlight(cornerRadius: 6))
                .overlay(presetSwatchSelection(isSelected: isSelected, cornerRadius: 6))
                .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.0), radius: 4, x: 0, y: 2)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.displayName)
    }

    private func effectPresetGradient(preset: WLEDEffectPreset) -> LinearGradient {
        if let stops = preset.gradientStops, !stops.isEmpty {
            return presetSwatchGradient(stops: stops)
        }

        let hue = Double((preset.effectId * 37) % 360) / 360.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.78, brightness: 0.96),
                Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.68, brightness: 0.78)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device)
                && viewModel.supportsCCTOutput(for: device, segmentId: 0),
            allowManualWhite: advancedUIEnabled,
            autoWhiteEnabled: viewModel.isAutoWhiteEnabled(for: device),
            cctKelvinRange: viewModel.cctKelvinRange(for: device),
            onColorChange: { color, temperature, _ in
                guard let idx = gradient.stops.firstIndex(where: { $0.id == selectedId }) else { return }
                clearColorPresetSelectionForManualEdit()
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
                    clearColorPresetSelectionForManualEdit()
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
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                Spacer()
                Text("\(Int(brightness))%")
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
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
        .padding(.horizontal, isInline ? 0 : 16)
    }
    
    @ViewBuilder
    private var speedSection: some View {
        if showsSpeed {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(speedLabel)
                        .font(AppTypography.style(.footnote, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                    Spacer()
                    Text("\(Int(currentSpeedValue))")
                        .font(AppTypography.style(.caption, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
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
            .padding(.horizontal, isInline ? 0 : 16)
        }
    }
    
    @ViewBuilder
    private var intensitySection: some View {
        if showsIntensity {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(intensityLabel)
                        .font(AppTypography.style(.footnote, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                    Spacer()
                    Text("\(Int(currentIntensityValue))")
                        .font(AppTypography.style(.caption, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
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
            .padding(.horizontal, isInline ? 0 : 16)
        }
    }
    
    @ViewBuilder
    private var previewSection: some View {
        if isInline && externalPreviewEnabled == nil {
            HStack {
                Spacer(minLength: 0)
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
        }
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

    private func clearColorPresetSelectionForManualEdit() {
        selectedColorPresetId = nil
        selectedRecoveredColorPresetId = nil
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
