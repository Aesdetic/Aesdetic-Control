//
//  DeviceCardComponents.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI
import Foundation
import PhotosUI

// MARK: - Enhanced Device Card with Modern Design

struct EnhancedDeviceCard: View {
    let device: WLEDDevice
    let viewModel: DeviceControlViewModel
    let onTap: () -> Void
    
    // Local state for interactive controls
    @State private var localBrightness: Double
    @State private var isControlling: Bool = false
    @State private var brightnessUpdateTimer: Timer?
    @State private var lastBrightnessSet: Date? = nil
    @State private var showImagePicker: Bool = false
    @State private var isToggling: Bool = false
    
    // Initialize local state from device
    init(device: WLEDDevice, viewModel: DeviceControlViewModel, onTap: @escaping () -> Void) {
        self.device = device
        self.viewModel = viewModel
        self.onTap = onTap
        self._localBrightness = State(initialValue: Double(device.brightness))
    }
    
    // Use coordinated power state from ViewModel
    private var currentPowerState: Bool {
        return viewModel.getCurrentPowerState(for: device.id)
    }
    
    private var brightnessEffect: Double {
        guard currentPowerState && device.isOnline else { return 0 }
        return Double(device.brightness) / 255.0
    }
    
    var body: some View {
        ZStack {
            // Product image as background element, aligned bottom-right
            productImageSection
            
            // Content layered on top
            VStack(spacing: 0) {
                // Header section
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                // Power button section
                powerButtonSection
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                
                // Push brightness to bottom with more spacing
                Spacer()
                Spacer(minLength: 8) // Additional spacing before brightness section
                
                // Brightness section - aligned to bottom with consistent margin
                if currentPowerState {
                    brightnessSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20) // Same margin as top/sides for consistency
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 193) // Increased by 5% (184 * 1.05)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) // Ensure all corners match
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceUpdated"))) { _ in
            syncWithDeviceState()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerSheet(deviceId: device.id)
        }
        .onAppear {
            syncWithDeviceState()
        }
        .onDisappear {
            brightnessUpdateTimer?.invalidate()
            brightnessUpdateTimer = nil
        }
    }
    
