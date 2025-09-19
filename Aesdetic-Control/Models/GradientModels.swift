import SwiftUI

struct GradientStop: Identifiable, Codable, Hashable {
    let id: UUID
    var position: Double   // 0.0 ... 1.0
    var hexColor: String

    init(id: UUID = UUID(), position: Double, hexColor: String) {
        self.id = id
        self.position = max(0.0, min(1.0, position))
        self.hexColor = hexColor
    }

    var color: Color { Color(hex: hexColor) }
}

struct LEDGradient: Identifiable, Codable, Hashable {
    let id: UUID
    var stops: [GradientStop]
    var name: String?

    init(id: UUID = UUID(), stops: [GradientStop], name: String? = nil) {
        self.id = id
        self.stops = stops.sorted { $0.position < $1.position }
        self.name = name
    }
}

enum GradientSampler {
    static func sample(_ gradient: LEDGradient, ledCount: Int, gamma: Double = 2.2) -> [String] {
        guard ledCount > 0 else { return [] }
        let stops = gradient.stops.sorted { $0.position < $1.position }
        guard stops.count >= 2 else { return Array(repeating: (stops.first?.hexColor ?? "000000"), count: ledCount) }

        var result: [String] = []
        for i in 0..<ledCount {
            let t = Double(i) / Double(max(ledCount - 1, 1))
            var c = interpolateColor(stops: stops, t: t)
            c = applyGamma(c, gamma)
            result.append(c.toHex())
        }
        return result
    }

    private static func interpolateColor(stops: [GradientStop], t: Double) -> Color {
        let t = max(0.0, min(1.0, t))
        if t <= stops.first!.position { return stops.first!.color }
        if t >= stops.last!.position { return stops.last!.color }
        var a = stops[0]
        var b = stops[1]
        for i in 0..<(stops.count - 1) {
            if t >= stops[i].position && t <= stops[i+1].position { a = stops[i]; b = stops[i+1]; break }
        }
        let span = max(0.000001, b.position - a.position)
        let localT = (t - a.position) / span
        return Color.lerp(a.color, b.color, localT)
    }
    
    static func sampleColor(at t: Double, stops: [GradientStop]) -> Color {
        let sorted = stops.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return .white }
        if sorted.count == 1 { return sorted[0].color }
        return interpolateColor(stops: sorted, t: t)
    }

    private static func applyGamma(_ color: Color, _ gamma: Double) -> Color {
        let rgb = color.toRGBArray()
        func correct(_ v: Int) -> Double {
            let n = max(0.0, min(1.0, Double(v) / 255.0))
            return pow(n, 1.0 / max(0.0001, gamma))
        }
        return Color(
            red: correct(rgb[0]),
            green: correct(rgb[1]),
            blue: correct(rgb[2])
        )
    }
}

extension Array where Element == Double {
    // Midpoint between nearest neighbors for suggested new stop placement
    func adjacentMid() -> Double? {
        guard count >= 2 else { return nil }
        let sorted = self.sorted()
        var best: (gap: Double, mid: Double)? = nil
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i+1]
            let gap = b - a
            let mid = a + gap / 2
            if best == nil || gap > best!.gap { best = (gap, mid) }
        }
        return best?.mid
    }
}


