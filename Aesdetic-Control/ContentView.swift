//
//  ContentView.swift
//  Aesdetic-Control
//
//  Created by Ryan Tam on 6/26/25.
//

import SwiftUI

struct ContentView: View {
    // Use the shared ViewModels to ensure proper state management
    @ObservedObject private var deviceViewModel = DeviceControlViewModel.shared
    @State private var selectedTab: DockTab = .dashboard
    
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
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DockBar(selectedTab: $selectedTab)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
        }
        .background(TabBarHider())
        .onAppear {
            // Passive discovery at launch (UDP/mDNS only)
            deviceViewModel.startPassiveDiscovery()
        }
        .preferredColorScheme(.dark) // Ensure dark theme consistency
    }
}

#Preview {
    ContentView()
}
