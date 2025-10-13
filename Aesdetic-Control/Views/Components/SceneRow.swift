import SwiftUI

struct SceneRow: View {
    let scene: Scene
    let onApply: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Scene Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                if scene.transitionEnabled {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundColor(.blue)
                } else if scene.effectsEnabled {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundColor(.yellow)
                } else {
                    Image(systemName: "paintbrush")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // Scene Info
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    // Brightness
                    Label("\(Int(round(Double(scene.brightness)/255.0*100)))%", systemImage: "sun.max")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Scene Type
                    Text(sceneTypeText)
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    // Created Date
                    Text(createdDateText)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Apply Button
            Button("Apply") {
                onApply()
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue)
            .cornerRadius(8)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var sceneTypeText: String {
        if scene.effectsEnabled {
            return "Effects"
        } else if scene.transitionEnabled {
            return "Transition"
        } else {
            return "Static"
        }
    }
    
    private var createdDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: scene.createdAt)
    }
}
