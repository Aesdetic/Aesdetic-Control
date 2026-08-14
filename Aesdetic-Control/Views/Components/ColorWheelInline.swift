import SwiftUI

struct ColorWheelInline: View {
    let initialColor: Color
    let initialTemperature: Double?
    let initialWhiteLevel: Double?
    let canRemove: Bool
    let supportsCCT: Bool
    let supportsWhite: Bool
    let usesKelvinCCT: Bool
    let allowCCTForTemperatureStops: Bool
    let allowManualWhite: Bool
    let autoWhiteEnabled: Bool
    let cctKelvinRange: ClosedRange<Int>
    let onColorChange: (Color, Double?, Double?) -> Void  // Color, optional temperature (0-1), optional white level (0-1)
    let onColorPreview: ((Color, Double?, Double?) -> Void)?
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
    @State private var spectrumSize: CGSize = .zero
    @State private var hexInput: String = ""
    @State private var isUsingTemperatureSlider: Bool = false
    @State private var isEditingHex: Bool = false
    @State private var isProgrammaticSyncInProgress: Bool = false
    @State private var colorPreviewWorkItem: DispatchWorkItem?
    @State private var lastColorPreviewSentAt: Date = .distantPast
    @AppStorage("savedGradientColors") private var savedColorsData: Data = Data()
    
