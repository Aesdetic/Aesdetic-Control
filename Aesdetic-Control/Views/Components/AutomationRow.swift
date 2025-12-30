import SwiftUI

struct AutomationRow: View {
    let automation: Automation
    let scenes: [Scene]
    let isNext: Bool
    var subtitle: String? = nil
    let onToggle: (Bool) -> Void
    var onRun: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onShortcutToggle: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    private var accentColor: Color {
        if let accent = automation.metadata.accentColorHex ?? automation.metadata.colorPreviewHex,
           !accent.isEmpty {
            return Color(hex: accent)
        }
        return Color.white
    }
    
    private var devicesLabel: String? {
        let count = automation.targets.deviceIds.count
        return count > 1 ? "Syncs \(count) devices" : nil
    }
    
    private var shortcutPinned: Bool {
        automation.metadata.pinnedToShortcuts ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            metadataRow
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isNext ? Color.orange.opacity(0.18) : Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(isNext ? Color.orange.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            onEdit?()
        }
        .accessibilityLabel("\(automation.name) automation")
        .accessibilityValue(automation.enabled ? "Enabled" : "Disabled")
        .accessibilityHint(automation.enabled ? "Double tap to disable this automation." : "Double tap to enable this automation.")
    }
    
    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Text(actionDescription)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                shortcutControls
                executionControls
            }
        }
    }
    
    private var metadataRow: some View {
        HStack(spacing: 10) {
            triggerRow
            if let devicesLabel {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Text(devicesLabel)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 10)
                    )
            }
            Spacer()
            if let nextTriggerDescription {
                Text(nextTriggerDescription)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    @ViewBuilder
    private var iconBadge: some View {
        if let iconName = automation.metadata.iconName {
            Image(systemName: iconName)
                .font(.body.weight(.semibold))
                .foregroundColor(accentColor.opacity(0.9))
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(automation.name)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            if isNext {
                Text("Next")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }
        }
    }
    
    private var shortcutControls: some View {
        HStack(spacing: 8) {
            if let onShortcutToggle {
                Button {
                    onShortcutToggle(!shortcutPinned)
                } label: {
                    Image(systemName: shortcutPinned ? "heart.fill" : "heart")
                        .foregroundColor(shortcutPinned ? .orange : .white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shortcutPinned ? "Remove from shortcuts" : "Add to shortcuts")
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var executionControls: some View {
        HStack(spacing: 8) {
            if let onRun {
                Button(action: onRun) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.black)
                        .padding(10)
                        .background(accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Run \(automation.name)")
            }
            Toggle("", isOn: Binding(
                get: { automation.enabled },
                set: { onToggle($0) }
            ))
            .tint(accentColor)
            .labelsHidden()
        }
    }
    
    private var triggerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption.weight(.medium))
                .foregroundColor(accentColor)
            
            Text(automation.trigger.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.85))
        }
    }
    
    @ViewBuilder
    private var actionRow: some View {
        switch automation.action {
        case .scene(let payload):
            let sceneName = payload.sceneName ?? scenes.first(where: { $0.id == payload.sceneId })?.name ?? "Scene"
            actionLabel(icon: "paintbrush", text: "→ \(sceneName)")
        case .preset(let payload):
            actionLabel(icon: "list.bullet.rectangle", text: "Preset \(payload.presetId)")
        case .playlist(let payload):
            actionLabel(icon: "list.bullet.rectangle", text: payload.playlistName ?? "Playlist \(payload.playlistId)")
        case .gradient:
            actionLabel(icon: "rainbow", text: "Color routine")
        case .transition(let payload):
            let title = payload.presetName ?? "Transition"
            actionLabel(icon: "sunrise.fill", text: title)
        case .effect(let payload):
            actionLabel(icon: "sparkles", text: payload.effectName ?? "Effect \(payload.effectId)")
        case .directState:
            actionLabel(icon: "lightbulb", text: "Custom color")
        }
    }
    
    @ViewBuilder
    private func actionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.medium))
                .foregroundColor(accentColor)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var actionDescription: String {
        switch automation.action {
        case .scene(let payload):
            let sceneName = payload.sceneName ?? scenes.first(where: { $0.id == payload.sceneId })?.name ?? "Scene"
            return "Scene · \(sceneName)"
        case .preset(let payload):
            return "Preset #\(payload.presetId)"
        case .playlist(let payload):
            return "Playlist #\(payload.playlistId)"
        case .gradient:
            return "Color · \(automation.summary)"
        case .transition:
            return "Transition · \(automation.summary)"
        case .effect(let payload):
            return "Animation · \(payload.effectName ?? "Effect")"
        case .directState:
            return "Custom state"
        }
    }
    
    private var nextTriggerDescription: String? {
        if let next = automation.nextTriggerDate() {
            return "Next at \(next.formatted(date: .omitted, time: .shortened))"
        }
        switch automation.trigger {
        case .sunrise, .sunset:
            return automation.trigger.displayName
        default:
            return nil
        }
    }
}
