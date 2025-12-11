import SwiftUI

struct AutomationCreationSheet: View {
    @Binding var builderDevice: WLEDDevice?
    @Binding var pendingTemplate: AutomationTemplate?
    @Binding var isPresented: Bool
    
    @ObservedObject private var deviceViewModel = DeviceControlViewModel.shared
    @ObservedObject private var scenesStore = ScenesStore.shared
    
    var body: some View {
        if deviceViewModel.devices.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "lightbulb.slash")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                Text("Add a device to create automations.")
                    .foregroundColor(.gray)
                Button("Close") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if let device = builderDevice {
            let scenes = scenesStore.scenes.filter { $0.deviceId == device.id }
            let effects = deviceViewModel.colorSafeEffectOptions(for: device)
            let prefill = pendingTemplate.map {
                $0.prefill(for: AutomationTemplate.Context(
                    device: device,
                    availableDevices: deviceViewModel.devices,
                    defaultGradient: deviceViewModel.automationGradient(for: device)
                ))
            }
            AddAutomationDialog(
                device: device,
                scenes: scenes,
                effectOptions: effects,
                availableDevices: deviceViewModel.devices,
                viewModel: deviceViewModel,
                templatePrefill: prefill
            ) { automation in
                AutomationStore.shared.add(automation)
            }
            .onDisappear {
                if !isPresented {
                    builderDevice = nil
                    pendingTemplate = nil
                }
            }
        } else {
            DevicePickerSheet(
                devices: deviceViewModel.devices,
                onSelect: { selection in
                    builderDevice = selection
                },
                onCancel: {
                    isPresented = false
                    pendingTemplate = nil
                }
            )
        }
    }
}

struct DevicePickerSheet: View {
    let devices: [WLEDDevice]
    var onSelect: (WLEDDevice) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section("Choose a device") {
                    ForEach(devices) { device in
                        Button {
                            onSelect(device)
                        } label: {
                            HStack {
                                Text(device.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if device.isOnline {
                                    Text("Online")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Offline")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
