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
                #if DEBUG
                print("❌ Core Data loading error: \(error.localizedDescription)")
                print("Error details: \(error.userInfo)")
                #endif
                
                // For now, we'll continue without Core Data rather than crash
                // In a production app, we might want to create an in-memory store as fallback
                #if DEBUG
                print("⚠️ Continuing without persistent storage. App functionality will be limited.")
                #endif
            } else {
                #if DEBUG
                print("✅ Core Data loaded successfully")
                #endif
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

    private lazy var deviceWriteContext: NSManagedObjectContext = {
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
                #if DEBUG
                print("Core Data save error: \(nsError), \(nsError.userInfo)")
                #endif
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
                #if DEBUG
                print("Core Data background save error: \(nsError), \(nsError.userInfo)")
                #endif
            }
        }
    }
    
    // MARK: - Device Management - Performance Optimized
    
    /// Save a device using optimized background context
    func saveDevice(_ device: WLEDDevice) async {
        let normalizedDevice = WLEDDeviceIdentity.normalized(device)
        await performDeviceSave { context in
            let deviceEntity = WLEDDeviceEntity.findOrCreate(for: normalizedDevice.id, in: context)
            deviceEntity.updateFromDevice(normalizedDevice)
        }
    }
    
    /// Save multiple devices efficiently in a single transaction
    func saveDevices(_ devices: [WLEDDevice]) async {
        let reconciledDevices = WLEDDeviceIdentity.reconciledDevices(devices)
        await performDeviceSave { context in
            for device in reconciledDevices {
                let deviceEntity = WLEDDeviceEntity.findOrCreate(for: device.id, in: context)
                deviceEntity.updateFromDevice(device)
            }
        }
    }
    
    /// Fetch all devices from Core Data
    func fetchDevices() async -> [WLEDDevice] {
        let context = viewContext
        let logger = logger
        return await context.perform {
            let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
            do {
                let entities = try context.fetch(request)
                return Self.reconcileDeviceEntities(entities, in: context, logger: logger)
            } catch {
                logger.error("Failed to fetch devices: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }
    
    /// Synchronously fetch all devices (used to avoid UI flicker on launch)
    func fetchDevicesSync() -> [WLEDDevice] {
        var result: [WLEDDevice] = []
        let context = viewContext
        let logger = logger
        context.performAndWait {
            let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
            do {
                let entities = try context.fetch(request)
                result = Self.reconcileDeviceEntities(entities, in: context, logger: logger)
            } catch {
                logger.error("Failed to fetch devices (sync): \(error.localizedDescription, privacy: .public)")
                result = []
            }
        }
        return result
    }

    /// Fetch a single device by ID (MAC address).
    func fetchDevice(id: String) async -> WLEDDevice? {
        let context = viewContext
        let logger = logger
        return await context.perform {
            let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
            do {
                let entities = try context.fetch(request)
                return Self.reconcileDeviceEntities(entities, in: context, logger: logger)
                    .first(where: { WLEDDeviceIdentity.matches($0.id, id) })
            } catch {
                logger.error("Failed to fetch device \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
    
    /// Delete a device by ID
    func deleteDevice(id: String) async {
        await performDeviceSave { context in
            let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
            
            do {
                let entities = try context.fetch(request).filter {
                    WLEDDeviceIdentity.matches($0.id, id)
                }
                for entity in entities {
                    context.delete(entity)
                }
            } catch {
                self.logger.error("Failed to delete device \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Wellness Entries

    func fetchWellnessEntry(for date: Date) async -> WellnessEntrySnapshot? {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let context = viewContext
        let logger = logger
        return await context.perform {
            let request: NSFetchRequest<WellnessEntryEntity> = WellnessEntryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "date == %@", normalizedDate as NSDate)
            request.fetchLimit = 1

            do {
                let entity = try context.fetch(request).first
                return entity?.toSnapshot()
            } catch {
                logger.error("Failed to fetch wellness entry: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func fetchWellnessEntries(limit: Int? = nil) async -> [WellnessEntrySnapshot] {
        let context = viewContext
        let logger = logger
        return await context.perform {
            let request: NSFetchRequest<WellnessEntryEntity> = WellnessEntryEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            if let limit {
                request.fetchLimit = limit
            }
            do {
                let entities = try context.fetch(request)
                return entities.map { $0.toSnapshot() }
            } catch {
                logger.error("Failed to fetch wellness entries: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    func fetchWellnessEntries(from startDate: Date, to endDate: Date) async -> [WellnessEntrySnapshot] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let context = viewContext
        let logger = logger
        return await context.perform {
            let request: NSFetchRequest<WellnessEntryEntity> = WellnessEntryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            do {
                let entities = try context.fetch(request)
                return entities.map { $0.toSnapshot() }
            } catch {
                logger.error("Failed to fetch wellness entries by range: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    func saveWellnessEntry(_ entry: WellnessEntrySnapshot) async {
        var normalizedEntry = entry
        normalizedEntry.date = Calendar.current.startOfDay(for: entry.date)
        normalizedEntry.updatedAt = Date()

        await performBackgroundSave { context in
            let entity = WellnessEntryEntity.findOrCreate(for: normalizedEntry.date, in: context)
            entity.update(from: normalizedEntry)
        }
    }
    
    // MARK: - Batch Operations for Performance

    private func performDeviceSave(_ operation: @escaping (NSManagedObjectContext) -> Void) async {
        let context = deviceWriteContext
        let logger = logger

        await context.perform {
            operation(context)

            guard context.hasChanges else { return }

            do {
                try context.save()
            } catch {
                logger.error("Device save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func reconcileDeviceEntities(
        _ entities: [WLEDDeviceEntity],
        in context: NSManagedObjectContext,
        logger: Logger
    ) -> [WLEDDevice] {
        let records = entities.compactMap { entity -> (WLEDDeviceEntity, WLEDDevice)? in
            guard let device = entity.toWLEDDevice() else { return nil }
            return (entity, device)
        }
        let reconciled = WLEDDeviceIdentity.reconciledDevices(records.map(\.1))
        let entitiesByIdentity = Dictionary(grouping: records, by: {
            WLEDDeviceIdentity.deduplicationKey(for: $0.1.id)
        })

        for device in reconciled {
            let key = WLEDDeviceIdentity.deduplicationKey(for: device.id)
            guard let matchingRecords = entitiesByIdentity[key],
                  let keeper = matchingRecords.max(by: { $0.1.lastSeen < $1.1.lastSeen })?.0 else {
                continue
            }

            if matchingRecords.count > 1 || keeper.id != device.id {
                keeper.id = device.id
                keeper.updateFromDevice(device)
                for duplicate in matchingRecords.map(\.0) where duplicate != keeper {
                    context.delete(duplicate)
                }
                logger.info("Reconciled \(matchingRecords.count, privacy: .public) records for device \(device.id, privacy: .public)")
            }
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                logger.error("Failed to reconcile duplicate devices: \(error.localizedDescription, privacy: .public)")
            }
        }
        return reconciled
    }
    
    private func performBackgroundSave(_ operation: @escaping (NSManagedObjectContext) -> Void) async {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        await context.perform {
            operation(context)
            
            guard context.hasChanges else { return }
            
            do {
                try context.save()
            } catch {
                #if DEBUG
                print("Background save error: \(error)")
                #endif
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
                #if DEBUG
                print("Batch save error: \(error)")
                #endif
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
        let context = viewContext
        return await withCheckedContinuation { continuation in
            context.perform {
                let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
                request.propertiesToFetch = ["isOnline"] // Only fetch needed properties
                
                do {
                    let devices = try context.fetch(request)
                    let total = devices.count
                    let online = devices.filter { $0.isOnline }.count
                    let offline = total - online
                    
                    continuation.resume(returning: (total: total, online: online, offline: offline))
                } catch {
                    #if DEBUG
                    print("Error fetching device statistics: \(error)")
                    #endif
                    continuation.resume(returning: (total: 0, online: 0, offline: 0))
                }
            }
        }
    }
} 
