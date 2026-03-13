//
//  WellnessViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine

struct WellnessReviewStats: Hashable {
    let daysTracked: Int
    let mainTasksCompleted: Int
    let secondaryTasksCompleted: Int
    let averageSleepQuality: Double
    let averageMood: Double
    let averageProductivity: Double
    let wokeOnTimeCount: Int
    let sunriseUsedCount: Int
}

@MainActor
class WellnessViewModel: ObservableObject {
    @Published var dailyFocus: String = "Today, focus on creating peaceful moments with perfect lighting."
    @Published var todaysHabits: [WellnessHabit] = []
    @Published var todaysJournal: JournalEntry?
    @Published var shouldShowMorningCheckin: Bool = false
    @Published var shouldShowEveningReflection: Bool = false
    private var integrationSyncTask: Task<Void, Never>? = nil
    
    init() {
        loadMockData()
        updateTimeBasedFeatures()
    }
    
    func refreshData() async {
        // Refresh mock data and update time-based features
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

    // MARK: - Wellness Entries

    func loadEntry(for date: Date) async -> WellnessEntrySnapshot {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        if let entry = await CoreDataManager.shared.fetchWellnessEntry(for: normalizedDate) {
            return entry
        }
        return WellnessEntrySnapshot.empty(for: normalizedDate)
    }

    func saveEntry(_ entry: WellnessEntrySnapshot) async {
        await CoreDataManager.shared.saveWellnessEntry(entry)
        await applyTomorrowPlan(from: entry)
    }

    func queueIntegrationSync(for entry: WellnessEntrySnapshot) {
        integrationSyncTask?.cancel()
        let snapshot = entry
        integrationSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await syncTasksToRemindersAndCalendar(for: snapshot)
        }
    }

    func loadHistory(limit: Int) async -> [WellnessEntrySummary] {
        let entries = await CoreDataManager.shared.fetchWellnessEntries(limit: limit)
        return entries.map { entry in
            WellnessEntrySummary(
                date: entry.date,
                summary: historySummaryText(for: entry),
                moodRating: entry.dayMoodRating
            )
        }
    }

    private func historySummaryText(for entry: WellnessEntrySnapshot) -> String {
        let candidates = [
            entry.dayRecapText,
            entry.intentionText,
            entry.brainDumpText,
            entry.sleepNotesText
        ]
        let trimmed = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return trimmed ?? "No notes yet."
    }

