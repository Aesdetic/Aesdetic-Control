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
    /// Sample a gradient across LED count, returning hex color strings
    /// - Parameters:
    ///   - gradient: The gradient to sample
    ///   - ledCount: Number of LEDs to sample for
    ///   - gamma: Parameter kept for backward compatibility (ignored - WLED handles gamma correction internally)
    /// - Returns: Array of hex color strings ready for WLED API
    /// 
    /// Note: WLED applies gamma correction internally by default, so we send sRGB colors directly.
    /// This ensures consistent colors whether using 1 stop or multiple stops.
    static func sample(_ gradient: LEDGradient, ledCount: Int, gamma: Double = 2.2) -> [String] {
        guard ledCount > 0 else { return [] }
        let stops = gradient.stops.sorted { $0.position < $1.position }
        
        // Handle single stop: WLED applies gamma correction internally, so send sRGB directly
        guard stops.count >= 2 else {
            let hex = stops.first?.hexColor ?? "000000"
            return Array(repeating: hex, count: ledCount)
        }

        // Fast path: If all stops have the same color, skip interpolation
        // WLED applies gamma correction internally, so send sRGB directly
        let firstColor = stops.first?.hexColor
        if stops.allSatisfy({ $0.hexColor == firstColor }) {
            return Array(repeating: (firstColor ?? "000000"), count: ledCount)
        }

        // Normal path: interpolate colors in sRGB space
        // WLED will apply gamma correction internally, so we send sRGB colors
        var result: [String] = []
        for i in 0..<ledCount {
            let t = Double(i) / Double(max(ledCount - 1, 1))
            let c = interpolateColor(stops: stops, t: t)
            // Send sRGB color directly - WLED handles gamma correction internally
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


