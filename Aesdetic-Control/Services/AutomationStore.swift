import Foundation
import Combine
import os.log

@MainActor
class AutomationStore: ObservableObject {
    static let shared = AutomationStore()
    
    @Published var automations: [Automation] = []
    
    private let fileURL: URL
    private var schedulerTimer: Timer?
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "AutomationStore")
    
    private init() {
        // Store in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documentsPath.appendingPathComponent("automations.json")
        
        load()
        scheduleNext()
    }
    
    deinit {
        schedulerTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func add(_ automation: Automation) {
        automations.append(automation)
        save()
        scheduleNext()
        logger.info("Added automation: \(automation.name)")
    }
    
    func update(_ automation: Automation) {
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[index] = automation
            save()
            scheduleNext()
            logger.info("Updated automation: \(automation.name)")
        }
    }
    
    func delete(id: UUID) {
        if let index = automations.firstIndex(where: { $0.id == id }) {
            let automation = automations[index]
            automations.remove(at: index)
            save()
            scheduleNext()
            logger.info("Deleted automation: \(automation.name)")
        }
    }
    
    func applyAutomation(_ automation: Automation) {
        logger.info("Applying automation: \(automation.name)")
        
        // Find the scene
        let scenesStore = ScenesStore.shared
        guard let scene = scenesStore.scenes.first(where: { $0.id == automation.sceneId }) else {
            logger.error("Scene not found for automation: \(automation.sceneId)")
            return
        }
        
        // Find the device
        let viewModel = DeviceControlViewModel.shared
        guard let device = viewModel.devices.first(where: { $0.id == automation.deviceId }) else {
            logger.error("Device not found for automation: \(automation.deviceId)")
            return
        }
        
        // Apply the scene
        Task {
            await viewModel.applyScene(scene, to: device)
        }
        
        // Update last triggered
        var updatedAutomation = automation
        updatedAutomation.lastTriggered = Date()
        update(updatedAutomation)
    }
    
    // MARK: - Private Methods
    
    private func scheduleNext() {
        schedulerTimer?.invalidate()
        
        guard !automations.isEmpty else { return }
        
        // Find the next automation to trigger
        let now = Date()
        let nextAutomations = automations.compactMap { automation -> (Automation, Date)? in
            guard automation.enabled,
                  let nextDate = automation.nextTriggerDate else { return nil }
            return (automation, nextDate)
        }
        
        guard let (nextAutomation, nextDate) = nextAutomations.min(by: { $0.1 < $1.1 }) else { return }
        
        let timeInterval = nextDate.timeIntervalSince(now)
        
        logger.info("Scheduling next automation '\(nextAutomation.name)' in \(timeInterval) seconds")
        
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.triggerAutomation(nextAutomation)
            }
        }
    }
    
    private func triggerAutomation(_ automation: Automation) {
        logger.info("Triggering automation: \(automation.name)")
        
        applyAutomation(automation)
        
        // Schedule the next automation
        scheduleNext()
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            automations = try JSONDecoder().decode([Automation].self, from: data)
            logger.info("Loaded \(self.automations.count) automations")
        } catch {
            // File doesn't exist on first launch - this is expected, not an error
            let nsError = error as NSError
            // NSFileReadNoSuchFileError = 260 (file not found)
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 260 {
                logger.debug("No automations file found (first launch) - will create on save")
            } else {
                logger.error("Failed to load automations: \(error.localizedDescription)")
            }
            automations = []
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(automations)
            try data.write(to: fileURL)
            logger.info("Saved \(self.automations.count) automations")
        } catch {
            logger.error("Failed to save automations: \(error.localizedDescription)")
        }
    }
}
