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
    @State private var showingCreateAutomation = false
    @State private var builderDevice: WLEDDevice? = nil
    @State private var pendingTemplate: AutomationTemplate? = nil
    
    // Animation constants (matching design system)
    private let standardAnimation: Animation = .easeInOut(duration: 0.25)
    private let fastAnimation: Animation = .easeInOut(duration: 0.15)
    
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    presetsSection
                    automationsSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 80)
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
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func headerSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automation")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Automations")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("Schedule sunrise lamps, bedtime fades, and more.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
            }
            Spacer()
            Button(action: { beginCreateAutomation() }) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.black)
                    .padding()
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Starters")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private var automationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Automations")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { beginCreateAutomation() }) {
                    Label("Create", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            let nextAutomationID = AutomationStore.shared.upcomingAutomationInfo?.automation.id
            if viewModel.automations.isEmpty {
                EmptyAutomationsView()
            } else {
                VStack(spacing: 14) {
                    ForEach(viewModel.automations) { automation in
                        AutomationRow(
                            automation: automation,
                            scenes: scenesStore.scenes,
                            isNext: nextAutomationID == automation.id,
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

#Preview {
    AutomationView()
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
}