//
//  ContentView.swift
//  Aesdetic-Control
//
//  Created by Ryan Tam on 6/26/25.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: DockTab = .dashboard
    @StateObject private var deviceControlViewModel = DeviceControlViewModel.shared
    private let dockHorizontalPadding: CGFloat = 16
    private let dockTopInsetPadding: CGFloat = 0
    private let dockBottomInsetOffset: CGFloat = -8
    private var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        liveAppBody
    }

    private var liveAppBody: some View {
        TabView(selection: $selectedTab) {
            DashboardView(activeTab: selectedTab)
                .tag(DockTab.dashboard)
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }

            DeviceControlView()
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
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DockBar(selectedTab: $selectedTab)
                .padding(.horizontal, dockHorizontalPadding)
                .padding(.top, dockTopInsetPadding)
                .padding(.bottom, dockBottomInsetOffset)
                .allowsHitTesting(!deviceControlViewModel.isMandatorySetupFlowActive)
                .opacity(deviceControlViewModel.isMandatorySetupFlowActive ? 0.55 : 1.0)
        }
        .onAppear {
            UITabBar.appearance().isHidden = true
            if !isRunningForPreviews {
                // Passive discovery at launch (UDP/mDNS only)
                DeviceControlViewModel.shared.startPassiveDiscovery()
            }
        }
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
