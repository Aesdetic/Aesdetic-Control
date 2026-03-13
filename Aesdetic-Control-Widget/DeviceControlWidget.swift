//
//  DeviceControlWidget.swift
//  Aesdetic-Control-Widget
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import WidgetKit
import SwiftUI
import AppIntents

struct DeviceControlWidget: Widget {
    let kind: String = "DeviceControlWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeviceControlProvider()) { entry in
            DeviceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("WLED Device Control")
        .description("Monitor and control your WLED devices from the Home Screen and StandBy mode.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct DeviceControlProvider: TimelineProvider {
    typealias Entry = DeviceWidgetEntry
    
    func placeholder(in context: Context) -> DeviceWidgetEntry {
        DeviceWidgetEntry(
            date: Date(),
            device: nil,
            brightness: 0,
            isOn: false,
            isOnline: false
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (DeviceWidgetEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeviceWidgetEntry>) -> Void) {
        let currentDate = Date()
        let entry = createEntry()
        
        // Update every 15 minutes or when widget timeline refreshes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func createEntry() -> DeviceWidgetEntry {
        // Load device data from shared UserDefaults
        if let deviceData = loadSharedDeviceData(),
           let device = try? JSONDecoder().decode(WidgetDevice.self, from: deviceData) {
            return DeviceWidgetEntry(
                date: Date(),
                device: device,
                brightness: device.brightness,
                isOn: device.isOn,
                isOnline: device.isOnline
            )
        }
        
        // Fallback to placeholder
        return DeviceWidgetEntry(
            date: Date(),
            device: nil,
            brightness: 0,
            isOn: false,
            isOnline: false
        )
    }

    private func loadSharedDeviceData() -> Data? {
        let groupId = "group.com.aesdetic.control"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            return nil
        }
        let fileURL = containerURL.appendingPathComponent("widgetDevice.json")
        return try? Data(contentsOf: fileURL)
    }
}

struct DeviceWidgetEntry: TimelineEntry {
    let date: Date
    let device: WidgetDevice?
    let brightness: Int
    let isOn: Bool
    let isOnline: Bool
}

// MARK: - Widget Device Model (shared structure)
struct WidgetDevice: Codable {
    let id: String
    let name: String
    let ipAddress: String
    let brightness: Int
    let isOn: Bool
    let isOnline: Bool
}

@main
struct DeviceControlWidgetBundle: WidgetBundle {
    init() {
        // Debug: Verify widget bundle loads
        print("🚀 DeviceControlWidgetBundle initialized - Widget should be discoverable")
    }
    
    var body: some Widget {
        DeviceControlWidget()
    }
}