    private var productImageSection: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    ZStack {
                        // Simplified, lower-cost ambient glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: currentPowerState && device.isOnline ? [
                                        Color.blue.opacity(brightnessEffect * 0.2),
                                        Color.blue.opacity(brightnessEffect * 0.06),
                                        Color.clear
                                    ] : [Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 60
                                )
                            )
                            .scaleEffect(1.25)
                            .blur(radius: currentPowerState && device.isOnline ? 6 + (brightnessEffect * 3) : 0)
                            .shadow(
                                color: currentPowerState && device.isOnline ? Color.blue.opacity(brightnessEffect * 0.15) : Color.clear,
                                radius: currentPowerState && device.isOnline ? 6 + (brightnessEffect * 4) : 0
                            )
                            .animation(.easeInOut(duration: 0.3), value: device.brightness)
                            .animation(.easeInOut(duration: 0.3), value: currentPowerState)
                            .animation(.easeInOut(duration: 0.3), value: device.isOnline)
                        
                        // Product image on top of the glow
                        ProductImageWithBrightness(
                            brightness: Double(device.brightness),
                            isOn: currentPowerState,
                            isOnline: device.isOnline,
                            deviceId: device.id
                        )
                    }
                    .frame(
                        width: geometry.size.width * 0.64, // 15% smaller than 75%
                        height: geometry.size.height * 0.68
                    )
                    .offset(x: 30, y: 30)
                    .mask(
                        // Create a smooth gradient mask to blend with card background
                        RadialGradient(
                            colors: [.white, .white.opacity(0.98), .white.opacity(0.9), .white.opacity(0.7), .white.opacity(0.4), .white.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.8
                        )
                    )
                }
            }
        }
        .clipped() // Clip the parts of the image that go outside the card's bounds
    }
    
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(size: 19, weight: .semibold)) // Headline is ~17px, increased by 2px
                    .foregroundColor(.primary)
                
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(device.isOnline ? .green : .red)
                    .frame(width: 8, height: 8)
                
                Text(device.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(device.isOnline ? .green : .red)
            }
        }
    }
    
    private var powerButtonSection: some View {
        HStack {
            Button(action: {
                // Calculate target state BEFORE any state changes
                let targetState = !currentPowerState
                
                // Register UI optimistic state with ViewModel for coordination
                viewModel.registerUIOptimisticState(deviceId: device.id, state: targetState)
                isToggling = true
                
                // Haptic feedback for immediate response
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                Task {
                    print("🎯 Device tab toggle initiated: \(device.id) → \(targetState ? "ON" : "OFF")")
                    
                    await viewModel.toggleDevicePower(device)
                    
                    // Allow time for the API call and state propagation
                    try? await Task.sleep(nanoseconds: 750_000_000) // 0.75 seconds
                    
                    // Reset UI state after completion
                    await MainActor.run {
                        isToggling = false
                        
                        // ViewModel will handle state cleanup automatically
                        // UI will reflect the coordinated state through currentPowerState
                        let finalState = viewModel.getCurrentPowerState(for: device.id)
                        
                        if finalState == targetState {
                            print("✅ Device tab toggle successful: \(targetState ? "ON" : "OFF")")
                        } else {
                            print("⚠️ Device tab toggle mismatch - wanted: \(targetState), got: \(finalState)")
                        }
                    }
                }
            }) {
                ZStack {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(currentPowerState ? .black : .white)
                        .opacity(isToggling ? 0.7 : 1.0)
                    
                    // Loading indicator overlay
                    if isToggling {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(currentPowerState ? .black : .white)
                    }
                }
                .frame(width: 36, height: 36) // Reduced by 10% (40 * 0.9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(currentPowerState ? .white : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white, lineWidth: currentPowerState ? 0 : 1.5)
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                .scaleEffect(isToggling ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isToggling)
                .animation(.easeInOut(duration: 0.2), value: currentPowerState)
            }
            .buttonStyle(.plain)
            .disabled(!device.isOnline || isToggling)
            
            Spacer()
        }
    }
    

    
    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Brightness")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Image change button positioned at top right
                Button(action: {
                    showImagePicker = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(.systemGray5))
                        )
                }
                .buttonStyle(.plain)
            }
            
            brightnessBar
        }
    }
    
    private var brightnessBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track - glassmorphic semi-transparent
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.systemGray6).opacity(0.3))
                    )
                    .frame(height: 25) // Increased by 5% (24 * 1.05)
                
                // Progress fill
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [device.currentColor.opacity(0.7), device.currentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(24, geometry.size.width * CGFloat(localBrightness / 255.0)), height: 25)
                    .animation(.easeInOut(duration: 0.1), value: localBrightness)
                
                // Brightness percentage text
                HStack {
                    Text("\(Int(localBrightness / 255.0 * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .padding(.leading, 8)
                    Spacer()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isControlling = true
                        let percentage = max(0, min(1, value.location.x / geometry.size.width))
                        let newBrightness = percentage * 255.0
                    
                    // Only update if change is significant enough
                    if abs(newBrightness - localBrightness) >= 5 {
                        localBrightness = newBrightness
                        
                        // Cancel previous timer and create new one
                        brightnessUpdateTimer?.invalidate()
                        brightnessUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            Task {
                                await updateBrightness()
                            }
                        }
                    }
                }
                .onEnded { _ in
                    // Final update when gesture ends
                    brightnessUpdateTimer?.invalidate()
                    Task {
                        await updateBrightness()
                    }
                }
            )
            .disabled(!device.isOnline || !currentPowerState)
        }
        .frame(height: 25)
    }
    
    private func syncWithDeviceState() {
        guard let updatedDevice = viewModel.devices.first(where: { $0.id == device.id }) else { return }
        
        // Only sync if we're not actively controlling and not recently set
        let now = Date()
        let canSync = !isControlling && (lastBrightnessSet == nil || now.timeIntervalSince(lastBrightnessSet!) > 1.0)
        if canSync {
            let deviceBrightness = Double(updatedDevice.brightness)
            if abs(localBrightness - deviceBrightness) > 15 {
                localBrightness = deviceBrightness
            }
        }
    }
    
    private func updateBrightness() async {
        let brightnessToSet = Int(localBrightness)
        lastBrightnessSet = Date()
        isControlling = false
        
        await viewModel.updateDeviceBrightness(device, brightness: brightnessToSet)
    }
}

// MARK: - Product Image Component

struct ProductImageWithBrightness: View {
    let brightness: Double
    let isOn: Bool
    let isOnline: Bool
    let deviceId: String
    @State private var selectedImageName: String = "product_image"
    
    var body: some View {
        ZStack {
            // Product image from assets or custom uploaded image
            Group {
                if let customURL = DeviceImageManager.shared.getCustomImageURL(for: selectedImageName),
                   let uiImage = DeviceImageManager.shared.loadDownsampledImage(at: customURL, maxDimension: 480) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.low)
                        .antialiased(false)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(selectedImageName)
                        .resizable()
                        .interpolation(.low)
                        .antialiased(false)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .opacity(imageOpacity)
            .saturation(saturationEffect)
            .brightness(brightnessBoost)
            .scaleEffect(scaleEffect)
            .shadow(color: glowColor, radius: glowRadius)
            .animation(.easeInOut(duration: 0.3), value: brightness)
            .animation(.easeInOut(duration: 0.3), value: isOn)
            .animation(.easeInOut(duration: 0.3), value: isOnline)
        }
        .onAppear {
            selectedImageName = DeviceImageManager.shared.getImageName(for: deviceId)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceImageChanged"))) { notification in
            if let changedDeviceId = notification.object as? String, changedDeviceId == deviceId {
                selectedImageName = DeviceImageManager.shared.getImageName(for: deviceId)
            }
        }
    }
    
