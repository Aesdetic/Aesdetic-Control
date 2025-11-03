//
//  DeviceWidgetView.swift
//  Aesdetic-Control-Widget
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import WidgetKit
import SwiftUI

struct DeviceWidgetView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.isLuminanceReduced) var isLuminanceReduced // StandBy mode detection
    @Environment(\.colorScheme) var colorScheme
    var entry: DeviceWidgetEntry
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
                .standByOptimized(isLuminanceReduced: isLuminanceReduced)
        case .systemMedium:
            MediumWidgetView(entry: entry)
                .standByOptimized(isLuminanceReduced: isLuminanceReduced)
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
                .standByOptimized(isLuminanceReduced: isLuminanceReduced)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
                .standByOptimized(isLuminanceReduced: isLuminanceReduced)
        default:
            SmallWidgetView(entry: entry)
                .standByOptimized(isLuminanceReduced: isLuminanceReduced)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @Environment(\.colorScheme) var colorScheme
    var entry: DeviceWidgetEntry
    
    var body: some View {
        VStack(spacing: isLuminanceReduced ? 12 : 8) {
            if let device = entry.device {
                // Device name - scaled up for StandBy
                Text(device.name)
                    .font(isLuminanceReduced ? .title2 : .headline)
                    .fontWeight(isLuminanceReduced ? .bold : .regular)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                // Status indicator - hidden in StandBy
                if !isLuminanceReduced {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.isOnline ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(entry.isOnline ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Power state - scaled up for StandBy
                HStack {
                    Image(systemName: entry.isOn ? "power" : "poweroff")
                        .font(isLuminanceReduced ? .system(size: 32, weight: .semibold) : .title2)
                        .foregroundColor(powerIconColor)
                    
                    Spacer()
                    
                    if entry.isOn {
                        Text("\(Int(round(Double(entry.brightness) / 255.0 * 100)))%")
                            .font(isLuminanceReduced ? .system(size: 28, weight: .bold, design: .rounded) : .title3)
                            .fontWeight(.semibold)
                            .monospacedDigit() // Better readability for numbers
                            .foregroundColor(textColor)
                    }
                }
            } else {
                // Empty state - scaled up for StandBy
                VStack(spacing: isLuminanceReduced ? 12 : 8) {
                    Image(systemName: "lightbulb")
                        .font(isLuminanceReduced ? .system(size: 40, weight: .medium) : .largeTitle)
                        .foregroundColor(textColor.opacity(0.6))
                    
                    Text("No Device")
                        .font(isLuminanceReduced ? .headline : .subheadline)
                        .foregroundColor(textColor.opacity(0.6))
                }
            }
        }
        .padding(isLuminanceReduced ? 16 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundView) // Transparent in StandBy
    }
    
    // MARK: - StandBy & Night Mode Helpers
    
    private var textColor: Color {
        if isLuminanceReduced {
            // StandBy mode: Use red tint for Night mode, white otherwise
            return colorScheme == .dark ? .red.opacity(0.9) : .white
        }
        return .primary
    }
    
    private var powerIconColor: Color {
        if isLuminanceReduced {
            return entry.isOn ? (colorScheme == .dark ? .red.opacity(0.9) : .white) : .gray.opacity(0.7)
        }
        return entry.isOn ? .blue : .gray
    }
    
    private var backgroundView: some View {
        Group {
            if isLuminanceReduced {
                // No background in StandBy mode (transparent)
                Color.clear
            } else {
                Color.clear // Will use system widget background
            }
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @Environment(\.colorScheme) var colorScheme
    var entry: DeviceWidgetEntry
    
    var body: some View {
        HStack(spacing: isLuminanceReduced ? 20 : 16) {
            if let device = entry.device {
                // Left: Device info - scaled up for StandBy
                VStack(alignment: .leading, spacing: isLuminanceReduced ? 12 : 8) {
                    Text(device.name)
                        .font(isLuminanceReduced ? .title : .headline)
                        .fontWeight(isLuminanceReduced ? .bold : .regular)
                        .foregroundColor(textColor)
                    
                    // Status indicator - hidden in StandBy
                    if !isLuminanceReduced {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(entry.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text(entry.isOnline ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(device.ipAddress)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Right: Power and brightness - scaled up for StandBy
                VStack(alignment: .trailing, spacing: isLuminanceReduced ? 12 : 8) {
                    Button(intent: TogglePowerIntent(deviceId: device.id)) {
                        Image(systemName: entry.isOn ? "power" : "poweroff")
                            .font(isLuminanceReduced ? .system(size: 36, weight: .semibold) : .title)
                            .foregroundColor(powerIconColor)
                            .frame(width: isLuminanceReduced ? 56 : 44, height: isLuminanceReduced ? 56 : 44)
                            .background(
                                Group {
                                    if isLuminanceReduced {
                                        // No background in StandBy
                                        Color.clear
                                    } else {
                                        Circle()
                                            .fill(entry.isOn ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    
                    if entry.isOn {
                        Text("\(Int(round(Double(entry.brightness) / 255.0 * 100)))%")
                            .font(isLuminanceReduced ? .system(size: 32, weight: .bold, design: .rounded) : .title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundColor(textColor)
                    }
                }
            } else {
                // Empty state - scaled up for StandBy
                VStack(spacing: isLuminanceReduced ? 12 : 8) {
                    Image(systemName: "lightbulb")
                        .font(isLuminanceReduced ? .system(size: 40, weight: .medium) : .largeTitle)
                        .foregroundColor(textColor.opacity(0.6))
                    
                    Text("No device selected")
                        .font(isLuminanceReduced ? .headline : .subheadline)
                        .foregroundColor(textColor.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(isLuminanceReduced ? 16 : 12)
        .background(backgroundView)
    }
    
    // MARK: - StandBy & Night Mode Helpers
    
    private var textColor: Color {
        if isLuminanceReduced {
            return colorScheme == .dark ? .red.opacity(0.9) : .white
        }
        return .primary
    }
    
    private var powerIconColor: Color {
        if isLuminanceReduced {
            return entry.isOn ? (colorScheme == .dark ? .red.opacity(0.9) : .white) : .gray.opacity(0.7)
        }
        return entry.isOn ? .blue : .gray
    }
    
    private var backgroundView: some View {
        Group {
            if isLuminanceReduced {
                Color.clear // Transparent in StandBy
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Circular Widget (Lock Screen / StandBy)

struct CircularWidgetView: View {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @Environment(\.colorScheme) var colorScheme
    var entry: DeviceWidgetEntry
    
    var body: some View {
        ZStack {
            if entry.device != nil {
                // Power icon in center - scaled up for StandBy
                Image(systemName: entry.isOn ? "power" : "poweroff")
                    .font(.system(size: isLuminanceReduced ? 32 : 24, weight: .semibold))
                    .foregroundColor(powerIconColor)
                
                // Brightness percentage on outer ring - scaled up for StandBy
                if entry.isOn {
                    Text("\(Int(round(Double(entry.brightness) / 255.0 * 100)))%")
                        .font(.system(size: isLuminanceReduced ? 14 : 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(textColor)
                        .offset(y: isLuminanceReduced ? -28 : -20)
                }
            } else {
                Image(systemName: "lightbulb")
                    .font(.system(size: isLuminanceReduced ? 32 : 24, weight: .medium))
                    .foregroundColor(textColor.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - StandBy & Night Mode Helpers
    
    private var textColor: Color {
        if isLuminanceReduced {
            return colorScheme == .dark ? .red.opacity(0.9) : .white
        }
        return .primary
    }
    
    private var powerIconColor: Color {
        if isLuminanceReduced {
            return entry.isOn ? (colorScheme == .dark ? .red.opacity(0.9) : .white) : .gray.opacity(0.7)
        }
        return entry.isOn ? .white : .gray
    }
}

// MARK: - Rectangular Widget (Lock Screen)

struct RectangularWidgetView: View {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @Environment(\.colorScheme) var colorScheme
    var entry: DeviceWidgetEntry
    
    var body: some View {
        HStack(spacing: isLuminanceReduced ? 12 : 8) {
            if let device = entry.device {
                Image(systemName: entry.isOn ? "power" : "poweroff")
                    .font(.system(size: isLuminanceReduced ? 24 : 18, weight: .semibold))
                    .foregroundColor(powerIconColor)
                
                VStack(alignment: .leading, spacing: isLuminanceReduced ? 4 : 2) {
                    Text(device.name)
                        .font(isLuminanceReduced ? .title3 : .headline)
                        .fontWeight(isLuminanceReduced ? .bold : .regular)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    if entry.isOn {
                        Text("\(Int(round(Double(entry.brightness) / 255.0 * 100)))% brightness")
                            .font(isLuminanceReduced ? .subheadline : .caption)
                            .monospacedDigit()
                            .foregroundColor(textColor.opacity(0.8))
                    } else {
                        Text("Off")
                            .font(isLuminanceReduced ? .subheadline : .caption)
                            .foregroundColor(textColor.opacity(0.8))
                    }
                }
            } else {
                Image(systemName: "lightbulb")
                    .font(.system(size: isLuminanceReduced ? 24 : 18, weight: .medium))
                    .foregroundColor(textColor.opacity(0.6))
                
                Text("No device")
                    .font(isLuminanceReduced ? .title3 : .headline)
                    .foregroundColor(textColor.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(.horizontal, isLuminanceReduced ? 8 : 4)
    }
    
    // MARK: - StandBy & Night Mode Helpers
    
    private var textColor: Color {
        if isLuminanceReduced {
            return colorScheme == .dark ? .red.opacity(0.9) : .white
        }
        return .primary
    }
    
    private var powerIconColor: Color {
        if isLuminanceReduced {
            return entry.isOn ? (colorScheme == .dark ? .red.opacity(0.9) : .white) : .gray.opacity(0.7)
        }
        return entry.isOn ? .blue : .gray
    }
}

// MARK: - StandBy Mode View Modifier

extension View {
    func standByOptimized(isLuminanceReduced: Bool) -> some View {
        self
            .background(
                Group {
                    if isLuminanceReduced {
                        // Transparent background for StandBy mode
                        Color.clear
                    } else {
                        // Use system widget background
                        Color.clear
                    }
                }
            )
    }
}

