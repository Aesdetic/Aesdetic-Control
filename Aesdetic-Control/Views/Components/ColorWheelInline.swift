import SwiftUI

struct ColorWheelInline: View {
    let initialColor: Color
    let canRemove: Bool
    let supportsCCT: Bool
    let supportsWhite: Bool
    let usesKelvinCCT: Bool
    let onColorChange: (Color, Double?, Double?) -> Void  // Color, optional temperature (0-1), optional white level (0-1)
    let onRemove: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var selectedColor: Color
    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var temperature: Double = 0.5 // 0 = orange, 0.5 = white, 1 = cool white
    @State private var whiteLevel: Double = 0.0 // 0 = no white, 1 = full white (for RGBW strips)
    @State private var pickerPosition: CGPoint = .zero
    @State private var hexInput: String = ""
    @State private var isUsingTemperatureSlider: Bool = false
    @State private var isEditingHex: Bool = false
    @AppStorage("savedGradientColors") private var savedColorsData: Data = Data()
    
    init(initialColor: Color, canRemove: Bool, supportsCCT: Bool, supportsWhite: Bool, usesKelvinCCT: Bool, onColorChange: @escaping (Color, Double?, Double?) -> Void, onRemove: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.initialColor = initialColor
        self.canRemove = canRemove
        self.supportsCCT = supportsCCT
        self.supportsWhite = supportsWhite
        self.usesKelvinCCT = usesKelvinCCT
        self.onColorChange = onColorChange
        self.onRemove = onRemove
        self.onDismiss = onDismiss
        _selectedColor = State(initialValue: initialColor)
    }
    
