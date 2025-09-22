import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredDevices) { device in
                    EnhancedDeviceCard(device: device, viewModel: viewModel) {
                        // No-op tap for now; parent handles detail elsewhere
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color.clear)
    }
}
