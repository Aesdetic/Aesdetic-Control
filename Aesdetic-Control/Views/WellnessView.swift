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
        // RESTRUCTURED: Remove NavigationStack, use working pattern from Dashboard
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Enhanced safe area spacing for status bar
                    Spacer()
                        .frame(height: max(80, geometry.safeAreaInsets.top + 40))
                    
                    // Header
                    HStack {
                        Text("Wellness")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    
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
                    
                    // Bottom spacing
                    Spacer()
                        .frame(height: 100)
                }
                .animation(standardAnimation, value: viewModel.shouldShowMorningCheckin)
                .animation(standardAnimation, value: viewModel.shouldShowEveningReflection)
            }
            .background(Color.clear)
            .refreshable {
                await viewModel.refreshData()
            }
        }
        .background(Color.clear)
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
            
            // Stats chip
            HStack {
                Text("7‑day mood avg: ")
                    .foregroundColor(.white.opacity(0.8))
                Text("–")
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            DailyJournalCard(entry: viewModel.todaysJournal)
                .padding(.horizontal, 16)
            
            // History list
            // Journal history list placeholder (model not implemented)
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
        .background(Color.clear)
        .padding(.bottom, 20)
    }
}

#Preview {
    WellnessView()
} 