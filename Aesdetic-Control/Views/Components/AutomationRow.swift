import SwiftUI

struct AutomationRow: View {
    let automation: Automation
    let scenes: [Scene]
    let isNext: Bool
    var isDeleting: Bool = false
    var isDeleteDisabled: Bool = false
    var deletionProgress: AutomationDeletionProgress? = nil
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
    private var isInteractionLocked: Bool {
        isDeleting
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
        ZStack(alignment: .bottomLeading) {
            HStack(alignment: .top, spacing: 12) {
                topContentColumn
                Spacer(minLength: 8)
                actionColumn
            }

            bottomContent
                .padding(.trailing, 54)
        }
        .padding(16)
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
        .accessibilityHint(isDeleting
            ? "Automation is being deleted. Keep app open until it completes."
            : "Double tap to edit this automation. Use the inline controls to run, save, delete, or toggle it."
        )
    }

    private var loadingOverlay: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(theme.surface.opacity(colorScheme == .dark ? 0.58 : 0.74))
            .overlay(
                VStack(spacing: 10) {
                    if isDeleting, let deletionProgress {
                        ProgressView(value: deletionProgress.fractionCompleted)
                            .progressViewStyle(.linear)
                            .tint(theme.textPrimary)
                        Text("Deleting on device... \(deletionProgress.completedSteps)/\(deletionProgress.totalSteps)")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        Text(deletionProgress.phaseDescription)
                            .font(AppTypography.style(.caption2))
                            .foregroundColor(theme.textSecondary)
                        Text("Keep app open")
                            .font(AppTypography.style(.caption2))
                            .foregroundColor(theme.textSecondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.textPrimary)
                        Text("Deleting...")
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        Text("Keep app open")
                            .font(AppTypography.style(.caption2))
                            .foregroundColor(theme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
            )
    }
    
    private var topContentColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            topStatusChips
            Text(automation.name)
                .font(AppTypography.style(.headline, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(actionDescription)
                .font(AppTypography.style(.caption, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.62))
            }
        }
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            colorPreviewStrip
            metadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var metadataRow: some View {
        HStack(spacing: 8) {
            triggerRow
            if let devicesLabel {
                neutralChip(devicesLabel)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var colorPreviewStrip: some View {
        let previews = actionColorPreviews
        if !previews.isEmpty {
            HStack(spacing: previews.count > 1 ? 4 : 0) {
                ForEach(Array(previews.enumerated()), id: \.offset) { _, gradient in
                    previewRail(for: gradient)
                }
            }
            .frame(maxWidth: previews.count > 1 ? 190 : 150)
            .accessibilityLabel("Automation color preview")
        }
    }
    
    @ViewBuilder
    private var iconBadge: some View {
        if let iconName = automation.metadata.iconName {
            Image(systemName: iconName)
                .font(AppTypography.style(.body, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .padding(10)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    @ViewBuilder
    private var topStatusChips: some View {
        HStack(spacing: 7) {
            if isNext {
                neutralChip("Next", prominent: true)
            }
            if isRunning {
                neutralChip(runningChipText, prominent: true)
            }
            if let deviceTimerStatus {
                neutralChip(deviceTimerStatus.text)
            }
            TimelineView(.periodic(from: .now, by: 20)) { context in
                if let triggerText = recentOnDeviceTriggerText(referenceDate: context.date) {
                    neutralChip(triggerText)
                }
            }
            if let onRetrySync,
               let deviceTimerStatus,
               deviceTimerStatus.retryable {
                Button("Retry") {
                    onRetrySync()
                }
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .buttonStyle(.plain)
            }
        }
    }

    private var actionColumn: some View {
        VStack(alignment: .trailing, spacing: 8) {
            powerToggleButton
            if let onShortcutToggle {
                neutralIconButton(
                    systemName: shortcutPinned ? "heart.fill" : "heart",
                    accessibilityLabel: shortcutPinned ? "Remove from shortcuts" : "Add to shortcuts"
                ) {
                    onShortcutToggle(!shortcutPinned)
                }
            }
            if let onRun {
                neutralIconButton(
                    systemName: "play",
                    accessibilityLabel: "Run \(automation.name)",
                    action: onRun
                )
            }
            if let onDelete {
                neutralIconButton(
                    systemName: "trash",
                    accessibilityLabel: isDeleteDisabled ? "Delete unavailable" : "Delete automation",
                    isDisabled: isDeleteDisabled,
                    action: onDelete
                )
            }
        }
    }

    private var powerToggleButton: some View {
        Button(action: {
            onToggle(!automation.enabled)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "power")
                    .font(AppTypography.style(.caption, weight: .semibold))
                Text(automation.enabled ? "On" : "Off")
                    .font(AppTypography.style(.caption, weight: .semibold))
            }
            .foregroundColor(.white.opacity(automation.enabled ? 0.96 : 0.62))
            .frame(minWidth: 70, minHeight: 38)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(automation.enabled ? 0.16 : 0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(automation.enabled ? "Disable \(automation.name)" : "Enable \(automation.name)")
    }

    private func neutralIconButton(
        systemName: String,
        accessibilityLabel: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white.opacity(isActive ? 0.95 : 0.76))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.16 : 0.10))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.20), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1.0)
        .accessibilityLabel(accessibilityLabel)
    }

    private func previewRail(for gradient: LEDGradient) -> some View {
        LinearGradient(
            gradient: Gradient(stops: gradient.stops.sorted { $0.position < $1.position }.map {
                .init(color: $0.color, location: $0.position)
            }),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 14)
        .frame(maxWidth: .infinity)
        .opacity(0.68)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func neutralChip(_ text: String, prominent: Bool = false) -> some View {
        Text(text)
            .font(AppTypography.style(.caption2, weight: .semibold))
            .foregroundColor(.white.opacity(prominent ? 0.94 : 0.76))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(prominent ? 0.16 : 0.10))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }
    
    private var triggerRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "clock")
                .font(AppTypography.style(.caption, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
            
            Text(compactTriggerDisplayName)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .layoutPriority(1)
        }
    }

    private var deviceTimerStatus: (text: String, color: Color, retryable: Bool)? {
        guard automation.enabled else { return nil }
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
            return ("Preparing", theme.textSecondary, false)
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
                .font(AppTypography.style(.caption, weight: .medium))
                .foregroundColor(accentColor)
            Text(text)
                .font(AppTypography.style(.caption))
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
            let summary = automation.summary
            if summary.localizedCaseInsensitiveCompare("Transition") == .orderedSame {
                return "Transition"
            }
            return "Transition · \(summary)"
        case .effect(let payload):
            return "Animation · \(payload.effectName ?? "Effect")"
        case .directState:
            return "Custom state"
        }
    }

    private var actionColorPreviews: [LEDGradient] {
        switch automation.action {
        case .gradient(let payload):
            return payload.powerOn ? [payload.gradient] : []
        case .transition(let payload):
            return [payload.startGradient, payload.endGradient]
        case .effect(let payload):
            if let gradient = payload.gradient {
                return [gradient]
            }
            if let hex = automation.metadata.colorPreviewHex, !hex.isEmpty {
                return [solidPreviewGradient(hex: hex)]
            }
            return []
        case .directState(let payload):
            return [solidPreviewGradient(hex: payload.colorHex)]
        case .scene, .preset, .playlist:
            if let hex = automation.metadata.colorPreviewHex, !hex.isEmpty {
                return [solidPreviewGradient(hex: hex)]
            }
            return []
        }
    }

    private func solidPreviewGradient(hex: String) -> LEDGradient {
        LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: hex),
            GradientStop(position: 1.0, hexColor: hex)
        ])
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

    private var compactTriggerDisplayName: String {
        switch automation.trigger {
        case .specificTime(let trigger):
            return compactTimeTriggerDisplay(trigger)
        case .sunrise(let solar):
            return solar.displayString(eventName: "Sunrise")
        case .sunset(let solar):
            return solar.displayString(eventName: "Sunset")
        }
    }

    private func compactTimeTriggerDisplay(_ trigger: TimeTrigger) -> String {
        let normalized = WeekdayMask.normalizeSunFirst(trigger.weekdays)
        let mondayFirstWeekdays: [(index: Int, label: String)] = [
            (1, "M"),
            (2, "Tu"),
            (3, "W"),
            (4, "Th"),
            (5, "F"),
            (6, "Sa"),
            (0, "Su")
        ]
        let selected = mondayFirstWeekdays.compactMap { weekday in
            normalized[weekday.index] ? weekday.label : nil
        }
        let daysText = selected.isEmpty ? "No days" : selected.joined(separator: " · ")
        return "\(trigger.time) · \(daysText)"
    }
}
