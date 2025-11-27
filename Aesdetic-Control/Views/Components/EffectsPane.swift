import SwiftUI
import Combine

struct EffectsPane: View {
    @EnvironmentObject private var viewModel: DeviceControlViewModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let device: WLEDDevice
    let segmentId: Int
    @Binding var isExpanded: Bool
    let onActivate: () -> Void
    
    @State private var isApplyingEffect = false
    @State private var isLoadingMetadata = false
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    @State private var effectSelectionId: Int = 0
    @State private var effectGradient: LEDGradient = EffectsPane.defaultEffectGradient
    @State private var stagedSolidColor: Color = .white
    @State private var selectedStopId: UUID?
    @State private var showColorPicker = false
    @State private var wheelInitial: Color = .white
    @State private var hasPendingGradientChanges = false
    @State private var autoApplyTask: Task<Void, Never>? = nil
    @State private var selectedColorPresetId: UUID? = nil
    @State private var animationBrightness: Double = 1.0
    @State private var isAdjustingAnimationBrightness = false
    @State private var baselineAnimationBrightness: Int? = nil
    @State private var stagedSpeedValue: Double?
    @State private var stagedIntensityValue: Double?
    @State private var isAdjustingSpeed = false
    @State private var isAdjustingFxIntensity = false
    
    private static let defaultEffectGradient = LEDGradient(stops: [
        GradientStop(position: 0.0, hexColor: "FFA000"),
        GradientStop(position: 1.0, hexColor: "FFFFFF")
    ])
    private static let minimumAnimationBrightness: Double = 0.05
    
    private var colorPresets: [ColorPreset] {
        PresetsStore.shared.colorPresets
    }
    
    private var metadataBundle: EffectMetadataBundle? {
        viewModel.effectMetadata(for: device)
    }
    
