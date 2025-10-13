import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Binding var selectedDevice: WLEDDevice?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredDevices) { device in
                    EnhancedDeviceCard(device: device, viewModel: viewModel) {
                        // Handle device selection for modal presentation
                        selectedDevice = device
                    }
                    .onTapGesture {
                        selectedDevice = device
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20) // Increased top padding for shadow space
            .padding(.bottom, 30) // Increased bottom padding for shadow space
        }
        .background(Color.clear)
    }
} 