    func loadReviewStats(endingAt date: Date, days: Int) async -> WellnessReviewStats {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: endDate) ?? endDate
        let entries = await CoreDataManager.shared.fetchWellnessEntries(from: startDate, to: endDate)
        return buildStats(from: entries)
    }

    private func buildStats(from entries: [WellnessEntrySnapshot]) -> WellnessReviewStats {
        let daysTracked = entries.count
        let mainTasksCompleted = entries.filter { $0.mainTaskDone }.count
        let secondaryTasksCompleted = entries.reduce(0) { result, entry in
            result + (entry.secondaryTaskOneDone ? 1 : 0) + (entry.secondaryTaskTwoDone ? 1 : 0)
        }
        let wokeOnTimeCount = entries.filter { $0.wokeOnTime }.count
        let sunriseUsedCount = entries.filter { $0.sunriseLampUsed }.count

        let averageSleepQuality = averageScore(entries.map { $0.sleepQuality })
        let averageMood = averageScore(entries.map { $0.dayMoodRating })
        let averageProductivity = averageScore(entries.map { $0.productivityRating })

        return WellnessReviewStats(
            daysTracked: daysTracked,
            mainTasksCompleted: mainTasksCompleted,
            secondaryTasksCompleted: secondaryTasksCompleted,
            averageSleepQuality: averageSleepQuality,
            averageMood: averageMood,
            averageProductivity: averageProductivity,
            wokeOnTimeCount: wokeOnTimeCount,
            sunriseUsedCount: sunriseUsedCount
        )
    }

    private func averageScore(_ values: [Int]) -> Double {
        let filtered = values.filter { $0 > 0 }
        guard !filtered.isEmpty else { return 0 }
        let total = filtered.reduce(0, +)
        return Double(total) / Double(filtered.count)
    }

    // MARK: - Integrations

    func fetchLatestWakeTime() async -> Date? {
        await WellnessIntegrationService.shared.fetchLatestWakeTime()
    }

    private func applyTomorrowPlan(from entry: WellnessEntrySnapshot) async {
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date
        var nextEntry = await loadEntry(for: nextDate)

        if nextEntry.mainTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !entry.tomorrowTaskOneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nextEntry.mainTaskText = entry.tomorrowTaskOneText
            nextEntry.mainTaskDurationMinutes = entry.tomorrowTaskOneDurationMinutes
        }
        if nextEntry.secondaryTaskOneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !entry.tomorrowTaskTwoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nextEntry.secondaryTaskOneText = entry.tomorrowTaskTwoText
            nextEntry.secondaryTaskOneDurationMinutes = entry.tomorrowTaskTwoDurationMinutes
        }
        if nextEntry.secondaryTaskTwoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !entry.tomorrowTaskThreeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nextEntry.secondaryTaskTwoText = entry.tomorrowTaskThreeText
            nextEntry.secondaryTaskTwoDurationMinutes = entry.tomorrowTaskThreeDurationMinutes
        }

        await CoreDataManager.shared.saveWellnessEntry(nextEntry)
    }

    private func syncTasksToRemindersAndCalendar(for entry: WellnessEntrySnapshot) async {
        var updated = entry
        let integration = WellnessIntegrationService.shared

        updated.mainTaskReminderId = await syncReminderIfNeeded(
            title: entry.mainTaskText,
            notes: entry.intentionText,
            dueDate: Calendar.current.date(byAdding: .hour, value: 9, to: entry.date),
            existingIdentifier: entry.mainTaskReminderId,
            integration: integration
        )

        updated.secondaryTaskOneReminderId = await syncReminderIfNeeded(
            title: entry.secondaryTaskOneText,
            notes: entry.intentionText,
            dueDate: Calendar.current.date(byAdding: .hour, value: 9, to: entry.date),
            existingIdentifier: entry.secondaryTaskOneReminderId,
            integration: integration
        )

        updated.secondaryTaskTwoReminderId = await syncReminderIfNeeded(
            title: entry.secondaryTaskTwoText,
            notes: entry.intentionText,
            dueDate: Calendar.current.date(byAdding: .hour, value: 9, to: entry.date),
            existingIdentifier: entry.secondaryTaskTwoReminderId,
            integration: integration
        )

        updated.mainTaskEventId = await syncEventIfNeeded(
            title: entry.mainTaskText,
            notes: entry.intentionText,
            startDate: Calendar.current.date(byAdding: .hour, value: 9, to: entry.date) ?? entry.date,
            durationMinutes: entry.mainTaskDurationMinutes,
            existingIdentifier: entry.mainTaskEventId,
            integration: integration
        )

        updated.secondaryTaskOneEventId = await syncEventIfNeeded(
            title: entry.secondaryTaskOneText,
            notes: entry.intentionText,
            startDate: Calendar.current.date(byAdding: .hour, value: 11, to: entry.date) ?? entry.date,
            durationMinutes: entry.secondaryTaskOneDurationMinutes,
            existingIdentifier: entry.secondaryTaskOneEventId,
            integration: integration
        )

        updated.secondaryTaskTwoEventId = await syncEventIfNeeded(
            title: entry.secondaryTaskTwoText,
            notes: entry.intentionText,
            startDate: Calendar.current.date(byAdding: .hour, value: 14, to: entry.date) ?? entry.date,
            durationMinutes: entry.secondaryTaskTwoDurationMinutes,
            existingIdentifier: entry.secondaryTaskTwoEventId,
            integration: integration
        )

        updated.tomorrowTaskOneReminderId = await syncReminderIfNeeded(
            title: entry.tomorrowTaskOneText,
            notes: "Tomorrow plan",
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: entry.date),
            existingIdentifier: entry.tomorrowTaskOneReminderId,
            integration: integration
        )

        updated.tomorrowTaskTwoReminderId = await syncReminderIfNeeded(
            title: entry.tomorrowTaskTwoText,
            notes: "Tomorrow plan",
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: entry.date),
            existingIdentifier: entry.tomorrowTaskTwoReminderId,
            integration: integration
        )

        updated.tomorrowTaskThreeReminderId = await syncReminderIfNeeded(
            title: entry.tomorrowTaskThreeText,
            notes: "Tomorrow plan",
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: entry.date),
            existingIdentifier: entry.tomorrowTaskThreeReminderId,
            integration: integration
        )

        updated.tomorrowTaskOneEventId = await syncEventIfNeeded(
            title: entry.tomorrowTaskOneText,
            notes: "Tomorrow plan",
            startDate: Calendar.current.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date,
            durationMinutes: entry.tomorrowTaskOneDurationMinutes,
            existingIdentifier: entry.tomorrowTaskOneEventId,
            integration: integration
        )

        updated.tomorrowTaskTwoEventId = await syncEventIfNeeded(
            title: entry.tomorrowTaskTwoText,
            notes: "Tomorrow plan",
            startDate: Calendar.current.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date,
            durationMinutes: entry.tomorrowTaskTwoDurationMinutes,
            existingIdentifier: entry.tomorrowTaskTwoEventId,
            integration: integration
        )

        updated.tomorrowTaskThreeEventId = await syncEventIfNeeded(
            title: entry.tomorrowTaskThreeText,
            notes: "Tomorrow plan",
            startDate: Calendar.current.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date,
            durationMinutes: entry.tomorrowTaskThreeDurationMinutes,
            existingIdentifier: entry.tomorrowTaskThreeEventId,
            integration: integration
        )

        await CoreDataManager.shared.saveWellnessEntry(updated)
    }

    private func syncReminderIfNeeded(
        title: String,
        notes: String?,
        dueDate: Date?,
        existingIdentifier: String?,
        integration: WellnessIntegrationService
    ) async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existingIdentifier }
        return await integration.upsertReminder(
            title: trimmed,
            notes: notes,
            dueDate: dueDate,
            existingIdentifier: existingIdentifier
        )
    }

    private func syncEventIfNeeded(
        title: String,
        notes: String?,
        startDate: Date,
        durationMinutes: Int,
        existingIdentifier: String?,
        integration: WellnessIntegrationService
    ) async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, durationMinutes > 0 else { return existingIdentifier }
        return await integration.upsertEvent(
            title: trimmed,
            notes: notes,
            startDate: startDate,
            durationMinutes: durationMinutes,
            existingIdentifier: existingIdentifier
        )
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
