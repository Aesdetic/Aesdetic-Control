//
//  DeviceListView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    var onDeviceTap: (WLEDDevice) -> Void = { _ in }
    @State private var showFilterMenu = false
    @State private var showBatchControls = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            DeviceListHeader(
                viewModel: viewModel,
                showFilterMenu: $showFilterMenu,
                showBatchControls: $showBatchControls
            )
            
            // Device List with Enhanced Cards
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredDevices) { device in
                            EnhancedDeviceCard(
                                device: device,
                                viewModel: viewModel
                            ) {
                                // Present immediately, prefetch in background to avoid delay
                                onDeviceTap(device)
                                Task.detached { [weak viewModel] in
                                    guard let vm = viewModel else { return }
                                    await vm.prefetchDeviceDetailData(for: device)
                                }
                            }
                            .id(device.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .refreshable {
                    await viewModel.refreshDevices()
                }
            }
            
            // Batch Controls Panel
            if viewModel.isBatchMode && !viewModel.selectedDevices.isEmpty {
                BatchControlsPanel(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showFilterMenu) {
            DeviceFilterSheet(viewModel: viewModel)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isBatchMode)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedDevices.count)
    }
}

// MARK: - Device List Header

struct DeviceListHeader: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Binding var showFilterMenu: Bool
    @Binding var showBatchControls: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Location filter buttons
            LocationFilterSection(viewModel: viewModel)
            
            // Batch mode header
            if viewModel.isBatchMode {
                BatchModeHeader(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

// MARK: - Location Filter Section

struct LocationFilterSection: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DeviceLocation.allCases, id: \.self) { location in
                    LocationFilterChip(
                        location: location,
                        isSelected: viewModel.locationFilter == location,
                        deviceCount: deviceCount(for: location)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.locationFilter = location
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func deviceCount(for location: DeviceLocation) -> Int {
        if location == .all {
            return viewModel.devices.count
        } else {
            return viewModel.devices.filter { $0.location == location }.count
        }
    }
}

// MARK: - Location Filter Chip

struct LocationFilterChip: View {
    let location: DeviceLocation
    let isSelected: Bool
    let deviceCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: location.systemImage)
                    .font(.system(size: 14, weight: .medium))
                
                Text(location.displayName)
                    .font(.system(size: 14, weight: .medium))
                
                Text("\(deviceCount)")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.7)
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? .white : Color.white.opacity(0.15))
            )

        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Batch Mode Header

struct BatchModeHeader: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    
    var body: some View {
        HStack {
            Button("Select All") {
                viewModel.selectAllDevices()
            }
            .foregroundColor(.blue)
            .disabled(viewModel.selectedDevices.count == viewModel.filteredDevices.count)
            
            Spacer()
            
            Text("\(viewModel.selectedDevices.count) selected")
                .foregroundColor(.gray)
                .font(.caption)
            
            Spacer()
            
            Button("Clear") {
                viewModel.deselectAllDevices()
            }
            .foregroundColor(.orange)
            .disabled(viewModel.selectedDevices.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 16)
    }
}

// MARK: - Device List Card

struct DeviceListCard: View {
    let device: WLEDDevice
    @ObservedObject var viewModel: DeviceControlViewModel
    @State private var isExpanded = false
    
