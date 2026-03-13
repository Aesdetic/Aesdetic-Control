import Foundation
import CoreData
import SwiftUI

private func encodeNameMap(_ map: [Int: String]?) -> String? {
    guard let map, !map.isEmpty else { return nil }
    let stringKeyed = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
    guard let data = try? JSONEncoder().encode(stringKeyed),
          let json = String(data: data, encoding: .utf8) else {
        return nil
    }
    return json
}

private func decodeNameMap(_ json: String?) -> [Int: String]? {
    guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
    guard let stringKeyed = try? JSONDecoder().decode([String: String].self, from: data) else {
        return nil
    }
    var map: [Int: String] = [:]
    map.reserveCapacity(stringKeyed.count)
    for (key, value) in stringKeyed {
        guard let id = Int(key) else { continue }
        map[id] = value
    }
    return map.isEmpty ? nil : map
}

// MARK: - WLEDDeviceEntity
@objc(WLEDDeviceEntity)
public class WLEDDeviceEntity: NSManagedObject {
    
}

extension WLEDDeviceEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WLEDDeviceEntity> {
        return NSFetchRequest<WLEDDeviceEntity>(entityName: "WLEDDeviceEntity")
    }
    
    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var ipAddress: String
    @NSManaged public var isOnline: Bool
    @NSManaged public var brightness: Int16
    @NSManaged public var currentColorHex: String
    @NSManaged public var autoWhiteMode: Int16
    @NSManaged public var productType: String
    @NSManaged public var location: String
    @NSManaged public var lastSeen: Date
    @NSManaged public var presetNamesJSON: String?
    @NSManaged public var playlistNamesJSON: String?
    @NSManaged public var state: WLEDStateEntity?
    
    // MARK: - Core Data Helper Methods
    
    /// Find existing entity or create new one
    static func findOrCreate(for deviceId: String, in context: NSManagedObjectContext) -> WLEDDeviceEntity {
        let request: NSFetchRequest<WLEDDeviceEntity> = WLEDDeviceEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", deviceId)
        request.fetchLimit = 1
        
        do {
            let existing = try context.fetch(request)
            if let entity = existing.first {
                return entity
            }
        } catch {
            #if DEBUG
            print("Error finding device entity: \(error)")
            #endif
        }
        
        // Create new entity
        let entity = WLEDDeviceEntity(context: context)
        entity.id = deviceId
        return entity
    }
    
    /// Update entity properties from WLEDDevice
    func updateFromDevice(_ device: WLEDDevice) {
        self.name = device.name
        self.ipAddress = device.ipAddress
        self.isOnline = device.isOnline
        self.brightness = Int16(device.brightness)
        self.currentColorHex = device.currentColor.toHex()
        if let mode = device.autoWhiteMode {
            self.autoWhiteMode = Int16(mode.rawValue)
        } else {
            self.autoWhiteMode = -1
        }
        self.productType = device.productType.rawValue
        self.location = device.location.rawValue
        
        self.lastSeen = device.lastSeen
        self.presetNamesJSON = encodeNameMap(device.presetNamesById)
        self.playlistNamesJSON = encodeNameMap(device.playlistNamesById)
        
        // Handle state update
        let stateEntity = self.state ?? WLEDStateEntity(context: self.managedObjectContext!)
        if let deviceState = device.state {
            stateEntity.update(from: deviceState)
        }
        self.state = stateEntity
    }
    
    /// Convert entity to WLEDDevice
    func toWLEDDevice() -> WLEDDevice? {
        return WLEDDevice(from: self)
    }
    
    // Computed properties for easy conversion
    var brightnessInt: Int {
        get { Int(brightness) }
        set { brightness = Int16(newValue) }
    }
    
    var currentColor: Color {
        get {
            let normalized = currentColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                return WLEDDevice.wledBootDefaultColor
            }
            if normalized.uppercased() == "000000", state == nil {
                return WLEDDevice.wledBootDefaultColor
            }
            return Color(hex: normalized)
        }
        set { currentColorHex = newValue.toHex() }
    }
    
    var productTypeEnum: ProductType {
        get { ProductType(rawValue: productType) ?? .generic }
        set { productType = newValue.rawValue }
    }
    
    var locationEnum: DeviceLocation {
        get { DeviceLocation(rawValue: location) }
        set { location = newValue.rawValue }
    }
}

// MARK: - WLEDStateEntity
@objc(WLEDStateEntity)
public class WLEDStateEntity: NSManagedObject {
    
}

