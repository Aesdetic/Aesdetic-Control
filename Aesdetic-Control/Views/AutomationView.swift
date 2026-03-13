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
    private var glassSurface: GlassSurfaceStyle { GlassTheme.surfaces(for: colorScheme) }
    private var glassText: GlassTextStyle { GlassTheme.text(for: colorScheme) }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    presetsSection
                    automationsSection
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .refreshable {
                await viewModel.refreshAutomations()
            }
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
                    .foregroundColor(glassText.pagePrimaryText)
                Text("Schedule sunrise lamps, bedtime fades, and more.")
                    .font(.subheadline)
                    .foregroundColor(glassText.pageSecondaryText)
            }
            Spacer()
            Button(action: { beginCreateAutomation() }) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(glassText.pagePrimaryText)
                    .padding()
                    .background(glassSurface.pillFillSelected)
                    .clipShape(Circle())
                    .shadow(
                        color: glassSurface.controlShadowAmbient.color,
                        radius: glassSurface.controlShadowAmbient.radius,
                        x: glassSurface.controlShadowAmbient.x,
                        y: glassSurface.controlShadowAmbient.y
                    )
                    .shadow(
                        color: glassSurface.controlShadowKey.color,
                        radius: glassSurface.controlShadowKey.radius,
                        x: glassSurface.controlShadowKey.x,
                        y: glassSurface.controlShadowKey.y
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Starters")
                .font(.title3.weight(.semibold))
                .foregroundColor(glassText.pagePrimaryText)
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
            GlassCardBackground(
                cornerRadius: 20,
                fill: glassSurface.cardFillInactive,
                outerStroke: glassSurface.cardStrokeOuter,
                innerStroke: glassSurface.cardStrokeInner,
                keyShadow: glassSurface.cardShadowKey,
                ambientShadow: glassSurface.cardShadowAmbient
            )
        )
    }
    
    private var automationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Automations")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(glassText.pagePrimaryText)
                Spacer()
                Button(action: { beginCreateAutomation() }) {
                    Label("Create", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(glassSurface.pillFillSelected)
                        .foregroundColor(glassText.pagePrimaryText)
                        .clipShape(Capsule())
                        .shadow(
                            color: glassSurface.controlShadowAmbient.color,
                            radius: glassSurface.controlShadowAmbient.radius,
                            x: glassSurface.controlShadowAmbient.x,
                            y: glassSurface.controlShadowAmbient.y
                        )
                        .shadow(
                            color: glassSurface.controlShadowKey.color,
                            radius: glassSurface.controlShadowKey.radius,
                            x: glassSurface.controlShadowKey.x,
                            y: glassSurface.controlShadowKey.y
                        )
                }
                .buttonStyle(.plain)
            }
            
            let nextAutomationID = AutomationStore.shared.upcomingAutomationInfo?.automation.id
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
            GlassCardBackground(
                cornerRadius: 20,
                fill: glassSurface.cardFillInactive,
                outerStroke: glassSurface.cardStrokeOuter,
                innerStroke: glassSurface.cardStrokeInner,
                keyShadow: glassSurface.cardShadowKey,
                ambientShadow: glassSurface.cardShadowAmbient
            )
        )
    }
}

struct AutomationView_Previews: PreviewProvider {
    static var previews: some View {
        AutomationView()
    }
}

// MARK: - Helpers

private extension AutomationView {
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
