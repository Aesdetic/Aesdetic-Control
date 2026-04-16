import Foundation

struct DeviceProfileCatalog {
    static let shared = DeviceProfileCatalog()

    let profiles: [DeviceProductProfileDefinition]

    private init() {
        profiles = Self.buildProfiles()
    }

    func profile(for productType: ProductType) -> DeviceProductProfileDefinition? {
        profiles.first(where: { $0.productType == productType })
    }

    func look(for productType: ProductType, lookId: String) -> DeviceLookProfileDefinition? {
        guard let profile = profile(for: productType) else { return nil }
        return profile.looks.first(where: { $0.id == lookId })
    }

    static func baseState(for profile: DeviceProductProfileDefinition) -> WLEDStateUpdate {
        let segment = SegmentUpdate(
            id: 0,
            on: true,
            bri: profile.baseBrightness,
            fx: 0,
            sx: 128,
            ix: 128,
            pal: 0
        )
        return WLEDStateUpdate(
            on: true,
            bri: profile.baseBrightness,
            seg: [segment]
        )
    }

    static func state(for look: DeviceLookProfileDefinition) -> WLEDStateUpdate {
        let color = look.colorRGB
        let payloadColor: [[Int]] = [[
            max(0, min(255, color[safe: 0] ?? 255)),
            max(0, min(255, color[safe: 1] ?? 255)),
            max(0, min(255, color[safe: 2] ?? 255))
        ]]
        let segment = SegmentUpdate(
            id: 0,
            on: true,
            bri: look.brightness,
            col: payloadColor,
            fx: look.effectId,
            sx: look.speed,
            ix: look.intensity,
            pal: look.paletteId
        )
        return WLEDStateUpdate(
            on: true,
            bri: look.brightness,
            seg: [segment]
        )
    }

    private static func buildProfiles() -> [DeviceProductProfileDefinition] {
        let sunriseLooks: [DeviceLookProfileDefinition] = [
            DeviceLookProfileDefinition(
                id: "focus_warm",
                name: "Focus Warm",
                previewHex: ["#FF9F2E", "#FFD37A"],
                brightness: 180,
                colorRGB: [255, 159, 46],
                effectId: 2,
                speed: 90,
                intensity: 120,
                paletteId: 0
            ),
            DeviceLookProfileDefinition(
                id: "sunrise_gentle",
                name: "Gentle Sunrise",
                previewHex: ["#FF6A00", "#FFC46B"],
                brightness: 170,
                colorRGB: [255, 106, 0],
                effectId: 3,
                speed: 70,
                intensity: 110,
                paletteId: 0
            )
        ]

        let deskLooks: [DeviceLookProfileDefinition] = [
            DeviceLookProfileDefinition(
                id: "deep_focus",
                name: "Deep Focus",
                previewHex: ["#2B7FFF", "#8ED3FF"],
                brightness: 165,
                colorRGB: [43, 127, 255],
                effectId: 0,
                speed: 128,
                intensity: 128,
                paletteId: 0
            ),
            DeviceLookProfileDefinition(
                id: "creative_flow",
                name: "Creative Flow",
                previewHex: ["#FF4D7E", "#7A6CFF"],
                brightness: 185,
                colorRGB: [255, 77, 126],
                effectId: 27,
                speed: 120,
                intensity: 155,
                paletteId: 0
            )
        ]

        let ambianceLooks: [DeviceLookProfileDefinition] = [
            DeviceLookProfileDefinition(
                id: "soft_evening",
                name: "Soft Evening",
                previewHex: ["#FF8B62", "#FFCB9A"],
                brightness: 145,
                colorRGB: [255, 139, 98],
                effectId: 3,
                speed: 65,
                intensity: 95,
                paletteId: 0
            ),
            DeviceLookProfileDefinition(
                id: "ambient_gradient",
                name: "Ambient Gradient",
                previewHex: ["#00A0FF", "#00FFAF"],
                brightness: 165,
                colorRGB: [0, 160, 255],
                effectId: 37,
                speed: 85,
                intensity: 130,
                paletteId: 0
            )
        ]

        let ceilingLooks: [DeviceLookProfileDefinition] = [
            DeviceLookProfileDefinition(
                id: "daylight_clean",
                name: "Daylight Clean",
                previewHex: ["#D9F3FF", "#9DD5FF"],
                brightness: 210,
                colorRGB: [217, 243, 255],
                effectId: 0,
                speed: 128,
                intensity: 128,
                paletteId: 0
            ),
            DeviceLookProfileDefinition(
                id: "cinema_mood",
                name: "Cinema Mood",
                previewHex: ["#3F5BFF", "#141A40"],
                brightness: 140,
                colorRGB: [63, 91, 255],
                effectId: 54,
                speed: 80,
                intensity: 140,
                paletteId: 0
            )
        ]

        return [
            DeviceProductProfileDefinition(
                id: "sunrise_lamp_v1",
                productType: .sunriseLamp,
                version: 1,
                displayName: "Sunrise Lamp",
                description: "Warm wake-up profile with smooth transitions.",
                baseBrightness: 170,
                segmentCount: 1,
                defaultLookId: "focus_warm",
                looks: sunriseLooks
            ),
            DeviceProductProfileDefinition(
                id: "desk_strip_v1",
                productType: .deskStrip,
                version: 1,
                displayName: "Desk Strip",
                description: "Balanced profile for focus and creative sessions.",
                baseBrightness: 175,
                segmentCount: 1,
                defaultLookId: "deep_focus",
                looks: deskLooks
            ),
            DeviceProductProfileDefinition(
                id: "ambiance_strip_v1",
                productType: .ambianceStrip,
                version: 1,
                displayName: "Ambiance Strip",
                description: "Soft room-filling profile for ambient lighting.",
                baseBrightness: 155,
                segmentCount: 1,
                defaultLookId: "soft_evening",
                looks: ambianceLooks
            ),
            DeviceProductProfileDefinition(
                id: "ceiling_panel_v1",
                productType: .ceilingPanel,
                version: 1,
                displayName: "Ceiling Panel",
                description: "High-coverage profile tuned for panel illumination.",
                baseBrightness: 200,
                segmentCount: 1,
                defaultLookId: "daylight_clean",
                looks: ceilingLooks
            )
        ]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
