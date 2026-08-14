//
//  ContentView.swift
//  Aesdetic-Control
//
//  Created by Ryan Tam on 6/26/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: DockTab = .dashboard
    @StateObject private var deviceControlViewModel = DeviceControlViewModel.shared
    @StateObject private var setupJourneyCoordinator = SetupJourneyCoordinator()
    @State private var setupJourneyActions = SetupJourneyActions()
    @State private var setupDeviceFrames: [String: CGRect] = [:]
    @State private var isDeviceDetailPresented = false
    private var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var isRunningUITests: Bool {
        AppRuntimeEnvironment.isRunningUITests
    }

    var body: some View {
        liveAppBody
    }

    private var liveAppBody: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                DashboardView(
                    activeTab: selectedTab,
                    onOpenDevices: { selectedTab = .devices },
                    onDetailPresentationChange: { isDeviceDetailPresented = $0 }
                )
                    .tag(DockTab.dashboard)
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2")
                    }

                DeviceControlView(
                    onAddDevice: setupJourneyCoordinator.beginAddDevice,
                    onReconnectDevice: setupJourneyCoordinator.beginReconnect,
                    onBeginProductSetup: { device, ssid in
                        setupJourneyCoordinator.beginProductSetup(device: device, provisionedSSID: ssid)
                    },
                    onDetailPresentationChange: { isDeviceDetailPresented = $0 }
                )
                    .tag(DockTab.devices)
                    .tabItem {
                        Label("Devices", systemImage: "lightbulb.2")
                    }

                AutomationView()
                    .tag(DockTab.automation)
                    .tabItem {
                        Label("Automation", systemImage: "clock.arrow.2.circlepath")
                    }

                WellnessView()
                    .tag(DockTab.wellness)
                    .tabItem {
                        Label("Wellness", systemImage: "heart.text.square")
                    }
            }
            .background(Color.clear)
            .tint(.primary)

            if setupJourneyCoordinator.isActive {
                SetupJourneyView(
                    coordinator: setupJourneyCoordinator,
                    viewModel: deviceControlViewModel,
                    deviceTargetFrames: setupDeviceFrames,
                    onRevealDevice: { _ in
                        selectedTab = .devices
                    }
                )
                .zIndex(10)
            }
        }
        .onPreferenceChange(SetupJourneyDeviceFramePreferenceKey.self) { frames in
            guard frames != setupDeviceFrames else { return }
            setupDeviceFrames = frames
        }
        .onChange(of: setupJourneyCoordinator.isProvisioningActive, initial: true) { _, isActive in
            deviceControlViewModel.setProvisioningNetworkTransitionActive(isActive)
        }
        .environment(\.setupJourneyActions, setupJourneyActions)
        .environment(\.setupJourneyTargetDeviceID, setupJourneyTargetDeviceID)
        .background {
            TabBarVisibilityController(
                isHidden: shouldHideTabBar,
                animated: shouldAnimateTabBarVisibility
            )
        }
        .onAppear {
            setupJourneyActions.beginProductSetup = { [weak setupJourneyCoordinator] device, ssid in
                setupJourneyCoordinator?.beginProductSetup(device: device, provisionedSSID: ssid)
            }
            if !isRunningForPreviews && !isRunningUITests {
                // Passive discovery at launch (UDP/mDNS only)
                DeviceControlViewModel.shared.startPassiveDiscovery()
                Task { @MainActor in
                    await Task.yield()
                    setupJourneyCoordinator.presentFirstLaunchIfNeeded(
                        hasPersistedDevices: !deviceControlViewModel.devices.isEmpty
                    )
                }
            }
        }
    }

    private var setupJourneyTargetDeviceID: String? {
        guard case .success(let completion) = setupJourneyCoordinator.stage else { return nil }
        return completion.canonicalDeviceID
    }

    private var shouldHideTabBar: Bool {
        isSetupFlowActive ||
            isDeviceDetailPresented
    }

    private var shouldAnimateTabBarVisibility: Bool {
        !isSetupFlowActive
    }

    private var isSetupFlowActive: Bool {
        setupJourneyCoordinator.isActive || deviceControlViewModel.isMandatorySetupFlowActive
    }
}

struct ContentView_Previews: PreviewProvider {
    @MainActor
    private static let deviceControlViewModel = DeviceControlViewModel.shared
    @MainActor
    private static let automationViewModel = AutomationViewModel.shared
    @MainActor
    private static let dashboardViewModel = DashboardViewModel.shared
    @MainActor
    private static let wellnessViewModel = WellnessViewModel()

    static var previews: some View {
        ContentView()
            .environmentObject(deviceControlViewModel)
            .environmentObject(automationViewModel)
            .environmentObject(dashboardViewModel)
            .environmentObject(wellnessViewModel)
            .environment(\.managedObjectContext, CoreDataManager.shared.viewContext)
    }
}
