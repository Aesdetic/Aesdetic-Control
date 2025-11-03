//
//  EffectMetadata.swift
//  Aesdetic-Control
//
//  Created by GPT-5 Codex on 10/31/25.
//

import Foundation

// MARK: - EffectMetadataBundle

/// Represents the parsed effect and palette metadata returned by the WLED `/json/fxdata` endpoint.
struct EffectMetadataBundle {
    let effects: [EffectMetadata]
    let palettes: [PaletteMetadata]
}

// MARK: - EffectMetadata

/// Metadata describing a single WLED effect (a.k.a. mode).
struct EffectMetadata: Identifiable {
    let id: Int
    let name: String
    let description: String?
    let parameters: [EffectParameter]
    let supportsPalette: Bool
    let isSoundReactive: Bool
    let colorSlotCount: Int

    /// Convenience flag indicating whether the effect exposes a speed parameter.
    var supportsSpeed: Bool {
        parameters.contains { $0.kind == .speed || ($0.kind == .genericSlider && $0.index == 0) }
    }

    /// Convenience flag indicating whether the effect exposes an intensity parameter.
    var supportsIntensity: Bool {
        parameters.contains { $0.kind == .intensity || ($0.kind == .genericSlider && $0.index == 1) }
    }
}

// MARK: - EffectParameter

struct EffectParameter: Identifiable {
    enum Kind {
        case speed
        case intensity
        case palette
        case color
        case genericSlider
    }
    let id = UUID()
    let index: Int
    let label: String
    let kind: Kind
}

// MARK: - PaletteMetadata

/// Metadata describing a single palette entry returned by `/json/fxdata`.
struct PaletteMetadata: Identifiable {
    let id: Int
    let name: String
    let isDynamic: Bool
    let description: String?
}

// MARK: - EffectMetadataParser

enum EffectMetadataParser {
    /// Parses the raw string lines returned from `/json/fxdata` into strongly-typed metadata.
    /// - Parameter lines: The raw response split into lines.
    /// - Returns: Parsed metadata bundle if decoding succeeds, otherwise `nil`.
    static func parse(lines: [String]) -> EffectMetadataBundle? {
        guard !lines.isEmpty else { return nil }
        let raw = lines.joined(separator: "\n")
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let effectsArray = root["effects"] as? [Any] ?? []
        let palettesArray = root["palettes"] as? [Any] ?? []

        let effects = effectsArray.enumerated().map { index, entry in
            parseEffect(entry: entry, index: index)
        }

        let palettes = palettesArray.enumerated().map { index, entry in
            parsePalette(entry: entry, index: index)
        }

        return EffectMetadataBundle(effects: effects, palettes: palettes)
    }

    // MARK: - Private helpers

    private static func parseEffect(entry: Any, index: Int) -> EffectMetadata {
        var name = "Effect \(index)"
        var description: String?
        var parameters: [EffectParameter] = []
        var supportsPalette = true
        var isSoundReactive = false
        var colorSlotCount = 0

        if let dict = entry as? [String: Any] {
            if let dictName = dict["name"] as? String { name = dictName }
            description = (dict["desc"] as? String)?.nilIfBlank ?? (dict["description"] as? String)?.nilIfBlank

            if let params = dict["params"] as? [String] ?? dict["parameters"] as? [String] {
                parameters = buildParameters(from: params)
            }

            // Palette support flags
            if let paletteFlag = dict["palette"] as? Bool ?? dict["usesPalette"] as? Bool ?? dict["pal"] as? Bool {
                supportsPalette = paletteFlag
            }

            if let soundFlag = dict["soundReactive"] as? Bool ?? dict["sound"] as? Bool {
                isSoundReactive = soundFlag
            }

            if let colors = dict["colors"] as? Int ?? dict["colorSlots"] as? Int {
                colorSlotCount = max(colors, colorSlotCount)
            }
        } else if let array = entry as? [Any] {
            if let arrayName = array.first as? String { name = arrayName }
            let strings = array.dropFirst().compactMap { $0 as? String }.filter { !$0.isEmpty }
            if let potentialDescription = strings.first, !looksLikeParameterLabel(potentialDescription) {
                description = potentialDescription
            }

            let paramStartIndex = description == nil ? 0 : 1
            let parameterLabels = Array(strings.dropFirst(paramStartIndex))
            parameters = buildParameters(from: parameterLabels)

            let bools = array.compactMap { $0 as? Bool }
            if let paletteFlag = bools.first {
                supportsPalette = paletteFlag
            }
            if bools.count > 1 {
                isSoundReactive = bools[1]
            }

            let ints = array.compactMap { value -> Int? in
                if let intValue = value as? Int { return intValue }
                if let doubleValue = value as? Double { return Int(doubleValue) }
                return nil
            }
            if let implicitColorCount = ints.last, implicitColorCount >= 0 && implicitColorCount <= 5 {
                // In legacy formats the last integer often represented color slot availability.
                colorSlotCount = max(colorSlotCount, implicitColorCount)
            }
        }

        if colorSlotCount == 0 {
            colorSlotCount = parameters.reduce(0) { partialResult, parameter in
                if case .color = parameter.kind { return partialResult + 1 }
                return partialResult
            }
        }

        return EffectMetadata(
            id: index,
            name: name,
            description: description,
            parameters: parameters,
            supportsPalette: supportsPalette,
            isSoundReactive: isSoundReactive,
            colorSlotCount: colorSlotCount
        )
    }

    private static func parsePalette(entry: Any, index: Int) -> PaletteMetadata {
        var name = "Palette \(index)"
        var isDynamic = false
        var description: String?

        if let dict = entry as? [String: Any] {
            if let dictName = dict["name"] as? String { name = dictName }
            isDynamic = dict["dynamic"] as? Bool ?? dict["isDynamic"] as? Bool ?? false
            description = (dict["desc"] as? String)?.nilIfBlank ?? (dict["description"] as? String)?.nilIfBlank
        } else if let array = entry as? [Any] {
            if let arrayName = array.first as? String { name = arrayName }
            if array.count > 1, let boolValue = array[1] as? Bool {
                isDynamic = boolValue
            }
            if array.count > 2, let descValue = array[2] as? String {
                description = descValue.nilIfBlank
            }
        } else if let string = entry as? String {
            name = string
        }

        return PaletteMetadata(id: index, name: name, isDynamic: isDynamic, description: description)
    }

    private static func buildParameters(from labels: [String]) -> [EffectParameter] {
        var parameters: [EffectParameter] = []
        var colorIndex = 0

        for (idx, label) in labels.enumerated() {
            let normalized = label.lowercased()
            let kind: EffectParameter.Kind

            if normalized.contains("speed") {
                kind = .speed
            } else if normalized.contains("intensity") || normalized.contains("amp") {
                kind = .intensity
            } else if normalized.contains("palette") {
                kind = .palette
            } else if normalized.contains("color") {
                kind = .color
                colorIndex += 1
            } else {
                kind = .genericSlider
            }

            parameters.append(EffectParameter(index: idx, label: label, kind: kind))
        }

        return parameters
    }

    private static func looksLikeParameterLabel(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("speed") || lower.contains("intensity") || lower.contains("palette") || lower.contains("color") || lower.contains("white") || lower.contains("power")
    }
}

// MARK: - Helpers

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}




