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
            // 2D Rectangular Color Gradient Picker
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Background: Hue gradient (horizontal) + Saturation gradient (vertical)
                    ZStack {
                        // Horizontal hue gradient
                        LinearGradient(
                            colors: [
                                Color(hue: 0.0, saturation: 1, brightness: 1),    // Red
                                Color(hue: 0.17, saturation: 1, brightness: 1),   // Yellow
                                Color(hue: 0.33, saturation: 1, brightness: 1),   // Green
                                Color(hue: 0.50, saturation: 1, brightness: 1),   // Cyan
                                Color(hue: 0.67, saturation: 1, brightness: 1),   // Blue
                                Color(hue: 0.83, saturation: 1, brightness: 1),   // Magenta
                                Color(hue: 1.0, saturation: 1, brightness: 1)     // Red
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        
                        // Vertical saturation gradient (saturated at bottom, white at top)
                        LinearGradient(
                            colors: [.clear, .white],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    
                    // Draggable indicator
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                        .position(pickerPosition)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateColorFromPosition(value.location, in: geo.size)
                        }
                        .onEnded { _ in
                            // Apply to device on release
                            applyColorToDevice()
                        }
                )
                .onAppear {
                    // Update picker position with actual geometry size
                    updatePickerPosition(in: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    // Update position when geometry changes
                    updatePickerPosition(in: newSize)
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
                        // Temperature gradient background
                        LinearGradient(
                            colors: [
                                Color.orange,           // Warm (left)
                                Color.white,            // Neutral white (center)
                                Color.blue.opacity(0.8) // Cool white (right)
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
                                // Apply temperature change immediately during drag
                                applyTemperatureShift()
                            }
                            .onEnded { _ in
                                // Apply final color to device on release
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
        // Convert temperature slider (0-1) to Kelvin range (2700K-8000K)
        let kelvin = Int(2700 + (temperature * (8000 - 2700)))
        
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
    
    private func updateColorFromPosition(_ location: CGPoint, in size: CGSize) {
        // Map position to hue (horizontal) and saturation (vertical)
        // Account for indicator radius to keep calculations within bounds
        let indicatorRadius: CGFloat = 14
        let maxX = size.width - indicatorRadius
        let maxY = size.height - indicatorRadius
        
        let x = max(indicatorRadius, min(location.x, maxX))
        let y = max(indicatorRadius, min(location.y, maxY))
        
        // Map to hue (0-1) and saturation (0-1)
        hue = Double((x - indicatorRadius) / (maxX - indicatorRadius))
        saturation = Double((y - indicatorRadius) / (maxY - indicatorRadius))
        
        // Reset temperature slider flag when using color picker
        isUsingTemperatureSlider = false
        
        updateColor()
        updatePickerPosition(in: size)
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
        let y = indicatorRadius + saturation * Double(maxY - indicatorRadius)
        
        pickerPosition = CGPoint(x: x, y: y)
    }
    
    private func applyTemperatureShift() {
        // WLED CCT (Correlated Color Temperature) Implementation
        // Temperature range: 0 = warm white (2700K), 0.5 = neutral, 1 = cool white (8000K)
        // Based on WLED's CCT handling documentation
        
        let r: CGFloat
        let g: CGFloat  
        let b: CGFloat
        
        // Convert temperature slider (0-1) to Kelvin range (2700K-8000K)
        let kelvin = 2700 + (temperature * (8000 - 2700))
        
        // WLED's CCT calculation: RGB values based on color temperature
        if kelvin <= 4000 {
            // Warm white range (2700K-4000K)
            let warmFactor = (4000 - kelvin) / 1300 // 0 to 1
            r = 1.0
            g = 0.8 + (warmFactor * 0.2)  // 0.8 to 1.0
            b = 0.3 - (warmFactor * 0.3)  // 0.3 to 0.0
        } else {
            // Cool white range (4000K-8000K)
            let coolFactor = (kelvin - 4000) / 4000 // 0 to 1
            r = 1.0 - (coolFactor * 0.2)  // 1.0 to 0.8
            g = 1.0
            b = 0.8 + (coolFactor * 0.2)   // 0.8 to 1.0
        }
        
        // Apply minimum brightness to prevent black colors
        let minBrightness: CGFloat = 0.1
        let finalR = max(minBrightness, r)
        let finalG = max(minBrightness, g)
        let finalB = max(minBrightness, b)
        
        selectedColor = Color(red: finalR, green: finalG, blue: finalB)
        extractHSV(from: selectedColor)
    }
    
    private func applyColorToDevice() {
        // Apply color using WLED-accurate conversion
        // For RGBWW strips: The color picker should detect when temperature slider
        // is being used and send appropriate WW/CW channel commands instead of RGB
        onColorChange(selectedColor)
        
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

