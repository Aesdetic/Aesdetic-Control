import SwiftUI

struct UnifiedColorPane: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice

    @State private var gradient = LEDGradient(stops: [
        GradientStop(position: 0.0, hexColor: "FF0000"),
        GradientStop(position: 1.0, hexColor: "0000FF")
    ])
    @State private var selectedStopId: UUID? = nil
    @State private var showWheel: Bool = false
    @State private var wheelInitial: Color = .white
    @State private var briUI: Double
    @State private var applyWorkItem: DispatchWorkItem? = nil

    init(device: WLEDDevice) {
        self.device = device
        _briUI = State(initialValue: Double(device.brightness))
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
            }
            .padding(.horizontal, 16)

            GradientBar(
                gradient: $gradient,
                selectedStopId: $selectedStopId,
                onTapStop: { id in
                    if let stop = gradient.stops.first(where: { $0.id == id }) {
                        wheelInitial = stop.color
                        showWheel = true
                    }
                },
                onTapAnywhere: { t, tapped in
                    let color = GradientSampler.sampleColor(at: t, stops: gradient.stops)
                    let new = GradientStop(position: t, hexColor: color.toHex())
                    gradient.stops.append(new)
                    gradient.stops.sort { $0.position < $1.position }
                    selectedStopId = new.id
                },
                onStopsChanged: { stops, phase in
                    throttleApply(stops: stops, phase: phase)
                }
            )
            .frame(height: 56)
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showWheel) {
            ColorWheelSheet(initial: wheelInitial, canRemove: (gradient.stops.count > 1), onRemoveStop: {
                if let id = selectedStopId, gradient.stops.count > 1 {
                    gradient.stops.removeAll { $0.id == id }
                    selectedStopId = nil
                    Task { await applyNow(stops: gradient.stops) }
                }
            }, onDone: { color in
                if let id = selectedStopId, let idx = gradient.stops.firstIndex(where: { $0.id == id }) {
                    gradient.stops[idx].hexColor = color.toHex()
                    Task { await applyNow(stops: gradient.stops) }
                }
            })
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            Task { await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount) }
        }
    }

    private func applyNow(stops: [GradientStop]) async {
        let ledCount = device.state?.segments.first?.len ?? 120
        if stops.count == 1 {
            // Treat as solid
            await viewModel.updateDeviceColor(device, color: stops[0].color)
        } else {
            await viewModel.applyGradientStopsAcrossStrip(device, stops: stops, ledCount: ledCount)
        }
    }
}


