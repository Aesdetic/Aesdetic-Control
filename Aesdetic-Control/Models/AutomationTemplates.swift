import Foundation

struct AutomationTemplate: Identifiable {
    struct Context {
        let device: WLEDDevice
        let availableDevices: [WLEDDevice]
        let defaultGradient: LEDGradient
    }
    
    struct Prefill {
        enum Trigger {
            case time(hour: Int, minute: Int, weekdays: [Bool]?)
            case sunrise(offsetMinutes: Int)
            case sunset(offsetMinutes: Int)
        }
        
        enum Action {
            case gradient(gradient: LEDGradient?, brightness: Int, fadeDuration: Double)
            case transition(payload: TransitionActionPayload, durationSeconds: Double?, endBrightness: Int?)
            case effect(effectId: Int, brightness: Int, gradient: LEDGradient?, speed: Int, intensity: Int)
        }
        
        var name: String?
        var targetDeviceIds: [String]?
        var allowPartialFailure: Bool?
        var trigger: Trigger
        var action: Action
        var metadata: AutomationMetadata?
    }
    
    let id: String
    let name: String
    let subtitle: String
    let iconName: String
    let accentHex: String
    private let builder: (Context) -> Prefill
    
    func prefill(for context: Context) -> Prefill {
        builder(context)
    }
}

extension AutomationTemplate {
    static let sunrise: AutomationTemplate = {
        AutomationTemplate(
            id: "sunrise",
            name: "Sunrise",
            subtitle: "Slowly brighten before dawn",
            iconName: "sunrise.fill",
            accentHex: "#FFA000"
        ) { context in
            let startGradient = LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: "#100804"),
                GradientStop(position: 0.5, hexColor: "#371401"),
                GradientStop(position: 1.0, hexColor: "#8B2D04")
            ])
            let payload = TransitionActionPayload(
                startGradient: startGradient,
                startBrightness: 6,
                endGradient: context.defaultGradient,
                endBrightness: 255,
                durationSeconds: 1800,
                shouldLoop: false,
                presetId: nil,
                presetName: "Sunrise Glow"
            )
            return Prefill(
                name: "\(context.device.name) Sunrise",
                targetDeviceIds: [context.device.id],
                allowPartialFailure: false,
                trigger: .sunrise(offsetMinutes: -15),
                action: .transition(payload: payload, durationSeconds: 1800, endBrightness: 255),
                metadata: AutomationMetadata(
                    colorPreviewHex: "#FFA000",
                    accentColorHex: "#FFA000",
                    iconName: "sunrise.fill",
                    templateId: "sunrise",
                    pinnedToShortcuts: true
                )
            )
        }
    }()
    
    static let sunset: AutomationTemplate = {
        AutomationTemplate(
            id: "sunset",
            name: "Sunset",
            subtitle: "Wind down at dusk",
            iconName: "moon.stars.fill",
            accentHex: "#FF7A18"
        ) { context in
            let gradient = LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: "#FF7A18"),
                GradientStop(position: 0.7, hexColor: "#9F3912"),
                GradientStop(position: 1.0, hexColor: "#200B02")
            ])
            return Prefill(
                name: "\(context.device.name) Sunset",
                targetDeviceIds: [context.device.id],
                allowPartialFailure: true,
                trigger: .sunset(offsetMinutes: 10),
                action: .gradient(gradient: gradient, brightness: 90, fadeDuration: 900),
                metadata: AutomationMetadata(
                    colorPreviewHex: "#FF7A18",
                    accentColorHex: "#FF7A18",
                    iconName: "moon.stars.fill",
                    templateId: "sunset",
                    pinnedToShortcuts: true
                )
            )
        }
    }()
    
    static let focus: AutomationTemplate = {
        AutomationTemplate(
            id: "focus",
            name: "Focus Boost",
            subtitle: "Cool tones for deep work",
            iconName: "bolt.fill",
            accentHex: "#50C7F0"
        ) { context in
            let gradient = LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: "#80E9FF"),
                GradientStop(position: 1.0, hexColor: "#1F7EFF")
            ])
            return Prefill(
                name: "Focus – \(context.device.name)",
                targetDeviceIds: [context.device.id],
                allowPartialFailure: true,
                trigger: .time(hour: 9, minute: 0, weekdays: [false, true, true, true, true, true, false]),
                action: .gradient(gradient: gradient, brightness: 200, fadeDuration: 0),
                metadata: AutomationMetadata(
                    colorPreviewHex: "#80E9FF",
                    accentColorHex: "#50C7F0",
                    iconName: "bolt.fill",
                    templateId: "focus",
                    pinnedToShortcuts: true
                )
            )
        }
    }()
    
    static let bedtime: AutomationTemplate = {
        AutomationTemplate(
            id: "bedtime",
            name: "Bedtime",
            subtitle: "Dim amber before sleep",
            iconName: "bed.double.fill",
            accentHex: "#FFB347"
        ) { context in
            let payload = TransitionActionPayload(
                startGradient: context.defaultGradient,
                startBrightness: context.device.brightness,
                endGradient: LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: "#FFA75E"),
                    GradientStop(position: 1.0, hexColor: "#3C1600")
                ]),
                endBrightness: 30,
                durationSeconds: 1200,
                shouldLoop: false,
                presetId: nil,
                presetName: "Bedtime Fade"
            )
            return Prefill(
                name: "Bedtime – \(context.device.name)",
                targetDeviceIds: [context.device.id],
                allowPartialFailure: true,
                trigger: .time(hour: 22, minute: 0, weekdays: nil),
                action: .transition(payload: payload, durationSeconds: 1200, endBrightness: 30),
                metadata: AutomationMetadata(
                    colorPreviewHex: "#FFA75E",
                    accentColorHex: "#FFB347",
                    iconName: "bed.double.fill",
                    templateId: "bedtime",
                    pinnedToShortcuts: true
                )
            )
        }
    }()
    
    static var quickStartTemplates: [AutomationTemplate] {
        [AutomationTemplate.sunrise, AutomationTemplate.sunset, AutomationTemplate.focus, AutomationTemplate.bedtime]
    }
}

