import SwiftUI
import PhotosUI

/// Settings view for controls exposed from the Devices page gear button.
struct RealTimeSettingsView: View {
    @ObservedObject var viewModel: DeviceControlViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("AppAppearance.selection") private var appearanceSelection = AppAppearance.system.rawValue
    @AppStorage(AppBackgroundPreference.selectedChoiceKey) private var selectedBackground = AppBackgroundChoice.defaultChoice.rawValue
    @AppStorage(AppBackgroundPreference.customVersionKey) private var customBackgroundVersion: Double = 0
    @State private var selectedBackgroundPhotoItem: PhotosPickerItem?
    @State private var isImportingBackgroundPhoto = false
    @State private var backgroundImportError: String?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $appearanceSelection) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title)
                                .tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Control the app color mode and backdrop used behind the glass interface.")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(AppBackgroundChoice.suggestedChoices) { choice in
                                backgroundChoiceButton(for: choice)
                            }

                            if AppBackgroundPreference.customBackgroundExists {
                                backgroundChoiceButton(for: .custom)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))

                    PhotosPicker(
                        selection: $selectedBackgroundPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            AppBackgroundPreference.customBackgroundExists ? "Change My Photo" : "Choose My Photo",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .disabled(isImportingBackgroundPhoto)

                    if isImportingBackgroundPhoto {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing photo...")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let backgroundImportError {
                        Text(backgroundImportError)
                            .font(AppTypography.style(.caption))
                            .foregroundColor(.red)
                    }

                    if AppBackgroundPreference.customBackgroundExists {
                        Button(role: .destructive) {
                            removeCustomBackground()
                        } label: {
                            Label("Remove My Photo", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("App Background")
                } footer: {
                    Text("Suggested backgrounds are tuned for readable glass. Custom photos are copied into the app and softened automatically.")
                }

                // MARK: - Real-Time Controls Section
                Section {
                    // Main toggle for real-time updates
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Real-Time Updates")
                                .font(AppTypography.style(.headline))
                            Text("Instantly sync device changes across all apps")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.isRealTimeEnabled)
                            .labelsHidden()
                            .sensorySelection(trigger: viewModel.isRealTimeEnabled)
                    }
                    .padding(.vertical, 4)
                    
                    // Connection status indicator
                    if viewModel.isRealTimeEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connection Status")
                                    .font(AppTypography.style(.subheadline))
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 6) {
                                    connectionStatusIndicator
                                    Text(connectionStatusText)
                                        .font(AppTypography.style(.caption))
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
                    .sensorySelection(trigger: UUID())
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
            .navigationTitle("Device Settings")
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
        .onChange(of: selectedBackgroundPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importBackgroundPhoto(from: newItem)
            }
        }
    }
    
    // MARK: - Helper Views

    @ViewBuilder
    private func backgroundChoiceButton(for choice: AppBackgroundChoice) -> some View {
        let isSelected = selectedBackgroundChoice == choice

        Button {
            selectedBackground = choice.rawValue
            backgroundImportError = nil
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                backgroundThumbnail(for: choice)
                    .frame(width: 86, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }

                Text(choice.title)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 86, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(choice.title) app background")
    }

    @ViewBuilder
    private func backgroundThumbnail(for choice: AppBackgroundChoice) -> some View {
        ZStack {
            if choice == .neutral {
                LinearGradient(
                    colors: [
                        Color(red: 0.953, green: 0.949, blue: 0.941),
                        Color(red: 0.825, green: 0.799, blue: 0.765)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if choice == .custom, let image = AppBackgroundPreference.image(for: .custom) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let assetName = choice.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.18)
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.14)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.clear,
                    Color.black.opacity(0.14)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }
    
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
                    .font(AppTypography.style(.subheadline))
                    .fontWeight(.medium)
                
                Text(device.ipAddress)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(device.isOnline ? .green : .red)
                        .frame(width: 6, height: 6)
                    
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(AppTypography.style(.caption))
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
                            .font(AppTypography.style(.caption))
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
                .font(AppTypography.style(.title3))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.style(.subheadline))
                    .fontWeight(.medium)
                
                Text(description)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var selectedBackgroundChoice: AppBackgroundChoice {
        AppBackgroundChoice(rawValue: selectedBackground) ?? .defaultChoice
    }

    @MainActor
    private func importBackgroundPhoto(from item: PhotosPickerItem) async {
        isImportingBackgroundPhoto = true
        backgroundImportError = nil
        defer {
            isImportingBackgroundPhoto = false
            selectedBackgroundPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                backgroundImportError = "That photo could not be loaded."
                return
            }

            try AppBackgroundPreference.saveCustomBackground(from: data)
            customBackgroundVersion = Date().timeIntervalSince1970
            selectedBackground = AppBackgroundChoice.custom.rawValue
        } catch {
            backgroundImportError = error.localizedDescription
        }
    }

    private func removeCustomBackground() {
        AppBackgroundPreference.deleteCustomBackground()
        customBackgroundVersion = Date().timeIntervalSince1970
        if selectedBackgroundChoice == .custom {
            selectedBackground = AppBackgroundChoice.defaultChoice.rawValue
        }
        backgroundImportError = nil
    }
}

// MARK: - Preview

struct RealTimeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RealTimeSettingsView(viewModel: DeviceControlViewModel.shared)
    }
}
