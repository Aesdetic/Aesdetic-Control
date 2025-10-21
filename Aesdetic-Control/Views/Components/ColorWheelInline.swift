import SwiftUI

struct ColorWheelInline: View {
    let initialColor: Color
    let canRemove: Bool
    let onColorChange: (Color) -> Void
    let onRemove: () -> Void
    let onDismiss: () -> Void
    
    @State private var selectedColor: Color
    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var temperature: Double = 0.5 // 0 = orange, 0.5 = white, 1 = cool white
    @State private var pickerPosition: CGPoint = .zero
    @State private var hexInput: String = ""
    @State private var isUsingTemperatureSlider: Bool = false
    @AppStorage("savedGradientColors") private var savedColorsData: Data = Data()
    
    init(initialColor: Color, canRemove: Bool, onColorChange: @escaping (Color) -> Void, onRemove: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.initialColor = initialColor
        self.canRemove = canRemove
        self.onColorChange = onColorChange
        self.onRemove = onRemove
        self.onDismiss = onDismiss
        _selectedColor = State(initialValue: initialColor)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Color Picker")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { onDismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Custom 2D Rectangular Color Gradient Picker
            customColorPickerView
            
            // Saved Colors Section
            savedColorsSection
            
            // Remove Button
            if canRemove {
                removeButton
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
        .onAppear {
            extractHSV(from: initialColor)
            updatePickerPosition()
            updateHexInput()
        }
    }
    
    // MARK: - Custom ColorPicker View
    
    private var customColorPickerView: some View {
        VStack(spacing: 16) {
            // Apple's Exact Spectrum Implementation
            GeometryReader { geo in
                ZStack {
                    // Apple's exact spectrum: HSV color space representation
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            // Apple's spectrum: Hue horizontally, Saturation vertically
                            LinearGradient(
                                colors: [
                                    Color(hue: 0.0, saturation: 1.0, brightness: 1.0),    // Red
                                    Color(hue: 0.083, saturation: 1.0, brightness: 1.0),  // Orange
                                    Color(hue: 0.167, saturation: 1.0, brightness: 1.0), // Yellow
                                    Color(hue: 0.333, saturation: 1.0, brightness: 1.0), // Green
                                    Color(hue: 0.5, saturation: 1.0, brightness: 1.0),   // Cyan
                                    Color(hue: 0.667, saturation: 1.0, brightness: 1.0),  // Blue
                                    Color(hue: 0.833, saturation: 1.0, brightness: 1.0),  // Purple
                                    Color(hue: 1.0, saturation: 1.0, brightness: 1.0)     // Red (wrap)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            // Apple's saturation gradient: White overlay from top to bottom
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Apple's exact indicator design
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                        )
                        .frame(width: 20, height: 20)
                        .position(pickerPosition)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateAppleSpectrumPosition(value.location, in: geo.size)
                        }
                        .onEnded { _ in
                            applyColorToDevice()
                        }
                )
                .onAppear {
                    updateAppleSpectrumIndicatorPosition(in: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    updateAppleSpectrumIndicatorPosition(in: newSize)
                }
            }
            .frame(height: 200)
            
            // Temperature Slider with Visual Gradient
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "thermometer.sun")
                        .foregroundColor(.orange)
                    Text("Temperature")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(temperatureText)
                        .foregroundColor(.white.opacity(0.8))
                }
                .font(.caption)
                
                // Custom slider with temperature gradient
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // WLED's exact CCT gradient background
                        LinearGradient(
                            colors: [
                                Color(hex: "#FFA000"),  // Warm white (~2700K)
                                Color(hex: "#FFF1EA"),  // Neutral white (~4000K) 
                                Color(hex: "#CBDBFF")   // Cool white (~6500K)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 6)
                        .cornerRadius(3)
                        
                        // Slider thumb
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .offset(x: CGFloat(temperature) * (geometry.size.width - 20))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newValue = Double(value.location.x / geometry.size.width)
                                temperature = max(0, min(1, newValue))
                                isUsingTemperatureSlider = true
                                // Only update color preview during drag, don't apply to device
                                applyTemperatureShift()
                            }
                            .onEnded { _ in
                                // Apply color to device only on release
                                applyColorToDevice()
                            }
                    )
                }
                .frame(height: 20)
            }
            
