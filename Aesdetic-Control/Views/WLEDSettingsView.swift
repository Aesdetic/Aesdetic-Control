import SwiftUI

fileprivate struct SettingsSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

fileprivate struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

fileprivate struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEnd: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value))")
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding<Double>(get: { value }, set: { value = $0 }),
                in: range,
                onEditingChanged: { editing in
                    if editing == false { onEnd?() }
                }
            )
        }
    }
}

fileprivate struct SegmentBoundsRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice
    let segmentId: Int
    @State var start: Int
    @State var stop: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Start \(start)")
                let startBinding: Binding<Double> = Binding<Double>(
                    get: { Double(start) },
                    set: { start = Int($0.rounded()) }
                )
                Slider(
                    value: startBinding,
                    in: 0...Double(stop)
                )
            }
            HStack {
                Text("Stop \(stop)")
                let stopBinding: Binding<Double> = Binding<Double>(
                    get: { Double(stop) },
                    set: { stop = Int($0.rounded()) }
                )
                Slider(
                    value: stopBinding,
                    in: Double(start + 1)...Double(max(start + 1, stop))
                )
            }
            Button("Apply") {
                Task {
                    await viewModel.updateSegmentBounds(
                        device: device,
                        segmentId: segmentId,
                        start: start,
                        stop: stop
                    )
                }
            }
        }
    }
}

// Small typed int stepper row to avoid complex closures in-line
fileprivate struct IntStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var onEnd: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Stepper("\(value)", value: $value, in: range, step: 1, onEditingChanged: { editing in
                if !editing { onEnd?() }
            })
            .labelsHidden()
        }
    }
}

fileprivate struct PowerToggleRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Binding var isOn: Bool
    let device: WLEDDevice

    var body: some View {
        HStack {
            Text("Power")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.white)
                .onChange(of: isOn) { _, val in
                    Task { await viewModel.setDevicePower(device, isOn: val) }
                }
                .sensorySelection(trigger: isOn)
        }
    }
}

fileprivate struct UDPTogglesRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Binding var udpSend: Bool
    @Binding var udpRecv: Bool
    let device: WLEDDevice

    var body: some View {
        HStack {
            Toggle("Send (UDPN)", isOn: $udpSend)
                .tint(.white)
                .foregroundColor(.white)
                .onChange(of: udpSend) { _, v in
                    Task { await viewModel.setUDPSync(device, send: v, recv: nil) }
                }
                .sensorySelection(trigger: udpSend)
            Spacer()
            Toggle("Receive", isOn: $udpRecv)
                .tint(.white)
                .foregroundColor(.white)
                .onChange(of: udpRecv) { _, v in
                    Task { await viewModel.setUDPSync(device, send: nil, recv: v) }
                }
                .sensorySelection(trigger: udpRecv)
        }
    }
}

fileprivate struct UDPNetworkRow: View {
    @Binding var network: Int
    let device: WLEDDevice

    var body: some View {
        HStack {
            Text("Network")
                .foregroundColor(.white)
            Spacer()
            Stepper("\(network)", value: $network, in: 0...255, step: 1, onEditingChanged: { _ in
                Task { _ = try? await WLEDAPIService.shared.setUDPSync(for: device, send: nil, recv: nil, network: network) }
            })
            .labelsHidden()
        }
    }
}

