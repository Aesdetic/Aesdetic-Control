import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    let onDeviceSelected: (WLEDDevice) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredDevices) { device in
                    // Wrap EnhancedDeviceCard in NavigationLink
                    // Card's own onTap is for internal controls (power, brightness)
                    // NavigationLink handles navigation to detail view
                    NavigationLink(value: device) {
                        EnhancedDeviceCard(device: device, viewModel: viewModel) {
                            // Empty onTap - navigation handled by NavigationLink
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20) // Increased top padding for shadow space
            .padding(.bottom, 30) // Increased bottom padding for shadow space
        }
        .background(Color.clear)
    }
} 
