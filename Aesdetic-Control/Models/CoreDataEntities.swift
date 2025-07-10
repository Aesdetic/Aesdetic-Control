import Foundation
import CoreData
import SwiftUI

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
    @NSManaged public var productType: String
    @NSManaged public var location: String
    @NSManaged public var lastSeen: Date
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
            print("Error finding device entity: \\(error)")
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
        self.productType = device.productType.rawValue
        self.location = device.location.rawValue
        self.lastSeen = device.lastSeen
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
        get { Color(hex: currentColorHex) }
        set { currentColorHex = newValue.toHex() }
    }
    
    var productTypeEnum: ProductType {
        get { ProductType(rawValue: productType) ?? .generic }
        set { productType = newValue.rawValue }
    }
    
    var locationEnum: DeviceLocation {
        get { DeviceLocation(rawValue: location) ?? .all }
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
    @NSManaged public var device: WLEDDeviceEntity?
    @NSManaged public var segments: NSSet?
    
    // Computed properties
    var brightnessInt: Int {
        get { Int(brightness) }
        set { brightness = Int16(newValue) }
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
        self.init(
            id: entity.id,
            name: entity.name,
            ipAddress: entity.ipAddress,
            isOnline: entity.isOnline,
            brightness: entity.brightnessInt,
            currentColor: entity.currentColor,
            productType: entity.productTypeEnum,
            location: entity.locationEnum,
            lastSeen: entity.lastSeen,
            state: entity.state?.toWLEDState()
        )
    }
}

extension WLEDStateEntity {
    func toWLEDState() -> WLEDState {
        let segments = segmentsArray.compactMap { $0.toSegment() }
        return WLEDState(
            brightness: brightnessInt,
            isOn: isOn,
            segments: segments
        )
    }
}

extension WLEDSegmentEntity {
    func toSegment() -> Segment {
        return Segment(
            id: segmentIdInt,
            start: startInt,
            stop: stopInt,
            len: lengthInt,
            grp: nil,
            spc: nil,
            ofs: nil,
            on: isOn,
            bri: brightnessInt,
            colors: colors,
            fx: effectInt,
            sx: speedInt,
            ix: intensityInt,
            pal: paletteInt,
            sel: isSelected,
            rev: isReversed,
            mi: isMirrored,
            cln: nil
        )
    }
} 