//
//  Automation.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import SwiftUI

// MARK: - Automation Execution State
enum AutomationExecutionState: String, Codable, CaseIterable {
    case pending = "pending"
    case active = "active"
    case completed = "completed"
    case failed = "failed"
    case disabled = "disabled"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .active: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .disabled: return "Disabled"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .orange
        case .active: return .blue
        case .completed: return .green
        case .failed: return .red
        case .disabled: return .gray
        }
    }
    
    var systemImage: String {
        switch self {
        case .pending: return "clock.fill"
        case .active: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .disabled: return "pause.circle.fill"
        }
    }
}

// MARK: - Automation Execution Result
struct AutomationExecutionResult: Codable {
    let timestamp: Date
    let state: AutomationExecutionState
    let duration: TimeInterval?
    let errorMessage: String?
    let affectedDevices: [String]
    
    init(state: AutomationExecutionState, duration: TimeInterval? = nil, errorMessage: String? = nil, affectedDevices: [String] = []) {
        self.timestamp = Date()
        self.state = state
        self.duration = duration
        self.errorMessage = errorMessage
        self.affectedDevices = affectedDevices
    }
}

struct Automation: Identifiable, Codable {
    let id: String
    var name: String
    var isEnabled: Bool
    var scheduleTime: DateComponents
    var devices: [String] // Device IDs
    var automationType: AutomationType
    var gradient: ColorGradient?
    var duration: TimeInterval // in seconds
    var createdAt: Date
    var lastTriggered: Date?
    
    // Enhanced status tracking
    var currentState: AutomationExecutionState
    var progress: Double // 0.0 to 1.0 for running automations
    var executionHistory: [AutomationExecutionResult]
    var nextExecutionDate: Date?
    var estimatedCompletionTime: Date?
    
    init(id: String, name: String, isEnabled: Bool = true, scheduleTime: DateComponents, devices: [String], automationType: AutomationType = .custom, gradient: ColorGradient? = nil, duration: TimeInterval = 1800) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.scheduleTime = scheduleTime
        self.devices = devices
        self.automationType = automationType
        self.gradient = gradient
        self.duration = duration
        self.createdAt = Date()
        self.lastTriggered = nil
        
        // Initialize enhanced status
        self.currentState = isEnabled ? .pending : .disabled
        self.progress = 0.0
        self.executionHistory = []
        self.nextExecutionDate = nil
        self.estimatedCompletionTime = nil
        
        // Calculate next execution date
        self.calculateNextExecution()
    }
    
    var nextTriggerTime: Date? {
        return nextExecutionDate
    }
    
    var lastExecutionResult: AutomationExecutionResult? {
        return executionHistory.last
    }
    
    var timeUntilNextExecution: TimeInterval? {
        guard let nextDate = nextExecutionDate else { return nil }
        return nextDate.timeIntervalSinceNow
    }
    
    var timeUntilCompletion: TimeInterval? {
        guard currentState == .active,
              let completionTime = estimatedCompletionTime else { return nil }
        return max(0, completionTime.timeIntervalSinceNow)
    }
    
    // MARK: - Status Management Methods
    
    mutating func updateState(_ newState: AutomationExecutionState, progress: Double = 0.0) {
        self.currentState = newState
        self.progress = progress
        
        if newState == .active {
            self.estimatedCompletionTime = Date().addingTimeInterval(duration)
        } else {
            self.estimatedCompletionTime = nil
        }
        
        // Add to execution history for significant state changes
        if newState != .pending {
            let result = AutomationExecutionResult(
                state: newState,
                duration: newState == .completed ? duration : nil,
                affectedDevices: devices
            )
            self.executionHistory.append(result)
            
            // Keep only last 10 execution results
            if executionHistory.count > 10 {
                executionHistory.removeFirst()
            }
        }
        
        // Update next execution time
        if newState == .completed || newState == .failed {
            calculateNextExecution()
        }
    }
    
    mutating func recordFailure(errorMessage: String) {
        let result = AutomationExecutionResult(
            state: .failed,
            errorMessage: errorMessage,
            affectedDevices: devices
        )
        self.executionHistory.append(result)
        self.currentState = .failed
        self.progress = 0.0
        self.estimatedCompletionTime = nil
        
        // Schedule next execution
        calculateNextExecution()
    }
    
    private mutating func calculateNextExecution() {
        guard isEnabled else {
            self.nextExecutionDate = nil
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        guard let hour = scheduleTime.hour,
              let minute = scheduleTime.minute else {
            self.nextExecutionDate = nil
            return
        }
        
        // Create today's trigger time
        var todayTrigger = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
        
        // If today's time has passed, set for tomorrow
        if let today = todayTrigger, today <= now {
            todayTrigger = calendar.date(byAdding: .day, value: 1, to: today)
        }
        
        self.nextExecutionDate = todayTrigger
        
        // Update current state based on next execution
        if currentState != .active {
            self.currentState = .pending
        }
    }
    
    mutating func toggle() {
        isEnabled.toggle()
        if !isEnabled {
            currentState = .disabled
            nextExecutionDate = nil
            estimatedCompletionTime = nil
        } else {
            calculateNextExecution()
        }
    }
}

