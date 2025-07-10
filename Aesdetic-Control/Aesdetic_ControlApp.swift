//
//  Aesdetic_ControlApp.swift
//  Aesdetic-Control
//
//  Created by Ryan Tam on 6/26/25.
//

import SwiftUI

@main
struct Aesdetic_ControlApp: App {
    @StateObject private var deviceControlViewModel = DeviceControlViewModel.shared
    @StateObject private var automationViewModel = AutomationViewModel.shared
    @StateObject private var dashboardViewModel = DashboardViewModel.shared
    @StateObject private var wellnessViewModel = WellnessViewModel()
    
    let coreDataManager = CoreDataManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceControlViewModel)
                .environmentObject(automationViewModel)
                .environmentObject(dashboardViewModel)
                .environmentObject(wellnessViewModel)
                .environment(\.managedObjectContext, coreDataManager.viewContext)
        }
    }
}
