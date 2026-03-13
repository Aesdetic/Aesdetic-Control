import Foundation

struct WellnessEntrySnapshot: Equatable, Hashable {
    var date: Date
    var sleepQuality: Int
    var sleepTime: Date?
    var wokeOnTime: Bool
    var sunriseLampUsed: Bool
    var sunriseHelped: SunriseHelped
    var identityIntentionText: String
    var intentionText: String
    var smallestNextStepText: String
    var mainTaskText: String
    var mainTaskDurationMinutes: Int
    var mainTaskReminderId: String?
    var mainTaskEventId: String?
    var secondaryTaskOneText: String
    var secondaryTaskOneDurationMinutes: Int
    var secondaryTaskOneReminderId: String?
    var secondaryTaskOneEventId: String?
    var secondaryTaskTwoText: String
    var secondaryTaskTwoDurationMinutes: Int
    var secondaryTaskTwoReminderId: String?
    var secondaryTaskTwoEventId: String?
    var mainTaskDone: Bool
    var secondaryTaskOneDone: Bool
    var secondaryTaskTwoDone: Bool
    var brainDumpText: String
    var sleepNotesText: String
    var wakeTime: Date?
    var middayBlockerText: String
    var dayRecapText: String
    var productivityRating: Int
    var dayMoodRating: Int
    var adjustTomorrowText: String
    var tomorrowTaskOneText: String
    var tomorrowTaskOneDurationMinutes: Int
    var tomorrowTaskOneReminderId: String?
    var tomorrowTaskOneEventId: String?
    var tomorrowTaskTwoText: String
    var tomorrowTaskTwoDurationMinutes: Int
    var tomorrowTaskTwoReminderId: String?
    var tomorrowTaskTwoEventId: String?
    var tomorrowTaskThreeText: String
    var tomorrowTaskThreeDurationMinutes: Int
    var tomorrowTaskThreeReminderId: String?
    var tomorrowTaskThreeEventId: String?
    var isLocked: Bool
    var updatedAt: Date

    static func empty(for date: Date) -> WellnessEntrySnapshot {
        WellnessEntrySnapshot(
            date: Calendar.current.startOfDay(for: date),
            sleepQuality: 0,
            sleepTime: nil,
            wokeOnTime: false,
            sunriseLampUsed: false,
            sunriseHelped: .unsure,
            identityIntentionText: "",
            intentionText: "",
            smallestNextStepText: "",
            mainTaskText: "",
            mainTaskDurationMinutes: 0,
            mainTaskReminderId: nil,
            mainTaskEventId: nil,
            secondaryTaskOneText: "",
            secondaryTaskOneDurationMinutes: 0,
            secondaryTaskOneReminderId: nil,
            secondaryTaskOneEventId: nil,
            secondaryTaskTwoText: "",
            secondaryTaskTwoDurationMinutes: 0,
            secondaryTaskTwoReminderId: nil,
            secondaryTaskTwoEventId: nil,
            mainTaskDone: false,
            secondaryTaskOneDone: false,
            secondaryTaskTwoDone: false,
            brainDumpText: "",
            sleepNotesText: "",
            wakeTime: nil,
            middayBlockerText: "",
            dayRecapText: "",
            productivityRating: 0,
            dayMoodRating: 0,
            adjustTomorrowText: "",
            tomorrowTaskOneText: "",
            tomorrowTaskOneDurationMinutes: 0,
            tomorrowTaskOneReminderId: nil,
            tomorrowTaskOneEventId: nil,
            tomorrowTaskTwoText: "",
            tomorrowTaskTwoDurationMinutes: 0,
            tomorrowTaskTwoReminderId: nil,
            tomorrowTaskTwoEventId: nil,
            tomorrowTaskThreeText: "",
            tomorrowTaskThreeDurationMinutes: 0,
            tomorrowTaskThreeReminderId: nil,
            tomorrowTaskThreeEventId: nil,
            isLocked: false,
            updatedAt: Date()
        )
    }
}

struct WellnessEntrySummary: Identifiable, Hashable {
    var date: Date
    var summary: String
    var moodRating: Int

    var id: Date { date }
}

enum SunriseHelped: String, CaseIterable, Identifiable, CustomStringConvertible {
    case yes = "Yes"
    case no = "No"
    case unsure = "Not sure"

    var id: String { rawValue }
    var description: String { rawValue }
}
