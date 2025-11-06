import SwiftUI

struct TransitionPane: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let device: WLEDDevice
    @Binding var dismissColorPicker: Bool

    // A/B gradients (lazy initialization)
    @State private var stopsA: [GradientStop]?
    @State private var stopsB: [GradientStop]?
    
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
    @State private var durationSec: Double = 10

    init(device: WLEDDevice, dismissColorPicker: Binding<Bool>) {
        self.device = device
        self._dismissColorPicker = dismissColorPicker
        _aBrightness = State(initialValue: Double(device.brightness))
        _bBrightness = State(initialValue: Double(device.brightness))
        // Initialize gradients immediately in init to avoid main queue dispatch during rendering
        let defaultStops = [
            GradientStop(position: 0.0, hexColor: "FF0000"),
            GradientStop(position: 1.0, hexColor: "0000FF")
        ]
        _gradientA = State(initialValue: LEDGradient(stops: defaultStops))
        _stopsA = State(initialValue: defaultStops)
        _gradientB = State(initialValue: LEDGradient(stops: []))
        _stopsB = State(initialValue: [])
    }
    // Direct gradient access (no longer lazy)
    private var currentGradientA: LEDGradient {
        gradientA ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FF0000"),
            GradientStop(position: 1.0, hexColor: "0000FF")
        ])
    }
    
    private var currentGradientB: LEDGradient {
        gradientB ?? LEDGradient(stops: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Transitions", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                // Transition On/Off Toggle (like EffectsPane)
                Button(action: {
                    if transitionOn {
                        // Turn transitions OFF
                        transitionOn = false
                        Task {
                            await viewModel.stopTransitionAndRevertToA(device: device)
                            await viewModel.applyGradientStopsAcrossStrip(device, stops: currentGradientA.stops, ledCount: device.state?.segments.first?.len ?? 120)
                        }
                    } else {
                        // Turn transitions ON
                        transitionOn = true
                        // Make B a deep copy of A on first enable
                        if currentGradientB.stops.isEmpty { 
                            let copiedStops = currentGradientA.stops.map { GradientStop(position: $0.position, hexColor: $0.hexColor) }
                            stopsB = copiedStops
                            gradientB = LEDGradient(stops: copiedStops)
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: transitionOn ? "power" : "poweroff")
                            .font(.caption)
                        Text(transitionOn ? "ON" : "OFF")
                            .font(.caption.weight(.medium))
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

            // Transition Controls
            if transitionOn {
                VStack(alignment: .leading, spacing: 12) {
                    // Start Button
                    Button("Start Transition") {
                        let gA = currentGradientA
                        let gB = currentGradientB.stops.isEmpty ? currentGradientA : currentGradientB
                        Task { await viewModel.startTransition(from: gA, aBrightness: Int(aBrightness), to: gB, bBrightness: Int(bBrightness), durationSec: durationSec, device: device) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Begins the transition using the selected gradients.")
                    
                    // Duration (mm:ss)
                    VStack(alignment: .leading, spacing: 6) {
                        let minutes = Int(durationSec) / 60
                        let seconds = Int(durationSec) % 60
                        HStack {
                            Text("Duration")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text(String(format: "%02d:%02d", minutes, seconds))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Slider(value: $durationSec, in: 2...120, step: 1)
                            .tint(.white)
                            .accessibilityLabel("Transition duration")
                            .accessibilityValue(String(format: "%d minutes %d seconds", minutes, seconds))
                            .accessibilityHint("Controls how long the gradient transition runs.")
                            .accessibilityAdjustableAction { direction in
                                let step: Double = 5
                                switch direction {
                                case .increment:
                                    durationSec = min(120, durationSec + step)
                                case .decrement:
                                    durationSec = max(2, durationSec - step)
                                @unknown default:
                                    break
                                }
                            }
                    }

                    // A Brightness
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("A Brightness")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("\(Int(round(aBrightness/255.0*100)))%")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Slider(value: $aBrightness, in: 0...255, step: 1)
                            .tint(.white)
                            .accessibilityLabel("Gradient A brightness")
                            .accessibilityValue("\(Int(round(aBrightness/255.0*100))) percent")
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

                    // A Gradient
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gradient A")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
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
                                wheelTarget = "A"; selectedA = id
                                if let idx = currentGradientA.stops.firstIndex(where: { $0.id == id }) { 
                                    wheelInitial = currentGradientA.stops[idx].color
                                    showWheel = true 
                                }
                            },
                            onTapAnywhere: { t, _ in
                                let c = GradientSampler.sampleColor(at: t, stops: currentGradientA.stops)
                                let new = GradientStop(position: t, hexColor: c.toHex())
                                var updatedStops = currentGradientA.stops
                                updatedStops.append(new)
                                updatedStops.sort { $0.position < $1.position }
                                gradientA = LEDGradient(stops: updatedStops)
                                stopsA = updatedStops
                                selectedA = new.id
                                throttleApply(stops: updatedStops, phase: .changed)
                            },
                            onStopsChanged: { stops, phase in
                                gradientA = LEDGradient(stops: stops)
                                stopsA = stops
                                throttleApply(stops: stops, phase: phase)
                            }
                        )
                        .frame(height: 56)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Gradient A editor")
                        .accessibilityValue("\(currentGradientA.stops.count) color stops")
                        .accessibilityHint("Double tap to adjust colors in gradient A.")
                    }
                    
                    // Inline color picker for Gradient A
                    if showWheel && wheelTarget == "A", let selectedId = selectedA {
                        let currentStops = currentGradientA.stops
                        let canRemove = currentStops.count > 1
                        let supportsCCT = viewModel.supportsCCT(for: device, segmentId: 0)
                        let supportsWhite = viewModel.supportsWhite(for: device, segmentId: 0)
                        let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: 0)
                        
                        ColorWheelInline(
                            initialColor: wheelInitial,
                            canRemove: canRemove,
                            supportsCCT: supportsCCT,
                            supportsWhite: supportsWhite,
                            usesKelvinCCT: usesKelvin,
                            onColorChange: { color, temperature, whiteLevel in
                                if let idx = currentGradientA.stops.firstIndex(where: { $0.id == selectedId }) {
                                    var updatedStops = currentGradientA.stops
                                    
                                       // Handle temperature if provided
                                       if let temp = temperature {
                                           // Use shared CCT color calculation utility
                                           updatedStops[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                                    } else {
                                        updatedStops[idx].hexColor = color.toHex()
                                    }
                                    
                                    gradientA = LEDGradient(stops: updatedStops)
                                    stopsA = updatedStops
                                    Task { await applyNow(stops: updatedStops) }
                                }
                            },
                            onRemove: {
                                if currentGradientA.stops.count > 1, let id = selectedA {
                                    var updatedStops = currentGradientA.stops
                                    updatedStops.removeAll { $0.id == id }
                                    gradientA = LEDGradient(stops: updatedStops)
                                    stopsA = updatedStops
                                    selectedA = nil
                                    Task { await applyNow(stops: updatedStops) }
                                }
                                showWheel = false
                            },
                            onDismiss: {
                                showWheel = false
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // B Brightness
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("B Brightness")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("\(Int(round(bBrightness/255.0*100)))%")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Slider(value: $bBrightness, in: 0...255, step: 1)
                            .tint(.white)
                            .accessibilityLabel("Gradient B brightness")
                            .accessibilityValue("\(Int(round(bBrightness/255.0*100))) percent")
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

                    // B Gradient (with preview capability)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gradient B")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
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
                                wheelTarget = "B"; selectedB = id
                                let currentStops = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                if let idx = currentStops.firstIndex(where: { $0.id == id }) {
                                    wheelInitial = currentStops[idx].color
                                    showWheel = true
                                }
                            },
                            onTapAnywhere: { t, _ in
                                var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                let c = GradientSampler.sampleColor(at: t, stops: src)
                                let new = GradientStop(position: t, hexColor: c.toHex())
                                src.append(new)
                                src.sort { $0.position < $1.position }
                                gradientB = LEDGradient(stops: src)
                                stopsB = src
                                selectedB = new.id
                                throttleApplyB(stops: src, phase: .changed)
                            },
                            onStopsChanged: { stops, phase in
                                gradientB = LEDGradient(stops: stops)
                                stopsB = stops
                                throttleApplyB(stops: stops, phase: phase)
                            }
                        )
                        .frame(height: 56)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Gradient B editor")
                        .accessibilityValue("\((currentGradientB.stops.isEmpty ? currentGradientA.stops.count : currentGradientB.stops.count)) color stops")
                        .accessibilityHint("Double tap to adjust colors in gradient B.")
                    }
                    
                    // Inline color picker for Gradient B
                    if showWheel && wheelTarget == "B", let selectedId = selectedB {
                        let currentStops = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                        let canRemove = currentStops.count > 1
                        let supportsCCT = viewModel.supportsCCT(for: device, segmentId: 0)
                        let supportsWhite = viewModel.supportsWhite(for: device, segmentId: 0)
                        let usesKelvin = viewModel.segmentUsesKelvinCCT(for: device, segmentId: 0)
                        
                        ColorWheelInline(
                            initialColor: wheelInitial,
                            canRemove: canRemove,
                            supportsCCT: supportsCCT,
                            supportsWhite: supportsWhite,
                            usesKelvinCCT: usesKelvin,
                            onColorChange: { color, temperature, whiteLevel in
                                var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                if let idx = src.firstIndex(where: { $0.id == selectedId }) {
                                       // Handle temperature if provided
                                       if let temp = temperature {
                                           // Use shared CCT color calculation utility
                                           src[idx].hexColor = Color.hexColor(fromCCTTemperature: temp)
                                    } else {
                                        src[idx].hexColor = color.toHex()
                                    }
                                    
                                    gradientB = LEDGradient(stops: src)
                                    stopsB = src
                                    Task { await applyNowB(stops: src) }
                                }
                            },
                            onRemove: {
                                var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                                if src.count > 1, let id = selectedB {
                                    src.removeAll { $0.id == id }
                                    gradientB = LEDGradient(stops: src)
                                    stopsB = src
                                    selectedB = nil
                                    Task { await applyNowB(stops: src) }
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Effects disabled state (like EffectsPane)
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.4))
                    Text("Transitions disabled")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Toggle ON to enable transitions")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
        .task {
            // Initialize gradients on first appearance
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceUpdated"))) { _ in
            if let d = viewModel.devices.first(where: { $0.id == device.id }) {
                aBrightness = Double(d.brightness)
                bBrightness = Double(d.brightness)
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
                Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount) }
            }
            applyWorkItem = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                work.perform()
            }
        } else {
            Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount) }
        }
    }
    
    // Separate work item for Gradient B to avoid conflicts
    @State private var applyWorkItemB: DispatchWorkItem? = nil
    
    private func throttleApplyB(stops: [GradientStop], phase: DragPhase) {
        let ledCount = device.state?.segments.first?.len ?? 120
        if phase == .changed {
            applyWorkItemB?.cancel()
            let work = DispatchWorkItem {
                Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount) }
            }
            applyWorkItemB = work
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                work.perform()
            }
        } else {
            Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount) }
        }
    }

    private func applyNow(stops: [GradientStop]) async {
        let ledCount = device.state?.segments.first?.len ?? 120
        if stops.count == 1 {
            await viewModel.updateDeviceColor(device, color: stops[0].color)
        } else {
            await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount)
        }
    }
    
    private func applyNowB(stops: [GradientStop]) async {
        let ledCount = device.state?.segments.first?.len ?? 120
        if stops.count == 1 {
            await viewModel.updateDeviceColor(device, color: stops[0].color)
        } else {
            await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount)
        }
    }
}

private extension TransitionPane {
    var backgroundFill: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 0.12 : 0.06)
    }
}