    init(
        initialColor: Color,
        initialTemperature: Double? = nil,
        initialWhiteLevel: Double? = nil,
        canRemove: Bool,
        supportsCCT: Bool,
        supportsWhite: Bool,
        usesKelvinCCT: Bool,
        allowCCTForTemperatureStops: Bool = false,
        allowManualWhite: Bool = true,
        autoWhiteEnabled: Bool = false,
        cctKelvinRange: ClosedRange<Int>? = nil,
        onColorChange: @escaping (Color, Double?, Double?) -> Void,
        onColorPreview: ((Color, Double?, Double?) -> Void)? = nil,
        onRemove: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.initialColor = initialColor
        self.initialTemperature = initialTemperature
        self.initialWhiteLevel = initialWhiteLevel
        self.canRemove = canRemove
        self.supportsCCT = supportsCCT
        self.supportsWhite = supportsWhite
        self.usesKelvinCCT = usesKelvinCCT
        self.allowCCTForTemperatureStops = allowCCTForTemperatureStops
        self.allowManualWhite = allowManualWhite
        self.autoWhiteEnabled = autoWhiteEnabled
        self.cctKelvinRange = cctKelvinRange ?? Self.defaultKelvinRange
        self.onColorChange = onColorChange
        self.onColorPreview = onColorPreview
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
                    .font(AppTypography.style(.headline))
                    .foregroundColor(primaryLabelColor)
                
                Spacer()
                
                // Hex Code (editable in place)
                if isEditingHex {
                    HStack(spacing: 4) {
                        Text("#")
                            .foregroundColor(secondaryLabelColor)
                            .font(AppTypography.style(.caption))
                        
                        TextField("FF5733", text: $hexInput)
                            .font(AppTypography.style(.caption))
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
                                if isProgrammaticSyncInProgress {
                                    #if DEBUG
                                    print("color_wheel.hex_auto_apply_suppressed_programmatic_sync")
                                    #endif
                                    return
                                }
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
                            .font(AppTypography.style(.caption))
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
                            .font(AppTypography.style(.caption))
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
                        .font(AppTypography.style(.caption))
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
            syncFromInitialState(force: true)
        }
        .onChange(of: initialColor) { _, _ in
            syncFromInitialState(force: false)
        }
        .onChange(of: initialTemperature) { _, _ in
            syncFromInitialState(force: true)
        }
        .onChange(of: initialWhiteLevel) { _, _ in
            syncFromInitialState(force: true)
        }
        .onDisappear {
            cancelColorPreview()
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
                            // Apple's spectrum: hue horizontally, saturation vertically.
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
                            // White overlay at the top creates the low-saturation edge.
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Apple's exact indicator design
                    spectrumIndicator
                        .position(pickerPosition)
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
                    updateSpectrumIndicatorPosition(in: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    updateSpectrumIndicatorPosition(in: newSize)
                }
            }
            .frame(height: 200)
            
            // Temperature Slider with Visual Gradient (shown only if device supports CCT)
            if supportsCCT {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "thermometer.sun")
                        .foregroundColor(.orange)
                    Text("White Temperature")
                        .foregroundColor(secondaryLabelColor)
                    Spacer()
                    if allowCCTForTemperatureStops && isUsingTemperatureSlider {
                        Text("CCT")
                            .font(AppTypography.style(.caption2, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundColor(.white)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
                .font(AppTypography.style(.caption))
                
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
                                // Only update visual preview during drag, don't apply to device
                                applyTemperatureShift()
                                updateSpectrumIndicatorPosition()
                                scheduleColorPreview()
                            }
                            .onEnded { value in
                                // Apply to device only when drag ends (on release)
                                // CRITICAL: Update hex input AFTER slider is released (not during drag)
                                updateHexInput()
                                // Ensure flag is still set after updateHexInput
                                isUsingTemperatureSlider = true
                                cancelColorPreview()
                                applyColorToDevice()
                            }
                    )
                }
                .frame(height: 20)
                HStack {
                    Text("Warm")
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(secondaryLabelColor)
                    Spacer()
                    Text("Cool")
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(secondaryLabelColor)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("White temperature")
            .accessibilityValue(temperatureText)
            .accessibilityIdentifier("CCTTemperatureSlider") // For UI testing
            .accessibilityHint("Adjusts between warm and cool white.")
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
                updateSpectrumIndicatorPosition()
                applyColorToDevice()
            }
            }
            
            // White Channel Slider (manual override, advanced UI only)
            if supportsWhite && allowManualWhite {
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
                .font(AppTypography.style(.caption))
                
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
                                isUsingTemperatureSlider = false
                                // Don't apply during drag, just update preview
                                scheduleColorPreview()
                            }
                            .onEnded { _ in
                                isUsingTemperatureSlider = false
                                // Apply color to device only on release
                                cancelColorPreview()
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
                isUsingTemperatureSlider = false
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
                    .font(AppTypography.style(.caption))
                    .foregroundColor(secondaryLabelColor)
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Saved colors
                    ForEach(Array(savedSwatches.enumerated()), id: \.offset) { index, swatch in
                        Button(action: {
                            applySavedSwatch(swatch)
                        }) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(swatch.color)
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
                        .accessibilityLabel(savedSwatchAccessibilityLabel(swatch, index: index))
                        .accessibilityHint("Applies the stored color to the device.")
                    }
                    
                    // Add new color button (only show if under max limit)
                    if savedSwatches.count < 8 {
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
                                        .font(AppTypography.style(.caption))
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
    
    private static let defaultKelvinRange: ClosedRange<Int> = 1900...10091
    private static let spectrumIndicatorRadius: CGFloat = 10
    private static let livePreviewInterval: TimeInterval = 0.09

    private var spectrumIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 20, height: 20)

            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
        .accessibilityHidden(true)
    }

    private func syncFromInitialState(force: Bool) {
        if !force, initialColor.toHex() == selectedColor.toHex() {
            return
        }
        #if DEBUG
        print("color_wheel.sync.begin force=\(force)")
        #endif
        isProgrammaticSyncInProgress = true
        selectedColor = initialColor
        extractHSV(from: initialColor)
        if let initialTemperature {
            temperature = max(0.0, min(1.0, initialTemperature))
            isUsingTemperatureSlider = true
            applyTemperatureShift()
        } else {
            isUsingTemperatureSlider = false
            extractTemperature(from: initialColor)
        }
        if let initialWhiteLevel, supportsWhite, allowManualWhite {
            whiteLevel = max(0.0, min(1.0, initialWhiteLevel))
        } else {
            whiteLevel = 0.0
        }
        updateSpectrumIndicatorPosition()
        updateHexInput()
        Task { @MainActor in
            isProgrammaticSyncInProgress = false
            #if DEBUG
            print("color_wheel.sync.end")
            #endif
        }
    }
    
    private var temperatureText: String {
        let clamped = max(0.0, min(1.0, temperature))
        if usesKelvinCCT {
            let kelvin = kelvinValue(fromNormalized: clamped)
            return "\(kelvin)K"
        }
        let percentCool = Int(round(clamped * 100))
        if percentCool == 0 {
            return "Warm"
        }
        if percentCool == 100 {
            return "Cool"
        }
        return "Warm to cool, \(percentCool)% cool"
    }

    private func kelvinValue(fromNormalized normalized: Double) -> Int {
        let clamped = max(0.0, min(1.0, normalized))
        let span = Double(cctKelvinRange.upperBound - cctKelvinRange.lowerBound)
        return Int(round(Double(cctKelvinRange.lowerBound) + clamped * span))
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
        
        // Keep temperature in sync for UI, but don't auto-enable temperature mode.
    }
    
    // Apple's exact spectrum position calculation
    private func updateAppleSpectrumPosition(_ location: CGPoint, in size: CGSize) {
        spectrumSize = size
        let point = ColorWheelSpectrumGeometry.clampedPoint(
            location,
            in: size,
            indicatorRadius: Self.spectrumIndicatorRadius
        )
        
        // Map to Apple's HSV color space
        let values = ColorWheelSpectrumGeometry.values(
            from: point,
            in: size,
            indicatorRadius: Self.spectrumIndicatorRadius
        )
        hue = values.hue
        saturation = values.saturation
        
        // Reset temperature slider flag when using color picker
        isUsingTemperatureSlider = false
        
        updateColor()
        updateSpectrumIndicatorPosition(in: size)
        scheduleColorPreview()
    }

    private func updateSpectrumIndicatorPosition(in size: CGSize? = nil) {
        if let size {
            spectrumSize = size
        }

        pickerPosition = ColorWheelSpectrumGeometry.position(
            hue: hue,
            saturation: saturation,
            in: size ?? spectrumSize,
            indicatorRadius: Self.spectrumIndicatorRadius
        )
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
        let payload = currentColorPayload()
        onColorChange(payload.color, payload.temperature, payload.whiteLevel)

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func scheduleColorPreview() {
        guard onColorPreview != nil else { return }

        // Keep at most one pending preview, but anchor its deadline to the last
        // sent update. A simple debounce never fires while a drag produces
        // events faster than the preview interval.
        colorPreviewWorkItem?.cancel()
        let payload = currentColorPayload()
        let elapsed = Date().timeIntervalSince(lastColorPreviewSentAt)
        let delay = max(0, Self.livePreviewInterval - elapsed)
        let work = DispatchWorkItem {
            lastColorPreviewSentAt = Date()
            colorPreviewWorkItem = nil
            onColorPreview?(payload.color, payload.temperature, payload.whiteLevel)
        }
        colorPreviewWorkItem = work

        if delay == 0 {
            work.perform()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !work.isCancelled {
                work.perform()
            }
        }
    }

    private func cancelColorPreview() {
        colorPreviewWorkItem?.cancel()
        colorPreviewWorkItem = nil
    }

    private func currentColorPayload() -> (color: Color, temperature: Double?, whiteLevel: Double?) {
        // CRITICAL FIX: Ensure we always send sRGB color to WLED
        // Convert selectedColor to hex string (which uses toRGBArray() for correct sRGB extraction)
        // Then recreate Color from hex to ensure sRGB consistency
        let hexString = selectedColor.toHex()
        let sRGBColor = Color(hex: hexString)  // Color(hex:) creates sRGB color explicitly
        
        // Apply color using WLED-accurate conversion
        // For RGBW strips: Pass white level (0-1) if white channel is supported
        // For RGBCCT strips: Pass temperature (0-1) if temperature slider is being used
        let temperatureValue = isUsingTemperatureSlider ? temperature : nil
        let whiteLevelValue = resolvedWhiteLevel(forTemperature: isUsingTemperatureSlider)
        if isUsingTemperatureSlider, let whiteLevelValue, whiteLevel <= 0.0 {
            whiteLevel = whiteLevelValue
        }
        return (sRGBColor, temperatureValue, whiteLevelValue)
    }
    
    // MARK: - Saved Colors Management
    
    private var savedSwatches: [SavedColorSwatch] {
        if let swatches = try? JSONDecoder().decode([SavedColorSwatch].self, from: savedColorsData) {
            return swatches
        }
        if let legacyHexColors = try? JSONDecoder().decode([String].self, from: savedColorsData) {
            return legacyHexColors.map { SavedColorSwatch(hexColor: $0) }
        }
        return []
    }
    
    private func updateSavedSwatches(_ swatches: [SavedColorSwatch]) {
        // Keep only last 8 colors (FIFO)
        let limited = Array(swatches.suffix(8))
        if let data = try? JSONEncoder().encode(limited) {
            savedColorsData = data
        }
    }
    
    private func saveCurrentColor() {
        var swatches = savedSwatches
        let swatch = SavedColorSwatch(
            hexColor: selectedColor.toHex(),
            temperature: isUsingTemperatureSlider ? temperature : nil,
            whiteLevel: whiteLevel > 0.0 ? whiteLevel : nil
        )
        
        // Remove if already exists (to avoid duplicates)
        swatches.removeAll { $0.matches(swatch) }
        
        // Add to end
        swatches.append(swatch)
        
        // Auto-remove oldest if > 8
        if swatches.count > 8 {
            swatches.removeFirst()
        }
        
        updateSavedSwatches(swatches)
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func deleteSavedColor(at index: Int) {
        var swatches = savedSwatches
        guard index < swatches.count else { return }
        swatches.remove(at: index)
        updateSavedSwatches(swatches)
    }

    private func applySavedSwatch(_ swatch: SavedColorSwatch) {
        selectedColor = swatch.color
        extractHSV(from: selectedColor)

        if supportsCCT, let savedTemperature = swatch.temperature {
            temperature = savedTemperature
            isUsingTemperatureSlider = true
            applyTemperatureShift()
        } else {
            isUsingTemperatureSlider = false
        }

        if supportsWhite, allowManualWhite {
            whiteLevel = swatch.whiteLevel ?? 0.0
        } else {
            whiteLevel = 0.0
        }

        updateSpectrumIndicatorPosition()
        updateHexInput()
        applyColorToDevice()
    }

    private func savedSwatchAccessibilityLabel(_ swatch: SavedColorSwatch, index: Int) -> String {
        if swatch.temperature != nil {
            return "Saved CCT color \(index + 1)"
        }
        if swatch.whiteLevel != nil {
            return "Saved white channel color \(index + 1)"
        }
        return "Saved color \(index + 1)"
    }
    
    // MARK: - Hex Input Functions
    
    private func isValidHex(_ hex: String) -> Bool {
        let cleanHex = hex.replacingOccurrences(of: "#", with: "").uppercased()
        return cleanHex.count == 6 && cleanHex.allSatisfy { $0.isHexDigit }
    }
    
    private func applyHexColor() {
        guard !isProgrammaticSyncInProgress else { return }
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

    private func resolvedWhiteLevel(forTemperature: Bool) -> Double? {
        guard supportsWhite, allowManualWhite else { return nil }
        if forTemperature {
            if allowCCTForTemperatureStops {
                return nil
            }
            if whiteLevel > 0.0 { return whiteLevel }
            if autoWhiteEnabled {
                return nil
            }
            // Default gentle white blend when CCT is unavailable on RGBW strips.
            return 0.35
        }
        if whiteLevel > 0.0 { return whiteLevel }
        return nil
    }
}

struct SavedColorSwatch: Codable, Hashable {
    var hexColor: String
    var temperature: Double?
    var whiteLevel: Double?

    private enum CodingKeys: String, CodingKey {
        case hexColor
        case temperature
        case whiteLevel
    }

    init(hexColor: String, temperature: Double? = nil, whiteLevel: Double? = nil) {
        self.hexColor = hexColor.replacingOccurrences(of: "#", with: "").uppercased()
        self.temperature = temperature.map(Self.clampUnit)
        self.whiteLevel = whiteLevel.map(Self.clampUnit)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hexColor: try container.decode(String.self, forKey: .hexColor),
            temperature: try container.decodeIfPresent(Double.self, forKey: .temperature),
            whiteLevel: try container.decodeIfPresent(Double.self, forKey: .whiteLevel)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hexColor, forKey: .hexColor)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(whiteLevel, forKey: .whiteLevel)
    }

    var color: Color {
        Color(hex: hexColor)
    }

    func matches(_ other: SavedColorSwatch) -> Bool {
        hexColor == other.hexColor &&
        Self.optionalUnitValue(temperature, equals: other.temperature) &&
        Self.optionalUnitValue(whiteLevel, equals: other.whiteLevel)
    }

    private static func clampUnit(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }

    private static func optionalUnitValue(_ lhs: Double?, equals rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs - rhs) < 0.000001
        default:
            return false
        }
    }
}

struct ColorWheelSpectrumGeometry {
    static func position(
        hue: Double,
        saturation: Double,
        in size: CGSize,
        indicatorRadius: CGFloat
    ) -> CGPoint {
        let bounds = interactionBounds(in: size, indicatorRadius: indicatorRadius)
        return CGPoint(
            x: bounds.minX + CGFloat(clampUnit(hue)) * (bounds.maxX - bounds.minX),
            y: bounds.minY + CGFloat(clampUnit(saturation)) * (bounds.maxY - bounds.minY)
        )
    }

