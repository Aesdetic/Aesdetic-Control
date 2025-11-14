import SwiftUI

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
    
    private static let defaultEffectGradient = LEDGradient(stops: [
        GradientStop(position: 0.0, hexColor: "FFA000"),
        GradientStop(position: 1.0, hexColor: "FFFFFF")
    ])
    
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
    
    private var speedBinding: Binding<Double> {
        Binding(
            get: { Double(currentState.speed) },
            set: { newValue in
                isApplyingEffect = true
                Task {
                    await viewModel.updateEffectSpeed(for: device, segmentId: segmentId, speed: Int(newValue.rounded()))
                    await MainActor.run {
                        isApplyingEffect = false
                    }
                }
            }
        )
    }
    
    private var intensityBinding: Binding<Double> {
        Binding(
            get: { Double(currentState.intensity) },
            set: { newValue in
                isApplyingEffect = true
                Task {
                    await viewModel.updateEffectIntensity(for: device, segmentId: segmentId, intensity: Int(newValue.rounded()))
                    await MainActor.run {
                        isApplyingEffect = false
                    }
                }
            }
        )
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
                if canEditGradient, let id = selectedStopId,
                   let index = effectGradient.stops.firstIndex(where: { $0.id == id }) {
                    var stops = effectGradient.stops
                    stops[index].hexColor = color.toHex()
                    effectGradient = LEDGradient(stops: stops)
                } else {
                    stagedSolidColor = color
                    effectGradient = LEDGradient(stops: [
                        GradientStop(position: 0.0, hexColor: color.toHex()),
                        GradientStop(position: 1.0, hexColor: color.toHex())
                    ])
                }
                wheelInitial = color
                hasPendingGradientChanges = true
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
        }
        .onAppear {
            if currentState.isEnabled {
                isExpanded = true
                onActivate()
                effectSelectionId = currentState.effectId
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
        .onChange(of: effectSelectionId) { _, newValue in
            guard newValue != 0 else { return }
            loadStagedGradient()
            hasPendingGradientChanges = true
            if isEffectEnabled {
                scheduleAutoApply(force: true)
            }
        }
        .onChange(of: viewModel.latestEffectGradientStops[device.id] ?? []) { _, newStops in
            guard !newStops.isEmpty else { return }
            effectGradient = preparedGradientForSlotCount(LEDGradient(stops: newStops), slotCount: slotCount)
            if slotCount <= 1, let firstHex = newStops.first?.hexColor {
                stagedSolidColor = Color(hex: firstHex)
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
                Label("Effects", systemImage: "sparkles")
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
            
            if isEffectEnabled && !effectOptions.isEmpty {
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
            if showsSpeed {
                sliderRow(label: speedLabel, value: speedBinding)
            }
            if showsIntensity {
                sliderRow(label: intensityLabel, value: intensityBinding)
            }
        }
    }
    
    private var effectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Effect")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Picker("Effect", selection: $effectSelectionId) {
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
                    viewModel.updateEffectGradient(effectGradient, for: device)
                    if isEffectEnabled {
                        scheduleAutoApply()
                    }
                },
                onStopsChanged: { stops, phase in
                    effectGradient = LEDGradient(stops: stops)
                    if phase == .ended {
                        hasPendingGradientChanges = true
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
    
    private func sliderRow(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: value, in: 0...255, step: 1)
                .tint(.white)
                .disabled(isApplyingEffect)
                .accessibilityLabel(label)
                .accessibilityValue("\(Int(value.wrappedValue))")
                .accessibilityHint("Adjusts \(label.lowercased()) for the current effect.")
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
            let color = GradientSampler.sampleColor(at: t, stops: sortedStops.isEmpty ? EffectsPane.defaultEffectGradient.stops : sortedStops)
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
        if let baseStops = viewModel.gradientStops(for: device.id), !baseStops.isEmpty {
            #if DEBUG
            print("[EffectsPane] loadStagedGradient using device gradient: \(baseStops.map { $0.hexColor })")
            #endif
            effectGradient = preparedGradientForSlotCount(LEDGradient(stops: baseStops), slotCount: slotCount)
        } else if let storedStops = viewModel.effectGradientStops(for: device.id), !storedStops.isEmpty {
            #if DEBUG
            print("[EffectsPane] loadStagedGradient using stored effect gradient: \(storedStops.map { $0.hexColor })")
            #endif
            effectGradient = preparedGradientForSlotCount(LEDGradient(stops: storedStops), slotCount: slotCount)
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
        if slotCount <= 1, let firstHex = effectGradient.stops.first?.hexColor {
            stagedSolidColor = Color(hex: firstHex)
            wheelInitial = stagedSolidColor
        }
        hasPendingGradientChanges = false
        selectedStopId = nil
    }
    
    func applyStagedEffect(force: Bool) {
        guard effectSelectionId != 0 else { return }
        if !force && !hasPendingGradientChanges && currentState.isEnabled { return }
        let baseGradient = canEditGradient ? effectGradient : LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: stagedSolidColor.toHex())
        ])
        let preparedGradient = preparedGradientForSlotCount(baseGradient, slotCount: slotCount)
        viewModel.updateEffectGradient(preparedGradient, for: device)
        if !force && !isEffectEnabled {
            effectGradient = preparedGradient
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
        Task {
            await viewModel.applyColorSafeEffect(effectSelectionId, with: preparedGradient, segmentId: segmentId, device: device)
            await MainActor.run {
                isApplyingEffect = false
                effectGradient = preparedGradient
                if slotCount <= 1, let firstHex = preparedGradient.stops.first?.hexColor {
                    stagedSolidColor = Color(hex: firstHex)
                }
            }
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
            } else {
                if effectSelectionId == 0, let first = effectOptions.first {
                    effectSelectionId = first.id
                }
                await MainActor.run {
                    isExpanded = true
                    onActivate()
                    loadStagedGradient()
                    isApplyingEffect = false
                }
                applyStagedEffect(force: true)
            }
        }
    }
    
    func saveEffectPresetDirectly() async {
        guard !effectOptions.isEmpty else { return }
        isSavingPreset = true
        let presetName = "Effect " + Date().formatted(date: .omitted, time: .shortened)
        let preset = WLEDEffectPreset(
            name: presetName,
            deviceId: device.id,
            effectId: effectSelectionId,
            speed: currentState.speed,
            intensity: currentState.intensity,
            paletteId: currentState.paletteId,
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