    private var connectionStatus: WLEDWebSocketManager.DeviceConnectionStatus? {
        viewModel.getConnectionStatus(for: device)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            HStack(spacing: 12) {
                // Selection checkbox (batch mode)
                if viewModel.isBatchMode {
                    Button {
                        if viewModel.selectedDevices.contains(device.id) {
                            viewModel.deselectDevice(device.id)
                        } else {
                            viewModel.selectDevice(device.id)
                        }
                    } label: {
                        Image(systemName: viewModel.selectedDevices.contains(device.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(viewModel.selectedDevices.contains(device.id) ? .green : .gray)
                            .font(.title3)
                    }
                }
                
                // Device icon with status indicator
                ZStack {
                    Image(systemName: "lightbulb.led")
                        .font(.title2)
                        .foregroundColor(device.isOn ? device.currentColor : .gray)
                    
                    // Connection status indicator
                    if let status = connectionStatus {
                        Circle()
                            .fill(connectionStatusColor(status.status))
                            .frame(width: 8, height: 8)
                            .offset(x: 12, y: -12)
                    }
                }
                
                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack {
                        Text(device.ipAddress)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        if let status = connectionStatus, let latency = status.latency {
                            Text("• \(Int(latency * 1000))ms")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                // Quick controls
                if !viewModel.isBatchMode {
                    QuickControlsView(device: device, viewModel: viewModel)
                }
                
                // Expand button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Expanded details
            if isExpanded {
                DeviceDetailPanel(device: device, connectionStatus: connectionStatus)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
    
    private func connectionStatusColor(_ status: WLEDWebSocketManager.ConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .reconnecting: return .yellow
        case .limitReached: return .purple
        case .disconnected: return .red
        }
    }
}

// MARK: - Quick Controls View

struct QuickControlsView: View {
    let device: WLEDDevice
    @ObservedObject var viewModel: DeviceControlViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            // Power toggle
            Button {
                Task {
                    await viewModel.toggleDevicePower(device)
                }
            } label: {
                Image(systemName: device.isOn ? "power.circle.fill" : "power.circle")
                    .foregroundColor(device.isOn ? .green : .gray)
                    .font(.title3)
            }
            .disabled(!device.isOnline)
            
            // Real-time connection toggle
            if viewModel.isRealTimeEnabled {
                Button {
                    if let status = viewModel.getConnectionStatus(for: device),
                       status.status == .connected {
                        viewModel.disconnectRealTimeForDevice(device)
                    } else {
                        viewModel.connectRealTimeForDevice(device)
                    }
                } label: {
                    let isConnected = viewModel.getConnectionStatus(for: device)?.status == .connected
                    Image(systemName: isConnected ? "bolt.fill" : "bolt.slash")
                        .foregroundColor(isConnected ? .blue : .gray)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Device Detail Panel

struct DeviceDetailPanel: View {
    let device: WLEDDevice
    let connectionStatus: WLEDWebSocketManager.DeviceConnectionStatus?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Connection details
            if let status = connectionStatus {
                HStack {
                    Text("Status:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(statusText(status.status))
                        .font(.caption)
                        .foregroundColor(statusColor(status.status))
                    
                    Spacer()
                    
                    if let lastConnected = status.lastConnected {
                        Text("Connected: \(lastConnected, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                if status.reconnectAttempts > 0 {
                    Text("Reconnect attempts: \(status.reconnectAttempts)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Device details
            HStack {
                Text("Brightness: \(device.brightness)")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text("Last seen: \(device.lastSeen, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.clear)
        .cornerRadius(8)
        .padding(.top, 4)
    }
    
    private func statusText(_ status: WLEDWebSocketManager.ConnectionStatus) -> String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .limitReached: return "Limit Reached"
        case .disconnected: return "Disconnected"
        }
    }
    
    private func statusColor(_ status: WLEDWebSocketManager.ConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .limitReached: return .purple
        case .disconnected: return .red
        }
    }
}

// MARK: - Connection Metrics View

struct ConnectionMetricsView: View {
    let metrics: WLEDWebSocketManager.ConnectionMetrics
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text("\(metrics.activeConnections)/\(metrics.totalConnections)")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Batch Controls Panel

struct BatchControlsPanel: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @State private var batchBrightness: Double = 128
    @State private var batchColor: Color = .white
    @State private var showColorPicker = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Batch Controls")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if viewModel.batchOperationInProgress {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Quick actions
            HStack(spacing: 16) {
                BatchActionButton(
                    title: "Power",
                    icon: "power",
                    isEnabled: !viewModel.batchOperationInProgress
                ) {
                    Task {
                        await viewModel.batchTogglePower()
                    }
                }
                
                BatchActionButton(
                    title: "Color",
                    icon: "paintpalette",
                    isEnabled: !viewModel.batchOperationInProgress
                ) {
                    showColorPicker = true
                }
                
                if viewModel.isRealTimeEnabled {
                    BatchActionButton(
                        title: "Connect",
                        icon: "bolt",
                        isEnabled: !viewModel.batchOperationInProgress
                    ) {
                        Task {
                            await viewModel.batchConnectRealTime()
                        }
                    }
                    
                    BatchActionButton(
                        title: "Disconnect",
                        icon: "bolt.slash",
                        isEnabled: !viewModel.batchOperationInProgress
                    ) {
                        viewModel.batchDisconnectRealTime()
                    }
                }
            }
            
            // Brightness control
            VStack(spacing: 8) {
                HStack {
                    Text("Brightness")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("\(Int(batchBrightness))")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                HStack {
                    Slider(value: $batchBrightness, in: 1...255)
                        .tint(.blue)
                    
                    Button("Apply") {
                        Task {
                            await viewModel.batchSetBrightness(Int(batchBrightness))
                        }
                    }
                    .foregroundColor(.blue)
                    .disabled(viewModel.batchOperationInProgress)
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sheet(isPresented: $showColorPicker) {
            ColorPicker("Select Color", selection: $batchColor)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Apply") {
                            Task {
                                await viewModel.batchSetColor(batchColor)
                            }
                            showColorPicker = false
                        }
                    }
                }
        }
    }
}

// MARK: - Batch Action Button

struct BatchActionButton: View {
    let title: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isEnabled ? .blue : .gray)
            .frame(minWidth: 60)
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Device Filter Sheet

struct DeviceFilterSheet: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                FilterOptionsSection(viewModel: viewModel)
                Divider()
                SortOptionsSection(viewModel: viewModel)
                Spacer()
            }
            .padding(20)
            .background(Color.clear)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Filter Options Section

struct FilterOptionsSection: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter by Location")
                .font(.headline)
                .foregroundColor(.white)
            
            ForEach(DeviceLocation.allCases, id: \.self) { location in
                LocationFilterRow(
                    location: location,
                    isSelected: viewModel.locationFilter == location
                ) {
                    viewModel.locationFilter = location
                }
            }
        }
    }
}

// MARK: - Sort Options Section

struct SortOptionsSection: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort By")
                .font(.headline)
                .foregroundColor(.white)
            
            ForEach(DeviceControlViewModel.DeviceSortOption.allCases, id: \.self) { option in
                SortOptionRow(
                    option: option,
                    isSelected: viewModel.sortOption == option
                ) {
                    viewModel.sortOption = option
                }
            }
        }
    }
}

// MARK: - Location Filter Row

struct LocationFilterRow: View {
    let location: DeviceLocation
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: location.systemImage)
                    .foregroundColor(.white)
                    .frame(width: 20)
                
                Text(location.displayName)
                    .foregroundColor(.white)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Sort Option Row

struct SortOptionRow: View {
    let option: DeviceControlViewModel.DeviceSortOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(option.title)
                    .foregroundColor(.white)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
    }
}



#Preview {
    DeviceListView(viewModel: DeviceControlViewModel.shared)
        .preferredColorScheme(.dark)
} 