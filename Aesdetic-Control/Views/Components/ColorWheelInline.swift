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
    @State private var temperature: Double = 5000 // Kelvin (2000-9000)
    @State private var pickerPosition: CGPoint = .zero
    @State private var useNativePicker: Bool = true // Toggle between native and custom
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
                
                // Toggle between native and custom picker
                Button(action: { 
                    useNativePicker.toggle()
                }) {
                    Image(systemName: useNativePicker ? "paintpalette" : "square.grid.3x3")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Button(action: { onDismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            if useNativePicker {
                // Apple's Native ColorPicker
                nativeColorPickerView
            } else {
                // Custom 2D Rectangular Color Gradient Picker
                customColorPickerView
            }
            
            // Saved Colors Section (shared between both)
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
        }
        .onChange(of: selectedColor) { _, newColor in
            if useNativePicker {
                // Auto-apply when using native picker
                applyColorToDevice()
            }
        }
    }
    
    // MARK: - Native ColorPicker View
    
    private var nativeColorPickerView: some View {
        VStack(spacing: 16) {
            // Apple's native color picker
            ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(height: 200)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            
            // Temperature Slider (still useful with native picker)
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "thermometer.sun")
                        .foregroundColor(.orange)
                    Text("Temperature")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(temperature))K")
                        .foregroundColor(.white.opacity(0.8))
                }
                .font(.caption)
                
                Slider(value: $temperature, in: 2000...9000, step: 100, onEditingChanged: { editing in
                    if !editing {
                        applyTemperatureShift()
                        applyColorToDevice()
                    }
                })
                .accentColor(.orange)
            }
            
            // Brightness Slider
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "sun.max")
                        .foregroundColor(.yellow)
                    Text("Brightness")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(brightness * 100))%")
                        .foregroundColor(.white.opacity(0.8))
                }
                .font(.caption)
                
                Slider(value: $brightness, in: 0...1, step: 0.01, onEditingChanged: { editing in
                    if !editing {
                        updateColor()
                        applyColorToDevice()
                    }
                })
                .accentColor(.yellow)
            }
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
                    Text("\(Int(temperature))K")
                        .foregroundColor(.white.opacity(0.8))
                }
                .font(.caption)
                
                Slider(value: $temperature, in: 2000...9000, step: 100, onEditingChanged: { editing in
                    if !editing {
                        // Apply temperature shift on release
                        applyTemperatureShift()
                        applyColorToDevice()
                    }
                })
                .accentColor(.orange)
            }
            
            // Brightness Slider
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "sun.max")
                        .foregroundColor(.yellow)
                    Text("Brightness")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(brightness * 100))%")
                        .foregroundColor(.white.opacity(0.8))
                }
                .font(.caption)
                
                Slider(value: $brightness, in: 0...1, step: 0.01, onEditingChanged: { editing in
                    if !editing {
                        // Apply brightness on release
                        updateColor()
                        applyColorToDevice()
                    }
                })
                .accentColor(.yellow)
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
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark.fill")
                            Text("Save")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.blue)
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
    
    private func updateColor() {
        selectedColor = Color(hue: hue, saturation: saturation, brightness: brightness)
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
        // Will be updated when GeometryReader provides size
        pickerPosition = CGPoint(x: hue * 200, y: (1.0 - saturation) * 200)
    }
    
    private func applyTemperatureShift() {
        // Apply color temperature shift to current color
        // Temperature range: 2000K (warm) to 9000K (cool)
        let normalizedTemp = (temperature - 2000) / 7000 // 0 = warm, 1 = cool
        
        // Extract RGB from current color
        let uiColor = UIColor(selectedColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Apply temperature shift (simplified algorithm)
        // Warm (low K): increase red, decrease blue
        // Cool (high K): decrease red, increase blue
        let tempShift = (normalizedTemp - 0.5) * 0.3
        let newR = max(0, min(1, r - tempShift))
        let newB = max(0, min(1, b + tempShift))
        
        selectedColor = Color(red: newR, green: g, blue: newB)
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
}

