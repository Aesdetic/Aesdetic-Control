import SwiftUI

struct TransitionPane: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice

    // A/B gradients (deeply isolated)
    @State private var stopsA: [GradientStop] = [
        GradientStop(position: 0.0, hexColor: "FF0000"),
        GradientStop(position: 1.0, hexColor: "0000FF")
    ]
    @State private var stopsB: [GradientStop] = []

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
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Toggle("Transition", isOn: Binding(get: { transitionOn }, set: { v in
                    if v {
                        // Make B a deep copy of A on first enable
                        if stopsB.isEmpty { stopsB = stopsA.map { GradientStop(position: $0.position, hexColor: $0.hexColor) } }
                    } else {
                        Task {
                            await viewModel.cancelStreaming(for: device)
                            await viewModel.applyGradientStopsAcrossStrip(device, stops: stopsA, ledCount: device.state?.segments.first?.len ?? 120)
                        }
                    }
                    transitionOn = v
                }))
                .tint(.white)
                .foregroundColor(.white)
                Spacer()
                Button("Start") {
                    let gA = LEDGradient(stops: stopsA)
                    let gB = LEDGradient(stops: stopsB.isEmpty ? stopsA : stopsB)
                    Task { await viewModel.startSmoothABStreaming(device, from: gA, to: gB, durationSec: durationSec, fps: 20, aBrightness: Int(aBrightness), bBrightness: Int(bBrightness)) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!transitionOn)
            }
            .padding(.horizontal, 16)

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
                gradient: Binding(get: { LEDGradient(stops: stopsA) }, set: { new in stopsA = new.stops }),
                selectedStopId: $selectedA,
                onTapStop: { id in
                    wheelTarget = "A"; selectedA = id
                    if let idx = stopsA.firstIndex(where: { $0.id == id }) { wheelInitial = stopsA[idx].color; showWheel = true }
                },
                onTapAnywhere: { t, _ in
                    let c = GradientSampler.sampleColor(at: t, stops: stopsA)
                    let new = GradientStop(position: t, hexColor: c.toHex())
                    stopsA.append(new)
                    stopsA.sort { $0.position < $1.position }
                    selectedA = new.id
                    throttleApply(stops: stopsA, phase: .changed)
                },
                onStopsChanged: { stops, phase in
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
                gradient: Binding(get: { LEDGradient(stops: stopsB.isEmpty ? stopsA : stopsB) }, set: { new in stopsB = new.stops }),
                selectedStopId: $selectedB,
                onTapStop: { id in
                    wheelTarget = "B"; selectedB = id
                    if let idx = (stopsB.isEmpty ? stopsA : stopsB).firstIndex(where: { $0.id == id }) {
                        wheelInitial = (stopsB.isEmpty ? stopsA : stopsB)[idx].color
                        showWheel = true
                    }
                },
                onTapAnywhere: { t, _ in
                    var src = stopsB.isEmpty ? stopsA : stopsB
                    let c = GradientSampler.sampleColor(at: t, stops: src)
                    let new = GradientStop(position: t, hexColor: c.toHex())
                    src.append(new)
                    src.sort { $0.position < $1.position }
                    stopsB = src
                    selectedB = new.id
                },
                onStopsChanged: { stops, _ in
                    stopsB = stops
                }
            )
            .frame(height: 56)
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showWheel) {
            ColorWheelSheet(initial: wheelInitial, canRemove: true, onRemoveStop: {
                if wheelTarget == "A" {
                    if stopsA.count > 1, let id = selectedA { stopsA.removeAll { $0.id == id }; selectedA = nil; Task { await applyNow(stops: stopsA) } }
                } else {
                    var src = stopsB.isEmpty ? stopsA : stopsB
                    if src.count > 1, let id = selectedB { src.removeAll { $0.id == id }; stopsB = src; selectedB = nil }
                }
            }, onDone: { color in
                if wheelTarget == "A" {
                    if let id = selectedA, let idx = stopsA.firstIndex(where: { $0.id == id }) {
                        stopsA[idx].hexColor = color.toHex()
                        Task { await applyNow(stops: stopsA) }
                    }
                } else {
                    if let id = selectedB, var src = Optional(stopsB.isEmpty ? stopsA : stopsB), let idx = src.firstIndex(where: { $0.id == id }) {
                        src[idx].hexColor = color.toHex(); stopsB = src
                    }
                }
            })
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
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


