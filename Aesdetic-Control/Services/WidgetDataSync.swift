//
//  WidgetDataSync.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import WidgetKit

/// Service for syncing device data to shared UserDefaults for widget access
@MainActor
class WidgetDataSync {
    static let shared = WidgetDataSync()
    
    private let appGroupID = "group.com.aesdetic.control"
    private let widgetDeviceKey = "widgetDevice"
    
    private init() {}
    
    /// Sync device data to shared UserDefaults for widget access
    func syncDevice(_ device: WLEDDevice) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("⚠️ Failed to access App Group UserDefaults")
            return
        }
        
        let widgetDevice = WidgetDevice(
            id: device.id,
            name: device.name,
            ipAddress: device.ipAddress,
            brightness: device.brightness,
            isOn: device.isOn,
            isOnline: device.isOnline
        )
        
        if let encoded = try? JSONEncoder().encode(widgetDevice) {
            sharedDefaults.set(encoded, forKey: widgetDeviceKey)
            sharedDefaults.synchronize()
            
            // Trigger widget timeline reload
            WidgetCenter.shared.reloadTimelines(ofKind: "DeviceControlWidget")
        }
    }
    
    /// Clear widget data
    func clearWidgetData() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else { return }
        sharedDefaults.removeObject(forKey: widgetDeviceKey)
        sharedDefaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "DeviceControlWidget")
    }
}

// MARK: - Widget Device Model (simplified for widget)
struct WidgetDevice: Codable {
    let id: String
    let name: String
    let ipAddress: String
    let brightness: Int
    let isOn: Bool
    let isOnline: Bool
}

