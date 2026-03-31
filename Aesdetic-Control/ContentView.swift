//
//  ContentView.swift
//  Aesdetic-Control
//
//  Created by Ryan Tam on 6/26/25.
//

import SwiftUI
import UIKit

struct ContentView: View {
    // Use the shared ViewModels to ensure proper state management
    @ObservedObject private var deviceViewModel = DeviceControlViewModel.shared
    @State private var selectedTab: DockTab = .dashboard
    private let dockHorizontalPadding: CGFloat = 16
    private let dockTopInsetPadding: CGFloat = 0
    private let dockBottomInsetOffset: CGFloat = -8

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
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
        }
        .onAppear {
            UITabBar.appearance().isHidden = true
            // Passive discovery at launch (UDP/mDNS only)
            deviceViewModel.startPassiveDiscovery()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
