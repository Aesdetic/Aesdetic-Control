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
class DashboardViewModel: ObservableObject {
    
    // MARK: - Singleton
    static let shared = DashboardViewModel()
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Enhanced automation integration
    private let automationViewModel = AutomationViewModel.shared
    
    // Greeting management
    @Published var currentGreeting: String = ""
    @Published var currentQuote: String = ""
    private var greetingTimer: Timer?
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
        setupGreetingRotation()
        setupDataBindings()
        setupAppLifecycleObservers()
        updateCurrentGreeting()
    }
    
    deinit {
        greetingTimer?.invalidate()
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
            self?.pauseGreetingTimer()
        }
        
        // Resume greeting timer when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeGreetingTimer()
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
        automationViewModel.activeAutomations
    }
    
    var nextUpcomingAutomation: Automation? {
        automationViewModel.nextUpcomingAutomation
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
            }
            .store(in: &cancellables)
    }
    
    func updateCurrentGreeting() {
        currentGreeting = getGreetingBasedOnTime()
        currentQuote = quoteManager.getTodaysQuote()
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
}

// MARK: - Supporting Types

private enum TimeOfDay {
    case morning, afternoon, evening, night
}

// MARK: - Daily Quote Manager

class DailyQuoteManager: ObservableObject {
    static let shared = DailyQuoteManager()
    
    // Morning quotes (5:00 - 11:59) - Motivational & Energy
    private let morningQuotes = [
        "Rise and shine bright today",
        "Your energy sets the tone",
        "Paint today brilliantly",
        "Embrace bright possibilities",
        "Let your light guide the way",
        "Fresh opportunities await",
        "Start strong, create boldly",
        "Your morning lights the world"
    ]
    
    // Afternoon quotes (12:00 - 16:59) - Resilience & Focus  
    private let afternoonQuotes = [
        "Keep shining through challenges",
        "Persistence creates perfect ambiance", 
        "Stay focused, cut through obstacles",
        "Power through with bright energy",
        "Resilience is your brightest quality",
        "Transform challenges to growth",
        "Your determination illuminates forward",
        "Breakthrough moments need steady light"
    ]
    
    // Evening/Night quotes (17:00 - 4:59) - Calming & Self-Love
    private let eveningQuotes = [
        "Embrace gentle evening glow",
        "You deserve warm, soft light",
        "Let calm atmosphere restore you", 
        "Create your gentle sanctuary",
        "Your worth shines in quiet moments",
        "Soften into evening self-love",
        "Gentle ambiance reflects inner peace",
        "Rest in your warm accomplishments"
    ]
    
    func getTodaysQuote() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
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
        let today = Calendar.current.startOfDay(for: Date())
        let daysSince1970 = Int(today.timeIntervalSince1970 / 86400)
        let timeSlot = hour / 6 // Creates 4 time slots per day
        let index = (daysSince1970 + timeSlot) % quotes.count
        return quotes[index]
    }
} 