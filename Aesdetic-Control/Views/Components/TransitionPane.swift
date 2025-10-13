import SwiftUI

struct TransitionPane: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice

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

    init(device: WLEDDevice) {
        self.device = device
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
        VStack(spacing: 16) {
            HStack {
                Toggle("Transition", isOn: Binding(get: { transitionOn }, set: { v in
                    if v {
                        // Make B a deep copy of A on first enable
                        if currentGradientB.stops.isEmpty { 
                            let copiedStops = currentGradientA.stops.map { GradientStop(position: $0.position, hexColor: $0.hexColor) }
                            stopsB = copiedStops
                            gradientB = LEDGradient(stops: copiedStops)
                        }
                    } else {
                        Task {
                            await viewModel.stopTransitionAndRevertToA(device: device)
                            await viewModel.applyGradientStopsAcrossStrip(device, stops: currentGradientA.stops, ledCount: device.state?.segments.first?.len ?? 120)
                        }
                    }
                    transitionOn = v
                }))
                .tint(.white)
                .foregroundColor(.white)
                Spacer()
                Button("Start") {
                    let gA = currentGradientA
                    let gB = currentGradientB.stops.isEmpty ? currentGradientA : currentGradientB
                    Task { await viewModel.startTransition(from: gA, aBrightness: Int(aBrightness), to: gB, bBrightness: Int(bBrightness), durationSec: durationSec, device: device) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!transitionOn)
            }
            .padding(.horizontal, 16)

            // Collapsible Transition Controls
            if transitionOn {
                VStack(spacing: 16) {
                    // Duration (mm:ss)
                    VStack(spacing: 6) {
                        let minutes = Int(durationSec) / 60
                        let seconds = Int(durationSec) % 60
                        HStack { Text(String(format: "Duration  %02d:%02d", minutes, seconds)).foregroundColor(.white); Spacer() }
                        Slider(value: $durationSec, in: 2...120, step: 1)
                    }
                    .padding(.horizontal, 16)

                    // A Brightness
                    VStack(spacing: 6) {
                        HStack { Text("A Brightness").foregroundColor(.white); Spacer(); Text("\(Int(round(aBrightness/255.0*100)))%").foregroundColor(.white.opacity(0.8)) }
                        Slider(value: $aBrightness, in: 0...255, step: 1)
                    }
                    .padding(.horizontal, 16)

                    // A Gradient
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
                    .padding(.horizontal, 16)

                    // B Brightness
                    VStack(spacing: 6) {
                        HStack { Text("B Brightness").foregroundColor(.white); Spacer(); Text("\(Int(round(bBrightness/255.0*100)))%").foregroundColor(.white.opacity(0.8)) }
                        Slider(value: $bBrightness, in: 0...255, step: 1)
                    }
                    .padding(.horizontal, 16)

                    // B Gradient (edit does not stream automatically)
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
                },
                onStopsChanged: { stops, _ in
                    gradientB = LEDGradient(stops: stops)
                    stopsB = stops
                }
                    )
                    .frame(height: 56)
                    .padding(.horizontal, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
        .sheet(isPresented: $showWheel) {
            ColorWheelSheet(initial: wheelInitial, canRemove: true, onRemoveStop: {
                if wheelTarget == "A" {
                    if currentGradientA.stops.count > 1, let id = selectedA { 
                        var updatedStops = currentGradientA.stops
                        updatedStops.removeAll { $0.id == id }
                        gradientA = LEDGradient(stops: updatedStops)
                        stopsA = updatedStops
                        selectedA = nil
                        Task { await applyNow(stops: updatedStops) }
                    }
                } else {
                    var src = currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops
                    if src.count > 1, let id = selectedB { 
                        src.removeAll { $0.id == id }
                        gradientB = LEDGradient(stops: src)
                        stopsB = src
                        selectedB = nil
                    }
                }
            }, onDone: { color in
                if wheelTarget == "A" {
                    if let id = selectedA, let idx = currentGradientA.stops.firstIndex(where: { $0.id == id }) {
                        var updatedStops = currentGradientA.stops
                        updatedStops[idx].hexColor = color.toHex()
                        gradientA = LEDGradient(stops: updatedStops)
                        stopsA = updatedStops
                        Task { await applyNow(stops: updatedStops) }
                    }
                } else {
                    if let id = selectedB, var src = Optional(currentGradientB.stops.isEmpty ? currentGradientA.stops : currentGradientB.stops), let idx = src.firstIndex(where: { $0.id == id }) {
                        src[idx].hexColor = color.toHex()
                        gradientB = LEDGradient(stops: src)
                        stopsB = src
                    }
                }
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceUpdated"))) { _ in
            if let d = viewModel.devices.first(where: { $0.id == device.id }) {
                aBrightness = Double(d.brightness)
                bBrightness = Double(d.brightness)
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

        private func applyNow(stops: [GradientStop]) async {
            let ledCount = device.state?.segments.first?.len ?? 120
            if stops.count == 1 {
                await viewModel.updateDeviceColor(device, color: stops[0].color)
            } else {
                await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount)
            }
        }
    }
