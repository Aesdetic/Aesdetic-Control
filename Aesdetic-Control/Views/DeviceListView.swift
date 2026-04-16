import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Binding var selectedDevice: WLEDDevice?
    var devices: [WLEDDevice]?  // Optional devices array for custom filtering
    var onSelectDevice: ((WLEDDevice) -> Void)? = nil
    
    private var displayDevices: [WLEDDevice] {
        devices ?? viewModel.filteredDevices
    }
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(displayDevices) { device in
                EnhancedDeviceCard(device: device, viewModel: viewModel) {
                    if let onSelectDevice {
                        onSelectDevice(device)
                    } else {
                        selectedDevice = device
                    }
                }
                .id(device.id) // Stable identity for better performance
                .onTapGesture {
                    if let onSelectDevice {
                        onSelectDevice(device)
                    } else {
                        selectedDevice = device
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        Task { @MainActor in
                            await viewModel.removeDevice(device)
                            if selectedDevice?.id == device.id {
                                selectedDevice = nil
                            }
                        }
                    } label: {
                        Label("Remove Device", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(Color.clear)
    }
}