extension WLEDStateEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WLEDStateEntity> {
        return NSFetchRequest<WLEDStateEntity>(entityName: "WLEDStateEntity")
    }
    
    @NSManaged public var brightness: Int16
    @NSManaged public var isOn: Bool
    @NSManaged public var transitionDeciseconds: NSNumber?
    @NSManaged public var device: WLEDDeviceEntity?
    @NSManaged public var segments: NSSet?
    
    // Computed properties
    var brightnessInt: Int {
        get { Int(brightness) }
        set { brightness = Int16(newValue) }
    }

    var transitionDecisecondsInt: Int? {
        transitionDeciseconds?.intValue
    }
    
    var segmentsArray: [WLEDSegmentEntity] {
        return segments?.allObjects as? [WLEDSegmentEntity] ?? []
    }
}

// MARK: - WLEDSegmentEntity
@objc(WLEDSegmentEntity)
public class WLEDSegmentEntity: NSManagedObject {
    
}

extension WLEDSegmentEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WLEDSegmentEntity> {
        return NSFetchRequest<WLEDSegmentEntity>(entityName: "WLEDSegmentEntity")
    }
    
    @NSManaged public var segmentId: Int16
    @NSManaged public var start: Int16
    @NSManaged public var stop: Int16
    @NSManaged public var length: Int16
    @NSManaged public var isOn: Bool
    @NSManaged public var brightness: Int16
    @NSManaged public var effect: Int16
    @NSManaged public var speed: Int16
    @NSManaged public var intensity: Int16
    @NSManaged public var palette: Int16
    @NSManaged public var isSelected: Bool
    @NSManaged public var isReversed: Bool
    @NSManaged public var isMirrored: Bool
    @NSManaged public var colorsData: Data?
    @NSManaged public var state: WLEDStateEntity?
    
    // Computed properties for easy conversion
    var segmentIdInt: Int { Int(segmentId) }
    var startInt: Int { Int(start) }
    var stopInt: Int { Int(stop) }
    var lengthInt: Int { Int(length) }
    var brightnessInt: Int { Int(brightness) }
    var effectInt: Int { Int(effect) }
    var speedInt: Int { Int(speed) }
    var intensityInt: Int { Int(intensity) }
    var paletteInt: Int { Int(palette) }
    
    var colors: [[Int]]? {
        get {
            guard let data = colorsData else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [[Int]]
        }
        set {
            if let colors = newValue {
                colorsData = try? JSONSerialization.data(withJSONObject: colors)
            } else {
                colorsData = nil
            }
        }
    }
}

// MARK: - WellnessEntryEntity
@objc(WellnessEntryEntity)
public class WellnessEntryEntity: NSManagedObject {
    
}

