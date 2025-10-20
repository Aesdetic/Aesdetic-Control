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
                        
                        // Vertical saturation gradient (white to transparent)
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
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
            
            // Temperature Slider
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
                
                Slider(value: $temperature, in: 0...1, step: 0.01, onEditingChanged: { editing in
                    if !editing {
                        // Apply temperature shift on release
                        applyTemperatureShift()
                        applyColorToDevice()
                    }
                })
                .accentColor(.orange)
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
                    
                    Button(action: saveCurrentColor) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 32, height: 32)
                            )
                    }
                }
                
                HStack(spacing: 8) {
                    ForEach(0..<6) { index in
                        if index < savedColors.count {
                            // Saved color button
                            Button(action: {
                                let color = Color(hex: savedColors[index])
                                selectedColor = color
                                extractHSV(from: color)
                                applyColorToDevice()
                            }) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: savedColors[index]))
                                    .frame(height: 44)
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
                        } else {
                            // Empty slot
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
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
        if temperature < 0.3 {
            return "Orange"
        } else if temperature < 0.7 {
            return "White"
        } else {
            return "Cool White"
        }
    }
    
    private func updateColor() {
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
        let x = max(0, min(location.x, size.width))
        let y = max(0, min(location.y, size.height))
        
        hue = Double(x / size.width)
        saturation = 1.0 - Double(y / size.height)
        
        updateColor()
        updatePickerPosition()
    }
    
    private func updatePickerPosition() {
        // Calculate position based on current hue and saturation
        // Use a reasonable default size that will be updated by GeometryReader
        let defaultSize: CGFloat = 300 // Reasonable default
        pickerPosition = CGPoint(x: hue * defaultSize, y: (1.0 - saturation) * defaultSize)
    }
    
    private func updatePickerPosition(in size: CGSize) {
        // Calculate position based on current hue and saturation with actual geometry size
        let x = hue * Double(size.width)
        let y = (1.0 - saturation) * Double(size.height)
        pickerPosition = CGPoint(x: x, y: y)
    }
    
    private func applyTemperatureShift() {
        // Apply color temperature shift to current color
        // Temperature range: 0 = orange, 0.5 = white, 1 = cool white
        
        // Extract RGB from current color
        let uiColor = UIColor(selectedColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Apply temperature shift based on simplified range
        if temperature < 0.3 {
            // Orange shift: increase red, decrease blue
            let orangeShift = (0.3 - temperature) / 0.3 * 0.2
            r = min(1, r + orangeShift)
            b = max(0, b - orangeShift * 0.5)
        } else if temperature > 0.7 {
            // Cool white shift: decrease red, increase blue
            let coolShift = (temperature - 0.7) / 0.3 * 0.2
            r = max(0, r - coolShift * 0.5)
            b = min(1, b + coolShift)
        }
        // White range (0.3-0.7) keeps original color
        
        selectedColor = Color(red: r, green: g, blue: b)
        extractHSV(from: selectedColor)
    }
    
    private func applyColorToDevice() {
        // Apply color using WLED-accurate conversion
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
        // Keep only last 6 colors (FIFO)
        let limited = Array(colors.suffix(6))
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
        
        // Auto-remove oldest if > 6
        if colors.count > 6 {
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