// MARK: - Computed Properties for UI
extension Automation {
    var timeString: String {
        guard let hour = scheduleTime.hour,
              let minute = scheduleTime.minute else { return "Invalid time" }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    var nextExecutionString: String {
        guard let nextDate = nextExecutionDate else { return "Not scheduled" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: nextDate, relativeTo: Date())
    }
    
    var statusDescription: String {
        switch currentState {
        case .pending:
            if let next = nextExecutionDate {
                let formatter = RelativeDateTimeFormatter()
                return "Next: \(formatter.localizedString(for: next, relativeTo: Date()))"
            }
            return "Scheduled"
        case .active:
            if let completion = estimatedCompletionTime {
                let remaining = completion.timeIntervalSinceNow
                if remaining > 0 {
                    return "Running (\(Int(remaining / 60))m remaining)"
                }
            }
            return "Running"
        case .completed:
            if let last = lastExecutionResult {
                let formatter = RelativeDateTimeFormatter()
                return "Completed \(formatter.localizedString(for: last.timestamp, relativeTo: Date()))"
            }
            return "Completed"
        case .failed:
            if let last = lastExecutionResult, let error = last.errorMessage {
                return "Failed: \(error)"
            }
            return "Failed"
        case .disabled:
            return "Disabled"
        }
    }
    
    var progressDescription: String {
        guard currentState == .active else { return "" }
        return "\(Int(progress * 100))% complete"
    }
}

enum AutomationType: String, CaseIterable, Codable {
    case sunrise = "sunrise"
    case sunset = "sunset"
    case focus = "focus"
    case relax = "relax"
    case sleep = "sleep"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .sunrise:
            return "Sunrise"
        case .sunset:
            return "Sunset"
        case .focus:
            return "Focus"
        case .relax:
            return "Relax"
        case .sleep:
            return "Sleep"
        case .custom:
            return "Custom"
        }
    }
    
    var systemImage: String {
        switch self {
        case .sunrise:
            return "sunrise.fill"
        case .sunset:
            return "sunset.fill"
        case .focus:
            return "brain.head.profile"
        case .relax:
            return "leaf.fill"
        case .sleep:
            return "moon.fill"
        case .custom:
            return "gear"
        }
    }
    
    var defaultGradient: ColorGradient {
        switch self {
        case .sunrise:
            return ColorGradient(
                startColor: .red,
                endColor: .yellow,
                intermediateColors: [.orange]
            )
        case .sunset:
            return ColorGradient(
                startColor: .yellow,
                endColor: .purple,
                intermediateColors: [.orange, .red]
            )
        case .focus:
            return ColorGradient(
                startColor: .blue,
                endColor: .white,
                intermediateColors: []
            )
        case .relax:
            return ColorGradient(
                startColor: .green,
                endColor: .blue,
                intermediateColors: []
            )
        case .sleep:
            return ColorGradient(
                startColor: .orange,
                endColor: .black,
                intermediateColors: [.red]
            )
        case .custom:
            return ColorGradient(
                startColor: .white,
                endColor: .white,
                intermediateColors: []
            )
        }
    }
}

struct ColorGradient: Codable {
    var startColor: Color
    var endColor: Color
    var intermediateColors: [Color]
    
    enum CodingKeys: String, CodingKey {
        case startColor
        case endColor
        case intermediateColors
    }
    
    init(startColor: Color, endColor: Color, intermediateColors: [Color] = []) {
        self.startColor = startColor
        self.endColor = endColor
        self.intermediateColors = intermediateColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startColorHex = try container.decode(String.self, forKey: .startColor)
        let endColorHex = try container.decode(String.self, forKey: .endColor)
        let intermediateHexes = try container.decode([String].self, forKey: .intermediateColors)
        
        self.startColor = Color(hex: startColorHex)
        self.endColor = Color(hex: endColorHex)
        self.intermediateColors = intermediateHexes.map { Color(hex: $0) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startColor.toHex(), forKey: .startColor)
        try container.encode(endColor.toHex(), forKey: .endColor)
        try container.encode(intermediateColors.map { $0.toHex() }, forKey: .intermediateColors)
    }
    
    var allColors: [Color] {
        return [startColor] + intermediateColors + [endColor]
    }
} 