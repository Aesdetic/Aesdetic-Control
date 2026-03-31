import SwiftUI

struct SaveTransitionPresetDialog: View {
    let device: WLEDDevice
    let currentGradientA: LEDGradient
    let currentGradientB: LEDGradient
    let currentBrightnessA: Int
    let currentBrightnessB: Int
    let currentDurationSec: Double
    let currentTemperatureA: Double?
    let currentWhiteLevelA: Double?
    let currentTemperatureB: Double?
    let currentWhiteLevelB: Double?
    let onSave: (TransitionPreset) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var presetName: String = ""
    
    init(device: WLEDDevice, currentGradientA: LEDGradient, currentGradientB: LEDGradient, currentBrightnessA: Int, currentBrightnessB: Int, currentDurationSec: Double, currentTemperatureA: Double? = nil, currentWhiteLevelA: Double? = nil, currentTemperatureB: Double? = nil, currentWhiteLevelB: Double? = nil, onSave: @escaping (TransitionPreset) -> Void) {
        self.device = device
        self.currentGradientA = currentGradientA
        self.currentGradientB = currentGradientB
        self.currentBrightnessA = currentBrightnessA
        self.currentBrightnessB = currentBrightnessB
        self.currentDurationSec = currentDurationSec
        self.currentTemperatureA = currentTemperatureA
        self.currentWhiteLevelA = currentWhiteLevelA
        self.currentTemperatureB = currentTemperatureB
        self.currentWhiteLevelB = currentWhiteLevelB
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Compact preview
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        GradientBar(
                            gradient: Binding(get: { currentGradientA }, set: { _ in }),
                            selectedStopId: .constant(nil),
                            onTapStop: { _ in },
                            onTapAnywhere: { _, _ in },
                            onStopsChanged: { _, _ in }
                        )
                        .frame(height: 28)
                        .disabled(true)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.blue.opacity(0.8))
                        
                        GradientBar(
                            gradient: Binding(get: { currentGradientB }, set: { _ in }),
                            selectedStopId: .constant(nil),
                            onTapStop: { _ in },
                            onTapAnywhere: { _, _ in },
                            onStopsChanged: { _, _ in }
                        )
                        .frame(height: 28)
                        .disabled(true)
                    }
                    
                    HStack(spacing: 16) {
                        Label(formatDuration(currentDurationSec), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Label("A: \(Int(round(Double(currentBrightnessA)/255.0*100)))%", systemImage: "sun.max")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Label("B: \(Int(round(Double(currentBrightnessB)/255.0*100)))%", systemImage: "sun.max")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
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
                    Text("Save Transition Preset")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            presetName = "Transition \(Date().presetNameTimestamp())"
            // Auto-focus text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        TransitionDurationPicker.clockString(seconds: seconds)
    }

    private func savePreset() {
        let preset = TransitionPreset(
            name: presetName,
            deviceId: device.id,
            gradientA: currentGradientA,
            brightnessA: currentBrightnessA,
            temperatureA: currentTemperatureA,
            whiteLevelA: currentWhiteLevelA,
            gradientB: currentGradientB,
            brightnessB: currentBrightnessB,
            temperatureB: currentTemperatureB,
            whiteLevelB: currentWhiteLevelB,
            durationSec: currentDurationSec
        )
        onSave(preset)
        dismiss()
    }
}
