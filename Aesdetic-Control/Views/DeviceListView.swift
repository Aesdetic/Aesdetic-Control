import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Binding var selectedDevice: WLEDDevice?
    var devices: [WLEDDevice]?  // Optional devices array for custom filtering
    
    private var displayDevices: [WLEDDevice] {
        devices ?? viewModel.filteredDevices
    }
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(displayDevices) { device in
                EnhancedDeviceCard(device: device, viewModel: viewModel) {
                    // Handle device selection for modal presentation
                    selectedDevice = device
                }
                .id(device.id) // Stable identity for better performance
                .onTapGesture {
                    selectedDevice = device
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
                .transition(PerformanceConfig.enableTransitions ? .asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ) : .identity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(Color.clear)
    }
} 
