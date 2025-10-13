import SwiftUI

struct SaveSceneDialog: View {
    let device: WLEDDevice
    let onSave: (Scene) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var sceneName: String = ""
    @State private var includeTransition: Bool = false
    @State private var includeEffects: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Save Scene")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                        
                        Text("Save current device state as a scene")
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Scene Name Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scene Name")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        TextField("Enter scene name", text: $sceneName)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    // Current State Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Current State")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("Brightness")
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(round(Double(device.brightness)/255.0*100)))%")
                                    .foregroundColor(.white)
                            }
                            
                            HStack {
                                Text("Power")
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text(device.isOn ? "On" : "Off")
                                    .foregroundColor(device.isOn ? .green : .red)
                            }
                            
                            HStack {
                                Text("Color")
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(device.currentColor)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button("Save Scene") {
                            saveScene()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(sceneName.isEmpty)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            sceneName = "Scene \(Date().formatted(date: .omitted, time: .shortened))"
        }
    }
    
    private func saveScene() {
        // Create a basic scene with current device state
        // For now, we'll create a simple static scene
        // In a full implementation, you'd capture the current gradient state from UnifiedColorPane
        let defaultStops = [
            GradientStop(position: 0.0, hexColor: device.currentColor.toHex()),
            GradientStop(position: 1.0, hexColor: device.currentColor.toHex())
        ]
        
        let scene = Scene(
            name: sceneName,
            deviceId: device.id,
            brightness: device.brightness,
            primaryStops: defaultStops,
            transitionEnabled: includeTransition,
            secondaryStops: includeTransition ? defaultStops : nil,
            durationSec: includeTransition ? 10.0 : nil,
            aBrightness: device.brightness,
            bBrightness: includeTransition ? device.brightness : nil,
            effectsEnabled: includeEffects
        )
        
        onSave(scene)
        dismiss()
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
