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
    @State private var isSavingPreset = false
    @State private var showSaveSuccess = false
    @State private var isAdjustingBrightness = false

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
        ]))
    }
    
    // Direct gradient access (no longer lazy)
    private var currentGradient: LEDGradient {
        gradient ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: activeDevice.currentColor.toHex()),
            GradientStop(position: 1.0, hexColor: activeDevice.currentColor.toHex())
        ])
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
                    DispatchQueue.main.async {
                        Task { await viewModel.updateDeviceBrightness(device, brightness: brightnessValue) }
                    }
                }
            }
            .padding(.horizontal, 16)

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
                    // Sample color from current gradient at tap position
                    let color = GradientSampler.sampleColor(at: t, stops: currentGradient.stops)
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
                        canRemove: currentGradient.stops.count > 1,
                        supportsCCT: supportsCCT,
                        supportsWhite: supportsWhite,
                        usesKelvinCCT: usesKelvin,
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
                                    }
                                } else {
                                    let stop = updatedGradient.stops[0]
                                    if let temp = temperature {
                                        stopTemperatures[stop.id] = temp
                                    } else {
                                        updatedGradient.stops[0].hexColor = color.toHex()
                                        stopTemperatures.removeValue(forKey: stop.id)
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
            guard let brightness = newBrightness, !isAdjustingBrightness else { return }
            briUI = Double(brightness)
        }
    }

    private func applyIncomingGradient(_ stops: [GradientStop]) {
        let currentStops = gradient?.stops ?? []
        if currentStops == stops { return }
        gradient = LEDGradient(stops: stops)
        selectedStopId = nil
        stopTemperatures = [:]
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
            gradient = LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: hex),
                GradientStop(position: 1.0, hexColor: hex)
            ])
        }
    }

    private func throttleApply(stops: [GradientStop], phase: DragPhase) {
        let task = {
            Task {
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    segmentId: segmentId,
                    stops: stops,
                    stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures
                )
            }
        }
        if phase == .changed {
            applyWorkItem?.cancel()
            let work = DispatchWorkItem {
                task()
            }
            applyWorkItem = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)  // 60ms throttle for realtime
                work.perform()
            }
        } else {
            task()
        }
    }

    private func applyNow(stops: [GradientStop]) async {
        let ledCount = device.state?.segments.first(where: { ($0.id ?? 0) == segmentId })?.len ?? device.state?.segments.first?.len ?? 120
        if stops.count == 1 {
            // For single color, check if temperature/CCT should be used
            let stop = stops[0]
            
            #if DEBUG
            // Debug logging
            print("🔵 applyNow: stops.count=\(stops.count), stop.id=\(stop.id)")
            print("🔵 applyNow: stopTemperatures.keys=\(Array(stopTemperatures.keys))")
            print("🔵 applyNow: stopTemperatures=\(stopTemperatures)")
            #endif
            
            // Check all stop IDs in stopTemperatures to find a match
            // This handles cases where the stop ID might have changed
            var foundTemperature: Double? = nil
            
            // First, try exact match
                if let temp = stopTemperatures[stop.id] {
                    foundTemperature = temp
                    #if DEBUG
                    print("🔵 applyNow: Found exact match - temperature \(temp) for stop \(stop.id)")
                    #endif
                } else {
                    // If no exact match, check if there's only one temperature stored (common in 1-tab mode)
                    if stopTemperatures.count == 1, let temp = stopTemperatures.values.first {
                        foundTemperature = temp
                        #if DEBUG
                        print("🔵 applyNow: Found single temperature value \(temp) (fallback for 1-tab mode)")
                        #endif
                    } else {
                        #if DEBUG
                        print("⚠️ applyNow: No temperature found for stop \(stop.id)")
                        #endif
                    }
                }
                
                if let temp = foundTemperature {
                    #if DEBUG
                    print("🔵 applyNow: Applying CCT with temperature \(temp)")
                    #endif
                // CRITICAL FIX: Use ColorPipeline with per-LED colors AND CCT (same as 2-tab mode)
                // This ensures CCT is applied correctly - WLED needs per-LED colors when CCT is set
                let gradient = LEDGradient(stops: stops)
                let frame = GradientSampler.sample(gradient, ledCount: ledCount)
                
                // Convert temperature (0.0-1.0) to CCT (0-255)
                let cct = Int(round(temp * 255.0))
                
                var intent = ColorIntent(deviceId: device.id, mode: .perLED)
                intent.segmentId = segmentId
                    intent.perLEDHex = frame
                    intent.cct = cct  // Set CCT in intent (same as 2-tab mode)
                    
                    #if DEBUG
                    print("🔵 applyNow: Using ColorPipeline with perLEDHex count=\(frame.count), cct=\(cct)")
                    #endif
                    await viewModel.applyColorIntent(intent, to: device)
                } else {
                    #if DEBUG
                    print("🔵 applyNow: Applying RGB color (no temperature)")
                    #endif
                // Standard RGB color mode - use ColorPipeline
                let gradient = LEDGradient(stops: stops)
                let frame = GradientSampler.sample(gradient, ledCount: ledCount)
                var intent = ColorIntent(deviceId: device.id, mode: .perLED)
                intent.segmentId = segmentId  // Use the selected segment
                intent.perLEDHex = frame
                await viewModel.applyColorIntent(intent, to: device)
            }
        } else {
            // For gradients with multiple stops, check if all stops share the same temperature
            // If they do, send segment-level CCT along with per-LED colors (Option 1)
            await viewModel.applyGradientStopsAcrossStrip(
                device,
                segmentId: segmentId,
                stops: stops,
                stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures
            )
        }
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
            brightness: Int(briUI),
            temperature: stopTemperatures.values.first ?? (stopTemperatures.isEmpty ? nil : 0.5)
        )
        
        // STEP 1: Save locally FIRST (immediate feedback, works even if WLED is offline)
        await MainActor.run {
            PresetsStore.shared.addColorPreset(preset)
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
                let existingPresets = try await apiService.fetchPresets(for: device)
                let usedIds = Set(existingPresets.map { $0.id })
                let presetId = (1...250).first { !usedIds.contains($0) } ?? 1
                
                let savedId = try await apiService.saveColorPreset(preset, to: device, presetId: presetId)
                
                // Update local preset with WLED ID if sync succeeded
                await MainActor.run {
                    preset.wledPresetId = savedId
                    PresetsStore.shared.updateColorPreset(preset)
                }
                
                #if DEBUG
                print("✅ Color preset synced to WLED device: ID \(savedId)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ Failed to sync color preset to WLED (saved locally): \(error.localizedDescription)")
                #endif
                // Preset is still saved locally, just not synced to WLED
            }
        }
    }
}



