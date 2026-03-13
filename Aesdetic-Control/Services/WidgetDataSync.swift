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
    private let widgetDeviceFilename = "widgetDevice.json"
    
    private init() {}
    
    /// Sync device data to shared UserDefaults for widget access
    func syncDevice(_ device: WLEDDevice) {
        guard let containerURL = sharedContainerURL() else {
            #if DEBUG
            print("⚠️ Failed to access App Group UserDefaults")
            #endif
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
            let fileURL = containerURL.appendingPathComponent(widgetDeviceFilename)
            do {
                try encoded.write(to: fileURL, options: [.atomic])
                WidgetCenter.shared.reloadTimelines(ofKind: "DeviceControlWidget")
            } catch {
                #if DEBUG
                print("⚠️ Failed to write widget data: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// Clear widget data
    func clearWidgetData() {
        guard let containerURL = sharedContainerURL() else { return }
        let fileURL = containerURL.appendingPathComponent(widgetDeviceFilename)
        try? FileManager.default.removeItem(at: fileURL)
        WidgetCenter.shared.reloadTimelines(ofKind: "DeviceControlWidget")
    }

    private func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
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