    static func values(
        from location: CGPoint,
        in size: CGSize,
        indicatorRadius: CGFloat
    ) -> (hue: Double, saturation: Double) {
        let bounds = interactionBounds(in: size, indicatorRadius: indicatorRadius)
        let point = clampedPoint(location, in: size, indicatorRadius: indicatorRadius)
        return (
            hue: Double((point.x - bounds.minX) / max(CGFloat(1), bounds.maxX - bounds.minX)),
            saturation: Double((point.y - bounds.minY) / max(CGFloat(1), bounds.maxY - bounds.minY))
        )
    }

    static func clampedPoint(
        _ location: CGPoint,
        in size: CGSize,
        indicatorRadius: CGFloat
    ) -> CGPoint {
        let bounds = interactionBounds(in: size, indicatorRadius: indicatorRadius)
        return CGPoint(
            x: max(bounds.minX, min(location.x, bounds.maxX)),
            y: max(bounds.minY, min(location.y, bounds.maxY))
        )
    }

    private static func interactionBounds(in size: CGSize, indicatorRadius: CGFloat) -> CGRect {
        let minX = indicatorRadius
        let minY = indicatorRadius
        let maxX = max(minX, size.width - indicatorRadius)
        let maxY = max(minY, size.height - indicatorRadius)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func clampUnit(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
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
