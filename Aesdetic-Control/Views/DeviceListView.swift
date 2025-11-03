import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Binding var selectedDevice: WLEDDevice?
    var devices: [WLEDDevice]?  // Optional devices array for custom filtering
    
    private var displayDevices: [WLEDDevice] {
        devices ?? viewModel.filteredDevices
    }
    
    var body: some View {
        ScrollView {
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
                    .transition(PerformanceConfig.enableTransitions ? .asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ) : .identity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20) // Increased top padding for shadow space
            .padding(.bottom, 30) // Increased bottom padding for shadow space
        }
        .background(Color.clear)
    }
} 
