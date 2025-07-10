//
//  WellnessView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI

struct WellnessView: View {
    @StateObject private var viewModel = WellnessViewModel()
    
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
                        
                        // Today's Focus Section
                        focusSection(geometry: geometry)
                        
                        // Morning Check-in (conditional)
                        if viewModel.shouldShowMorningCheckin {
                            checkinSection(geometry: geometry)
                        }
                        
                        // Habit Tracker Section
                        habitsSection(geometry: geometry)
                        
                        // Daily Journal Section
                        journalSection(geometry: geometry)
                        
                        // Evening Reflection (conditional)
                        if viewModel.shouldShowEveningReflection {
                            reflectionSection(geometry: geometry)
                        }
                        
                        // Wellness Tips Section
                        tipsSection(geometry: geometry)
                        
                        // Bottom padding for safe scrolling
                        Color.clear.frame(height: 20)
                    }
                    .animation(standardAnimation, value: viewModel.shouldShowMorningCheckin)
                    .animation(standardAnimation, value: viewModel.shouldShowEveningReflection)
                }
                .background(Color.black) // Dark theme background
                .navigationBarHidden(true)
                .refreshable {
                    await viewModel.refreshData()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func headerSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wellness")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
    }
    
    // MARK: - Today's Focus Section
    @ViewBuilder
    private func focusSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Focus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            
            TodaysFocusCard(focus: viewModel.dailyFocus)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Morning Check-in Section
    @ViewBuilder  
    private func checkinSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Morning Check-in")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            
            MorningCheckinCard()
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Habits Section
    @ViewBuilder
    private func habitsSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Habits")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            
            HabitTrackerCard(habits: viewModel.todaysHabits)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Journal Section
    @ViewBuilder
    private func journalSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Journal")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            
            DailyJournalCard(entry: viewModel.todaysJournal)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Evening Reflection Section
    @ViewBuilder
    private func reflectionSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Evening Reflection")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            
            EveningReflectionCard()
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Wellness Tips Section
    @ViewBuilder
    private func tipsSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lighting Wellness")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            
            LightingWellnessTipsCard()
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    WellnessView()
} 