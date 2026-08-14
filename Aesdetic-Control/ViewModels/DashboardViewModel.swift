//
//  DashboardViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    
    // MARK: - Singleton
    static let shared = DashboardViewModel()
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Enhanced automation integration
    private let automationViewModel = AutomationViewModel.shared
    private let automationStore = AutomationStore.shared
    
    // Greeting management
    @Published var currentGreeting: String = ""
    @Published var currentQuote: String = ""
    private var greetingTimer: Timer?
    private var subtitleRefreshTask: Task<Void, Never>?
    private let quoteManager = DailyQuoteManager.shared
    
    // Data sources
    private let deviceController = DeviceControlViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Simple "Good [time]" greetings without exclamation marks
    private let morningGreetings = [
        "Good morning"
    ]
    
    private let afternoonGreetings = [
        "Good afternoon"
    ]
    
    private let eveningGreetings = [
        "Good evening"
    ]
    
    private let nightGreetings = [
        "Good night"
    ]
    
    private init() {
        if AppRuntimeEnvironment.isRunningUnitTests {
            return
        }
        setupGreetingRotation()
        setupDataBindings()
        setupAppLifecycleObservers()
        updateCurrentGreeting()
    }
    
    deinit {
        greetingTimer?.invalidate()
        subtitleRefreshTask?.cancel()
        // Clean up notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App Lifecycle Management
    
    private func setupAppLifecycleObservers() {
        // Pause greeting timer when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseGreetingTimer()
            }
        }
        
        // Resume greeting timer when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeGreetingTimer()
            }
        }
    }
    
    private func pauseGreetingTimer() {
        greetingTimer?.invalidate()
        greetingTimer = nil
    }
    
    private func resumeGreetingTimer() {
        // Update greeting immediately when app becomes active
        updateCurrentGreeting()
        setupGreetingRotation()
    }
    
    // MARK: - Data Access Properties
    
    var devices: [WLEDDevice] {
        deviceController.devices
    }
    
    var automations: [Automation] {
        automationViewModel.automations
    }
    
    var enabledAutomations: [Automation] {
        automationViewModel.enabledAutomations
    }
    
    var activeAutomations: [Automation] {
        // Since we don't have active automations in our simplified model, return empty array
        []
    }
    
    var nextUpcomingAutomation: Automation? {
        // Since we don't have next upcoming automation in our simplified model, return nil
        nil
    }
    
    // MARK: - Public Methods
    
    func refreshData() async {
        isLoading = true
        errorMessage = nil
        
        // Refresh devices
        await deviceController.refreshAllDevices()
        
        // Refresh automations
        await automationViewModel.refreshAutomations()
        
        updateCurrentGreeting()
        
        isLoading = false
    }
    
    func toggleAutomation(_ automation: Automation) {
        automationViewModel.toggleAutomation(automation)
    }
    
    // MARK: - Greeting Management
    
    private func setupGreetingRotation() {
        // Invalidate existing timer first
        greetingTimer?.invalidate()
        
        // Rotate greeting every 30 minutes (reasonable frequency)
        greetingTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentGreeting()
            }
        }
    }
    
    private func setupDataBindings() {
        // Listen to device changes for context-aware greetings
        deviceController.$devices
            .sink { [weak self] _ in
                self?.updateCurrentGreeting()
            }
            .store(in: &cancellables)
        
        // Listen to automation changes
        automationViewModel.$automations
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.updateCurrentGreeting()
            }
            .store(in: &cancellables)
    }
    
    func updateCurrentGreeting() {
        let now = Date()
        currentGreeting = getGreetingBasedOnTime()
        currentQuote = quoteManager.getQuote(for: now)

        subtitleRefreshTask?.cancel()
        subtitleRefreshTask = nil
        guard shouldShowRoutineSubtitle(referenceDate: now) else { return }

        subtitleRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let subtitle = await self.routineSubtitle(referenceDate: now) else { return }
            guard !Task.isCancelled else { return }
            self.currentQuote = subtitle
        }
    }
    
    private func getGreetingBasedOnTime() -> String {
        let timeOfDay = getCurrentTimeOfDay()
        let baseGreetings = getGreetingsForTimeOfDay(timeOfDay)
        
        // Select simple time-based greeting without long contextual additions
        return baseGreetings.randomElement() ?? "Welcome to your smart home!"
    }
    
    private func getCurrentTimeOfDay() -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }
    
    private func getGreetingsForTimeOfDay(_ timeOfDay: TimeOfDay) -> [String] {
        switch timeOfDay {
        case .morning:
            return morningGreetings
        case .afternoon:
            return afternoonGreetings
        case .evening:
            return eveningGreetings
        case .night:
            return nightGreetings
        }
    }

    private func shouldShowRoutineSubtitle(referenceDate: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: referenceDate)
        let minute = calendar.component(.minute, from: referenceDate)
        let halfHourSlot = (hour * 2) + (minute >= 30 ? 1 : 0)
        let day = calendar.ordinality(of: .day, in: .era, for: referenceDate) ?? 0
        return (day + halfHourSlot).isMultiple(of: 2)
    }

    private func routineSubtitle(referenceDate: Date) async -> String? {
        let wakeAutomations = automations.filter(isWakeAutomation)
        let nextWake = await nextCandidate(
            in: wakeAutomations.filter(\.enabled),
            referenceDate: referenceDate
        )
        let nextWindDown = await nextCandidate(
            in: automations.filter { $0.enabled && isWindDownAutomation($0) },
            referenceDate: referenceDate
        )

        if let nextWindDown,
           nextWake == nil || nextWindDown.date < nextWake!.date {
            return "Wind Down starts \(timePhrase(for: nextWindDown.date, referenceDate: referenceDate))"
        }

        if let nextWake {
            return "Wake sunrise starts \(wakePhrase(for: nextWake.date, referenceDate: referenceDate))"
        }

        if wakeAutomations.isEmpty || wakeAutomations.contains(where: { !$0.enabled }) {
            return await naturalSunriseSubtitle(referenceDate: referenceDate)
        }

        return nil
    }

    private func nextCandidate(
        in automations: [Automation],
        referenceDate: Date
    ) async -> (automation: Automation, date: Date)? {
        var best: (automation: Automation, date: Date)?
        for automation in automations {
            guard let date = await automationStore.nextTriggerDate(for: automation, referenceDate: referenceDate) else {
                continue
            }
            if best == nil || date < best!.date {
                best = (automation, date)
            }
        }
        return best
    }

    private func naturalSunriseSubtitle(referenceDate: Date) async -> String? {
        guard let device = preferredDashboardDevice(),
              let reference = await automationStore.currentSolarReference(
                for: device,
                requestAuthorization: false
              ),
              let sunrise = automationStore.resolveSolarTriggerDate(
                event: .sunrise,
                coordinate: reference.coordinate,
                date: referenceDate,
                offsetMinutes: 0,
                timeZone: reference.timeZone
              ) else {
            return nil
        }
        return "Next sunrise is \(timePhrase(for: sunrise, referenceDate: referenceDate))"
    }

    private func preferredDashboardDevice() -> WLEDDevice? {
        devices.first { $0.productType == .sunriseLamp } ?? devices.first
    }

    private func isWakeAutomation(_ automation: Automation) -> Bool {
        let templateId = automation.metadata.templateId?.lowercased() ?? ""
        if templateId == "sunrise" || templateId == "onboarding_wake_v2" {
            return true
        }
        let name = automation.name.lowercased()
        return name.contains("wake") || name.contains("sunrise") || name.contains("morning")
    }

    private func isWindDownAutomation(_ automation: Automation) -> Bool {
        let templateId = automation.metadata.templateId?.lowercased() ?? ""
        if templateId == "bedtime" || templateId == "sunset" {
            return true
        }
        let name = automation.name.lowercased()
        return name.contains("wind down")
            || name.contains("unwind")
            || name.contains("bedtime")
            || name.contains("sleep")
            || name.contains("sunset")
    }

    private func wakePhrase(for date: Date, referenceDate: Date) -> String {
        let interval = date.timeIntervalSince(referenceDate)
        if interval > 0, interval <= 18 * 60 * 60 {
            return "in \(compactDuration(interval))"
        }
        return timePhrase(for: date, referenceDate: referenceDate)
    }

    private func timePhrase(for date: Date, referenceDate: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return "at \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "at \(time) tomorrow"
        }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "on \(day) at \(time)"
    }

    private func compactDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Supporting Types

