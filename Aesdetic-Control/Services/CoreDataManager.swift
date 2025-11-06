import Foundation
import CoreData
import os.log

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()
    
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "CoreData")
    
    // MARK: - Core Data Stack
    
    lazy var persistentContainer: NSPersistentContainer = {
        // First, try the standard approach which should work in most cases
        let container = NSPersistentContainer(name: "AesdeticControl")
        
        // Configure for better performance
        let description = container.persistentStoreDescriptions.first
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true
        
        // Enable persistent history tracking for better multi-context coordination
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("❌ Core Data loading error: \(error.localizedDescription)")
                print("Error details: \(error.userInfo)")
                
                // For now, we'll continue without Core Data rather than crash
                // In a production app, we might want to create an in-memory store as fallback
                #if DEBUG
                print("⚠️ Continuing without persistent storage. App functionality will be limited.")
                #endif
            } else {
                print("✅ Core Data loaded successfully")
            }
        }
        
        // Configure automatic merging from remote notifications
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        return container
    }()
    
    // Background context for heavy operations
    lazy var backgroundContext: NSManagedObjectContext = {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // MARK: - Performance Optimized Save Operations
    
    func saveContext() async {
        let context = viewContext
        
        guard context.hasChanges else { return }
        
        await context.perform {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Core Data save error: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    func saveInBackground() async {
        let context = backgroundContext
        
        guard context.hasChanges else { return }
        
        await context.perform {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Core Data background save error: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // MARK: - Device Management - Performance Optimized
    
    /// Save a device using optimized background context
    func saveDevice(_ device: WLEDDevice) async {
        await performBackgroundSave { context in
            let deviceEntity = WLEDDeviceEntity.findOrCreate(for: device.id, in: context)
            deviceEntity.updateFromDevice(device)
        }
    }
    
    /// Save multiple devices efficiently in a single transaction
    func saveDevices(_ devices: [WLEDDevice]) async {
        await performBackgroundSave { context in
            for device in devices {
                let deviceEntity = WLEDDeviceEntity.findOrCreate(for: device.id, in: context)
                deviceEntity.updateFromDevice(device)
            }
        }
    }
    
    /// Fetch all devices from Core Data
    func fetchDevices() async -> [WLEDDevice] {
        await viewContext.perform {
            let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
            do {
                let entities = try self.viewContext.fetch(request)
                return entities.compactMap { $0.toWLEDDevice() }
            } catch {
                self.logger.error("Failed to fetch devices: \\(error)")
                return []
            }
        }
    }
    
    /// Delete a device by ID
    func deleteDevice(id: String) async {
        await performBackgroundSave { context in
            let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            
            do {
                let entities = try context.fetch(request)
                for entity in entities {
                    context.delete(entity)
                }
            } catch {
                self.logger.error("Failed to delete device \\(id): \\(error)")
            }
        }
    }
    
    // MARK: - Batch Operations for Performance
    
    private func performBackgroundSave(_ operation: @escaping (NSManagedObjectContext) -> Void) async {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        await context.perform {
            operation(context)
            
            guard context.hasChanges else { return }
            
            do {
                try context.save()
            } catch {
                print("Background save error: \(error)")
            }
        }
    }
    
    private func performBatchBackgroundSave(_ operation: @escaping (NSManagedObjectContext) -> Void) async {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        await context.perform {
            // Perform batch operation
            operation(context)
            
            guard context.hasChanges else { return }
            
            do {
                try context.save()
                
                // Reduce memory pressure by resetting context after batch operation
                context.reset()
            } catch {
                print("Batch save error: \(error)")
            }
        }
    }
    
    // MARK: - Memory Management
    
    func clearMemoryCache() {
        viewContext.refreshAllObjects()
        backgroundContext.reset()
    }
    
    // MARK: - Statistics with Optimized Queries
    
    func getDeviceStatistics() async -> (total: Int, online: Int, offline: Int) {
        return await withCheckedContinuation { continuation in
            viewContext.perform {
                let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
                request.propertiesToFetch = ["isOnline"] // Only fetch needed properties
                
                do {
                    let devices = try self.viewContext.fetch(request)
                    let total = devices.count
                    let online = devices.filter { $0.isOnline }.count
                    let offline = total - online
                    
                    continuation.resume(returning: (total: total, online: online, offline: offline))
                } catch {
                    print("Error fetching device statistics: \(error)")
                    continuation.resume(returning: (total: 0, online: 0, offline: 0))
                }
            }
        }
    }
} 