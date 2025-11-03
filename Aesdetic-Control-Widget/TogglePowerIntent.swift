//
//  TogglePowerIntent.swift
//  Aesdetic-Control-Widget
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import AppIntents
import Foundation

struct TogglePowerIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Device Power"
    static var description = IntentDescription("Turns the WLED device on or off.")
    
    @Parameter(title: "Device ID")
    var deviceId: String
    
    init() {
        self.deviceId = ""
    }
    
    init(deviceId: String) {
        self.deviceId = deviceId
    }
    
    func perform() async throws -> some IntentResult {
        // Send notification to main app to toggle device
        NotificationCenter.default.post(
            name: NSNotification.Name("WidgetTogglePower"),
            object: nil,
            userInfo: ["deviceId": deviceId]
        )
        
        return .result()
    }
}

struct BrightnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Device Brightness"
    static var description = IntentDescription("Adjusts the brightness of a WLED device.")
    
    @Parameter(title: "Device ID")
    var deviceId: String
    
    @Parameter(title: "Brightness", description: "Brightness level from 0 to 100")
    var brightness: Int
    
    func perform() async throws -> some IntentResult {
        // Send notification to main app to set brightness
        NotificationCenter.default.post(
            name: NSNotification.Name("WidgetSetBrightness"),
            object: nil,
            userInfo: [
                "deviceId": deviceId,
                "brightness": brightness
            ]
        )
        
        return .result()
    }
}

