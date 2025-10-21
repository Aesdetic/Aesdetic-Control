import SwiftUI

struct UnifiedColorPane: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice

    @State private var gradient: LEDGradient?
    @State private var selectedStopId: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var briUI: Double
    @State private var applyWorkItem: DispatchWorkItem? = nil

    init(device: WLEDDevice) {
        self.device = device
        _briUI = State(initialValue: Double(device.brightness))
        // Initialize gradient immediately in init to avoid main queue dispatch during rendering
        _gradient = State(initialValue: LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FF0000"),
            GradientStop(position: 1.0, hexColor: "0000FF")
        ]))
    }
    
    // Direct gradient access (no longer lazy)
    private var currentGradient: LEDGradient {
        gradient ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FF0000"),
            GradientStop(position: 1.0, hexColor: "0000FF")
        ])
    }

    var body: some View {
        VStack(spacing: 16) {
            // Brightness with percent label; apply on release
            VStack(spacing: 6) {
                HStack {
                    Text("Brightness")
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(round(briUI/255.0*100)))%")
                        .foregroundColor(.white.opacity(0.8))
                }
                Slider(value: $briUI, in: 0...255, step: 1, onEditingChanged: { editing in
                    if !editing {
                        DispatchQueue.main.async {
                            Task { await viewModel.updateDeviceBrightness(device, brightness: Int(briUI)) }
                        }
                    }
                })
                .sensorySelection(trigger: Int(briUI))
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
                    gradient = updatedGradient
                    selectedStopId = new.id
                },
                onStopsChanged: { stops, phase in
                    throttleApply(stops: stops, phase: phase)
                }
            )
            .frame(height: 56)
            .padding(.horizontal, 16)
            
            // Inline color picker
            if showWheel, let selectedId = selectedStopId {
                ColorWheelInline(
                    initialColor: wheelInitial,
                    canRemove: currentGradient.stops.count > 1,
                    onColorChange: { color in
                        if let idx = currentGradient.stops.firstIndex(where: { $0.id == selectedId }) {
                            var updatedGradient = currentGradient
                            updatedGradient.stops[idx].hexColor = color.toHex()
                            gradient = updatedGradient
                            Task { await applyNow(stops: updatedGradient.stops) }
                        }
                    },
                    onRemove: {
                        if currentGradient.stops.count > 1 {
                            var updatedGradient = currentGradient
                            updatedGradient.stops.removeAll { $0.id == selectedId }
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
        .task {
            // Initialize gradient on first appearance
            if gradient == nil {
                gradient = LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: "FF0000"),
                    GradientStop(position: 1.0, hexColor: "0000FF")
                ])
            }
        }
        .onAppear {
            briUI = Double(device.brightness)
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
                try? await Task.sleep(nanoseconds: 60_000_000)  // 60ms throttle for realtime
                work.perform()
            }
        } else {
            Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount) }
        }
    }

    private func applyNow(stops: [GradientStop]) async {
        let ledCount = device.state?.segments.first?.len ?? 120
        if stops.count == 1 {
            // For single color, use ColorPipeline to ensure proper brightness handling
            // This prevents the brightness dimming issue in single color mode
            let gradient = LEDGradient(stops: stops)
            let frame = GradientSampler.sample(gradient, ledCount: ledCount)
            var intent = ColorIntent(deviceId: device.id, mode: .perLED)
            intent.segmentId = 0
            intent.perLEDHex = frame
            await viewModel.applyColorIntent(intent, to: device)
        } else {
            await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount)
        }
    }
}


