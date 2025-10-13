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
                
                Button("Done") {
                    onColorChange(selectedColor)
                    onDismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.blue)
            }
            
            // Color Preview
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedColor)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
            
            // HSV Controls
            VStack(spacing: 12) {
                // Hue
                VStack(spacing: 4) {
                    HStack {
                        Text("Hue")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(Int(hue * 360))°")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Slider(value: $hue, in: 0...1)
                        .accentColor(.white)
                        .onChange(of: hue) { _, _ in updateColor() }
                }
                
                // Saturation
                VStack(spacing: 4) {
                    HStack {
                        Text("Saturation")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(Int(saturation * 100))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Slider(value: $saturation, in: 0...1)
                        .accentColor(.white)
                        .onChange(of: saturation) { _, _ in updateColor() }
                }
                
                // Brightness
                VStack(spacing: 4) {
                    HStack {
                        Text("Brightness")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(Int(brightness * 100))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Slider(value: $brightness, in: 0...1)
                        .accentColor(.white)
                        .onChange(of: brightness) { _, _ in updateColor() }
                }
            }
            
            // Quick Color Presets
            VStack(spacing: 8) {
                Text("Quick Colors")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(quickColors, id: \.self) { color in
                        Button(action: {
                            selectedColor = color
                            extractHSV(from: color)
                        }) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
            
            // Remove Button
            if canRemove {
                Button(action: {
                    onRemove()
                    onDismiss()
                }) {
                    Text("Remove Stop")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
        .onAppear {
            extractHSV(from: initialColor)
        }
    }
    
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
    
    private let quickColors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple,
        .pink, .cyan, .mint, .indigo, .brown, .gray,
        .white, .black, .primary, .secondary, .clear, Color(red: 0.5, green: 0.5, blue: 0.5)
    ]
}
