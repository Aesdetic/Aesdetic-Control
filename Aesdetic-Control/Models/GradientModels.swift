import SwiftUI

/// Gradient interpolation modes for smooth color transitions
enum GradientInterpolation: String, Codable, CaseIterable {
    case linear = "linear"
    case easeInOut = "easeInOut"
    case easeIn = "easeIn"
    case easeOut = "easeOut"
    case cubic = "cubic"
    
    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeInOut: return "Smooth"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .cubic: return "Cubic"
        }
    }
    
    var description: String {
        switch self {
        case .linear: return "Linear color transition"
        case .easeInOut: return "Smooth start and end"
        case .easeIn: return "Slow start, fast end"
        case .easeOut: return "Fast start, slow end"
        case .cubic: return "Cubic bezier-like curve"
        }
    }
}

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
    var interpolation: GradientInterpolation  // Interpolation mode for gradient blending

    init(id: UUID = UUID(), stops: [GradientStop], name: String? = nil, interpolation: GradientInterpolation = .linear) {
        self.id = id
        self.stops = stops.sorted { $0.position < $1.position }
        self.name = name
        self.interpolation = interpolation
    }
}

enum GradientSampler {
    /// Sample a gradient across LED count, returning hex color strings
    /// - Parameters:
    ///   - gradient: The gradient to sample
    ///   - ledCount: Number of LEDs to sample for
    ///   - gamma: Parameter kept for backward compatibility (ignored - WLED handles gamma correction internally)
    ///   - interpolation: Interpolation mode for color transitions (defaults to gradient's interpolation mode)
    /// - Returns: Array of hex color strings ready for WLED API
    /// 
    /// Note: WLED applies gamma correction internally by default, so we send sRGB colors directly.
    /// This ensures consistent colors whether using 1 stop or multiple stops.
    static func sample(_ gradient: LEDGradient, ledCount: Int, gamma: Double = 2.2, interpolation: GradientInterpolation? = nil) -> [String] {
        guard ledCount > 0 else { return [] }
        let stops = gradient.stops.sorted { $0.position < $1.position }
        let interpolationMode = interpolation ?? gradient.interpolation
        
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

        // Normal path: interpolate colors in sRGB space with easing
        // WLED will apply gamma correction internally, so we send sRGB colors
        var result: [String] = []
        for i in 0..<ledCount {
            let rawT = Double(i) / Double(max(ledCount - 1, 1))
            // CRITICAL: Use rawT to find which stops to interpolate between,
            // then apply easing to the local interpolation factor within that segment.
            // This ensures easing affects color blending smoothness, not position mapping.
            let c = interpolateColor(stops: stops, t: rawT, interpolation: interpolationMode)
            // Send sRGB color directly - WLED handles gamma correction internally
            result.append(c.toHex())
        }
        return result
    }
    
    /// Apply interpolation curve to a normalized position (0.0-1.0)
    /// - Parameters:
    ///   - t: Raw position along gradient (0.0-1.0)
    ///   - mode: Interpolation mode to apply
    /// - Returns: Transformed position with easing curve applied
    private static func applyInterpolation(_ t: Double, mode: GradientInterpolation) -> Double {
        let clampedT = max(0.0, min(1.0, t))
        
        switch mode {
        case .linear:
            return clampedT
            
        case .easeInOut:
            // Smooth start and end (ease-in-out cubic)
            if clampedT < 0.5 {
                return 4 * clampedT * clampedT * clampedT
            } else {
                return 1 - pow(-2 * clampedT + 2, 3) / 2
            }
            
        case .easeIn:
            // Slow start, fast end (ease-in cubic)
            return clampedT * clampedT * clampedT
            
        case .easeOut:
            // Fast start, slow end (ease-out cubic)
            return 1 - pow(1 - clampedT, 3)
            
        case .cubic:
            // Cubic bezier-like curve (smooth S-curve)
            // Using cubic bezier approximation: (0.4, 0.0, 0.2, 1.0)
            let t2 = clampedT * clampedT
            let t3 = t2 * clampedT
            return 3 * t2 - 2 * t3
        }
    }

    /// Interpolate between gradient stops in sRGB color space
    /// - Parameters:
    ///   - stops: Sorted gradient stops
    ///   - t: Position along gradient (0.0-1.0) - raw position to find which stops to use
    ///   - interpolation: Interpolation mode to apply to localT within the segment
    /// - Returns: Interpolated Color in sRGB space
    /// 
    /// Note: Uses Color.lerp() which performs linear RGB interpolation in sRGB space.
    /// No gamma correction applied - WLED handles gamma internally.
    /// 
    /// CRITICAL: This function uses `t` to find which stops to interpolate between,
    /// then calculates the local interpolation factor within that segment, and applies
    /// easing to that local factor. This ensures easing affects color blending smoothness,
    /// not which segment we sample from.
    private static func interpolateColor(stops: [GradientStop], t: Double, interpolation: GradientInterpolation = .linear) -> Color {
        let t = max(0.0, min(1.0, t))
        if t <= stops.first!.position { return stops.first!.color }
        if t >= stops.last!.position { return stops.last!.color }
        var a = stops[0]
        var b = stops[1]
        for i in 0..<(stops.count - 1) {
            if t >= stops[i].position && t <= stops[i+1].position { a = stops[i]; b = stops[i+1]; break }
        }
        let span = max(0.000001, b.position - a.position)
        // Calculate local interpolation factor within this segment (0.0-1.0)
        let rawLocalT = (t - a.position) / span
        // Apply easing curve to the local interpolation factor
        // This affects how smoothly colors blend within the segment, not which segment we're in
        let easedLocalT = applyInterpolation(rawLocalT, mode: interpolation)
        return Color.lerp(a.color, b.color, easedLocalT)
    }
    
    /// Sample a color from gradient stops at a specific position (0.0-1.0)
    /// - Parameters:
    ///   - t: Position along the gradient (0.0 = start, 1.0 = end)
    ///   - stops: Array of gradient stops to sample from
    ///   - interpolation: Optional interpolation mode (defaults to linear for preview)
    /// - Returns: SwiftUI Color in sRGB space (ready for conversion to hex/RGB)
    /// 
    /// Note: Uses sRGB interpolation (no gamma correction). WLED handles gamma internally.
    /// Used by GradientBar for tap-to-add-stop functionality and visual preview.
    /// Consistent with `sample()` method - all colors use the same sRGB color system.
    /// 
    /// CRITICAL: Uses raw position `t` to find which stops to interpolate between,
    /// then applies easing to the local interpolation factor within that segment.
    /// This ensures easing affects color blending smoothness, not position mapping.
    static func sampleColor(at t: Double, stops: [GradientStop], interpolation: GradientInterpolation = .linear) -> Color {
        let sorted = stops.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return .white }
        if sorted.count == 1 { return sorted[0].color }
        // Use raw position to find stops, easing is applied to localT within interpolateColor
        return interpolateColor(stops: sorted, t: t, interpolation: interpolation)
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


