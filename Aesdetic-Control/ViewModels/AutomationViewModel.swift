//
//  AutomationViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine

@MainActor
class AutomationViewModel: ObservableObject {
    
    // MARK: - Singleton
    static let shared = AutomationViewModel()
    
    @Published var automations: [Automation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Real-time update properties
    private var realTimeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadMockAutomations()
        // Use intelligent timer management instead of always starting
        optimizeTimerFrequency()
    }
    
    deinit {
        realTimeTimer?.invalidate()
    }
    
    // MARK: - Real-Time Updates
    
    private func startRealTimeUpdates() {
        // Reduced frequency: Update every 8 seconds instead of 5 seconds for better performance
        // Most automation state changes don't need sub-second precision
        realTimeTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.updateAutomationStates() }
        }
    }
    
    private func stopRealTimeUpdates() {
        realTimeTimer?.invalidate()
        realTimeTimer = nil
    }
    
    // MARK: - Intelligent Timer Management
    
    private func optimizeTimerFrequency() {
        // Pause timer if no active automations need frequent updates
        let needsFrequentUpdates = automations.contains { automation in
            automation.currentState == .active || 
            (automation.currentState == .pending && automation.nextExecutionDate?.timeIntervalSinceNow ?? 3600 < 300) // Next execution within 5 minutes
        }
        
        if needsFrequentUpdates && realTimeTimer == nil {
            startRealTimeUpdates()
        } else if !needsFrequentUpdates && realTimeTimer != nil {
            // Keep a slower timer for basic status updates
            stopRealTimeUpdates()
            startSlowTimer()
        }
    }
    
    private func startSlowTimer() {
        // Slow timer for when no active automations need frequent updates (every 45 seconds)
        realTimeTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateAutomationStates()
                self?.optimizeTimerFrequency() // Re-evaluate timer needs
            }
        }
    }
    
    private func updateAutomationStates() {
        var hasChanges = false
        
        for i in 0..<automations.count {
            var automation = automations[i]
            let previousState = automation.currentState
            let previousProgress = automation.progress
            
            // Update automation state based on time and current conditions
            updateAutomationRealTimeState(&automation)
            
            // Check if anything changed to trigger UI updates
            if automation.currentState != previousState || abs(automation.progress - previousProgress) > 0.01 {
                hasChanges = true
            }
            
            automations[i] = automation
        }
        
        // Only trigger objectWillChange if there were actual changes
        if hasChanges {
            objectWillChange.send()
        }
        
        // Optimize timer frequency based on current automation states
        optimizeTimerFrequency()
    }
    
    private func updateAutomationRealTimeState(_ automation: inout Automation) {
        guard automation.isEnabled else {
            if automation.currentState != .disabled {
                automation.updateState(.disabled)
            }
            return
        }
        
        // Simulate automation execution state changes
        switch automation.currentState {
        case .pending:
            // Check if it's time to execute
            if let nextDate = automation.nextExecutionDate,
               nextDate.timeIntervalSinceNow <= 0 {
                automation.updateState(.active, progress: 0.0)
            }
            
        case .active:
            // Update progress and check for completion
            if let completionTime = automation.estimatedCompletionTime {
                let totalDuration = automation.duration
                let elapsed = totalDuration - completionTime.timeIntervalSinceNow
                let progress = min(1.0, max(0.0, elapsed / totalDuration))
                
                automation.progress = progress
                
                // Complete if time has elapsed
                if progress >= 1.0 {
                    automation.updateState(.completed)
                }
            }
            
        case .completed, .failed:
            // Check if it's time for next execution
            if let nextDate = automation.nextExecutionDate,
               nextDate.timeIntervalSinceNow > 60 { // 1 minute buffer
                automation.updateState(.pending)
            }
            
        case .disabled:
            // Stay disabled until manually enabled
            break
        }
    }
    
    // MARK: - Public Methods
    
    func refreshAutomations() async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // TODO: Implement real automation refresh from Core Data or API
        loadMockAutomations()
        isLoading = false
    }
    
    func toggleAutomation(_ automation: Automation) {
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[index].toggle()
            
            // TODO: Persist changes to Core Data
            saveAutomations()
            
            // Optimize timer frequency after state change
            optimizeTimerFrequency()
        }
    }
    
    func updateAutomationProgress(_ automationId: String, progress: Double) {
        if let index = automations.firstIndex(where: { $0.id == automationId }) {
            DispatchQueue.main.async {
                self.automations[index].progress = progress
                self.objectWillChange.send()
            }
        }
    }
    
    func startAutomation(_ automation: Automation) {
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            DispatchQueue.main.async { self.automations[index].updateState(.active) }
            
            // TODO: Trigger actual automation execution
            simulateAutomationExecution(automation)
            
            // Optimize timer frequency for active automation
            optimizeTimerFrequency()
        }
    }
    
    func stopAutomation(_ automation: Automation) {
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            DispatchQueue.main.async { self.automations[index].updateState(.completed) }
            
            // Optimize timer frequency after stopping automation
            optimizeTimerFrequency()
        }
    }
    
    func recordAutomationFailure(_ automationId: String, error: String) {
        if let index = automations.firstIndex(where: { $0.id == automationId }) {
            automations[index].recordFailure(errorMessage: error)
        }
    }
    
    // MARK: - Data Management
    
    private func loadMockAutomations() {
        var mockAutomations = [
            Automation(
                id: "auto1",
                name: "Morning Sunrise",
                isEnabled: true,
                scheduleTime: DateComponents(hour: 7, minute: 0),
                devices: ["1"],
                automationType: .sunrise,
                duration: 1800 // 30 minutes
            ),
            Automation(
                id: "auto2",
                name: "Evening Wind Down",
                isEnabled: false,
                scheduleTime: DateComponents(hour: 21, minute: 30),
                devices: ["1", "2"],
                automationType: .sunset,
                duration: 3600 // 1 hour
            ),
            Automation(
                id: "auto3",
                name: "Focus Mode",
                isEnabled: true,
                scheduleTime: DateComponents(hour: 9, minute: 15),
                devices: ["1", "3"],
                automationType: .focus,
                duration: 7200 // 2 hours
            ),
            Automation(
                id: "auto4",
                name: "Relaxation",
                isEnabled: true,
                scheduleTime: DateComponents(hour: 20, minute: 0),
                devices: ["2"],
                automationType: .relax,
                duration: 5400 // 1.5 hours
            )
        ]
        
        // Add some execution history for demo purposes
        mockAutomations[0].executionHistory.append(
            AutomationExecutionResult(state: .completed, duration: 1800, affectedDevices: ["1"])
        )
        
        mockAutomations[2].updateState(.active, progress: 0.3) // Simulate running automation
        
        // Simulate a failed automation
        mockAutomations.append(
            Automation(
                id: "auto5",
                name: "Sleep Mode",
                isEnabled: true,
                scheduleTime: DateComponents(hour: 22, minute: 30),
                devices: ["1", "2", "3"],
                automationType: .sunset,
                duration: 2700 // 45 minutes
            )
        )
        mockAutomations[4].recordFailure(errorMessage: "Device offline")
        
        automations = mockAutomations
    }
    
    private func saveAutomations() {
        // TODO: Implement Core Data persistence
        // For now, just trigger a UI update
        objectWillChange.send()
    }
    
    private func simulateAutomationExecution(_ automation: Automation) {
        // TODO: Implement actual automation execution logic
        // This would integrate with WLED API to control devices
        print("Starting automation: \(automation.name)")
    }
    
    // MARK: - Computed Properties
    
    var activeAutomations: [Automation] {
        automations.filter { $0.currentState == .active }
    }
    
    var pendingAutomations: [Automation] {
        automations.filter { $0.currentState == .pending && $0.isEnabled }
    }
    
    var enabledAutomations: [Automation] {
        automations.filter { $0.isEnabled }
    }
    
    var nextUpcomingAutomation: Automation? {
        let upcoming = pendingAutomations
            .compactMap { automation -> (Automation, Date)? in
                guard let nextDate = automation.nextExecutionDate else { return nil }
                return (automation, nextDate)
            }
            .sorted { $0.1 < $1.1 }
            .first
        
        return upcoming?.0
    }
} 