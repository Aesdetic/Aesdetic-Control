//
//  PlaceholderComponents.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

// Trivial edit to force recompile

import SwiftUI

// MARK: - Dashboard Components

struct DailyGreetingCard: View {
    let greeting: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct DeviceOverviewCard: View {
    let device: WLEDDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: device.productType.systemImage)
                    .foregroundColor(device.isOnline ? .green : .gray)
                Spacer()
                Circle()
                    .fill(device.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            
            Text(device.name)
                .font(.headline)
                .lineLimit(1)
            
            Text("\(device.brightness)% brightness")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct AutomationOverviewCard: View {
    let automation: Automation
    
    var body: some View {
        HStack {
            Image(systemName: automation.automationType.systemImage)
                .foregroundColor(automation.isEnabled ? .blue : .gray)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(automation.name)
                    .font(.headline)
                Text(automation.timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: .constant(automation.isEnabled))
                .labelsHidden()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
}

// MARK: - Device Control Components

struct DeviceControlCard: View {
    let device: WLEDDevice
    
    var body: some View {
        HStack {
            Image(systemName: device.productType.systemImage)
                .font(.title2)
                .foregroundColor(device.isOnline ? device.currentColor : .gray)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(device.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(device.isOnline ? .green : .red)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(device.brightness)%")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Rectangle()
                    .fill(device.currentColor.opacity(0.7))
                    .frame(width: 30, height: 20)
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct DiscoveryStatusView: View {
    var body: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Scanning for devices...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct EmptyDevicesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No devices found")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Make sure your WLED devices are connected to the same WiFi network.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Automation Components

struct QuickPresetCard: View {
    let preset: AutomationType
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: {
            // TODO: Handle preset activation
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPressed = false
                }
            }
        }) {
            VStack(spacing: 12) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                
                Text(preset.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.1))
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AutomationCard: View {
    let automation: Automation
    @State private var isToggling: Bool = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon section
            Image(systemName: automation.automationType.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(automation.isEnabled ? .white : .white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(automation.isEnabled ? .blue.opacity(0.3) : .white.opacity(0.1))
                )
            
            // Content section
            VStack(alignment: .leading, spacing: 4) {
                Text(automation.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(automation.timeString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("•")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("\(Int(automation.duration / 60)) min")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Toggle switch
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isToggling = true
                }
                // TODO: Handle automation toggle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isToggling = false
                    }
                }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(automation.isEnabled ? .white : .white.opacity(0.2))
                        .frame(width: 50, height: 30)
                    
                    Circle()
                        .fill(automation.isEnabled ? .black : .white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .offset(x: automation.isEnabled ? 10 : -10)
                }
                .scaleEffect(isToggling ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: automation.isEnabled)
                .animation(.easeInOut(duration: 0.2), value: isToggling)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
        .animation(.easeInOut(duration: 0.2), value: automation.isEnabled)
    }
}

struct EmptyAutomationsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No automations yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Create your first automation to schedule lighting routines and make your home smarter.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
    }
}

// MARK: - Wellness Components

struct TodaysFocusCard: View {
    let focus: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                Text("Focus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text(focus)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
    }
}

struct MorningCheckinCard: View {
    @State private var selectedMood: JournalEntry.Mood? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sun.max")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                Text("Check-in")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text("How are you feeling this morning?")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            HStack(spacing: 12) {
                ForEach(JournalEntry.Mood.allCases, id: \.self) { mood in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMood = mood
                        }
                        // TODO: Handle mood selection
                    }) {
                        Text(mood.emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(selectedMood == mood ? .white.opacity(0.2) : .clear)
                            )
                            .scaleEffect(selectedMood == mood ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: selectedMood)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
    }
}

struct HabitTrackerCard: View {
    let habits: [WellnessHabit]
    @State private var completionStates: [String: Bool] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                Text("Habits")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Progress indicator
                let completedCount = habits.filter { getCompletionState(for: $0) }.count
                Text("\(completedCount)/\(habits.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            VStack(spacing: 12) {
                ForEach(habits) { habit in
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                completionStates[habit.id] = !(completionStates[habit.id] ?? habit.isCompleted)
                            }
                            // TODO: Handle habit completion toggle
                        }) {
                            Image(systemName: getCompletionState(for: habit) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(getCompletionState(for: habit) ? .green : .white.opacity(0.5))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text(habit.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(getCompletionState(for: habit) ? 0.7 : 0.9))
                            .strikethrough(getCompletionState(for: habit))
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
    }
    
    private func getCompletionState(for habit: WellnessHabit) -> Bool {
        return completionStates[habit.id] ?? habit.isCompleted
    }
}

struct DailyJournalCard: View {
    let entry: JournalEntry?
    @State private var journalText: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "book")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                Text("Journal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Word count
                let wordCount = journalText.split(separator: " ").count
                Text("\(wordCount) words")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(minHeight: 100)
                
                TextEditor(text: $journalText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onTapGesture {
                        isEditing = true
                    }
                
                if journalText.isEmpty && !isEditing {
                    Text("How was your day? What are you grateful for?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 100)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
        .onAppear {
            journalText = entry?.content ?? ""
        }
    }
}

struct EveningReflectionCard: View {
    @State private var reflectionText: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "moon.stars")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                Text("Reflection")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text("What are you grateful for today?")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(minHeight: 80)
                
                TextEditor(text: $reflectionText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onTapGesture {
                        isEditing = true
                    }
                
                if reflectionText.isEmpty && !isEditing {
                    Text("Three things I'm grateful for...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
    }
}

struct LightingWellnessTipsCard: View {
    @State private var currentTipIndex: Int = 0
    
    private let tips = [
        "Use warm light (2700K-3000K) in the evening to support your natural circadian rhythm and improve sleep quality.",
        "Bright, cool light in the morning helps wake up your body and boost alertness for the day ahead.",
        "Dim your lights 1-2 hours before bedtime to signal to your body that it's time to prepare for sleep.",
        "Consider blue light filters on devices in the evening to reduce eye strain and support better rest.",
        "Natural light exposure during the day helps maintain healthy vitamin D levels and mood balance."
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                Text("Wellness Tip")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentTipIndex = (currentTipIndex + 1) % tips.count
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text(tips[currentTipIndex])
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .animation(.easeInOut(duration: 0.3), value: currentTipIndex)
            
            // Tip indicator dots
            HStack(spacing: 6) {
                ForEach(0..<tips.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentTipIndex ? .white.opacity(0.8) : .white.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentTipIndex)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        )
    }
}

// MARK: - Placeholder Views

struct CreateAutomationView: View {
    var body: some View {
        NavigationStack {
            Text("Create Automation")
                .navigationTitle("New Automation")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
} 