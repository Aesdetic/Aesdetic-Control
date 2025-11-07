import SwiftUI

struct SaveEffectPresetDialog: View {
    let device: WLEDDevice
    let currentEffectId: Int
    let currentSpeed: Int?
    let currentIntensity: Int?
    let currentPaletteId: Int?
    let currentBrightness: Int
    let onSave: (WLEDEffectPreset) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var presetName: String = ""
    
    init(device: WLEDDevice, currentEffectId: Int, currentSpeed: Int?, currentIntensity: Int?, currentPaletteId: Int?, currentBrightness: Int, onSave: @escaping (WLEDEffectPreset) -> Void) {
        self.device = device
        self.currentEffectId = currentEffectId
        self.currentSpeed = currentSpeed
        self.currentIntensity = currentIntensity
        self.currentPaletteId = currentPaletteId
        self.currentBrightness = currentBrightness
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Compact preview
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundColor(.yellow)
                        .frame(width: 40, height: 40)
                        .background(Color.yellow.opacity(0.15))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Effect \(currentEffectId)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 12) {
                            if let speed = currentSpeed {
                                Label("\(speed)", systemImage: "speedometer")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            if let intensity = currentIntensity {
                                Label("\(intensity)", systemImage: "slider.horizontal.3")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Label("\(Int(round(Double(currentBrightness)/255.0*100)))%", systemImage: "sun.max")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    Spacer()
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
                    Text("Save Effect Preset")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            presetName = "Effect Preset \(Date().formatted(date: .omitted, time: .shortened))"
            // Auto-focus text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func savePreset() {
        let preset = WLEDEffectPreset(
            name: presetName,
            deviceId: device.id,
            effectId: currentEffectId,
            speed: currentSpeed,
            intensity: currentIntensity,
            paletteId: currentPaletteId,
            brightness: currentBrightness
        )
        onSave(preset)
        dismiss()
    }
}
