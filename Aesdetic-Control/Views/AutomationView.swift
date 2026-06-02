//
//  AutomationView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI

struct AutomationView: View {
    @ObservedObject private var viewModel = AutomationViewModel.shared
    @ObservedObject private var deviceViewModel = DeviceControlViewModel.shared
    @ObservedObject private var automationStore = AutomationStore.shared
    @StateObject private var scenesStore = ScenesStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCreateAutomation = false
    @State private var builderDevice: WLEDDevice? = nil
    @State private var pendingTemplate: AutomationTemplate? = nil
    @State private var editingAutomation: Automation? = nil
    @State private var automationPendingDelete: Automation? = nil
    
    // Animation constants (matching design system)
    private let standardAnimation: Animation = .easeInOut(duration: 0.25)
    private let fastAnimation: Animation = .easeInOut(duration: 0.15)
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var sectionCardStyle: AppCardStyle {
        AppCardStyles.glass(for: colorScheme, tone: .inactive, cornerRadius: 24)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    overviewSection
                    shortcutsSection
                    automationsSection
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .refreshable {
                await viewModel.refreshAutomations(force: true)
            }
        }
        .task {
            await viewModel.refreshAutomations()
        }
        .sheet(isPresented: $showingCreateAutomation, onDismiss: {
            builderDevice = nil
            pendingTemplate = nil
            editingAutomation = nil
        }) {
            AutomationCreationSheet(
                builderDevice: $builderDevice,
                pendingTemplate: $pendingTemplate,
                editingAutomation: $editingAutomation,
                isPresented: $showingCreateAutomation
            )
        }
        .alert(
            "Delete automation?",
            isPresented: Binding(
                get: { automationPendingDelete != nil },
                set: { if !$0 { automationPendingDelete = nil } }
            ),
            presenting: automationPendingDelete
        ) { automation in
            Button("Delete", role: .destructive) {
                automationStore.delete(id: automation.id)
                automationPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                automationPendingDelete = nil
            }
        } message: { automation in
            Text(deleteConfirmationMessage(for: automation))
        }
        .background(Color.clear)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Automations")
                    .font(AppTypography.style(.largeTitle, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text("Schedule sunrise lamps, bedtime fades, and more.")
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(theme.textSecondary)
            }
            Spacer()
            AppGlassIconButton(systemName: "plus", action: { beginCreateAutomation() })
                .disabled(automationStore.hasAnyDeletionInProgress)
                .opacity(automationStore.hasAnyDeletionInProgress ? 0.45 : 1.0)
        }
    }

    private var overviewSection: some View {
        AppOverviewCard(
            metrics: [
                AppOverviewMetric(value: "\(viewModel.automations.count)", label: "Saved\nAutomations"),
                AppOverviewMetric(value: "\(viewModel.automations.filter { $0.enabled }.count)", label: "Enabled\nNow"),
                AppOverviewMetric(value: nextAutomationValue, label: "Next\nRun")
            ]
        )
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts")
                    .font(AppTypography.style(.title3, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                if !shortcutAutomations.isEmpty {
                    Text("\(shortcutAutomations.count)")
                        .font(AppTypography.style(.caption2, weight: .semibold))
                        .foregroundColor(theme.textPrimary.opacity(0.78))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.surfaceMuted.opacity(0.30))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(theme.cardStrokeOuter.opacity(0.5), lineWidth: 1)
                                )
                        )
                }
                Spacer()
                Menu {
                    if shortcutMenuAutomations.isEmpty {
                        Text("No automations available")
                    } else {
                        ForEach(shortcutMenuAutomations, id: \.id) { automation in
                            Button(automation.name) {
                                toggleShortcutPin(automation: automation, pinned: true)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(theme.textPrimary.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(theme.surfaceMuted.opacity(0.3))
                                .overlay(
                                    Circle()
                                        .stroke(theme.cardStrokeOuter.opacity(0.55), lineWidth: 1)
                                )
                        )
                }
                .disabled(automationStore.hasAnyDeletionInProgress || shortcutMenuAutomations.isEmpty)
                .opacity((automationStore.hasAnyDeletionInProgress || shortcutMenuAutomations.isEmpty) ? 0.45 : 1.0)
                .accessibilityLabel("Add shortcut")
            }

            if shortcutAutomations.isEmpty {
                Text("Pin automations with the heart icon for quick access.")
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.surfaceMuted.opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(theme.cardStrokeOuter.opacity(0.4), lineWidth: 1)
                            )
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shortcutAutomations, id: \.id) { automation in
                            AutomationShortcutChip(
                                title: automation.name,
                                description: shortcutDescription(for: automation),
                                isEnabled: automation.enabled,
                                isNext: nextAutomationID == automation.id,
                                action: {
                                    var updated = automation
                                    updated.enabled.toggle()
                                    automationStore.update(updated)
                                }
                            )
                            .contextMenu {
                                Button((automation.metadata.pinnedToShortcuts ?? false) ? "Unfavorite" : "Favorite") {
                                    toggleShortcutPin(automation: automation, pinned: !(automation.metadata.pinnedToShortcuts ?? false))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            AppCardBackground(style: sectionCardStyle)
        )
        .clipShape(RoundedRectangle(cornerRadius: sectionCardStyle.cornerRadius, style: .continuous))
    }

    private var automationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Automations")
                    .font(AppTypography.style(.title3, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                createAutomationButton
                .disabled(automationStore.hasAnyDeletionInProgress)
                .opacity(automationStore.hasAnyDeletionInProgress ? 0.45 : 1.0)
            }
            
            if viewModel.automations.isEmpty {
                EmptyAutomationsView()
            } else {
                VStack(spacing: 14) {
                    ForEach(viewModel.automations, id: \.id) { (automation: Automation) in
                        let runStatus = activeAutomationRunStatus(for: automation)
                        let isDeleting = automationStore.isDeletionInProgress(for: automation.id)
                        AutomationRow(
                            automation: automation,
                            scenes: scenesStore.scenes,
                            isNext: nextAutomationID == automation.id,
                            isDeleting: isDeleting,
                            isDeleteDisabled: isDeleting,
                            deletionProgress: automationStore.deletionProgress(for: automation.id),
                            isRunning: runStatus != nil,
                            runningProgress: runStatus?.progress,
                            subtitle: targetName(for: automation),
                            onToggle: { enabled in
                                var updated = automation
                                updated.enabled = enabled
                                automationStore.update(updated)
                            },
                            onRun: {
                                automationStore.applyAutomation(automation)
                            },
                            onEdit: {
                                beginEditAutomation(automation)
                            },
                            onShortcutToggle: { pinned in
                                toggleShortcutPin(automation: automation, pinned: pinned)
                            },
                            onRetrySync: {
                                automationStore.retryOnDeviceSync(for: automation.id)
                            },
                            onDelete: {
                                automationPendingDelete = automation
                            }
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(
            AppCardBackground(style: sectionCardStyle)
        )
        .clipShape(RoundedRectangle(cornerRadius: sectionCardStyle.cornerRadius, style: .continuous))
    }
}

struct AutomationView_Previews: PreviewProvider {
    static var previews: some View {
        AutomationView()
    }
}

private struct AutomationShortcutChip: View {
    let title: String
    let description: String
    let isEnabled: Bool
    let isNext: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var chipFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(isEnabled ? 0.12 : 0.08)
            : Color.white.opacity(isEnabled ? 0.22 : 0.16)
    }

    private var chipStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.24)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(description)
                    .font(AppTypography.style(.caption2, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.trailing, isNext ? 40 : 0)
            }
            .frame(width: 168, height: 38, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(chipBackground)
            .overlay(alignment: .bottomTrailing) {
                if isNext {
                    nextBadge
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var chipBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isEnabled {
            shape
                .fill(Color.clear)
                .appLiquidGlass(role: .card, cornerRadius: 16)
        } else {
            shape
                .fill(chipFill)
                .overlay(
                    shape
                        .stroke(chipStroke, lineWidth: 1)
                )
        }
    }

    private var nextBadge: some View {
        Text("Next")
            .font(AppTypography.style(.caption2, weight: .medium))
            .foregroundColor(.white.opacity(0.94))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Helpers

private extension AutomationView {
    var shortcutAutomations: [Automation] {
        let pinned = viewModel.automations.filter { $0.metadata.pinnedToShortcuts ?? false }
        guard let nextId = nextAutomationID else { return pinned }
        return pinned.sorted { lhs, rhs in
            let lhsIsNext = lhs.id == nextId
            let rhsIsNext = rhs.id == nextId
            if lhsIsNext != rhsIsNext {
                return lhsIsNext
            }
            let lhsDate = lhs.lastTriggered ?? lhs.updatedAt
            let rhsDate = rhs.lastTriggered ?? rhs.updatedAt
            return lhsDate > rhsDate
        }
    }

    var shortcutMenuAutomations: [Automation] {
        viewModel.automations
            .filter { !($0.metadata.pinnedToShortcuts ?? false) }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func toggleShortcutPin(automation: Automation, pinned: Bool) {
        var updated = automation
        var metadata = updated.metadata
        metadata.pinnedToShortcuts = pinned
        updated.metadata = metadata
        automationStore.update(updated, syncOnDevice: false)
    }

    func shortcutDescription(for automation: Automation) -> String {
        switch automation.action {
        case .scene(let payload):
            let sceneName = payload.sceneName ?? scenesStore.scenes.first(where: { $0.id == payload.sceneId })?.name ?? "Scene"
            return "Scene · \(sceneName)"
        case .preset(let payload):
            return "Preset · #\(payload.presetId)"
        case .playlist(let payload):
            let playlistName = payload.playlistName ?? "Playlist #\(payload.playlistId)"
            return "Playlist · \(playlistName)"
        case .gradient(let payload):
            return payload.powerOn ? "Color · \(automation.summary)" : "Power · Off"
        case .transition:
            let summary = automation.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.lowercased().hasPrefix("transition") {
                return summary
            }
            return "Transition · \(summary)"
        case .effect(let payload):
            return "Animation · \(payload.effectName ?? "Effect \(payload.effectId)")"
        case .directState:
            return "Custom state"
        }
    }

    var createAutomationButton: some View {
        Button(action: { beginCreateAutomation() }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(AppTypography.style(.caption))
                Text("Create Automation")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create automation")
    }

    var nextAutomationID: UUID? {
        automationStore.upcomingAutomationInfo?.automation.id
    }

    var nextAutomationValue: String {
        if let nextDate = automationStore.upcomingAutomationInfo?.date {
            return nextDate.formatted(date: .omitted, time: .shortened)
        }
        if viewModel.automations.contains(where: { automation in
            switch automation.trigger {
            case .sunrise, .sunset:
                return automation.enabled
            default:
                return false
            }
        }) {
            return "Solar"
        }
        return "--"
    }

    func beginCreateAutomation(with template: AutomationTemplate? = nil) {
        guard !automationStore.hasAnyDeletionInProgress else { return }
        pendingTemplate = template
        editingAutomation = nil
        if deviceViewModel.devices.count == 1 {
            builderDevice = deviceViewModel.devices.first
        } else {
            builderDevice = nil
        }
        showingCreateAutomation = true
    }

    func beginEditAutomation(_ automation: Automation) {
        let targetIds = Set(automation.targets.deviceIds)
        guard !automationStore.hasAnyDeletionInProgress,
              !automationStore.hasOnDeviceSyncInProgress(for: targetIds) else { return }
        pendingTemplate = nil
        editingAutomation = automation
        builderDevice = deviceViewModel.devices.first(where: { targetIds.contains($0.id) })
            ?? deviceViewModel.devices.first
        showingCreateAutomation = true
    }
    
    func targetName(for automation: Automation) -> String? {
        let ids = automation.targets.deviceIds
        guard !ids.isEmpty else { return nil }
        if ids.count == 1,
           let device = deviceViewModel.devices.first(where: { $0.id == ids[0] }) {
            return device.name
        }
        return "\(ids.count) devices"
    }

    func deleteConfirmationMessage(for automation: Automation) -> String {
        let ids = automation.targets.deviceIds
        if ids.count <= 1 {
            return "Delete \"\(automation.name)\" from this device?"
        }
        return "Delete \"\(automation.name)\" from \(ids.count) devices?"
    }

    func activeAutomationRunStatus(for automation: Automation) -> ActiveRunStatus? {
        let targetIds = Set(automation.targets.deviceIds)
        guard !targetIds.isEmpty else { return nil }
        return deviceViewModel.activeRunStatus.values.first { status in
            guard targetIds.contains(status.deviceId), status.kind == .automation else { return false }
            if let statusAutomationId = status.automationId {
                return statusAutomationId == automation.id
            }
            return status.title == automation.name
        }
    }
}
