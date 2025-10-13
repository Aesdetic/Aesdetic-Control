import Foundation

struct Automation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var enabled: Bool
    var time: String  // "HH:mm" format
    var weekdays: [Bool]  // 7 elements, Sunday through Saturday
    var sceneId: UUID
    var deviceId: String
    var createdAt: Date
    var lastTriggered: Date?
    
    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        time: String,
        weekdays: [Bool] = Array(repeating: false, count: 7),
        sceneId: UUID,
        deviceId: String,
        createdAt: Date = Date(),
        lastTriggered: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.time = time
        self.weekdays = weekdays
        self.sceneId = sceneId
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.lastTriggered = lastTriggered
    }
    
    // Helper computed properties
    var weekdaysString: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let selectedDays = weekdays.enumerated().compactMap { index, isSelected in
            isSelected ? dayNames[index] : nil
        }
        return selectedDays.isEmpty ? "Never" : selectedDays.joined(separator: ", ")
    }
    
    var nextTriggerDate: Date? {
        guard enabled else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Parse time
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }
        
        // Find next matching weekday
        for dayOffset in 0..<7 {
            let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            let weekday = calendar.component(.weekday, from: candidateDate) - 1 // Convert to 0-6 (Sun-Sat)
            
            if weekdays[weekday] {
                var components = calendar.dateComponents([.year, .month, .day], from: candidateDate)
                components.hour = hour
                components.minute = minute
                components.second = 0
                
                if let triggerDate = calendar.date(from: components) {
                    // Only return if it's in the future
                    if triggerDate > now {
                        return triggerDate
                    }
                }
            }
        }
        
        return nil
    }
}