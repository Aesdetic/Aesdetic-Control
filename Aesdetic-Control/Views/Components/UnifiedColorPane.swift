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

    init(device: WLEDDevice, dismissColorPicker: Binding<Bool>, segmentId: Int = 0) {
        self.device = device
        self._dismissColorPicker = dismissColorPicker
        self.segmentId = segmentId
        _briUI = State(initialValue: Double(device.brightness))
        
        // Initialize gradient from device's current color
        let deviceColorHex = device.currentColor.toHex()
        _gradient = State(initialValue: LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: deviceColorHex),
            GradientStop(position: 1.0, hexColor: deviceColorHex)
        ]))
    }
    
    // Direct gradient access (no longer lazy)
    private var currentGradient: LEDGradient {
        gradient ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: device.currentColor.toHex()),
            GradientStop(position: 1.0, hexColor: device.currentColor.toHex())
        ])
    }

    var body: some View {
        VStack(spacing: 16) {
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
                    let color = GradientSampler.sampleColor(at: t, stops: currentGradient.stops)
                    let new = GradientStop(position: t, hexColor: color.toHex())
                    var updatedGradient = currentGradient
                    updatedGradient.stops.append(new)
                    updatedGradient.stops.sort { $0.position < $1.position }
                    
                    // Option 3: Inherit temperature from nearest existing stop
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
                                
                                print("🔵 onColorChange: Stored temperature \(temp) for stopId \(selectedId)")
                                print("🔵 onColorChange: stopTemperatures=\(stopTemperatures)")
                                
                                // Calculate expected hex color from CCT temperature
                                // This matches WLED's CCT color calculation
                                let r: CGFloat
                                let g: CGFloat
                                let b: CGFloat
                                
                                if temp <= 0.5 {
                                    // Warm to neutral range (0.0 to 0.5)
                                    let factor = temp * 2.0
                                    r = 1.0
                                    g = 0.627 + (factor * (0.945 - 0.627))
                                    b = 0.0 + (factor * (0.918 - 0.0))
                                } else {
                                    // Neutral to cool range (0.5 to 1.0)
                                    let factor = (temp - 0.5) * 2.0
                                    r = 1.0 - (factor * (1.0 - 0.796))
                                    g = 0.945 - (factor * (0.945 - 0.859))
                                    b = 0.918 + (factor * (1.0 - 0.918))
                                }
                                
                                // Convert to hex directly from RGB values (no Color conversion)
                                let redInt = Int((r * 255).rounded())
                                let greenInt = Int((g * 255).rounded())
                                let blueInt = Int((b * 255).rounded())
                                updatedGradient.stops[idx].hexColor = String(format: "%02X%02X%02X", redInt, greenInt, blueInt)
                                
                                // Update gradient state
                                gradient = updatedGradient
                                
                                print("🔵 onColorChange: Calling applyNow with stops.count=\(updatedGradient.stops.count)")
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
            // Refresh device state on first appearance
            await viewModel.refreshDeviceState(device)
            
            // Initialize gradient from updated device color
            if gradient == nil {
                let colorHex = device.currentColor.toHex()
                gradient = LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: colorHex),
                    GradientStop(position: 1.0, hexColor: colorHex)
                ])
            }
        }
        .onAppear {
            briUI = Double(device.brightness)
            
            // Sync gradient from device's current color
            let colorHex = device.currentColor.toHex()
            let currentColorHex = gradient?.stops.first?.hexColor ?? ""
            if currentColorHex != colorHex {
                gradient = LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: colorHex),
                    GradientStop(position: 1.0, hexColor: colorHex)
                ])
            }
        }
        .onChange(of: dismissColorPicker) { _, newValue in
            if newValue {
                showWheel = false
            }
        }
    }

    private func throttleApply(stops: [GradientStop], phase: DragPhase) {
        let ledCount = device.state?.segments.first?.len ?? 120
        if phase == .changed {
            applyWorkItem?.cancel()
            let work = DispatchWorkItem {
                Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount, stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures) }
            }
            applyWorkItem = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)  // 60ms throttle for realtime
                work.perform()
            }
        } else {
            Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount, stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures) }
        }
    }

    private func applyNow(stops: [GradientStop]) async {
        let ledCount = device.state?.segments.first?.len ?? 120
        if stops.count == 1 {
            // For single color, check if temperature/CCT should be used
            let stop = stops[0]
            
            // Debug logging
            print("🔵 applyNow: stops.count=\(stops.count), stop.id=\(stop.id)")
            print("🔵 applyNow: stopTemperatures.keys=\(Array(stopTemperatures.keys))")
            print("🔵 applyNow: stopTemperatures=\(stopTemperatures)")
            
            // Check all stop IDs in stopTemperatures to find a match
            // This handles cases where the stop ID might have changed
            var foundTemperature: Double? = nil
            
            // First, try exact match
            if let temp = stopTemperatures[stop.id] {
                foundTemperature = temp
                print("🔵 applyNow: Found exact match - temperature \(temp) for stop \(stop.id)")
            } else {
                // If no exact match, check if there's only one temperature stored (common in 1-tab mode)
                if stopTemperatures.count == 1, let temp = stopTemperatures.values.first {
                    foundTemperature = temp
                    print("🔵 applyNow: Found single temperature value \(temp) (fallback for 1-tab mode)")
                } else {
                    print("⚠️ applyNow: No temperature found for stop \(stop.id)")
                }
            }
            
            if let temp = foundTemperature {
                print("🔵 applyNow: Applying CCT with temperature \(temp)")
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
                
                print("🔵 applyNow: Using ColorPipeline with perLEDHex count=\(frame.count), cct=\(cct)")
                await viewModel.applyColorIntent(intent, to: device)
            } else {
                print("🔵 applyNow: Applying RGB color (no temperature)")
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
            await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount, stopTemperatures: stopTemperatures.isEmpty ? nil : stopTemperatures)
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
}



