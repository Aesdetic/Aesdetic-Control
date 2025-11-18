import Foundation
import SwiftUI
import Combine

/// Comprehensive resource and memory management system
@MainActor
class ResourceManager: ObservableObject {
    static let shared = ResourceManager()
    
    // MARK: - Memory Management
    @Published var memoryUsage: Double = 0.0
    @Published var isLowMemoryWarning: Bool = false
    
    // MARK: - Cache Management
    private let maxCacheAge: TimeInterval = 300 // 5 minutes
    private let maxCacheSize: Int = 100 // Maximum cache entries
    
    // MARK: - Performance Monitoring
    @Published var averageFrameTime: Double = 0.0
    @Published var isPerformanceOptimized: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    private var memoryTimer: Timer?
    private var performanceTimer: Timer?
    
    // MARK: - Resource Cleanup Handlers
    private var cleanupHandlers: [String: () -> Void] = [:]
    
    private init() {
        setupMemoryMonitoring()
        setupPerformanceMonitoring()
        setupAppLifecycleHandlers()
    }
    
    deinit {
        memoryTimer?.invalidate()
        performanceTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Memory Monitoring
    
    private func setupMemoryMonitoring() {
        // Monitor memory usage every 30 seconds
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
        
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }
    
    private func updateMemoryUsage() {
        let usage = getMemoryUsage()
        DispatchQueue.main.async {
            self.memoryUsage = usage
            
            // Trigger cleanup if memory usage is high
            if usage > 80.0 { // 80% threshold
                self.performMemoryCleanup()
            }
        }
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedBytes = info.resident_size
            let totalBytes = ProcessInfo.processInfo.physicalMemory
            return Double(usedBytes) / Double(totalBytes) * 100.0
        }
        
        return 0.0
    }
    
