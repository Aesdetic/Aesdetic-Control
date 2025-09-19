//
//  WellnessViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine

@MainActor
class WellnessViewModel: ObservableObject {
    @Published var dailyFocus: String = "Today, focus on creating peaceful moments with perfect lighting."
    @Published var todaysHabits: [WellnessHabit] = []
    @Published var todaysJournal: JournalEntry?
    @Published var shouldShowMorningCheckin: Bool = false
    @Published var shouldShowEveningReflection: Bool = false
    
    init() {
        loadMockData()
        updateTimeBasedFeatures()
    }
    
    func refreshData() async {
        // TODO: Implement data refresh
        loadMockData()
        updateTimeBasedFeatures()
    }
    
    private func updateTimeBasedFeatures() {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Show morning check-in between 6 AM and 10 AM
        shouldShowMorningCheckin = (6...10).contains(hour)
        
        // Show evening reflection after 6 PM
        shouldShowEveningReflection = hour >= 18
    }
    
    private func loadMockData() {
        todaysHabits = [
            WellnessHabit(id: "1", name: "Morning Meditation", isCompleted: false),
            WellnessHabit(id: "2", name: "Gratitude Practice", isCompleted: true),
            WellnessHabit(id: "3", name: "Evening Wind Down", isCompleted: false)
        ]
        
        // Mock journal entry if none exists
        if todaysJournal == nil {
            todaysJournal = JournalEntry(
                id: UUID().uuidString,
                content: "",
                mood: .neutral,
                date: Date()
            )
        }
    }

    func upsertTodayJournal(content: String, mood: JournalEntry.Mood) {
        if var entry = todaysJournal {
            entry.content = content
            entry.mood = mood
            entry.date = Date()
            todaysJournal = entry
        } else {
            todaysJournal = JournalEntry(
                id: UUID().uuidString,
                content: content,
                mood: mood,
                date: Date()
            )
        }
    }
}

struct WellnessHabit: Identifiable, Codable {
    let id: String
    var name: String
    var isCompleted: Bool
}

struct JournalEntry: Identifiable, Codable, Equatable {
    var id: String
    var content: String
    var mood: Mood
    var date: Date
    
    enum Mood: String, CaseIterable, Codable {
        case excellent = "excellent"
        case good = "good"
        case neutral = "neutral"
        case low = "low"
        case poor = "poor"
        
        var emoji: String {
            switch self {
            case .excellent: return "😄"
            case .good: return "😊"
            case .neutral: return "😐"
            case .low: return "😔"
            case .poor: return "😢"
            }
        }
    }
} 