import SwiftUI

struct UnifiedColorPane: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let device: WLEDDevice
    @Binding var dismissColorPicker: Bool
    let segmentId: Int  // Track which segment we're controlling

    @State private var gradient: LEDGradient?
    @State private var selectedStopId: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var briUI: Double
    @State private var applyWorkItem: DispatchWorkItem? = nil
    @State private var stopTemperatures: [UUID: Double] = [:]  // Track temperature (0-1) for each stop
    @State private var stopWhiteLevels: [UUID: Double] = [:]  // Track white level (0-1) for each stop
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    @State private var isAdjustingBrightness = false
    @State private var lastBrightnessSet: Date? = nil  // Track when brightness was last set by user
    @State private var interpolationMode: GradientInterpolation = .linear  // Gradient interpolation mode
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false

    private var liveDevice: WLEDDevice? {
        viewModel.devices.first(where: { $0.id == device.id })
    }
    
    private var activeDevice: WLEDDevice {
        liveDevice ?? device
    }
    
    init(device: WLEDDevice, dismissColorPicker: Binding<Bool>, segmentId: Int = 0) {
        self.device = device
        _dismissColorPicker = dismissColorPicker
        self.segmentId = segmentId
        _briUI = State(initialValue: Double(device.brightness))
        
        // Initialize gradient from device's current color
        // Will be restored from persisted gradient in onAppear
        let deviceColorHex = device.currentColor.toHex()
        _gradient = State(initialValue: LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: deviceColorHex),
            GradientStop(position: 1.0, hexColor: deviceColorHex)
        ], interpolation: .linear))
    }
    
    // Direct gradient access (no longer lazy)
    private var currentGradient: LEDGradient {
        let defaultGradient = LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: activeDevice.currentColor.toHex()),
            GradientStop(position: 1.0, hexColor: activeDevice.currentColor.toHex())
        ], interpolation: interpolationMode)
        let result = gradient ?? defaultGradient
        // Sync interpolation mode with gradient (deferred to avoid state modification during view update)
        // This sync happens in onAppear/task instead
        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header with Preset button (matching Transition/Effects style)
            HStack {
                Label("Colors", systemImage: "paintbrush.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                Button(action: {
                    Task {
                        await saveColorPresetDirectly()
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
            .padding(.horizontal, 16)
            
            // Brightness with percent label; apply on release
            VStack(spacing: 6) {
                HStack {
                    Text("Brightness")
                        .foregroundColor(primaryLabelColor)
                    Spacer()
                    Text("\(Int(round(briUI/255.0*100)))%")
                        .foregroundColor(secondaryLabelColor)
                }
                Slider(value: $briUI, in: 0...255, step: 1, onEditingChanged: { editing in
                    isAdjustingBrightness = editing
                    if !editing {
                        // CRITICAL: Mark when brightness was set to prevent WebSocket overwrites
                        lastBrightnessSet = Date()
                        DispatchQueue.main.async {
                            Task { await viewModel.updateDeviceBrightness(device, brightness: Int(briUI)) }
                        }
                    }
                })
                .tint(sliderTintColor)
                .sensorySelection(trigger: Int(briUI))
                .accessibilityLabel("Brightness")
                .accessibilityValue("\(Int(round(briUI / 255.0 * 100))) percent")
                .accessibilityHint("Adjusts the segment brightness.")
                .accessibilityAdjustableAction { direction in
                    let step: Double = 12.75 // roughly 5%
                    switch direction {
                    case .increment:
                        briUI = min(255, briUI + step)
                    case .decrement:
                        briUI = max(0, briUI - step)
                    @unknown default:
                        break
                    }
                    let brightnessValue = Int(round(briUI))
                    // CRITICAL: Mark when brightness was set to prevent WebSocket overwrites
                    lastBrightnessSet = Date()
                    DispatchQueue.main.async {
                        Task { await viewModel.updateDeviceBrightness(device, brightness: brightnessValue) }
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Interpolation mode selector (only show when multiple stops)
            if advancedUIEnabled, currentGradient.stops.count >= 2 {
                VStack(spacing: 6) {
                    HStack {
                        Text("Blend Style")
                            .foregroundColor(primaryLabelColor)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GradientInterpolation.allCases, id: \.self) { mode in
                                Button(action: {
                                    interpolationMode = mode
                                    var updatedGradient = currentGradient
                                    updatedGradient.interpolation = mode
                                    gradient = updatedGradient
                                    // Apply immediately when interpolation changes
                                    Task { await applyNow(stops: updatedGradient.stops) }
                                }) {
                                    Text(mode.displayName)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(interpolationMode == mode ? .black : .white.opacity(0.8))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(interpolationMode == mode ? Color.white : Color.white.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 16)
            }

            GradientBar(
                gradient: Binding(
                    get: { currentGradient },
                    set: { newGradient in
                        gradient = newGradient
                    }
                ),
                selectedStopId: $selectedStopId,
                onTapStop: { id in
                    print("🎨 onTapStop called with id: \(id)")
                    if let stop = currentGradient.stops.first(where: { $0.id == id }) {
                        print("🎨 Found stop with color: \(stop.color)")
                        wheelInitial = stop.color
                        showWheel = true
                        print("🎨 showWheel set to: \(showWheel)")
                    } else {
                        print("❌ Stop not found for id: \(id)")
                    }
                },
                onTapAnywhere: { t, tapped in
                    // Sample color from current gradient at tap position (use current interpolation mode)
                    let color = GradientSampler.sampleColor(at: t, stops: currentGradient.stops, interpolation: currentGradient.interpolation)
                    let new = GradientStop(position: t, hexColor: color.toHex())
                    var updatedGradient = currentGradient
                    updatedGradient.stops.append(new)
                    updatedGradient.stops.sort { $0.position < $1.position }
                    
                    // Inherit temperature from nearest existing stop
                    if !stopTemperatures.isEmpty {
                        // Find the nearest stop by position
                        let sortedStops = updatedGradient.stops.sorted { $0.position < $1.position }
                        if let newIndex = sortedStops.firstIndex(where: { $0.id == new.id }) {
                            var nearestTemperature: Double? = nil
                            var minDistance: Double = Double.greatestFiniteMagnitude
                            
                            // Check stops before and after the new one
                            for (idx, stop) in sortedStops.enumerated() {
                                if idx != newIndex, let temp = stopTemperatures[stop.id] {
                                    let distance = abs(stop.position - new.position)
                                    if distance < minDistance {
                                        minDistance = distance
                                        nearestTemperature = temp
                                    }
                                }
                            }
                            
                            // If found a nearby stop with temperature, inherit it
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
                                if idx != newIndex, let level = stopWhiteLevels[stop.id] {
                                    let distance = abs(stop.position - new.position)
                                    if distance < minDistance {
                                        minDistance = distance
                                        nearestWhite = level
                                    }
                                }
                            }

                            if let inheritedWhite = nearestWhite {
                                stopWhiteLevels[new.id] = inheritedWhite
                            }
                        }
                    }
                    
                    gradient = updatedGradient
                    selectedStopId = new.id
                    
                    // Immediately apply the new gradient with the added stop
                    Task { await applyNow(stops: updatedGradient.stops) }
                },
                onStopsChanged: { stops, phase in
                    throttleApply(stops: stops, phase: phase)
                }
            )
            .frame(height: 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gradient editor")
            .accessibilityValue("\(currentGradient.stops.count) color stops")
            .accessibilityHint("Double tap a stop to edit its color or double tap in the gradient to add a new stop.")
            .padding(.horizontal, 16)
            
            // Inline color picker
            // In 1-tab mode (single stop), automatically select the first stop if none selected
            if showWheel {
                // Ensure selectedStopId is set in 1-tab mode
                let effectiveSelectedId = selectedStopId ?? currentGradient.stops.first?.id
                
                if let selectedId = effectiveSelectedId {
                    let supportsCCT = viewModel.supportsCCT(for: device, segmentId: segmentId)
                    let supportsWhite = viewModel.supportsWhite(for: device, segmentId: segmentId)
                    let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: segmentId)
                    ColorWheelInline(
                        initialColor: wheelInitial,
                        initialTemperature: stopTemperatures[selectedId],
                        initialWhiteLevel: stopWhiteLevels[selectedId],
                        canRemove: currentGradient.stops.count > 1,
                        supportsCCT: supportsCCT,
                        supportsWhite: supportsWhite,
                        usesKelvinCCT: usesKelvin,
                        allowCCTForTemperatureStops: viewModel.temperatureStopsUseCCT(for: device),
                        allowManualWhite: advancedUIEnabled,
                        cctKelvinRange: viewModel.cctKelvinRange(for: device),
                        onColorChange: { color, temperature, whiteLevel in
                            // Use the selectedId (already unwrapped, so guaranteed non-nil)
                            guard let idx = currentGradient.stops.firstIndex(where: { $0.id == selectedId }) else {
                                // If no stop found, create/update the first stop
                                var updatedGradient = currentGradient
                                if updatedGradient.stops.isEmpty {
                                    let newStop = GradientStop(position: 0.0, hexColor: color.toHex())
                                    updatedGradient.stops = [newStop]
                                    if let temp = temperature {
                                        stopTemperatures[newStop.id] = temp
                                        if let white = whiteLevel {
                                            stopWhiteLevels[newStop.id] = white
                                        } else {
                                            stopWhiteLevels.removeValue(forKey: newStop.id)
                                        }
                                    } else if let white = whiteLevel {
                                        stopWhiteLevels[newStop.id] = white
                                    }
                                } else {
                                    let stop = updatedGradient.stops[0]
                                    if let temp = temperature {
                                        stopTemperatures[stop.id] = temp
                                        if let white = whiteLevel {
                                            stopWhiteLevels[stop.id] = white
                                        } else {
                                            stopWhiteLevels.removeValue(forKey: stop.id)
                                        }
                                    } else if let white = whiteLevel {
                                        stopWhiteLevels[stop.id] = white
                                    } else {
                                        updatedGradient.stops[0].hexColor = color.toHex()
                                        stopTemperatures.removeValue(forKey: stop.id)
                                        stopWhiteLevels.removeValue(forKey: stop.id)
                                    }
                                }
                                gradient = updatedGradient
                                Task { await applyNow(stops: updatedGradient.stops) }
                                return
                            }
                            
                            var updatedGradient = currentGradient
                            
                            // CRITICAL FIX: When temperature slider is active, don't update hexColor
                            // The hex color should match what WLED will produce from CCT
                            // For CCT 0 (warm), WLED produces #FFA000 (orange)
                            // We should store that hex color instead of extracting from Color object
                            if let temp = temperature {
                                // Store temperature for this stop FIRST, before calling applyNow
                                stopTemperatures[selectedId] = temp
                                if let white = whiteLevel {
                                    stopWhiteLevels[selectedId] = white
                                } else {
                                    stopWhiteLevels.removeValue(forKey: selectedId)
                                }
                                
                                #if DEBUG
                                print("🔵 onColorChange: Stored temperature \(temp) for stopId \(selectedId)")
                                print("🔵 onColorChange: stopTemperatures=\(stopTemperatures)")
                                #endif
                                
                                // Use shared CCT color calculation utility
                                updatedGradient.stops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                                
                                // Update gradient state
                                gradient = updatedGradient
                                
                                #if DEBUG
                                print("🔵 onColorChange: Calling applyNow with stops.count=\(updatedGradient.stops.count)")
                                #endif
                                // Apply immediately - temperature slider should work in real-time
                                Task { await applyNow(stops: updatedGradient.stops) }
                            } else {
                                // No temperature: use extracted hex color
                                updatedGradient.stops[idx].hexColor = color.toHex()
                                stopTemperatures.removeValue(forKey: selectedId)
                                if let white = whiteLevel {
                                    stopWhiteLevels[selectedId] = white
                                } else {
                                    stopWhiteLevels.removeValue(forKey: selectedId)
                                }
                                gradient = updatedGradient
                                Task { await applyNow(stops: updatedGradient.stops) }
                            }
                        },
                        onRemove: {
                            if currentGradient.stops.count > 1 {
                                var updatedGradient = currentGradient
                                updatedGradient.stops.removeAll { $0.id == selectedId }
                                // Clean up temperature tracking for removed stop
                                stopTemperatures.removeValue(forKey: selectedId)
                                stopWhiteLevels.removeValue(forKey: selectedId)
                                gradient = updatedGradient
                                selectedStopId = nil
                                Task { await applyNow(stops: updatedGradient.stops) }
                            }
                        },
                        onDismiss: { showWheel = false }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(containerFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(borderStroke, lineWidth: 1)
                )
        )
        .task {
            // Load persisted gradient into UI first (don't refresh state to prevent flash)
            if let latestStops = viewModel.gradientStops(for: device.id), !latestStops.isEmpty {
                applyIncomingGradient(latestStops)
            } else {
                syncGradientIfNeeded(with: activeDevice.currentColor)
            }
            if !isAdjustingBrightness {
                briUI = Double(activeDevice.brightness)
            }
            // Sync interpolation mode with gradient (safe to do in task)
            if let currentGrad = gradient, currentGrad.interpolation != interpolationMode {
                interpolationMode = currentGrad.interpolation
            }
            // Only refresh state for brightness/power status, not color (to prevent flash)
            // Color is already correct from persisted gradient
        }
        .onAppear {
            if let latestStops = viewModel.gradientStops(for: device.id), !latestStops.isEmpty {
                applyIncomingGradient(latestStops)
            } else {
                syncGradientIfNeeded(with: activeDevice.currentColor)
            }
            briUI = Double(activeDevice.brightness)
            // Sync interpolation mode with gradient (safe to do in onAppear)
            if let currentGrad = gradient, currentGrad.interpolation != interpolationMode {
                interpolationMode = currentGrad.interpolation
            }
        }
        .onChange(of: dismissColorPicker) { _, newValue in
            if newValue {
                showWheel = false
            }
        }
        .onChange(of: viewModel.latestGradientStops[device.id] ?? []) { _, newStops in
            guard !newStops.isEmpty else { return }
            applyIncomingGradient(newStops)
        }
        .onChange(of: liveDevice?.currentColor.toHex()) { _, newHex in
            guard let hex = newHex else { return }
            syncGradientIfNeeded(with: Color(hex: hex))
        }
        .onChange(of: liveDevice?.brightness) { _, newBrightness in
            guard newBrightness != nil else { return }
            
            // CRITICAL: Don't sync if user is currently adjusting brightness
            if isAdjustingBrightness {
                return
            }
            
            // CRITICAL: Don't sync if brightness was recently set by user (within 2 seconds)
            // This prevents WebSocket echo updates from overwriting user changes
            if let lastSet = lastBrightnessSet {
                let elapsed = Date().timeIntervalSince(lastSet)
                if elapsed < 2.0 {
                    return
                }
            }
            
            // CRITICAL: Use effective brightness (preserved brightness if device is off)
            // Use activeDevice so we prefer the live ViewModel copy instead of the stale snapshot
            // This prevents UI from jumping to 0 when device is turned off
            let effectiveBrightness = viewModel.getEffectiveBrightness(for: activeDevice)
            let deviceBrightness = Double(effectiveBrightness)
            
            // CRITICAL: Only sync if difference is significant (threshold of 10)
            // This prevents small WebSocket echo differences from causing UI jitter
            if abs(briUI - deviceBrightness) > 10 {
                briUI = deviceBrightness
            }
        }
    }

    private func applyIncomingGradient(_ stops: [GradientStop]) {
        let currentStops = gradient?.stops ?? []
        if currentStops == stops { return }
        // Preserve interpolation mode when updating gradient
        let existingInterpolation = gradient?.interpolation ?? .linear
        gradient = LEDGradient(stops: stops, interpolation: existingInterpolation)
        interpolationMode = existingInterpolation
        selectedStopId = nil
        stopTemperatures = [:]
        stopWhiteLevels = [:]
    }

    private func syncGradientIfNeeded(with color: Color) {
        let hex = color.toHex()
        let shouldReplace: Bool
        if let existing = gradient {
            let uniqueHexes = Set(existing.stops.map { $0.hexColor.uppercased() })
            shouldReplace = uniqueHexes.count <= 1 && (uniqueHexes.first ?? "") != hex.uppercased()
        } else {
            shouldReplace = true
        }
        if shouldReplace {
            // Preserve interpolation mode when syncing gradient
            let existingInterpolation = gradient?.interpolation ?? .linear
            gradient = LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: hex),
                GradientStop(position: 1.0, hexColor: hex)
            ], interpolation: existingInterpolation)
            interpolationMode = existingInterpolation
        }
    }

    private func throttleApply(stops: [GradientStop], phase: DragPhase) {
        let ledCount = viewModel.totalLEDCount(for: device)
        if phase == .changed {
            applyWorkItem?.cancel()
            let work = DispatchWorkItem {
                Task {
                    await viewModel.applyGradientStopsAcrossStrip(
                        device,
                        stops: stops,
                        ledCount: ledCount,
                        stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures,
                        stopWhiteLevels: stopWhiteLevels.isEmpty ? nil : stopWhiteLevels,
                        disableActiveEffect: true,
                        segmentId: segmentId,
                        interpolation: currentGradient.interpolation,
                        userInitiated: true,
                        preferSegmented: true
                    )
                }
            }
            applyWorkItem = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)  // 60ms throttle for realtime
                work.perform()
            }
        } else {
            Task {
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: stops,
                    ledCount: ledCount,
                    stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures,
                    stopWhiteLevels: stopWhiteLevels.isEmpty ? nil : stopWhiteLevels,
                    disableActiveEffect: true,
                    segmentId: segmentId,
                    interpolation: currentGradient.interpolation,
                    userInitiated: true,
                    preferSegmented: true
                )
            }
        }
    }

    private func applyNow(stops: [GradientStop]) async {
        let ledCount = viewModel.totalLEDCount(for: device)
        await viewModel.applyGradientStopsAcrossStrip(
            device,
            stops: stops,
            ledCount: ledCount,
            stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures,
            stopWhiteLevels: stopWhiteLevels.isEmpty ? nil : stopWhiteLevels,
            disableActiveEffect: true,
            segmentId: segmentId,
            interpolation: currentGradient.interpolation,
            userInitiated: true,
            preferSegmented: true
        )
    }
}


private extension UnifiedColorPane {
    var containerFill: Color {
        Color.white.opacity(adjustedOpacity(0.06))
    }

    var borderStroke: Color {
        Color.white.opacity(adjustedOpacity(0.12))
    }

    var primaryLabelColor: Color {
        .white
    }

    var secondaryLabelColor: Color {
        colorSchemeContrast == .increased ? .white : .white.opacity(0.8)
    }

    var sliderTintColor: Color {
        colorSchemeContrast == .increased ? .white : .white.opacity(0.9)
    }

    func adjustedOpacity(_ base: Double) -> Double {
        colorSchemeContrast == .increased ? min(1.0, base * 1.7) : base
    }
    
    // MARK: - Direct Preset Saving
    
    func saveColorPresetDirectly() async {
        await MainActor.run {
            isSavingPreset = true
            showSaveSuccess = false
        }
        
        let presetName = "Color Preset \(Date().formatted(date: .omitted, time: .shortened))"
        var preset = ColorPreset(
            name: presetName,
            gradientStops: currentGradient.stops,
            gradientInterpolation: currentGradient.interpolation,
            brightness: Int(briUI),
            temperature: stopTemperatures.values.first ?? (stopTemperatures.isEmpty ? nil : 0.5),
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
