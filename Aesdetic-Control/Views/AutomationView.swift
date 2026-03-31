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
    @StateObject private var scenesStore = ScenesStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCreateAutomation = false
    @State private var builderDevice: WLEDDevice? = nil
    @State private var pendingTemplate: AutomationTemplate? = nil
    
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
                    presetsSection
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
        }) {
            AutomationCreationSheet(
                builderDevice: $builderDevice,
                pendingTemplate: $pendingTemplate,
                isPresented: $showingCreateAutomation
                )
        }
        .background(Color.clear)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Automations")
                    .font(.largeTitle.bold())
                    .foregroundColor(theme.textPrimary)
                Text("Schedule sunrise lamps, bedtime fades, and more.")
                    .font(.subheadline)
                    .foregroundColor(theme.textSecondary)
            }
            Spacer()
            AppGlassIconButton(systemName: "plus", action: { beginCreateAutomation() })
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

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Starters")
                .font(.title3.weight(.semibold))
                .foregroundColor(theme.textPrimary)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(AutomationTemplate.quickStartTemplates) { template in
                    QuickPresetCard(template: template) { tappedTemplate in
                        beginCreateAutomation(with: tappedTemplate)
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
                    .font(.title3.weight(.semibold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                AppGlassPillButton(
                    title: "Create",
                    isSelected: true,
                    iconName: "plus",
                    size: .compact,
                    action: { beginCreateAutomation() }
                )
            }
            
            if viewModel.automations.isEmpty {
                EmptyAutomationsView()
            } else {
                VStack(spacing: 14) {
                    ForEach(viewModel.automations) { automation in
                        let runStatus = activeAutomationRunStatus(for: automation)
                        AutomationRow(
                            automation: automation,
                            scenes: scenesStore.scenes,
                            isNext: nextAutomationID == automation.id,
                            isRunning: runStatus != nil,
                            runningProgress: runStatus?.progress,
                            subtitle: targetName(for: automation),
                            onToggle: { enabled in
                                var updated = automation
                                updated.enabled = enabled
                                AutomationStore.shared.update(updated)
                            },
                            onRun: {
                                AutomationStore.shared.applyAutomation(automation)
                            },
                            onShortcutToggle: { pinned in
                                var updated = automation
                                var metadata = updated.metadata
                                metadata.pinnedToShortcuts = pinned
                                updated.metadata = metadata
                                AutomationStore.shared.update(updated)
                            },
                            onRetrySync: {
                                AutomationStore.shared.retryOnDeviceSync(for: automation.id)
                            },
                            onDelete: {
                                AutomationStore.shared.delete(id: automation.id)
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

// MARK: - Helpers

private extension AutomationView {
    var nextAutomationID: UUID? {
        AutomationStore.shared.upcomingAutomationInfo?.automation.id
    }

    var nextAutomationValue: String {
        if let nextDate = AutomationStore.shared.upcomingAutomationInfo?.date {
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
        pendingTemplate = template
        if deviceViewModel.devices.count == 1 {
            builderDevice = deviceViewModel.devices.first
        } else {
            builderDevice = nil
        }
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