    private func handleMemoryWarning() {
        #if DEBUG
        print("⚠️ Memory Warning Received - Performing Emergency Cleanup")
        #endif
        isLowMemoryWarning = true
        
        // Immediate cleanup
        performEmergencyCleanup()
        
        // Reset warning after 10 seconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self.isLowMemoryWarning = false
        }
    }
    
    // MARK: - Performance Monitoring
    
    private func setupPerformanceMonitoring() {
        // Monitor performance every 60 seconds
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePerformanceMetrics()
            }
        }
    }
    
    private func updatePerformanceMetrics() {
        Task {
        // Simple performance heuristic based on memory usage and cache size
        let memoryScore = max(0, 100 - memoryUsage)
            let cacheScore = await getCacheEfficiencyScore()
        
        let overallScore = (memoryScore + cacheScore) / 2
        
        DispatchQueue.main.async {
            self.isPerformanceOptimized = overallScore > 70
            
            if !self.isPerformanceOptimized {
                self.performPerformanceOptimization()
                }
            }
        }
    }
    
    private func getCacheEfficiencyScore() async -> Double {
        // Evaluate cache efficiency across all services
        let apiCacheSize = await WLEDAPIService.shared.getCacheSize()
        let coreDataCacheSize = CoreDataManager.shared.getContextSize()
        
        // Score based on cache size vs optimal size
        let totalCacheSize = apiCacheSize + coreDataCacheSize
        if totalCacheSize < maxCacheSize {
            return 100.0
        } else {
            return max(0, 100.0 - Double(totalCacheSize - maxCacheSize))
        }
    }
    
    // MARK: - App Lifecycle Management
    
    private func setupAppLifecycleHandlers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidEnterBackground()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWillEnterForeground()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWillTerminate()
            }
        }
    }
    
    private func handleAppDidEnterBackground() {
        #if DEBUG
        print("📱 App entering background - Optimizing resources")
        #endif
        
        // Pause non-essential timers
        Task { @MainActor in
            pauseNonEssentialOperations()
        }
        
        // Perform background cleanup
        Task { @MainActor in
            performBackgroundCleanup()
        }
    }
    
    @MainActor private func handleAppWillEnterForeground() {
        #if DEBUG
        print("📱 App entering foreground - Resuming operations")
        #endif
        
        // Resume operations
        Task { @MainActor in
            resumeOperations()
        }
        
        // Check if cleanup is needed after background time
        if memoryUsage > 60.0 {
            performMemoryCleanup()
        }
    }
    
    private func handleAppWillTerminate() {
        #if DEBUG
        print("📱 App terminating - Final cleanup")
        #endif
        Task { @MainActor in
            performFinalCleanup()
        }
    }
    
    // MARK: - Cleanup Operations
    
    func registerCleanupHandler(identifier: String, handler: @escaping () -> Void) {
        cleanupHandlers[identifier] = handler
    }
    
    func unregisterCleanupHandler(identifier: String) {
        cleanupHandlers.removeValue(forKey: identifier)
    }
    
    @MainActor private func performMemoryCleanup() {
        #if DEBUG
        print("🧹 Performing memory cleanup")
        #endif
        
        // Core Data cleanup
        CoreDataManager.shared.clearMemoryCache()
        
        // API cache cleanup
        Task {
            await WLEDAPIService.shared.clearCache()
        }
        
        // WebSocket cleanup
        WLEDWebSocketManager.shared.cleanupInactiveConnections()
        
        // Run registered cleanup handlers
        for (identifier, handler) in cleanupHandlers {
            #if DEBUG
            print("Running cleanup handler: \(identifier)")
            #endif
            handler()
        }
        
        // System cleanup
        URLCache.shared.removeAllCachedResponses()
        
        // Force garbage collection hint
        autoreleasepool {
            // Empty autoreleasepool to encourage cleanup
        }
    }
    
    private func performEmergencyCleanup() {
        #if DEBUG
        print("🚨 Emergency cleanup - Freeing maximum memory")
        #endif
        
        // Aggressive memory cleanup
        Task { @MainActor in
            performMemoryCleanup()
        }
        
        // Additional emergency measures
        CoreDataManager.shared.backgroundContext.reset()
        
        // Clear all caches aggressively
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 50 * 1024 * 1024 // Restore after cleanup
        URLCache.shared.memoryCapacity = 10 * 1024 * 1024
    }
    
    @MainActor private func performBackgroundCleanup() {
        // Lightweight cleanup for background state
        performMemoryCleanup()
        
        // Reduce memory footprint
        CoreDataManager.shared.clearMemoryCache()
    }
    
    @MainActor private func performPerformanceOptimization() {
        #if DEBUG
        print("⚡ Optimizing performance")
        #endif
        
        // Cache optimization
        performMemoryCleanup()
        
        // Reduce update frequencies temporarily
        NotificationCenter.default.post(name: .performanceOptimizationRequested, object: nil)
    }
    
    @MainActor private func performFinalCleanup() {
        // Cancel all timers
        memoryTimer?.invalidate()
        performanceTimer?.invalidate()
        
        // Final memory cleanup
        performMemoryCleanup()
        
        // Save any pending data
        Task {
            await CoreDataManager.shared.saveContext()
        }
    }
    
    // MARK: - Operation Control
    
    @MainActor
    private func pauseNonEssentialOperations() {
        // Pause timers in ViewModels
        DashboardViewModel.shared.pauseBackgroundOperations()
        AutomationViewModel.shared.pauseBackgroundOperations()
        
        // Reduce WebSocket activity
        WLEDWebSocketManager.shared.pauseBackgroundOperations()
    }
    
    @MainActor
    private func resumeOperations() {
        // Resume timers
        DashboardViewModel.shared.resumeBackgroundOperations()
        AutomationViewModel.shared.resumeBackgroundOperations()
        
        // Resume WebSocket activity
        WLEDWebSocketManager.shared.resumeBackgroundOperations()
    }
    
    // MARK: - Public Interface
    
    func forceCleanup() {
        Task { @MainActor in
            performMemoryCleanup()
        }
    }
    
    func getResourceReport() async -> (memoryUsage: Double, cacheSize: Int, isOptimized: Bool) {
        let cacheSize = await WLEDAPIService.shared.getCacheSize()
        return (
            memoryUsage: memoryUsage,
            cacheSize: cacheSize,
            isOptimized: isPerformanceOptimized
        )
    }
}

// MARK: - Protocol for Cleanup Capable Services

protocol CleanupCapable {
    func clearCache() async
    func getCacheSize() async -> Int
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let performanceOptimizationRequested = Notification.Name("performanceOptimizationRequested")
    static let memoryWarningHandled = Notification.Name("memoryWarningHandled")
}

// MARK: - Core Data Manager Extension

extension CoreDataManager {
    func getContextSize() -> Int {
        return viewContext.registeredObjects.count
    }
}

// MARK: - WebSocket Manager Extension  

extension WLEDWebSocketManager {
    func cleanupInactiveConnections() {
        // Clean up inactive WebSocket connections
        // This is handled automatically by the connection management system
    }
    
    func pauseBackgroundOperations() {
        // Pause non-essential WebSocket operations
        // WebSocket connections are maintained but health checks are reduced
    }
    
    func resumeBackgroundOperations() {
        // Resume WebSocket operations
        // Full health check frequency is restored
    }
}

// MARK: - ViewModel Extensions

extension DashboardViewModel {
    func pauseBackgroundOperations() {
        // Pause non-essential operations when in background
        // Implemented in DashboardViewModel if needed
    }
    
    func resumeBackgroundOperations() {
        // Resume operations when returning to foreground
        // Implemented in DashboardViewModel if needed
    }
}

extension AutomationViewModel {
    func pauseBackgroundOperations() {
        // Pause automation monitoring when in background
        // AutomationStore handles this internally
    }
    
    func resumeBackgroundOperations() {
        // Resume automation monitoring
        // AutomationStore handles this internally
    }
} 
