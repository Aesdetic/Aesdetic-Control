import SwiftUI

// MARK: - Custom Location Model

struct CustomLocation: Identifiable, Codable, Hashable {
    let id = UUID()
    let name: String
    let icon: String // SF Symbol name or emoji for custom locations
    
    init(name: String, icon: String = "house") {
        self.name = name
        self.icon = icon
    }
}

struct EditDeviceInfoDialog: View {
    let device: WLEDDevice
    @EnvironmentObject var viewModel: DeviceControlViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var deviceName: String
    @State private var selectedLocation: DeviceLocation
    @State private var customLocations: [CustomLocation] = []
    @State private var newLocationName: String = ""
    @State private var newLocationIcon: String = "house"
    @State private var isAddingCustomLocation: Bool = false
    @State private var showIconPicker: Bool = false
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isLocationFieldFocused: Bool
    
    init(device: WLEDDevice) {
        self.device = device
        _deviceName = State(initialValue: device.name)
        _selectedLocation = State(initialValue: device.location)
        _customLocations = State(initialValue: []) // Load lazily to avoid blocking init
    }
    
            var body: some View {
        NavigationStack {
            ZStack {
                // Even thinner background material
                Color.black.opacity(0.2).ignoresSafeArea()
                
                ScrollView {
                VStack(spacing: 24) {
                    // Device Name Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Device Name")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        
                        TextField("Device Name", text: $deviceName)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .focused($isNameFieldFocused)
                    }
                    
                    // Location Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Location")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        
                        // Default locations (Bedroom and Living Room only)
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach([DeviceLocation.bedroom, DeviceLocation.livingRoom], id: \.self) { location in
                                LocationButton(
                                    location: location,
                                    isSelected: selectedLocation == location
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedLocation = location
                                    }
                                }
                            }
                        }
                        
                        // Custom locations
                        if !customLocations.isEmpty {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(customLocations) { customLocation in
                                    CustomLocationButton(
                                        location: customLocation,
                                        isSelected: selectedLocation == .custom(customLocation.name)
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedLocation = .custom(customLocation.name)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Add custom location section
                        if isAddingCustomLocation {
                            VStack(spacing: 12) {
                                TextField("New Location", text: $newLocationName)
                                    .textFieldStyle(.plain)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.12))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                    .focused($isLocationFieldFocused)
                                
                                // Icon selection
                                HStack {
                                    Text("Icon:")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Button(action: { showIconPicker = true }) {
                                        Group {
                                            if isSFSymbol(newLocationIcon) {
                                                Image(systemName: newLocationIcon)
                                                    .font(.title2)
                                                    .foregroundColor(.white)
                                            } else {
                                                Text(newLocationIcon)
                                                    .font(.title2)
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 40, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.1))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                HStack(spacing: 12) {
                                    Button("Cancel") {
                                        cancelAddingLocation()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                    )
                                    .foregroundColor(.white)
                                    
                                    Button("Add") {
                                        addCustomLocation()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white)
                                    )
                                    .foregroundColor(.black)
                                    .disabled(newLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(.top, 8)
                        } else {
                            Button(action: { startAddingLocation() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                    Text("Add Custom Location")
                                }
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                        )
                        .foregroundColor(.white)
                        
                        Button("Save") {
                            Task {
                                await saveChanges()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                        )
                        .foregroundColor(.black)
                    }
                    .padding(.top, 16)
                }
                .padding(24)
                .padding(.bottom, 40) // Extra bottom padding for scroll
                }
            }
            .navigationTitle("Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.thinMaterial, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Load custom locations lazily to avoid blocking init
            customLocations = loadCustomLocations()
        }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $newLocationIcon)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeleteCustomLocation"))) { notification in
            if let locationName = notification.object as? String {
                deleteCustomLocation(locationName)
            }
        }
    }
    
    private func saveChanges() async {
        // Trim whitespace
        let newName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate name is not empty
        guard !newName.isEmpty else {
            return
        }
        
        // Save name if changed
        if newName != device.name {
            await viewModel.renameDevice(device, to: newName)
        }
        
        // Save location if changed
        if selectedLocation != device.location {
            await viewModel.updateDeviceLocation(device, location: selectedLocation)
        }
        
        dismiss()
    }
    
    private func loadCustomLocations() -> [CustomLocation] {
        // Load from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: "customLocations"),
              let locations = try? JSONDecoder().decode([CustomLocation].self, from: data) else {
            return []
        }
        return locations
    }
    
    private func saveCustomLocations() {
        if let data = try? JSONEncoder().encode(customLocations) {
            UserDefaults.standard.set(data, forKey: "customLocations")
        }
    }
    
    private func startAddingLocation() {
        isAddingCustomLocation = true
        newLocationName = ""
        newLocationIcon = "house"
        // Focus the text field after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLocationFieldFocused = true
        }
    }
    
    private func cancelAddingLocation() {
        isAddingCustomLocation = false
        newLocationName = ""
        newLocationIcon = "house"
        isLocationFieldFocused = false
    }
    
    private func addCustomLocation() {
        let trimmedName = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Check if location already exists
        guard !customLocations.contains(where: { $0.name == trimmedName }) else { return }
        
        let newLocation = CustomLocation(name: trimmedName, icon: newLocationIcon)
        customLocations.append(newLocation)
        saveCustomLocations()
        
        // Select the new location
        selectedLocation = .custom(trimmedName)
        
        cancelAddingLocation()
    }
    
    private func deleteCustomLocation(_ locationName: String) {
        customLocations.removeAll { $0.name == locationName }
        saveCustomLocations()
        
        // If the deleted location was selected, reset to bedroom
        if case .custom(let customLocation) = selectedLocation, customLocation == locationName {
            selectedLocation = .bedroom
        }
    }
    
    private func isSFSymbol(_ icon: String) -> Bool {
        // Check if the icon is an SF Symbol (doesn't contain emoji characters)
        return !icon.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji
        }
    }
}

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    
    private let sfSymbolIcons = [
        "house", "house.fill", "building.2", "building.2.fill", "building",
        "building.columns", "building.columns.fill", "house.lodge", "house.lodge.fill",
        "tent", "tent.fill", "car", "car.fill", "truck", "truck.fill",
        "bicycle", "scooter", "airplane", "ferry", "sailboat", "sailboat.fill",
        "tree", "tree.fill", "leaf", "leaf.fill", "sun.max", "sun.max.fill",
        "moon", "moon.fill", "cloud", "cloud.fill", "cloud.rain", "cloud.rain.fill",
        "snowflake", "flame", "flame.fill", "drop", "drop.fill", "bolt", "bolt.fill",
        "sofa", "bed.double", "fork.knife", "desktopcomputer", "door.left.hand.open",
        "shower", "bathtub", "refrigerator", "microwave", "washer", "dryer",
        "gamecontroller", "tv", "music.note", "book", "pencil", "scissors",
        "key", "lock", "lock.open", "bell", "bell.fill", "gear", "wrench"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background with even thinner material
                Color.black.opacity(0.3).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Current selection
                    VStack(spacing: 12) {
                        Text("Selected Icon")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        
                        Group {
                            if sfSymbolIcons.contains(selectedIcon) {
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 60))
                                    .foregroundColor(.white)
                            } else {
                                Text(selectedIcon)
                                    .font(.system(size: 60))
                            }
                        }
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                    }
                    .padding(.top, 20)
                
                // SF Symbols grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(sfSymbolIcons, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                                dismiss()
                            }) {
                                Image(systemName: icon)
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedIcon == icon ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Custom emoji input
                VStack(spacing: 12) {
                    Text("Or enter custom emoji:")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    
                    TextField("Enter emoji", text: $selectedIcon)
                        .textFieldStyle(.plain)
                        .font(.title)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .onSubmit {
                            dismiss()
                        }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                }
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.thinMaterial, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Location Button

struct LocationButton: View {
    let location: DeviceLocation
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon - Use SF Symbols for default locations
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .black : .white)
                
                // Label
                Text(location.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? .black : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var iconName: String {
        switch location {
        case .all:
            return "square.grid.2x2"
        case .livingRoom:
            return "sofa"
        case .bedroom:
            return "bed.double"
        case .kitchen:
            return "fork.knife"
        case .office:
            return "desktopcomputer"
        case .hallway:
            return "door.left.hand.open"
        case .bathroom:
            return "shower"
        case .outdoor:
            return "sun.max"
        case .custom:
            return "house" // Default SF Symbol for custom locations
        }
    }
}

// MARK: - Custom Location Button

struct CustomLocationButton: View {
    let location: CustomLocation
    let isSelected: Bool
    let action: () -> Void
    
    @State private var showContextMenu = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon - Handle both SF Symbols and emojis
                Group {
                    if isSFSymbol(location.icon) {
                        Image(systemName: location.icon)
                            .font(.system(size: 24))
                            .foregroundColor(isSelected ? .black : .white)
                    } else {
                        Text(location.icon)
                            .font(.system(size: 24))
                            .foregroundColor(isSelected ? .black : .white)
                    }
                }
                
                // Label
                Text(location.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? .black : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: {
                // Edit location - could be implemented later
            }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: {
                deleteCustomLocation()
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func isSFSymbol(_ icon: String) -> Bool {
        // Check if the icon is an SF Symbol (doesn't contain emoji characters)
        return !icon.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji
        }
    }
    
    private func deleteCustomLocation() {
        // This will be handled by the parent view
        NotificationCenter.default.post(
            name: NSNotification.Name("DeleteCustomLocation"),
            object: location.name
        )
    }
}