    var body: some View {
        ZStack {
            // Background tap area to dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 16) {
                // Header
                HStack {
                Text("Color Picker")
                    .font(.headline)
                    .foregroundColor(primaryLabelColor)
                
                Spacer()
                
                // Hex Code (editable in place)
                if isEditingHex {
                    HStack(spacing: 4) {
                        Text("#")
                            .foregroundColor(secondaryLabelColor)
                            .font(.caption)
                        
                        TextField("FF5733", text: $hexInput)
                            .font(.caption.monospaced())
                            .foregroundColor(primaryLabelColor)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(fieldBackgroundColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(fieldStrokeColor, lineWidth: 1)
                            )
                            .frame(width: 60)
                            .onSubmit {
                                applyHexColor()
                                isEditingHex = false
                            }
                            .onChange(of: hexInput) { _, newValue in
                                // Auto-apply when valid hex is entered, but NOT during temperature slider drag
                                if isValidHex(newValue) && !isUsingTemperatureSlider {
                                    applyHexColor()
                                }
                            }
                    }
                } else {
                    Button(action: {
                        isEditingHex = true
                    }) {
                        Text("#\(hexInput)")
                            .font(.caption.monospaced())
                            .foregroundColor(tertiaryLabelColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(chipBackgroundColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(chipStrokeColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit hex color")
                    .accessibilityHint("Switches to text entry for the color code.")
                }
                
                // Remove Stop Button (if can remove)
                if canRemove {
                    Button(action: {
                        onRemove()
                        onDismiss()
                    }) {
                        Text("- Remove")
                            .font(.caption)
                            .foregroundColor(inverseButtonForeground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(inverseButtonBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(fieldStrokeColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove gradient stop")
                    .accessibilityHint("Deletes the selected stop from the gradient.")
                }
                
                Button(action: { onDismiss() }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(inverseButtonForeground)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(inverseButtonBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(fieldStrokeColor, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close color picker")
                .accessibilityHint("Dismisses the inline color picker.")
            }
            
            // Custom 2D Rectangular Color Gradient Picker
            customColorPickerView
            
            // Saved Colors Section
            savedColorsSection
        }
        .padding(20)
        .background(containerBackgroundColor)
        .cornerRadius(16)
        .onTapGesture {
            // Block dismissal when tapping inside the color picker container
            // This prevents the background tap gesture from dismissing the picker
        }
        .onAppear {
            extractHSV(from: initialColor)
            extractTemperature(from: initialColor)
            updatePickerPosition()
            updateHexInput()
        }
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
            
            // Temperature Slider with Visual Gradient (shown only if device supports CCT)
            if supportsCCT {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "thermometer.sun")
                        .foregroundColor(.orange)
                    Text("Temperature")
                        .foregroundColor(secondaryLabelColor)
                    Spacer()
                    Text(temperatureText)
                        .foregroundColor(secondaryLabelColor)
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
                                let oldTemp = temperature
                                temperature = max(0, min(1, newValue))
                                isUsingTemperatureSlider = true
                                // Only update visual preview during drag, don't apply to device
                                #if DEBUG
                                print("🔵 Temperature slider: onChanged - temp changed from \(oldTemp) to \(temperature), NOT applying to device")
                                #endif
                                applyTemperatureShift()
                            }
                            .onEnded { value in
                                // Apply to device only when drag ends (on release)
                                #if DEBUG
                                print("🔵 Temperature slider: onEnded - temp=\(temperature), NOW applying to device")
                                print("🔵 Temperature slider: isUsingTemperatureSlider=\(isUsingTemperatureSlider)")
                                #endif
                                // CRITICAL: Update hex input AFTER slider is released (not during drag)
                                updateHexInput()
                                // Ensure flag is still set after updateHexInput
                                isUsingTemperatureSlider = true
                                #if DEBUG
                                print("🔵 Temperature slider: About to call applyColorToDevice()")
                                #endif
                                applyColorToDevice()
                                #if DEBUG
                                print("🔵 Temperature slider: Finished calling applyColorToDevice()")
                                #endif
                            }
                    )
                }
                .frame(height: 20)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(usesKelvinCCT ? "Color temperature" : "Color temperature")
            .accessibilityValue(temperatureText)
            .accessibilityIdentifier("CCTTemperatureSlider") // For UI testing
            .accessibilityHint(usesKelvinCCT ? "Adjusts the light's color temperature in Kelvin." : "Adjusts between warm and cool white.")
            .accessibilityAdjustableAction { direction in
                let step: Double = 0.05
                switch direction {
                case .increment:
                    temperature = min(1, temperature + step)
                case .decrement:
                    temperature = max(0, temperature - step)
                @unknown default:
                    break
                }
                isUsingTemperatureSlider = true
                applyTemperatureShift()
                applyColorToDevice()
            }
            }
            
            // White Channel Slider (shown only if device supports white channel - RGBW strips)
            if supportsWhite {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.white)
                    Text("White Channel")
                        .foregroundColor(secondaryLabelColor)
                    Spacer()
                    Text(whiteLevelText)
                        .foregroundColor(secondaryLabelColor)
                }
                .font(.caption)
                
                // Custom slider with white gradient
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Gradient from no white to full white
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.3),  // No white
                                Color.white                 // Full white
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
                            .offset(x: CGFloat(whiteLevel) * (geometry.size.width - 20))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newValue = Double(value.location.x / geometry.size.width)
                                whiteLevel = max(0, min(1, newValue))
                                // Don't apply during drag, just update preview
                            }
                            .onEnded { _ in
                                // Apply color to device only on release
                                applyColorToDevice()
                            }
                    )
                }
                .frame(height: 20)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("White channel")
            .accessibilityValue(whiteLevelText)
            .accessibilityHint("Blends in neutral white LEDs.")
            .accessibilityAdjustableAction { direction in
                let step: Double = 0.05
                switch direction {
                case .increment:
                    whiteLevel = min(1, whiteLevel + step)
                case .decrement:
                    whiteLevel = max(0, whiteLevel - step)
                @unknown default:
                    break
                }
                applyColorToDevice()
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
                    .foregroundColor(secondaryLabelColor)
                
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
                            // Reset temperature flag when using saved color
                            isUsingTemperatureSlider = false
                            applyColorToDevice()
                        }) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(hex: colorHex))
                                .frame(width: 29, height: 29)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.white.opacity(adjustedOpacity(0.3)), lineWidth: 1)
                                )
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteSavedColor(at: index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityLabel("Saved color \(index + 1)")
                        .accessibilityHint("Applies the stored color to the device.")
                    }
                    
                    // Add new color button (only show if under max limit)
                    if savedColors.count < 8 {
                        Button(action: saveCurrentColor) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(chipBackgroundColor)
                                .frame(width: 29, height: 29)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.white.opacity(adjustedOpacity(0.3)), lineWidth: 1)
                                )
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.caption)
                                        .foregroundColor(tertiaryLabelColor)
                                )
                        }
                        .accessibilityLabel("Save current color")
                        .accessibilityHint("Adds the current selection to saved colors.")
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private var temperatureText: String {
        if usesKelvinCCT {
            let kelvin = Segment.kelvinValue(fromNormalized: temperature)
            return "\(kelvin)K"
        }
        let eightBit = Segment.eightBitValue(fromNormalized: temperature)
        if temperature < 0.3 {
            return "CCT \(eightBit) (Warm)"
        } else if temperature < 0.7 {
            return "CCT \(eightBit) (Neutral)"
        } else {
            return "CCT \(eightBit) (Cool)"
        }
    }
    
    private var whiteLevelText: String {
        // Convert white level (0-1) to percentage
        let percentage = Int(whiteLevel * 100)
        return "\(percentage)%"
    }
    
    private func updateColor() {
        // Don't override temperature-generated colors
        if isUsingTemperatureSlider {
            return
        }
        
        // HSV colors are device-independent, so we can use standard Color initializer
        // The critical sRGB conversion happens when extracting RGB values (toHex/toRGBArray)
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
    
    private func extractTemperature(from color: Color) {
        // Reverse the temperature calculation to find which CCT temperature matches this color
        let rgb = color.toRGBArray()
        guard rgb.count >= 3 else { return }
        
        let r = Double(rgb[0]) / 255.0
        let g = Double(rgb[1]) / 255.0
        let b = Double(rgb[2]) / 255.0
        
        // WLED's CCT colors:
        // #FFA000 = RGB(255, 160, 0)
        // #FFF1EA = RGB(255, 241, 234)
        // #CBDBFF = RGB(203, 219, 255)
        
        // Warm white (2700K): #FFA000 = (1.0, 0.627, 0.0)
        let warmR: Double = 1.0
        let warmG: Double = 0.627
        let warmB: Double = 0.0
        
        // Neutral white (4000K): #FFF1EA = (1.0, 0.945, 0.918)
        let neutralR: Double = 1.0
        let neutralG: Double = 0.945
        let neutralB: Double = 0.918
        
        // Cool white (6500K): #CBDBFF = (0.796, 0.859, 1.0)
        let coolR: Double = 0.796
        let coolG: Double = 0.859
        let coolB: Double = 1.0
        
        // Calculate distance to each CCT point
        let distToWarm = sqrt(pow(r - warmR, 2) + pow(g - warmG, 2) + pow(b - warmB, 2))
        let distToNeutral = sqrt(pow(r - neutralR, 2) + pow(g - neutralG, 2) + pow(b - neutralB, 2))
        let distToCool = sqrt(pow(r - coolR, 2) + pow(g - coolG, 2) + pow(b - coolB, 2))
        
        // Find the closest CCT temperature
        let minDist = min(distToWarm, distToNeutral, distToCool)
        
        if minDist == distToWarm {
            // Closest to warm white (2700K), check if in warm-neutral range
            if g > 0.7 && b > 0.5 {
                // Interpolate between warm and neutral
                temperature = 0.25 // Estimate based on color position
            } else {
                temperature = 0.0
            }
        } else if minDist == distToNeutral {
            // Check if closer to warm or cool side
            if distToWarm < distToCool {
                // Interpolate in warm-neutral range (0.0 to 0.5)
                let factor = distToWarm / (distToWarm + distToNeutral)
                temperature = 0.5 * factor
            } else {
                // Interpolate in neutral-cool range (0.5 to 1.0)
                let factor = distToCool / (distToCool + distToNeutral)
                temperature = 0.5 + (0.5 * factor)
            }
        } else {
            // Closest to cool white (6500K)
            if g > 0.8 && r > 0.7 {
                // Interpolate between neutral and cool
                temperature = 0.75 // Estimate based on color position
            } else {
                temperature = 1.0
            }
        }
        
        // If the color is clearly a CCT white (low saturation), set isUsingTemperatureSlider to true
        if saturation < 0.3 {
            isUsingTemperatureSlider = true
        }
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
        
        // Use shared CCT color calculation utility
        let components = Color.cctColorComponents(temperature: temperature)
        selectedColor = Color(.sRGB, red: Double(components.r), green: Double(components.g), blue: Double(components.b), opacity: 1.0)
        extractHSV(from: selectedColor)
        // Don't update hexInput during temperature slider drag - it triggers onChange and applies prematurely
        // Hex input will be updated when slider is released
    }
    
    private func applyColorToDevice() {
        #if DEBUG
        print("🔵 applyColorToDevice() called - isUsingTemperatureSlider=\(isUsingTemperatureSlider), temperature=\(temperature)")
        #endif
        // CRITICAL FIX: Ensure we always send sRGB color to WLED
        // Convert selectedColor to hex string (which uses toRGBArray() for correct sRGB extraction)
        // Then recreate Color from hex to ensure sRGB consistency
        let hexString = selectedColor.toHex()
        let sRGBColor = Color(hex: hexString)  // Color(hex:) creates sRGB color explicitly
        
        // Apply color using WLED-accurate conversion
        // For RGBW strips: Pass white level (0-1) if white channel is supported
        // For RGBCCT strips: Pass temperature (0-1) if temperature slider is being used
        let temperatureValue = isUsingTemperatureSlider ? temperature : nil
        let whiteLevelValue = supportsWhite && whiteLevel > 0.0 ? whiteLevel : nil
        #if DEBUG
        print("🔵 applyColorToDevice() calling onColorChange - tempValue=\(temperatureValue?.description ?? "nil")")
        #endif
        onColorChange(sRGBColor, temperatureValue, whiteLevelValue)
        
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
        // Reset temperature flag when using hex input
        isUsingTemperatureSlider = false
        applyColorToDevice()
    }
    
    private func updateHexInput() {
        hexInput = selectedColor.toHex().replacingOccurrences(of: "#", with: "")
    }
}


