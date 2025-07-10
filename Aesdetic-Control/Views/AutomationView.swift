//
//  AutomationView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI

struct AutomationView: View {
    @ObservedObject private var viewModel = AutomationViewModel.shared
    @State private var showingCreateAutomation = false
    
    // Animation constants (matching design system)
    private let standardAnimation: Animation = .easeInOut(duration: 0.25)
    private let fastAnimation: Animation = .easeInOut(duration: 0.15)
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Header Section
                        headerSection(geometry: geometry)
                        
                        // Quick Presets Section
                        presetsSection(geometry: geometry)
                        
                        // User Automations Section
                        automationsSection(geometry: geometry)
                        
                        // Bottom padding for safe scrolling
                        Color.clear.frame(height: 20)
                    }
                    .animation(standardAnimation, value: viewModel.automations.count)
                }
                .background(Color.black) // Dark theme background
                .navigationBarHidden(true)
                .refreshable {
                    await viewModel.refreshAutomations()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingCreateAutomation) {
            CreateAutomationView()
        }
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func headerSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automation")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
    }
    
    // MARK: - Quick Presets Section
    @ViewBuilder
    private func presetsSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Presets")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            
            // Grid of preset cards
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                QuickPresetCard(preset: .sunrise)
                QuickPresetCard(preset: .sunset)
                QuickPresetCard(preset: .focus)
                QuickPresetCard(preset: .relax)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - User Automations Section  
    @ViewBuilder
    private func automationsSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header with create button
            HStack {
                Text("My Automations")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    showingCreateAutomation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Create")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(1.0)
                .animation(fastAnimation, value: showingCreateAutomation)
            }
            .padding(.horizontal, 16)
            
            // Automations list or empty state
            if viewModel.automations.isEmpty {
                EmptyAutomationsView()
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.automations) { automation in
                        AutomationCard(automation: automation)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    AutomationView()
} 