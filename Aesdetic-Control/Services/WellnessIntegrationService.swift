import Foundation
import EventKit
import HealthKit

final class WellnessIntegrationService {
    static let shared = WellnessIntegrationService()

    private let eventStore = EKEventStore()
    private let healthStore = HKHealthStore()
    private let calendarIdentifierKey = "wellness_calendar_identifier"
    private let remindersListIdentifierKey = "wellness_reminders_list_identifier"
    private var remindersAccessGranted: Bool? = nil
    private var calendarAccessGranted: Bool? = nil
    private var healthAccessGranted: Bool? = nil

    private init() {}

    // MARK: - Permissions

    func requestReminderAccess() async -> Bool {
        if let cached = remindersAccessGranted {
            return cached
        }
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, *) {
            if status == .fullAccess || status == .writeOnly {
                remindersAccessGranted = true
                return true
            }
        } else {
            if status == .authorized {
                remindersAccessGranted = true
                return true
            }
        }
        if status == .denied || status == .restricted {
            remindersAccessGranted = false
            return false
        }
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                remindersAccessGranted = granted
                return granted
            } catch {
                remindersAccessGranted = false
                return false
            }
        } else {
            let granted: Bool = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            remindersAccessGranted = granted
            return granted
        }
    }

    func requestCalendarAccess() async -> Bool {
        if let cached = calendarAccessGranted {
            return cached
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            if status == .fullAccess || status == .writeOnly {
                calendarAccessGranted = true
                return true
            }
        } else {
            if status == .authorized {
                calendarAccessGranted = true
                return true
            }
        }
        if status == .denied || status == .restricted {
            calendarAccessGranted = false
            return false
        }
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                calendarAccessGranted = granted
                return granted
            } catch {
                calendarAccessGranted = false
                return false
            }
        } else {
            let granted: Bool = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            calendarAccessGranted = granted
            return granted
        }
    }

    func requestHealthAccess() async -> Bool {
        if let cached = healthAccessGranted {
            return cached
        }
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            healthAccessGranted = false
            return false
        }
        do {
            let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                healthStore.requestAuthorization(toShare: [], read: [sleepType]) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
            healthAccessGranted = granted
            return granted
        } catch {
            healthAccessGranted = false
            return false
        }
    }

    // MARK: - Reminders

    func upsertReminder(
        title: String,
        notes: String?,
        dueDate: Date?,
        existingIdentifier: String?
    ) async -> String? {
        guard await requestReminderAccess() else { return nil }
        let reminder = existingIdentifier
            .flatMap { eventStore.calendarItem(withIdentifier: $0) as? EKReminder }
            ?? EKReminder(eventStore: eventStore)

        reminder.calendar = ensureWellnessReminderList()
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }

        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    // MARK: - Calendar Events

    func upsertEvent(
        title: String,
        notes: String?,
        startDate: Date,
        durationMinutes: Int,
        existingIdentifier: String?
    ) async -> String? {
        guard durationMinutes > 0 else { return nil }
        guard await requestCalendarAccess() else { return nil }
        let event = existingIdentifier
            .flatMap { eventStore.event(withIdentifier: $0) }
            ?? EKEvent(eventStore: eventStore)

        event.calendar = ensureWellnessCalendar()
        event.title = title
        event.notes = notes
        event.startDate = startDate
        event.endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    // MARK: - HealthKit

    func fetchLatestWakeTime() async -> Date? {
        guard await requestHealthAccess(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            end: Date(),
            options: .strictEndDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 20,
                sortDescriptors: [sort]
            ) { _, results, _ in
                let samples = results?.compactMap { $0 as? HKCategorySample } ?? []
                let asleepSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                let latestWake = asleepSamples.first?.endDate ?? samples.first?.endDate
                continuation.resume(returning: latestWake)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    private func ensureWellnessCalendar() -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarIdentifierKey),
           let calendar = eventStore.calendar(withIdentifier: id) {
            return calendar
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "Wellness"
        calendar.source = eventStore.defaultCalendarForNewEvents?.source
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIdentifierKey)
        } catch {
            return eventStore.defaultCalendarForNewEvents ?? calendar
        }
        return calendar
    }

    private func ensureWellnessReminderList() -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: remindersListIdentifierKey),
           let calendar = eventStore.calendar(withIdentifier: id) {
            return calendar
        }
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = "Wellness Tasks"
        calendar.source = eventStore.defaultCalendarForNewReminders()?.source
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: remindersListIdentifierKey)
        } catch {
            return eventStore.defaultCalendarForNewReminders() ?? calendar
        }
        return calendar
    }
}