private extension ColorWheelInline {
    var containerBackgroundColor: Color {
        Color.white.opacity(adjustedOpacity(0.12))
    }

    var primaryLabelColor: Color {
        .white
    }

    var secondaryLabelColor: Color {
        colorSchemeContrast == .increased ? .white : .white.opacity(0.8)
    }

    var tertiaryLabelColor: Color {
        colorSchemeContrast == .increased ? .white.opacity(0.95) : .white.opacity(0.7)
    }

    var fieldBackgroundColor: Color {
        Color.white.opacity(adjustedOpacity(0.1))
    }

    var fieldStrokeColor: Color {
        Color.white.opacity(adjustedOpacity(0.2))
    }

    var chipBackgroundColor: Color {
        Color.white.opacity(adjustedOpacity(0.05))
    }

    var chipStrokeColor: Color {
        Color.white.opacity(adjustedOpacity(0.12))
    }

    var inverseButtonBackground: Color {
        Color.white.opacity(adjustedOpacity(0.75))
    }

    var inverseButtonForeground: Color {
        Color.black.opacity(colorSchemeContrast == .increased ? 0.9 : 0.7)
    }

    func adjustedOpacity(_ base: Double) -> Double {
        colorSchemeContrast == .increased ? min(1.0, base * 1.6) : base
    }
}