    private var effectOptions: [EffectMetadata] {
        viewModel.colorSafeEffectOptions(for: device)
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
            if effectOptions.isEmpty {
                isLoadingMetadata = true
                await viewModel.loadEffectMetadata(for: device)
                isLoadingMetadata = false
            }
            syncEffectSelectionIfNeeded()
            await syncAnimationBrightnessFromDevice()
        }
        .onAppear {
            if currentState.isEnabled {
                isExpanded = true
                onActivate()
                effectSelectionId = currentState.effectId
                rememberBaselineBrightnessIfNeeded()
            }
            syncEffectSelectionIfNeeded()
        }
        .onChange(of: currentState.effectId) { _, newValue in
            if currentState.isEnabled {
                effectSelectionId = newValue
                if !isExpanded {
                    isExpanded = true
                    onActivate()
                }
                loadStagedGradient()
            }
        }
        .onChange(of: effectOptions.count) { _, _ in
            syncEffectSelectionIfNeeded()
        }
        .onReceive(
            viewModel.$devices
                .map { devices -> Int in
                    guard let live = devices.first(where: { $0.id == device.id }) else {
                        return device.brightness
                    }
                    return viewModel.getEffectiveBrightness(for: live)
                }
                .removeDuplicates()
        ) { newBrightness in
            let ratio = Double(newBrightness) / 255.0
            if !isAdjustingAnimationBrightness {
                animationBrightness = min(1.0, max(Self.minimumAnimationBrightness, ratio))
            }
            if isEffectEnabled && !isAdjustingAnimationBrightness {
                baselineAnimationBrightness = newBrightness
            }
        }
        .onChange(of: currentState.isEnabled) { _, enabled in
            if enabled {
                rememberBaselineBrightnessIfNeeded()
                if !isExpanded {
                    isExpanded = true
                    onActivate()
                }
            } else {
                showColorPicker = false
                autoApplyTask?.cancel()
                autoApplyTask = nil
                isExpanded = false
                Task { await MainActor.run { restoreBaselineBrightnessIfNeeded() } }
                stagedSpeedValue = nil
                stagedIntensityValue = nil
                isAdjustingSpeed = false
                isAdjustingFxIntensity = false
            }
        }
        .onChange(of: effectSelectionId) { _, newValue in
            guard newValue != 0 else { return }
            loadStagedGradient()
            hasPendingGradientChanges = true
            if isEffectEnabled {
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
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label("Animations", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if isExpanded {
                    Button(action: { Task { await saveEffectPresetDirectly() } }) {
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
                                .font(.caption)
                        }
                        Text(isEffectEnabled ? "ON" : "OFF")
                            .font(.caption.weight(.medium))
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
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            } else if effectOptions.isEmpty {
                Text(isLoadingMetadata ? "Loading effects…" : "No color-safe effects available")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            effectPicker
            if canEditGradient {
                gradientEditor
            } else {
                solidColorEditor
            }
            animationBrightnessControl
            if showsSpeed {
                speedControl
            }
            if showsIntensity {
                intensityControl
            }
        }
    }
    
    private var effectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Animation")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Picker("Animation", selection: $effectSelectionId) {
                ForEach(effectOptions) { effect in
                    Text(effect.name)
                        .tag(effect.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .disabled(isApplyingEffect || effectOptions.isEmpty)
            .accessibilityHint("Selects a lighting effect that keeps your chosen colors.")
        }
    }

    private var gradientEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gradient")
                .font(.caption)
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
                onTapStop: { id in
                    selectedStopId = id
                    if let stop = effectGradient.stops.first(where: { $0.id == id }) {
                        wheelInitial = stop.color
                        showColorPicker = true
                    }
                },
                onTapAnywhere: { t, _ in
                    let color = GradientSampler.sampleColor(at: t, stops: effectGradient.stops)
                    let newStop = GradientStop(position: t, hexColor: color.toHex())
                    var stops = effectGradient.stops
                    stops.append(newStop)
                    stops.sort { $0.position < $1.position }
                    effectGradient = LEDGradient(stops: stops)
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
                .font(.caption)
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
    
    private var animationBrightnessControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Animation Brightness")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(animationBrightness * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(
                value: Binding(
                    get: { animationBrightness },
                    set: { newValue in
                        animationBrightness = newValue
                    }
                ),
                in: Self.minimumAnimationBrightness...1.0,
                step: 0.01,
                onEditingChanged: { editing in
                    isAdjustingAnimationBrightness = editing
                    if editing {
                        rememberBaselineBrightnessIfNeeded()
                    } else {
                        applyAnimationBrightness()
                    }
                }
            )
            .tint(.white)
            .accessibilityLabel("Animation brightness")
            .accessibilityValue("\(Int(animationBrightness * 100)) percent")
            .accessibilityHint("Adjusts WLED brightness for animations.")
            .disabled(!isEffectEnabled)
        }
    }
    
    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(speedLabel)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(currentSpeedSliderValue))")
                    .font(.caption)
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
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(currentIntensitySliderValue))")
                    .font(.caption)
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
    
    func syncEffectSelectionIfNeeded() {
        let currentId = currentState.effectId
        if currentId > 0 {
            effectSelectionId = currentId
        } else if effectSelectionId == 0, let first = effectOptions.first {
            effectSelectionId = first.id
        }
        loadStagedGradient()
        if slotCount <= 1, let firstHex = effectGradient.stops.first?.hexColor {
            stagedSolidColor = Color(hex: firstHex)
            wheelInitial = stagedSolidColor
        }
        hasPendingGradientChanges = false
    }
    
    func loadStagedGradient() {
        // Preserve the selected stop's position before regenerating
        let selectedPosition = selectedStopId.flatMap { id in
            effectGradient.stops.first(where: { $0.id == id })?.position
        }
        
        if let storedStops = viewModel.effectGradientStops(for: device.id), !storedStops.isEmpty {
            #if DEBUG
            print("[EffectsPane] loadStagedGradient using stored effect gradient: \(storedStops.map { $0.hexColor })")
            #endif
            effectGradient = preparedGradientForSlotCount(LEDGradient(stops: storedStops), slotCount: slotCount)
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
            await viewModel.applyColorSafeEffect(effectSelectionId, with: preparedGradient, segmentId: segmentId, device: liveDevice)
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

    private func applyAnimationBrightness() {
        guard isEffectEnabled else { return }
        let target = max(
            1,
            min(255, Int((animationBrightness * 255.0).rounded()))
        )
        rememberBaselineBrightnessIfNeeded()
        Task {
            await viewModel.updateDeviceBrightness(device, brightness: target)
            await MainActor.run {
                baselineAnimationBrightness = target
            }
        }
    }
    
    private var currentSpeedSliderValue: Double {
        stagedSpeedValue ?? Double(currentState.speed)
    }
    
    private var currentIntensitySliderValue: Double {
        stagedIntensityValue ?? Double(currentState.intensity)
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

    @MainActor
    private func currentEffectiveBrightness() -> Int {
        if let live = viewModel.devices.first(where: { $0.id == device.id }) {
            return viewModel.getEffectiveBrightness(for: live)
        }
        return viewModel.getEffectiveBrightness(for: device)
    }

    @MainActor
    private func syncAnimationBrightnessFromDevice() async {
        let brightness = currentEffectiveBrightness()
        let ratio = Double(brightness) / 255.0
        animationBrightness = min(1.0, max(Self.minimumAnimationBrightness, ratio))
    }

    @MainActor
    private func rememberBaselineBrightnessIfNeeded() {
        if baselineAnimationBrightness == nil {
            baselineAnimationBrightness = currentEffectiveBrightness()
        }
    }

    @MainActor
    private func restoreBaselineBrightnessIfNeeded() {
        guard let baseline = baselineAnimationBrightness else { return }
        baselineAnimationBrightness = nil
        Task {
            await viewModel.updateDeviceBrightness(device, brightness: baseline)
        }
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
                await MainActor.run {
                    restoreBaselineBrightnessIfNeeded()
                }
            } else {
                if effectSelectionId == 0, let first = effectOptions.first {
                    effectSelectionId = first.id
                }
                await MainActor.run {
                    rememberBaselineBrightnessIfNeeded()
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
        isSavingPreset = true
        let presetName = "Effect " + Date().formatted(date: .omitted, time: .shortened)
        let preparedGradient = preparedGradientForSlotCount(effectGradient, slotCount: slotCount)
        let preset = WLEDEffectPreset(
            name: presetName,
            deviceId: device.id,
            effectId: effectSelectionId,
            speed: currentState.speed,
            intensity: currentState.intensity,
            paletteId: currentState.paletteId,
            gradientStops: preparedGradient.stops,
            gradientInterpolation: preparedGradient.interpolation,
            brightness: device.brightness
        )
        await MainActor.run {
            PresetsStore.shared.addEffectPreset(preset)
            isSavingPreset = false
            showSaveSuccess = true
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
            showSaveSuccess = false
        }
    }
}


