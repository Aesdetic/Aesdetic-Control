//
//  DiagnosticsView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 2/5/26.
//

import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Environment(\.dismiss) private var dismiss

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    diagnosticRow(label: "Network", value: viewModel.isNetworkAvailable ? "Available" : "Unavailable")
                    diagnosticRow(label: "Scanning", value: viewModel.isScanning ? "Active" : "Idle")
                    diagnosticRow(label: "Discovery", value: viewModel.wledService.discoveryProgress.isEmpty ? "Idle" : viewModel.wledService.discoveryProgress)

                    if let lastDiscovery = viewModel.wledService.lastDiscoveryTime {
                        diagnosticRow(label: "Last Discovery", value: dateFormatter.string(from: lastDiscovery))
                    } else {
                        diagnosticRow(label: "Last Discovery", value: "Unknown")
                    }

                    if let discoveryError = viewModel.discoveryErrorMessage {
                        diagnosticRow(label: "Discovery Error", value: discoveryError)
                    }
                }

                Section("Devices") {
                    if viewModel.devices.isEmpty {
                        Text("No devices loaded.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.devices.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })) { device in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(device.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(device.isOnline ? "Online" : "Offline")
                                        .font(.caption)
                                        .foregroundColor(device.isOnline ? .green : .red)
                                }

                                Text("IP: \(device.ipAddress)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("ID: \(device.id)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                if let source = viewModel.wledService.lastDiscoverySourceByDevice[device.id]
                                    ?? viewModel.wledService.lastDiscoverySourceByIP[device.ipAddress] {
                                    Text("Source: \(source)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if viewModel.isRealTimeEnabled {
                                    let status = viewModel.getConnectionStatus(for: device)?.status
                                    Text("WebSocket: \(webSocketLabel(status))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else if let status = viewModel.reconnectionStatus[device.id], !status.isEmpty {
                                    Text("Connection: \(status)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Text("Last seen: \(dateFormatter.string(from: device.lastSeen))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Recent Events") {
                    let events = viewModel.diagnosticsLog.suffix(30).reversed()
                    if events.isEmpty {
                        Text("No diagnostic events yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(events)) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(timeFormatter.string(from: entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.message)
                                    .font(.footnote)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func diagnosticRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func webSocketLabel(_ status: WLEDWebSocketManager.ConnectionStatus?) -> String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .reconnecting:
            return "Reconnecting"
        case .limitReached:
            return "Limit reached"
        case .disconnected, .none:
            return "Disconnected"
        }
    }
}