    private var imageOpacity: Double {
        if !isOnline {
            return 0.3
        } else if !isOn {
            return 0.6
        } else {
            // When on, opacity also responds to brightness for more dramatic effect
            let baseOpacity = 0.8
            let brightnessOpacity = brightnessEffect * 0.2
            return baseOpacity + brightnessOpacity
        }
    }
    
    private var brightnessEffect: Double {
        guard isOn && isOnline else { return 0 }
        return brightness / 255.0
    }
    
    private var saturationEffect: Double {
        if !isOnline || !isOn {
            return 0.3 // Desaturated when off
        } else {
            // More saturated colors at higher brightness
            return 0.8 + (brightnessEffect * 0.4)
        }
    }
    
    private var brightnessBoost: Double {
        if !isOnline || !isOn {
            return -0.2 // Darker when off
        } else {
            // Brightness boost ranges from 0 to 0.3 based on device brightness
            return brightnessEffect * 0.3
        }
    }
    
    private var scaleEffect: Double {
        if !isOnline || !isOn {
            return 0.95 // Slightly smaller when off
        } else {
            // Subtle scale effect for high brightness (1.0 to 1.05)
            return 1.0 + (brightnessEffect * 0.05)
        }
    }
    
    private var glowColor: Color {
        if !isOnline || !isOn {
            return .clear
        } else {
            // Warm glow that gets stronger with brightness
            return .yellow.opacity(brightnessEffect * 0.6)
        }
    }
    
    private var glowRadius: CGFloat {
        if !isOnline || !isOn {
            return 0
        } else {
            // Glow radius based on brightness (0 to 15)
            return CGFloat(brightnessEffect * 15)
        }
    }
}

// MARK: - Image Picker Sheet

struct ImagePickerSheet: View {
    let deviceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImage: String = "product_image"
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoading = false
    
    // Aesdetic brand product images
    private let aesdeticProducts = [
        ("aesdetic_strip_v1", "Aesdetic Strip V1"),
        ("aesdetic_bulb_smart", "Aesdetic Smart Bulb"),
        ("aesdetic_panel_rgb", "Aesdetic RGB Panel"),
        ("aesdetic_controller_pro", "Aesdetic Controller Pro")
    ]
    
    // Default/fallback images
    private let otherImages = [
        ("product_image", "Generic LED Device"),
        ("led_strip_default", "LED Strip"),
        ("smart_bulb_default", "Smart Bulb"),
        ("led_panel_default", "LED Panel"),
        ("rgb_controller_default", "RGB Controller")
    ]
    
