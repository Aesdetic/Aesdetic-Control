//
//  Aesdetic_ControlApp.swift
//  Aesdetic-Control
//
//  Created by Ryan Tam on 6/26/25.
//

import SwiftUI
import Network

@main
struct Aesdetic_ControlApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var deviceControlViewModel = DeviceControlViewModel.shared
    @StateObject private var automationViewModel = AutomationViewModel.shared
    @StateObject private var dashboardViewModel = DashboardViewModel.shared
    @StateObject private var wellnessViewModel = WellnessViewModel()
    
    let coreDataManager = CoreDataManager.shared
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            RootContainer()
                .environmentObject(deviceControlViewModel)
                .environmentObject(automationViewModel)
                .environmentObject(dashboardViewModel)
                .environmentObject(wellnessViewModel)
                .environment(\.managedObjectContext, coreDataManager.viewContext)
                .onAppear {
                    // Configure transparent backgrounds immediately
                    configureAppearances()
                    
                    // CRITICAL: Warm up the sheet presentation system
                    // This forces iOS to initialize presentation controllers
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                        #if DEBUG
                        print("✅ Warmed up presentation system")
                        #endif
                    }
                    
                    // Prompt Local Network access immediately
                    LocalNetworkPrompter.shared.trigger()
                    
                    // Listen for widget intents
                    setupWidgetNotificationListeners()
                }
                .task {
                    // Warm caches shortly after launch to speed up first detail open after reinstall
                    Task.detached { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if let first = deviceControlViewModel.devices.first {
                            await deviceControlViewModel.prefetchDeviceDetailData(for: first)
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // When app becomes active, ensure permission prompt (if still pending)
                        LocalNetworkPrompter.shared.trigger()
                        
                        // Immediately check device status when returning to app
                        Task { @MainActor in
                            await deviceControlViewModel.checkDeviceStatusOnAppActive()
                            deviceControlViewModel.resumeRealTimeConnectionsIfNeeded()
                        }
                    case .background:
                        deviceControlViewModel.pauseRealTimeConnectionsIfNeeded()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
    
    // MARK: - Appearance Configuration
    private func configureAppearances() {
        // Keep tab bar visuals neutral; actual tab bar is hidden in SwiftUI.
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundColor = UIColor.clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().isHidden = true
        
        // Also configure TabView container background
        UITabBar.appearance().backgroundColor = UIColor.clear
        UITabBar.appearance().barTintColor = UIColor.clear
        
        // Make NavigationBar background transparent
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = UIColor.clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

        // Ensure UIKit-backed containers do not paint opaque fallback colors.
        UIScrollView.appearance().backgroundColor = .clear
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear

        // Keep window transparent so shared AppBackground is always visible.
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.backgroundColor = UIColor.clear
                window.isOpaque = false
            }
        }
    }
    
    // MARK: - Widget Notification Listeners
    
    private func setupWidgetNotificationListeners() {
        let viewModel = deviceControlViewModel // Capture for Sendable closure
        
        // Listen for widget power toggle intents
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WidgetTogglePower"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let deviceId = userInfo["deviceId"] as? String {
                Task { @MainActor in
                    // Access devices on MainActor to avoid Sendable closure issues
                    if let device = viewModel.devices.first(where: { $0.id == deviceId }) {
                        await viewModel.toggleDevicePower(device)
                    }
                }
            }
        }
        
        // Listen for widget brightness set intents
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WidgetSetBrightness"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let deviceId = userInfo["deviceId"] as? String,
               let brightness = userInfo["brightness"] as? Int {
                Task { @MainActor in
                    // Access devices on MainActor to avoid Sendable closure issues
                    if let device = viewModel.devices.first(where: { $0.id == deviceId }) {
                        await viewModel.updateDeviceBrightness(device, brightness: brightness)
                    }
                }
            }
        }
    }
}
