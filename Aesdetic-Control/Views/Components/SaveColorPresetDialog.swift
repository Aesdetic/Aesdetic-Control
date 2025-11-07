import SwiftUI

struct SaveColorPresetDialog: View {
    let device: WLEDDevice
    let currentGradient: LEDGradient
    let currentBrightness: Int
    let currentTemperature: Double?
    let onSave: (ColorPreset) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var presetName: String = ""
    
    init(device: WLEDDevice, currentGradient: LEDGradient, currentBrightness: Int, currentTemperature: Double?, onSave: @escaping (ColorPreset) -> Void) {
        self.device = device
        self.currentGradient = currentGradient
        self.currentBrightness = currentBrightness
        self.currentTemperature = currentTemperature
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Compact preview
                HStack(spacing: 12) {
                    GradientBar(
                        gradient: Binding(get: { currentGradient }, set: { _ in }),
                        selectedStopId: .constant(nil),
                        onTapStop: { _ in },
                        onTapAnywhere: { _, _ in },
                        onStopsChanged: { _, _ in }
                    )
                    .frame(height: 32)
                    .disabled(true)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(round(Double(currentBrightness)/255.0*100)))%")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        if let temp = currentTemperature {
                            Text("CCT \(Int(temp * 100))%")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
                
                // Preset Name Input (Primary Focus)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preset Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextField("Enter preset name", text: $presetName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !presetName.isEmpty {
                                savePreset()
                            }
                        }
                }
                .padding(.horizontal, 16)
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Save") {
                        savePreset()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(presetName.isEmpty)
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Save Color Preset")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            presetName = "Color Preset \(Date().formatted(date: .omitted, time: .shortened))"
            // Auto-focus text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func savePreset() {
        let preset = ColorPreset(
            name: presetName,
            gradientStops: currentGradient.stops,
            brightness: currentBrightness,
            temperature: currentTemperature
        )
        onSave(preset)
        dismiss()
    }
}
