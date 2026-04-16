import SwiftUI
import Combine

struct EffectsPane: View {
    @EnvironmentObject private var viewModel: DeviceControlViewModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openURL) private var openURL
    let device: WLEDDevice
    let segmentId: Int
    @Binding var isExpanded: Bool
    let onActivate: () -> Void
    
    @State private var isApplyingEffect = false
    @State private var isLoadingMetadata = false
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    @State private var showSavePresetDialog = false
    @State private var effectSelectionId: Int = 0
    @State private var effectGradient: LEDGradient = EffectsPane.defaultEffectGradient
    @State private var stagedSolidColor: Color = .white
    @State private var selectedStopId: UUID?
    @State private var showColorPicker = false
    @State private var wheelInitial: Color = .white
    @State private var hasPendingGradientChanges = false
    @State private var autoApplyTask: Task<Void, Never>? = nil
    @State private var selectedColorPresetId: UUID? = nil
    @State private var segmentBrightness: Double = 255
    @State private var isAdjustingSegmentBrightness = false
    @State private var isInitializing = true
    @State private var isProgrammaticEffectSync = false
    @State private var stagedSpeedValue: Double?
    @State private var stagedIntensityValue: Double?
    @State private var isAdjustingSpeed = false
    @State private var isAdjustingFxIntensity = false
    @State private var stagedCustomValues: [Int: Double] = [:]
    @State private var isAdjustingCustom: Set<Int> = []
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    @State private var colorSource: EffectColorSource = .gradient
    @State private var lastPaletteSelection: Int? = nil
    
    private static let defaultEffectGradient = LEDGradient(stops: [
        GradientStop(position: 0.0, hexColor: "FFA000"),
        GradientStop(position: 1.0, hexColor: "FFFFFF")
    ])
    private static let minimumSegmentBrightness: Double = 1.0

    private enum EffectColorSource: String, CaseIterable, Identifiable {
        case gradient
        case palette

        var id: String { rawValue }
    }
    
    private var colorPresets: [ColorPreset] {
        PresetsStore.shared.colorPresets
    }
    
    private var metadataBundle: EffectMetadataBundle? {
        viewModel.effectMetadata(for: device)
    }
    
    private var effectOptions: [EffectMetadata] {
        if advancedUIEnabled {
            return viewModel.allEffectOptions(for: device)
        }
        return viewModel.colorSafeEffectOptions(for: device)
    }

    private var paletteOptions: [PaletteMetadata] {
        metadataBundle?.palettes ?? []
    }
    
    private var currentState: DeviceEffectState {
        viewModel.currentEffectState(for: device, segmentId: segmentId)
    }
    
    private var isEffectEnabled: Bool {
        currentState.isEnabled
    }
    
    private var activeEffectMetadata: EffectMetadata? {
        effectOptions.first(where: { $0.id == effectSelectionId })
    }
    
    private var slotCount: Int {
        max(activeEffectMetadata?.colorSlotCount ?? 2, 1)
    }

    private var supportsPalettePicker: Bool {
        guard advancedUIEnabled else { return false }
        guard let metadata = activeEffectMetadata, metadata.supportsPalette else { return false }
        return !paletteOptions.isEmpty
    }

    private var isPaletteMode: Bool {
        supportsPalettePicker && colorSource == .palette
    }

    private var canEditGradient: Bool {
        slotCount >= 2 && !isPaletteMode
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

    private var customSliderParameters: [EffectParameter] {
        guard advancedUIEnabled else { return [] }
        return activeEffectMetadata?.parameters.filter { $0.kind == .genericSlider && $0.index >= 2 } ?? []
    }

    private var toggleParameters: [EffectParameter] {
        guard advancedUIEnabled else { return [] }
        return activeEffectMetadata?.parameters.filter { param in
            param.kind == .toggle && (5...7).contains(param.index)
        } ?? []
    }
    
    private var colorWheelOverlay: some View {
        let supportsCCT = viewModel.supportsCCT(for: device, segmentId: segmentId)
        let supportsWhite = viewModel.supportsWhite(for: device, segmentId: segmentId)
        let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: segmentId)
        return ColorWheelInline(
            initialColor: wheelInitial,
            canRemove: canEditGradient && effectGradient.stops.count > 1,
            supportsCCT: supportsCCT,
            supportsWhite: supportsWhite,
            usesKelvinCCT: usesKelvin,
            allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device)
                && viewModel.supportsCCTOutput(for: device, segmentId: segmentId),
            allowManualWhite: advancedUIEnabled,
            autoWhiteEnabled: viewModel.isAutoWhiteEnabled(for: device),
            cctKelvinRange: viewModel.cctKelvinRange(for: device),
            onColorChange: { color, _, _ in
                if canEditGradient {
                    // In gradient mode, we need a selected stop
                    // If selectedStopId is nil, try to use the first stop as fallback
                    let targetStopId = selectedStopId ?? effectGradient.stops.first?.id
                    
                    if let id = targetStopId,
                       let index = effectGradient.stops.firstIndex(where: { $0.id == id }) {
                        // Update only the selected stop
                        var stops = effectGradient.stops
                        stops[index].hexColor = color.toHex()
                        effectGradient = LEDGradient(stops: stops)
                        // Ensure selectedStopId is set if it was nil
                        if selectedStopId == nil {
                            selectedStopId = id
                        }
                    } else {
                        // No valid stop found - this shouldn't happen, but fallback to solid color
                        stagedSolidColor = color
                        effectGradient = LEDGradient(stops: [
                            GradientStop(position: 0.0, hexColor: color.toHex()),
                            GradientStop(position: 1.0, hexColor: color.toHex())
                        ])
                    }
                } else {
                    // Single color mode - update solid color
                    stagedSolidColor = color
                    effectGradient = LEDGradient(stops: [
                        GradientStop(position: 0.0, hexColor: color.toHex()),
                        GradientStop(position: 1.0, hexColor: color.toHex())
                    ])
                }
                wheelInitial = color
                hasPendingGradientChanges = true
                selectedColorPresetId = nil
                viewModel.updateEffectGradient(effectGradient, for: device)
                if isEffectEnabled {
                    scheduleAutoApply()
                }
            },
            onRemove: {
                if canEditGradient, let id = selectedStopId {
                    var stops = effectGradient.stops
                    if stops.count > 1 {
                        stops.removeAll { $0.id == id }
                        effectGradient = LEDGradient(stops: stops.sorted { $0.position < $1.position })
                        hasPendingGradientChanges = true
                        selectedColorPresetId = nil
                        viewModel.updateEffectGradient(effectGradient, for: device)
                        if isEffectEnabled {
                            scheduleAutoApply()
                        }
                    }
                }
                showColorPicker = false
            },
            onDismiss: {
                showColorPicker = false
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    init(
        device: WLEDDevice,
        segmentId: Int,
        isExpanded: Binding<Bool>,
        onActivate: @escaping () -> Void
    ) {
        self.device = device
        self.segmentId = segmentId
        self._isExpanded = isExpanded
        self.onActivate = onActivate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isExpanded {
                controls
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
        .task {
            let needsFetch = metadataBundle?.effects.isEmpty ?? true
            if needsFetch {
                isLoadingMetadata = true
            }
            await viewModel.loadEffectMetadata(for: device)
            if needsFetch {
                isLoadingMetadata = false
            }
            syncEffectSelectionIfNeeded()
            syncColorSourcePreference()
            await syncSegmentBrightnessFromDevice()
            if advancedUIEnabled, let metadata = activeEffectMetadata, metadata.isSoundReactive {
                await viewModel.refreshAudioReactiveStatus(for: device)
            }
            isInitializing = false
        }
        .onAppear {
            if currentState.isEnabled {
                isExpanded = true
                onActivate()
                effectSelectionId = currentState.effectId
            }
            syncEffectSelectionIfNeeded()
            syncColorSourcePreference()
            if advancedUIEnabled, !paletteOptions.isEmpty {
                Task { await viewModel.loadPalettePreviewsIfNeeded(for: device) }
            }
        }
        .onChange(of: currentState.effectId) { _, newValue in
            if currentState.isEnabled {
                isProgrammaticEffectSync = true
                effectSelectionId = newValue
                Task { @MainActor in
                    isProgrammaticEffectSync = false
                }
                if !isExpanded {
                    isExpanded = true
                    onActivate()
                }
                loadStagedGradient()
                syncColorSourcePreference()
            }
        }
        .onChange(of: effectSelectionId) { _, _ in
            if advancedUIEnabled, let metadata = activeEffectMetadata, metadata.isSoundReactive {
                Task { await viewModel.refreshAudioReactiveStatus(for: device) }
            }
        }
        .onChange(of: effectOptions.count) { _, _ in
            syncEffectSelectionIfNeeded()
            syncColorSourcePreference()
        }
        .onChange(of: paletteOptions.count) { _, _ in
            syncColorSourcePreference()
            if advancedUIEnabled, !paletteOptions.isEmpty {
                Task { await viewModel.loadPalettePreviewsIfNeeded(for: device) }
            }
        }
        .onChange(of: advancedUIEnabled) { _, _ in
            syncColorSourcePreference()
            if advancedUIEnabled, !paletteOptions.isEmpty {
                Task { await viewModel.loadPalettePreviewsIfNeeded(for: device) }
            }
        }
        .onChange(of: currentState.paletteId) { _, _ in
            syncColorSourcePreference()
        }
        .onReceive(
            viewModel.$devices
                .map { devices -> Int in
                    guard let live = devices.first(where: { $0.id == device.id }) else {
                        return viewModel.segmentBrightnessValue(for: device, segmentId: segmentId)
                    }
                    return viewModel.segmentBrightnessValue(for: live, segmentId: segmentId)
                }
                .removeDuplicates()
        ) { newBrightness in
            if !isAdjustingSegmentBrightness {
                segmentBrightness = Double(newBrightness)
            }
        }
        .onChange(of: currentState.isEnabled) { _, enabled in
            if enabled {
                if !isExpanded {
                    isExpanded = true
                    onActivate()
                }
            } else {
                showColorPicker = false
                autoApplyTask?.cancel()
                autoApplyTask = nil
                isExpanded = false
                stagedSpeedValue = nil
                stagedIntensityValue = nil
                isAdjustingSpeed = false
                isAdjustingFxIntensity = false
            }
        }
        .onChange(of: effectSelectionId) { _, newValue in
            guard newValue != 0 else { return }
            if isProgrammaticEffectSync {
                #if DEBUG
                print("[EffectsPane] Suppressing auto-apply during programmatic effect sync (effectId=\(newValue))")
                #endif
                return
            }
            loadStagedGradient()
            hasPendingGradientChanges = true
            if isEffectEnabled && !isInitializing {
                scheduleAutoApply(force: true)
            }
            stagedSpeedValue = nil
            stagedIntensityValue = nil
            isAdjustingSpeed = false
            isAdjustingFxIntensity = false
        }
        .onChange(of: viewModel.latestEffectGradientStops[device.id] ?? []) { _, newStops in
            guard !newStops.isEmpty else { return }
            // Preserve the selected stop's position before regenerating
            let selectedPosition = selectedStopId.flatMap { id in
                effectGradient.stops.first(where: { $0.id == id })?.position
            }
            
            effectGradient = preparedGradientForSlotCount(LEDGradient(stops: newStops), slotCount: slotCount)
            
            // Map the selected stop ID to the new stop by position
            if let position = selectedPosition {
                // Find the stop closest to the preserved position
                let sortedStops = effectGradient.stops.sorted { $0.position < $1.position }
                if let closestStop = sortedStops.min(by: { abs($0.position - position) < abs($1.position - position) }) {
                    selectedStopId = closestStop.id
                } else if let firstStop = sortedStops.first {
                    selectedStopId = firstStop.id
                }
            }
            
            if slotCount <= 1, let firstHex = newStops.first?.hexColor {
                stagedSolidColor = Color(hex: firstHex)
            }
        }
        .onChange(of: currentState.speed) { _, _ in
            if !isAdjustingSpeed {
                stagedSpeedValue = nil
            }
        }
        .onChange(of: currentState.intensity) { _, _ in
            if !isAdjustingFxIntensity {
                stagedIntensityValue = nil
            }
        }
        .onDisappear {
            autoApplyTask?.cancel()
            autoApplyTask = nil
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                onActivate()
            }
        }
        .sheet(isPresented: $showSavePresetDialog) {
            SaveEffectPresetDialog(
                device: device,
                currentEffectId: effectSelectionId,
                currentSpeed: currentState.speed,
                currentIntensity: currentState.intensity,
                currentPaletteId: currentState.paletteId,
                currentBrightness: Int(round(segmentBrightness))
            ) { preset in
                Task {
                    await saveEffectPreset(preset)
                }
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label("Animations", systemImage: "sparkles")
                    .font(AppTypography.style(.headline))
                    .foregroundColor(.white)
                Spacer()
                if isExpanded {
                    Button(action: {
                        if advancedUIEnabled {
                            showSavePresetDialog = true
                        } else {
                            Task { await saveEffectPresetDirectly() }
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
                    .disabled(isApplyingEffect || isSavingPreset)
                }

                Button(action: toggleEffect) {
                    HStack(spacing: 6) {
                        if isApplyingEffect {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: isEffectEnabled ? "power" : "poweroff")
                                .font(AppTypography.style(.caption))
                        }
                        Text(isEffectEnabled ? "ON" : "OFF")
                            .font(AppTypography.style(.caption, weight: .medium))
                    }
                    .foregroundColor(isEffectEnabled ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isEffectEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isApplyingEffect || effectOptions.isEmpty)
            }
            
            if !effectOptions.isEmpty && !isEffectEnabled {
                Text("Animated patterns that respect your color choices")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))
            } else if effectOptions.isEmpty {
                Text(isLoadingMetadata ? "Loading effects…" : "No color-safe effects available")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))
            }

            if advancedUIEnabled {
                let usesFallback = metadataBundle?.effects.isEmpty != false
                let sourceLabel = usesFallback ? "Fallback list" : "WLED fxdata"
                let mappingName = activeEffectMetadata?.name ?? "Unknown"
                Text("Effect ID \(effectSelectionId) · \(mappingName) · \(sourceLabel)")
                    .font(AppTypography.style(.caption2))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }
    
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            effectPicker
            if supportsPalettePicker {
                colorSourceToggle
            }
            if isPaletteMode {
                palettePicker
            } else if canEditGradient {
                gradientEditor
            } else {
                solidColorEditor
            }
            if advancedUIEnabled {
                segmentBrightnessControl
            }
            if showsSpeed {
                speedControl
            }
            if showsIntensity {
                intensityControl
            }
            if advancedUIEnabled {
                if let metadata = activeEffectMetadata, metadata.isSoundReactive {
                    audioReactiveNotice
                }
                if !customSliderParameters.isEmpty {
                    customSliders
                }
                if !toggleParameters.isEmpty {
                    toggleControls
                }
            }
        }
    }
    
    private var effectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Animation")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.7))
            
            Picker("Animation", selection: $effectSelectionId) {
                ForEach(effectOptions) { effect in
                    let label = effect.isSoundReactive ? "\(effect.name) · Sound-Activated" : effect.name
                    Text(label)
                        .tag(effect.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .disabled(isApplyingEffect || effectOptions.isEmpty)
            .accessibilityHint("Selects a lighting effect that keeps your chosen colors.")
        }
    }

    private var colorSourceToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color Source")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.7))
            Picker("Color Source", selection: $colorSource) {
                Text("Gradient").tag(EffectColorSource.gradient)
                Text("WLED Palette").tag(EffectColorSource.palette)
            }
            .pickerStyle(.segmented)
            .tint(.white)
            .onChange(of: colorSource) { _, newValue in
                handleColorSourceChange(newValue)
            }
            .disabled(isApplyingEffect)
            .accessibilityHint("Choose between your gradient colors or a WLED palette.")
        }
    }

    private var gradientEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gradient")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.7))
            GradientBar(
                gradient: Binding(
                    get: { effectGradient },
                    set: { newGradient in
                        effectGradient = newGradient
                        hasPendingGradientChanges = true
                        selectedColorPresetId = nil
                    }
                ),
                selectedStopId: $selectedStopId,
                allowsStopDrag: false,
                allowsStopRemoval: false,
                onTapStop: { id in
                    selectedStopId = id
                    if let stop = effectGradient.stops.first(where: { $0.id == id }) {
                        wheelInitial = stop.color
                        showColorPicker = true
                    }
                },
                onTapAnywhere: { t, _ in
                    let stops = effectGradient.stops
                    if stops.count >= slotCount {
                        if let nearest = stops.min(by: { abs($0.position - t) < abs($1.position - t) }) {
                            selectedStopId = nearest.id
                            wheelInitial = nearest.color
                            showColorPicker = true
                        }
                        return
                    }
                    let color = GradientSampler.sampleColor(at: t, stops: stops)
                    let newStop = GradientStop(position: t, hexColor: color.toHex())
                    var updatedStops = stops
                    updatedStops.append(newStop)
                    updatedStops.sort { $0.position < $1.position }
                    effectGradient = LEDGradient(stops: updatedStops)
                    selectedStopId = newStop.id
                    wheelInitial = color
                    showColorPicker = true
                    hasPendingGradientChanges = true
                    selectedColorPresetId = nil
                    viewModel.updateEffectGradient(effectGradient, for: device)
                    if isEffectEnabled {
                        scheduleAutoApply()
                    }
                },
                onStopsChanged: { stops, phase in
                    effectGradient = LEDGradient(stops: stops)
                    if phase == .ended {
                        hasPendingGradientChanges = true
                        selectedColorPresetId = nil
                        viewModel.updateEffectGradient(effectGradient, for: device)
                        if isEffectEnabled {
                            scheduleAutoApply()
                        }
                    }
                }
            )
            .frame(height: 56)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            if showColorPicker {
                colorWheelOverlay
            }
            if !colorPresets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(colorPresets) { preset in
                            presetChip(for: preset)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var solidColorEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.7))
            Button(action: {
                selectedStopId = effectGradient.stops.first?.id ?? UUID()
                wheelInitial = stagedSolidColor
                showColorPicker = true
            }) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(stagedSolidColor)
                    .frame(height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            if showColorPicker {
                colorWheelOverlay
            }
        }
    }
    
    private var segmentBrightnessControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Segment Brightness")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(round(segmentBrightness / 255.0 * 100)))%")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(
                value: Binding(
                    get: { segmentBrightness },
                    set: { newValue in
                        segmentBrightness = newValue
                    }
                ),
                in: Self.minimumSegmentBrightness...255.0,
                step: 1,
                onEditingChanged: { editing in
                    isAdjustingSegmentBrightness = editing
                    if !editing {
                        applySegmentBrightness()
                    }
                }
            )
            .tint(.white)
            .accessibilityLabel("Segment brightness")
            .accessibilityValue("\(Int(round(segmentBrightness / 255.0 * 100))) percent")
            .accessibilityHint("Adjusts brightness for this animation segment (global brightness still applies).")
            .disabled(!isEffectEnabled)
        }
    }
    
    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(speedLabel)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(currentSpeedSliderValue))")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(
                value: Binding(
                    get: { currentSpeedSliderValue },
                    set: { stagedSpeedValue = $0 }
                ),
                in: 0...255,
                step: 1,
                onEditingChanged: { editing in
                    isAdjustingSpeed = editing
                    if !editing {
                        applySpeedIfNeeded()
                    }
                }
            )
                .tint(.white)
            .accessibilityLabel("Animation speed")
            .accessibilityValue("\(Int(currentSpeedSliderValue))")
            .accessibilityHint("Adjusts the effect speed.")
                .disabled(isApplyingEffect)
        }
    }
    
    private var intensityControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(intensityLabel)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(currentIntensitySliderValue))")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(
                value: Binding(
                    get: { currentIntensitySliderValue },
                    set: { stagedIntensityValue = $0 }
                ),
                in: 0...255,
                step: 1,
                onEditingChanged: { editing in
                    isAdjustingFxIntensity = editing
                    if !editing {
                        applyIntensityIfNeeded()
                    }
                }
            )
            .tint(.white)
            .accessibilityLabel("Animation intensity")
            .accessibilityValue("\(Int(currentIntensitySliderValue))")
            .accessibilityHint("Adjusts the effect intensity.")
            .disabled(isApplyingEffect)
        }
    }

    private var audioReactiveNotice: some View {
        let status = viewModel.audioReactiveEnabled(for: device)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Audio Reactive")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if status == true {
                    Text("Enabled")
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.green)
                } else if status == false {
                    Text("Disabled")
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.orange)
                } else {
                    Text("Unknown")
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Text("Audio effects require the WLED audio usermod to be enabled.")
                .font(AppTypography.style(.caption2))
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 10) {
                Button("Check Status") {
                    Task { await viewModel.refreshAudioReactiveStatus(for: device) }
                }
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.15))
                )

                Button("Open Audio Settings") {
                    if let url = URL(string: "http://\(device.ipAddress)/settings/um") {
                        openURL(url)
                    }
                }
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.15))
                )
            }
        }
    }

    private var palettePicker: some View {
        let selectionBinding = Binding<Int>(
            get: { currentState.paletteId ?? lastPaletteSelection ?? paletteOptions.first?.id ?? 0 },
            set: { newValue in
                lastPaletteSelection = newValue
                Task {
                    await viewModel.updateEffectPalette(for: device, segmentId: segmentId, paletteId: newValue)
                }
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text("Palette")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.7))
            Picker("Palette", selection: selectionBinding) {
                ForEach(paletteOptions) { palette in
                    Text(palette.name)
                        .tag(palette.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .disabled(isApplyingEffect)
            .accessibilityHint("Choose a WLED palette for this effect.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(paletteOptions) { palette in
                        let stops = viewModel.palettePreviewStops(for: device, paletteId: palette.id, fallbackGradient: effectGradient)
                        Button {
                            selectionBinding.wrappedValue = palette.id
                        } label: {
                            PalettePreviewCard(
                                name: palette.name,
                                stops: stops,
                                isSelected: selectionBinding.wrappedValue == palette.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var customSliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(customSliderParameters) { param in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(param.label)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(Int(currentCustomSliderValue(for: param.index)))")
                            .font(AppTypography.style(.caption))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Slider(
                        value: Binding(
                            get: { currentCustomSliderValue(for: param.index) },
                            set: { stagedCustomValues[param.index] = $0 }
                        ),
                        in: 0...255,
                        step: 1,
                        onEditingChanged: { editing in
                            if editing {
                                isAdjustingCustom.insert(param.index)
                            } else {
                                isAdjustingCustom.remove(param.index)
                                applyCustomIfNeeded(param.index)
                            }
                        }
                    )
                    .tint(.white)
                    .disabled(isApplyingEffect)
                }
            }
        }
    }

    private var toggleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(toggleParameters) { param in
                if let optionIndex = optionIndex(for: param.index) {
                    Toggle(param.label, isOn: Binding(
                        get: { currentOptionValue(for: optionIndex) },
                        set: { newValue in
                            Task {
                                await viewModel.updateEffectOption(
                                    for: device,
                                    segmentId: segmentId,
                                    optionIndex: optionIndex,
                                    value: newValue
                                )
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .white))
                    .disabled(isApplyingEffect)
                }
            }
        }
    }
    
}

private struct PalettePreviewCard: View {
    let name: String
    let stops: [GradientStop]
    let isSelected: Bool

    private var gradientStops: [Gradient.Stop] {
        let resolvedStops = stops.isEmpty
            ? [GradientStop(position: 0.0, hexColor: "000000"),
               GradientStop(position: 1.0, hexColor: "000000")]
            : stops
        return resolvedStops.map { Gradient.Stop(color: Color(hex: $0.hexColor), location: $0.position) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    gradient: Gradient(stops: gradientStops),
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 120, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                )
            Text(name)
                .font(AppTypography.style(.caption2))
                .foregroundColor(.white.opacity(isSelected ? 0.95 : 0.7))
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
        )
    }
}

private extension EffectsPane {
    var backgroundFill: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 0.12 : 0.06)
    }
    
    func toggleExpansion() {
        if isExpanded {
            isExpanded = false
        } else {
            isExpanded = true
            onActivate()
        }
    }

    func scheduleAutoApply(force: Bool = false) {
        autoApplyTask?.cancel()
        autoApplyTask = Task { @MainActor in
            #if DEBUG
            print("[EffectsPane] scheduleAutoApply force=\(force) effectId=\(effectSelectionId) stops=\(effectGradient.stops.map { $0.hexColor })")
            #endif
            try? await Task.sleep(nanoseconds: 120_000_000)
            applyStagedEffect(force: force)
        }
    }

    func preparedGradientForSlotCount(_ gradient: LEDGradient, slotCount: Int) -> LEDGradient {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        if slotCount <= 1 {
            let hex = sortedStops.first?.hexColor ?? "FFFFFF"
            return LEDGradient(stops: [GradientStop(position: 0.0, hexColor: hex)])
        }
        let clampedCount = max(2, slotCount)
        let positions: [Double]
        if clampedCount == 2 {
            positions = [0.0, 1.0]
        } else {
            positions = (0..<clampedCount).map { Double($0) / Double(clampedCount - 1) }
        }
        let generatedStops = positions.map { t -> GradientStop in
            let sourceStops = sortedStops.isEmpty ? EffectsPane.defaultEffectGradient.stops : sortedStops
            let color = GradientSampler.sampleColor(at: t, stops: sourceStops)
            return GradientStop(position: t, hexColor: color.toHex())
        }
        return LEDGradient(stops: generatedStops)
    }

    func optionIndex(for parameterIndex: Int) -> Int? {
        switch parameterIndex {
        case 5:
            return 1
        case 6:
            return 2
        case 7:
            return 3
        default:
            return nil
        }
    }

    func currentOptionValue(for optionIndex: Int) -> Bool {
        switch optionIndex {
        case 1:
            return currentState.option1 ?? false
        case 2:
            return currentState.option2 ?? false
        case 3:
            return currentState.option3 ?? false
        default:
            return false
        }
    }
    
    func syncEffectSelectionIfNeeded() {
        isProgrammaticEffectSync = true
        let currentId = currentState.effectId
        if currentId > 0 {
            effectSelectionId = currentId
        } else if effectSelectionId == 0, let first = effectOptions.first {
            effectSelectionId = first.id
        }
        loadStagedGradient()
        stagedCustomValues = [:]
        isAdjustingCustom = []
        if slotCount <= 1, let firstHex = effectGradient.stops.first?.hexColor {
            stagedSolidColor = Color(hex: firstHex)
            wheelInitial = stagedSolidColor
        }
        hasPendingGradientChanges = false
        Task { @MainActor in
            isProgrammaticEffectSync = false
        }
    }

    private func syncColorSourcePreference() {
        guard supportsPalettePicker else {
            colorSource = .gradient
            return
        }
        if let paletteId = currentState.paletteId {
            lastPaletteSelection = paletteId
            colorSource = .palette
        } else {
            colorSource = .gradient
        }
    }

    private func handleColorSourceChange(_ newValue: EffectColorSource) {
        guard supportsPalettePicker else {
            colorSource = .gradient
            return
        }
        switch newValue {
        case .palette:
            let paletteId = currentState.paletteId
                ?? lastPaletteSelection
                ?? paletteOptions.first?.id
                ?? 0
            lastPaletteSelection = paletteId
            Task {
                await viewModel.updateEffectPalette(for: device, segmentId: segmentId, paletteId: paletteId)
            }
        case .gradient:
            Task {
                await viewModel.clearEffectPalette(for: device, segmentId: segmentId)
                await MainActor.run {
                    hasPendingGradientChanges = true
                    scheduleAutoApply(force: true)
                }
            }
        }
    }
    
    func loadStagedGradient() {
        // Preserve the selected stop's position before regenerating
        let selectedPosition = selectedStopId.flatMap { id in
            effectGradient.stops.first(where: { $0.id == id })?.position
        }

        if let storedStops = viewModel.effectGradientStops(for: device.id), !storedStops.isEmpty {
            let unique = Set(storedStops.map { $0.hexColor.uppercased() })
            let storedIsSingle = unique.count <= 1
            if slotCount > 1, storedIsSingle, let multiStops = viewModel.effectMultiStopGradientStops(for: device.id), !multiStops.isEmpty {
                effectGradient = preparedGradientForSlotCount(LEDGradient(stops: multiStops), slotCount: slotCount)
            } else {
            #if DEBUG
            print("[EffectsPane] loadStagedGradient using stored effect gradient: \(storedStops.map { $0.hexColor })")
            #endif
                effectGradient = preparedGradientForSlotCount(LEDGradient(stops: storedStops), slotCount: slotCount)
            }
        } else if let baseStops = viewModel.gradientStops(for: device.id), !baseStops.isEmpty {
            #if DEBUG
            print("[EffectsPane] loadStagedGradient using device gradient: \(baseStops.map { $0.hexColor })")
            #endif
            effectGradient = preparedGradientForSlotCount(LEDGradient(stops: baseStops), slotCount: slotCount)
        } else {
            let hex = device.currentColor.toHex()
            effectGradient = preparedGradientForSlotCount(LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: hex),
                GradientStop(position: 1.0, hexColor: hex)
            ]), slotCount: slotCount)
            #if DEBUG
            print("[EffectsPane] loadStagedGradient falling back to current color: \(hex)")
            #endif
        }
        selectedColorPresetId = nil
        
        // Map the selected stop ID to the new stop by position
        if let position = selectedPosition {
            // Find the stop closest to the preserved position
            let sortedStops = effectGradient.stops.sorted { $0.position < $1.position }
            if let closestStop = sortedStops.min(by: { abs($0.position - position) < abs($1.position - position) }) {
                selectedStopId = closestStop.id
            } else if let firstStop = sortedStops.first {
                selectedStopId = firstStop.id
            } else {
                selectedStopId = nil
            }
        } else {
            // Only clear selectedStopId if we didn't have a position to preserve
            selectedStopId = nil
        }
        
        if slotCount <= 1, let firstHex = effectGradient.stops.first?.hexColor {
            stagedSolidColor = Color(hex: firstHex)
            wheelInitial = stagedSolidColor
        }
        hasPendingGradientChanges = false
    }
    
    func applyStagedEffect(force: Bool) {
        guard effectSelectionId != 0 else { return }
        if !force && !hasPendingGradientChanges && currentState.isEnabled { return }
        
        // Preserve the selected stop's position before regenerating
        let selectedPosition = selectedStopId.flatMap { id in
            effectGradient.stops.first(where: { $0.id == id })?.position
        }
        
        let baseGradient = canEditGradient ? effectGradient : LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: stagedSolidColor.toHex())
        ])
        let preparedGradient = preparedGradientForSlotCount(baseGradient, slotCount: slotCount)
        viewModel.updateEffectGradient(preparedGradient, for: device)
        
        // Helper to map selected stop by position
        let mapSelectedStop: (LEDGradient) -> Void = { gradient in
            if let position = selectedPosition {
                let sortedStops = gradient.stops.sorted { $0.position < $1.position }
                if let closestStop = sortedStops.min(by: { abs($0.position - position) < abs($1.position - position) }) {
                    selectedStopId = closestStop.id
                } else if let firstStop = sortedStops.first {
                    selectedStopId = firstStop.id
                }
            }
        }
        
        if !force && !isEffectEnabled {
            effectGradient = preparedGradient
            mapSelectedStop(preparedGradient)
            if slotCount <= 1, let firstHex = preparedGradient.stops.first?.hexColor {
                stagedSolidColor = Color(hex: firstHex)
            }
            return
        }
        if !force && !hasPendingGradientChanges {
            return
        }
        isApplyingEffect = true
        hasPendingGradientChanges = false
        let liveDevice = viewModel.devices.first(where: { $0.id == device.id }) ?? device
        Task {
            let preferPalette = advancedUIEnabled && (currentState.paletteId != nil)
            await viewModel.applyColorSafeEffect(
                effectSelectionId,
                with: preparedGradient,
                segmentId: segmentId,
                device: liveDevice,
                userInitiated: true,
                preferPaletteIfAvailable: preferPalette,
                includeAllEffects: advancedUIEnabled
            )
            await MainActor.run {
                isApplyingEffect = false
                effectGradient = preparedGradient
                mapSelectedStop(preparedGradient)
                if slotCount <= 1, let firstHex = preparedGradient.stops.first?.hexColor {
                    stagedSolidColor = Color(hex: firstHex)
                }
            }
        }
    }
    
    @ViewBuilder
    private func presetChip(for preset: ColorPreset) -> some View {
        let isSelected = selectedColorPresetId == preset.id
        Button(action: {
            applyColorPreset(preset)
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
        .accessibilityLabel("\(preset.name) color preset")
        .accessibilityHint("Applies the color preset to the animation gradient.")
    }
    
    private func applyColorPreset(_ preset: ColorPreset) {
        let sortedStops = preset.gradientStops.sorted { $0.position < $1.position }
        guard !sortedStops.isEmpty else { return }
        
        let newGradient = LEDGradient(stops: sortedStops, interpolation: effectGradient.interpolation)
        effectGradient = newGradient
        selectedStopId = nil
        selectedColorPresetId = preset.id
        stagedSolidColor = Color(hex: sortedStops.first?.hexColor ?? "FFFFFF")
        hasPendingGradientChanges = true
        viewModel.updateEffectGradient(newGradient, for: device)
        if isEffectEnabled {
            scheduleAutoApply(force: true)
        }
    }

    private func applySegmentBrightness() {
        guard isEffectEnabled else { return }
        let target = max(
            1,
            min(255, Int(segmentBrightness.rounded()))
        )
        Task {
            await viewModel.updateSegmentBrightness(for: device, segmentId: segmentId, brightness: target)
        }
    }
    
    private var currentSpeedSliderValue: Double {
        stagedSpeedValue ?? Double(currentState.speed)
    }
    
    private var currentIntensitySliderValue: Double {
        stagedIntensityValue ?? Double(currentState.intensity)
    }

    private func currentCustomSliderValue(for index: Int) -> Double {
        if let staged = stagedCustomValues[index] {
            return staged
        }
        switch index {
        case 2:
            return Double(currentState.custom1 ?? 128)
        case 3:
            return Double(currentState.custom2 ?? 128)
        case 4:
            return Double(currentState.custom3 ?? 128)
        default:
            return 0
        }
    }

    private func currentCustomValueInt(for index: Int) -> Int {
        switch index {
        case 2:
            return currentState.custom1 ?? 128
        case 3:
            return currentState.custom2 ?? 128
        case 4:
            return currentState.custom3 ?? 128
        default:
            return 0
        }
    }
    
    private func applySpeedIfNeeded() {
        let target = Int(round(stagedSpeedValue ?? Double(currentState.speed)))
        guard target != currentState.speed else {
            stagedSpeedValue = nil
            return
        }
        stagedSpeedValue = Double(target)
        isApplyingEffect = true
        Task {
            await viewModel.updateEffectSpeed(for: device, segmentId: segmentId, speed: target)
            await MainActor.run {
                isApplyingEffect = false
                stagedSpeedValue = nil
            }
        }
    }
    
    private func applyIntensityIfNeeded() {
        let target = Int(round(stagedIntensityValue ?? Double(currentState.intensity)))
        guard target != currentState.intensity else {
            stagedIntensityValue = nil
            return
        }
        stagedIntensityValue = Double(target)
        isApplyingEffect = true
        Task {
            await viewModel.updateEffectIntensity(for: device, segmentId: segmentId, intensity: target)
            await MainActor.run {
                isApplyingEffect = false
                stagedIntensityValue = nil
            }
        }
    }

    private func applyCustomIfNeeded(_ index: Int) {
        let target = Int(round(stagedCustomValues[index] ?? Double(currentCustomValueInt(for: index))))
        guard target != currentCustomValueInt(for: index) else {
            stagedCustomValues[index] = nil
            return
        }
        stagedCustomValues[index] = Double(target)
        isApplyingEffect = true
        Task {
            await viewModel.updateEffectCustomParameter(for: device, segmentId: segmentId, index: index, value: target)
            await MainActor.run {
                isApplyingEffect = false
                stagedCustomValues[index] = nil
            }
        }
    }

    @MainActor
    private func currentSegmentBrightness() -> Int {
        viewModel.segmentBrightnessValue(for: device, segmentId: segmentId)
    }

    @MainActor
    private func syncSegmentBrightnessFromDevice() async {
        segmentBrightness = Double(currentSegmentBrightness())
    }
    
    func toggleEffect() {
        guard !effectOptions.isEmpty else { return }
        let currentlyEnabled = isEffectEnabled
        #if DEBUG
        print("[EffectsPane] toggleEffect currentlyEnabled=\(currentlyEnabled) selection=\(effectSelectionId)")
        #endif
        isApplyingEffect = true
        Task {
            if currentlyEnabled {
                await viewModel.disableEffect(for: device, segmentId: segmentId)
                await MainActor.run {
                    isApplyingEffect = false
                    isExpanded = false
                    autoApplyTask?.cancel()
                    autoApplyTask = nil
                }
            } else {
                if effectSelectionId == 0, let first = effectOptions.first {
                    effectSelectionId = first.id
                }
                await MainActor.run {
                    isExpanded = true
                    onActivate()
                    loadStagedGradient()
                    isApplyingEffect = false
                    stagedSpeedValue = nil
                    stagedIntensityValue = nil
                }
                applyStagedEffect(force: true)
            }
        }
    }
    
    func saveEffectPresetDirectly() async {
        guard !effectOptions.isEmpty else { return }
        let preparedGradient = preparedGradientForSlotCount(effectGradient, slotCount: slotCount)
        let preset = WLEDEffectPreset(
            name: "Effect \(Date().presetNameTimestamp())",
            deviceId: device.id,
            effectId: effectSelectionId,
            speed: currentState.speed,
            intensity: currentState.intensity,
            paletteId: currentState.paletteId,
            gradientStops: preparedGradient.stops,
            gradientInterpolation: preparedGradient.interpolation,
            brightness: device.brightness
        )
        await saveEffectPreset(preset)
    }

    func saveEffectPreset(_ presetInput: WLEDEffectPreset) async {
        isSavingPreset = true
        showSaveSuccess = false
        var preset = presetInput
        do {
            let savedId = try await PresetSyncManager.shared.saveEffectPreset(preset, to: device)
            await MainActor.run {
                preset.wledPresetId = savedId
                PresetsStore.shared.addEffectPreset(preset)
                isSavingPreset = false
                showSaveSuccess = true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                showSaveSuccess = false
            }
            #if DEBUG
            print("✅ Effect preset saved to WLED device: ID \(savedId)")
            #endif
        } catch {
            await MainActor.run {
                isSavingPreset = false
                showSaveSuccess = false
            }
            #if DEBUG
            print("⚠️ Failed to save effect preset to WLED: \(error.localizedDescription)")
            #endif
        }
    }
}
