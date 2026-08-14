import Foundation

enum AesdeticWLEDPresetMarkerKind: String, Codable, CaseIterable, Hashable {
    case savedColor = "saved-color"
    case savedAnimation = "saved-animation"
    case savedTransition = "saved-transition"
    case transitionStep = "transition-step"
    case automation = "automation"
    case automationStep = "automation-step"

    var isInternalAsset: Bool {
        switch self {
        case .transitionStep, .automation, .automationStep:
            return true
        case .savedColor, .savedAnimation, .savedTransition:
            return false
        }
    }
}

struct AesdeticWLEDPresetNameMarker: Equatable {
    let kind: AesdeticWLEDPresetMarkerKind
    let displayName: String
    let ownershipToken: String?

    static func parse(_ rawName: String) -> AesdeticWLEDPresetNameMarker? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[AD") else { return nil }
        guard let closingIndex = trimmed.firstIndex(of: "]") else { return nil }

        let markerBody = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)..<closingIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard markerBody.hasPrefix("AD") else { return nil }

        var descriptor = String(markerBody.dropFirst(2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var ownershipToken: String?
        if descriptor.hasPrefix(":") {
            descriptor.removeFirst()
            if let spaceIndex = descriptor.firstIndex(where: { $0.isWhitespace }) {
                let qualifier = String(descriptor[..<spaceIndex])
                if qualifier.hasPrefix("o=") {
                    let token = String(qualifier.dropFirst(2))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if !token.isEmpty {
                        ownershipToken = token
                    }
                }
                descriptor = String(descriptor[descriptor.index(after: spaceIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return nil
            }
        }

        guard let kindToken = descriptor.split(whereSeparator: \.isWhitespace).first,
              let kind = AesdeticWLEDPresetMarkerKind(rawValue: String(kindToken)) else {
            return nil
        }

        let displayStart = trimmed.index(after: closingIndex)
        let displayName = String(trimmed[displayStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AesdeticWLEDPresetNameMarker(
            kind: kind,
            displayName: displayName,
            ownershipToken: ownershipToken
        )
    }

    static func displayName(from rawName: String) -> String {
        parse(rawName)?.displayName ?? rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func markedName(
        _ rawDisplayName: String,
        as kind: AesdeticWLEDPresetMarkerKind,
        ownerId: UUID? = nil
    ) -> String {
        let displayName = displayName(from: rawDisplayName)
        let fallback = fallbackDisplayName(for: kind)
        let qualifier = ownerId.map { ":o=\(ownershipToken(for: $0))" } ?? ""
        return "[AD\(qualifier) \(kind.rawValue)] \(displayName.isEmpty ? fallback : displayName)"
    }

    static func preservingExistingMarker(from existingName: String?, newDisplayName: String) -> String {
        guard let existingName,
              let marker = parse(existingName) else {
            return newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let displayName = displayName(from: newDisplayName)
        let fallback = fallbackDisplayName(for: marker.kind)
        let qualifier = marker.ownershipToken.map { ":o=\($0)" } ?? ""
        return "[AD\(qualifier) \(marker.kind.rawValue)] \(displayName.isEmpty ? fallback : displayName)"
    }

    static func ownershipToken(for ownerId: UUID) -> String {
        String(
            ownerId.uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
                .prefix(12)
        )
    }

    private static func fallbackDisplayName(for kind: AesdeticWLEDPresetMarkerKind) -> String {
        switch kind {
        case .savedColor:
            return "Color"
        case .savedAnimation:
            return "Animation"
        case .savedTransition:
            return "Transition"
        case .transitionStep:
            return "Transition Step"
        case .automation:
            return "Automation"
        case .automationStep:
            return "Automation Step"
        }
    }
}

extension WLEDPlaylist {
    var displayName: String {
        AesdeticWLEDPresetNameMarker.displayName(from: name)
    }
}

struct WLEDRecoveredColorPreset: Identifiable {
    let id: Int
    let displayName: String
    let gradient: LEDGradient
    let brightness: Int
    let sourcePreset: WLEDPreset
}

enum WLEDDevicePresetRecovery {
    static let defaultEditableStopLimit = 5

    static func recoveredColorPresets(
        for deviceId: String,
        presets: [WLEDPreset],
        playlists: [WLEDPlaylist],
        localColorPresets: [ColorPreset],
        automationPresetIds: Set<Int> = [],
        maxEditableStops: Int = defaultEditableStopLimit
    ) -> [WLEDRecoveredColorPreset] {
        let playlistRecordIds = Set(playlists.map(\.id))
        let playlistStepIds = Set(playlists.flatMap(\.presets).filter { $0 > 0 })
        let localPresetIds = Set(
            localColorPresets.compactMap { preset in
                preset.wledPresetIds?[deviceId] ?? preset.wledPresetId
            }
        )

        return presets.compactMap { preset -> WLEDRecoveredColorPreset? in
            guard preset.id > 0,
                  !playlistRecordIds.contains(preset.id),
                  !localPresetIds.contains(preset.id),
                  recoveredKind(
                    for: preset,
                    playlistStepIds: playlistStepIds,
                    automationPresetIds: automationPresetIds
                  ) == .color,
                  let snapshot = colorSnapshot(for: preset, maxEditableStops: maxEditableStops) else {
                return nil
            }
            return WLEDRecoveredColorPreset(
                id: preset.id,
                displayName: preset.displayName,
                gradient: snapshot.gradient,
                brightness: snapshot.brightness,
                sourcePreset: preset
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == rhs.id {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    static func colorSnapshot(
        for preset: WLEDPreset,
        maxEditableStops: Int = defaultEditableStopLimit
    ) -> (gradient: LEDGradient, brightness: Int)? {
        let segments = preset.state?.seg ?? (preset.segment.map { [$0] } ?? [])
        let rawStops = colorStops(from: segments)
        guard !rawStops.isEmpty else { return nil }

        let simplifiedStops = simplifiedEditableStops(rawStops, maxCount: maxEditableStops)
        let brightness = max(0, min(255, preset.state?.bri ?? segments.first?.bri ?? 255))
        return (LEDGradient(stops: simplifiedStops, interpolation: .linear), brightness)
    }

    static func isEffectDevicePreset(_ preset: WLEDPreset) -> Bool {
        let segments = preset.state?.seg ?? (preset.segment.map { [$0] } ?? [])
        return segments.contains { segment in
            guard let effectId = segment.fx else { return false }
            return effectId > 0
        }
    }

    static func devicePresetHasColorData(_ preset: WLEDPreset) -> Bool {
        let segments = preset.state?.seg ?? (preset.segment.map { [$0] } ?? [])
        return segments.contains { segment in
            guard let colors = segment.col else { return false }
            return colors.contains { color in
                color.prefix(3).contains { $0 > 0 }
            }
        }
    }

    private enum RecoveredKind {
        case color
        case animation
        case hidden
    }

    private static func recoveredKind(
        for preset: WLEDPreset,
        playlistStepIds: Set<Int>,
        automationPresetIds: Set<Int>
    ) -> RecoveredKind? {
        if let marker = AesdeticWLEDPresetNameMarker.parse(preset.name) {
            switch marker.kind {
            case .savedColor:
                return .color
            case .savedAnimation:
                return .animation
            case .savedTransition, .transitionStep, .automation, .automationStep:
                return .hidden
            }
        }

        if playlistStepIds.contains(preset.id) || automationPresetIds.contains(preset.id) {
            return .hidden
        }

        let normalizedName = preset.displayName.lowercased()
        if normalizedName.hasPrefix("automation ")
            || normalizedName.hasPrefix("automation step ")
            || normalizedName.hasPrefix("automation transition ")
            || normalizedName.hasPrefix("transition step ")
            || normalizedName.hasPrefix("auto step ") {
            return .hidden
        }

        if isEffectDevicePreset(preset) {
            return .animation
        }
        if devicePresetHasColorData(preset) {
            return .color
        }
        return nil
    }

    private static func colorStops(from segments: [SegmentUpdate]) -> [GradientStop] {
        struct Sample {
            let order: Int
            let start: Int?
            let stop: Int?
            let hex: String
        }

        let samples = segments.enumerated().compactMap { index, segment -> Sample? in
            guard let color = segment.col?.first,
                  color.count >= 3 else {
                return nil
            }
            return Sample(
                order: index,
                start: segment.start,
                stop: segment.stop,
                hex: hexColor(red: color[0], green: color[1], blue: color[2])
            )
        }
        guard !samples.isEmpty else { return [] }

        let useBounds = samples.allSatisfy { sample in
            guard let start = sample.start, let stop = sample.stop else { return false }
            return stop > start
        }

        let ordered = useBounds
            ? samples.sorted { ($0.start ?? 0) < ($1.start ?? 0) }
            : samples.sorted { $0.order < $1.order }

        if ordered.count == 1 {
            return [GradientStop(position: 0, hexColor: ordered[0].hex)]
        }

        if useBounds {
            let minStart = ordered.compactMap(\.start).min() ?? 0
            let maxStop = ordered.compactMap(\.stop).max() ?? (minStart + ordered.count)
            let span = max(1, maxStop - minStart)
            return ordered.map { sample in
                let center = Double(((sample.start ?? minStart) + (sample.stop ?? minStart)) - (2 * minStart)) / 2.0
                let position = max(0, min(1, center / Double(span)))
                return GradientStop(position: position, hexColor: sample.hex)
            }
        }

        return ordered.enumerated().map { index, sample in
            GradientStop(
                position: Double(index) / Double(max(ordered.count - 1, 1)),
                hexColor: sample.hex
            )
        }
    }

    private static func simplifiedEditableStops(_ stops: [GradientStop], maxCount: Int) -> [GradientStop] {
        let sorted = stops.sorted { $0.position < $1.position }
        var deduped: [GradientStop] = []
        for stop in sorted {
            if deduped.last?.hexColor.uppercased() != stop.hexColor.uppercased() {
                deduped.append(stop)
            }
        }

        guard deduped.count > max(1, maxCount) else {
            return normalizedPositions(deduped)
        }

        let targetCount = max(2, maxCount)
        var sampled: [GradientStop] = []
        for index in 0..<targetCount {
            let sourceIndex = Int(round(Double(index) * Double(deduped.count - 1) / Double(targetCount - 1)))
            sampled.append(deduped[sourceIndex])
        }
        return normalizedPositions(sampled)
    }

    private static func normalizedPositions(_ stops: [GradientStop]) -> [GradientStop] {
        guard stops.count > 1 else { return stops }
        return stops.enumerated().map { index, stop in
            GradientStop(
                position: Double(index) / Double(stops.count - 1),
                hexColor: stop.hexColor
            )
        }
    }

    private static func hexColor(red: Int, green: Int, blue: Int) -> String {
        String(
            format: "%02X%02X%02X",
            max(0, min(255, red)),
            max(0, min(255, green)),
            max(0, min(255, blue))
        )
    }
}
