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
    
    var body: some View {
        ZStack {
            TabView {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2")
                    }

                DeviceControlView()
                    .tabItem {
                        Label("Devices", systemImage: "lightbulb.2")
                    }

                AutomationView()
                    .tabItem {
                        Label("Automation", systemImage: "clock.arrow.2.circlepath")
                    }
                
                WellnessView()
                    .tabItem {
                        Label("Wellness", systemImage: "heart.text.square")
                    }
            }
        }
        .onAppear {
            // Auto-start discovery when app launches if no devices exist
            Task {
                if deviceViewModel.devices.isEmpty {
                    await deviceViewModel.startScanning()
                }
            }
        }
        .preferredColorScheme(.dark) // Ensure dark theme consistency
    }
}

#Preview {
    ContentView()
}
