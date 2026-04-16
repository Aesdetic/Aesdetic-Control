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
    @ObservedObject private var automationStore = AutomationStore.shared
    @FocusState private var isTextFieldFocused: Bool
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false
    
    @State private var presetName: String = ""
    @State private var includeBrightness: Bool = true
    @State private var saveSegmentBounds: Bool = true
    @State private var selectedSegmentsOnly: Bool = false
    @State private var quickLoadTag: String = ""
    @State private var applyAtBoot: Bool = false
    @State private var customAPICommand: String = ""
    
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
                        .font(AppTypography.style(.title3))
                        .foregroundColor(.yellow)
                        .frame(width: 40, height: 40)
                        .background(Color.yellow.opacity(0.15))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Effect \(currentEffectId)")
                            .font(AppTypography.style(.subheadline, weight: .medium))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 12) {
                            if let speed = currentSpeed {
                                Label("\(speed)", systemImage: "speedometer")
                                    .font(AppTypography.style(.caption))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            if let intensity = currentIntensity {
                                Label("\(intensity)", systemImage: "slider.horizontal.3")
                                    .font(AppTypography.style(.caption))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Label("\(Int(round(Double(currentBrightness)/255.0*100)))%", systemImage: "sun.max")
                                .font(AppTypography.style(.caption))
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
                        .font(AppTypography.style(.subheadline, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextField("Enter preset name", text: $presetName)
                        .textFieldStyle(.plain)
                        .font(AppTypography.style(.body))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !presetName.isEmpty && !automationStore.hasAnyDeletionInProgress {
                                savePreset()
                            }
                        }
                }
                .padding(.horizontal, 16)
                
                if advancedUIEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save Options")
                            .font(AppTypography.style(.subheadline, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Toggle("Include brightness", isOn: $includeBrightness)
                            .tint(.blue)
                        Toggle("Save segment bounds", isOn: $saveSegmentBounds)
                            .tint(.blue)
                        Toggle("Selected segments only", isOn: $selectedSegmentsOnly)
                            .tint(.blue)
                        Toggle("Apply at boot", isOn: $applyAtBoot)
                            .tint(.blue)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quick Load Tag (optional)")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(.white.opacity(0.7))
                            TextField("Example: 1", text: $quickLoadTag)
                                .textFieldStyle(.plain)
                                .font(AppTypography.style(.body))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom API Command (optional)")
                                .font(AppTypography.style(.caption))
                                .foregroundColor(.white.opacity(0.7))
                            Text("JSON object or HTTP API string. If set, this is saved instead of current effect state.")
                                .font(AppTypography.style(.caption2))
                                .foregroundColor(.white.opacity(0.55))
                            TextEditor(text: $customAPICommand)
                                .font(AppTypography.text(size: 13, weight: .regular, relativeTo: .footnote))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 84)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .padding(.top, 4)
                    }
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 16)
                }
                
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
                    .disabled(presetName.isEmpty || automationStore.hasAnyDeletionInProgress)
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
                        .font(AppTypography.style(.headline))
                        .foregroundColor(.white)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            presetName = "Effect Preset \(Date().presetNameTimestamp())"
            // Auto-focus text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func savePreset() {
        guard !automationStore.hasAnyDeletionInProgress else { return }
        let sanitizedQuickLoad = quickLoadTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quickLoadValue = sanitizedQuickLoad.isEmpty
            ? nil
            : String(sanitizedQuickLoad.prefix(8))
        let preset = WLEDEffectPreset(
            name: presetName,
            deviceId: device.id,
            effectId: currentEffectId,
            speed: currentSpeed,
            intensity: currentIntensity,
            paletteId: currentPaletteId,
            brightness: currentBrightness,
            includeBrightness: includeBrightness,
            saveSegmentBounds: saveSegmentBounds,
            selectedSegmentsOnly: selectedSegmentsOnly,
            quickLoadTag: quickLoadValue,
            applyAtBoot: applyAtBoot,
            customAPICommand: customAPICommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : customAPICommand.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(preset)
        dismiss()
    }
}
