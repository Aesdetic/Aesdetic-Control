import SwiftUI

struct DeviceDetailView: View {
    let device: WLEDDevice
    let viewModel: DeviceControlViewModel
    let onDismiss: () -> Void

    @State private var localBrightness: Double
    @State private var localColor: Color
    @State private var isOn: Bool
    @State private var briTimer: Timer? = nil
    @State private var colorWorkItem: DispatchWorkItem? = nil

    init(device: WLEDDevice, viewModel: DeviceControlViewModel, onDismiss: @escaping () -> Void) {
        self.device = device
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _localBrightness = State(initialValue: Double(device.brightness))
        _localColor = State(initialValue: device.currentColor)
        _isOn = State(initialValue: device.isOn)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
            header

                // Power
                HStack(spacing: 12) {
                    Text(isOn ? "On" : "Off")
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: Binding(get: { isOn }, set: { newValue in
                        isOn = newValue
                        Task { await viewModel.toggleDevicePower(device) }
                    }))
                    .labelsHidden()
                    .tint(.white)
                }
                .padding(.horizontal, 16)

                // Brightness bar (glass style) - show percent, apply on release
                brightnessBar

                UnifiedColorPane(device: device)
                    .environmentObject(viewModel)

                // Transition controls
                TransitionPane(device: device)
                    .environmentObject(viewModel)

            Spacer()
        }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Sync UI with latest device entry when returning to foreground
            if let d = viewModel.devices.first(where: { $0.id == device.id }) {
                localBrightness = Double(d.brightness)
                localColor = d.currentColor
                isOn = d.isOn
            }
        }
    }

    private var header: some View {
            HStack {
                Button(action: { onDismiss() }) {
                    Image(systemName: "chevron.backward")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                Spacer()
            VStack(spacing: 2) {
                Text(device.name)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            // Placeholder settings button
            Image(systemName: "gearshape")
                .font(.title3.weight(.semibold))
                .foregroundColor(.black)
                .frame(width: 32, height: 32)
                .background(Color.white)
                .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var brightnessBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Brightness")
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(localBrightness))")
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Glass background
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )

                    // Fill according to brightness
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(24, geometry.size.width * CGFloat(localBrightness / 255.0)), height: 25)
                        .allowsHitTesting(false)

                    // Text overlay
                    Text("\(Int((localBrightness/255.0)*100))%")
                        .foregroundColor(.black)
                        .padding(.leading, 10)
                        .frame(height: 25, alignment: .center)
                }
                .frame(height: 25)
                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let x = max(0, min(geometry.size.width, g.location.x))
                    let v = Double(x / geometry.size.width) * 255.0
                    if abs(v - localBrightness) >= 5 {
                        localBrightness = v
                        briTimer?.invalidate()
                        briTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { _ in
                            DispatchQueue.main.async {
                                Task { await viewModel.updateDeviceBrightness(device, brightness: Int(localBrightness)) }
                            }
                        }
                    }
                }.onEnded { _ in
                    DispatchQueue.main.async {
                        Task { await viewModel.updateDeviceBrightness(device, brightness: Int(localBrightness)) }
                    }
                })
            }
            .frame(height: 25)
            .padding(.horizontal, 16)
        }
    }
}


extension DeviceDetailView {
	init(device: WLEDDevice) {
		self.init(device: device, viewModel: DeviceControlViewModel.shared, onDismiss: {})
	}
}


