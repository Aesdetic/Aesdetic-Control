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
            ContentView()
                .environmentObject(deviceControlViewModel)
                .environmentObject(automationViewModel)
                .environmentObject(dashboardViewModel)
                .environmentObject(wellnessViewModel)
                .environment(\.managedObjectContext, coreDataManager.viewContext)
                .onAppear {
                    // Configure transparent backgrounds immediately
                    configureAppearances()
                    
                    // Prompt Local Network access immediately
                    LocalNetworkPrompter.shared.trigger()
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
                    if newPhase == .active {
                        // When app becomes active, ensure permission prompt (if still pending)
                        LocalNetworkPrompter.shared.trigger()
                    }
                }
        }
    }
    
    // MARK: - Appearance Configuration
    private func configureAppearances() {
        // Make TabView background transparent
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundColor = UIColor.clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        
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
        
        // Set window background to white to prevent black default
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.backgroundColor = UIColor.white
            }
        }
    }
}

// Retained Bonjour browser to reliably trigger Local Network permission immediately
final class LocalNetworkPrompter {
    static let shared = LocalNetworkPrompter()
    private var browser: NWBrowser?
    private var udpConnection: NWConnection?
    private var lastTrigger: Date?
    private init() {}
    
    func trigger() {
        #if targetEnvironment(simulator)
        // Simulator does not show the Local Network prompt; no-op to avoid unnecessary work
        return
        #else
        // Avoid spamming: only trigger if not in the last 5 seconds
        if let last = lastTrigger, Date().timeIntervalSince(last) < 5 { return }
        lastTrigger = Date()
        
        // Start a short-lived Bonjour browse that reliably surfaces the system prompt
        if browser == nil {
            let params = NWParameters.tcp
            let bonjour = NWBrowser.Descriptor.bonjour(type: "_wled._tcp", domain: nil)
            let b = NWBrowser(for: bonjour, using: params)
            browser = b
            b.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.browser?.cancel()
                self?.browser = nil
            }
        }

        // Also send one small UDP broadcast to trigger permission deterministically (WLED discovery port)
        if udpConnection == nil {
            let endpoint = NWEndpoint.hostPort(host: "255.255.255.255", port: NWEndpoint.Port(rawValue: 21324)!)
            let conn = NWConnection(to: endpoint, using: .udp)
            udpConnection = conn
            conn.stateUpdateHandler = { _ in }
            conn.start(queue: .main)
            let payload = "{}".data(using: .utf8)!
            conn.send(content: payload, completion: .contentProcessed { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.udpConnection?.cancel()
                    self?.udpConnection = nil
                }
            })
        }
        #endif
    }
}
