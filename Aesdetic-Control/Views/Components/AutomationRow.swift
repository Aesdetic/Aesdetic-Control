import SwiftUI

struct AutomationRow: View {
    let automation: Automation
    let scenes: [Scene]
    let isNext: Bool
    var isDeleting: Bool = false
    var isRunning: Bool = false
    var runningProgress: Double? = nil
    var subtitle: String? = nil
    let onToggle: (Bool) -> Void
    var onRun: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onShortcutToggle: ((Bool) -> Void)? = nil
    var onRetrySync: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var solarTriggerDate: Date?
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var cardStyle: AppCardStyle {
        AppCardStyles.glass(
            for: colorScheme,
            tone: automation.enabled ? .active : .inactive,
            cornerRadius: cardCornerRadius
        )
    }
    private let cardCornerRadius: CGFloat = 20
    private var isInteractionLockedDuringSync: Bool {
        guard automation.metadata.runOnDevice else { return false }
        let deviceIds = automation.targets.deviceIds
        guard !deviceIds.isEmpty else { return false }
        return deviceIds.contains { automation.metadata.syncState(for: $0) == .syncing }
    }

    private var isInteractionLocked: Bool {
        isDeleting || isInteractionLockedDuringSync
    }
    
    private var accentColor: Color {
        if let accent = automation.metadata.accentColorHex ?? automation.metadata.colorPreviewHex,
           !accent.isEmpty {
            return Color(hex: accent)
        }
        return theme.textPrimary
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
            AppCardBackground(style: cardStyle)
        )
        .blur(radius: isInteractionLocked ? 3 : 0)
        .overlay {
            if isInteractionLocked {
                loadingOverlay
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .allowsHitTesting(!isInteractionLocked)
        .animation(.easeInOut(duration: 0.2), value: isInteractionLocked)
        .onTapGesture {
            guard !isInteractionLocked else { return }
            onEdit?()
        }
        .onAppear {
            loadSolarTriggerDate()
        }
        .onChange(of: automation.trigger) { _, _ in
            loadSolarTriggerDate()
        }
        .accessibilityLabel("\(automation.name) automation")
        .accessibilityValue(automation.enabled ? "Enabled" : "Disabled")
        .accessibilityHint(
            isDeleting
                ? "Automation is being deleted from device. Keep app open until it completes."
                : (isInteractionLockedDuringSync
                    ? "Automation is getting ready. Controls are temporarily locked."
                : (automation.enabled ? "Double tap to disable this automation." : "Double tap to enable this automation.")
                  )
        )
    }

    private var loadingOverlay: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(theme.surface.opacity(colorScheme == .dark ? 0.58 : 0.74))
            .overlay(
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.textPrimary)
                    Text(isDeleting ? "Deleting on device..." : "Getting ready...")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(theme.textPrimary)
                    if isDeleting {
                        Text("Keep app open")
                            .font(.caption2)
                            .foregroundColor(theme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
            )
    }
    
    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
                Text(actionDescription)
                    .font(.subheadline)
                    .foregroundColor(theme.textSecondary)
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
                    .fill(theme.surfaceMuted)
                    .overlay(
                        Text(devicesLabel)
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 10)
                    )
            }
            if isRunning {
                Capsule()
                    .fill(theme.surfaceMuted)
                    .overlay(
                        Text(runningChipText)
                            .font(.caption)
                            .foregroundColor(theme.status.positive)
                            .padding(.horizontal, 10)
                    )
            }
            if let deviceTimerStatus {
                Capsule()
                    .fill(theme.surfaceMuted)
                    .overlay(
                        Text(deviceTimerStatus.text)
                            .font(.caption)
                            .foregroundColor(deviceTimerStatus.color)
                            .padding(.horizontal, 10)
                    )
            }
            if let onRetrySync,
               let deviceTimerStatus,
               deviceTimerStatus.retryable {
                Button("Retry") {
                    onRetrySync()
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.status.warning)
                .buttonStyle(.plain)
            }
            TimelineView(.periodic(from: .now, by: 20)) { context in
                if let triggerText = recentOnDeviceTriggerText(referenceDate: context.date) {
                    Capsule()
                        .fill(theme.surfaceMuted)
                        .overlay(
                            Text(triggerText)
                                .font(.caption)
                                .foregroundColor(theme.status.info)
                                .padding(.horizontal, 10)
                        )
                }
            }
            Spacer()
            if let nextTriggerDescription {
                Text(nextTriggerDescription)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
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
                .background(theme.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(automation.name)
                .font(.headline.weight(.semibold))
                .foregroundColor(theme.textPrimary)
            if isNext {
                Text("Next")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.status.warning.opacity(0.18))
                    .foregroundColor(theme.status.warning)
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
                        .foregroundColor(shortcutPinned ? theme.status.warning : theme.textSecondary)
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
                AppGlassIconButton(systemName: "play.fill", size: 40, action: onRun)
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
                .foregroundColor(theme.textPrimary)
        }
    }

    private var deviceTimerStatus: (text: String, color: Color, retryable: Bool)? {
        guard automation.metadata.runOnDevice else { return nil }
        let deviceIds = automation.targets.deviceIds
        if deviceIds.isEmpty {
            return ("Not ready", .orange, true)
        }
        let states = deviceIds.map { automation.metadata.syncState(for: $0) }
        let syncedCount = states.filter { $0 == .synced }.count
        if syncedCount == deviceIds.count {
            return ("Ready", theme.status.positive, false)
        }
        if states.contains(.syncing) {
            return ("Getting ready", theme.textSecondary, false)
        }
        if states.contains(.notSynced) {
            if syncedCount > 0 {
                return ("Partially ready", theme.status.warning, true)
            }
            return ("Not ready", theme.status.warning, true)
        }
        return ("Not ready", theme.status.warning, true)
    }

    private var runningChipText: String {
        guard let runningProgress, runningProgress > 0 else {
            return "Running"
        }
        let percent = max(0, min(100, Int((runningProgress * 100.0).rounded())))
        return "Running \(percent)%"
    }

    private func recentOnDeviceTriggerText(referenceDate: Date) -> String? {
        guard automation.metadata.runOnDevice else { return nil }
        guard let lastTriggered = automation.lastTriggered else { return nil }
        let elapsed = referenceDate.timeIntervalSince(lastTriggered)
        guard elapsed >= 0 && elapsed <= 180 else { return nil }
        if elapsed < 60 {
            return "Triggered now"
        }
        let minutes = max(1, Int((elapsed / 60.0).rounded()))
        return "Triggered \(minutes)m ago"
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
        case .gradient(let payload):
            actionLabel(icon: payload.powerOn ? "rainbow" : "power", text: payload.powerOn ? "Color routine" : "Power off")
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
                .foregroundColor(theme.textSecondary)
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
        case .gradient(let payload):
            return payload.powerOn ? "Color · \(automation.summary)" : "Power · Off"
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
        if let solarTriggerDate {
            return "Next at \(solarTriggerDate.formatted(date: .omitted, time: .shortened))"
        }
        switch automation.trigger {
        case .sunrise, .sunset:
            return automation.trigger.displayName
        default:
            return nil
        }
    }

    private func loadSolarTriggerDate() {
        solarTriggerDate = nil
        switch automation.trigger {
        case .sunrise, .sunset:
            Task {
                let resolved = await AutomationStore.shared.nextTriggerDate(for: automation)
                await MainActor.run {
                    solarTriggerDate = resolved
                }
            }
        default:
            break
        }
    }
}
