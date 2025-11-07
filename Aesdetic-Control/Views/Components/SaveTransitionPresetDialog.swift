import SwiftUI

struct SaveTransitionPresetDialog: View {
    let device: WLEDDevice
    let currentGradientA: LEDGradient
    let currentGradientB: LEDGradient
    let currentBrightnessA: Int
    let currentBrightnessB: Int
    let currentDurationSec: Double
    let onSave: (TransitionPreset) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var presetName: String = ""
    
    init(device: WLEDDevice, currentGradientA: LEDGradient, currentGradientB: LEDGradient, currentBrightnessA: Int, currentBrightnessB: Int, currentDurationSec: Double, onSave: @escaping (TransitionPreset) -> Void) {
        self.device = device
        self.currentGradientA = currentGradientA
        self.currentGradientB = currentGradientB
        self.currentBrightnessA = currentBrightnessA
        self.currentBrightnessB = currentBrightnessB
        self.currentDurationSec = currentDurationSec
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
                        Label("\(Int(currentDurationSec))s", systemImage: "clock")
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
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            presetName = "Transition \(Date().formatted(date: .omitted, time: .shortened))"
            // Auto-focus text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func savePreset() {
        let preset = TransitionPreset(
            name: presetName,
            deviceId: device.id,
            gradientA: currentGradientA,
            brightnessA: currentBrightnessA,
            gradientB: currentGradientB,
            brightnessB: currentBrightnessB,
            durationSec: currentDurationSec
        )
        onSave(preset)
        dismiss()
    }
}
