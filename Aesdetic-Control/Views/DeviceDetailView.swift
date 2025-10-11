import SwiftUI

struct DeviceDetailView: View {
    let device: WLEDDevice
    @ObservedObject var viewModel: DeviceControlViewModel
    @State private var selectedTab: String = "Light"
    
    var body: some View {
        ZStack {
            // Simple black background (no heavy effects!)
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab Navigation Bar
                tabNavigationBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // Tab Content
                ScrollView {
                    tabContent
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // Add settings action if needed
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Tab Navigation Bar
    
    private var tabNavigationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(["Light", "Scenes", "Automation", "Syncs", "Settings"], id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }) {
                        Text(tab)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedTab == tab ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(selectedTab == tab ? Color.white : Color.white.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.white.opacity(selectedTab == tab ? 0 : 0.3), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "Light":
            lightTabContent
        case "Scenes":
            scenesTabContent
        case "Automation":
            automationTabContent
        case "Syncs":
            syncsTabContent
        case "Settings":
            settingsTabContent
        default:
            EmptyView()
        }
    }
    
    private var lightTabContent: some View {
        VStack(spacing: 16) {
            // Unified Color Pane
            UnifiedColorPane(device: device)
            
            // Transition Pane
            TransitionPane(device: device)
        }
    }
    
    private var scenesTabContent: some View {
        VStack {
            Text("Scenes")
                .font(.title2)
                .foregroundColor(.white)
            Text("Coming soon...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var automationTabContent: some View {
        VStack {
            Text("Automation")
                .font(.title2)
                .foregroundColor(.white)
            Text("Coming soon...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var syncsTabContent: some View {
        VStack {
            Text("Syncs")
                .font(.title2)
                .foregroundColor(.white)
            Text("Coming soon...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var settingsTabContent: some View {
        VStack {
            Text("Settings")
                .font(.title2)
                .foregroundColor(.white)
            Text("Coming soon...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