    // Get user uploaded images
    private var uploadedImages: [(String, String)] {
        DeviceImageManager.shared.getUploadedImages()
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Custom Upload Section
                    VStack(spacing: 16) {
                        Text("Upload Custom Image")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                                
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Choose from Photos")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text("Upload a PNG image for your device")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                    )
                            )
                        }
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Aesdetic Products Section
                    VStack(spacing: 16) {
                        Text("Aesdetic Products")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(aesdeticProducts.enumerated()), id: \.offset) { index, imageInfo in
                                ImageSelectionCard(
                                    imageName: imageInfo.0,
                                    displayName: imageInfo.1,
                                    isSelected: selectedImage == imageInfo.0,
                                    deviceId: deviceId
                                ) {
                                    selectedImage = imageInfo.0
                                    DeviceImageManager.shared.setImageName(imageInfo.0, for: deviceId)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    if !uploadedImages.isEmpty {
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // Uploads Section
                        VStack(spacing: 16) {
                            Text("Uploads")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(Array(uploadedImages.enumerated()), id: \.offset) { index, imageInfo in
                                    ImageSelectionCard(
                                        imageName: imageInfo.0,
                                        displayName: imageInfo.1,
                                        isSelected: selectedImage == imageInfo.0,
                                        deviceId: deviceId
                                    ) {
                                        selectedImage = imageInfo.0
                                        DeviceImageManager.shared.setImageName(imageInfo.0, for: deviceId)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Others Section
                    VStack(spacing: 16) {
                        Text("Others")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(otherImages.enumerated()), id: \.offset) { index, imageInfo in
                                ImageSelectionCard(
                                    imageName: imageInfo.0,
                                    displayName: imageInfo.1,
                                    isSelected: selectedImage == imageInfo.0,
                                    deviceId: deviceId
                                ) {
                                    selectedImage = imageInfo.0
                                    DeviceImageManager.shared.setImageName(imageInfo.0, for: deviceId)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Choose Device Image")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await handleSelectedPhoto(newItem)
                }
            }
        }
        .onAppear {
            selectedImage = DeviceImageManager.shared.getImageName(for: deviceId)
        }
    }
    
    private func handleSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // Save the custom image and get the new image name
                let customImageName = await DeviceImageManager.shared.saveCustomImage(data, for: deviceId)
                await MainActor.run {
                    selectedImage = customImageName
                    isLoading = false
                }
            }
        } catch {
            print("Error loading selected photo: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Device Image Manager

class DeviceImageManager: ObservableObject {
    static let shared = DeviceImageManager()
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let imageCache = NSCache<NSString, UIImage>()

    init() {
        // Approximate pixel-cost cache (width*height). Target ~50M pixels total.
        imageCache.totalCostLimit = 50_000_000
    }
    
    func getImageName(for deviceId: String) -> String {
        return UserDefaults.standard.string(forKey: "deviceImage_\(deviceId)") ?? "product_image"
    }
    
    func setImageName(_ imageName: String, for deviceId: String) {
        UserDefaults.standard.set(imageName, forKey: "deviceImage_\(deviceId)")
        // Post notification to update UI
        NotificationCenter.default.post(name: NSNotification.Name("DeviceImageChanged"), object: deviceId)
    }
    
    func saveCustomImage(_ imageData: Data, for deviceId: String) async -> String {
        let baseName = "custom_\(deviceId)_\(UUID().uuidString)"
        let jpgURL = documentsDirectory.appendingPathComponent("\(baseName).jpg")
        // Downsample before saving to cap stored size
        if let down = downsampleCGImage(from: imageData as NSData, maxDimension: 1200) {
            let ui = UIImage(cgImage: down)
            if let jpg = ui.jpegData(compressionQuality: 0.85) {
                do {
                    try jpg.write(to: jpgURL, options: .atomic)
                    setImageName(baseName, for: deviceId)
                    imageCache.setObject(ui, forKey: jpgURL.absoluteString as NSString, cost: Int(ui.size.width * ui.size.height))
                    return baseName
                } catch {
                    print("Error writing compressed image: \(error)")
                }
            }
        }
        // Fallback: write original bytes as PNG
        let pngURL = documentsDirectory.appendingPathComponent("\(baseName).png")
        do {
            try imageData.write(to: pngURL, options: .atomic)
            setImageName(baseName, for: deviceId)
            return baseName
        } catch {
            print("Error saving custom image fallback: \(error)")
            return "product_image"
        }
    }
    
    func getCustomImageURL(for imageName: String) -> URL? {
        guard imageName.hasPrefix("custom_") else { return nil }
        let jpg = documentsDirectory.appendingPathComponent("\(imageName).jpg")
        if FileManager.default.fileExists(atPath: jpg.path) { return jpg }
        let png = documentsDirectory.appendingPathComponent("\(imageName).png")
        if FileManager.default.fileExists(atPath: png.path) { return png }
        return nil
    }
    
    func getUploadedImages() -> [(String, String)] {
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            return files.compactMap { url in
                let filename = url.lastPathComponent
                guard (filename.hasSuffix(".png") || filename.hasSuffix(".jpg")) && filename.hasPrefix("custom_") else { return nil }
                let imageName = url.deletingPathExtension().lastPathComponent
                let displayName = "Custom Image"
                return (imageName, displayName)
            }
        } catch {
            print("Error reading uploaded images: \(error)")
            return []
        }
    }

    // Downsample large images to reduce memory usage
    func loadDownsampledImage(at url: URL, maxDimension: CGFloat) -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let ui = UIImage(cgImage: cgImage)
        imageCache.setObject(ui, forKey: key, cost: Int(ui.size.width * ui.size.height))
        return ui
    }

    private func downsampleCGImage(from data: NSData, maxDimension: Int) -> CGImage? {
        let options: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data, options) else { return nil }
        let thumbOpts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts)
    }
}

// MARK: - Image Selection Card

struct ImageSelectionCard: View {
    let imageName: String
    let displayName: String
    let isSelected: Bool
    let deviceId: String
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Image preview
            Group {
                if let customURL = DeviceImageManager.shared.getCustomImageURL(for: imageName),
                   let uiImage = DeviceImageManager.shared.loadDownsampledImage(at: customURL, maxDimension: 300) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.low)
                        .antialiased(false)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(imageName)
                        .resizable()
                        .interpolation(.low)
                        .antialiased(false)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.8) : Color.clear,
                        lineWidth: 2
                    )
            )
            .onTapGesture {
                onSelect()
            }
            
            // Image name
            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
        )
    }
} 