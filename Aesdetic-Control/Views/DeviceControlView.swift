//
//  DeviceControlView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI
import Network
import Foundation
import Combine

struct DeviceControlView: View {
    @ObservedObject private var viewModel = DeviceControlViewModel.shared
    @State private var showAddDevice: Bool = false
    @State private var selectedDevice: WLEDDevice?
    @State private var showDeviceDetail: Bool = false
    @State private var showRealTimeSettings: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                // Dark theme background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Main Content
                    if viewModel.devices.isEmpty && !viewModel.isScanning {
                        EmptyStateView(
                            onScan: { Task { viewModel.startScanning() } },
                            onAddDevice: { showAddDevice = true }
                        )
                    } else {
                        // Device List (show immediately when devices are found, even during scanning)
                        VStack(spacing: 0) {
                            // Optional: Show small scanning indicator at top if still scanning
                            if viewModel.isScanning {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Discovering devices...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("\(viewModel.devices.count) found")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                            }
                            
                            DeviceListView(viewModel: viewModel) { tapped in
                                selectedDevice = tapped
                                showDeviceDetail = true
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Real-Time Settings Button
                    Button {
                        showRealTimeSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    // Add Device Button
                    Button {
                        showAddDevice = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Periodically optimize active connections to reduce memory/network footprint
            viewModel.optimizeWebSocketConnections()
        }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showRealTimeSettings) {
            RealTimeSettingsView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showDeviceDetail) {
            if let device = selectedDevice {
                DeviceDetailView(device: device, viewModel: viewModel) {
                    showDeviceDetail = false
                    selectedDevice = nil
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var realTimeStatusColor: Color {
        guard viewModel.isRealTimeEnabled else { return .gray }
        
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
}




// MARK: - Empty State View

struct EmptyStateView: View {
    let onScan: () -> Void
    let onAddDevice: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            // Title and Description
            VStack(spacing: 8) {
                Text("No WLED Devices Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Make sure your WLED devices are powered on and connected to the same WiFi network.")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Action Buttons
            VStack(spacing: 12) {
                Button("Scan for Devices") {
                    onScan()
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button("Add Device Manually") {
                    onAddDevice()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Enhanced Scanning State View

struct ScanningStateView: View {
    let progress: String
    let devicesFound: Int
    let lastDiscoveryTime: Date?
    
    @State private var animationProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated scanning icon
            VStack(spacing: 16) {
                ZStack {
                    // Outer scanning ring
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                        .frame(width: 100, height: 100)
                    
                    // Animated scanning ring
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(animationProgress * 360))
                        .animation(
                            Animation.linear(duration: 2)
                                .repeatForever(autoreverses: false),
                            value: animationProgress
                        )
                    
                    // Inner icon
                    Image(systemName: "wifi")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            
            // Progress text and status
            VStack(spacing: 16) {
                Text("Discovering WLED Devices")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(progress)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: progress)
                
                // Devices found counter
                if devicesFound > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Text("Found \(devicesFound) device\(devicesFound == 1 ? "" : "s")")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            // Discovery methods info
            VStack(spacing: 12) {
                Text("Using multiple discovery methods:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack(spacing: 20) {
                    DiscoveryMethodBadge(
                        icon: "network",
                        title: "mDNS",
                        description: "Bonjour/Zeroconf"
                    )
                    
                    DiscoveryMethodBadge(
                        icon: "dot.radiowaves.left.and.right",
                        title: "UDP",
                        description: "Broadcast"
                    )
                    
                    DiscoveryMethodBadge(
                        icon: "globe",
                        title: "IP Scan",
                        description: "Network ranges"
                    )
                }
            }
            .padding(.top, 8)
            
            // Last discovery time
            if let lastTime = lastDiscoveryTime {
                Text("Last scan: \(formatRelativeTime(lastTime))")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 32)
        .onAppear {
            animationProgress = 1
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct DiscoveryMethodBadge: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text(description)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Button Styles

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.blue)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Add Device Sheet

struct AddDeviceSheet: View {
    let viewModel: DeviceControlViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var manualIP: String = ""
    @State private var isScanning: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isScanning {
                    // Show enhanced scanning progress
                    VStack(spacing: 24) {
                        ScanningStateView(
                            progress: viewModel.wledService.discoveryProgress,
                            devicesFound: viewModel.devices.count,
                            lastDiscoveryTime: viewModel.wledService.lastDiscoveryTime
                        )
                        
                        Button("Stop Scanning") {
                            viewModel.wledService.stopDiscovery()
                            isScanning = false
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    VStack(spacing: 24) {
                        // Auto Discovery Section
                        VStack(spacing: 16) {
                            Text("Auto Discovery")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                
                            Text("Automatically scan your network for WLED devices using mDNS, UDP broadcasts, and IP scanning")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            
                            Button("Start Comprehensive Scan") {
                                Task {
                                    isScanning = true
                                    viewModel.startScanning()
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                        }
                        
                        // Manual Entry Section
                        VStack(spacing: 16) {
                            Text("Manual Entry")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("Enter the IP address of your WLED device if auto-discovery doesn't find it")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            
                            TextField("192.168.1.100", text: $manualIP)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                                .keyboardType(.numbersAndPunctuation)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            Button("Add Device") {
                                if !manualIP.isEmpty {
                                    viewModel.addDeviceByIP(manualIP)
                                    dismiss()
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(manualIP.isEmpty)
                        }
                        
                        Spacer()
                        
                        // Tips section
                        VStack(spacing: 8) {
                            Text("💡 Tips for finding your WLED device:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                            
                            Text("• Check your router's device list\n• Look for devices named 'WLED' or 'ESP'\n• Try accessing the WLED web interface\n• Use a network scanner app")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
            .navigationTitle("Add WLED Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isScanning {
                            viewModel.wledService.stopDiscovery()
                        }
                        dismiss()
                    }
                }
            }
        }
        .onReceive(viewModel.wledService.$isScanning) { scanning in
            if !scanning && isScanning {
                // Auto-dismiss after successful scan if devices were found
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !viewModel.devices.isEmpty {
                        dismiss()
                    } else {
                        isScanning = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#Preview {
    DeviceControlView()
} 