private enum TimeOfDay {
    case morning, afternoon, evening, night
}

// MARK: - Daily Quote Manager

class DailyQuoteManager: ObservableObject {
    static let shared = DailyQuoteManager()
    
    // Morning quotes (5:00 - 11:59)
    private let morningQuotes = [
        "Start softly, then move with purpose",
        "Let the morning meet you gently",
        "Small rituals make the day lighter",
        "Begin with calm, then build momentum",
        "A steady morning changes everything",
        "Make space for the day you want",
        "Wake slowly and choose your pace",
        "The first light sets the tone"
    ]
    
    // Afternoon quotes (12:00 - 16:59)
    private let afternoonQuotes = [
        "Reset the room, reset your focus",
        "Keep the pace clear and steady",
        "A quiet pause can sharpen the day",
        "Make the next hour lighter",
        "Good focus starts with the atmosphere",
        "Let your space support your energy",
        "Small adjustments can change the mood",
        "Stay steady through the middle of the day"
    ]
    
    // Evening/Night quotes (17:00 - 4:59)
    private let eveningQuotes = [
        "Let the room slow down with you",
        "Dim the day and keep what matters",
        "A calmer evening begins with softer light",
        "Make tonight easy to return from",
        "Give your mind a softer landing",
        "The day can end gently",
        "Rest is part of the rhythm",
        "Settle in with a quieter glow"
    ]
    
    func getTodaysQuote() -> String {
        getQuote(for: Date())
    }

    func getQuote(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let quotes: [String]
        
        switch hour {
        case 5..<12:
            quotes = morningQuotes
        case 12..<17:
            quotes = afternoonQuotes
        default:
            quotes = eveningQuotes
        }
        
        // Use hour + day for variation while keeping consistency within time periods
        let today = Calendar.current.startOfDay(for: date)
        let daysSince1970 = Int(today.timeIntervalSince1970 / 86400)
        let timeSlot = hour / 6 // Creates 4 time slots per day
        let index = (daysSince1970 + timeSlot) % quotes.count
        return quotes[index]
    }
}