struct WLEDSettingsView: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.openURL) private var openURL
    let device: WLEDDevice

    @State private var isOn: Bool = false
    @State private var brightnessDouble: Double = 50
    @State private var segStart: Int = 0
    @State private var segStop: Int = 60
    @State private var udpSend: Bool = false
    @State private var udpRecv: Bool = false
    @State private var udpNetwork: Int = 0
    @State private var info: Info?
    @State private var isLoading: Bool = false
    // Night Light mirrors (WLEDStateUpdate.nl)
    @State private var nightLightOn: Bool = false
    @State private var nightLightDurationMin: Int = 10
    @State private var nightLightMode: Int = 0
    @State private var nightLightTargetBri: Int = 0
    @State private var isEditingName: Bool = false
    @State private var editingName: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                infoSection
                powerSection
                syncSection
                ledSection
                nightLightSection
                realtimeSection
                actionsSection
            }
            .padding(16)
        }
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Config")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadState() }
    }

    // MARK: - Sections

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Device Name Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Device Name")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.white.opacity(0.8))
                
                HStack {
                    if isEditingName {
                        TextField("Device Name", text: $editingName)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .font(.title3.weight(.semibold))
                            .onSubmit {
                                Task {
                                    await viewModel.renameDevice(device, to: editingName)
                                    isEditingName = false
                                }
                            }
                            .onAppear {
                                editingName = device.name
                            }
                    } else {
                        Text(device.name)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if isEditingName {
                            // Cancel editing
                            isEditingName = false
                        } else {
                            // Start editing
                            isEditingName = true
                            editingName = device.name
                        }
                    }) {
                        Image(systemName: isEditingName ? "xmark" : "pencil")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
            
            // Refresh Button
            HStack {
                Spacer()
                Button(action: { Task { await loadState() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                            .font(.subheadline.weight(.medium))
                        Text("Refresh")
                            .foregroundColor(.white)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
            
            infoRow(label: "IP", value: device.ipAddress)
            if let ver = info?.ver { infoRow(label: "Firmware", value: ver) }
            infoRow(label: "MAC", value: device.id)
            infoRow(label: "LEDs", value: "\(segStop)")
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
        .cornerRadius(12)
    }

    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PowerToggleRow(isOn: $isOn, device: device)
                .environmentObject(viewModel)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
        .cornerRadius(12)
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Interfaces")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            UDPTogglesRow(udpSend: $udpSend, udpRecv: $udpRecv, device: device)
                .environmentObject(viewModel)
            UDPNetworkRow(network: $udpNetwork, device: device)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
        .cornerRadius(12)
    }

    private var ledSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Brightness")
            SliderRow(
    label: "Level",
    value: $brightnessDouble,
    range: 0...100
) {
    // commit on release
    Task {
        let bri = Int((brightnessDouble / 100.0 * 255.0).rounded())
        await viewModel.updateDeviceBrightness(device, brightness: bri)
    }
}

            SettingsSectionHeader(title: "Segment 0")
            SegmentBoundsRow(
                device: device,
                segmentId: 0,
                start: segStart,
                stop: segStop
            )
            .environmentObject(viewModel)
            HStack {
                NavigationLink(value: "web-settings") {
                    Text("Open Web Config")
                        .foregroundColor(.white)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
        .cornerRadius(12)
    }

    private var realtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Realtime Updates")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: Binding(get: { viewModel.isRealTimeEnabled }, set: { v in
                    if v { viewModel.enableRealTimeUpdates() } else { viewModel.disableRealTimeUpdates() }
                }))
                .labelsHidden()
                .tint(.white)
            }
            HStack(spacing: 12) {
                Button(action: { Task { await viewModel.forceReconnection(device) } }) {
                    Text("Reconnect")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white)
                        .cornerRadius(10)
                }
                .sensorySuccess(trigger: UUID())
                Button(action: { Task { await WLEDAPIService.shared.clearCache() } }) {
                    Text("Clear Cache")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white)
                        .cornerRadius(10)
                }
                .sensorySelection(trigger: UUID())
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
        .cornerRadius(12)
    }

    // MARK: - Night Light
    private var nightLightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Night Light")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Toggle("Enabled", isOn: $nightLightOn)
                .tint(.white)
                .foregroundColor(.white)
            IntStepperRow(
                title: "Duration (min)",
                value: $nightLightDurationMin,
                range: 1...255,
                onEnd: commitNightLight
            )
            .sensorySelection(trigger: nightLightDurationMin)
            IntStepperRow(
                title: "Mode",
                value: $nightLightMode,
                range: 0...3,
                onEnd: commitNightLight
            )
            .sensorySelection(trigger: nightLightMode)
            IntStepperRow(
                title: "Target Brightness",
                value: $nightLightTargetBri,
                range: 0...255,
                onEnd: commitNightLight
            )
            .sensorySelection(trigger: nightLightTargetBri)
            Button("Apply Night Light") { commitNightLight() }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.white)
                .cornerRadius(10)
                .sensorySuccess(trigger: UUID())
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
        .cornerRadius(12)
    }

    private func commitNightLight() {
        Task {
            _ = try? await WLEDAPIService.shared.configureNightLight(
                enabled: nightLightOn,
                duration: nightLightDurationMin,
                mode: nightLightMode,
                targetBrightness: nightLightTargetBri,
                for: device
            )
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Actions")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Button(action: { openURL(URL(string: "http://\(device.ipAddress)/update")!) }) {
                settingsButton("Firmware Update")
            }
            Button(action: { openURL(URL(string: "http://\(device.ipAddress)/security")!) }) {
                settingsButton("Security Settings")
            }
            Button(action: { openURL(URL(string: "http://\(device.ipAddress)/reset")!) }) {
                settingsButton("Factory Reset (Web UI)")
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value).foregroundColor(.white)
        }
    }

    private func settingsButton(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
            .cornerRadius(12)
    }

    private func loadState() async {
        isLoading = true
        defer { isLoading = false }
        // Initialize from current device snapshot
        isOn = device.isOn
        brightnessDouble = Double(device.brightness) / 255.0 * 100.0
        segStart = 0
        segStop = device.state?.segments.first?.len ?? segStop
        do {
            let resp = try await WLEDAPIService.shared.getState(for: device)
            await MainActor.run {
                info = resp.info
                isOn = resp.state.isOn
                brightnessDouble = Double(resp.state.brightness) / 255.0 * 100.0
                if let len = resp.state.segments.first?.len { segStop = len }
            }
        } catch { }
    }
}

// MARK: - File-Private Subviews

fileprivate struct SegmentLengthRow: View {
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice
    let segmentId: Int
    @State var start: Int
    @State var stop: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Start")
                    .foregroundColor(.white)
                Spacer()
                Stepper("\(start)", value: $start, in: 0...max(0, stop), step: 1)
                    .labelsHidden()
            }
            HStack {
                Text("Stop")
                    .foregroundColor(.white)
                Spacer()
                Stepper("\(stop)", value: $stop, in: max(1, start)...2048, step: 1, onEditingChanged: { editing in
                    if !editing {
                        Task { await viewModel.updateSegmentBounds(device: device, segmentId: segmentId, start: start, stop: stop) }
                    }
                })
                .labelsHidden()
            }
        }
    }
}

extension WLEDSettingsView: Hashable {
    static func == (lhs: WLEDSettingsView, rhs: WLEDSettingsView) -> Bool { lhs.device.id == rhs.device.id }
    func hash(into hasher: inout Hasher) { hasher.combine(device.id) }
}