extension WellnessEntryEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WellnessEntryEntity> {
        return NSFetchRequest<WellnessEntryEntity>(entityName: "WellnessEntryEntity")
    }

    @NSManaged public var date: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var sleepQuality: Int16
    @NSManaged public var sleepTime: Date?
    @NSManaged public var wokeOnTime: Bool
    @NSManaged public var sunriseLampUsed: Bool
    @NSManaged public var sunriseHelped: String
    @NSManaged public var identityIntentionText: String
    @NSManaged public var intentionText: String
    @NSManaged public var smallestNextStepText: String
    @NSManaged public var mainTaskText: String
    @NSManaged public var mainTaskDurationMinutes: Int32
    @NSManaged public var mainTaskReminderId: String?
    @NSManaged public var mainTaskEventId: String?
    @NSManaged public var secondaryTaskOneText: String
    @NSManaged public var secondaryTaskOneDurationMinutes: Int32
    @NSManaged public var secondaryTaskOneReminderId: String?
    @NSManaged public var secondaryTaskOneEventId: String?
    @NSManaged public var secondaryTaskTwoText: String
    @NSManaged public var secondaryTaskTwoDurationMinutes: Int32
    @NSManaged public var secondaryTaskTwoReminderId: String?
    @NSManaged public var secondaryTaskTwoEventId: String?
    @NSManaged public var mainTaskDone: Bool
    @NSManaged public var secondaryTaskOneDone: Bool
    @NSManaged public var secondaryTaskTwoDone: Bool
    @NSManaged public var brainDumpText: String
    @NSManaged public var sleepNotesText: String
    @NSManaged public var wakeTime: Date?
    @NSManaged public var middayBlockerText: String
    @NSManaged public var dayRecapText: String
    @NSManaged public var productivityRating: Int16
    @NSManaged public var dayMoodRating: Int16
    @NSManaged public var adjustTomorrowText: String
    @NSManaged public var tomorrowTaskOneText: String
    @NSManaged public var tomorrowTaskOneDurationMinutes: Int32
    @NSManaged public var tomorrowTaskOneReminderId: String?
    @NSManaged public var tomorrowTaskOneEventId: String?
    @NSManaged public var tomorrowTaskTwoText: String
    @NSManaged public var tomorrowTaskTwoDurationMinutes: Int32
    @NSManaged public var tomorrowTaskTwoReminderId: String?
    @NSManaged public var tomorrowTaskTwoEventId: String?
    @NSManaged public var tomorrowTaskThreeText: String
    @NSManaged public var tomorrowTaskThreeDurationMinutes: Int32
    @NSManaged public var tomorrowTaskThreeReminderId: String?
    @NSManaged public var tomorrowTaskThreeEventId: String?
    @NSManaged public var isLocked: Bool

    static func findOrCreate(for date: Date, in context: NSManagedObjectContext) -> WellnessEntryEntity {
        let request: NSFetchRequest<WellnessEntryEntity> = WellnessEntryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", date as NSDate)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let entity = WellnessEntryEntity(context: context)
        entity.date = date
        entity.updatedAt = Date()
        entity.sleepQuality = 0
        entity.sleepTime = nil
        entity.wokeOnTime = false
        entity.sunriseLampUsed = false
        entity.sunriseHelped = SunriseHelped.unsure.rawValue
        entity.identityIntentionText = ""
        entity.intentionText = ""
        entity.smallestNextStepText = ""
        entity.mainTaskText = ""
        entity.mainTaskDurationMinutes = 0
        entity.mainTaskReminderId = nil
        entity.mainTaskEventId = nil
        entity.secondaryTaskOneText = ""
        entity.secondaryTaskOneDurationMinutes = 0
        entity.secondaryTaskOneReminderId = nil
        entity.secondaryTaskOneEventId = nil
        entity.secondaryTaskTwoText = ""
        entity.secondaryTaskTwoDurationMinutes = 0
        entity.secondaryTaskTwoReminderId = nil
        entity.secondaryTaskTwoEventId = nil
        entity.mainTaskDone = false
        entity.secondaryTaskOneDone = false
        entity.secondaryTaskTwoDone = false
        entity.brainDumpText = ""
        entity.sleepNotesText = ""
        entity.wakeTime = nil
        entity.middayBlockerText = ""
        entity.dayRecapText = ""
        entity.productivityRating = 0
        entity.dayMoodRating = 0
        entity.adjustTomorrowText = ""
        entity.tomorrowTaskOneText = ""
        entity.tomorrowTaskOneDurationMinutes = 0
        entity.tomorrowTaskOneReminderId = nil
        entity.tomorrowTaskOneEventId = nil
        entity.tomorrowTaskTwoText = ""
        entity.tomorrowTaskTwoDurationMinutes = 0
        entity.tomorrowTaskTwoReminderId = nil
        entity.tomorrowTaskTwoEventId = nil
        entity.tomorrowTaskThreeText = ""
        entity.tomorrowTaskThreeDurationMinutes = 0
        entity.tomorrowTaskThreeReminderId = nil
        entity.tomorrowTaskThreeEventId = nil
        entity.isLocked = false
        return entity
    }

    func update(from entry: WellnessEntrySnapshot) {
        date = entry.date
        updatedAt = entry.updatedAt
        sleepQuality = Int16(entry.sleepQuality)
        sleepTime = entry.sleepTime
        wokeOnTime = entry.wokeOnTime
        sunriseLampUsed = entry.sunriseLampUsed
        sunriseHelped = entry.sunriseHelped.rawValue
        identityIntentionText = entry.identityIntentionText
        intentionText = entry.intentionText
        smallestNextStepText = entry.smallestNextStepText
        mainTaskText = entry.mainTaskText
        mainTaskDurationMinutes = Int32(entry.mainTaskDurationMinutes)
        mainTaskReminderId = entry.mainTaskReminderId
        mainTaskEventId = entry.mainTaskEventId
        secondaryTaskOneText = entry.secondaryTaskOneText
        secondaryTaskOneDurationMinutes = Int32(entry.secondaryTaskOneDurationMinutes)
        secondaryTaskOneReminderId = entry.secondaryTaskOneReminderId
        secondaryTaskOneEventId = entry.secondaryTaskOneEventId
        secondaryTaskTwoText = entry.secondaryTaskTwoText
        secondaryTaskTwoDurationMinutes = Int32(entry.secondaryTaskTwoDurationMinutes)
        secondaryTaskTwoReminderId = entry.secondaryTaskTwoReminderId
        secondaryTaskTwoEventId = entry.secondaryTaskTwoEventId
        mainTaskDone = entry.mainTaskDone
        secondaryTaskOneDone = entry.secondaryTaskOneDone
        secondaryTaskTwoDone = entry.secondaryTaskTwoDone
        brainDumpText = entry.brainDumpText
        sleepNotesText = entry.sleepNotesText
        wakeTime = entry.wakeTime
        middayBlockerText = entry.middayBlockerText
        dayRecapText = entry.dayRecapText
        productivityRating = Int16(entry.productivityRating)
        dayMoodRating = Int16(entry.dayMoodRating)
        adjustTomorrowText = entry.adjustTomorrowText
        tomorrowTaskOneText = entry.tomorrowTaskOneText
        tomorrowTaskOneDurationMinutes = Int32(entry.tomorrowTaskOneDurationMinutes)
        tomorrowTaskOneReminderId = entry.tomorrowTaskOneReminderId
        tomorrowTaskOneEventId = entry.tomorrowTaskOneEventId
        tomorrowTaskTwoText = entry.tomorrowTaskTwoText
        tomorrowTaskTwoDurationMinutes = Int32(entry.tomorrowTaskTwoDurationMinutes)
        tomorrowTaskTwoReminderId = entry.tomorrowTaskTwoReminderId
        tomorrowTaskTwoEventId = entry.tomorrowTaskTwoEventId
        tomorrowTaskThreeText = entry.tomorrowTaskThreeText
        tomorrowTaskThreeDurationMinutes = Int32(entry.tomorrowTaskThreeDurationMinutes)
        tomorrowTaskThreeReminderId = entry.tomorrowTaskThreeReminderId
        tomorrowTaskThreeEventId = entry.tomorrowTaskThreeEventId
        isLocked = entry.isLocked
    }

    func toSnapshot() -> WellnessEntrySnapshot {
        WellnessEntrySnapshot(
            date: date,
            sleepQuality: Int(sleepQuality),
            sleepTime: sleepTime,
            wokeOnTime: wokeOnTime,
            sunriseLampUsed: sunriseLampUsed,
            sunriseHelped: SunriseHelped(rawValue: sunriseHelped) ?? .yes,
            identityIntentionText: identityIntentionText,
            intentionText: intentionText,
            smallestNextStepText: smallestNextStepText,
            mainTaskText: mainTaskText,
            mainTaskDurationMinutes: Int(mainTaskDurationMinutes),
            mainTaskReminderId: mainTaskReminderId,
            mainTaskEventId: mainTaskEventId,
            secondaryTaskOneText: secondaryTaskOneText,
            secondaryTaskOneDurationMinutes: Int(secondaryTaskOneDurationMinutes),
            secondaryTaskOneReminderId: secondaryTaskOneReminderId,
            secondaryTaskOneEventId: secondaryTaskOneEventId,
            secondaryTaskTwoText: secondaryTaskTwoText,
            secondaryTaskTwoDurationMinutes: Int(secondaryTaskTwoDurationMinutes),
            secondaryTaskTwoReminderId: secondaryTaskTwoReminderId,
            secondaryTaskTwoEventId: secondaryTaskTwoEventId,
            mainTaskDone: mainTaskDone,
            secondaryTaskOneDone: secondaryTaskOneDone,
            secondaryTaskTwoDone: secondaryTaskTwoDone,
            brainDumpText: brainDumpText,
            sleepNotesText: sleepNotesText,
            wakeTime: wakeTime,
            middayBlockerText: middayBlockerText,
            dayRecapText: dayRecapText,
            productivityRating: Int(productivityRating),
            dayMoodRating: Int(dayMoodRating),
            adjustTomorrowText: adjustTomorrowText,
            tomorrowTaskOneText: tomorrowTaskOneText,
            tomorrowTaskOneDurationMinutes: Int(tomorrowTaskOneDurationMinutes),
            tomorrowTaskOneReminderId: tomorrowTaskOneReminderId,
            tomorrowTaskOneEventId: tomorrowTaskOneEventId,
            tomorrowTaskTwoText: tomorrowTaskTwoText,
            tomorrowTaskTwoDurationMinutes: Int(tomorrowTaskTwoDurationMinutes),
            tomorrowTaskTwoReminderId: tomorrowTaskTwoReminderId,
            tomorrowTaskTwoEventId: tomorrowTaskTwoEventId,
            tomorrowTaskThreeText: tomorrowTaskThreeText,
            tomorrowTaskThreeDurationMinutes: Int(tomorrowTaskThreeDurationMinutes),
            tomorrowTaskThreeReminderId: tomorrowTaskThreeReminderId,
            tomorrowTaskThreeEventId: tomorrowTaskThreeEventId,
            isLocked: isLocked,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Core Data Relationships
extension WLEDStateEntity {
    
    @objc(addSegmentsObject:)
    @NSManaged public func addToSegments(_ value: WLEDSegmentEntity)
    
    @objc(removeSegmentsObject:)
    @NSManaged public func removeFromSegments(_ value: WLEDSegmentEntity)
    
    @objc(addSegments:)
    @NSManaged public func addToSegments(_ values: NSSet)
    
    @objc(removeSegments:)
    @NSManaged public func removeFromSegments(_ values: NSSet)
}

// MARK: - Conversion Extensions
extension WLEDDevice {
    init?(from entity: WLEDDeviceEntity) {
        let storedHex = entity.currentColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackHex = WLEDDevice.wledBootDefaultHex
        let resolvedHex: String
        if storedHex.isEmpty {
            resolvedHex = fallbackHex
        } else if storedHex.uppercased() == "000000" && entity.state == nil {
            resolvedHex = fallbackHex
        } else {
            resolvedHex = storedHex
        }
        self.id = entity.id
        self.name = entity.name
        self.ipAddress = entity.ipAddress
        self.isOnline = entity.isOnline
        self.brightness = Int(entity.brightness)
        self.currentColor = Color(hex: resolvedHex)
        if entity.autoWhiteMode >= 0 {
            self.autoWhiteMode = AutoWhiteMode(rawValue: Int(entity.autoWhiteMode))
        } else {
            self.autoWhiteMode = nil
        }
        self.productType = ProductType(rawValue: entity.productType) ?? .generic
        self.location = DeviceLocation(rawValue: entity.location)
        self.lastSeen = entity.lastSeen
        self.state = entity.state?.toWLEDState()
        self.presetNamesById = decodeNameMap(entity.presetNamesJSON)
        self.playlistNamesById = decodeNameMap(entity.playlistNamesJSON)
    }
}

extension WLEDStateEntity {
    func toWLEDState() -> WLEDState {
        let segments = segmentsArray.compactMap { $0.toSegment() }
        
        return WLEDState(
            brightness: self.brightnessInt,
            isOn: self.isOn,
            segments: segments,
            transitionDeciseconds: self.transitionDecisecondsInt,
            presetId: nil,
            playlistId: nil,
            mainSegment: nil
        )
    }
    
    func update(from state: WLEDState) {
        self.isOn = state.isOn
        self.brightness = Int16(state.brightness)
        if let deciseconds = state.transitionDeciseconds {
            self.transitionDeciseconds = NSNumber(value: deciseconds)
        } else {
            self.transitionDeciseconds = nil
        }
        
        // Update segments
        // Remove existing segments
        if let existing = self.segments {
            self.removeFromSegments(existing)
        }
        
        // Add new segments
        let newSegmentEntities = state.segments.map { segment -> WLEDSegmentEntity in
            let entity = WLEDSegmentEntity(context: self.managedObjectContext!)
            entity.update(from: segment)
            return entity
        }
        self.addToSegments(NSSet(array: newSegmentEntities))
    }
}

extension WLEDSegmentEntity {
    func toSegment() -> Segment {
        return Segment(
            id: self.segmentIdInt,
            start: self.startInt,
            stop: self.stopInt,
            len: self.lengthInt,
            grp: nil, // Not persisted
            spc: nil, // Not persisted
            ofs: nil, // Not persisted
            on: self.isOn,
            bri: self.brightnessInt,
            colors: self.colors,
            cct: nil, // CCT not persisted in CoreData
            fx: self.effectInt,
            sx: self.speedInt,
            ix: self.intensityInt,
            pal: self.paletteInt,
            sel: nil,
            rev: nil,
            mi: nil,
            cln: nil, // Not persisted
            frz: nil
        )
    }

    func update(from segment: Segment) {
        self.segmentId = Int16(segment.id ?? 0)
        self.start = Int16(segment.start ?? 0)
        self.stop = Int16(segment.stop ?? 0)
        self.length = Int16(segment.len ?? 0)
        self.isOn = segment.on ?? true
        self.brightness = Int16(segment.bri ?? 255)
        self.effect = Int16(segment.fx ?? 0)
        self.speed = Int16(segment.sx ?? 128)
        self.intensity = Int16(segment.ix ?? 128)
        self.palette = Int16(segment.pal ?? 0)
        self.isSelected = segment.sel ?? false
        self.isReversed = segment.rev ?? false
        self.isMirrored = segment.mi ?? false
        self.colors = segment.colors
    }
} 
