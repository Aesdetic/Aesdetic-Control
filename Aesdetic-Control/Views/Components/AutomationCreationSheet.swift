import SwiftUI

struct AutomationCreationSheet: View {
    @Binding var builderDevice: WLEDDevice?
    @Binding var pendingTemplate: AutomationTemplate?
    @Binding var editingAutomation: Automation?
    @Binding var isPresented: Bool
    
    @ObservedObject private var deviceViewModel = DeviceControlViewModel.shared
    @ObservedObject private var scenesStore = ScenesStore.shared
    @ObservedObject private var automationStore = AutomationStore.shared

    private var defaultAutomationName: String {
        AutomationDefaultNaming.defaultName(for: automationStore.automations)
    }
    
    var body: some View {
        if deviceViewModel.devices.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "lightbulb.slash")
                    .font(AppTypography.style(.largeTitle))
                    .foregroundColor(.white.opacity(0.58))
                Text("Add a device to create automations.")
                    .foregroundColor(.white.opacity(0.58))
                Button("Close") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if let editing = editingAutomation {
            let targetIds = Set(editing.targets.deviceIds)
            let device = builderDevice
                ?? deviceViewModel.devices.first(where: { targetIds.contains($0.id) })
                ?? deviceViewModel.devices.first!
            let scenes = scenesStore.scenes.filter { targetIds.contains($0.deviceId) || $0.deviceId == device.id }
            let effects = deviceViewModel.colorSafeEffectOptions(for: device)
            AddAutomationDialog(
                device: device,
                scenes: scenes,
                effectOptions: effects,
                availableDevices: deviceViewModel.devices,
                viewModel: deviceViewModel,
                defaultName: editing.name,
                editingAutomation: editing
            ) { automation in
                AutomationStore.shared.update(automation)
            }
            .id("edit-\(editing.id.uuidString)-\(device.id)")
            .onDisappear {
                if !isPresented {
                    builderDevice = nil
                    pendingTemplate = nil
                    editingAutomation = nil
                }
            }
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
                defaultName: pendingTemplate == nil ? defaultAutomationName : nil,
                templatePrefill: prefill
            ) { automation in
                AutomationStore.shared.add(automation)
            }
            .id("create-\(device.id)-\(pendingTemplate?.id ?? "custom")")
            .onDisappear {
                if !isPresented {
                    builderDevice = nil
                    pendingTemplate = nil
                    editingAutomation = nil
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
                                    .foregroundColor(.white)
                                Spacer()
                                if device.isOnline {
                                    Text("Online")
                                        .font(AppTypography.style(.caption))
                                        .foregroundColor(.white)
                                } else {
                                    Text("Offline")
                                        .font(AppTypography.style(.caption))
                                        .foregroundColor(.white)
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
