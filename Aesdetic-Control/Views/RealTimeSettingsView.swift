import SwiftUI

/// Settings view for controlling real-time device synchronization features
struct RealTimeSettingsView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // MARK: - Real-Time Controls Section
                Section {
                    // Main toggle for real-time updates
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Real-Time Updates")
                                .font(.headline)
                            Text("Instantly sync device changes across all apps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.isRealTimeEnabled)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    
                    // Connection status indicator
                    if viewModel.isRealTimeEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connection Status")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 6) {
                                    connectionStatusIndicator
                                    Text(connectionStatusText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if viewModel.webSocketConnectionStatus == .reconnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                } header: {
                    Text("Real-Time Synchronization")
                } footer: {
                    if viewModel.isRealTimeEnabled {
                        Text("Devices will instantly reflect changes made from other apps or physical controls. This feature uses WebSocket connections for optimal performance.")
                    } else {
                        Text("Enable real-time updates to automatically sync device states across all applications and physical controls.")
                    }
                }
                
                // MARK: - Per-Device Controls Section
                if viewModel.isRealTimeEnabled && !viewModel.devices.isEmpty {
                    Section {
                        ForEach(viewModel.devices) { device in
                            deviceRow(for: device)
                        }
                    } header: {
                        Text("Device Connections")
                    } footer: {
                        Text("Manage real-time connections for individual devices. Offline devices will automatically reconnect when available.")
                    }
                }
                
                // MARK: - Advanced Settings Section
                Section {
                    Button {
                        viewModel.refreshRealTimeConnections()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh All Connections")
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(!viewModel.isRealTimeEnabled)
                    
                } header: {
                    Text("Connection Management")
                } footer: {
                    Text("Use this to reset all WebSocket connections if you're experiencing sync issues.")
                }
                
                // MARK: - Information Section
                Section {
                    informationRow(
                        icon: "wifi",
                        title: "Network Requirements",
                        description: "Devices must be on the same Wi-Fi network"
                    )
                    
                    informationRow(
                        icon: "bolt.fill",
                        title: "Performance Impact",
                        description: "Minimal battery usage with efficient WebSocket connections"
                    )
                    
                    informationRow(
                        icon: "lock.shield",
                        title: "Privacy & Security",
                        description: "All communication stays on your local network"
                    )
                    
                } header: {
                    Text("About Real-Time Updates")
                }
            }
            .navigationTitle("Real-Time Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private var connectionStatusIndicator: some View {
        Circle()
            .fill(connectionStatusColor)
            .frame(width: 8, height: 8)
    }
    
    private var connectionStatusColor: Color {
        switch viewModel.webSocketConnectionStatus {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .limitReached:
            return .purple
        case .disconnected:
            return .red
        }
    }
    
    private var connectionStatusText: String {
        switch viewModel.webSocketConnectionStatus {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .limitReached:
            return "Connection Limit Reached"
        case .disconnected:
            return "Disconnected"
        }
    }
    
    @ViewBuilder
    private func deviceRow(for device: WLEDDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(device.isOnline ? .green : .red)
                        .frame(width: 6, height: 6)
                    
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(device.isOnline ? .green : .red)
                }
                
                if device.isOnline {
                    Button {
                        if viewModel.isRealTimeEnabled {
                            viewModel.connectRealTimeForDevice(device)
                        }
                    } label: {
                        Text("Reconnect")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func informationRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    RealTimeSettingsView(viewModel: DeviceControlViewModel.shared)
} 