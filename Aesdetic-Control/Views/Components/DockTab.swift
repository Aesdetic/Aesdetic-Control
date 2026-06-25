import SwiftUI

enum DockTab: String, CaseIterable, Identifiable {
    case dashboard
    case devices
    case automation
    case wellness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .devices:
            return "Devices"
        case .automation:
            return "Automation"
        case .wellness:
            return "Wellness"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .devices:
            return "lightbulb.2"
        case .automation:
            return "clock.arrow.2.circlepath"
        case .wellness:
            return "heart.text.square"
        }
    }
}
