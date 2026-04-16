import Foundation

enum DeviceProfileSetupState: String, Codable, CaseIterable {
    case pendingSelection = "pending_selection"
    case completed = "completed"
    case genericManual = "generic_manual"
    case legacy = "legacy"

    var displayName: String {
        switch self {
        case .pendingSelection:
            return "Setup Required"
        case .completed:
            return "Configured"
        case .genericManual:
            return "Custom WLED"
        case .legacy:
            return "Legacy Device"
        }
    }
}

struct DeviceLookProfileDefinition: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let previewHex: [String]
    let brightness: Int
    let colorRGB: [Int]
    let effectId: Int
    let speed: Int
    let intensity: Int
    let paletteId: Int?
}

struct DeviceProductProfileDefinition: Identifiable, Codable, Hashable {
    let id: String
    let productType: ProductType
    let version: Int
    let displayName: String
    let description: String
    let baseBrightness: Int
    let segmentCount: Int
    let defaultLookId: String
    let looks: [DeviceLookProfileDefinition]
}

struct DeviceProfileBackupSnapshot: Codable {
    let capturedAt: Date
    let state: WLEDState
    let presetId: Int?
    let playlistId: Int?
}