            // Hex Input Field
            VStack(spacing: 6) {
                HStack {
                    Text("#")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.caption)
                    
                    TextField("FF5733", text: $hexInput)
                        .font(.caption.monospaced())
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .onSubmit {
                            applyHexColor()
                        }
                        .onChange(of: hexInput) { _, newValue in
                            // Auto-apply when valid hex is entered
                            if isValidHex(newValue) {
                                applyHexColor()
                            }
                        }
                }
            }
        }
    }
    
    // MARK: - Saved Colors Section
    
    private var savedColorsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Saved Colors")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Saved colors
                    ForEach(Array(savedColors.enumerated()), id: \.offset) { index, colorHex in
                        Button(action: {
                            let color = Color(hex: colorHex)
                            selectedColor = color
                            extractHSV(from: color)
                            applyColorToDevice()
                        }) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: colorHex))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteSavedColor(at: index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    
                    // Add new color button (only show if under max limit)
                    if savedColors.count < 8 {
                        Button(action: saveCurrentColor) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Remove Button
    
    private var removeButton: some View {
        Button(action: {
            onRemove()
            onDismiss()
        }) {
            HStack {
                Image(systemName: "trash")
                Text("Remove Stop")
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Helper Functions
    
    private var temperatureText: String {
        // Convert temperature slider (0-1) to Kelvin range (2700K-6500K)
        // Based on WLED's exact CCT values: #FFA000 (2700K) to #CBDBFF (6500K)
        let kelvin = Int(2700 + (temperature * (6500 - 2700)))
        
        if temperature < 0.3 {
            return "\(kelvin)K (Warm)"
        } else if temperature < 0.7 {
            return "\(kelvin)K (Neutral)"
        } else {
            return "\(kelvin)K (Cool)"
        }
    }
    
    private func updateColor() {
        // Don't override temperature-generated colors
        if isUsingTemperatureSlider {
            return
        }
        
        // Use full brightness (1.0) for accurate color representation
        // Brightness will be controlled by WLED device separately
        selectedColor = Color(hue: hue, saturation: saturation, brightness: 1.0)
        updateHexInput()
    }
    
    private func extractHSV(from color: Color) {
        let uiColor = UIColor(color)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }
    
    // Apple's exact spectrum position calculation
    private func updateAppleSpectrumPosition(_ location: CGPoint, in size: CGSize) {
        // Apple's spectrum mapping: Hue horizontally (0-1), Saturation vertically (0-1)
        // Top = saturated (1.0), Bottom = white (0.0)
        let indicatorRadius: CGFloat = 10
        let maxX = size.width - indicatorRadius
        let maxY = size.height - indicatorRadius
        
        let x = max(indicatorRadius, min(location.x, maxX))
        let y = max(indicatorRadius, min(location.y, maxY))
        
        // Map to Apple's HSV color space
        hue = Double((x - indicatorRadius) / (maxX - indicatorRadius))
        saturation = Double((y - indicatorRadius) / (maxY - indicatorRadius))  // Top=1.0, Bottom=0.0
        
        // Reset temperature slider flag when using color picker
        isUsingTemperatureSlider = false
        
        updateColor()
        updateAppleSpectrumIndicatorPosition(in: size)
    }
    
    private func updateAppleSpectrumIndicatorPosition(in size: CGSize) {
        // Calculate position based on current hue and saturation
        let indicatorRadius: CGFloat = 10
        let maxX = size.width - indicatorRadius
        let maxY = size.height - indicatorRadius
        
        let x = indicatorRadius + hue * Double(maxX - indicatorRadius)
        let y = indicatorRadius + saturation * Double(maxY - indicatorRadius)
        
        pickerPosition = CGPoint(x: x, y: y)
    }
    
    private func updatePickerPosition() {
        // Calculate position based on current hue and saturation
        // Use a reasonable default size that will be updated by GeometryReader
        let defaultSize: CGFloat = 300 // Reasonable default
        pickerPosition = CGPoint(x: hue * defaultSize, y: (1.0 - saturation) * defaultSize)
    }
    
    private func updatePickerPosition(in size: CGSize) {
        // Calculate position based on current hue and saturation with actual geometry size
        // Account for indicator radius (14px) to keep it within bounds
        let indicatorRadius: CGFloat = 14
        let maxX = size.width - indicatorRadius
        let maxY = size.height - indicatorRadius
        
        let x = indicatorRadius + hue * Double(maxX - indicatorRadius)
        // Fix: Use (1.0 - saturation) to match visual gradient (saturated at top, white at bottom)
        let y = indicatorRadius + (1.0 - saturation) * Double(maxY - indicatorRadius)
        
        pickerPosition = CGPoint(x: x, y: y)
    }
    
    private func applyTemperatureShift() {
        // WLED's exact CCT (Correlated Color Temperature) Implementation
        // Temperature range: 0 = #FFA000 (2700K), 0.5 = #FFF1EA (4000K), 1 = #CBDBFF (6500K)
        // Based on WLED's native CCT color values
        
        let r: CGFloat
        let g: CGFloat  
        let b: CGFloat
        
        if temperature <= 0.5 {
            // Warm to neutral range (0.0 to 0.5)
            // Interpolate between #FFA000 and #FFF1EA
            let factor = temperature * 2.0 // 0 to 1
            
            // #FFA000 = RGB(255, 160, 0) = (1.0, 0.627, 0.0)
            // #FFF1EA = RGB(255, 241, 234) = (1.0, 0.945, 0.918)
            r = 1.0
            g = 0.627 + (factor * (0.945 - 0.627))  // 0.627 to 0.945
            b = 0.0 + (factor * (0.918 - 0.0))      // 0.0 to 0.918
        } else {
            // Neutral to cool range (0.5 to 1.0)
            // Interpolate between #FFF1EA and #CBDBFF
            let factor = (temperature - 0.5) * 2.0 // 0 to 1
            
            // #FFF1EA = RGB(255, 241, 234) = (1.0, 0.945, 0.918)
            // #CBDBFF = RGB(203, 219, 255) = (0.796, 0.859, 1.0)
            r = 1.0 - (factor * (1.0 - 0.796))      // 1.0 to 0.796
            g = 0.945 - (factor * (0.945 - 0.859))  // 0.945 to 0.859
            b = 0.918 + (factor * (1.0 - 0.918))    // 0.918 to 1.0
        }
        
        selectedColor = Color(red: r, green: g, blue: b)
        extractHSV(from: selectedColor)
    }
    
    private func applyColorToDevice() {
        // Apply color using WLED-accurate conversion
        // For RGBWW strips: The color picker should detect when temperature slider
        // is being used and send appropriate WW/CW channel commands instead of RGB
        
        // Ensure minimum brightness for CCT colors to be visible
        var finalColor = selectedColor
        if isUsingTemperatureSlider {
            // For CCT colors, ensure they have sufficient brightness to be visible
            let minBrightness: CGFloat = 0.3 // Minimum 30% brightness for CCT colors
            if brightness < minBrightness {
                // Extract RGB components and scale to minimum brightness
                let uiColor = UIColor(finalColor)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                
                // Scale to minimum brightness
                let scale = minBrightness / max(r, g, b)
                finalColor = Color(red: r * scale, green: g * scale, blue: b * scale)
            }
        }
        
        onColorChange(finalColor)
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Saved Colors Management
    
    private var savedColors: [String] {
        (try? JSONDecoder().decode([String].self, from: savedColorsData)) ?? []
    }
    
    private func updateSavedColors(_ colors: [String]) {
        // Keep only last 8 colors (FIFO)
        let limited = Array(colors.suffix(8))
        if let data = try? JSONEncoder().encode(limited) {
            savedColorsData = data
        }
    }
    
    private func saveCurrentColor() {
        var colors = savedColors
        let hex = selectedColor.toHex()
        
        // Remove if already exists (to avoid duplicates)
        colors.removeAll { $0 == hex }
        
        // Add to end
        colors.append(hex)
        
        // Auto-remove oldest if > 8
        if colors.count > 8 {
            colors.removeFirst()
        }
        
        updateSavedColors(colors)
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func deleteSavedColor(at index: Int) {
        var colors = savedColors
        guard index < colors.count else { return }
        colors.remove(at: index)
        updateSavedColors(colors)
    }
    
    // MARK: - Hex Input Functions
    
    private func isValidHex(_ hex: String) -> Bool {
        let cleanHex = hex.replacingOccurrences(of: "#", with: "").uppercased()
        return cleanHex.count == 6 && cleanHex.allSatisfy { $0.isHexDigit }
    }
    
    private func applyHexColor() {
        let cleanHex = hexInput.replacingOccurrences(of: "#", with: "").uppercased()
        guard isValidHex(cleanHex) else { return }
        
        let color = Color(hex: cleanHex)
        selectedColor = color
        extractHSV(from: color)
        applyColorToDevice()
    }
    
    private func updateHexInput() {
        hexInput = selectedColor.toHex().replacingOccurrences(of: "#", with: "")
    }
}

