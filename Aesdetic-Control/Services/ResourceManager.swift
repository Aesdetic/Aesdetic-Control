import Foundation
import UIKit
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
        print("⚠️ Memory Warning Received - Performing Emergency Cleanup")
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
        // Simple performance heuristic based on memory usage and cache size
        let memoryScore = max(0, 100 - memoryUsage)
        let cacheScore = getCacheEfficiencyScore()
        
        let overallScore = (memoryScore + cacheScore) / 2
        
        DispatchQueue.main.async {
            self.isPerformanceOptimized = overallScore > 70
            
            if !self.isPerformanceOptimized {
                self.performPerformanceOptimization()
            }
        }
    }
    
    private func getCacheEfficiencyScore() -> Double {
        // Evaluate cache efficiency across all services
        let apiCacheSize = WLEDAPIService.shared.getCacheSize()
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
        print("📱 App entering background - Optimizing resources")
        
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
        print("📱 App entering foreground - Resuming operations")
        
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
        print("📱 App terminating - Final cleanup")
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
        print("🧹 Performing memory cleanup")
        
        // Core Data cleanup
        CoreDataManager.shared.clearMemoryCache()
        
        // API cache cleanup
        WLEDAPIService.shared.clearCache()
        
        // WebSocket cleanup
        WLEDWebSocketManager.shared.cleanupInactiveConnections()
        
        // Run registered cleanup handlers
        for (identifier, handler) in cleanupHandlers {
            print("Running cleanup handler: \(identifier)")
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
        print("🚨 Emergency cleanup - Freeing maximum memory")
        
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
        print("⚡ Optimizing performance")
        
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
    
    func getResourceReport() -> (memoryUsage: Double, cacheSize: Int, isOptimized: Bool) {
        return (
            memoryUsage: memoryUsage,
            cacheSize: getCacheSize(),
            isOptimized: isPerformanceOptimized
        )
    }
    
    private func getCacheSize() -> Int {
        return cleanupHandlers.count // Simplified cache size metric
    }
}

// MARK: - Protocol for Cleanup Capable Services

protocol CleanupCapable {
    func clearCache()
    func getCacheSize() -> Int
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
        // Implementation depends on connection tracking
    }
    
    func pauseBackgroundOperations() {
        // Pause non-essential WebSocket operations
    }
    
    func resumeBackgroundOperations() {
        // Resume WebSocket operations
    }
}

// MARK: - ViewModel Extensions

extension DashboardViewModel {
    func pauseBackgroundOperations() {
        // Pause greeting rotation timer when in background
    }
    
    func resumeBackgroundOperations() {
        // Resume greeting rotation timer
    }
}

extension AutomationViewModel {
    func pauseBackgroundOperations() {
        // Pause automation monitoring when in background
    }
    
    func resumeBackgroundOperations() {
        // Resume automation monitoring
    }
} 
