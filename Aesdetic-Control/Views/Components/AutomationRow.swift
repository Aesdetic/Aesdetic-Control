import SwiftUI

struct AutomationRow: View {
    let automation: Automation
    let scenes: [Scene]
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Automation Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(automation.enabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: automation.enabled ? "clock.fill" : "clock")
                    .font(.title3)
                    .foregroundColor(automation.enabled ? .green : .gray)
            }
            
            // Automation Info
            VStack(alignment: .leading, spacing: 4) {
                Text(automation.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Time and Days
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Text(automation.time)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(automation.weekdaysString)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Scene
                    if let scene = scenes.first(where: { $0.id == automation.sceneId }) {
                        HStack(spacing: 8) {
                            Image(systemName: "paintbrush")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            
                            Text("→ \(scene.name)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Next Trigger
                    if let nextTrigger = automation.nextTriggerDate {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Text("Next: \(nextTrigger.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Enable Toggle
            Toggle("", isOn: Binding(
                get: { automation.enabled },
                set: { onToggle($0) }
            ))
            .tint(.green)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}
